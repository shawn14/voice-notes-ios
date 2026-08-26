//
//  ReviewPrompter.swift
//  voice notes
//
//  Asks for an App Store rating at the transformation moment — the first
//  few times the user sees a rambling recording come back as a clean note.
//  The app had never asked (2026-08-26), which is why the listing has a
//  handful of ratings against competitors' thousands. Apple caps prompts at
//  three per 365 days on its side; we additionally ask at most once per
//  marketing version, and only after the third enhanced note.
//

import Foundation

nonisolated enum ReviewPrompter {
    private static let askedVersionKey = "reviewPrompt.askedVersion"
    private static let enhancedSeenKey = "reviewPrompt.enhancedNotesSeen"
    static let threshold = 3

    /// Call when an enhanced note is shown. Returns true when it is time to
    /// ask — the caller invokes SwiftUI's `requestReview`.
    static func noteEnhancedShown() -> Bool {
        let defaults = UserDefaults.standard
        let seen = defaults.integer(forKey: enhancedSeenKey) + 1
        defaults.set(seen, forKey: enhancedSeenKey)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard seen >= threshold, defaults.string(forKey: askedVersionKey) != version else { return false }
        defaults.set(version, forKey: askedVersionKey)
        return true
    }
}
