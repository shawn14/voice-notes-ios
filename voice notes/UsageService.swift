//
//  UsageService.swift
//  voice notes
//
//  Tracks user recording usage and stats
//

import Foundation
import SwiftUI

// MARK: - Usage Service

@Observable
class UsageService {
    static let shared = UsageService()

    private let defaults = UserDefaults.standard

    // Keys
    private let totalRecordingSecondsKey = "totalRecordingSeconds"
    private let monthlyRecordingSecondsKey = "monthlyRecordingSeconds"
    private let monthStartKey = "monthStart"
    private let noteCountKey = "totalNoteCount"
    private let aiCallsKey = "aiCallsThisMonth"

    // MARK: - Recording Time

    var totalRecordingSeconds: Int {
        get { defaults.integer(forKey: totalRecordingSecondsKey) }
        set { defaults.set(newValue, forKey: totalRecordingSecondsKey) }
    }

    var monthlyRecordingSeconds: Int {
        get {
            resetMonthlyIfNeeded()
            return defaults.integer(forKey: monthlyRecordingSecondsKey)
        }
        set { defaults.set(newValue, forKey: monthlyRecordingSecondsKey) }
    }

    // Free tier limit: 30 minutes per month
    var monthlyLimitSeconds: Int { 30 * 60 }

    var remainingMinutesThisMonth: Int {
        max(0, (monthlyLimitSeconds - monthlyRecordingSeconds) / 60)
    }

    var usedMinutesThisMonth: Int {
        monthlyRecordingSeconds / 60
    }

    var totalMinutes: Int {
        totalRecordingSeconds / 60
    }

    var usagePercentage: Double {
        Double(monthlyRecordingSeconds) / Double(monthlyLimitSeconds)
    }

    var isOverLimit: Bool {
        monthlyRecordingSeconds >= monthlyLimitSeconds
    }

    // MARK: - Note Count

    var totalNoteCount: Int {
        get { defaults.integer(forKey: noteCountKey) }
        set { defaults.set(newValue, forKey: noteCountKey) }
    }

    // MARK: - AI Calls

    var aiCallsThisMonth: Int {
        get {
            resetMonthlyIfNeeded()
            return defaults.integer(forKey: aiCallsKey)
        }
        set { defaults.set(newValue, forKey: aiCallsKey) }
    }

    // MARK: - Methods

    func addRecordingTime(seconds: Int) {
        totalRecordingSeconds += seconds
        monthlyRecordingSeconds += seconds
    }

    func incrementNoteCount() {
        totalNoteCount += 1
    }

    func incrementAICalls() {
        aiCallsThisMonth += 1
    }

    private func resetMonthlyIfNeeded() {
        let calendar = Calendar.current
        let now = Date()

        if let monthStart = defaults.object(forKey: monthStartKey) as? Date {
            // Check if we're in a new month
            if !calendar.isDate(monthStart, equalTo: now, toGranularity: .month) {
                // Reset monthly counters
                defaults.set(0, forKey: monthlyRecordingSecondsKey)
                defaults.set(0, forKey: aiCallsKey)
                defaults.set(now, forKey: monthStartKey)
            }
        } else {
            // First run - set month start
            defaults.set(now, forKey: monthStartKey)
        }
    }

    // MARK: - Formatted Strings

    var usageDisplayString: String {
        "\(usedMinutesThisMonth) of \(monthlyLimitSeconds / 60) mins"
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
