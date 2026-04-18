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
    let topics: [String]            // 1-5 semantic topic tags
    let emotionalTone: String?      // Speaker's emotional tone
    let enhancedNote: String?       // AI-enhanced version of the note

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

// MARK: - Knowledge Article Compilation Response

struct CompileArticleResponse: Codable {
    let summary: String
    let openThreads: [OpenThread]?
    let timeline: [TimelineEvent]?
    let connections: [ArticleConnection]?
    let sentimentArc: String?
    let decisions: [ArticleDecision]?
    let relationshipContext: String?
    let thinkingEvolution: String?
    // Only emitted by .purpose article compiles — a structured HomeLayout JSON string
    // (stringified because nested heterogeneous structures are harder for the LLM to emit reliably)
    let homeLayoutJSON: String?
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

    // MARK: - Filler Word Removal

    static func cleanFillerWords(from transcript: String, apiKey: String) async throws -> String {
        // Skip very short transcripts
        guard transcript.split(separator: " ").count > 10 else {
            return transcript
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Remove filler words and verbal tics (um, uh, like, you know, so, basically, actually, I mean, right, sort of, kind of, well, yeah, okay so, honestly, literally) from this transcript. Preserve all meaning, tone, and sentence structure. Do not summarize, rephrase, or change the content. Return only the cleaned text."],
                ["role": "user", "content": transcript]
            ],
            "max_tokens": 4096,
            "temperature": 0.1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            // If parsing fails, return original transcript
            return transcript
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Title Generation

    static func generateTitle(for text: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
                ["role": "user", "content": String(text.prefix(500))]
            ],
            "max_tokens": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return "Untitled Note"
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Note Analysis (Notes ≠ Decisions)

    static var analysisPrompt: String {
        """
        \(ContextAssembler.flatPrefix(for: .extraction))You are an AI assistant in a voice note app.

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
    }

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

    static var intentPrompt: String {
        """
        \(ContextAssembler.flatPrefix(for: .extraction))You are an AI assistant in a voice note app that turns notes into actionable items.

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
    7. Topics: 1-5 semantic topic tags describing what this note is ABOUT (e.g. "Q2 planning", "hiring", "product launch")
    8. Emotional tone: single word describing the speaker's tone
    9. Enhanced note: a cleaned-up, expanded, well-structured version of what the user said. Not just filler word removal — actually make the thought more complete and organized. Preserve the user's voice and intent.
    10. Standard analysis: summary, key points, decisions, actions, commitments, unresolved

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
        "topics": ["board meeting", "scheduling", "governance"],
        "emotionalTone": "decisive",
        "enhancedNote": "A cleaned-up, well-structured version of the original note with complete thoughts and proper organization.",
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
    - topics: 1-5 short semantic topic tags. These describe what the note is ABOUT, not keywords. E.g. "Q2 planning", "hiring", "product launch", "design team".
    - emotionalTone: Single word from: confident, uncertain, frustrated, excited, neutral, worried, optimistic, decisive. Pick the best fit.
    - enhancedNote: A well-structured, cleaned-up version of what the user said. Remove filler, fix grammar, expand incomplete thoughts, organize into clear paragraphs. Preserve the user's voice and intent. Not a summary — the full thought, just better written.
    - Return ONLY JSON, no other text
    """
    }

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
            "max_tokens": 2500
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
            topics: parsed.topics ?? [],
            emotionalTone: parsed.emotionalTone,
            enhancedNote: parsed.enhancedNote,
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

    // MARK: - Lightweight Extraction (for web articles and derived notes)

    /// Lighter extraction for non-voice sources — topics, people, summary only.
    /// Skips actions, commitments, unresolved items, next steps.
    static func extractIntentLightweight(text: String, apiKey: String) async throws -> IntentAnalysis {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Analyze this text and extract structured information.
        This is reference material (a web article or saved AI response), NOT a personal voice note.
        Extract topics and people mentioned, but do NOT extract personal actions, commitments, or unresolved items.

        Return ONLY valid JSON:
        {
            "intent": "Idea",
            "intentConfidence": 0.8,
            "mentionedPeople": ["name1", "name2"],
            "topics": ["topic1", "topic2"],
            "emotionalTone": "neutral",
            "enhancedNote": "A clean, concise summary of the content (2-4 sentences)",
            "summary": "One sentence summary",
            "keyPoints": ["point1", "point2"],
            "inferredProject": "project name or null"
        }
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": String(text.prefix(4000))]
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

        let parsed = try JSONDecoder().decode(IntentAnalysisResponse.self, from: jsonData)

        return IntentAnalysis(
            intent: parsed.intent,
            intentConfidence: parsed.intentConfidence,
            subject: nil,
            nextStep: nil,
            nextStepType: "simple",
            missingInfo: [],
            inferredProject: parsed.inferredProject,
            mentionedPeople: parsed.mentionedPeople ?? [],
            topics: parsed.topics ?? [],
            emotionalTone: parsed.emotionalTone,
            enhancedNote: parsed.enhancedNote,
            summary: parsed.summary,
            keyPoints: parsed.keyPoints,
            decisions: [],
            actions: [],
            commitments: [],
            unresolved: []
        )
    }

    // MARK: - Knowledge Article Compilation

    /// Compile or update a KnowledgeArticle from new notes.
    static func compileArticle(
        existingSummary: String?,
        existingOpenThreads: [OpenThread],
        existingTimeline: [TimelineEvent],
        existingConnections: [ArticleConnection],
        existingSentimentArc: String?,
        existingDecisions: [ArticleDecision],
        existingRelationshipContext: String?,
        existingThinkingEvolution: String?,
        articleName: String,
        articleType: KnowledgeArticleType,
        newNoteTexts: [String],
        apiKey: String
    ) async throws -> CompileArticleResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build existing article context
        var existingContext = ""
        if let summary = existingSummary, !summary.isEmpty {
            existingContext += "Current summary: \(summary)\n"
        }
        if let arc = existingSentimentArc, !arc.isEmpty {
            existingContext += "Sentiment arc: \(arc)\n"
        }
        if let rel = existingRelationshipContext, !rel.isEmpty {
            existingContext += "Relationship context: \(rel)\n"
        }
        if let evolution = existingThinkingEvolution, !evolution.isEmpty {
            existingContext += "Thinking evolution: \(evolution)\n"
        }
        if !existingOpenThreads.isEmpty {
            let threads = existingOpenThreads.map { "- \($0.thread) (\($0.status), \($0.daysOpen)d)" }.joined(separator: "\n")
            existingContext += "Open threads:\n\(threads)\n"
        }
        if !existingDecisions.isEmpty {
            let decs = existingDecisions.map { "- \($0.decision) [\($0.status)]" }.joined(separator: "\n")
            existingContext += "Decisions:\n\(decs)\n"
        }

        let newNotesText = newNoteTexts.enumerated().map { "Note \($0.offset + 1): \($0.element)" }.joined(separator: "\n\n")

        let typeSpecificFields: String
        switch articleType {
        case .person:
            typeSpecificFields = """
            "relationshipContext": "Who this person is and your relationship (1-2 sentences)",
            "sentimentArc": "How the relationship tone has evolved (e.g. 'Cautious -> Warming up -> Trusted partner')",
            """
        case .project:
            typeSpecificFields = """
            "decisions": [{"decision": "what was decided", "status": "resolved or open", "date": "when"}],
            "thinkingEvolution": "How your approach has changed over time (1 sentence)",
            "sentimentArc": "Overall project mood trajectory",
            """
        case .topic:
            typeSpecificFields = """
            "thinkingEvolution": "How your thinking on this topic has evolved (1-2 sentences)",
            "sentimentArc": "Your emotional relationship with this topic over time",
            """
        case .self:
            typeSpecificFields = """
            "relationshipContext": "Who this user is — their role, interests, skills, what they're currently working on (2-3 sentences)",
            "thinkingEvolution": "How their focus has shifted over time based on what they've been capturing (1 sentence)",
            """
        case .purpose:
            typeSpecificFields = """
            "thinkingEvolution": "What this user uses EEON for — their role, goal, methodology. Write as a system-prompt directive that can be injected into other AI calls. Example: 'The user is a founder. Frame responses to prioritize and rank their projects by execution readiness. Flag decisions that unblock execution.' Or: 'The user is a Jungian dream interpreter. Frame all notes through archetypes; always surface the dreamer's feeling over the symbol's meaning.' Be specific, concrete, and actionable.",
            "homeLayoutJSON": "A JSON STRING (stringified — escape quotes) describing the user's home-screen layout. The outer object has {\\"sections\\": [...], \\"version\\": 1}. Each section has {\\"kindRaw\\": <one of the allowed section IDs>, \\"title\\": <optional override>, \\"rationale\\": <REQUIRED — one short sentence explaining WHY this section is here for THIS user, written in second person, max 80 chars, e.g. 'Because you ship AI apps and want to flag silent projects.'>, \\"limit\\": <optional number>, \\"staleDaysThreshold\\": <optional number>}. Pick 4-6 sections that best match this user's role. **ALWAYS put `todayThree` as the FIRST section regardless of archetype** — it is the daily-intentions ritual and universal across roles. Allowed kindRaw values: todayThree, priorityProjects, silentProjects, openDecisions, ideaInbox, openThreads, clientRoster, followUpsPerClient, relationshipArcs, recurringPatterns, emotionalToneArc, referenceResonance, activeInquiries, contradictionLedger, knowledgeCarousel, recentNotes, dailyBrief. FOUNDER example: todayThree, priorityProjects, openDecisions, ideaInbox, silentProjects, recentNotes. COACH example: todayThree, clientRoster, followUpsPerClient, relationshipArcs, recentNotes. DREAM INTERPRETER example: todayThree, recurringPatterns, emotionalToneArc, referenceResonance, recentNotes. RESEARCHER example: todayThree, activeInquiries, contradictionLedger, knowledgeCarousel, recentNotes. Always include recentNotes as a fallback at the end. Adapt based on the user's actual notes if you have evidence — e.g., if notes mention many clients, lean coach; many dreams, lean interpreter. Rationales must be specific to the user's stated purpose — not generic. For todayThree, rationale should be about daily intentions in their role's language — e.g., 'Because staying on your three things is how you keep shipping.'"
            """
        case .reference:
            typeSpecificFields = """
            "thinkingEvolution": "Key frameworks, concepts, or quotable passages from this reference material. Optimized for retrieval when the user asks questions this reference could answer.",
            """
        }

        let articleKind: String
        let compilationGuidance: String
        switch articleType {
        case .person, .project, .topic:
            articleKind = "a \(articleType.label.lowercased()) named \"\(articleName)\""
            compilationGuidance = """
            Update the article with information from the new notes below.
            Preserve existing information unless contradicted by newer notes.
            Be concise — summaries should be 2-3 sentences max.
            WEB SOURCE and DERIVED entries are reference material. They may inform connections and context but should not override summaries or timelines established by primary voice notes.
            """
        case .self:
            articleKind = "the app's user (\"\(articleName)\")"
            compilationGuidance = """
            Compile a first-person profile: who the user is, what they care about, what they're working on, who they know, what they've made.
            PROFILE SEED entries (user-authored, high authority) are canonical identity facts — never contradict them.
            Use voice notes to surface current context: what they're focused on lately, recurring themes, who they mention often.
            Be concise. The summary will be injected into every AI call as "About the user" context.
            """
        case .purpose:
            articleKind = "what EEON is FOR this user"
            compilationGuidance = """
            Compile a directive that defines WHO the user is and HOW EEON should serve them.
            PURPOSE SEED entries (user-authored, high authority) are the canonical role statement — start there.
            Observe patterns from voice notes: what do they repeatedly ask for? What framings do they use? What decisions do they make?
            The `thinkingEvolution` field is the most important — it will be injected as a system-prompt addition into every substantive AI call, so it must be a concrete, actionable directive.
            The `summary` should be a 1-sentence human-readable version the user will see in Settings.
            """
        case .reference:
            articleKind = "uploaded reference material about \"\(articleName)\""
            compilationGuidance = """
            This article indexes user-uploaded canon (books, essays, domain expertise). The user did NOT write these notes — they imported them as reference.
            Summarize frameworks, key concepts, and quotable passages. Do NOT treat this as the user's own thinking.
            This article will be retrieved by RAG when the user asks a question that maps to its domain.
            Preserve quotes verbatim where useful. Attribution matters.
            """
        }

        let systemPrompt = """
        You maintain a living knowledge article about \(articleKind).
        \(compilationGuidance)

        Return ONLY valid JSON with this structure:
        {
            "summary": "2-3 sentence overview incorporating new information",
            "openThreads": [{"thread": "description of open item", "status": "open|waiting|stale", "daysOpen": 0}],
            "timeline": [{"date": "YYYY-MM-DD or description", "event": "what happened"}],
            "connections": [{"articleName": "name of related person/project/topic", "reason": "why connected"}],
            \(typeSpecificFields)
        }

        Rules:
        - Keep summaries factual and concise
        - Mark threads as "stale" if they seem forgotten (>5 days with no update)
        - Timeline should only include significant events, max 10 entries
        - Connections should link to other people, projects, or topics mentioned alongside this entity
        - Return ONLY valid JSON, no other text
        """

        let userContent: String
        if existingContext.isEmpty {
            userContent = "Create a new article from these notes:\n\n\(newNotesText)"
        } else {
            userContent = "Current article state:\n\(existingContext)\n\nNew notes to incorporate:\n\n\(newNotesText)"
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
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

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummaryError.apiError("Empty response")
        }

        return try JSONDecoder().decode(CompileArticleResponse.self, from: jsonData)
    }

    /// Lint all knowledge articles for stale threads, contradictions, connections, and gaps.
    static func lintArticles(
        articleSummaries: [(name: String, type: String, summary: String, openThreadCount: Int, daysSinceLastMention: Int)],
        apiKey: String
    ) async throws -> [KnowledgeLintResult] {
        guard !articleSummaries.isEmpty else { return [] }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let articlesText = articleSummaries.map { article in
            "[\(article.type)] \(article.name): \(article.summary) (open threads: \(article.openThreadCount), last mentioned: \(article.daysSinceLastMention)d ago)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a knowledge base health checker. Review these knowledge articles and find issues.

        Return JSON array of issues found:
        [
            {
                "lintType": "stale_thread|contradiction|connection|gap",
                "content": "Human-readable description of the issue",
                "severity": "info|warning|urgent",
                "relatedArticleNames": ["Article Name 1", "Article Name 2"]
            }
        ]

        Lint types:
        - stale_thread: Open commitments or threads with no follow-up (>5 days)
        - contradiction: Conflicting information across articles
        - connection: Articles that should be linked but aren't
        - gap: Missing information that seems important

        Rules:
        - Return 0-5 most important issues
        - Focus on actionable insights, not trivia
        - "urgent" = needs action today, "warning" = needs attention this week, "info" = nice to know
        - Return ONLY valid JSON array, no other text
        - If no issues found, return empty array []
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Review these knowledge articles:\n\n\(articlesText)"]
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

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            return []
        }

        return (try? JSONDecoder().decode([KnowledgeLintResult].self, from: jsonData)) ?? []
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
    let topics: [String]?
    let emotionalTone: String?
    let enhancedNote: String?
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

// MARK: - Account Context for Reports

extension SummaryService {
    /// Builds a structured context string from all user data for account-level reports.
    /// Call on @MainActor (SwiftData models are not Sendable). Pass the resulting String to async API calls.
    static func buildAccountContext(
        notes: [Note],
        projects: [Project],
        decisions: [ExtractedDecision],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        people: [MentionedPerson],
        kanbanItems: [KanbanItem]
    ) -> String {
        let maxContextLength = 12_000
        var sections: [String] = []

        // Projects (always included, compact)
        if !projects.isEmpty {
            let projectLines = projects.map { project in
                let status = project.isStalled ? "stalled" : "active"
                let lastActivity = project.lastActivityAt?.formatted(date: .abbreviated, time: .omitted) ?? "none"
                return "- \(project.name): \(project.noteCount) notes, \(project.openActionCount) open actions, last activity: \(lastActivity), status: \(status)"
            }
            sections.append("PROJECTS (\(projects.count) total):\n" + projectLines.joined(separator: "\n"))
        }

        // Decisions (always included, compact)
        if !decisions.isEmpty {
            let decisionLines = decisions.map { d in
                "- [\(d.createdAt.formatted(date: .abbreviated, time: .omitted))] \(d.content) (Status: \(d.status), Affects: \(d.affects))"
            }
            sections.append("DECISIONS (\(decisions.count) total):\n" + decisionLines.joined(separator: "\n"))
        }

        // Actions (always included, compact)
        if !actions.isEmpty {
            let actionLines = actions.map { a in
                let status = a.isCompleted ? "completed" : (a.isBlocked ? "blocked" : "open")
                return "- [\(a.createdAt.formatted(date: .abbreviated, time: .omitted))] \(a.content) — Owner: \(a.owner), Deadline: \(a.deadline), Status: \(status), Priority: \(a.priority)"
            }
            sections.append("ACTIONS (\(actions.count) total):\n" + actionLines.joined(separator: "\n"))
        }

        // Commitments (always included, compact)
        if !commitments.isEmpty {
            let commitmentLines = commitments.map { c in
                let status = c.isCompleted ? "completed" : "open"
                return "- [\(c.createdAt.formatted(date: .abbreviated, time: .omitted))] \(c.who): \(c.what) — Status: \(status)"
            }
            sections.append("COMMITMENTS (\(commitments.count) total):\n" + commitmentLines.joined(separator: "\n"))
        }

        // People (always included, compact)
        if !people.isEmpty {
            let peopleLines = people.filter { !$0.isArchived }.map { p in
                "- \(p.displayName): \(p.mentionCount) mentions, \(p.openCommitmentCount) open commitments, last mentioned: \(p.lastMentionedAt.formatted(date: .abbreviated, time: .omitted))"
            }
            sections.append("PEOPLE (\(people.filter { !$0.isArchived }.count) total):\n" + peopleLines.joined(separator: "\n"))
        }

        // Build non-note context first to measure remaining budget
        let fixedContext = "ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")
        let remainingBudget = maxContextLength - fixedContext.count

        // Notes (trimmed to fit budget)
        if !notes.isEmpty && remainingBudget > 200 {
            let notesToInclude = Array(notes.prefix(50))
            var noteLines: [String] = []
            var noteCharsUsed = 0
            let headerLine = "NOTES (\(notes.count) total):\n"
            noteCharsUsed += headerLine.count

            for note in notesToInclude {
                let preview = String((note.transcript ?? note.content).prefix(200))
                let line = "- [\(note.createdAt.formatted(date: .abbreviated, time: .omitted))] \(note.displayTitle): \(preview)"
                if noteCharsUsed + line.count + 1 > remainingBudget - 100 { break }
                noteLines.append(line)
                noteCharsUsed += line.count + 1
            }

            if !noteLines.isEmpty {
                sections.insert(headerLine + noteLines.joined(separator: "\n"), at: 0)
            }
        }

        // Kanban items (trimmed if needed)
        let currentLength = ("ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")).count
        if !kanbanItems.isEmpty && currentLength < maxContextLength - 200 {
            let kanbanBudget = maxContextLength - currentLength - 50
            var kanbanLines: [String] = []
            var kanbanCharsUsed = 0

            for item in kanbanItems {
                let daysSince = Calendar.current.dateComponents([.day], from: item.updatedAt, to: Date()).day ?? 0
                let line = "- [\(item.column)] \(item.content) — Type: \(item.itemType), Days since update: \(daysSince)"
                if kanbanCharsUsed + line.count + 1 > kanbanBudget { break }
                kanbanLines.append(line)
                kanbanCharsUsed += line.count + 1
            }

            if !kanbanLines.isEmpty {
                sections.append("KANBAN ITEMS (\(kanbanItems.count) total):\n" + kanbanLines.joined(separator: "\n"))
            }
        }

        return "ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")
    }
}
