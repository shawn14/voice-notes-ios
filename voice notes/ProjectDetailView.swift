//
//  ProjectDetailView.swift
//  voice notes
//
//  Notes flow through Kanban columns
//  Clean card-based design
//

import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query private var tags: [Tag]

    @State private var selectedColumn: KanbanColumn = .thinking
    @State private var searchText = ""

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Notes belonging to this project
    private var projectNotes: [Note] {
        allNotes.filter { $0.projectId == project.id }
    }

    // Filtered notes for selected column
    private var filteredNotes: [Note] {
        var notes = projectNotes.filter { $0.kanbanColumn == selectedColumn }

        if !searchText.isEmpty {
            notes = notes.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    // Count for each column
    private func count(for column: KanbanColumn) -> Int {
        projectNotes.filter { $0.kanbanColumn == column }.count
    }

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
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
                .padding(.top, 8)

                // Column filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(KanbanColumn.allCases, id: \.self) { column in
                            ProjectColumnTab(
                                column: column,
                                count: count(for: column),
                                isSelected: selectedColumn == column
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedColumn = column
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
                        Image(systemName: "note.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("No notes in \(selectedColumn.rawValue)")
                            .font(.headline)
                            .foregroundStyle(.gray)
                        Text("Record a voice note to get started")
                            .font(.subheadline)
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredNotes) { note in
                                NoteCard(
                                    note: note,
                                    column: selectedColumn,
                                    onMoveForward: { moveForward(note) },
                                    onMoveBackward: { moveBackward(note) }
                                )
                            }
                        }
                        .padding(.bottom, 120) // Space for record button
                    }
                }
            }

            // Record button at bottom
            VStack {
                Spacer()
                ProjectRecordButton(
                    isRecording: isRecording,
                    isTranscribing: isTranscribing,
                    onTap: toggleRecording
                )
                .padding(.bottom, 30)
            }

            // Recording overlay
            if isRecording {
                ProjectRecordingOverlay(
                    onStop: stopRecording,
                    onCancel: cancelRecording
                )
            }

            // Transcribing overlay
            if isTranscribing {
                ProjectTranscribingOverlay()
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func moveForward(_ note: Note) {
        let columns = KanbanColumn.allCases
        guard let currentIndex = columns.firstIndex(of: note.kanbanColumn),
              currentIndex < columns.count - 1 else { return }

        note.kanbanColumn = columns[currentIndex + 1]
    }

    private func moveBackward(_ note: Note) {
        let columns = KanbanColumn.allCases
        guard let currentIndex = columns.firstIndex(of: note.kanbanColumn),
              currentIndex > 0 else { return }

        note.kanbanColumn = columns[currentIndex - 1]
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
            audioFileName: currentAudioFileName,
            projectId: project.id  // Automatically assign to this project
        )
        modelContext.insert(note)

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

// MARK: - Project Column Tab

struct ProjectColumnTab: View {
    let column: KanbanColumn
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(column.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .foregroundStyle(isSelected ? .white : .gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? column.color : Color(.systemGray5).opacity(0.3))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Note Card

struct NoteCard: View {
    let note: Note
    let column: KanbanColumn
    let onMoveForward: () -> Void
    let onMoveBackward: () -> Void

    var body: some View {
        NavigationLink(destination: NoteEditorView(note: note)) {
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

                    // AI Insight
                    if let insight = note.aiInsight, !insight.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text(insight)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // Move buttons
                HStack(spacing: 4) {
                    if column != .thinking {
                        Button(action: onMoveBackward) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if column != .done {
                        Button(action: onMoveForward) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(8)
                                .background(Color.green.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Record Button

struct ProjectRecordButton: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.3) : Color.red)
                    .frame(width: 72, height: 72)

                if isTranscribing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: isRecording ? 24 : 28, height: isRecording ? 24 : 28)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                }
            }
            .shadow(color: .red.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(isTranscribing)
    }
}

// MARK: - Recording Overlay

struct ProjectRecordingOverlay: View {
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Pulsing mic icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }

                Text("Recording...")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 40) {
                    Button(action: onCancel) {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.gray)
                            Text("Cancel")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }

                    Button(action: onStop) {
                        VStack(spacing: 8) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.red)
                            Text("Stop")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Transcribing Overlay

struct ProjectTranscribingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Transcribing...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let project = Project(name: "EEON", icon: "folder", colorName: "blue")
    return NavigationStack {
        ProjectDetailView(project: project)
    }
    .modelContainer(for: [Project.self, Note.self], inMemory: true)
    .preferredColorScheme(.dark)
}
