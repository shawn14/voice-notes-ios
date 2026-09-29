import Foundation
import CloudKit

/// Settings → "AI agents". One switch connects this phone to the EEON
/// connector; agents (Claude Code, Codex, Cursor, claude.ai) then sign in with
/// just the URL and the user approves each one here by QR or short code.
///
/// Why this shape (2026-09-29): the old flow made the user sign in to Apple in
/// a web sheet and then carry a long secret token to every computer. The
/// mirror (`AgentMirrorService`) carries the notes, so no Apple web sign-in is
/// needed, and OAuth pairing means no token is ever copied by hand.
@Observable
final class AIAccessService {
    static let shared = AIAccessService()

    /// The one URL every agent adds. No token in it.
    static let mcpURL = "https://www.eeon.com/api/mcp"

    private let defaults = UserDefaults.standard
    private let tokenKey = "aiAccessConnectorToken"
    private let cloudKitAPITokenKey = "EEONCloudKitAPIToken"

    var isConnecting = false
    var lastError: String?

    /// A pairing code opened from the camera QR (`voicenotes://pair?code=`)
    /// or typed in; the root view presents the approval sheet for it.
    var pendingPairCode: String?

    // Stored (not computed over UserDefaults) so @Observable tracks it.
    // Computed reads were invisible to SwiftUI: Disconnect changed the token
    // but the screen never redrew (Shawn, 2026-09-29).
    private(set) var connectorToken: String?
    var isConnected: Bool { connectorToken?.isEmpty == false }
    var mcpURL: String { Self.mcpURL }

    private init() {
        connectorToken = defaults.string(forKey: tokenKey)
    }

    // MARK: - Connect / disconnect

    /// One tap: create this phone's connection and upload notes for agents.
    @MainActor
    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        lastError = nil
        defer { isConnecting = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request(path: "/api/connect/device", method: "POST"))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let token = (try? JSONDecoder().decode(DeviceConnection.self, from: data))?.token,
                  !token.isEmpty else {
                lastError = serverMessage(data) ?? "Couldn't turn on AI agents. Check your connection and try again."
                return
            }
            defaults.set(token, forKey: tokenKey)
            connectorToken = token
            AgentMirrorService.shared.clearHashes()
            await AgentMirrorService.shared.syncNow()
            await AgentMirrorService.shared.refreshStatus()
        } catch {
            lastError = "Couldn't turn on AI agents. Check your connection and try again."
        }
    }

    /// Revoke server-side (deletes the note copy and every approved agent)
    /// and forget locally.
    @MainActor
    func disconnect() async {
        if let token = connectorToken {
            var revoke = request(path: "/api/connect/revoke", method: "POST")
            revoke.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            revoke.httpBody = "token=\(token)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: revoke)
        }
        defaults.removeObject(forKey: tokenKey)
        connectorToken = nil
        AgentMirrorService.shared.clearHashes()
        await AgentMirrorService.shared.refreshStatus()
    }

    // MARK: - Pairing (approve an agent)

    /// Which agent is asking for this code, or a readable error.
    func pairingClientName(code: String) async -> Result<String, PairingError> {
        guard var components = URLComponents(string: "https://www.eeon.com/api/pair") else { return .failure(.message("Invalid code.")) }
        components.queryItems = [URLQueryItem(name: "code", value: Self.normalize(code))]
        guard let url = components.url else { return .failure(.message("Invalid code.")) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let name = (try? JSONDecoder().decode(PairInfo.self, from: data))?.clientName {
                return .success(name)
            }
            return .failure(.message(serverMessage(data) ?? "That code didn't work. Start again on your computer."))
        } catch {
            return .failure(.message("Couldn't reach EEON. Check your connection."))
        }
    }

    /// Approve (or refuse) the agent. Turns AI agents on first if needed.
    @MainActor
    func decidePairing(code: String, approve: Bool) async -> Result<Void, PairingError> {
        if approve && !isConnected { await connect() }
        guard let token = connectorToken else {
            return .failure(.message(lastError ?? "Turn on AI agents first."))
        }
        var req = request(path: "/api/pair", method: "POST", token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(PairDecision(code: Self.normalize(code), approve: approve))
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                await AgentMirrorService.shared.refreshStatus()
                return .success(())
            }
            return .failure(.message(serverMessage(data) ?? "That code didn't work. Start again on your computer."))
        } catch {
            return .failure(.message("Couldn't reach EEON. Check your connection."))
        }
    }

    static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Setup text (no tokens anywhere)

    var claudeCommand: String { "claude mcp add --transport http eeon \(mcpURL)" }
    var codexCommand: String { "codex mcp add eeon --url \(mcpURL)\ncodex mcp login eeon" }

    // MARK: - Orders (dormant AI-order recorder; see CLAUDE.md)

    func enqueueOrder(
        id: UUID,
        title: String,
        instructions: String,
        createdAt: Date,
        project: String?
    ) async {
        guard let token = connectorToken else { return }
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstructions.isEmpty else { return }
        do {
            try await send(
                url: URL(string: "https://www.eeon.com/api/orders")!,
                method: "POST",
                token: token,
                body: OrderMirrorPayload(
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

    /// Legacy connections made with the old Apple web sign-in can still read
    /// live CloudKit; keep their token fresh when this build carries the API
    /// token. The mirror makes this optional for reads.
    @discardableResult
    func refreshCloudKitAccessIfPossible() async -> Bool {
        guard let token = connectorToken else { return false }
        guard let apiToken = cloudKitAPIToken,
              let url = endpoint(path: "/api/connect/refresh") else {
            // Debug installs carry the unresolved $(EEON_CLOUDKIT_API_TOKEN)
            // placeholder. The agent mirror covers reads either way.
            print("[AIAccess] CloudKit refresh skipped: no EEONCloudKitAPIToken in this build")
            return false
        }
        do {
            let webAuthToken = try await fetchWebAuthToken(apiToken: apiToken)
            try await send(
                url: url,
                method: "POST",
                token: token,
                body: CloudKitRefreshPayload(ckWebAuthToken: webAuthToken, environment: "production")
            )
            return true
        } catch {
            // Device connections have no CloudKit token to refresh; the mirror
            // serves their reads, so this is expected and not user-facing.
            print("[AIAccess] CloudKit refresh failed: \(error)")
            return false
        }
    }

    // MARK: - HTTP

    func endpoint(path: String) -> URL? {
        URL(string: "https://www.eeon.com\(path)")
    }

    private func request(path: String, method: String, token: String? = nil) -> URLRequest {
        var req = URLRequest(url: endpoint(path: path)!)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    /// Authenticated JSON request to an EEON connector endpoint.
    func send<T: Encodable>(url: URL, method: String, token: String, body: T?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func serverMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ServerError.self, from: data))?.error
    }

    private var cloudKitAPIToken: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: cloudKitAPITokenKey) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
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

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum PairingError: Error {
    case message(String)

    var text: String {
        switch self { case .message(let text): return text }
    }
}

private struct DeviceConnection: Decodable { let token: String }
private struct PairInfo: Decodable { let clientName: String }
private struct PairDecision: Encodable { let code: String; let approve: Bool }
private struct ServerError: Decodable { let error: String }

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
