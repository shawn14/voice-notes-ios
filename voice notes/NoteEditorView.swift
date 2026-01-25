//
//  NoteEditorView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    @Query private var allTags: [Tag]

    @Query private var allProjects: [Project]

    @State private var isProcessingTags = false
    @State private var isAnalyzing = false
    @State private var isTransforming = false
    @State private var analysis: NoteAnalysis?
    @State private var intentAnalysis: IntentAnalysis?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingDeleteConfirm = false
    @State private var transformedText: String?
    @State private var transformationType: String?
    @State private var showingCustomPrompt = false
    @State private var customPromptText = ""
    @State private var showingShareSheet = false
    @State private var showingProjectPicker = false

    @State private var audioRecorder = AudioRecorder()
    private let isNewNote: Bool

    /// Content formatted for sharing
    private var shareableContent: String {
        var parts: [String] = []

        if !note.title.isEmpty {
            parts.append(note.title)
            parts.append("")  // blank line
        }

        if !note.content.isEmpty {
            parts.append(note.content)
        }

        // Add tags if any
        if !note.tags.isEmpty {
            parts.append("")
            parts.append("Tags: " + note.tags.map { $0.name }.joined(separator: ", "))
        }

        return parts.joined(separator: "\n")
    }

    /// Items to share (text + audio if available)
    private var shareItems: [Any] {
        var items: [Any] = [shareableContent]

        // Include audio file if available
        if let audioURL = note.audioURL {
            items.append(audioURL)
        }

        return items
    }

    init(note: Note?) {
        if let note = note {
            self.note = note
            self.isNewNote = false
        } else {
            self.note = Note()
            self.isNewNote = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title field - wraps to multiple lines
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)

                // Audio playback bar (if has audio)
                if let url = note.audioURL {
                    HStack {
                        AudioPlayerBar(url: url, audioRecorder: audioRecorder)

                        // Extract button for voice notes
                        if note.transcript != nil && !note.transcript!.isEmpty {
                            Button(action: extractIntent) {
                                if isAnalyzing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("Extract", systemImage: "brain.head.profile")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isAnalyzing)
                        }
                    }
                }

                // Intent Strip (after audio player)
                if intentAnalysis != nil || note.intentType != "Unknown" {
                    IntentStripView(
                        selectedIntent: Binding(
                            get: { note.intent },
                            set: { note.intent = $0 }
                        ),
                        aiConfidence: intentAnalysis?.intentConfidence
                    )
                }

                // Structured Extraction (subject + missing info)
                if let subject = note.extractedSubject {
                    StructuredExtractionView(
                        subject: subject,
                        missingInfo: note.missingInfo
                    )
                }

                // Next Step (prominent, actionable)
                if let nextStep = note.suggestedNextStep, !nextStep.isEmpty {
                    NextStepView(note: note)
                }

                // Project Association
                ProjectAssociationView(
                    inferredProjectName: note.inferredProjectName,
                    assignedProjectId: $note.projectId,
                    allProjects: allProjects,
                    showingPicker: $showingProjectPicker
                )

                // Note Analysis
                if let analysis = analysis {
                    NoteAnalysisView(
                        analysis: analysis,
                        onDismiss: { self.analysis = nil },
                        hasNextStep: note.suggestedNextStep != nil && !note.suggestedNextStep!.isEmpty
                    )
                }

                // Notes section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Notes")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // AI Transform menu
                        if !note.content.isEmpty {
                            Menu {
                                Section("Share") {
                                    Button(action: { transformNote(to: "tweet") }) {
                                        Label("Tweet / X Post", systemImage: "bird")
                                    }
                                    Button(action: { transformNote(to: "linkedin") }) {
                                        Label("LinkedIn Post", systemImage: "person.2")
                                    }
                                    Button(action: { transformNote(to: "thread") }) {
                                        Label("Twitter Thread", systemImage: "text.bubble")
                                    }
                                }
                                Section("Build in Public") {
                                    Button(action: { transformNote(to: "changelog") }) {
                                        Label("Changelog Entry", systemImage: "list.bullet.rectangle")
                                    }
                                    Button(action: { transformNote(to: "update") }) {
                                        Label("Product Update", systemImage: "megaphone")
                                    }
                                    Button(action: { transformNote(to: "blog") }) {
                                        Label("Blog Post Intro", systemImage: "doc.richtext")
                                    }
                                }
                                Section("Format") {
                                    Button(action: { transformNote(to: "summary") }) {
                                        Label("Summarize", systemImage: "text.badge.minus")
                                    }
                                    Button(action: { transformNote(to: "bullets") }) {
                                        Label("Action Items", systemImage: "checklist")
                                    }
                                    Button(action: { transformNote(to: "cleanup") }) {
                                        Label("Clean Up", systemImage: "wand.and.stars")
                                    }
                                }
                                Section {
                                    Button(action: { showingCustomPrompt = true }) {
                                        Label("Custom Prompt...", systemImage: "pencil.and.outline")
                                    }
                                }
                            } label: {
                                if isTransforming {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("AI", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.purple)
                            .disabled(isTransforming)
                        }
                    }

                    TextEditor(text: $note.content)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.black)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(Color(red: 1.0, green: 0.98, blue: 0.9))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }

                // Transformed text result
                if let transformed = transformedText, let type = transformationType {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(transformationTitle(for: type))
                                .font(.headline)
                                .foregroundStyle(.purple)

                            Spacer()

                            Button("Use This") {
                                note.content = transformed
                                transformedText = nil
                                transformationType = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)

                            Button(action: {
                                transformedText = nil
                                transformationType = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(transformed)
                            .font(.system(.body, design: .serif))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)

                        // Copy button
                        Button(action: {
                            UIPasteboard.general.string = transformed
                        }) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Tags section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Tags")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: extractTags) {
                            if isProcessingTags {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Auto-tag", systemImage: "tag")
                            }
                        }
                        .disabled(isProcessingTags || (note.content.isEmpty && (note.transcript?.isEmpty ?? true)))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Current tags (auto-tagged in red)
                    if !note.tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(note.tags) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.name)
                                    Button(action: { removeTag(tag) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .cornerRadius(16)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(isNewNote ? "New Note" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNewNote {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .fontWeight(.semibold)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog("Delete Note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onChange(of: note.content) {
            note.updatedAt = Date()
        }
        .sheet(isPresented: $showingCustomPrompt) {
            CustomPromptSheet(
                promptText: $customPromptText,
                isPresented: $showingCustomPrompt,
                onSubmit: {
                    transformNote(to: "custom")
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareNoteView(note: note)
        }
    }

    private func removeTag(_ tag: Tag) {
        note.tags.removeAll { $0.id == tag.id }
    }

    private func saveNote() {
        modelContext.insert(note)
        dismiss()
    }

    private func deleteNote() {
        if let fileName = note.audioFileName {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(note)
        dismiss()
    }

    private func extractTags() {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            return
        }

        isProcessingTags = true
        let textToAnalyze = [note.content, note.transcript ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        Task {
            do {
                let extractor = TagExtractor(apiKey: apiKey)
                let tagNames = try await extractor.extractTags(from: textToAnalyze)

                await MainActor.run {
                    for name in tagNames {
                        if let existingTag = allTags.first(where: { $0.name.lowercased() == name.lowercased() }) {
                            if !note.tags.contains(existingTag) {
                                note.tags.append(existingTag)
                            }
                        } else {
                            let newTag = Tag(name: name)
                            modelContext.insert(newTag)
                            note.tags.append(newTag)
                        }
                    }
                    isProcessingTags = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isProcessingTags = false
                }
            }
        }
    }

    private func extractIntent() {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            return
        }

        // Use content (which contains transcript) or fall back to transcript
        let textToAnalyze = !note.content.isEmpty ? note.content : (note.transcript ?? "")
        guard !textToAnalyze.isEmpty else { return }

        isAnalyzing = true

        Task {
            do {
                let result = try await SummaryService.extractIntent(text: textToAnalyze, apiKey: apiKey)
                await MainActor.run {
                    intentAnalysis = result

                    // Update note with intent data
                    note.intentType = result.intent
                    note.intentConfidence = result.intentConfidence

                    if let subject = result.subject {
                        note.extractedSubject = ExtractedSubject(
                            topic: subject.topic,
                            action: subject.action
                        )
                    }

                    note.suggestedNextStep = result.nextStep
                    note.nextStepTypeRaw = result.nextStepType
                    note.missingInfo = result.missingInfo.map {
                        MissingInfoItem(field: $0.field, description: $0.description)
                    }
                    note.inferredProjectName = result.inferredProject

                    // Auto-match inferred project to existing projects
                    if let inferredName = result.inferredProject, !inferredName.isEmpty {
                        // Try to find a matching project using ProjectMatcher
                        let textToMatch = "\(inferredName) \(note.content)"
                        if let match = ProjectMatcher.findMatch(for: textToMatch, in: self.allProjects) {
                            note.projectId = match.project.id
                        }
                    }

                    // Also populate the legacy analysis for backward compatibility
                    analysis = NoteAnalysis(
                        summary: result.summary,
                        keyPoints: result.keyPoints,
                        extractedDecisions: result.decisions,
                        extractedActions: result.actions,
                        extractedCommitments: result.commitments,
                        unresolvedItems: result.unresolved
                    )

                    // Save extracted items to database (separate from note)
                    for decision in result.decisions {
                        let extracted = ExtractedDecision(
                            content: decision.content,
                            affects: decision.affects,
                            confidence: decision.confidence,
                            status: "Active",
                            sourceNoteId: note.id
                        )
                        modelContext.insert(extracted)
                    }

                    for action in result.actions {
                        let extracted = ExtractedAction(
                            content: action.content,
                            owner: action.owner,
                            deadline: action.deadline,
                            priority: "Normal",
                            sourceNoteId: note.id
                        )
                        modelContext.insert(extracted)
                    }

                    for commitment in result.commitments {
                        let extracted = ExtractedCommitment(
                            who: commitment.who,
                            what: commitment.what,
                            sourceNoteId: note.id
                        )
                        modelContext.insert(extracted)
                    }

                    for unresolved in result.unresolved {
                        let extracted = UnresolvedItem(
                            content: unresolved.content,
                            reason: unresolved.reason,
                            sourceNoteId: note.id
                        )
                        modelContext.insert(extracted)
                    }

                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isAnalyzing = false
                }
            }
        }
    }

    private func transformNote(to type: String) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            return
        }

        guard !note.content.isEmpty else { return }

        isTransforming = true
        transformationType = type

        Task {
            do {
                let result = try await transformText(note.content, to: type, apiKey: apiKey)
                await MainActor.run {
                    transformedText = result
                    isTransforming = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isTransforming = false
                }
            }
        }
    }

    private func transformText(_ text: String, to type: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = transformPrompt(for: type, text: text)

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
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

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func transformPrompt(for type: String, text: String) -> String {
        switch type {
        case "tweet":
            return """
            Turn this into a compelling tweet (max 280 chars). Make it punchy and engaging for the indie hacker / startup community. No hashtags unless they add value. Just return the tweet text.

            Original: \(text)
            """
        case "linkedin":
            return """
            Turn this into a LinkedIn post for a solo founder / indie hacker. Make it authentic and valuable, not salesy. Include line breaks for readability. Just return the post text.

            Original: \(text)
            """
        case "thread":
            return """
            Turn this into a Twitter/X thread (3-5 tweets). Number each tweet. Make it valuable for the indie hacker community. Keep each under 280 chars.

            Original: \(text)
            """
        case "changelog":
            return """
            Turn this into a changelog entry for a product update. Be concise and focus on what changed and why it matters to users. Use bullet points if multiple items.

            Original: \(text)
            """
        case "update":
            return """
            Turn this into a "building in public" product update. Make it authentic, share the journey including challenges. Good for sharing with your audience.

            Original: \(text)
            """
        case "blog":
            return """
            Write a compelling blog post introduction (2-3 paragraphs) based on this. Hook the reader and set up the main points. Authentic indie hacker voice.

            Original: \(text)
            """
        case "summary":
            return """
            Summarize this in 2-3 concise sentences. Focus on the key points.

            Original: \(text)
            """
        case "bullets":
            return """
            Extract actionable items and key points as a bullet list. Focus on next steps and decisions.

            Original: \(text)
            """
        case "cleanup":
            return """
            Clean up this text: fix grammar, improve clarity, but keep the same meaning and tone. Return only the cleaned text.

            Original: \(text)
            """
        case "custom":
            return """
            \(customPromptText)

            Text to work with:
            \(text)
            """
        default:
            return "Summarize: \(text)"
        }
    }

    private func transformationTitle(for type: String) -> String {
        switch type {
        case "tweet": return "Tweet"
        case "linkedin": return "LinkedIn Post"
        case "thread": return "Twitter Thread"
        case "changelog": return "Changelog"
        case "update": return "Product Update"
        case "blog": return "Blog Intro"
        case "summary": return "Summary"
        case "bullets": return "Action Items"
        case "cleanup": return "Cleaned Up"
        case "custom": return "Custom Result"
        default: return "Result"
        }
    }
}

// Custom prompt sheet
struct CustomPromptSheet: View {
    @Binding var promptText: String
    @Binding var isPresented: Bool
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What should AI do with your note?")
                    .font(.headline)

                TextEditor(text: $promptText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Text("Examples:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    PromptSuggestion(text: "Turn this into a cold email", promptText: $promptText)
                    PromptSuggestion(text: "Make this funnier", promptText: $promptText)
                    PromptSuggestion(text: "Translate to Spanish", promptText: $promptText)
                    PromptSuggestion(text: "Write a landing page headline", promptText: $promptText)
                    PromptSuggestion(text: "Create a Hacker News post", promptText: $promptText)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Custom Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transform") {
                        isPresented = false
                        onSubmit()
                    }
                    .disabled(promptText.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct PromptSuggestion: View {
    let text: String
    @Binding var promptText: String

    var body: some View {
        Button(action: { promptText = text }) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// Audio player bar
struct AudioPlayerBar: View {
    let url: URL
    @Bindable var audioRecorder: AudioRecorder

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: audioRecorder.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
            }

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 3, height: CGFloat.random(in: 8...25))
                }
            }
            .frame(height: 30)

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func togglePlayback() {
        if audioRecorder.isPlaying {
            audioRecorder.stopPlaying()
        } else {
            try? audioRecorder.playAudio(url: url)
        }
    }
}

// Note Analysis View - Collapsed by default, shows "Why we think this"
struct NoteAnalysisView: View {
    let analysis: NoteAnalysis
    let onDismiss: () -> Void
    let hasNextStep: Bool  // If true, hide single action (it's already shown as Next Step)

    @State private var isExpanded = false

    // Only show actions if there are multiple, or if they're delegated (not "Me")
    private var actionsToShow: [NoteAnalysis.ActionExtract] {
        let actions = analysis.extractedActions
        // If there's a next step and only one action owned by "Me", hide it (redundant)
        if hasNextStep && actions.count == 1 && actions.first?.owner.lowercased() == "me" {
            return []
        }
        return actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header - always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text("Why we think this")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary
                    Text(analysis.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)

                    // Key Points
                    if !analysis.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Key Points")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            ForEach(analysis.keyPoints, id: \.self) { point in
                                Text("• \(point)")
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Extracted Decisions
                    if !analysis.extractedDecisions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Decisions", systemImage: "checkmark.seal")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)

                            ForEach(analysis.extractedDecisions, id: \.content) { decision in
                                HStack {
                                    Text(decision.content)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(decision.confidence)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(confidenceColor(for: decision.confidence))
                                        .foregroundStyle(.white)
                                        .cornerRadius(4)
                                }
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // Extracted Actions (only if multiple or delegated)
                    if !actionsToShow.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Actions", systemImage: "checklist")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)

                            ForEach(actionsToShow, id: \.content) { action in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.content)
                                        .font(.subheadline)
                                    HStack(spacing: 12) {
                                        Label(action.owner, systemImage: "person")
                                        Label(action.deadline, systemImage: "calendar")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // Commitments
                    if !analysis.extractedCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Commitments", systemImage: "person.badge.clock")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)

                            ForEach(analysis.extractedCommitments, id: \.what) { commitment in
                                Text("\(commitment.who): \(commitment.what)")
                                    .font(.subheadline)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    // Unresolved
                    if !analysis.unresolvedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Needs Resolution", systemImage: "questionmark.circle")
                                .font(.subheadline.bold())
                                .foregroundStyle(.purple)

                            ForEach(analysis.unresolvedItems, id: \.content) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.content)
                                        .font(.subheadline)
                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func confidenceColor(for level: String) -> Color {
        switch level.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }
}

// MARK: - Intent Strip View

struct IntentStripView: View {
    @Binding var selectedIntent: NoteIntent
    let aiConfidence: Double?
    @State private var showConfidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        if aiConfidence != nil {
                            withAnimation { showConfidence.toggle() }
                        }
                    }

                Spacer()

                if showConfidence, let confidence = aiConfidence {
                    Text("\(Int(confidence * 100))% confident")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteIntent.allCases, id: \.self) { intent in
                        IntentPill(
                            intent: intent,
                            isSelected: selectedIntent == intent,
                            onTap: { selectedIntent = intent }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct IntentPill: View {
    let intent: NoteIntent
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: intent.icon)
                    .font(.caption)
                Text(intent.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? intent.color : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Structured Extraction View

struct StructuredExtractionView: View {
    let subject: ExtractedSubject
    let missingInfo: [MissingInfoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(subject.topic)
                        .font(.headline)
                }

                if let action = subject.action, !action.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(action)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Missing info warnings
            if !missingInfo.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(missingInfo, id: \.field) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Next Step View (Interactive Resolution)

struct NextStepView: View {
    @Bindable var note: Note
    @State private var isExpanded = false
    @State private var selectedDate = Date()

    private var isResolved: Bool { note.isNextStepResolved }
    private var nextStep: String { note.suggestedNextStep ?? "" }
    private var stepType: NextStepType { note.nextStepType }

    var body: some View {
        VStack(spacing: 0) {
            // Main card - tap to expand
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    Image(systemName: isResolved ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isResolved ? .green : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next step")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isResolved, let resolution = note.nextStepResolution {
                            Text("✓ \(resolution)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                        } else {
                            Text(nextStep)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }

                    Spacer()

                    if isResolved {
                        Button(action: { note.unresolveNextStep() }) {
                            Text("Undo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Expanded resolution UI
            if isExpanded && !isResolved {
                VStack(spacing: 12) {
                    Divider()

                    switch stepType {
                    case .date:
                        DateResolutionView(
                            selectedDate: $selectedDate,
                            onResolve: { dateString in
                                note.resolveNextStep(with: dateString)
                                withAnimation { isExpanded = false }
                            }
                        )

                    case .contact:
                        ContactResolutionView(
                            onResolve: { contactString in
                                note.resolveNextStep(with: contactString)
                                withAnimation { isExpanded = false }
                            }
                        )

                    case .decision:
                        DecisionResolutionView(
                            onResolve: { decision in
                                note.resolveNextStep(with: decision)
                                withAnimation { isExpanded = false }
                            }
                        )

                    case .simple:
                        SimpleResolutionView(
                            onResolve: {
                                note.resolveNextStep(with: "Done")
                                withAnimation { isExpanded = false }
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(isResolved ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isResolved ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Date Resolution View

struct DateResolutionView: View {
    @Binding var selectedDate: Date
    let onResolve: (String) -> Void
    @State private var showFullPicker = false

    private var quickDates: [(String, Date)] {
        let calendar = Calendar.current
        let today = Date()
        return [
            ("Today", today),
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today)!),
            ("Next Week", calendar.date(byAdding: .weekOfYear, value: 1, to: today)!)
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            // Quick date options
            HStack(spacing: 8) {
                ForEach(quickDates, id: \.0) { label, date in
                    Button(action: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        onResolve(formatter.string(from: date))
                    }) {
                        Text(label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { showFullPicker.toggle() }) {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Full date picker (when expanded)
            if showFullPicker {
                DatePicker("Pick a date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)

                Button(action: {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    onResolve(formatter.string(from: selectedDate))
                }) {
                    Text("Confirm Date")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Contact Resolution View

struct ContactResolutionView: View {
    let onResolve: (String) -> Void
    @State private var contactName = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Who did you contact?", text: $contactName)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    let resolution = contactName.isEmpty ? "Contacted" : "Sent to \(contactName)"
                    onResolve(resolution)
                }) {
                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Decision Resolution View

struct DecisionResolutionView: View {
    let onResolve: (String) -> Void
    @State private var decision = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("What did you decide?", text: $decision)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    let resolution = decision.isEmpty ? "Decided" : "Decided: \(decision)"
                    onResolve(resolution)
                }) {
                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Simple Resolution View

struct SimpleResolutionView: View {
    let onResolve: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button(action: onResolve) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("Mark Done")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Project Association View

struct ProjectAssociationView: View {
    let inferredProjectName: String?
    @Binding var assignedProjectId: UUID?
    let allProjects: [Project]
    @Binding var showingPicker: Bool

    private var assignedProject: Project? {
        guard let id = assignedProjectId else { return nil }
        return allProjects.first { $0.id == id }
    }

    private var displayText: String {
        if let project = assignedProject {
            return project.name
        } else if let inferred = inferredProjectName, !inferred.isEmpty {
            return "\(inferred) (suggested)"
        }
        return "No project"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: assignedProject?.icon ?? "folder")
                .foregroundStyle(assignedProject != nil ? .blue : .secondary)

            Text(displayText)
                .font(.subheadline)
                .foregroundStyle(assignedProject != nil ? .primary : .secondary)

            if inferredProjectName != nil && assignedProject == nil {
                Text("(suggested)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Button("None") {
                    assignedProjectId = nil
                }

                Divider()

                ForEach(allProjects.filter { !$0.isArchived }) { project in
                    Button(project.name) {
                        assignedProjectId = project.id
                    }
                }
            } label: {
                Text("Change")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// Flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, spacing: spacing, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(note: nil)
    }
    .modelContainer(for: [Note.self, Tag.self, Project.self], inMemory: true)
}
