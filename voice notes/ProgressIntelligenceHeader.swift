//
//  ProgressIntelligenceHeader.swift
//  voice notes
//
//  Summary header showing health, momentum, and dropped balls
//

import SwiftUI
import SwiftData

struct ProgressIntelligenceHeader: View {
    let items: [KanbanItem]
    let movements: [KanbanMovement]
    let onDroppedBallsTap: () -> Void

    private var healthCounts: (strong: Int, atRisk: Int, stalled: Int) {
        HealthScoreService.healthCounts(for: items)
    }

    private var momentum: MomentumStats {
        MomentumService.calculateMomentum(movements: movements, items: items)
    }

    private var droppedBalls: [DroppedBall] {
        HealthScoreService.detectDroppedBalls(items: items)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Health indicators
            HStack(spacing: 6) {
                if healthCounts.strong > 0 {
                    HealthDot(count: healthCounts.strong, status: .strong)
                }
                if healthCounts.atRisk > 0 {
                    HealthDot(count: healthCounts.atRisk, status: .atRisk)
                }
                if healthCounts.stalled > 0 {
                    HealthDot(count: healthCounts.stalled, status: .stalled)
                }
            }

            Divider()
                .frame(height: 20)

            // Momentum
            MomentumIndicator(stats: momentum)

            Spacer()

            // Dropped balls
            if !droppedBalls.isEmpty {
                Button(action: onDroppedBallsTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("\(droppedBalls.count) need attention")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Health Dot

struct HealthDot: View {
    let count: Int
    let status: HealthStatus

    var color: Color {
        switch status {
        case .strong: return .green
        case .atRisk: return .orange
        case .stalled: return .red
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Momentum Indicator

struct MomentumIndicator: View {
    let stats: MomentumStats

    var color: Color {
        switch stats.direction {
        case .up: return .green
        case .down: return .orange
        case .flat: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("Momentum")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: stats.direction.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Dropped Balls Sheet

struct DroppedBallsSheet: View {
    let droppedBalls: [DroppedBall]
    let onMoveItem: (KanbanItem, KanbanColumn) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if droppedBalls.isEmpty {
                    ContentUnavailableView(
                        "All Clear",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing needs your attention right now.")
                    )
                } else {
                    ForEach(droppedBalls) { ball in
                        DroppedBallRow(ball: ball, onMove: { column in
                            onMoveItem(ball.item, column)
                        })
                    }
                }
            }
            .navigationTitle("Needs Attention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DroppedBallRow: View {
    let ball: DroppedBall
    let onMove: (KanbanColumn) -> Void

    var reasonColor: Color {
        switch ball.reason {
        case .decisionWithoutAction: return .blue
        case .stuckInColumn: return .orange
        case .openCommitment: return .blue
        }
    }

    var reasonLabel: String {
        switch ball.reason {
        case .decisionWithoutAction: return "No Actions"
        case .stuckInColumn: return "Stuck"
        case .openCommitment: return "Open Commitment"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(reasonLabel)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(reasonColor.opacity(0.2))
                    .foregroundStyle(reasonColor)
                    .cornerRadius(4)

                Spacer()

                Text("\(ball.daysSinceIssue)d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Item content
            Text(ball.item.content)
                .font(.subheadline)

            // Description
            Text(ball.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quick actions
            HStack(spacing: 8) {
                ForEach([KanbanColumn.doing, .done], id: \.self) { column in
                    if column != ball.item.kanbanColumn {
                        Button {
                            onMove(column)
                        } label: {
                            Label(column.rawValue, systemImage: column.icon)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ProgressIntelligenceHeader(
            items: [],
            movements: [],
            onDroppedBallsTap: {}
        )
        Spacer()
    }
}
