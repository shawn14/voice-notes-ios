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
        guard !AudioRecorder.isAnyRecording else {
            throw CaptureIntentError.recordingAlreadyActive
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw CaptureIntentError.micPermissionNeeded
        }
        guard UsageService.shared.canCreateNote else {
            throw CaptureIntentError.freeLimitReached
        }

        // Clear any Live Activity left behind by a reaped process before adding
        // ours, so sessions can't stack up on the Lock Screen.
        await endStaleActivities()

        // Per the AudioRecordingIntent contract iOS will kill a recording
        // with no Live Activity. Request the activity FIRST — if it fails
        // (e.g. Live Activities disabled system-wide), no audio file gets
        // created at all, so there's nothing to leak.
        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date(), isPaused: false, pausedReason: nil
        )
        guard let newActivity = try? Activity.request(
            attributes: RecordingActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        ) else {
            throw CaptureIntentError.liveActivitiesUnavailable
        }

        do {
            _ = try recorder.startRecording()
        } catch {
            await newActivity.end(nil, dismissalPolicy: .immediate)
            throw error
        }

        activity = newActivity
        isCapturing = true

        // Mirror recorder pause/resume into the Live Activity.
        recorder.onPauseStateChange = { [weak self] paused in
            Task { @MainActor [weak self] in
                await self?.updateActivityPauseState(paused: paused)
            }
        }
    }

    /// Ends Live Activities that outlived their process (app reaped mid-capture).
    /// Skips the current session's activity so a launch-time sweep can never kill
    /// a capture that just started.
    func endStaleActivities() async {
        for stale in Activity<RecordingActivityAttributes>.activities where stale.id != activity?.id {
            await stale.end(nil, dismissalPolicy: .immediate)
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

        // Clear the stored reference synchronously, before the first await,
        // so a re-entrant toggle() that starts a NEW session during the
        // suspension below can't have its activity clobbered by this call
        // finishing afterward.
        if let endingActivity = activity {
            activity = nil
            let finalState = RecordingActivityAttributes.ContentState(
                startedAt: Date(), isPaused: false, pausedReason: nil
            )
            await endingActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
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

        // Claim the note so the foreground pending-drain can't process it
        // concurrently while this inline pipeline runs (it selects "pending" only).
        note.transcriptionStatus = "processing"
        try? context.save()

        SharedDefaults.updateLastNote(
            preview: "Processing voice note…",
            date: note.createdAt,
            intent: note.intentType
        )
        WidgetCenter.shared.reloadAllTimelines()

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            // No pipeline will run, so don't leave a claim nothing owns.
            note.transcriptionStatus = "pending"
            try? context.save()
            return
        }

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
            // Release the claim so the note goes back with its audio to the
            // foreground drain, which retries it. Nothing is lost.
            note.transcriptionStatus = "pending"
            try? context.save()
            print("🎙️ Background capture processing deferred: \(error)")
        }
    }
}
