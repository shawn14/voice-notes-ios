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
                Text("This context is prepended to every AI call — note extraction, daily briefs, and assistant chat. Write in natural language about who you are and what matters to you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("My EEON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    authService.eeonContext = trimmed.isEmpty ? nil : trimmed
                    hasChanges = false
                    dismiss()
                }
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            text = authService.eeonContext ?? ""
        }
    }
}

#Preview {
    NavigationStack {
        MyEEONView()
    }
}
