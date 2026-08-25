//
//  ReminderCommandParser.swift
//  voice notes
//
//  "Remind me to call Dan on Friday at 5" → a reminder, confirmed with one tap.
//  Pocket's headline voice command (Mar 2026: "Hey Pocket, remind me…").
//
//  Fully on-device and deterministic — a regex for the trigger, NSDataDetector
//  for the date phrase — so it runs before the IntentClassifier API call and
//  costs nothing. A matched command is still saved as a note (EEON is memory;
//  the capture is never lost); the reminder itself is created only after the
//  user confirms in ReminderConfirmSheet.
//

import Foundation

nonisolated enum ReminderCommandParser {
    nonisolated struct Command: Identifiable, Equatable {
        let id = UUID()
        /// What to remind about, cleaned of the trigger and the date phrase.
        let title: String
        /// Parsed from speech when present ("tomorrow at 5", "Friday", "in two hours").
        let due: Date?
        /// The full transcript, shown back to the user for trust.
        let original: String
    }

    /// Trigger at the start of the utterance. Tolerates a wake word, politeness,
    /// and both phrasings: "remind me (to|that|about|of)" and "set a reminder (to|for|that)".
    /// The optional connector needs its own word boundary: without it "remind
    /// me tomorrow" matched "to" inside "tomorrow" and the title began "morrow".
    private static let trigger = #"^\W*(?:(?:hey|ok|okay)\s+)?(?:eeon[,\s]+)?(?:please\s+)?(?:can you\s+|could you\s+)?(?:remind me\b\s*(?:(?:to|that|about|of)\b)?|(?:set|create|add|make)\s+a\s+reminder\b\s*(?:(?:to|for|that|about)\b)?)\s*"#

    /// "in two hours", "in 20 minutes", "in a week" — relative durations that
    /// NSDataDetector does not parse.
    private static let relative = #"\bin\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty[- ]five|sixty|\d+)\s+(minutes?|hours?|days?|weeks?)\b"#

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15,
        "twenty": 20, "thirty": 30, "forty-five": 45, "forty five": 45, "sixty": 60
    ]

    /// Words that dangle once the date phrase is cut out of the middle:
    /// "tomorrow at 9 *to* send the invoice" → "send the invoice".
    private static func stripConnectors(_ s: String) -> String {
        s.replacingOccurrences(
            of: #"^\s*(?:(?:to|that|about|of|and|then)\b\s*)+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
    }

    static func parse(_ transcript: String) -> Command? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: trigger, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }

        var body = String(text[range.upperBound...])
        var due: Date?

        // Relative duration first — it is unambiguous and the detector skips it.
        if let regex = try? NSRegularExpression(pattern: relative, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
           let whole = Range(m.range, in: body),
           let amountRange = Range(m.range(at: 1), in: body),
           let unitRange = Range(m.range(at: 2), in: body) {
            let amountText = body[amountRange].lowercased()
            let amount = Int(amountText) ?? numberWords[amountText] ?? 1
            let unit = body[unitRange].lowercased()
            let seconds: TimeInterval
            if unit.hasPrefix("minute") { seconds = 60 }
            else if unit.hasPrefix("hour") { seconds = 3600 }
            else if unit.hasPrefix("day") { seconds = 86_400 }
            else { seconds = 7 * 86_400 }
            due = Date().addingTimeInterval(Double(amount) * seconds)
            body = String(body[..<whole.lowerBound]) + " " + stripConnectors(String(body[whole.upperBound...]))
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let dateMatch = detector.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
           let dateRange = Range(dateMatch.range, in: body) {
            due = dateMatch.date
            var prefix = String(body[..<dateRange.lowerBound])
            let suffix = String(body[dateRange.upperBound...])
            // "call Dan *on* Friday" → drop the dangling preposition too.
            prefix = prefix.replacingOccurrences(
                of: #"\s*\b(at|on|by|for|in|around|before|until|this|next)\s*$"#,
                with: "", options: [.regularExpression, .caseInsensitive]
            )
            body = prefix + " " + stripConnectors(suffix)
        }
        body = stripConnectors(body)

        body = body
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !body.isEmpty else { return nil }

        let title = body.prefix(1).uppercased() + body.dropFirst()
        return Command(title: title, due: due, original: transcript)
    }
}
