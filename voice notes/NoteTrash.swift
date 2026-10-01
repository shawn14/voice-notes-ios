//
//  NoteTrash.swift
//  voice notes
//
//  Recently Deleted (2026-10-01, design: docs/superpowers/specs/
//  2026-10-01-recently-deleted-design.md, Option B). Deleting a note writes a
//  snapshot to Application Support/Trash/<id>/ and moves its audio and photos
//  there, then deletes the note from SwiftData for real — so CloudKit, the
//  agent mirror, RAG, widgets and exports never see trashed notes and need no
//  filtering. Restore re-inserts a Note with the same id. Entries older than
//  30 days are purged on app foreground.
//
//  The bin is per-device by design: a note deleted on the iPad can only be
//  restored on the iPad (once restored it syncs back everywhere).
//
//  The snapshot walks `Note.schemaMetadata`, so a stored field added to Note
//  later is captured without touching this file — as long as its type is one
//  `encode`/`decode` handle (String, Date, Bool, Int, Double, Data, UUID, and
//  optionals). An unsupported type is skipped and logged, not a crash.
//  `Schema.PropertyMetadata` keeps `name`/`keypath` internal, so they're read
//  by reflection; if a future SDK changes that, `moveToTrash` refuses (the
//  note is kept) instead of writing an empty snapshot.
//

import Foundation
import SwiftData

struct TrashedNote: Identifiable, Hashable {
    let id: UUID
    let title: String
    let preview: String
    let createdAt: Date
    let deletedAt: Date
    let hasAudio: Bool

    var expiresAt: Date { deletedAt.addingTimeInterval(NoteTrash.retention) }

    var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0)
    }
}

enum NoteTrash {
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    private static let snapshotFile = "note.plist"
    private static let filesFolder = "files"

    // Snapshot keys outside the Note fields
    private static let fieldsKey = "fields"
    private static let tagNamesKey = "tagNames"
    private static let deletedAtKey = "deletedAt"

    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Note's stored properties (name + key path) from the @Model metadata.
    private static let noteProperties: [(name: String, keypath: AnyKeyPath)] =
        Note.schemaMetadata.compactMap { metadata in
            var name: String?
            var keypath: AnyKeyPath?
            for child in Mirror(reflecting: metadata).children {
                if child.label == "name" { name = child.value as? String }
                if child.label == "keypath" { keypath = child.value as? AnyKeyPath }
            }
            guard let name, let keypath else { return nil }
            return (name, keypath)
        }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - Delete (move to trash)

    /// Moves a note to Recently Deleted. If the snapshot can't be written the
    /// note is NOT deleted — losing a note to a disk error is the one outcome
    /// this feature exists to prevent.
    @discardableResult
    static func moveToTrash(_ note: Note, context: ModelContext) -> Bool {
        let fm = FileManager.default
        let entry = folder(for: note.id)
        let files = entry.appendingPathComponent(filesFolder, isDirectory: true)

        let fields = encodeFields(of: note)
        guard fields["id"] != nil, fields["createdAt"] != nil else {
            print("NoteTrash: Note metadata unreadable, note kept")
            return false
        }

        do {
            try? fm.removeItem(at: entry)  // A re-deleted restored note replaces its old entry
            try fm.createDirectory(at: files, withIntermediateDirectories: true)

            let snapshot: [String: Any] = [
                fieldsKey: fields,
                tagNamesKey: note.tags.map(\.name),
                deletedAtKey: Date()
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
            try data.write(to: entry.appendingPathComponent(snapshotFile), options: .atomic)
        } catch {
            print("NoteTrash: snapshot failed, note kept: \(error)")
            try? fm.removeItem(at: entry)
            return false
        }

        // Audio + photos move with it (a missing file is fine — e.g. typed notes)
        for name in [note.audioFileName].compactMap({ $0 }) + note.imageFileNames {
            try? fm.moveItem(at: documents.appendingPathComponent(name),
                             to: files.appendingPathComponent(name))
        }

        context.delete(note)
        try? context.save()
        return true
    }

    // MARK: - List

    static func entries() -> [TrashedNote] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> TrashedNote? in
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let snapshot = readSnapshot(folder),
                  let fields = snapshot[fieldsKey] as? [String: Any],
                  let deletedAt = snapshot[deletedAtKey] as? Date else { return nil }
            let title = (fields["title"] as? String) ?? ""
            let body = (fields["enhancedNoteText"] as? String)
                ?? (fields["transcript"] as? String)
                ?? (fields["content"] as? String) ?? ""
            return TrashedNote(
                id: id,
                title: title.isEmpty ? String(body.prefix(60)) : title,
                preview: String(body.prefix(140)),
                createdAt: (fields["createdAt"] as? Date) ?? deletedAt,
                deletedAt: deletedAt,
                hasAudio: fields["audioFileName"] != nil
            )
        }
        .sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - Restore

    /// Re-creates the note with its original id, fields, tags, audio and photos.
    @discardableResult
    static func restore(_ id: UUID, context: ModelContext) -> Note? {
        let fm = FileManager.default
        let entry = folder(for: id)
        guard let snapshot = readSnapshot(entry),
              let fields = snapshot[fieldsKey] as? [String: Any] else { return nil }

        let note = Note()
        for property in noteProperties {
            guard let value = fields[property.name] else { continue }
            if !decode(value, into: property.keypath, on: note) {
                print("NoteTrash: could not restore field \(property.name)")
            }
        }
        note.id = id

        // Tags are a relationship, so the snapshot keeps names; re-link or recreate
        let tagNames = snapshot[tagNamesKey] as? [String] ?? []
        if !tagNames.isEmpty {
            let existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            note.tagsOptional = tagNames.map { name in
                existing.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? {
                    let tag = Tag(name: name)
                    context.insert(tag)
                    return tag
                }()
            }
        }

        let files = entry.appendingPathComponent(filesFolder, isDirectory: true)
        for name in [note.audioFileName].compactMap({ $0 }) + note.imageFileNames {
            try? fm.moveItem(at: files.appendingPathComponent(name),
                             to: documents.appendingPathComponent(name))
        }

        context.insert(note)
        try? context.save()
        try? fm.removeItem(at: entry)
        return note
    }

    // MARK: - Permanent delete

    static func deleteForever(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Removes entries past the 30-day window. Cheap; call on foreground.
    static func purgeExpired(now: Date = Date()) {
        for entry in entries() where entry.expiresAt <= now {
            deleteForever(entry.id)
        }
    }

    // MARK: - Snapshot encoding

    private static func readSnapshot(_ folder: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(snapshotFile)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Every stored attribute as a property-list value; nils are omitted.
    private static func encodeFields(of note: Note) -> [String: Any] {
        var fields: [String: Any] = [:]
        for property in noteProperties {
            guard let value = unwrap(note[keyPath: property.keypath]) else { continue }
            switch value {
            case let v as String: fields[property.name] = v
            case let v as Date: fields[property.name] = v
            case let v as Bool: fields[property.name] = v
            case let v as Int: fields[property.name] = v
            case let v as Double: fields[property.name] = v
            case let v as Data: fields[property.name] = v
            case let v as UUID: fields[property.name] = v.uuidString
            case is [Tag]: break  // tagsOptional — saved as names
            default: print("NoteTrash: skipping field \(property.name) of type \(type(of: value))")
            }
        }
        return fields
    }

    /// Flattens Optional-in-Any: returns nil for `.none`, the wrapped value otherwise.
    private static func unwrap(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.flatMap { unwrap($0.value) }
    }

    private static func decode(_ value: Any, into keypath: AnyKeyPath, on note: Note) -> Bool {
        func set<T>(_ type: T.Type, _ v: T?) -> Bool {
            guard let v else { return false }
            if let kp = keypath as? ReferenceWritableKeyPath<Note, T> { note[keyPath: kp] = v; return true }
            if let kp = keypath as? ReferenceWritableKeyPath<Note, T?> { note[keyPath: kp] = v; return true }
            return false
        }
        return set(String.self, value as? String)
            || set(Date.self, value as? Date)
            || set(Bool.self, value as? Bool)
            || set(Int.self, value as? Int)
            || set(Double.self, value as? Double)
            || set(Data.self, value as? Data)
            || set(UUID.self, (value as? String).flatMap(UUID.init(uuidString:)))
    }
}
