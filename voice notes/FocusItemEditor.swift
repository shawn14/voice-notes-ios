//
//  FocusItemEditor.swift
//  voice notes
//
//  Sheet editor for one FocusItem — used for both Add and Edit flows
//  in TuneConversationView's third card. Mirrors the existing
//  editor pattern (mic + transcript + save) with weight chips added.
//

import SwiftUI

struct FocusItemEditor: View {
    @Environment(\.dismiss) private var dismiss

    let initialItem: FocusItem?
    let onSave: (FocusItem) -> Void

    @State private var content: String = ""
    @State private var note: String = ""
    @State private var weight: FocusWeight = .primary

    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    init(initialItem: FocusItem? = nil, onSave: @escaping (FocusItem) -> Void) {
        self.initialItem = initialItem
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.eeonTextSecondary)
                Spacer()
                Text(initialItem == nil ? "Add Focus" : "Edit Focus")
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
                Spacer()
                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What do you want EEON to weight as your focus?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.eeonTextPrimary)

                    contentField

                    Text("Optional note")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.top, 8)
                    noteField

                    Text("Weight")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.top, 8)
                    weightChips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }

            actionBar
        }
        .background(Color.eeonBackground.ignoresSafeArea())
        .overlay { recordingOverlays }
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if let item = initialItem {
                content = item.content
                note = item.note ?? ""
                weight = item.weight
            }
        }
    }

    private var contentField: some View {
        ZStack(alignment: .topLeading) {
            if content.isEmpty {
                Text("StockAlarm…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
            }
            TextEditor(text: $content)
                .font(.body)
                .foregroundStyle(.eeonTextPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 100)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.eeonCard))
    }

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text("Where I want to spend most of my time")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
            }
            TextEditor(text: $note)
                .font(.subheadline)
                .foregroundStyle(.eeonTextPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 60)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.eeonCard))
    }

    private var weightChips: some View {
        HStack(spacing: 8) {
            ForEach(FocusWeight.allCases, id: \.self) { w in
                Button {
                    weight = w
                } label: {
                    Text(w.label)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(weight == w ? Color("EEONAccent") : Color.eeonCard)
                        .foregroundStyle(weight == w ? .white : .eeonTextPrimary)
                        .cornerRadius(10)
                }
            }
            Spacer()
        }
    }

    private var actionBar: some View {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !trimmed.isEmpty

        return HStack(spacing: 12) {
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent"))
                        .frame(width: 56, height: 56)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Button(action: save) {
                Text("Save")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(canSave ? Color("EEONAccent") : Color("EEONAccent").opacity(0.4))
                    )
            }
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.eeonBackground)
    }

    @ViewBuilder
    private var recordingOverlays: some View {
        if isRecording {
            HomeRecordingOverlay(
                onStop: stopRecording,
                onCancel: cancelRecording,
                audioRecorder: audioRecorder
            )
        } else if isTranscribing {
            HomeTranscribingOverlay()
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = FocusItem(
            id: initialItem?.id ?? UUID(),
            content: trimmed,
            weight: weight,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        onSave(item)
        dismiss()
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                errorMessage = "Microphone permission is required."
                showingError = true
                return
            }
            do {
                currentAudioFileName = try audioRecorder.startRecording()
                await MainActor.run { isRecording = true }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording."
            showingError = true
            isRecording = false
            return
        }
        isRecording = false
        isTranscribing = true
        Task { await transcribeAndAppend(url: url) }
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
                errorMessage = "OpenAI API key is not configured."
                showingError = true
                isTranscribing = false
            }
            return
        }
        let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
        do {
            let transcript = try await service.transcribe(audioURL: url)
            await MainActor.run {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content = transcript
                } else {
                    note = note.isEmpty ? transcript : note + " " + transcript
                }
                isTranscribing = false
            }
            if let fileName = currentAudioFileName {
                audioRecorder.deleteRecording(fileName: fileName)
                await MainActor.run { currentAudioFileName = nil }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showingError = true
                isTranscribing = false
            }
        }
    }
}
