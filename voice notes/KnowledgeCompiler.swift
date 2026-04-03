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

        // Topics extracted from this note
        for topic in note.topics {
            let article = findOrCreate(
                name: topic,
                type: .topic,
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
    func recompileDirtyArticles(context: ModelContext) async {
        // 15-minute cooldown
        if let lastCompile = lastCompileAt,
           Date().timeIntervalSince(lastCompile) < 15 * 60 {
            return
        }

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return }
        guard !isCompiling else { return }

        await MainActor.run { isCompiling = true }

        // Fetch dirty articles, sorted by most recently mentioned
        var descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.isDirty == true },
            sortBy: [SortDescriptor(\.lastMentionedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5

        guard let dirtyArticles = try? context.fetch(descriptor), !dirtyArticles.isEmpty else {
            await MainActor.run { isCompiling = false }
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
                    return "[\(dateStr)] \(String(text.prefix(500)))"
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

                    article.isDirty = false
                    article.lastCompiledAt = Date()
                    article.lastCompiledNoteDate = newNotes.last?.createdAt
                    article.updatedAt = Date()

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
            return try await SummaryService.lintArticles(articleSummaries: summaries, apiKey: apiKey)
        } catch {
            print("[KnowledgeCompiler] Lint failed: \(error)")
            return []
        }
    }
}
