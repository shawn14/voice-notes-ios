//
//  HomeLayout.swift
//  voice notes
//
//  The home screen layout is compiled by the Karpathy LLM (KnowledgeCompiler)
//  as part of the `.purpose` KnowledgeArticle. It's a structured list of
//  section IDs + optional params chosen from a fixed catalog — picked to
//  match the user's declared role (founder / coach / dream interpreter / etc).
//
//  The catalog is intentionally closed. New section kinds require engineering,
//  which keeps the UI coherent and testable. The LLM only *picks and orders*.
//

import Foundation

// MARK: - Section Catalog

enum HomeSectionKind: String, Codable, CaseIterable {
    // Capture + always-present
    case captureHero         // Voice mic / capture CTA (always rendered at bottom — layout ignored)

    // Project / execution-oriented (founder, PM, creator)
    case priorityProjects    // Active projects ranked by momentum
    case silentProjects      // Projects untouched N days — "you started this"
    case openDecisions       // ExtractedDecisions with no follow-up action
    case ideaInbox           // Notes with intent=idea not yet tied to a project
    case todayThree          // User's "Today's 3" existing pattern
    case openThreads         // Cross-article open threads (from KnowledgeArticle.openThreads)

    // People / relationship-oriented (coach, community builder, therapist)
    case clientRoster        // .person articles ranked by last meaningful note
    case followUpsPerClient  // Commitments grouped by person
    case relationshipArcs    // Person articles with sentimentArc changes

    // Pattern / symbolic (dream interpreter, journaler, therapist)
    case recurringPatterns   // Recurring topics/symbols across notes
    case emotionalToneArc    // Emotional tone over time
    case referenceResonance  // .reference articles that match recent notes

    // Research / synthesis (academic, writer)
    case activeInquiries     // Topic articles with open questions
    case contradictionLedger // Where notes or sources contradict

    // Always-available fallbacks (generic)
    case knowledgeCarousel   // Existing horizontal scroll of all articles
    case recentNotes         // Existing tabbed note feed
    case dailyBrief          // Daily/weekly compiled brief

    /// Human-readable title — shown when the LLM doesn't specify one.
    var defaultTitle: String {
        switch self {
        case .captureHero: return ""
        case .priorityProjects: return "Active Build"
        case .silentProjects: return "Silent Projects"
        case .openDecisions: return "Open Decisions"
        case .ideaInbox: return "Idea Inbox"
        case .todayThree: return "Today's 3"
        case .openThreads: return "Open Threads"
        case .clientRoster: return "Your People"
        case .followUpsPerClient: return "Follow-ups"
        case .relationshipArcs: return "Relationship Arcs"
        case .recurringPatterns: return "Recurring Patterns"
        case .emotionalToneArc: return "Emotional Arc"
        case .referenceResonance: return "From Your Library"
        case .activeInquiries: return "Active Inquiries"
        case .contradictionLedger: return "Contradictions"
        case .knowledgeCarousel: return "Your Knowledge"
        case .recentNotes: return "Recent Notes"
        case .dailyBrief: return "Today's Brief"
        }
    }
}

// MARK: - Section + Layout

struct HomeSection: Codable, Identifiable, Equatable {
    var id: String { kindRaw + (title ?? "") }
    let kindRaw: String           // Raw value of HomeSectionKind
    let title: String?            // Override default title (LLM-picked, archetype-specific)
    let limit: Int?               // Optional cap on rows shown
    let staleDaysThreshold: Int?  // For silentProjects / openThreads

    var kind: HomeSectionKind? {
        HomeSectionKind(rawValue: kindRaw)
    }

    var effectiveTitle: String {
        title ?? kind?.defaultTitle ?? ""
    }
}

struct HomeLayout: Codable, Equatable {
    let sections: [HomeSection]
    let version: Int  // Bump when section schema changes

    static let currentVersion = 1

    /// Fallback layout for users who haven't compiled a purpose article yet.
    /// Matches today's AIHomeView ordering so behavior is unchanged pre-compile.
    static let `default` = HomeLayout(
        sections: [
            HomeSection(kindRaw: HomeSectionKind.knowledgeCarousel.rawValue, title: nil, limit: nil, staleDaysThreshold: nil),
            HomeSection(kindRaw: HomeSectionKind.recentNotes.rawValue, title: nil, limit: nil, staleDaysThreshold: nil),
        ],
        version: currentVersion
    )

    /// Decode from a JSON string stored on the purpose article. Returns .default on any parse error.
    static func decode(from json: String?) -> HomeLayout {
        guard let json, let data = json.data(using: .utf8) else { return .default }
        do {
            let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)
            // Filter out unknown kinds (forward-compat — old layout referencing deleted section)
            let valid = decoded.sections.filter { $0.kind != nil }
            return HomeLayout(sections: valid, version: decoded.version)
        } catch {
            print("[HomeLayout] decode failed, using default: \(error)")
            return .default
        }
    }
}

// MARK: - KnowledgeArticle Extension

extension KnowledgeArticle {
    /// The compiled home layout stored on the .purpose article.
    /// Getter returns .default if unset or invalid.
    var homeLayout: HomeLayout {
        get { HomeLayout.decode(from: homeLayoutJSON) }
        set {
            let data = try? JSONEncoder().encode(newValue)
            homeLayoutJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}
