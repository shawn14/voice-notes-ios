//
//  SharedDefaults.swift
//  VoiceNotesWidget
//
//  Mirror of the main app's SharedDefaults for widget to read shared state
//

import Foundation

struct SharedDefaults {
    static let suiteName = "group.com.eeon.voicenotes"

    static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Keys

    private static let noteCountKey = "shared_noteCount"
    private static let isProKey = "shared_isPro"
    private static let lastNotePreviewKey = "shared_lastNotePreview"
    private static let lastNoteDateKey = "shared_lastNoteDate"
    private static let lastNoteIntentKey = "shared_lastNoteIntent"
    private static let totalNotesKey = "shared_totalNotes"

    // MARK: - Read

    static var noteCount: Int {
        suite.integer(forKey: noteCountKey)
    }

    static var isPro: Bool {
        suite.bool(forKey: isProKey)
    }

    static var lastNotePreview: String? {
        suite.string(forKey: lastNotePreviewKey)
    }

    static var lastNoteDate: Date? {
        suite.object(forKey: lastNoteDateKey) as? Date
    }

    static var lastNoteIntent: String? {
        suite.string(forKey: lastNoteIntentKey)
    }

    static var totalNotes: Int {
        suite.integer(forKey: totalNotesKey)
    }

    static let freeNoteLimit = 10

    static var freeNotesRemaining: Int {
        max(0, freeNoteLimit - noteCount)
    }
}
