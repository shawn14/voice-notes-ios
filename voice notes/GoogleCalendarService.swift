//
//  GoogleCalendarService.swift
//  voice notes
//
//  Direct Google Calendar integration for events that are not synced into
//  iPhone Calendar. Read-only: OAuth requests calendar.readonly, stores the
//  user's token in Keychain, and maps Google events into CalendarMeeting.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

nonisolated struct GoogleCalendarReadSummary: Equatable {
    let calendarCount: Int
    let hiddenSharedCalendarCount: Int
    let eventCount: Int
    let meetingCount: Int

    var statusLine: String {
        var line = "\(meetingCount) meetings from \(calendarCount) Google calendar\(calendarCount == 1 ? "" : "s")"
        if hiddenSharedCalendarCount > 0 {
            line += ". \(hiddenSharedCalendarCount) shared hidden"
        }
        return line
    }
}

@MainActor
@Observable
final class GoogleCalendarService {
    static let shared = GoogleCalendarService()
    static let includeSharedCalendarsKey = "googleCalendarIncludeSharedCalendars"

    private static let tokenService = "com.eeon.google-calendar"
    private static let tokenAccount = "oauth-token"
    private static let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var authSession: ASWebAuthenticationSession?
    private var presentationContextProvider = GoogleCalendarPresentationContextProvider()

    private init() {}

    var isConfigured: Bool {
        guard clientID != nil,
              registeredOAuthScheme != nil else { return false }
        return true
    }

    var isConnected: Bool {
        storedToken() != nil
    }

    var configurationStatus: String {
        if isConfigured { return "Ready" }
        if clientID == nil { return "Needs Google OAuth client ID" }
        return "Needs Google OAuth URL scheme"
    }

    func signIn() async throws {
        guard let clientID else { throw GoogleCalendarError.missingClientID }
        guard let callbackScheme = registeredOAuthScheme else { throw GoogleCalendarError.missingURLScheme }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 32)
        let redirectURI = Self.redirectURI(for: callbackScheme)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw GoogleCalendarError.badAuthURL }

        let callback = try await openAuthSession(authURL, callbackScheme: callbackScheme)
        let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let returnedState = values.first(where: { $0.name == "state" })?.value
        guard returnedState == state else { throw GoogleCalendarError.stateMismatch }
        if let error = values.first(where: { $0.name == "error" })?.value {
            throw GoogleCalendarError.oauth(error)
        }
        guard let code = values.first(where: { $0.name == "code" })?.value else {
            throw GoogleCalendarError.missingCode
        }

        let token = try await exchangeCode(code, verifier: verifier)
        try saveToken(token)
    }

    func disconnect() {
        deleteToken()
    }

    func meetings(
        in interval: DateInterval,
        includeSharedCalendars: Bool = false
    ) async throws -> (summary: GoogleCalendarReadSummary, meetings: [CalendarMeeting]) {
        let token = try await validAccessToken()
        let allCalendars = try await calendarList(accessToken: token)
        let visibleCalendars = allCalendars.filter { $0.selected != false }
        let calendars = includeSharedCalendars ? visibleCalendars : visibleCalendars.filter(\.isPersonal)
        let hiddenSharedCount = visibleCalendars.count - calendars.count
        var allEvents: [GoogleCalendarEvent] = []
        var allMeetings: [CalendarMeeting] = []

        for calendar in calendars {
            let events = try await events(
                calendarID: calendar.id,
                calendarTitle: calendar.displayTitle,
                interval: interval,
                accessToken: token
            )
            allEvents.append(contentsOf: events)
            allMeetings.append(contentsOf: events.compactMap { $0.meeting(calendarTitle: calendar.displayTitle) })
        }

        let deduped = Dictionary(grouping: allMeetings, by: { $0.id })
            .compactMap { $0.value.first }
            .sorted { $0.startDate < $1.startDate }

        return (
            GoogleCalendarReadSummary(
                calendarCount: calendars.count,
                hiddenSharedCalendarCount: hiddenSharedCount,
                eventCount: allEvents.count,
                meetingCount: deduped.count
            ),
            deduped
        )
    }

    private var clientID: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GoogleCalendarOAuthClientID") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              trimmed.contains(".apps.googleusercontent.com") else { return nil }
        return trimmed
    }

    private var registeredOAuthScheme: String? {
        guard let clientID,
              let scheme = Self.reversedClientIDScheme(clientID) else { return nil }
        return Self.registeredURLSchemes.contains(scheme) ? scheme : nil
    }

    private func openAuthSession(_ url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.authSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: GoogleCalendarError.cancelled)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: GoogleCalendarError.authSessionFailed)
            }
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> StoredGoogleToken {
        guard let callbackScheme = registeredOAuthScheme else { throw GoogleCalendarError.missingURLScheme }
        let response = try await tokenRequest([
            "client_id": clientID ?? "",
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectURI(for: callbackScheme)
        ])

        guard let accessToken = response.accessToken,
              let expiresIn = response.expiresIn else {
            throw GoogleCalendarError.oauth(response.errorDescription ?? response.error ?? "Missing access token")
        }

        return StoredGoogleToken(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            scope: response.scope
        )
    }

    private func refreshToken(_ token: StoredGoogleToken) async throws -> StoredGoogleToken {
        guard let refreshToken = token.refreshToken else { throw GoogleCalendarError.notConnected }
        let response = try await tokenRequest([
            "client_id": clientID ?? "",
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        guard let accessToken = response.accessToken,
              let expiresIn = response.expiresIn else {
            throw GoogleCalendarError.oauth(response.errorDescription ?? response.error ?? "Missing refreshed access token")
        }

        let updated = StoredGoogleToken(
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            scope: response.scope ?? token.scope
        )
        try saveToken(updated)
        return updated
    }

    private func validAccessToken() async throws -> String {
        guard let token = storedToken() else { throw GoogleCalendarError.notConnected }
        if token.expiresAt.timeIntervalSinceNow > 60 {
            return token.accessToken
        }
        return try await refreshToken(token).accessToken
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.badResponse }
        let decoded = try decoder.decode(GoogleTokenResponse.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarError.oauth(decoded.errorDescription ?? decoded.error ?? "HTTP \(http.statusCode)")
        }
        return decoded
    }

    private func calendarList(accessToken: String) async throws -> [GoogleCalendarListItem] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "showHidden", value: "false")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGoogleResponse(response, data: data)
        return try decoder.decode(GoogleCalendarListResponse.self, from: data).items
    }

    private func events(
        calendarID: String,
        calendarTitle: String,
        interval: DateInterval,
        accessToken: String
    ) async throws -> [GoogleCalendarEvent] {
        var pageToken: String?
        var out: [GoogleCalendarEvent] = []

        repeat {
            let encodedID = Self.pathEncoded(calendarID)
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")!
            components.queryItems = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: Self.rfc3339(interval.start)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339(interval.end)),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "timeZone", value: TimeZone.current.identifier)
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateGoogleResponse(response, data: data)
            let page = try decoder.decode(GoogleEventsResponse.self, from: data)
            out.append(contentsOf: page.items.map { event in
                var event = event
                event.calendarTitle = calendarTitle
                return event
            })
            pageToken = page.nextPageToken
        } while pageToken != nil

        return out
    }

    private func validateGoogleResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? decoder.decode(GoogleAPIError.self, from: data).error.message) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.oauth(error)
        }
    }

    private func storedToken() -> StoredGoogleToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.tokenService,
            kSecAttrAccount as String: Self.tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? decoder.decode(StoredGoogleToken.self, from: data)
    }

    private func saveToken(_ token: StoredGoogleToken) throws {
        let data = try encoder.encode(token)
        deleteToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.tokenService,
            kSecAttrAccount as String: Self.tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleCalendarError.keychain(status) }
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.tokenService,
            kSecAttrAccount as String: Self.tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func pathEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func redirectURI(for callbackScheme: String) -> String {
        "\(callbackScheme):/oauth2redirect"
    }

    private static func reversedClientIDScheme(_ clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        return prefix.isEmpty ? nil : "com.googleusercontent.apps.\(prefix)"
    }

    private static var registeredURLSchemes: Set<String> {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }
        let schemes = types.flatMap { type -> [String] in
            type["CFBundleURLSchemes"] as? [String] ?? []
        }
        return Set(schemes)
    }
}

private final class GoogleCalendarPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        guard let scene = scenes.first else {
            fatalError("Google Calendar OAuth requires an active window scene")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}

nonisolated private struct StoredGoogleToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scope: String?
}

nonisolated private struct GoogleTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    let tokenType: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
    }
}

nonisolated private struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListItem]
}

nonisolated private struct GoogleCalendarListItem: Decodable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let primary: Bool?
    let accessRole: String?
    let selected: Bool?

    var displayTitle: String {
        summaryOverride ?? summary ?? "Google Calendar"
    }

    var isPersonal: Bool {
        primary == true || id == "primary" || accessRole == "owner"
    }
}

nonisolated private struct GoogleEventsResponse: Decodable {
    let items: [GoogleCalendarEvent]
    let nextPageToken: String?
}

nonisolated private struct GoogleCalendarEvent: Decodable {
    let id: String?
    let iCalUID: String?
    let status: String?
    let summary: String?
    let location: String?
    let description: String?
    let hangoutLink: String?
    let htmlLink: String?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
    let attendees: [GoogleEventAttendee]?
    let conferenceData: GoogleConferenceData?
    var calendarTitle: String?

    var isDeclinedByUser: Bool {
        attendees?.contains { $0.selfAttendee == true && $0.responseStatus == "declined" } ?? false
    }

    func meeting(calendarTitle: String) -> CalendarMeeting? {
        guard status != "cancelled",
              !isDeclinedByUser,
              !start.isAllDay,
              let startDate = start.resolvedDate,
              let endDate = end.resolvedDate else {
            return nil
        }

        let title = (summary ?? "Untitled meeting").trimmingCharacters(in: .whitespacesAndNewlines)
        let people = (attendees ?? [])
            .filter { $0.selfAttendee != true }
            .compactMap { ($0.displayName ?? $0.email)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("@") }
            .prefix(CalendarContextService.maxAttendees)

        return CalendarMeeting(
            id: "google-\(calendarTitle)-\(id ?? iCalUID ?? title)-\(startDate.timeIntervalSince1970)",
            title: title,
            calendarTitle: calendarTitle,
            startDate: startDate,
            endDate: endDate,
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines),
            attendees: Array(people),
            meetingURL: meetingURL
        )
    }

    private var meetingURL: URL? {
        if let hangoutLink, let url = URL(string: hangoutLink) { return url }
        if let entry = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" || $0.entryPointType == "more" }),
           let uri = entry.uri,
           let url = URL(string: uri) {
            return url
        }
        for text in [location, description, htmlLink].compactMap({ $0 }) {
            if let url = Self.firstURL(in: text) { return url }
        }
        return nil
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }
}

nonisolated private struct GoogleEventDateTime: Decodable {
    let date: String?
    let dateTime: String?

    var isAllDay: Bool {
        dateTime == nil && date != nil
    }

    var resolvedDate: Date? {
        if let dateTime {
            return Self.parseDateTime(dateTime)
        }
        if let date {
            return Self.parseDateOnly(date)
        }
        return nil
    }

    private static func parseDateTime(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        return formatter.date(from: value)
    }
}

nonisolated private struct GoogleEventAttendee: Decodable {
    let email: String?
    let displayName: String?
    let responseStatus: String?
    let selfAttendee: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case responseStatus
        case selfAttendee = "self"
    }
}

nonisolated private struct GoogleConferenceData: Decodable {
    let entryPoints: [GoogleConferenceEntryPoint]?
}

nonisolated private struct GoogleConferenceEntryPoint: Decodable {
    let entryPointType: String?
    let uri: String?
}

nonisolated private struct GoogleAPIError: Decodable {
    let error: GoogleAPIErrorBody
}

nonisolated private struct GoogleAPIErrorBody: Decodable {
    let message: String
}

enum GoogleCalendarError: LocalizedError {
    case missingClientID
    case badAuthURL
    case cancelled
    case authSessionFailed
    case stateMismatch
    case missingCode
    case missingURLScheme
    case notConnected
    case badResponse
    case oauth(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google Calendar is not configured in this build."
        case .badAuthURL:
            return "Could not create the Google sign-in URL."
        case .cancelled:
            return "Google sign-in was cancelled."
        case .authSessionFailed:
            return "Could not open Google sign-in."
        case .stateMismatch:
            return "Google sign-in returned an invalid state."
        case .missingCode:
            return "Google did not return an authorization code."
        case .missingURLScheme:
            return "Google Calendar needs the OAuth URL scheme in this build."
        case .notConnected:
            return "Google Calendar is not connected."
        case .badResponse:
            return "Google Calendar returned an invalid response."
        case .oauth(let message):
            return message
        case .keychain(let status):
            return "Could not save Google Calendar token (\(status))."
        }
    }
}
