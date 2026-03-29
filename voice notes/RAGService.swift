//
//  RAGService.swift
//  voice notes
//
//  Retrieval-Augmented Generation pipeline for answering questions about past notes.
//

import Foundation

struct RAGResponse {
    let answer: String
    let sourceNotes: [Note]
    let suggestedFollowUps: [String]
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

    /// Answer a question using RAG over the user's notes.
    /// Pipeline: embed query -> vector search -> keyword search -> merge -> GPT answer with citations.
    func answerQuestion(query: String, allNotes: [Note]) async throws -> RAGResponse {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw RAGError.noAPIKey
        }

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
            if seenIds.insert(note.id).inserted {
                mergedNotes.append(note)
            }
        }
        for note in keywordNotes {
            if seenIds.insert(note.id).inserted {
                mergedNotes.append(note)
            }
        }

        // Take top 10 after merge
        let contextNotes = Array(mergedNotes.prefix(10))

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
        \(AuthService.shared.eeonContextPrefix)You are EEON, an AI memory assistant. Answer the user's question based on their notes below.
        Always cite which note(s) your answer comes from using [Note: title, date].
        If you can't find relevant information, say so honestly.
        After answering, provide exactly 2-3 follow-up questions on new lines prefixed with "FOLLOWUP: ".
        Do not use emojis.

        --- USER'S NOTES ---

        \(notesContext)
        """

        let apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": query]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let rawResponse = decoded.choices.first?.message.content ?? "I couldn't generate a response."

        // Step 7: Parse follow-ups and answer
        let lines = rawResponse.components(separatedBy: "\n")
        var answerLines: [String] = []
        var followUps: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("FOLLOWUP:") {
                let followUp = trimmed.replacingOccurrences(of: "FOLLOWUP:", with: "").trimmingCharacters(in: .whitespaces)
                if !followUp.isEmpty {
                    followUps.append(followUp)
                }
            } else {
                answerLines.append(line)
            }
        }

        let answerText = answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Match cited notes back to Note objects by checking if displayTitle appears in the answer
        let citedNotes = contextNotes.filter { note in
            answerText.contains(note.displayTitle)
        }
        let sourceNotes = citedNotes.isEmpty ? Array(contextNotes.prefix(3)) : citedNotes

        // Default follow-ups if none were parsed
        if followUps.isEmpty {
            followUps = [
                "Tell me more about this",
                "What decisions relate to this?",
                "What should I do next?"
            ]
        }

        return RAGResponse(
            answer: answerText,
            sourceNotes: sourceNotes,
            suggestedFollowUps: followUps
        )
    }
}
