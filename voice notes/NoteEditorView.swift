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

    @State private var isProcessingTags = false
    @State private var isAnalyzing = false
    @State private var isTransforming = false
    @State private var analysis: ChiefOfStaffAnalysis?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingDeleteConfirm = false
    @State private var transformedText: String?
    @State private var transformationType: String?
    @State private var showingCustomPrompt = false
    @State private var customPromptText = ""

    @State private var audioRecorder = AudioRecorder()
    private let isNewNote: Bool

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

                        // Analyze button for voice notes
                        if note.transcript != nil && !note.transcript!.isEmpty {
                            Button(action: analyzeNote) {
                                if isAnalyzing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("Analyze", systemImage: "brain.head.profile")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isAnalyzing)
                        }
                    }
                }

                // Chief of Staff Analysis
                if let analysis = analysis {
                    ChiefOfStaffView(analysis: analysis, onDismiss: { self.analysis = nil })
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

    private func analyzeNote() {
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
                let result = try await SummaryService.analyzeAsChiefOfStaff(text: textToAnalyze, apiKey: apiKey)
                await MainActor.run {
                    analysis = result
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

// Chief of Staff Analysis View
struct ChiefOfStaffView: View {
    let analysis: ChiefOfStaffAnalysis
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Analysis", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.red)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            // Classification tags
            FlowLayout(spacing: 6) {
                ForEach(analysis.classification, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(classificationColor(for: tag))
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                }
            }

            // Decisions
            if !analysis.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Decisions", systemImage: "checkmark.seal")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)

                    ForEach(analysis.decisions, id: \.self) { decision in
                        Text("• \(decision)")
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // Action Items
            if !analysis.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Action Items", systemImage: "checklist")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)

                    ForEach(analysis.actionItems, id: \.action) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.action)
                                .font(.subheadline)

                            HStack(spacing: 12) {
                                Label(item.owner, systemImage: "person")
                                Label(item.deadline, systemImage: "calendar")
                                Text(item.confidence)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(confidenceColor(for: item.confidence))
                                    .foregroundStyle(.white)
                                    .cornerRadius(4)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }

            // Open Questions
            if !analysis.openQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Open Questions", systemImage: "questionmark.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)

                    ForEach(analysis.openQuestions, id: \.self) { question in
                        Text("• \(question)")
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }

            // Suggested Automations
            if !analysis.suggestedAutomations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Suggested Actions", systemImage: "wand.and.stars")
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)

                    ForEach(analysis.suggestedAutomations, id: \.self) { suggestion in
                        HStack {
                            Text(suggestion)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func classificationColor(for type: String) -> Color {
        switch type.lowercased() {
        case "decision": return .green
        case "commitment": return .orange
        case "delegation": return .blue
        case "idea": return .purple
        case "risk/concern", "risk", "concern": return .red
        case "fyi": return .gray
        default: return .secondary
        }
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
    .modelContainer(for: [Note.self, Tag.self], inMemory: true)
}
