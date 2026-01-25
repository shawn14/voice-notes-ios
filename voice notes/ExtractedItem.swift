//
//  ExtractedItem.swift
//  voice notes
//

import Foundation
import SwiftData

// MARK: - Decision Status
enum DecisionStatus: String, Codable {
    case active = "Active"
    case pending = "Pending"
    case superseded = "Superseded"
    case reversed = "Reversed"
}

// MARK: - Action Priority
enum ActionPriority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case high = "High"
    case normal = "Normal"
    case low = "Low"
}

@Model
final class ExtractedDecision {
    var id: UUID = UUID()
    var content: String = ""
    var affects: String = ""
    var confidence: String = "Medium"  // High, Medium, Low
    var status: String = "Active"  // Active, Pending, Superseded, Reversed
    var createdAt: Date = Date()
    var sourceNoteId: UUID?

    init(content: String, affects: String = "", confidence: String = "Medium", status: String = "Active", sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.affects = affects
        self.confidence = confidence
        self.status = status
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
    }

    var isActive: Bool {
        status == "Active" || status == "Pending"
    }
}

@Model
final class ExtractedAction {
    var id: UUID = UUID()
    var content: String = ""
    var owner: String = "Me"
    var deadline: String = "TBD"
    var isCompleted: Bool = false
    var isBlocked: Bool = false
    var priority: String = "Normal"  // Urgent, High, Normal, Low
    var createdAt: Date = Date()
    var sourceNoteId: UUID?

    init(content: String, owner: String = "Me", deadline: String = "TBD", priority: String = "Normal", sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.owner = owner
        self.deadline = deadline
        self.isCompleted = false
        self.isBlocked = false
        self.priority = priority
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
    }

    var requiresAttention: Bool {
        !isCompleted && (isBlocked || isOverdue || priority == "Urgent")
    }

    var isOverdue: Bool {
        // Simple heuristic: check if deadline contains "overdue" or past date patterns
        deadline.lowercased().contains("overdue") ||
        deadline.lowercased().contains("yesterday") ||
        deadline.lowercased().contains("last week")
    }

    var isDueSoon: Bool {
        deadline.lowercased().contains("today") ||
        deadline.lowercased().contains("tomorrow") ||
        deadline.lowercased().contains("this week")
    }
}

@Model
final class ExtractedCommitment {
    var id: UUID = UUID()
    var who: String = ""
    var what: String = ""
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var sourceNoteId: UUID?

    init(who: String, what: String, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.who = who
        self.what = what
        self.isCompleted = false
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
    }

    var isUserCommitment: Bool {
        who.lowercased() == "me" || who.lowercased() == "i" || who.lowercased().contains("myself")
    }
}

// MARK: - Unresolved Item (for ambiguous notes)
@Model
final class UnresolvedItem {
    var id: UUID = UUID()
    var content: String = ""
    var reason: String = ""  // "No decision", "No owner", "Ambiguous"
    var createdAt: Date = Date()
    var sourceNoteId: UUID?

    init(content: String, reason: String, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.reason = reason
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
    }
}
