//
//  KanbanBoardView.swift
//  voice notes
//
//  A thinking surface, not a verdict. Kanban-style organization.
//

import SwiftUI
import SwiftData

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \KanbanItem.sortOrder) private var allItems: [KanbanItem]
    @Query(sort: \KanbanMovement.movedAt, order: .reverse) private var allMovements: [KanbanMovement]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var tags: [Tag]

    @State private var selectedColumn: KanbanColumn = .doing
    @State private var draggedItem: KanbanItem?

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false


    // Filtered items by column
    func items(for column: KanbanColumn) -> [KanbanItem] {
        allItems
            .filter { $0.column == column.rawValue }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Column selector (mobile-friendly tabs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(KanbanColumn.allCases, id: \.self) { column in
                            ColumnTab(
                                column: column,
                                count: items(for: column).count,
                                isSelected: selectedColumn == column,
                                onTap: { selectedColumn = column }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                // Current column content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if items(for: selectedColumn).isEmpty {
                            EmptyColumnView(column: selectedColumn)
                        } else {
                            ForEach(items(for: selectedColumn)) { item in
                                KanbanCard(item: item, allItems: allItems, onMove: { newColumn in
                                    moveItem(item, to: newColumn)
                                })
                                .draggable(item.id.uuidString) {
                                    KanbanCardPreview(item: item)
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(selectedColumn.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: selectedColumn.icon)
                        Text(selectedColumn.rawValue)
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: NotesListView()) {
                        Image(systemName: "note.text")
                    }
                }
            }
            .overlay {
                if isRecording || isTranscribing {
                    RecordingOverlay(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        recordingTime: audioRecorder.formattedTime,
                        onStop: stopRecording,
                        onCancel: cancelRecording
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if !isRecording && !isTranscribing {
                    RecordButtonView(onTap: startRecording)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .task {
                let _ = await audioRecorder.requestPermission()
            }
        }
    }

    private func moveItem(_ item: KanbanItem, to column: KanbanColumn) {
        let fromColumn = item.kanbanColumn

        // Update the item
        item.kanbanColumn = column
        item.updatedAt = Date()

        // Record the movement
        let movement = KanbanMovement(itemId: item.id, fromColumn: fromColumn, toColumn: column)
        modelContext.insert(movement)
    }

    // MARK: - Recording Functions

    private func startRecording() {
        do {
            currentAudioFileName = try audioRecorder.startRecording()
            isRecording = true
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording"
            showingError = true
            isRecording = false
            return
        }

        isRecording = false
        isTranscribing = true
        transcribeAndSave(url: url)
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        currentAudioFileName = nil
        isRecording = false
    }

    private func transcribeAndSave(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil)
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                let transcript = try await service.transcribe(audioURL: url)

                await MainActor.run {
                    saveNote(transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func saveNote(transcript: String?) {
        let note = Note(
            title: "",
            content: transcript ?? "",
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        modelContext.insert(note)

        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let context = modelContext
            Task {
                do {
                    // Generate title
                    let title = try await generateTitle(for: transcript, apiKey: apiKey)

                    // Extract tags
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: transcript)

                    // Analyze and create Kanban items
                    let kanbanItems = try await analyzeForKanban(text: transcript, apiKey: apiKey, noteId: note.id)

                    await MainActor.run {
                        note.title = title

                        for name in tagNames {
                            if let existingTag = existingTags.first(where: { $0.name.lowercased() == name.lowercased() }) {
                                if !note.tags.contains(existingTag) {
                                    note.tags.append(existingTag)
                                }
                            } else {
                                let newTag = Tag(name: name)
                                context.insert(newTag)
                                note.tags.append(newTag)
                            }
                        }

                        // Insert Kanban items
                        for item in kanbanItems {
                            context.insert(item)
                        }

                        // Switch to the column with the most new items
                        if let primaryColumn = kanbanItems.first?.kanbanColumn {
                            selectedColumn = primaryColumn
                        }
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Analysis failed: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        }

        currentAudioFileName = nil
        isTranscribing = false
    }

    private func analyzeForKanban(text: String, apiKey: String, noteId: UUID) async throws -> [KanbanItem] {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Extract items from this voice note for a Kanban thinking board.

        Columns:
        - Thinking: Ideas, open questions, no clear next step yet
        - Decided: Clear decisions made, direction locked in
        - Doing: Active work, explicit intent to do soon
        - Waiting: Blocked, delegated, pending external input

        Return JSON array:
        [
            {
                "content": "Brief item (5-10 words max)",
                "column": "Thinking|Decided|Doing|Waiting",
                "type": "Idea|Decision|Action|Commitment",
                "nudge": "One helpful question or next step"
            }
        ]

        NUDGE RULES (critical):
        - Thinking items: Ask the forcing question. "What would make this a yes/no?" or "Test this how?"
        - Decided items: State the impact briefly. "Affects pricing and onboarding."
        - Doing items: If vague, ask "What does done look like?" If clear, leave nudge empty "".
        - Waiting items: "Follow up in X days?" or identify the blocker.

        Keep nudges SHORT. One sentence max. No explanations.
        Prefer Thinking if uncertain.
        Return ONLY valid JSON array, no markdown.

        Voice note:
        \(text)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 800
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

        struct KanbanExtract: Codable {
            let content: String
            let column: String
            let type: String
            let nudge: String
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard var content = response.choices.first?.message.content else {
            print("No content in response")
            return []
        }

        // Strip markdown code blocks if present
        if content.contains("```") {
            content = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = content.data(using: .utf8) else {
            print("Could not convert to data: \(content)")
            return []
        }

        print("Kanban AI response: \(content)")

        let extracts: [KanbanExtract]
        do {
            extracts = try JSONDecoder().decode([KanbanExtract].self, from: jsonData)
        } catch {
            print("JSON decode failed: \(error)")
            print("Raw content: \(content)")
            throw error
        }

        print("Created \(extracts.count) Kanban items")

        return extracts.map { extract in
            let column = KanbanColumn(rawValue: extract.column) ?? .thinking
            let type = KanbanItemType(rawValue: extract.type) ?? .note

            return KanbanItem(
                content: extract.content,
                column: column,
                itemType: type,
                reason: extract.nudge,
                sourceNoteId: noteId
            )
        }
    }

    private func generateTitle(for transcript: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let transcriptForTitle = transcript.count > 2000
            ? "\(String(transcript.prefix(1000)))\n...\n\(String(transcript.suffix(1000)))"
            : transcript

        let prompt = """
        Generate a very short title (3-6 words max) for this voice note.
        Return ONLY the title, no quotes.

        Transcript: \(transcriptForTitle)
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 20
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
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Voice Note"
    }
}

// MARK: - Column Tab

struct ColumnTab: View {
    let column: KanbanColumn
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var columnColor: Color {
        switch column {
        case .thinking: return .blue
        case .decided: return .green
        case .doing: return .blue
        case .waiting: return .orange
        case .done: return .gray
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: column.icon)
                        .font(.caption)
                    Text(column.rawValue)
                        .font(.subheadline.weight(.medium))
                }

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? columnColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? columnColor : .secondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kanban Card

struct KanbanCard: View {
    @Bindable var item: KanbanItem
    let allItems: [KanbanItem]
    let onMove: (KanbanColumn) -> Void

    var itemColor: Color {
        switch item.kanbanColumn {
        case .thinking: return .blue
        case .decided: return .green
        case .doing: return .blue
        case .waiting: return .orange
        case .done: return .gray
        }
    }

    var healthStatus: HealthStatus {
        HealthScoreService.healthStatus(for: item, allItems: allItems)
    }

    var healthColor: Color {
        switch healthStatus {
        case .strong: return .green
        case .atRisk: return .orange
        case .stalled: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge with health indicator
            HStack {
                // Health dot
                if item.kanbanColumn != .done {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 8, height: 8)
                }

                Text(item.kanbanItemType.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(itemColor.opacity(0.2))
                    .foregroundStyle(itemColor)
                    .cornerRadius(4)

                // Staleness indicator
                if let staleness = item.stalenessLabel, item.kanbanColumn != .done {
                    Text(staleness)
                        .font(.caption2)
                        .foregroundStyle(item.isStale ? .orange : .secondary)
                }

                Spacer()

                // Move menu
                Menu {
                    ForEach(KanbanColumn.allCases, id: \.self) { column in
                        if column != item.kanbanColumn {
                            Button {
                                onMove(column)
                            } label: {
                                Label(column.rawValue, systemImage: column.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }

            // Content
            Text(item.content)
                .font(.subheadline)

            // Reason (why it's here)
            if !item.reason.isEmpty {
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Metadata
            if let deadline = item.deadline, !deadline.isEmpty {
                Label(deadline, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(itemColor)
                .frame(width: 3),
            alignment: .leading
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Card Preview (for dragging)

struct KanbanCardPreview: View {
    let item: KanbanItem

    var body: some View {
        Text(item.content)
            .font(.caption)
            .padding(8)
            .background(Color(.systemBackground))
            .cornerRadius(6)
            .shadow(radius: 4)
    }
}

// MARK: - Empty Column View

struct EmptyColumnView: View {
    let column: KanbanColumn

    var message: String {
        switch column {
        case .thinking:
            return "Ideas and open questions will appear here"
        case .decided:
            return "Decisions you've made will appear here"
        case .doing:
            return "Active work and next actions will appear here"
        case .waiting:
            return "Blocked or delegated items will appear here"
        case .done:
            return "Completed items will appear here"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: column.icon)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

#Preview {
    KanbanBoardView()
        .modelContainer(for: [Note.self, Tag.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self], inMemory: true)
}
