//
//  KnowledgeCompiler.swift
//  voice notes
//
//  Compiles cross-note intelligence into KnowledgeArticles.
//  Tier 1: mark dirty (local). Tier 2.5: recompile (API). Tier 3: lint/heal (API).
//

import Foundation
import SwiftData

@Observable
final class KnowledgeCompiler {
    static let shared = KnowledgeCompiler()

    var isCompiling = false
    var lastCompileAt: Date?

    private enum Keys {
        static let lastCompileDate = "knowledgeCompiler.lastCompileDate"
    }

    private init() {
        lastCompileAt = UserDefaults.standard.object(forKey: Keys.lastCompileDate) as? Date
    }

    // MARK: - Tier 1: Mark Affected Articles (on note save, local only)

    /// After extraction, identify which articles this note affects.
    /// Sets isDirty = true on each. Zero API calls.
    @MainActor
    func markAffectedArticles(note: Note, context: ModelContext) {
        let allArticles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []

        // Seed notes route directly to their singleton article — skip people/topics/project extraction
        switch note.sourceType {
        case .profileSeed:
            let name = AuthService.shared.userName ?? "You"
            let article = findOrCreate(name: name, type: .self, existing: allArticles, context: context)
            // Seeds replace prior seed content — drop old seed-note links so compile sees only current seed
            let seedIds = Self.priorSeedNoteIds(for: .profileSeed, in: context, excluding: note.id)
            article.linkedNoteIds = article.linkedNoteIds.filter { !seedIds.contains($0) }
            markDirty(article: article, noteId: note.id)
        case .purposeSeed:
            let article = findOrCreate(name: "Purpose", type: .purpose, existing: allArticles, context: context)
            let seedIds = Self.priorSeedNoteIds(for: .purposeSeed, in: context, excluding: note.id)
            article.linkedNoteIds = article.linkedNoteIds.filter { !seedIds.contains($0) }
            markDirty(article: article, noteId: note.id)
        default:
            // People mentioned in this note
            for personName in note.mentionedPeople {
                let article = findOrCreate(
                    name: personName,
                    type: .person,
                    existing: allArticles,
                    context: context
                )
                markDirty(article: article, noteId: note.id)
            }

            // Topics extracted from this note — .document source upgrades topic → reference
            let topicType: KnowledgeArticleType = (note.sourceType == .document) ? .reference : .topic
            for topic in note.topics {
                let article = findOrCreate(
                    name: topic,
                    type: topicType,
                    existing: allArticles,
                    context: context
                )
                markDirty(article: article, noteId: note.id)
            }

            // Inferred project
            if let projectName = note.inferredProjectName, !projectName.isEmpty {
                let article = findOrCreate(
                    name: projectName,
                    type: .project,
                    existing: allArticles,
                    context: context
                )
                markDirty(article: article, noteId: note.id)
            }
        }

        // Log ingest event
        let affectedNames = (note.mentionedPeople + note.topics + [note.inferredProjectName].compactMap { $0 })
            .filter { !$0.isEmpty }
        let ingestTitle: String
        switch note.sourceType {
        case .voice: ingestTitle = "Recorded voice note"
        case .webArticle: ingestTitle = "Ingested web article"
        case .derived: ingestTitle = "Saved assistant answer"
        case .document: ingestTitle = "Ingested document"
        case .audioImport: ingestTitle = "Imported audio file"
        case .profileSeed: ingestTitle = "Updated your profile"
        case .purposeSeed: ingestTitle = "Updated your purpose"
        }
        let detail = affectedNames.isEmpty ? nil : "Marked \(affectedNames.count) articles: \(affectedNames.prefix(5).joined(separator: ", "))"
        let event = KnowledgeEvent(eventType: .ingest, title: ingestTitle, detail: detail, sourceNoteId: note.id)
        context.insert(event)

        try? context.save()
    }

    // MARK: - Seed Management

    /// Returns IDs of prior seed notes of the given type, excluding the current one.
    /// Used to detach stale seed links from their article (so compile uses only the newest seed).
    @MainActor
    private static func priorSeedNoteIds(
        for sourceType: NoteSourceType,
        in context: ModelContext,
        excluding currentId: UUID
    ) -> Set<UUID> {
        let raw = sourceType.rawValue
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.sourceTypeRaw == raw }
        )
        let priorNotes = (try? context.fetch(descriptor)) ?? []
        return Set(priorNotes.map(\.id).filter { $0 != currentId })
    }

    /// Delete prior seed notes of a given type after saving a new seed.
    /// Keeps the app's note list clean — only one canonical seed per article.
    @MainActor
    static func replacePriorSeeds(
        for sourceType: NoteSourceType,
        keeping currentId: UUID,
        in context: ModelContext
    ) {
        let raw = sourceType.rawValue
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.sourceTypeRaw == raw }
        )
        let priorNotes = (try? context.fetch(descriptor)) ?? []
        for note in priorNotes where note.id != currentId {
            context.delete(note)
        }
        try? context.save()
    }

    // MARK: - Entity Resolution

    private func findOrCreate(
        name: String,
        type: KnowledgeArticleType,
        existing: [KnowledgeArticle],
        context: ModelContext
    ) -> KnowledgeArticle {
        // Look for existing article of the same type that matches
        for article in existing where article.articleType == type {
            if article.matches(name: name) {
                return article
            }
        }

        // Create new article
        let article = KnowledgeArticle(name: name, articleType: type)
        context.insert(article)
        return article
    }

    private func markDirty(article: KnowledgeArticle, noteId: UUID) {
        article.isDirty = true
        article.mentionCount += 1
        article.lastMentionedAt = Date()
        article.updatedAt = Date()
        article.addLinkedNote(id: noteId)
    }

    // MARK: - Tier 2.5: Recompile Dirty Articles (on note save + app foreground)

    /// Recompile articles marked dirty. Max 5 per pass, 15-min cooldown.
    /// Pass `force: true` for user-initiated saves (Tune EEON) to bypass the cooldown.
    func recompileDirtyArticles(context: ModelContext, force: Bool = false) async {
        // 15-minute cooldown — skipped for user-initiated (force) compiles
        if !force, let lastCompile = lastCompileAt,
           Date().timeIntervalSince(lastCompile) < 15 * 60 {
            return
        }

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            // Defensive — ensure isCompiling flag isn't left spinning if the UI flipped it
            await MainActor.run { isCompiling = false }
            return
        }
        guard !isCompiling else { return }

        await MainActor.run { isCompiling = true }

        // Fetch dirty articles, sorted by most recently mentioned
        var descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.isDirty == true },
            sortBy: [SortDescriptor(\.lastMentionedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5

        guard let dirtyArticles = try? context.fetch(descriptor), !dirtyArticles.isEmpty else {
            await MainActor.run {
                isCompiling = false
                // Even with nothing to compile, make sure downstream consumers see the latest cached state
                ContextAssembler.shared.refresh(from: context)
            }
            return
        }

        // Fetch all notes for lookups
        let allNotes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let noteLookup = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })

        for article in dirtyArticles {
            do {
                // Get new notes since last compile
                let linkedIds = article.linkedNoteIds
                let newNotes: [Note]
                if let lastCompiled = article.lastCompiledNoteDate {
                    newNotes = linkedIds.compactMap { noteLookup[$0] }
                        .filter { $0.createdAt > lastCompiled }
                        .sorted { $0.createdAt < $1.createdAt }
                } else {
                    // First compile — include all linked notes
                    newNotes = linkedIds.compactMap { noteLookup[$0] }
                        .sorted { $0.createdAt < $1.createdAt }
                }

                guard !newNotes.isEmpty else {
                    await MainActor.run { article.isDirty = false }
                    continue
                }

                let noteTexts = newNotes.map { note -> String in
                    let text = note.enhancedNoteText ?? note.transcript ?? note.content
                    let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
                    let prefix: String
                    switch note.sourceType {
                    case .voice:
                        prefix = "[\(dateStr)]"
                    case .webArticle:
                        prefix = "[WEB SOURCE: \(dateStr)]"
                    case .derived:
                        prefix = "[DERIVED: \(dateStr)]"
                    case .document:
                        prefix = "[DOCUMENT: \(dateStr)]"
                    case .audioImport:
                        prefix = "[AUDIO IMPORT: \(dateStr)]"
                    case .profileSeed:
                        prefix = "[PROFILE SEED (user-authored, high authority)]"
                    case .purposeSeed:
                        prefix = "[PURPOSE SEED (user-authored, high authority)]"
                    }
                    return "\(prefix) \(String(text.prefix(500)))"
                }

                let response = try await SummaryService.compileArticle(
                    existingSummary: article.summary.isEmpty ? nil : article.summary,
                    existingOpenThreads: article.openThreads,
                    existingTimeline: article.timeline,
                    existingConnections: article.connections,
                    existingSentimentArc: article.sentimentArc,
                    existingDecisions: article.decisions,
                    existingRelationshipContext: article.relationshipContext,
                    existingThinkingEvolution: article.thinkingEvolution,
                    articleName: article.name,
                    articleType: article.articleType,
                    newNoteTexts: noteTexts,
                    apiKey: apiKey
                )

                await MainActor.run {
                    article.summary = response.summary
                    if let threads = response.openThreads { article.openThreads = threads }
                    if let timeline = response.timeline { article.timeline = timeline }
                    if let connections = response.connections { article.connections = connections }
                    if let arc = response.sentimentArc { article.sentimentArc = arc }
                    if let decisions = response.decisions { article.decisions = decisions }
                    if let rel = response.relationshipContext { article.relationshipContext = rel }
                    if let evolution = response.thinkingEvolution { article.thinkingEvolution = evolution }
                    // Purpose-only: persist the compiled home layout JSON so AIHomeView can read it.
                    if article.articleType == .purpose, let layout = response.homeLayoutJSON, !layout.isEmpty {
                        article.homeLayoutJSON = layout
                    }

                    article.isDirty = false
                    article.lastCompiledAt = Date()
                    article.lastCompiledNoteDate = newNotes.last?.createdAt
                    article.updatedAt = Date()

                    // Log compile event
                    let compileEvent = KnowledgeEvent(
                        eventType: .compile,
                        title: "Compiled \(article.name)",
                        detail: "Incorporated \(newNotes.count) new note\(newNotes.count == 1 ? "" : "s")",
                        relatedArticleName: article.name
                    )
                    context.insert(compileEvent)

                    try? context.save()
                }
            } catch {
                print("[KnowledgeCompiler] Failed to compile article '\(article.name)': \(error)")
            }
        }

        // Only set cooldown after actually compiling
        await MainActor.run {
            isCompiling = false
            lastCompileAt = Date()
            UserDefaults.standard.set(Date(), forKey: Keys.lastCompileDate)
            // Always refresh — cache is cheap to rebuild and being stale is the bug we just shipped
            ContextAssembler.shared.refresh(from: context)
        }
    }

    // MARK: - Tier 3: Lint Articles (daily, one API call)

    /// Scan all articles for stale threads, contradictions, and gaps.
    func lintArticles(context: ModelContext) async -> [KnowledgeLintResult] {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return [] }

        let allArticles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []
        guard !allArticles.isEmpty else { return [] }

        let summaries = allArticles.map { article -> (name: String, type: String, summary: String, openThreadCount: Int, daysSinceLastMention: Int) in
            let daysSince: Int
            if let last = article.lastMentionedAt {
                daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            } else {
                daysSince = Int.max
            }
            return (
                name: article.name,
                type: article.articleType.label,
                summary: article.summary.isEmpty ? "(no summary yet)" : article.summary,
                openThreadCount: article.openThreads.count,
                daysSinceLastMention: daysSince
            )
        }

        do {
            let results = try await SummaryService.lintArticles(articleSummaries: summaries, apiKey: apiKey)

            // Log lint event if issues found
            if !results.isEmpty {
                let typeCounts = Dictionary(grouping: results, by: { $0.lintType })
                    .map { "\($0.value.count) \($0.key.replacingOccurrences(of: "_", with: " "))" }
                    .joined(separator: ", ")
                let lintEvent = KnowledgeEvent(
                    eventType: .lint,
                    title: "Knowledge health check",
                    detail: "Found \(results.count) issue\(results.count == 1 ? "" : "s"): \(typeCounts)"
                )
                await MainActor.run {
                    context.insert(lintEvent)
                    try? context.save()
                }
            }

            // Auto-cleanup: delete events older than 30 days
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let oldEvents = (try? context.fetch(FetchDescriptor<KnowledgeEvent>(
                predicate: #Predicate { $0.createdAt < cutoff }
            ))) ?? []
            for event in oldEvents {
                await MainActor.run { context.delete(event) }
            }
            if !oldEvents.isEmpty {
                await MainActor.run { try? context.save() }
            }

            return results
        } catch {
            print("[KnowledgeCompiler] Lint failed: \(error)")
            return []
        }
    }
}
