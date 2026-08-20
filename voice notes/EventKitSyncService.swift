//
//  EventKitSyncService.swift
//  voice notes
//
//  "One note updates your apps": pushes extracted action items into an
//  "EEON" list in Apple Reminders via EventKit. Reminders sync onward to
//  whatever accounts the phone has (iCloud, Google, Outlook) — no OAuth.
//  One-way push, deduped by action id, safe across re-runs and the
//  pending-note drain. Off by default; enabled from Settings, which
//  triggers the system permission prompt.
//

import Foundation
import EventKit

@Observable
final class EventKitSyncService {
    static let shared = EventKitSyncService()

    static let enabledKey = "eventKitRemindersSyncEnabled"
    private let mapKey = "eventKitReminderMap" // [action UUID string: reminder identifier]
    private let store = EKEventStore()

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// iOS 17+ full-access request. Returns whether access was granted.
    func requestAccess() async -> Bool {
        do { return try await store.requestFullAccessToReminders() }
        catch {
            print("[EventKitSync] access request failed: \(error)")
            return false
        }
    }

    /// Push new extracted actions into the EEON Reminders list. Actions that
    /// already have a reminder (dedup map) are skipped, so re-processing a
    /// note never duplicates reminders. No-op unless enabled + authorized.
    func sync(actions: [ExtractedAction]) async {
        guard isEnabled, !actions.isEmpty else { return }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        guard let list = try? eeonRemindersList() else { return }

        var map = reminderMap()
        var savedAny = false
        for action in actions where map[action.id.uuidString] == nil {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = action.content
            reminder.notes = "From an EEON voice note"
            if action.priority == "Urgent" || action.priority == "High" {
                reminder.priority = 1
            }
            if let due = Self.parseDate(from: action.deadline) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: due
                )
            }
            do {
                try store.save(reminder, commit: false)
                map[action.id.uuidString] = reminder.calendarItemIdentifier
                savedAny = true
            } catch {
                print("[EventKitSync] reminder save failed: \(error)")
            }
        }
        if savedAny {
            try? store.commit()
            saveReminderMap(map)
        }
    }

    /// Find or create the "EEON" list in Reminders.
    private func eeonRemindersList() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == "EEON" }) {
            return existing
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "EEON"
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first else {
            throw NSError(domain: "EventKitSync", code: 1)
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    /// Best-effort date from the extractor's free-text deadlines
    /// ("Friday", "tomorrow", "Aug 30"). "TBD"/empty → nil.
    static func parseDate(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "TBD" else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector?.firstMatch(in: trimmed, options: [], range: range)?.date
    }

    private func reminderMap() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: mapKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    private func saveReminderMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: mapKey)
        }
    }
}
