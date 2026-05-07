//
//  FocusItem.swift
//  voice notes
//
//  Structured user-declared priority item — lives on the .purpose KnowledgeArticle
//  as a JSON-encoded list. Read by ContextAssembler (for prompt injection) and
//  MomentumPictureSection (for activity computation).
//

import Foundation

enum FocusWeight: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
    case tertiary

    var label: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .tertiary: return "Tertiary"
        }
    }
}

struct FocusItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var content: String
    var weight: FocusWeight
    var note: String?

    init(id: UUID = UUID(), content: String, weight: FocusWeight, note: String? = nil) {
        self.id = id
        self.content = content
        self.weight = weight
        self.note = note
    }
}

extension Array where Element == FocusItem {
    /// JSON-encode for persistence on KnowledgeArticle.focusItemsJSON
    var encodedJSON: String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Decode from JSON string. Returns [] on any parse failure.
    static func decode(from json: String?) -> [FocusItem] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([FocusItem].self, from: data)) ?? []
    }
}
