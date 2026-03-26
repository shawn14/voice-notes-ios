//
//  CompletedItemsView.swift
//  voice notes
//
//  Progress & completed items — momentum tracking + history log
//

import SwiftUI
import SwiftData

struct CompletedItemsView: View {
    @Query(filter: #Predicate<ExtractedAction> { $0.isCompleted },
           sort: \ExtractedAction.completedAt, order: .reverse)
    private var completedActions: [ExtractedAction]

    @Query(filter: #Predicate<ExtractedCommitment> { $0.isCompleted },
           sort: \ExtractedCommitment.completedAt, order: .reverse)
    private var completedCommitments: [ExtractedCommitment]

    @Query(filter: #Predicate<ExtractedAction> { !$0.isCompleted })
    private var openActions: [ExtractedAction]

    @Query(filter: #Predicate<ExtractedCommitment> { !$0.isCompleted })
    private var openCommitments: [ExtractedCommitment]

    @Query(sort: \DailyBrief.briefDate, order: .reverse)
    private var dailyBriefs: [DailyBrief]

    @Environment(\.dismiss) private var dismiss

    private var allCompletedItems: [(date: Date, type: String, content: String, owner: String?)] {
        var items: [(date: Date, type: String, content: String, owner: String?)] = []

        for action in completedActions {
            if let completedAt = action.completedAt {
                items.append((completedAt, "action", action.content, action.owner))
            }
        }

        for commitment in completedCommitments {
            if let completedAt = commitment.completedAt {
                items.append((completedAt, "commitment", commitment.what, commitment.who))
            }
        }

        // Include completed suggested actions from daily briefs
        for brief in dailyBriefs {
            for action in brief.completedSuggestedActionItems {
                items.append((brief.briefDate, "daily_action", action.content, nil))
            }
        }

        return items.sorted { $0.date > $1.date }
    }

    private var groupedByDate: [(date: Date, items: [(type: String, content: String, owner: String?)])] {
        let calendar = Calendar.current
        var groups: [Date: [(type: String, content: String, owner: String?)]] = [:]

        for item in allCompletedItems {
            let dayStart = calendar.startOfDay(for: item.date)
            groups[dayStart, default: []].append((item.type, item.content, item.owner))
        }

        return groups.map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
    }

    // MARK: - Momentum Stats

    private var completedToday: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return allCompletedItems.filter { $0.date >= today }.count
    }

    private var completedThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return allCompletedItems.filter { $0.date >= startOfWeek }.count
    }

    private var streakDays: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // Check if today has completions, if not start from yesterday
        let todayItems = allCompletedItems.filter { calendar.isDate($0.date, inSameDayAs: checkDate) }
        if todayItems.isEmpty {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while true {
            let dayItems = allCompletedItems.filter { calendar.isDate($0.date, inSameDayAs: checkDate) }
            if dayItems.isEmpty { break }
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        return streak
    }

    private var totalOpen: Int {
        openActions.count + openCommitments.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if allCompletedItems.isEmpty && totalOpen == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Momentum header
                            momentumHeader
                                .padding(.horizontal)
                                .padding(.top, 8)

                            // Progress ring
                            if totalOpen > 0 || allCompletedItems.count > 0 {
                                progressSection
                                    .padding(.horizontal)
                            }

                            // Weekly activity
                            weeklyActivitySection
                                .padding(.horizontal)

                            // Completed items list
                            if !allCompletedItems.isEmpty {
                                completedListSection
                                    .padding(.horizontal)
                            }

                            Color.clear.frame(height: 20)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Momentum Header

    private var momentumHeader: some View {
        HStack(spacing: 0) {
            MomentumStat(
                value: "\(streakDays)",
                label: "Day Streak",
                icon: "flame.fill",
                color: streakDays > 0 ? .orange : .gray
            )
            MomentumStat(
                value: "\(completedToday)",
                label: "Today",
                icon: "checkmark.circle.fill",
                color: completedToday > 0 ? .green : .gray
            )
            MomentumStat(
                value: "\(completedThisWeek)",
                label: "This Week",
                icon: "calendar",
                color: completedThisWeek > 0 ? .blue : .gray
            )
            MomentumStat(
                value: "\(allCompletedItems.count)",
                label: "All Time",
                icon: "trophy.fill",
                color: allCompletedItems.count > 0 ? .yellow : .gray
            )
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        let total = allCompletedItems.count + totalOpen
        let completionRate = total > 0 ? Double(allCompletedItems.count) / Double(total) : 0

        return VStack(spacing: 12) {
            HStack {
                Text("Completion Rate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(completionRate * 100))%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(completionRate > 0.7 ? .green : completionRate > 0.4 ? .yellow : .orange)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5).opacity(0.4))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: completionRate > 0.7
                                    ? [.green, .green.opacity(0.7)]
                                    : completionRate > 0.4
                                        ? [.yellow, .orange]
                                        : [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * completionRate, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Label("\(allCompletedItems.count) done", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Label("\(totalOpen) open", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }

    // MARK: - Weekly Activity

    private var weeklyActivitySection: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build last 7 days
        let days: [(label: String, count: Int)] = (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let count = allCompletedItems.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            let formatter = DateFormatter()
            formatter.dateFormat = offset == 0 ? "'Today'" : "EEE"
            return (formatter.string(from: day), count)
        }

        let maxCount = max(days.map(\.count).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        Text("\(day.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(day.count > 0 ? .white : .gray)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                day.count > 0
                                    ? LinearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [Color(.systemGray5).opacity(0.4)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 48))

                        Text(day.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }

    // MARK: - Completed List

    private var completedListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            ForEach(groupedByDate.prefix(10), id: \.date) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(formatDateHeader(group.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)

                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)

                                HStack(spacing: 6) {
                                    Text(typeLabel(item.type))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(typeColor(item.type))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(typeColor(item.type).opacity(0.15))
                                        .cornerRadius(4)

                                    if let owner = item.owner, owner != "Me" && !owner.isEmpty {
                                        Text(owner)
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.green.opacity(0.5))
            }

            Text("No completed items yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Check off tasks in Today's Focus\nand they'll show up here.")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "action": return "Task"
        case "commitment": return "Commitment"
        case "daily_action": return "Daily Focus"
        default: return "Item"
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "action": return .blue
        case "commitment": return .purple
        case "daily_action": return .orange
        default: return .gray
        }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Momentum Stat

struct MomentumStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CompletedItemsView()
        .modelContainer(for: [ExtractedAction.self, ExtractedCommitment.self, DailyBrief.self])
}
