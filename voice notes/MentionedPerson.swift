//
//  MentionedPerson.swift
//  voice notes
//
//  People Tracker: Stores unique people mentioned across notes

import Foundation
import SwiftData

@Model
final class MentionedPerson {
    var id: UUID = UUID()
    var name: String = ""
    var normalizedName: String = ""  // lowercase for matching
    var firstMentionedAt: Date = Date()
    var lastMentionedAt: Date = Date()
    var mentionCount: Int = 1
    var openCommitmentCount: Int = 0
    var isArchived: Bool = false

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.normalizedName = MentionedPerson.normalize(name)
        self.firstMentionedAt = Date()
        self.lastMentionedAt = Date()
        self.mentionCount = 1
        self.openCommitmentCount = 0
        self.isArchived = false
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func incrementMention() {
        mentionCount += 1
        lastMentionedAt = Date()
    }

    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components.first?.prefix(1) ?? ""
            let last = components.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(1)).uppercased()
        }
        return "?"
    }

    var displayName: String {
        name.isEmpty ? "Unknown" : name
    }
}
