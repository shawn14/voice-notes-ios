//
//  UsageService.swift
//  voice notes
//
//  Simple monetization: 5 free notes, then pay
//

import Foundation
import SwiftUI

// MARK: - Usage Service

@Observable
class UsageService {
    static let shared = UsageService()

    private let defaults = UserDefaults.standard

    // Keys
    private let noteCountKey = "totalNoteCount"
    private let totalRecordingSecondsKey = "totalRecordingSeconds"
    private let hasShownPaywallKey = "hasShownPaywall"
    private let subscriptionStatusKey = "subscriptionStatus"

    // MARK: - Constants

    static let freeNoteLimit = 5

    // MARK: - Core State

    var noteCount: Int {
        get { defaults.integer(forKey: noteCountKey) }
        set { defaults.set(newValue, forKey: noteCountKey) }
    }

    var hasShownPaywall: Bool {
        get { defaults.bool(forKey: hasShownPaywallKey) }
        set { defaults.set(newValue, forKey: hasShownPaywallKey) }
    }

    var subscriptionStatus: String {
        get { defaults.string(forKey: subscriptionStatusKey) ?? "free" }
        set { defaults.set(newValue, forKey: subscriptionStatusKey) }
    }

    // MARK: - Computed Properties

    var isPro: Bool { subscriptionStatus == "pro" }

    var canCreateNote: Bool {
        isPro || noteCount < UsageService.freeNoteLimit
    }

    var freeNotesRemaining: Int {
        max(0, UsageService.freeNoteLimit - noteCount)
    }

    var freeNotesUsed: Int {
        min(noteCount, UsageService.freeNoteLimit)
    }

    // MARK: - Methods

    func incrementNoteCount() {
        noteCount += 1
    }

    /// Call this when a note is deleted to give back a free slot
    func decrementNoteCount() {
        noteCount = max(0, noteCount - 1)
    }

    /// Sync note count with actual database count
    func syncNoteCount(actualCount: Int) {
        noteCount = actualCount
    }

    func shouldShowPaywall() -> Bool {
        // Show when they hit the limit
        !isPro && noteCount >= UsageService.freeNoteLimit && !hasShownPaywall
    }

    // MARK: - Recording Time (kept for stats display)

    var totalRecordingSeconds: Int {
        get { defaults.integer(forKey: totalRecordingSecondsKey) }
        set { defaults.set(newValue, forKey: totalRecordingSecondsKey) }
    }

    var totalMinutes: Int {
        totalRecordingSeconds / 60
    }

    var totalRecordingTimeString: String {
        let hours = totalRecordingSeconds / 3600
        let minutes = (totalRecordingSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    func addRecordingTime(seconds: Int) {
        totalRecordingSeconds += seconds
    }

    // MARK: - Pro Upgrade

    func upgradeToPro() {
        subscriptionStatus = "pro"
    }

    func downgradeToFree() {
        subscriptionStatus = "free"
    }

    // MARK: - Reset (for testing/sign out)

    func resetAllUsage() {
        noteCount = 0
        totalRecordingSeconds = 0
        hasShownPaywall = false
        subscriptionStatus = "free"
    }

    // Legacy compatibility - these can be removed later
    var canExtract: Bool { true }  // Always allow extraction now
    var canResolve: Bool { true }  // Always allow resolution now
    func useExtraction() { }  // No-op
    func useResolution() { }  // No-op
    var freeExtractionsRemaining: Int { 999 }
    var freeResolutionsRemaining: Int { 999 }
    var totalExtractionsUsed: Int { 0 }
    var totalResolutionsUsed: Int { 0 }
    var isFirstNote: Bool {
        get { noteCount == 0 }
        set { }  // No-op
    }
}

// MARK: - App Info

struct AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var versionString: String {
        "Version \(version), build \(build)"
    }
}
