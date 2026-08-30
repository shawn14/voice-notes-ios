//
//  AskInputSheet.swift
//  voice notes
//
//  Discoverable entry point for "chat with your notes." Presents a text input
//  plus a row of canned starter prompts. Submitting calls `onSubmit(query)`,
//  whose caller is expected to set `pendingAnswerQuery` to open AnswerSheet
//  with the chosen query.
//
//  The canned prompts are deliberately chosen to map cleanly to the 5 routes
//  in `RAGService` (ranking, trends, timeRange, semantic) so users discover the
//  cost-efficient backends just by trying them.
//

import SwiftUI

private enum AskMemoryScope: String, CaseIterable, Identifiable {
    case everything
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: return "Everything"
        case .today: return "Today"
        case .last7Days: return "7 days"
        case .last30Days: return "30 days"
        }
    }

    var description: String {
        switch self {
        case .everything: return "every note you've captured"
        case .today: return "notes from today"
        case .last7Days: return "notes from the last 7 days"
        case .last30Days: return "notes from the last 30 days"
        }
    }

    func scopedQuery(_ query: String) -> String {
        switch self {
        case .everything:
            return query
        case .today:
            return "Using only my notes from today, \(query)"
        case .last7Days:
            return "Using only my notes from the last 7 days, \(query)"
        case .last30Days:
            return "Using only my notes from the last 30 days, \(query)"
        }
    }
}

struct AskInputSheet: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var queryText: String = ""
    @State private var selectedScope: AskMemoryScope = .everything
    @FocusState private var isFocused: Bool

    private let cannedPrompts: [String] = [
        "Summarize my top 10 projects",
        "Any trends across all my notes?",
        "What was my focus last week?",
        "What's most important today?"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Headline
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask your memory")
                        .font(.title3.bold())
                        .foregroundStyle(Color("EEONTextPrimary"))
                    Text("Type a question or pick a starter below. EEON searches \(selectedScope.description).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                scopePicker

                // Input row
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("What do you want to know?", text: $queryText, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($isFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color("EEONCard"))
                        .cornerRadius(14)
                        .onSubmit { submit() }

                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSubmit ? Color("EEONAccentAI") : Color("EEONTextTertiary"))
                    }
                    .disabled(!canSubmit)
                }
                .padding(.horizontal)

                // Canned prompt chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("STARTERS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ForEach(cannedPrompts, id: \.self) { prompt in
                            Button {
                                onSubmit(selectedScope.scopedQuery(prompt))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color("EEONAccentAI"))
                                    Text(prompt)
                                        .font(.subheadline)
                                        .foregroundStyle(Color("EEONTextPrimary"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color("EEONCard"))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.top, 4)

                Spacer()
            }
            .navigationTitle("Ask EEON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color("EEONTextSecondary"))
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AskMemoryScope.allCases) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Text(scope.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedScope == scope ? .white : Color("EEONTextPrimary"))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(selectedScope == scope ? Color("EEONAccentAI") : Color("EEONCard"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var canSubmit: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(selectedScope.scopedQuery(trimmed))
    }
}

#Preview {
    AskInputSheet(
        onSubmit: { query in print("submit: \(query)") },
        onCancel: { print("cancel") }
    )
}
