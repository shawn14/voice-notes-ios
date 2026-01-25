//
//  KanbanItem.swift
//  voice notes
//
//  Unified Kanban item that can hold any extracted signal
//

import Foundation
import SwiftData
import SwiftUI

enum KanbanColumn: String, Codable, CaseIterable {
    case thinking = "Thinking"
    case decided = "Decided"
    case doing = "Doing"
    case waiting = "Waiting"
    case done = "Done"

    var icon: String {
        switch self {
        case .thinking: return "lightbulb"
        case .decided: return "checkmark.seal"
        case .doing: return "figure.run"
        case .waiting: return "hourglass"
        case .done: return "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .thinking: return .purple
        case .decided: return .green
        case .doing: return .blue
        case .waiting: return .orange
        case .done: return .gray
        }
    }
}

enum KanbanItemType: String, Codable {
    case idea = "Idea"
    case decision = "Decision"
    case action = "Action"
    case commitment = "Commitment"
    case note = "Note"
}

@Model
final class KanbanItem {
    var id: UUID = UUID()
    var content: String = ""
    var column: String = "Thinking"  // KanbanColumn raw value
    var itemType: String = "Note"    // KanbanItemType raw value
    var reason: String = ""          // Why it's in this column
    var sortOrder: Int = 0           // For manual reordering
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceNoteId: UUID?
    var projectId: UUID?  // Links to Project

    // Optional metadata
    var owner: String?
    var deadline: String?
    var affects: String?

    init(
        content: String,
        column: KanbanColumn = .thinking,
        itemType: KanbanItemType = .note,
        reason: String = "",
        sourceNoteId: UUID? = nil,
        projectId: UUID? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.column = column.rawValue
        self.itemType = itemType.rawValue
        self.reason = reason
        self.sortOrder = 0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceNoteId = sourceNoteId
        self.projectId = projectId
    }

    var kanbanColumn: KanbanColumn {
        get { KanbanColumn(rawValue: column) ?? .thinking }
        set {
            column = newValue.rawValue
            updatedAt = Date()
        }
    }

    var kanbanItemType: KanbanItemType {
        get { KanbanItemType(rawValue: itemType) ?? .note }
        set { itemType = newValue.rawValue }
    }

    // MARK: - Health Computed Properties

    /// Days since last update
    var daysSinceUpdate: Int {
        Calendar.current.dateComponents([.day], from: updatedAt, to: Date()).day ?? 0
    }

    /// Item is stale if not in Done and hasn't been updated in 7+ days
    var isStale: Bool {
        kanbanColumn != .done && daysSinceUpdate >= 7
    }

    /// Staleness description for display
    var stalenessLabel: String? {
        guard daysSinceUpdate > 0 else { return nil }
        return "\(daysSinceUpdate)d"
    }
}
