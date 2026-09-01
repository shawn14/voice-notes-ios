//
//  CalendarContextService.swift
//  voice notes
//
//  "Calendar context": when a recording overlaps a calendar event, the note
//  learns the event's title and who was there. The AI title and the
//  extraction pass get that as context ("Standup with Lena and Marco"
//  instead of "Discussion about the launch"), and the note shows
//  "During Standup · with Lena, Marco".
//
//  One EventKit implementation covers Apple, Google and Outlook calendars —
//  whatever accounts the phone already has — with no OAuth, the same way
//  Reminders sync and markdown export cover their three logos. Read-only:
//  EEON never writes to the calendar.
//
//  Off by default; enabled from Settings → Connections, which triggers the
//  system permission prompt (NSCalendarsFullAccessUsageDescription).
//

import Foundation
import EventKit
import AVFoundation

/// What we keep from the event. Stored on Note as JSON (calendarContextJSON).
nonisolated struct CalendarContext: Codable, Equatable {
    let title: String
    let attendees: [String]
    let startDate: Date
    let endDate: Date
    let location: String?

    /// One line for the AI prompts. Facts only — the model is told not to
    /// invent content from it.
    var promptLine: String {
        var line = "Recorded during the calendar event \"\(title)\""
        if !attendees.isEmpty {
            line += " with " + attendees.joined(separator: ", ")
        }
        if let location, !location.isEmpty {
            line += " at " + location
        }
        return line + "."
    }

    /// "with Lena, Marco" / "with Lena, Marco and 3 others"
    var attendeesLabel: String? {
        guard !attendees.isEmpty else { return nil }
        let shown = attendees.prefix(3)
        let rest = attendees.count - shown.count
        var label = "with " + shown.joined(separator: ", ")
        if rest > 0 { label += " and \(rest) other\(rest == 1 ? "" : "s")" }
        return label
    }
}

nonisolated struct CalendarMeeting: Identifiable, Equatable {
    let id: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let attendees: [String]
    let meetingURL: URL?

    var isHappeningNow: Bool {
        DateInterval(start: startDate, end: endDate).contains(Date())
    }
}

nonisolated struct CalendarReadSummary: Equatable {
    let authorizationStatus: String
    let calendarCount: Int
    let sourceNames: [String]
    let rawEventCount: Int
    let visibleMeetingCount: Int

    var sourceSummary: String {
        guard !sourceNames.isEmpty else { return "No calendar sources visible" }
        let shown = sourceNames.prefix(3).joined(separator: ", ")
        let extra = sourceNames.count - min(sourceNames.count, 3)
        return extra > 0 ? "\(shown) + \(extra) more" : shown
    }
}

@Observable
final class CalendarContextService {
    static let shared = CalendarContextService()

    static let enabledKey = "calendarContextEnabled"
    nonisolated static let maxAttendees = 8

    /// Recording start is a little before the file's first sample and the
    /// user often presses Record a minute into a meeting; pad both ends.
    private static let windowPadding: TimeInterval = 60

    private let store = EKEventStore()

    /// Notes already looked up this process (matched or not), plus notes
    /// excluded outright (audio imports). Every voice path calls
    /// `attachIfNeeded`, so without this a note with no overlapping event
    /// would be queried twice (title pass, then processNoteSave).
    private var settled = Set<UUID>()

    private init() {}

    /// Imported audio was recorded some other time; the event at the moment
    /// of import is irrelevant. Call before the import's first AI pass.
    func excludeFromMatching(_ noteID: UUID) {
        settled.insert(noteID)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isAuthorized: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return true
        case .notDetermined, .restricted, .denied, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    var authorizationStatusLabel: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .fullAccess: return "Full access"
        case .writeOnly: return "Write only"
        @unknown default: return "Unknown"
        }
    }

    /// iOS 17+ full-access request (read needs full access; write-only is
    /// the one that doesn't). Returns whether access was granted.
    func requestAccess() async -> Bool {
        do { return try await store.requestFullAccessToEvents() }
        catch {
            print("[CalendarContext] access request failed: \(error)")
            return false
        }
    }

    // MARK: - Attach

    /// Looks up the event the note's recording overlapped and stores it on
    /// the note. No-op unless enabled + authorized, the note is a voice
    /// capture with audio, and nothing is attached yet — so it is safe to
    /// call from every processing path (foreground, background capture,
    /// pending drain, processNoteSave) without double work.
    func attachIfNeeded(to note: Note) async {
        guard isEnabled, isAuthorized else { return }
        guard note.calendarContextJSON == nil,
              !settled.contains(note.id),
              note.sourceType == .voice,
              let audioURL = note.audioURL else { return }
        settled.insert(note.id)

        // Duration may not be on the note yet (AIHomeView loads it
        // asynchronously); read the file if so.
        var duration = note.audioDuration ?? 0
        if duration <= 0 {
            if let loaded = try? await AVURLAsset(url: audioURL).load(.duration) {
                let seconds = CMTimeGetSeconds(loaded)
                if seconds.isFinite && seconds > 0 { duration = seconds }
            }
        }

        // Recording window. AudioRecorder creates the file when recording
        // starts, so the file's creation date is the true start. Note.createdAt
        // is NOT the stop time on the foreground path — saveNote runs after
        // Whisper + filler-word cleanup, 10–60s later, which on a back-to-back
        // schedule is enough to land the note in the wrong meeting.
        let start: Date
        let end: Date
        if let created = (try? FileManager.default.attributesOfItem(atPath: audioURL.path))?[.creationDate] as? Date,
           created <= note.createdAt {
            start = created
            end = duration > 0 ? created.addingTimeInterval(duration) : note.createdAt
        } else {
            end = note.createdAt
            start = end.addingTimeInterval(-duration)
        }

        if let context = event(overlapping: start, end: end) {
            note.calendarContext = context
        }
    }

    /// The non-all-day event with the largest overlap with [start, end],
    /// skipping events the user declined. Nil when nothing overlaps.
    func event(overlapping start: Date, end: Date) -> CalendarContext? {
        guard isAuthorized else { return nil }
        let windowStart = start.addingTimeInterval(-Self.windowPadding)
        let windowEnd = end.addingTimeInterval(Self.windowPadding)
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)

        var best: (event: EKEvent, overlap: TimeInterval)?
        for event in store.events(matching: predicate) where !event.isAllDay {
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                continue
            }
            let overlap = min(windowEnd, event.endDate).timeIntervalSince(max(windowStart, event.startDate))
            guard overlap > 0 else { continue }
            if best == nil || overlap > best!.overlap {
                best = (event, overlap)
            }
        }
        guard let event = best?.event else { return nil }

        let attendees = (event.attendees ?? [])
            .filter { !$0.isCurrentUser }
            .compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("@") }   // drop bare addresses
            .prefix(Self.maxAttendees)

        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return CalendarContext(
            title: title,
            attendees: Array(attendees),
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// User-facing calendar view: upcoming meetings in a date interval.
    /// Same EventKit store as context matching, so Google Calendar support is
    /// exactly whatever the iPhone Calendar app can already see.
    func meetings(in interval: DateInterval) -> [CalendarMeeting] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                if let me = event.attendees?.first(where: { $0.isCurrentUser }),
                   me.participantStatus == .declined {
                    return false
                }
                return !(event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.startDate < $1.startDate }
            .map(meeting(from:))
    }

    func readSummary(in interval: DateInterval) -> CalendarReadSummary {
        guard isAuthorized else {
            return CalendarReadSummary(
                authorizationStatus: authorizationStatusLabel,
                calendarCount: 0,
                sourceNames: [],
                rawEventCount: 0,
                visibleMeetingCount: 0
            )
        }

        let calendars = store.calendars(for: .event)
        let sourceNames = Array(Set(calendars.map { $0.source.title })).sorted()
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        let events = store.events(matching: predicate)
        let visible = events.filter { event in
            guard !event.isAllDay,
                  !(event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            if let me = event.attendees?.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined {
                return false
            }
            return true
        }

        return CalendarReadSummary(
            authorizationStatus: authorizationStatusLabel,
            calendarCount: calendars.count,
            sourceNames: sourceNames,
            rawEventCount: events.count,
            visibleMeetingCount: visible.count
        )
    }

    private func meeting(from event: EKEvent) -> CalendarMeeting {
        let attendees = (event.attendees ?? [])
            .filter { !$0.isCurrentUser }
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("@") }
            .prefix(Self.maxAttendees)

        return CalendarMeeting(
            id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
            title: (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            calendarTitle: event.calendar.title,
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            attendees: Array(attendees),
            meetingURL: meetingURL(from: event)
        )
    }

    private func meetingURL(from event: EKEvent) -> URL? {
        if let url = event.url, Self.isMeetingURL(url) {
            return url
        }

        let candidates = [event.location, event.notes].compactMap { $0 }
        var firstURL: URL?
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for candidate in candidates {
            let range = NSRange(candidate.startIndex..., in: candidate)
            let matches = detector?.matches(in: candidate, options: [], range: range) ?? []
            for match in matches {
                guard let url = match.url else { continue }
                if firstURL == nil { firstURL = url }
                if Self.isMeetingURL(url) { return url }
            }
        }
        return firstURL
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return text.contains("meet.google.com")
            || text.contains("zoom.us")
            || text.contains("teams.microsoft.com")
            || text.contains("webex.com")
    }
}
