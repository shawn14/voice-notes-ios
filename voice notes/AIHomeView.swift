//
//  AIHomeView.swift
//  voice notes
//
//  EEON v2 Home Screen — clean, Letterly-inspired layout
//  Greeting > Daily Brief > Tabbed Note Feed > Bottom Bar (Write/Mic/Search)
//

import SwiftUI
import SwiftData
import AuthenticationServices
import WidgetKit
import UniformTypeIdentifiers
import AVFoundation

/// Identifiable wrapper that drives `.sheet(item:)` for the AnswerSheet.
/// Setting this to a non-nil value presents the sheet with the wrapped query.
fileprivate struct AnswerQuery: Identifiable {
    let id = UUID()
    let query: String
}

struct AIHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var tags: [Tag]
    @Query private var extractedActions: [ExtractedAction]
    @Binding var shouldStartRecording: Bool

    private var authService = AuthService.shared
    private var intelligenceService = IntelligenceService.shared
    private var backgroundCapture = BackgroundCaptureService.shared
    private var googleCalendarService = GoogleCalendarService.shared
    private let recordingRed = Color(red: 1.0, green: 0.23, blue: 0.27)

    init(shouldStartRecording: Binding<Bool>) {
        self._shouldStartRecording = shouldStartRecording
    }

    @State private var showingSettings = false
    /// Which list Home shows — and what the one record button records.
    @State private var homeMode: HomeMode = .notes
    @State private var pendingAnswerQuery: AnswerQuery?
    /// "Remind me…" heard in a recording — confirmed in ReminderConfirmSheet.
    @State private var pendingReminder: ReminderCommandParser.Command?
    @State private var showPaywall = false
    /// Set when iCloud uploads are persistently failing — drives syncFailureBanner.
    @State private var syncFailure: (since: Date, message: String)?
    @AppStorage("homeOnboardingChecklistDismissedAt") private var onboardingChecklistDismissedRaw: Double = 0
    @AppStorage(EventKitSyncService.enabledKey) private var remindersSyncEnabled = false
    @AppStorage(CalendarContextService.enabledKey) private var calendarContextEnabled = false

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    /// True while capturing an Order (an instruction for an agent) rather than
    /// a note. Set by the Order button before recording starts.
    @State private var capturingOrder = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Audio import state
    @State private var showingAudioImporter = false

    // Source picker
    @State private var showingSourcePicker = false

    // Type note
    @State private var showingTypeNote = false

    // Navigation state
    @State private var navigateToNote: Note?
    @State private var navigateTransformType: AITransformType?
    /// Swipe "Edit" on a note card: push the detail already in edit mode.
    @State private var editNote: Note?
    /// Swipe "Share" on a note card or action item.
    @State private var sharePayload: EEONSharePayload?

    @State private var showingFullRecorder = false
    @State private var showingAskSheet = false
    #if DEBUG
    @State private var didStartRecorderDemo = false
    @State private var didOpenAskDemo = false
    #endif
    private var visibleLibraryNotes: [Note] {
        libraryVisibleNotes(notes)
    }

    private var visibleExtractedActions: [ExtractedAction] {
        extractedActions.filter { !libraryIsSchemaSeedName($0.content) && !libraryIsSchemaSeedName($0.owner) }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            regularBody
        } else {
            compactBody
        }
    }

    /// Warns that notes are not reaching iCloud. Silent unless
    /// `CloudKitEventLog.exportFailure()` sees two consecutive genuine
    /// failures, so it cannot become background noise the user learns to
    /// ignore. States the consequence ("only on this iPhone") rather than the
    /// mechanism, because the consequence is what the user needs to act on.
    @ViewBuilder
    private var syncFailureBanner: some View {
        if let failure = syncFailure {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes aren't reaching iCloud")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                    Text("New notes since \(failure.since.formatted(date: .abbreviated, time: .shortened)) are only on this iPhone. Open Settings › iCloud & Sync.")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Adaptive bodies

    /// iPad / Mac Catalyst layout: sidebar-first split view.
    /// Sidebar shows a simple list of recent notes; the detail keeps the full
    /// capture surface (the existing iPhone experience) so every section is
    /// still reachable. This avoids restructuring any state or subview
    /// ownership — it's purely a layout branch.
    @ViewBuilder
    private var regularBody: some View {
        NavigationSplitView {
            RecentNotesSidebar(
                notes: libraryVisibleNotes(notes)
            )
            .navigationTitle("Library")
        } detail: {
            compactBody
        }
    }

    /// iPhone / compact layout — the original body, unchanged.
    @ViewBuilder
    private var compactBody: some View {
        NavigationStack {
            ZStack {
                Color.eeonBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Main scrollable content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // 1. Header: date · Ask · avatar
                            headerBar
                                .padding(.horizontal)

                            // Sync is broken and the user would otherwise never
                            // know. Home deliberately isn't a nag surface (the
                            // drift banner was removed for exactly that reason),
                            // but this is different in kind: it means notes are
                            // NOT backed up and would be lost with the phone.
                            // CloudKitEventLog.exportFailure() only fires after
                            // two consecutive real failures, so it stays quiet
                            // for transient hiccups.
                            syncFailureBanner
                                .padding(.horizontal)

                            if showSetupLine {
                                setupLine
                                    .padding(.horizontal)
                            }

                            // Free tier warning
                            if !UsageService.shared.isPro {
                                let remaining = UsageService.shared.freeNotesRemaining
                                if remaining <= 2 && remaining > 0 {
                                    freeNotesWarning(remaining: remaining)
                                        .padding(.horizontal)
                                }
                            }

                            // Option A (2026-09-10, Shawn): today's meetings as a
                            // strip, one quiet tasks line, then Notes | AI Prompts.
                            // No persona sections, knowledge, or briefs live here
                            // (see MEMORY.md kill list).
                            homeStack

                            // Spacer so content doesn't show behind bottom bar
                            Color.clear.frame(height: 20)
                        }
                        .padding(.top, 8)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        if isRecording && !showingFullRecorder {
                            recordingBar
                        }
                        bottomBar
                    }
                }

                // Recording no longer takes over the screen (2026-08-20).
                // Press to start, press again to stop — keep scrolling, leave
                // the app, lock the phone. The full recorder (waveform + live
                // transcript) is opt-in via the recording bar, because it is
                // the expensive part: it pins the screen awake and runs
                // continuous on-device speech recognition.
                if isRecording && showingFullRecorder {
                    HomeRecordingOverlay(
                        onStop: {
                            showingFullRecorder = false
                            stopRecording()
                        },
                        onCancel: {
                            showingFullRecorder = false
                            cancelRecording()
                        },
                        onMinimize: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingFullRecorder = false
                            }
                        },
                        audioRecorder: audioRecorder,
                        captureNoun: captureNoun
                    )
                }

                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay(isAIPrompt: capturingOrder)
                }
            }
            .navigationBarHidden(true)
            .background(DisableBackSwipe())
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                #if DEBUG
                // Screenshot automation (fastlane snap, -ShowReminderDemo):
                // present the "remind me…" confirmation for a fixed utterance.
                if ProcessInfo.processInfo.arguments.contains("-ShowReminderDemo"), pendingReminder == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        pendingReminder = ReminderCommandParser.parse("Remind me to send Lena the pricing deck on Friday at 5pm")
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-StartRecorderDemo"), !didStartRecorderDemo {
                    didStartRecorderDemo = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if !isRecording && !isTranscribing {
                            toggleRecording()
                        }
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-OpenAskDemo"), !didOpenAskDemo {
                    didOpenAskDemo = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showingAskSheet = true
                    }
                }
                #endif
            }
            .sheet(item: $pendingReminder) { command in
                ReminderConfirmSheet(command: command) { pendingReminder = nil }
            }
            .sheet(item: $pendingAnswerQuery) { item in
                AnswerSheet(initialQuery: item.query)
            }
            .sheet(isPresented: $showingAskSheet) {
                AnswerSheet(navigationTitle: "Ask EEON", showsDoneButton: true)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onDismiss: { showPaywall = false })
            }
            .sheet(isPresented: $showingTypeNote) {
                TypeNoteSheet(onSave: { text in
                    showingTypeNote = false
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    createTypedNote(content: text)
                }, onCancel: {
                    showingTypeNote = false
                })
            }
            // Stop pressed on the lock-screen indicator while the in-app
            // recorder owns the session.
            .onChange(of: backgroundCapture.inAppStopRequested) { _, requested in
                guard requested else { return }
                backgroundCapture.clearInAppStopRequest()
                if isRecording { stopRecording() }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .fileImporter(
                isPresented: $showingAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let sourceURL = urls.first else { return }
                    importAudioFile(from: sourceURL)
                case .failure(let error):
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
            .sheet(isPresented: $showingSourcePicker) {
                SourcePickerSheet(
                    onRecordAudio: {
                        toggleRecording()
                    },
                    onTypeNote: {
                        showingTypeNote = true
                    },
                    onImportAudio: {
                        showingAudioImporter = true
                    },
                    onImportPDF: { url in
                        savePDFNote(from: url)
                    },
                    onWebLink: { urlString in
                        saveWebNote(from: urlString)
                    }
                )
            }
            .navigationDestination(item: $navigateToNote) { note in
                NoteDetailView(
                    note: note,
                    initialTab: navigateTransformType != nil ? .transform : .insights,
                    autoTransform: navigateTransformType
                )
            }
            .onChange(of: navigateToNote) { oldValue, newValue in
                if newValue == nil {
                    navigateTransformType = nil
                }
            }
            .navigationDestination(item: $editNote) { note in
                NoteDetailView(note: note, startEditing: true)
            }
            .sheet(item: $sharePayload) { payload in
                ActivityViewControllerRepresentable(activityItems: [payload.text])
            }
            .onChange(of: shouldStartRecording) { _, newValue in
                if newValue {
                    shouldStartRecording = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        await MainActor.run {
                            if !isRecording && !isTranscribing {
                                toggleRecording()
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if backgroundCapture.isCapturing {
                    backgroundCaptureBanner
                }
            }
            .onAppear {
                trackSession()
                // Cheap UserDefaults read; no network. Refreshed on every
                // appearance so the banner clears as soon as an export succeeds.
                syncFailure = CloudKitEventLog.exportFailure()
                // Sync free note counter with actual database count
                let actualCount = visibleLibraryNotes.count
                UsageService.shared.syncNoteCount(actualCount: actualCount)

                // Check for pending share extension ingests
                Task {
                    let projects = libraryVisibleProjects((try? modelContext.fetch(FetchDescriptor<Project>())) ?? [])
                    let tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
                    await IntelligenceService.shared.processPendingIngests(
                        context: modelContext,
                        projects: projects,
                        tags: tags
                    )
                }
            }
        }
    }

    // MARK: - 1. Header

    private var hasCalendarSource: Bool {
        googleCalendarService.isConnected
            || (calendarContextEnabled && CalendarContextService.shared.isAuthorized)
    }

    /// One line: the date, Ask, avatar. The greeting went with Option A —
    /// orientation, not content, and the date does that job alone.
    private var headerBar: some View {
        HStack(alignment: .center, spacing: EEONLayout.tight) {
            Text(todayDateString)
                .font(EEONType.screenTitle)
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: EEONLayout.tight)

            Button {
                showingAskSheet = true
            } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.eeonAccentAI)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask EEON")
            .disabled(isRecording || isTranscribing)

            Button {
                showingSettings = true
            } label: {
                accountAvatar
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var accountAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if authService.isSignedIn {
                UserAvatarView(name: authService.displayName, size: 40)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title)
                    .foregroundStyle(.eeonTextSecondary)
                    .frame(width: 40, height: 40)
            }

            if googleCalendarService.isConnected {
                Text("G")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color.eeonAccent))
                    .overlay(Circle().stroke(Color.eeonBackground, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    private var todayDateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: - Free Notes Warning

    private func freeNotesWarning(remaining: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("\(remaining) of \(UsageService.freeNoteLimit) free notes left")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            Spacer()
            Button("Upgrade") {
                showPaywall = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(10)
    }

    /// Slim, always-legible recording state. Tap to open the full recorder
    /// with waveform and live transcript; the mic button below stops.
    private var recordingBar: some View {
        Button {
            showingFullRecorder = true
        } label: {
            HStack(spacing: EEONLayout.snug) {
                Circle()
                    .fill(recordingRed)
                    .frame(width: 9, height: 9)
                    .opacity(audioRecorder.isPaused ? 0.4 : 1)

                Text(audioRecorder.isPaused ? audioRecorder.recordingStatusText : "Recording \(captureNoun)")
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)

                Text(audioRecorder.formattedTime)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)

                Spacer()

                Text("View")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonAccent)
            }
            .padding(.horizontal, EEONLayout.standard)
            .frame(minHeight: EEONLayout.minTarget)
            .background(Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: EEONLayout.chipRadius))
            .padding(.horizontal, EEONLayout.screenMargin)
            .padding(.bottom, EEONLayout.tight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Bottom Bar (one record button)

    /// What the active capture will become, for every label that names it.
    private var captureNoun: String { capturingOrder ? "AI prompt" : "note" }

    /// One button. It records whatever the list above is showing — a note in
    /// Notes mode, an AI prompt in AI Prompts mode (AI colour). Ask moved to
    /// the header (Option A, 2026-09-10). Long-press for the non-voice inputs.
    private var bottomBar: some View {
        let promptMode = homeMode == .prompts
        return HStack {
            Button {
                if isRecording {
                    toggleRecording()
                    return
                }
                capturingOrder = promptMode
                toggleRecording()
                // Paywall, background capture, or a mic error: nothing
                // started, so the next Note must not become an order.
                if !isRecording { capturingOrder = false }
            } label: {
                HStack(spacing: EEONLayout.tight) {
                    if isTranscribing {
                        ProgressView()
                            .tint(.white)
                    } else if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: promptMode ? "brain.head.profile" : "waveform")
                            .font(.body.weight(.semibold))
                    }

                    Text(isTranscribing ? "Working…" : isRecording ? "Stop" : (promptMode ? "Record AI prompt" : "Record"))
                        .font(EEONType.control)
                        .lineLimit(1)

                    if isRecording {
                        Text(audioRecorder.formattedTime)
                            .font(EEONType.control)
                            .monospacedDigit()
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, EEONLayout.loose)
                .frame(minHeight: 56)
                .frame(maxWidth: .infinity)
                .background(isRecording ? recordingRed : (promptMode ? Color.eeonAccentAI : Color.eeonAccent))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isTranscribing)
            .accessibilityLabel(isRecording ? "Stop recording" : (promptMode ? "Record an AI prompt" : "Record a note"))
            .contextMenu {
                Button {
                    showingTypeNote = true
                } label: {
                    Label("Type a note", systemImage: "square.and.pencil")
                }
                Button {
                    showingAudioImporter = true
                } label: {
                    Label("Import a recording", systemImage: "square.and.arrow.down")
                }
                Button {
                    showingSourcePicker = true
                } label: {
                    Label("Add a link or document", systemImage: "doc.badge.plus")
                }
            }
        }
        .padding(.horizontal, EEONLayout.screenMargin)
        .padding(.top, 8)
        .background(
            Color.eeonBackground
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.eeonTextPrimary.opacity(0.08), radius: 4, y: -2)
        )
    }

    // MARK: - Home stack

    enum HomeMode: String, CaseIterable, Identifiable {
        case notes = "Notes"
        case prompts = "AI Prompts"

        var id: String { rawValue }
    }

    /// Option A (2026-09-10): today's meetings as a strip, one quiet tasks
    /// line, then a Notes | AI Prompts list. AI prompts never appear among
    /// notes; the record button records into whichever list is showing.
    private var homeStack: some View {
        VStack(alignment: .leading, spacing: EEONLayout.standard) {
            CalendarMeetingsView(compact: true)

            tasksLine

            Picker("Show", selection: $homeMode) {
                ForEach(HomeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if homeMode == .notes {
                notesList
            } else {
                promptsList
            }
        }
    }

    // MARK: Tasks line

    private var homeOpenActions: [ExtractedAction] {
        visibleExtractedActions.filter { !$0.isCompleted }
    }

    /// Due today or already overdue.
    private var tasksDueNow: Int {
        let now = Date()
        return homeOpenActions.filter { action in
            guard let due = EventKitSyncService.parseDate(from: action.deadline) else { return false }
            return Calendar.current.isDateInToday(due) || due < now
        }.count
    }

    private var tasksLineText: String {
        let due = tasksDueNow
        if due > 0 { return due == 1 ? "1 task due today" : "\(due) tasks due today" }
        let open = homeOpenActions.count
        return open == 1 ? "1 open task" : "\(open) open tasks"
    }

    /// Low-key on purpose: one line, no card, no rows. Disappears when
    /// there is nothing open. Tap → Tasks.
    @ViewBuilder
    private var tasksLine: some View {
        if !homeOpenActions.isEmpty {
            NavigationLink {
                TasksView()
            } label: {
                HStack(spacing: EEONLayout.tight) {
                    Image(systemName: "checklist")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextSecondary)
                    Text(tasksLineText)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    Image(systemName: "chevron.right")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextTertiary)
                    Spacer()
                }
                .frame(minHeight: EEONLayout.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All tasks")
            .padding(.horizontal)
        }
    }

    // MARK: Notes and AI Prompts

    /// Notes that are notes. Newest first by capture time — editing a note
    /// must not move it.
    private var homeNotes: [Note] {
        visibleLibraryNotes
            .filter { $0.intent != .order && $0.intent != .orderDone }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var homePrompts: [Note] {
        visibleLibraryNotes
            .filter { $0.intent == .order || $0.intent == .orderDone }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private static let homeNoteLimit = 20

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private func dayGroups(_ notes: [Note]) -> [(String, [Note])] {
        var out: [(String, [Note])] = []
        for note in notes {
            let key = dayLabel(for: note.createdAt)
            if let last = out.last, last.0 == key {
                out[out.count - 1].1.append(note)
            } else {
                out.append((key, [note]))
            }
        }
        return out
    }

    private var notesList: some View {
        let shown = Array(homeNotes.prefix(Self.homeNoteLimit))
        return VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                quietLine("No notes yet. Tap Record and start talking.")
            } else {
                ForEach(dayGroups(shown), id: \.0) { day, dayNotes in
                    dayHeader(day)
                    noteGroupCard(dayNotes, status: { _ in nil })
                }
                if homeNotes.count > shown.count {
                    NavigationLink(destination: AllNotesView()) {
                        HStack(spacing: EEONLayout.tight) {
                            Text("All \(homeNotes.count) notes")
                                .font(EEONType.control)
                                .foregroundStyle(.eeonAccent)
                            Image(systemName: "chevron.right")
                                .font(EEONType.badge)
                                .foregroundStyle(.eeonAccent)
                        }
                        .frame(minHeight: EEONLayout.minTarget)
                        .padding(.horizontal)
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All notes")
                }
            }
        }
    }

    private var promptsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if homePrompts.isEmpty {
                quietLine("No AI prompts yet. Tap Record AI prompt and tell your agents what to build.")
            } else {
                ForEach(dayGroups(homePrompts), id: \.0) { day, dayNotes in
                    dayHeader(day)
                    noteGroupCard(dayNotes, status: { $0.intent == .orderDone ? "Done" : "Queued" })
                }
            }
        }
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(EEONType.meta)
            .foregroundStyle(.eeonTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.vertical, 12)
    }

    private func dayHeader(_ day: String) -> some View {
        Text(day)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.eeonTextSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, EEONLayout.standard + 2)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    /// One day's notes as a single inset-grouped card: rows divided by
    /// inset hairlines, the way Settings and Tasks read.
    private func noteGroupCard(_ dayNotes: [Note], status: @escaping (Note) -> String?) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(dayNotes.enumerated()), id: \.element.id) { index, note in
                noteRow(note, status: status(note))
                if index < dayNotes.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
        .padding(.horizontal)
    }

    private func noteMetaLine(_ note: Note) -> String {
        var parts = [note.createdAt.formatted(date: .omitted, time: .shortened)]
        if let seconds = note.audioDuration, seconds > 0 {
            parts.append(NoteFeedCard.durationText(seconds))
        }
        if let topic = note.topics.first, !topic.isEmpty {
            parts.append(topic.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    /// Title on top, "time · length · topic" underneath, chevron. Swipe for
    /// Edit / Share / Delete (no full swipe — a note goes only on that tap).
    private func noteRow(_ note: Note, status: String?) -> some View {
        EEONSwipeActionsRow(
            actions: [
                .edit { editNote = note },
                .share { sharePayload = EEONSharePayload(text: noteShareText(note)) },
                .delete { deleteNote(note) }
            ],
            allowsFullSwipe: false
        ) {
            NavigationLink(destination: NoteDetailView(note: note)) {
                HStack(alignment: .center, spacing: EEONLayout.snug) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.displayTitle)
                            .font(EEONType.itemTitle)
                            .foregroundStyle(.eeonTextPrimary)
                            .lineLimit(1)
                        Text(noteMetaLine(note))
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let status {
                        Text(status)
                            .font(EEONType.badge)
                            .foregroundStyle(status == "Done" ? Color.eeonTextTertiary : Color.eeonAccentAI)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((status == "Done" ? Color.eeonTextTertiary : Color.eeonAccentAI).opacity(0.12)))
                    }

                    Image(systemName: "chevron.right")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func deleteNote(_ note: Note) {
        withAnimation(.easeInOut(duration: 0.2)) {
            note.deleteAudioFile()
            note.deleteImageFiles()
            modelContext.delete(note)
            try? modelContext.save()
        }
    }

    private func noteShareText(_ note: Note) -> String {
        var parts: [String] = []
        if !note.displayTitle.isEmpty { parts.append(note.displayTitle) }
        let body = note.enhancedNoteText ?? note.transcript ?? note.content
        if !body.isEmpty { parts.append(body) }
        parts.append("Shared from EEON")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Setup line

    /// One quiet row until calendar and Reminders are connected. Tap →
    /// Settings, where both toggles live. Dismissable; never comes back.
    private var showSetupLine: Bool {
        guard onboardingChecklistDismissedRaw == 0 else { return false }
        return !hasCalendarSource || !remindersSyncEnabled
    }

    private var setupLineText: String {
        switch (hasCalendarSource, remindersSyncEnabled) {
        case (false, false): return "Connect your calendar and Reminders"
        case (false, true): return "Connect your calendar"
        default: return "Send tasks to Reminders"
        }
    }

    private var setupLine: some View {
        HStack(spacing: EEONLayout.tight) {
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: EEONLayout.tight) {
                    Image(systemName: "gearshape")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonAccentAI)
                    Text(setupLineText)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextTertiary)
                }
                .frame(minHeight: EEONLayout.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onboardingChecklistDismissedRaw = Date().timeIntervalSince1970
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.eeonTextTertiary)
                    .eeonTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss setup")
        }
    }

    // MARK: - Background Capture Banner

    private var backgroundCaptureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: backgroundCapture.recorder.isPaused ? "pause.circle.fill" : "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !backgroundCapture.recorder.isPaused)
            Text(backgroundCapture.recorder.isPaused
                 ? backgroundCapture.recorder.recordingStatusText
                 : "Recording · \(backgroundCapture.recorder.formattedTime)")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                Task { try? await backgroundCapture.stop() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Signed Out View

    private var signedOutView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero section
                VStack(spacing: 20) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.eeonAccent.opacity(0.08 - Double(i) * 0.02), lineWidth: 1)
                                .frame(width: CGFloat(100 + i * 40), height: CGFloat(100 + i * 40))
                        }

                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.eeonAccent.opacity(0.2), Color.eeonAccent.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 88, height: 88)

                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.eeonAccent, .eeonAccent.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                    .padding(.top, 32)

                    VStack(spacing: 10) {
                        Text("Speak. EEON listens.")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.eeonTextPrimary)

                        Text("Record a thought, get back clarity.\nDecisions, tasks, and follow-ups -- extracted automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)

                // Feature cards
                VStack(spacing: 12) {
                    WelcomeFeatureRow(
                        icon: "mic.fill",
                        iconColor: .eeonAccent,
                        title: "Record anything",
                        subtitle: "Meetings, ideas, reminders -- just talk"
                    )

                    WelcomeFeatureRow(
                        icon: "sparkles",
                        iconColor: .eeonAccentAI,
                        title: "AI extracts what matters",
                        subtitle: "Decisions, commitments, and action items"
                    )

                    WelcomeFeatureRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Stay on track",
                        subtitle: "Daily briefs, progress tracking, nothing slips"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)

                // Sign in CTA
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            authService.handleSignInResult(.success(authorization))
                        case .failure(let error):
                            if let authorizationError = error as? ASAuthorizationError,
                               authorizationError.code == .canceled {
                                return
                            }
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    Text("5 free notes \u{00B7} No credit card required")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .padding(.bottom, 24)

                Color.clear.frame(height: 100)

                #if DEBUG
                Button {
                    OnboardingState.set(.needsSignIn)
                } label: {
                    Text("Reset Onboarding")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange.opacity(0.5))
                }
                .padding(.bottom, 8)
                #endif
            }
        }
    }

    // MARK: - Session Tracking

    private func trackSession() {
        var count = UserDefaults.standard.integer(forKey: "eeon_session_count")
        count += 1
        UserDefaults.standard.set(count, forKey: "eeon_session_count")
        UserDefaults.standard.set(Date(), forKey: "eeon_last_open_date")
    }

    // MARK: - Recording

    private func toggleRecording() {
        // A background capture (Action Button / Control Center) owns the mic.
        // The big button becomes its stop button instead of fighting for the
        // session.
        if BackgroundCaptureService.shared.isCapturing {
            Task { try? await BackgroundCaptureService.shared.stop() }
            return
        }
        if isRecording {
            stopRecording()
        } else {
            if !UsageService.shared.canCreateNote {
                showPaywall = true
                return
            }
            startRecording()
        }
    }

    private func startRecording() {
        do {
            currentAudioFileName = try audioRecorder.startRecording()
            isRecording = true
            // Show the recorder on tap. Hiding it made pressing record feel
            // like nothing happened. Swiping it down keeps the capture running
            // and drops the expensive live transcription.
            showingFullRecorder = true
            // Lock-screen indicator, so locking the phone mid-recording still
            // shows it's running (and offers a stop button).
            Task { await BackgroundCaptureService.shared.showActivity(for: audioRecorder) }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func stopRecording() {
        Task { await BackgroundCaptureService.shared.hideActivity() }
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording"
            showingError = true
            isRecording = false
            return
        }

        isRecording = false
        isTranscribing = true
        transcribeAndSave(url: url)
    }

    private func cancelRecording() {
        Task { await BackgroundCaptureService.shared.hideActivity() }
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        currentAudioFileName = nil
        isRecording = false
        capturingOrder = false
    }

    private func transcribeAndSave(url: URL, isImport: Bool = false) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            let forcedIntent: NoteIntent? = capturingOrder ? .order : nil
            saveNote(transcript: nil, isImport: isImport, forcedIntent: forcedIntent)
            if forcedIntent == .order {
                capturingOrder = false
            }
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                let rawTranscript = try await service.transcribe(audioURL: url)

                // Clean filler words
                let transcript: String
                do {
                    transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
                } catch {
                    transcript = rawTranscript
                }

                // "Remind me…" is decided on-device before any classifier call:
                // it is a note (the capture is kept) plus a confirmation sheet.
                // Imports are exempt — an old recording is not a command.
                let isOrder = capturingOrder
                let reminderCommand = (isImport || isOrder) ? nil : ReminderCommandParser.parse(transcript)

                // Classify intent: question routes to AnswerSheet, note saves as usual.
                // On classifier failure we fall back to .newNote — the safer default is
                // "your speech became a note" rather than swallowing it into a Q&A.
                let intent: IntentType
                if isOrder || reminderCommand != nil {
                    // Orders are always saved, never answered as a question.
                    intent = .newNote
                } else {
                    do {
                        intent = try await IntentClassifier.shared.classify(transcript: transcript)
                    } catch {
                        print("[IntentClassifier] classification failed, defaulting to newNote: \(error)")
                        intent = .newNote
                    }
                }

                await MainActor.run {
                    switch intent {
                    case .question:
                        // Discard the audio file — questions don't get saved as notes.
                        if let fileName = currentAudioFileName {
                            audioRecorder.deleteRecording(fileName: fileName)
                        }
                        currentAudioFileName = nil
                        isTranscribing = false
                        pendingAnswerQuery = AnswerQuery(query: transcript)
                    case .newNote:
                        let forcedIntent: NoteIntent? = isOrder ? .order : (reminderCommand != nil ? .reminder : nil)
                        let note = saveNote(transcript: transcript, isImport: isImport, forcedIntent: forcedIntent)
                        if isOrder { capturingOrder = false }
                        if let reminderCommand {
                            // Whatever the user decides in the sheet, the
                            // extraction pass must not push a second copy.
                            EventKitSyncService.shared.markHandledByCommand(note.id)
                            pendingReminder = reminderCommand
                        }
                    }
                }
            } catch TranscriptionService.TranscriptionError.noSpeechDetected {
                await MainActor.run { capturingOrder = false }
                // Silent / near-silent audio. Never fabricate a note from it
                // (that is where "Welcome everyone to the video" came from).
                await MainActor.run {
                    if let fileName = currentAudioFileName {
                        audioRecorder.deleteRecording(fileName: fileName)
                    }
                    currentAudioFileName = nil
                    isTranscribing = false
                    errorMessage = "No speech detected. Nothing was saved — try recording again."
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    _ = saveNote(
                        transcript: nil,
                        pending: true,
                        isImport: isImport,
                        forcedIntent: capturingOrder ? .order : nil
                    )
                    if capturingOrder {
                        capturingOrder = false
                    }
                }
            }
        }
    }


    private func importAudioFile(from sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file"
            showingError = true
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = documentsPath.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            errorMessage = "Could not import file: \(error.localizedDescription)"
            showingError = true
            return
        }

        if (try? AVAudioPlayer(contentsOf: destinationURL)) != nil {
            currentAudioFileName = fileName
            isTranscribing = true
            transcribeAndSave(url: destinationURL, isImport: true)
        } else {
            errorMessage = "Could not read audio file"
            showingError = true
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    @discardableResult
    private func saveNote(
        transcript: String?,
        pending: Bool = false,
        isImport: Bool = false,
        forcedIntent: NoteIntent? = nil
    ) -> Note {
        let note = Note(
            title: "",
            content: transcript ?? "",
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        if let forcedIntent {
            note.intentType = forcedIntent.rawValue
            note.intentConfidence = 1.0
        }
        modelContext.insert(note)
        if pending {
            note.transcriptionStatus = "pending"
        }
        if isImport {
            // Recorded some other time — the meeting happening at import
            // time has nothing to do with it.
            note.sourceType = .audioImport
            CalendarContextService.shared.excludeFromMatching(note.id)
        }

        // Track usage and store duration
        if let fileName = currentAudioFileName {
            trackRecordingUsage(fileName: fileName, for: note)
        }
        UsageService.shared.incrementNoteCount()
        try? modelContext.save()
        if note.intentType == NoteIntent.order.rawValue {
            mirrorAIOrder(note)
        }

        // Update widget
        let preview = transcript ?? note.displayTitle
        SharedDefaults.updateLastNote(
            preview: String(preview.prefix(100)),
            date: note.createdAt,
            intent: note.intentType
        )
        SharedDefaults.updateTotalNotes(notes.count + 1)
        WidgetKit.WidgetCenter.shared.reloadAllTimelines()

        // AI processing
        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let context = modelContext
            let allProjects = projects

            Task {
                do {
                    // Calendar context first so the title can name the meeting.
                    await CalendarContextService.shared.attachIfNeeded(to: note)
                    let title = try await SummaryService.generateTitle(
                        for: transcript,
                        context: note.calendarContext?.promptLine,
                        apiKey: apiKey
                    )
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: transcript)

                    await MainActor.run {
                        note.title = title

                        for tagName in tagNames {
                            if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                note.tags.append(existingTag)
                            } else {
                                let newTag = Tag(name: tagName)
                                context.insert(newTag)
                                note.tags.append(newTag)
                            }
                        }

                        isTranscribing = false
                        currentAudioFileName = nil
                        navigateToNote = note

                        SharedDefaults.updateLastNote(
                            preview: note.displayTitle,
                            date: note.createdAt,
                            intent: note.intentType
                        )
                        WidgetKit.WidgetCenter.shared.reloadAllTimelines()
                        if note.intentType == NoteIntent.order.rawValue {
                            mirrorAIOrder(note)
                        }
                    }

                    await intelligenceService.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: allProjects,
                        tags: existingTags,
                        context: context
                    )
                    await MainActor.run {
                        if note.intentType == NoteIntent.order.rawValue {
                            mirrorAIOrder(note)
                        }
                    }

                    Task {
                        await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                    }
                } catch {
                    await MainActor.run {
                        isTranscribing = false
                        currentAudioFileName = nil
                    }
                }
            }
        } else {
            isTranscribing = false
            currentAudioFileName = nil
            StatusCounters.shared.incrementNotesToday()
            StatusCounters.shared.markSessionStale()
        }
        return note
    }

    private func mirrorAIOrder(_ note: Note) {
        let instructionCandidates: [String?] = [
            note.content.trimmingCharacters(in: .whitespacesAndNewlines),
            note.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let instructions = instructionCandidates
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? note.displayTitle
        let id = note.id
        let title = note.displayTitle
        let createdAt = note.createdAt
        let project = note.inferredProjectName

        Task {
            await AIAccessService.shared.enqueueOrder(
                id: id,
                title: title,
                instructions: instructions,
                createdAt: createdAt,
                project: project
            )
            await AIAccessService.shared.refreshCloudKitAccessIfPossible()
        }
    }

    // MARK: - Create Typed Note

    private func createTypedNote(content: String) {
        let note = Note(
            title: "",
            content: content,
            transcript: content,
            audioFileName: nil
        )
        modelContext.insert(note)
        UsageService.shared.incrementNoteCount()
        try? modelContext.save()

        // Same post-capture moment as voice notes: land on the note and
        // refresh the widget. Typed notes are first-class captures.
        navigateToNote = note
        SharedDefaults.updateLastNote(
            preview: String(content.prefix(100)),
            date: note.createdAt,
            intent: note.intentType
        )
        SharedDefaults.updateTotalNotes(notes.count + 1)
        WidgetKit.WidgetCenter.shared.reloadAllTimelines()

        if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let allProjects = projects
            let context = modelContext

            Task {
                do {
                    let title = try await SummaryService.generateTitle(for: content, apiKey: apiKey)
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: content)

                    await MainActor.run {
                        note.title = title

                        for tagName in tagNames {
                            if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                if !note.tags.contains(where: { $0.id == existingTag.id }) {
                                    note.tags.append(existingTag)
                                }
                            } else {
                                let newTag = Tag(name: tagName.capitalized)
                                modelContext.insert(newTag)
                                note.tags.append(newTag)
                            }
                        }

                        if let match = ProjectMatcher.findMatch(for: content, in: allProjects) {
                            note.projectId = match.project.id
                        }
                    }

                    // Full intelligence pipeline — extraction, enhanced text,
                    // knowledge events — same as voice captures.
                    await intelligenceService.processNoteSave(
                        note: note,
                        transcript: content,
                        projects: allProjects,
                        tags: existingTags,
                        context: context
                    )

                    // Embed so Ask EEON / RAG can find typed notes.
                    Task {
                        await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                    }
                } catch {
                    print("Error processing typed note: \(error)")
                }
            }
        }
    }

    // MARK: - Create Web Note

    private func saveWebNote(from urlString: String) {
        isTranscribing = true

        Task {
            do {
                let webContent = try await WebContentService.fetchArticle(from: urlString)

                await MainActor.run {
                    let note = Note(
                        title: webContent.title,
                        content: webContent.text,
                        transcript: webContent.text,
                        audioFileName: nil
                    )
                    note.sourceTypeRaw = NoteSourceType.webArticle.rawValue
                    note.originalURL = webContent.url
                    modelContext.insert(note)
                    UsageService.shared.incrementNoteCount()
                    try? modelContext.save()

                    isTranscribing = false
                    navigateToNote = note

                    // AI processing
                    if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                        let existingTags = tags
                        let allProjects = projects
                        let context = modelContext

                        Task {
                            do {
                                let extractor = TagExtractor(apiKey: apiKey)
                                let tagNames = try await extractor.extractTags(from: webContent.text)

                                await MainActor.run {
                                    for tagName in tagNames {
                                        if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                            if !note.tags.contains(where: { $0.id == existingTag.id }) {
                                                note.tags.append(existingTag)
                                            }
                                        } else {
                                            let newTag = Tag(name: tagName.capitalized)
                                            context.insert(newTag)
                                            note.tags.append(newTag)
                                        }
                                    }

                                    if let match = ProjectMatcher.findMatch(for: webContent.text, in: allProjects) {
                                        note.projectId = match.project.id
                                    }
                                }

                                await intelligenceService.processNoteSave(
                                    note: note,
                                    transcript: webContent.text,
                                    projects: allProjects,
                                    tags: existingTags,
                                    context: context
                                )

                                await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                            } catch {
                                print("Error processing web note: \(error)")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    errorMessage = "Couldn't load that link: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    // MARK: - Create PDF/Document Note

    private func savePDFNote(from sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file"
            showingError = true
            return
        }

        isTranscribing = true

        Task {
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            do {
                // Copy file to documents first for reliable access
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
                let localURL = documentsPath.appendingPathComponent(fileName)
                try FileManager.default.copyItem(at: sourceURL, to: localURL)

                let extracted: ExtractedDocument
                if sourceURL.pathExtension.lowercased() == "pdf" {
                    extracted = try await PDFExtractionService.shared.extractText(from: localURL)
                } else {
                    // Plain text file
                    let text = try String(contentsOf: localURL, encoding: .utf8)
                    extracted = ExtractedDocument(
                        text: text,
                        title: sourceURL.deletingPathExtension().lastPathComponent,
                        pageCount: 1,
                        wasOCR: false
                    )
                }

                await MainActor.run {
                    let note = Note(
                        title: extracted.title,
                        content: extracted.text,
                        transcript: extracted.text,
                        audioFileName: nil
                    )
                    note.sourceTypeRaw = NoteSourceType.document.rawValue
                    modelContext.insert(note)
                    UsageService.shared.incrementNoteCount()
                    try? modelContext.save()

                    isTranscribing = false
                    navigateToNote = note

                    // AI processing
                    if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                        let existingTags = tags
                        let allProjects = projects
                        let context = modelContext

                        Task {
                            do {
                                let title = try await SummaryService.generateTitle(for: extracted.text, apiKey: apiKey)
                                let extractor = TagExtractor(apiKey: apiKey)
                                let tagNames = try await extractor.extractTags(from: extracted.text)

                                await MainActor.run {
                                    note.title = title

                                    for tagName in tagNames {
                                        if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                            if !note.tags.contains(where: { $0.id == existingTag.id }) {
                                                note.tags.append(existingTag)
                                            }
                                        } else {
                                            let newTag = Tag(name: tagName.capitalized)
                                            context.insert(newTag)
                                            note.tags.append(newTag)
                                        }
                                    }

                                    if let match = ProjectMatcher.findMatch(for: extracted.text, in: allProjects) {
                                        note.projectId = match.project.id
                                    }
                                }

                                await intelligenceService.processNoteSave(
                                    note: note,
                                    transcript: extracted.text,
                                    projects: allProjects,
                                    tags: existingTags,
                                    context: context
                                )

                                await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                            } catch {
                                print("Error processing PDF note: \(error)")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    errorMessage = "Couldn't extract text: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func trackRecordingUsage(fileName: String, for note: Note? = nil) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsURL.appendingPathComponent(fileName)

        let asset = AVURLAsset(url: audioURL)
        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    UsageService.shared.addRecordingTime(seconds: Int(seconds))
                    if let note = note {
                        await MainActor.run {
                            note.audioDuration = seconds
                        }
                    }
                }
            } catch {
                print("Failed to load audio duration: \(error)")
            }
        }
    }
}

// MARK: - Welcome Feature Row (signed-out screen)

struct WelcomeFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.eeonCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.eeonDivider, lineWidth: 1)
                )
        )
    }
}

// MARK: - Note Feed Card

struct NoteFeedCard: View {
    /// "1h 24m" / "8m" / "42s" — matches how a capture stream reads a length.
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    @Environment(\.colorScheme) var colorScheme
    let note: Note

    private var preview: String {
        if let transcript = note.transcript, !transcript.isEmpty {
            let firstLine = transcript.components(separatedBy: .newlines).first ?? transcript
            return String(firstLine.prefix(80))
        }
        if !note.content.isEmpty {
            let firstLine = note.content.components(separatedBy: .newlines).first ?? note.content
            return String(firstLine.prefix(80))
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            Text(note.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(2)

            // Metadata line, Pocket-style: time · duration · category.
            // The day lives in the section header, so the card carries the
            // time of day, how long the recording ran, and one tag.
            HStack(spacing: 6) {
                Text(note.createdAt.formatted(date: .omitted, time: .shortened))
                if let seconds = note.audioDuration, seconds > 0 {
                    Text("·")
                    Text(NoteFeedCard.durationText(seconds))
                }
                if let topic = note.topics.first, !topic.isEmpty {
                    Text("·")
                    Text(topic.capitalized)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.eeonTextSecondary)

            // 1-line preview
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.eeonTextTertiary)
                    .lineLimit(2)
            }

            // Intent/topic chips removed 2026-08-19 — a card is title,
            // time, preview. Status glyphs (archive/favorite) remain.
            HStack(spacing: 4) {
                Spacer()

                if note.isArchived {
                    Image(systemName: "archivebox.fill")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextTertiary)
                }

                if note.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(12)
        .overlay(alignment: .topTrailing) {
            if let icon = note.sourceType.badgeIcon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.eeonTextSecondary)
                    .padding(6)
            }
        }
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Recent Notes Sidebar (iPad / Regular size class)

/// Simple list of recent notes rendered in the NavigationSplitView sidebar on
/// iPad and Mac Catalyst. Intentionally independent of the main feed's tab /
/// sort / tag-filter state so it stays a pure "recent notes" lens and doesn't
/// require threading AIHomeView state through to the sidebar.
fileprivate struct RecentNotesSidebar: View {
    let notes: [Note]

    var body: some View {
        List {
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.eeonTextTertiary)
                    Text("No notes yet")
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(notes.prefix(8))) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        RecentNotesSidebarRow(note: note)
                    }
                }

                if notes.count > 8 {
                    NavigationLink(destination: AllNotesView()) {
                        Label("All Recent", systemImage: "clock")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

fileprivate struct RecentNotesSidebarRow: View {
    let note: Note

    private var preview: String {
        if let transcript = note.transcript, !transcript.isEmpty {
            let firstLine = transcript.components(separatedBy: .newlines).first ?? transcript
            return String(firstLine.prefix(80))
        }
        if !note.content.isEmpty {
            let firstLine = note.content.components(separatedBy: .newlines).first ?? note.content
            return String(firstLine.prefix(80))
        }
        return "Untitled note"
    }

    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: note.updatedAt, relativeTo: Date())
    }

    /// Pocket-style metadata line: time, then the meeting it was recorded in.
    private var metaString: String {
        if let event = note.calendarContext?.title, !event.isEmpty {
            return "\(timeString) \u{00B7} \(event)"
        }
        return timeString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(2)
            Text(metaString)
                .font(.caption)
                .foregroundStyle(.eeonTextSecondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Disable Interactive Pop Gesture

/// Disables iOS's NavigationStack interactive back-swipe at the root so horizontal
/// drags on the home screen don't trigger edge-swipe feedback. Uses viewDidAppear
/// for reliable timing — updateUIViewController fires before the view is actually
/// in the UIKit hierarchy, so navigationController is nil there.
///
/// Note: this doesn't disable the iOS system "back to previous app" gesture that
/// appears when launching from TestFlight or another app (the "◀ TestFlight" chip).
/// That's a system gesture apps can't control; it disappears when users launch
/// from the home screen directly.
private struct DisableBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DisableBackSwipeVC {
        DisableBackSwipeVC()
    }
    func updateUIViewController(_ uiViewController: DisableBackSwipeVC, context: Context) {}
}

private final class DisableBackSwipeVC: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        var current: UIViewController? = self
        while let vc = current {
            if let nav = vc.navigationController {
                nav.interactivePopGestureRecognizer?.isEnabled = false
                return
            }
            current = vc.parent
        }
    }
}

// MARK: - Preview

#Preview {
    AIHomeView(shouldStartRecording: .constant(false))
        .modelContainer(for: [Note.self, Tag.self, Project.self, DailyBrief.self, MentionedPerson.self, ExtractedURL.self, ExtractedCommitment.self], inMemory: true)
}
