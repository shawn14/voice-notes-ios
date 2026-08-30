//
//  HomeLenses.swift
//  voice notes
//
//  Calendar and Categories as mutually-exclusive LENSES on the same stream,
//  not as rows stacked on top of it (2026-08-20 redesign).
//
//  The earlier mistake was rendering a category rail, a date rail and the
//  feed's own date headers simultaneously — three navigations competing for
//  one job. The earlier over-correction was deleting date and category
//  browsing outright. This is the Day One resolution: one switcher, one lens
//  visible at a time, each feeding the same chronological feed below it.
//

import SwiftUI

enum HomeLens: String, CaseIterable, Identifiable {
    case notes = "Library"
    case calendar = "Calendar"

    var id: String { rawValue }
}

// The `categories` lens was removed 2026-08-21. It made you switch VIEWS to
// perform a filter, while the funnel button in the top bar already filtered by
// category from the feed itself — two routes to one outcome, and the indirect
// one was the prominent one. Category filtering now lives only in the filter
// sheet, reachable without leaving the notes.

// MARK: - Calendar lens

/// A real month grid: every day is a 44pt target, days that hold notes carry
/// a dot, and tapping one filters the feed below. Months are navigable, so
/// old notes are reachable — the 14-day strip could only ever see two weeks.
struct CalendarLensView: View {
    let notesByDayCount: [Date: Int]
    @Binding var selectedDay: Date?

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    /// Day cells for the visible month, padded with nils so the first of the
    /// month lands under the right weekday.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday
        else { return [] }
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        var out: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days {
            out.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return out
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(spacing: EEONLayout.snug) {
            header
            weekdayRow
            grid
        }
        .padding(.vertical, EEONLayout.snug)
    }

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .eeonTapTarget()
            }

            Spacer()

            Text(monthTitle)
                .font(EEONType.section)
                .foregroundStyle(.eeonTextPrimary)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .eeonTapTarget()
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: EEONLayout.minTarget)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let startOfDay = calendar.startOfDay(for: day)
        let count = notesByDayCount[startOfDay] ?? 0
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDay = isSelected ? nil : startOfDay
            }
        } label: {
            VStack(spacing: 3) {
                // Today is a filled circle with a white number, the way the
                // system calendar marks it.
                Text("\(calendar.component(.day, from: day))")
                    .font(EEONType.body)
                    .foregroundStyle(
                        (isSelected || isToday) ? Color.white
                        : count > 0 ? Color.eeonTextPrimary
                        : Color.eeonTextTertiary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(
                            isSelected ? Color.eeonAccent
                            : isToday ? Color.eeonTextPrimary
                            : Color.clear
                        )
                    )

                Circle()
                    .fill(count > 0
                          ? ((isSelected || isToday) ? Color.eeonAccent : Color.eeonAccent)
                          : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: EEONLayout.minTarget)
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !isSelected)
    }

    private func shiftMonth(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
            withAnimation(.easeInOut(duration: 0.15)) { visibleMonth = next }
        }
    }
}
