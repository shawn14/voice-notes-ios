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
    case notes = "Notes"
    case calendar = "Calendar"
    case categories = "Categories"

    var id: String { rawValue }
}

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
                Text("\(calendar.component(.day, from: day))")
                    .font(EEONType.body)
                    .foregroundStyle(
                        isSelected ? Color.white
                        : (isToday ? Color.eeonAccent : Color.eeonTextPrimary)
                    )
                Circle()
                    .fill(count > 0
                          ? (isSelected ? Color.white : Color.eeonAccent)
                          : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: EEONLayout.minTarget)
            .background(isSelected ? Color.eeonAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: EEONLayout.chipRadius))
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !isSelected)
        .opacity(count == 0 ? 0.4 : 1)
    }

    private func shiftMonth(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
            withAnimation(.easeInOut(duration: 0.15)) { visibleMonth = next }
        }
    }
}

// MARK: - Categories lens

/// Categories as a full-width list, not a cramped horizontal rail. Names get
/// the whole row, so nothing truncates — the reason "Product De…" happened.
struct CategoriesLensView: View {
    let categories: [(String, Int)]
    @Binding var selectedCategory: String?

    var body: some View {
        VStack(spacing: EEONLayout.tight) {
            ForEach(categories, id: \.0) { name, count in
                categoryRow(name: name, count: count)
            }
        }
        .padding(.vertical, EEONLayout.tight)
    }

    private func categoryRow(name: String, count: Int) -> some View {
        let isSelected = selectedCategory == name
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = isSelected ? nil : name
            }
        } label: {
            HStack(spacing: EEONLayout.snug) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.eeonAccent : Color.eeonAccent.opacity(0.25))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(EEONType.badge)
                            .foregroundStyle(isSelected ? Color.white : Color.eeonAccent)
                    )

                Text(name)
                    .font(EEONType.body)
                    .foregroundStyle(.eeonTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: EEONLayout.tight)

                Text("\(count)")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(EEONType.meta)
                        .foregroundStyle(Color.eeonAccent)
                }
            }
            .padding(.horizontal, EEONLayout.snug)
            .frame(minHeight: EEONLayout.minTarget)
            .background(isSelected ? Color.eeonAccent.opacity(0.12) : Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: EEONLayout.chipRadius))
        }
        .buttonStyle(.plain)
    }
}
