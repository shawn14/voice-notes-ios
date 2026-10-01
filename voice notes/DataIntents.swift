//
//  DataIntents.swift
//  voice notes
//
//  Shortcuts / Siri / Spotlight actions that move information in and out of
//  EEON (2026-09-26). Until now the only actions were Record/Stop, and none
//  took input or returned anything, so no automation could reach EEON.
//
//  In:  Add to EEON (text or a link), Add File to EEON (audio, video, PDF,
//       image, text file).
//  Out: Get Recent Notes, Search Notes, Ask EEON, and a Note entity that
//       other actions can pass along (its title/text/date are readable).
//
//  Inbound items go through the Share Extension's queue
//  (SharedDefaults.pendingIngests → IntelligenceService.processPendingIngests),
//  so a link is fetched as an article, a PDF/image becomes text, audio is
//  transcribed, and everything gets the normal extraction + embedding. An
//  item leaves the queue only after its note is saved, so if iOS ends the
//  intent early the app finishes it on next launch.
//
//  App-target only (not duplicated into the widget): perform() needs the
//  model container, set in voice_notesApp.init().
//

import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Set once in voice_notesApp.init().
enum DataIntentBridge {
    static var container: ModelContainer?

    @MainActor
    static func drainQueue() async {
        guard let container else { return }
        let context = container.mainContext
        let projects = libraryVisibleProjects((try? context.fetch(FetchDescriptor<Project>())) ?? [])
        let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        await IntelligenceService.shared.processPendingIngests(context: context, projects: projects, tags: tags)
    }

    /// Copy any file (Open in EEON, the in-app picker) into the shared
    /// queue and process it. Returns false when the file couldn't be copied.
    @MainActor @discardableResult
    static func importFile(_ url: URL, title: String? = nil) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let folder = SharedDefaults.sharedImportsURL else { return false }
        let ext = url.pathExtension.lowercased()
        let stored = "\(UUID().uuidString).\(ext.isEmpty ? "dat" : ext)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(stored))
        } catch {
            print("[DataIntentBridge] import failed for \(url.lastPathComponent): \(error)")
            return false
        }
        enqueue(file: stored, originalName: url.lastPathComponent,
                type: UTType(filenameExtension: ext) ?? .data, title: title)
        return true
    }

    /// Clipboard → note: a link is read as an article, an image is OCR'd,
    /// text is saved as written. Returns false when the clipboard is empty.
    @MainActor @discardableResult
    static func importClipboard() -> Bool {
        let board = UIPasteboard.general
        if let url = board.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            enqueue(text: nil, url: url.absoluteString)
        } else if let text = board.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isLink = !trimmed.contains(where: \.isWhitespace)
                && URL(string: trimmed).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } == true
            enqueue(text: isLink ? nil : trimmed, url: isLink ? trimmed : nil)
        } else if let image = board.image, let data = image.pngData(), let folder = SharedDefaults.sharedImportsURL {
            let stored = "\(UUID().uuidString).png"
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent(stored))
            } catch { return false }
            enqueue(file: stored, originalName: "Pasted image.png", type: .png, title: nil)
        } else {
            return false
        }
        return true
    }

    @MainActor
    static func enqueue(text: String?, url: String?, title: String? = nil) {
        SharedDefaults.addPendingIngest(.init(
            id: UUID().uuidString, url: url, text: text, title: title, annotation: nil,
            sharedFileName: nil, originalFileName: nil,
            contentTypeIdentifier: text != nil ? SharedDefaults.typedTextContentType : nil,
            createdAt: Date()
        ))
        Task { await drainQueue() }
    }

    @MainActor
    static func enqueue(file stored: String, originalName: String, type: UTType, title: String?) {
        SharedDefaults.addPendingIngest(.init(
            id: UUID().uuidString, url: nil, text: nil, title: title, annotation: nil,
            sharedFileName: stored, originalFileName: originalName,
            contentTypeIdentifier: type.identifier, createdAt: Date()
        ))
        Task { await drainQueue() }
    }

    @MainActor
    static func notes(limit: Int, matching query: String? = nil) throws -> [Note] {
        guard let container else { throw DataIntentError.appNotReady }
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if query == nil { descriptor.fetchLimit = limit * 2 }
        let all = librarySearchableNotes(try container.mainContext.fetch(descriptor))
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return Array(all.prefix(limit))
        }
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let hits = all.filter { note in
            let haystack = [note.title, note.content, note.enhancedNoteText ?? "", note.transcript ?? ""]
                .joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        return Array(hits.prefix(limit))
    }
}

enum DataIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady, empty, unreadableFile, noAnswer(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "EEON isn't ready yet — open the app once, then try again."
        case .empty: return "There was nothing to add."
        case .unreadableFile: return "EEON couldn't read that file."
        case .noAnswer(let reason): return "EEON couldn't answer: \(reason)"
        }
    }
}

// MARK: - In

struct AddToEEONIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to EEON"
    static var description = IntentDescription(
        "Save text or a link as an EEON note. Links are read as articles; everything gets EEON's summary, tasks and search.",
        categoryName: "Add"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text or Link", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Title")
    var noteTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to EEON") { \.$noteTitle }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DataIntentError.empty }
        let isLink = !trimmed.contains(where: \.isWhitespace)
            && URL(string: trimmed).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } == true
        DataIntentBridge.enqueue(text: isLink ? nil : trimmed, url: isLink ? trimmed : nil, title: noteTitle)
        return .result(dialog: isLink ? "Saving that link to EEON." : "Added to EEON.")
    }
}

struct AddFileToEEONIntent: AppIntent {
    static var title: LocalizedStringResource = "Add File to EEON"
    static var description = IntentDescription(
        "Import a recording, video, PDF, image or text file. Recordings are transcribed; documents and photos become searchable text.",
        categoryName: "Add"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "File",
        supportedContentTypes: [.audio, .movie, .pdf, .image, .plainText, .text]
    )
    var file: IntentFile

    @Parameter(title: "Title")
    var noteTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$file) to EEON") { \.$noteTitle }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let folder = SharedDefaults.sharedImportsURL else { throw DataIntentError.appNotReady }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let type = file.type ?? UTType(filenameExtension: (file.filename as NSString).pathExtension) ?? .data
        let ext = type.preferredFilenameExtension ?? (file.filename as NSString).pathExtension
        let stored = "\(UUID().uuidString).\(ext.isEmpty ? "dat" : ext)"
        let data = file.data
        guard !data.isEmpty else { throw DataIntentError.unreadableFile }
        try data.write(to: folder.appendingPathComponent(stored), options: .atomic)

        DataIntentBridge.enqueue(file: stored, originalName: file.filename, type: type, title: noteTitle)
        return .result(dialog: "Added \(file.filename) to EEON.")
    }
}

// MARK: - Out

struct NoteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "EEON Note"
    static var defaultQuery = NoteEntityQuery()

    var id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Text") var text: String
    @Property(title: "Created") var created: Date
    @Property(title: "Link") var link: URL?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(created.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    @MainActor
    init(_ note: Note) {
        id = note.id
        title = note.title.isEmpty ? "Untitled note" : note.title
        text = note.enhancedNoteText ?? note.transcript ?? note.content
        created = note.createdAt
        link = note.originalURL.flatMap(URL.init(string:))
    }
}

struct NoteEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        guard let container = DataIntentBridge.container else { throw DataIntentError.appNotReady }
        let wanted = Set(identifiers)
        let notes = try container.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { wanted.contains($0.id) }))
        return notes.map(NoteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteEntity] {
        try DataIntentBridge.notes(limit: 25, matching: string).map(NoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteEntity] {
        try DataIntentBridge.notes(limit: 15).map(NoteEntity.init)
    }
}

struct GetRecentNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recent EEON Notes"
    static var description = IntentDescription("Returns your most recent EEON notes.", categoryName: "Find")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Count", default: 5, inclusiveRange: (1, 50))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$count) most recent EEON notes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        .result(value: try DataIntentBridge.notes(limit: count).map(NoteEntity.init))
    }
}

struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search EEON Notes"
    static var description = IntentDescription(
        "Finds notes containing every word you enter, newest first.", categoryName: "Find"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Search For")
    var query: String

    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 50))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search EEON for \(\.$query)") { \.$limit }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        .result(value: try DataIntentBridge.notes(limit: limit, matching: query).map(NoteEntity.init))
    }
}

struct AskEEONIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask EEON"
    static var description = IntentDescription(
        "Ask a question about everything you've told EEON and get an answer from your notes.",
        categoryName: "Find"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask EEON?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask EEON \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let container = DataIntentBridge.container else { throw DataIntentError.appNotReady }
        let context = container.mainContext
        let notes = try context.fetch(FetchDescriptor<Note>())
        let articles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        do {
            let response = try await RAGService.shared.answerQuestion(
                query: question, allNotes: notes, articles: articles, projects: projects
            )
            return .result(value: response.answer, dialog: "\(response.answer)")
        } catch {
            throw DataIntentError.noAnswer(error.localizedDescription)
        }
    }
}
