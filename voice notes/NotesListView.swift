//
//  NotesListView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var tags: [Tag]

    @State private var searchText = ""
    @State private var selectedTag: Tag?
    @State private var showingNewNote = false
    @State private var pulseAnimation = false

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    let noteColors: [Color] = [
        Color(red: 1.0, green: 0.95, blue: 0.7),   // Yellow sticky
        Color(red: 1.0, green: 0.85, blue: 0.85),  // Pink sticky
        Color(red: 0.95, green: 0.95, blue: 0.9),  // Cream/white
        Color(red: 0.85, green: 0.9, blue: 1.0),   // Light blue
    ]

    var filteredNotes: [Note] {
        var result = notes

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                ($0.transcript?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Tag filter pills
                        if !tags.isEmpty && !isRecording {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    TagPill(
                                        name: "All",
                                        isSelected: selectedTag == nil,
                                        action: { selectedTag = nil }
                                    )

                                    ForEach(tags) { tag in
                                        TagPill(
                                            name: tag.name,
                                            isSelected: selectedTag == tag,
                                            action: { selectedTag = tag }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Notes grid
                        if filteredNotes.isEmpty && !isRecording {
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 60)

                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.red.opacity(0.3))

                                Text("No Notes Yet")
                                    .font(.title2.bold())
                                    .foregroundStyle(.secondary)

                                Text("Tap the record button to start")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)

                                Image(systemName: "arrow.down")
                                    .font(.title)
                                    .foregroundStyle(.red.opacity(0.5))
                                    .padding(.top, 20)
                            }
                        } else if !isRecording {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, note in
                                    NavigationLink(destination: NoteEditorView(note: note)) {
                                        StickyNoteCard(
                                            note: note,
                                            color: noteColors[index % noteColors.count]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteNote(note)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 120)
                        }
                    }
                    .padding(.top)
                }

                // Recording Overlay
                if isRecording || isTranscribing {
                    RecordingOverlay(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        recordingTime: audioRecorder.formattedTime,
                        onStop: stopRecording,
                        onCancel: cancelRecording
                    )
                }

                // Floating Record Button (only when not recording)
                if !isRecording && !isTranscribing {
                    VStack {
                        Spacer()

                        HStack {
                            // Text note button
                            Button(action: { showingNewNote = true }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color(.systemGray))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }

                            Spacer()

                            // Big Record Button
                            Button(action: startRecording) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.2))
                                        .frame(width: 90, height: 90)
                                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                        .opacity(pulseAnimation ? 0 : 0.6)

                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 80, height: 80)

                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.red, Color(red: 0.8, green: 0, blue: 0)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 70, height: 70)
                                        .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)

                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                    pulseAnimation = true
                                }
                            }

                            Spacer()

                            Color.clear
                                .frame(width: 50, height: 50)
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 20)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search notes")
            .navigationTitle("Voice Notes")
            .sheet(isPresented: $showingNewNote) {
                NavigationStack {
                    NoteEditorView(note: nil)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .task {
                let _ = await audioRecorder.requestPermission()
            }
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
            // Save without transcription
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
                    // Save without transcription on error
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func saveNote(transcript: String?) {
        let note = Note(
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        modelContext.insert(note)

        // Auto-extract tags
        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            Task {
                do {
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: transcript)

                    await MainActor.run {
                        for name in tagNames {
                            let tag = Tag(name: name)
                            modelContext.insert(tag)
                            note.tags.append(tag)
                        }
                    }
                } catch {
                    print("Tag extraction failed: \(error)")
                }
            }
        }

        currentAudioFileName = nil
        isTranscribing = false
    }

    private func deleteNote(_ note: Note) {
        if let fileName = note.audioFileName {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(note)
    }
}

// Recording Overlay - shown while recording
struct RecordingOverlay: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let recordingTime: String
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var wavePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                if isTranscribing {
                    // Transcribing state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)

                        Text("Transcribing...")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    // Recording state
                    // Animated waveform
                    HStack(spacing: 4) {
                        ForEach(0..<20, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 4, height: waveHeight(for: i))
                        }
                    }
                    .frame(height: 60)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            wavePhase = 1
                        }
                    }

                    // Timer
                    Text(recordingTime)
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("Recording...")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                if !isTranscribing {
                    // Control buttons
                    HStack(spacing: 50) {
                        // Cancel button
                        Button(action: onCancel) {
                            VStack(spacing: 8) {
                                Image(systemName: "xmark")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())

                                Text("Cancel")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        // Stop button
                        Button(action: onStop) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 80, height: 80)

                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                }

                                Text("Stop")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let base = 20.0
        let variance = 30.0 * wavePhase
        let offset = sin(Double(index) * 0.5 + wavePhase * .pi * 2)
        return base + variance * CGFloat(abs(offset))
    }
}

struct StickyNoteCard: View {
    let note: Note
    let color: Color

    @State private var rotation: Double = Double.random(in: -2...2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.displayTitle)
                .font(.system(.headline, design: .serif))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(.black.opacity(0.8))

            if !note.content.isEmpty {
                Text(note.content)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(4)
            } else if let transcript = note.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(4)
            }

            Spacer()

            HStack {
                Text(note.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.black.opacity(0.4))

                Spacer()

                if note.hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.5))
                }
            }

            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(2)) { tag in
                        Text(tag.name)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.1))
                            .cornerRadius(4)
                    }
                    if note.tags.count > 2 {
                        Text("+\(note.tags.count - 2)")
                            .font(.system(size: 9))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
            }
        }
        .padding(12)
        .frame(minHeight: 150)
        .background(color)
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 2)
        .rotationEffect(.degrees(rotation))
    }
}

struct TagPill: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.red : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Note.self, Tag.self], inMemory: true)
}
