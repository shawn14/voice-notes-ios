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
        // Only compile for pro users
        guard UsageService.shared.isPro else { return }

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
}
