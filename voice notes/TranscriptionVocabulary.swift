//
//  TranscriptionVocabulary.swift
//  voice notes
//
//  Custom vocabulary for Whisper. The transcription endpoint accepts a `prompt`
//  field — free text it treats as preceding context — and spells the names and
//  terms in it correctly when they occur in the audio. Pocket ships this as a
//  "custom vocabulary dictionary" the user fills in by hand; EEON fills most of
//  it in from what it already knows (the people and projects extracted from
//  past notes) and lets the user add the rest.
//
//  Two lists, one prompt:
//    - custom:  user-entered in Settings → Capture → "Words EEON should know"
//    - learned: refreshed from MentionedPerson + Project on app-active and after
//               every extraction pass; never edited by hand
//
//  Whisper keeps only the FINAL 224 tokens of the prompt and silently drops
//  everything before. So terms are chosen by priority (user terms, then the
//  most-mentioned people) but EMITTED in reverse — user terms last — so an
//  overflow drops the least important names, never the ones typed by hand.
//
//  Storage is UserDefaults only (no in-memory state), so the singleton is safe
//  to read from any actor — TranscriptionService reads it at init.
//

import Foundation
import SwiftData

nonisolated final class TranscriptionVocabulary: @unchecked Sendable {
    static let shared = TranscriptionVocabulary()

    private enum Keys {
        static let custom = "transcriptionVocabulary.custom"
        static let learned = "transcriptionVocabulary.learned"
    }

    /// Whisper's prompt is limited to 224 tokens — the LAST 224. Proper nouns
    /// tokenize at ~2.5–3.5 chars/token, so 450 characters stays under it.
    static let maxPromptCharacters = 450
    static let maxLearnedPeople = 40
    static let maxLearnedProjects = 20

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Custom terms (user-entered)

    var customTerms: [String] {
        get { defaults.stringArray(forKey: Keys.custom) ?? [] }
        set { defaults.set(Self.dedupe(newValue), forKey: Keys.custom) }
    }

    /// Learned from the user's own notes. Read-only outside `refreshLearned`.
    var learnedTerms: [String] {
        defaults.stringArray(forKey: Keys.learned) ?? []
    }

    // MARK: - Learned terms (people + projects EEON has already extracted)

    /// Rebuilds the learned list from SwiftData. Cheap (two fetches, no AI);
    /// call on app-active and after an extraction pass writes new people.
    func refreshLearned(context: ModelContext) {
        var people = FetchDescriptor<MentionedPerson>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.mentionCount, order: .reverse)]
        )
        people.fetchLimit = Self.maxLearnedPeople
        let peopleNames = ((try? context.fetch(people)) ?? []).map(\.name)

        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projectNames = projects
            .filter { !$0.isArchived && !libraryIsSchemaSeedName($0.name) }
            .prefix(Self.maxLearnedProjects)
            .flatMap { [$0.name] + $0.aliases }

        let learned = Self.dedupe(peopleNames + projectNames)
        defaults.set(learned, forKey: Keys.learned)
    }

    // MARK: - Prompt

    /// The text sent as Whisper's `prompt`. Nil when there is nothing to send,
    /// so the request body is byte-identical to before for users with no
    /// vocabulary. Selected by priority, emitted reversed (see header).
    var whisperPrompt: String? {
        var included: [String] = []
        var length = 0
        for term in Self.dedupe(customTerms + learnedTerms) {
            let cost = term.count + (included.isEmpty ? 0 : 2)
            guard length + cost <= Self.maxPromptCharacters else { break }
            included.append(term)
            length += cost
        }
        guard !included.isEmpty else { return nil }
        return included.reversed().joined(separator: ", ") + "."
    }

    // MARK: - Parsing

    /// Splits user input on newlines and commas, trims, and drops junk.
    static func parseTerms(_ text: String) -> [String] {
        let pieces = text
            .replacingOccurrences(of: ",", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return dedupe(pieces)
    }

    /// Case-insensitive de-dupe preserving first occurrence and its casing.
    /// Also drops empties, one-character terms, the extraction's "Me"
    /// self-reference, and the "__seed" placeholders from schema seeding.
    static func dedupe(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in terms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = term.lowercased()
            guard term.count >= 2,
                  !term.hasPrefix("_"),
                  !libraryIsSchemaSeedName(term),
                  key != "me", key != "i", key != "unknown",
                  !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(term)
        }
        return out
    }
}
