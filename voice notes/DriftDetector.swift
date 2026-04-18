//
//  DriftDetector.swift
//  voice notes
//
//  Detects when a user's capture behavior has drifted from their declared purpose.
//  Runs as a local heuristic (no API calls) — infers the role from the compiled
//  `.purpose` directive keywords, then checks whether recent notes match the
//  expected signals for that role.
//
//  When drift or staleness is detected, AIHomeView surfaces a soft banner
//  inviting the user to re-tune. Never auto-re-tunes silently.
//

import Foundation
import SwiftData

enum InferredRole: String {
    case founder, coach, interpreter, researcher, journaler, unknown
}

enum DriftStatus: Equatable {
    case fresh                        // Tuned recently, no drift
    case stale                        // Purpose article > 30 days old
    case drifted(role: InferredRole, score: Double)  // Role-expected signals missing in recent captures
}

@Observable
final class DriftDetector {
    static let shared = DriftDetector()

    private enum Keys {
        static let lastCheckDate = "driftDetector.lastCheckDate"
        static let lastBannerDismissedDate = "driftDetector.lastBannerDismissedDate"
    }

    /// Minimum interval between drift checks (runs at most once per 24h).
    private let checkInterval: TimeInterval = 24 * 60 * 60

    /// Hide the banner for this many days after user dismisses.
    private let dismissDuration: TimeInterval = 14 * 24 * 60 * 60

    private init() {}

    // MARK: - Public API

    /// Returns the current drift status. Cheap (no API calls). Caches nothing heavy.
    @MainActor
    func check(in context: ModelContext) -> DriftStatus {
        // Respect dismiss window — if user dismissed recently, return fresh
        let dismissRaw = UserDefaults.standard.double(forKey: Keys.lastBannerDismissedDate)
        let dismissedAt = Date(timeIntervalSince1970: dismissRaw)
        if Date().timeIntervalSince(dismissedAt) < dismissDuration {
            return .fresh
        }

        // Fetch the purpose article
        let purposeRaw = "purpose"
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == purposeRaw }
        )
        guard let article = (try? context.fetch(descriptor))?.first else {
            return .fresh
        }

        // Staleness: purpose hasn't been re-compiled in > 30 days
        if let compiled = article.lastCompiledAt,
           let daysSince = Calendar.current.dateComponents([.day], from: compiled, to: Date()).day,
           daysSince > 30 {
            return .stale
        }

        // Drift: does recent capture behavior match the role implied by the directive?
        let directive = (article.thinkingEvolution ?? "") + " " + article.summary
        let role = Self.inferRole(from: directive)
        if role == .unknown { return .fresh }

        let recentNotes = fetchRecentNotes(in: context, limit: 30)
        guard recentNotes.count >= 10 else { return .fresh }  // Too little signal

        let matchCount = recentNotes.filter { Self.matches(role: role, note: $0) }.count
        let matchRatio = Double(matchCount) / Double(recentNotes.count)

        // If < 30% of recent captures match the expected signals, flag drift
        if matchRatio < 0.3 {
            return .drifted(role: role, score: 1.0 - matchRatio)
        }

        return .fresh
    }

    /// User tapped Dismiss on the banner — hide for 14 days.
    func dismissBanner() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastBannerDismissedDate)
    }

    // MARK: - Role Inference

    /// Very simple keyword classifier — fast, predictable, no API call.
    /// Good enough as a first pass; can be replaced with an LLM call in v2.
    static func inferRole(from text: String) -> InferredRole {
        let lower = text.lowercased()

        let founderKeywords = ["founder", "ceo", "startup", "ship", "shipping", "build product", "pitch", "runway", "investors"]
        let coachKeywords = ["coach", "coaching", "client", "session", "clients", "therap", "mentor"]
        let interpreterKeywords = ["dream", "interpret", "jung", "archetype", "symbol", "unconscious"]
        let researcherKeywords = ["research", "phd", "thesis", "academic", "literature", "scholar", "paper"]
        let journalerKeywords = ["journal", "reflect", "gratitude", "feeling", "mood"]

        // Return the category with the most keyword hits
        let scores: [(InferredRole, Int)] = [
            (.founder, founderKeywords.filter { lower.contains($0) }.count),
            (.coach, coachKeywords.filter { lower.contains($0) }.count),
            (.interpreter, interpreterKeywords.filter { lower.contains($0) }.count),
            (.researcher, researcherKeywords.filter { lower.contains($0) }.count),
            (.journaler, journalerKeywords.filter { lower.contains($0) }.count),
        ]
        let top = scores.max(by: { $0.1 < $1.1 })
        guard let top, top.1 > 0 else { return .unknown }
        return top.0
    }

    // MARK: - Per-Role Match Signals

    /// Does this note look like something the given role would typically capture?
    /// Local-only check — uses fields already populated by the extraction pipeline.
    private static func matches(role: InferredRole, note: Note) -> Bool {
        switch role {
        case .founder:
            // Projects, decisions, actions, commitments
            return note.projectId != nil
                || note.intent == .decision
                || note.intent == .action
                || note.inferredProjectName?.isEmpty == false
        case .coach:
            // People mentions, commitments
            return !note.mentionedPeople.isEmpty || note.intent == .reminder
        case .interpreter:
            // Emotional tone, topics (dream content tends to have tone)
            return note.emotionalTone?.isEmpty == false
                || note.topics.contains { $0.lowercased().contains("dream") || $0.lowercased().contains("symbol") }
        case .researcher:
            // Multiple topics, ideas
            return note.topics.count >= 2 || note.intent == .idea
        case .journaler:
            // Emotional tone captured — reflective practice
            return note.emotionalTone?.isEmpty == false
        case .unknown:
            return true  // No expectations
        }
    }

    // MARK: - Helpers

    @MainActor
    private func fetchRecentNotes(in context: ModelContext, limit: Int) -> [Note] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.createdAt >= cutoff && $0.sourceTypeRaw == "voice" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
