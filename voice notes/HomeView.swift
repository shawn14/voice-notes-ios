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
                    if authService.isSignedIn, let firstName = authService.displayName.components(separatedBy: " ").first, !firstName.isEmpty {
                        Text("Hi, \(firstName)")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color("EEONTextPrimary"))
                    } else {
                        Text("All Notes")
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
                                    Text("Sign In")
                                        .font(.headline)
                                        .foregroundStyle(Color("EEONTextPrimary"))
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
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("Sign In")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color("EEONTextPrimary"))
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
    let audioRecorder: AudioRecorder

    // Waveform bars driven by real audio metering — 8 bold bars
    private let barCount = 8
    @State private var barLevels: [CGFloat] = Array(repeating: 0.15, count: 8)
    @State private var meterTimer: Timer?

    // Ring pulse animation
    @State private var ringScales: [CGFloat] = [1.0, 1.0, 1.0]
    @State private var ringOpacities: [Double] = [0.18, 0.12, 0.06]
    @State private var ringAnimating = false

    // Timer dot blink
    @State private var dotVisible = true

    // Live transcription
    @State private var liveTranscription = LiveTranscriptionService()

    // Blinking cursor
    @State private var cursorVisible = true

    private let usageService = UsageService.shared
    private let accentRed = Color("EEONAccent")

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top bar: close button + timer pill
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // MARK: - Waveform strip with ring pulses
                waveformSection
                    .padding(.top, 32)

                // MARK: - Live transcript (hero)
                transcriptSection
                    .padding(.top, 24)

                Spacer()

                // MARK: - Bottom: Pro upsell + controls
                bottomControls
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            startMetering()
            startDotBlink()
            startCursorBlink()
            startRingPulse()
            startLiveTranscription()
        }
        .onDisappear {
            meterTimer?.invalidate()
            meterTimer = nil
            liveTranscription.stop()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }

            Spacer()

            // Timer pill with red tint
            HStack(spacing: 6) {
                Circle()
                    .fill(accentRed)
                    .frame(width: 8, height: 8)
                    .opacity(dotVisible ? 1.0 : 0.3)

                Text(audioRecorder.formattedTime)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color("EEONTextPrimary"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(accentRed.opacity(0.15), in: Capsule())

            Spacer()

            // Invisible spacer to balance the close button
            Color.clear
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Waveform Section with Ring Pulses

    private var waveformSection: some View {
        ZStack {
            // Expanding ring pulses behind the waveform
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(accentRed.opacity(ringOpacities[i]), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScales[i])
            }

            // Bold waveform bars (8 thick capsules)
            HStack(alignment: .center, spacing: 10) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(accentRed)
                        .frame(width: 18, height: barHeight(for: index))
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.5)
                                .delay(Double(index) * 0.02),
                            value: barLevels[index]
                        )
                }
            }
        }
        .frame(height: 120)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = barLevels[index]
        let minHeight: CGFloat = 14
        let maxHeight: CGFloat = 100
        return minHeight + level * (maxHeight - minHeight)
    }

    // MARK: - Live Transcript Section

    private var transcriptSection: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    let confirmedText = liveTranscription.liveTranscript
                    let activeWord = liveTranscription.currentWord

                    if confirmedText.isEmpty && activeWord.isEmpty {
                        Text("Start speaking...")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white.opacity(0.3))
                    } else {
                        // Build attributed text: confirmed words in white, current word in red
                        (buildTranscriptText(confirmed: confirmedText, active: activeWord))
                            .font(.system(size: 22, weight: .regular))
                            .lineSpacing(6)
                    }

                    // Blinking cursor
                    Rectangle()
                        .fill(accentRed)
                        .frame(width: 2, height: 24)
                        .opacity(cursorVisible ? 1.0 : 0.0)
                        .padding(.top, 2)
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
        .padding(.horizontal, 24)
        .frame(maxHeight: 300)
    }

    private func buildTranscriptText(confirmed: String, active: String) -> Text {
        let confirmedText = Text(confirmed).foregroundColor(.white)

        guard !active.isEmpty else {
            return confirmedText
        }

        let separator = confirmed.isEmpty ? "" : " "
        let activeText = Text(active)
            .foregroundColor(accentRed)
            .fontWeight(.bold)

        return Text("\(confirmedText)\(separator)\(activeText)")
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 32) {
            // Pro upsell (free users only)
            if !usageService.isPro {
                HStack(spacing: 4) {
                    Text("\(usageService.freeNotesRemaining) notes left")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))

                    Text("\u{00B7}")
                        .foregroundStyle(.white.opacity(0.3))

                    Text("Get PRO for unlimited")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Three controls in a row
            HStack(spacing: 0) {
                // Restart button
                Button {
                    liveTranscription.stop()
                    onCancel()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .frame(maxWidth: .infinity)

                // Stop button (center, prominent)
                Button {
                    liveTranscription.stop()
                    onStop()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 3)
                            .frame(width: 72, height: 72)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(accentRed)
                            .frame(width: 28, height: 28)
                    }
                }
                .frame(maxWidth: .infinity)

                // Pause placeholder (AudioRecorder doesn't support pause)
                Color.clear
                    .frame(width: 56, height: 56)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Timers & Animation

    private func startMetering() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let level = audioRecorder.normalizedLevel

            // Each bar gets the current level with per-bar variation
            // for a flowing, organic wave feel
            var newLevels = [CGFloat]()
            for i in 0..<barCount {
                let phase = sin(Double(i) * 0.8 + Date().timeIntervalSinceReferenceDate * 4.0)
                let variation = CGFloat(phase) * 0.15
                let barLevel = max(0.05, min(1.0, level + variation + CGFloat.random(in: -0.06...0.06)))
                newLevels.append(barLevel)
            }
            barLevels = newLevels
        }
    }

    private func startDotBlink() {
        // Blink the recording dot every 0.8s
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                dotVisible.toggle()
            }
        }
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                cursorVisible.toggle()
            }
        }
    }

    private func startRingPulse() {
        // Animate 3 concentric rings expanding outward in sequence
        func pulseRing(_ index: Int) {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringScales[index] = 3.5
                ringOpacities[index] = 0.0
            }
        }

        // Stagger the three rings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) { pulseRing(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { pulseRing(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pulseRing(2) }
    }

    private func startLiveTranscription() {
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
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated sparkles icon
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent").opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color("EEONAccent"))
                        .symbolEffect(.pulse)
                }

                Text("Understanding your note...")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color("EEONTextPrimary"))

                Text("Transcribing and finding insights")
                    .font(.subheadline)
                    .foregroundStyle(Color("EEONTextSecondary"))
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

    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    private let usage = UsageService.shared

    private var accountSection: some View {
        Section {
            accountRow

            Button {
                if !usage.isPro { showingPaywall = true }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(usage.isPro ? Color("EEONAccentAI").opacity(0.15) : Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: usage.isPro ? "sparkles" : "star.fill")
                            .foregroundStyle(usage.isPro ? Color("EEONAccentAI") : .orange)
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
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if !usage.isPro {
                Button { showingPaywall = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles").foregroundStyle(Color("EEONAccent")).frame(width: 44)
                        Text("Upgrade to Pro").font(.body).foregroundStyle(.primary)
                        Spacer()
                        Text("$9.99/mo").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain).padding(.vertical, 4)
            }

            HStack(spacing: 16) {
                Image(systemName: "globe").foregroundStyle(Color("EEONAccentAI")).frame(width: 44)
                Text(AppInfo.versionString).font(.body)
                Spacer()
            }
            .padding(.vertical, 4)

            Button { showingShareSheet = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Color("EEONAccentAI")).frame(width: 44)
                    Text("Share Voice Notes").font(.body).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain).padding(.vertical, 4)

            if usage.isPro {
                Button { showingResetConfirm = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.orange).frame(width: 44)
                        Text("Downgrade to Free").font(.body).foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain).padding(.vertical, 4)
            }

            if authService.isSignedIn {
                Button { showingSignOutConfirm = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.primary).frame(width: 44)
                        Text("Sign Out").font(.body)
                        Spacer()
                    }
                }
                .buttonStyle(.plain).padding(.vertical, 4)
            } else {
                Button { showSignIn = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Color("EEONAccent")).frame(width: 44)
                        Text("Sign In").font(.body).foregroundStyle(Color("EEONAccent"))
                        Spacer()
                    }
                }
                .buttonStyle(.plain).padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }

    private var accountRow: some View {
        Button {
            editedName = authService.userName ?? ""
            showingEditName = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccentAI").opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: authService.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(Color("EEONAccentAI"))
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
                        .foregroundStyle(Color("EEONAccent"))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Appearance Section
                Section {
                    Picker("Appearance", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                // MARK: - Personalization
                Section {
                    NavigationLink {
                        TuneConversationView()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color("EEONAccent").opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "scope")
                                    .foregroundStyle(Color("EEONAccent"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tune EEON")
                                    .font(.body.weight(.medium))
                                Text("Who you are, what it's for")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        KnowledgeBaseView()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.brown.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "books.vertical.fill")
                                    .foregroundStyle(.brown)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Knowledge Base")
                                    .font(.body.weight(.medium))
                                Text("Books, articles, domain expertise")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Personalization")
                } footer: {
                    Text("Tell EEON who you are and what it's for. Auto-refines as you capture notes.")
                        .font(.caption)
                }

                // MARK: - Usage Section
                Section {
                    UsageSectionContent(usage: usage, noteCount: notes.count)
                } header: {
                    Text("Usage")
                }

                // MARK: - Account Section
                accountSection


                // MARK: - Preferences Section
                Section {
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

                // MARK: - Notifications Section
                NotificationSettingsSection()

                // MARK: - Support Section
                Section {
                    Button {
                        if let url = URL(string: "mailto:support@eeon.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "envelope")
                                .foregroundStyle(Color("EEONAccentAI"))
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
                                .foregroundStyle(Color("EEONAccentAI"))
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
                        OnboardingState.set(.needsSignIn)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(Color("EEONAccentAI"))
                                .frame(width: 44)

                            Text("Reset Onboarding")
                                .font(.body)
                                .foregroundStyle(Color("EEONAccentAI"))

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
                ShareSheet(items: [URL(string: "https://apps.apple.com/app/id6758273499")!])
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(onDismiss: {
                    showingPaywall = false
                })
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
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
        case "purple": return Color("EEONAccentAI")
        case "pink": return .pink
        default: return .blue
        }
    }

    private func signOutOnly() {
        // Dismiss settings first, then sign out after sheet animation completes
        // This avoids the sheet dismissal fighting the root view swap
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AuthService.shared.signOut()
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
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.orange)
                        .frame(width: 44)

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

            Toggle(isOn: $dailyBriefEnabled) {
                HStack(spacing: 16) {
                    Image(systemName: "sun.horizon")
                        .foregroundStyle(.yellow)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily brief notification")
                            .font(.body)
                        Text("Morning reminder to review your brief")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .onChange(of: dailyBriefEnabled) { _, enabled in
                Task {
                    if enabled {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: briefTime)
                        await NotificationScheduler.shared.scheduleDailyBriefReminder(
                            at: components.hour ?? 8,
                            minute: components.minute ?? 0
                        )
                    } else {
                        await NotificationScheduler.shared.scheduleDailyBriefReminder(at: 8, minute: 0)
                    }
                }
            }

            if dailyBriefEnabled {
                DatePicker(selection: $briefTime, displayedComponents: .hourAndMinute) {
                    HStack(spacing: 16) {
                        Image(systemName: "clock")
                            .foregroundStyle(Color("EEONAccentAI"))
                            .frame(width: 44)

                        Text("Brief time")
                            .font(.body)
                    }
                }
                .padding(.vertical, 4)
                .onChange(of: briefTime) { _, newTime in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                    Task {
                        await NotificationScheduler.shared.scheduleDailyBriefReminder(
                            at: components.hour ?? 8,
                            minute: components.minute ?? 0
                        )
                    }
                }
            }
        } header: {
            Text("Notifications")
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: [Note.self, Project.self, Tag.self], inMemory: true)
}
