//
//  TranscriptionService.swift
//  voice notes
//

import Foundation

actor TranscriptionService {
    private let apiKey: String

    enum TranscriptionError: LocalizedError {
        case invalidURL
        case invalidAudioFile
        case apiError(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .invalidAudioFile:
                return "Could not read audio file"
            case .apiError(let message):
                return "API Error: \(message)"
            case .networkError(let error):
                return "Network Error: \(error.localizedDescription)"
            }
        }
    }

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioURL: URL) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError.invalidAudioFile
        }

        // Check file size - Whisper has 25MB limit
        // For larger files, we'd need to chunk them
        let fileSizeMB = Double(audioData.count) / (1024 * 1024)
        if fileSizeMB > 25 {
            return try await transcribeLargeFile(audioURL: audioURL)
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidURL
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }

    private func transcribeLargeFile(audioURL: URL) async throws -> String {
        // For files larger than 25MB, we need to split them
        // This is a simplified version - production would use AVAssetExportSession
        // to properly split audio files into chunks

        // For now, throw an error suggesting the user record shorter clips
        throw TranscriptionError.apiError("Audio file too large. Please record shorter segments (under 25MB).")
    }
}

nonisolated struct TranscriptionResponse: Codable, Sendable {
    let text: String
}
