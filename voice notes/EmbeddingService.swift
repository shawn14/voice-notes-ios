//
//  EmbeddingService.swift
//  voice notes
//
//  Generates text embeddings via OpenAI text-embedding-3-small for semantic search.
//

import Foundation

@Observable
class EmbeddingService {
    static let shared = EmbeddingService()

    private let model = "text-embedding-3-small"
    private let embeddingDimension = 1536

    enum EmbeddingError: LocalizedError {
        case apiError(String)
        case noAPIKey
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .apiError(let message):
                return "Embedding API Error: \(message)"
            case .noAPIKey:
                return "OpenAI API key not configured"
            case .invalidResponse:
                return "Invalid embedding response"
            }
        }
    }

    /// Generate an embedding vector for the given text using OpenAI text-embedding-3-small.
    /// Returns a 1536-dimensional Float array.
    func generateEmbedding(for text: String) async throws -> [Float] {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw EmbeddingError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/embeddings")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Truncate to ~8000 tokens worth of text (roughly 32000 chars) to stay within model limits
        let truncatedText = text.count > 32000 ? String(text.prefix(32000)) : text

        let body: [String: Any] = [
            "model": model,
            "input": truncatedText
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EmbeddingError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let embedding = first["embedding"] as? [Double] else {
            throw EmbeddingError.invalidResponse
        }

        // Convert Double array to Float array for compact storage
        return embedding.map { Float($0) }
    }

    /// Generate an embedding and store it on the note. Fails silently — embedding is optional.
    func generateAndStoreEmbedding(for note: Note) async {
        let textToEmbed = !note.content.isEmpty ? note.content : (note.transcript ?? "")
        guard !textToEmbed.isEmpty else { return }

        do {
            let embedding = try await generateEmbedding(for: textToEmbed)
            let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            await MainActor.run {
                note.embeddingData = data
            }
        } catch {
            // Embedding failure should not affect note save — log and move on
            print("[EmbeddingService] Failed to generate embedding: \(error.localizedDescription)")
        }
    }
}
