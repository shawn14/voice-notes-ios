//
//  DailyBrief.swift
//  voice notes
//
//  Tier 3: Daily AI-generated brief (one AI call per day)
//  Immutable for the day, stored in SwiftData
//

import Foundation
import SwiftData

// MARK: - Daily Brief Model

@Model
final class DailyBrief {
    var id: UUID = UUID()
    var briefDate: Date = Date()  // Start of day, normalized
    var generatedAt: Date = Date()

    // AI-generated content
    var whatMattersToday: String = ""

    // JSON-encoded arrays (SwiftData doesn't support arrays of custom types directly)
    var changesData: Data = Data()
    var driftingItemsData: Data = Data()
    var suggestedActionsData: Data = Data()
    var highlightsData: Data = Data()
    var warningsData: Data = Data()

    // Snapshot metrics
    var openItemCount: Int = 0
    var stalledItemCount: Int = 0
    var momentumDirection: String = "flat"
    var activeProjectCount: Int = 0
    var notesYesterday: Int = 0
    var notesThisWeek: Int = 0

    init(briefDate: Date = Date()) {
        self.id = UUID()
        self.briefDate = Calendar.current.startOfDay(for: briefDate)
        self.generatedAt = Date()
    }

    // MARK: - JSON Accessors

    var changes: [ChangeItem] {
        get {
            guard !changesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([ChangeItem].self, from: changesData)) ?? []
        }
        set {
            changesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var driftingItems: [DriftingItem] {
        get {
            guard !driftingItemsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([DriftingItem].self, from: driftingItemsData)) ?? []
        }
        set {
            driftingItemsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var suggestedActions: [SuggestedAction] {
        get {
            guard !suggestedActionsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([SuggestedAction].self, from: suggestedActionsData)) ?? []
        }
        set {
            suggestedActionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var highlights: [String] {
        get {
            guard !highlightsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: highlightsData)) ?? []
        }
        set {
            highlightsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var warnings: [DailyWarning] {
        get {
            guard !warningsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([DailyWarning].self, from: warningsData)) ?? []
        }
        set {
            warningsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Computed Properties

    var momentum: MomentumDirection {
        MomentumDirection(rawValue: momentumDirection) ?? .flat
    }

    var isFromToday: Bool {
        Calendar.current.isDateInToday(briefDate)
    }

    var freshnessLabel: String {
        let hours = Int(Date().timeIntervalSince(generatedAt) / 3600)
        if hours < 1 {
            return "Generated just now"
        } else if hours < 2 {
            return "Generated 1 hour ago"
        } else if hours < 24 {
            return "Generated \(hours) hours ago"
        } else {
            return "Generated yesterday"
        }
    }
}

// MARK: - Supporting Types

struct ChangeItem: Codable, Identifiable {
    var id: UUID = UUID()
    let content: String
    let changeType: ChangeType
    let projectName: String?

    enum ChangeType: String, Codable {
        case newNote
        case decisionMade
        case actionCompleted
        case itemMoved
        case projectUpdate
    }

    var icon: String {
        switch changeType {
        case .newNote: return "note.text"
        case .decisionMade: return "checkmark.seal"
        case .actionCompleted: return "checkmark.circle.fill"
        case .itemMoved: return "arrow.right"
        case .projectUpdate: return "folder"
        }
    }
}

struct DriftingItem: Codable, Identifiable {
    var id: UUID = UUID()
    let content: String
    let daysSinceActivity: Int
    let projectName: String?
    let itemType: String

    var urgencyLabel: String {
        if daysSinceActivity >= 14 {
            return "Critical"
        } else if daysSinceActivity >= 7 {
            return "Needs attention"
        } else {
            return "Slowing down"
        }
    }
}

struct SuggestedAction: Codable, Identifiable {
    var id: UUID = UUID()
    let content: String
    let reason: String
    let projectName: String?
    let priority: Priority

    enum Priority: String, Codable {
        case high
        case medium
        case low
    }

    var icon: String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "arrow.right.circle.fill"
        case .low: return "circle"
        }
    }
}

struct DailyWarning: Codable, Identifiable {
    var id: UUID = UUID()
    let type: WarningType
    let content: String
    let daysSinceIssue: Int

    enum WarningType: String, Codable {
        case stalled
        case overdue
        case commitment
    }

    var icon: String {
        switch type {
        case .stalled: return "pause.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .commitment: return "person.badge.clock"
        }
    }

    var color: String {
        switch type {
        case .stalled: return "orange"
        case .overdue: return "red"
        case .commitment: return "purple"
        }
    }
}

// MARK: - Daily Brief AI Response

/// Response structure for AI-generated daily brief
struct DailyBriefResponse: Codable {
    let summary: String
    let highlights: [String]
    let priorities: [PriorityItem]
    let warnings: [WarningItem]

    struct PriorityItem: Codable {
        let content: String
        let reason: String
        let projectName: String?
    }

    struct WarningItem: Codable {
        let type: String  // stalled, overdue, commitment
        let content: String
        let daysSinceIssue: Int
    }
}
