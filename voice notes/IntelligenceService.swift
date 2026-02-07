//
//  IntelligenceService.swift
//  voice notes
//
//  Central orchestrator for the three-tier intelligence system:
//  - Tier 1: Instant (on note save)
//  - Tier 2: Session (on app foreground, local computation)
//  - Tier 3: Daily (one AI call per day)
//

import Foundation
import SwiftData

@Observable
final class IntelligenceService {
    static let shared = IntelligenceService()

    // MARK: - State

    var sessionBrief: SessionBrief?
    var isRefreshingSession = false
    var isRefreshingDaily = false
    var dailyBriefError: String?

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastDailyBriefDate = "intelligence.lastDailyBriefDate"
        static let sessionNeedsRefresh = "sessionBrief.needsRefresh"
        static let lastBriefNoteCount = "sessionBrief.lastNoteCount"
    }

    // MARK: - Init

    private init() {
        // Load cached session brief
        sessionBrief = SessionBrief.loadFromCache()
    }

    // MARK: - Tier 1: Instant (on note save)

    /// Process a note immediately after save
    /// Updates counters and marks session as needing refresh
    func processNoteSave(
        note: Note,
        transcript: String?,
        projects: [Project],
        tags: [Tag],
        context: ModelContext
    ) async {
        guard let transcript = transcript, !transcript.isEmpty,
              let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            // Just update counters
            StatusCounters.shared.incrementNotesToday()
            StatusCounters.shared.markSessionStale()
            return
        }

        // Extract intent (existing SummaryService call)
        do {
            let result = try await SummaryService.extractIntent(text: transcript, apiKey: apiKey)

            await MainActor.run {
                // Apply extraction to note
                note.intentType = result.intent
                note.intentConfidence = result.intentConfidence

                if let subject = result.subject {
                    note.extractedSubject = ExtractedSubject(
                        topic: subject.topic,
                        action: subject.action
                    )
                }

                note.suggestedNextStep = result.nextStep
                note.nextStepTypeRaw = result.nextStepType
                note.missingInfo = result.missingInfo.map {
                    MissingInfoItem(field: $0.field, description: $0.description)
                }
                note.inferredProjectName = result.inferredProject

                // Auto-match project
                if let inferredName = result.inferredProject, !inferredName.isEmpty {
                    let textToMatch = "\(inferredName) \(note.content)"
                    if let match = ProjectMatcher.findMatch(for: textToMatch, in: projects) {
                        note.projectId = match.project.id

                        // Update project activity
                        match.project.lastActivityAt = Date()
                        match.project.noteCount += 1
                    }
                }
            }
        } catch {
            print("Intent extraction failed: \(error)")
        }

        // Update counters
        StatusCounters.shared.incrementNotesToday()
        StatusCounters.shared.markSessionStale()
    }

    // MARK: - Tier 2: Session (on app active)

    /// Refresh session brief if needed (local computation only, NO AI)
    func refreshSessionBriefIfNeeded(
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) async {
        // Check if we have a valid cached brief
        if let cached = sessionBrief, !cached.isStale {
            let needsRefresh = UserDefaults.standard.bool(forKey: Keys.sessionNeedsRefresh)
            let lastNoteCount = UserDefaults.standard.integer(forKey: Keys.lastBriefNoteCount)
            let noteCountChanged = notes.count != lastNoteCount

            // Skip refresh if cache is fresh AND note count unchanged AND not explicitly marked stale
            if !needsRefresh && !cached.isSoftExpired && !noteCountChanged {
                return  // Cache is fresh, skip refresh
            }
        }

        guard !isRefreshingSession else { return }
        isRefreshingSession = true

        // Build new session brief (all local computation)
        let newBrief = SessionBriefBuilder.build(
            notes: notes,
            projects: projects,
            items: items,
            movements: movements,
            actions: actions,
            commitments: commitments,
            unresolved: unresolved
        )

        await MainActor.run {
            sessionBrief = newBrief
            newBrief.saveToCache()
            UserDefaults.standard.set(false, forKey: Keys.sessionNeedsRefresh)
            UserDefaults.standard.set(notes.count, forKey: Keys.lastBriefNoteCount)
            isRefreshingSession = false
        }

        // Also update status counters
        StatusCounters.shared.recompute(
            notes: notes,
            actions: actions,
            commitments: commitments,
            items: items,
            unresolved: unresolved
        )
        StatusCounters.shared.updateActiveProjects(count: projects.filter { !$0.isArchived }.count)
    }

    // MARK: - Tier 3: Daily (on day rollover)

    /// Check if daily brief needs generation and generate if needed
    func checkAndGenerateDailyBrief(
        context: ModelContext,
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Check if we already generated a brief today
        if let lastDate = UserDefaults.standard.object(forKey: Keys.lastDailyBriefDate) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            if lastDay >= today {
                return  // Already generated today
            }
        }

        // Also check SwiftData for existing brief
        let descriptor = FetchDescriptor<DailyBrief>(
            predicate: #Predicate { $0.briefDate >= today }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            UserDefaults.standard.set(Date(), forKey: Keys.lastDailyBriefDate)
            return  // Already have a brief for today
        }

        guard !isRefreshingDaily else { return }
        isRefreshingDaily = true
        dailyBriefError = nil

        // Generate daily brief with AI
        do {
            let brief = try await generateDailyBrief(
                notes: notes,
                projects: projects,
                items: items,
                movements: movements,
                actions: actions,
                commitments: commitments,
                unresolved: unresolved
            )

            await MainActor.run {
                context.insert(brief)
                try? context.save()
                UserDefaults.standard.set(Date(), forKey: Keys.lastDailyBriefDate)
                isRefreshingDaily = false
            }
        } catch {
            await MainActor.run {
                dailyBriefError = error.localizedDescription
                isRefreshingDaily = false
            }
        }
    }

    /// Force regenerate daily brief (for retry after error)
    func regenerateDailyBrief(
        context: ModelContext,
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) async {
        // Clear the last date to force regeneration
        UserDefaults.standard.removeObject(forKey: Keys.lastDailyBriefDate)

        await checkAndGenerateDailyBrief(
            context: context,
            notes: notes,
            projects: projects,
            items: items,
            movements: movements,
            actions: actions,
            commitments: commitments,
            unresolved: unresolved
        )
    }

    // MARK: - Private: AI Generation

    private func generateDailyBrief(
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) async throws -> DailyBrief {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw DailyBriefError.noAPIKey
        }

        // Build context string
        let contextString = buildBriefContext(
            notes: notes,
            projects: projects,
            items: items,
            movements: movements,
            actions: actions,
            commitments: commitments,
            unresolved: unresolved
        )

        // Call AI
        let response = try await callDailyBriefAI(context: contextString, apiKey: apiKey)

        // Build DailyBrief model
        let brief = DailyBrief()
        brief.whatMattersToday = response.summary
        brief.highlights = response.highlights

        // Convert priorities to suggested actions
        brief.suggestedActions = response.priorities.map { priority in
            SuggestedAction(
                content: priority.content,
                reason: priority.reason,
                projectName: priority.projectName,
                priority: .high
            )
        }

        // Convert warnings
        brief.warnings = response.warnings.map { warning in
            let type: DailyWarning.WarningType
            switch warning.type.lowercased() {
            case "stalled": type = .stalled
            case "overdue": type = .overdue
            case "commitment": type = .commitment
            default: type = .stalled
            }
            return DailyWarning(
                type: type,
                content: warning.content,
                daysSinceIssue: warning.daysSinceIssue
            )
        }

        // Snapshot metrics
        brief.openItemCount = items.filter { $0.kanbanColumn != .done }.count
        brief.stalledItemCount = HealthScoreService.detectDroppedBalls(items: items).count
        brief.momentumDirection = MomentumService.calculateMomentum(movements: movements, items: items).direction.rawValue
        brief.activeProjectCount = projects.filter { !$0.isArchived }.count

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()

        brief.notesYesterday = notes.filter {
            $0.createdAt >= startOfYesterday && $0.createdAt < startOfToday
        }.count
        brief.notesThisWeek = notes.filter { $0.createdAt >= startOfWeek }.count

        return brief
    }

    private func buildBriefContext(
        notes: [Note],
        projects: [Project],
        items: [KanbanItem],
        movements: [KanbanMovement],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        unresolved: [UnresolvedItem]
    ) -> String {
        var context = ""

        // Build project lookup dictionary for O(1) access
        let projectLookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })

        // Recent notes (last 15)
        let recentNotes = notes.sorted { $0.createdAt > $1.createdAt }.prefix(15)
        if !recentNotes.isEmpty {
            context += "RECENT NOTES:\n"
            for note in recentNotes {
                let projectName = note.projectId.flatMap { projectLookup[$0] } ?? "Inbox"
                let preview = String(note.content.prefix(100)).replacingOccurrences(of: "\n", with: " ")
                context += "- [\(projectName)] \(note.displayTitle): \(preview)\n"
            }
            context += "\n"
        }

        // Active items by column
        let activeItems = items.filter { $0.kanbanColumn != .done }
        let columns: [KanbanColumn] = [.thinking, .decided, .doing, .waiting]
        for column in columns {
            let columnItems = activeItems.filter { $0.kanbanColumn == column }
            if !columnItems.isEmpty {
                context += "\(column.rawValue.uppercased()) (\(columnItems.count) items):\n"
                for item in columnItems.prefix(5) {
                    context += "- \(item.content) (\(item.daysSinceUpdate)d old)\n"
                }
                context += "\n"
            }
        }

        // Dropped balls
        let droppedBalls = HealthScoreService.detectDroppedBalls(items: items)
        if !droppedBalls.isEmpty {
            context += "NEEDS ATTENTION (\(droppedBalls.count) items):\n"
            for ball in droppedBalls.prefix(5) {
                context += "- \(ball.item.content): \(ball.description)\n"
            }
            context += "\n"
        }

        // Open commitments
        let openCommitments = commitments.filter { !$0.isCompleted }
        if !openCommitments.isEmpty {
            context += "OPEN COMMITMENTS (\(openCommitments.count)):\n"
            for commitment in openCommitments.prefix(5) {
                context += "- \(commitment.who): \(commitment.what)\n"
            }
            context += "\n"
        }

        // Momentum
        let momentum = MomentumService.calculateMomentum(movements: movements, items: items)
        context += "MOMENTUM: \(momentum.direction.rawValue) (this week: \(momentum.movementsThisWeek), last week: \(momentum.movementsLastWeek))\n"
        context += "Completed this week: \(momentum.completedThisWeek)\n"

        return context
    }

    private func callDailyBriefAI(context: String, apiKey: String) async throws -> DailyBriefResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are an AI assistant generating a daily brief for a founder's voice notes app.
        Be direct, actionable, and founder-friendly. Focus on what matters TODAY.

        Return JSON with this EXACT structure:
        {
            "summary": "One paragraph overview of the day's priorities",
            "highlights": ["3-5 key things to know today"],
            "priorities": [
                {"content": "What to focus on", "reason": "Why it matters", "projectName": "Optional project name or null"}
            ],
            "warnings": [
                {"type": "stalled|overdue|commitment", "content": "What needs attention", "daysSinceIssue": 5}
            ]
        }

        Rules:
        - summary: 1-3 sentences, focus on what matters today
        - highlights: 3-5 bullet points of key info
        - priorities: 3-5 actionable items, ordered by importance
        - warnings: 0-3 items that need attention, be honest about problems
        - Return ONLY valid JSON, no other text
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Here's what's happening:\n\n\(context)"]
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DailyBriefError.apiError(errorMessage)
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw DailyBriefError.parsingError
        }

        return try JSONDecoder().decode(DailyBriefResponse.self, from: jsonData)
    }
}

// MARK: - Errors

enum DailyBriefError: LocalizedError {
    case noAPIKey
    case apiError(String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .apiError(let message):
            return "API Error: \(message)"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}
