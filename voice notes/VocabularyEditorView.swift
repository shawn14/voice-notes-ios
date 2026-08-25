//
//  VocabularyEditorView.swift
//  voice notes
//
//  Settings → Capture → "Words EEON should know". One term per line. What the
//  user types is sent to Whisper on every transcription, ahead of the names
//  and projects EEON has learned on its own (shown read-only below so the user
//  can see what is already covered before typing it again).
//

import SwiftUI

struct VocabularyEditorView: View {
    @State private var text: String = TranscriptionVocabulary.shared.customTerms.joined(separator: "\n")
    @State private var learned: [String] = TranscriptionVocabulary.shared.learnedTerms
    @FocusState private var editorFocused: Bool

    var body: some View {
        List {
            Section {
                TextEditor(text: $text)
                    .font(EEONType.body)
                    .frame(minHeight: 140)
                    .focused($editorFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Lena Ortiz\nStockAlarm\nCaddie Tap")
                                .font(EEONType.body)
                                .foregroundStyle(.eeonTextTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Your words")
            } footer: {
                Text("Names, products, jargon — one per line. Whisper spells these correctly when it hears them.")
                    .font(EEONType.meta)
            }

            Section {
                if learned.isEmpty {
                    Text("Nothing yet. People and projects show up here as EEON extracts them from your notes.")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                } else {
                    Text(learned.joined(separator: " · "))
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                }
            } header: {
                Text("Learned from your notes")
            } footer: {
                Text("Included automatically. Up to \(TranscriptionVocabulary.maxLearnedPeople) people and \(TranscriptionVocabulary.maxLearnedProjects) projects, most-mentioned first.")
                    .font(EEONType.meta)
            }
        }
        .navigationTitle("Words EEON should know")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, newValue in
            TranscriptionVocabulary.shared.customTerms = TranscriptionVocabulary.parseTerms(newValue)
        }
        .onAppear { editorFocused = text.isEmpty }
    }
}

#Preview {
    NavigationStack { VocabularyEditorView() }
}
