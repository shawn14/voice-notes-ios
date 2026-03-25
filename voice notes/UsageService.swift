//
//  UsageService.swift
//  voice notes
//
//  Simple monetization: 5 free notes, then pay
//

import Foundation
import SwiftUI
import WidgetKit

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
    private let reportCountKey = "reportGenerationCount"

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

    var isPro: Bool { subscriptionStatus == "pro" && AuthService.shared.isSignedIn }

    var canCreateNote: Bool {
        isPro || noteCount < UsageService.freeNoteLimit
    }

    // MARK: - Report Usage

    static let freeReportLimit = 2

    var reportGenerationCount: Int {
        get { defaults.integer(forKey: reportCountKey) }
        set { defaults.set(newValue, forKey: reportCountKey) }
    }

    var canGenerateReport: Bool {
        isPro || reportGenerationCount < UsageService.freeReportLimit
    }

    var freeReportsRemaining: Int {
        max(0, UsageService.freeReportLimit - reportGenerationCount)
    }

    func incrementReportCount() {
        reportGenerationCount += 1
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
        syncToSharedDefaults()
    }

    /// Call this when a note is deleted to give back a free slot
    func decrementNoteCount() {
        noteCount = max(0, noteCount - 1)
        syncToSharedDefaults()
    }

    /// Sync note count with actual database count
    func syncNoteCount(actualCount: Int) {
        noteCount = actualCount
        syncToSharedDefaults()
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
        syncToSharedDefaults()
    }

    func downgradeToFree() {
        subscriptionStatus = "free"
        // Reset paywall flag so user can see upgrade prompt again
        hasShownPaywall = false
        syncToSharedDefaults()
    }

    // MARK: - Reset (for testing/sign out)

    func resetAllUsage() {
        noteCount = 0
        totalRecordingSeconds = 0
        hasShownPaywall = false
        subscriptionStatus = "free"
        reportGenerationCount = 0
    }

    // MARK: - Shared Defaults Sync (for Widget)

    /// Sync current usage state to App Group UserDefaults so the widget can read it
    func syncToSharedDefaults() {
        SharedDefaults.updateNoteCount(noteCount)
        SharedDefaults.updateProStatus(isPro)
        WidgetCenter.shared.reloadAllTimelines()
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
