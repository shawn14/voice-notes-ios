//
//  MomentumPictureSection.swift
//  voice notes
//
//  Home section that observes capture activity against the user's declared
//  focus items. Renders an activity bar per item plus a one-line drift
//  callout when the user's stated #1 priority doesn't match observed
//  capture density. Pure local computation — no LLM calls.
//

import SwiftUI
import SwiftData

struct MomentumPictureSection: View {
    let title: String
    let rationale: String?
    let focusItems: [FocusItem]
    let notes: [Note]

    private static let lookbackDays: Int = 14

    var body: some View {
        if focusItems.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let activity = computeActivity()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                Spacer()
            }

            if let rationale = rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .padding(.bottom, 4)
            }

            VStack(spacing: 8) {
                ForEach(activity) { row in
                    activityRow(row)
                }
            }

            if let drift = driftMessage(activity) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(drift)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }

    private func activityRow(_ row: ActivityRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                Text("\(row.item.weight.label) · \(row.activityLabel)")
                    .font(.caption2)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.eeonTextSecondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: row.item.weight))
                        .frame(width: geo.size.width * row.normalizedScore)
                }
            }
            .frame(width: 80, height: 6)
        }
        .padding(.vertical, 4)
    }

    private func barColor(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return Color("EEONAccent")
        case .secondary: return Color("EEONAccent").opacity(0.55)
        case .tertiary: return Color.eeonTextSecondary.opacity(0.45)
        }
    }

    // MARK: - Computation

    private struct ActivityRow: Identifiable {
        let item: FocusItem
        let noteCount: Int
        let normalizedScore: Double
        var id: UUID { item.id }
        var activityLabel: String {
            switch noteCount {
            case 0: return "silent"
            case 1: return "1 note"
            default: return "\(noteCount) notes"
            }
        }
    }

    private func computeActivity() -> [ActivityRow] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? Date()
        let recentNotes = notes.filter { $0.createdAt >= cutoff }

        let counts: [UUID: Int] = focusItems.reduce(into: [:]) { acc, item in
            let needle = item.content.lowercased()
            let count = recentNotes.filter { note in
                let proj = note.inferredProject?.lowercased() ?? ""
                let content = note.content.lowercased()
                return proj.contains(needle) || content.contains(needle)
            }.count
            acc[item.id] = count
        }

        let maxCount = max(counts.values.max() ?? 0, 1)
        return focusItems.map { item in
            let count = counts[item.id] ?? 0
            let normalized = Double(count) / Double(maxCount)
            return ActivityRow(item: item, noteCount: count, normalizedScore: normalized)
        }
    }

    private func driftMessage(_ rows: [ActivityRow]) -> String? {
        guard let primary = rows.first(where: { $0.item.weight == .primary }) else { return nil }
        let dominant = rows.max(by: { $0.noteCount < $1.noteCount })
        guard let dominant else { return nil }

        if dominant.item.id != primary.item.id, dominant.noteCount > primary.noteCount {
            let primaryLabel = primary.noteCount == 0
                ? "hasn't been touched"
                : "got \(primary.noteCount) note\(primary.noteCount == 1 ? "" : "s")"
            return "\(primary.item.content) is your stated primary, but \(dominant.item.content) dominated this week (\(dominant.noteCount) notes). \(primary.item.content) \(primaryLabel)."
        }
        return nil
    }
}
