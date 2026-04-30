//
//  CustomRewriteTemplateEditorSheet.swift
//  voice notes
//
//  Sheet for creating or editing a user-authored rewrite template.
//

import SwiftUI
import SwiftData

struct CustomRewriteTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Existing template to edit, or nil for create.
    let editing: CustomRewriteTemplate?

    @State private var name: String = ""
    @State private var emoji: String = "✨"
    @State private var systemPrompt: String = ""
    @FocusState private var promptFocused: Bool

    private static let promptCharLimit = 2000

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedPrompt: String {
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedPrompt.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameAndEmojiSection
                    promptSection
                    examplesHint
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(editing == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let editing {
                name = editing.name
                emoji = editing.emoji.isEmpty ? "✨" : editing.emoji
                systemPrompt = editing.systemPrompt
            }
        }
    }

    // MARK: - Sections

    private var nameAndEmojiSection: some View {
        HStack(spacing: 12) {
            TextField("✨", text: $emoji)
                .font(.title2)
                .multilineTextAlignment(.center)
                .frame(width: 56, height: 56)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .onChange(of: emoji) { _, newValue in
                    // Keep only the last grapheme cluster
                    if let last = newValue.last, newValue.count > 1 {
                        emoji = String(last)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Tweet thread, exec summary, …", text: $name)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trimmedPrompt.count) / \(Self.promptCharLimit)")
                    .font(.caption2)
                    .foregroundStyle(trimmedPrompt.count > Self.promptCharLimit ? .red : .secondary)
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                if systemPrompt.isEmpty {
                    Text("Rewrite this voice note as …")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                }
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 220)
                    .focused($promptFocused)
                    .onChange(of: systemPrompt) { _, newValue in
                        if newValue.count > Self.promptCharLimit {
                            systemPrompt = String(newValue.prefix(Self.promptCharLimit))
                        }
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }

    private var examplesHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Tips")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("Write the prompt as an instruction to the AI. Example: \"Rewrite this voice note as a tweet thread of 5 tweets, each under 280 characters, with a hook in tweet 1.\"")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Actions

    private func save() {
        guard canSave else { return }
        let safeEmoji = emoji.isEmpty ? "✨" : emoji
        if let existing = editing {
            existing.name = trimmedName
            existing.emoji = safeEmoji
            existing.systemPrompt = trimmedPrompt
            existing.updatedAt = Date()
        } else {
            let nextOrder = nextSortOrder()
            let template = CustomRewriteTemplate(
                name: trimmedName,
                emoji: safeEmoji,
                systemPrompt: trimmedPrompt,
                sortOrder: nextOrder
            )
            modelContext.insert(template)
        }
        try? modelContext.save()
        dismiss()
    }

    /// Append new templates to the end of the list.
    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<CustomRewriteTemplate>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let highest = (try? modelContext.fetch(descriptor))?.first?.sortOrder ?? -1
        return highest + 1
    }
}

#Preview("Create") {
    CustomRewriteTemplateEditorSheet(editing: nil)
        .modelContainer(for: CustomRewriteTemplate.self, inMemory: true)
}
