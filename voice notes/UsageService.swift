//
//  UsageService.swift
//  voice notes
//
//  Tracks user usage: extractions, resolutions, and recording stats
//

import Foundation
import SwiftUI

// MARK: - Usage Quota

struct UsageQuota: Codable {
    var extractionsRemaining: Int = 5
    var resolutionsRemaining: Int = 3
    var totalExtractionsUsed: Int = 0
    var totalResolutionsUsed: Int = 0
    var hasCompletedFirstExtraction: Bool = false  // "free-free" flag
    var hasCompletedFirstResolution: Bool = false  // "free-free" flag
    var lastResetDate: Date? = nil  // For future monthly reset
}

// MARK: - Usage Service

@Observable
class UsageService {
    static let shared = UsageService()

    private let defaults = UserDefaults.standard

    // Keys
    private let quotaKey = "usageQuota"
    private let totalRecordingSecondsKey = "totalRecordingSeconds"
    private let noteCountKey = "totalNoteCount"
    private let isFirstNoteKey = "isFirstNote"
    private let hasShownPaywallKey = "hasShownPaywall"
    private let subscriptionStatusKey = "subscriptionStatus"

    // MARK: - Quota State

    var quota: UsageQuota {
        get {
            guard let data = defaults.data(forKey: quotaKey),
                  let decoded = try? JSONDecoder().decode(UsageQuota.self, from: data) else {
                return UsageQuota()
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: quotaKey)
            }
        }
    }

    var isFirstNote: Bool {
        get {
            // If key doesn't exist, it's the first note
            if defaults.object(forKey: isFirstNoteKey) == nil {
                return true
            }
            return defaults.bool(forKey: isFirstNoteKey)
        }
        set { defaults.set(newValue, forKey: isFirstNoteKey) }
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

    var canExtract: Bool {
        isPro || quota.extractionsRemaining > 0
    }

    var canResolve: Bool {
        isPro || quota.resolutionsRemaining > 0
    }

    // "Free-free" display (shows 1 used, but didn't actually decrement)
    var displayExtractionsUsed: Int {
        quota.hasCompletedFirstExtraction ? max(1, 5 - quota.extractionsRemaining) : 0
    }

    var freeExtractionsRemaining: Int {
        quota.extractionsRemaining
    }

    var freeResolutionsRemaining: Int {
        quota.resolutionsRemaining
    }

    var totalExtractionsUsed: Int {
        quota.totalExtractionsUsed
    }

    var totalResolutionsUsed: Int {
        quota.totalResolutionsUsed
    }

    // MARK: - Usage Methods

    func useExtraction() {
        var currentQuota = quota

        // First extraction is "free-free" - don't decrement, just mark as completed
        if !isPro && currentQuota.hasCompletedFirstExtraction {
            currentQuota.extractionsRemaining = max(0, currentQuota.extractionsRemaining - 1)
        }

        currentQuota.hasCompletedFirstExtraction = true
        currentQuota.totalExtractionsUsed += 1

        quota = currentQuota
    }

    func useResolution() {
        var currentQuota = quota

        // First resolution is "free-free" - don't decrement, just mark as completed
        if !isPro && currentQuota.hasCompletedFirstResolution {
            currentQuota.resolutionsRemaining = max(0, currentQuota.resolutionsRemaining - 1)
        }

        currentQuota.hasCompletedFirstResolution = true
        currentQuota.totalResolutionsUsed += 1

        quota = currentQuota
    }

    func shouldShowPaywall() -> Bool {
        // Show after first successful resolution, only once
        quota.totalResolutionsUsed == 1 && !hasShownPaywall
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
            return "\(minutes) minutes"
        }
    }

    // MARK: - Note Count

    var totalNoteCount: Int {
        get { defaults.integer(forKey: noteCountKey) }
        set { defaults.set(newValue, forKey: noteCountKey) }
    }

    // MARK: - Methods

    func addRecordingTime(seconds: Int) {
        totalRecordingSeconds += seconds
    }

    func incrementNoteCount() {
        totalNoteCount += 1
    }

    // MARK: - Pro Upgrade

    func upgradeToPro() {
        subscriptionStatus = "pro"
    }

    func downgradeToFree() {
        subscriptionStatus = "free"
    }

    // MARK: - Reset (for testing)

    func resetAllUsage() {
        quota = UsageQuota()
        isFirstNote = true
        hasShownPaywall = false
        subscriptionStatus = "free"
    }
}

// MARK: - Subscription Tier

enum SubscriptionTier: String {
    case free = "Free"
    case pro = "Pro"
    case team = "Team"

    var monthlyMinutes: Int {
        switch self {
        case .free: return 30
        case .pro: return 300  // 5 hours
        case .team: return 1000
        }
    }

    var price: String {
        switch self {
        case .free: return "Free"
        case .pro: return "$9.99/mo"
        case .team: return "$24.99/mo"
        }
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
