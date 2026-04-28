//
//  AnswerSheet.swift
//  voice notes
//
//  Single-question one-shot Q&A modal. Voice-routed questions (via IntentClassifier)
//  and extraction-chip taps open this sheet. The user sees one question and one
//  answer at a time — submitting "Ask another" REPLACES the current answer rather
//  than appending to a chat history.
//

import SwiftUI
import SwiftData
import Combine

struct AnswerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query private var knowledgeArticles: [KnowledgeArticle]

    /// The question to run on appear. Required; non-optional by design.
    let initialQuery: String

    private enum LoadState {
        case loading
        case answer(question: String, response: RAGResponse)
        case error(String)
    }

    @State private var state: LoadState = .loading
    @State private var followUpInput: String = ""
    @State private var didSave: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var navigateToNote: Note?
    @State private var hasRunInitial: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch state {
                        case .loading:
                            loadingView
                        case .answer(let question, let response):
                            answerView(question: question, response: response)
                        case .error(let message):
                            errorView(message: message)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .overlay(Color.eeonDivider)

                // "Ask another" input — replaces the current answer
                HStack(spacing: 12) {
                    TextField("Ask another", text: $followUpInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.eeonCard)
                        .cornerRadius(20)
                        .onSubmit { submitFollowUp() }

                    Button(action: submitFollowUp) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(canSubmit ? .eeonAccentAI : .eeonTextTertiary)
                    }
                    .disabled(!canSubmit)
                }
                .padding()
                .background(Color.eeonBackground)
            }
            .navigationTitle("Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if showingSaveConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to Notes")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationDestination(item: $navigateToNote) { note in
                NoteDetailView(note: note)
            }
            .onAppear {
                guard !hasRunInitial else { return }
                hasRunInitial = true
                runQuery(initialQuery)
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if case .loading = state { return false }
        return true
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        HStack(spacing: 12) {
            TypingIndicator()
            Text("Searching your notes...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private func answerView(question: String, response: RAGResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question
            VStack(alignment: .leading, spacing: 4) {
                Text("QUESTION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(question)
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
            }

            // Answer
            VStack(alignment: .leading, spacing: 4) {
                Text("ANSWER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(response.answer)
                    .font(.body)
                    .foregroundStyle(.eeonTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.eeonCard)
            .cornerRadius(12)

            // Source chips
            if !response.sourceNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOURCES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    FlowLayout(spacing: 6) {
                        ForEach(response.sourceNotes, id: \.id) { note in
                            Button(action: {
                                navigateToNote = note
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text")
                                        .font(.caption2)
                                    Text(note.displayTitle)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.eeonAccentAI.opacity(0.1))
                                .foregroundStyle(.eeonAccentAI)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Save as note button
            Button(action: { saveAsNote(question: question, answer: response.answer) }) {
                HStack(spacing: 6) {
                    Image(systemName: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.subheadline)
                    Text(didSave ? "Saved" : "Save as note")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(didSave ? .green : .eeonAccentAI)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(didSave ? Color.green.opacity(0.1) : Color.eeonAccentAI.opacity(0.1))
                .cornerRadius(10)
            }
            .disabled(didSave)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Couldn't get an answer")
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.top, 24)
    }

    // MARK: - Actions

    private func submitFollowUp() {
        let trimmed = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .loading = state { return }
        followUpInput = ""
        runQuery(trimmed)
    }

    private func runQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .loading
        didSave = false

        Task {
            do {
                let response = try await RAGService.shared.answerQuestion(
                    query: trimmed,
                    allNotes: allNotes,
                    articles: Array(knowledgeArticles)
                )
                await MainActor.run {
                    state = .answer(question: trimmed, response: response)
                }
            } catch {
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func saveAsNote(question: String, answer: String) {
        let titleSource = String(question.prefix(50))
        let title = question.count > 50 ? titleSource + "..." : titleSource

        let note = Note(
            title: title,
            content: answer
        )
        note.intent = .idea
        note.sourceType = .derived

        modelContext.insert(note)
        try? modelContext.save()

        didSave = true
        withAnimation { showingSaveConfirmation = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaveConfirmation = false }
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.eeonAccentAI.opacity(index <= dotCount ? 1.0 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
    }
}

// MARK: - Preview

#Preview {
    AnswerSheet(initialQuery: "What did I decide this week?")
        .modelContainer(for: [Note.self, ExtractedDecision.self, ExtractedAction.self], inMemory: true)
}
