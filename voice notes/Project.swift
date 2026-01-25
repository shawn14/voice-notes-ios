//
//  Project.swift
//  voice notes
//
//  Top-level container: a venture, product, or initiative
//  User-created, stable, emotionally meaningful
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "folder"  // SF Symbol name
    var colorName: String = "blue"  // For visual distinction
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var sortOrder: Int = 0

    // Aliases for matching (stored as JSON array)
    var aliasesData: Data = Data()

    init(name: String, icon: String = "folder", colorName: String = "blue") {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isArchived = false
        self.sortOrder = 0
        self.aliasesData = Data()

        // Auto-generate initial aliases from name
        var initial: [String] = []
        initial.append(name.lowercased())
        initial.append(name.lowercased().replacingOccurrences(of: " ", with: ""))

        // Add acronym if multi-word
        let words = name.split(separator: " ")
        if words.count > 1 {
            let acronym = words.map { String($0.prefix(1)) }.joined().lowercased()
            initial.append(acronym)
        }

        self.aliases = initial
    }

    var color: String { colorName }

    // MARK: - Aliases

    var aliases: [String] {
        get {
            guard !aliasesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: aliasesData)) ?? []
        }
        set {
            aliasesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Add a new alias (normalized, deduplicated)
    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var current = aliases
        if !current.contains(normalized) {
            current.append(normalized)
            aliases = current
            updatedAt = Date()
        }
    }

    /// Check if text matches any alias
    func matches(text: String) -> Bool {
        let normalized = text.lowercased()
        return aliases.contains { alias in
            normalized.contains(alias)
        }
    }
}
