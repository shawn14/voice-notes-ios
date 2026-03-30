//
//  ExtractionChipsView.swift
//  voice notes
//
//  Tappable extraction chips that flow into AssistantView queries.
//

import SwiftUI

// MARK: - Chip Category

enum ChipCategory {
    case decision
    case action
    case commitment
    case person
    case topic

    var color: Color {
        switch self {
        case .decision: return .green
        case .action: return .orange
        case .commitment: return .blue
        case .person: return .purple
        case .topic: return Color("EEONTextSecondary")
        }
    }

    var icon: String {
        switch self {
        case .decision: return "checkmark.seal.fill"
        case .action: return "circle"
        case .commitment: return "handshake.fill"
        case .person: return "person.fill"
        case .topic: return "tag.fill"
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: maxWidth, height: y + rowHeight)
        )
    }
}

// MARK: - Extraction Chip View

struct ExtractionChipView: View {
    let text: String
    let category: ChipCategory
    var isCompact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(isCompact ? .caption2 : .caption)
                Text(text)
                    .font(isCompact ? .caption : .subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.vertical, isCompact ? 4 : 6)
            .background(category.color.opacity(0.15))
            .foregroundStyle(category.color)
            .cornerRadius(isCompact ? 6 : 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Chip View (with checkbox)

struct ActionChipView: View {
    let action: ExtractedAction
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(action.isCompleted ? .green : .orange)
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                Text(action.content)
                    .font(.subheadline)
                    .lineLimit(1)
                    .strikethrough(action.isCompleted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(action.isCompleted ? 0.08 : 0.15))
        .foregroundStyle(action.isCompleted ? .gray : .orange)
        .cornerRadius(8)
    }
}

// MARK: - Extraction Chips Section

struct ExtractionChipsSection: View {
    let decisions: [ExtractedDecision]
    let actions: [ExtractedAction]
    let commitments: [ExtractedCommitment]
    let people: [String]
    let topics: [String]
    let onChipTap: (String) -> Void
    let onActionToggle: (ExtractedAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Decisions
            if !decisions.isEmpty {
                chipGroup(title: "Decisions", icon: "checkmark.seal.fill", color: .green) {
                    FlowLayout(spacing: 8) {
                        ForEach(decisions) { decision in
                            ExtractionChipView(
                                text: decision.content,
                                category: .decision,
                                onTap: {
                                    onChipTap("Tell me more about the decision to \(decision.content)")
                                }
                            )
                        }
                    }
                }
            }

            // Actions
            if !actions.isEmpty {
                chipGroup(title: "Actions", icon: "bolt.fill", color: .orange) {
                    FlowLayout(spacing: 8) {
                        ForEach(actions) { action in
                            ActionChipView(
                                action: action,
                                onTap: {
                                    onChipTap("What else did I say about \(action.content)?")
                                },
                                onToggle: {
                                    onActionToggle(action)
                                }
                            )
                        }
                    }
                }
            }

            // Commitments
            if !commitments.isEmpty {
                chipGroup(title: "Commitments", icon: "handshake.fill", color: .blue) {
                    FlowLayout(spacing: 8) {
                        ForEach(commitments) { commitment in
                            ExtractionChipView(
                                text: "\(commitment.who): \(commitment.what)",
                                category: .commitment,
                                onTap: {
                                    onChipTap("What did I promise \(commitment.who)?")
                                }
                            )
                        }
                    }
                }
            }

            // People
            if !people.isEmpty {
                chipGroup(title: "People", icon: "person.2.fill", color: .purple) {
                    FlowLayout(spacing: 8) {
                        ForEach(people, id: \.self) { person in
                            ExtractionChipView(
                                text: person,
                                category: .person,
                                onTap: {
                                    onChipTap("What have I said about \(person)?")
                                }
                            )
                        }
                    }
                }
            }

            // Topics
            if !topics.isEmpty {
                chipGroup(title: "Topics", icon: "tag.fill", color: .gray) {
                    FlowLayout(spacing: 6) {
                        ForEach(topics, id: \.self) { topic in
                            ExtractionChipView(
                                text: topic,
                                category: .topic,
                                isCompact: true,
                                onTap: {
                                    onChipTap("Summarize everything about \(topic)")
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chipGroup<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }

            content()
        }
    }
}
