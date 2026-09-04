import Foundation
import AuthenticationServices
import CloudKit

/// In-app "Set up AI access": runs the EEON connect flow inside an
/// ASWebAuthenticationSession (same pattern as Google Calendar), captures the
/// connector token the web callback returns via `voicenotes://ai-access`, and
/// keeps it so Settings can show the user their connector URL + token to add
/// to Claude / ChatGPT / Cursor. Read-only; the token is revocable.
@Observable
final class AIAccessService: NSObject {
    static let shared = AIAccessService()

    private let defaults = UserDefaults.standard
    private let tokenKey = "aiAccessConnectorToken"
    private let urlKey = "aiAccessMCPURL"
    private let cloudKitAPITokenKey = "EEONCloudKitAPIToken"

    private var authSession: ASWebAuthenticationSession?
    private let contextProvider = AIAccessPresentationContextProvider()

    /// The URL the connect flow lives at. `?app=1` makes the callback return
    /// into the app via the voicenotes:// scheme instead of the web page.
    private let startURL = URL(string: "https://www.eeon.com/api/connect/start?app=1")!
    private let callbackScheme = "voicenotes"

    var isConnecting = false
    var lastError: String?

    private override init() { super.init() }

    var connectorToken: String? { defaults.string(forKey: tokenKey) }
    var mcpURL: String { defaults.string(forKey: urlKey) ?? "https://www.eeon.com/api/mcp" }
    var isConnected: Bool { connectorToken?.isEmpty == false }

    /// A ready-to-paste Claude Code command for the current connector.
    var claudeCommand: String? {
        guard let token = connectorToken else { return nil }
        return "claude mcp add --transport http eeon \(mcpURL) --header \"Authorization: Bearer \(token)\""
    }

    @MainActor
    func connect() async {
        isConnecting = true
        lastError = nil
        defer { isConnecting = false }
        do {
            let callback = try await openAuthSession(startURL)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                lastError = readableError(error)
                return
            }
            guard let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
                lastError = "Sign-in finished but no connector was returned. Please try again."
                return
            }
            let url = items.first(where: { $0.name == "url" })?.value ?? mcpURL
            defaults.set(token, forKey: tokenKey)
            defaults.set(url, forKey: urlKey)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the sheet — not an error worth surfacing.
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Revoke server-side (best effort) and forget locally.
    func disconnect() {
        if let token = connectorToken,
           let revoke = URL(string: "https://www.eeon.com/api/connect/revoke") {
            var req = URLRequest(url: revoke)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "token=\(token)".data(using: .utf8)
            URLSession.shared.dataTask(with: req).resume()
        }
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: urlKey)
    }

    func enqueueOrder(
        id: UUID,
        title: String,
        instructions: String,
        createdAt: Date,
        project: String?
    ) async {
        guard let token = connectorToken,
              let url = endpoint(path: "/api/orders") else { return }
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstructions.isEmpty else { return }

        do {
            try await postJSON(
                url: url,
                token: token,
                payload: OrderMirrorPayload(
                    id: id.uuidString,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    instructions: trimmedInstructions,
                    date: Self.iso8601.string(from: createdAt),
                    project: project,
                    recordName: nil
                )
            )
        } catch {
            lastError = "Could not queue this AI order. It is still saved in EEON."
        }
    }

    @discardableResult
    func refreshCloudKitAccessIfPossible() async -> Bool {
        guard let token = connectorToken,
              let apiToken = cloudKitAPIToken,
              let url = endpoint(path: "/api/connect/refresh") else { return false }
        do {
            let webAuthToken = try await fetchWebAuthToken(apiToken: apiToken)
            try await postJSON(
                url: url,
                token: token,
                payload: CloudKitRefreshPayload(
                    ckWebAuthToken: webAuthToken,
                    environment: "production"
                )
            )
            return true
        } catch {
            lastError = "AI memory access needs reconnecting."
            return false
        }
    }

    private func readableError(_ code: String) -> String {
        switch code {
        case "read_failed":
            return "Signed in, but couldn't read your notes. Make sure iCloud is on for the same Apple Account."
        case "no_token":
            return "Sign-in didn't complete. Please try again."
        default:
            return code
        }
    }

    private func openAuthSession(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.authSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.presentationContextProvider = contextProvider
            // Clean session each time. A shared Safari session can carry stale
            // Apple sign-in state that makes CloudKit report "session has timed
            // out"; ephemeral avoids that at the cost of a full sign-in.
            session.prefersEphemeralWebBrowserSession = true
            authSession = session
            if !session.start() {
                continuation.resume(throwing: ASWebAuthenticationSessionError(.presentationContextInvalid))
            }
        }
    }

    private var cloudKitAPIToken: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: cloudKitAPITokenKey) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private func endpoint(path: String) -> URL? {
        guard var components = URLComponents(string: mcpURL) else { return nil }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func fetchWebAuthToken(apiToken: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchWebAuthTokenOperation(apiToken: apiToken)
            operation.fetchWebAuthTokenResultBlock = { result in
                continuation.resume(with: result)
            }
            operation.qualityOfService = .utility
            CKContainer(identifier: "iCloud.aivoiceeeon").privateCloudDatabase.add(operation)
        }
    }

    private func postJSON<T: Encodable>(url: URL, token: String, payload: T) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct OrderMirrorPayload: Encodable {
    let id: String
    let title: String
    let instructions: String
    let date: String
    let project: String?
    let recordName: String?
}

private struct CloudKitRefreshPayload: Encodable {
    let ckWebAuthToken: String
    let environment: String
}

private final class AIAccessPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        guard let scene = scenes.first else {
            fatalError("AI access setup requires an active window scene")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}
