//
//  DailyIntention.swift
//  voice notes
//
//  "Today's 3" — the primary daily-ritual pattern in EEON.
//  Each DailyIntention is one of (up to) three intentions a user sets for
//  the current day. Filtered by `dateKey` (YYYY-MM-DD) so SwiftData queries
//  are O(1) hash matches rather than date-range scans.
//
//  When the day rolls over, old intentions are kept (for review / history)
//  but no longer show on the home — a fresh empty state appears.
//

import Foundation
import SwiftData

@Model
final class DailyIntention {
    var id: UUID = UUID()
    var dateKey: String = ""       // "2026-04-18" local — used for today-filter queries
    var order: Int = 0             // 0, 1, 2 — display order
    var content: String = ""
    var createdAt: Date = Date()
    var isCompleted: Bool = false
    var completedAt: Date?

    init(dateKey: String, order: Int, content: String) {
        self.id = UUID()
        self.dateKey = dateKey
        self.order = order
        self.content = content
        self.createdAt = Date()
        self.isCompleted = false
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = .current
        return formatter.string(from: Date())
    }

    func toggleCompleted() {
        isCompleted.toggle()
        completedAt = isCompleted ? Date() : nil
    }
}
