//
//  NoteWikiConnectionsView.swift
//  voice notes
//
//  Karpathy-pattern note-level connections — render the wiki pages this note touched.
//  Reverse-lookup on KnowledgeArticle.linkedNoteIds. Hides chrome when empty.
//

import SwiftUI
import SwiftData

struct NoteWikiConnectionsView: View {
    let noteId: UUID

    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var allArticles: [KnowledgeArticle]

    private var connectedArticles: [KnowledgeArticle] {
        allArticles.filter { article in
            guard article.articleType != .index else { return false }
            return article.linkedNoteIds.contains(noteId)
        }
    }

    var body: some View {
        if !connectedArticles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.eeonTextSecondary)
                    Text("Connects to")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.eeonTextSecondary)
                        .textCase(.uppercase)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(connectedArticles) { article in
                            NavigationLink(destination: KnowledgeArticleDetailView(article: article)) {
                                connectionChip(article: article)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionChip(article: KnowledgeArticle) -> some View {
        HStack(spacing: 6) {
            Image(systemName: article.articleType.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(typeColor(for: article.articleType))

            Text(article.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(typeColor(for: article.articleType).opacity(0.10))
        .overlay(
            Capsule()
                .strokeBorder(typeColor(for: article.articleType).opacity(0.25), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func typeColor(for type: KnowledgeArticleType) -> Color {
        switch type {
        case .person: return .purple
        case .project: return .green
        case .topic: return .orange
        case .self: return Color("EEONAccent")
        case .purpose: return .indigo
        case .reference: return .brown
        case .index: return .cyan
        }
    }
}
