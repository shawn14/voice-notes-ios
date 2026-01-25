//
//  DecisionLogView.swift
//  voice notes
//
//  Chronological, searchable history of decisions and movements
//

import SwiftUI
import SwiftData

struct DecisionLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KanbanItem.updatedAt, order: .reverse) private var allItems: [KanbanItem]
    @Query(sort: \KanbanMovement.movedAt, order: .reverse) private var allMovements: [KanbanMovement]

    @State private var searchText = ""
    @State private var selectedFilter: LogFilter = .all

    enum LogFilter: String, CaseIterable {
        case all = "All"
        case decisions = "Decisions"
        case actions = "Actions"
        case movements = "Movements"
    }

    private var filteredItems: [KanbanItem] {
        var items = allItems

        // Filter by type
        switch selectedFilter {
        case .decisions:
            items = items.filter { $0.kanbanItemType == .decision }
        case .actions:
            items = items.filter { $0.kanbanItemType == .action }
        case .all, .movements:
            break
        }

        // Search filter
        if !searchText.isEmpty {
            items = items.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.reason.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    private var groupedByDate: [(date: Date, items: [LogEntry])] {
        var entries: [LogEntry] = []

        // Add items
        if selectedFilter != .movements {
            for item in filteredItems {
                entries.append(.item(item))
            }
        }

        // Add movements
        if selectedFilter == .all || selectedFilter == .movements {
            for movement in allMovements {
                if let item = allItems.first(where: { $0.id == movement.itemId }) {
                    if searchText.isEmpty || item.content.localizedCaseInsensitiveContains(searchText) {
                        entries.append(.movement(movement, item))
                    }
                }
            }
        }

        // Sort by date (most recent first)
        entries.sort { $0.date > $1.date }

        // Group by day
        let calendar = Calendar.current
        var grouped: [Date: [LogEntry]] = [:]

        for entry in entries {
            let dayStart = calendar.startOfDay(for: entry.date)
            grouped[dayStart, default: []].append(entry)
        }

        return grouped
            .map { (date: $0.key, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            ForEach(groupedByDate, id: \.date) { group in
                Section {
                    ForEach(group.items) { entry in
                        LogEntryRow(entry: entry)
                    }
                } header: {
                    Text(formatDate(group.date))
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search decisions and actions")
        .navigationTitle("Decision Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(LogFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Log Entry

enum LogEntry: Identifiable {
    case item(KanbanItem)
    case movement(KanbanMovement, KanbanItem)

    var id: String {
        switch self {
        case .item(let item):
            return "item-\(item.id)"
        case .movement(let movement, _):
            return "movement-\(movement.id)"
        }
    }

    var date: Date {
        switch self {
        case .item(let item):
            return item.updatedAt
        case .movement(let movement, _):
            return movement.movedAt
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        switch entry {
        case .item(let item):
            ItemLogRow(item: item)
        case .movement(let movement, let item):
            MovementLogRow(movement: movement, item: item)
        }
    }
}

struct ItemLogRow: View {
    let item: KanbanItem

    var typeColor: Color {
        switch item.kanbanItemType {
        case .decision: return .green
        case .action: return .blue
        case .commitment: return .blue
        case .idea: return .orange
        case .note: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.kanbanItemType.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .cornerRadius(4)

                Text(item.kanbanColumn.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(item.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(item.content)
                .font(.subheadline)

            if !item.reason.isEmpty {
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

struct MovementLogRow: View {
    let movement: KanbanMovement
    let item: KanbanItem

    var body: some View {
        HStack(spacing: 12) {
            // Movement arrow
            VStack(spacing: 2) {
                Image(systemName: movement.fromKanbanColumn.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: movement.toKanbanColumn.icon)
                    .font(.caption2)
                    .foregroundStyle(columnColor(movement.toKanbanColumn))
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Moved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(movement.fromKanbanColumn.rawValue)
                        .font(.caption.weight(.medium))
                    Text("→")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(movement.toKanbanColumn.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(columnColor(movement.toKanbanColumn))

                    Spacer()

                    Text(formatTime(movement.movedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private func columnColor(_ column: KanbanColumn) -> Color {
        switch column {
        case .thinking: return .blue
        case .decided: return .green
        case .doing: return .blue
        case .waiting: return .orange
        case .done: return .gray
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DecisionLogView()
    }
    .modelContainer(for: [KanbanItem.self, KanbanMovement.self], inMemory: true)
}
