//
//  KnowledgeOverviewView.swift
//  voice notes
//
//  Browse all knowledge articles by type, with stats and recent activity feed.
//

import SwiftUI
import SwiftData

struct KnowledgeOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var allArticles: [KnowledgeArticle]
    @Query(sort: \KnowledgeEvent.createdAt, order: .reverse) private var allEvents: [KnowledgeEvent]

    @State private var selectedType: ArticleFilter = .all

    enum ArticleFilter: String, CaseIterable {
        case all = "All"
        case people = "People"
        case projects = "Projects"
        case topics = "Topics"

        var articleType: KnowledgeArticleType? {
            switch self {
            case .all: return nil
            case .people: return .person
            case .projects: return .project
            case .topics: return .topic
            }
        }
    }

    private var filteredArticles: [KnowledgeArticle] {
        guard let type = selectedType.articleType else { return allArticles }
        return allArticles.filter { $0.articleType == type }
    }

    private var updatedTodayCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return allArticles.filter { article in
            guard let compiled = article.lastCompiledAt else { return false }
            return compiled >= today
        }.count
    }

    private var ingestedThisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allEvents.filter { $0.eventType == .ingest && $0.createdAt >= weekAgo }.count
    }

    private var recentEvents: [KnowledgeEvent] {
        Array(allEvents.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats header
                statsHeader

                // Filter picker
                Picker("Filter", selection: $selectedType) {
                    ForEach(ArticleFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Articles list
                if filteredArticles.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredArticles) { article in
                            NavigationLink(destination: KnowledgeArticleDetailView(article: article)) {
                                articleRow(article)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                // Recent activity
                if !recentEvents.isEmpty {
                    recentActivitySection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Knowledge Base")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 16) {
            statBadge(value: "\(allArticles.count)", label: "Articles")
            statBadge(value: "\(updatedTodayCount)", label: "Updated Today")
            statBadge(value: "\(ingestedThisWeekCount)", label: "Ingested This Week")
        }
        .padding(.horizontal)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.eeonTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.eeonCard)
        .cornerRadius(12)
    }

    // MARK: - Article Row

    private func articleRow(_ article: KnowledgeArticle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: article.articleType.icon)
                .font(.title3)
                .foregroundStyle(.eeonAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(article.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)

                    Spacer()

                    Text("\(article.mentionCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.eeonAccent.opacity(0.12))
                        .cornerRadius(8)
                }

                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.caption)
                        .foregroundStyle(.eeonTextTertiary)
                        .lineLimit(2)
                }

                if let compiled = article.lastCompiledAt {
                    Text(compiled, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.eeonTextSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.eeonCard)
        .cornerRadius(12)
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
                .padding(.horizontal)

            LazyVStack(spacing: 6) {
                ForEach(recentEvents) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.eventType.icon)
                            .font(.caption)
                            .foregroundStyle(.eeonTextSecondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.eeonTextPrimary)

                            if let detail = event.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(event.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(.eeonTextTertiary)
            Text("No knowledge articles yet")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
            Text("Record voice notes or share articles to build your knowledge base")
                .font(.caption)
                .foregroundStyle(.eeonTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}
