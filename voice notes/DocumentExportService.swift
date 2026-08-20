//
//  DocumentExportService.swift
//  voice notes
//
//  "Conversations become searchable files": writes each note as a markdown
//  file into a user-chosen folder via the Files app. Because Google Drive,
//  OneDrive, and Obsidian vaults are all Files providers, one folder pick
//  covers them all — no OAuth, no per-service API. The folder is remembered
//  with a security-scoped bookmark. Files are named stably per note
//  (date + title slug + id suffix), so re-exports overwrite in place and
//  nothing is ever duplicated or deleted.
//

import Foundation

@Observable
final class DocumentExportService {
    static let shared = DocumentExportService()

    static let enabledKey = "documentExportEnabled"
    private let bookmarkKey = "documentExportFolderBookmark"

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var hasFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Human-readable name of the chosen folder, for the Settings row.
    var folderName: String? {
        guard let url = resolveFolder() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return url.lastPathComponent
    }

    /// Store the picked folder (from a Files-app folder picker) as a
    /// security-scoped bookmark.
    func setFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
    }

    /// Export one note as markdown into the chosen folder. Overwrites the
    /// note's own file if it exists (stable name). No-op unless enabled and
    /// a folder is set. Never deletes anything.
    func export(note: Note) {
        guard isEnabled else { return }
        guard let folder = resolveFolder() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }

        let fileURL = folder.appendingPathComponent(fileName(for: note))
        let markdown = Self.markdown(for: note)
        do {
            try markdown.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        } catch {
            print("[DocumentExport] write failed: \(error)")
        }
    }

    /// Backfill: export every non-archived note. Returns the count written.
    func exportAll(notes: [Note]) -> Int {
        guard let folder = resolveFolder() else { return 0 }
        defer { folder.stopAccessingSecurityScopedResource() }

        var written = 0
        for note in notes where !note.isArchived {
            let fileURL = folder.appendingPathComponent(fileName(for: note))
            if let data = Self.markdown(for: note).data(using: .utf8),
               (try? data.write(to: fileURL, options: .atomic)) != nil {
                written += 1
            }
        }
        return written
    }

    // MARK: - Internals

    private func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let refreshed = try? url.bookmarkData() {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// Stable per-note filename: 2026-08-19-call-the-bank-3f2a.md
    private func fileName(for note: Note) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: note.createdAt)
        let slugSource = note.displayTitle.isEmpty ? "note" : note.displayTitle
        let slug = slugSource
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        let suffix = note.id.uuidString.suffix(4).lowercased()
        return "\(date)-\(slug.isEmpty ? "note" : slug)-\(suffix).md"
    }

    static func markdown(for note: Note) -> String {
        var parts: [String] = []
        parts.append("# \(note.displayTitle.isEmpty ? "Voice note" : note.displayTitle)")
        parts.append("_\(note.createdAt.formatted(date: .long, time: .shortened)) · EEON_")
        if let enhanced = note.enhancedNoteText, !enhanced.isEmpty {
            parts.append(enhanced)
        } else if !note.content.isEmpty {
            parts.append(note.content)
        }
        if let transcript = note.transcript, !transcript.isEmpty,
           transcript != note.enhancedNoteText {
            parts.append("---\n\n**Original transcript**\n\n\(transcript)")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }
}
