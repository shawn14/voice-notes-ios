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
    @State private var isGeneratingSummary = false
    @State private var keyPoints: [String] = []
    @State private var actionItems: [String] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingDeleteConfirm = false

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
                // Title field
                TextField("Title", text: $note.title)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .textFieldStyle(.plain)

                // Audio playback bar (if has audio)
                if let url = note.audioURL {
                    HStack {
                        AudioPlayerBar(url: url, audioRecorder: audioRecorder)

                        // Summarize button for voice notes
                        if note.transcript != nil && !note.transcript!.isEmpty {
                            Button(action: generateSummary) {
                                if isGeneratingSummary {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isGeneratingSummary)
                        }
                    }
                }

                // Key Points section
                if !keyPoints.isEmpty {
                    SummarySection(
                        title: "Key Points",
                        icon: "sparkles",
                        items: keyPoints,
                        color: Color.blue.opacity(0.1)
                    )
                }

                // Action Items section
                if !actionItems.isEmpty {
                    SummarySection(
                        title: "Action Items",
                        icon: "checkmark.circle",
                        items: actionItems,
                        color: Color.orange.opacity(0.1)
                    )
                }

                // Notes section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                        .foregroundStyle(.secondary)

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

                    // Current tags
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

                    // Available tags
                    if !availableTags.isEmpty {
                        Divider()
                        Text("Tap to add")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 8) {
                            ForEach(availableTags) { tag in
                                Button(action: { addTag(tag) }) {
                                    Text(tag.name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
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
    }

    private var availableTags: [Tag] {
        allTags.filter { !note.tags.contains($0) }
    }

    private func addTag(_ tag: Tag) {
        note.tags.append(tag)
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

    private func generateSummary() {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            errorMessage = "OpenAI API key not configured"
            showingError = true
            return
        }

        guard let transcript = note.transcript, !transcript.isEmpty else { return }

        isGeneratingSummary = true

        Task {
            do {
                let summary = try await SummaryService.generateSummary(for: transcript, apiKey: apiKey)
                await MainActor.run {
                    keyPoints = summary.keyPoints
                    actionItems = summary.actionItems
                    isGeneratingSummary = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isGeneratingSummary = false
                }
            }
        }
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

// Summary section component
struct SummarySection: View {
    let title: String
    let icon: String
    let items: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color)
                        .cornerRadius(8)
                }
            }
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
