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

struct AskInputSheet: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var queryText: String = ""
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
                    Text("Type a question or pick a starter below. EEON searches every note you've captured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

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
                                onSubmit(prompt)
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

    private var canSubmit: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

#Preview {
    AskInputSheet(
        onSubmit: { query in print("submit: \(query)") },
        onCancel: { print("cancel") }
    )
}
