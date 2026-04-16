//
//  HomeSections.swift
//  voice notes
//
//  Self-contained section views dispatched from AIHomeView via HomeLayout.
//  Each section:
//    - Takes the minimal SwiftData collection it needs as props
//    - Renders its own header, empty state, and content
//    - Navigates/dispatches callbacks rather than mutating global state
//
//  Adding a new section kind:
//    1. Add the case to HomeSectionKind in HomeLayout.swift
//    2. Add a default title in HomeSectionKind.defaultTitle
//    3. Update the purpose compile prompt to mention the new kind
//    4. Add a struct here + dispatch case in AIHomeView.sectionView(for:)
//

import SwiftUI
import SwiftData

// MARK: - Shared Section Header

struct HomeSectionHeader: View {
    let title: String
    let subtitle: String?
    let accentColor: Color

    init(_ title: String, subtitle: String? = nil, accentColor: Color = Color("EEONAccent")) {
        self.title = title
        self.subtitle = subtitle
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Priority Projects (founder / PM archetype)

struct PriorityProjectsSection: View {
    let projects: [Project]
    let title: String
    let limit: Int

    @Environment(\.modelContext) private var modelContext

    private var active: [Project] {
        projects
            .filter { !$0.isArchived }
            .sorted { a, b in
                // Active first (non-stalled), then by last activity
                let aStalled = a.isStalled
                let bStalled = b.isStalled
                if aStalled != bStalled { return !aStalled }
                let aDate = a.lastActivityAt ?? .distantPast
                let bDate = b.lastActivityAt ?? .distantPast
                return aDate > bDate
            }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title)
                VStack(spacing: 6) {
                    ForEach(active) { project in
                        ProjectRow(project: project)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color("EEONAccent"))
                .frame(width: 36, height: 36)
                .background(Color("EEONAccent").opacity(0.12))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                HStack(spacing: 8) {
                    Text("\(project.noteCount) notes")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                    if project.openActionCount > 0 {
                        Text("• \(project.openActionCount) open")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let last = project.lastActivityAt {
                        Text("• \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.eeonCard)
        .cornerRadius(12)
    }
}

// MARK: - Silent Projects (founder drift-catcher)

struct SilentProjectsSection: View {
    let projects: [Project]
    let title: String
    let staleDays: Int

    private var stalled: [Project] {
        projects
            .filter { !$0.isArchived && $0.daysSinceActivity >= staleDays && $0.daysSinceActivity < 9999 }
            .sorted { $0.daysSinceActivity > $1.daysSinceActivity }
    }

    var body: some View {
        if !stalled.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title, subtitle: "Untouched \(staleDays)+ days")
                VStack(spacing: 6) {
                    ForEach(stalled) { project in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                            Text(project.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.eeonTextPrimary)
                            Spacer()
                            Text("\(project.daysSinceActivity)d silent")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Open Decisions (founder archetype)

struct OpenDecisionsSection: View {
    let decisions: [ExtractedDecision]
    let notes: [Note]
    let title: String
    let limit: Int

    private var active: [ExtractedDecision] {
        decisions
            .filter { $0.status == "Active" || $0.status == "Pending" }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func sourceNote(for decision: ExtractedDecision) -> Note? {
        guard let id = decision.sourceNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    var body: some View {
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(active) { decision in
                        decisionRow(decision)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func decisionRow(_ decision: ExtractedDecision) -> some View {
        if let note = sourceNote(for: decision) {
            NavigationLink(destination: NoteDetailView(note: note)) {
                decisionContent(decision)
            }
            .buttonStyle(.plain)
        } else {
            decisionContent(decision)
        }
    }

    private func decisionContent(_ decision: ExtractedDecision) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.content)
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                if !decision.affects.isEmpty {
                    Text("Affects: \(decision.affects)")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.eeonTextSecondary)
        }
        .padding(10)
        .background(Color.eeonCard)
        .cornerRadius(10)
    }
}

// MARK: - Idea Inbox (sparks not yet routed)

struct IdeaInboxSection: View {
    let notes: [Note]
    let title: String
    let limit: Int

    private var ideas: [Note] {
        notes
            .filter { $0.intent == .idea && $0.projectId == nil && !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title, subtitle: "\(ideas.count) unassigned")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ideas) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.yellow)
                                    .padding(.top, 2)
                                Text(note.displayTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.eeonTextPrimary)
                                    .lineLimit(2)
                                Spacer()
                                Text(note.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                            .padding(10)
                            .background(Color.eeonCard)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Client Roster (coach archetype)

struct ClientRosterSection: View {
    let articles: [KnowledgeArticle]
    let title: String
    let limit: Int

    private var people: [KnowledgeArticle] {
        articles
            .filter { $0.articleType == .person }
            .sorted { ($0.lastMentionedAt ?? .distantPast) > ($1.lastMentionedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title)
                VStack(spacing: 6) {
                    ForEach(people) { person in
                        NavigationLink(destination: KnowledgeArticleDetailView(article: person)) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.eeonTextPrimary)
                                    if !person.summary.isEmpty {
                                        Text(person.summary)
                                            .font(.caption)
                                            .foregroundStyle(.eeonTextSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if let last = person.lastMentionedAt {
                                    Text(last.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.eeonTextSecondary)
                                }
                            }
                            .padding(10)
                            .background(Color.eeonCard)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Follow-Ups Per Client (coach archetype)

struct FollowUpsPerClientSection: View {
    let commitments: [ExtractedCommitment]
    let notes: [Note]
    let title: String
    let limit: Int

    private var open: [ExtractedCommitment] {
        commitments
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func sourceNote(for commitment: ExtractedCommitment) -> Note? {
        guard let id = commitment.sourceNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    var body: some View {
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title, subtitle: "\(open.count) open")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(open) { c in
                        commitmentRow(c)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func commitmentRow(_ c: ExtractedCommitment) -> some View {
        if let note = sourceNote(for: c) {
            NavigationLink(destination: NoteDetailView(note: note)) {
                commitmentContent(c)
            }
            .buttonStyle(.plain)
        } else {
            commitmentContent(c)
        }
    }

    private func commitmentContent(_ c: ExtractedCommitment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundStyle(.indigo)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.what)
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                if !c.who.isEmpty {
                    Text(c.who)
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.eeonTextSecondary)
        }
        .padding(10)
        .background(Color.eeonCard)
        .cornerRadius(10)
    }
}

// MARK: - Recurring Patterns (dream interpreter / journaler)

struct RecurringPatternsSection: View {
    let articles: [KnowledgeArticle]
    let title: String
    let limit: Int

    private var topics: [KnowledgeArticle] {
        articles
            .filter { $0.articleType == .topic && $0.mentionCount >= 2 }
            .sorted { $0.mentionCount > $1.mentionCount }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title, subtitle: "Across your notes")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(topics) { topic in
                            NavigationLink(destination: KnowledgeArticleDetailView(article: topic)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text("\(topic.mentionCount)×")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.orange)
                                    }
                                    Text(topic.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.eeonTextPrimary)
                                        .lineLimit(1)
                                    if !topic.summary.isEmpty {
                                        Text(topic.summary)
                                            .font(.caption)
                                            .foregroundStyle(.eeonTextSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(width: 200, alignment: .leading)
                                .padding(12)
                                .background(Color.eeonCard)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Reference Resonance (dream interpreter / researcher)

struct ReferenceResonanceSection: View {
    let articles: [KnowledgeArticle]
    let title: String
    let limit: Int

    private var refs: [KnowledgeArticle] {
        articles
            .filter { $0.articleType == .reference }
            .sorted { ($0.lastMentionedAt ?? .distantPast) > ($1.lastMentionedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HomeSectionHeader(title, subtitle: "Canon you've uploaded")
                VStack(spacing: 6) {
                    ForEach(refs) { ref in
                        NavigationLink(destination: KnowledgeArticleDetailView(article: ref)) {
                            HStack(spacing: 12) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.title3)
                                    .foregroundStyle(.brown)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ref.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.eeonTextPrimary)
                                    if !ref.summary.isEmpty {
                                        Text(ref.summary)
                                            .font(.caption)
                                            .foregroundStyle(.eeonTextSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.eeonCard)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
