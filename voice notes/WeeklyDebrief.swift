//
//  WeeklyDebrief.swift
//  voice notes
//
//  Stores AI-generated weekly summaries of progress
//

import Foundation
import SwiftData

@Model
final class WeeklyDebrief {
    var id: UUID = UUID()
    var weekStartDate: Date = Date()
    var generatedAt: Date = Date()
    var summary: String = ""
    var momentumScore: String = ""  // "up", "down", "flat"
    var highlightsData: Data = Data()  // JSON-encoded [String]
    var concernsData: Data = Data()    // JSON-encoded [String]

    init(weekStartDate: Date) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.generatedAt = Date()
    }

    var highlights: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: highlightsData)) ?? []
        }
        set {
            highlightsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var concerns: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: concernsData)) ?? []
        }
        set {
            concernsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Week identifier string for grouping (e.g., "2026-W04")
    var weekIdentifier: String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: weekStartDate)
        let year = calendar.component(.yearForWeekOfYear, from: weekStartDate)
        return String(format: "%d-W%02d", year, weekOfYear)
    }

    /// Human-readable date range
    var dateRangeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate

        return "\(formatter.string(from: weekStartDate)) - \(formatter.string(from: endDate))"
    }
}
