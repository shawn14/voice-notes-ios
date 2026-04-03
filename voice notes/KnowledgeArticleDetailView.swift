//
//  KnowledgeArticleDetailView.swift
//  voice notes
//
//  Full detail view for a KnowledgeArticle — summary, threads, timeline, connections
//

import SwiftUI
import SwiftData

struct KnowledgeArticleDetailView: View {
    let article: KnowledgeArticle

    @Environment(\.colorScheme) var colorScheme
    @Query(sort: \Note.createdAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var allArticles: [KnowledgeArticle]

    private var linkedNotes: [Note] {
        let ids = Set(article.linkedNoteIds)
        return allNotes.filter { ids.contains($0.id) }
    }

    private var typeColor: Color {
        switch article.articleType {
        case .person: return .purple
        case .project: return .green
        case .topic: return .orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if !article.summary.isEmpty {
                    summarySection
                }

                contextSection

                if !article.openThreads.isEmpty {
                    openThreadsSection
                }

                if !article.decisions.isEmpty && article.articleType == .project {
                    decisionsSection
                }

                if let arc = article.sentimentArc, !arc.isEmpty {
                    sentimentSection(arc: arc)
                }

                if !article.connections.isEmpty {
                    connectionsSection
                }

                if !article.timeline.isEmpty {
                    timelineSection
                }

                if !linkedNotes.isEmpty {
                    sourceNotesSection
                }
            }
            .padding()
        }
        .background(Color("EEONBackground"))
        .navigationTitle(article.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: article.articleType.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(typeColor)
                .frame(width: 44, height: 44)
                .background(typeColor.opacity(0.12))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.articleType.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(typeColor)
                    .textCase(.uppercase)

                Text("\(article.mentionCount) mention\(article.mentionCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer()

            if let compiled = article.lastCompiledAt {
                Text("Updated \(compiled.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.eeonTextTertiary)
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.summary)
                .font(.body)
                .foregroundStyle(.eeonTextPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Context

    @ViewBuilder
    private var contextSection: some View {
        if let rel = article.relationshipContext, !rel.isEmpty {
            labeledCard(label: "Relationship", text: rel, icon: "person.2.fill", color: .purple)
        }
        if let evolution = article.thinkingEvolution, !evolution.isEmpty {
            labeledCard(label: "How Your Thinking Evolved", text: evolution, icon: "arrow.triangle.swap", color: .blue)
        }
    }

    // MARK: - Open Threads

    @ViewBuilder
    private var openThreadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Open Threads", icon: "circle.dotted", color: typeColor)

            ForEach(article.openThreads) { thread in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(threadColor(status: thread.status))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.thread)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)

                        HStack(spacing: 8) {
                            Text(thread.status.capitalized)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(threadColor(status: thread.status))

                            if thread.daysOpen > 0 {
                                Text("\(thread.daysOpen)d open")
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Decisions

    @ViewBuilder
    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Decisions", icon: "checkmark.seal.fill", color: .green)

            ForEach(article.decisions) { decision in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: decision.status == "resolved" ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(decision.status == "resolved" ? .green : .orange)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.decision)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)

                        if let date = decision.date {
                            Text(date)
                                .font(.caption2)
                                .foregroundStyle(.eeonTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Sentiment Arc

    @ViewBuilder
    private func sentimentSection(arc: String) -> some View {
        labeledCard(label: "Sentiment Arc", text: arc, icon: "waveform.path.ecg", color: typeColor)
    }

    // MARK: - Connections

    @ViewBuilder
    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Connected To", icon: "link", color: .blue)

            ForEach(article.connections) { connection in
                if let linked = allArticles.first(where: { $0.name == connection.articleName }) {
                    NavigationLink(destination: KnowledgeArticleDetailView(article: linked)) {
                        connectionRow(connection: connection)
                    }
                    .buttonStyle(.plain)
                } else {
                    connectionRow(connection: connection)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func connectionRow(connection: ArticleConnection) -> some View {
        HStack(spacing: 10) {
            Text(connection.articleName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.eeonTextPrimary)

            Spacer()

            Text(connection.reason)
                .font(.caption)
                .foregroundStyle(.eeonTextTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Timeline", icon: "clock.fill", color: .secondary)

            ForEach(article.timeline) { event in
                HStack(alignment: .top, spacing: 10) {
                    Text(event.date)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.eeonTextTertiary)
                        .frame(width: 70, alignment: .leading)

                    Text(event.event)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextPrimary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Source Notes

    @ViewBuilder
    private var sourceNotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Source Notes", icon: "doc.text.fill", color: .secondary)

            ForEach(linkedNotes.prefix(10)) { note in
                NavigationLink(destination: NoteDetailView(note: note)) {
                    HStack(spacing: 10) {
                        Text(note.displayTitle)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            if linkedNotes.count > 10 {
                Text("+ \(linkedNotes.count - 10) more notes")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.eeonTextPrimary)
        }
    }

    @ViewBuilder
    private func labeledCard(label: String, text: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: label, icon: icon, color: color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    private func threadColor(status: String) -> Color {
        switch status.lowercased() {
        case "open": return .orange
        case "waiting": return .blue
        case "stale": return .red
        default: return .gray
        }
    }
}
