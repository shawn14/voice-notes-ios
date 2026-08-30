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

    private var indexArticle: KnowledgeArticle? {
        libraryVisibleArticles(allArticles).first { $0.articleType == .index && !$0.summary.isEmpty }
    }

    private var filteredArticles: [KnowledgeArticle] {
        // Exclude the index article from the list — it's surfaced separately as the hero card.
        let visible = libraryVisibleArticles(allArticles).filter { $0.articleType != .index }
        guard let type = selectedType.articleType else { return visible }
        return visible.filter { $0.articleType == type }
    }

    private var updatedTodayCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return libraryVisibleArticles(allArticles).filter { article in
            guard let compiled = article.lastCompiledAt else { return false }
            return compiled >= today
        }.count
    }

    private var ingestedThisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allEvents.filter { $0.eventType == .ingest && $0.createdAt >= weekAgo }.count
    }

    private var recentEvents: [KnowledgeEvent] {
        Array(allEvents.filter { !libraryIsSchemaSeedName($0.title) }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero: LLM-compiled overview of the wiki itself ("you are here")
                if let indexArticle {
                    indexHeroCard(article: indexArticle)
                        .padding(.horizontal)
                }

                // Stats header
                statsHeader

                NavigationLink(destination: KnowledgeMindMapView()) {
                    HStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Memory Map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Color.eeonAccentAI)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

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

    // MARK: - Index Hero Card

    @ViewBuilder
    private func indexHeroCard(article: KnowledgeArticle) -> some View {
        NavigationLink(destination: KnowledgeArticleDetailView(article: article)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: KnowledgeArticleType.index.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("Overview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .textCase(.uppercase)
                    Spacer()
                    if let compiled = article.lastCompiledAt {
                        Text(compiled, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }

                Text(article.summary)
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.10), Color.eeonCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 16) {
            statBadge(value: "\(libraryVisibleArticles(allArticles).count)", label: "Articles")
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

// MARK: - Knowledge Mind Map

private struct KnowledgeMindMapView: View {
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse)
    private var articles: [KnowledgeArticle]

    private var visibleArticles: [KnowledgeArticle] {
        libraryVisibleArticles(articles)
            .filter { $0.articleType != .purpose && !$0.summary.isEmpty }
            .prefix(24)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if visibleArticles.isEmpty {
                    ContentUnavailableView(
                        "No Map Yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Record or import more notes to build connected knowledge.")
                    )
                    .frame(minHeight: 360)
                } else {
                    GeometryReader { proxy in
                        let layout = nodeLayout(in: proxy.size)
                        ZStack {
                            Canvas { context, _ in
                                for edge in edges(layout: layout) {
                                    var path = Path()
                                    path.move(to: edge.from)
                                    path.addLine(to: edge.to)
                                    context.stroke(
                                        path,
                                        with: .color(Color.eeonTextTertiary.opacity(0.28)),
                                        lineWidth: 1
                                    )
                                }
                            }

                            ForEach(layout) { node in
                                NavigationLink(destination: KnowledgeArticleDetailView(article: node.article)) {
                                    VStack(spacing: 4) {
                                        Image(systemName: node.article.articleType.icon)
                                            .font(.caption.weight(.semibold))
                                        Text(node.article.name)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .foregroundStyle(.eeonTextPrimary)
                                    .frame(width: node.diameter, height: node.diameter)
                                    .background(node.article.articleType.mapColor.opacity(0.18))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(node.article.articleType.mapColor.opacity(0.45), lineWidth: 1)
                                    )
                                    .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .position(node.point)
                            }
                        }
                    }
                    .frame(height: 540)
                    .background(Color.eeonCard.opacity(0.55))
                    .cornerRadius(14)

                    connectionList
                }
            }
            .padding()
        }
        .navigationTitle("Memory Map")
        .navigationBarTitleDisplayMode(.large)
    }

    private var connectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)

            let connected = visibleArticles.filter { !$0.connections.isEmpty }
            if connected.isEmpty {
                Text("Connections appear as EEON compiles links between people, projects, and topics.")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
            } else {
                ForEach(connected) { article in
                    ForEach(article.connections) { connection in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.eeonAccentAI)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(article.name) -> \(connection.articleName)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.eeonTextPrimary)
                                Text(connection.reason)
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.eeonCard)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private func nodeLayout(in size: CGSize) -> [MindMapNode] {
        let articles = visibleArticles
        guard !articles.isEmpty else { return [] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(120, min(size.width, size.height) * 0.36)
        let centerArticle = articles.first { $0.articleType == .index } ?? articles.first
        let outerArticles = articles.filter { $0.id != centerArticle?.id }

        var nodes: [MindMapNode] = []
        if let centerArticle {
            nodes.append(MindMapNode(article: centerArticle, point: center, diameter: 112))
        }

        for (index, article) in outerArticles.enumerated() {
            let angle = (Double(index) / Double(max(outerArticles.count, 1))) * Double.pi * 2 - Double.pi / 2
            let ringAdjust = CGFloat(index % 2) * 34
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (radius + ringAdjust),
                y: center.y + CGFloat(sin(angle)) * (radius + ringAdjust)
            )
            nodes.append(MindMapNode(article: article, point: point, diameter: 92))
        }
        return nodes
    }

    private func edges(layout: [MindMapNode]) -> [(from: CGPoint, to: CGPoint)] {
        var byName: [String: CGPoint] = [:]
        for node in layout {
            byName[node.article.name.lowercased()] = node.point
        }
        return layout.flatMap { node in
            node.article.connections.compactMap { connection in
                guard let to = byName[connection.articleName.lowercased()] else { return nil }
                return (from: node.point, to: to)
            }
        }
    }
}

private struct MindMapNode: Identifiable {
    var id: UUID { article.id }
    let article: KnowledgeArticle
    let point: CGPoint
    let diameter: CGFloat
}

private extension KnowledgeArticleType {
    var mapColor: Color {
        switch self {
        case .person: return .blue
        case .project: return .green
        case .topic: return .orange
        case .self: return .purple
        case .purpose: return .indigo
        case .reference: return .brown
        case .index: return .cyan
        }
    }
}
