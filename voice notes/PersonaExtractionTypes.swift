//
//  PersonaExtractionTypes.swift
//  voice notes
//
//  Karpathy-pattern persona-driven extraction. The .purpose KnowledgeArticle
//  compiles a PersonaExtractionSchema (parallel to homeLayoutJSON); each note
//  saved by a tuned user accrues PersonaExtractionItems alongside the permanent
//  baseline extraction (decisions/actions/commitments/etc., never replaced).
//

import Foundation

/// One item extracted from a note via the user's persona schema.
/// Persisted as JSON on `Note.personaExtractionsJSON`.
struct PersonaExtractionItem: Codable, Identifiable, Equatable {
    /// Stable id for SwiftUI ForEach — not persisted independently of the note.
    var id: String { "\(category)-\(content)" }

    /// Category key from the schema (e.g. "businesses_touched", "symbols").
    let category: String

    /// The extracted text the LLM pulled from the note.
    let content: String

    /// Optional structured metadata the LLM may surface (confidence, owner, etc.).
    let metadata: [String: String]?
}

/// The Karpathy-LLM-compiled extraction schema for a tuned user.
/// Persisted as JSON on `KnowledgeArticle.noteExtractionSchemaJSON` (only on `.purpose`).
struct PersonaExtractionSchema: Codable, Equatable {
    struct Category: Codable, Identifiable, Equatable {
        var id: String { key }

        /// Stable key matched in `PersonaExtractionItem.category`.
        let key: String

        /// Human-readable label (e.g. "Businesses", "Symbols").
        let label: String

        /// SF Symbols name.
        let icon: String

        /// Second-person description shown in Tune.
        let description: String
    }

    let version: Int
    let categories: [Category]
    /// Free-form sentence injected into the persona-extraction system prompt
    /// to bias the LLM toward the user's lens.
    let extractionPromptFragment: String

    /// Lookup category by key. Renderers tolerate unknown keys so schema
    /// regenerations don't orphan old `Note.personaExtractionsJSON` data.
    func category(for key: String) -> Category? {
        categories.first { $0.key == key }
    }
}
