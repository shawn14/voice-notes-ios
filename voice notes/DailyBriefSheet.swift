//
//  DailyBriefSheet.swift
//  voice notes
//
//  Full daily brief details sheet
//

import SwiftUI
import SwiftData

struct DailyBriefSheet: View {
    let brief: DailyBrief
    let sessionBrief: SessionBrief?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero Section
                    HeroSection(brief: brief)

                    // Highlights
                    if !brief.highlights.isEmpty {
                        HighlightsSection(highlights: brief.highlights)
                    }

                    // Priorities / Suggested Actions
                    if !brief.suggestedActions.isEmpty {
                        PrioritiesSection(actions: brief.suggestedActions)
                    }

                    // Warnings
                    if !brief.warnings.isEmpty {
                        WarningsSection(warnings: brief.warnings)
                    }

                    // Session Intelligence
                    if let session = sessionBrief {
                        SessionIntelligenceSection(session: session)
                    }

                    // Metrics Footer
                    MetricsFooter(brief: brief)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Daily Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Hero Section

private struct HeroSection: View {
    let brief: DailyBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)

                Text("Here's what matters today")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(brief.whatMattersToday)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                DailyBriefMomentumBadge(direction: brief.momentum)

                Text(brief.freshnessLabel)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }
}

// MARK: - Daily Brief Momentum Badge

private struct DailyBriefMomentumBadge: View {
    let direction: MomentumDirection

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .font(.caption.weight(.medium))

            Text("Momentum \(direction.label)")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(colorFor(direction))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorFor(direction).opacity(0.15))
        .cornerRadius(8)
    }

    private func colorFor(_ direction: MomentumDirection) -> Color {
        switch direction {
        case .up: return .green
        case .down: return .orange
        case .flat: return .gray
        }
    }
}

// MARK: - Highlights Section

private struct HighlightsSection: View {
    let highlights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Highlights")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(highlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)

                    Text(highlight)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Priorities Section

private struct PrioritiesSection: View {
    let actions: [SuggestedAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(.blue)
                Text("Focus Areas")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            ForEach(actions) { action in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: action.icon)
                            .foregroundStyle(priorityColor(action.priority))
                            .font(.body)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.content)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Text(action.reason)
                                .font(.caption)
                                .foregroundStyle(.gray)

                            if let project = action.projectName {
                                Text(project)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(12)
    }

    private func priorityColor(_ priority: SuggestedAction.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

// MARK: - Warnings Section

private struct WarningsSection: View {
    let warnings: [DailyWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Needs Attention")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: warning.icon)
                        .foregroundStyle(colorFor(warning.color))
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.content)
                            .font(.subheadline)
                            .foregroundStyle(.white)

                        Text("\(warning.daysSinceIssue) days")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        default: return .orange
        }
    }
}

// MARK: - Session Intelligence Section

private struct SessionIntelligenceSection: View {
    let session: SessionBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Live Status")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            // Top Active Projects
            if !session.topActiveProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Projects")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))

                    ForEach(session.topActiveProjects) { project in
                        HStack(spacing: 12) {
                            Image(systemName: project.icon)
                                .foregroundStyle(colorFor(project.colorName))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)

                                Text(project.activityLabel)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            if project.openActionCount > 0 {
                                Text("\(project.openActionCount) open")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            // Quick Stats
            HStack(spacing: 16) {
                StatBadge(
                    value: "\(session.quickStats.openActions)",
                    label: "Open",
                    color: .blue
                )
                StatBadge(
                    value: "\(session.quickStats.stalledItemCount)",
                    label: "Stalled",
                    color: session.quickStats.stalledItemCount > 0 ? .orange : .gray
                )
                StatBadge(
                    value: "\(session.quickStats.notesToday)",
                    label: "Today",
                    color: .green
                )
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(12)
    }

    private func colorFor(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        default: return .blue
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Metrics Footer

private struct MetricsFooter: View {
    let brief: DailyBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snapshot")
                .font(.caption.weight(.medium))
                .foregroundStyle(.gray)

            HStack(spacing: 16) {
                FooterStat(label: "Open Items", value: "\(brief.openItemCount)")
                FooterStat(label: "Active Projects", value: "\(brief.activeProjectCount)")
                FooterStat(label: "Notes This Week", value: "\(brief.notesThisWeek)")
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

private struct FooterStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    let brief = DailyBrief()
    brief.whatMattersToday = "Focus on the investor pitch deck and follow up with the design team about the new onboarding flow."
    brief.highlights = [
        "Investor meeting scheduled for Thursday",
        "Design review completed yesterday",
        "3 new feature requests from customers"
    ]

    return DailyBriefSheet(brief: brief, sessionBrief: nil)
}
