//
//  HomeView.swift
//  voice notes
//
//  All Notes home page with filter tabs
//  Clean Wave-style design
//

import SwiftUI
import SwiftData

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
                                .foregroundStyle(.purple)
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

        // Force save to persist immediately
        try? modelContext.save()

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
                .background(isSelected ? Color.purple : Color(.systemGray5).opacity(0.3))
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
        case "purple": return .purple
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
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @State private var showingAddProject = false
    @State private var newProjectName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Projects") {
                    ForEach(projects) { project in
                        NavigationLink(destination: ProjectEditView(project: project)) {
                            HStack {
                                Image(systemName: project.icon)
                                    .foregroundStyle(projectColor(project.colorName))
                                Text(project.name)
                                Spacer()
                                Text("\(project.aliases.count) aliases")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteProjects)

                    Button(action: { showingAddProject = true }) {
                        Label("Add Project", systemImage: "plus.circle")
                    }
                }

                Section("Preferences") {
                    Text("Audio Quality")
                    Text("Transcription Language")
                }

                Section("About") {
                    Text("Version 1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        case "purple": return .purple
        case "pink": return .pink
        default: return .blue
        }
    }
}

// MARK: - Project Edit View

struct ProjectEditView: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var newAlias = ""

    private let availableColors = ["blue", "red", "orange", "green", "purple", "pink", "yellow"]
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
        case "purple": return .purple
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
