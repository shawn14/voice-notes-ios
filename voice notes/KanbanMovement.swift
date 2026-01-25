//
//  KanbanMovement.swift
//  voice notes
//
//  Tracks column changes for movement history and momentum calculation
//

import Foundation
import SwiftData

@Model
final class KanbanMovement {
    var id: UUID = UUID()
    var itemId: UUID = UUID()     // References KanbanItem.id
    var fromColumn: String = "Thinking"
    var toColumn: String = "Thinking"
    var movedAt: Date = Date()

    init(itemId: UUID, fromColumn: KanbanColumn, toColumn: KanbanColumn) {
        self.id = UUID()
        self.itemId = itemId
        self.fromColumn = fromColumn.rawValue
        self.toColumn = toColumn.rawValue
        self.movedAt = Date()
    }

    var fromKanbanColumn: KanbanColumn {
        KanbanColumn(rawValue: fromColumn) ?? .thinking
    }

    var toKanbanColumn: KanbanColumn {
        KanbanColumn(rawValue: toColumn) ?? .thinking
    }

    /// Check if this movement was a "forward" progression
    var isForwardMovement: Bool {
        let order: [KanbanColumn] = [.thinking, .decided, .doing, .waiting, .done]
        guard let fromIndex = order.firstIndex(of: fromKanbanColumn),
              let toIndex = order.firstIndex(of: toKanbanColumn) else {
            return false
        }
        return toIndex > fromIndex
    }

    /// Check if this movement completed an item
    var isCompletion: Bool {
        toKanbanColumn == .done
    }
}
