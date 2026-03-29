//
//  ReportsView.swift
//  voice notes
//
//  AI Reports - Account-level intelligence via chat with pre-built report pills
//

import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var decisions: [ExtractedDecision]
    @Query private var actions: [ExtractedAction]
    @Query private var commitments: [ExtractedCommitment]
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var people: [MentionedPerson]
    @Query(sort: \KanbanItem.updatedAt, order: .reverse) private var kanbanItems: [KanbanItem]

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var savedMessageId: UUID?
    @State private var showingSaveConfirmation = false
    @State private var showPaywall = false
    @FocusState private var isInputFocused: Bool
    @State private var lastReportType: ReportType?
    @State private var personalizedReports: [PersonalizedReport] = PersonalizedReportStore.cached ?? []

    var body: some View {
        VStack(spacing: 0) {
            pillRow

            Divider()
                .background(Color(.systemGray4))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if messages.isEmpty {
                            emptyState
                        }

                        ForEach(messages) { message in
                            ReportMessageBubble(
                                message: message,
                                isSaved: savedMessageId == message.id,
                                onSave: message.role == .assistant ? { saveAsNote(message) } : nil,
                                onCopy: message.role == .assistant ? { copyToClipboard(message) } : nil
                            )
                            .id(message.id)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating report...")
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

            HStack(spacing: 12) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .focused($isInputFocused)

                Button(action: { sendFreeformMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(AuthService.shared.userName ?? "AI Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(onDismiss: { showPaywall = false })
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

    // MARK: - Pill Row

    private var pillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !personalizedReports.isEmpty {
                    // Personalized reports from My EEON
                    ForEach(personalizedReports) { report in
                        Button {
                            handlePersonalizedPillTap(report)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: report.icon)
                                    .font(.system(size: 12))
                                Text(report.name)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hexString: report.pillColor))
                            .foregroundStyle(Color(hexString: report.pillTextColor))
                            .cornerRadius(20)
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.5 : 1.0)
                    }
                } else {
                    // Default static reports
                    ForEach(ReportType.allCases) { reportType in
                        Button {
                            handlePillTap(reportType)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: reportType.icon)
                                    .font(.system(size: 12))
                                Text(reportType.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hexString: reportType.pillColor))
                            .foregroundStyle(Color(hexString: reportType.pillTextColor))
                            .cornerRadius(20)
                        }
                        .disabled(isLoading && reportType != .custom)
                        .opacity(isLoading && reportType != .custom ? 0.5 : 1.0)
                    }
                }

                // Always show Custom pill at end
                if !personalizedReports.isEmpty {
                    Button {
                        isInputFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 12))
                            Text("Custom")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hexString: "2a1a2a"))
                        .foregroundStyle(Color(hexString: "ff6bff"))
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Ask anything about your notes")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("or tap a report above")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if notes.isEmpty {
                Text("Record some notes first to generate reports")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func handlePersonalizedPillTap(_ report: PersonalizedReport) {
        guard checkUsage() else { return }
        lastReportType = nil
        sendPersonalizedMessage(report)
    }

    private func handlePillTap(_ reportType: ReportType) {
        if reportType == .custom {
            isInputFocused = true
            return
        }

        guard checkUsage() else { return }

        lastReportType = reportType
        sendMessage(reportType.userPrompt, reportType: reportType)
    }

    private func sendFreeformMessage() {
        guard !inputText.isEmpty else { return }
        guard checkUsage() else { return }

        lastReportType = nil
        let text = inputText
        inputText = ""
        sendMessage(text, reportType: .custom)
    }

    private func checkUsage() -> Bool {
        if !UsageService.shared.canGenerateReport {
            showPaywall = true
            return false
        }
        return true
    }

    private func sendPersonalizedMessage(_ report: PersonalizedReport) {
        let userMessage = ChatMessage(role: .user, content: report.userPrompt, timestamp: Date())
        messages.append(userMessage)
        isLoading = true

        let context = SummaryService.buildAccountContext(
            notes: notes, projects: projects, decisions: decisions,
            actions: actions, commitments: commitments, people: people, kanbanItems: kanbanItems
        )

        Task {
            do {
                let response = try await callPersonalizedReportAPI(report: report, accountContext: context)
                await MainActor.run {
                    let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                    messages.append(assistantMessage)
                    isLoading = false
                    UsageService.shared.incrementReportCount()
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

    private func callPersonalizedReportAPI(report: PersonalizedReport, accountContext: String) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not configured"])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        \(AuthService.shared.eeonContextPrefix)You are an AI assistant analyzing a user's complete voice notes history. You have full access to their notes, projects, decisions, actions, commitments, people, and workflow board.

        Be concise, actionable, and tailored to the user's role. Use markdown formatting for structured output. Do not use emojis.

        \(report.instructions)

        Here is the user's complete account context:

        \(accountContext)
        """

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        let recentMessages = messages.suffix(10)
        for message in recentMessages {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.content
            ])
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": apiMessages,
            "temperature": 0.5,
            "max_tokens": 3000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? "No response generated."
    }

    private func sendMessage(_ text: String, reportType: ReportType) {
        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        messages.append(userMessage)
        isLoading = true

        // Build context on main thread (SwiftData models aren't Sendable)
        let context = SummaryService.buildAccountContext(
            notes: notes,
            projects: projects,
            decisions: decisions,
            actions: actions,
            commitments: commitments,
            people: people,
            kanbanItems: kanbanItems
        )

        Task {
            do {
                let response = try await callReportAPI(
                    reportType: reportType,
                    accountContext: context
                )
                await MainActor.run {
                    let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
                    messages.append(assistantMessage)
                    isLoading = false
                    UsageService.shared.incrementReportCount()
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

    private func callReportAPI(reportType: ReportType, accountContext: String) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not configured"])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        \(AuthService.shared.eeonContextPrefix)You are an AI assistant analyzing a founder's complete voice notes history. You have full access to their notes, projects, decisions, actions, commitments, people, and workflow board.

        Be concise, actionable, and founder-friendly. Use markdown formatting for structured output. Do not use emojis.

        \(reportType.reportInstructions)

        Here is the user's complete account context:

        \(accountContext)
        """

        // Build conversation history (last 10 messages — already includes current user message)
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        let recentMessages = messages.suffix(10)
        for message in recentMessages {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.content
            ])
        }

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
        lastReportType = nil
    }

    private func copyToClipboard(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
    }

    private func saveAsNote(_ message: ChatMessage) {
        let title: String
        if let reportType = lastReportType, reportType != .custom {
            title = "\(reportType.rawValue) — \(Date().formatted(date: .abbreviated, time: .omitted))"
        } else {
            if let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
               messageIndex > 0,
               messages[messageIndex - 1].role == .user {
                let userPrompt = String(messages[messageIndex - 1].content.prefix(50))
                title = messages[messageIndex - 1].content.count > 50 ? userPrompt + "..." : userPrompt
            } else {
                title = "AI Report — \(Date().formatted(date: .abbreviated, time: .omitted))"
            }
        }

        let note = Note(title: title, content: message.content)
        note.intent = .idea
        modelContext.insert(note)

        savedMessageId = message.id
        withAnimation { showingSaveConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaveConfirmation = false }
        }
    }
}

// MARK: - Report Message Bubble

struct ReportMessageBubble: View {
    let message: ChatMessage
    var isSaved: Bool = false
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?

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

                    if let onCopy = onCopy {
                        Button(action: onCopy) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                Text("Copy")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                    }

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

// MARK: - Color Hex Extension

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255.0
        g = Double((int >> 8) & 0xFF) / 255.0
        b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    NavigationStack {
        ReportsView()
    }
    .modelContainer(for: [Note.self, Project.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, MentionedPerson.self, KanbanItem.self], inMemory: true)
}
