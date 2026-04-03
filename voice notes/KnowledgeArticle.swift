//
//  KnowledgeArticle.swift
//  voice notes
//
//  Living knowledge article — compiled by LLM from voice notes.
//  Types: person, project, topic. Auto-maintained, never manually edited.
//

import Foundation
import SwiftData

// MARK: - Article Type

enum KnowledgeArticleType: String, CaseIterable, Codable {
    case person = "person"
    case project = "project"
    case topic = "topic"

    var icon: String {
        switch self {
        case .person: return "person.fill"
        case .project: return "folder.fill"
        case .topic: return "lightbulb.fill"
        }
    }

    var label: String {
        switch self {
        case .person: return "Person"
        case .project: return "Project"
        case .topic: return "Topic"
        }
    }
}

// MARK: - JSON Supporting Types

struct OpenThread: Codable, Identifiable {
    var id: String { thread }
    let thread: String
    let status: String      // "open", "waiting", "stale"
    let daysOpen: Int
}

struct TimelineEvent: Codable, Identifiable {
    var id: String { "\(date)-\(event)" }
    let date: String        // ISO date or human-readable
    let event: String
}

struct ArticleConnection: Codable, Identifiable {
    var id: String { articleName }
    let articleName: String
    let reason: String
}

struct ArticleDecision: Codable, Identifiable {
    var id: String { decision }
    let decision: String
    let status: String      // "resolved", "open"
    let date: String?
}

struct KnowledgeLintResult: Codable, Identifiable {
    var id: String { content }
    let lintType: String    // "stale_thread", "contradiction", "connection", "gap"
    let content: String
    let severity: String    // "info", "warning", "urgent"
    let relatedArticleNames: [String]
}

// MARK: - KnowledgeArticle Model

@Model
final class KnowledgeArticle {
    var id: UUID = UUID()
    var name: String = ""
    var articleTypeRaw: String = "topic"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastCompiledAt: Date?
    var isDirty: Bool = true
    var mentionCount: Int = 0
    var lastMentionedAt: Date?

    // Core content (LLM-compiled)
    var summary: String = ""
    var openThreadsJSON: String?
    var timelineJSON: String?
    var connectionsJSON: String?
    var sentimentArc: String?

    // Type-specific fields
    var decisionsJSON: String?
    var relationshipContext: String?
    var thinkingEvolution: String?

    // Source tracking
    var linkedNoteIdsJSON: String?
    var lastCompiledNoteDate: Date?

    // Aliases for entity resolution
    var aliasesJSON: String?

    init(name: String, articleType: KnowledgeArticleType) {
        self.id = UUID()
        self.name = name
        self.articleTypeRaw = articleType.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDirty = true
        self.mentionCount = 0

        // Auto-generate initial aliases
        var initial = [name.lowercased()]
        let words = name.split(separator: " ")
        if words.count > 1 {
            // Add first name for people ("Sarah Chen" -> "sarah")
            initial.append(String(words[0]).lowercased())
        }
        self.aliases = initial
    }

    // MARK: - Computed Accessors

    var articleType: KnowledgeArticleType {
        get { KnowledgeArticleType(rawValue: articleTypeRaw) ?? .topic }
        set { articleTypeRaw = newValue.rawValue }
    }

    var openThreads: [OpenThread] {
        get {
            guard let json = openThreadsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([OpenThread].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            openThreadsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var timeline: [TimelineEvent] {
        get {
            guard let json = timelineJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TimelineEvent].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            timelineJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var connections: [ArticleConnection] {
        get {
            guard let json = connectionsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ArticleConnection].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            connectionsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var decisions: [ArticleDecision] {
        get {
            guard let json = decisionsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ArticleDecision].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            decisionsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var linkedNoteIds: [UUID] {
        get {
            guard let json = linkedNoteIdsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            linkedNoteIdsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var aliases: [String] {
        get {
            guard let json = aliasesJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            aliasesJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // MARK: - Entity Resolution

    func matches(name candidate: String) -> Bool {
        let normalized = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if self.name.lowercased() == normalized { return true }
        return aliases.contains { $0 == normalized || normalized.contains($0) || $0.contains(normalized) }
    }

    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var current = aliases
        if !current.contains(normalized) {
            current.append(normalized)
            aliases = current
        }
    }

    func addLinkedNote(id: UUID) {
        var current = linkedNoteIds
        if !current.contains(id) {
            current.append(id)
            linkedNoteIds = current
        }
    }

    var isRecentlyUpdated: Bool {
        guard let compiled = lastCompiledAt else { return false }
        return Date().timeIntervalSince(compiled) < 24 * 60 * 60
    }
}
