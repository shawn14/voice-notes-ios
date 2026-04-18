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
        case .self: return Color("EEONAccent")
        case .purpose: return .indigo
        case .reference: return .brown
        }
    }

    // MARK: - Staleness

    private var daysSinceLastMention: Int? {
        guard let last = article.lastMentionedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    private var freshnessLabel: String {
        guard let days = daysSinceLastMention else { return "never mentioned" }
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        return "\(days / 30)mo ago"
    }

    private var isStale: Bool {
        (daysSinceLastMention ?? 0) > 14
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + name + freshness badge
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: article.articleType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(typeColor)
                    .frame(width: 28, height: 28)
                    .background(typeColor.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(article.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(article.articleType.label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(typeColor)
                        .tracking(0.5)
                }

                Spacer(minLength: 0)

                if article.isRecentlyUpdated {
                    Circle()
                        .fill(typeColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                }
            }

            // Summary — the LLM-compiled paragraph. Primary content of the card.
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // Bottom strip: freshness · open signal · mentions
            HStack(spacing: 8) {
                // Freshness — when last touched, stale in orange if > 2w
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(freshnessLabel)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(isStale ? .orange : .eeonTextSecondary)

                // Primary open signal — type-specific substance
                if let substance = openSignal {
                    Text("·")
                        .foregroundStyle(.eeonTextSecondary)
                    HStack(spacing: 3) {
                        Image(systemName: substance.icon)
                            .font(.system(size: 9))
                        Text(substance.label)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(typeColor)
                }

                Spacer(minLength: 0)

                // Total mention count as tiny badge on the right
                Text("\(article.mentionCount)×")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
        .padding(14)
        .frame(width: 240, height: 170, alignment: .topLeading)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isStale ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Open Signal

    /// Type-specific substance shown in the bottom strip. Gives each article kind
    /// a "what's alive in this card" signal beyond just mention count.
    private struct OpenSignal {
        let icon: String
        let label: String
    }

    private var openSignal: OpenSignal? {
        switch article.articleType {
        case .person:
            if !article.openThreads.isEmpty {
                return OpenSignal(icon: "circle.dotted", label: "\(article.openThreads.count) open")
            }
            if let arc = article.sentimentArc, !arc.isEmpty {
                return OpenSignal(icon: "heart", label: "evolving")
            }
            return nil
        case .project:
            let openDecisions = article.decisions.filter { $0.status.lowercased() == "open" }.count
            if openDecisions > 0 {
                return OpenSignal(icon: "checkmark.seal", label: "\(openDecisions) decision\(openDecisions == 1 ? "" : "s") open")
            }
            if !article.openThreads.isEmpty {
                return OpenSignal(icon: "circle.dotted", label: "\(article.openThreads.count) threads")
            }
            return nil
        case .topic, .`self`, .purpose:
            if !article.openThreads.isEmpty {
                return OpenSignal(icon: "questionmark.circle", label: "\(article.openThreads.count) open")
            }
            return nil
        case .reference:
            // Reference material — the signal is "how often has EEON leaned on this?"
            if article.mentionCount >= 3 {
                return OpenSignal(icon: "quote.bubble", label: "cited")
            }
            return nil
        }
    }
}
