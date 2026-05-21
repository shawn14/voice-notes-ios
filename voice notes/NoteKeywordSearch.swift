//
//  NoteKeywordSearch.swift
//  voice notes
//
//  Pure, stateless keyword search over notes. No UI, no SwiftData container
//  dependency — given a query and a list of notes, returns ranked matches.
//

import Foundation

enum NoteKeywordSearch {

    /// Returns the notes matching `query`, ranked.
    ///
    /// Matching: the query is split into whitespace-separated terms; a note
    /// matches when EVERY term appears (case- and diacritic-insensitive
    /// substring, via `localizedStandardContains`) somewhere in its combined
    /// searchable text — title + content + transcript + enhancedNoteText.
    ///
    /// An empty or whitespace-only query returns `[]` (search is inactive).
    ///
    /// Ranking: notes whose `title` contains any term sort first; ties break
    /// by `updatedAt` descending (most recently updated first).
    static func match(query: String, in notes: [Note]) -> [Note] {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        let matches = notes.filter { note in
            let haystack = searchableText(for: note)
            return terms.allSatisfy { haystack.localizedStandardContains($0) }
        }

        return matches.sorted { lhs, rhs in
            let lhsTitle = titleMatches(lhs, terms: terms)
            let rhsTitle = titleMatches(rhs, terms: terms)
            if lhsTitle != rhsTitle { return lhsTitle }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// The combined text a query is matched against for one note.
    private static func searchableText(for note: Note) -> String {
        [
            note.title,
            note.content,
            note.transcript ?? "",
            note.enhancedNoteText ?? ""
        ].joined(separator: " ")
    }

    /// True when any query term appears in the note's title.
    private static func titleMatches(_ note: Note, terms: [String]) -> Bool {
        terms.contains { note.title.localizedStandardContains($0) }
    }
}
