//
//  CalendarMeetingsView.swift
//  voice notes
//
//  Calendar is not just metadata for saved notes. It is a working surface:
//  see today's, this week's, or this month's meetings, then record with the
//  same EventKit context EEON attaches to voice notes.
//

import SwiftUI
import SwiftData

private enum CalendarMeetingScope: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        }
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 604800)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 2592000)
        }
    }
}

private struct CalendarMeetingsSnapshot {
    let meetings: [CalendarMeeting]
    let readSummary: CalendarReadSummary?
    let googleSummary: GoogleCalendarReadSummary?
    let savedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(savedAt) < 90
    }
}

@MainActor
private enum CalendarMeetingsMemoryCache {
    static var snapshots: [String: CalendarMeetingsSnapshot] = [:]
}

struct CalendarMeetingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL

    @AppStorage(CalendarContextService.enabledKey) private var calendarContextEnabled = false
    @AppStorage(GoogleCalendarService.includeSharedCalendarsKey) private var includeSharedGoogleCalendars = false
    @AppStorage("calendarMeetingsIncludeIPhoneCalendars") private var includeIPhoneCalendars = false
    private var googleCalendarService = GoogleCalendarService.shared

    @Query(sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]

    var embedded: Bool = false
    var onRecord: (() -> Void)?

    @State private var scope: CalendarMeetingScope = .today
    @State private var meetings: [CalendarMeeting] = []
    @State private var readSummary: CalendarReadSummary?
    @State private var googleSummary: GoogleCalendarReadSummary?
    @State private var selectedMeetingID: String?
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

    init(embedded: Bool = false, onRecord: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onRecord = onRecord
    }

    private var selectedMeeting: CalendarMeeting? {
        if let selectedMeetingID,
           let selected = meetings.first(where: { $0.id == selectedMeetingID }) {
            return selected
        }
        return meetings.first
    }

    private var isCalendarReady: Bool {
        isScreenshotMode
            || googleCalendarService.isConnected
            || (calendarContextEnabled && CalendarContextService.shared.isAuthorized)
    }

    private var isScreenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SeedScreenshotData")
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: embedded ? EEONLayout.snug : EEONLayout.standard) {
            calendarRangeHeader

            if !isCalendarReady {
                connectState
            } else if shouldShowFullLoadingState {
                loadingState
            } else if meetings.isEmpty {
                calendarStatusLine
                emptyState
            } else {
                calendarStatusLine
                if horizontalSizeClass == .regular, !embedded, let selectedMeeting {
                    HStack(alignment: .top, spacing: EEONLayout.standard) {
                        meetingList
                        meetingDetail(selectedMeeting)
                            .frame(width: 320)
                    }
                } else {
                    meetingList
                    if !embedded, let selectedMeeting {
                        meetingDetail(selectedMeeting)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .task { await refreshMeetings() }
        .onChange(of: scope) { _, _ in
            Task { await refreshMeetings() }
        }
        .onChange(of: includeSharedGoogleCalendars) { _, _ in
            Task { await refreshMeetings(force: true) }
        }
        .onChange(of: includeIPhoneCalendars) { _, _ in
            Task { await refreshMeetings(force: true) }
        }
    }

    private var shouldShowFullLoadingState: Bool {
        isLoading && !hasLoadedOnce && meetings.isEmpty && readSummary == nil && googleSummary == nil
    }

    @ViewBuilder
    private var calendarRangeHeader: some View {
        if embedded {
            HStack(alignment: .center, spacing: EEONLayout.tight) {
                Label("Calendar", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)

                Spacer(minLength: EEONLayout.tight)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.eeonAccent)
                }

                calendarOptionsMenu
                refreshCalendarButton
                calendarRangeMenu
            }
        } else {
            fullCalendarRangeHeader
        }
    }

    private var fullCalendarRangeHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: EEONLayout.tight) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scopeTitle)
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)

                Text(scopeSubtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer(minLength: EEONLayout.tight)

            calendarRangeMenu
        }
    }

    private var calendarRangeMenu: some View {
        Menu {
            ForEach(CalendarMeetingScope.allCases) { item in
                Button {
                    scope = item
                } label: {
                    if item == scope {
                        Label(item.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(item.menuTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(scope.rawValue)
                    .font(EEONType.control)
                Image(systemName: "chevron.down")
                    .font(EEONType.badge)
            }
            .foregroundStyle(Color.eeonAccent)
            .frame(minHeight: EEONLayout.minTarget)
        }
        .accessibilityLabel("Calendar range")
        .accessibilityValue(scope.rawValue)
    }

    @ViewBuilder
    private var calendarOptionsMenu: some View {
        if googleCalendarService.isConnected {
            Menu {
                Toggle(isOn: $includeSharedGoogleCalendars) {
                    Label("Shared Google calendars", systemImage: "person.2")
                }
                if calendarContextEnabled && CalendarContextService.shared.isAuthorized {
                    Toggle(isOn: $includeIPhoneCalendars) {
                        Label("iPhone Calendar", systemImage: "calendar")
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(EEONType.badge)
                    .foregroundStyle(.eeonTextSecondary)
                    .eeonTapTarget()
            }
            .accessibilityLabel("Calendar Options")
        }
    }

    private var refreshCalendarButton: some View {
        Button {
            Task { await refreshMeetings(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(EEONType.badge)
                .foregroundStyle(.eeonTextSecondary)
                .eeonTapTarget()
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("Refresh Calendar")
    }

    private var scopeTitle: String {
        switch scope {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        }
    }

    private var scopeSubtitle: String {
        let interval = scope.interval(containing: Date())
        switch scope {
        case .today:
            return Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .week:
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) - \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return Date().formatted(.dateTime.month(.wide).year())
        }
    }

    @ViewBuilder
    private var calendarStatusLine: some View {
        if !embedded || errorMessage != nil {
            HStack(spacing: EEONLayout.tight) {
                Image(systemName: errorMessage == nil ? "calendar.badge.checkmark" : "exclamationmark.triangle")
                    .font(EEONType.badge)
                    .foregroundStyle(errorMessage == nil ? Color.eeonAccentAI : Color.orange)

                Text(statusText)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(2)

                Spacer(minLength: EEONLayout.tight)

                if !embedded {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.eeonAccent)
                    }

                    calendarOptionsMenu
                    refreshCalendarButton
                }
            }
        }
    }

    private var statusText: String {
        if let errorMessage { return errorMessage }
        guard let readSummary else {
            if let googleSummary { return googleSummary.statusLine }
            return "Checking connected calendars"
        }
        if let googleSummary {
            return "\(googleSummary.statusLine). iPhone: \(readSummary.visibleMeetingCount) meetings from \(readSummary.calendarCount) calendars."
        }
        if googleCalendarService.isConnected {
            return "Google connected. iPhone: \(readSummary.visibleMeetingCount) meetings from \(readSummary.calendarCount) calendars."
        }
        if !googleCalendarService.isConfigured {
            return "Google direct needs OAuth config. iPhone: \(readSummary.visibleMeetingCount) meetings from \(readSummary.calendarCount) calendars."
        }
        return "\(readSummary.visibleMeetingCount) meetings from \(readSummary.calendarCount) calendars: \(readSummary.sourceSummary)"
    }

    private var meetingList: some View {
        LazyVStack(alignment: .leading, spacing: embedded ? EEONLayout.tight : EEONLayout.snug) {
            ForEach(meetings) { meeting in
                meetingRow(meeting)
            }
        }
    }

    private func meetingRow(_ meeting: CalendarMeeting) -> some View {
        let isSelected = !embedded && selectedMeeting?.id == meeting.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMeetingID = meeting.id
            }
            if embedded, let meetingURL = meeting.meetingURL {
                openURL(meetingURL)
            }
        } label: {
            HStack(spacing: embedded ? 10 : 12) {
                Text(initials(for: meeting))
                    .font(embedded ? EEONType.badge : EEONType.control)
                    .foregroundStyle(.white)
                    .frame(width: embedded ? 34 : 42, height: embedded ? 34 : 42)
                    .background(Circle().fill(Color.eeonAccentAI.opacity(0.86)))

                VStack(alignment: .leading, spacing: embedded ? 2 : 4) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(embedded ? EEONType.preview : EEONType.itemTitle)
                            .foregroundStyle(.eeonTextPrimary)
                            .lineLimit(embedded ? 1 : 2)

                        if meeting.meetingURL != nil && !embedded {
                            Image(systemName: "video.fill")
                                .font(EEONType.badge)
                                .foregroundStyle(Color.eeonAccent)
                        }
                    }

                    Text(meetingMetaLine(for: meeting))
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .lineLimit(1)

                    if !embedded {
                        Text(meeting.calendarTitle)
                            .font(EEONType.badge)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if meeting.isHappeningNow {
                    Text("Now")
                        .font(EEONType.badge)
                        .foregroundStyle(Color.eeonAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.eeonAccent.opacity(0.13))
                        .clipShape(Capsule())
                } else if embedded, meeting.meetingURL != nil {
                    Image(systemName: "video")
                        .font(EEONType.control)
                        .foregroundStyle(Color.eeonAccent)
                } else {
                    if !embedded {
                        Image(systemName: "chevron.right")
                            .font(EEONType.badge)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
            }
            .padding(embedded ? 10 : 12)
            .background(isSelected ? Color.eeonAccentAI.opacity(0.12) : Color.eeonCard)
            .overlay(
                RoundedRectangle(cornerRadius: EEONLayout.cardRadius)
                    .stroke(isSelected ? Color.eeonAccentAI.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func meetingDetail(_ meeting: CalendarMeeting) -> some View {
        VStack(alignment: .leading, spacing: EEONLayout.standard) {
            detailSection("Details") {
                VStack(alignment: .leading, spacing: EEONLayout.tight) {
                    Text(meeting.title)
                        .font(EEONType.itemTitle)
                        .foregroundStyle(.eeonTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(timeLine(for: meeting), systemImage: "clock")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)

                    if let location = meeting.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
            }

            if !meeting.attendees.isEmpty {
                detailSection("People") {
                    VStack(alignment: .leading, spacing: EEONLayout.snug) {
                        ForEach(meeting.attendees, id: \.self) { person in
                            HStack(spacing: EEONLayout.snug) {
                                Text(initials(from: person))
                                    .font(EEONType.badge)
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.eeonTextSecondary))
                                Text(person)
                                    .font(EEONType.preview)
                                    .foregroundStyle(.eeonTextPrimary)
                            }
                        }
                    }
                }
            }

            let relatedNotes = matchingNotes(for: meeting)
            if !relatedNotes.isEmpty {
                detailSection("Notes") {
                    VStack(alignment: .leading, spacing: EEONLayout.snug) {
                        ForEach(relatedNotes) { note in
                            NavigationLink(destination: NoteDetailView(note: note)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.title)
                                        .font(EEONType.control)
                                        .foregroundStyle(.eeonTextPrimary)
                                        .lineLimit(2)
                                    Text(note.createdAt.formatted(.dateTime.hour().minute()))
                                        .font(EEONType.badge)
                                        .foregroundStyle(.eeonTextTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: EEONLayout.tight) {
                if let meetingURL = meeting.meetingURL {
                    Button {
                        openURL(meetingURL)
                    } label: {
                        Label("Open call", systemImage: "video")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.eeonAccentAI)
                }

                if let onRecord {
                    Button {
                        onRecord()
                    } label: {
                        Label("Record", systemImage: "waveform")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.eeonAccent)
                }
            }
            .font(EEONType.control)
        }
        .padding(EEONLayout.standard)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            Text(title)
                .font(EEONType.section)
                .foregroundStyle(.eeonTextSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(.eeonTextTertiary)

            Text("Connect a calendar")
                .font(.headline)
                .foregroundStyle(.eeonTextSecondary)

            Text("Connect Google directly, or use the calendars already visible in iPhone Calendar.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: EEONLayout.tight) {
                Button {
                    connectGoogle()
                } label: {
                    Label("Connect Google Calendar", systemImage: "g.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.eeonAccent)

                Button {
                    enableCalendar()
                } label: {
                    Label("Use iPhone Calendar", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Color.eeonAccentAI)
            }
            .font(EEONType.control)

            if let errorMessage {
                Text(errorMessage)
                    .font(EEONType.meta)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Permission: \(CalendarContextService.shared.authorizationStatusLabel)")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.eeonAccent)
            Text("Loading calendar")
                .font(EEONType.body)
                .foregroundStyle(.eeonTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 44))
                .foregroundStyle(.eeonTextTertiary)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.eeonTextSecondary)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.eeonTextTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let readSummary, readSummary.calendarCount == 0 {
                Button {
                    openURL(URL(string: "calshow://")!)
                } label: {
                    Label("Open iPhone Calendar", systemImage: "calendar")
                }
                .font(EEONType.control)
                .buttonStyle(.bordered)
                .tint(Color.eeonAccentAI)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "No meetings today"
        case .week: return "No meetings this week"
        case .month: return "No meetings this month"
        }
    }

    private var emptyMessage: String {
        guard let readSummary else {
            if googleCalendarService.isConnected {
                return "Google Calendar is connected, but it returned no meetings for this range."
            }
            return "EEON is checking connected calendars."
        }
        if googleCalendarService.isConnected, let googleSummary, googleSummary.meetingCount == 0 {
            return "Google Calendar is connected and returned \(googleSummary.eventCount) events for this range. Try Week or Month if the meeting is later."
        }
        if readSummary.calendarCount == 0 {
            if googleCalendarService.isConfigured {
                return "iPhone Calendar returned no calendars. If the meeting only exists in Google, connect Google Calendar directly."
            }
            return "iPhone Calendar returned no calendars. Open iPhone Calendar and make sure your Google calendars are enabled."
        }
        if readSummary.rawEventCount == 0 {
            if googleCalendarService.isConfigured {
                return "iPhone Calendar has no events in this range. If the meeting is in Google but not on the phone, connect Google Calendar directly."
            }
            return "EEON can see \(readSummary.calendarCount) calendars, but EventKit returned no events for this range. Try Week or Month, or check that the Google calendar is selected in iPhone Calendar."
        }
        return "EEON found \(readSummary.rawEventCount) calendar events here, but none are scheduled meetings after filtering all-day or declined events."
    }

    private func enableCalendar() {
        Task {
            errorMessage = nil
            let granted = await CalendarContextService.shared.requestAccess()
            guard granted else {
                errorMessage = "Calendar access was not granted."
                return
            }
            calendarContextEnabled = true
            await refreshMeetings()
        }
    }

    @MainActor
    private func refreshMeetings(force: Bool = false) async {
        if isScreenshotMode {
            meetings = Self.fixtureMeetings()
            readSummary = CalendarReadSummary(
                authorizationStatus: "Full access",
                calendarCount: 3,
                sourceNames: ["Google", "iCloud"],
                rawEventCount: meetings.count,
                visibleMeetingCount: meetings.count
            )
            googleSummary = GoogleCalendarReadSummary(
                calendarCount: 1,
                hiddenSharedCalendarCount: 0,
                eventCount: meetings.count,
                meetingCount: 2
            )
            settleSelection()
            hasLoadedOnce = true
            return
        }

        guard googleCalendarService.isConnected || (calendarContextEnabled && CalendarContextService.shared.isAuthorized) else {
            meetings = []
            readSummary = nil
            googleSummary = nil
            selectedMeetingID = nil
            isLoading = false
            hasLoadedOnce = true
            return
        }

        let interval = scope.interval(containing: Date())
        let cacheKey = calendarCacheKey(for: interval)
        if let cached = CalendarMeetingsMemoryCache.snapshots[cacheKey], !force {
            apply(cached)
            if cached.isFresh {
                return
            }
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        var combined: [CalendarMeeting] = []
        if shouldReadIPhoneCalendar {
            readSummary = CalendarContextService.shared.readSummary(in: interval)
            combined.append(contentsOf: CalendarContextService.shared.meetings(in: interval))
        } else {
            readSummary = nil
        }

        if googleCalendarService.isConnected {
            do {
                let result = try await googleCalendarService.meetings(
                    in: interval,
                    includeSharedCalendars: includeSharedGoogleCalendars
                )
                googleSummary = result.summary
                combined.append(contentsOf: result.meetings)
            } catch {
                googleSummary = nil
                errorMessage = error.localizedDescription
            }
        } else {
            googleSummary = nil
        }

        let nextMeetings = Dictionary(grouping: combined, by: { dedupeKey(for: $0) })
            .compactMap { $0.value.first }
            .sorted { $0.startDate < $1.startDate }
        let snapshot = CalendarMeetingsSnapshot(
            meetings: nextMeetings,
            readSummary: readSummary,
            googleSummary: googleSummary,
            savedAt: Date()
        )
        CalendarMeetingsMemoryCache.snapshots[cacheKey] = snapshot
        apply(snapshot)
        if let readSummary {
            print("[CalendarMeetings] scope=\(scope.rawValue) auth=\(readSummary.authorizationStatus) calendars=\(readSummary.calendarCount) sources=\(readSummary.sourceSummary) rawEvents=\(readSummary.rawEventCount) visibleMeetings=\(readSummary.visibleMeetingCount)")
        }
        if let googleSummary {
            print("[CalendarMeetings] scope=\(scope.rawValue) googleCalendars=\(googleSummary.calendarCount) googleEvents=\(googleSummary.eventCount) googleMeetings=\(googleSummary.meetingCount)")
        }
    }

    private func connectGoogle() {
        Task {
            errorMessage = nil
            do {
                try await googleCalendarService.signIn()
                await refreshMeetings()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func settleSelection() {
        if let selectedMeetingID,
           meetings.contains(where: { $0.id == selectedMeetingID }) {
            return
        }
        selectedMeetingID = meetings.first(where: { $0.isHappeningNow })?.id ?? meetings.first?.id
    }

    private var shouldReadIPhoneCalendar: Bool {
        guard calendarContextEnabled, CalendarContextService.shared.isAuthorized else { return false }
        return !googleCalendarService.isConnected || includeIPhoneCalendars
    }

    @MainActor
    private func apply(_ snapshot: CalendarMeetingsSnapshot) {
        meetings = snapshot.meetings
        readSummary = snapshot.readSummary
        googleSummary = snapshot.googleSummary
        settleSelection()
        hasLoadedOnce = true
    }

    private func calendarCacheKey(for interval: DateInterval) -> String {
        let start = Int(interval.start.timeIntervalSince1970)
        let end = Int(interval.end.timeIntervalSince1970)
        return "\(scope.rawValue)|\(start)|\(end)|sharedGoogle:\(includeSharedGoogleCalendars)|iphone:\(shouldReadIPhoneCalendar)|google:\(googleCalendarService.isConnected)"
    }

    private func dedupeKey(for meeting: CalendarMeeting) -> String {
        let normalizedTitle = meeting.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let startMinute = Int(meeting.startDate.timeIntervalSince1970 / 60)
        let endMinute = Int(meeting.endDate.timeIntervalSince1970 / 60)
        return "\(normalizedTitle)|\(startMinute)|\(endMinute)"
    }

    private func matchingNotes(for meeting: CalendarMeeting) -> [Note] {
        let padded = DateInterval(
            start: meeting.startDate.addingTimeInterval(-1800),
            end: meeting.endDate.addingTimeInterval(1800)
        )
        return Array(notes.filter { note in
            if let context = note.calendarContext {
                let contextInterval = DateInterval(start: context.startDate, end: context.endDate)
                if context.title.caseInsensitiveCompare(meeting.title) == .orderedSame {
                    return true
                }
                if contextInterval.intersects(padded) {
                    return true
                }
            }
            return note.sourceType == .voice && padded.contains(note.createdAt)
        }.prefix(3))
    }

    private func timeLine(for meeting: CalendarMeeting) -> String {
        let time = "\(timeOnly(meeting.startDate)) - \(timeOnly(meeting.endDate))"
        if scope == .today || Calendar.current.isDateInToday(meeting.startDate) {
            return time
        }
        let day = meeting.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day), \(time)"
    }

    private func meetingMetaLine(for meeting: CalendarMeeting) -> String {
        if !embedded {
            return timeLine(for: meeting)
        }

        var parts = [timeLine(for: meeting)]
        if meeting.meetingURL != nil {
            parts.append("Google Meet")
        } else if let location = meeting.location, !location.isEmpty {
            parts.append(location)
        } else if !meeting.calendarTitle.isEmpty {
            parts.append(meeting.calendarTitle)
        }
        return parts.joined(separator: " · ")
    }

    private func timeOnly(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func initials(for meeting: CalendarMeeting) -> String {
        if let first = meeting.attendees.first {
            return initials(from: first)
        }
        return initials(from: meeting.title)
    }

    private func initials(from text: String) -> String {
        let words = text
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(words).uppercased()
        return value.isEmpty ? "EE" : value
    }

    private static func fixtureMeetings() -> [CalendarMeeting] {
        let now = Date()
        return [
            CalendarMeeting(
                id: "fixture-standup",
                title: "Standup",
                calendarTitle: "Google Calendar",
                startDate: now.addingTimeInterval(-1500),
                endDate: now.addingTimeInterval(2100),
                location: "Google Meet",
                attendees: ["Lena Ortiz", "Marco"],
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
            ),
            CalendarMeeting(
                id: "fixture-pricing",
                title: "StockAlarm pricing review",
                calendarTitle: "Google Calendar",
                startDate: now.addingTimeInterval(5400),
                endDate: now.addingTimeInterval(9000),
                location: nil,
                attendees: ["Patrick Shannon"],
                meetingURL: URL(string: "https://meet.google.com/prc-rvw-eeon")
            ),
            CalendarMeeting(
                id: "fixture-customer",
                title: "Customer follow-up",
                calendarTitle: "iCloud",
                startDate: now.addingTimeInterval(12600),
                endDate: now.addingTimeInterval(14400),
                location: "Phone",
                attendees: ["Craig"],
                meetingURL: nil
            )
        ]
    }
}
