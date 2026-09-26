//
//  SpeakerDiarizationService.swift
//  voice notes
//
//  "Identify Speakers" on a saved recording (2026-09-25). OpenAI's
//  gpt-4o-transcribe-diarize separates speakers well but accepts no prompt,
//  so it misspells the names and jargon TranscriptionVocabulary teaches
//  Whisper (live test: "Hi Mark" → "Piemark", "paywall" → "pay roll").
//  We therefore keep Whisper's words and only borrow the speaker turns:
//  SpeakerAttribution aligns the two word streams and writes
//  "Speaker A: …" paragraphs, which SpeakerLabelDetector and the Speakers
//  editor already understand.
//
//  Verified against the live API 2026-09-25:
//  - response_format=diarized_json → segments[{speaker:"A", text, start, end}]
//  - hard limit 1400 s per request ("audio duration … is longer than 1400
//    seconds which is the maximum for this model"), so long recordings are
//    chunked
//  - known_speaker_names[] + known_speaker_references[] (data:audio/mp4;base64
//    clips cut from the same recording) make the model return those names,
//    which keeps "Speaker A" the same person across chunks
//

import Foundation
import AVFoundation

nonisolated struct DiarizedSegment: Codable, Hashable {
    var speaker: String
    var text: String
    var start: Double
    var end: Double
}

nonisolated private struct DiarizedResponse: Decodable {
    let segments: [DiarizedSegment]
}

// MARK: - Pure alignment (no I/O — covered by the golden fixture proof)

nonisolated enum SpeakerAttribution {
    /// Sentences longer than this are split at word-level speaker changes
    /// instead of taking one majority speaker (unpunctuated rambles).
    static let longSentenceWords = 40
    /// How far ahead in the diarized stream to look for a matching word.
    static let searchWindow = 12

    /// "A" → "Speaker A"; already-canonical labels pass through.
    static func canonicalLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("speaker") { return trimmed }
        return "Speaker \(trimmed)"
    }

    static func normalize(_ word: Substring) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }

    /// Returns Whisper's transcript re-flowed into "Speaker X: …" paragraphs,
    /// or nil when fewer than two speakers were found (nothing to attribute).
    static func attributedTranscript(transcript: String, segments: [DiarizedSegment]) -> String? {
        let speakers = Set(segments.map { canonicalLabel($0.speaker) })
        guard speakers.count >= 2 else { return nil }

        // Diarized word stream with a speaker per word.
        var diarized: [(word: String, speaker: String)] = []
        for segment in segments {
            let label = canonicalLabel(segment.speaker)
            for token in segment.text.split(whereSeparator: \.isWhitespace) {
                let norm = normalize(token)
                if !norm.isEmpty { diarized.append((norm, label)) }
            }
        }
        let words = transcript.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, !diarized.isEmpty else { return nil }

        // Monotone greedy match: each Whisper word takes the speaker of the
        // next equal diarized word within the window. Unmatched words
        // ("15th" vs "fifteenth") inherit a neighbour's speaker below.
        var assigned: [String?] = Array(repeating: nil, count: words.count)
        var pointer = 0
        var misses = 0
        for (i, word) in words.enumerated() {
            let norm = normalize(word)
            guard !norm.isEmpty else { continue }
            let upper = min(pointer + searchWindow, diarized.count)
            if pointer < upper, let hit = (pointer..<upper).first(where: { diarized[$0].word == norm }) {
                assigned[i] = diarized[hit].speaker
                pointer = hit + 1
                misses = 0
            } else {
                misses += 1
                // Drift guard: after a run of misses, re-anchor near the
                // proportional position so one divergent passage can't
                // strand the pointer for the rest of the recording.
                if misses >= searchWindow {
                    let proportional = Int(Double(i) / Double(words.count) * Double(diarized.count))
                    pointer = min(max(pointer, proportional - searchWindow / 2), diarized.count)
                    misses = 0
                }
            }
        }
        // Fill gaps: forward from the previous speaker, leading gap from the first known.
        let firstKnown = assigned.compactMap { $0 }.first ?? speakers.sorted().first!
        var last = firstKnown
        let perWord: [String] = assigned.map { speaker in
            if let speaker { last = speaker }
            return last
        }

        // Group into sentences, give each its majority speaker, then merge runs.
        var runs: [(speaker: String, words: [Substring])] = []
        func append(_ speaker: String, _ chunk: [Substring]) {
            guard !chunk.isEmpty else { return }
            if let lastRun = runs.last, lastRun.speaker == speaker {
                runs[runs.count - 1].words += chunk
            } else {
                runs.append((speaker, chunk))
            }
        }

        var start = 0
        for (i, word) in words.enumerated() {
            let endsSentence = word.last.map { ".?!…".contains($0) } ?? false
            guard endsSentence || i == words.count - 1 else { continue }
            let range = start...i
            let sentence = Array(words[range])
            let owners = Array(perWord[range])
            if sentence.count > longSentenceWords {
                var runStart = 0
                for j in 1...owners.count where j == owners.count || owners[j] != owners[runStart] {
                    append(owners[runStart], Array(sentence[runStart..<j]))
                    runStart = j
                }
            } else {
                append(majority(owners), sentence)
            }
            start = i + 1
        }

        return runs
            .map { "\($0.speaker): \($0.words.joined(separator: " "))" }
            .joined(separator: "\n\n")
    }

    /// Most frequent speaker; ties go to whoever spoke first in the sentence.
    static func majority(_ owners: [String]) -> String {
        var counts: [String: Int] = [:]
        for owner in owners { counts[owner, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        return owners.first { counts[$0] == best } ?? owners[0]
    }

}

/// Main-actor side (default isolation): SpeakerLabel is a main-actor type.
extension SpeakerAttribution {
    /// Swap line-leading markers for the names the user gave them, for display.
    static func displayTranscript(_ transcript: String, labels: [SpeakerLabel]) -> String {
        let named = labels.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !named.isEmpty else { return transcript }
        return transcript
            .components(separatedBy: "\n")
            .map { line in
                for label in named where line.hasPrefix(label.marker + ":") {
                    return label.displayName + line.dropFirst(label.marker.count)
                }
                return line
            }
            .joined(separator: "\n")
    }
}

// MARK: - API

nonisolated enum SpeakerDiarizationService {
    enum DiarizationError: LocalizedError {
        case invalidAudio
        case singleSpeaker
        case api(String)

        var errorDescription: String? {
            switch self {
            case .invalidAudio: return "Couldn't read this recording's audio."
            case .singleSpeaker: return "EEON only heard one speaker in this recording."
            case .api(let message): return message
            }
        }
    }

    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    /// Live-verified model cap is 1400 s; stay under it with margin.
    static let maxRequestSeconds: Double = 1380
    static let chunkSeconds: Double = 1200
    static let maxUploadBytes = 24 * 1024 * 1024
    /// API accepts at most four reference speakers, each 2–10 s.
    static let maxReferences = 4

    /// Diarize the recording and return Whisper's transcript re-flowed by speaker.
    static func attribute(audioURL: URL, transcript: String, apiKey: String) async throws -> String {
        let segments = try await diarize(audioURL: audioURL, apiKey: apiKey)
        guard let result = SpeakerAttribution.attributedTranscript(transcript: transcript, segments: segments) else {
            throw DiarizationError.singleSpeaker
        }
        return result
    }

    static func diarize(audioURL: URL, apiKey: String) async throws -> [DiarizedSegment] {
        guard let duration = try? await AVURLAsset(url: audioURL).load(.duration) else {
            throw DiarizationError.invalidAudio
        }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { throw DiarizationError.invalidAudio }

        let size = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        let directlyUploadable = ["m4a", "mp3", "mp4", "wav", "webm", "ogg", "flac"]
            .contains(audioURL.pathExtension.lowercased())
        if seconds <= maxRequestSeconds, size <= maxUploadBytes, directlyUploadable {
            return try await request(fileURL: audioURL, apiKey: apiKey, references: [])
        }

        // Chunked: speakers from the first chunk become named references for
        // the rest, so labels stay stable across the whole recording.
        var all: [DiarizedSegment] = []
        var references: [(name: String, dataURL: String)] = []
        var offset: Double = 0
        while offset < seconds {
            let end = min(offset + chunkSeconds, seconds)
            let chunkURL = try await exportClip(from: audioURL, start: offset, end: end)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            var segments = try await request(fileURL: chunkURL, apiKey: apiKey, references: references)
            segments = relabel(segments, known: Set(references.map(\.name)), used: Set(all.map(\.speaker)))
            for index in segments.indices {
                segments[index].start += offset
                segments[index].end += offset
            }
            all += segments

            if references.count < maxReferences {
                references += try await newReferences(
                    for: segments, from: audioURL,
                    excluding: Set(references.map(\.name)),
                    limit: maxReferences - references.count
                )
            }
            offset = end
        }
        return all
    }

    /// Canonicalize labels; a label the model invented in a later chunk ("A")
    /// must not collide with a reference name from an earlier one.
    static func relabel(_ segments: [DiarizedSegment], known: Set<String>, used: Set<String>) -> [DiarizedSegment] {
        var taken = used.union(known)
        var mapping: [String: String] = [:]
        return segments.map { segment in
            var copy = segment
            if known.contains(segment.speaker) { return copy }
            if let mapped = mapping[segment.speaker] {
                copy.speaker = mapped
                return copy
            }
            var candidate = SpeakerAttribution.canonicalLabel(segment.speaker)
            if !known.isEmpty || taken.contains(candidate) {
                let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { "Speaker \($0)" }
                candidate = letters.first { !taken.contains($0) } ?? candidate
            }
            taken.insert(candidate)
            mapping[segment.speaker] = candidate
            copy.speaker = candidate
            return copy
        }
    }

    /// One 2–10 s clip per new speaker, from their longest segment.
    static func newReferences(
        for segments: [DiarizedSegment], from audioURL: URL,
        excluding: Set<String>, limit: Int
    ) async throws -> [(name: String, dataURL: String)] {
        var longest: [String: DiarizedSegment] = [:]
        for segment in segments where !excluding.contains(segment.speaker) {
            if segment.end - segment.start > (longest[segment.speaker].map { $0.end - $0.start } ?? 0) {
                longest[segment.speaker] = segment
            }
        }
        var result: [(String, String)] = []
        for (speaker, segment) in longest.sorted(by: { $0.key < $1.key }).prefix(limit)
        where segment.end - segment.start >= 2 {
            let clip = try await exportClip(from: audioURL, start: segment.start, end: min(segment.end, segment.start + 10))
            defer { try? FileManager.default.removeItem(at: clip) }
            let data = try Data(contentsOf: clip)
            result.append((speaker, "data:audio/mp4;base64,\(data.base64EncodedString())"))
        }
        return result
    }

    static func exportClip(from sourceURL: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw DiarizationError.invalidAudio
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diarize_\(UUID().uuidString).m4a")
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 1000),
            end: CMTime(seconds: end, preferredTimescale: 1000)
        )
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            throw DiarizationError.invalidAudio
        }
        return outputURL
    }

    /// Multipart body for one diarize request. Shared by the foreground
    /// path and BackgroundDiarizationService (which writes it to a file,
    /// because background sessions only upload from files).
    static func multipartBody(
        fileURL: URL, references: [(name: String, dataURL: String)], boundary: String
    ) throws -> Data {
        guard let audio = try? Data(contentsOf: fileURL) else { throw DiarizationError.invalidAudio }
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "gpt-4o-transcribe-diarize")
        field("response_format", "diarized_json")
        field("chunking_strategy", "auto")
        for reference in references {
            field("known_speaker_names[]", reference.name)
            field("known_speaker_references[]", reference.dataURL)
        }
        let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension.lowercased()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func urlRequest(apiKey: String, boundary: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func parseSegments(data: Data, statusCode: Int) throws -> [DiarizedSegment] {
        guard statusCode == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw DiarizationError.api(message ?? "Speaker identification failed. Try again.")
        }
        return try JSONDecoder().decode(DiarizedResponse.self, from: data).segments
    }

    private static func request(
        fileURL: URL, apiKey: String, references: [(name: String, dataURL: String)]
    ) async throws -> [DiarizedSegment] {
        let boundary = UUID().uuidString
        let body = try multipartBody(fileURL: fileURL, references: references, boundary: boundary)
        let (data, response) = try await URLSession.shared.upload(
            for: urlRequest(apiKey: apiKey, boundary: boundary), from: body
        )
        return try parseSegments(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
