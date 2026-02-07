//
//  NoteDetailView.swift
//  voice notes
//
//  Simplified note detail view - clean Wave-inspired design
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI

enum NoteTab: String, CaseIterable {
    case insights = "Insights"
    case transcript = "Transcript"
    case transform = "Transform"
}

// MARK: - AI Transform Types

enum AITransformType: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case executiveSummary = "Executive Summary"
    case tweet = "Tweet"
    case prd = "PRD"
    case meetingSummary = "Meeting Summary"
    case ceoReport = "CEO Report"
    case custom = "Custom..."

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .executiveSummary: return "briefcase"
        case .tweet: return "at"
        case .prd: return "list.bullet.clipboard"
        case .meetingSummary: return "person.3"
        case .ceoReport: return "chart.bar.doc.horizontal"
        case .custom: return "wand.and.stars"
        }
    }

    var prompt: String {
        switch self {
        case .summary:
            return "Summarize this voice note in 2-3 concise sentences, capturing the key points."
        case .executiveSummary:
            return "Create a brief executive summary of this voice note. Include: key points, decisions made, and action items. Format with bullet points."
        case .tweet:
            return "Convert this voice note into a compelling tweet (max 280 characters). Make it engaging and shareable."
        case .prd:
            return "Transform this voice note into a Product Requirements Document (PRD) format. Include: Overview, Goals, Requirements, Success Metrics, and Timeline if mentioned."
        case .meetingSummary:
            return "Format this as a meeting summary. Include: Attendees (if mentioned), Discussion Points, Decisions Made, Action Items with owners, and Next Steps."
        case .ceoReport:
            return "Transform this into a concise CEO/executive report. Include: Key Highlights, Strategic Implications, Risks/Concerns, and Recommended Actions. Keep it brief and high-level."
        case .custom:
            return "" // User provides custom prompt
        }
    }
}

struct NoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    @Query private var allProjects: [Project]
    @Query private var allDecisions: [ExtractedDecision]
    @Query private var allActions: [ExtractedAction]
    @Query private var allExtractedURLs: [ExtractedURL]

    @State private var selectedTab: NoteTab = .insights
    @State private var audioRecorder = AudioRecorder()
    @State private var showingDeleteConfirm = false
    @State private var showingShareSheet = false
    @State private var showingProjectPicker = false
    @State private var isGeneratingSummary = false

    // AI Transform state
    @State private var showingAIMenu = false
    @State private var showingCustomPrompt = false
    @State private var customPromptText = ""
    @State private var isGeneratingAI = false
    @State private var aiOutput: String?
    @State private var aiOutputType: AITransformType?
    @State private var aiError: String?

    // Image attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var selectedImageForFullscreen: String?
    @State private var showingFullscreenImage = false

    // Computed summary from transcript
    private var summary: String {
        // If we have extracted subject/next step, build a summary
        var parts: [String] = []

        if let subject = note.extractedSubject {
            parts.append(subject.topic)
            if let action = subject.action, !action.isEmpty {
                parts.append(action)
            }
        }

        if let nextStep = note.suggestedNextStep, !nextStep.isEmpty {
            parts.append("Next: \(nextStep)")
        }

        // If no extraction, use content or transcript preview
        if parts.isEmpty {
            let text = !note.content.isEmpty ? note.content : (note.transcript ?? "")
            return text.isEmpty ? "No summary available" : text
        }

        return parts.joined(separator: ". ")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Tab picker
                tabPicker
                    .padding(.top, 8)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        contentView
                    }
                    .padding()
                    .padding(.bottom, 100) // Space for audio player
                }

                Spacer()
            }

            // Bottom audio player
            if note.audioURL != nil {
                audioPlayerBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Photo picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        if isProcessingImage {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .foregroundStyle(.white)
                        }
                    }
                    .disabled(isProcessingImage)

                    // Share button
                    Button(action: { showingShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            processPhoto(newItem)
        }
        .fullScreenCover(isPresented: $showingFullscreenImage) {
            if let fileName = selectedImageForFullscreen {
                FullscreenImageView(fileName: fileName) {
                    showingFullscreenImage = false
                    selectedImageForFullscreen = nil
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Delete Note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareNoteView(note: note)
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerSheet(
                selectedProjectId: $note.projectId,
                projects: allProjects.filter { !$0.isArchived },
                noteContent: note.transcript ?? note.content
            )
        }
        .sheet(isPresented: $showingCustomPrompt) {
            CustomPromptSheet(
                promptText: $customPromptText,
                isPresented: $showingCustomPrompt,
                onSubmit: {
                    generateAIContent(type: .custom, customPrompt: customPromptText)
                    customPromptText = ""
                }
            )
        }
        .alert("AI Error", isPresented: .init(
            get: { aiError != nil },
            set: { if !$0 { aiError = nil } }
        )) {
            Button("OK") { aiError = nil }
        } message: {
            Text(aiError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.displayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        // Date
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.gray)

                        // Project badge if assigned
                        if let projectId = note.projectId,
                           let project = allProjects.first(where: { $0.id == projectId }) {
                            Button(action: { showingProjectPicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: project.icon)
                                        .font(.caption)
                                    Text(project.name)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .cornerRadius(12)
                            }
                        }
                    }
                }

                Spacer()

                // Favorite button
                Button(action: { note.isFavorite.toggle() }) {
                    Image(systemName: note.isFavorite ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(note.isFavorite ? .red : .gray)
                }
            }
        }
        .padding()
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(NoteTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedTab == tab ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedTab == tab ? Color(.systemGray5) : Color.clear
                        )
                        .cornerRadius(8)
                }
            }
        }
        .padding(4)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .insights:
            insightsView
        case .transcript:
            transcriptView
        case .transform:
            transformView
        }
    }

    // Computed properties for note-specific decisions and actions
    private var noteDecisions: [ExtractedDecision] {
        allDecisions.filter { $0.sourceNoteId == note.id }
    }

    private var noteActions: [ExtractedAction] {
        allActions.filter { $0.sourceNoteId == note.id && !$0.isCompleted }
    }

    private var noteURLs: [ExtractedURL] {
        allExtractedURLs.filter { $0.sourceNoteId == note.id }
    }

    private var insightsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Image Gallery (if note has images)
            if note.hasImages {
                ImageGalleryView(
                    imageFileNames: note.imageFileNames,
                    onImageTap: { fileName in
                        selectedImageForFullscreen = fileName
                        showingFullscreenImage = true
                    },
                    onImageDelete: { fileName in
                        ImageService.deleteImage(fileName: fileName)
                        note.removeImageFileName(fileName)
                    }
                )
            }

            // AI Insights Card (if any extracted items exist)
            if !noteDecisions.isEmpty || !noteActions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text("AI Found")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    ForEach(noteDecisions) { decision in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(decision.content)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    ForEach(noteActions) { action in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(action.content)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            Text(summary)
                .font(.body)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(12)

            // Intent badge if available
            if note.intentType != "Unknown" {
                HStack {
                    Image(systemName: note.intent.icon)
                    Text(note.intentType)
                }
                .font(.subheadline)
                .foregroundStyle(note.intent.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(note.intent.color.opacity(0.15))
                .cornerRadius(20)
            }

            // Next step if available
            if let nextStep = note.suggestedNextStep, !nextStep.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Step")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.gray)

                    HStack(spacing: 12) {
                        Image(systemName: note.isNextStepResolved ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            .foregroundStyle(note.isNextStepResolved ? .green : .blue)

                        Text(note.isNextStepResolved ? (note.nextStepResolution ?? "Done") : nextStep)
                            .font(.body)
                            .foregroundStyle(note.isNextStepResolved ? .green : .white)

                        Spacer()

                        if !note.isNextStepResolved {
                            Button("Done") {
                                note.resolveNextStep(with: "Completed")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
                }
            }

            // URL Previews
            if !noteURLs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.blue)
                        Text("Links")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.gray)
                    }

                    ForEach(noteURLs) { extractedURL in
                        URLPreviewCard(extractedURL: extractedURL)
                    }
                }
            }

            // Delete button
            Button(action: { showingDeleteConfirm = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Note")
                }
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.top, 20)
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let transcript = note.transcript, !transcript.isEmpty {
                HStack {
                    Spacer()
                    Text("\(transcript.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Text(transcript)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("No transcript available")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Transform View

    private var transformView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Transform options grid
            Text("Transform your note")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.gray)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(AITransformType.allCases) { type in
                    Button {
                        if type == .custom {
                            showingCustomPrompt = true
                        } else {
                            generateAIContent(type: type)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.title2)
                            Text(type.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(aiOutputType == type ? .white : .blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(aiOutputType == type ? Color.blue : Color.blue.opacity(0.15))
                        .cornerRadius(12)
                    }
                    .disabled(isGeneratingAI)
                }
            }

            // Output section
            if isGeneratingAI {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.blue)
                    Text("Generating \(aiOutputType?.rawValue ?? "")...")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let output = aiOutput, let type = aiOutputType {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: type.icon)
                            .foregroundStyle(.blue)
                        Text(type.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)

                        Spacer()

                        // Copy button
                        Button {
                            UIPasteboard.general.string = output
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }

                    Text(output)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("Select a transform above")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    Text("AI will generate content from your note")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Audio Player

    private var audioPlayerBar: some View {
        VStack(spacing: 12) {
            // Seek slider
            HStack(spacing: 8) {
                Text(formatDuration(audioRecorder.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
                    .frame(width: 40, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { audioRecorder.currentTime },
                        set: { audioRecorder.seek(to: $0) }
                    ),
                    in: 0...(audioRecorder.duration > 0 ? audioRecorder.duration : (note.audioDuration ?? 1))
                )
                .tint(.blue)

                Text(formatDuration(audioRecorder.duration > 0 ? audioRecorder.duration : note.audioDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
                    .frame(width: 40, alignment: .leading)
            }

            // Controls row
            HStack(spacing: 20) {
                // Skip backward 15s
                Button {
                    audioRecorder.seek(to: audioRecorder.currentTime - 15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                // Play/Pause
                Button(action: togglePlayback) {
                    Image(systemName: audioRecorder.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.blue)
                        .clipShape(Circle())
                }

                // Skip forward 15s
                Button {
                    audioRecorder.seek(to: audioRecorder.currentTime + 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                // Speed control
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            audioRecorder.setPlaybackRate(Float(rate))
                        } label: {
                            HStack {
                                Text(rate == 1.0 ? "1x" : "\(rate, specifier: "%.2g")x")
                                if audioRecorder.playbackRate == Float(rate) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(audioRecorder.playbackRate, specifier: "%.2g")x")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.95))
        )
        .padding()
    }

    // MARK: - Actions

    private func togglePlayback() {
        guard let url = note.audioURL else { return }

        if audioRecorder.isPlaying {
            audioRecorder.pausePlaying()
        } else if audioRecorder.currentTime > 0 {
            audioRecorder.resumePlaying()
        } else {
            try? audioRecorder.playAudio(url: url)
        }
    }

    private func deleteNote() {
        if let fileName = note.audioFileName {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        // Delete image files
        note.deleteImageFiles()
        modelContext.delete(note)
        dismiss()
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - AI Generation

    private func generateAIContent(type: AITransformType, customPrompt: String? = nil) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            aiError = "OpenAI API key not configured"
            return
        }

        let sourceText = note.transcript ?? note.content
        guard !sourceText.isEmpty else {
            aiError = "No content to transform"
            return
        }

        let prompt = customPrompt ?? type.prompt

        isGeneratingAI = true
        aiOutputType = type

        Task {
            do {
                let result = try await generateWithOpenAI(
                    prompt: prompt,
                    content: sourceText,
                    apiKey: apiKey
                )

                await MainActor.run {
                    aiOutput = result
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiError = "Failed to generate: \(error.localizedDescription)"
                    isGeneratingAI = false
                    aiOutputType = nil
                }
            }
        }
    }

    // MARK: - Photo Processing

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingImage = true

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        aiError = "Could not load image"
                        isProcessingImage = false
                        selectedPhotoItem = nil
                    }
                    return
                }

                let fileName = try ImageService.saveImage(image, noteId: note.id)

                await MainActor.run {
                    note.addImageFileName(fileName)
                    isProcessingImage = false
                    selectedPhotoItem = nil
                }

                // Try OCR if note has no content
                if note.content.isEmpty {
                    let extractedText = try await ImageService.extractText(from: image)
                    if !extractedText.isEmpty {
                        await MainActor.run {
                            note.content = extractedText
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    aiError = "Failed to process image: \(error.localizedDescription)"
                    isProcessingImage = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func generateWithOpenAI(prompt: String, content: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": content]
            ],
            "max_tokens": 1000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No response generated"
    }
}

// MARK: - Project Picker Sheet

struct ProjectPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProjectId: UUID?
    let projects: [Project]
    var noteContent: String = ""  // For learning from corrections

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedProjectId = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.gray)
                        Text("No Project")
                        Spacer()
                        if selectedProjectId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(projects) { project in
                    Button {
                        // Learn from this assignment if changing to a different project
                        if selectedProjectId != project.id && !noteContent.isEmpty {
                            ProjectMatcher.learnFromCorrection(text: noteContent, assignedTo: project)
                        }
                        selectedProjectId = project.id
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: project.icon)
                                .foregroundStyle(.blue)
                            Text(project.name)
                            Spacer()
                            if selectedProjectId == project.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Image Gallery View

struct ImageGalleryView: View {
    let imageFileNames: [String]
    let onImageTap: (String) -> Void
    let onImageDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.blue)
                Text("Attachments")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(imageFileNames.count) image\(imageFileNames.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(imageFileNames, id: \.self) { fileName in
                        ImageThumbnailView(
                            fileName: fileName,
                            onTap: { onImageTap(fileName) },
                            onDelete: { onImageDelete(fileName) }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

struct ImageThumbnailView: View {
    let fileName: String
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        if let image = ImageService.loadImage(fileName: fileName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .cornerRadius(8)
                .clipped()
                .onTapGesture { onTap() }
                .contextMenu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .confirmationDialog("Delete Image?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    Button("Cancel", role: .cancel) { }
                }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.gray)
                }
        }
    }
}

struct FullscreenImageView: View {
    let fileName: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = ImageService.loadImage(fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - URL Preview Card

struct URLPreviewCard: View {
    let extractedURL: ExtractedURL

    var body: some View {
        Button {
            if let url = URL(string: extractedURL.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                // Favicon or image placeholder
                if let imageURLString = extractedURL.imageURL,
                   let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        case .failure:
                            urlPlaceholderIcon
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        @unknown default:
                            urlPlaceholderIcon
                        }
                    }
                } else {
                    urlPlaceholderIcon
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(extractedURL.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let description = extractedURL.urlDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(extractedURL.displayHost)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var urlPlaceholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.15))
                .frame(width: 60, height: 60)

            Image(systemName: "link")
                .font(.title2)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NoteDetailView(note: Note(
            title: "Reflecting Loss and Change in Neighborhood",
            content: "A person reflects on the end of 2008, expressing a sense of finality and possibly loss.",
            transcript: "Feel like they took the shot of no. Can I ride through the hood?"
        ))
    }
    .modelContainer(for: [Note.self, Project.self], inMemory: true)
}
