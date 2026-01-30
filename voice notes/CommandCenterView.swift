//
//  CommandCenterView.swift
//  voice notes
//
//  Executive Home Screen - Command Center, not a notebook
//

import SwiftUI
import SwiftData

struct CommandCenterView: View {
    @Environment(\.modelContext) private var modelContext

    // Queries for extracted items
    @Query(sort: \ExtractedDecision.createdAt, order: .reverse) private var allDecisions: [ExtractedDecision]
    @Query(sort: \ExtractedAction.createdAt, order: .reverse) private var allActions: [ExtractedAction]
    @Query(sort: \ExtractedCommitment.createdAt, order: .reverse) private var allCommitments: [ExtractedCommitment]
    @Query(sort: \UnresolvedItem.createdAt, order: .reverse) private var allUnresolved: [UnresolvedItem]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @Query private var tags: [Tag]

    @State private var showingNotesContext = false

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Filtered data
    var openDecisions: [ExtractedDecision] {
        allDecisions.filter { $0.isActive }
    }

    var myCommitments: [ExtractedCommitment] {
        allCommitments.filter { $0.isUserCommitment && !$0.isCompleted }
    }

    var actionsNeedingAttention: [ExtractedAction] {
        allActions.filter { $0.requiresAttention || $0.isDueSoon }
            .sorted { action1, action2 in
                // Sort by urgency: overdue > urgent > due soon > blocked
                if action1.isOverdue != action2.isOverdue { return action1.isOverdue }
                if (action1.priority == "Urgent") != (action2.priority == "Urgent") {
                    return action1.priority == "Urgent"
                }
                if action1.isDueSoon != action2.isDueSoon { return action1.isDueSoon }
                return action1.isBlocked && !action2.isBlocked
            }
    }

    var pendingActions: [ExtractedAction] {
        allActions.filter { !$0.isCompleted && !$0.requiresAttention && !$0.isDueSoon }
    }

    // Items that require immediate attention
    var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []

        // Overdue actions
        for action in allActions where action.isOverdue && !action.isCompleted {
            items.append(AttentionItem(
                content: action.content,
                reason: "Overdue",
                consequence: "This was due and may be blocking progress",
                type: .overdue
            ))
        }

        // Due soon
        for action in allActions where action.isDueSoon && !action.isCompleted && !action.isOverdue {
            items.append(AttentionItem(
                content: action.content,
                reason: "Due soon",
                consequence: "Needs action today or tomorrow",
                type: .dueSoon
            ))
        }

        // User commitments (things you said you'd do)
        for commitment in myCommitments {
            items.append(AttentionItem(
                content: commitment.what,
                reason: "You committed to this",
                consequence: "Others may be waiting on you",
                type: .commitment
            ))
        }

        // Blocked actions
        for action in allActions where action.isBlocked && !action.isCompleted {
            items.append(AttentionItem(
                content: action.content,
                reason: "Blocked",
                consequence: "Cannot proceed until resolved",
                type: .blocked
            ))
        }

        return items
    }

    // All incomplete actions (for display when no urgent items)
    var openActions: [ExtractedAction] {
        allActions.filter { !$0.isCompleted }
    }

    var needsAttention: Bool {
        !attentionItems.isEmpty
    }

    var hasActiveDecisions: Bool {
        !openDecisions.isEmpty
    }

    var lastDecisionDate: Date? {
        allDecisions.max(by: { $0.createdAt < $1.createdAt })?.createdAt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // THE ONE QUESTION: "Do I need to do anything right now?"

                    if needsAttention {
                        // 1. ATTENTION REQUIRED - dominates the screen
                        AttentionSection(items: attentionItems)
                    }

                    if hasActiveDecisions {
                        // 2. ACTIVE DECISIONS - shown as current state
                        CommandSection(title: "Active Decisions", icon: "checkmark.seal", tint: .green) {
                            ForEach(openDecisions) { decision in
                                DecisionStateRow(decision: decision)
                            }
                        }
                    }

                    // 3. OPEN ACTIONS - things to do (shown if any exist)
                    if !openActions.isEmpty && !needsAttention {
                        CommandSection(title: "To Do", icon: "checklist") {
                            ForEach(openActions) { action in
                                ActionRow(action: action, urgent: false)
                            }
                        }
                    }

                    // 4. ALL CLEAR STATE - only if nothing needs attention, no decisions, no actions
                    if !needsAttention && !hasActiveDecisions && openActions.isEmpty {
                        AllClearState(
                            lastDecisionDate: lastDecisionDate,
                            noteCount: notes.count
                        )
                    }

                    // Unresolved items (need clarity)
                    if !allUnresolved.isEmpty {
                        CommandSection(title: "Needs Clarity", icon: "questionmark.circle", tint: .blue) {
                            ForEach(allUnresolved.prefix(3)) { item in
                                UnresolvedRow(item: item)
                            }
                        }
                    }

                    // 5. Recent Context (collapsed by default)
                    DisclosureGroup(isExpanded: $showingNotesContext) {
                        VStack(spacing: 8) {
                            ForEach(notes.prefix(10)) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    RecentNoteRow(note: note)
                                }
                                .buttonStyle(.plain)
                            }

                            if notes.count > 10 {
                                NavigationLink(destination: NotesListView()) {
                                    Text("View all \(notes.count) notes")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text("Recent Context")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(notes.count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
                .padding(.bottom, 100)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Command Center")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: NotesListView()) {
                        Image(systemName: "note.text")
                    }
                }
            }
            .overlay {
                // Recording Overlay
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

        // Auto-generate title, extract tags, AND analyze for decisions/actions
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

                    // AUTO-ANALYZE: Extract decisions, actions, commitments
                    let analysis = try await SummaryService.analyzeNote(text: transcript, apiKey: apiKey)

                    await MainActor.run {
                        note.title = title

                        // Add tags
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

                        // Save extracted decisions
                        for decision in analysis.extractedDecisions {
                            let extracted = ExtractedDecision(
                                content: decision.content,
                                affects: decision.affects,
                                confidence: decision.confidence,
                                status: "Active",
                                sourceNoteId: note.id
                            )
                            context.insert(extracted)
                        }

                        // Save extracted actions
                        for action in analysis.extractedActions {
                            let extracted = ExtractedAction(
                                content: action.content,
                                owner: action.owner,
                                deadline: action.deadline,
                                priority: "Normal",
                                sourceNoteId: note.id
                            )
                            context.insert(extracted)
                        }

                        // Save extracted commitments
                        for commitment in analysis.extractedCommitments {
                            let extracted = ExtractedCommitment(
                                who: commitment.who,
                                what: commitment.what,
                                sourceNoteId: note.id
                            )
                            context.insert(extracted)
                        }

                        // Save unresolved items
                        for unresolved in analysis.unresolvedItems {
                            let extracted = UnresolvedItem(
                                content: unresolved.content,
                                reason: unresolved.reason,
                                sourceNoteId: note.id
                            )
                            context.insert(extracted)
                        }
                    }
                } catch {
                    print("AI processing failed: \(error)")
                }
            }
        }

        currentAudioFileName = nil
        isTranscribing = false
    }

    private func generateTitle(for transcript: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let transcriptForTitle: String
        if transcript.count > 2000 {
            let start = String(transcript.prefix(1000))
            let end = String(transcript.suffix(1000))
            transcriptForTitle = "\(start)\n...[middle truncated]...\n\(end)"
        } else {
            transcriptForTitle = transcript
        }

        let prompt = """
        Generate a very short title (3-6 words max) that summarizes this voice note transcript.
        Return ONLY the title, no quotes or punctuation at the end.

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
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Voice Note"
    }
}

// MARK: - Attention Item Model

enum AttentionType {
    case overdue, dueSoon, commitment, blocked
}

struct AttentionItem: Identifiable {
    let id = UUID()
    let content: String
    let reason: String
    let consequence: String
    let type: AttentionType
}

// MARK: - Attention Section (Dominates when present)

struct AttentionSection: View {
    let items: [AttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Needs Your Attention")
                    .font(.headline)
            }

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.content)
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 12) {
                        Label(item.reason, systemImage: iconFor(item.type))
                            .font(.caption)
                            .foregroundStyle(colorFor(item.type))

                        Text(item.consequence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorFor(item.type).opacity(0.1))
                .overlay(
                    Rectangle()
                        .fill(colorFor(item.type))
                        .frame(width: 3),
                    alignment: .leading
                )
                .cornerRadius(8)
            }
        }
    }

    private func iconFor(_ type: AttentionType) -> String {
        switch type {
        case .overdue: return "clock.badge.exclamationmark"
        case .dueSoon: return "calendar.badge.clock"
        case .commitment: return "person.badge.clock"
        case .blocked: return "hand.raised"
        }
    }

    private func colorFor(_ type: AttentionType) -> Color {
        switch type {
        case .overdue: return .red
        case .dueSoon: return .orange
        case .commitment: return .blue
        case .blocked: return .blue
        }
    }
}

// MARK: - Decision State Row (Shows decisions as current state)

struct DecisionStateRow: View {
    @Bindable var decision: ExtractedDecision

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                // Phrase as current state, not a log entry
                Text(decision.content)
                    .font(.subheadline)

                if !decision.affects.isEmpty {
                    Text("Affects: \(decision.affects)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button("Mark Superseded") {
                    decision.status = "Superseded"
                }
                Button("Mark Reversed") {
                    decision.status = "Reversed"
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
                    .padding(8)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - All Clear State (Situational Reassurance)

struct AllClearState: View {
    let lastDecisionDate: Date?
    let noteCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Nothing needs your attention")
                    .font(.headline)

                // Situational context
                if let lastDate = lastDecisionDate {
                    Text("Your last decision was \(lastDate, style: .relative) ago")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if noteCount > 0 {
                    Text("You have \(noteCount) note\(noteCount == 1 ? "" : "s") recorded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Record a voice note to capture decisions and actions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Command Section

struct CommandSection<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
            }

            VStack(spacing: 8) {
                content
            }
        }
    }
}


// MARK: - Commitment Row

struct CommitmentRow: View {
    @Bindable var commitment: ExtractedCommitment

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { commitment.isCompleted.toggle() }) {
                Image(systemName: commitment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(commitment.isCompleted ? .green : .secondary)
            }

            Text(commitment.what)
                .font(.subheadline)
                .strikethrough(commitment.isCompleted)
                .foregroundStyle(commitment.isCompleted ? .secondary : .primary)

            Spacer()

            Text(commitment.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Action Row

struct ActionRow: View {
    @Bindable var action: ExtractedAction
    let urgent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { action.isCompleted.toggle() }) {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(action.isCompleted ? .green : (urgent ? .orange : .secondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(action.content)
                    .font(.subheadline)
                    .strikethrough(action.isCompleted)
                    .foregroundStyle(action.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    if action.owner != "Me" {
                        Label(action.owner, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if action.deadline != "TBD" {
                        Label(action.deadline, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(action.isOverdue ? .red : (action.isDueSoon ? .orange : .secondary))
                    }

                    if action.isBlocked {
                        Label("Blocked", systemImage: "hand.raised")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(urgent ? Color.orange.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Unresolved Row

struct UnresolvedRow: View {
    let item: UnresolvedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.content)
                .font(.subheadline)

            HStack(spacing: 8) {
                Text(item.reason)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text(item.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Recent Note Row

struct RecentNoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            if note.hasAudio {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(note.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
// MARK: - Record Button

struct RecordButtonView: View {
    let onTap: () -> Void
    @State private var pulseAnimation = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.6)

                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color(red: 0.8, green: 0, blue: 0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }
}

#Preview {
    CommandCenterView()
        .modelContainer(for: [Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self], inMemory: true)
}
