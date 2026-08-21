//
//  QuizService.swift
//  voice notes
//
//  Turns a note into practice questions (2026-08-20).
//
//  The School Notes transform already ends with "2-3 review questions", but
//  they render as static text at the bottom of a note — you read the question
//  with the answer sitting right above it, which is recognition, not recall.
//  Pocket's student mode gives you flashcards you actually work through.
//  This generates that: discrete question/answer pairs, stored on the note so
//  a quiz costs one API call ever, not one per attempt.
//

import Foundation

/// One practice question. `id` is persisted so per-question progress (got it /
/// missed) survives a re-render of the quiz view.
struct QuizQuestion: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var question: String
    var answer: String
}

enum QuizError: LocalizedError {
    case noAPIKey
    case tooShort
    case apiError(String)
    case parsingError
    case empty

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured."
        case .tooShort:
            return "This note is too short to make a quiz from."
        case .apiError(let message):
            return message
        case .parsingError:
            return "Couldn't read the quiz that came back."
        case .empty:
            return "Couldn't find anything quizzable in this note."
        }
    }
}

enum QuizService {

    /// Notes shorter than this can't support recall questions worth asking —
    /// a grocery list quizzed back at you is noise, not study.
    static let minimumCharacters = 120

    /// The model is told to quiz ONLY on what the note contains. A quiz that
    /// invents plausible-sounding facts is worse than no quiz: the user is
    /// memorising, so a hallucinated answer gets learned as true.
    private static let systemPrompt = """
    You write practice questions that help someone remember their own notes.

    Rules:
    - Ask ONLY about information actually present in the note. Never introduce
      outside facts, and never ask about something the note does not answer.
    - Each answer must be findable in the note. Keep answers to 1-2 sentences.
    - Prefer questions that require recall ("What are the three stages of...")
      over yes/no or ones whose answer is contained in the question.
    - Write 4-8 questions depending on how much substance the note has. Fewer
      good questions beats padding.
    - Vary what you probe: definitions, relationships, sequences, figures,
      names, and why-something-matters.
    - Use the note's own vocabulary so the answers feel like the user's words.

    Return ONLY JSON in this exact shape:
    {"questions":[{"question":"...","answer":"..."}]}
    """

    private struct QuizPayload: Codable {
        struct Item: Codable {
            let question: String
            let answer: String
        }
        let questions: [Item]
    }

    /// Generate questions from a note's text. The caller persists the result on
    /// the note; this does no storage of its own.
    static func generateQuiz(for text: String, apiKey: String) async throws -> [QuizQuestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { throw QuizError.tooShort }
        guard !apiKey.isEmpty else { throw QuizError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": String(trimmed.prefix(6000))]
            ],
            // Guarantees parseable JSON, so a stray "Here you go:" preamble
            // can't break the decode the way it can for the older call sites.
            "response_format": ["type": "json_object"],
            "temperature": 0.4,
            "max_tokens": 1200
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QuizError.apiError(message)
        }

        let result = try JSONDecoder().decode(SummaryChatResponse.self, from: data)
        guard let content = result.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw QuizError.parsingError
        }

        let payload: QuizPayload
        do {
            payload = try JSONDecoder().decode(QuizPayload.self, from: jsonData)
        } catch {
            throw QuizError.parsingError
        }

        let questions = payload.questions
            .map { QuizQuestion(question: $0.question.trimmed, answer: $0.answer.trimmed) }
            .filter { !$0.question.isEmpty && !$0.answer.isEmpty }

        guard !questions.isEmpty else { throw QuizError.empty }
        return questions
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
