//
//  AssistantView.swift
//  voice notes
//
//  AI Assistant - Chat with your notes, generate PRDs, summaries, etc.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Quick Actions

enum AssistantAction: String, CaseIterable {
    case prd = "PRD"
    case execSummary = "Exec Summary"
    case todoList = "To-Do List"
    case weeklyUpdate = "Weekly Update"
    case meetingNotes = "Meeting Notes"
    case decisions = "Decisions Made"

    var icon: String {
        switch self {
        case .prd: return "doc.text"
        case .execSummary: return "doc.plaintext"
        case .todoList: return "checklist"
        case .weeklyUpdate: return "calendar"
        case .meetingNotes: return "person.2"
        case .decisions: return "checkmark.seal"
        }
    }

    var prompt: String {
        switch self {
        case .prd:
            return "Create a PRD (Product Requirements Document) based on my recent notes about features, requirements, and discussions."
        case .execSummary:
            return "Write an executive summary of my recent notes - key decisions, progress, and blockers."
        case .todoList:
            return "Create a prioritized to-do list from all the action items and tasks mentioned in my notes."
        case .weeklyUpdate:
            return "Write a weekly update based on my notes from the past week - what I accomplished, what's in progress, and what's next."
        case .meetingNotes:
            return "Compile and organize my meeting notes into a clean summary with action items."
        case .decisions:
            return "List all the decisions I've made recently based on my notes, with context for each."
        }
    }
}

// MARK: - Assistant View

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query private var allDecisions: [ExtractedDecision]
    @Query private var allActions: [ExtractedAction]

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var selectedNotes: Set<UUID> = []
    @State private var showingNoteSelector = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var savedMessageId: UUID?
    @State private var showingSaveConfirmation = false

    // Use recent notes as context by default
    private var contextNotes: [Note] {
        if selectedNotes.isEmpty {
            // Use last 10 notes by default
            return Array(allNotes.prefix(10))
        } else {
            return allNotes.filter { selectedNotes.contains($0.id) }
        }
    }

    private var notesContext: String {
        contextNotes.map { note in
            """
            --- Note: \(note.displayTitle) (\(note.createdAt.formatted(date: .abbreviated, time: .shortened))) ---
            \(note.content.isEmpty ? (note.transcript ?? "") : note.content)
            """
        }.joined(separator: "\n\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Welcome message
                            if messages.isEmpty {
                                WelcomeSection(onActionTap: { action in
                                    sendMessage(action.prompt)
                                })
                            }

                            // Chat messages
                            ForEach(messages) { message in
                                MessageBubble(
                                    message: message,
                                    isSaved: savedMessageId == message.id,
                                    onSave: message.role == .assistant ? { saveAsNote(message) } : nil
                                )
                                .id(message.id)
                            }

                            // Loading indicator
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
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
                }

                Divider()

                // Input area
                HStack(spacing: 12) {
                    // Note selector button
                    Button(action: { showingNoteSelector = true }) {
                        Image(systemName: selectedNotes.isEmpty ? "doc.text" : "doc.text.fill")
                            .font(.title3)
                            .foregroundColor(selectedNotes.isEmpty ? .gray : .blue)
                    }

                    // Text input
                    TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)

                    // Send button
                    Button(action: { sendMessage(inputText) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty || isLoading)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: clearChat) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
            .sheet(isPresented: $showingNoteSelector) {
                NoteSelectorView(
                    allNotes: allNotes,
                    selectedNotes: $selectedNotes
                )
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
        }
    }

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await callAssistantAPI(userMessage: text)
                await MainActor.run {
                    let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
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

    private func callAssistantAPI(userMessage: String) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not configured"])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are an AI assistant for a founder's voice notes app. You have access to the user's notes and can help them:
        - Answer questions about their notes
        - Generate documents (PRDs, summaries, to-do lists, etc.)
        - Find specific information across their notes
        - Synthesize insights from multiple notes

        Be concise, actionable, and founder-friendly. Use markdown formatting for structured output.

        Here are the user's notes for context:

        \(notesContext)

        ---

        Recent decisions extracted from notes:
        \(allDecisions.prefix(5).map { "- \($0.content)" }.joined(separator: "\n"))

        Recent actions extracted from notes:
        \(allActions.prefix(5).map { "- \($0.content) (Owner: \($0.owner))" }.joined(separator: "\n"))
        """

        // Build conversation history
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in messages {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.content
            ])
        }

        // Add current message
        apiMessages.append(["role": "user", "content": userMessage])

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content ?? "I couldn't generate a response."
    }

    private func clearChat() {
        messages = []
        selectedNotes = []
    }

    private func saveAsNote(_ message: ChatMessage) {
        // Find the user's question that prompted this response
        var userPrompt = "Assistant Response"
        if let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
           messageIndex > 0 {
            let previousMessage = messages[messageIndex - 1]
            if previousMessage.role == .user {
                // Use first 50 chars of user prompt as title
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
        note.intent = .idea  // Default to "Idea" for AI-generated content

        modelContext.insert(note)

        // Mark as saved and show confirmation
        savedMessageId = message.id
        withAnimation {
            showingSaveConfirmation = true
        }

        // Hide confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingSaveConfirmation = false
            }
        }
    }
}

// MARK: - Welcome Section

struct WelcomeSection: View {
    let onActionTap: (AssistantAction) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Notes Assistant")
                    .font(.title2.bold())

                Text("Ask me anything - I can search across all your notes, answer questions, or help you create documents.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            // Quick actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(AssistantAction.allCases, id: \.self) { action in
                        QuickActionButton(action: action) {
                            onActionTap(action)
                        }
                    }
                }
            }
            .padding(.horizontal)

            // Example prompts
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ExamplePrompt(text: "What decisions have I made this week?", onTap: {
                        onActionTap(.decisions)
                    })
                    ExamplePrompt(text: "Summarize my notes about the new feature", onTap: {
                        // Custom prompt
                    })
                    ExamplePrompt(text: "What am I forgetting to do?", onTap: {
                        // Custom prompt
                    })
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

struct QuickActionButton: View {
    let action: AssistantAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.title2)
                Text(action.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct ExamplePrompt: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isSaved: Bool = false
    var onSave: (() -> Void)?

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color(.systemGray6))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .cornerRadius(16)

                HStack(spacing: 12) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Save as Note button (only for assistant messages)
                    if let onSave = onSave {
                        Button(action: onSave) {
                            HStack(spacing: 4) {
                                Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.caption)
                                Text(isSaved ? "Saved" : "Save as Note")
                                    .font(.caption2)
                            }
                            .foregroundColor(isSaved ? .green : .blue)
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

// MARK: - Note Selector View

struct NoteSelectorView: View {
    let allNotes: [Note]
    @Binding var selectedNotes: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: { selectedNotes = [] }) {
                        HStack {
                            Text("Use recent notes (default)")
                            Spacer()
                            if selectedNotes.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section("Select specific notes") {
                    ForEach(allNotes.prefix(30)) { note in
                        Button(action: { toggleNote(note.id) }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(note.displayTitle)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedNotes.contains(note.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggleNote(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }
}

// MARK: - Preview

#Preview {
    AssistantView()
        .modelContainer(for: [Note.self, ExtractedDecision.self, ExtractedAction.self], inMemory: true)
}
