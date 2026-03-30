//
//  AssistantView.swift
//  voice notes
//
//  RAG-powered chat interface — ask questions about your notes, get cited answers.
//

import SwiftUI
import SwiftData
import UIKit
import Combine

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var sourceNotes: [Note]?
    var suggestedFollowUps: [String]?

    enum Role {
        case user
        case assistant
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Assistant View

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var savedMessageId: UUID?
    @State private var showingSaveConfirmation = false
    @State private var navigateToNote: Note?

    /// Optional pre-filled query sent automatically on appear (e.g. from extraction chip tap)
    var initialQuery: String? = nil
    @State private var hasSentInitialQuery = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Empty state with starter queries
                            if messages.isEmpty {
                                RAGWelcomeSection(onQueryTap: { query in
                                    sendQuery(query)
                                })
                            }

                            // Chat messages
                            ForEach(messages) { message in
                                RAGMessageBubble(
                                    message: message,
                                    isSaved: savedMessageId == message.id,
                                    onSave: message.role == .assistant ? { saveAsNote(message) } : nil,
                                    onSourceTap: { note in
                                        navigateToNote = note
                                    },
                                    onFollowUpTap: { query in
                                        sendQuery(query)
                                    }
                                )
                                .id(message.id)
                            }

                            // Loading indicator
                            if isLoading {
                                HStack(spacing: 8) {
                                    TypingIndicator()
                                    Text("Searching your notes...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            } else {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) {
                        if isLoading {
                            withAnimation {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
                    .overlay(Color.eeonDivider)

                // Input area
                HStack(spacing: 12) {
                    // Text input
                    TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.eeonCard)
                        .cornerRadius(20)
                        .onSubmit {
                            sendQuery(inputText)
                        }

                    // Send button
                    Button(action: { sendQuery(inputText) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(inputText.isEmpty || isLoading ? .eeonTextTertiary : .eeonAccentAI)
                    }
                    .disabled(inputText.isEmpty || isLoading)
                }
                .padding()
                .background(Color.eeonBackground)
            }
            .navigationTitle("Ask EEON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: clearChat) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(messages.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Something went wrong")
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
                    .animation(.easeInOut, value: showingSaveConfirmation)
                }
            }
            .onAppear {
                if let query = initialQuery, !query.isEmpty, !hasSentInitialQuery {
                    hasSentInitialQuery = true
                    sendQuery(query)
                }
            }
            .navigationDestination(item: $navigateToNote) { note in
                NoteDetailView(note: note)
            }
        }
    }

    private func sendQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await RAGService.shared.answerQuestion(query: trimmed, allNotes: allNotes)
                await MainActor.run {
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: response.answer,
                        timestamp: Date(),
                        sourceNotes: response.sourceNotes,
                        suggestedFollowUps: response.suggestedFollowUps
                    )
                    messages.append(assistantMessage)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLoading = false
                }
            }
        }
    }

    private func clearChat() {
        messages = []
    }

    private func saveAsNote(_ message: ChatMessage) {
        var userPrompt = "Assistant Response"
        if let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
           messageIndex > 0 {
            let previousMessage = messages[messageIndex - 1]
            if previousMessage.role == .user {
                userPrompt = String(previousMessage.content.prefix(50))
                if previousMessage.content.count > 50 {
                    userPrompt += "..."
                }
            }
        }

        let note = Note(
            title: userPrompt,
            content: message.content
        )
        note.intent = .idea

        modelContext.insert(note)

        savedMessageId = message.id
        withAnimation {
            showingSaveConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingSaveConfirmation = false
            }
        }
    }
}

// MARK: - RAG Welcome Section

struct RAGWelcomeSection: View {
    let onQueryTap: (String) -> Void

    private let starterQueries = [
        "What should I focus on today?",
        "What am I forgetting?",
        "Summarize this week",
        "What did I decide recently?"
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color("EEONAccent"))

                Text("Ask EEON")
                    .font(.title2.bold())

                Text("Ask questions about your notes. I'll search across everything and give you cited answers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            // Starter queries
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(starterQueries, id: \.self) { query in
                    Button(action: { onQueryTap(query) }) {
                        HStack {
                            Text(query)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.eeonCard)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
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

// MARK: - RAG Message Bubble

struct RAGMessageBubble: View {
    let message: ChatMessage
    var isSaved: Bool = false
    var onSave: (() -> Void)?
    var onSourceTap: ((Note) -> Void)?
    var onFollowUpTap: ((String) -> Void)?

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(message.role == .user ? Color.eeonAccent.opacity(0.15) : Color.eeonCard)
                    .foregroundStyle(message.role == .user ? .eeonTextPrimary : .eeonTextPrimary)
                    .cornerRadius(16)

                // Source notes (assistant only)
                if let sources = message.sourceNotes, !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        FlowLayout(spacing: 6) {
                            ForEach(sources, id: \.id) { note in
                                Button(action: { onSourceTap?(note) }) {
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

                // Follow-up suggestions (assistant only)
                if let followUps = message.suggestedFollowUps, !followUps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Follow up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(followUps, id: \.self) { followUp in
                            Button(action: { onFollowUpTap?(followUp) }) {
                                HStack {
                                    Text(followUp)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .font(.caption)
                                        .foregroundStyle(.eeonAccentAI)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.eeonCard)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Timestamp + save
                HStack(spacing: 12) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let onSave = onSave {
                        Button(action: onSave) {
                            HStack(spacing: 4) {
                                Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.caption)
                                Text(isSaved ? "Saved" : "Save as Note")
                                    .font(.caption2)
                            }
                            .foregroundColor(isSaved ? .green : .eeonAccentAI)
                        }
                        .disabled(isSaved)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
    }
}

// MARK: - Preview

#Preview {
    AssistantView()
        .modelContainer(for: [Note.self, ExtractedDecision.self, ExtractedAction.self], inMemory: true)
}
