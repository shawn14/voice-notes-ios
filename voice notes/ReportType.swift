//
//  ReportType.swift
//  voice notes
//
//  Report type definitions for AI Reports screen
//

import Foundation

enum ReportType: String, CaseIterable, Identifiable {
    case ceoReport = "CEO Report"
    case swot = "SWOT"
    case goalTracker = "Goals"
    case weeklySummary = "Weekly"
    case people = "People"
    case projectStatus = "Projects"
    case decisionLog = "Decisions"
    case actionAudit = "Actions"
    case custom = "Custom"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .ceoReport: return "📊"
        case .swot: return "🔍"
        case .goalTracker: return "🎯"
        case .weeklySummary: return "📅"
        case .people: return "👥"
        case .projectStatus: return "📁"
        case .decisionLog: return "📋"
        case .actionAudit: return "✅"
        case .custom: return "✨"
        }
    }

    var pillColor: String {
        switch self {
        case .ceoReport: return "1a3a5c"
        case .swot: return "3a1a1a"
        case .goalTracker: return "1a3a1a"
        case .weeklySummary: return "3a2a1a"
        case .people: return "2a1a3a"
        case .projectStatus: return "1a2a3a"
        case .decisionLog: return "2a2a1a"
        case .actionAudit: return "1a2a2a"
        case .custom: return "2a1a2a"
        }
    }

    var pillTextColor: String {
        switch self {
        case .ceoReport: return "4a9eff"
        case .swot: return "ff6b6b"
        case .goalTracker: return "4aff6b"
        case .weeklySummary: return "ffaa4a"
        case .people: return "aa6bff"
        case .projectStatus: return "4affff"
        case .decisionLog: return "ffff4a"
        case .actionAudit: return "4affaa"
        case .custom: return "ff6bff"
        }
    }

    var userPrompt: String {
        switch self {
        case .ceoReport:
            return "Generate a CEO Report across all my notes and projects."
        case .swot:
            return "Create a SWOT analysis based on everything in my notes."
        case .goalTracker:
            return "Show me goal tracking — what's on track, what's drifting, and suggested corrections."
        case .weeklySummary:
            return "Write a weekly summary — decisions made, actions completed, and what stalled."
        case .people:
            return "Generate a people report — who I owe things to, who owes me, and relationship health."
        case .projectStatus:
            return "Give me a project status report — health, blockers, momentum for each project."
        case .decisionLog:
            return "Show me all decisions with their current status and any that need revisiting."
        case .actionAudit:
            return "Audit my open actions — what's overdue, blocked, or missing an owner."
        case .custom:
            return ""
        }
    }

    var reportInstructions: String {
        switch self {
        case .ceoReport:
            return """
            Generate a CEO-level report with these sections:
            ## Highlights
            Top 3-5 achievements or progress points.
            ## Strategic Implications
            What these developments mean for the bigger picture.
            ## Risks & Concerns
            Items that need attention or could become problems.
            ## Recommended Actions
            Specific next steps, prioritized.
            """
        case .swot:
            return """
            Generate a SWOT analysis based on the user's notes, projects, and extracted intelligence:
            ## Strengths
            What's working well — active projects, completed actions, strong momentum areas.
            ## Weaknesses
            What's struggling — stalled items, overdue actions, unresolved issues.
            ## Opportunities
            Potential improvements, ideas mentioned but not acted on, connections between projects.
            ## Threats
            Risks — items drifting too long, commitments at risk, dependencies on others.
            """
        case .goalTracker:
            return """
            Analyze the user's projects, actions, and decisions to infer their goals and track progress:
            ## Active Goals (Inferred)
            What the user appears to be working toward based on their notes and projects.
            ## On Track
            Goals with recent activity and forward momentum.
            ## Drifting
            Goals with stalled items or no recent activity.
            ## Suggested Course Corrections
            Specific actions to get drifting goals back on track.
            """
        case .weeklySummary:
            return """
            Write a weekly summary covering the past 7 days:
            ## What Happened This Week
            Key notes recorded, decisions made, actions taken.
            ## Completed
            Actions and commitments that were finished.
            ## Still In Progress
            Items actively being worked on.
            ## Stalled or Blocked
            Items that haven't moved and may need attention.
            ## Next Week's Priorities
            Suggested focus areas based on open items.
            """
        case .people:
            return """
            Generate a people relationship report:
            ## Commitments I Owe Others
            What I've promised to other people, with status.
            ## Commitments Others Owe Me
            What others have committed to, with status.
            ## People Needing Attention
            People with open commitments or recent mentions who may need follow-up.
            ## Relationship Health
            Overall assessment of key relationships based on commitment follow-through.
            """
        case .projectStatus:
            return """
            Generate a project-by-project status report:
            For each active project, include:
            ## [Project Name]
            - **Status**: Active/Stalled/Completed
            - **Momentum**: Accelerating/Steady/Slowing/Stalled
            - **Open Items**: Count of open actions, unresolved items
            - **Blockers**: Any blocked items or overdue actions
            - **Recent Activity**: Last note or action date
            - **Recommended Next Step**: Most important thing to do next
            """
        case .decisionLog:
            return """
            Generate a decision log report:
            ## Active Decisions
            Decisions currently in effect, with context and what they affect.
            ## Pending Decisions
            Decisions that need to be made — waiting on information or input.
            ## Decisions to Revisit
            Any decisions that may need to be reconsidered based on new information or time elapsed.
            ## Decision Timeline
            Chronological list of recent decisions with dates.
            """
        case .actionAudit:
            return """
            Audit all open actions:
            ## Overdue
            Actions past their deadline or flagged as overdue.
            ## Blocked
            Actions that are blocked and need unblocking.
            ## No Owner
            Actions without a clear owner assigned.
            ## Due Soon
            Actions coming up that need attention.
            ## By Priority
            Remaining open actions grouped by priority (Urgent, High, Normal, Low).
            """
        case .custom:
            return "Answer the user's question based on their complete notes history. Be concise and actionable. Use markdown formatting."
        }
    }
}
