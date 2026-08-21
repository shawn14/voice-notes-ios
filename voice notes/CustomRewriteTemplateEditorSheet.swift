//
//  CustomRewriteTemplateEditorSheet.swift
//  voice notes
//
//  Structured template builder (2026-08-20): a template is a name, overall
//  instructions (goal, tone, style), and an ordered list of sections — each
//  with a heading and its own extraction instructions. Structure beats a raw
//  prompt box: users describe the shape they want instead of writing prompt
//  engineering, and the compiled prompt is generated for them.
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
    @State private var globalInstructions: String = ""
    @State private var sections: [TemplateSection] = []

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usableSections: [TemplateSection] {
        sections.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A template needs a name and something to say — either overall
    /// instructions or at least one real section.
    private var canSave: Bool {
        !trimmedName.isEmpty
            && (!globalInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !usableSections.isEmpty)
    }

    var body: some View {
        NavigationStack {
            List {
                identitySection
                instructionsSection
                sectionsSection
            }
            .navigationTitle(editing == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: - Sections of the form

    private var identitySection: some View {
        Section {
            // Emoji picker removed 2026-08-21 — custom templates render with
            // the same SF Symbol as everything else, so asking for an emoji
            // collected input that was never displayed.
            TextField("Client call notes, lecture notes, …", text: $name)
                .font(.body)
        } header: {
            Text("Name")
        }
    }

    private var instructionsSection: some View {
        Section {
            TextEditor(text: $globalInstructions)
                .frame(minHeight: 90)
                .font(.body)
        } header: {
            Text("Overall instructions")
        } footer: {
            Text("The goal, voice, and style for this format — for example: keep it factual and terse, write for someone who missed the meeting, never drop names or numbers.")
        }
    }

    private var sectionsSection: some View {
        Section {
            ForEach($sections) { $section in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Section heading", text: $section.title)
                        .font(.body.weight(.semibold))
                    TextField("What goes under this heading", text: $section.instructions, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                }
                .padding(.vertical, 4)
            }
            .onDelete { sections.remove(atOffsets: $0) }
            .onMove { sections.move(fromOffsets: $0, toOffset: $1) }

            Button {
                withAnimation { sections.append(TemplateSection()) }
            } label: {
                Label("Add section", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            HStack {
                Text("Sections")
                Spacer()
                if !sections.isEmpty {
                    EditButton()
                        .font(.caption)
                }
            }
        } footer: {
            Text("Three to six focused sections works best. Each becomes a labelled block in every note using this format.")
        }
    }

    // MARK: - Load / save

    private func loadExisting() {
        guard let editing, name.isEmpty else { return }
        name = editing.name
        emoji = editing.emoji
        globalInstructions = editing.globalInstructions
        sections = editing.sections

        // A template authored before the structured builder has only a raw
        // prompt — carry it into the instructions box so nothing is lost.
        if globalInstructions.isEmpty && sections.isEmpty {
            globalInstructions = editing.systemPrompt
        }
    }

    private func save() {
        let compiled = CustomRewriteTemplate.compilePrompt(
            globalInstructions: globalInstructions,
            sections: usableSections
        )

        if let editing {
            editing.name = trimmedName
            editing.emoji = emoji.isEmpty ? "✨" : emoji
            editing.globalInstructions = globalInstructions
            editing.sections = usableSections
            editing.systemPrompt = compiled
            editing.updatedAt = Date()
        } else {
            let template = CustomRewriteTemplate(
                name: trimmedName,
                emoji: emoji.isEmpty ? "✨" : emoji,
                systemPrompt: compiled
            )
            template.globalInstructions = globalInstructions
            template.sections = usableSections
            modelContext.insert(template)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CustomRewriteTemplateEditorSheet(editing: nil)
}
