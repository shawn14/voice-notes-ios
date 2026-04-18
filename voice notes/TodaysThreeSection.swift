//
//  TodaysThreeSection.swift
//  voice notes
//
//  Home-screen section for the "Today's 3" daily-ritual pattern.
//  - Empty state: big CTA "Set your 3 for today" that opens a voice-first capture sheet.
//  - Populated: three check-off rows. Tapping a row's circle marks complete (strikethrough).
//
//  Section kind: `.todayThree` in HomeSectionKind. Always rendered at the top of a
//  compiled layout because the purpose prompt biases the LLM toward including it first.
//

import SwiftUI
import SwiftData

// MARK: - Section View

struct TodaysThreeSection: View {
    let title: String
    let rationale: String?

    @Environment(\.modelContext) private var modelContext
    @State private var showingCaptureSheet = false

    @Query(sort: [SortDescriptor(\DailyIntention.order)])
    private var allIntentions: [DailyIntention]

    private var todayIntentions: [DailyIntention] {
        let key = DailyIntention.todayKey()
        return allIntentions.filter { $0.dateKey == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title, rationale: rationale)

            if todayIntentions.isEmpty {
                emptyState
            } else {
                intentionsList
            }
        }
        .sheet(isPresented: $showingCaptureSheet) {
            TodaysThreeCaptureSheet()
        }
    }

    private var emptyState: some View {
        Button {
            showingCaptureSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent").opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color("EEONAccent"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set your 3 for today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Tap to speak your top three intentions.")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.eeonCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color("EEONAccent").opacity(0.3), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var intentionsList: some View {
        VStack(spacing: 6) {
            ForEach(todayIntentions) { intention in
                intentionRow(intention)
            }

            // Edit existing intentions (re-opens capture sheet)
            Button {
                showingCaptureSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.caption)
                    Text("Edit today's 3")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color("EEONAccent"))
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func intentionRow(_ intention: DailyIntention) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                intention.toggleCompleted()
                try? modelContext.save()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: intention.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(intention.isCompleted ? Color.green : Color("EEONAccent"))
                    .padding(.top, 1)
                Text(intention.content)
                    .font(.body)
                    .foregroundStyle(intention.isCompleted ? .eeonTextSecondary : .eeonTextPrimary)
                    .strikethrough(intention.isCompleted, color: .eeonTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.eeonCard)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capture Sheet

/// Voice-first input for setting or editing today's three intentions.
/// Shared mic button transcribes via Whisper; the transcript populates the first
/// empty row, so the user can speak each intention one at a time in sequence.
struct TodaysThreeCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\DailyIntention.order)])
    private var allIntentions: [DailyIntention]

    @State private var texts: [String] = ["", "", ""]
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var audioRecorder = AudioRecorder()
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    private var todayKey: String { DailyIntention.todayKey() }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eeonBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header

                            VStack(spacing: 10) {
                                ForEach(0..<3, id: \.self) { idx in
                                    intentionField(index: idx)
                                }
                            }

                            voiceRow
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                    }
                }
                .disabled(isRecording || isTranscribing)
                .blur(radius: (isRecording || isTranscribing) ? 3 : 0)

                if isRecording {
                    HomeRecordingOverlay(
                        onStop: stopRecording,
                        onCancel: cancelRecording,
                        audioRecorder: audioRecorder
                    )
                }
                if isTranscribing {
                    HomeTranscribingOverlay()
                }
            }
            .navigationTitle("Today's 3")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!hasAnyContent)
                }
            }
            .onAppear(perform: loadExisting)
            .alert("Something went wrong", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What are your three for today?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap the mic and speak them. EEON will fill the first empty row each time you stop.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func intentionField(index: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color("EEONAccent").opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(index + 1)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color("EEONAccent"))
            }

            TextField("Intention \(index + 1)", text: $texts[index], axis: .vertical)
                .font(.body)
                .lineLimit(1...3)
                .submitLabel(.next)
        }
        .padding(12)
        .background(Color.eeonCard)
        .cornerRadius(12)
    }

    private var voiceRow: some View {
        Button {
            toggleRecording()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent"))
                        .frame(width: 56, height: 56)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speak your intentions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                    Text("Each recording fills the next empty row")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.eeonCard)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var hasAnyContent: Bool {
        texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func loadExisting() {
        let key = todayKey
        let today = allIntentions.filter { $0.dateKey == key }.sorted { $0.order < $1.order }
        for (i, intention) in today.enumerated() where i < 3 {
            texts[i] = intention.content
        }
    }

    private func save() {
        // Replace today's intentions with whatever is in the three slots.
        let key = todayKey
        let existing = allIntentions.filter { $0.dateKey == key }
        for item in existing { modelContext.delete(item) }

        for (i, raw) in texts.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let intention = DailyIntention(dateKey: key, order: i, content: trimmed)
            modelContext.insert(intention)
        }
        try? modelContext.save()
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
                errorMessage = "Microphone permission is required to record."
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
        Task { await transcribeAndFillNext(url: url) }
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        isRecording = false
        currentAudioFileName = nil
    }

    private func transcribeAndFillNext(url: URL) async {
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
                fillNextEmpty(with: transcript)
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

    private func fillNextEmpty(with transcript: String) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        for i in 0..<3 where texts[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts[i] = cleaned
            return
        }
        // All three filled — append to the last one instead of dropping the capture
        texts[2] += " " + cleaned
    }
}

#Preview {
    TodaysThreeCaptureSheet()
        .modelContainer(for: [DailyIntention.self], inMemory: true)
}
