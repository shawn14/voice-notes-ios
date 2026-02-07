//
//  SummaryService.swift
//  voice notes
//

import Foundation

struct NoteSummary: Sendable {
    let keyPoints: [String]
    let actionItems: [String]
}

struct NoteAnalysis: Sendable {
    let summary: String
    let keyPoints: [String]
    let extractedDecisions: [DecisionExtract]
    let extractedActions: [ActionExtract]
    let extractedCommitments: [CommitmentExtract]
    let unresolvedItems: [UnresolvedExtract]

    struct DecisionExtract: Sendable {
        let content: String
        let affects: String
        let confidence: String
    }

    struct ActionExtract: Sendable {
        let content: String
        let owner: String
        let deadline: String
    }

    struct CommitmentExtract: Sendable {
        let who: String
        let what: String
    }

    struct UnresolvedExtract: Sendable {
        let content: String
        let reason: String  // "No decision", "No owner", "Ambiguous"
    }
}

// MARK: - Intent Analysis

struct IntentAnalysis: Sendable {
    let intent: String              // Action, Decision, Idea, Update, Reminder
    let intentConfidence: Double    // 0.0 - 1.0
    let subject: SubjectExtract?
    let nextStep: String?
    let nextStepType: String        // date, contact, decision, simple
    let missingInfo: [MissingInfoExtract]
    let inferredProject: String?
    let mentionedPeople: [String]   // Names of people mentioned

    // Include existing analysis fields for combined extraction
    let summary: String
    let keyPoints: [String]
    let decisions: [NoteAnalysis.DecisionExtract]
    let actions: [NoteAnalysis.ActionExtract]
    let commitments: [NoteAnalysis.CommitmentExtract]
    let unresolved: [NoteAnalysis.UnresolvedExtract]

    struct SubjectExtract: Sendable {
        let topic: String
        let action: String?
    }

    struct MissingInfoExtract: Sendable {
        let field: String
        let description: String
    }
}

enum SummaryService {
    enum SummaryError: LocalizedError {
        case apiError(String)
        case parsingError

        var errorDescription: String? {
            switch self {
            case .apiError(let message):
                return "API Error: \(message)"
            case .parsingError:
                return "Could not parse summary"
            }
        }
    }

    static func generateSummary(for text: String, apiKey: String) async throws -> NoteSummary {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // For longer transcripts, sample throughout the text
        let textToAnalyze: String
        if text.count > 8000 {
            let chunkSize = 2000
            let start = String(text.prefix(chunkSize))
            let q1Start = text.index(text.startIndex, offsetBy: text.count / 4 - chunkSize/2)
            let q1End = text.index(text.startIndex, offsetBy: text.count / 4 + chunkSize/2)
            let q1 = String(text[q1Start..<q1End])
            let midStart = text.index(text.startIndex, offsetBy: text.count / 2 - chunkSize/2)
            let midEnd = text.index(text.startIndex, offsetBy: text.count / 2 + chunkSize/2)
            let mid = String(text[midStart..<midEnd])
            let q3Start = text.index(text.startIndex, offsetBy: 3 * text.count / 4 - chunkSize/2)
            let q3End = text.index(text.startIndex, offsetBy: 3 * text.count / 4 + chunkSize/2)
            let q3 = String(text[q3Start..<q3End])
            let end = String(text.suffix(chunkSize))
            textToAnalyze = "\(start)\n...\n\(q1)\n...\n\(mid)\n...\n\(q3)\n...\n\(end)"
        } else {
            textToAnalyze = text
        }

        let prompt = """
        Analyze the following transcript and extract:
        1. Key Points: The most important facts, decisions, or information mentioned (3-7 bullet points)
        2. Action Items: Any tasks, to-dos, or next steps mentioned (0-7 items)

        Return your response as a JSON object with this exact structure:
        {
            "keyPoints": ["point 1", "point 2", ...],
            "actionItems": ["action 1", "action 2", ...]
        }

        If there are no action items, return an empty array for actionItems.
        Keep each point concise (1-2 sentences max).
        Return ONLY the JSON, no other text.

        Transcript:
        \(textToAnalyze)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.parsingError
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(SummaryChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw SummaryError.parsingError
        }

        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8) else {
            throw SummaryError.parsingError
        }

        do {
            let summary = try JSONDecoder().decode(SummaryResponse.self, from: jsonData)
            return NoteSummary(keyPoints: summary.keyPoints, actionItems: summary.actionItems)
        } catch {
            // Try to extract from imperfect JSON
            return try parseSummaryFallback(from: content)
        }
    }

    private static func parseSummaryFallback(from content: String) throws -> NoteSummary {
        // Simple fallback parser
        var keyPoints: [String] = []
        var actionItems: [String] = []

        // Try to find keyPoints array
        if let keyPointsMatch = content.range(of: "\"keyPoints\"\\s*:\\s*\\[([^\\]]*)\\]", options: .regularExpression) {
            let keyPointsStr = String(content[keyPointsMatch])
            let items = keyPointsStr.components(separatedBy: "\",")
            for item in items {
                let cleaned = item
                    .replacingOccurrences(of: "\"keyPoints\"", with: "")
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    keyPoints.append(cleaned)
                }
            }
        }

        // Try to find actionItems array
        if let actionMatch = content.range(of: "\"actionItems\"\\s*:\\s*\\[([^\\]]*)\\]", options: .regularExpression) {
            let actionStr = String(content[actionMatch])
            let items = actionStr.components(separatedBy: "\",")
            for item in items {
                let cleaned = item
                    .replacingOccurrences(of: "\"actionItems\"", with: "")
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    actionItems.append(cleaned)
                }
            }
        }

        if keyPoints.isEmpty {
            throw SummaryError.parsingError
        }

        return NoteSummary(keyPoints: keyPoints, actionItems: actionItems)
    }

    // MARK: - Note Analysis (Notes ≠ Decisions)

    static let analysisPrompt = """
    You are an AI assistant in a founder-focused voice note app.

    CORE RULE: Notes are events. Decisions, actions, and commitments are separate objects.
    A note may produce decisions or actions, but it does not own them.

    For this note, provide:
    1. A brief summary (1-2 sentences)
    2. Key factual points (not actions or decisions)
    3. Extract any decisions, actions, or commitments as SEPARATE items
    4. Flag anything unresolved or ambiguous

    Return a JSON object with this EXACT structure:
    {
        "summary": "Brief description of what this note is about",
        "keyPoints": ["Factual takeaway 1", "Factual takeaway 2"],
        "decisions": [
            {
                "content": "What was decided",
                "affects": "What this impacts",
                "confidence": "High/Medium/Low"
            }
        ],
        "actions": [
            {
                "content": "What must be done",
                "owner": "Who owns it (default: Me)",
                "deadline": "By when (infer or TBD)"
            }
        ],
        "commitments": [
            {
                "who": "Who promised (use 'Me' if the speaker)",
                "what": "What was promised"
            }
        ],
        "unresolved": [
            {
                "content": "What was mentioned but not resolved",
                "reason": "No decision / No owner / Ambiguous"
            }
        ]
    }

    Rules:
    - Keep the note summary lightweight
    - Do NOT track status or completion in the note
    - Decisions and actions are READ-ONLY references in the note
    - They will be stored and managed separately
    - Flag items where no clear decision was made (e.g., "we should revisit pricing")
    - Flag items with no owner or ambiguous responsibility
    - Be precise, minimal, no fluff
    - Return ONLY JSON, no other text
    """

    static func analyzeNote(text: String, apiKey: String) async throws -> NoteAnalysis {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": analysisPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(SummaryChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummaryError.parsingError
        }

        let parsed = try JSONDecoder().decode(NoteAnalysisResponse.self, from: jsonData)

        return NoteAnalysis(
            summary: parsed.summary,
            keyPoints: parsed.keyPoints,
            extractedDecisions: parsed.decisions.map {
                NoteAnalysis.DecisionExtract(content: $0.content, affects: $0.affects, confidence: $0.confidence)
            },
            extractedActions: parsed.actions.map {
                NoteAnalysis.ActionExtract(content: $0.content, owner: $0.owner, deadline: $0.deadline)
            },
            extractedCommitments: parsed.commitments.map {
                NoteAnalysis.CommitmentExtract(who: $0.who, what: $0.what)
            },
            unresolvedItems: parsed.unresolved.map {
                NoteAnalysis.UnresolvedExtract(content: $0.content, reason: $0.reason)
            }
        )
    }

    // MARK: - Intent Extraction (Enhanced Analysis)

    static let intentPrompt = """
    You are an AI assistant in a founder-focused voice note app that turns notes into actionable items.

    CORE RULES:
    1. Be DECISIVE - pick ONE intent, don't hedge
    2. Be ACTIONABLE - next step should be imperative ("Pick...", "Send...", "Schedule...")
    3. Be HONEST - surface what's missing, don't hide gaps
    4. Notes are events. Decisions, actions, and commitments are separate objects.

    INTENT TYPES:
    - Action: Something that needs to be done (task, to-do, next step)
    - Decision: A choice that was made or needs to be made
    - Idea: A concept, thought, or potential opportunity
    - Update: Status information or progress report
    - Reminder: Something to remember or not forget

    For this note, provide:
    1. The PRIMARY intent (pick one, be decisive)
    2. The subject: what's this about? (topic + action)
    3. The next step: what should happen next? (imperative verb)
    4. Missing info: what's incomplete or unclear?
    5. Project inference: what project does this belong to?
    6. People mentioned: names of people referenced (not "I", "me", "myself")
    7. Standard analysis: summary, key points, decisions, actions, commitments, unresolved

    NEXT STEP TYPES (classify based on what resolution requires):
    - date: Involves picking a date/time ("Pick a date", "Schedule", "Set deadline", "When should we...")
    - contact: Involves reaching out to someone ("Send to", "Email", "Call", "Message", "Tell...")
    - decision: Involves choosing between options ("Decide on", "Choose between", "Pick one...")
    - simple: Everything else - just needs to be done ("Review", "Check", "Confirm", "Update...")

    Return a JSON object with this EXACT structure:
    {
        "intent": "Action",
        "intentConfidence": 0.9,
        "subject": {
            "topic": "Board Meeting",
            "action": "Reschedule to next week"
        },
        "nextStep": "Pick a date for the board meeting",
        "nextStepType": "date",
        "missingInfo": [
            {"field": "date", "description": "Needs a specific date"}
        ],
        "inferredProject": "StockAlarm",
        "mentionedPeople": ["John", "Sarah"],
        "summary": "Brief description of what this note is about",
        "keyPoints": ["Factual takeaway 1", "Factual takeaway 2"],
        "decisions": [
            {
                "content": "What was decided",
                "affects": "What this impacts",
                "confidence": "High/Medium/Low"
            }
        ],
        "actions": [
            {
                "content": "What must be done",
                "owner": "Who owns it (default: Me)",
                "deadline": "By when (infer or TBD)"
            }
        ],
        "commitments": [
            {
                "who": "Who promised (use 'Me' if the speaker)",
                "what": "What was promised"
            }
        ],
        "unresolved": [
            {
                "content": "What was mentioned but not resolved",
                "reason": "No decision / No owner / Ambiguous"
            }
        ]
    }

    Rules:
    - intent: Pick ONE from Action, Decision, Idea, Update, Reminder
    - intentConfidence: Your confidence 0.0-1.0 (be honest)
    - subject.topic: The main subject/entity being discussed
    - subject.action: What's happening with it (can be null for pure updates)
    - nextStep: Always imperative verb, specific and actionable. Null if truly complete.
    - nextStepType: Pick ONE from date, contact, decision, simple based on what resolution requires
    - missingInfo: Array of gaps. Empty array if nothing missing.
    - inferredProject: Best guess at project name. Null if unclear.
    - mentionedPeople: Array of proper names mentioned. Exclude "I", "me", "myself". Empty array if none.
    - Return ONLY JSON, no other text
    """

    static func extractIntent(text: String, apiKey: String) async throws -> IntentAnalysis {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": intentPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 1500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(SummaryChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummaryError.parsingError
        }

        let parsed = try JSONDecoder().decode(IntentAnalysisResponse.self, from: jsonData)

        return IntentAnalysis(
            intent: parsed.intent,
            intentConfidence: parsed.intentConfidence,
            subject: parsed.subject.map {
                IntentAnalysis.SubjectExtract(topic: $0.topic, action: $0.action)
            },
            nextStep: parsed.nextStep,
            nextStepType: parsed.nextStepType ?? "simple",
            missingInfo: parsed.missingInfo.map {
                IntentAnalysis.MissingInfoExtract(field: $0.field, description: $0.description)
            },
            inferredProject: parsed.inferredProject,
            mentionedPeople: parsed.mentionedPeople ?? [],
            summary: parsed.summary,
            keyPoints: parsed.keyPoints,
            decisions: parsed.decisions.map {
                NoteAnalysis.DecisionExtract(content: $0.content, affects: $0.affects, confidence: $0.confidence)
            },
            actions: parsed.actions.map {
                NoteAnalysis.ActionExtract(content: $0.content, owner: $0.owner, deadline: $0.deadline)
            },
            commitments: parsed.commitments.map {
                NoteAnalysis.CommitmentExtract(who: $0.who, what: $0.what)
            },
            unresolved: parsed.unresolved.map {
                NoteAnalysis.UnresolvedExtract(content: $0.content, reason: $0.reason)
            }
        )
    }
}

// MARK: - Intent Analysis Response

nonisolated struct IntentAnalysisResponse: Codable, Sendable {
    let intent: String
    let intentConfidence: Double
    let subject: SubjectResponse?
    let nextStep: String?
    let nextStepType: String?
    let missingInfo: [MissingInfoResponse]
    let inferredProject: String?
    let mentionedPeople: [String]?
    let summary: String
    let keyPoints: [String]
    let decisions: [DecisionResponse]
    let actions: [ActionResponse]
    let commitments: [CommitmentResponse]
    let unresolved: [UnresolvedResponse]

    struct SubjectResponse: Codable, Sendable {
        let topic: String
        let action: String?
    }

    struct MissingInfoResponse: Codable, Sendable {
        let field: String
        let description: String
    }

    struct DecisionResponse: Codable, Sendable {
        let content: String
        let affects: String
        let confidence: String
    }

    struct ActionResponse: Codable, Sendable {
        let content: String
        let owner: String
        let deadline: String
    }

    struct CommitmentResponse: Codable, Sendable {
        let who: String
        let what: String
    }

    struct UnresolvedResponse: Codable, Sendable {
        let content: String
        let reason: String
    }
}

nonisolated struct NoteAnalysisResponse: Codable, Sendable {
    let summary: String
    let keyPoints: [String]
    let decisions: [DecisionResponse]
    let actions: [ActionResponse]
    let commitments: [CommitmentResponse]
    let unresolved: [UnresolvedResponse]

    struct DecisionResponse: Codable, Sendable {
        let content: String
        let affects: String
        let confidence: String
    }

    struct ActionResponse: Codable, Sendable {
        let content: String
        let owner: String
        let deadline: String
    }

    struct CommitmentResponse: Codable, Sendable {
        let who: String
        let what: String
    }

    struct UnresolvedResponse: Codable, Sendable {
        let content: String
        let reason: String
    }
}

nonisolated struct SummaryChatResponse: Codable, Sendable {
    let choices: [Choice]

    struct Choice: Codable, Sendable {
        let message: Message
    }

    struct Message: Codable, Sendable {
        let content: String
    }
}

nonisolated struct SummaryResponse: Codable, Sendable {
    let keyPoints: [String]
    let actionItems: [String]
}

// MARK: - URL Metadata

struct URLMetadata: Sendable {
    let title: String?
    let description: String?
    let siteName: String?
    let imageURL: String?
    let faviconURL: String?
}

// MARK: - URL Detection & Metadata Fetching

extension SummaryService {
    /// Detect URLs in text using NSDataDetector (no API call, instant)
    static func detectURLs(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let urlString = String(text[range])
            // Filter out email addresses and other non-http links
            guard urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else { return nil }
            return urlString
        }
        .prefix(3) // Limit to 3 URLs per note
        .map { $0 }
    }

    /// Fetch OpenGraph metadata from a URL (HTML parsing, no API call)
    static func fetchURLMetadata(urlString: String) async throws -> URLMetadata {
        guard let url = URL(string: urlString) else {
            throw URLMetadataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLMetadataError.fetchFailed
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw URLMetadataError.invalidResponse
        }

        return parseOpenGraphTags(from: html, baseURL: url)
    }

    private static func parseOpenGraphTags(from html: String, baseURL: URL) -> URLMetadata {
        // Extract OpenGraph meta tags
        let title = extractMetaContent(from: html, property: "og:title")
            ?? extractMetaContent(from: html, name: "title")
            ?? extractTitleTag(from: html)

        let description = extractMetaContent(from: html, property: "og:description")
            ?? extractMetaContent(from: html, name: "description")

        let siteName = extractMetaContent(from: html, property: "og:site_name")

        var imageURL = extractMetaContent(from: html, property: "og:image")
        // Make relative URLs absolute
        if let image = imageURL, !image.hasPrefix("http") {
            if image.hasPrefix("//") {
                imageURL = "https:" + image
            } else if image.hasPrefix("/") {
                imageURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(image)"
            }
        }

        // Try to get favicon
        var faviconURL = extractFaviconURL(from: html, baseURL: baseURL)
        if faviconURL == nil {
            // Fallback to standard favicon location
            faviconURL = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")/favicon.ico"
        }

        return URLMetadata(
            title: title,
            description: description,
            siteName: siteName,
            imageURL: imageURL,
            faviconURL: faviconURL
        )
    }

    private static func extractMetaContent(from html: String, property: String) -> String? {
        // Match: <meta property="og:title" content="...">
        let pattern = #"<meta\s+[^>]*property\s*=\s*["']\#(property)["'][^>]*content\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            // Try reverse order: content before property
            let reversePattern = #"<meta\s+[^>]*content\s*=\s*["']([^"']*)["'][^>]*property\s*=\s*["']\#(property)["']"#
            guard let reverseRegex = try? NSRegularExpression(pattern: reversePattern, options: .caseInsensitive),
                  let reverseMatch = reverseRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let reverseRange = Range(reverseMatch.range(at: 1), in: html) else {
                return nil
            }
            return String(html[reverseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMetaContent(from html: String, name: String) -> String? {
        // Match: <meta name="description" content="...">
        let pattern = #"<meta\s+[^>]*name\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            // Try reverse order
            let reversePattern = #"<meta\s+[^>]*content\s*=\s*["']([^"']*)["'][^>]*name\s*=\s*["']\#(name)["']"#
            guard let reverseRegex = try? NSRegularExpression(pattern: reversePattern, options: .caseInsensitive),
                  let reverseMatch = reverseRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                  let reverseRange = Range(reverseMatch.range(at: 1), in: html) else {
                return nil
            }
            return String(html[reverseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractTitleTag(from html: String) -> String? {
        let pattern = #"<title[^>]*>([^<]*)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFaviconURL(from html: String, baseURL: URL) -> String? {
        // Match: <link rel="icon" href="..."> or <link rel="shortcut icon" href="...">
        let pattern = #"<link\s+[^>]*rel\s*=\s*["'][^"']*icon[^"']*["'][^>]*href\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let hrefRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        var favicon = String(html[hrefRange])
        if !favicon.hasPrefix("http") {
            if favicon.hasPrefix("//") {
                favicon = "https:" + favicon
            } else if favicon.hasPrefix("/") {
                favicon = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(favicon)"
            }
        }
        return favicon
    }
}

enum URLMetadataError: LocalizedError {
    case invalidURL
    case fetchFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .fetchFailed: return "Failed to fetch URL"
        case .invalidResponse: return "Invalid response"
        }
    }
}
