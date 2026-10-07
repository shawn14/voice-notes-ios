//
//  RecentlyDeleted.swift
//  voice notes
//
//  Deleting a note moves it here for 30 days instead of destroying it.
//
//  The note is written out as a JSON snapshot in Application Support/
//  `recently-deleted`, its recording and photos stay where they are, and only
//  then is the SwiftData record deleted. So everything that reads notes (Home,
//  search, Ask, exports, the agent mirror, iCloud on other devices) sees an
//  ordinary delete, with no "is it deleted?" filter to forget anywhere, and no
//  new stored field for CloudKit. Restoring re-inserts the note with the same
//  id, so its tasks, decisions and commitments (linked by `sourceNoteId`, never
//  cascade-deleted) attach again by themselves.
//
//  The bin lives on the device that did the deleting, like the audio does.
//
//  Adding a stored field to `Note`? Add it to `DeletedNoteSnapshot` in all four
//  places (the field, `init(note:)`, `apply(to:)`, `coveredFields`). A DEBUG
//  launch check, `RecentlyDeletedStore.verifySnapshotCoversNote`, fails loudly
//  if you forget.
//

import Foundation
import SwiftData

nonisolated struct DeletedNoteSnapshot: Codable, Sendable, Identifiable {
    var deletedAt: Date
    var tagNames: [String]

    var id: UUID
    var title: String
    var content: String
    var transcript: String?
    var audioFileName: String?
    var createdAt: Date
    var updatedAt: Date
    var projectId: UUID?
    var column: String
    var aiInsight: String?
    var isFavorite: Bool
    var isArchived: Bool
    var audioDuration: Double?
    var intentType: String
    var intentConfidence: Double
    var extractedSubjectJSON: String?
    var suggestedNextStep: String?
    var nextStepTypeRaw: String?
    var missingInfoJSON: String?
    var nextStepResolvedAt: Date?
    var nextStepResolution: String?
    var inferredProjectName: String?
    var imageFileNamesJSON: String?
    var mentionedPeopleJSON: String?
    var activeRewriteText: String?
    var activeRewriteType: String?
    var transcriptionStatus: String
    var embeddingData: Data?
    var topicsJSON: String?
    var emotionalTone: String?
    var enhancedNoteText: String?
    var enhancedNoteEdited: Bool
    var enhancedNoteEditedAt: Date?
    var summaryFormat: String?
    var quizJSON: String?
    var personaExtractionsJSON: String?
    var calendarContextJSON: String?
    var speakerLabelsJSON: String?
    var sourceTypeRaw: String
    var originalURL: String?
    var annotation: String?
    var derivedFromQueryId: String?

    /// Missing keys fall back to a default, so a snapshot written by an older
    /// build stays readable after `Note` gains a field.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt) ?? Date()
        tagNames = try c.decodeIfPresent([String].self, forKey: .tagNames) ?? []
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId)
        column = try c.decodeIfPresent(String.self, forKey: .column) ?? ""
        aiInsight = try c.decodeIfPresent(String.self, forKey: .aiInsight)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        audioDuration = try c.decodeIfPresent(Double.self, forKey: .audioDuration)
        intentType = try c.decodeIfPresent(String.self, forKey: .intentType) ?? ""
        intentConfidence = try c.decodeIfPresent(Double.self, forKey: .intentConfidence) ?? 0
        extractedSubjectJSON = try c.decodeIfPresent(String.self, forKey: .extractedSubjectJSON)
        suggestedNextStep = try c.decodeIfPresent(String.self, forKey: .suggestedNextStep)
        nextStepTypeRaw = try c.decodeIfPresent(String.self, forKey: .nextStepTypeRaw)
        missingInfoJSON = try c.decodeIfPresent(String.self, forKey: .missingInfoJSON)
        nextStepResolvedAt = try c.decodeIfPresent(Date.self, forKey: .nextStepResolvedAt)
        nextStepResolution = try c.decodeIfPresent(String.self, forKey: .nextStepResolution)
        inferredProjectName = try c.decodeIfPresent(String.self, forKey: .inferredProjectName)
        imageFileNamesJSON = try c.decodeIfPresent(String.self, forKey: .imageFileNamesJSON)
        mentionedPeopleJSON = try c.decodeIfPresent(String.self, forKey: .mentionedPeopleJSON)
        activeRewriteText = try c.decodeIfPresent(String.self, forKey: .activeRewriteText)
        activeRewriteType = try c.decodeIfPresent(String.self, forKey: .activeRewriteType)
        transcriptionStatus = try c.decodeIfPresent(String.self, forKey: .transcriptionStatus) ?? ""
        embeddingData = try c.decodeIfPresent(Data.self, forKey: .embeddingData)
        topicsJSON = try c.decodeIfPresent(String.self, forKey: .topicsJSON)
        emotionalTone = try c.decodeIfPresent(String.self, forKey: .emotionalTone)
        enhancedNoteText = try c.decodeIfPresent(String.self, forKey: .enhancedNoteText)
        enhancedNoteEdited = try c.decodeIfPresent(Bool.self, forKey: .enhancedNoteEdited) ?? false
        enhancedNoteEditedAt = try c.decodeIfPresent(Date.self, forKey: .enhancedNoteEditedAt)
        summaryFormat = try c.decodeIfPresent(String.self, forKey: .summaryFormat)
        quizJSON = try c.decodeIfPresent(String.self, forKey: .quizJSON)
        personaExtractionsJSON = try c.decodeIfPresent(String.self, forKey: .personaExtractionsJSON)
        calendarContextJSON = try c.decodeIfPresent(String.self, forKey: .calendarContextJSON)
        speakerLabelsJSON = try c.decodeIfPresent(String.self, forKey: .speakerLabelsJSON)
        sourceTypeRaw = try c.decodeIfPresent(String.self, forKey: .sourceTypeRaw) ?? ""
        originalURL = try c.decodeIfPresent(String.self, forKey: .originalURL)
        annotation = try c.decodeIfPresent(String.self, forKey: .annotation)
        derivedFromQueryId = try c.decodeIfPresent(String.self, forKey: .derivedFromQueryId)
    }

    /// Every stored `Note` attribute this snapshot carries.
    static let coveredFields: Set<String> = [
        "id", "title", "content", "transcript",
        "audioFileName", "createdAt", "updatedAt", "projectId",
        "column", "aiInsight", "isFavorite", "isArchived",
        "audioDuration", "intentType", "intentConfidence", "extractedSubjectJSON",
        "suggestedNextStep", "nextStepTypeRaw", "missingInfoJSON", "nextStepResolvedAt",
        "nextStepResolution", "inferredProjectName", "imageFileNamesJSON", "mentionedPeopleJSON",
        "activeRewriteText", "activeRewriteType", "transcriptionStatus", "embeddingData",
        "topicsJSON", "emotionalTone", "enhancedNoteText", "enhancedNoteEdited",
        "enhancedNoteEditedAt", "summaryFormat", "quizJSON", "personaExtractionsJSON",
        "calendarContextJSON", "speakerLabelsJSON", "sourceTypeRaw", "originalURL",
        "annotation", "derivedFromQueryId",
    ]
}

extension DeletedNoteSnapshot {
    init(note: Note, deletedAt: Date = Date()) {
        self.deletedAt = deletedAt
        tagNames = note.tags.map(\.name)
        id = note.id
        title = note.title
        content = note.content
        transcript = note.transcript
        audioFileName = note.audioFileName
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        projectId = note.projectId
        column = note.column
        aiInsight = note.aiInsight
        isFavorite = note.isFavorite
        isArchived = note.isArchived
        audioDuration = note.audioDuration
        intentType = note.intentType
        intentConfidence = note.intentConfidence
        extractedSubjectJSON = note.extractedSubjectJSON
        suggestedNextStep = note.suggestedNextStep
        nextStepTypeRaw = note.nextStepTypeRaw
        missingInfoJSON = note.missingInfoJSON
        nextStepResolvedAt = note.nextStepResolvedAt
        nextStepResolution = note.nextStepResolution
        inferredProjectName = note.inferredProjectName
        imageFileNamesJSON = note.imageFileNamesJSON
        mentionedPeopleJSON = note.mentionedPeopleJSON
        activeRewriteText = note.activeRewriteText
        activeRewriteType = note.activeRewriteType
        transcriptionStatus = note.transcriptionStatus
        embeddingData = note.embeddingData
        topicsJSON = note.topicsJSON
        emotionalTone = note.emotionalTone
        enhancedNoteText = note.enhancedNoteText
        enhancedNoteEdited = note.enhancedNoteEdited
        enhancedNoteEditedAt = note.enhancedNoteEditedAt
        summaryFormat = note.summaryFormat
        quizJSON = note.quizJSON
        personaExtractionsJSON = note.personaExtractionsJSON
        calendarContextJSON = note.calendarContextJSON
        speakerLabelsJSON = note.speakerLabelsJSON
        sourceTypeRaw = note.sourceTypeRaw
        originalURL = note.originalURL
        annotation = note.annotation
        derivedFromQueryId = note.derivedFromQueryId
    }

    func apply(to note: Note) {
        note.id = id
        note.title = title
        note.content = content
        note.transcript = transcript
        note.audioFileName = audioFileName
        note.createdAt = createdAt
        note.updatedAt = updatedAt
        note.projectId = projectId
        note.column = column
        note.aiInsight = aiInsight
        note.isFavorite = isFavorite
        note.isArchived = isArchived
        note.audioDuration = audioDuration
        note.intentType = intentType
        note.intentConfidence = intentConfidence
        note.extractedSubjectJSON = extractedSubjectJSON
        note.suggestedNextStep = suggestedNextStep
        note.nextStepTypeRaw = nextStepTypeRaw
        note.missingInfoJSON = missingInfoJSON
        note.nextStepResolvedAt = nextStepResolvedAt
        note.nextStepResolution = nextStepResolution
        note.inferredProjectName = inferredProjectName
        note.imageFileNamesJSON = imageFileNamesJSON
        note.mentionedPeopleJSON = mentionedPeopleJSON
        note.activeRewriteText = activeRewriteText
        note.activeRewriteType = activeRewriteType
        note.transcriptionStatus = transcriptionStatus
        note.embeddingData = embeddingData
        note.topicsJSON = topicsJSON
        note.emotionalTone = emotionalTone
        note.enhancedNoteText = enhancedNoteText
        note.enhancedNoteEdited = enhancedNoteEdited
        note.enhancedNoteEditedAt = enhancedNoteEditedAt
        note.summaryFormat = summaryFormat
        note.quizJSON = quizJSON
        note.personaExtractionsJSON = personaExtractionsJSON
        note.calendarContextJSON = calendarContextJSON
        note.speakerLabelsJSON = speakerLabelsJSON
        note.sourceTypeRaw = sourceTypeRaw
        note.originalURL = originalURL
        note.annotation = annotation
        note.derivedFromQueryId = derivedFromQueryId
    }

    nonisolated var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? "Untitled note" : String(body.prefix(60))
    }

    nonisolated var bodyText: String {
        enhancedNoteText ?? transcript ?? content
    }

    nonisolated var purgeDate: Date {
        deletedAt.addingTimeInterval(RecentlyDeletedStore.retention)
    }

    /// Whole days left before this note is removed for good (never below 0).
    nonisolated func daysLeft(now: Date = Date()) -> Int {
        max(0, Int(ceil(purgeDate.timeIntervalSince(now) / 86_400)))
    }
}

enum RecentlyDeletedStore {
    nonisolated static let retention: TimeInterval = 30 * 86_400

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("recently-deleted", isDirectory: true)
    }

    nonisolated private static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    nonisolated private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: Delete → bin

    /// Move a note to the bin. If the snapshot cannot be written the note is
    /// left exactly as it was and this returns false: a delete that cannot be
    /// undone must not silently stand in for one that can.
    @discardableResult
    static func trash(_ note: Note, in context: ModelContext) -> Bool {
        let snapshot = DeletedNoteSnapshot(note: note)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL(for: snapshot.id), options: .atomic)
        } catch {
            print("[RecentlyDeleted] could not archive note, leaving it in place: \(error.localizedDescription)")
            return false
        }
        context.delete(note)
        do {
            try context.save()
        } catch {
            // The delete did not stick, so the note is still live: a snapshot
            // left behind would later let the bin purge a live note's files.
            context.rollback()
            try? FileManager.default.removeItem(at: fileURL(for: snapshot.id))
            print("[RecentlyDeleted] delete failed, note left in place: \(error.localizedDescription)")
            return false
        }
        return true
    }

    // MARK: Read

    nonisolated static func entries() -> [DeletedNoteSnapshot] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(DeletedNoteSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: Restore

    /// Put a note back. Returns the restored (or already present) note.
    @discardableResult
    static func restore(_ snapshot: DeletedNoteSnapshot, in context: ModelContext) -> Note? {
        let id = snapshot.id
        // A row can outlive its snapshot (purged while the list was open).
        // Without the snapshot's files there is nothing left to restore.
        guard FileManager.default.fileExists(atPath: fileURL(for: id).path) else { return nil }
        let existing = try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
        if let existing {
            // Already back (restored before, or it came down from iCloud).
            try? FileManager.default.removeItem(at: fileURL(for: id))
            return existing
        }

        let note = Note()
        snapshot.apply(to: note)
        context.insert(note)

        if !snapshot.tagNames.isEmpty {
            let allTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            note.tags = snapshot.tagNames.compactMap { name in allTags.first { $0.name == name } }
        }

        do {
            try context.save()
        } catch {
            print("[RecentlyDeleted] restore failed, keeping the snapshot: \(error.localizedDescription)")
            context.delete(note)
            return nil
        }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        return note
    }

    // MARK: Remove for good

    /// Remove a binned note and its recording and photos. A file a live note
    /// still points to is never removed: if the note is back in the store
    /// (a failed delete, or it returned from iCloud) only the snapshot goes.
    static func purge(_ snapshot: DeletedNoteSnapshot, in context: ModelContext) {
        purge([snapshot], in: context)
    }

    static func purge(_ snapshots: [DeletedNoteSnapshot], in context: ModelContext) {
        guard !snapshots.isEmpty else { return }
        // If the live notes cannot be read, keep every file and drop nothing.
        guard let liveNotes = try? context.fetch(FetchDescriptor<Note>()) else { return }
        var inUse = Set<String>()
        for note in liveNotes {
            if let audio = note.audioFileName { inUse.insert(audio) }
            inUse.formUnion(note.imageFileNames)
        }

        let fm = FileManager.default
        for snapshot in snapshots {
            if let audio = snapshot.audioFileName, !inUse.contains(audio) {
                try? fm.removeItem(at: documents.appendingPathComponent(audio))
                try? fm.removeItem(at: TranscriptTimelineStore.fileURL(forAudioFileName: audio))
            }
            for image in imageFileNames(in: snapshot) where !inUse.contains(image) {
                try? fm.removeItem(at: documents.appendingPathComponent(image))
            }
            try? fm.removeItem(at: fileURL(for: snapshot.id))
        }
    }

    /// Remove notes that have been in the bin longer than `retention`.
    /// Returns how many were removed.
    @discardableResult
    static func purgeExpired(now: Date = Date(), in context: ModelContext) -> Int {
        let expired = entries().filter { $0.purgeDate <= now }
        purge(expired, in: context)
        return expired.count
    }

    /// Empty the bin now (account / all-data deletion).
    static func purgeAll(in context: ModelContext) {
        purge(entries(), in: context)
    }

    nonisolated private static func imageFileNames(in snapshot: DeletedNoteSnapshot) -> [String] {
        guard let json = snapshot.imageFileNamesJSON, let data = json.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return names
    }

    // MARK: Drift guard

    #if DEBUG
    /// A `Note` field the snapshot does not carry would be lost on restore.
    /// Compares the live SwiftData schema with `coveredFields` at launch.
    static func verifySnapshotCoversNote() {
        guard let entity = Schema([Note.self]).entitiesByName["Note"] else { return }
        let stored = Set(entity.attributes.map(\.name))
        let missing = stored.subtracting(DeletedNoteSnapshot.coveredFields)
        let stale = DeletedNoteSnapshot.coveredFields.subtracting(stored)
        if !missing.isEmpty || !stale.isEmpty {
            assertionFailure("DeletedNoteSnapshot is out of date. Missing: \(missing.sorted()) Stale: \(stale.sorted())")
        }
    }
    #endif
}
