//
//  StatusCounters.swift
//  voice notes
//
//  Tier 1: Instant UI counters for real-time status updates
//  Updates immediately on note save, persists to UserDefaults
//

import Foundation
import SwiftData

@Observable
final class StatusCounters {
    static let shared = StatusCounters()

    // MARK: - Counters

    var openTodoCount: Int = 0
    var attentionCount: Int = 0
    var unresolvedCount: Int = 0
    var notesToday: Int = 0
    var notesThisWeek: Int = 0
    var activeProjectCount: Int = 0
    var stalledItemCount: Int = 0

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let openTodoCount = "statusCounters.openTodoCount"
        static let attentionCount = "statusCounters.attentionCount"
        static let unresolvedCount = "statusCounters.unresolvedCount"
        static let notesToday = "statusCounters.notesToday"
        static let notesThisWeek = "statusCounters.notesThisWeek"
        static let activeProjectCount = "statusCounters.activeProjectCount"
        static let stalledItemCount = "statusCounters.stalledItemCount"
        static let lastComputeDate = "statusCounters.lastComputeDate"
    }

    // MARK: - Init

    private init() {
        loadFromDefaults()
    }

    // MARK: - Recompute

    /// Recompute all counters from current data
    func recompute(
        notes: [Note],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        items: [KanbanItem],
        unresolved: [UnresolvedItem]
    ) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now

        // Count notes today and this week
        notesToday = notes.filter { $0.createdAt >= startOfToday }.count
        notesThisWeek = notes.filter { $0.createdAt >= startOfWeek }.count

        // Count open actions (not completed)
        openTodoCount = actions.filter { !$0.isCompleted }.count

        // Count open commitments (not completed)
        let openCommitments = commitments.filter { !$0.isCompleted }.count

        // Count unresolved items
        unresolvedCount = unresolved.count

        // Count items needing attention (stalled or at-risk from HealthScoreService)
        let activeItems = items.filter { $0.kanbanColumn != .done }
        var atRiskCount = 0
        var stalledCount = 0

        for item in activeItems {
            let status = HealthScoreService.healthStatus(for: item, allItems: items)
            switch status {
            case .atRisk: atRiskCount += 1
            case .stalled: stalledCount += 1
            case .strong: break
            }
        }

        attentionCount = atRiskCount + stalledCount + openCommitments
        stalledItemCount = stalledCount

        persistToDefaults()
    }

    /// Quick update after note save (incremental, not full recompute)
    func incrementNotesToday() {
        notesToday += 1
        notesThisWeek += 1
        persistToDefaults()
    }

    /// Update project count
    func updateActiveProjects(count: Int) {
        activeProjectCount = count
        persistToDefaults()
    }

    /// Mark session brief as needing refresh
    func markSessionStale() {
        // This is a hook for IntelligenceService to know it should refresh
        UserDefaults.standard.set(true, forKey: "sessionBrief.needsRefresh")
    }

    // MARK: - Persistence

    func loadFromDefaults() {
        let defaults = UserDefaults.standard

        // Check if we need to reset daily/weekly counts
        let calendar = Calendar.current
        let now = Date()
        let lastCompute = defaults.object(forKey: Keys.lastComputeDate) as? Date

        if let lastCompute = lastCompute {
            let lastDay = calendar.startOfDay(for: lastCompute)
            let today = calendar.startOfDay(for: now)

            // Reset daily count if new day
            if lastDay < today {
                defaults.set(0, forKey: Keys.notesToday)
            }

            // Reset weekly count if new week
            let lastWeek = calendar.component(.weekOfYear, from: lastCompute)
            let thisWeek = calendar.component(.weekOfYear, from: now)
            if lastWeek != thisWeek {
                defaults.set(0, forKey: Keys.notesThisWeek)
            }
        }

        openTodoCount = defaults.integer(forKey: Keys.openTodoCount)
        attentionCount = defaults.integer(forKey: Keys.attentionCount)
        unresolvedCount = defaults.integer(forKey: Keys.unresolvedCount)
        notesToday = defaults.integer(forKey: Keys.notesToday)
        notesThisWeek = defaults.integer(forKey: Keys.notesThisWeek)
        activeProjectCount = defaults.integer(forKey: Keys.activeProjectCount)
        stalledItemCount = defaults.integer(forKey: Keys.stalledItemCount)
    }

    func persistToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(openTodoCount, forKey: Keys.openTodoCount)
        defaults.set(attentionCount, forKey: Keys.attentionCount)
        defaults.set(unresolvedCount, forKey: Keys.unresolvedCount)
        defaults.set(notesToday, forKey: Keys.notesToday)
        defaults.set(notesThisWeek, forKey: Keys.notesThisWeek)
        defaults.set(activeProjectCount, forKey: Keys.activeProjectCount)
        defaults.set(stalledItemCount, forKey: Keys.stalledItemCount)
        defaults.set(Date(), forKey: Keys.lastComputeDate)
    }
}
