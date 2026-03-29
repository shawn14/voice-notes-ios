//
//  VectorSearchService.swift
//  voice notes
//
//  Performs cosine similarity search across note embeddings using Accelerate/vDSP.
//

import Foundation
import Accelerate

@Observable
class VectorSearchService {
    static let shared = VectorSearchService()

    /// Search notes by cosine similarity to the query embedding.
    /// Returns top-K notes sorted by similarity score (highest first).
    /// Notes with nil embeddings are skipped.
    func search(query: [Float], notes: [Note], topK: Int = 10) -> [(Note, Float)] {
        guard !query.isEmpty else { return [] }

        var results: [(Note, Float)] = []

        for note in notes {
            guard let data = note.embeddingData else { continue }

            // Reconstruct Float array from Data
            let embedding = data.withUnsafeBytes { buffer -> [Float] in
                guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                    return []
                }
                return Array(UnsafeBufferPointer(start: pointer, count: data.count / MemoryLayout<Float>.size))
            }

            guard embedding.count == query.count else { continue }

            let similarity = cosineSimilarity(query, embedding)
            results.append((note, similarity))
        }

        // Sort by similarity descending, take top K
        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }

    /// Compute cosine similarity between two vectors using vDSP for performance.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
