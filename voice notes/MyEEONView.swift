//
//  MyEEONView.swift
//  voice notes
//
//  Personal context prompt — tells EEON who you are
//

import SwiftUI

struct MyEEONView: View {
    @Environment(\.dismiss) private var dismiss
    private var authService = AuthService.shared

    @State private var text: String = ""
    @State private var hasChanges = false
    @State private var isGeneratingReports = false

    private let charGuide = 500
    private let placeholder = "Tell EEON about yourself — your role, what you're building, your priorities. This helps personalize your briefs, extractions, and assistant responses.\n\nExample: \"I'm a solo founder building a B2B SaaS for logistics. My team is me + 2 contractors. I'm focused on closing our first 10 customers and shipping v2 by end of Q1.\""

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .onChange(of: text) {
                            hasChanges = text != (authService.eeonContext ?? "")
                        }
                }
            } header: {
                Text("About You")
            } footer: {
                HStack {
                    Text("\(text.count) characters")
                        .foregroundStyle(text.count > charGuide ? .orange : .secondary)
                    Spacer()
                    Text("~\(charGuide) recommended")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Section {
                Text("This context is prepended to every AI call — note extraction, daily briefs, and assistant chat. Your report options will also update to match your role.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isGeneratingReports {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generating your reports...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("My EEON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndGenerateReports()
                }
                .disabled(!hasChanges || isGeneratingReports)
            }
        }
        .onAppear {
            text = authService.eeonContext ?? ""
        }
    }

    private func saveAndGenerateReports() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        authService.eeonContext = trimmed.isEmpty ? nil : trimmed
        hasChanges = false

        if trimmed.isEmpty {
            PersonalizedReportStore.clear()
            dismiss()
            return
        }

        // Generate personalized reports in background, then dismiss
        isGeneratingReports = true
        Task {
            do {
                _ = try await PersonalizedReportStore.generate()
            } catch {
                print("Failed to generate personalized reports: \(error)")
            }
            await MainActor.run {
                isGeneratingReports = false
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MyEEONView()
    }
}
