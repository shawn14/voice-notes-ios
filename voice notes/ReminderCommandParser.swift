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
    private static let relative = #"\bin\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty[- ]five|sixty|\d+)\s+(min(?:ute)?s?|hours?|hrs?|days?|weeks?)\b"#

    /// "in half an hour" / "in an hour and a half" — the two spoken durations
    /// the number-word form above cannot express.
    private static let halfHour = #"\bin\s+(half\s+an\s+hour|an\s+hour\s+and\s+a\s+half)\b"#

    /// A bare clock time — "at 5", "at 5:30", "at 5pm" — which NSDataDetector
    /// only resolves when a day is also named.
    private static let bareTime = #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b"#

    /// The command is the first sentence. "Remind me to email the contract.
    /// Also Dan said the deck is due Thursday…" must not become a Thursday
    /// reminder titled with the whole note — the rest stays in the note.
    private static func firstSentence(_ s: String) -> String {
        if let r = s.range(of: #"[.!?](?:\s+[A-Z]|\s*\n|\s*$)|\n"#, options: .regularExpression) {
            return String(s[..<r.lowerBound])
        }
        return s
    }

    /// Next occurrence of a clock time. Without am/pm, whichever of the
    /// 12-hour readings comes next (5 → 5 PM at 2 PM, 5 AM at 11 PM).
    private static func nextClockTime(hour: Int, minute: Int, meridiem: String?) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var candidates: [Int] = []
        if let m = meridiem?.lowercased().replacingOccurrences(of: ".", with: "") {
            let base = hour % 12
            candidates = [m == "pm" ? base + 12 : base]
        } else if hour <= 12 {
            candidates = [hour % 12, hour % 12 + 12]
        } else {
            candidates = [hour]
        }
        let options = candidates.compactMap { h -> Date? in
            guard h < 24 else { return nil }
            return calendar.date(bySettingHour: h, minute: minute, second: 0, of: now)
        }
        if let next = options.filter({ $0 > now }).min() { return next }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let earliest = options.min() else { return nil }
        return calendar.date(bySettingHour: calendar.component(.hour, from: earliest),
                             minute: minute, second: 0, of: tomorrow)
    }

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

        var body = firstSentence(String(text[range.upperBound...]))
        var due: Date?

        // Relative duration first — it is unambiguous and the detector skips it.
        if let regex = try? NSRegularExpression(pattern: halfHour, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
           let whole = Range(m.range, in: body),
           let phrase = Range(m.range(at: 1), in: body) {
            let minutes: Double = body[phrase].lowercased().hasPrefix("half") ? 30 : 90
            due = Date().addingTimeInterval(minutes * 60)
            body = String(body[..<whole.lowerBound]) + " " + stripConnectors(String(body[whole.upperBound...]))
        } else if let regex = try? NSRegularExpression(pattern: relative, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
           let whole = Range(m.range, in: body),
           let amountRange = Range(m.range(at: 1), in: body),
           let unitRange = Range(m.range(at: 2), in: body) {
            let amountText = body[amountRange].lowercased()
            let amount = Int(amountText) ?? numberWords[amountText] ?? 1
            let unit = body[unitRange].lowercased()
            let seconds: TimeInterval
            if unit.hasPrefix("min") { seconds = 60 }                       // min, mins, minute(s)
            else if unit.hasPrefix("h") { seconds = 3600 }                  // hour(s), hr(s)
            else if unit.hasPrefix("day") { seconds = 86_400 }
            else { seconds = 7 * 86_400 }                                   // week(s)
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
        } else if let regex = try? NSRegularExpression(pattern: bareTime, options: [.caseInsensitive]),
                  let m = regex.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
                  let whole = Range(m.range, in: body),
                  let hourRange = Range(m.range(at: 1), in: body),
                  let hour = Int(body[hourRange]), (0...23).contains(hour) {
            let minute = Range(m.range(at: 2), in: body).flatMap { Int(body[$0]) } ?? 0
            let meridiem = Range(m.range(at: 3), in: body).map { String(body[$0]) }
            due = nextClockTime(hour: hour, minute: minute, meridiem: meridiem)
            body = String(body[..<whole.lowerBound]) + " " + stripConnectors(String(body[whole.upperBound...]))
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
