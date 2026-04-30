//
//  RewriteTemplatePickerSheet.swift
//  voice notes
//
//  Letterly-inspired rewrite template picker
//

import SwiftUI
import SwiftData

struct RewriteTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSelectTemplate: (RewriteTemplate) -> Void

    private let sections = RewriteTemplateSection.allCases

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !customTemplates.isEmpty {
                        customTemplatesSection
                    }

                    ForEach(sections) { section in
                        let templates = RewriteTemplateCatalog.templates(for: section)
                        if !templates.isEmpty {
                            templateSection(title: section.rawValue, templates: templates)
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            editorTarget = .create
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("New")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(10)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemBackground))
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    }
                    .accessibilityLabel("New custom template")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
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

    // MARK: - Sections

    private var customTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Templates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal)

            VStack(spacing: 2) {
                ForEach(customTemplates) { custom in
                    customTemplateRow(custom)
                }
            }
            .padding(.horizontal)
        }
    }

    private func templateSection(title: String, templates: [RewriteTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal)

            VStack(spacing: 2) {
                ForEach(templates) { template in
                    templateRow(template)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Rows

    private func customTemplateRow(_ custom: CustomRewriteTemplate) -> some View {
        Button {
            onSelectTemplate(custom.asRewriteTemplate)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(custom.emoji.isEmpty ? "✨" : custom.emoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Text(custom.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editorTarget = .edit(custom)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = custom
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func templateRow(_ template: RewriteTemplate) -> some View {
        Button {
            if template.isPro && !SubscriptionManager.shared.isSubscribed {
                onSelectTemplate(template)
            } else {
                onSelectTemplate(template)
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(template.emoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Text(template.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                if template.section == .favorites {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                } else if template.isPro {
                    Text("PRO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(6)
                } else {
                    Text("FREE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(10)
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

// MARK: - Preview

#Preview {
    RewriteTemplatePickerSheet { template in
        print("Selected: \(template.name)")
    }
    .modelContainer(for: CustomRewriteTemplate.self, inMemory: true)
}
