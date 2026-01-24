//
//  RecordingView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var audioRecorder = AudioRecorder()
    @State private var recordingState: RecordingState = .idle
    @State private var audioFileName: String?
    @State private var transcript: String?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var hasPermission = false
    @State private var waveformPhase: CGFloat = 0

    enum RecordingState {
        case idle
        case recording
        case transcribing
        case complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top section with waveform
                ZStack {
                    // Gradient background
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.5, blue: 1.0),
                            Color(red: 0.3, green: 0.7, blue: 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Waveform visualization
                    if recordingState == .recording {
                        WaveformView(phase: waveformPhase)
                            .onAppear {
                                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                    waveformPhase = .pi * 2
                                }
                            }
                    }

                    VStack {
                        Text("Recording")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(audioRecorder.formattedTime)
                            .font(.system(size: 56, weight: .light, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 200)

                // Main content area
                VStack(spacing: 32) {
                    Spacer()

                    if recordingState == .transcribing {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Transcribing audio...")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    } else if recordingState == .complete {
                        // Show transcript preview
                        if let transcript = transcript {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Transcript", systemImage: "text.quote")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                ScrollView {
                                    Text(transcript)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }

                        // Save/Discard buttons
                        HStack(spacing: 16) {
                            Button(action: discardRecording) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Discard")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.red)
                                .cornerRadius(12)
                            }

                            Button(action: saveRecording) {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Save")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Status text
                        Text(recordingState == .recording ? "Tap to stop" : "Tap to start recording")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Record button
                        Button(action: toggleRecording) {
                            ZStack {
                                // Outer ring
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 4)
                                    .frame(width: 88, height: 88)

                                // Inner button
                                if recordingState == .recording {
                                    // Stop square
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red)
                                        .frame(width: 32, height: 32)
                                } else {
                                    // Record circle
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 72, height: 72)
                                }
                            }
                        }
                        .disabled(!hasPermission && recordingState == .idle)

                        // Cancel and Pause buttons (when recording)
                        if recordingState == .recording {
                            HStack(spacing: 60) {
                                Button(action: cancelRecording) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.title2)
                                        Text("Cancel")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                Button(action: {}) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "pause")
                                            .font(.title2)
                                        Text("Pause")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 32)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recordingState == .recording {
                            _ = audioRecorder.stopRecording()
                        }
                        if let fileName = audioFileName {
                            audioRecorder.deleteRecording(fileName: fileName)
                        }
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .task {
                hasPermission = await audioRecorder.requestPermission()
                if !hasPermission {
                    errorMessage = "Microphone access is required for recording. Please enable it in Settings."
                    showingError = true
                }
            }
        }
    }

    private func toggleRecording() {
        if recordingState == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            audioFileName = try audioRecorder.startRecording()
            recordingState = .recording
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording"
            showingError = true
            return
        }

        recordingState = .transcribing
        transcribeAudio(url: url)
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = audioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        audioFileName = nil
        recordingState = .idle
    }

    private func transcribeAudio(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            recordingState = .complete
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey)
                let result = try await service.transcribe(audioURL: url)

                await MainActor.run {
                    transcript = result
                    recordingState = .complete
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    recordingState = .complete
                }
            }
        }
    }

    private func discardRecording() {
        if let fileName = audioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        dismiss()
    }

    private func saveRecording() {
        let note = Note(
            transcript: transcript,
            audioFileName: audioFileName
        )
        modelContext.insert(note)

        // Auto-extract tags if we have a transcript
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

        dismiss()
    }
}

// Waveform visualization
struct WaveformView: View {
    var phase: CGFloat

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, through: width, by: 2) {
                    let relativeX = x / width
                    let sine = sin((relativeX * 4 * .pi) + phase)
                    let amplitude = 20.0 * (1 - abs(relativeX - 0.5) * 2)
                    let y = midY + sine * amplitude
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(.red.opacity(0.8)), lineWidth: 2)
        }
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: [Note.self, Tag.self], inMemory: true)
}
