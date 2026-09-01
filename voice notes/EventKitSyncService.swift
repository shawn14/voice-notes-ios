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

    /// Notes whose reminder was handled by the "remind me…" command flow.
    /// The extraction pass will still pull an action item out of the same
    /// note; skipping those here keeps Reminders from getting it twice.
    private var commandHandledNotes = Set<UUID>()

    private init() {}

    func markHandledByCommand(_ noteID: UUID) {
        commandHandledNotes.insert(noteID)
    }

    func isHandledByCommand(_ noteID: UUID?) -> Bool {
        guard let noteID else { return false }
        return commandHandledNotes.contains(noteID)
    }

    enum CreateError: LocalizedError {
        case accessDenied
        var errorDescription: String? { "Reminders access is off" }
    }

    /// One reminder in the EEON list, on the user's explicit ask ("remind
    /// me…" + confirmation). Independent of the Settings sync toggle —
    /// requests access on the spot if needed.
    func createReminder(title: String, due: Date?) async throws {
        if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
            guard await requestAccess() else { throw CreateError.accessDenied }
        }
        let list = try eeonRemindersList()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = "From an EEON voice note"
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
    }

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

    /// Mirror completion changes from EEON back into the reminder created for
    /// an extracted action. Best effort: no-op if Reminders sync is off, access
    /// is missing, or the action was never pushed to Reminders.
    func updateCompletion(for action: ExtractedAction) async {
        guard isEnabled else { return }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }

        var map = reminderMap()
        guard let identifier = map[action.id.uuidString] else { return }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            map.removeValue(forKey: action.id.uuidString)
            saveReminderMap(map)
            return
        }

        reminder.isCompleted = action.isCompleted
        reminder.completionDate = action.isCompleted ? (action.completedAt ?? Date()) : nil

        do {
            try store.save(reminder, commit: true)
        } catch {
            print("[EventKitSync] reminder completion update failed: \(error)")
        }
    }

    /// Remove the Apple Reminder paired to an EEON task when the task is
    /// deleted. Best effort: if Reminders access is missing, keep the mapping
    /// so a later authorized cleanup still has the identifier.
    func deleteReminder(forActionID actionID: UUID) async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }

        var map = reminderMap()
        guard let identifier = map[actionID.uuidString] else { return }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            map.removeValue(forKey: actionID.uuidString)
            saveReminderMap(map)
            return
        }

        do {
            try store.remove(reminder, commit: true)
            map.removeValue(forKey: actionID.uuidString)
            saveReminderMap(map)
        } catch {
            print("[EventKitSync] reminder delete failed: \(error)")
        }
    }

    /// Mirror a renamed EEON task onto its paired Apple Reminder, if any.
    func updateTitle(for action: ExtractedAction) async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        guard let identifier = reminderMap()[action.id.uuidString],
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder,
              reminder.title != action.content else { return }
        reminder.title = action.content
        do {
            try store.save(reminder, commit: true)
        } catch {
            print("[EventKitSync] reminder rename failed: \(error)")
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
