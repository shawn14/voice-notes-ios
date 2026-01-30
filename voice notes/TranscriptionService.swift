//
//  TranscriptionService.swift
//  voice notes
//

import Foundation
import AVFoundation

// MARK: - Supported Languages

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto = ""
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"
    case polish = "pl"
    case turkish = "tr"
    case vietnamese = "vi"
    case thai = "th"
    case indonesian = "id"
    case swedish = "sv"
    case danish = "da"
    case norwegian = "no"
    case finnish = "fi"
    case greek = "el"
    case hebrew = "he"
    case czech = "cs"
    case romanian = "ro"
    case hungarian = "hu"
    case ukrainian = "uk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .vietnamese: return "Vietnamese"
        case .thai: return "Thai"
        case .indonesian: return "Indonesian"
        case .swedish: return "Swedish"
        case .danish: return "Danish"
        case .norwegian: return "Norwegian"
        case .finnish: return "Finnish"
        case .greek: return "Greek"
        case .hebrew: return "Hebrew"
        case .czech: return "Czech"
        case .romanian: return "Romanian"
        case .hungarian: return "Hungarian"
        case .ukrainian: return "Ukrainian"
        }
    }
}

// MARK: - Language Settings

class LanguageSettings {
    static let shared = LanguageSettings()

    private let key = "transcriptionLanguage"

    var selectedLanguage: TranscriptionLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let lang = TranscriptionLanguage(rawValue: raw) {
                return lang
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

// MARK: - Transcription Service

actor TranscriptionService {
    private let apiKey: String
    private let language: TranscriptionLanguage

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

    init(apiKey: String, language: TranscriptionLanguage = .auto) {
        self.apiKey = apiKey
        self.language = language
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

        // Add language field (if not auto-detect)
        if language != .auto {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language.rawValue)\r\n".data(using: .utf8)!)
        }

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
        // Split audio into ~10 minute chunks and transcribe each
        let asset = AVURLAsset(url: audioURL)

        guard let duration = try? await asset.load(.duration) else {
            throw TranscriptionError.invalidAudioFile
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        let chunkDuration: Double = 600 // 10 minutes per chunk
        let numberOfChunks = Int(ceil(durationSeconds / chunkDuration))

        var transcripts: [String] = []

        for i in 0..<numberOfChunks {
            let startTime = Double(i) * chunkDuration
            let endTime = min(startTime + chunkDuration, durationSeconds)

            // Export chunk
            let chunkURL = try await exportAudioChunk(
                from: audioURL,
                startTime: startTime,
                endTime: endTime,
                chunkIndex: i
            )

            // Transcribe chunk
            let chunkTranscript = try await transcribeChunk(audioURL: chunkURL)
            transcripts.append(chunkTranscript)

            // Clean up chunk file
            try? FileManager.default.removeItem(at: chunkURL)
        }

        return transcripts.joined(separator: " ")
    }

    private func exportAudioChunk(from sourceURL: URL, startTime: Double, endTime: Double, chunkIndex: Int) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.invalidAudioFile
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_\(chunkIndex)_\(UUID().uuidString).m4a")

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 1000),
            end: CMTime(seconds: endTime, preferredTimescale: 1000)
        )

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw TranscriptionError.apiError("Failed to split audio: \(error.localizedDescription)")
        }

        return outputURL
    }

    private func transcribeChunk(audioURL: URL) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        let audioData = try Data(contentsOf: audioURL)

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language field (if not auto-detect)
        if language != .auto {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language.rawValue)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
}

nonisolated struct TranscriptionResponse: Codable, Sendable {
    let text: String
}
