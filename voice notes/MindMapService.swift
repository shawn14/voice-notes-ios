//
//  MindMapService.swift
//  voice notes
//
//  Per-note mind map (2026-09-25): one recording as a topic tree, the
//  presentation Pocket ships as "dynamic mind maps". The knowledge-base
//  Memory Map (KnowledgeOverviewView) spans all notes; this is one note.
//
//  One gpt-4o-mini JSON call. The result is cached as a file keyed by note
//  id + a hash of the note text, NOT as a SwiftData field: a new stored
//  field is a CloudKit schema change with a Production deploy gate, and a
//  mind map is cheap to regenerate on another device.
//

import Foundation
import CryptoKit

nonisolated struct NoteMindMapNode: Codable, Hashable, Identifiable {
    var title: String
    var children: [NoteMindMapNode]

    var id: String { title + "\(children.count)" }

    init(title: String, children: [NoteMindMapNode] = []) {
        self.title = title
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        children = try c.decodeIfPresent([NoteMindMapNode].self, forKey: .children) ?? []
    }
}

nonisolated enum MindMapService {
    enum MindMapError: LocalizedError {
        case tooShort, api(String), unreadable
        var errorDescription: String? {
            switch self {
            case .tooShort: return "This note is too short for a mind map."
            case .api(let message): return message
            case .unreadable: return "Couldn't build a mind map for this note. Try again."
            }
        }
    }

    static let maxBranches = 6
    static let maxLeaves = 5
    /// ~6k words; longer notes are trimmed from the middle (start and end
    /// carry the framing and the conclusions).
    static let maxCharacters = 36_000

    // MARK: Cache

    static func cacheKey(noteID: UUID, text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(noteID.uuidString)-\(digest)"
    }

    private static var cacheDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mind-maps", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cached(noteID: UUID, text: String) -> NoteMindMapNode? {
        let url = cacheDirectory.appendingPathComponent(cacheKey(noteID: noteID, text: text) + ".json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(NoteMindMapNode.self, from: $0) }
    }

    private static func store(_ map: NoteMindMapNode, noteID: UUID, text: String) {
        // One file per note: drop maps of older versions of the text.
        let prefix = noteID.uuidString
        let old = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in old where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
        let url = cacheDirectory.appendingPathComponent(cacheKey(noteID: noteID, text: text) + ".json")
        try? JSONEncoder().encode(map).write(to: url, options: .atomic)
    }

    // MARK: Generate

    static func mindMap(noteID: UUID, text: String, apiKey: String, forceRefresh: Bool = false) async throws -> NoteMindMapNode {
        if !forceRefresh, let hit = cached(noteID: noteID, text: text) { return hit }
        let map = try await generate(text: text, apiKey: apiKey)
        store(map, noteID: noteID, text: text)
        return map
    }

    static func generate(text: String, apiKey: String) async throws -> NoteMindMapNode {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.split(whereSeparator: \.isWhitespace).count >= 20 else { throw MindMapError.tooShort }
        let input: String
        if trimmed.count > maxCharacters {
            let half = maxCharacters / 2
            input = String(trimmed.prefix(half)) + "\n…\n" + String(trimmed.suffix(half))
        } else {
            input = trimmed
        }

        let prompt = """
        Turn this voice note into a mind map someone could read INSTEAD of the note.

        Return JSON: {"title": string, "children": [{"title": string, "children": [{"title": string}]}]}
        - Root title: the note's subject in 2–5 words.
        - 3–\(maxBranches) branches: the main themes, in the order they came up. 1–4 words each.
        - Under each branch, 1–\(maxLeaves) leaves. Every leaf states the actual content: the decision,
          number, date, name, owner or next step. Up to 10 words, a phrase, not a sentence.
          Example (from an unrelated note about a kitchen remodel):
            good "Contractor starts March 3, not Feb 20"   bad "Start date"
            good "Dana picks tile samples by Tuesday"       bad "Dana's task"
          A leaf that could apply to any note is wrong: it must contain a specific word, name or
          number from THIS note. Keep qualifiers ("almost no", "about") exactly as said.
        - Use only what is in the note. Never invent details. Keep names and numbers exactly as said.
        - No leaf repeats its branch title.

        Note:
        \(input)
        """
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": prompt]],
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "max_tokens": 900,
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw MindMapError.api(message ?? "Couldn't build a mind map. Try again.")
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = ((envelope["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        else { throw MindMapError.unreadable }
        return try parse(content)
    }

    /// Decode and clamp the model's JSON to the shape the view can draw.
    static func parse(_ content: String) throws -> NoteMindMapNode {
        guard let data = content.data(using: .utf8),
              var root = try? JSONDecoder().decode(NoteMindMapNode.self, from: data) else {
            throw MindMapError.unreadable
        }
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        root.title = clean(root.title)
        root.children = root.children.prefix(maxBranches).compactMap { branch in
            let title = clean(branch.title)
            guard !title.isEmpty else { return nil }
            let leaves = branch.children.map { clean($0.title) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(title) != .orderedSame }
                .prefix(maxLeaves)
                .map { NoteMindMapNode(title: $0) }
            return NoteMindMapNode(title: title, children: Array(leaves))
        }
        guard !root.title.isEmpty, !root.children.isEmpty else { throw MindMapError.unreadable }
        return root
    }
}
