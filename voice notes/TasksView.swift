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

    /// Inline on the main screen (feed dropdown → Tasks): no NavigationStack,
    /// no toolbar, no inner ScrollView — home already scrolls. Default is the
    /// standalone sheet.
    var embedded: Bool = false

    @State private var showingCompleted = false
    @State private var showingAddTask = false
    @State private var showingCompleteVisibleConfirm = false
    @State private var newTaskText = ""
    @State private var navigateToNote: Note?
    @State private var editingAction: ExtractedAction?
    @State private var editTaskText = ""
    @State private var sharePayload: EEONSharePayload?

    // MARK: - Grouping

    /// Due date if the extractor caught one in speech ("by Friday"), else
    /// the day the note was captured.
    private func day(for action: ExtractedAction) -> Date {
        EventKitSyncService.parseDate(from: action.deadline) ?? action.createdAt
    }

    private var visibleActions: [ExtractedAction] {
        actions.filter { showingCompleted ? true : !$0.isCompleted }
    }

    private var hasOpenVisibleActions: Bool {
        visibleActions.contains { !$0.isCompleted }
    }

    private var hasCompletedVisibleActions: Bool {
        visibleActions.contains { $0.isCompleted }
    }

    private var visibleTasksShareText: String {
        guard !visibleActions.isEmpty else { return "EEON Tasks" }

        var lines: [String] = ["EEON Tasks"]
        for (day, dayActions) in grouped {
            lines.append("")
            lines.append(day)
            for action in dayActions {
                lines.append(taskExportLine(for: action))
            }
        }
        return lines.joined(separator: "\n")
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
        if embedded {
            embeddedBody
        } else {
            standaloneBody
        }
    }

    /// Rows only. Rows link to their source note through the enclosing
    /// NavigationStack (AIHomeView's), the same way feed cards do.
    private var embeddedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visibleActions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.0) { day, dayActions in
                        dayHeader(day, count: dayActions.count)
                        ForEach(dayActions) { action in
                            taskSwipeRow(action)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    showingAddTask = true
                } label: {
                    Label("Add task", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.eeonAccent)
                        .frame(minHeight: EEONLayout.minTarget)
                }

                if !visibleActions.isEmpty {
                    ShareLink(item: visibleTasksShareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.eeonAccent)
                            .frame(minHeight: EEONLayout.minTarget)
                    }
                }

                if hasOpenVisibleActions {
                    Button {
                        showingCompleteVisibleConfirm = true
                    } label: {
                        Label("Complete visible", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.eeonAccent)
                            .frame(minHeight: EEONLayout.minTarget)
                    }
                }

                Spacer()
                Button(showingCompleted ? "Hide completed" : "Show completed") {
                    withAnimation { showingCompleted.toggle() }
                }
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .frame(minHeight: EEONLayout.minTarget)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .alert("New task", isPresented: $showingAddTask) {
            TextField("What needs doing?", text: $newTaskText)
            Button("Cancel", role: .cancel) { newTaskText = "" }
            Button("Add") { addTask() }
        }
        .alert("Edit task", isPresented: Binding(
            get: { editingAction != nil },
            set: { if !$0 { editingAction = nil } }
        )) {
            TextField("Task", text: $editTaskText)
            Button("Cancel", role: .cancel) { editingAction = nil }
            Button("Save") { renameTask() }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityViewControllerRepresentable(activityItems: [payload.text])
        }
        .confirmationDialog("Complete Visible Tasks?", isPresented: $showingCompleteVisibleConfirm, titleVisibility: .visible) {
            Button("Complete Visible Tasks") {
                markVisibleComplete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the tasks currently shown as complete and updates any matching Apple Reminders.")
        }
    }

    private var standaloneBody: some View {
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
                                    taskSwipeRow(action)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Color.clear.frame(height: 80)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: visibleTasksShareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(visibleActions.isEmpty)
                    .accessibilityLabel("Share tasks")

                    Button {
                        showingCompleted.toggle()
                    } label: {
                        Image(systemName: showingCompleted
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingCompleted ? "Hide completed" : "Show completed")

                    Menu {
                        Button {
                            showingCompleteVisibleConfirm = true
                        } label: {
                            Label("Mark Visible Complete", systemImage: "checkmark.circle")
                        }
                        .disabled(!hasOpenVisibleActions)

                        Button {
                            reopenVisible()
                        } label: {
                            Label("Reopen Visible", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(!hasCompletedVisibleActions)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(visibleActions.isEmpty)
                    .accessibilityLabel("Task actions")
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
            .alert("Edit task", isPresented: Binding(
                get: { editingAction != nil },
                set: { if !$0 { editingAction = nil } }
            )) {
                TextField("Task", text: $editTaskText)
                Button("Cancel", role: .cancel) { editingAction = nil }
                Button("Save") { renameTask() }
            }
            .sheet(item: $sharePayload) { payload in
                ActivityViewControllerRepresentable(activityItems: [payload.text])
            }
            .confirmationDialog("Complete Visible Tasks?", isPresented: $showingCompleteVisibleConfirm, titleVisibility: .visible) {
                Button("Complete Visible Tasks") {
                    markVisibleComplete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This marks the tasks currently shown as complete and updates any matching Apple Reminders.")
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

    @ViewBuilder
    private func taskSwipeRow(_ action: ExtractedAction) -> some View {
        EEONSwipeActionsRow(
            actions: [
                .edit { beginEdit(action) },
                .share { sharePayload = EEONSharePayload(text: taskShareText(action)) },
                .delete { delete(action) }
            ],
            background: .eeonBackground
        ) {
            if let note = sourceNote(for: action) {
                NavigationLink(destination: NoteDetailView(note: note)) {
                    taskRowContent(action)
                }
                .buttonStyle(.plain)
            } else {
                taskRowContent(action)
            }
        }
    }

    private func taskRowContent(_ action: ExtractedAction) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

    private func taskExportLine(for action: ExtractedAction) -> String {
        let checkbox = action.isCompleted ? "x" : " "
        var detail: [String] = []
        if !action.owner.isEmpty && action.owner.lowercased() != "me" {
            detail.append(action.owner)
        }
        if action.deadline != "TBD" && !action.deadline.isEmpty {
            detail.append(action.deadline)
        }
        if action.priority != "Normal" && !action.priority.isEmpty {
            detail.append(action.priority)
        }
        let suffix = detail.isEmpty ? "" : " — " + detail.joined(separator: " · ")
        return "- [\(checkbox)] \(action.content)\(suffix)"
    }

    private func toggle(_ action: ExtractedAction) {
        withAnimation(.easeInOut(duration: 0.2)) {
            action.isCompleted.toggle()
            action.completedAt = action.isCompleted ? Date() : nil
            try? modelContext.save()
        }
        persistTaskChanges([action])
    }

    private func markVisibleComplete() {
        var changed: [ExtractedAction] = []
        withAnimation(.easeInOut(duration: 0.2)) {
            let now = Date()
            for action in visibleActions where !action.isCompleted {
                action.isCompleted = true
                action.completedAt = now
                changed.append(action)
            }
            try? modelContext.save()
        }
        persistTaskChanges(changed)
    }

    private func reopenVisible() {
        var changed: [ExtractedAction] = []
        withAnimation(.easeInOut(duration: 0.2)) {
            for action in visibleActions where action.isCompleted {
                action.isCompleted = false
                action.completedAt = nil
                changed.append(action)
            }
            try? modelContext.save()
        }
        persistTaskChanges(changed)
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

    private func taskShareText(_ action: ExtractedAction) -> String {
        var line = action.content
        if action.deadline != "TBD", !action.deadline.isEmpty { line += " (due \(action.deadline))" }
        return line + "\n\nShared from EEON"
    }

    private func beginEdit(_ action: ExtractedAction) {
        editTaskText = action.content
        editingAction = action
    }

    private func renameTask() {
        guard let action = editingAction else { return }
        editingAction = nil
        let trimmed = editTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        editTaskText = ""
        guard !trimmed.isEmpty, trimmed != action.content else { return }
        action.content = trimmed
        try? modelContext.save()
        if let note = sourceNote(for: action) {
            DocumentExportService.shared.export(note: note, context: modelContext)
        }
        Task { await EventKitSyncService.shared.updateTitle(for: action) }
    }

    private func delete(_ action: ExtractedAction) {
        let actionID = action.id
        let note = sourceNote(for: action)
        withAnimation(.easeInOut(duration: 0.2)) {
            modelContext.delete(action)
            try? modelContext.save()
        }
        if let note {
            DocumentExportService.shared.export(note: note, context: modelContext)
        }
        Task {
            await EventKitSyncService.shared.deleteReminder(forActionID: actionID)
        }
    }

    private func persistTaskChanges(_ changed: [ExtractedAction]) {
        guard !changed.isEmpty else { return }

        var exportedNoteIds = Set<UUID>()
        for action in changed {
            if let note = sourceNote(for: action), exportedNoteIds.insert(note.id).inserted {
                DocumentExportService.shared.export(note: note, context: modelContext)
            }
        }

        Task {
            for action in changed {
                await EventKitSyncService.shared.updateCompletion(for: action)
            }
        }
    }
}
