//
//  DecisionLogView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct DecisionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExtractedDecision.createdAt, order: .reverse) private var decisions: [ExtractedDecision]
    @Query private var projects: [Project]
    @Query private var notes: [Note]

    private var grouped: [(Date, [ExtractedDecision])] {
        NotesReorgHelpers.groupByWeek(items: decisions, dateKey: { $0.createdAt })
    }

    private func projectName(for decision: ExtractedDecision) -> String? {
        guard let noteId = decision.sourceNoteId,
              let note = notes.first(where: { $0.id == noteId }),
              let projectId = note.projectId,
              let project = projects.first(where: { $0.id == projectId }) else {
            return nil
        }
        return project.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if decisions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 40))
                                .foregroundStyle(.eeonTextTertiary)
                            Text("No decisions yet")
                                .font(.headline)
                            Text("As you capture voice notes, EEON will extract decisions here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }

                    ForEach(grouped, id: \.0) { weekStart, items in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(weekHeader(weekStart))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.eeonTextSecondary)
                                .padding(.horizontal, 16)

                            ForEach(items) { d in
                                decisionRow(d)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Decisions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func decisionRow(_ d: ExtractedDecision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(d.content)
                .font(.body)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if let proj = projectName(for: d) {
                    Label(proj, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextTertiary)
                }
                Text(d.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.eeonTextTertiary)
                if d.confidence != "Medium" {
                    Text(d.confidence)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.eeonCard)
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func weekHeader(_ weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Week of \(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }
}
