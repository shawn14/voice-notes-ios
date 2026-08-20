//
//  TasksView.swift
//  voice notes
//
//  Every next step, in one place. Action items extracted from recordings,
//  grouped by day, each carrying a link back to the note it came from —
//  you never lose the "why" behind the "what".
//
//  Data already exists: ExtractedAction.sourceNoteId is set by the
//  extraction pipeline. This is the surface that was missing.
//

import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ExtractedAction.createdAt, order: .reverse)
    private var actions: [ExtractedAction]
    @Query private var notes: [Note]

    @State private var showingCompleted = false
    @State private var showingAddTask = false
    @State private var newTaskText = ""
    @State private var navigateToNote: Note?

    // MARK: - Grouping

    /// Due date if the extractor caught one in speech ("by Friday"), else
    /// the day the note was captured.
    private func day(for action: ExtractedAction) -> Date {
        EventKitSyncService.parseDate(from: action.deadline) ?? action.createdAt
    }

    private var visibleActions: [ExtractedAction] {
        actions.filter { showingCompleted ? true : !$0.isCompleted }
    }

    private var grouped: [(String, [ExtractedAction])] {
        let calendar = Calendar.current
        let thisYear = DateFormatter()
        thisYear.dateFormat = "EEEE, MMM d"
        let otherYear = DateFormatter()
        otherYear.dateFormat = "EEEE, MMM d, yyyy"

        func label(for date: Date) -> String {
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            if calendar.isDateInTomorrow(date) { return "Tomorrow" }
            if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
                return thisYear.string(from: date)
            }
            return otherYear.string(from: date)
        }

        let sorted = visibleActions.sorted { day(for: $0) > day(for: $1) }
        var out: [(String, [ExtractedAction])] = []
        for action in sorted {
            let key = label(for: day(for: action))
            if var last = out.last, last.0 == key {
                last.1.append(action)
                out[out.count - 1] = last
            } else {
                out.append((key, [action]))
            }
        }
        return out
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eeonBackground.ignoresSafeArea()

                if visibleActions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(grouped, id: \.0) { day, dayActions in
                                dayHeader(day, count: dayActions.count)
                                ForEach(dayActions) { action in
                                    taskRow(action)
                                }
                            }
                            Color.clear.frame(height: 80)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCompleted.toggle()
                    } label: {
                        Image(systemName: showingCompleted
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingCompleted ? "Hide completed" : "Show completed")
                }
            }
            .safeAreaInset(edge: .bottom) {
                addTaskBar
            }
            .navigationDestination(item: $navigateToNote) { note in
                NoteDetailView(note: note)
            }
            .alert("New task", isPresented: $showingAddTask) {
                TextField("What needs doing?", text: $newTaskText)
                Button("Cancel", role: .cancel) { newTaskText = "" }
                Button("Add") { addTask() }
            }
        }
    }

    // MARK: - Pieces

    private func dayHeader(_ day: String, count: Int) -> some View {
        HStack {
            Text(day)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.eeonTextSecondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.eeonTextTertiary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func taskRow(_ action: ExtractedAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(action)
            } label: {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(action.isCompleted ? Color.eeonAccent : Color.eeonTextTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.content)
                    .font(.body)
                    .foregroundStyle(action.isCompleted ? .eeonTextTertiary : .eeonTextPrimary)
                    .strikethrough(action.isCompleted, color: .eeonTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let due = EventKitSyncService.parseDate(from: action.deadline) {
                        Label(due.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                    if action.priority == "Urgent" || action.priority == "High" {
                        Text(action.priority.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    if sourceNote(for: action) != nil {
                        Label("From a note", systemImage: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if let note = sourceNote(for: action) { navigateToNote = note }
        }
    }

    private var addTaskBar: some View {
        HStack {
            Spacer()
            Button {
                showingAddTask = true
            } label: {
                Label("Add Task", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.eeonAccent)
                    .clipShape(Capsule())
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.eeonTextTertiary)
            Text(showingCompleted ? "Nothing here yet" : "You're all clear")
                .font(.headline)
                .foregroundStyle(.eeonTextSecondary)
            Text("Action items EEON hears in your recordings show up here automatically.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Actions

    private func sourceNote(for action: ExtractedAction) -> Note? {
        guard let id = action.sourceNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    private func toggle(_ action: ExtractedAction) {
        withAnimation(.easeInOut(duration: 0.2)) {
            action.isCompleted.toggle()
            action.completedAt = action.isCompleted ? Date() : nil
            try? modelContext.save()
        }
    }

    private func addTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        newTaskText = ""
        guard !trimmed.isEmpty else { return }
        let action = ExtractedAction(content: trimmed)
        modelContext.insert(action)
        try? modelContext.save()
        Task { await EventKitSyncService.shared.sync(actions: [action]) }
    }
}
