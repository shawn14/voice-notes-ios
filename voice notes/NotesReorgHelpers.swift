//
//  NotesReorgHelpers.swift
//  voice notes
//
//  Pure helpers shared by the notes-reorganization pack
//  (intent chips, loose ends, mood timeline, decision log).
//

import Foundation
import SwiftUI

enum NotesReorgHelpers {
    /// All intent types the user can filter by, excluding `.unknown`
    /// (used for chips that count classified notes).
    static let filterableIntents: [NoteIntent] = [
        .action, .decision, .idea, .update, .reminder
    ]

    /// Counts how many notes have each intent. Skips `.unknown`.
    static func intentCounts(notes: [Note]) -> [NoteIntent: Int] {
        var counts: [NoteIntent: Int] = [:]
        for intent in filterableIntents { counts[intent] = 0 }
        for note in notes {
            let intent = note.intent
            if filterableIntents.contains(intent) {
                counts[intent, default: 0] += 1
            }
        }
        return counts
    }

    /// Filters notes to those whose intent is in the selected set.
    /// If selected is empty, returns all notes (no filter).
    static func filterByIntents(notes: [Note], selected: Set<NoteIntent>) -> [Note] {
        guard !selected.isEmpty else { return notes }
        return notes.filter { selected.contains($0.intent) }
    }

    /// Returns the start-of-week date for a given date (Monday-based ISO weeks).
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Groups any items by week-of-year, returning [(weekStart, items)] sorted descending.
    static func groupByWeek<T>(items: [T], dateKey: (T) -> Date) -> [(Date, [T])] {
        let grouped = Dictionary(grouping: items, by: { weekStart(for: dateKey($0)) })
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }
}

#if DEBUG
// Sanity checks — run at module load in Debug to catch regressions.
@MainActor private let _notesReorgHelpersChecks: Void = {
    // intentCounts on empty input returns zero for every filterable intent.
    let empty = NotesReorgHelpers.intentCounts(notes: [])
    assert(empty.count == NotesReorgHelpers.filterableIntents.count)
    for intent in NotesReorgHelpers.filterableIntents {
        assert(empty[intent] == 0, "Empty notes should yield 0 count for \(intent)")
    }

    // filterByIntents with empty selection is a passthrough.
    let n = Note(title: "x", content: "y")
    let pass = NotesReorgHelpers.filterByIntents(notes: [n], selected: [])
    assert(pass.count == 1, "Empty selection should not filter")

    // weekStart is monotonic — same week input → same output.
    let d1 = Date()
    let d2 = d1.addingTimeInterval(60)
    assert(NotesReorgHelpers.weekStart(for: d1) == NotesReorgHelpers.weekStart(for: d2),
           "Two timestamps in the same minute should share a week start")
}()
#endif
