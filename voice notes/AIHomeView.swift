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

struct AIHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme

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

    @Binding var shouldStartRecording: Bool

    private var authService = AuthService.shared
    private var intelligenceService = IntelligenceService.shared

    init(shouldStartRecording: Binding<Bool>) {
        self._shouldStartRecording = shouldStartRecording
    }

    @State private var showingSettings = false
    @State private var showingAssistant = false
    @State private var showPaywall = false
    @State private var showSignIn = false

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Audio import state
    @State private var showingAudioImporter = false

    // Type note
    @State private var showingTypeNote = false

    // Navigation state
    @State private var navigateToNote: Note?
    @State private var navigateTransformType: AITransformType?

    // Daily brief expansion
    @State private var isBriefExpanded = false

    // Feed tabs & sorting
    enum FeedTab: String, CaseIterable {
        case all = "All"
        case ai = "AI"
        case favorites = "Favorites"
        case archive = "Archive"
    }
    @State private var selectedTab: FeedTab = .all
    @State private var sortNewestFirst = true
    @State private var selectedTagFilter: Tag?
    @State private var showingTagManagement = false
    @State private var showingTagFilter = false

    // Today's daily brief
    private var todaysBrief: DailyBrief? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyBriefs.first { $0.briefDate >= today }
    }

    /// Computed AI tab data (only built when AI tab is selected)
    private var aiTabData: AITabData {
        AITabBuilder.build(
            notes: notes,
            actions: extractedActions,
            commitments: extractedCommitments,
            decisions: extractedDecisions,
            people: mentionedPeople
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
        switch selectedTab {
        case .all:
            base = notes.filter { !$0.isArchived }
        case .ai:
            base = notes.filter { !$0.isArchived }
        case .favorites:
            base = notes.filter { $0.isFavorite && !$0.isArchived }
        case .archive:
            base = notes.filter { $0.isArchived }
        }
        // Apply tag filter if selected
        if let tag = selectedTagFilter {
            base = base.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        }
        if sortNewestFirst {
            return base // Already sorted newest first by @Query
        } else {
            return base.reversed()
        }
    }

    /// Group notes by month for section headers
    private var notesByMonth: [(String, [Note])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var grouped: [(String, [Note])] = []
        var currentMonth = ""
        var currentGroup: [Note] = []

        for note in filteredNotes {
            let month = formatter.string(from: note.createdAt)
            if month != currentMonth {
                if !currentGroup.isEmpty {
                    grouped.append((currentMonth, currentGroup))
                }
                currentMonth = month
                currentGroup = [note]
            } else {
                currentGroup.append(note)
            }
        }
        if !currentGroup.isEmpty {
            grouped.append((currentMonth, currentGroup))
        }
        return grouped
    }

    private var emptyStateIcon: String {
        switch selectedTab {
        case .all: return "waveform.circle"
        case .ai: return "sparkles"
        case .favorites: return "heart.circle"
        case .archive: return "archivebox"
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .all: return "Your memory starts here"
        case .ai: return "Almost there"
        case .favorites: return "Your greatest hits"
        case .archive: return "Clean slate"
        }
    }

    private var emptyStateSubtitle: String {
        switch selectedTab {
        case .all: return "Hit the mic and say what's on your mind. EEON will remember it for you."
        case .ai: return "Record a few more notes and EEON will start connecting the dots."
        case .favorites: return "Tap the heart on any note to pin it here."
        case .archive: return "Archived notes live here. Out of sight, never out of reach."
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eeonBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !authService.isSignedIn {
                        signedOutView
                    } else {
                        // Main scrollable content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // 1. Greeting bar
                                greetingBar
                                    .padding(.horizontal)

                                // Daily brief removed — AI tab handles organization

                                // Free tier warning
                                if authService.isSignedIn && !UsageService.shared.isPro {
                                    let remaining = UsageService.shared.freeNotesRemaining
                                    if remaining <= 2 && remaining > 0 {
                                        freeNotesWarning(remaining: remaining)
                                            .padding(.horizontal)
                                    }
                                }

                                // 3. Note feed with tabs
                                noteFeed

                                // Spacer for bottom bar
                                Color.clear.frame(height: 90)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }

                // Recording overlay
                if isRecording {
                    HomeRecordingOverlay(
                        onStop: stopRecording,
                        onCancel: cancelRecording,
                        audioRecorder: audioRecorder
                    )
                }

                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAssistant) {
                AssistantView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onDismiss: { showPaywall = false })
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
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
            .onAppear {
                trackSession()
                // Sync free note counter with actual database count
                let actualCount = notes.filter { !$0.isArchived }.count
                UsageService.shared.syncNoteCount(actualCount: actualCount)
            }
        }
    }

    // MARK: - 1. Greeting Bar

    private var greetingBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)

                Text(todayDateString)
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer()

            // Tag filter
            Button {
                showingTagFilter = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .padding(.trailing, 8)

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
        return timeGreeting
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - 2. Daily Brief Card (Collapsible, Executive Summary)

    private var dailyBriefCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isBriefExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    if intelligenceService.isRefreshingDaily {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.blue)
                            Text("Preparing your brief...")
                                .font(.subheadline)
                                .foregroundStyle(.eeonTextSecondary)
                        }
                    } else {
                        Text("Daily Brief")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.eeonTextPrimary)
                    }

                    Spacer()

                    if !intelligenceService.isRefreshingDaily {
                        Image(systemName: isBriefExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // Collapsed: short executive summary (2-3 lines)
            if !isBriefExpanded && !intelligenceService.isRefreshingDaily {
                if let brief = todaysBrief, !brief.whatMattersToday.isEmpty {
                    Text(brief.whatMattersToday)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextPrimary.opacity(0.8))
                        .lineLimit(3)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }

            // Expanded: full executive brief
            if isBriefExpanded, let brief = todaysBrief {
                Divider()
                    .background(Color.eeonDivider)

                VStack(alignment: .leading, spacing: 10) {
                    // Executive summary text
                    if !brief.whatMattersToday.isEmpty {
                        Text(brief.whatMattersToday)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)
                            .lineSpacing(3)
                    }

                    // Warnings as a compact alert line
                    if !brief.warnings.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(brief.warnings.prefix(2).map(\.content).joined(separator: " \u{00B7} "))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color("EEONAccent").opacity(0.12), Color("EEONAccentAI").opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

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

    // MARK: - 3. Bottom Bar (Write / Mic / Search)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Write button (left)
            Button {
                showingTypeNote = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity)

            // Mic button (center, elevated)
            Button(action: {
                toggleRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.eeonAccent)
                        .frame(width: 64, height: 64)

                    if isTranscribing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isTranscribing)
            .offset(y: -6)

            // Search button (right)
            Button {
                showingAssistant = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background(
            Color.eeonBackground
                .shadow(color: Color.eeonTextPrimary.opacity(0.08), radius: 4, y: -2)
        )
    }

    // MARK: - 4. Note Feed (Tabbed, Grouped by Month)

    private var noteFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar + sort button
            HStack(spacing: 0) {
                ForEach(FeedTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .eeonTextPrimary : .eeonTextSecondary)

                            Rectangle()
                                .fill(selectedTab == tab ? Color.eeonAccent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Sort toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sortNewestFirst.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Tag chip strip (hidden on AI tab and when no tags)
            if selectedTab != .ai && !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Show tags sorted by note count, top 12
                        ForEach(sortedTags.prefix(12)) { tag in
                            Button {
                                if selectedTagFilter?.id == tag.id {
                                    selectedTagFilter = nil
                                } else {
                                    selectedTagFilter = tag
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tag.name)
                                    Text("(\(tagNoteCount(tag)))")
                                        .font(.caption2)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedTagFilter?.id == tag.id
                                        ? Color.eeonAccent
                                        : Color.eeonCard
                                )
                                .foregroundStyle(
                                    selectedTagFilter?.id == tag.id
                                        ? .white
                                        : .eeonTextSecondary
                                )
                                .cornerRadius(16)
                            }
                        }

                        // "+N more" pill if there are more than 12 tags
                        if sortedTags.count > 12 {
                            Button {
                                showingTagFilter = true
                            } label: {
                                Text("+\(sortedTags.count - 12) more")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.eeonCard)
                                    .foregroundStyle(.eeonTextTertiary)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 4)
            }

            // Active tag filter chip
            if let tag = selectedTagFilter {
                HStack(spacing: 6) {
                    Text(tag.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                    Button {
                        withAnimation { selectedTagFilter = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if selectedTab == .ai {
                // AI-organized view
                AITabView(data: aiTabData, noteCount: notes.filter { !$0.isArchived }.count)
            } else if filteredNotes.isEmpty {
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Grouped by month
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(notesByMonth, id: \.0) { month, monthNotes in
                        Section {
                            // 2-column grid
                            let columns = [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ]
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(monthNotes) { note in
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
                        } header: {
                            Text(month)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.eeonTextSecondary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
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
                    Button {
                        showSignIn = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Sign In to Get Started")
                                .font(.headline)
                        }
                        .foregroundStyle(.eeonTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.eeonCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.eeonDivider, lineWidth: 1)
                                )
                        )
                    }
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
        if isRecording {
            stopRecording()
        } else {
            if !authService.isSignedIn {
                showSignIn = true
                return
            }
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
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func stopRecording() {
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
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        currentAudioFileName = nil
        isRecording = false
    }

    private func transcribeAndSave(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil)
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

                await MainActor.run {
                    saveNote(transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil, pending: true)
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
            transcribeAndSave(url: destinationURL)
        } else {
            errorMessage = "Could not read audio file"
            showingError = true
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    private func saveNote(transcript: String?, pending: Bool = false) {
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
                    let title = try await SummaryService.generateTitle(for: transcript, apiKey: apiKey)
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

        if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let allProjects = projects

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
                } catch {
                    print("Error processing typed note: \(error)")
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

struct NoteFeedCard: View {
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

            // Date
            Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.eeonTextSecondary)

            // 1-line preview
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.eeonTextTertiary)
                    .lineLimit(2)
            }

            // Intent icon or first topic chip
            HStack(spacing: 4) {
                if note.intent != .unknown {
                    Image(systemName: note.intent.icon)
                        .font(.caption2)
                        .foregroundStyle(note.intent.color)
                }

                if let firstTopic = note.topics.first {
                    Text(firstTopic)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                        .lineLimit(1)
                }

                Spacer()

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
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Preview

#Preview {
    AIHomeView(shouldStartRecording: .constant(false))
        .modelContainer(for: [Note.self, Tag.self, Project.self, DailyBrief.self, MentionedPerson.self, ExtractedURL.self, ExtractedCommitment.self], inMemory: true)
}
