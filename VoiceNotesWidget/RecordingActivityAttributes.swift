//
//  RecordingActivityAttributes.swift
//  VoiceNotesWidget
//
//  ActivityKit attributes for the recording Live Activity. Duplicated into
//  the VoiceNotesWidget target (SharedDefaults.swift pattern) — keep both
//  copies identical.
//

import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Baseline for the on-screen timer. Re-baselined on resume so the
        /// timer shows recorded time, not wall-clock time across pauses.
        var startedAt: Date
        var isPaused: Bool
        var pausedReason: String?
    }
}
