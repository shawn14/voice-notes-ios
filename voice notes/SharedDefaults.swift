//
//  SharedDefaults.swift
//  voice notes
//
//  Shared UserDefaults for App Group — enables widget to read app state
//

import Foundation

/// Keys and accessors for data shared between the main app and widget extension
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

    // MARK: - Write (main app)

    static func updateNoteCount(_ count: Int) {
        suite.set(count, forKey: noteCountKey)
    }

    static func updateProStatus(_ isPro: Bool) {
        suite.set(isPro, forKey: isProKey)
    }

    static func updateLastNote(preview: String, date: Date, intent: String) {
        suite.set(preview, forKey: lastNotePreviewKey)
        suite.set(date, forKey: lastNoteDateKey)
        suite.set(intent, forKey: lastNoteIntentKey)
    }

    static func updateTotalNotes(_ count: Int) {
        suite.set(count, forKey: totalNotesKey)
    }

    // MARK: - Read (widget)

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
