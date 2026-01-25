//
//  ProjectMatcher.swift
//  voice notes
//
//  Smart project detection: aliases → fuzzy → AI fallback
//  Goal: Make assignment feel telepathic
//

import Foundation

struct ProjectMatch {
    let project: Project
    let confidence: Double  // 0.0 to 1.0
    let matchType: MatchType

    enum MatchType: String {
        case alias = "alias"
        case fuzzy = "fuzzy"
        case ai = "ai"
    }
}

struct ProjectMatcher {

    /// Minimum confidence to auto-assign (below this → inbox)
    static let autoAssignThreshold: Double = 0.6

    /// High confidence - don't even show confirmation
    static let highConfidenceThreshold: Double = 0.85

    // MARK: - Main Matching Function

    /// Find the best matching project for given text
    /// Returns nil if no confident match found (goes to inbox)
    static func findMatch(for text: String, in projects: [Project]) -> ProjectMatch? {
        guard !projects.isEmpty else { return nil }

        let normalizedText = normalize(text)

        // Layer 1: Exact alias match (highest confidence)
        if let aliasMatch = matchByAlias(text: normalizedText, projects: projects) {
            return aliasMatch
        }

        // Layer 2: Fuzzy match (medium confidence)
        if let fuzzyMatch = matchByFuzzy(text: normalizedText, projects: projects) {
            return fuzzyMatch
        }

        // No match - will go to inbox
        // Layer 3 (AI) is called separately when needed
        return nil
    }

    // MARK: - Layer 1: Alias Matching

    private static func matchByAlias(text: String, projects: [Project]) -> ProjectMatch? {
        // Find all projects that have an alias match
        var matches: [(Project, Int)] = []  // (project, alias length)

        for project in projects {
            for alias in project.aliases {
                if text.contains(alias) {
                    // Longer alias = more specific = better match
                    matches.append((project, alias.count))
                    break
                }
            }
        }

        // Return the one with longest matching alias (most specific)
        if let best = matches.max(by: { $0.1 < $1.1 }) {
            return ProjectMatch(
                project: best.0,
                confidence: 0.95,  // Alias matches are high confidence
                matchType: .alias
            )
        }

        return nil
    }

    // MARK: - Layer 2: Fuzzy Matching

    private static func matchByFuzzy(text: String, projects: [Project]) -> ProjectMatch? {
        let textWords = Set(text.split(separator: " ").map { String($0) })

        var bestMatch: (Project, Double)? = nil

        for project in projects {
            // Get all words from project name and aliases
            var projectWords: Set<String> = []
            projectWords.formUnion(project.name.lowercased().split(separator: " ").map { String($0) })
            for alias in project.aliases {
                projectWords.formUnion(alias.split(separator: " ").map { String($0) })
            }

            // Calculate word overlap
            let overlap = textWords.intersection(projectWords)
            guard !overlap.isEmpty else { continue }

            // Score based on:
            // 1. How many project words matched (recall)
            // 2. Bonus for matching significant words (longer = more significant)
            let recall = Double(overlap.count) / Double(projectWords.count)
            let significantMatches = overlap.filter { $0.count >= 4 }.count
            let score = recall * 0.6 + Double(significantMatches) * 0.15

            if score > 0.3 {  // Minimum threshold
                if bestMatch == nil || score > bestMatch!.1 {
                    bestMatch = (project, score)
                }
            }
        }

        if let (project, score) = bestMatch {
            // Cap fuzzy confidence at 0.75 (never as confident as alias)
            let confidence = min(0.4 + score * 0.5, 0.75)
            return ProjectMatch(
                project: project,
                confidence: confidence,
                matchType: .fuzzy
            )
        }

        return nil
    }

    // MARK: - Layer 3: AI Matching

    /// Use AI to resolve ambiguous cases
    /// Call this only when Layer 1 & 2 fail or return multiple close matches
    static func matchWithAI(text: String, projects: [Project], apiKey: String) async throws -> ProjectMatch? {
        guard !projects.isEmpty else { return nil }

        let projectNames = projects.map { $0.name }.joined(separator: ", ")

        let prompt = """
        Which project does this note most likely belong to?
        Projects: \(projectNames)
        Note: "\(text.prefix(500))"

        Reply with ONLY the project name, or "none" if unclear.
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1,
            "max_tokens": 50
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let answer = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        if answer == "none" || answer.isEmpty {
            return nil
        }

        // Find the project that matches the AI's answer
        if let project = projects.first(where: { $0.name.lowercased() == answer }) {
            return ProjectMatch(
                project: project,
                confidence: 0.7,  // AI match is medium-high confidence
                matchType: .ai
            )
        }

        // Fuzzy match on AI answer (in case of slight variations)
        if let project = projects.first(where: { answer.contains($0.name.lowercased()) || $0.name.lowercased().contains(answer) }) {
            return ProjectMatch(
                project: project,
                confidence: 0.65,
                matchType: .ai
            )
        }

        return nil
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "'", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Learn from user correction - add new alias
    static func learnFromCorrection(text: String, assignedTo project: Project) {
        // Extract potential alias from the text
        let words = text.lowercased().split(separator: " ")

        // Find sequences that might be the project reference
        for i in 0..<words.count {
            // Single word
            let single = String(words[i])
            if single.count >= 3 && !commonWords.contains(single) {
                // Check if this word appears near project-related words
                let context = words[max(0, i-2)..<min(words.count, i+3)].joined(separator: " ")
                if context.contains("for") || context.contains("about") || context.contains("regarding") {
                    project.addAlias(single)
                }
            }

            // Two words
            if i < words.count - 1 {
                let twoWords = "\(words[i]) \(words[i+1])"
                if twoWords.count >= 5 && levenshteinSimilarity(twoWords, project.name.lowercased()) > 0.6 {
                    project.addAlias(twoWords)
                }
            }
        }
    }

    /// Simple Levenshtein distance ratio (0 to 1)
    private static func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 || len2 == 0 {
            return len1 == len2 ? 1.0 : 0.0
        }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: len2 + 1), count: len1 + 1)

        for i in 0...len1 { matrix[i][0] = i }
        for j in 0...len2 { matrix[0][j] = j }

        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        let distance = matrix[len1][len2]
        let maxLen = max(len1, len2)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "need", "want", "like",
        "this", "that", "these", "those", "i", "you", "he", "she", "it",
        "we", "they", "my", "your", "his", "her", "its", "our", "their",
        "about", "just", "also", "some", "new", "now", "get", "got", "going"
    ]
}
