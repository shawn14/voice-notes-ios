//
//  HealthScoreService.swift
//  voice notes
//
//  Calculates health scores and detects dropped balls
//

import Foundation
import SwiftData

// MARK: - Health Status

enum HealthStatus: String {
    case strong = "Strong"
    case atRisk = "At Risk"
    case stalled = "Stalled"

    var color: String {
        switch self {
        case .strong: return "green"
        case .atRisk: return "orange"
        case .stalled: return "red"
        }
    }
}

// MARK: - Dropped Ball

struct DroppedBall: Identifiable {
    let id = UUID()
    let item: KanbanItem
    let reason: DroppedBallReason
    let daysSinceIssue: Int

    var description: String {
        switch reason {
        case .decisionWithoutAction:
            return "Decision made \(daysSinceIssue)d ago with no follow-up actions"
        case .stuckInColumn(let column, let threshold):
            return "In \(column.rawValue) for \(daysSinceIssue)d (threshold: \(threshold)d)"
        case .openCommitment:
            return "Open commitment for \(daysSinceIssue)d"
        }
    }
}

enum DroppedBallReason {
    case decisionWithoutAction
    case stuckInColumn(column: KanbanColumn, threshold: Int)
    case openCommitment
}

// MARK: - Health Score Service

struct HealthScoreService {

    /// Column thresholds for "stuck" detection
    static let stuckThresholds: [KanbanColumn: Int] = [
        .thinking: 7,
        .decided: 5,
        .doing: 10,
        .waiting: 5,
        .done: Int.max  // Never stale in Done
    ]

    // MARK: - Individual Item Health

    /// Calculate health score for a single item (0-100)
    static func healthScore(for item: KanbanItem, allItems: [KanbanItem]) -> Int {
        var score = 100

        // Content < 10 chars: -20
        if item.content.count < 10 {
            score -= 20
        }

        // No owner: -15
        if item.owner == nil || item.owner?.isEmpty == true {
            score -= 15
        }

        // Staleness penalties
        let days = item.daysSinceUpdate
        if item.kanbanColumn != .done {
            if days >= 14 {
                score -= 40
            } else if days >= 7 {
                score -= 20
            } else if days >= 3 {
                score -= 5
            }
        }

        // Decision without follow-up actions: -25
        if item.kanbanColumn == .decided && item.kanbanItemType == .decision {
            let hasRelatedActions = allItems.contains { otherItem in
                otherItem.kanbanItemType == .action &&
                otherItem.sourceNoteId == item.sourceNoteId &&
                otherItem.kanbanColumn != .done
            }
            if !hasRelatedActions && days >= 3 {
                score -= 25
            }
        }

        return max(0, score)
    }

    /// Get health status from score
    static func healthStatus(for score: Int) -> HealthStatus {
        if score >= 70 {
            return .strong
        } else if score >= 40 {
            return .atRisk
        } else {
            return .stalled
        }
    }

    /// Get health status for an item
    static func healthStatus(for item: KanbanItem, allItems: [KanbanItem]) -> HealthStatus {
        let score = healthScore(for: item, allItems: allItems)
        return healthStatus(for: score)
    }

    // MARK: - Aggregate Health

    /// Count items by health status
    static func healthCounts(for items: [KanbanItem]) -> (strong: Int, atRisk: Int, stalled: Int) {
        var strong = 0
        var atRisk = 0
        var stalled = 0

        let activeItems = items.filter { $0.kanbanColumn != .done }

        for item in activeItems {
            let status = healthStatus(for: item, allItems: items)
            switch status {
            case .strong: strong += 1
            case .atRisk: atRisk += 1
            case .stalled: stalled += 1
            }
        }

        return (strong, atRisk, stalled)
    }

    // MARK: - Dropped Ball Detection

    /// Detect all dropped balls
    static func detectDroppedBalls(items: [KanbanItem]) -> [DroppedBall] {
        var droppedBalls: [DroppedBall] = []

        let activeItems = items.filter { $0.kanbanColumn != .done }

        for item in activeItems {
            // 1. Decisions without actions (3+ days old)
            if item.kanbanColumn == .decided && item.kanbanItemType == .decision {
                let hasRelatedActions = items.contains { otherItem in
                    otherItem.kanbanItemType == .action &&
                    otherItem.sourceNoteId == item.sourceNoteId &&
                    otherItem.kanbanColumn != .done
                }
                if !hasRelatedActions && item.daysSinceUpdate >= 3 {
                    droppedBalls.append(DroppedBall(
                        item: item,
                        reason: .decisionWithoutAction,
                        daysSinceIssue: item.daysSinceUpdate
                    ))
                }
            }

            // 2. Stuck items (exceeded column threshold)
            let threshold = stuckThresholds[item.kanbanColumn] ?? 7
            if item.daysSinceUpdate >= threshold {
                droppedBalls.append(DroppedBall(
                    item: item,
                    reason: .stuckInColumn(column: item.kanbanColumn, threshold: threshold),
                    daysSinceIssue: item.daysSinceUpdate
                ))
            }

            // 3. Open commitments (7+ days for user commitments)
            if item.kanbanItemType == .commitment && item.daysSinceUpdate >= 7 {
                // Check if it's a user commitment (owner is "Me" or similar)
                let owner = item.owner?.lowercased() ?? "me"
                let isUserCommitment = owner == "me" || owner == "i" || owner.contains("myself")
                if isUserCommitment {
                    droppedBalls.append(DroppedBall(
                        item: item,
                        reason: .openCommitment,
                        daysSinceIssue: item.daysSinceUpdate
                    ))
                }
            }
        }

        // Remove duplicates (an item can only be one type of dropped ball)
        var seen = Set<UUID>()
        return droppedBalls.filter { ball in
            guard !seen.contains(ball.item.id) else { return false }
            seen.insert(ball.item.id)
            return true
        }
    }
}
