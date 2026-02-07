//
//  SessionBrief.swift
//  voice notes
//
//  Tier 2: Session-level intelligence (local computation, no AI)
//  Cached in UserDefaults, refreshed on app foreground with 15-60 min TTL
//

import Foundation

// MARK: - Session Brief

struct SessionBrief: Codable {
    let generatedAt: Date
    let topActiveProjects: [ProjectSummary]
    let stalledItems: [StalledItemSummary]
    let attentionWarnings: [AttentionWarning]
    let quickStats: QuickStats

    // MARK: - Staleness

    /// Session brief is stale if older than 60 minutes (hard expire)
    var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > 60 * 60
    }

    /// Session brief is soft expired if older than 15 minutes
    var isSoftExpired: Bool {
        Date().timeIntervalSince(generatedAt) > 15 * 60
    }

    /// Human-readable freshness
    var freshnessLabel: String {
        let minutes = Int(Date().timeIntervalSince(generatedAt) / 60)
        if minutes < 1 {
            return "Updated just now"
        } else if minutes < 5 {
            return "Updated \(minutes)m ago"
        } else if minutes < 60 {
            return "Updated \(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "Updated \(hours)h ago"
        }
    }

    // MARK: - Persistence

    private static let cacheKey = "sessionBrief.cached"

    static func loadFromCache() -> SessionBrief? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionBrief.self, from: data)
    }

    func saveToCache() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}

// MARK: - Project Summary

struct ProjectSummary: Codable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let colorName: String
    let noteCount: Int
    let openActionCount: Int
    let lastActivityAt: Date?
    let daysSinceActivity: Int

    var activityLabel: String {
        if daysSinceActivity == 0 {
            return "Active today"
        } else if daysSinceActivity == 1 {
            return "Active yesterday"
        } else if daysSinceActivity < 7 {
            return "Active \(daysSinceActivity)d ago"
        } else {
            return "No activity in \(daysSinceActivity)d"
        }
    }
}

// MARK: - Stalled Item Summary

struct StalledItemSummary: Codable, Identifiable {
    let id: UUID
    let content: String
    let column: String
    let itemType: String
    let daysSinceUpdate: Int
    let projectName: String?
    let reason: String

    var urgencyLevel: UrgencyLevel {
        if daysSinceUpdate >= 14 {
            return .critical
        } else if daysSinceUpdate >= 7 {
            return .high
        } else {
            return .medium
        }
    }

    enum UrgencyLevel: String, Codable {
        case critical
        case high
        case medium
    }
}

// MARK: - Attention Warning

struct AttentionWarning: Codable, Identifiable {
    let id: UUID
    let type: WarningType
    let title: String
    let description: String
    let daysSinceIssue: Int
    let relatedItemId: UUID?

    enum WarningType: String, Codable {
        case stalled
        case commitment
        case decisionWithoutAction
        case overdue
    }

    var icon: String {
        switch type {
        case .stalled: return "pause.circle.fill"
        case .commitment: return "person.badge.clock"
        case .decisionWithoutAction: return "arrow.triangle.branch"
        case .overdue: return "exclamationmark.circle.fill"
        }
    }

    var color: String {
        switch type {
        case .stalled: return "orange"
        case .commitment: return "purple"
        case .decisionWithoutAction: return "yellow"
        case .overdue: return "red"
        }
    }
}

// MARK: - Quick Stats

struct QuickStats: Codable {
    let totalNotes: Int
    let notesToday: Int
    let notesThisWeek: Int
    let openActions: Int
    let openCommitments: Int
    let unresolvedCount: Int
    let activeProjectCount: Int
    let stalledItemCount: Int
    let atRiskCount: Int

    var hasAttentionItems: Bool {
        stalledItemCount > 0 || atRiskCount > 0 || openCommitments > 0
    }

    var attentionSummary: String {
        var parts: [String] = []
        if stalledItemCount > 0 {
            parts.append("\(stalledItemCount) stalled")
        }
        if atRiskCount > 0 {
            parts.append("\(atRiskCount) at risk")
        }
        if openCommitments > 0 {
            parts.append("\(openCommitments) open commitment\(openCommitments == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Session Brief Builder

struct SessionBriefBuilder {

    /// Build session brief from current data (all local computation, no AI)
    static func build(
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) -> SessionBrief {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now

        // Calculate dropped balls once and reuse (was being called 3 times before)
        let droppedBalls = HealthScoreService.detectDroppedBalls(items: items)

        // Build project summaries (top 3 most active)
        let activeProjects = projects.filter { !$0.isArchived }
        let projectSummaries = buildProjectSummaries(projects: activeProjects, notes: notes, items: items)
            .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
            .prefix(3)
            .map { $0 }

        // Build stalled items (reuse cached droppedBalls)
        let stalledItems = buildStalledItems(droppedBalls: droppedBalls, projects: projects)

        // Build attention warnings (reuse cached droppedBalls)
        let warnings = buildAttentionWarnings(droppedBalls: droppedBalls, commitments: commitments)

        // Build quick stats
        let notesToday = notes.filter { $0.createdAt >= startOfToday }.count
        let notesThisWeek = notes.filter { $0.createdAt >= startOfWeek }.count
        let openActions = actions.filter { !$0.isCompleted }.count
        let openCommitments = commitments.filter { !$0.isCompleted }.count

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

        let quickStats = QuickStats(
            totalNotes: notes.count,
            notesToday: notesToday,
            notesThisWeek: notesThisWeek,
            openActions: openActions,
            openCommitments: openCommitments,
            unresolvedCount: unresolved.count,
            activeProjectCount: activeProjects.count,
            stalledItemCount: stalledCount,
            atRiskCount: atRiskCount
        )

        return SessionBrief(
            generatedAt: Date(),
            topActiveProjects: Array(projectSummaries),
            stalledItems: stalledItems,
            attentionWarnings: warnings,
            quickStats: quickStats
        )
    }

    // MARK: - Private Builders

    private static func buildProjectSummaries(
        projects: [Project],
        notes: [Note],
        items: [KanbanItem]
    ) -> [ProjectSummary] {
        projects.map { project in
            let projectNotes = notes.filter { $0.projectId == project.id }
            let projectItems = items.filter { $0.projectId == project.id }
            let openActions = projectItems.filter {
                $0.kanbanItemType == .action && $0.kanbanColumn != .done
            }.count

            let lastActivity = projectNotes.map { $0.updatedAt }.max()
            let daysSince: Int
            if let last = lastActivity {
                daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            } else {
                daysSince = Int.max
            }

            return ProjectSummary(
                id: project.id,
                name: project.name,
                icon: project.icon,
                colorName: project.colorName,
                noteCount: projectNotes.count,
                openActionCount: openActions,
                lastActivityAt: lastActivity,
                daysSinceActivity: daysSince
            )
        }
    }

    private static func buildStalledItems(
        droppedBalls: [DroppedBall],
        projects: [Project]
    ) -> [StalledItemSummary] {
        // Build project lookup for O(1) access
        let projectLookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })

        return droppedBalls.map { ball in
            let projectName = ball.item.projectId.flatMap { projectLookup[$0] }

            return StalledItemSummary(
                id: ball.item.id,
                content: ball.item.content,
                column: ball.item.kanbanColumn.rawValue,
                itemType: ball.item.kanbanItemType.rawValue,
                daysSinceUpdate: ball.daysSinceIssue,
                projectName: projectName,
                reason: ball.description
            )
        }
    }

    private static func buildAttentionWarnings(
        droppedBalls: [DroppedBall],
        commitments: [ExtractedCommitment]
    ) -> [AttentionWarning] {
        var warnings: [AttentionWarning] = []

        for ball in droppedBalls.prefix(5) {
            let warningType: AttentionWarning.WarningType
            switch ball.reason {
            case .decisionWithoutAction:
                warningType = .decisionWithoutAction
            case .stuckInColumn:
                warningType = .stalled
            case .openCommitment:
                warningType = .commitment
            }

            warnings.append(AttentionWarning(
                id: UUID(),
                type: warningType,
                title: String(ball.item.content.prefix(50)),
                description: ball.description,
                daysSinceIssue: ball.daysSinceIssue,
                relatedItemId: ball.item.id
            ))
        }

        // Add open commitment warnings
        let openCommitments = commitments.filter { !$0.isCompleted }
        for commitment in openCommitments.prefix(3) {
            let days = Calendar.current.dateComponents([.day], from: commitment.createdAt, to: Date()).day ?? 0
            if days >= 5 {
                warnings.append(AttentionWarning(
                    id: UUID(),
                    type: .commitment,
                    title: commitment.what,
                    description: "Open commitment for \(days) days",
                    daysSinceIssue: days,
                    relatedItemId: nil
                ))
            }
        }

        return warnings
    }
}
