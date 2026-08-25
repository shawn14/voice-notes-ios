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

@Observable
final class CalendarContextService {
    static let shared = CalendarContextService()

    static let enabledKey = "calendarContextEnabled"
    static let maxAttendees = 8

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
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
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
}
