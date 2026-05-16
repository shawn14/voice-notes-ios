//
//  IntentClassifier.swift
//  voice notes
//
//  Classifies user voice input as either a new note or a question/query about past notes.
//

import Foundation

enum IntentType: String {
    case newNote = "note"
    case question = "question"
}

/// Sub-route classification for question types. Picked by `classifyQuestionRoute(query:)`
/// after `classify(transcript:)` returns `.question`. Each route maps to a specialized
/// handler in `RAGService` for cost-efficient retrieval.
enum QuestionRoute: Equatable, CustomStringConvertible {
    case ranking
    case trends
    case timeRange(DateInterval)
    case entity(String?)
    case semantic

    var label: String {
        switch self {
        case .ranking:   return "ranking"
        case .trends:    return "trends"
        case .timeRange: return "timeRange"
        case .entity:    return "entity"
        case .semantic:  return "semantic"
        }
    }

    /// Short human-readable badge shown above the answer in the UI.
    var badgeText: String {
        switch self {
        case .ranking:                  return "From: top projects"
        case .trends:                   return "From: brief synthesis"
        case .timeRange:                return "From: time-windowed notes"
        case .entity(let name?):        return "From: \(name)"
        case .entity(nil):              return "From: matched article"
        case .semantic:                 return "From: notes"
        }
    }

    var description: String { label }
}

@Observable
class IntentClassifier {
    static let shared = IntentClassifier()

    enum ClassifierError: LocalizedError {
        case noAPIKey
        case apiError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not configured"
            case .apiError(let message):
                return "Classifier API Error: \(message)"
            case .invalidResponse:
                return "Invalid classifier response"
            }
        }
    }

    /// Classify a transcript as either a new note or a question about past notes.
    /// Uses GPT-4o-mini for fast classification (<1 second target).
    func classify(transcript: String) async throws -> IntentType {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw ClassifierError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        Classify if this is a new thought/note to record OR a question about past notes.
        Questions include: queries starting with 'what', 'show me', 'summarize', 'remind me', \
        'how many', 'when did I', 'who did I', 'list my', 'draft a', 'prepare me', 'connect the dots'.
        New notes include: stream of consciousness, meeting recaps, ideas, decisions, updates.
        If ambiguous, classify as newNote.
        Respond with ONLY 'question' or 'note'.
        """

        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": apiMessages,
            "temperature": 0,
            "max_tokens": 10
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClassifierError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClassifierError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let raw = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if raw.contains("question") {
            return .question
        }
        // Default to newNote for ambiguous or "note" responses
        return .newNote
    }

    // MARK: - Question Sub-Routing

    /// Classify a user question into a sub-route so RAGService can dispatch to the
    /// cheapest backend. Runs AFTER `classify(transcript:)` returns `.question`.
    ///
    /// Order of operations:
    ///  1. Deterministic fast-paths (time range, top-N, exact entity-name match, trends keywords)
    ///  2. LLM fallback (~$0.00003 per call) only when no fast-path matches
    ///
    /// `articleNames` should be the names+aliases of compiled `KnowledgeArticle`s
    /// so entity matches catch "what about Sarah" → `.entity("Sarah")`.
    func classifyQuestionRoute(query: String, articleNames: [String] = []) async throws -> QuestionRoute {
        // Fast path 1: explicit time window
        if let interval = Self.parseTimeRange(in: query) {
            return .timeRange(interval)
        }

        // Fast path 2: top-N / ranking regex
        if Self.matchesRanking(query: query) {
            return .ranking
        }

        // Fast path 3: trends keywords (checked before entity so "trends about Sarah" → trends, not entity)
        if Self.matchesTrends(query: query) {
            return .trends
        }

        // Fast path 4: exact entity-name match against compiled article catalog
        if let entityName = Self.matchEntityName(query: query, articleNames: articleNames) {
            return .entity(entityName)
        }

        // LLM fallback
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            return .semantic // Without API key, safe default
        }

        let systemPrompt = """
        You route memory questions to the cheapest backend that can answer them.

        Choose ONE:
        - ranking — user wants a ranked list (top, most, biggest, busiest)
        - trends — user wants patterns/themes across many notes ("any trends",
          "what am I thinking about lately", "themes")
        - timeRange — user names a time window (today, yesterday, this week,
          last month, in April, since X)
        - entity — user names a specific project, person, or topic
        - semantic — open-ended question that requires searching individual notes

        Output: one word, lowercase.
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": query]
            ],
            "temperature": 0,
            "max_tokens": 4
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return .semantic // Safe fallback on transport error
        }

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let raw = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch raw {
        case "ranking":                            return .ranking
        case "trends":                             return .trends
        case "timerange", "time-range", "time_range":
            return .timeRange(Self.defaultTimeRange())
        case "entity":                             return .entity(nil)
        case "semantic":                           return .semantic
        default:                                   return .semantic
        }
    }

    // MARK: - Static Regex / Heuristic Helpers (no LLM cost)

    /// Parse common natural-language time windows from a question.
    /// Returns nil if no recognizable window is present.
    static func parseTimeRange(in query: String) -> DateInterval? {
        let lower = query.lowercased()
        let now = Date()
        let cal = Calendar.current

        if lower.contains("today") {
            let start = cal.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        }
        if lower.contains("yesterday") {
            let startOfToday = cal.startOfDay(for: now)
            if let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) {
                return DateInterval(start: startOfYesterday, end: startOfToday)
            }
        }
        if lower.contains("this week") {
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start {
                return DateInterval(start: weekStart, end: now)
            }
        }
        if lower.contains("last week") {
            if let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
               let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
                return DateInterval(start: lastWeekStart, end: thisWeekStart)
            }
        }
        if lower.contains("this month") {
            if let monthStart = cal.dateInterval(of: .month, for: now)?.start {
                return DateInterval(start: monthStart, end: now)
            }
        }
        if lower.contains("last month") {
            if let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start,
               let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) {
                return DateInterval(start: lastMonthStart, end: thisMonthStart)
            }
        }

        // "past N days" / "last N days"
        if let regex = try? NSRegularExpression(
            pattern: "(?:past|last)\\s+(\\d{1,3})\\s+days?",
            options: .caseInsensitive
        ) {
            let ns = lower as NSString
            if let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2 {
                let numStr = ns.substring(with: match.range(at: 1))
                if let days = Int(numStr), days > 0, days <= 365,
                   let start = cal.date(byAdding: .day, value: -days, to: now) {
                    return DateInterval(start: start, end: now)
                }
            }
        }

        // "in <month>" with current year
        let monthNames = ["january", "february", "march", "april", "may", "june",
                          "july", "august", "september", "october", "november", "december"]
        for (idx, name) in monthNames.enumerated() {
            if lower.contains("in \(name)") {
                let monthNum = idx + 1
                let year = cal.dateComponents([.year], from: now).year ?? 2026
                var comps = DateComponents()
                comps.year = year
                comps.month = monthNum
                comps.day = 1
                if let startDate = cal.date(from: comps),
                   let endDate = cal.date(byAdding: .month, value: 1, to: startDate) {
                    return DateInterval(start: startDate, end: min(endDate, now))
                }
            }
        }

        return nil
    }

    /// Match queries that ask for a ranked list.
    static func matchesRanking(query: String) -> Bool {
        let lower = query.lowercased()
        let patterns = [
            "top \\d", "top ten", "top five", "top three",
            "most active", "most recent", "most mentioned",
            "biggest", "busiest", "longest", "smallest",
            "rank ", "ranked ", "ranking",
            "list (my|all|the).*(project|projects|people|topic)"
        ]
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    /// Match queries asking for corpus-wide trends, patterns, or themes.
    static func matchesTrends(query: String) -> Bool {
        let lower = query.lowercased()
        let phrases = [
            "trend", "trends",
            "pattern", "patterns",
            "theme", "themes",
            "across all my notes",
            "what am i thinking about",
            "what have i been thinking",
            "what's been on my mind"
        ]
        return phrases.contains { lower.contains($0) }
    }

    /// Match a query that explicitly names a compiled article (person/project/topic).
    /// Prefers the longest match so "Sarah Chen" beats "Sarah".
    static func matchEntityName(query: String, articleNames: [String]) -> String? {
        guard !articleNames.isEmpty else { return nil }
        let lower = query.lowercased()
        let sortedByLength = articleNames.sorted { $0.count > $1.count }
        for name in sortedByLength where !name.isEmpty {
            if lower.contains(name.lowercased()) {
                return name
            }
        }
        return nil
    }

    /// Default time range when the LLM says "timeRange" but the query has no explicit window.
    /// Falls back to the past 7 days.
    static func defaultTimeRange() -> DateInterval {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return DateInterval(start: start, end: now)
    }
}
