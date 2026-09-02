//
//  HomeView.swift
//  voice notes
//
//  Library home page with filter tabs
//  Clean Wave-style design
//

import SwiftUI
import SwiftData
import UIKit
import StoreKit
import AVFoundation
import PhotosUI
import CloudKit
import AuthenticationServices

// MARK: - Filter Options

enum NoteFilter: String, CaseIterable {
    case all = "Library"
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

    @State private var showPaywall = false
    @State private var showSignIn = false
    @State private var showingAddProjectFromMain = false
    @State private var newProjectName = ""

    // Tag filtering
    @State private var selectedTag: Tag?

    // Photo attachment
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false


    // Type note (alternative to voice)
    @State private var showingTypeNote = false

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

    private var headerView: some View {
        VStack(spacing: 0) {
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
                            .foregroundStyle(Color("EEONTextSecondary"))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if authService.isSignedIn, let firstName = authService.firstNameForGreeting {
                        Text("Hi, \(firstName)")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color("EEONTextPrimary"))
                    } else {
                        Text("Library")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color("EEONTextPrimary"))
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private var briefAndSearchSection: some View {
        VStack(spacing: 0) {
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

            if authService.isSignedIn {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color("EEONTextSecondary"))
                    TextField("Search", text: $searchText)
                        .foregroundStyle(Color("EEONTextPrimary"))
                }
                .padding(12)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 12)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("EEONBackground").ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView
                    briefAndSearchSection

                    // Spacer between search and notes list
                    Spacer().frame(height: 16)

                    // Tag filter indicator
                    if let tag = selectedTag {
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)

                            Text(tag.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color("EEONTextPrimary"))

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTag = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(Color("EEONTextSecondary"))
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
                                    .foregroundStyle(Color("EEONTextPrimary"))
                                Text("Your notes are safely stored in iCloud")
                                    .font(.subheadline)
                                    .foregroundStyle(Color("EEONTextSecondary"))
                                Button(action: { showSignIn = true }) {
                                    Text("Sign in with Apple")
                                        .font(.headline)
                                        .foregroundStyle(Color("EEONTextPrimary"))
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                                .accessibilityLabel("Sign in with Apple")
                                .padding(.top, 8)
                            }
                        } else {
                            // Signed in but no notes
                            VStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color("EEONTextSecondary"))
                                Text("No notes yet")
                                    .font(.headline)
                                    .foregroundStyle(Color("EEONTextSecondary"))
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
                        onRecord: toggleRecording,
                        onTypeNote: { showingTypeNote = true }
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
                                Text("Sign in with Apple")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color("EEONTextPrimary"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                            }
                                .accessibilityLabel("Sign in with Apple")
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
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
                AnswerSheet(initialQuery: "What should I focus on today?")
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onDismiss: {
                    showPaywall = false
                })
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
        }
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

                    // Generate embedding for semantic search (non-blocking, failure-tolerant)
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

            // Still update status counters for notes without transcripts
            StatusCounters.shared.incrementNotesToday()
            StatusCounters.shared.markSessionStale()
        }
    }

    // MARK: - Create Typed Note

    private func createTypedNote(content: String) {
        let note = Note(
            title: "",
            content: content,
            transcript: content,  // Treat typed text as transcript for AI processing
            audioFileName: nil    // No audio for typed notes
        )
        modelContext.insert(note)
        UsageService.shared.incrementNoteCount()
        try? modelContext.save()

        // AI processing for title, tags (same as voice notes)
        if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let allProjects = projects

            Task {
                do {
                    let title = try await generateTitle(for: content, apiKey: apiKey)
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

                        // Auto-assign project
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

    // MARK: - Auto-Extract for First Note

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
                    .foregroundStyle(Color("EEONTextPrimary"))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Color("EEONTextSecondary"))

                    // Duration (if audio)
                    if note.hasAudio {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Color("EEONTextSecondary"))
                        Text(formattedDuration(note.audioDuration))
                            .font(.caption)
                            .foregroundStyle(Color("EEONTextSecondary"))
                    }

                    // Intent badge
                    if note.intent != .unknown {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Color("EEONTextSecondary"))
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
                                .foregroundStyle(Color("EEONAccentAI"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color("EEONAccentAI").opacity(0.15))
                                .cornerRadius(6)
                            }

                            // Overflow indicator
                            if note.mentionedPeople.count > 3 {
                                Text("+\(note.mentionedPeople.count - 3)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color("EEONAccentAI"))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color("EEONAccentAI").opacity(0.15))
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
                            .foregroundStyle(Color("EEONTextSecondary"))
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
    var onTypeNote: (() -> Void)? = nil
    var onImportAudio: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 40) {
            // Subtle keyboard icon for typing (low-key, left of record)
            if let onType = onTypeNote, !isRecording && !isTranscribing {
                Button(action: onType) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .frame(width: 44, height: 44)
            } else {
                // Spacer to keep record button centered
                Color.clear.frame(width: 44, height: 44)
            }

            // Record button (primary)
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

            // Import audio button (right of record)
            if let onImport = onImportAudio, !isRecording && !isTranscribing {
                Button(action: onImport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .frame(width: 44, height: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.bottom, 30)
    }
}

// MARK: - Type Note Sheet

struct TypeNoteSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var noteText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $noteText)
                    .focused($isFocused)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                    .overlay(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(Color("EEONTextSecondary").opacity(0.6))
                                .padding(.top, 24)
                                .padding(.leading, 21)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Color("EEONTextSecondary"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(noteText)
                    }
                    .fontWeight(.semibold)
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // A half-typed note must never die to an accidental swipe-down.
        // Cancel remains the deliberate discard.
        .interactiveDismissDisabled(
            !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
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
                        colors: [Color("EEONAccent"), Color("EEONAccent").opacity(0.7)],
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
    /// Dismiss the recorder while recording keeps running in the background.
    /// Live transcription stops here; audio capture does not.
    var onMinimize: (() -> Void)?
    let audioRecorder: AudioRecorder

    private let barCount = 28
    @State private var barLevels: [CGFloat] = Array(repeating: 0.15, count: 28)
    @State private var meterTimer: Timer?

    @State private var dotVisible = true
    @State private var dotTimer: Timer?
    @State private var cursorVisible = true
    @State private var cursorTimer: Timer?
    @State private var liveTranscription = LiveTranscriptionService()

    private let accentRed = Color(red: 1.0, green: 0.23, blue: 0.27)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                recordingBackground

                VStack(spacing: 20) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, max(CGFloat(16), geometry.safeAreaInsets.top + 8))

                    Spacer(minLength: 8)

                    recordingState
                        .padding(.horizontal, 24)

                    waveformSection
                        .padding(.horizontal, 26)

                    transcriptSection(maxHeight: min(CGFloat(260), geometry.size.height * 0.30))
                        .padding(.horizontal, 20)

                    Spacer(minLength: 10)

                    bottomControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, max(CGFloat(18), geometry.safeAreaInsets.bottom + 12))
                }
            }
        }
        .onAppear {
            startMetering()
            startDotBlink()
            startCursorBlink()
            startLiveTranscription()
        }
        .onChange(of: audioRecorder.isPaused) { _, isPaused in
            if isPaused {
                liveTranscription.stop()
            } else {
                startLiveTranscription()
            }
        }
        .onDisappear {
            meterTimer?.invalidate()
            meterTimer = nil
            dotTimer?.invalidate()
            dotTimer = nil
            cursorTimer?.invalidate()
            cursorTimer = nil
            liveTranscription.stop()
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 80, let onMinimize {
                    liveTranscription.stop()
                    onMinimize()
                }
            }
        )
    }

    private var recordingBackground: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.02, green: 0.03, blue: 0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    liveTranscription.stop()
                    onCancel()
                } label: {
                    Text("Discard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentRed)
                        .frame(minWidth: 78, alignment: .leading)
                }
                .accessibilityLabel("Discard recording")
                .accessibilityHint("Stops recording and deletes this audio.")

                Spacer()

                Color.clear
                    .frame(width: 78, height: 1)
            }

            Text("Recording")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 44)
    }

    private var recordingState: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(audioRecorder.isPaused ? .yellow : accentRed)
                    .frame(width: 10, height: 10)
                    .opacity(audioRecorder.isPaused ? 1.0 : (dotVisible ? 1.0 : 0.35))

                Text(audioRecorder.isPaused ? "Paused" : "Recording")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Text(audioRecorder.isPaused ? "Paused" : audioRecorder.formattedTime)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .foregroundStyle(.white)

            Text(audioRecorder.isPaused ? "Tap Resume to continue." : "Tap Finish to save this note.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var waveformSection: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(audioRecorder.isPaused ? Color.white.opacity(0.35) : accentRed)
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(
                        .spring(response: 0.28, dampingFraction: 0.72)
                            .delay(Double(index) * 0.006),
                        value: barLevels[index]
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = barLevels[index]
        let minHeight: CGFloat = 8
        let maxHeight: CGFloat = 76
        return minHeight + level * (maxHeight - minHeight)
    }

    private func transcriptSection(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live transcript")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(audioRecorder.isPaused ? "Paused" : "Listening")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Divider()
                .overlay(Color.white.opacity(0.12))

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        let confirmedText = liveTranscription.liveTranscript
                        let activeWord = liveTranscription.currentWord

                        if confirmedText.isEmpty && activeWord.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(audioRecorder.isPaused ? "Recording is paused." : "Start talking.")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                Text(audioRecorder.isPaused ? "Your note will continue when you resume." : "Words will appear here while EEON listens.")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.50))
                            }
                        } else {
                            buildTranscriptText(confirmed: confirmedText, active: activeWord)
                                .font(.system(size: 20, weight: .regular))
                                .lineSpacing(5)
                        }

                        Rectangle()
                            .fill(.white.opacity(0.75))
                            .frame(width: 2, height: 24)
                            .opacity(audioRecorder.isPaused ? 0.0 : (cursorVisible ? 1.0 : 0.0))
                            .padding(.top, 4)
                            .id("cursor")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: liveTranscription.liveTranscript) { _, _ in
                        withAnimation {
                            proxy.scrollTo("cursor", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: maxHeight)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func buildTranscriptText(confirmed: String, active: String) -> Text {
        var result = Text(confirmed).foregroundColor(.white)

        if !active.isEmpty {
            let separator = confirmed.isEmpty ? "" : " "
            result = result
                + Text(separator).foregroundColor(.white)
                + Text(active).foregroundColor(accentRed).fontWeight(.bold)
        }

        return result
    }

    private var bottomControls: some View {
        HStack(alignment: .top, spacing: 10) {
            if let onMinimize {
                controlButton(
                    icon: "chevron.down",
                    title: "Minimize",
                    iconColor: .white,
                    background: Color.white.opacity(0.13),
                    accessibilityHint: "Keeps recording in the background."
                ) {
                    liveTranscription.stop()
                    onMinimize()
                }
            }

            controlButton(
                icon: audioRecorder.isPaused ? "play.fill" : "pause.fill",
                title: audioRecorder.isPaused ? "Resume" : "Pause",
                iconColor: .black,
                background: Color.white.opacity(0.94),
                accessibilityHint: audioRecorder.isPaused ? "Starts recording again." : "Pauses recording without saving yet."
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if audioRecorder.isPaused {
                        audioRecorder.resumeRecording()
                        startLiveTranscription()
                    } else {
                        liveTranscription.stop()
                        audioRecorder.pauseRecording()
                    }
                }
            }

            controlButton(
                icon: "stop.fill",
                title: "Finish",
                iconColor: .white,
                background: accentRed,
                accessibilityHint: "Stops recording and saves this note."
            ) {
                liveTranscription.stop()
                onStop()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(
        icon: String,
        title: String,
        iconColor: Color,
        background: Color,
        titleColor: Color = .white,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 64, height: 64)
                    .background(background, in: Circle())

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(titleColor.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let level = audioRecorder.isPaused ? CGFloat(0.08) : max(CGFloat(0.12), audioRecorder.normalizedLevel)

            var newLevels = [CGFloat]()
            for i in 0..<barCount {
                let phase = sin(Double(i) * 0.48 + Date().timeIntervalSinceReferenceDate * 3.2)
                let variation = audioRecorder.isPaused ? CGFloat(0.0) : CGFloat(phase) * 0.12
                let randomness = audioRecorder.isPaused ? CGFloat(0.0) : CGFloat.random(in: -0.04...0.04)
                let barLevel = max(0.05, min(1.0, level + variation + randomness))
                newLevels.append(barLevel)
            }
            barLevels = newLevels
        }
    }

    private func startDotBlink() {
        dotTimer?.invalidate()
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                dotVisible.toggle()
            }
        }
    }

    private func startCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                cursorVisible.toggle()
            }
        }
    }

    private func startLiveTranscription() {
        guard !audioRecorder.isPaused else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SkipSpeechForScreenshot") {
            return
        }
        #endif
        Task {
            let authorized = await liveTranscription.requestAuthorization()
            if authorized {
                liveTranscription.start()
            }
        }
    }
}

// MARK: - Transcribing Overlay

struct HomeTranscribingOverlay: View {
    @State private var activeStep = 0
    @State private var stepTimer: Timer?

    private let steps: [MemoryProcessingStep] = [
        MemoryProcessingStep(icon: "waveform", title: "Writing the note", subtitle: "Turning your voice into clean text"),
        MemoryProcessingStep(icon: "sparkles", title: "Finding what matters", subtitle: "Pulling out decisions, people, and projects"),
        MemoryProcessingStep(icon: "checklist", title: "Preparing follow-ups", subtitle: "Finding action items for Reminders"),
        MemoryProcessingStep(icon: "sparkle.magnifyingglass", title: "Ready for Ask EEON", subtitle: "Adding this context to your searchable memory")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    Color(red: 0.03, green: 0.05, blue: 0.09).opacity(0.96),
                    Color.black.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color("EEONAccent").opacity(0.24))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: -140, y: -130)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 112, height: 112)

                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color("EEONAccent"))
                        .symbolEffect(.pulse)
                }

                VStack(spacing: 8) {
                    Text("Building your memory")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("EEON is turning this recording into notes, tasks, and AI-searchable context.")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        ProcessingStepRow(
                            step: step,
                            state: state(for: index)
                        )

                        if index < steps.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.leading, 62)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
                .padding(.horizontal, 26)

                ProgressView(value: Double(activeStep + 1), total: Double(steps.count))
                    .tint(Color("EEONAccent"))
                    .padding(.horizontal, 54)
            }
        }
        .onAppear {
            startSteps()
        }
        .onDisappear {
            stepTimer?.invalidate()
            stepTimer = nil
        }
    }

    private func state(for index: Int) -> ProcessingStepState {
        if index < activeStep { return .complete }
        if index == activeStep { return .active }
        return .waiting
    }

    private func startSteps() {
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: true) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeStep = (activeStep + 1) % steps.count
            }
        }
    }
}

private struct MemoryProcessingStep: Identifiable {
    let icon: String
    let title: String
    let subtitle: String

    var id: String { title }
}

private enum ProcessingStepState {
    case complete
    case active
    case waiting
}

private struct ProcessingStepRow: View {
    let step: MemoryProcessingStep
    let state: ProcessingStepState

    private var iconColor: Color {
        switch state {
        case .complete: return .green
        case .active: return Color("EEONAccent")
        case .waiting: return .white.opacity(0.34)
        }
    }

    private var iconName: String {
        state == .complete ? "checkmark.circle.fill" : step.icon
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(state == .waiting ? 0.12 : 0.18))
                    .frame(width: 42, height: 42)

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .scaleEffect(state == .active ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: state == .active)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state == .waiting ? .white.opacity(0.42) : .white)

                Text(step.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(state == .waiting ? 0.28 : 0.56))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
        case "purple": return Color("EEONAccentAI")
        case "pink": return .pink
        case "yellow": return .yellow
        default: return .blue
        }
    }

    var body: some View {
        List(projects) { project in
            HStack {
                Image(systemName: project.icon)
                    .foregroundStyle(colorFor(project.colorName))
                Text(project.name)
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
    @Query private var knowledgeArticles: [KnowledgeArticle]
    @Query private var dailyBriefs: [DailyBrief]
    @Query private var kanbanItems: [KanbanItem]
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var mentionedPeople: [MentionedPerson]

    // Observe AuthService for reactive updates
    private var authService = AuthService.shared
    private var googleCalendarService = GoogleCalendarService.shared
    @AppStorage(EventKitSyncService.enabledKey) private var remindersSyncEnabled = false
    @AppStorage(CalendarContextService.enabledKey) private var calendarContextEnabled = false
    @AppStorage(PersonaPresetStore.autoSummarizeKey) private var autoSummarizeEnabled = false
    @AppStorage(AskModelPreference.storageKey) private var askModelPreferenceRaw = AskModelPreference.balanced.rawValue
    @State private var showingAddProject = false
    @State private var newProjectName = ""
    @State private var showingShareSheet = false
    @State private var showingPaywall = false
    @State private var showingManageSubscriptions = false
    @State private var showingResetConfirm = false
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteAllDataConfirm = false
    @State private var showingEditName = false
    @State private var editedName = ""
    @State private var signInError: String?
    @State private var documentExportConfirmation: String?
    @State private var googleCalendarFeedback: String?
    @State private var isConnectingGoogleCalendar = false

    // Export state
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showingExportShareSheet = false

    // iCloud sync state
    @State private var isSyncing = false
    @State private var lastSyncedAt: Date?
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @State private var syncFeedback: String?

    // Diagnostic state (populated lazily by loadDiagnostics)
    @State private var diagUserRecordID: String = "—"
    @State private var diagZones: [String] = []
    @State private var diagZonesError: String?
    @State private var diagIsLoading = false
    @State private var diagCKNoteCount: String = "—"
    @State private var diagCKNoteError: String?
    @State private var diagEvents: [CloudKitEventLogEntry] = []

    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    private let usage = UsageService.shared


    // MARK: - Connections (extracted — keeps the body type-checkable)

    private var connectionsSection: some View {
        Group {
            Section {
                connectionStatusRow(
                    icon: "icloud",
                    title: "iCloud Sync",
                    subtitle: aiAccessSubtitle,
                    status: aiAccessStatusBadge,
                    statusColor: iCloudStatus == .available ? Color.secondary : Color.orange
                )

                connectionStatusRow(
                    icon: "sparkle.magnifyingglass",
                    title: "EEON MCP Connector",
                    subtitle: aiConnectorSubtitle,
                    status: aiConnectorStatusBadge,
                    statusColor: iCloudStatus == .available ? Color.secondary : Color.orange
                )

                Button {
                    documentExportConfirmation = aiAccessHelpText
                } label: {
                    EEONSettingsRow(
                        icon: "questionmark.circle",
                        title: "How AI tools connect",
                        subtitle: "Authorize the connector in each workspace"
                    ) {
                        EEONChevron()
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Sync & AI")
            } footer: {
                Text("iCloud sync stays private by default. AI access requires explicit CloudKit authorization.")
            }
        }
        .alert("Connections", isPresented: Binding(
            get: { documentExportConfirmation != nil },
            set: { if !$0 { documentExportConfirmation = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentExportConfirmation ?? "")
        }
    }

    private func connectionStatusRow(
        icon: String,
        title: String,
        subtitle: String,
        status: String,
        statusColor: Color
    ) -> some View {
        EEONSettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle
        ) {
            Text(status)
                .font(EEONType.badge)
                .foregroundStyle(statusColor)
        }
    }

    private var remindersSyncRow: some View {
        Toggle(isOn: $remindersSyncEnabled) {
            EEONSettingsRow(
                icon: "checklist",
                title: "Reminders",
                subtitle: "Action items can appear in an EEON list"
            )
        }
        .onChange(of: remindersSyncEnabled) { _, isOn in
            guard isOn else { return }
            Task {
                let granted = await EventKitSyncService.shared.requestAccess()
                if !granted {
                    await MainActor.run { remindersSyncEnabled = false }
                }
            }
        }
    }

    private var calendarContextRow: some View {
        Toggle(isOn: $calendarContextEnabled) {
            EEONSettingsRow(
                icon: "calendar",
                title: "iPhone Calendar",
                subtitle: "Shows iCloud, Google, and Outlook events from iPhone Calendar"
            )
        }
        .onChange(of: calendarContextEnabled) { _, isOn in
            guard isOn else { return }
            Task {
                let granted = await CalendarContextService.shared.requestAccess()
                if !granted {
                    await MainActor.run { calendarContextEnabled = false }
                }
            }
        }
    }

    private var googleCalendarRow: some View {
        Button {
            handleGoogleCalendarTap()
        } label: {
            EEONSettingsRow(
                icon: "g.circle",
                title: "Google Calendar",
                subtitle: googleCalendarSubtitle
            ) {
                Text(googleCalendarStatus)
                    .font(EEONType.badge)
                    .foregroundStyle(googleCalendarStatusColor)
            }
        }
        .buttonStyle(.plain)
    }

    private var googleCalendarSubtitle: String {
        if let googleCalendarFeedback {
            return googleCalendarFeedback
        }
        if googleCalendarService.isConnected {
            return "Direct read-only Google Calendar is connected"
        }
        if googleCalendarService.isConfigured {
            return "Connect directly when Google events are not on this phone"
        }
        return "Needs Google OAuth client ID in this build"
    }

    private var googleCalendarStatus: String {
        if isConnectingGoogleCalendar { return "Opening..." }
        if googleCalendarService.isConnected { return "Connected" }
        return "Connect"
    }

    private var googleCalendarStatusColor: Color {
        if googleCalendarService.isConnected { return Color.secondary }
        return googleCalendarService.isConfigured ? Color.eeonAccent : Color.orange
    }

    private func handleGoogleCalendarTap() {
        guard !isConnectingGoogleCalendar else { return }

        guard googleCalendarService.isConfigured else {
            googleCalendarFeedback = googleCalendarService.configurationStatus
            documentExportConfirmation = "Google Calendar is not configured in this build: \(googleCalendarService.configurationStatus). Rebuild EEON with the Google OAuth client ID and matching reversed Google URL scheme."
            return
        }

        if googleCalendarService.isConnected {
            googleCalendarService.disconnect()
            googleCalendarFeedback = "Disconnected"
            return
        }

        Task {
            await MainActor.run {
                isConnectingGoogleCalendar = true
                googleCalendarFeedback = "Opening Google sign-in..."
            }
            do {
                try await googleCalendarService.signIn()
                await MainActor.run {
                    isConnectingGoogleCalendar = false
                    googleCalendarFeedback = "Connected"
                }
            } catch {
                await MainActor.run {
                    isConnectingGoogleCalendar = false
                    googleCalendarFeedback = error.localizedDescription
                    documentExportConfirmation = "Google Calendar did not connect: \(error.localizedDescription)"
                }
            }
        }
    }

    private var aiAccessSubtitle: String {
        switch iCloudStatus {
        case .available:
            return "Notes sync through your Apple account"
        case .noAccount:
            return "Sign in to iCloud to sync notes"
        case .restricted:
            return "Restricted by device policy"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .couldNotDetermine:
            return "Checking iCloud"
        @unknown default:
            return "Check iCloud status"
        }
    }

    private var aiAccessStatusBadge: String {
        iCloudStatus == .available ? "On" : "Off"
    }

    private var aiAccessHelpText: String {
        if iCloudStatus == .available {
            return "EEON syncs notes through your private iCloud database. This does not automatically give AI tools access. In each AI workspace, add the EEON CloudKit connector and sign in with Apple. There is no phone folder picker."
        }
        return "EEON needs iCloud to sync notes. Sign in to iCloud in the Settings app, then return to EEON."
    }

    private var aiConnectorSubtitle: String {
        if iCloudStatus == .available {
            return "Add it in your AI tool on your computer — not a switch here"
        }
        return "Turn on iCloud to make notes available"
    }

    private var aiConnectorStatusBadge: String {
        // "Available" read as "it's on" (Shawn, 2026-09-02). Nothing is
        // connected until the user adds the connector in their AI tool, and
        // the app can't detect that — so the honest state is "ready to connect".
        iCloudStatus == .available ? "Ready to connect" : "Needs iCloud"
    }

    /// Auto-format every new note in the style the user's profession preset
    /// implies (School Notes, Case Note, Clinical Note...). Pro-only — it
    /// costs one extra AI call per note.
    private var autoSummarizeRow: some View {
        Toggle(isOn: $autoSummarizeEnabled) {
            HStack(spacing: 16) {
                Image(systemName: "text.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.eeonAccentAI)
                    .frame(width: EEONLayout.minTarget)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-format new notes")
                        .font(.body)
                    Text(autoSummarizeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!SubscriptionManager.shared.isSubscribed)
    }

    private var autoSummarizeSubtitle: String {
        guard SubscriptionManager.shared.isSubscribed else { return "Pro feature" }
        if let raw = PersonaPresetStore.defaultTransformRaw {
            return "Written as \(raw)"
        }
        return "Choose a default note format"
    }

    private var dataSection: some View {
        Section {
            Button {
                generateExport()
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        if isExporting {
                            ProgressView().tint(.blue)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export My Data")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Library + knowledge articles as markdown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .padding(.vertical, 4)
        } header: {
            Text("Data")
        } footer: {
            Text("Your notes are yours. Export anytime as a single markdown file — opens in Obsidian, Notion, or any text editor.")
                .font(.caption)
        }
    }

    private var signedOutAccountPrompt: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            HStack(spacing: EEONLayout.standard) {
                EEONSettingsIcon(systemName: "person.crop.circle.badge.plus")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Account")
                        .font(EEONType.body)
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Use Apple ID to restore account and Pro access")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                }

                Spacer(minLength: EEONLayout.tight)
            }

            SettingsAppleSignInButton(onCompletion: handleSettingsAppleSignIn)
        }
        .padding(.vertical, 8)
    }

    private func handleSettingsAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            authService.handleSignInResult(.success(authorization))
            Task {
                await SubscriptionManager.shared.updateSubscriptionStatus()
            }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            signInError = error.localizedDescription
        }
    }

    // MARK: - iCloud Sync Section

    private var iCloudSyncSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: iCloudStatusIcon)
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(iCloudStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Button {
                syncNow()
            } label: {
                HStack(spacing: 16) {
                    EEONSettingsIcon(systemName: "arrow.triangle.2.circlepath")
                    Text(isSyncing ? "Syncing…" : (syncFeedback ?? "Sync Now"))
                        .font(.body)
                        .foregroundStyle(isSyncing ? .secondary : Color("EEONAccent"))
                    Spacer()
                    if isSyncing {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .disabled(isSyncing || iCloudStatus != .available)

            // Storage readout. A compact version of the diagnostics panel,
            // restored 2026-08-20 after removing it made a "where are my
            // notes?" question impossible to answer from the device.
            //
            // Sync mode matters: development-signed builds use CloudKit's
            // DEVELOPMENT database, TestFlight/App Store builds use
            // PRODUCTION. Same account, same app, two separate datastores —
            // which is why notes can appear to vanish when moving between a
            // sideloaded build and TestFlight. Nothing is deleted.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Storage")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    Spacer()
                    Text(diagInitOutcome)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                }
                HStack {
                    Text("Notes on this device")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    Spacer()
                    Text("\(notes.count)")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                }
                HStack {
                    Text("Build")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    Spacer()
                    Text(Self.buildDescription)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("iCloud & Sync")
        } footer: {
            if let lastSyncedAt {
                Text("Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened)). Notes sync automatically across your devices via iCloud.")
            } else {
                Text("Your notes sync automatically across iPhone, iPad, and Mac when you're signed into the same iCloud account.")
            }
        }
    }

    private var iCloudStatusIcon: String {
        switch iCloudStatus {
        case .available:          return "icloud.fill"
        case .noAccount:          return "icloud.slash"
        case .restricted:         return "icloud.slash"
        case .temporarilyUnavailable: return "icloud"
        case .couldNotDetermine:  return "icloud"
        @unknown default:         return "icloud"
        }
    }

    private var iCloudStatusText: String {
        switch iCloudStatus {
        case .available:          return "Connected"
        case .noAccount:          return "Not signed into iCloud — open Settings → Apple ID to sign in"
        case .restricted:         return "Restricted by device policy"
        case .temporarilyUnavailable: return "Temporarily unavailable — retry shortly"
        case .couldNotDetermine:  return "Checking…"
        @unknown default:         return "Unknown"
        }
    }

    private var iCloudStatusShortText: String {
        switch iCloudStatus {
        case .available:          return "iCloud on"
        case .noAccount:          return "Needs sign-in"
        case .restricted:         return "Restricted"
        case .temporarilyUnavailable: return "Unavailable"
        case .couldNotDetermine:  return "Checking"
        @unknown default:         return "Unknown"
        }
    }

    private func refreshiCloudStatus() async {
        let container = CKContainer(identifier: "iCloud.aivoiceeeon")
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        await MainActor.run { iCloudStatus = status }
    }

    /// Version + build, and which CloudKit environment this build talks to.
    static var buildDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if DEBUG
        let environment = "dev CloudKit"
        #else
        let environment = "prod CloudKit"
        #endif
        return "\(version) (\(build)) · \(environment)"
    }

    private var diagInitOutcome: String {
        UserDefaults.standard.string(forKey: "cloudKitInitOutcome") ?? "unknown"
    }

    private var diagInitError: String? {
        UserDefaults.standard.string(forKey: "cloudKitInitError")
    }

    @ViewBuilder
    private func diagRow(label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadDiagnostics() async {
        await MainActor.run { diagIsLoading = true }
        await refreshiCloudStatus()

        let container = CKContainer(identifier: "iCloud.aivoiceeeon")

        // User record ID — proves CloudKit can identify the signed-in iCloud user
        var userID = "—"
        do {
            let recordID = try await container.userRecordID()
            userID = recordID.recordName
        } catch {
            userID = "error: \(error.localizedDescription)"
        }

        // Private DB zone list — the real answer to "did SwiftData create its zone?"
        var zones: [String] = []
        var zonesError: String?
        do {
            let all = try await container.privateCloudDatabase.allRecordZones()
            zones = all.map { $0.zoneID.zoneName }
        } catch {
            zonesError = error.localizedDescription
        }

        // Live count of CD_Note records in CloudKit — walks the zone via
        // recordZoneChanges instead of CKQuery so the count works regardless
        // of whether `recordName` has a queryable index in the Production
        // schema. This is the same primitive NSPersistentCloudKitContainer
        // uses for sync, so the count reflects what SwiftData would actually
        // pull on this device.
        var ckNoteCount = "—"
        var ckNoteError: String?
        let swiftDataZoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        do {
            var count = 0
            var token: CKServerChangeToken? = nil
            var more = true
            while more {
                let result = try await container.privateCloudDatabase.recordZoneChanges(
                    inZoneWith: swiftDataZoneID,
                    since: token
                )
                for (_, modResult) in result.modificationResultsByID {
                    if case .success(let mod) = modResult,
                       mod.record.recordType == "CD_Note" {
                        count += 1
                    }
                }
                token = result.changeToken
                more = result.moreComing
            }
            ckNoteCount = "\(count)"
        } catch {
            ckNoteCount = "error"
            ckNoteError = error.localizedDescription
        }

        let events = CloudKitEventLog.recent()

        await MainActor.run {
            diagUserRecordID = userID
            diagZones = zones
            diagZonesError = zonesError
            diagCKNoteCount = ckNoteCount
            diagCKNoteError = ckNoteError
            diagEvents = events
            diagIsLoading = false
        }
    }

    private func syncNow() {
        isSyncing = true
        syncFeedback = nil
        Task {
            try? modelContext.save()
            await refreshiCloudStatus()
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                isSyncing = false
                if iCloudStatus == .available {
                    lastSyncedAt = Date()
                    syncFeedback = "Synced"
                } else {
                    syncFeedback = "Couldn't reach iCloud"
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { syncFeedback = nil }
        }
    }

    // MARK: - Detail screens
    //
    // Each is one domain. The sections they wrap kept their footers (the
    // explanatory copy is useful once you are IN the room) but lost their
    // headers, because the navigation title now says the same thing.

    /// The one row that stands in for the whole account domain.
    private var accountSummaryRow: some View {
        HStack(spacing: EEONLayout.standard) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(Color("EEONAccentAI"))
                .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)

            VStack(alignment: .leading, spacing: 2) {
                Text(accountDisplayName)
                    .font(EEONType.body)
                    .foregroundStyle(.eeonTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(accountSummarySubtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer(minLength: EEONLayout.tight)
        }
        .frame(minHeight: EEONLayout.minTarget)
        .padding(.vertical, 4)
    }

    private var accountDisplayName: String {
        cleaned(authService.userName)
            ?? cleaned(authService.userEmail)
            ?? "Apple Account"
    }

    private var accountSummarySubtitle: String {
        authService.isSignedIn ? "Signed in with Apple" : "Not signed in"
    }

    private var accountEmailText: String {
        cleaned(authService.userEmail) ?? "Not shared"
    }

    private var accountNameText: String {
        cleaned(authService.userName) ?? "Add Name"
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var accountDetail: some View {
        List {
            if authService.isSignedIn {
                Section {
                    LabeledContent("Name") {
                        Button {
                            editedName = cleaned(authService.userName) ?? ""
                            showingEditName = true
                        } label: {
                            Text(accountNameText)
                                .foregroundStyle(cleaned(authService.userName) == nil ? Color("EEONAccentAI") : .secondary)
                        }
                    }

                    LabeledContent("Email", value: accountEmailText)

                    LabeledContent("Sign in with Apple", value: "Connected")
                } header: {
                    Text("Apple Account")
                } footer: {
                    Text("Apple only shares your name and email the first time you authorize the app. If no name is stored, add one here.")
                }

                Section {
                    LabeledContent("Plan", value: usage.isPro ? "EEON Pro" : "Free")

                    if !usage.isPro {
                        Button("Upgrade to Pro") {
                            showingPaywall = true
                        }
                    } else {
                        Button("Downgrade to Free", role: .destructive) {
                            showingResetConfirm = true
                        }
                    }
                } header: {
                    Text("Subscription")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirm = true
                    }
                }

                Section {
                    Button("Delete Account & Data", role: .destructive) {
                        showingDeleteAllDataConfirm = true
                    }
                } footer: {
                    Text("This permanently deletes your account, notes, projects, and associated data from this device and iCloud. This action cannot be undone.")
                }
            } else {
                Section {
                    signedOutAccountPrompt
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var captureDetail: some View {
        List {
            Section {
                NavigationLink {
                    LanguagePickerView()
                } label: {
                    EEONSettingsRow(
                        icon: "globe",
                        title: "Transcription Language"
                    ) {
                        Text(LanguageSettings.shared.selectedLanguage.displayName)
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }

                NavigationLink {
                    VocabularyEditorView()
                } label: {
                    EEONSettingsRow(
                        icon: "character.book.closed",
                        title: "Words EEON should know"
                    ) {
                        let count = TranscriptionVocabulary.shared.customTerms.count
                        if count > 0 {
                            Text("\(count)")
                                .font(EEONType.meta)
                                .foregroundStyle(.eeonTextSecondary)
                        }
                    }
                }
            } footer: {
                Text("Names, products and jargon you add here are spelled correctly in every transcript. People and projects from your notes are included automatically.")
                    .font(EEONType.meta)
            }

            Section {
                autoSummarizeRow
            } footer: {
                Text("New notes are automatically rewritten in your preset's format on save. Students get study notes — headings, key concepts, and review questions — without picking anything.")
                    .font(EEONType.meta)
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var askDetail: some View {
        List {
            Section {
                Picker("Answer style", selection: $askModelPreferenceRaw) {
                    ForEach(AskModelPreference.allCases) { preference in
                        Label(preference.title, systemImage: preference.systemImage)
                            .tag(preference.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Fast keeps Ask lightweight. Balanced is the default. Thorough gives EEON more room when questions need synthesis across notes and articles.")
                    .font(EEONType.meta)
            }
        }
        .navigationTitle("Ask EEON")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionsDetail: some View {
        List {
            connectionsSection
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var syncDetail: some View {
        List {
            iCloudSyncSection
        }
        .navigationTitle("iCloud & Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dataDetail: some View {
        List {
            dataSection
        }
        .navigationTitle("Export My Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helpDetail: some View {
        List {
            Section {
                Button {
                    if let url = URL(string: "mailto:support@eeon.com") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    EEONSettingsRow(icon: "envelope", title: "Contact Support") {
                        EEONChevron()
                    }
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://eeon.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    EEONSettingsRow(icon: "hand.raised", title: "Privacy Policy") {
                        EEONChevron()
                    }
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://eeon.com/terms") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    EEONSettingsRow(icon: "doc.text", title: "Terms of Use") {
                        EEONChevron()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Help & About")
        .navigationBarTitleDisplayMode(.inline)
    }

    #if DEBUG
    private var developerDetail: some View {
        List {
            Section {
                Button {
                    OnboardingState.set(.needsSignIn)
                } label: {
                    HStack(spacing: EEONLayout.standard) {
                        EEONSettingsIcon(systemName: "arrow.counterclockwise.circle")
                        Text("Reset Onboarding")
                            .font(EEONType.body)
                            .foregroundStyle(Color("EEONAccentAI"))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)

                Button {
                    UsageService.shared.noteCount = 0
                    UsageService.shared.hasShownPaywall = false
                } label: {
                    HStack(spacing: EEONLayout.standard) {
                        EEONSettingsIcon(systemName: "gobackward")
                        Text("Reset Free Notes Counter")
                            .font(EEONType.body)
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } footer: {
                Text("Debug tools for testing. Reset Onboarding will restart the app.")
                    .font(EEONType.meta)
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif

    private var planSummaryRow: some View {
        HStack(spacing: EEONLayout.standard) {
            EEONSettingsIcon(systemName: usage.isPro ? "star.fill" : "star")

            VStack(alignment: .leading, spacing: 2) {
                Text(usage.isPro ? "EEON Pro" : "Free")
                    .font(EEONType.body)
                    .foregroundStyle(.eeonTextPrimary)
                Text(usageStatusText)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer(minLength: EEONLayout.tight)

            if usage.isPro {
                settingsStatusPill("Pro", color: .eeonAccentAI)
            } else {
                Button("Upgrade") {
                    showingPaywall = true
                }
                .font(EEONType.badge)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(minHeight: EEONLayout.minTarget)
        .padding(.vertical, 2)
    }

    private func settingsStatusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(EEONType.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var usageStatusText: String {
        if usage.isPro {
            return "\(noteCount) notes recorded"
        }
        return "\(usage.freeNotesUsed) of \(UsageService.freeNoteLimit) free notes used"
    }

    private var noteCount: Int {
        notes.filter {
            $0.sourceType != .profileSeed && $0.sourceType != .purposeSeed
        }.count
    }

    private var personalizationSettingsRow: some View {
        NavigationLink {
            TuneConversationView()
        } label: {
            EEONSettingsRow(
                icon: "person.crop.circle",
                title: "Personalization",
                subtitle: "Profile, focus, tone"
            )
        }
    }

    private var captureSettingsRow: some View {
        NavigationLink {
            captureDetail
        } label: {
            EEONSettingsRow(
                icon: "waveform",
                title: "Capture",
                subtitle: "Language, vocabulary, format"
            )
        }
    }

    private var askSettingsRow: some View {
        NavigationLink {
            askDetail
        } label: {
            EEONSettingsRow(
                icon: "sparkle.magnifyingglass",
                title: "Ask EEON",
                subtitle: selectedAskModelPreference.title
            )
        }
    }

    private var peopleSpeakersSettingsRow: some View {
        NavigationLink {
            PeopleSpeakersSettingsView()
        } label: {
            EEONSettingsRow(
                icon: "person.2",
                title: "People & Speakers",
                subtitle: peopleSpeakersSummary
            )
        }
    }

    private var peopleSpeakersSummary: String {
        let peopleCount = mentionedPeople.filter { !$0.isArchived }.count
        let speakerCount = Set(notes.flatMap { note in
            note.speakerLabels
                .map(\.displayName)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("speaker ") }
        }).count

        if peopleCount == 0 && speakerCount == 0 {
            return "Rename people and speakers across notes"
        }
        if speakerCount == 0 {
            return "\(peopleCount) people"
        }
        return "\(peopleCount) people, \(speakerCount) named speakers"
    }

    private var selectedAskModelPreference: AskModelPreference {
        AskModelPreference(rawValue: askModelPreferenceRaw) ?? .balanced
    }

    private var syncSettingsRow: some View {
        NavigationLink {
            syncDetail
        } label: {
            EEONSettingsRow(
                icon: "icloud",
                title: "iCloud & Storage",
                subtitle: "\(noteCount) notes · \(iCloudStatusShortText)"
            )
        }
    }

    private var exportSettingsRow: some View {
        NavigationLink {
            dataDetail
        } label: {
            EEONSettingsRow(
                icon: "square.and.arrow.up",
                title: "Export My Data",
                subtitle: "Markdown backup"
            )
        }
    }

    private var helpSettingsRow: some View {
        NavigationLink {
            helpDetail
        } label: {
            EEONSettingsRow(
                icon: "questionmark.circle",
                title: "Help & About",
                subtitle: "Support, privacy, terms"
            )
        }
    }

    #if DEBUG
    private var developerSettingsRow: some View {
        NavigationLink {
            developerDetail
        } label: {
            EEONSettingsRow(
                icon: "hammer",
                title: "Developer",
                subtitle: "Debug tools"
            )
        }
    }
    #endif

    private var accountSettingsSection: some View {
        Section {
            // Plan first — the status a user checks most, prominent like Stock
            // Alarm's membership card, not a buried row (Shawn, 2026-09-02).
            planSummaryRow
            if authService.isSignedIn {
                NavigationLink {
                    accountDetail
                } label: {
                    accountSummaryRow
                }
            } else {
                signedOutAccountPrompt
            }
            if usage.isPro {
                // The #1 complaint across this category's App Store reviews is
                // that cancellation is hidden. One tap to Apple's own manage /
                // cancel screen (2026-09-02).
                Button {
                    showingManageSubscriptions = true
                } label: {
                    EEONSettingsRow(
                        icon: "creditcard",
                        title: "Manage Subscription",
                        subtitle: "Change plan or cancel anytime"
                    ) {
                        EEONChevron()
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Account")
        }
    }

    private var assistantSettingsSection: some View {
        Section {
            // Ask answer-style used to be a whole sub-screen for one picker.
            // Inline it (Shawn, 2026-09-02: "everything's in a sub-menu").
            Picker(selection: $askModelPreferenceRaw) {
                ForEach(AskModelPreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            } label: {
                Label("Answer style", systemImage: "sparkle.magnifyingglass")
            }
            .pickerStyle(.menu)

            autoSummarizeRow
            personalizationSettingsRow
            captureSettingsRow
            peopleSpeakersSettingsRow
        } header: {
            Text("Assistant")
        }
    }

    private var connectionsSettingsSection: some View {
        // Inlined 2026-09-01 (Shawn): the calendar and reminder toggles used
        // to hide one tap deep behind a "Calendars & Connections" row. They
        // are the settings people actually flip, so they live on the root now;
        // only the AI-connector / iCloud status detail stays behind a tap.
        Section {
            calendarContextRow
            googleCalendarRow
            remindersSyncRow
            NavigationLink {
                AIAccessSetupView()
            } label: {
                EEONSettingsRow(
                    icon: "sparkle.magnifyingglass",
                    title: "Set up AI access",
                    subtitle: AIAccessService.shared.isConnected ? "Connected · manage" : "Connect Claude, Cursor, or ChatGPT"
                )
            }
        } header: {
            Text("Connections")
        } footer: {
            Text("Calendar and Reminders are read-only meeting context. AI access is set up inside each AI tool on your computer — it is not a switch here.")
        }
    }

    private var dataSettingsSection: some View {
        Section {
            syncSettingsRow
            exportSettingsRow
        } header: {
            Text("Data")
        }
    }

    private var helpSettingsSection: some View {
        Section {
            helpSettingsRow
            #if DEBUG
            developerSettingsRow
            #endif
        } header: {
            Text("Help")
        } footer: {
            Text(Self.buildDescription)
                .font(EEONType.meta)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var body: some View {
        NavigationStack {
            // Settings is a compact table of contents: account, core behavior,
            // connections, alerts, data, and help. Explanatory copy belongs one
            // tap deeper so the root stays scannable.
            List {
                accountSettingsSection
                assistantSettingsSection
                connectionsSettingsSection
                NotificationSettingsSection()
                dataSettingsSection
                helpSettingsSection

                // MARK: - Developer Section (DEBUG only)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await refreshiCloudStatus()
                await loadDiagnostics()
            }
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
            .alert("Sign In Error", isPresented: Binding(
                get: { signInError != nil },
                set: { if !$0 { signInError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(signInError ?? "")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [URL(string: "https://apps.apple.com/us/app/voice-notes-knowledge-wiki/id6758273499")!])
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(onDismiss: {
                    showingPaywall = false
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
                Button("Sign Out", role: .destructive) {
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
            .alert("Export failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $showingExportShareSheet) {
                if let url = exportURL {
                    ExportShareSheet(url: url)
                }
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
        case "purple": return Color("EEONAccentAI")
        case "pink": return .pink
        default: return .blue
        }
    }

    private func signOutOnly() {
        AuthService.shared.signOut()
        dismiss()
    }

    /// Generate the markdown export, then immediately present the iOS share
    /// sheet so the user can save/share the file without a second tap.
    private func generateExport() {
        isExporting = true
        exportError = nil
        Task {
            do {
                let url = try ExportService.generateExport(context: modelContext)
                exportURL = url
                isExporting = false
                showingExportShareSheet = true
            } catch {
                exportError = error.localizedDescription
                isExporting = false
            }
        }
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
        // Dismiss first, then clear data after sheet animation completes
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AuthService.shared.clearAllUserData()
        }
    }
}

private struct PeopleSpeakersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var people: [MentionedPerson]
    @Query private var notes: [Note]
    @Query private var actions: [ExtractedAction]
    @Query private var commitments: [ExtractedCommitment]
    @Query private var articles: [KnowledgeArticle]

    private struct SpeakerNameRow: Identifiable {
        let name: String
        let count: Int
        var id: String { name.lowercased() }
    }

    @State private var editingName: String?
    @State private var editedName = ""

    private var activePeople: [MentionedPerson] {
        people.filter { !$0.isArchived }
    }

    private var namedSpeakers: [SpeakerNameRow] {
        var counts: [String: Int] = [:]
        for note in notes {
            for label in note.speakerLabels {
                let displayName = label.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !displayName.isEmpty, !displayName.lowercased().hasPrefix("speaker ") else { continue }
                counts[displayName, default: 0] += 1
            }
        }
        return counts
            .map { SpeakerNameRow(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
    }

    var body: some View {
        List {
            Section {
                if activePeople.isEmpty {
                    emptyRow("People named in notes will appear here.")
                } else {
                    ForEach(activePeople) { person in
                        Button {
                            beginRename(person.displayName)
                        } label: {
                            EEONSettingsRow(
                                icon: "person",
                                title: person.displayName,
                                subtitle: "\(person.mentionCount) mentions"
                            ) {
                                EEONChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("People")
            } footer: {
                Text("Rename a person here to update extracted people, commitments, and transcript speaker labels that use the same name.")
                    .font(EEONType.meta)
            }

            Section {
                if namedSpeakers.isEmpty {
                    emptyRow("Named transcript speakers will appear here.")
                } else {
                    ForEach(namedSpeakers) { speaker in
                        Button {
                            beginRename(speaker.name)
                        } label: {
                            EEONSettingsRow(
                                icon: "person.2",
                                title: speaker.name,
                                subtitle: "\(speaker.count) speaker labels"
                            ) {
                                EEONChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Named Speakers")
            } footer: {
                Text("EEON can rename saved speaker labels globally. Automatic voice-print identification still requires a dedicated diarization provider.")
                    .font(EEONType.meta)
            }
        }
        .navigationTitle("People & Speakers")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename", isPresented: Binding(
            get: { editingName != nil },
            set: { if !$0 { editingName = nil; editedName = "" } }
        )) {
            TextField("Name", text: $editedName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                editingName = nil
                editedName = ""
            }
            Button("Save") {
                if let oldName = editingName {
                    rename(oldName, to: editedName)
                }
                editingName = nil
                editedName = ""
            }
        } message: {
            Text("This updates matching people and speaker labels across your notes.")
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(EEONType.meta)
            .foregroundStyle(.eeonTextSecondary)
            .padding(.vertical, 4)
    }

    private func beginRename(_ name: String) {
        editingName = name
        editedName = name
    }

    private func rename(_ oldName: String, to rawNewName: String) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldNormalized = MentionedPerson.normalize(oldName)
        let newNormalized = MentionedPerson.normalize(newName)
        guard !newName.isEmpty, !oldNormalized.isEmpty, oldNormalized != newNormalized else { return }

        mergePeople(oldNormalized: oldNormalized, newName: newName, newNormalized: newNormalized)
        let changedArticles = renamePersonArticles(
            oldName: oldName,
            oldNormalized: oldNormalized,
            newName: newName,
            newNormalized: newNormalized
        )
        let changedActions = renameActions(oldNormalized: oldNormalized, newName: newName)
        let changedCommitments = renameCommitments(oldNormalized: oldNormalized, newName: newName, newNormalized: newNormalized)

        var changedNotes: [Note] = []
        for note in notes {
            var changed = false

            let renamedPeople = note.mentionedPeople.map { name in
                MentionedPerson.normalize(name) == oldNormalized ? newName : name
            }
            let dedupedPeople = dedupedNames(renamedPeople)
            if dedupedPeople != note.mentionedPeople {
                note.mentionedPeople = dedupedPeople
                changed = true
            }

            var labels = note.speakerLabels
            for index in labels.indices {
                let labelName = labels[index].displayName
                if MentionedPerson.normalize(labelName) == oldNormalized {
                    labels[index].name = newName
                    changed = true
                }
            }
            if labels != note.speakerLabels {
                note.speakerLabels = labels
                changed = true
            }

            if changed {
                note.updatedAt = Date()
                changedNotes.append(note)
            }
        }
        let changedNoteIds = Set(
            changedNotes.map(\.id) +
            changedActions.compactMap(\.sourceNoteId) +
            changedCommitments.compactMap(\.sourceNoteId)
        )

        try? modelContext.save()

        for note in notes where changedNoteIds.contains(note.id) {
            DocumentExportService.shared.export(note: note, context: modelContext)
        }
        for article in changedArticles {
            DocumentExportService.shared.removeExportedArticleFile(for: article, previousName: oldName)
            DocumentExportService.shared.export(article: article)
        }
        if !changedActions.isEmpty {
            Task {
                for action in changedActions {
                    await EventKitSyncService.shared.sync(actions: [action])
                }
            }
        }
        TranscriptionVocabulary.shared.refreshLearned(context: modelContext)
    }

    private func mergePeople(oldNormalized: String, newName: String, newNormalized: String) {
        let target = people.first { $0.normalizedName == newNormalized }
        for person in people where person.normalizedName == oldNormalized {
            if let target, target.id != person.id {
                target.mentionCount += person.mentionCount
                target.firstMentionedAt = min(target.firstMentionedAt, person.firstMentionedAt)
                target.lastMentionedAt = max(target.lastMentionedAt, person.lastMentionedAt)
                target.openCommitmentCount += person.openCommitmentCount
                modelContext.delete(person)
            } else {
                person.name = newName
                person.normalizedName = newNormalized
            }
        }
    }

    private func renamePersonArticles(
        oldName: String,
        oldNormalized: String,
        newName: String,
        newNormalized: String
    ) -> [KnowledgeArticle] {
        let matching = articles.filter { article in
            article.articleType == .person &&
            (MentionedPerson.normalize(article.name) == oldNormalized ||
             article.aliases.contains(oldNormalized))
        }
        let target = articles.first {
            $0.articleType == .person && MentionedPerson.normalize($0.name) == newNormalized
        }

        var changed: [KnowledgeArticle] = []
        for article in matching {
            if let target, target.id != article.id {
                target.mentionCount += article.mentionCount
                target.lastMentionedAt = maxOptionalDate(target.lastMentionedAt, article.lastMentionedAt)
                target.linkedNoteIds = dedupedUUIDs(target.linkedNoteIds + article.linkedNoteIds)
                target.addAlias(oldName)
                target.addAlias(article.name)
                target.isDirty = true
                target.updatedAt = Date()
                DocumentExportService.shared.removeExportedArticleFile(for: article, previousName: article.name)
                modelContext.delete(article)
                changed.append(target)
            } else {
                article.addAlias(oldName)
                article.name = newName
                article.aliases = dedupedNames(article.aliases + [newNormalized, oldNormalized])
                article.isDirty = true
                article.updatedAt = Date()
                changed.append(article)
            }
        }
        return Array(Dictionary(grouping: changed, by: \.id).compactMap { $0.value.first })
    }

    private func renameActions(oldNormalized: String, newName: String) -> [ExtractedAction] {
        var changed: [ExtractedAction] = []
        for action in actions where MentionedPerson.normalize(action.owner) == oldNormalized {
            action.owner = newName
            changed.append(action)
        }
        return changed
    }

    private func renameCommitments(oldNormalized: String, newName: String, newNormalized: String) -> [ExtractedCommitment] {
        var changed: [ExtractedCommitment] = []
        for commitment in commitments {
            var didChange = false
            if let personName = commitment.personName, personName == oldNormalized {
                commitment.personName = newNormalized
                didChange = true
            }
            if MentionedPerson.normalize(commitment.who) == oldNormalized {
                commitment.who = newName
                didChange = true
            }
            if didChange {
                changed.append(commitment)
            }
        }
        return changed
    }

    private func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (let lhs?, nil): return lhs
        case (nil, let rhs?): return rhs
        case (let lhs?, let rhs?): return max(lhs, rhs)
        }
    }

    private func dedupedUUIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            out.append(id)
        }
        return out
    }

    private func dedupedNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = MentionedPerson.normalize(trimmed)
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}

private struct SettingsAppleSignInButton: View {
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            onCompletion(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .cornerRadius(EEONLayout.cardRadius)
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
                    .fill(Color("EEONAccentAI").opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "note.text")
                    .foregroundStyle(Color("EEONAccentAI"))
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
        case "purple": return Color("EEONAccentAI")
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
                                .foregroundStyle(Color("EEONAccent"))
                        }
                    }
                }
            }
        }
        .navigationTitle("Transcription Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Settings Section

struct NotificationSettingsSection: View {
    @AppStorage("proactiveRemindersEnabled") private var proactiveRemindersEnabled = true
    @AppStorage("dailyBriefEnabled") private var dailyBriefEnabled = true

    @State private var briefTime: Date = {
        let scheduler = NotificationScheduler.shared
        var components = DateComponents()
        components.hour = scheduler.dailyBriefHour
        components.minute = scheduler.dailyBriefMinute
        return Calendar.current.date(from: components) ?? Date()
    }()

    var body: some View {
        Section {
            Toggle(isOn: $proactiveRemindersEnabled) {
                HStack(spacing: 16) {
                    EEONSettingsIcon(systemName: "bell.badge")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proactive reminders")
                            .font(.body)
                        Text("Alerts for stale commitments, overdue actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .onChange(of: proactiveRemindersEnabled) { _, enabled in
                if !enabled {
                    NotificationScheduler.shared.removeAllPendingNotifications()
                }
            }

            // Daily-brief notification toggle removed 2026-08-20 — the brief
            // no longer has a home surface; the toggle was orphaned confusion.

            // Brief-time picker removed with the daily-brief toggle (2026-08-20).
        } header: {
            Text("Notifications")
        }
    }
}

// MARK: - Export Share Sheet

/// Wraps UIActivityViewController so we can present the iOS share sheet as a
/// SwiftUI sheet. Used for the "Export My Data" flow — once the markdown file
/// URL exists, this sheet lets the user save it to Files, AirDrop it, email it,
/// or open it in Obsidian / Notion / any text editor.
private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: [Note.self, Project.self, Tag.self], inMemory: true)
}
