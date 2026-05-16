//
//  RAGService.swift
//  voice notes
//
//  Retrieval-Augmented Generation pipeline for answering questions about past notes.
//
//  Phase 1 architecture: a question is classified into a `QuestionRoute` by
//  `IntentClassifier.classifyQuestionRoute`, and each route delegates to the
//  cheapest backend that can answer it:
//    - .ranking    -> Project table fetch sorted by lastActivityAt
//    - .trends     -> last 14 DailyBriefs + index article + topic frequencies
//    - .timeRange  -> date-windowed Note + matching DailyBriefs
//    - .entity     -> compiled KnowledgeArticle full body + recent linked notes
//    - .semantic   -> existing vector search + keyword merge (the only route
//                     that pays for query embedding + vector search cost)
//

import Foundation

struct RAGResponse {
    let answer: String
    let sourceNotes: [Note]
    let suggestedFollowUps: [String]
    let route: QuestionRoute
}

@Observable
class RAGService {
    static let shared = RAGService()

    enum RAGError: LocalizedError {
        case noAPIKey
        case apiError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not configured"
            case .apiError(let message):
                return "RAG API Error: \(message)"
            case .invalidResponse:
                return "Invalid RAG response"
            }
        }
    }

    // MARK: - Public Entry Point

    /// Dispatch the question to the cheapest backend that can answer it.
    /// `projects` and `dailyBriefs` are needed for the ranking / trends / time-range
    /// routes; callers should `@Query` them and pass through.
    func answerQuestion(
        query: String,
        allNotes: [Note],
        articles: [KnowledgeArticle] = [],
        projects: [Project] = [],
        dailyBriefs: [DailyBrief] = []
    ) async throws -> RAGResponse {
        let articleNames = articles.flatMap { [$0.name] + $0.aliases }
        let route = try await IntentClassifier.shared.classifyQuestionRoute(
            query: query,
            articleNames: articleNames
        )

        switch route {
        case .ranking:
            return try await answerRanking(query: query, projects: projects, articles: articles)
        case .trends:
            return try await answerTrends(query: query, dailyBriefs: dailyBriefs, articles: articles)
        case .timeRange(let interval):
            return try await answerTimeRange(query: query, interval: interval,
                                             allNotes: allNotes, dailyBriefs: dailyBriefs)
        case .entity(let name):
            return try await answerEntity(query: query, articleName: name,
                                          articles: articles, allNotes: allNotes)
        case .semantic:
            return try await answerSemantic(query: query, allNotes: allNotes, articles: articles)
        }
    }

    // MARK: - Route: ranking ("top N projects/people/topics")

    private func answerRanking(
        query: String,
        projects: [Project],
        articles: [KnowledgeArticle]
    ) async throws -> RAGResponse {
        let topProjects = projects
            .filter { !$0.isArchived }
            .sorted { (a, b) -> Bool in
                let aDate = a.lastActivityAt ?? .distantPast
                let bDate = b.lastActivityAt ?? .distantPast
                if aDate == bDate { return a.noteCount > b.noteCount }
                return aDate > bDate
            }
            .prefix(10)

        // Brand-new user with no projects -> fall through to semantic
        if topProjects.isEmpty {
            return try await answerSemantic(query: query, allNotes: [], articles: articles)
        }

        let rows = topProjects.enumerated().map { idx, p -> String in
            let daysStr = p.daysSinceActivity == Int.max ? "never" : "\(p.daysSinceActivity)d ago"
            let stalled = p.isStalled ? " [stalled]" : ""
            return "\(idx + 1). \(p.name) — \(p.noteCount) notes, \(p.openActionCount) open actions, last activity \(daysStr)\(stalled)"
        }.joined(separator: "\n")

        let systemPrompt = """
        \(ContextAssembler.flatPrefix(for: .rag))You are EEON, the user's memory assistant. Answer concisely. Cite sources inline using [Project: name]. End with exactly 2-3 lines prefixed "FOLLOWUP: ". No emojis. If the supplied context is insufficient, say so plainly — do not speculate.
        The PROJECT TABLE below is the authoritative ranking. Do not invent projects not listed.

        --- PROJECT TABLE (top 10 by recent activity) ---

        \(rows)
        """

        let raw = try await callLLM(systemPrompt: systemPrompt, userPrompt: query, maxTokens: 500)
        let (answer, followUps) = parseAnswerAndFollowUps(raw)
        let defaults = followUps.isEmpty ? [
            "Which project should I prioritize?",
            "What are the stalled projects?",
            "Show me the most recent activity"
        ] : followUps

        return RAGResponse(
            answer: answer,
            sourceNotes: [],
            suggestedFollowUps: defaults,
            route: .ranking
        )
    }

    // MARK: - Route: trends (corpus-wide patterns)

    private func answerTrends(
        query: String,
        dailyBriefs: [DailyBrief],
        articles: [KnowledgeArticle]
    ) async throws -> RAGResponse {
        let recentBriefs = dailyBriefs
            .sorted { $0.briefDate > $1.briefDate }
            .prefix(14)

        // If we have no daily briefs yet, fall back to semantic over notes
        guard !recentBriefs.isEmpty else {
            return try await answerSemantic(query: query, allNotes: [], articles: articles)
        }

        let briefBlocks = recentBriefs.map { brief -> String in
            let dateStr = brief.briefDate.formatted(date: .abbreviated, time: .omitted)
            var text = "[Brief: \(dateStr)] \(brief.whatMattersToday)"
            if !brief.highlights.isEmpty {
                text += "\n  Highlights: " + brief.highlights.prefix(3).joined(separator: "; ")
            }
            if !brief.changes.isEmpty {
                text += "\n  Changes: " + brief.changes.prefix(3)
                    .map { "\($0.changeType.rawValue): \($0.content)" }
                    .joined(separator: "; ")
            }
            text += "\n  Momentum: \(brief.momentumDirection)"
            return text
        }.joined(separator: "\n\n")

        let indexArticle = articles.first { $0.articleType == .index }
        let indexBlock: String = {
            guard let idx = indexArticle, !idx.summary.isEmpty else { return "" }
            return "\n\n--- KNOWLEDGE INDEX ---\n\(idx.summary)"
        }()

        let systemPrompt = """
        \(ContextAssembler.flatPrefix(for: .rag))You are EEON, the user's memory assistant. Answer concisely. Cite sources inline using [Brief: date] or [Article: name]. End with exactly 2-3 lines prefixed "FOLLOWUP: ". No emojis. If the supplied context is insufficient, say so plainly — do not speculate.
        The DAILY BRIEFS below are AI-summarized snapshots. Identify recurring themes, momentum shifts, and 2-3 specific patterns. Quote brief dates as evidence.

        --- DAILY BRIEFS (last 14 days, newest first) ---

        \(briefBlocks)\(indexBlock)
        """

        let raw = try await callLLM(systemPrompt: systemPrompt, userPrompt: query, maxTokens: 700)
        let (answer, followUps) = parseAnswerAndFollowUps(raw)
        let defaults = followUps.isEmpty ? [
            "What changed in the last week?",
            "What topics am I avoiding?",
            "Show me the strongest momentum shift"
        ] : followUps

        return RAGResponse(
            answer: answer,
            sourceNotes: [],
            suggestedFollowUps: defaults,
            route: .trends
        )
    }

    // MARK: - Route: timeRange ("last week", "in April", etc.)

    private func answerTimeRange(
        query: String,
        interval: DateInterval,
        allNotes: [Note],
        dailyBriefs: [DailyBrief]
    ) async throws -> RAGResponse {
        let notesInRange = allNotes
            .filter { interval.contains($0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)

        let briefsInRange = dailyBriefs
            .filter { interval.contains($0.briefDate) }
            .sorted { $0.briefDate > $1.briefDate }
            .prefix(7)

        if notesInRange.isEmpty && briefsInRange.isEmpty {
            let startStr = interval.start.formatted(date: .abbreviated, time: .omitted)
            let endStr = interval.end.formatted(date: .abbreviated, time: .omitted)
            return RAGResponse(
                answer: "No notes or briefs found in the requested time window (\(startStr) – \(endStr)).",
                sourceNotes: [],
                suggestedFollowUps: [
                    "What about the last 30 days?",
                    "Show me my most recent notes",
                    "Try a different time window"
                ],
                route: .timeRange(interval)
            )
        }

        let notesBlock = notesInRange.enumerated().map { idx, note in
            let text = !note.content.isEmpty ? note.content : (note.transcript ?? "")
            let excerpt = text.count > 300 ? String(text.prefix(300)) + "..." : text
            let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
            return "[Note \(idx + 1): \"\(note.displayTitle)\", \(dateStr)]\n\(excerpt)"
        }.joined(separator: "\n\n")

        let briefsBlock = briefsInRange.map { brief -> String in
            let dateStr = brief.briefDate.formatted(date: .abbreviated, time: .omitted)
            return "[Brief: \(dateStr)] \(brief.whatMattersToday) — momentum: \(brief.momentumDirection)"
        }.joined(separator: "\n")

        let windowDesc = "\(interval.start.formatted(date: .abbreviated, time: .omitted)) to \(interval.end.formatted(date: .abbreviated, time: .omitted))"

        let systemPrompt = """
        \(ContextAssembler.flatPrefix(for: .rag))You are EEON, the user's memory assistant. Answer concisely. Cite sources inline using [Note: title] or [Brief: date]. End with exactly 2-3 lines prefixed "FOLLOWUP: ". No emojis. If the supplied context is insufficient, say so plainly — do not speculate.
        Only reference notes and briefs inside the time window (\(windowDesc)). If the window has no data, say so.

        --- DAILY BRIEFS IN WINDOW ---

        \(briefsBlock.isEmpty ? "(none)" : briefsBlock)

        --- NOTES IN WINDOW (most recent first) ---

        \(notesBlock.isEmpty ? "(none)" : notesBlock)
        """

        let raw = try await callLLM(systemPrompt: systemPrompt, userPrompt: query, maxTokens: 700)
        let (answer, followUps) = parseAnswerAndFollowUps(raw)
        let defaults = followUps.isEmpty ? [
            "What were the biggest decisions in this window?",
            "Who came up most often?",
            "What's still unresolved?"
        ] : followUps

        return RAGResponse(
            answer: answer,
            sourceNotes: Array(notesInRange),
            suggestedFollowUps: defaults,
            route: .timeRange(interval)
        )
    }

    // MARK: - Route: entity (specific Person/Project/Topic article)

    private func answerEntity(
        query: String,
        articleName: String?,
        articles: [KnowledgeArticle],
        allNotes: [Note]
    ) async throws -> RAGResponse {
        let queryLower = query.lowercased()
        let matchedArticles: [KnowledgeArticle] = {
            if let name = articleName {
                return articles.filter {
                    $0.name.lowercased() == name.lowercased() ||
                    $0.aliases.contains(name.lowercased())
                }
            }
            return articles.filter { article in
                !article.summary.isEmpty && (
                    queryLower.contains(article.name.lowercased()) ||
                    article.name.lowercased().contains(queryLower) ||
                    article.aliases.contains { queryLower.contains($0) }
                )
            }
        }()

        guard !matchedArticles.isEmpty else {
            return try await answerSemantic(query: query, allNotes: allNotes, articles: articles)
        }

        let topMatches = Array(matchedArticles.prefix(3))

        var linkedNoteIdsSet = Set<UUID>()
        for article in topMatches {
            for id in article.linkedNoteIds.prefix(5) {
                linkedNoteIdsSet.insert(id)
            }
        }
        let linkedNotes = Array(allNotes
            .filter { linkedNoteIdsSet.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5))

        let articleBlocks = topMatches.map { article -> String in
            var text = "[\(article.articleType.label): \(article.name)]\nSUMMARY: \(article.summary)"
            if !article.openThreads.isEmpty {
                text += "\nOPEN THREADS: " + article.openThreads.map { $0.thread }.joined(separator: "; ")
            }
            if !article.decisions.isEmpty {
                text += "\nDECISIONS: " + article.decisions.prefix(5).map { $0.decision }.joined(separator: " | ")
            }
            if let arc = article.sentimentArc, !arc.isEmpty {
                text += "\nSENTIMENT: \(arc)"
            }
            return text
        }.joined(separator: "\n\n")

        let notesBlock = linkedNotes.enumerated().map { idx, note in
            let text = !note.content.isEmpty ? note.content : (note.transcript ?? "")
            let excerpt = text.count > 400 ? String(text.prefix(400)) + "..." : text
            let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
            return "[Note \(idx + 1): \"\(note.displayTitle)\", \(dateStr)]\n\(excerpt)"
        }.joined(separator: "\n\n")

        let systemPrompt = """
        \(ContextAssembler.flatPrefix(for: .rag))You are EEON, the user's memory assistant. Answer concisely. Cite sources inline using [Note: title] or [Article: name]. End with exactly 2-3 lines prefixed "FOLLOWUP: ". No emojis. If the supplied context is insufficient, say so plainly — do not speculate.
        The COMPILED ARTICLE is the source of truth for this entity. Notes are supporting evidence only.

        --- COMPILED ARTICLES ---

        \(articleBlocks)

        --- LINKED NOTES (most recent) ---

        \(notesBlock.isEmpty ? "(none)" : notesBlock)
        """

        let raw = try await callLLM(systemPrompt: systemPrompt, userPrompt: query, maxTokens: 600)
        let (answer, followUps) = parseAnswerAndFollowUps(raw)
        let defaults = followUps.isEmpty ? [
            "What's the latest on this?",
            "What decisions are pending?",
            "Who else is involved?"
        ] : followUps

        return RAGResponse(
            answer: answer,
            sourceNotes: linkedNotes,
            suggestedFollowUps: defaults,
            route: .entity(topMatches.first?.name)
        )
    }

    // MARK: - Route: semantic (default vector-search RAG over notes)

    /// Original RAG pipeline. Preserved verbatim from the pre-router implementation so
    /// any question that doesn't match a specialized route still gets today's behavior.
    private func answerSemantic(
        query: String,
        allNotes: [Note],
        articles: [KnowledgeArticle]
    ) async throws -> RAGResponse {
        guard let _ = APIKeys.openAI else { throw RAGError.noAPIKey }

        // Step 1: Generate embedding for the query
        let queryEmbedding = try await EmbeddingService.shared.generateEmbedding(for: query)

        // Step 2: Semantic search — top 10 by cosine similarity
        let semanticResults = VectorSearchService.shared.search(query: queryEmbedding, notes: allNotes, topK: 10)
        let semanticNotes = semanticResults.map { $0.0 }

        // Step 3: Keyword search on titles + transcripts
        let queryTerms = query.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 2 }
        let keywordNotes = allNotes.filter { note in
            let searchText = "\(note.title) \(note.content) \(note.transcript ?? "")".lowercased()
            return queryTerms.contains { searchText.contains($0) }
        }

        // Step 4: Merge and deduplicate, preserving semantic ranking
        var seenIds = Set<UUID>()
        var mergedNotes: [Note] = []
        for note in semanticNotes {
            if seenIds.insert(note.id).inserted { mergedNotes.append(note) }
        }
        for note in keywordNotes {
            if seenIds.insert(note.id).inserted { mergedNotes.append(note) }
        }
        let contextNotes = Array(mergedNotes.prefix(10))

        // Step 4.5: Build knowledge index for LLM context
        let nonEmptyArticles = articles.filter { !$0.summary.isEmpty }
        let knowledgeIndex: String
        if !nonEmptyArticles.isEmpty {
            let indexLines = nonEmptyArticles
                .sorted { $0.mentionCount > $1.mentionCount }
                .prefix(50)
                .map { "[\($0.articleType.label)] \($0.name) — \(String($0.summary.prefix(80))), \($0.mentionCount) mentions" }
            knowledgeIndex = "\n\n--- KNOWLEDGE INDEX ---\n" + indexLines.joined(separator: "\n")
        } else {
            knowledgeIndex = ""
        }

        // Step 4.6: Find relevant knowledge articles by name/summary match
        let queryLower = query.lowercased()
        let relevantArticles = articles.filter { article in
            !article.summary.isEmpty && (
                queryLower.contains(article.name.lowercased()) ||
                article.name.lowercased().contains(queryLower) ||
                article.aliases.contains { queryLower.contains($0) }
            )
        }.prefix(3)

        let articleContext: String
        if !relevantArticles.isEmpty {
            articleContext = "\n\n--- COMPILED KNOWLEDGE ---\n\n" + relevantArticles.map { article in
                var text = "[\(article.articleType.label): \(article.name)]\n\(article.summary)"
                if !article.openThreads.isEmpty {
                    text += "\nOpen threads: " + article.openThreads.map { $0.thread }.joined(separator: "; ")
                }
                if let arc = article.sentimentArc, !arc.isEmpty {
                    text += "\nSentiment: \(arc)"
                }
                return text
            }.joined(separator: "\n\n")
        } else {
            articleContext = ""
        }

        // Step 5: Build context string from notes
        let notesContext = contextNotes.enumerated().map { index, note in
            let text = !note.content.isEmpty ? note.content : (note.transcript ?? "")
            let excerpt = text.count > 500 ? String(text.prefix(500)) + "..." : text
            let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
            return """
            [Note \(index + 1): "\(note.displayTitle)", \(dateStr)]
            \(excerpt)
            """
        }.joined(separator: "\n\n")

        // Step 6: Call GPT-4o-mini with RAG context
        let systemPrompt = """
        \(ContextAssembler.flatPrefix(for: .rag))You are EEON, an AI memory assistant. Answer the user's question based on their compiled knowledge and notes below.
        Prefer compiled knowledge articles when available — they contain synthesized, up-to-date information.
        Always cite which note(s) or article(s) your answer comes from.
        If you can't find relevant information, say so honestly.
        After answering, provide exactly 2-3 follow-up questions on new lines prefixed with "FOLLOWUP: ".
        Do not use emojis.
        \(knowledgeIndex)
        \(articleContext)

        --- USER'S NOTES ---

        \(notesContext)
        """

        let raw = try await callLLM(systemPrompt: systemPrompt, userPrompt: query, maxTokens: 2000, temperature: 0.7)
        let (answer, followUps) = parseAnswerAndFollowUps(raw)

        // Match cited notes back to Note objects by checking displayTitle in the answer
        let citedNotes = contextNotes.filter { answer.contains($0.displayTitle) }
        let sourceNotes = citedNotes.isEmpty ? Array(contextNotes.prefix(3)) : citedNotes
        let defaults = followUps.isEmpty ? [
            "Tell me more about this",
            "What decisions relate to this?",
            "What should I do next?"
        ] : followUps

        return RAGResponse(
            answer: answer,
            sourceNotes: sourceNotes,
            suggestedFollowUps: defaults,
            route: .semantic
        )
    }

    // MARK: - Shared LLM call helper

    /// Single point where the OpenAI completion is issued. Day 4 will add a sibling
    /// `streamCompletion(...)` here that returns an `AsyncThrowingStream<String, Error>`.
    private func callLLM(
        systemPrompt: String,
        userPrompt: String,
        model: String = "gpt-4o-mini",
        maxTokens: Int = 800,
        temperature: Double = 0.5
    ) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw RAGError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RAGError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RAGError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        struct APIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "I couldn't generate a response."
    }

    /// Pull `FOLLOWUP:`-prefixed lines out of an LLM response, returning the cleaned
    /// answer body and the parsed follow-up suggestions in order.
    private func parseAnswerAndFollowUps(_ raw: String) -> (answer: String, followUps: [String]) {
        let lines = raw.components(separatedBy: "\n")
        var answerLines: [String] = []
        var followUps: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("FOLLOWUP:") {
                let followUp = trimmed
                    .replacingOccurrences(of: "FOLLOWUP:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !followUp.isEmpty {
                    followUps.append(followUp)
                }
            } else {
                answerLines.append(line)
            }
        }
        let answerText = answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (answerText, followUps)
    }
}
