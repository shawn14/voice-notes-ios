//
//  RewriteTemplatePickerSheet.swift
//  voice notes
//
//  "More formats…" — the full catalog of rewrite templates plus the user's
//  own. Restyled 2026-08-26 to the app's settings language: an inset-grouped
//  list, the one settings-row component, a blue "Pro" tag instead of the old
//  purple gradient, no duplicated Favorites block, and a plain "Formats" title.
//

import SwiftUI
import SwiftData

struct RewriteTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSelectTemplate: (RewriteTemplate) -> Void

    /// Favorites duplicated "Enhance" from General; the catalog order is the
    /// order people read: general, editing, summary, content.
    private let sections: [RewriteTemplateSection] = [.general, .textEditing, .summary, .contentCreation]

    @Query(sort: [SortDescriptor(\CustomRewriteTemplate.sortOrder, order: .forward)])
    private var customTemplates: [CustomRewriteTemplate]

    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: CustomRewriteTemplate?

    enum EditorTarget: Identifiable {
        case create
        case edit(CustomRewriteTemplate)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let t): return t.id.uuidString
            }
        }
    }

    private var isPro: Bool { SubscriptionManager.shared.isSubscribed }

    var body: some View {
        NavigationStack {
            List {
                if !customTemplates.isEmpty {
                    Section("Your templates") {
                        ForEach(customTemplates) { custom in
                            customTemplateRow(custom)
                        }
                    }
                }

                ForEach(sections) { section in
                    let templates = RewriteTemplateCatalog.templates(for: section)
                    if !templates.isEmpty {
                        Section(section.rawValue) {
                            ForEach(templates) { template in
                                templateRow(template)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        editorTarget = .create
                    } label: {
                        EEONSettingsRow(icon: "plus", title: "New template", subtitle: "Name it, describe the sections, use it anywhere") {
                            EEONChevron()
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Pro formats and your own templates need EEON Pro. Enhance is always free.")
                        .font(EEONType.meta)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Formats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New template")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $editorTarget) { target in
            switch target {
            case .create:
                CustomRewriteTemplateEditorSheet(editing: nil)
            case .edit(let template):
                CustomRewriteTemplateEditorSheet(editing: template)
            }
        }
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { template in
            Button("Delete \"\(template.name)\"", role: .destructive) {
                deleteTemplate(template)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Rows

    private func customTemplateRow(_ custom: CustomRewriteTemplate) -> some View {
        Button {
            onSelectTemplate(custom.asRewriteTemplate)
            dismiss()
        } label: {
            EEONSettingsRow(icon: "wand.and.stars", title: custom.name) {
                if !isPro { ProTag() }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingDelete = custom } label: { Label("Delete", systemImage: "trash") }
            Button { editorTarget = .edit(custom) } label: { Label("Edit", systemImage: "pencil") }
                .tint(Color.eeonAccent)
        }
        .contextMenu {
            Button { editorTarget = .edit(custom) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { pendingDelete = custom } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func templateRow(_ template: RewriteTemplate) -> some View {
        Button {
            onSelectTemplate(template)
            dismiss()
        } label: {
            EEONSettingsRow(icon: template.icon, title: template.name) {
                if template.isPro && !isPro { ProTag() }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func deleteTemplate(_ template: CustomRewriteTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
        pendingDelete = nil
    }
}

/// The one Pro marker: accent-tinted capsule, no gradient. Shown only to
/// people who aren't subscribed — a subscriber never needs the reminder.
private struct ProTag: View {
    var body: some View {
        Text("Pro")
            .font(EEONType.badge)
            .foregroundStyle(Color.eeonAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.eeonAccent.opacity(0.12)))
    }
}

// MARK: - Preview

#Preview {
    RewriteTemplatePickerSheet { template in
        print("Selected: \(template.name)")
    }
    .modelContainer(for: CustomRewriteTemplate.self, inMemory: true)
}
