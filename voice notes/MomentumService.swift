//
//  MomentumService.swift
//  voice notes
//
//  Calculates momentum based on movement activity
//

import Foundation
import SwiftData

// MARK: - Momentum Direction

enum MomentumDirection: String {
    case up = "up"
    case down = "down"
    case flat = "flat"

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    var label: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .flat: return "→"
        }
    }

    var color: String {
        switch self {
        case .up: return "green"
        case .down: return "orange"
        case .flat: return "gray"
        }
    }
}

// MARK: - Momentum Stats

struct MomentumStats {
    let direction: MomentumDirection
    let movementsThisWeek: Int
    let movementsLastWeek: Int
    let completedThisWeek: Int
    let createdThisWeek: Int

    var ratio: Double {
        guard movementsLastWeek > 0 else {
            return movementsThisWeek > 0 ? 2.0 : 1.0
        }
        return Double(movementsThisWeek) / Double(movementsLastWeek)
    }
}

// MARK: - Momentum Service

struct MomentumService {

    /// Calculate momentum comparing this week vs last week
    static func calculateMomentum(
        movements: [KanbanMovement],
        items: [KanbanItem]
    ) -> MomentumStats {
        let calendar = Calendar.current
        let now = Date()

        // Get start of this week and last week
        let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!

        // Count movements this week
        let movementsThisWeek = movements.filter { movement in
            movement.movedAt >= thisWeekStart
        }.count

        // Count movements last week
        let movementsLastWeek = movements.filter { movement in
            movement.movedAt >= lastWeekStart && movement.movedAt < thisWeekStart
        }.count

        // Count completions this week
        let completedThisWeek = movements.filter { movement in
            movement.movedAt >= thisWeekStart && movement.isCompletion
        }.count

        // Count items created this week
        let createdThisWeek = items.filter { item in
            item.createdAt >= thisWeekStart
        }.count

        // Calculate direction
        let direction: MomentumDirection
        if movementsLastWeek == 0 {
            direction = movementsThisWeek > 0 ? .up : .flat
        } else {
            let ratio = Double(movementsThisWeek) / Double(movementsLastWeek)
            if ratio >= 1.2 {
                direction = .up
            } else if ratio <= 0.8 {
                direction = .down
            } else {
                direction = .flat
            }
        }

        return MomentumStats(
            direction: direction,
            movementsThisWeek: movementsThisWeek,
            movementsLastWeek: movementsLastWeek,
            completedThisWeek: completedThisWeek,
            createdThisWeek: createdThisWeek
        )
    }

    /// Get movements for a specific week
    static func movements(
        for weekStart: Date,
        from allMovements: [KanbanMovement]
    ) -> [KanbanMovement] {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        return allMovements.filter { movement in
            movement.movedAt >= weekStart && movement.movedAt < weekEnd
        }
    }

    /// Get weekly activity summary
    static func weeklySummary(
        movements: [KanbanMovement],
        items: [KanbanItem],
        weekStart: Date
    ) -> (forward: Int, backward: Int, completed: Int, created: Int) {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let weekMovements = movements.filter { $0.movedAt >= weekStart && $0.movedAt < weekEnd }
        let weekItems = items.filter { $0.createdAt >= weekStart && $0.createdAt < weekEnd }

        let forward = weekMovements.filter { $0.isForwardMovement }.count
        let backward = weekMovements.filter { !$0.isForwardMovement }.count
        let completed = weekMovements.filter { $0.isCompletion }.count

        return (forward, backward, completed, weekItems.count)
    }
}
