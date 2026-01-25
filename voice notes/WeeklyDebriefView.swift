//
//  WeeklyDebriefView.swift
//  voice notes
//
//  Display and generate AI-powered weekly summaries
//

import SwiftUI
import SwiftData

struct WeeklyDebriefView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyDebrief.weekStartDate, order: .reverse) private var debriefs: [WeeklyDebrief]
    @Query(sort: \KanbanItem.updatedAt, order: .reverse) private var allItems: [KanbanItem]
    @Query(sort: \KanbanMovement.movedAt, order: .reverse) private var allMovements: [KanbanMovement]

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var currentWeekStart: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
    }

    private var hasCurrentWeekDebrief: Bool {
        debriefs.contains { Calendar.current.isDate($0.weekStartDate, equalTo: currentWeekStart, toGranularity: .weekOfYear) }
    }

    var body: some View {
        List {
            // Generate button section
            if !hasCurrentWeekDebrief {
                Section {
                    Button {
                        generateDebrief()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            VStack(alignment: .leading) {
                                Text(isGenerating ? "Generating..." : "Generate This Week's Debrief")
                                    .font(.headline)
                                Text("AI summary of what moved, what stalled, and what needs attention")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isGenerating)
                }
            }

            // Debriefs list
            ForEach(debriefs) { debrief in
                Section {
                    DebriefCard(debrief: debrief)
                } header: {
                    HStack {
                        Text(debrief.dateRangeDescription)
                        Spacer()
                        MomentumBadge(direction: MomentumDirection(rawValue: debrief.momentumScore) ?? .flat)
                    }
                }
            }

            if debriefs.isEmpty && hasCurrentWeekDebrief == false {
                ContentUnavailableView(
                    "No Debriefs Yet",
                    systemImage: "doc.text",
                    description: Text("Generate your first weekly debrief to see a summary of your progress.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Weekly Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func generateDebrief() {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            return
        }

        isGenerating = true

        Task {
            do {
                let debrief = try await generateDebriefWithAI(apiKey: apiKey)

                await MainActor.run {
                    modelContext.insert(debrief)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate debrief: \(error.localizedDescription)"
                    showingError = true
                    isGenerating = false
                }
            }
        }
    }

    private func generateDebriefWithAI(apiKey: String) async throws -> WeeklyDebrief {
        let weekStart = currentWeekStart

        // Calculate stats
        let momentum = MomentumService.calculateMomentum(movements: allMovements, items: allItems)
        let (forward, backward, completed, created) = MomentumService.weeklySummary(
            movements: allMovements,
            items: allItems,
            weekStart: weekStart
        )
        let droppedBalls = HealthScoreService.detectDroppedBalls(items: allItems)
        let health = HealthScoreService.healthCounts(for: allItems)

        // Build context for AI
        let activeItems = allItems.filter { $0.kanbanColumn != .done }.prefix(20)
        let recentCompleted = allItems.filter { $0.kanbanColumn == .done }.prefix(10)

        let itemsSummary = activeItems.map { "- [\($0.kanbanColumn.rawValue)] \($0.content)" }.joined(separator: "\n")
        let completedSummary = recentCompleted.map { "- \($0.content)" }.joined(separator: "\n")
        let droppedSummary = droppedBalls.map { "- \($0.item.content): \($0.description)" }.joined(separator: "\n")

        let prompt = """
        Generate a weekly debrief for a founder. Be direct and useful, not cheerful.

        STATS THIS WEEK:
        - Forward movements: \(forward)
        - Backward movements: \(backward)
        - Completed: \(completed)
        - New items created: \(created)
        - Health: \(health.strong) strong, \(health.atRisk) at risk, \(health.stalled) stalled

        ACTIVE ITEMS:
        \(itemsSummary.isEmpty ? "None" : itemsSummary)

        COMPLETED THIS WEEK:
        \(completedSummary.isEmpty ? "None" : completedSummary)

        NEEDS ATTENTION:
        \(droppedSummary.isEmpty ? "None" : droppedSummary)

        Return JSON:
        {
            "summary": "2-3 sentences on the week. What actually happened. No fluff.",
            "highlights": ["Up to 3 wins or forward progress items"],
            "concerns": ["Up to 3 things that need attention or are slipping"]
        }

        Keep it short. Founder time is scarce. Return ONLY valid JSON.
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 500
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

        struct DebriefResponse: Codable {
            let summary: String
            let highlights: [String]
            let concerns: [String]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard var content = response.choices.first?.message.content else {
            throw NSError(domain: "WeeklyDebrief", code: 1, userInfo: [NSLocalizedDescriptionKey: "No content in response"])
        }

        // Strip markdown
        if content.contains("```") {
            content = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = content.data(using: .utf8) else {
            throw NSError(domain: "WeeklyDebrief", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON data"])
        }

        let debriefResponse = try JSONDecoder().decode(DebriefResponse.self, from: jsonData)

        let debrief = WeeklyDebrief(weekStartDate: weekStart)
        debrief.summary = debriefResponse.summary
        debrief.momentumScore = momentum.direction.rawValue
        debrief.highlights = debriefResponse.highlights
        debrief.concerns = debriefResponse.concerns

        return debrief
    }
}

// MARK: - Debrief Card

struct DebriefCard: View {
    let debrief: WeeklyDebrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary
            Text(debrief.summary)
                .font(.subheadline)

            // Highlights
            if !debrief.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Highlights", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)

                    ForEach(debrief.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.green)
                            Text(highlight)
                                .font(.caption)
                        }
                    }
                }
            }

            // Concerns
            if !debrief.concerns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Concerns", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)

                    ForEach(debrief.concerns, id: \.self) { concern in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.orange)
                            Text(concern)
                                .font(.caption)
                        }
                    }
                }
            }

            // Generated timestamp
            Text("Generated \(formatDate(debrief.generatedAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Momentum Badge

struct MomentumBadge: View {
    let direction: MomentumDirection

    var color: Color {
        switch direction {
        case .up: return .green
        case .down: return .orange
        case .flat: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: direction.icon)
            Text("Momentum")
        }
        .font(.caption2)
        .foregroundStyle(color)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeeklyDebriefView()
    }
    .modelContainer(for: [KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self], inMemory: true)
}
