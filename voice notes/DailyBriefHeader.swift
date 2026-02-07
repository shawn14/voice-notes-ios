//
//  DailyBriefHeader.swift
//  voice notes
//
//  Collapsible card showing daily brief summary in HomeView
//

import SwiftUI
import SwiftData

struct DailyBriefHeader: View {
    let brief: DailyBrief?
    let sessionBrief: SessionBrief?
    let isGenerating: Bool
    let error: String?
    let onRetry: () -> Void

    @State private var showingFullBrief = false

    var body: some View {
        Button {
            if brief != nil {
                showingFullBrief = true
            } else if error != nil {
                onRetry()
            }
        } label: {
            HStack(spacing: 12) {
                // Freshness indicator
                FreshnessIndicator(
                    brief: brief,
                    sessionBrief: sessionBrief,
                    isGenerating: isGenerating
                )

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    if isGenerating {
                        Text("Preparing your daily brief...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    } else if error != nil {
                        Text("Couldn't load brief")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("Tap to retry")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    } else if let brief = brief {
                        Text(briefSummary(brief))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Text(brief.freshnessLabel)
                                .font(.caption)
                                .foregroundStyle(.gray)

                            if brief.stalledItemCount > 0 {
                                Text("•")
                                    .foregroundStyle(.gray)
                                Text("\(brief.stalledItemCount) needs attention")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        // Show first priority action
                        if let firstAction = brief.suggestedActions.first {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text(firstAction.content)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .padding(.top, 4)
                        }
                    } else if let session = sessionBrief {
                        Text(sessionSummary(session))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(session.freshnessLabel)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    } else {
                        Text("Your daily brief will appear here")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                // Chevron
                if brief != nil || sessionBrief != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(16)
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingFullBrief) {
            if let brief = brief {
                DailyBriefSheet(brief: brief, sessionBrief: sessionBrief)
            }
        }
    }

    private func briefSummary(_ brief: DailyBrief) -> String {
        if !brief.whatMattersToday.isEmpty {
            return brief.whatMattersToday
        }
        if let first = brief.highlights.first {
            return first
        }
        return "Your brief for today is ready"
    }

    private func sessionSummary(_ session: SessionBrief) -> String {
        let stats = session.quickStats
        var parts: [String] = []

        if stats.notesToday > 0 {
            parts.append("\(stats.notesToday) note\(stats.notesToday == 1 ? "" : "s") today")
        }
        if stats.openActions > 0 {
            parts.append("\(stats.openActions) open action\(stats.openActions == 1 ? "" : "s")")
        }
        if stats.stalledItemCount > 0 {
            parts.append("\(stats.stalledItemCount) stalled")
        }

        if parts.isEmpty {
            return "All caught up"
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Freshness Indicator

struct FreshnessIndicator: View {
    let brief: DailyBrief?
    let sessionBrief: SessionBrief?
    let isGenerating: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
                .frame(width: 44, height: 44)

            if isGenerating {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.blue)
            } else {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var backgroundColor: Color {
        if isGenerating { return .blue }
        if brief != nil { return .green }
        if sessionBrief?.isSoftExpired == true { return .yellow }
        return .gray
    }

    private var iconName: String {
        if brief != nil { return "sun.max.fill" }
        if sessionBrief != nil { return "sparkles" }
        return "moon.fill"
    }

    private var iconColor: Color {
        if brief != nil {
            // Fresh today = green, older = yellow
            if brief!.isFromToday {
                return .green
            } else {
                return .yellow
            }
        }
        if sessionBrief != nil {
            return sessionBrief!.isSoftExpired ? .yellow : .blue
        }
        return .gray
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            DailyBriefHeader(
                brief: nil as DailyBrief?,
                sessionBrief: nil as SessionBrief?,
                isGenerating: true,
                error: nil as String?,
                onRetry: {}
            )

            DailyBriefHeader(
                brief: nil as DailyBrief?,
                sessionBrief: nil as SessionBrief?,
                isGenerating: false,
                error: "Network error",
                onRetry: {}
            )
        }
        .padding()
    }
}
