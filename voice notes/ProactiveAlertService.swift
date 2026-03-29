//
//  ProactiveAlertService.swift
//  voice notes
//
//  Scans extracted data for stale commitments, overdue actions,
//  decision decay, and recurring patterns — generates proactive alerts.
//

import Foundation
import SwiftData

// MARK: - Alert Types

enum ProactiveAlertType: String, Codable {
    case staleCommitment
    case decisionDecay
    case overdueAction
    case patternDetected
    case dailyBrief
}

// MARK: - Proactive Alert

struct ProactiveAlert: Identifiable {
    let id: UUID
    let type: ProactiveAlertType
    let title: String
    let body: String
    let relatedNoteId: UUID?
    let createdAt: Date

    init(type: ProactiveAlertType, title: String, body: String, relatedNoteId: UUID? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.body = body
        self.relatedNoteId = relatedNoteId
        self.createdAt = Date()
    }
}

// MARK: - Proactive Alert Service

@Observable
final class ProactiveAlertService {
    static let shared = ProactiveAlertService()

    /// Last time alerts were generated (throttle to once per 4 hours)
    private let lastScanKey = "proactiveAlerts_lastScanDate"

    private init() {}

    // MARK: - Public API

    /// Generate all proactive alerts by scanning extracted data.
    /// Call from background task or on app foreground.
    func generateAlerts(using modelContext: ModelContext) -> [ProactiveAlert] {
        var alerts: [ProactiveAlert] = []

        alerts.append(contentsOf: detectStaleCommitments(using: modelContext))
        alerts.append(contentsOf: detectDecisionDecay(using: modelContext))
        alerts.append(contentsOf: detectOverdueActions(using: modelContext))
        alerts.append(contentsOf: detectPatterns(using: modelContext))

        return alerts
    }

    /// Whether enough time has passed since the last scan (4-hour throttle)
    var shouldScan: Bool {
        guard let lastScan = UserDefaults.standard.object(forKey: lastScanKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastScan) > 4 * 60 * 60
    }

    /// Mark the current time as the last scan
    func recordScan() {
        UserDefaults.standard.set(Date(), forKey: lastScanKey)
    }

    // MARK: - Detection: Stale Commitments

    private func detectStaleCommitments(using modelContext: ModelContext) -> [ProactiveAlert] {
        let descriptor = FetchDescriptor<ExtractedCommitment>(
            predicate: #Predicate<ExtractedCommitment> { !$0.isCompleted }
        )
        guard let commitments = try? modelContext.fetch(descriptor) else { return [] }

        let now = Date()
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: now)!

        return commitments.compactMap { commitment in
            guard commitment.createdAt < threeDaysAgo else { return nil }

            let daysAgo = Calendar.current.dateComponents([.day], from: commitment.createdAt, to: now).day ?? 0
            let person = commitment.isUserCommitment ? "yourself" : commitment.who

            return ProactiveAlert(
                type: .staleCommitment,
                title: "Open commitment to \(person)",
                body: "You said you'd \(commitment.what) \(daysAgo) days ago",
                relatedNoteId: commitment.sourceNoteId
            )
        }
    }

    // MARK: - Detection: Decision Decay

    private func detectDecisionDecay(using modelContext: ModelContext) -> [ProactiveAlert] {
        let decisionDescriptor = FetchDescriptor<ExtractedDecision>()
        let actionDescriptor = FetchDescriptor<ExtractedAction>(
            predicate: #Predicate<ExtractedAction> { !$0.isCompleted }
        )

        guard let decisions = try? modelContext.fetch(decisionDescriptor),
              let actions = try? modelContext.fetch(actionDescriptor) else { return [] }

        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        // Build a set of action content keywords for loose topic matching
        let actionKeywords = Set(actions.flatMap { action in
            action.content.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 }
        })

        return decisions.compactMap { decision in
            guard decision.isActive,
                  decision.createdAt < sevenDaysAgo else { return nil }

            // Check if any action content loosely references the decision
            let decisionWords = decision.content.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 }

            let hasRelatedAction = decisionWords.contains { actionKeywords.contains($0) }
            guard !hasRelatedAction else { return nil }

            let daysAgo = Calendar.current.dateComponents([.day], from: decision.createdAt, to: now).day ?? 0
            let snippet = String(decision.content.prefix(60))

            return ProactiveAlert(
                type: .decisionDecay,
                title: "Decision needs follow-up",
                body: "You decided \"\(snippet)\" \(daysAgo) days ago but haven't acted on it",
                relatedNoteId: decision.sourceNoteId
            )
        }
    }

    // MARK: - Detection: Overdue Actions

    private func detectOverdueActions(using modelContext: ModelContext) -> [ProactiveAlert] {
        let descriptor = FetchDescriptor<ExtractedAction>(
            predicate: #Predicate<ExtractedAction> { !$0.isCompleted }
        )
        guard let actions = try? modelContext.fetch(descriptor) else { return [] }

        return actions.compactMap { action in
            // Check the deadline string for overdue/past-date signals
            let dl = action.deadline.lowercased()
            let isOverdue = dl.contains("overdue") ||
                            dl.contains("yesterday") ||
                            dl.contains("last week") ||
                            dl.contains("last month")

            // Also try to parse an actual date from the deadline
            let parsedOverdue: Bool = {
                let formatter = DateFormatter()
                for format in ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d, yyyy", "MMMM d, yyyy", "MM-dd-yyyy"] {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: action.deadline) {
                        return date < Date()
                    }
                }
                return false
            }()

            guard isOverdue || parsedOverdue else { return nil }

            return ProactiveAlert(
                type: .overdueAction,
                title: "Overdue action",
                body: "\(action.content) — was due \(action.deadline)",
                relatedNoteId: action.sourceNoteId
            )
        }
    }

    // MARK: - Detection: Recurring Patterns

    private func detectPatterns(using modelContext: ModelContext) -> [ProactiveAlert] {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.createdAt > fourteenDaysAgo }
        )
        guard let notes = try? modelContext.fetch(descriptor) else { return [] }

        // Count topic occurrences in the last 7 days
        var topicNoteCount: [String: Int] = [:]

        for note in notes where note.createdAt > sevenDaysAgo {
            for topic in note.topics {
                let normalized = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                topicNoteCount[normalized, default: 0] += 1
            }
        }

        return topicNoteCount.compactMap { topic, count in
            guard count >= 4 else { return nil }

            return ProactiveAlert(
                type: .patternDetected,
                title: "Recurring theme: \(topic.capitalized)",
                body: "You've mentioned \(topic) \(count) times this week",
                relatedNoteId: nil
            )
        }
    }
}
