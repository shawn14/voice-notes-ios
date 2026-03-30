//
//  RewriteTemplatePickerSheet.swift
//  voice notes
//
//  Letterly-inspired rewrite template picker
//

import SwiftUI

struct RewriteTemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelectTemplate: (RewriteTemplate) -> Void

    private let sections = RewriteTemplateSection.allCases

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections) { section in
                        let templates = RewriteTemplateCatalog.templates(for: section)
                        if !templates.isEmpty {
                            templateSection(title: section.rawValue, templates: templates)
                        }
                    }

                    // Bottom actions
                    HStack(spacing: 16) {
                        // + New custom template (disabled for now)
                        Button {
                            // Future: custom template creation
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("New")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                        }
                        .disabled(true)
                        .opacity(0.5)

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
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section View

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

    // MARK: - Template Row

    private func templateRow(_ template: RewriteTemplate) -> some View {
        Button {
            if template.isPro && !SubscriptionManager.shared.isSubscribed {
                // Will be handled by caller — pass template anyway so caller can show paywall
                onSelectTemplate(template)
            } else {
                onSelectTemplate(template)
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                // Emoji icon
                Text(template.emoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // Template name
                Text(template.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                // Favorite star for favorites section, PRO badge otherwise
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
}

// MARK: - Preview

#Preview {
    RewriteTemplatePickerSheet { template in
        print("Selected: \(template.name)")
    }
}
