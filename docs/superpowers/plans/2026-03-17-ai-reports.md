# AI Reports Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated AI Reports chat screen with pre-built prompt pills (CEO Report, SWOT, Goals, etc.) that generates account-level intelligence from all user data via GPT.

**Architecture:** New `ReportsView` chat screen (modeled on existing `AssistantView`) with a `ReportType` enum defining 9 report templates. A new `SummaryService.buildAccountContext()` method aggregates all SwiftData records into a structured context string. `UsageService` gets a new counter for free-tier gating (2 free reports). Entry point is a new button in AIHomeView's header.

**Tech Stack:** SwiftUI, SwiftData, OpenAI GPT-4o-mini (URLSession), UserDefaults

---

### Task 1: Add ReportType enum with pill config and system prompts

**Files:**
- Create: `voice notes/ReportType.swift`

- [ ] **Step 1: Create ReportType.swift with all 9 report types**

```swift
//
//  ReportType.swift
//  voice notes
//
//  Report type definitions for AI Reports screen
//

import Foundation

enum ReportType: String, CaseIterable, Identifiable {
    case ceoReport = "CEO Report"
    case swot = "SWOT"
    case goalTracker = "Goals"
    case weeklySummary = "Weekly"
    case people = "People"
    case projectStatus = "Projects"
    case decisionLog = "Decisions"
    case actionAudit = "Actions"
    case custom = "Custom"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .ceoReport: return "📊"
        case .swot: return "🔍"
        case .goalTracker: return "🎯"
        case .weeklySummary: return "📅"
        case .people: return "👥"
        case .projectStatus: return "📁"
        case .decisionLog: return "📋"
        case .actionAudit: return "✅"
        case .custom: return "✨"
        }
    }

    var pillColor: String {
        switch self {
        case .ceoReport: return "1a3a5c"
        case .swot: return "3a1a1a"
        case .goalTracker: return "1a3a1a"
        case .weeklySummary: return "3a2a1a"
        case .people: return "2a1a3a"
        case .projectStatus: return "1a2a3a"
        case .decisionLog: return "2a2a1a"
        case .actionAudit: return "1a2a2a"
        case .custom: return "2a1a2a"
        }
    }

    var pillTextColor: String {
        switch self {
        case .ceoReport: return "4a9eff"
        case .swot: return "ff6b6b"
        case .goalTracker: return "4aff6b"
        case .weeklySummary: return "ffaa4a"
        case .people: return "aa6bff"
        case .projectStatus: return "4affff"
        case .decisionLog: return "ffff4a"
        case .actionAudit: return "4affaa"
        case .custom: return "ff6bff"
        }
    }

    /// The user-facing message sent when tapping the pill
    var userPrompt: String {
        switch self {
        case .ceoReport:
            return "Generate a CEO Report across all my notes and projects."
        case .swot:
            return "Create a SWOT analysis based on everything in my notes."
        case .goalTracker:
            return "Show me goal tracking — what's on track, what's drifting, and suggested corrections."
        case .weeklySummary:
            return "Write a weekly summary — decisions made, actions completed, and what stalled."
        case .people:
            return "Generate a people report — who I owe things to, who owes me, and relationship health."
        case .projectStatus:
            return "Give me a project status report — health, blockers, momentum for each project."
        case .decisionLog:
            return "Show me all decisions with their current status and any that need revisiting."
        case .actionAudit:
            return "Audit my open actions — what's overdue, blocked, or missing an owner."
        case .custom:
            return "" // Custom doesn't send a prompt, it focuses the input
        }
    }

    /// System prompt instructions specific to this report type
    var reportInstructions: String {
        switch self {
        case .ceoReport:
            return """
            Generate a CEO-level report with these sections:
            ## Highlights
            Top 3-5 achievements or progress points.
            ## Strategic Implications
            What these developments mean for the bigger picture.
            ## Risks & Concerns
            Items that need attention or could become problems.
            ## Recommended Actions
            Specific next steps, prioritized.
            """
        case .swot:
            return """
            Generate a SWOT analysis based on the user's notes, projects, and extracted intelligence:
            ## Strengths
            What's working well — active projects, completed actions, strong momentum areas.
            ## Weaknesses
            What's struggling — stalled items, overdue actions, unresolved issues.
            ## Opportunities
            Potential improvements, ideas mentioned but not acted on, connections between projects.
            ## Threats
            Risks — items drifting too long, commitments at risk, dependencies on others.
            """
        case .goalTracker:
            return """
            Analyze the user's projects, actions, and decisions to infer their goals and track progress:
            ## Active Goals (Inferred)
            What the user appears to be working toward based on their notes and projects.
            ## On Track
            Goals with recent activity and forward momentum.
            ## Drifting
            Goals with stalled items or no recent activity.
            ## Suggested Course Corrections
            Specific actions to get drifting goals back on track.
            """
        case .weeklySummary:
            return """
            Write a weekly summary covering the past 7 days:
            ## What Happened This Week
            Key notes recorded, decisions made, actions taken.
            ## Completed
            Actions and commitments that were finished.
            ## Still In Progress
            Items actively being worked on.
            ## Stalled or Blocked
            Items that haven't moved and may need attention.
            ## Next Week's Priorities
            Suggested focus areas based on open items.
            """
        case .people:
            return """
            Generate a people relationship report:
            ## Commitments I Owe Others
            What I've promised to other people, with status.
            ## Commitments Others Owe Me
            What others have committed to, with status.
            ## People Needing Attention
            People with open commitments or recent mentions who may need follow-up.
            ## Relationship Health
            Overall assessment of key relationships based on commitment follow-through.
            """
        case .projectStatus:
            return """
            Generate a project-by-project status report:
            For each active project, include:
            ## [Project Name]
            - **Status**: Active/Stalled/Completed
            - **Momentum**: Accelerating/Steady/Slowing/Stalled
            - **Open Items**: Count of open actions, unresolved items
            - **Blockers**: Any blocked items or overdue actions
            - **Recent Activity**: Last note or action date
            - **Recommended Next Step**: Most important thing to do next
            """
        case .decisionLog:
            return """
            Generate a decision log report:
            ## Active Decisions
            Decisions currently in effect, with context and what they affect.
            ## Pending Decisions
            Decisions that need to be made — waiting on information or input.
            ## Decisions to Revisit
            Any decisions that may need to be reconsidered based on new information or time elapsed.
            ## Decision Timeline
            Chronological list of recent decisions with dates.
            """
        case .actionAudit:
            return """
            Audit all open actions:
            ## Overdue
            Actions past their deadline or flagged as overdue.
            ## Blocked
            Actions that are blocked and need unblocking.
            ## No Owner
            Actions without a clear owner assigned.
            ## Due Soon
            Actions coming up that need attention.
            ## By Priority
            Remaining open actions grouped by priority (Urgent, High, Normal, Low).
            """
        case .custom:
            return "Answer the user's question based on their complete notes history. Be concise and actionable. Use markdown formatting."
        }
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Open `voice notes.xcodeproj` in Xcode and add `ReportType.swift` to the "voice notes" group if it wasn't auto-discovered, or use `xcodebuild` to verify it compiles. New `.swift` files in the project directory are typically auto-discovered by Xcode's folder references.

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "voice notes/ReportType.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: add ReportType enum with pill config and system prompts"
```

---

### Task 2: Add buildAccountContext to SummaryService

**Files:**
- Modify: `voice notes/SummaryService.swift` (append new extension at end of file)

- [ ] **Step 1: Add the buildAccountContext static method**

Append this extension to the end of `SummaryService.swift`, before the closing of the file:

```swift
// MARK: - Account Context for Reports

extension SummaryService {
    /// Builds a structured context string from all user data for account-level reports.
    /// Call on @MainActor (SwiftData models are not Sendable). Pass the resulting String to async API calls.
    static func buildAccountContext(
        notes: [Note],
        projects: [Project],
        decisions: [ExtractedDecision],
        actions: [ExtractedAction],
        commitments: [ExtractedCommitment],
        people: [MentionedPerson],
        kanbanItems: [KanbanItem]
    ) -> String {
        let maxContextLength = 12_000
        var sections: [String] = []

        // Projects (always included, compact)
        if !projects.isEmpty {
            let projectLines = projects.map { project in
                let status = project.isStalled ? "stalled" : "active"
                let lastActivity = project.lastActivityAt?.formatted(date: .abbreviated, time: .omitted) ?? "none"
                return "- \(project.name): \(project.noteCount) notes, \(project.openActionCount) open actions, last activity: \(lastActivity), status: \(status)"
            }
            sections.append("PROJECTS (\(projects.count) total):\n" + projectLines.joined(separator: "\n"))
        }

        // Decisions (always included, compact)
        if !decisions.isEmpty {
            let decisionLines = decisions.map { d in
                "- [\(d.createdAt.formatted(date: .abbreviated, time: .omitted))] \(d.content) (Status: \(d.status), Affects: \(d.affects))"
            }
            sections.append("DECISIONS (\(decisions.count) total):\n" + decisionLines.joined(separator: "\n"))
        }

        // Actions (always included, compact)
        if !actions.isEmpty {
            let actionLines = actions.map { a in
                let status = a.isCompleted ? "completed" : (a.isBlocked ? "blocked" : "open")
                return "- [\(a.createdAt.formatted(date: .abbreviated, time: .omitted))] \(a.content) — Owner: \(a.owner), Deadline: \(a.deadline), Status: \(status), Priority: \(a.priority)"
            }
            sections.append("ACTIONS (\(actions.count) total):\n" + actionLines.joined(separator: "\n"))
        }

        // Commitments (always included, compact)
        if !commitments.isEmpty {
            let commitmentLines = commitments.map { c in
                let status = c.isCompleted ? "completed" : "open"
                return "- [\(c.createdAt.formatted(date: .abbreviated, time: .omitted))] \(c.who): \(c.what) — Status: \(status)"
            }
            sections.append("COMMITMENTS (\(commitments.count) total):\n" + commitmentLines.joined(separator: "\n"))
        }

        // People (always included, compact)
        if !people.isEmpty {
            let peopleLines = people.filter { !$0.isArchived }.map { p in
                "- \(p.displayName): \(p.mentionCount) mentions, \(p.openCommitmentCount) open commitments, last mentioned: \(p.lastMentionedAt.formatted(date: .abbreviated, time: .omitted))"
            }
            sections.append("PEOPLE (\(people.filter { !$0.isArchived }.count) total):\n" + peopleLines.joined(separator: "\n"))
        }

        // Build non-note context first to measure remaining budget
        let fixedContext = "ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")
        let remainingBudget = maxContextLength - fixedContext.count

        // Notes (trimmed to fit budget)
        if !notes.isEmpty && remainingBudget > 200 {
            let notesToInclude = Array(notes.prefix(50))
            var noteLines: [String] = []
            var noteCharsUsed = 0
            let headerLine = "NOTES (\(notes.count) total):\n"
            noteCharsUsed += headerLine.count

            for note in notesToInclude {
                let preview = String((note.transcript ?? note.content).prefix(200))
                let line = "- [\(note.createdAt.formatted(date: .abbreviated, time: .omitted))] \(note.displayTitle): \(preview)"
                if noteCharsUsed + line.count + 1 > remainingBudget - 100 { break }
                noteLines.append(line)
                noteCharsUsed += line.count + 1
            }

            if !noteLines.isEmpty {
                sections.insert(headerLine + noteLines.joined(separator: "\n"), at: 0)
            }
        }

        // Kanban items (trimmed if needed)
        let currentLength = ("ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")).count
        if !kanbanItems.isEmpty && currentLength < maxContextLength - 200 {
            let kanbanBudget = maxContextLength - currentLength - 50
            var kanbanLines: [String] = []
            var kanbanCharsUsed = 0

            for item in kanbanItems {
                let daysSince = Calendar.current.dateComponents([.day], from: item.updatedAt, to: Date()).day ?? 0
                let line = "- [\(item.column)] \(item.content) — Type: \(item.itemType), Days since update: \(daysSince)"
                if kanbanCharsUsed + line.count + 1 > kanbanBudget { break }
                kanbanLines.append(line)
                kanbanCharsUsed += line.count + 1
            }

            if !kanbanLines.isEmpty {
                sections.append("KANBAN ITEMS (\(kanbanItems.count) total):\n" + kanbanLines.joined(separator: "\n"))
            }
        }

        return "ACCOUNT CONTEXT:\n================\n\n" + sections.joined(separator: "\n\n")
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: add buildAccountContext for account-level AI reports"
```

---

### Task 3: Add report generation counter to UsageService

**Files:**
- Modify: `voice notes/UsageService.swift`

- [ ] **Step 1: Add reportGenerationCount key, property, and canGenerateReport**

In `UsageService.swift`, add after the existing `subscriptionStatusKey` (line 23):

```swift
private let reportCountKey = "reportGenerationCount"
```

Add after `subscriptionStatus` property (after line 44):

```swift
var reportGenerationCount: Int {
    get { defaults.integer(forKey: reportCountKey) }
    set { defaults.set(newValue, forKey: reportCountKey) }
}
```

Add after `canCreateNote` (after line 51):

```swift
static let freeReportLimit = 2

var canGenerateReport: Bool {
    isPro || reportGenerationCount < UsageService.freeReportLimit
}

var freeReportsRemaining: Int {
    max(0, UsageService.freeReportLimit - reportGenerationCount)
}

func incrementReportCount() {
    reportGenerationCount += 1
}
```

In `resetAllUsage()` (line 123), add:

```swift
reportGenerationCount = 0
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/UsageService.swift"
git commit -m "feat: add report generation counter to UsageService (2 free limit)"
```

---

### Task 4: Create ReportsView chat screen

**Files:**
- Create: `voice notes/ReportsView.swift`

- [ ] **Step 1: Create ReportsView.swift**

This is the main chat screen, modeled closely on `AssistantView.swift`. Key differences: scrollable pill row instead of grid, account-level context instead of 10-note context, report-specific titles on save, usage gating.

```swift
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

    // All data for context building
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

    // Track the last report type used (for save title)
    @State private var lastReportType: ReportType?

    var body: some View {
        VStack(spacing: 0) {
            // Pill row
            pillRow

            Divider()
                .background(Color(.systemGray4))

            // Chat area
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

            // Input bar
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
        .navigationTitle("AI Reports")
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
                ForEach(ReportType.allCases) { reportType in
                    Button {
                        handlePillTap(reportType)
                    } label: {
                        HStack(spacing: 6) {
                            Text(reportType.emoji)
                                .font(.system(size: 14))
                            Text(reportType.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: reportType.pillColor))
                        .foregroundStyle(Color(hex: reportType.pillTextColor))
                        .cornerRadius(20)
                    }
                    .disabled(isLoading && reportType != .custom)
                    .opacity(isLoading && reportType != .custom ? 0.5 : 1.0)
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

    private func handlePillTap(_ reportType: ReportType) {
        if reportType == .custom {
            isInputFocused = true
            return
        }

        guard checkUsage() else { return }

        lastReportType = reportType
        let prompt = reportType.userPrompt
        sendMessage(prompt, reportType: reportType)
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
                    userMessage: text,
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

    private func callReportAPI(userMessage: String, reportType: ReportType, accountContext: String) async throws -> String {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not configured"])
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are an AI assistant analyzing a founder's complete voice notes history. You have full access to their notes, projects, decisions, actions, commitments, people, and workflow board.

        Be concise, actionable, and founder-friendly. Use markdown formatting for structured output.

        \(reportType.reportInstructions)

        Here is the user's complete account context:

        \(accountContext)
        """

        // Build conversation history (last 10 messages only)
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Include conversation history (last 10 messages), which already contains the current user message
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
            // Use first 50 chars of preceding user message
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
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
```

- [ ] **Step 2: Add file to Xcode project**

Add `ReportsView.swift` to the "voice notes" group in the Xcode project if needed.

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "voice notes/ReportsView.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: add ReportsView chat screen with pill row and account-level GPT"
```

---

### Task 5: Add Reports button to AIHomeView header

**Files:**
- Modify: `voice notes/AIHomeView.swift`

- [ ] **Step 1: Add state variable and reports button to header**

In `AIHomeView.swift`, add a new `@State` property alongside the existing ones (after line 34):

```swift
@State private var showingReports = false
```

In the `headerView` computed property (line 168-198), modify the `HStack` to add a reports button before the avatar button. Replace the existing `headerView`:

```swift
private var headerView: some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            if authService.isSignedIn, let session = intelligenceService.sessionBrief {
                Text(session.freshnessLabel)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }

        Spacer()

        if authService.isSignedIn {
            NavigationLink(destination: ReportsView()) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .padding(.trailing, 8)
        }

        Button {
            showingSettings = true
        } label: {
            if authService.isSignedIn {
                UserAvatarView(name: authService.displayName, size: 36)
            } else {
                Image(systemName: "person.circle")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
        }
    }
    .padding(.horizontal)
    .padding(.top, 8)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Test on simulator**

Run the app in Xcode. Verify:
- Sparkles button appears in header next to avatar (only when signed in)
- Tapping it navigates to AI Reports screen
- Pill row is visible and scrollable
- Empty state shows correctly
- Back navigation works

- [ ] **Step 4: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: add AI Reports entry point to AIHomeView header"
```

---

### Task 6: End-to-end test and polish

**Files:**
- Possibly modify: `voice notes/ReportsView.swift`, `voice notes/ReportType.swift` (bug fixes only)

- [ ] **Step 1: Test pill-to-report flow**

Run the app on simulator with test data. Verify:
1. Tap "CEO Report" pill → user message appears → loading indicator → GPT response with markdown
2. Tap "SWOT" pill → second report generates in same thread
3. Copy button works (copies to clipboard)
4. Save as Note works (creates note with "CEO Report — Mar 17, 2026" title)
5. Clear chat resets everything

- [ ] **Step 2: Test free-form chat**

1. Type a custom question in the input bar → sends and gets response
2. Type while loading → send button is disabled
3. Custom pill → focuses the input bar

- [ ] **Step 3: Test usage gating**

1. As a non-pro user, generate 2 reports → PaywallView appears on 3rd attempt
2. Verify counter increments in UserDefaults

- [ ] **Step 4: Test edge cases**

1. With no notes → "Record some notes first" message shows
2. API key missing → error alert
3. Rapid pill tapping while loading → pills are disabled/dimmed

- [ ] **Step 5: Fix any issues found, then commit**

```bash
git add -A
git commit -m "polish: AI Reports end-to-end testing fixes"
```
