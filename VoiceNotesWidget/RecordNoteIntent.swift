//
//  RecordNoteIntent.swift
//  VoiceNotesWidget
//
//  AppIntent for interactive widget — opens app in recording mode
//

import AppIntents
import Foundation

struct RecordNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Note"
    static var description = IntentDescription("Opens Voice Notes and starts recording")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // The app will detect the intent via the deep link
        return .result()
    }
}
