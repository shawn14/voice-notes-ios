import Foundation
import SwiftData
import CryptoKit

/// Keeps the opt-in agent mirror current, so Claude Code / Codex / Cursor can
/// read the user's notes through the EEON connector even when Apple's
/// short-lived CloudKit web token has lapsed (decision 2026-09-29: option B).
///
/// Each note and knowledge article is sent with its CloudKit field names
/// (`CD_title`, `CD_enhancedNoteText`, ...). The server maps them with the same
/// code it uses for live CloudKit reads, so agents see identical markdown.
///
/// Only changed documents are uploaded: a SHA-256 of each payload is kept
/// locally, and a document goes up when its hash differs. Documents that
/// vanished locally are deleted server-side. Audio never leaves the phone.
@Observable
final class AgentMirrorService {
    static let shared = AgentMirrorService()

    /// Set once at launch so saves anywhere in the app can trigger a sync.
    var container: ModelContainer? {
        didSet { observeSavesIfNeeded() }
    }

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var status: AgentAccessStatus?

    private let defaults = UserDefaults.standard
    private let enabledKey = "agentMirrorEnabled"
    private let batchSize = 50
    private var saveObserver: NSObjectProtocol?
    private var pendingSync: Task<Void, Never>?

    private init() {}

    /// On by default when the user connects; they can switch it off on the
    /// AI agents screen, which deletes the server copy.
    var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    // MARK: - Triggers

    private func observeSavesIfNeeded() {
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleSync()
        }
    }

    /// Debounced: note capture saves several times in a row (title, AI
    /// enhancement, extraction), so wait for it to settle.
    func scheduleSync(after seconds: Double = 8) {
        pendingSync?.cancel()
        pendingSync = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    // MARK: - Sync

    @MainActor
    @discardableResult
    func syncNow() async -> Bool {
        guard isEnabled,
              !isSyncing,
              let token = AIAccessService.shared.connectorToken,
              let container,
              let url = AIAccessService.shared.endpoint(path: "/api/mirror") else { return false }

        isSyncing = true
        defer { isSyncing = false }

        let docs = buildDocuments(context: container.mainContext)
        var known = loadHashes(for: token)
        let firstSync = known.isEmpty

        var changed: [MirrorDocument] = []
        var hashes: [String: String] = [:]
        for doc in docs {
            let hash = doc.contentHash
            hashes[doc.key] = hash
            if known[doc.key] != hash { changed.append(doc) }
        }
        let deleted = known.keys.filter { hashes[$0] == nil }

        if changed.isEmpty && deleted.isEmpty && !firstSync {
            lastError = nil
            return true
        }

        do {
            let batches = stride(from: 0, to: max(changed.count, 1), by: batchSize).map {
                Array(changed[$0..<min($0 + batchSize, changed.count)])
            }
            for (index, batch) in batches.enumerated() {
                let isLast = index == batches.count - 1
                let body = MirrorSyncBody(
                    upserts: batch,
                    deletes: isLast ? Array(deleted) : nil,
                    // First sync after connect: clear anything the server holds
                    // that this phone does not (e.g. a previous device's copy).
                    keepOnly: isLast && firstSync ? Array(hashes.keys) : nil
                )
                try await AIAccessService.shared.send(url: url, method: "POST", token: token, body: body)
                for doc in batch { known[doc.key] = doc.contentHash }
                saveHashes(known, for: token)
            }
            for key in deleted { known.removeValue(forKey: key) }
            saveHashes(known, for: token)
            lastError = nil
            print("[AgentMirror] synced \(changed.count) changed, \(deleted.count) deleted, \(docs.count) total")
            await refreshStatus()
            return true
        } catch {
            lastError = "Couldn't update your notes for AI agents. Will retry."
            print("[AgentMirror] sync failed: \(error)")
            return false
        }
    }

    /// Turn the mirror off: delete the server copy and forget local hashes.
    @MainActor
    func disable() async {
        isEnabled = false
        guard let token = AIAccessService.shared.connectorToken,
              let url = AIAccessService.shared.endpoint(path: "/api/mirror") else { return }
        try? await AIAccessService.shared.send(url: url, method: "DELETE", token: token, body: Optional<MirrorSyncBody>.none)
        clearHashes()
        await refreshStatus()
    }

    @MainActor
    func enable() async {
        isEnabled = true
        clearHashes()
        await syncNow()
    }

    /// Server-reported state: what an agent would actually see right now.
    @MainActor
    func refreshStatus() async {
        guard let token = AIAccessService.shared.connectorToken,
              let url = AIAccessService.shared.endpoint(path: "/api/connect/status") else {
            status = nil
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 401 {
                status = AgentAccessStatus(state: .notConnected)
                return
            }
            status = try JSONDecoder.agentStatus.decode(AgentAccessStatus.self, from: data)
            // Server lost its copy (or never got one) while we think it is
            // current: forget the hashes so the next sync re-uploads.
            if isEnabled, status?.state == .proxyOnly || ((status?.notes ?? 0) + (status?.articles ?? 0) == 0 && !loadHashes(for: token).isEmpty) {
                clearHashes()
                scheduleSync(after: 1)
            }
        } catch {
            // Network hiccup: keep the last known status rather than flashing red.
            print("[AgentMirror] status failed: \(error)")
        }
    }

    // MARK: - Payloads

    @MainActor
    private func buildDocuments(context: ModelContext) -> [MirrorDocument] {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let articles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projectNames = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        var docs: [MirrorDocument] = []
        for note in notes where !note.isArchived {
            let id = note.id.uuidString
            var fields: [String: MirrorValue] = [
                "CD_id": .string(id),
                "CD_title": .string(note.title),
                "CD_content": .string(note.content),
                "CD_createdAt": .date(note.createdAt),
                "CD_updatedAt": .date(note.updatedAt),
                "CD_intentType": .string(note.intentType),
                "CD_sourceTypeRaw": .string(note.sourceTypeRaw)
            ]
            fields["CD_transcript"] = note.transcript.map(MirrorValue.string)
            fields["CD_enhancedNoteText"] = note.enhancedNoteText.map(MirrorValue.string)
            // A named project is what agents search for ("my note about X").
            let project = note.projectId.flatMap { projectNames[$0] }.flatMap { $0.isEmpty ? nil : $0 }
                ?? note.inferredProjectName
            fields["CD_inferredProjectName"] = project.map(MirrorValue.string)
            fields["CD_mentionedPeopleJSON"] = note.mentionedPeopleJSON.map(MirrorValue.string)
            fields["CD_topicsJSON"] = note.topicsJSON.map(MirrorValue.string)
            fields["CD_emotionalTone"] = note.emotionalTone.map(MirrorValue.string)
            fields["CD_summaryFormat"] = note.summaryFormat.map(MirrorValue.string)
            fields["CD_calendarContextJSON"] = note.calendarContextJSON.map(MirrorValue.string)
            fields["CD_speakerLabelsJSON"] = note.speakerLabelsJSON.map(MirrorValue.string)
            docs.append(MirrorDocument(recordType: "CD_Note", id: id, fields: fields))
        }

        for article in articles where !article.name.isEmpty {
            let id = article.id.uuidString
            var fields: [String: MirrorValue] = [
                "CD_id": .string(id),
                "CD_name": .string(article.name),
                "CD_articleTypeRaw": .string(article.articleTypeRaw),
                "CD_createdAt": .date(article.createdAt),
                "CD_updatedAt": .date(article.updatedAt),
                "CD_mentionCount": .int(article.mentionCount),
                "CD_summary": .string(article.summary)
            ]
            fields["CD_lastCompiledAt"] = article.lastCompiledAt.map(MirrorValue.date)
            fields["CD_lastMentionedAt"] = article.lastMentionedAt.map(MirrorValue.date)
            fields["CD_aliasesJSON"] = article.aliasesJSON.map(MirrorValue.string)
            fields["CD_linkedNoteIdsJSON"] = article.linkedNoteIdsJSON.map(MirrorValue.string)
            fields["CD_openThreadsJSON"] = article.openThreadsJSON.map(MirrorValue.string)
            fields["CD_timelineJSON"] = article.timelineJSON.map(MirrorValue.string)
            fields["CD_connectionsJSON"] = article.connectionsJSON.map(MirrorValue.string)
            fields["CD_decisionsJSON"] = article.decisionsJSON.map(MirrorValue.string)
            fields["CD_relationshipContext"] = article.relationshipContext.map(MirrorValue.string)
            fields["CD_thinkingEvolution"] = article.thinkingEvolution.map(MirrorValue.string)
            fields["CD_sentimentArc"] = article.sentimentArc.map(MirrorValue.string)
            docs.append(MirrorDocument(recordType: "CD_KnowledgeArticle", id: id, fields: fields))
        }
        return docs
    }

    // MARK: - Hash store (Application Support, per connection)

    private var hashesURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("agent-mirror-hashes.json")
    }

    private func loadHashes(for token: String) -> [String: String] {
        guard let url = hashesURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredHashes.self, from: data),
              stored.connection == Self.fingerprint(token) else { return [:] }
        return stored.hashes
    }

    private func saveHashes(_ hashes: [String: String], for token: String) {
        guard let url = hashesURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = StoredHashes(connection: Self.fingerprint(token), hashes: hashes)
        try? JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }

    func clearHashes() {
        guard let url = hashesURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Never store the connector token itself in the hash file.
    private static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Wire types

struct AgentAccessStatus: Decodable, Equatable {
    enum State: String, Decodable {
        case ready, syncing
        case proxyOnly = "proxy_only"
        case notConnected = "not_connected"
    }

    var state: State
    var notes: Int = 0
    var articles: Int = 0
    var lastSyncAt: Date?
    var lastAgentReadAt: Date?

    init(state: State) { self.state = state }
}

private extension JSONDecoder {
    static let agentStatus: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()
}

private struct StoredHashes: Codable {
    let connection: String
    let hashes: [String: String]
}

enum MirrorValue: Encodable, Equatable {
    case string(String)
    case int(Int)
    /// CloudKit TIMESTAMP: milliseconds since 1970, which the server mapper reads.
    case date(Date)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .date(let value): try container.encode((value.timeIntervalSince1970 * 1000).rounded())
        }
    }
}

struct MirrorDocument: Encodable {
    let recordType: String
    let id: String
    let fields: [String: MirrorValue]

    var key: String { "\(recordType == "CD_Note" ? "note" : "article"):\(id)" }

    var contentHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct MirrorSyncBody: Encodable {
    let upserts: [MirrorDocument]
    let deletes: [String]?
    let keepOnly: [String]?
}
