//
//  MyEEONView.swift
//  voice notes
//
//  Personal context prompt — tells EEON who you are
//

import SwiftUI

struct MyEEONView: View {
    @Environment(\.dismiss) private var dismiss
    private var authService = AuthService.shared

    @State private var text: String = ""
    @State private var hasChanges = false
    @State private var isGeneratingReports = false

    // Voice recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var pulseAnimation = false

    private let charGuide = 500
    private let placeholder = "Tell EEON about yourself — your role, what you're building, your priorities. This helps personalize your briefs, extractions, and assistant responses.\n\nExample: \"I'm a solo founder building a B2B SaaS for logistics. My team is me + 2 contractors. I'm focused on closing our first 10 customers and shipping v2 by end of Q1.\""

    var body: some View {
        ZStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                        }

                        TextEditor(text: $text)
                            .font(.body)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .onChange(of: text) {
                                hasChanges = text != (authService.eeonContext ?? "")
                            }
                    }
                } header: {
                    HStack {
                        Text("About You")
                        Spacer()
                        // Voice input button
                        Button {
                            toggleRecording()
                        } label: {
                            Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                                .foregroundStyle(isRecording ? .red : .blue)
                                .symbolEffect(.pulse, isActive: isRecording)
                        }
                        .disabled(isTranscribing)
                    }
                } footer: {
                    HStack {
                        Text("\(text.count) characters")
                            .foregroundStyle(text.count > charGuide ? .orange : .secondary)
                        Spacer()
                        Text("~\(charGuide) recommended")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                Section {
                    Text("This context is prepended to every AI call — note extraction, daily briefs, and assistant chat. Your report options will also update to match your role.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isGeneratingReports {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating your reports...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(isRecording || isTranscribing)
            .blur(radius: (isRecording || isTranscribing) ? 3 : 0)

            // Recording overlay
            if isRecording {
                recordingOverlay
            }

            // Transcribing overlay
            if isTranscribing {
                transcribingOverlay
            }
        }
        .navigationTitle("My EEON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndGenerateReports()
                }
                .disabled(!hasChanges || isGeneratingReports || isRecording || isTranscribing)
            }
        }
        .onAppear {
            text = authService.eeonContext ?? ""
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
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

                Text(audioRecorder.formattedTime)
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .foregroundStyle(.white)

                Text("Recording...")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 50) {
                    Button {
                        cancelRecording()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.gray)
                            Text("Cancel")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                    }

                    Button {
                        stopRecording()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)
                            Text("Done")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
        .onAppear {
            pulseAnimation = true
        }
        .onDisappear {
            pulseAnimation = false
        }
    }

    // MARK: - Transcribing Overlay

    private var transcribingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 100, height: 100)

                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)
                }

                Text("Processing...")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)

                Text("Transcribing your voice")
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                ProgressView()
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Recording Actions

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                errorMessage = "Microphone permission is required to record"
                showingError = true
                return
            }

            do {
                currentAudioFileName = try audioRecorder.startRecording()
                await MainActor.run {
                    isRecording = true
                }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                showingError = true
            }
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

        Task {
            await transcribeAndAppend(url: url)
        }
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        isRecording = false
        currentAudioFileName = nil
    }

    private func transcribeAndAppend(url: URL) async {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "OpenAI API key not configured"
                showingError = true
                isTranscribing = false
            }
            return
        }

        let language = LanguageSettings.shared.selectedLanguage
        let service = TranscriptionService(apiKey: apiKey, language: language)

        do {
            let transcript = try await service.transcribe(audioURL: url)

            await MainActor.run {
                // Append transcribed text to existing text
                if text.isEmpty {
                    text = transcript
                } else {
                    text += "\n\n" + transcript
                }
                hasChanges = text != (authService.eeonContext ?? "")
                isTranscribing = false
            }

            // Clean up audio file
            if let fileName = currentAudioFileName {
                audioRecorder.deleteRecording(fileName: fileName)
                await MainActor.run {
                    currentAudioFileName = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showingError = true
                isTranscribing = false
            }
        }
    }

    // MARK: - Save

    private func saveAndGenerateReports() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        authService.eeonContext = trimmed.isEmpty ? nil : trimmed
        hasChanges = false

        if trimmed.isEmpty {
            PersonalizedReportStore.clear()
            dismiss()
            return
        }

        // Generate personalized reports in background, then dismiss
        isGeneratingReports = true
        Task {
            do {
                _ = try await PersonalizedReportStore.generate()
            } catch {
                print("Failed to generate personalized reports: \(error)")
            }
            await MainActor.run {
                isGeneratingReports = false
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MyEEONView()
    }
}
