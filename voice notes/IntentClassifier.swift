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
}
