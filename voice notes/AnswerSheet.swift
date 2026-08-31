//
//  AnswerSheet.swift
//  voice notes
//
//  Q&A surface for chat-with-memory. Voice-routed questions and extraction-chip
//  taps still open it as a modal; Library uses the same view pushed in the
//  current NavigationStack so it does not stack a prompt sheet over an answer sheet.
//

import SwiftUI
import SwiftData
import Combine

struct AnswerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query private var knowledgeArticles: [KnowledgeArticle]
    @Query private var projects: [Project]
    @Query private var dailyBriefs: [DailyBrief]

    /// When present, run this question on appear. When nil, the view opens as
    /// a composer for Ask Library.
    let initialQuery: String?
    let navigationTitle: String
    let showsDoneButton: Bool
    let wrapsInNavigationStack: Bool

    private enum LoadState {
        case idle
        case loading
        case answer(question: String, response: RAGResponse)
        case error(String)
    }

    private struct AnswerTurn: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
        let routeBadge: String
        let sourceTitles: [String]
    }

    @State private var state: LoadState = .idle
    @State private var previousTurns: [AnswerTurn] = []
    @State private var activeScopePrefix: String?
    @State private var followUpInput: String = ""
    @State private var submittedQuestion: String?
    @State private var didSave: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var navigateToNote: Note?
    @State private var hasRunInitial: Bool = false
    @FocusState private var isComposerFocused: Bool

    init(
        initialQuery: String,
        navigationTitle: String = "Answer",
        showsDoneButton: Bool = true,
        wrapsInNavigationStack: Bool = true
    ) {
        self.initialQuery = initialQuery
        self.navigationTitle = navigationTitle
        self.showsDoneButton = showsDoneButton
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    init(
        navigationTitle: String = "Ask Library",
        showsDoneButton: Bool = false,
        wrapsInNavigationStack: Bool = false
    ) {
        self.initialQuery = nil
        self.navigationTitle = navigationTitle
        self.showsDoneButton = showsDoneButton
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { answerContent }
            } else {
                answerContent
            }
        }
    }

    private var answerContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !previousTurns.isEmpty {
                        historyView
                    }

                    switch state {
                    case .idle:
                        askStartView
                    case .loading:
                        loadingView(question: submittedQuestion)
                    case .answer(let question, let response):
                        answerView(question: question, response: response)
                    case .error(let message):
                        errorView(question: submittedQuestion, message: message)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(Color.eeonDivider)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(inputPlaceholder, text: $followUpInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.eeonCard)
                    .cornerRadius(20)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitTypedQuestion() }

                Button(action: submitTypedQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(canSubmit ? .eeonAccentAI : .eeonTextTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .disabled(!canSubmit)
                .accessibilityLabel("Send question")
            }
            .padding()
            .background(Color.eeonBackground)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { answerToolbar }
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
            if let query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                runQuery(query)
            } else {
                state = .idle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isComposerFocused = true
                }
            }
        }
    }

    private var inputPlaceholder: String {
        if case .idle = state { return "Ask your Library" }
        return "Ask another"
    }

    private var canSubmit: Bool {
        let trimmed = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if case .loading = state { return false }
        return true
    }

    @ToolbarContentBuilder
    private var answerToolbar: some ToolbarContent {
        if showsDoneButton {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Sub-views

    private var askStartView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 42)

            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.eeonAccentAI)
                .frame(width: 68, height: 68)
                .background(Circle().fill(Color.eeonAccentAI.opacity(0.14)))

            Text("Ask Library")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.eeonTextPrimary)

            Text("Type a question about your notes.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func loadingView(question: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let question, !question.isEmpty {
                questionBubble(question)
            }

            HStack(spacing: 12) {
                TypingIndicator()
                Text("Searching your Library...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                HStack(spacing: 8) {
                    Text("ANSWER")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(response.route.badgeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.eeonAccentAI.opacity(0.08))
                        .cornerRadius(8)
                }
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

            if !response.suggestedFollowUps.isEmpty {
                followUpSuggestions(response.suggestedFollowUps)
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(previousTurns.suffix(3)) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(turn.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.eeonTextPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(turn.routeBadge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(turn.answer)
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .lineLimit(3)
                    if !turn.sourceTitles.isEmpty {
                        Text(turn.sourceTitles.prefix(3).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .background(Color.eeonCard.opacity(0.7))
                .cornerRadius(10)
            }
        }
    }

    private func followUpSuggestions(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOLLOW-UPS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                    Button {
                        askFollowUp(suggestion)
                    } label: {
                        HStack(spacing: 5) {
                            Text(suggestion)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.eeonAccentAI.opacity(0.1))
                        .foregroundStyle(.eeonAccentAI)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func questionBubble(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QUESTION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(question)
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
        }
    }

    private func errorView(question: String?, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question, !question.isEmpty {
                questionBubble(question)
            }

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

    private func submitTypedQuestion() {
        let trimmed = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .loading = state { return }
        followUpInput = ""
        appendCurrentTurnToHistory()
        runQuery(trimmed)
    }

    private func askFollowUp(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .loading = state { return }
        followUpInput = ""
        appendCurrentTurnToHistory()
        runQuery(trimmed)
    }

    private func appendCurrentTurnToHistory() {
        guard case let .answer(question, response) = state else { return }
        let turn = AnswerTurn(
            question: question,
            answer: response.answer,
            routeBadge: response.route.badgeText,
            sourceTitles: response.sourceNotes.map(\.displayTitle)
        )
        previousTurns.append(turn)
    }

    private func runQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if activeScopePrefix == nil, let scope = scopePrefix(in: trimmed) {
            activeScopePrefix = scope
        }
        let ragQuery = contextualQuery(for: trimmed)

        state = .loading
        submittedQuestion = trimmed
        didSave = false

        Task {
            do {
                let response = try await RAGService.shared.answerQuestion(
                    query: ragQuery,
                    allNotes: allNotes,
                    articles: Array(knowledgeArticles),
                    projects: projects,
                    dailyBriefs: dailyBriefs
                )
                await MainActor.run {
                    submittedQuestion = nil
                    state = .answer(question: trimmed, response: response)
                }
            } catch {
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func contextualQuery(for query: String) -> String {
        var resolvedQuery = query
        if let prefix = activeScopePrefix, scopePrefix(in: query) == nil {
            resolvedQuery = "\(prefix) \(query)"
        }

        guard !previousTurns.isEmpty else { return resolvedQuery }
        let context = previousTurns.suffix(3).map { turn -> String in
            var lines = [
                "Previous question: \(turn.question)",
                "Previous answer: \(turn.answer)"
            ]
            if !turn.sourceTitles.isEmpty {
                lines.append("Previous sources: \(turn.sourceTitles.prefix(5).joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")

        return """
        \(resolvedQuery)

        Ask session context for resolving pronouns and short follow-ups:
        \(context)

        Use the session context only to understand what "this", "that", or "more" refers to. Ground the answer in the user's notes and cite note or article sources.
        """
    }

    private func scopePrefix(in query: String) -> String? {
        let normalized = query.lowercased()
        let prefixes = [
            "Using only my notes from today,",
            "Using only my notes from the last 7 days,",
            "Using only my notes from the last 30 days,"
        ]
        return prefixes.first { normalized.hasPrefix($0.lowercased()) }
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
