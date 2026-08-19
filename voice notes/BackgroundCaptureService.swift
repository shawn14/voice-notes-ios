//
//  BackgroundCaptureService.swift
//  voice notes
//
//  Owns Pocket-style background capture sessions started from App Intents
//  (Action Button / Control Center / Siri) while the phone stays locked.
//  The Live Activity it starts is REQUIRED by AudioRecordingIntent — iOS
//  kills the recording if none is active.
//

import Foundation
import SwiftData
import AVFoundation
import ActivityKit
import WidgetKit

@Observable
final class BackgroundCaptureService {
    static let shared = BackgroundCaptureService()

    private(set) var isCapturing = false
    /// Exposed so AIHomeView can render live state (elapsed time, paused).
    let recorder = AudioRecorder()

    private var activity: Activity<RecordingActivityAttributes>?
    private var container: ModelContainer?

    private init() {}

    /// Called once from voice_notesApp.init() after the container resolves.
    func configure(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func toggle() async throws {
        if isCapturing {
            try await stop()
        } else {
            try await start()
        }
    }

    @MainActor
    func start() async throws {
        guard !isCapturing else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw CaptureIntentError.micPermissionNeeded
        }
        guard UsageService.shared.canCreateNote else {
            throw CaptureIntentError.freeLimitReached
        }

        _ = try recorder.startRecording()
        isCapturing = true

        // Mirror recorder pause/resume into the Live Activity.
        recorder.onPauseStateChange = { [weak self] paused in
            Task { @MainActor [weak self] in
                await self?.updateActivityPauseState(paused: paused)
            }
        }

        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date(), isPaused: false, pausedReason: nil
        )
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
        if activity == nil {
            // Per the AudioRecordingIntent contract iOS will kill a
            // recording with no Live Activity. Don't record silently-doomed
            // audio: save nothing yet, stop cleanly, and surface the error.
            _ = recorder.stopRecording()
            isCapturing = false
            throw CaptureIntentError.appNotReady
        }
    }

    @MainActor
    private func updateActivityPauseState(paused: Bool) async {
        guard let activity else { return }
        // Re-baseline the timer on resume so it shows recorded time,
        // not wall-clock time across the pause.
        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-recorder.recordingTime),
            isPaused: paused,
            pausedReason: paused ? "Paused — audio in use (call?) · auto-resumes" : nil
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    @MainActor
    func stop() async throws {
        guard isCapturing else { return }
        recorder.onPauseStateChange = nil
        let url = recorder.stopRecording()
        isCapturing = false

        if let activity {
            let finalState = RecordingActivityAttributes.ContentState(
                startedAt: Date(), isPaused: false, pausedReason: nil
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            self.activity = nil
        }

        guard let url else { return }
        await saveAndProcess(url: url)
    }

    /// Save-first, process-second. The note lands as "pending" before any
    /// network call, so a reaped process loses nothing — the existing
    /// foreground drain (voice_notesApp) finishes pending notes.
    @MainActor
    private func saveAndProcess(url: URL) async {
        guard let container else { return }
        let context = container.mainContext
        let fileName = url.lastPathComponent

        let note = Note(title: "", content: "", transcript: nil, audioFileName: fileName)
        note.transcriptionStatus = "pending"
        context.insert(note)
        UsageService.shared.incrementNoteCount()
        try? context.save()

        SharedDefaults.updateLastNote(
            preview: "Processing voice note…",
            date: note.createdAt,
            intent: note.intentType
        )
        WidgetCenter.shared.reloadAllTimelines()

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return }

        do {
            let service = TranscriptionService(
                apiKey: apiKey,
                language: LanguageSettings.shared.selectedLanguage
            )
            let rawTranscript = try await service.transcribe(audioURL: url)
            let transcript: String
            do {
                transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
            } catch {
                transcript = rawTranscript
            }

            note.transcript = transcript
            note.content = transcript
            note.transcriptionStatus = "completed"
            note.updatedAt = Date()
            try? context.save()

            if let title = try? await SummaryService.generateTitle(for: transcript, apiKey: apiKey) {
                note.title = title
            }

            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            await IntelligenceService.shared.processNoteSave(
                note: note,
                transcript: transcript,
                projects: projects,
                tags: tags,
                context: context
            )
            await EmbeddingService.shared.generateAndStoreEmbedding(for: note)

            SharedDefaults.updateLastNote(
                preview: note.displayTitle,
                date: note.createdAt,
                intent: note.intentType
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Note stays "pending" with its audio — the foreground drain
            // retries it. Nothing is lost.
            print("🎙️ Background capture processing deferred: \(error)")
        }
    }
}
