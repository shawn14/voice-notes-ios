//
//  PersonaChipsView.swift
//  voice notes
//
//  Karpathy persona-driven extraction chips. Renders Note.personaExtractions
//  grouped by category, with category icon/label pulled from the .purpose article's
//  compiled schema. Tolerates unknown category keys so schema regenerations
//  don't orphan old data — stale-key items render with a generic tag icon.
//

import SwiftUI
import SwiftData

struct PersonaChipsView: View {
    let note: Note

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "purpose" })
    private var purposeArticles: [KnowledgeArticle]

    private var schema: PersonaExtractionSchema? {
        purposeArticles.first?.noteExtractionSchema
    }

    private var groupedItems: [(category: String, label: String, icon: String, items: [PersonaExtractionItem])] {
        let items = note.personaExtractions
        guard !items.isEmpty else { return [] }

        // Preserve schema's declared order; orphan keys append at the end.
        var seenKeys: Set<String> = []
        var result: [(String, String, String, [PersonaExtractionItem])] = []

        if let schema {
            for category in schema.categories {
                let matching = items.filter { $0.category == category.key }
                guard !matching.isEmpty else { continue }
                seenKeys.insert(category.key)
                result.append((category.key, category.label, category.icon, matching))
            }
        }

        // Orphan items — categories that don't appear in current schema (regen drift).
        let orphanKeys = Set(items.map(\.category)).subtracting(seenKeys)
        for orphanKey in orphanKeys.sorted() {
            let matching = items.filter { $0.category == orphanKey }
            result.append((orphanKey, prettifyKey(orphanKey), "tag", matching))
        }

        return result
    }

    var body: some View {
        if !groupedItems.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groupedItems, id: \.category) { group in
                    categorySection(label: group.label, icon: group.icon, items: group.items)
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(label: String, icon: String, items: [PersonaExtractionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.eeonAccent)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .textCase(.uppercase)
            }

            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    chip(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(item: PersonaExtractionItem) -> some View {
        Text(item.content)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.eeonTextPrimary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.eeonAccent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.eeonAccent.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// "businesses_touched" → "Businesses Touched"
    private func prettifyKey(_ key: String) -> String {
        key.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
