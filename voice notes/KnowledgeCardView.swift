//
//  KnowledgeCardView.swift
//  voice notes
//
//  Compact card for horizontal scroll in AIHomeView
//

import SwiftUI

struct KnowledgeCardView: View {
    let article: KnowledgeArticle

    @Environment(\.colorScheme) var colorScheme

    private var typeColor: Color {
        switch article.articleType {
        case .person: return .purple
        case .project: return .green
        case .topic: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: icon + name
            HStack(spacing: 8) {
                Image(systemName: article.articleType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(typeColor)
                    .frame(width: 28, height: 28)
                    .background(typeColor.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(article.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(1)

                    Text("\(article.mentionCount) mention\(article.mentionCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextSecondary)
                }

                Spacer()

                if article.isRecentlyUpdated {
                    Circle()
                        .fill(typeColor)
                        .frame(width: 6, height: 6)
                }
            }

            // Summary
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(.eeonTextTertiary)
                    .lineLimit(3)
            }

            // Open threads count
            if !article.openThreads.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dotted")
                        .font(.caption2)
                    Text("\(article.openThreads.count) open thread\(article.openThreads.count == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .foregroundStyle(typeColor)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

// Placeholder until Task 7 creates the real view
struct KnowledgeArticleDetailView: View {
    let article: KnowledgeArticle
    var body: some View {
        Text(article.name)
            .navigationTitle(article.name)
    }
}
