//
//  TagExtractor.swift
//  voice notes
//

import Foundation

actor TagExtractor {
    private let apiKey: String

    enum ExtractionError: LocalizedError {
        case apiError(String)
        case networkError(Error)
        case parsingError

        var errorDescription: String? {
            switch self {
            case .apiError(let message):
                return "API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            case .parsingError:
                return "Could not parse tags from response"
            }
        }
    }

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func extractTags(from text: String) async throws -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // For longer transcripts, sample beginning, middle, and end
        let textToAnalyze: String
        if text.count > 4000 {
            let start = String(text.prefix(1500))
            let middleStart = text.index(text.startIndex, offsetBy: text.count / 2 - 500)
            let middleEnd = text.index(text.startIndex, offsetBy: text.count / 2 + 500)
            let middle = String(text[middleStart..<middleEnd])
            let end = String(text.suffix(1500))
            textToAnalyze = "\(start)\n...\n\(middle)\n...\n\(end)"
        } else {
            textToAnalyze = text
        }

        let prompt = """
        Analyze the following text and extract 3-5 relevant topic tags.
        Return ONLY a JSON array of lowercase tag strings, no explanation.
        Tags should be single words or short phrases (2-3 words max).
        Focus on the main topics, people, places, and action items mentioned.
        Example output: ["meeting", "project update", "q4 goals"]

        Text to analyze:
        \(textToAnalyze)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 100
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtractionError.parsingError
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ExtractionError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw ExtractionError.parsingError
        }

        // Parse the JSON array from the response
        guard let jsonData = content.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: jsonData) else {
            // Try to extract tags even if not perfect JSON
            return parseTagsFallback(from: content)
        }

        return tags
    }

    private func parseTagsFallback(from content: String) -> [String] {
        // Simple fallback parser for imperfect JSON
        let cleaned = content
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\"", with: "")

        return cleaned
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated struct ChatCompletionResponse: Codable, Sendable {
    let choices: [Choice]

    struct Choice: Codable, Sendable {
        let message: Message
    }

    struct Message: Codable, Sendable {
        let content: String
    }
}
