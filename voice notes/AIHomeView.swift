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

enum NotesViewMode: String, CaseIterable {
    case list = "List"
    case mood = "Mood"
}

struct AIHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var tags: [Tag]
    @Query(sort: \DailyBrief.briefDate, order: .reverse) private var dailyBriefs: [DailyBrief]
    @Query private var extractedCommitments: [ExtractedCommitment]
    @Query private var kanbanItems: [KanbanItem]
    @Query private var kanbanMovements: [KanbanMovement]
    @Query private var extractedActions: [ExtractedAction]
    @Query private var extractedDecisions: [ExtractedDecision]
    @Query private var mentionedPeople: [MentionedPerson]
    @Query private var unresolvedItems: [UnresolvedItem]
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var knowledgeArticles: [KnowledgeArticle]
    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "purpose" })
    private var purposeArticles: [KnowledgeArticle]

    @Binding var shouldStartRecording: Bool

    private var authService = AuthService.shared
    private var intelligenceService = IntelligenceService.shared
    private var backgroundCapture = BackgroundCaptureService.shared
    private let recordingRed = Color(red: 1.0, green: 0.23, blue: 0.27)

    init(shouldStartRecording: Binding<Bool>) {
        self._shouldStartRecording = shouldStartRecording
    }

    @State private var showingSettings = false
    @State private var pendingAnswerQuery: AnswerQuery?
    /// "Remind me…" heard in a recording — confirmed in ReminderConfirmSheet.
    @State private var pendingReminder: ReminderCommandParser.Command?
    @State private var showingIdentity = false
    @State private var showingWhyThisHome = false
    @State private var showPaywall = false
    @State private var driftStatus: DriftStatus = .fresh
    @AppStorage("tuneBannerDismissedAt") private var tuneBannerDismissedRaw: Double = 0

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
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

    // Daily brief expansion

    // Feed tabs & sorting
    enum FeedTab: String, CaseIterable {
        case all = "All"
        case notebooks = "Notebooks"
        case ai = "AI"
        case favorites = "Favorites"
        case archive = "Archive"
    }
    @State private var selectedTab: FeedTab = .all
    @State private var sortNewestFirst = true
    @State private var viewMode: NotesViewMode = .list
    @State private var selectedTagFilter: Tag?
    @State private var showingTagManagement = false
    @State private var showingTagFilter = false
    /// What the feed shows under the Library header. Library is the default;
    /// Tasks and Highlights render inline in the same place.
    enum FeedMode: String, CaseIterable, Identifiable, Hashable {
        case library = "Library"
        case tasks = "Tasks"
        case highlights = "Highlights"

        var id: String { rawValue }
    }
    @State private var feedMode: FeedMode = .library
    @State private var selectedCategory: String?
    @State private var showingDatePicker = false
    @State private var showingFullRecorder = false
    #if DEBUG
    @State private var didStartRecorderDemo = false
    #endif
    @State private var selectedDay: Date?
    @State private var selectedIntents: Set<NoteIntent> = []

    // Keyword search — global substring search across all notes
    @State private var searchQuery = ""

    // Today's daily brief
    private var todaysBrief: DailyBrief? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyBriefs.first { $0.briefDate >= today }
    }

    /// Computed AI tab data (only built when AI tab is selected)
    private var aiTabData: AITabData {
        AITabBuilder.build(
            notes: visibleLibraryNotes,
            actions: visibleExtractedActions,
            commitments: visibleExtractedCommitments,
            decisions: visibleExtractedDecisions,
            people: visibleMentionedPeople
        )
    }

    /// Tags sorted by note count descending
    private var sortedTags: [Tag] {
        tags.sorted { (($0.notes ?? []).count) > (($1.notes ?? []).count) }
    }

    private func tagNoteCount(_ tag: Tag) -> Int {
        (tag.notes ?? []).count
    }

    /// Filtered notes based on selected tab and optional tag filter
    private var filteredNotes: [Note] {
        var base: [Note]
        // Always exclude Tune EEON seed notes — they're configuration, not memory.
        // They live inside Tune EEON; showing them in the feed would inflate counts,
        // pollute search, and let users accidentally delete their own config.
        let visible = librarySearchableNotes(notes)
        switch selectedTab {
        case .all:
            base = visible.filter { !$0.isArchived }
        case .notebooks:
            base = visible.filter { !$0.isArchived }
        case .ai:
            base = visible.filter { !$0.isArchived }
        case .favorites:
            base = visible.filter { $0.isFavorite && !$0.isArchived }
        case .archive:
            base = visible.filter { $0.isArchived }
        }
        // Apply tag filter if selected
        if let tag = selectedTagFilter {
            base = base.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        }

        // Category card selection (Pocket-style top row)
        if let category = selectedCategory {
            base = base.filter { note in
                (note.topics.first?.capitalized ?? "Unfiled") == category
            }
        }

        // Week-strip day selection
        if let day = selectedDay {
            base = base.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
        }
        // Apply intent filter if any selected
        base = NotesReorgHelpers.filterByIntents(notes: base, selected: selectedIntents)
        if sortNewestFirst {
            return base // Already sorted newest first by @Query
        } else {
            return base.reversed()
        }
    }

    /// The query with surrounding whitespace removed. Empty when search is inactive.
    private var activeSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while the user has a non-empty search query entered.
    private var isSearching: Bool {
        !activeSearchQuery.isEmpty
    }

    /// Global keyword search results across every note (including archived),
    /// excluding only the Tune EEON seed notes — which are configuration, not
    /// memory, and must never appear in the feed or search (see `filteredNotes`).
    private var searchResults: [Note] {
        NoteKeywordSearch.match(query: activeSearchQuery, in: librarySearchableNotes(notes))
    }

    private var visibleLibraryNotes: [Note] {
        libraryVisibleNotes(notes)
    }

    private var visibleProjects: [Project] {
        libraryVisibleProjects(projects)
    }

    private var visibleKnowledgeArticles: [KnowledgeArticle] {
        libraryVisibleArticles(knowledgeArticles)
    }

    private var visibleMentionedPeople: [MentionedPerson] {
        libraryVisiblePeople(mentionedPeople)
    }

    private var visibleExtractedActions: [ExtractedAction] {
        extractedActions.filter { !libraryIsSchemaSeedName($0.content) && !libraryIsSchemaSeedName($0.owner) }
    }

    private var visibleExtractedCommitments: [ExtractedCommitment] {
        extractedCommitments.filter { !libraryIsSchemaSeedName($0.who) && !libraryIsSchemaSeedName($0.what) }
    }

    private var visibleExtractedDecisions: [ExtractedDecision] {
        extractedDecisions.filter { !libraryIsSchemaSeedName($0.content) && !libraryIsSchemaSeedName($0.affects) }
    }

    private var libraryPreviewNotes: [Note] {
        Array(visibleLibraryNotes.prefix(8))
    }

    private var librarySummaries: [LibraryCollectionSummary] {
        libraryCollectionSummaries(
            notes: notes,
            projects: visibleProjects
        )
    }

    private var libraryHomeCollections: [LibraryCollectionSummary] {
        librarySummaries.filter { $0.kind != .recent }
    }

    /// Group notes by month for section headers
    private var notesByDay: [(String, [Note])] {
        // Chronological, day-grouped feed: Today / Yesterday / "Tuesday, Mar 4".
        let calendar = Calendar.current
        let thisYear = DateFormatter()
        thisYear.dateFormat = "EEEE, MMM d"
        let otherYear = DateFormatter()
        otherYear.dateFormat = "EEEE, MMM d, yyyy"

        func label(for date: Date) -> String {
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
                return thisYear.string(from: date)
            }
            return otherYear.string(from: date)
        }

        var grouped: [(String, [Note])] = []
        var currentDay = ""
        var currentGroup: [Note] = []

        for note in filteredNotes {
            let day = label(for: note.createdAt)
            if day != currentDay {
                if !currentGroup.isEmpty {
                    grouped.append((currentDay, currentGroup))
                }
                currentDay = day
                currentGroup = [note]
            } else {
                currentGroup.append(note)
            }
        }
        if !currentGroup.isEmpty {
            grouped.append((currentDay, currentGroup))
        }
        return grouped
    }

    /// Notebooks: notes auto-filed by what they are — the matched project's
    /// name when ProjectMatcher assigned one, else the note's first topic,
    /// else "Unfiled". Zero manual filing. Groups ordered by most recent note.
    private var notesByNotebook: [(String, [Note])] {
        var groups: [String: [Note]] = [:]
        for note in filteredNotes {
            let name: String
            if let pid = note.projectId,
               let project = projects.first(where: { $0.id == pid }),
               !project.name.isEmpty {
                name = project.name
            } else if let topic = note.topics.first, !topic.isEmpty {
                name = topic.capitalized
            } else {
                name = "Unfiled"
            }
            groups[name, default: []].append(note)
        }
        return groups.sorted {
            ($0.value.first?.createdAt ?? .distantPast) > ($1.value.first?.createdAt ?? .distantPast)
        }.map { ($0.key, $0.value) }
    }

    private var emptyStateIcon: String {
        switch selectedTab {
        case .all: return "waveform.circle"
        case .notebooks: return "books.vertical"
        case .ai: return "sparkles"
        case .favorites: return "heart.circle"
        case .archive: return "archivebox"
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .all: return "Your memory starts here"
        case .notebooks: return "Nothing filed yet"
        case .ai: return "Almost there"
        case .favorites: return "Your greatest hits"
        case .archive: return "Clean slate"
        }
    }

    private var emptyStateSubtitle: String {
        switch selectedTab {
        case .all: return "Hit the mic and say what's on your mind. EEON will remember it for you."
        case .notebooks: return "Record notes and they'll file themselves into notebooks by project and topic."
        case .ai: return "Record a few more notes and EEON will start connecting the dots."
        case .favorites: return "Tap the heart on any note to pin it here."
        case .archive: return "Archived notes live here. Out of sight, never out of reach."
        }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            regularBody
        } else {
            compactBody
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
                            // 1. Greeting bar
                            greetingBar
                                .padding(.horizontal)

                            // Lens switcher removed 2026-08-21. Notes /
                            // Calendar / Categories were whole-screen views
                            // you switched INTO to perform a filter and back
                            // out of afterwards. Both are now dropdowns on
                            // the feed header: pick a category or a date and
                            // the notes below re-filter in place. You never
                            // leave the main screen.

                            // Tune EEON hero card — prominent until user has compiled a .purpose article
                            if showTuneHeroCard {
                                tuneHeroCard
                                    .padding(.horizontal)
                            }

                            // Drift / staleness "Re-tune" banner removed from home
                            // (2026-08-19 simplification — home is the capture
                            // stream, not a nag surface). driftBanner view kept
                            // in codebase; re-tune lives in Settings / Tune EEON.

                            // Daily brief is "Highlights" in the feed dropdown (2026-08-25), not a card here.

                            // Free tier warning
                            if !UsageService.shared.isPro {
                                let remaining = UsageService.shared.freeNotesRemaining
                                if remaining <= 2 && remaining > 0 {
                                    freeNotesWarning(remaining: remaining)
                                        .padding(.horizontal)
                                }
                            }

                            // Layout-driven sections — order determined by HomeLayout.decode,
                            // which anchors knowledgeCarousel and recentNotes at indices 0 and 1
                            // (platform-universal) and lets the LLM order persona-shaped sections
                            // at index 2+. The case .knowledgeCarousel dispatch in
                            // sectionView(for:section:) renders knowledgeCardsSection.
                            ForEach(activeLayout.sections) { section in
                                if let kind = section.kind {
                                    sectionView(for: kind, section: section)
                                }
                            }

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
                        audioRecorder: audioRecorder
                    )
                }

                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay()
                }
            }
            .navigationBarHidden(true)
            .background(DisableBackSwipe())
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingIdentity) {
                TuneConversationView()
            }
            .sheet(isPresented: $showingWhyThisHome) {
                WhyThisHomeSheet(onTune: {
                    showingIdentity = true
                })
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
                #endif
            }
            .sheet(item: $pendingReminder) { command in
                ReminderConfirmSheet(command: command) { pendingReminder = nil }
            }
            .sheet(item: $pendingAnswerQuery) { item in
                AnswerSheet(initialQuery: item.query)
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
            .sheet(isPresented: $showingTagManagement) {
                TagManagementSheet()
            }
            .sheet(isPresented: $showingTagFilter) {
                TagFilterSheet(selectedTagFilter: $selectedTagFilter)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                ScrollView {
                    CalendarLensView(notesByDayCount: notesByDayCount, selectedDay: $selectedDay)
                        .padding(.horizontal)
                }
                .navigationTitle("Pick a date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
                // Sync free note counter with actual database count
                let actualCount = visibleLibraryNotes.count
                UsageService.shared.syncNoteCount(actualCount: actualCount)
                // Run drift check (local-only, throttled inside the service)
                driftStatus = DriftDetector.shared.check(in: modelContext)

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

    // MARK: - 1. Greeting Bar

    /// True once the .purpose article has a compiled directive — used to gate the
    /// "Tuned for you" chip so pre-tune users don't see it.
    private var hasCompiledPurpose: Bool {
        guard let article = purposeArticles.first else { return false }
        return (article.thinkingEvolution?.isEmpty == false) || !article.summary.isEmpty
    }

    // MARK: - Lenses (one at a time, never stacked)

    /// Note counts keyed by start-of-day, for the calendar's dots.
    private var notesByDayCount: [Date: Int] {
        var out: [Date: Int] = [:]
        let calendar = Calendar.current
        for note in visibleLibraryNotes {
            let day = calendar.startOfDay(for: note.createdAt)
            out[day, default: 0] += 1
        }
        return out
    }

    /// Human label for the active date filter.
    private var dateFilterLabel: String {
        guard let selectedDay else { return "All dates" }
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Date filter as a dropdown, matching the category one. The month grid
    /// still exists for browsing, but it now opens in a half-height sheet
    /// instead of taking over the screen as a tab.
    private var dateFilterMenu: some View {
        Menu {
            Button {
                withAnimation { selectedDay = nil }
            } label: {
                if selectedDay == nil {
                    Label("All dates", systemImage: "checkmark")
                } else {
                    Text("All dates")
                }
            }

            Divider()

            Button {
                withAnimation { selectedDay = Calendar.current.startOfDay(for: Date()) }
            } label: { Text("Today") }

            Button {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                withAnimation {
                    selectedDay = yesterday.map { Calendar.current.startOfDay(for: $0) }
                }
            } label: { Text("Yesterday") }

            Divider()

            Button {
                showingDatePicker = true
            } label: { Label("Pick a date…", systemImage: "calendar") }
        } label: {
            HStack(spacing: 5) {
                Text(dateFilterLabel)
                    .font(EEONType.meta)
                    .foregroundStyle(selectedDay == nil ? Color.eeonTextSecondary : Color.eeonAccent)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selectedDay == nil ? Color.eeonTextSecondary : Color.eeonAccent)
            }
            .frame(minHeight: EEONLayout.minTarget)
            .contentShape(Rectangle())
        }
    }

    // Filter sheet removed 2026-08-25: category and day are the two dropdowns
    // on the feed header (conversationsHeader). Two controls, one job.

    // MARK: - Capture-stream header (category cards + week strip)

    /// Top categories by note count, as tappable cards. Built from the same
    /// auto-filing rule as notebooks: matched project name, else first topic.
    private var topCategories: [(String, Int)] {
        var counts: [String: Int] = [:]
        for note in visibleLibraryNotes {
            let topic = note.topics.first { !libraryIsSchemaSeedName($0) }
            let name = topic?.capitalized ?? "Unfiled"
            counts[name, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    private var categoryCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(topCategories, id: \.0) { name, count in
                    categoryCard(name: name, count: count)
                }
            }
            .padding(.horizontal)
        }
    }

    private func categoryCard(name: String, count: Int) -> some View {
        let isSelected = selectedCategory == name
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = isSelected ? nil : name
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.eeonAccent.opacity(0.85), Color("EEONAccentAI").opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(.white)
                    )
                Text(name)
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(count)")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .padding(EEONLayout.snug)
            .frame(minWidth: 112, maxWidth: 168, alignment: .leading)
            .background(isSelected ? Color.eeonAccent.opacity(0.18) : Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// The last 14 days as a scrollable strip — tap a day to filter the feed
    /// to it, tap again to clear.
    private var weekStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [Date] = (0..<14).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }.reversed()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        dayChip(day)
                            .id(day)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { proxy.scrollTo(today, anchor: .trailing) }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        let weekday = day.formatted(.dateTime.weekday(.narrow))
        let number = calendar.component(.day, from: day)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDay = isSelected ? nil : day
            }
        } label: {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.caption2)
                    .foregroundStyle(.eeonTextSecondary)
                Text("\(number)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.eeonAccent : Color.eeonTextPrimary))
            }
            .frame(width: 40, height: 52)
            .background(isSelected ? Color.eeonAccent : Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var feedTitle: String {
        switch feedMode {
        case .library: return "Library"
        case .tasks: return "Tasks"
        case .highlights: return "Highlights"
        }
    }

    private var feedSubtitle: String {
        switch feedMode {
        case .library:
            return libraryNoteCountLabel(visibleLibraryNotes.count)
        case .tasks:
            return openTaskCount == 1 ? "1 open task" : "\(openTaskCount) open tasks"
        case .highlights:
            return "Today"
        }
    }

    private var openTaskCount: Int {
        extractedActions.filter { !$0.isCompleted }.count
    }

    private var conversationsHeader: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            Picker("View", selection: $feedMode) {
                ForEach(FeedMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(alignment: .firstTextBaseline, spacing: EEONLayout.tight) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedTitle)
                        .font(.headline)
                        .foregroundStyle(.eeonTextPrimary)
                    Text(feedSubtitle)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                }

                Spacer(minLength: EEONLayout.tight)

                if feedMode == .library {
                    NavigationLink(destination: LibraryView()) {
                        Label("See All", systemImage: "rectangle.stack")
                            .font(EEONType.control)
                            .foregroundStyle(.eeonAccent)
                            .frame(minHeight: EEONLayout.minTarget)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var greetingBar: some View {
        HStack(alignment: .top) {
            // One line, not four. The greeting is orientation, not content —
            // it earns a single row or it doesn't run (2026-08-20 redesign).
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(EEONType.screenTitle)
                    .foregroundStyle(.eeonTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(todayDateString)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // Optional keyboard path into the same RAG system voice questions use.
            // Record remains the primary control; Ask is not a capture mode.
            NavigationLink(destination: AnswerSheet(navigationTitle: "Ask Library")) {
                Label("Ask", systemImage: "sparkle.magnifyingglass")
                    .font(EEONType.control)
                    .foregroundStyle(.eeonAccentAI)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.eeonCard)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask EEON")

            // Settings / avatar
            Button {
                showingSettings = true
            } label: {
                if authService.isSignedIn {
                    UserAvatarView(name: authService.displayName, size: 36)
                } else {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundStyle(.eeonTextSecondary)
                }
            }
        }
        .padding(.top, 8)
    }

    /// Small chip shown under the greeting once the user has a compiled .purpose article.
    /// Tapping opens the "Why this home?" sheet so the magic is legible, not opaque.
    private var tunedForYouChip: some View {
        Button {
            showingWhyThisHome = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .semibold))
                Text("Personalized")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(Color("EEONAccent"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color("EEONAccent").opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        if hour < 12 {
            timeGreeting = "Good morning"
        } else if hour < 17 {
            timeGreeting = "Good afternoon"
        } else {
            timeGreeting = "Good evening"
        }
        if authService.isSignedIn, let firstName = authService.firstNameForGreeting {
            return "\(timeGreeting), \(firstName)"
        }
        return timeGreeting
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // dailyBriefCard removed 2026-08-25 — it was dead code since the 08-19
    // home simplification. Today's brief renders as "Highlights" in the feed
    // dropdown (TodayHighlightsView).

    // MARK: - Free Notes Warning

    private func freeNotesWarning(remaining: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("\(remaining) free note\(remaining == 1 ? "" : "s") left")
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

    // MARK: - Knowledge Cards

    @ViewBuilder
    private var knowledgeCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Knowledge")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)

                Spacer()

                NavigationLink(destination: KnowledgeOverviewView()) {
                    HStack(spacing: 4) {
                        Text("\(visibleKnowledgeArticles.count) articles")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.eeonTextSecondary)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(visibleKnowledgeArticles.prefix(10)) { article in
                        NavigationLink(destination: KnowledgeArticleDetailView(article: article)) {
                            KnowledgeCardView(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
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

                Text(audioRecorder.recordingStatusText)
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

    // MARK: - 3. Bottom Bar (Mic / New Note / Search)

    private var bottomBar: some View {
        // Notepad simplification (2026-08-19, Shawn): the single mic button IS
        // the app — spoken questions still reach Ask/RAG via IntentClassifier.
        // The Ask and New Note pills were removed; TypeNoteSheet and
        // SourcePickerSheet remain wired (sheets + state) but currently have
        // no entry point on the bottom bar.
        HStack {
            Spacer()

            // A labelled pill, not a bare mic (2026-08-20). On iOS a
            // microphone glyph usually means "dictate into this field" —
            // voice INPUT — which is part of why recording read as something
            // you talk into. The label states the action and the state:
            // Record -> Stop, with the timer inline while running.
            Button(action: {
                toggleRecording()
            }) {
                HStack(spacing: EEONLayout.snug) {
                    if isTranscribing {
                        ProgressView()
                            .tint(.white)
                    } else if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "waveform")
                            .font(.body.weight(.semibold))
                    }

                    Text(isTranscribing ? "Working…" : isRecording ? "Stop" : "Record")
                        .font(EEONType.control)

                    if isRecording {
                        Text(audioRecorder.formattedTime)
                            .font(EEONType.control)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, EEONLayout.loose)
                .frame(minHeight: 56)
                .frame(maxWidth: .infinity)
                .background(isRecording ? recordingRed : Color.eeonAccent)
                .clipShape(Capsule())
            }
            .disabled(isTranscribing)
            .padding(.horizontal, EEONLayout.screenMargin)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            Color.eeonBackground
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.eeonTextPrimary.opacity(0.08), radius: 4, y: -2)
        )
    }

    // MARK: - Feed (search router)

    /// Feed entry point: the search field, then either search results or the
    /// normal tabbed browse feed depending on whether a query is active.
    private var noteFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal)
                .padding(.bottom, 8)

            if isSearching {
                searchResultsSection
            } else {
                browseFeed
            }
        }
    }

    /// Global keyword search input. Manual TextField (not `.searchable()`) so it
    /// fits AIHomeView's custom in-feed layout.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.eeonTextSecondary)

            TextField("Search Library", text: $searchQuery)
                .font(.subheadline)
                .foregroundStyle(.eeonTextPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.eeonTextSecondary)
                        .eeonTapTarget()
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.eeonCard)
        .cornerRadius(10)
    }

    /// Flat grid of keyword-search results, or an empty state. Replaces the
    /// tabbed browse feed while a query is active.
    @ViewBuilder
    private var searchResultsSection: some View {
        if searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.eeonTextTertiary)
                Text("No notes match \u{201C}\(activeSearchQuery)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(searchResults.count == 1 ? "1 result" : "\(searchResults.count) results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Single-column, notepad-style list (2026-08-19 simplification)
                let columns = [GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(searchResults) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            NoteFeedCard(note: note)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                note.isFavorite.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(
                                    note.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                                )
                            }

                            Button {
                                withAnimation {
                                    note.isArchived.toggle()
                                    try? modelContext.save()
                                }
                            } label: {
                                Label(
                                    note.isArchived ? "Unarchive" : "Archive",
                                    systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - 4. Note Feed (Tabbed, Grouped by Month)

    private var browseFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab row (All/Notebooks/AI/Favorites/Archive) + sort removed
            // 2026-08-19 (Shawn): home is search + the chronological notes,
            // nothing else. selectedTab stays .all; the other tab views are
            // unreachable but intact. NOTE: archived notes currently have no
            // UI surface — see session notes.

            // Tag chip strip removed 2026-08-19 — notepad simplification.
            // Tag filtering still available via the toolbar tag sheet.

            // Intent filter chips removed 2026-08-19 — notepad simplification.

            // Mood sparkline removed with the view-mode picker (2026-08-19).

            // Active tag-filter chip removed 2026-08-19 with its entry point.

            // Loose Ends lane removed from the All tab (2026-08-19
            // simplification): with 60+ open items it buried the
            // chronological feed entirely. Unresolved items still surface
            // via the AI tab and proactive alerts.

            // Library / Tasks / Highlights mode switch. Library is a summary
            // surface; the full chronological archive lives behind See All.
            conversationsHeader
                .padding(.bottom, 8)

            if feedMode == .tasks {
                TasksView(embedded: true)
            } else if feedMode == .highlights {
                TodayHighlightsView(
                    brief: todaysBrief,
                    isRefreshing: intelligenceService.isRefreshingDaily,
                    sessionBrief: intelligenceService.sessionBrief
                )
            } else if selectedTab == .ai {
                // AI-organized view
                AITabView(data: aiTabData, noteCount: visibleLibraryNotes.count)
            } else if librarySearchableNotes(notes).isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: emptyStateIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(.eeonTextTertiary)

                    Text(emptyStateTitle)
                        .font(.headline)
                        .foregroundStyle(.eeonTextSecondary)

                    Text(emptyStateSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, EEONLayout.screenMargin)
                .padding(.vertical, 40)
            } else {
                libraryHome
            }
        }
    }

    private var libraryHome: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            askLibraryCard
                .padding(.horizontal)

            if !libraryHomeCollections.isEmpty {
                libraryCollectionsSection
            }

            if !visibleLibraryNotes.isEmpty {
                recentLibrarySection
            }
        }
        .padding(.bottom, EEONLayout.standard)
    }

    private var askLibraryCard: some View {
        NavigationLink(destination: AnswerSheet(navigationTitle: "Ask Library")) {
            HStack(spacing: EEONLayout.standard) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(EEONType.body)
                    .foregroundStyle(.eeonAccentAI)
                    .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
                    .background(Circle().fill(Color.eeonAccentAI.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Library")
                        .font(EEONType.body)
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Notes, topics, and people")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(EEONType.badge)
                    .foregroundStyle(.eeonTextTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var libraryCollectionsSection: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            HomeSectionHeader("Collections", subtitle: "Auto-organized")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EEONLayout.snug) {
                    ForEach(libraryHomeCollections) { summary in
                        NavigationLink(destination: LibraryCollectionView(kind: summary.kind)) {
                            LibraryCollectionCompactCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recentLibrarySection: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Latest \(libraryPreviewNotes.count) of \(visibleLibraryNotes.count)")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                }

                Spacer()

                NavigationLink(destination: LibraryCollectionView(kind: .recent)) {
                    Text("See All")
                        .font(EEONType.control)
                        .foregroundStyle(.eeonAccent)
                        .frame(minHeight: EEONLayout.minTarget)
                }
            }
            .padding(.horizontal)

            LazyVStack(spacing: EEONLayout.snug) {
                ForEach(libraryPreviewNotes) { note in
                    noteFeedLink(note)
                }
            }
            .padding(.horizontal)
        }
    }

    private func noteFeedLink(_ note: Note) -> some View {
        NavigationLink(destination: NoteDetailView(note: note)) {
            NoteFeedCard(note: note)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                note.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    note.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                )
            }

            Button {
                withAnimation {
                    note.isArchived.toggle()
                    try? modelContext.save()
                }
            } label: {
                Label(
                    note.isArchived ? "Unarchive" : "Archive",
                    systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
        }
    }

    // MARK: - Personalization Hero Card

    /// Show the personalization hero card when the user hasn't set up their purpose yet.
    /// Once the purpose is compiled (article has non-empty directive), the card disappears.
    /// User can also dismiss manually; dismissals re-show after 14 days if still empty.
    private var showTuneHeroCard: Bool {
        let hasPurpose = (purposeArticles.first?.thinkingEvolution?.isEmpty == false)
            || (purposeArticles.first?.summary.isEmpty == false)
        if hasPurpose { return false }
        let dismissed = Date(timeIntervalSince1970: tuneBannerDismissedRaw)
        let daysSince = Calendar.current.dateComponents([.day], from: dismissed, to: Date()).day ?? 999
        return daysSince >= 14
    }

    private var tuneHeroCard: some View {
        Button {
            showingIdentity = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent").opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color("EEONAccent"))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personalize EEON")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Tell it who you are, what it's for, and what to remember for you.")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    tuneBannerDismissedRaw = Date().timeIntervalSince1970
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.eeonCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color("EEONAccent").opacity(0.35), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drift Banner

    /// Gentle prompt when the purpose article is stale or when recent captures
    /// don't match the declared role. Tap to re-tune; tap × to dismiss for 14 days.
    private var driftBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 36, height: 36)
                .background(Color.indigo.opacity(0.15))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(driftBannerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                Text(driftBannerBody)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showingIdentity = true
            } label: {
                Text("Update")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.indigo)
                    .cornerRadius(8)
            }
            Button {
                DriftDetector.shared.dismissBanner()
                withAnimation { driftStatus = .fresh }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.eeonTextSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.indigo.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var driftBannerTitle: String {
        switch driftStatus {
        case .stale: return "It's been a while since you tuned EEON"
        case .drifted: return "Your captures are telling a different story"
        case .fresh: return ""
        }
    }

    private var driftBannerBody: String {
        switch driftStatus {
        case .stale:
            return "EEON's lens is over a month old. Update it to match how you think today."
        case .drifted(let role, _):
            let roleName: String = {
                switch role {
                case .founder: return "founder"
                case .coach: return "coach"
                case .interpreter: return "dream interpreter"
                case .researcher: return "researcher"
                case .journaler: return "journaler"
                case .unknown: return "your lens"
                }
            }()
            return "You told EEON you're a \(roleName), but recent notes don't match. Want to re-tune?"
        case .fresh:
            return ""
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

    // MARK: - Layout-Driven Sections

    /// Active home layout — compiled by KnowledgeCompiler on the .purpose article,
    /// or the default layout if no purpose article has been compiled yet.
    private var activeLayout: HomeLayout {
        purposeArticles.first?.homeLayout ?? .default
    }

    /// Dispatch a section kind to its concrete view. Sections render themselves
    /// or disappear entirely when they have no data — so the user never sees an
    /// empty "Silent Projects" placeholder.
    @ViewBuilder
    private func sectionView(for kind: HomeSectionKind, section: HomeSection) -> some View {
        let t = section.effectiveTitle
        switch kind {
        case .priorityProjects:
            PriorityProjectsSection(projects: visibleProjects, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .silentProjects:
            SilentProjectsSection(projects: visibleProjects, title: t, rationale: section.rationale, staleDays: section.staleDaysThreshold ?? 9)
        case .openDecisions:
            OpenDecisionsSection(decisions: visibleExtractedDecisions, notes: visibleLibraryNotes, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .ideaInbox:
            IdeaInboxSection(notes: visibleLibraryNotes, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .clientRoster:
            ClientRosterSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 8)
        case .followUpsPerClient:
            FollowUpsPerClientSection(commitments: visibleExtractedCommitments, notes: visibleLibraryNotes, title: t, rationale: section.rationale, limit: section.limit ?? 6)
        case .recurringPatterns:
            RecurringPatternsSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 8)
        case .referenceResonance:
            ReferenceResonanceSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .knowledgeCarousel:
            if !visibleKnowledgeArticles.isEmpty { knowledgeCardsSection }
        case .recentNotes:
            noteFeed
        case .todayThree:
            EmptyView() // Today's 3 removed from home 2026-08-19
        case .openThreads:
            OpenThreadsSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .momentumPicture:
            MomentumPictureSection(
                title: t,
                rationale: section.rationale,
                focusItems: purposeArticles.first?.focusItems ?? [],
                notes: visibleLibraryNotes
            )
        case .emotionalToneArc:
            EmotionalToneArcSection(notes: visibleLibraryNotes, title: t, rationale: section.rationale, limit: section.limit ?? 14)
        case .activeInquiries:
            ActiveInquiriesSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        case .relationshipArcs:
            RelationshipArcsSection(articles: visibleKnowledgeArticles, title: t, rationale: section.rationale, limit: section.limit ?? 5)
        // Still stubs — captureHero is always rendered elsewhere; dailyBrief needs a DailyBrief model display;
        // contradictionLedger needs persisted lint results (deferred, see plan).
        case .captureHero, .contradictionLedger, .dailyBrief:
            EmptyView()
        }
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
    }

    private func transcribeAndSave(url: URL, isImport: Bool = false) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil, isImport: isImport)
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
                let reminderCommand = isImport ? nil : ReminderCommandParser.parse(transcript)

                // Classify intent: question routes to AnswerSheet, note saves as usual.
                // On classifier failure we fall back to .newNote — the safer default is
                // "your speech became a note" rather than swallowing it into a Q&A.
                let intent: IntentType
                if reminderCommand != nil {
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
                        let note = saveNote(transcript: transcript, isImport: isImport)
                        if let reminderCommand {
                            note.intentType = NoteIntent.reminder.rawValue
                            // Whatever the user decides in the sheet, the
                            // extraction pass must not push a second copy.
                            EventKitSyncService.shared.markHandledByCommand(note.id)
                            pendingReminder = reminderCommand
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    _ = saveNote(transcript: nil, pending: true, isImport: isImport)
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
    private func saveNote(transcript: String?, pending: Bool = false, isImport: Bool = false) -> Note {
        let note = Note(
            title: "",
            content: transcript ?? "",
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        modelContext.insert(note)
        if pending {
            note.transcriptionStatus = "pending"
        }
        if isImport {
            // Recorded some other time — the meeting happening at import
            // time has nothing to do with it.
            CalendarContextService.shared.excludeFromMatching(note.id)
        }

        // Track usage and store duration
        if let fileName = currentAudioFileName {
            trackRecordingUsage(fileName: fileName, for: note)
        }
        UsageService.shared.incrementNoteCount()
        try? modelContext.save()

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
                    }

                    await intelligenceService.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: allProjects,
                        tags: existingTags,
                        context: context
                    )

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

// MARK: - Note Feed Card (compact for 2-column grid)

private struct LibraryCollectionCompactCard: View {
    let summary: LibraryCollectionSummary

    var body: some View {
        HStack(spacing: EEONLayout.tight) {
            Image(systemName: summary.kind.icon)
                .font(EEONType.control)
                .foregroundStyle(summary.kind.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(summary.kind.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(summary.subtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(width: 148, alignment: .leading)
        .frame(minHeight: EEONLayout.minTarget)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }
}

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
                    NavigationLink(destination: LibraryCollectionView(kind: .recent)) {
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
