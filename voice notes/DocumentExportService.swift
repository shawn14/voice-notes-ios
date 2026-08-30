//
//  DocumentExportService.swift
//  voice notes
//
//  "Conversations become searchable files": writes each note as markdown into
//  EEON's iCloud Drive document container by default, with a user-selected
//  iCloud Drive folder as an advanced fallback. Files are named stably per note
//  (date + title slug + id suffix), so re-exports overwrite in place and
//  nothing is ever duplicated or deleted.
//

import Foundation
import SwiftData

@Observable
final class DocumentExportService {
    static let shared = DocumentExportService()

    enum FolderSelectionResult {
        case ready
        case iCloudUnavailable
        case localOnly
        case notICloudDrive
        case failed
    }

    static let enabledKey = "markdownVaultAutoExportEnabled"
    private static let legacyEnabledKey = "documentExportEnabled"
    private static let defaultVaultFolderName = "EEON Vault"
    private static let iCloudContainerIdentifier = "iCloud.aivoiceeeon"
    private let bookmarkKey = "documentExportFolderBookmark"
    private let folderModeKey = "documentExportFolderMode"
    private let appICloudVaultPathKey = "documentExportAppICloudVaultPath"
    private let userSelectedCreatesVaultSubfolderKey = "documentExportCreatesVaultSubfolder"

    private init() {}

    private enum FolderMode: String {
        case appICloud
        case userSelected
    }

    private struct FolderAccess {
        let url: URL
        let stopAccessing: () -> Void
    }

    struct ExportedDocument: Codable, Sendable {
        let path: String
        let contents: String
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var hasFolder: Bool {
        guard let folder = resolveFolder() else { return false }
        folder.stopAccessing()
        return true
    }

    /// Human-readable name of the chosen folder, for the Settings row.
    var folderName: String? {
        guard let folder = resolveFolder() else { return nil }
        defer { folder.stopAccessing() }
        return folder.url.lastPathComponent
    }

    var isUsingDefaultICloudFolder: Bool {
        folderMode == .appICloud
    }

    /// Use EEON's app-owned iCloud Documents container. This avoids Apple's
    /// generic folder picker for the default setup and lets iCloud sync the
    /// vault to the user's Mac later, wherever the phone is.
    @discardableResult
    func useDefaultICloudFolder() -> FolderSelectionResult {
        guard let folderURL = defaultICloudVaultURL() else {
            disconnect()
            return .iCloudUnavailable
        }

        do {
            try createDirectory(at: folderURL)
        } catch {
            print("[DocumentExport] default iCloud setup failed: \(error)")
            disconnect()
            return .failed
        }

        let defaults = UserDefaults.standard
        defaults.set(FolderMode.appICloud.rawValue, forKey: folderModeKey)
        defaults.set(folderURL.path, forKey: appICloudVaultPathKey)
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: userSelectedCreatesVaultSubfolderKey)
        // Settings enables automatic export only after the proof write succeeds.
        defaults.set(false, forKey: Self.enabledKey)
        defaults.set(false, forKey: Self.legacyEnabledKey)
        return .ready
    }

    /// Store the picked folder (from a Files-app folder picker) as a
    /// security-scoped bookmark.
    @discardableResult
    func setFolder(_ url: URL) -> FolderSelectionResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            switch Self.syncProviderKind(for: url, bookmark: bookmark) {
            case .iCloudDrive:
                break
            case .localStorage:
                disconnect()
                return .localOnly
            case .unsupported:
                disconnect()
                return .notICloudDrive
            }

            let createsVaultSubfolder = Self.isVisibleICloudDriveRoot(url)
            let targetURL: URL
            if createsVaultSubfolder {
                targetURL = url.appendingPathComponent(Self.defaultVaultFolderName, isDirectory: true)
            } else {
                targetURL = url
            }
            do {
                try createDirectory(at: targetURL)
            } catch {
                print("[DocumentExport] folder setup failed: \(error)")
                disconnect()
                return .failed
            }

            let defaults = UserDefaults.standard
            defaults.set(bookmark, forKey: bookmarkKey)
            defaults.set(FolderMode.userSelected.rawValue, forKey: folderModeKey)
            defaults.set(createsVaultSubfolder, forKey: userSelectedCreatesVaultSubfolderKey)
            defaults.removeObject(forKey: appICloudVaultPathKey)
            // Settings enables automatic export only after the proof write succeeds.
            defaults.set(false, forKey: Self.enabledKey)
            defaults.set(false, forKey: Self.legacyEnabledKey)
            return .ready
        } catch {
            print("[DocumentExport] bookmark creation failed: \(error)")
            disconnect()
            return .failed
        }
    }

    /// Stop writing future files and forget the connection. Existing exported
    /// markdown files are user-owned files and are intentionally left alone.
    func disconnect() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Self.enabledKey)
        defaults.set(false, forKey: Self.legacyEnabledKey)
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: folderModeKey)
        defaults.removeObject(forKey: appICloudVaultPathKey)
        defaults.removeObject(forKey: userSelectedCreatesVaultSubfolderKey)
    }

    /// Write a small proof file into the connected vault. This gives the Mac
    /// and MCP clients a concrete sync target without reading private notes.
    func writeAIAccessTestFile() -> Bool {
        guard let folder = resolveFolder() else { return false }
        defer { folder.stopAccessing() }

        let contents = Self.aiAccessTestContents(writtenAt: Date())
        do {
            try write(contents, to: folder.url.appendingPathComponent("eeon-ai-access-test.txt"))
            return true
        } catch {
            print("[DocumentExport] AI access test write failed: \(error)")
            return false
        }
    }

    /// Export one note as markdown into the chosen folder. Overwrites the
    /// note's own file if it exists (stable name). No-op unless enabled and
    /// a folder is set. Never deletes anything.
    func export(note: Note) {
        export(note: note, metadata: .empty)
    }

    /// Export one note with related SwiftData records when a context is
    /// available. This is the MCP-grade path: frontmatter includes actions,
    /// decisions, commitments, project, calendar context, speakers, and tags.
    @MainActor
    func export(note: Note, context: ModelContext) {
        export(note: note, metadata: metadata(for: note, context: context))
    }

    private func export(note: Note, metadata: NoteExportMetadata) {
        guard isEnabled else { return }
        guard let folder = resolveFolder() else { return }
        defer { folder.stopAccessing() }

        let fileURL = folder.url.appendingPathComponent(fileName(for: note))
        let markdown = Self.markdown(for: note, metadata: metadata)
        do {
            try write(markdown, to: fileURL)
            writeVaultIndex(in: folder.url)
        } catch {
            print("[DocumentExport] write failed: \(error)")
        }
    }

    /// Export one compiled knowledge article into an articles/ subfolder.
    func export(article: KnowledgeArticle) {
        guard isEnabled else { return }
        guard let folder = resolveFolder() else { return }
        defer { folder.stopAccessing() }

        let articlesFolder = folder.url.appendingPathComponent("articles", isDirectory: true)
        do {
            try createDirectory(at: articlesFolder)
            let fileURL = articlesFolder.appendingPathComponent(articleFileName(for: article))
            try write(Self.markdown(for: article), to: fileURL)
            writeVaultIndex(in: folder.url)
        } catch {
            print("[DocumentExport] article write failed: \(error)")
        }
    }

    /// Remove the old generated article file after a rename. Note export never
    /// deletes user notes; this only targets the previous deterministic article
    /// filename for the same article id so MCP does not see both names.
    func removeExportedArticleFile(for article: KnowledgeArticle, previousName: String) {
        guard isEnabled else { return }
        guard let folder = resolveFolder() else { return }
        defer { folder.stopAccessing() }

        let articlesFolder = folder.url.appendingPathComponent("articles", isDirectory: true)
        let oldFileURL = articlesFolder.appendingPathComponent(articleFileName(for: article, name: previousName))
        do {
            if FileManager.default.fileExists(atPath: oldFileURL.path) {
                try FileManager.default.removeItem(at: oldFileURL)
                writeVaultIndex(in: folder.url)
            }
        } catch {
            print("[DocumentExport] old article removal failed: \(error)")
        }
    }

    /// Backfill: export every non-archived note. Returns the count written.
    func exportAll(notes: [Note]) -> Int {
        exportAll(notes: libraryVisibleNotes(notes), articles: [])
    }

    /// Backfill notes and articles into the chosen folder. Returns note count.
    func exportAll(notes: [Note], articles: [KnowledgeArticle]) -> Int {
        exportAll(notes: libraryVisibleNotes(notes), articles: libraryVisibleArticles(articles)) { _ in .empty }
    }

    /// Backfill notes and articles with full related metadata. Used by Settings
    /// so manually exporting old notes produces the same MCP-grade frontmatter
    /// as write-on-save exports.
    @MainActor
    func exportAll(notes: [Note], articles: [KnowledgeArticle], context: ModelContext) -> Int {
        exportAll(notes: libraryVisibleNotes(notes), articles: libraryVisibleArticles(articles)) { note in
            metadata(for: note, context: context)
        }
    }

    @MainActor
    func documentsForExport(
        notes: [Note],
        articles: [KnowledgeArticle],
        context: ModelContext
    ) -> [ExportedDocument] {
        var documents: [ExportedDocument] = []
        for note in libraryVisibleNotes(notes) {
            documents.append(ExportedDocument(
                path: fileName(for: note),
                contents: Self.markdown(for: note, metadata: metadata(for: note, context: context))
            ))
        }
        for article in libraryVisibleArticles(articles) where !article.summary.isEmpty {
            documents.append(ExportedDocument(
                path: "articles/\(articleFileName(for: article))",
                contents: Self.markdown(for: article)
            ))
        }
        documents.append(ExportedDocument(
            path: "eeon-ai-access-test.txt",
            contents: Self.aiAccessTestContents(writtenAt: Date())
        ))
        documents.append(ExportedDocument(
            path: "eeon-vault.html",
            contents: Self.vaultIndexHTML(for: documents, generatedAt: Date())
        ))
        return documents
    }

    private func exportAll(
        notes: [Note],
        articles: [KnowledgeArticle],
        metadataForNote: (Note) -> NoteExportMetadata
    ) -> Int {
        guard let folder = resolveFolder() else { return 0 }
        defer { folder.stopAccessing() }

        var written = 0
        for note in libraryVisibleNotes(notes) {
            let fileURL = folder.url.appendingPathComponent(fileName(for: note))
            if (try? write(Self.markdown(for: note, metadata: metadataForNote(note)), to: fileURL)) != nil {
                written += 1
            }
        }
        if !articles.isEmpty {
            let articlesFolder = folder.url.appendingPathComponent("articles", isDirectory: true)
            try? createDirectory(at: articlesFolder)
            for article in libraryVisibleArticles(articles) where !article.summary.isEmpty {
                let fileURL = articlesFolder.appendingPathComponent(articleFileName(for: article))
                try? write(Self.markdown(for: article), to: fileURL)
            }
        }
        writeVaultIndex(in: folder.url)
        return written
    }

    // MARK: - Internals

    private var folderMode: FolderMode? {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: folderModeKey),
           let mode = FolderMode(rawValue: rawValue) {
            return mode
        }
        if defaults.data(forKey: bookmarkKey) != nil {
            return .userSelected
        }
        return nil
    }

    private func resolveFolder() -> FolderAccess? {
        switch folderMode {
        case .appICloud:
            return resolveAppICloudFolder()
        case .userSelected:
            return resolveUserSelectedFolder()
        case nil:
            return nil
        }
    }

    private func resolveAppICloudFolder() -> FolderAccess? {
        let defaults = UserDefaults.standard
        let savedURL = defaults.string(forKey: appICloudVaultPathKey).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let folderURL = defaultICloudVaultURL() ?? savedURL
        guard let folderURL else { return nil }

        do {
            try createDirectory(at: folderURL)
        } catch {
            print("[DocumentExport] default iCloud folder resolve failed: \(error)")
            return nil
        }

        if defaults.string(forKey: appICloudVaultPathKey) != folderURL.path {
            defaults.set(folderURL.path, forKey: appICloudVaultPathKey)
        }

        return FolderAccess(url: folderURL) {}
    }

    private func defaultICloudVaultURL() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: Self.iCloudContainerIdentifier
        ) else {
            return nil
        }
        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.defaultVaultFolderName, isDirectory: true)
    }

    private func resolveUserSelectedFolder() -> FolderAccess? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            disconnect()
            return nil
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            disconnect()
            return nil
        }
        let accessing = url.startAccessingSecurityScopedResource()
        switch Self.syncProviderKind(for: url, bookmark: bookmark) {
        case .iCloudDrive:
            break
        case .localStorage, .unsupported:
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            disconnect()
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        let targetURL: URL
        if UserDefaults.standard.bool(forKey: userSelectedCreatesVaultSubfolderKey) {
            targetURL = url.appendingPathComponent(Self.defaultVaultFolderName, isDirectory: true)
            do {
                try createDirectory(at: targetURL)
            } catch {
                print("[DocumentExport] remembered folder setup failed: \(error)")
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                return nil
            }
        } else {
            targetURL = url
        }

        return FolderAccess(url: targetURL) {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private enum SyncProviderKind {
        case iCloudDrive
        case localStorage
        case unsupported
    }

    nonisolated private static func syncProviderKind(for url: URL, bookmark: Data) -> SyncProviderKind {
        if bookmarkDataContains(bookmark, "com.apple.FileProvider.LocalStorage") {
            return .localStorage
        }

        if bookmarkDataContains(bookmark, "CloudDocs")
            || bookmarkDataContains(bookmark, "MobileDocuments")
            || bookmarkDataContains(bookmark, "Mobile Documents")
            || bookmarkDataContains(bookmark, "iCloudDrive")
            || bookmarkDataContains(bookmark, "iCloud Drive")
            || bookmarkDataContains(bookmark, "com.apple.CloudDocs")
            || url.standardizedFileURL.path.contains("/com~apple~CloudDocs/")
            || FileManager.default.isUbiquitousItem(at: url) {
            return .iCloudDrive
        }

        return .unsupported
    }

    nonisolated private static func isVisibleICloudDriveRoot(_ url: URL) -> Bool {
        let standardizedPath = url.standardizedFileURL.path
        return url.lastPathComponent == "com~apple~CloudDocs"
            || url.lastPathComponent == "iCloud Drive"
            || standardizedPath.hasSuffix("/Mobile Documents/com~apple~CloudDocs")
            || standardizedPath.hasSuffix("/MobileDocuments/com~apple~CloudDocs")
    }

    nonisolated private static func bookmarkDataContains(_ bookmark: Data, _ value: String) -> Bool {
        bookmark.range(of: Data(value.utf8)) != nil
    }

    nonisolated private static func ensureDirectoryExists(at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            print("[DocumentExport] folder setup failed: \(error)")
            return false
        }
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
        markdown(for: note, metadata: .empty)
    }

    static func markdown(for note: Note, metadata: NoteExportMetadata) -> String {
        var parts: [String] = []
        parts.append(frontmatter(for: note, metadata: metadata))
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

    static func markdown(for article: KnowledgeArticle) -> String {
        var parts: [String] = []
        parts.append(frontmatter(for: article))
        parts.append("# \(article.name.isEmpty ? article.articleType.label : article.name)")

        if !article.summary.isEmpty {
            parts.append(article.summary)
        }
        if let relationship = article.relationshipContext, !relationship.isEmpty {
            parts.append("## Relationship Context\n\n\(relationship)")
        }
        if let evolution = article.thinkingEvolution, !evolution.isEmpty {
            parts.append("## Thinking Evolution\n\n\(evolution)")
        }
        if !article.openThreads.isEmpty {
            parts.append("## Open Threads\n\n" + article.openThreads.map {
                "- [\($0.status)] \($0.thread) (\($0.daysOpen)d)"
            }.joined(separator: "\n"))
        }
        if !article.timeline.isEmpty {
            parts.append("## Timeline\n\n" + article.timeline.map {
                "- \($0.date): \($0.event)"
            }.joined(separator: "\n"))
        }
        if !article.connections.isEmpty {
            parts.append("## Connections\n\n" + article.connections.map {
                "- \($0.articleName): \($0.reason)"
            }.joined(separator: "\n"))
        }
        if !article.decisions.isEmpty {
            parts.append("## Decisions\n\n" + article.decisions.map {
                "- [\($0.status)] \($0.decision)\($0.date.map { " (\($0))" } ?? "")"
            }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Metadata

    struct NoteExportMetadata {
        var projectName: String?
        var decisions: [ExtractedDecision]
        var actions: [ExtractedAction]
        var commitments: [ExtractedCommitment]

        static let empty = NoteExportMetadata(
            projectName: nil,
            decisions: [],
            actions: [],
            commitments: []
        )
    }

    @MainActor
    private func metadata(for note: Note, context: ModelContext) -> NoteExportMetadata {
        let noteID = note.id

        let decisions = (try? context.fetch(FetchDescriptor<ExtractedDecision>(
            predicate: #Predicate { $0.sourceNoteId == noteID }
        ))) ?? []
        let actions = (try? context.fetch(FetchDescriptor<ExtractedAction>(
            predicate: #Predicate { $0.sourceNoteId == noteID }
        ))) ?? []
        let commitments = (try? context.fetch(FetchDescriptor<ExtractedCommitment>(
            predicate: #Predicate { $0.sourceNoteId == noteID }
        ))) ?? []

        var projectName: String?
        if let projectID = note.projectId {
            projectName = (try? context.fetch(FetchDescriptor<Project>(
                predicate: #Predicate { $0.id == projectID }
            )))?.first?.name
        } else {
            projectName = note.inferredProjectName
        }

        return NoteExportMetadata(
            projectName: projectName,
            decisions: decisions,
            actions: actions,
            commitments: commitments
        )
    }

    // MARK: - Frontmatter

    private static func frontmatter(for note: Note, metadata: NoteExportMetadata) -> String {
        var lines: [String] = [
            "---",
            "eeon: 1",
            "id: \(note.id.uuidString)",
            "kind: note",
            "created: \(iso(note.createdAt))",
            "updated: \(iso(note.updatedAt))",
            "title: \(yaml(note.displayTitle))",
            "source: \(note.sourceType.rawValue)"
        ]

        append("project", metadata.projectName, to: &lines)
        append("people", note.mentionedPeople, to: &lines)
        append("speaker_names", note.speakerNames, to: &lines)
        append("topics", note.topics, to: &lines)
        append("tone", note.emotionalTone, to: &lines)
        append("format", note.summaryFormat, to: &lines)
        if let context = note.calendarContext {
            append("calendar_event", context.title, to: &lines)
            append("attendees", context.attendees, to: &lines)
        }
        if let duration = note.audioDuration {
            lines.append("audio_seconds: \(Int(duration.rounded()))")
        }
        appendBlock("speakers", note.speakerLabels.map { item in
            [
                "marker": item.marker,
                "name": item.displayName
            ]
        }, to: &lines)

        appendBlock("decisions", metadata.decisions.map { item in
            [
                "text": item.content,
                "status": item.status,
                "affects": item.affects
            ].compactMapValues { $0.isEmpty ? nil : $0 }
        }, to: &lines)

        appendBlock("actions", metadata.actions.map { item in
            [
                "text": item.content,
                "done": item.isCompleted ? "true" : "false",
                "due": item.deadline,
                "owner": item.owner
            ].compactMapValues { $0.isEmpty ? nil : $0 }
        }, to: &lines)

        appendBlock("commitments", metadata.commitments.map { item in
            [
                "who": item.who,
                "what": item.what,
                "done": item.isCompleted ? "true" : "false"
            ].compactMapValues { $0.isEmpty ? nil : $0 }
        }, to: &lines)

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func frontmatter(for article: KnowledgeArticle) -> String {
        var lines: [String] = [
            "---",
            "eeon: 1",
            "id: \(article.id.uuidString)",
            "kind: article",
            "article_type: \(article.articleType.rawValue)",
            "name: \(yaml(article.name))",
            "updated: \(iso(article.lastCompiledAt ?? article.updatedAt))",
            "mentions: \(article.mentionCount)"
        ]
        if let last = article.lastMentionedAt {
            lines.append("last_mentioned: \(iso(last))")
        }
        append("aliases", article.aliases, to: &lines)
        append("linked_notes", article.linkedNoteIds.map(\.uuidString), to: &lines)
        appendBlock("open_threads", article.openThreads.map { item in
            [
                "thread": item.thread,
                "status": item.status,
                "days_open": "\(item.daysOpen)"
            ]
        }, to: &lines)
        appendBlock("timeline", article.timeline.map { item in
            [
                "date": item.date,
                "event": item.event
            ]
        }, to: &lines)
        appendBlock("connections", article.connections.map { item in
            [
                "article": item.articleName,
                "reason": item.reason
            ]
        }, to: &lines)
        appendBlock("decisions", article.decisions.map { item in
            [
                "decision": item.decision,
                "status": item.status,
                "date": item.date ?? ""
            ].compactMapValues { $0.isEmpty ? nil : $0 }
        }, to: &lines)
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func append(_ key: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(key): \(yaml(value))")
    }

    private static func append(_ key: String, _ values: [String], to lines: inout [String]) {
        let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        lines.append("\(key): [\(clean.map(yaml).joined(separator: ", "))]")
    }

    private static func appendBlock(_ key: String, _ values: [[String: String]], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("\(key):")
        for value in values {
            lines.append("  -")
            for field in value.keys.sorted() {
                lines.append("    \(field): \(yaml(value[field] ?? ""))")
            }
        }
    }

    nonisolated private static func yaml(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    nonisolated private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    nonisolated private static func aiAccessTestContents(writtenAt: Date) -> String {
        """
        # EEON AI Access Test

        If an AI assistant can read this file from the EEON vault on your Mac, iCloud sync and MCP access are connected.

        Written: \(Self.iso(writtenAt))

        """
    }

    nonisolated private static func vaultIndexHTML(for documents: [ExportedDocument], generatedAt: Date) -> String {
        let markdownDocs = documents
            .filter { $0.path.hasSuffix(".md") }
            .sorted { $0.path < $1.path }
        let articleCount = markdownDocs.filter { $0.path.hasPrefix("articles/") }.count
        let noteCount = markdownDocs.count - articleCount
        let rows = markdownDocs.map { document -> String in
            let title = document.contents
                .components(separatedBy: .newlines)
                .first { $0.hasPrefix("# ") }?
                .replacingOccurrences(of: "# ", with: "") ?? URL(fileURLWithPath: document.path).deletingPathExtension().lastPathComponent
            return "<li><a href=\"\(htmlEscapedValue(document.path))\">\(htmlEscapedValue(title))</a><span>\(htmlEscapedValue(document.path))</span></li>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>EEON Vault</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; color: #151515; background: #f7f7f8; }
            main { padding: 24px; max-width: 920px; margin: 0 auto; }
            h1 { margin: 0 0 4px; font-size: 32px; }
            p { margin: 0 0 24px; color: #666; }
            ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
            li { background: white; border: 1px solid #e7e7ea; border-radius: 10px; padding: 12px 14px; }
            a { color: #111; font-weight: 650; text-decoration: none; display: block; }
            span { color: #777; font-size: 13px; }
          </style>
        </head>
        <body>
          <main>
            <h1>EEON Vault</h1>
            <p>\(noteCount) notes, \(articleCount) articles. Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened)).</p>
            <ul>
        \(rows)
            </ul>
          </main>
        </body>
        </html>
        """
    }

    nonisolated private static func htmlEscapedValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Browser index

    private func writeVaultIndex(in folder: URL) {
        let noteFiles = markdownFiles(in: folder)
            .filter { $0.lastPathComponent != "eeon-vault.html" }
        let articleFiles = markdownFiles(in: folder.appendingPathComponent("articles", isDirectory: true))
        let rows = (noteFiles + articleFiles)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { file -> String in
                let title = titleFromMarkdown(file) ?? file.deletingPathExtension().lastPathComponent
                let rel = relativePath(file, from: folder)
                return "<li><a href=\"\(htmlEscaped(rel))\">\(htmlEscaped(title))</a><span>\(htmlEscaped(rel))</span></li>"
            }
            .joined(separator: "\n")

        let pageHTML = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>EEON Vault</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; color: #151515; background: #f7f7f8; }
            main { padding: 24px; max-width: 920px; margin: 0 auto; }
            h1 { margin: 0 0 4px; font-size: 32px; }
            p { margin: 0 0 24px; color: #666; }
            ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
            li { background: white; border: 1px solid #e7e7ea; border-radius: 10px; padding: 12px 14px; }
            a { color: #111; font-weight: 650; text-decoration: none; display: block; }
            span { color: #777; font-size: 13px; }
          </style>
        </head>
        <body>
          <main>
            <h1>EEON Vault</h1>
            <p>\(noteFiles.count) notes, \(articleFiles.count) articles. Generated \(Date().formatted(date: .abbreviated, time: .shortened)).</p>
            <ul>
        \(rows)
            </ul>
          </main>
        </body>
        </html>
        """
        try? write(pageHTML, to: folder.appendingPathComponent("eeon-vault.html"))
    }

    private func write(_ contents: String, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?

        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try contents.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let writeError {
            throw writeError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    private func createDirectory(at url: URL) throws {
        var coordinationError: NSError?
        var createError: Error?
        let parentURL = url.deletingLastPathComponent()

        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: parentURL,
            options: [],
            error: &coordinationError
        ) { coordinatedParentURL in
            do {
                let coordinatedURL = coordinatedParentURL.appendingPathComponent(
                    url.lastPathComponent,
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: coordinatedURL, withIntermediateDirectories: true)
            } catch {
                createError = error
            }
        }

        if let createError {
            throw createError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    private func markdownFiles(in folder: URL) -> [URL] {
        var coordinationError: NSError?
        var readError: Error?
        var files: [URL] = []

        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: folder,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                files = try FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                readError = error
            }
        }

        if coordinationError != nil || readError != nil { return [] }
        return files.filter { $0.pathExtension.lowercased() == "md" }
    }

    private func titleFromMarkdown(_ url: URL) -> String? {
        var coordinationError: NSError?
        var readError: Error?
        var text = ""

        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                text = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        guard coordinationError == nil, readError == nil else { return nil }
        return text
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("# ") }?
            .replacingOccurrences(of: "# ", with: "")
    }

    private func relativePath(_ url: URL, from folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func articleFileName(for article: KnowledgeArticle) -> String {
        articleFileName(for: article, name: article.name)
    }

    private func articleFileName(for article: KnowledgeArticle, name: String) -> String {
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: "-")
        let suffix = article.id.uuidString.suffix(4).lowercased()
        return "\(article.articleType.rawValue)-\(slug.isEmpty ? "article" : slug)-\(suffix).md"
    }
}
