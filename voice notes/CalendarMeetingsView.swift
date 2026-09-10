//
//  CalendarMeetingsView.swift
//  voice notes
//
//  The Calendar section of Home: today's, this week's, or this month's
//  meetings, read from Google Calendar (direct OAuth) and/or iPhone Calendar
//  (EventKit). Record with the big button below it and EEON attaches the
//  overlapping event as context (CalendarContextService.attachIfNeeded).
//
//  This view is only ever rendered inside AIHomeView. The former full-screen
//  mode (split view, meeting detail pane, related notes) was unreachable and
//  was removed in the 2026-09-10 UX simplification.
//

import SwiftUI

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
    @Environment(\.openURL) private var openURL

    @AppStorage(CalendarContextService.enabledKey) private var calendarContextEnabled = false
    @AppStorage(GoogleCalendarService.includeSharedCalendarsKey) private var includeSharedGoogleCalendars = false
    @AppStorage("calendarMeetingsIncludeIPhoneCalendars") private var includeIPhoneCalendars = false
    private var googleCalendarService = GoogleCalendarService.shared

    /// Home's strip (Option A, 2026-09-10): today only, one title line that
    /// opens `CalendarScreen`, meetings as chips. The full view is the
    /// pushed screen.
    var compact: Bool = false

    init(compact: Bool = false) {
        self.compact = compact
    }

    /// The chosen range persists across visits and launches (Shawn,
    /// 2026-09-10: "if you pick day, week, or month, it stays that way"),
    /// and Home's strip follows it.
    @AppStorage("calendarMeetingScope") private var scopeRaw: String = CalendarMeetingScope.today.rawValue
    private var scope: CalendarMeetingScope {
        get { CalendarMeetingScope(rawValue: scopeRaw) ?? .today }
        nonmutating set { scopeRaw = newValue.rawValue }
    }
    @State private var meetings: [CalendarMeeting] = []
    @State private var readSummary: CalendarReadSummary?
    @State private var googleSummary: GoogleCalendarReadSummary?
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

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
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            if compact {
                compactStrip
            } else {
                header

                googleReauthBanner

                if !isCalendarReady {
                    connectState
                } else if shouldShowFullLoadingState {
                    loadingState
                } else {
                    errorLine
                    if meetings.isEmpty {
                        emptyState
                    } else {
                        meetingList
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, compact ? 0 : 4)
        .task { await refreshMeetings() }
        .onChange(of: scopeRaw) { _, _ in
            Task { await refreshMeetings() }
        }
        .onChange(of: includeSharedGoogleCalendars) { _, _ in
            Task { await refreshMeetings(force: true) }
        }
        .onChange(of: includeIPhoneCalendars) { _, _ in
            Task { await refreshMeetings(force: true) }
        }
    }

    // MARK: - Compact strip (Home)

    private var compactTitle: String {
        if !isCalendarReady { return "Calendar · not connected" }
        let range = scope.menuTitle
        if !hasLoadedOnce { return range }
        switch meetings.count {
        case 0: return "\(range) · no meetings"
        case 1: return "\(range) · 1 meeting"
        default: return "\(range) · \(meetings.count) meetings"
        }
    }

    private var compactStrip: some View {
        VStack(alignment: .leading, spacing: EEONLayout.tight) {
            NavigationLink {
                CalendarScreen()
            } label: {
                HStack(spacing: EEONLayout.tight) {
                    Image(systemName: "calendar")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextSecondary)
                    Text(compactTitle)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextTertiary)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.eeonAccent)
                    }
                }
                .frame(minHeight: EEONLayout.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar")

            if googleCalendarService.needsReauth {
                HStack(spacing: EEONLayout.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(EEONType.badge)
                        .foregroundStyle(Color.orange)
                    Text("Google sign-in expired")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    Spacer(minLength: EEONLayout.tight)
                    Button("Reconnect") { connectGoogle() }
                        .font(EEONType.control)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.eeonAccent)
                }
            }

            if !meetings.isEmpty {
                let shown = Array(meetings.prefix(Self.compactRowLimit))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, meeting in
                        compactRow(meeting)
                        if index < shown.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                    if meetings.count > shown.count {
                        Divider().padding(.leading, 14)
                        NavigationLink {
                            CalendarScreen()
                        } label: {
                            HStack(spacing: EEONLayout.tight) {
                                Text("More")
                                    .font(EEONType.control)
                                    .foregroundStyle(.eeonAccent)
                                Text("\(meetings.count - shown.count)")
                                    .font(EEONType.meta)
                                    .foregroundStyle(.eeonTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(EEONType.badge)
                                    .foregroundStyle(.eeonAccent)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.eeonCard)
                .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
            }
        }
    }

    private static let compactRowLimit = 3

    /// Day for a meeting that is not today: weekday in Week, date in Month.
    private func compactDayLabel(for meeting: CalendarMeeting) -> String? {
        if Calendar.current.isDateInToday(meeting.startDate) { return nil }
        switch scope {
        case .today, .week:
            return meeting.startDate.formatted(.dateTime.weekday(.abbreviated))
        case .month:
            return meeting.startDate.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// A row is tappable only when it has somewhere to go (a call link).
    @ViewBuilder
    private func compactRow(_ meeting: CalendarMeeting) -> some View {
        if let meetingURL = meeting.meetingURL {
            Button {
                openURL(meetingURL)
            } label: {
                compactRowContent(meeting)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the call")
        } else {
            compactRowContent(meeting)
        }
    }

    private func compactRowContent(_ meeting: CalendarMeeting) -> some View {
        let now = meeting.isHappeningNow
        return HStack(alignment: .center, spacing: EEONLayout.snug) {
            VStack(alignment: .leading, spacing: 1) {
                if let day = compactDayLabel(for: meeting) {
                    Text(day)
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextTertiary)
                }
                Text(timeOnly(meeting.startDate))
                    .font(EEONType.meta)
                    .foregroundStyle(now ? Color.eeonAccent : Color.eeonTextSecondary)
                    .monospacedDigit()
            }
            .frame(width: 74, alignment: .leading)

            Text(meeting.title)
                .font(EEONType.itemTitle)
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if now {
                Text("Now")
                    .font(EEONType.badge)
                    .foregroundStyle(Color.eeonAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.eeonAccent.opacity(0.13)))
            } else if meeting.meetingURL != nil {
                Image(systemName: "video")
                    .font(EEONType.badge)
                    .foregroundStyle(Color.eeonAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Header

    /// Same shape as the Tasks and Notes headers on Home: title + meta line on
    /// the left, one control on the right. Range, refresh, and calendar
    /// options all live in that single menu.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: EEONLayout.tight) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar")
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
                Text(scopeSubtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer(minLength: EEONLayout.tight)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.eeonAccent)
            }

            calendarMenu
        }
    }

    private var calendarMenu: some View {
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

            Divider()

            Button {
                Task { await refreshMeetings(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)

            if googleCalendarService.isConnected {
                Divider()
                Toggle(isOn: $includeSharedGoogleCalendars) {
                    Label("Shared Google calendars", systemImage: "person.2")
                }
                if calendarContextEnabled && CalendarContextService.shared.isAuthorized {
                    Toggle(isOn: $includeIPhoneCalendars) {
                        Label("iPhone Calendar", systemImage: "calendar")
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
        .accessibilityLabel("Calendar options")
        .accessibilityValue(scope.rawValue)
    }

    private var scopeSubtitle: String {
        let interval = scope.interval(containing: Date())
        switch scope {
        case .today:
            return Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .week:
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return Date().formatted(.dateTime.month(.wide).year())
        }
    }

    /// Shown whenever Google has permanently rejected our token. It survives
    /// refreshes (unlike `errorMessage`, which clears as soon as we stop calling
    /// Google) so a dead connection cannot quietly disappear behind iPhone
    /// Calendar results.
    @ViewBuilder
    private var googleReauthBanner: some View {
        if googleCalendarService.needsReauth {
            HStack(alignment: .firstTextBaseline, spacing: EEONLayout.tight) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(EEONType.badge)
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Calendar sign-in expired")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                    if CalendarContextService.shared.isAuthorized, calendarContextEnabled {
                        Text("Showing iPhone Calendar until you reconnect.")
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }

                Spacer(minLength: EEONLayout.tight)

                Button("Reconnect") { connectGoogle() }
                    .font(EEONType.control)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.eeonAccent)
            }
            .padding(.vertical, 6)
        }
    }

    private var shouldShowFullLoadingState: Bool {
        isLoading && !hasLoadedOnce && meetings.isEmpty && readSummary == nil && googleSummary == nil
    }

    /// Only speaks when a read actually failed; healthy state is silent.
    @ViewBuilder
    private var errorLine: some View {
        if let errorMessage {
            HStack(spacing: EEONLayout.tight) {
                Image(systemName: "exclamationmark.triangle")
                    .font(EEONType.badge)
                    .foregroundStyle(Color.orange)
                Text(errorMessage)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(2)
                Spacer(minLength: EEONLayout.tight)
            }
        }
    }

    // MARK: - Meetings

    private var meetingList: some View {
        LazyVStack(alignment: .leading, spacing: EEONLayout.tight) {
            ForEach(meetings) { meeting in
                meetingRow(meeting)
            }
        }
    }

    /// A row is tappable only when it has somewhere to go (a call link).
    @ViewBuilder
    private func meetingRow(_ meeting: CalendarMeeting) -> some View {
        if let meetingURL = meeting.meetingURL {
            Button {
                openURL(meetingURL)
            } label: {
                meetingRowContent(meeting)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the call")
        } else {
            meetingRowContent(meeting)
        }
    }

    private func meetingRowContent(_ meeting: CalendarMeeting) -> some View {
        HStack(spacing: 10) {
            Text(initials(for: meeting))
                .font(EEONType.badge)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.eeonAccentAI.opacity(0.86)))

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(EEONType.preview)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(1)

                Text(meetingMetaLine(for: meeting))
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(1)
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
            } else if meeting.meetingURL != nil {
                Image(systemName: "video")
                    .font(EEONType.control)
                    .foregroundStyle(Color.eeonAccent)
            }
        }
        .padding(10)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }

    // MARK: - States

    /// Compact: Home's setup checklist already explains calendars at length.
    private var connectState: some View {
        VStack(alignment: .leading, spacing: EEONLayout.snug) {
            Text("No calendar connected")
                .font(EEONType.control)
                .foregroundStyle(.eeonTextPrimary)
            Text("Meetings show here once a calendar is connected.")
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextSecondary)

            HStack(spacing: EEONLayout.tight) {
                Button {
                    connectGoogle()
                } label: {
                    Label("Google Calendar", systemImage: "g.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.eeonAccent)

                Button {
                    enableCalendar()
                } label: {
                    Label("iPhone Calendar", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Color.eeonAccentAI)
            }
            .font(EEONType.control)
            .controlSize(.small)

            if let errorMessage {
                Text(errorMessage)
                    .font(EEONType.meta)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.eeonAccent)
            Text("Loading calendar")
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    /// One quiet line. A hint appears only when something looks wrong, not
    /// merely because the day is free.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(emptyTitle)
                .font(EEONType.control)
                .foregroundStyle(.eeonTextSecondary)

            if let hint = emptyHint {
                Text(hint)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let readSummary, readSummary.calendarCount == 0 {
                Button {
                    openURL(URL(string: "calshow://")!)
                } label: {
                    Label("Open iPhone Calendar", systemImage: "calendar")
                }
                .font(EEONType.control)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.eeonAccentAI)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var emptyTitle: String {
        switch scope {
        case .today: return "No meetings today"
        case .week: return "No meetings this week"
        case .month: return "No meetings this month"
        }
    }

    private var emptyHint: String? {
        if let readSummary, readSummary.calendarCount == 0 {
            return "iPhone Calendar returned no calendars. Check that your calendars are enabled there."
        }
        let hiddenEvents = (readSummary?.rawEventCount ?? 0) + (googleSummary?.eventCount ?? 0)
        if hiddenEvents > 0 {
            return "All-day and declined events are hidden."
        }
        return nil
    }

    // MARK: - Data

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
            hasLoadedOnce = true
            return
        }

        guard googleCalendarService.isConnected || (calendarContextEnabled && CalendarContextService.shared.isAuthorized) else {
            meetings = []
            readSummary = nil
            googleSummary = nil
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
                // Google just dropped out. If iPhone Calendar is available, read it
                // now rather than showing an empty day until the next refresh —
                // `shouldReadIPhoneCalendar` skipped it while Google looked healthy.
                if combined.isEmpty,
                   calendarContextEnabled,
                   CalendarContextService.shared.isAuthorized {
                    readSummary = CalendarContextService.shared.readSummary(in: interval)
                    combined.append(contentsOf: CalendarContextService.shared.meetings(in: interval))
                }
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

    private var shouldReadIPhoneCalendar: Bool {
        guard calendarContextEnabled, CalendarContextService.shared.isAuthorized else { return false }
        return !googleCalendarService.isConnected || includeIPhoneCalendars
    }

    @MainActor
    private func apply(_ snapshot: CalendarMeetingsSnapshot) {
        meetings = snapshot.meetings
        readSummary = snapshot.readSummary
        googleSummary = snapshot.googleSummary
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

    // MARK: - Formatting

    private func timeLine(for meeting: CalendarMeeting) -> String {
        let time = "\(timeOnly(meeting.startDate)) - \(timeOnly(meeting.endDate))"
        if scope == .today || Calendar.current.isDateInToday(meeting.startDate) {
            return time
        }
        let day = meeting.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day), \(time)"
    }

    private func meetingMetaLine(for meeting: CalendarMeeting) -> String {
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

    // MARK: - Screenshot fixtures

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

/// The full calendar — Today / Week / Month, refresh, calendar options —
/// pushed from Home's strip. Same view, non-compact.
struct CalendarScreen: View {
    var body: some View {
        ScrollView {
            CalendarMeetingsView()
                .padding(.top, 8)
        }
        .background(Color.eeonBackground.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
