//
//  TranscriptTimeline.swift
//  voice notes
//
//  Tap a sentence in the Original transcript to hear it.
//
//  Whisper's verbose_json already returns a start/end time for every segment;
//  until now they were used to drop silence hallucinations and then discarded.
//  They are kept here as a small JSON file per recording, in Application
//  Support/`transcript-timelines`, keyed by the audio file name. Deliberately
//  NOT a SwiftData field: audio never leaves the phone, so its timings have no
//  reason to sync, and a new stored field is a CloudKit schema change.
//
//  The stored transcript is not Whisper's text verbatim: filler words are
//  cleaned out, speakers get "Speaker A:" paragraphs, and the user can edit.
//  `TranscriptTimelineAligner` therefore matches word by word and tolerates
//  missing and inserted words; a sentence it cannot place is simply not
//  tappable.
//

import Foundation

nonisolated struct TranscriptTimeline: Codable, Sendable, Equatable {
    nonisolated struct Line: Codable, Sendable, Equatable {
        let start: Double
        let end: Double
        let text: String
    }

    var lines: [Line]
}

nonisolated enum TranscriptTimelineStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("transcript-timelines", isDirectory: true)
    }

    static func fileURL(forAudioFileName audioFileName: String) -> URL {
        directory.appendingPathComponent(audioFileName + ".json")
    }

    static func save(_ lines: [TranscriptTimeline.Line], forAudioFileName audioFileName: String) {
        guard !lines.isEmpty, !audioFileName.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(TranscriptTimeline(lines: lines))
            try data.write(to: fileURL(forAudioFileName: audioFileName), options: .atomic)
        } catch {
            print("[TranscriptTimeline] save failed: \(error.localizedDescription)")
        }
    }

    static func load(forAudioFileName audioFileName: String) -> TranscriptTimeline? {
        guard let data = try? Data(contentsOf: fileURL(forAudioFileName: audioFileName)),
              let timeline = try? JSONDecoder().decode(TranscriptTimeline.self, from: data),
              !timeline.lines.isEmpty else { return nil }
        return timeline
    }

    /// Remove timings whose recording is gone (a purged note, or a throwaway
    /// dictation such as a Tune EEON answer). Run once per launch.
    static func pruneOrphans() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for file in files where file.pathExtension == "json" {
            let audioFileName = file.deletingPathExtension().lastPathComponent
            if !fm.fileExists(atPath: documents.appendingPathComponent(audioFileName).path) {
                try? fm.removeItem(at: file)
            }
        }
    }
}

// MARK: - Alignment

nonisolated enum TranscriptTimelineAligner {
    /// A stretch of the displayed transcript and the audio time it plays at.
    nonisolated struct Span: Sendable, Equatable {
        let range: Range<String.Index>
        let start: Double
        let end: Double
    }

    nonisolated struct Token: Sendable {
        let text: String
        let range: Range<String.Index>
    }

    /// How far ahead in the transcript a spoken word may be found. Covers an
    /// inserted speaker label or a short user edit without letting a common
    /// word ("the") jump the cursor into a later sentence.
    private static let lookahead = 12

    /// Lowercased words with their position. Scripts written without spaces
    /// (Chinese, Japanese, Thai) yield one token per character so they align
    /// too.
    static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var wordStart: String.Index?
        var index = text.startIndex

        func closeWord(at end: String.Index) {
            if let start = wordStart {
                result.append(Token(text: text[start..<end].lowercased(), range: start..<end))
                wordStart = nil
            }
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isLetter || character.isNumber {
                if isUnspacedScript(character) {
                    closeWord(at: index)
                    result.append(Token(text: String(character), range: index..<next))
                } else if wordStart == nil {
                    wordStart = index
                }
            } else if character == "'" || character == "’" {
                // Keep "don't" as one word; a leading quote starts nothing.
            } else {
                closeWord(at: index)
            }
            index = next
        }
        closeWord(at: text.endIndex)
        return result.map { Token(text: $0.text.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: ""), range: $0.range) }
    }

    private static func isUnspacedScript(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0E00...0x0E7F,   // Thai
             0x3040...0x30FF,   // Hiragana, Katakana
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified
             0xF900...0xFAFF:   // CJK compatibility
            return true
        default:
            return false
        }
    }

    /// Place each timed line on the transcript. Spans come back in order and
    /// never overlap.
    static func align(transcript: String, timeline: TranscriptTimeline) -> [Span] {
        let transcriptTokens = tokens(in: transcript)
        guard !transcriptTokens.isEmpty else { return [] }

        var spans: [Span] = []
        var cursor = 0

        for line in timeline.lines {
            let spoken = tokens(in: line.text).map(\.text)
            guard !spoken.isEmpty else { continue }

            var first: Int?
            var last: Int?
            var hits = 0
            var position = cursor

            for (offset, word) in spoken.enumerated() {
                guard position < transcriptTokens.count else { break }
                let limit = min(position + lookahead, transcriptTokens.count)
                var found: Int?
                for candidate in position..<limit where transcriptTokens[candidate].text == word {
                    // Adjacent is always trusted. A jump ahead must be
                    // confirmed by the following word, or it is a coincidence.
                    if candidate == position {
                        found = candidate
                        break
                    }
                    let nextSpoken = offset + 1 < spoken.count ? spoken[offset + 1] : nil
                    let nextWritten = candidate + 1 < transcriptTokens.count ? transcriptTokens[candidate + 1].text : nil
                    if let nextSpoken, nextSpoken == nextWritten {
                        found = candidate
                        break
                    }
                }
                if let found {
                    if first == nil { first = found }
                    last = found
                    hits += 1
                    position = found + 1
                }
            }

            guard let first, let last else { continue }
            // A few stray common words are not a sentence: most of what was
            // said has to be there. Short lines ("Yes.") match whole or not at
            // all.
            let needed = spoken.count < 4 ? spoken.count : max(2, (spoken.count * 2 + 4) / 5)
            if hits < needed { continue }

            var end = transcriptTokens[last].range.upperBound
            while end < transcript.endIndex, !transcript[end].isWhitespace, !transcript[end].isLetter, !transcript[end].isNumber {
                end = transcript.index(after: end)
            }
            spans.append(Span(range: transcriptTokens[first].range.lowerBound..<end, start: line.start, end: line.end))
            cursor = last + 1
        }
        return spans
    }

    /// The span playing at `time`, or nil before the first one.
    static func activeIndex(in spans: [Span], at time: Double) -> Int? {
        var low = 0
        var high = spans.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if spans[mid].start <= time {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }
}
