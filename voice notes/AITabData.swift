//
//  AITabData.swift
//  voice notes
//
//  Data models for the AI tab sections — zero API calls, all local computation.
//

import Foundation

struct AITabData {
    var attentionItems: [AIAttentionItem]
    var activeThreads: [ActiveThread]
    var peopleSummaries: [PersonSummary]
    var recentDecisions: [DecisionItem]
    var staleItems: [StaleItem]

    var totalItemCount: Int {
        attentionItems.count + activeThreads.count + peopleSummaries.count + recentDecisions.count + staleItems.count
    }

    static let empty = AITabData(
        attentionItems: [],
        activeThreads: [],
        peopleSummaries: [],
        recentDecisions: [],
        staleItems: []
    )
}

// MARK: - Attention Items

enum AIAttentionType: String {
    case overdueAction = "Overdue"
    case urgentAction = "Urgent"
    case staleCommitment = "Stale Commitment"
    case unresolvedStep = "Unresolved Step"

    var icon: String {
        switch self {
        case .overdueAction: return "clock.badge.exclamationmark"
        case .urgentAction: return "exclamationmark.triangle"
        case .staleCommitment: return "person.badge.clock"
        case .unresolvedStep: return "arrow.uturn.right.circle"
        }
    }

    var color: String {
        switch self {
        case .overdueAction: return "red"
        case .urgentAction: return "orange"
        case .staleCommitment: return "yellow"
        case .unresolvedStep: return "purple"
        }
    }
}

struct AIAttentionItem: Identifiable {
    let id: UUID
    let text: String
    let sourceNoteTitle: String
    let sourceNoteId: UUID?
    let ageDays: Int
    let owner: String?
    let score: Double
    let type: AIAttentionType
}

// MARK: - Active Threads

struct ActiveThread: Identifiable {
    let id: String // topic name
    let topic: String
    let noteCount: Int
    let score: Double
    let recentNotes: [(id: UUID, title: String, date: Date)]
}

// MARK: - People Summaries

struct PersonSummary: Identifiable {
    let id: UUID
    let name: String
    let openCommitmentCount: Int
    let lastMentionedAt: Date
    let commitments: [String]
}

// MARK: - Recent Decisions

struct DecisionItem: Identifiable {
    let id: UUID
    let content: String
    let affects: String?
    let sourceNoteTitle: String
    let sourceNoteId: UUID?
    let date: Date
}

// MARK: - Stale Items

struct StaleItem: Identifiable {
    let id: UUID
    let noteTitle: String
    let noteId: UUID
    let unresolvedStep: String?
    let ageDays: Int
}
