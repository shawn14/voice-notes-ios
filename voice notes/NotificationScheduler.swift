//
//  NotificationScheduler.swift
//  voice notes
//
//  Schedules local push notifications from ProactiveAlertService results.
//  Handles permission, deduplication, daily brief reminders, and action buttons.
//

import Foundation
import UserNotifications

@Observable
final class NotificationScheduler: NSObject {
    static let shared = NotificationScheduler()

    /// Maximum notifications scheduled per scan (avoid overwhelming users)
    private static let maxNotificationsPerDay = 5

    // MARK: - Notification Categories

    static let commitmentCategory = "COMMITMENT_REMINDER"
    static let actionCategory = "ACTION_REMINDER"
    static let generalCategory = "GENERAL"
    static let markDoneAction = "MARK_DONE"

    // MARK: - UserDefaults Keys

    private let permissionRequestedKey = "notifications_permissionRequested"
    private let dailyBriefHourKey = "notifications_dailyBriefHour"
    private let dailyBriefMinuteKey = "notifications_dailyBriefMinute"

    private override init() {
        super.init()
        registerCategories()
    }

    // MARK: - Permission

    /// Request notification permission. Call after the user has created a few notes
    /// (not on first launch — use `requestPermissionIfReady()` for gated flow).
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(true, forKey: permissionRequestedKey)
            if granted {
                await MainActor.run {
                    // Ensure delegate is set for foreground notifications
                    center.delegate = self
                }
            }
            return granted
        } catch {
            print("[NotificationScheduler] Permission error: \(error)")
            return false
        }
    }

    /// Request permission only after the 3rd note (natural moment, not intrusive)
    func requestPermissionIfReady() async {
        let alreadyRequested = UserDefaults.standard.bool(forKey: permissionRequestedKey)
        guard !alreadyRequested else { return }

        let noteCount = UsageService.shared.noteCount
        guard noteCount >= 3 else { return }

        _ = await requestPermission()
    }

    // MARK: - Schedule Alerts

    /// Schedule local notifications for the given alerts.
    /// Caps at `maxNotificationsPerDay` and deduplicates by content hash.
    func scheduleAlerts(_ alerts: [ProactiveAlert]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Check user preference
        guard UserDefaults.standard.object(forKey: "proactiveRemindersEnabled") as? Bool ?? true else { return }

        // Get already-pending notifications to avoid duplicates
        let pending = await center.pendingNotificationRequests()
        let existingIds = Set(pending.map { $0.identifier })

        var scheduled = 0

        for alert in alerts {
            guard scheduled < NotificationScheduler.maxNotificationsPerDay else { break }

            let identifier = notificationIdentifier(for: alert)
            guard !existingIds.contains(identifier) else { continue }

            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier(for: alert.type)

            // Attach related note ID for deep linking
            if let noteId = alert.relatedNoteId {
                content.userInfo["noteId"] = noteId.uuidString
            }
            content.userInfo["alertType"] = alert.type.rawValue

            // Deliver in 5 seconds (immediate-ish, but not a time-interval of 0)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                print("[NotificationScheduler] Failed to schedule: \(error)")
            }
        }
    }

    // MARK: - Daily Brief Reminder

    /// Schedule a recurring daily notification to open the app and see the brief.
    func scheduleDailyBriefReminder(at hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        guard UserDefaults.standard.object(forKey: "dailyBriefEnabled") as? Bool ?? true else {
            // Remove existing daily brief if disabled
            center.removePendingNotificationRequests(withIdentifiers: ["daily_brief_reminder"])
            return
        }

        // Remove old daily brief notification before re-scheduling
        center.removePendingNotificationRequests(withIdentifiers: ["daily_brief_reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Your daily brief is ready"
        content.body = "See what needs your attention today"
        content.sound = .default
        content.categoryIdentifier = NotificationScheduler.generalCategory

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_brief_reminder", content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[NotificationScheduler] Failed to schedule daily brief: \(error)")
        }

        // Persist the chosen time
        UserDefaults.standard.set(hour, forKey: dailyBriefHourKey)
        UserDefaults.standard.set(minute, forKey: dailyBriefMinuteKey)
    }

    /// The currently configured daily brief hour (default 8)
    var dailyBriefHour: Int {
        let val = UserDefaults.standard.object(forKey: dailyBriefHourKey) as? Int
        return val ?? 8
    }

    /// The currently configured daily brief minute (default 0)
    var dailyBriefMinute: Int {
        let val = UserDefaults.standard.object(forKey: dailyBriefMinuteKey) as? Int
        return val ?? 0
    }

    // MARK: - Remove All

    /// Clear all pending proactive notifications
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Private Helpers

    private func registerCategories() {
        let markDone = UNNotificationAction(
            identifier: NotificationScheduler.markDoneAction,
            title: "Mark Done",
            options: []
        )

        let commitmentCategory = UNNotificationCategory(
            identifier: NotificationScheduler.commitmentCategory,
            actions: [markDone],
            intentIdentifiers: []
        )

        let actionCategory = UNNotificationCategory(
            identifier: NotificationScheduler.actionCategory,
            actions: [markDone],
            intentIdentifiers: []
        )

        let generalCategory = UNNotificationCategory(
            identifier: NotificationScheduler.generalCategory,
            actions: [],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            commitmentCategory, actionCategory, generalCategory
        ])
    }

    /// Stable identifier per alert to prevent duplicate scheduling
    private func notificationIdentifier(for alert: ProactiveAlert) -> String {
        let base = "\(alert.type.rawValue)_\(alert.relatedNoteId?.uuidString ?? "none")"
        // Include a date component so the same alert can reappear the next day
        let day = Calendar.current.component(.dayOfYear, from: Date())
        return "\(base)_\(day)"
    }

    private func categoryIdentifier(for type: ProactiveAlertType) -> String {
        switch type {
        case .staleCommitment: return NotificationScheduler.commitmentCategory
        case .overdueAction: return NotificationScheduler.actionCategory
        case .decisionDecay, .patternDetected, .dailyBrief: return NotificationScheduler.generalCategory
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification tap and action buttons
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        if response.actionIdentifier == NotificationScheduler.markDoneAction {
            // Post a notification so the app can mark the item done
            if let noteIdString = userInfo["noteId"] as? String {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .proactiveAlertMarkDone,
                        object: nil,
                        userInfo: ["noteId": noteIdString, "alertType": userInfo["alertType"] as? String ?? ""]
                    )
                }
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Tapped the notification — deep link to the note
            if let noteIdString = userInfo["noteId"] as? String {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .proactiveAlertOpenNote,
                        object: nil,
                        userInfo: ["noteId": noteIdString]
                    )
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let proactiveAlertMarkDone = Notification.Name("proactiveAlertMarkDone")
    static let proactiveAlertOpenNote = Notification.Name("proactiveAlertOpenNote")
}
