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

// MARK: - Filter Options

enum NoteFilter: String, CaseIterable {
    case all = "All Notes"
    case projects = "Projects"
    case favorites = "Favorites"
    case recent = "Recent"

    var icon: String {
        switch self {
        case .all: return "waveform"
        case .projects: return "folder"
        case .favorites: return "star"
        case .recent: return "clock"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var tags: [Tag]

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

    // Filtered notes based on search and filter
    private var filteredNotes: [Note] {
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
            // For now, show notes with tags (could add a favorite flag later)
            result = result.filter { !$0.tags.isEmpty }
        case .recent:
            // Show notes from last 7 days
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { $0.createdAt >= weekAgo }
        }

        return result
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
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundStyle(.gray)
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

                    // Search bar
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

                    // Filter tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(NoteFilter.allCases, id: \.self) { filter in
                                FilterTab(
                                    title: filter.rawValue,
                                    isSelected: selectedFilter == filter
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedFilter = filter
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

                    // Notes list
                    if filteredNotes.isEmpty {
                        Spacer()
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
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(filteredNotes) { note in
                                    NavigationLink(destination: NoteEditorView(note: note)) {
                                        HomeNoteRow(note: note)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 120) // Space for bottom bar
                        }
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

                // Sign in button (bottom right) - shows when not signed in
                if !AuthService.shared.isSignedIn && !isRecording && !isTranscribing {
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
                        onCancel: cancelRecording
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
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
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
                let service = TranscriptionService(apiKey: apiKey)
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

        // Track usage
        if let fileName = currentAudioFileName {
            trackRecordingUsage(fileName: fileName)
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

        // AI processing for title and tags
        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let context = modelContext

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

    private func trackRecordingUsage(fileName: String) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsURL.appendingPathComponent(fileName)

        let asset = AVURLAsset(url: audioURL)
        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    UsageService.shared.addRecordingTime(seconds: Int(seconds))
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

    var body: some View {
        HStack(spacing: 16) {
            // Mic icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: note.hasAudio ? "mic.fill" : "note.text")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()

            // Duration (if audio)
            if note.hasAudio {
                Text("00:07") // TODO: Store actual duration
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
    }
}

// MARK: - Bottom Record Button

struct HomeBottomBar: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let onRecord: () -> Void

    var body: some View {
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

// MARK: - Recording Overlay

struct HomeRecordingOverlay: View {
    let onStop: () -> Void
    let onCancel: () -> Void

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

                Text("Recording...")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)

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
                ProgressView()
                    .scaleEffect(2)
                    .tint(.white)

                Text("Transcribing...")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
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

    @State private var showingAddProject = false
    @State private var newProjectName = ""
    @State private var showingShareSheet = false
    @State private var showingPaywall = false
    @State private var showingResetConfirm = false
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteAllDataConfirm = false

    private let usage = UsageService.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Usage Section
                Section {
                    // AI Extractions remaining
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Extractions")
                                .font(.body.weight(.medium))
                            if usage.isPro {
                                Text("Unlimited")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(usage.freeExtractionsRemaining) of 5 remaining")
                                    .font(.caption)
                                    .foregroundColor(usage.freeExtractionsRemaining > 0 ? .secondary : .red)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Resolutions remaining
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Actions Resolved")
                                .font(.body.weight(.medium))
                            if usage.isPro {
                                Text("Unlimited")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(usage.freeResolutionsRemaining) of 3 remaining")
                                    .font(.caption)
                                    .foregroundColor(usage.freeResolutionsRemaining > 0 ? .secondary : .red)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Recording (unlimited)
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "mic.fill")
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording")
                                .font(.body.weight(.medium))
                            Text("Unlimited (\(usage.totalRecordingTimeString) recorded)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Notes count
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "note.text")
                                .foregroundStyle(.blue)
                        }

                        Text("Total Notes: \(notes.count)")
                            .font(.body)

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Stats
                    if usage.totalExtractionsUsed > 0 || usage.totalResolutionsUsed > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total extractions: \(usage.totalExtractionsUsed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Total resolutions: \(usage.totalResolutionsUsed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Usage")
                }

                // MARK: - Account Section
                Section {
                    // Account info
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: AuthService.shared.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            if AuthService.shared.isSignedIn {
                                Text(AuthService.shared.displayName)
                                    .font(.body.weight(.medium))
                                if let email = AuthService.shared.userEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Not signed in")
                                    .font(.body.weight(.medium))
                                Text("Local data only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
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

                    // Sign Out (keeps data)
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

                    // Delete All Data (destructive)
                    Button {
                        showingDeleteAllDataConfirm = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                                .frame(width: 44)

                            Text("Delete All Data")
                                .font(.body)
                                .foregroundStyle(.red)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
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
                        Text("Language Settings")
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "globe")
                                .foregroundStyle(.green)
                                .frame(width: 44)

                            Text("Transcription Language")
                                .font(.body)

                            Spacer()

                            Text("English")
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
                        if let url = URL(string: "mailto:support@voicenotes.app") {
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
                        if let url = URL(string: "https://voicenotes.app/privacy") {
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
                } header: {
                    Text("Support")
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
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [URL(string: "https://apps.apple.com/app/voice-notes")!])
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
                Button("Sign Out") {
                    signOutOnly()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your notes will be kept and synced with iCloud. You can sign back in anytime.")
            }
            .confirmationDialog("Delete All Data?", isPresented: $showingDeleteAllDataConfirm, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllDataAndSignOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all your notes, projects, and data. This cannot be undone.")
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
        // Delete all notes
        for note in notes {
            modelContext.delete(note)
        }

        // Delete all projects
        for project in projects {
            modelContext.delete(project)
        }

        // Sign out and reset
        AuthService.shared.signOut()

        // Reset onboarding flag to show sign in screen again
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")

        // Dismiss settings
        dismiss()
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

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: [Note.self, Project.self, Tag.self], inMemory: true)
}
