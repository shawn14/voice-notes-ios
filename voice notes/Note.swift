//
//  Note.swift
//  voice notes
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Note Intent Classification

enum NoteIntent: String, CaseIterable, Codable {
    case action = "Action"
    case decision = "Decision"
    case idea = "Idea"
    case update = "Update"
    case reminder = "Reminder"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .action: return "checkmark.circle"
        case .decision: return "checkmark.seal"
        case .idea: return "lightbulb"
        case .update: return "arrow.triangle.2.circlepath"
        case .reminder: return "bell"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .action: return .orange
        case .decision: return .green
        case .idea: return .purple
        case .update: return .blue
        case .reminder: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Structured Extraction Models

struct ExtractedSubject: Codable, Sendable {
    let topic: String
    let action: String?

    static func fromJSON(_ json: String?) -> ExtractedSubject? {
        guard let json = json,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExtractedSubject.self, from: data)
    }

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct MissingInfoItem: Codable, Sendable {
    let field: String
    let description: String

    static func fromJSON(_ json: String?) -> [MissingInfoItem] {
        guard let json = json,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MissingInfoItem].self, from: data)) ?? []
    }

    static func toJSON(_ items: [MissingInfoItem]) -> String? {
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Next Step Types

enum NextStepType: String, Codable, CaseIterable {
    case date = "date"           // "Pick a date", "Schedule", "Set deadline"
    case contact = "contact"     // "Send to", "Email", "Call", "Message"
    case decision = "decision"   // "Decide on", "Choose between"
    case simple = "simple"       // "Review", "Check", "Confirm", or fallback

    var icon: String {
        switch self {
        case .date: return "calendar"
        case .contact: return "person.crop.circle"
        case .decision: return "arrow.triangle.branch"
        case .simple: return "checkmark.circle"
        }
    }
}

@Model
final class Note {
    var id: UUID
    var title: String
    var content: String
    var transcript: String?
    var audioFileName: String?
    var createdAt: Date
    var updatedAt: Date
    var projectId: UUID?
    var column: String = "Thinking"  // KanbanColumn raw value
    var aiInsight: String?  // AI-generated summary or next step

    // Intent classification
    var intentType: String = "Unknown"  // Action, Decision, Idea, Update, Reminder, Unknown
    var intentConfidence: Double = 0.0

    // Structured extraction (JSON-encoded)
    var extractedSubjectJSON: String?   // JSON: {"topic": "Board Meeting", "action": "Reschedule"}
    var suggestedNextStep: String?      // "Pick a date for the board meeting"
    var nextStepTypeRaw: String?        // "date", "contact", "decision", "simple"
    var missingInfoJSON: String?        // JSON array: [{"field": "date", "description": "Needs exact date"}]

    // Next step resolution
    var nextStepResolvedAt: Date?       // When was it resolved
    var nextStepResolution: String?     // What was chosen ("Jan 28", "Sent to John", etc.)

    // Project inference
    var inferredProjectName: String?    // AI-suggested project name

    @Relationship(deleteRule: .nullify, inverse: \Tag.notes)
    var tags: [Tag]

    init(
        title: String = "",
        content: String = "",
        transcript: String? = nil,
        audioFileName: String? = nil,
        projectId: UUID? = nil,
        column: String = "Thinking"
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.projectId = projectId
        self.column = column
        self.tags = []
    }

    var kanbanColumn: KanbanColumn {
        get { KanbanColumn(rawValue: column) ?? .thinking }
        set {
            column = newValue.rawValue
            updatedAt = Date()
        }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !content.isEmpty { return String(content.prefix(50)) }
        if let transcript = transcript, !transcript.isEmpty {
            return String(transcript.prefix(50))
        }
        return "Untitled Note"
    }

    var hasAudio: Bool {
        audioFileName != nil
    }

    var audioURL: URL? {
        guard let fileName = audioFileName else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    // MARK: - Intent Computed Properties

    var intent: NoteIntent {
        get { NoteIntent(rawValue: intentType) ?? .unknown }
        set {
            intentType = newValue.rawValue
            updatedAt = Date()
        }
    }

    var extractedSubject: ExtractedSubject? {
        get {
            ExtractedSubject.fromJSON(extractedSubjectJSON)
        }
        set {
            extractedSubjectJSON = newValue?.toJSON()
            updatedAt = Date()
        }
    }

    var missingInfo: [MissingInfoItem] {
        get {
            MissingInfoItem.fromJSON(missingInfoJSON)
        }
        set {
            missingInfoJSON = MissingInfoItem.toJSON(newValue)
            updatedAt = Date()
        }
    }

    // MARK: - Next Step Resolution

    var nextStepType: NextStepType {
        get { NextStepType(rawValue: nextStepTypeRaw ?? "") ?? .simple }
        set {
            nextStepTypeRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var isNextStepResolved: Bool {
        nextStepResolvedAt != nil
    }

    func resolveNextStep(with resolution: String) {
        nextStepResolution = resolution
        nextStepResolvedAt = Date()
        updatedAt = Date()
    }

    func unresolveNextStep() {
        nextStepResolution = nil
        nextStepResolvedAt = nil
        updatedAt = Date()
    }
}
