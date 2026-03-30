//
//  AITabBuilder.swift
//  voice notes
//
//  Pure computation — builds AITabData from SwiftData query results with zero API calls.
//

import Foundation

enum AITabBuilder {

    static func build(
        notes: [Note],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        decisions: [ExtractedDecision],
        people: [MentionedPerson]
    ) -> AITabData {
        let now = Date()
        let calendar = Calendar.current
        let noteLookup = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        return AITabData(
            attentionItems: buildAIAttentionItems(notes: notes, actions: actions, commitments: commitments, noteLookup: noteLookup, now: now, calendar: calendar),
            activeThreads: buildActiveThreads(notes: notes, now: now, calendar: calendar),
            peopleSummaries: buildPeopleSummaries(people: people, commitments: commitments),
            recentDecisions: buildRecentDecisions(decisions: decisions, noteLookup: noteLookup, now: now, calendar: calendar),
            staleItems: buildStaleItems(notes: notes, actions: actions, noteLookup: noteLookup, now: now, calendar: calendar)
        )
    }

    // MARK: - Needs Attention

    private static func buildAIAttentionItems(
        notes: [Note],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        noteLookup: [UUID: Note],
        now: Date,
        calendar: Calendar
    ) -> [AIAttentionItem] {
        var items: [AIAttentionItem] = []

        // Overdue actions (not completed, has overdue deadline)
        for action in actions where !action.isCompleted {
            let sourceNote = action.sourceNoteId.flatMap { noteLookup[$0] }
            let ageDays = calendar.dateComponents([.day], from: action.createdAt, to: now).day ?? 0

            if action.isOverdue {
                items.append(AIAttentionItem(
                    id: action.id,
                    text: action.content,
                    sourceNoteTitle: sourceNote?.displayTitle ?? "Unknown Note",
                    sourceNoteId: action.sourceNoteId,
                    ageDays: ageDays,
                    owner: action.owner,
                    score: 100,
                    type: .overdueAction
                ))
            } else if action.priority == "Urgent" || action.priority == "High" {
                items.append(AIAttentionItem(
                    id: action.id,
                    text: action.content,
                    sourceNoteTitle: sourceNote?.displayTitle ?? "Unknown Note",
                    sourceNoteId: action.sourceNoteId,
                    ageDays: ageDays,
                    owner: action.owner,
                    score: 80,
                    type: .urgentAction
                ))
            }
        }

        // Stale commitments (unresolved, older than 5 days)
        for commitment in commitments where !commitment.isCompleted {
            let ageDays = calendar.dateComponents([.day], from: commitment.createdAt, to: now).day ?? 0
            if ageDays > 5 {
                let sourceNote = commitment.sourceNoteId.flatMap { noteLookup[$0] }
                items.append(AIAttentionItem(
                    id: commitment.id,
                    text: "\(commitment.who): \(commitment.what)",
                    sourceNoteTitle: sourceNote?.displayTitle ?? "Unknown Note",
                    sourceNoteId: commitment.sourceNoteId,
                    ageDays: ageDays,
                    owner: commitment.who,
                    score: 60 + Double(ageDays) / 2.0,
                    type: .staleCommitment
                ))
            }
        }

        // Notes with unresolved next steps older than 3 days
        for note in notes {
            guard let _ = note.suggestedNextStep, note.nextStepResolvedAt == nil else { continue }
            let ageDays = calendar.dateComponents([.day], from: note.createdAt, to: now).day ?? 0
            if ageDays > 3 {
                items.append(AIAttentionItem(
                    id: note.id,
                    text: note.suggestedNextStep ?? "",
                    sourceNoteTitle: note.displayTitle,
                    sourceNoteId: note.id,
                    ageDays: ageDays,
                    owner: nil,
                    score: 40 + Double(ageDays) / 3.0,
                    type: .unresolvedStep
                ))
            }
        }

        // Sort by score descending, take top 5
        return Array(items.sorted { $0.score > $1.score }.prefix(5))
    }

    // MARK: - Active Threads

    private static func buildActiveThreads(
        notes: [Note],
        now: Date,
        calendar: Calendar
    ) -> [ActiveThread] {
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        // Filter non-archived notes from last 14 days
        let recentNotes = notes.filter { !$0.isArchived && $0.createdAt >= fourteenDaysAgo }

        // Build topic -> [Note] dictionary
        var topicNotes: [String: [Note]] = [:]
        for note in recentNotes {
            for topic in note.topics {
                let normalized = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { continue }
                topicNotes[normalized, default: []].append(note)
            }
        }

        // Filter topics with 3+ notes, score and sort
        var threads: [ActiveThread] = []
        for (topic, threadNotes) in topicNotes where threadNotes.count >= 3 {
            let score = threadNotes.reduce(0.0) { sum, note in
                let daysSince = max(0, Double(calendar.dateComponents([.day], from: note.createdAt, to: now).day ?? 0))
                return sum + (1.0 / (1.0 + daysSince))
            }

            let sorted = threadNotes.sorted { $0.createdAt > $1.createdAt }
            let recentThree = Array(sorted.prefix(3)).map { (id: $0.id, title: $0.displayTitle, date: $0.createdAt) }

            // Use the original casing from the first note's topic that matches
            let displayTopic = threadNotes.first?.topics.first { $0.lowercased() == topic } ?? topic.capitalized

            threads.append(ActiveThread(
                id: topic,
                topic: displayTopic,
                noteCount: threadNotes.count,
                score: score,
                recentNotes: recentThree
            ))
        }

        return Array(threads.sorted { $0.score > $1.score }.prefix(5))
    }

    // MARK: - People Summaries

    private static func buildPeopleSummaries(
        people: [MentionedPerson],
        commitments: [ExtractedCommitment]
    ) -> [PersonSummary] {
        // Build commitment lookup by normalized person name
        let openCommitments = commitments.filter { !$0.isCompleted && $0.personName != nil }
        var commitmentsByPerson: [String: [String]] = [:]
        for c in openCommitments {
            if let name = c.personName {
                commitmentsByPerson[name, default: []].append(c.what)
            }
        }

        var summaries: [PersonSummary] = []
        for person in people where !person.isArchived {
            let personCommitments = commitmentsByPerson[person.normalizedName] ?? []
            let count = max(person.openCommitmentCount, personCommitments.count)
            guard count > 0 else { continue }

            summaries.append(PersonSummary(
                id: person.id,
                name: person.displayName,
                openCommitmentCount: count,
                lastMentionedAt: person.lastMentionedAt,
                commitments: personCommitments
            ))
        }

        return Array(summaries.sorted { $0.lastMentionedAt > $1.lastMentionedAt }.prefix(4))
    }

    // MARK: - Recent Decisions

    private static func buildRecentDecisions(
        decisions: [ExtractedDecision],
        noteLookup: [UUID: Note],
        now: Date,
        calendar: Calendar
    ) -> [DecisionItem] {
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let recent = decisions
            .filter { $0.createdAt >= fourteenDaysAgo && $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }

        return Array(recent.prefix(5)).map { decision in
            let sourceNote = decision.sourceNoteId.flatMap { noteLookup[$0] }
            return DecisionItem(
                id: decision.id,
                content: decision.content,
                affects: decision.affects.isEmpty ? nil : decision.affects,
                sourceNoteTitle: sourceNote?.displayTitle ?? "Unknown Note",
                sourceNoteId: decision.sourceNoteId,
                date: decision.createdAt
            )
        }
    }

    // MARK: - Stale Items

    private static func buildStaleItems(
        notes: [Note],
        actions: [ExtractedAction],
        noteLookup: [UUID: Note],
        now: Date,
        calendar: Calendar
    ) -> [StaleItem] {
        var items: [StaleItem] = []

        // Notes with unresolved next steps older than 7 days
        for note in notes {
            guard let step = note.suggestedNextStep, note.nextStepResolvedAt == nil, !note.isArchived else { continue }
            let ageDays = calendar.dateComponents([.day], from: note.createdAt, to: now).day ?? 0
            if ageDays > 7 {
                items.append(StaleItem(
                    id: note.id,
                    noteTitle: note.displayTitle,
                    noteId: note.id,
                    unresolvedStep: step,
                    ageDays: ageDays
                ))
            }
        }

        // Actions not completed and older than 14 days
        for action in actions where !action.isCompleted {
            let ageDays = calendar.dateComponents([.day], from: action.createdAt, to: now).day ?? 0
            if ageDays > 14, let noteId = action.sourceNoteId {
                let sourceNote = noteLookup[noteId]
                items.append(StaleItem(
                    id: action.id,
                    noteTitle: sourceNote?.displayTitle ?? "Unknown Note",
                    noteId: noteId,
                    unresolvedStep: action.content,
                    ageDays: ageDays
                ))
            }
        }

        // Sort by age descending, take top 3
        return Array(items.sorted { $0.ageDays > $1.ageDays }.prefix(3))
    }
}
