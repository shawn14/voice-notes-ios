//
//  HomeView.swift
//  voice notes
//
//  All Notes home page with filter tabs
//  Clean Wave-style design
//

import SwiftUI
import SwiftData
import UIKit
import AVFoundation
import PhotosUI

// MARK: - Filter Options

enum NoteFilter: String, CaseIterable {
    case all = "All Notes"
    case projects = "Projects"
    case favorites = "Favorites"
    case recent = "Recent"
    case people = "People"

    var icon: String {
        switch self {
        case .all: return "waveform"
        case .projects: return "folder"
        case .favorites: return "star"
        case .recent: return "clock"
        case .people: return "person.2"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var tags: [Tag]
    @Query(sort: \KanbanItem.createdAt, order: .reverse) private var kanbanItems: [KanbanItem]
    @Query private var kanbanMovements: [KanbanMovement]
    @Query private var extractedActions: [ExtractedAction]
    @Query private var extractedCommitments: [ExtractedCommitment]
    @Query private var unresolvedItems: [UnresolvedItem]
    // Note: @Query loads all records. For large datasets, consider using FetchDescriptor with fetchLimit
    // in a manual fetch instead. Currently limited by SwiftData macro syntax.
    @Query(sort: \DailyBrief.briefDate, order: .reverse) private var dailyBriefs: [DailyBrief]

    // Observe AuthService for name changes
    private var authService = AuthService.shared

    // Intelligence service
    private var intelligenceService = IntelligenceService.shared

    @State private var searchText = ""
    @State private var selectedFilter: NoteFilter = .all
    @State private var showingSettings = false
    @State private var showingAssistant = false
    @State private var selectedProject: Project?

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // First-run clarity flow
    @State private var showFirstClarity = false
    @State private var showExtractFallback = false
    @State private var newlyCreatedNote: Note?
    @State private var showPaywall = false
    @State private var showSignIn = false
    @State private var showingAddProjectFromMain = false
    @State private var newProjectName = ""

    // Tag filtering
    @State private var selectedTag: Tag?

    // Photo attachment
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    // People view
    @State private var showingPeopleView = false

    // Filtered notes based on search and filter
    private var filteredNotes: [Note] {
        // Don't show notes when signed out - they'll reappear on sign in
        guard authService.isSignedIn else {
            return []
        }

        var result = notes

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply category filter
        switch selectedFilter {
        case .all:
            break // Show all
        case .projects:
            result = result.filter { $0.projectId != nil }
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .recent:
            // Show notes from last 7 days
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { $0.createdAt >= weekAgo }
        case .people:
            // People filter opens PeopleView, so show all here
            break
        }

        // Apply tag filter
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains { $0.id == tag.id } }
        }

        return result
    }

    // Today's daily brief (if available)
    private var todaysBrief: DailyBrief? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyBriefs.first { $0.briefDate >= today }
    }

    // Retry daily brief generation
    private func retryDailyBrief() {
        Task {
            await intelligenceService.regenerateDailyBrief(
                context: modelContext,
                notes: notes,
                projects: projects,
                items: kanbanItems,
                movements: kanbanMovements,
                actions: extractedActions,
                commitments: extractedCommitments,
                unresolved: unresolvedItems
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with assistant and settings
                    HStack {
                        Button {
                            showingAssistant = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                        }

                        Spacer()

                        Button {
                            showingSettings = true
                        } label: {
                            if authService.isSignedIn {
                                UserAvatarView(name: authService.displayName, size: 36)
                            } else {
                                Image(systemName: "person.circle")
                                    .font(.title2)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Title
                    HStack {
                        Text("All Notes")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Daily Brief Header (only show when signed in)
                    if authService.isSignedIn {
                        DailyBriefHeader(
                            brief: todaysBrief,
                            sessionBrief: intelligenceService.sessionBrief,
                            isGenerating: intelligenceService.isRefreshingDaily,
                            error: intelligenceService.dailyBriefError,
                            onRetry: retryDailyBrief
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Usage warning (show when 2 or fewer free notes remaining)
                    if authService.isSignedIn && !UsageService.shared.isPro {
                        let remaining = UsageService.shared.freeNotesRemaining
                        if remaining <= 2 && remaining > 0 {
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
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    }

                    // Background processing indicator
                    if intelligenceService.isRefreshingDaily {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.blue)
                            Text("Generating daily brief...")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }

                    // Search bar (only show when signed in)
                    if authService.isSignedIn {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.gray)
                            TextField("Search", text: $searchText)
                                .foregroundStyle(.white)
                        }
                        .padding(12)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }

                    // Filter tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(NoteFilter.allCases, id: \.self) { filter in
                                FilterTab(
                                    title: filter.rawValue,
                                    isSelected: selectedFilter == filter
                                ) {
                                    if filter == .people {
                                        showingPeopleView = true
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedFilter = filter
                                        }
                                    }
                                }
                            }

                            // Projects quick access
                            if projects.filter({ !$0.isArchived }).isEmpty {
                                // Prompt to create first project
                                Button(action: { showingAddProjectFromMain = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption.weight(.semibold))
                                        Text("Add Project")
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue.opacity(0.4))
                                    .cornerRadius(20)
                                }
                            } else {
                                ForEach(projects.filter { !$0.isArchived }.prefix(3)) { project in
                                    NavigationLink(value: project) {
                                        Text(project.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(Color(.systemGray5).opacity(0.3))
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                    }

                    // Tag filter indicator
                    if let tag = selectedTag {
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)

                            Text(tag.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTag = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Notes list
                    if filteredNotes.isEmpty {
                        Spacer()
                        if !authService.isSignedIn {
                            // Signed out - prompt to sign in
                            VStack(spacing: 16) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.blue)
                                Text("Sign in to see your notes")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("Your notes are safely stored in iCloud")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                                Button(action: { showSignIn = true }) {
                                    Text("Sign In")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 8)
                            }
                        } else {
                            // Signed in but no notes
                            VStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.gray)
                                Text("No notes yet")
                                    .font(.headline)
                                    .foregroundStyle(.gray)
                                Text("Tap the record button to get started")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray.opacity(0.7))
                            }
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredNotes) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    HomeNoteRow(note: note) { tag in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedTag = tag
                                        }
                                    }
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.2))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        note.isFavorite.toggle()
                                    } label: {
                                        Label(
                                            note.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                                        )
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .padding(.bottom, 80) // Space for bottom bar
                    }
                }

                // Bottom tab bar
                VStack {
                    Spacer()
                    HomeBottomBar(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        onRecord: toggleRecording
                    )
                }

                // Sign in button (bottom right) - shows when not signed in and notes exist
                // (Don't show when empty state sign-in prompt is visible)
                if !authService.isSignedIn && !isRecording && !isTranscribing && !filteredNotes.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showSignIn = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("Sign In")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 100)
                        }
                    }
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAssistant) {
                AssistantView()
            }
            .sheet(isPresented: $showSignIn) {
                SignInView(onSignedIn: {
                    showSignIn = false
                })
            }
            .sheet(isPresented: $showFirstClarity) {
                if let note = newlyCreatedNote {
                    FirstClarityView(note: note, onComplete: {
                        showFirstClarity = false
                        newlyCreatedNote = nil
                    })
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onDismiss: {
                    showPaywall = false
                })
            }
            .sheet(isPresented: $showingPeopleView) {
                PeopleView()
            }
            .alert("Ready to understand", isPresented: $showExtractFallback) {
                Button("See what I can do") {
                    // Navigate to NoteEditorView with the note
                    // The user can tap Extract there
                    showExtractFallback = false
                }
                Button("Later", role: .cancel) {
                    showExtractFallback = false
                    newlyCreatedNote = nil
                }
            } message: {
                Text("Tap Extract to turn this thought into action.")
            }
            .alert("New Project", isPresented: $showingAddProjectFromMain) {
                TextField("Project name", text: $newProjectName)
                Button("Create") {
                    if !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty {
                        let project = Project(name: newProjectName.trimmingCharacters(in: .whitespaces))
                        modelContext.insert(project)
                        newProjectName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newProjectName = ""
                }
            } message: {
                Text("Projects help organize related notes together.")
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            processSelectedPhoto(newItem)
        }
    }

    // MARK: - Photo Processing

    private func processSelectedPhoto(_ item: PhotosPickerItem) {
        // Must be signed in
        if !authService.isSignedIn {
            showSignIn = true
            selectedPhotoItem = nil
            return
        }

        // Check usage
        if !UsageService.shared.canCreateNote {
            showPaywall = true
            selectedPhotoItem = nil
            return
        }

        isProcessingPhoto = true

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        errorMessage = "Could not load image"
                        showingError = true
                        isProcessingPhoto = false
                        selectedPhotoItem = nil
                    }
                    return
                }

                await MainActor.run {
                    createNoteWithImage(image)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to process image: \(error.localizedDescription)"
                    showingError = true
                    isProcessingPhoto = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func createNoteWithImage(_ image: UIImage) {
        let noteId = UUID()

        do {
            let fileName = try ImageService.saveImage(image, noteId: noteId)

            let note = Note(
                title: "Photo Note",
                content: ""
            )
            note.addImageFileName(fileName)
            modelContext.insert(note)

            // Track usage
            UsageService.shared.incrementNoteCount()

            // Try to extract text from image (OCR)
            Task {
                do {
                    let extractedText = try await ImageService.extractText(from: image)
                    if !extractedText.isEmpty {
                        await MainActor.run {
                            note.content = extractedText
                            note.title = String(extractedText.prefix(50))
                        }

                        // Process with AI if we got text
                        if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                            let title = try await generateTitle(for: extractedText, apiKey: apiKey)
                            await MainActor.run {
                                note.title = title
                            }

                            // Tier 1 processing
                            await intelligenceService.processNoteSave(
                                note: note,
                                transcript: extractedText,
                                projects: projects,
                                tags: tags,
                                context: modelContext
                            )
                        }
                    }
                } catch {
                    print("OCR failed: \(error)")
                }
            }

            isProcessingPhoto = false
            selectedPhotoItem = nil

        } catch {
            errorMessage = "Failed to save image: \(error.localizedDescription)"
            showingError = true
            isProcessingPhoto = false
            selectedPhotoItem = nil
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            // Must be signed in to record
            if !authService.isSignedIn {
                showSignIn = true
                return
            }
            // Check if user can create more notes
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

    private func deleteNote(_ note: Note) {
        note.deleteAudioFile()
        note.deleteImageFiles()
        modelContext.delete(note)
    }

    private func transcribeAndSave(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil)
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                let transcript = try await service.transcribe(audioURL: url)

                await MainActor.run {
                    saveNote(transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func saveNote(transcript: String?) {
        let note = Note(
            title: "",
            content: transcript ?? "",
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        modelContext.insert(note)

        // Track usage and store duration
        if let fileName = currentAudioFileName {
            trackRecordingUsage(fileName: fileName, for: note)
        }
        UsageService.shared.incrementNoteCount()

        // Force save to persist immediately
        try? modelContext.save()

        // Check if this is the first note with transcript -> auto-extract
        let isFirstNote = UsageService.shared.isFirstNote
        if isFirstNote && transcript != nil && !transcript!.isEmpty {
            UsageService.shared.isFirstNote = false

            if UsageService.shared.canExtract {
                autoExtractAndShowClarity(note: note, transcript: transcript!)
            }
        }

        // AI processing for title, tags, and Tier 1 intelligence
        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let context = modelContext
            let allProjects = projects

            Task {
                do {
                    // Generate title
                    let title = try await generateTitle(for: transcript, apiKey: apiKey)

                    // Extract tags
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: transcript)

                    await MainActor.run {
                        note.title = title

                        // Apply tags
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
                    }

                    // Tier 1: Process note with IntelligenceService
                    await intelligenceService.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: allProjects,
                        tags: existingTags,
                        context: context
                    )
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

            // Still update status counters for notes without transcripts
            StatusCounters.shared.incrementNotesToday()
            StatusCounters.shared.markSessionStale()
        }
    }

    // MARK: - Auto-Extract for First Note

    private func autoExtractAndShowClarity(note: Note, transcript: String) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            // No API key - show fallback
            newlyCreatedNote = note
            showExtractFallback = true
            return
        }

        Task {
            do {
                let result = try await SummaryService.extractIntent(text: transcript, apiKey: apiKey)

                await MainActor.run {
                    // Apply extraction to note
                    note.intentType = result.intent
                    note.intentConfidence = result.intentConfidence

                    if let subject = result.subject {
                        note.extractedSubject = ExtractedSubject(
                            topic: subject.topic,
                            action: subject.action
                        )
                    }

                    note.suggestedNextStep = result.nextStep
                    note.nextStepTypeRaw = result.nextStepType
                    note.missingInfo = result.missingInfo.map {
                        MissingInfoItem(field: $0.field, description: $0.description)
                    }
                    note.inferredProjectName = result.inferredProject

                    // Auto-match inferred project to existing projects
                    if let inferredName = result.inferredProject, !inferredName.isEmpty {
                        let textToMatch = "\(inferredName) \(note.content)"
                        if let match = ProjectMatcher.findMatch(for: textToMatch, in: projects) {
                            note.projectId = match.project.id
                        }
                    }

                    // Track usage
                    UsageService.shared.useExtraction()

                    // Show FirstClarityView
                    newlyCreatedNote = note
                    showFirstClarity = true
                }
            } catch {
                // FAILURE GUARDRAIL: Don't silently fail
                await MainActor.run {
                    newlyCreatedNote = note
                    showExtractFallback = true
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
                    // Store duration on note
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

    private func generateTitle(for text: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
                ["role": "user", "content": text]
            ],
            "max_tokens": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Voice Note"
    }
}

// MARK: - Filter Tab

struct FilterTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color(.systemGray5).opacity(0.3))
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Note Row

struct HomeNoteRow: View {
    let note: Note
    var onTagTap: ((Tag) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            // Intent-colored icon or first image thumbnail
            if let firstImageFileName = note.imageFileNames.first,
               let thumbnail = ImageService.loadImage(fileName: firstImageFileName) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .cornerRadius(12)
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(note.intent.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: note.hasAudio ? "mic.fill" : "note.text")
                        .font(.title2)
                        .foregroundStyle(note.intent.color)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(note.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.gray)

                    // Duration (if audio)
                    if note.hasAudio {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text(formattedDuration(note.audioDuration))
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    // Intent badge
                    if note.intent != .unknown {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: note.intent.icon)
                                .font(.caption2)
                            Text(note.intentType)
                                .font(.caption2)
                        }
                        .foregroundStyle(note.intent.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(note.intent.color.opacity(0.1))
                        .cornerRadius(4)
                    }
                }

                // Tags and People
                if !note.tags.isEmpty || note.hasMentionedPeople {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // Tags
                            ForEach(note.tags, id: \.id) { tag in
                                Button {
                                    onTagTap?(tag)
                                } label: {
                                    Text(tag.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }

                            // People pills (first 3)
                            ForEach(note.mentionedPeople.prefix(3), id: \.self) { name in
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 8))
                                    Text(name)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(6)
                            }

                            // Overflow indicator
                            if note.mentionedPeople.count > 3 {
                                Text("+\(note.mentionedPeople.count - 3)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.15))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }

                // Next step with quick resolve
                if let nextStep = note.suggestedNextStep, !nextStep.isEmpty, !note.isNextStepResolved {
                    HStack(spacing: 8) {
                        Image(systemName: note.nextStepType.icon)
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text(nextStep)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            note.resolveNextStep(with: "Done")
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
    }

    private func formattedDuration(_ seconds: Double?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "--:--" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Bottom Record Button

struct HomeBottomBar: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let onRecord: () -> Void

    var body: some View {
        // Record button only
        Button(action: onRecord) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 72, height: 72)

                if isTranscribing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: isRecording ? 24 : 28, height: isRecording ? 24 : 28)
                }
            }
            .shadow(color: .red.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(isTranscribing)
        .padding(.bottom, 30)
    }
}

// MARK: - User Avatar View

struct UserAvatarView: View {
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            // First letter of first and last name
            let first = components.first?.prefix(1) ?? ""
            let last = components.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            // Just first letter if single name
            return String(first.prefix(1)).uppercased()
        }
        return "U"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Recording Overlay

struct HomeRecordingOverlay: View {
    let onStop: () -> Void
    let onCancel: () -> Void
    let audioRecorder: AudioRecorder

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Pulsing mic icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 100, height: 100)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }

                Text(audioRecorder.formattedTime)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)

                Text("Recording...")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 60) {
                    Button(action: onCancel) {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.gray)
                            Text("Cancel")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                    }

                    Button(action: onStop) {
                        VStack(spacing: 8) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                            Text("Stop")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Transcribing Overlay

struct HomeTranscribingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated sparkles icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 100, height: 100)

                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)
                }

                Text("Understanding your note...")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)

                Text("Transcribing and finding insights")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
        }
    }
}

// MARK: - Projects List View (placeholder for navigation)

struct ProjectsListView: View {
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    private func colorFor(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .blue
        case "pink": return .pink
        case "yellow": return .yellow
        default: return .blue
        }
    }

    var body: some View {
        List(projects) { project in
            NavigationLink(destination: ProjectDetailView(project: project)) {
                HStack {
                    Image(systemName: project.icon)
                        .foregroundStyle(colorFor(project.colorName))
                    Text(project.name)
                }
            }
        }
        .navigationTitle("Projects")
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var notes: [Note]
    @Query private var dailyBriefs: [DailyBrief]
    @Query private var kanbanItems: [KanbanItem]

    // Observe AuthService for reactive updates
    private var authService = AuthService.shared

    @State private var showingAddProject = false
    @State private var newProjectName = ""
    @State private var showingShareSheet = false
    @State private var showingPaywall = false
    @State private var showingResetConfirm = false
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteAllDataConfirm = false
    @State private var showingEditName = false
    @State private var editedName = ""
    @State private var showSignIn = false

    private let usage = UsageService.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Usage Section
                Section {
                    UsageSectionContent(usage: usage, noteCount: notes.count)
                } header: {
                    Text("Usage")
                }

                // MARK: - Account Section
                Section {
                    // Account info with edit button
                    Button {
                        editedName = authService.userName ?? ""
                        showingEditName = true
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: authService.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                if authService.isSignedIn {
                                    Text(authService.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let email = authService.userEmail {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Not signed in")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("Local data only")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if authService.isSignedIn {
                                Text("Edit")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    // Current level
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(usage.isPro ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: usage.isPro ? "sparkles" : "star.fill")
                                .foregroundStyle(usage.isPro ? .blue : .orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan: \(usage.isPro ? "Pro" : "Free")")
                                .font(.body.weight(.medium))
                            if usage.isPro {
                                Text("All features unlocked")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Upgrade for unlimited AI")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !usage.isPro {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)

                    // Upgrade option (only show if not Pro)
                    if !usage.isPro {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                    .frame(width: 44)

                                Text("Upgrade to Pro")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text("$9.99/mo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    // Version
                    HStack(spacing: 16) {
                        Image(systemName: "globe")
                            .foregroundStyle(.blue)
                            .frame(width: 44)

                        Text(AppInfo.versionString)
                            .font(.body)

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Share
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                                .frame(width: 44)

                            Text("Share Voice Notes")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    // Reset to Free (for Pro users or testing)
                    if usage.isPro {
                        Button {
                            showingResetConfirm = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .foregroundStyle(.orange)
                                    .frame(width: 44)

                                Text("Downgrade to Free")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    // Sign In / Sign Out (conditional)
                    if authService.isSignedIn {
                        Button {
                            showingSignOutConfirm = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(.primary)
                                    .frame(width: 44)

                                Text("Sign Out")
                                    .font(.body)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            showSignIn = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundStyle(.blue)
                                    .frame(width: 44)

                                Text("Sign In")
                                    .font(.body)
                                    .foregroundStyle(.blue)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Account")
                }

                // MARK: - Projects Section
                Section {
                    if projects.isEmpty {
                        // Empty state for no projects
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue.opacity(0.7))

                            Text("Organize your notes")
                                .font(.headline)

                            Text("Projects help group related notes together. AI can auto-assign notes to projects based on content.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: { showingAddProject = true }) {
                                Label("Create Your First Project", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 16)
                    } else {
                        ForEach(projects) { project in
                            NavigationLink(destination: ProjectEditView(project: project)) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(projectColor(project.colorName).opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: project.icon)
                                            .foregroundStyle(projectColor(project.colorName))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.body)
                                        if !project.aliases.isEmpty {
                                            Text("\(project.aliases.count) aliases")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteProjects)

                        Button(action: { showingAddProject = true }) {
                            HStack(spacing: 16) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                                    .frame(width: 44)

                                Text("Add Project")
                                    .font(.body)
                                    .foregroundStyle(.blue)

                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Projects")
                }

                // MARK: - Preferences Section
                Section {
                    NavigationLink {
                        Text("Audio Quality Settings")
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "waveform.circle")
                                .foregroundStyle(.blue)
                                .frame(width: 44)

                            Text("Audio Quality")
                                .font(.body)

                            Spacer()

                            Text("High")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "globe")
                                .foregroundStyle(.green)
                                .frame(width: 44)

                            Text("Transcription Language")
                                .font(.body)

                            Spacer()

                            Text(LanguageSettings.shared.selectedLanguage.displayName)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Preferences")
                }

                // MARK: - Support Section
                Section {
                    Button {
                        if let url = URL(string: "mailto:support@eeon.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "envelope")
                                .foregroundStyle(.blue)
                                .frame(width: 44)

                            Text("Contact Support")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    Button {
                        if let url = URL(string: "https://eeon.com/privacy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "hand.raised")
                                .foregroundStyle(.orange)
                                .frame(width: 44)

                            Text("Privacy Policy")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    Button {
                        if let url = URL(string: "https://eeon.com/terms") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.blue)
                                .frame(width: 44)

                            Text("Terms of Use")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Support")
                }

                // MARK: - Developer Section (DEBUG only)
                #if DEBUG
                Section {
                    Button {
                        // Reset onboarding flags
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                        UserDefaults.standard.set(false, forKey: "hasSeenOnboardingPaywall")
                        // Force app restart by crashing (development only)
                        fatalError("Restart app to see onboarding")
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.purple)
                                .frame(width: 44)

                            Text("Reset Onboarding")
                                .font(.body)
                                .foregroundStyle(.purple)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)

                    Button {
                        // Reset usage counters
                        UsageService.shared.noteCount = 0
                        UsageService.shared.hasShownPaywall = false
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "gobackward")
                                .foregroundStyle(.orange)
                                .frame(width: 44)

                            Text("Reset Free Notes Counter")
                                .font(.body)
                                .foregroundStyle(.orange)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug tools for testing. Reset Onboarding will restart the app.")
                        .font(.caption)
                }
                #endif

                // MARK: - Danger Zone (at bottom)
                Section {
                    Button {
                        showingDeleteAllDataConfirm = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                                .frame(width: 44)

                            Text("Delete Account & Data")
                                .font(.body)
                                .foregroundStyle(.red)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will permanently delete your account, all notes, projects, and associated data from this device and iCloud. This action cannot be undone.")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Project", isPresented: $showingAddProject) {
                TextField("Project name", text: $newProjectName)
                Button("Cancel", role: .cancel) { newProjectName = "" }
                Button("Create") {
                    if !newProjectName.isEmpty {
                        let project = Project(name: newProjectName)
                        modelContext.insert(project)
                        newProjectName = ""
                    }
                }
            }
            .alert("Edit Name", isPresented: $showingEditName) {
                TextField("Your name", text: $editedName)
                Button("Cancel", role: .cancel) { editedName = "" }
                Button("Save") {
                    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        authService.userName = trimmed
                    }
                    editedName = ""
                }
            } message: {
                Text("This name will be shown in the app and used for your avatar initials.")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [URL(string: "https://apps.apple.com/app/voice-notes")!])
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(onDismiss: {
                    showingPaywall = false
                })
            }
            .sheet(isPresented: $showSignIn) {
                SignInView(onSignedIn: {
                    showSignIn = false
                })
            }
            .confirmationDialog("Downgrade to Free?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                Button("Downgrade", role: .destructive) {
                    UsageService.shared.downgradeToFree()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will lose access to unlimited extractions and resolutions.")
            }
            .confirmationDialog("Sign Out?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out") {
                    signOutOnly()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your notes will be kept and synced with iCloud. You can sign back in anytime.")
            }
            .confirmationDialog("Delete Account & Data?", isPresented: $showingDeleteAllDataConfirm, titleVisibility: .visible) {
                Button("Delete Account & Data", role: .destructive) {
                    deleteAllDataAndSignOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your account and all associated data including notes, projects, and recordings. This action cannot be undone.")
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(projects[index])
        }
    }

    private func projectColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .blue
        case "pink": return .pink
        default: return .blue
        }
    }

    private func signOutOnly() {
        // Just sign out - keep all data locally and in iCloud
        AuthService.shared.signOut()

        // Reset onboarding flag to show sign in screen again
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")

        // Dismiss settings
        dismiss()
    }

    private func deleteAllDataAndSignOut() {
        // Delete all notes and their audio files
        for note in notes {
            note.deleteAudioFile()
            modelContext.delete(note)
        }

        // Delete all projects
        for project in projects {
            modelContext.delete(project)
        }

        // Delete all daily briefs
        for brief in dailyBriefs {
            modelContext.delete(brief)
        }

        // Delete all kanban items
        for item in kanbanItems {
            modelContext.delete(item)
        }

        // Clear intelligence caches
        SessionBrief.clearCache()
        StatusCounters.shared.reset()

        // Clear all user data including name/email and usage
        AuthService.shared.clearAllUserData()

        // Reset onboarding flag to show sign in screen again
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")

        // Dismiss settings
        dismiss()
    }
}

// MARK: - Usage Section Content

struct UsageSectionContent: View {
    let usage: UsageService
    let noteCount: Int

    var body: some View {
        // Notes usage
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.body.weight(.medium))

                if usage.isPro {
                    Text("Unlimited")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray5))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(usage.freeNotesRemaining == 0 ? Color.red : Color.orange)
                                .frame(width: geometry.size.width * CGFloat(usage.freeNotesUsed) / CGFloat(UsageService.freeNoteLimit), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            if !usage.isPro {
                Text("\(usage.freeNotesUsed) of \(UsageService.freeNoteLimit)")
                    .font(.subheadline)
                    .foregroundStyle(usage.freeNotesRemaining == 0 ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)

        // Total stats
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.bar")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Total Stats")
                    .font(.body.weight(.medium))
                Text("\(noteCount) notes • \(usage.totalRecordingTimeString) recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Usage Ring View

struct UsageRingView: View {
    let progress: Double

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 6)

            // Progress ring
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    progress >= 1.0 ? Color.red : Color.orange,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center icon
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(progress >= 1.0 ? .red : .orange)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Project Edit View

struct ProjectEditView: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var newAlias = ""

    private let availableColors = ["blue", "red", "orange", "green", "pink", "yellow"]
    private let availableIcons = ["folder", "star", "bolt", "flame", "leaf", "briefcase", "cart", "airplane", "gamecontroller", "heart"]

    var body: some View {
        Form {
            Section("Project Info") {
                TextField("Name", text: $project.name)

                Picker("Color", selection: $project.colorName) {
                    ForEach(availableColors, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(colorFor(color))
                                .frame(width: 20, height: 20)
                            Text(color.capitalized)
                        }
                        .tag(color)
                    }
                }

                Picker("Icon", selection: $project.icon) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Label(icon.capitalized, systemImage: icon)
                            .tag(icon)
                    }
                }
            }

            Section("Aliases") {
                Text("Aliases help auto-match notes to this project")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(project.aliases, id: \.self) { alias in
                    HStack {
                        Text(alias)
                        Spacer()
                        Button(action: { removeAlias(alias) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add alias", text: $newAlias)
                    Button("Add") {
                        if !newAlias.isEmpty {
                            project.addAlias(newAlias)
                            newAlias = ""
                        }
                    }
                    .disabled(newAlias.isEmpty)
                }
            }

            Section {
                Toggle("Archived", isOn: $project.isArchived)
            }
        }
        .navigationTitle("Edit Project")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func removeAlias(_ alias: String) {
        var aliases = project.aliases
        aliases.removeAll { $0 == alias }
        project.aliases = aliases
    }

    private func colorFor(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .blue
        case "pink": return .pink
        default: return .blue
        }
    }
}

// MARK: - Language Picker View

struct LanguagePickerView: View {
    @State private var selectedLanguage = LanguageSettings.shared.selectedLanguage

    var body: some View {
        List {
            ForEach(TranscriptionLanguage.allCases) { language in
                Button {
                    selectedLanguage = language
                    LanguageSettings.shared.selectedLanguage = language
                } label: {
                    HStack {
                        Text(language.displayName)
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedLanguage == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Transcription Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: [Note.self, Project.self, Tag.self], inMemory: true)
}
