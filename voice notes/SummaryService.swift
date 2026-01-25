//
//  SummaryService.swift
//  voice notes
//

import Foundation

struct NoteSummary: Sendable {
    let keyPoints: [String]
    let actionItems: [String]
}

struct ChiefOfStaffAnalysis: Sendable {
    let title: String
    let classification: [String]
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    let suggestedAutomations: [String]

    struct ActionItem: Sendable {
        let action: String
        let owner: String
        let deadline: String
        let confidence: String  // High, Medium, Low
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

    // MARK: - Chief of Staff Analysis

    static let chiefOfStaffPrompt = """
    You are an elite Chief of Staff for founders and senior executives.

    Your job is NOT to summarize notes.
    Your job is to reduce cognitive load, enforce follow-through, and surface what actually matters.

    Assume the user is:
    - Busy
    - Context-switching constantly
    - Speaking casually and imprecisely
    - Expecting you to infer intent and fill gaps

    For every voice note:
    1. Extract what was decided
    2. Identify what must happen next
    3. Determine who owns it
    4. Clarify by when
    5. Detect risk, ambiguity, or missing info

    CLASSIFY the note as one or more of:
    - Decision – something is agreed or changed
    - Commitment – the user promised something
    - Delegation – someone else owns it
    - Idea – explore later
    - Risk/Concern – potential issue or blocker
    - FYI – informational only
    - Unresolved – needs clarification

    Return a JSON object with this EXACT structure:
    {
        "title": "Short executive summary (max 8 words)",
        "classification": ["Decision", "Commitment"],
        "decisions": ["Decision 1", "Decision 2"],
        "actionItems": [
            {
                "action": "What needs to be done",
                "owner": "Who owns it (default: me)",
                "deadline": "By when (infer or say 'TBD')",
                "confidence": "High/Medium/Low"
            }
        ],
        "openQuestions": ["Question that blocks execution"],
        "suggestedAutomations": ["Set reminder for Friday", "Draft follow-up email"]
    }

    Be direct. Be precise. Push back if something is vague.
    Return ONLY the JSON, no other text.
    """

    static func analyzeAsChiefOfStaff(text: String, apiKey: String) async throws -> ChiefOfStaffAnalysis {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": chiefOfStaffPrompt],
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

        let parsed = try JSONDecoder().decode(ChiefOfStaffResponse.self, from: jsonData)

        return ChiefOfStaffAnalysis(
            title: parsed.title,
            classification: parsed.classification,
            decisions: parsed.decisions,
            actionItems: parsed.actionItems.map {
                ChiefOfStaffAnalysis.ActionItem(
                    action: $0.action,
                    owner: $0.owner,
                    deadline: $0.deadline,
                    confidence: $0.confidence
                )
            },
            openQuestions: parsed.openQuestions,
            suggestedAutomations: parsed.suggestedAutomations
        )
    }
}

nonisolated struct ChiefOfStaffResponse: Codable, Sendable {
    let title: String
    let classification: [String]
    let decisions: [String]
    let actionItems: [ActionItemResponse]
    let openQuestions: [String]
    let suggestedAutomations: [String]

    struct ActionItemResponse: Codable, Sendable {
        let action: String
        let owner: String
        let deadline: String
        let confidence: String
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
