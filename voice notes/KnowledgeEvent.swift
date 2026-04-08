//
//  KnowledgeEvent.swift
//  voice notes
//
//  Records knowledge base activity — ingestion, compilation, and lint events.
//  Append-only log surfaced as "Recent Activity" in KnowledgeOverviewView.
//

import Foundation
import SwiftData

// MARK: - Event Type

enum KnowledgeEventType: String, CaseIterable {
    case ingest = "ingest"
    case compile = "compile"
    case lint = "lint"

    var icon: String {
        switch self {
        case .ingest: return "arrow.down.doc"
        case .compile: return "gearshape.2"
        case .lint: return "checkmark.shield"
        }
    }

    var label: String {
        switch self {
        case .ingest: return "Ingested"
        case .compile: return "Compiled"
        case .lint: return "Health Check"
        }
    }
}

// MARK: - KnowledgeEvent Model

@Model
final class KnowledgeEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var eventTypeRaw: String = "ingest"
    var title: String = ""
    var detail: String?
    var relatedArticleName: String?
    var sourceNoteId: UUID?

    var eventType: KnowledgeEventType {
        get { KnowledgeEventType(rawValue: eventTypeRaw) ?? .ingest }
        set { eventTypeRaw = newValue.rawValue }
    }

    init(eventType: KnowledgeEventType, title: String, detail: String? = nil, relatedArticleName: String? = nil, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.eventTypeRaw = eventType.rawValue
        self.title = title
        self.detail = detail
        self.relatedArticleName = relatedArticleName
        self.sourceNoteId = sourceNoteId
    }
}
