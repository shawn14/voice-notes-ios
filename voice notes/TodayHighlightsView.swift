//
//  TodayHighlightsView.swift
//  voice notes
//
//  "Highlights" in the feed dropdown. Renders today's DailyBrief inline on the
//  main screen — what mattered, the highlights, suggested next steps you can
//  tick off, and anything going stale.
//
//  The brief has been generated every day since Tier 3 shipped (one AI call
//  per day, IntelligenceService.checkAndGenerateDailyBrief) and, since the
//  08-19 home simplification, shown nowhere: `dailyBriefCard` was dead code.
//  Pocket sells the same thing as "Daily highlights" on Pro. This surface
//  costs zero extra API calls — the data was already there.
//

import SwiftUI
import SwiftData

struct TodayHighlightsView: View {
    let brief: DailyBrief?
    let isRefreshing: Bool
    let sessionBrief: SessionBrief?

    @Environment(\.modelContext) private var modelContext
    @State private var showingFullBrief = false

    var body: some View {
        VStack(alignment: .leading, spacing: EEONLayout.standard) {
            if isRefreshing {
                loading
            } else if let brief {
                content(brief)
            } else {
                empty
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .sheet(isPresented: $showingFullBrief) {
            if let brief {
                DailyBriefSheet(brief: brief, sessionBrief: sessionBrief)
            }
        }
    }

    // MARK: - States

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.eeonAccent)
            Text("Preparing today's highlights…")
                .font(EEONType.body)
                .foregroundStyle(.eeonTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 44))
                .foregroundStyle(.eeonTextTertiary)
            Text("No highlights yet")
                .font(.headline)
                .foregroundStyle(.eeonTextSecondary)
            Text("EEON writes today's highlights from what you captured — what moved, what's open, what to do next. Record a few notes and check back tomorrow morning.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private func content(_ brief: DailyBrief) -> some View {
        // Freshness + full brief
        HStack {
            Text(brief.freshnessLabel)
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextTertiary)
            Spacer()
            Button("Full brief") { showingFullBrief = true }
                .font(EEONType.meta.weight(.semibold))
                .foregroundStyle(Color.eeonAccent)
                .frame(minHeight: EEONLayout.minTarget)
        }

        if !brief.whatMattersToday.isEmpty {
            Text(brief.whatMattersToday)
                .font(EEONType.body)
                .foregroundStyle(.eeonTextPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !brief.highlights.isEmpty {
            section("Highlights") {
                ForEach(brief.highlights, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.eeonAccent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(line)
                            .font(EEONType.body)
                            .foregroundStyle(.eeonTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        if !brief.suggestedActions.isEmpty {
            section("Next steps") {
                ForEach(brief.suggestedActions) { action in
                    suggestedActionRow(action, brief: brief)
                }
            }
        }

        if !brief.warnings.isEmpty {
            section("Going stale") {
                ForEach(brief.warnings) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: warning.icon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 3)
                        Text(warning.content)
                            .font(EEONType.body)
                            .foregroundStyle(.eeonTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        Color.clear.frame(height: 8)
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.eeonTextSecondary)
                .textCase(.uppercase)
            content()
        }
        .padding(.top, 4)
    }

    private func suggestedActionRow(_ action: SuggestedAction, brief: DailyBrief) -> some View {
        let done = brief.isSuggestedActionCompleted(action)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    brief.toggleSuggestedAction(action)
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(done ? Color.eeonAccent : Color.eeonTextTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.content)
                    .font(EEONType.body)
                    .foregroundStyle(done ? .eeonTextTertiary : .eeonTextPrimary)
                    .strikethrough(done, color: .eeonTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !action.reason.isEmpty {
                    Text(action.reason)
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
