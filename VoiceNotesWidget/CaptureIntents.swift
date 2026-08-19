//
//  CaptureIntents.swift
//  VoiceNotesWidget
//
//  App Intents for Pocket-style background capture. This file is duplicated
//  into the VoiceNotesWidget target (SharedDefaults.swift pattern) — keep
//  both copies identical. perform() always runs in the app process, where
//  voice_notesApp.init() installs the CaptureBridge handlers.
//

import AppIntents
import Foundation

/// Runtime bridge between the intents (compiled into both targets) and
/// BackgroundCaptureService (app target only). Set in voice_notesApp.init().
enum CaptureBridge {
    static var toggleHandler: (@Sendable () async throws -> Void)?
    static var stopHandler: (@Sendable () async throws -> Void)?
}

/// One press from anywhere — Action Button, Control Center, Lock Screen,
/// Siri, Shortcuts, Back Tap. Not recording → start (phone stays locked,
/// Live Activity appears). Recording → stop and save.
struct ToggleRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Record EEON Note"
    static var description = IntentDescription(
        "Start or stop an EEON voice note without opening the app."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let handler = CaptureBridge.toggleHandler else {
            throw CaptureIntentError.appNotReady
        }
        try await handler()
        return .result()
    }
}

/// Stop button on the Live Activity. LiveActivityIntent ⇒ runs in the app
/// process even though the button lives in the widget extension.
struct StopRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop EEON Recording"
    static var description = IntentDescription("Stop and save the current EEON recording.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let handler = CaptureBridge.stopHandler else {
            throw CaptureIntentError.appNotReady
        }
        try await handler()
        return .result()
    }
}

enum CaptureIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case micPermissionNeeded
    case freeLimitReached
    case recordingAlreadyActive
    case liveActivitiesUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "EEON isn't ready yet — open the app once, then try again."
        case .micPermissionNeeded:
            return "Open EEON and allow microphone access first."
        case .freeLimitReached:
            return "Free note limit reached — open EEON to upgrade."
        case .recordingAlreadyActive:
            return "EEON is already recording — stop the current recording first."
        case .liveActivitiesUnavailable:
            return "Enable Live Activities for EEON in Settings to record from the Lock Screen."
        }
    }
}
