//
//  MoodTimelineHelpers.swift
//  voice notes
//

import SwiftUI

enum MoodTimelineHelpers {
    /// Map an emotionalTone string (positive / negative / neutral / mixed)
    /// to a tint color. Unknown tones return clear (no tint).
    static func moodColor(for tone: String?) -> Color {
        switch tone?.lowercased() {
        case "positive": return Color.green
        case "negative": return Color.red
        case "neutral":  return Color.gray
        case "mixed":    return Color.orange
        default:         return Color.clear
        }
    }

    /// Returns one mood color per day for the last 7 days, oldest → newest.
    /// Uses the dominant tone of the day's notes. Empty days return clear.
    static func moodSparkline(notes: [Note], today: Date = Date()) -> [Color] {
        let calendar = Calendar.current
        var days: [Color] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                days.append(.clear); continue
            }
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let dayNotes = notes.filter { $0.createdAt >= start && $0.createdAt < end }
            if dayNotes.isEmpty {
                days.append(.clear)
            } else {
                let dominant = Dictionary(grouping: dayNotes, by: { ($0.emotionalTone ?? "neutral").lowercased() })
                    .max { $0.value.count < $1.value.count }?.key
                days.append(moodColor(for: dominant))
            }
        }
        return days
    }
}

#if DEBUG
@MainActor private let _moodTimelineChecks: Void = {
    assert(MoodTimelineHelpers.moodColor(for: "positive") == .green)
    assert(MoodTimelineHelpers.moodColor(for: "POSITIVE") == .green, "Case-insensitive")
    assert(MoodTimelineHelpers.moodColor(for: nil) == .clear)
    assert(MoodTimelineHelpers.moodColor(for: "garbage") == .clear)

    let empty = MoodTimelineHelpers.moodSparkline(notes: [])
    assert(empty.count == 7, "Sparkline always has 7 days")
    assert(empty.allSatisfy { $0 == .clear }, "Empty notes → all clear")
}()
#endif
