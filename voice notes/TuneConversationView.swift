//
//  TuneConversationView.swift
//  voice notes
//
//  Personalization screen for EEON — two fields (profile, purpose).
//
//  Open behavior:
//    - First time (both empty): drops straight into the Profile editor
//    - Returning user: shows Review mode with both fields displayed + Edit per field
//
//  Editing:
//    - Big mic button → Whisper transcribe → appends to text field
//    - Save: persists as a seed Note, force-compiles the article, returns to Review
//    - Returning user sees "What EEON now understands" preview on the purpose field
//
//  Reference material lives in a separate KnowledgeBaseView (Settings).
//

import SwiftUI
import SwiftData

struct TuneConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Note> { $0.sourceTypeRaw == "profileSeed" })
    private var profileSeedNotes: [Note]

    @Query(filter: #Predicate<Note> { $0.sourceTypeRaw == "purposeSeed" })
    private var purposeSeedNotes: [Note]

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "purpose" })
    private var purposeArticles: [KnowledgeArticle]

    enum Field: Hashable { case profile, purpose }

    // MARK: - State

    @State private var editingField: Field?
    @State private var draftText: String = ""
    @State private var originalDraftText: String = ""

    // Voice capture
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Save state
    @State private var isSaving = false
    @State private var savedConfirmation: String?

    // MARK: - Derived

    private var profileText: String { profileSeedNotes.first?.content ?? "" }
    private var purposeText: String { purposeSeedNotes.first?.content ?? "" }

    private var compiledPurposeDirective: String? {
        guard let article = purposeArticles.first else { return nil }
        if let directive = article.thinkingEvolution, !directive.isEmpty { return directive }
        if !article.summary.isEmpty { return article.summary }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.eeonBackground.ignoresSafeArea()

            if let field = editingField {
                editorView(for: field)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                reviewView
                    .transition(.opacity)
            }

            if isRecording {
                HomeRecordingOverlay(
                    onStop: stopRecording,
                    onCancel: cancelRecording,
                    audioRecorder: audioRecorder
                )
            }
            if isTranscribing {
                HomeTranscribingOverlay()
            }

            if let confirmation = savedConfirmation {
                savedToast(text: confirmation)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: editingField)
        .onAppear {
            // First-time user: drop straight into profile editor.
            if profileText.isEmpty && purposeText.isEmpty {
                beginEditing(.profile)
            }
        }
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Review Mode

    private var reviewView: some View {
        VStack(spacing: 0) {
            reviewHeader

            ScrollView {
                VStack(spacing: 16) {
                    reviewCard(
                        icon: "person.crop.circle.fill",
                        iconColor: Color("EEONAccent"),
                        title: "About You",
                        emptyHint: "Tell EEON who you are so it can tailor every answer.",
                        content: profileText,
                        onEdit: { beginEditing(.profile) }
                    )

                    reviewCard(
                        icon: "scope",
                        iconColor: .indigo,
                        title: "What EEON Is For You",
                        emptyHint: "Your role, your methodology — what EEON should be for you.",
                        content: purposeText,
                        compiledDirective: compiledPurposeDirective,
                        onEdit: { beginEditing(.purpose) }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
    }

    private var reviewHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .frame(width: 32, height: 32)
            }
            Spacer()
            Text("Tune EEON")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func reviewCard(
        icon: String,
        iconColor: Color,
        title: String,
        emptyHint: String,
        content: String,
        compiledDirective: String? = nil,
        onEdit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(10)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
                Spacer()
                Button(action: onEdit) {
                    Text(content.isEmpty ? "Add" : "Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("EEONAccent"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color("EEONAccent").opacity(0.12))
                        .cornerRadius(10)
                }
            }

            if content.isEmpty {
                Text(emptyHint)
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.eeonTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let compiled = compiledDirective {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.indigo)
                            Text("What EEON now understands")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.eeonTextSecondary)
                        }
                        Text(compiled)
                            .font(.footnote)
                            .foregroundStyle(.eeonTextPrimary.opacity(0.9))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.indigo.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                                    )
                            )
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Editor Mode

    @ViewBuilder
    private func editorView(for field: Field) -> some View {
        VStack(spacing: 0) {
            editorHeader(for: field)

            ScrollView {
                VStack(spacing: 24) {
                    editorPrompt(for: field)

                    bigMicButton

                    orTypeField(placeholder: editorPlaceholder(for: field))

                    if field == .purpose, let compiled = compiledPurposeDirective {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.indigo)
                                Text("What EEON currently understands")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                            Text(compiled)
                                .font(.footnote)
                                .foregroundStyle(.eeonTextPrimary.opacity(0.9))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.indigo.opacity(0.08))
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }

            editorFooter(for: field)
        }
        .disabled(isRecording || isTranscribing)
        .blur(radius: (isRecording || isTranscribing) ? 3 : 0)
    }

    private func editorHeader(for field: Field) -> some View {
        HStack {
            Button {
                cancelEditing()
            } label: {
                Text("Cancel")
                    .font(.body)
                    .foregroundStyle(.eeonTextSecondary)
            }
            Spacer()
            Text(field == .profile ? "About You" : "What EEON Is For You")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            Spacer()
            Color.clear.frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func editorPrompt(for field: Field) -> some View {
        switch field {
        case .profile:
            VStack(alignment: .leading, spacing: 10) {
                Text("Tell me about yourself.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                Text("Your role, what you're working on, links, who you are in a paragraph. Tap the mic and talk — no need to write.")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .purpose:
            VStack(alignment: .leading, spacing: 10) {
                Text("What should EEON be for you?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                Text("A founder, a coach, a dream interpreter, a researcher — tell me the lens you want EEON to use when it processes your notes.")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func editorPlaceholder(for field: Field) -> String {
        switch field {
        case .profile: return "I'm …"
        case .purpose: return "I want EEON to …"
        }
    }

    private var bigMicButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(Color("EEONAccent").opacity(0.15))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(Color("EEONAccent"))
                    .frame(width: 100, height: 100)
                Image(systemName: "mic.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func orTypeField(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or type — you can edit what EEON heard here.")
                .font(.caption)
                .foregroundStyle(.eeonTextSecondary)

            ZStack(alignment: .topLeading) {
                if draftText.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                TextEditor(text: $draftText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.eeonCard)
            .cornerRadius(10)
        }
    }

    private func editorFooter(for field: Field) -> some View {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !trimmed.isEmpty && !isSaving
        let hasChanged = trimmed != originalDraftText.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            Task { await saveEdit(field: field) }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white).scaleEffect(0.9)
                }
                Text(hasChanged ? "Save" : "Done")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color("EEONAccent"))
            .cornerRadius(12)
            .opacity(canSave ? 1.0 : 0.5)
        }
        .disabled(!canSave)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.eeonBackground)
    }

    // MARK: - Saved Toast

    private func savedToast(text: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.eeonCard)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Editing Lifecycle

    private func beginEditing(_ field: Field) {
        switch field {
        case .profile: draftText = profileText
        case .purpose: draftText = purposeText
        }
        originalDraftText = draftText
        editingField = field
    }

    private func cancelEditing() {
        editingField = nil
        draftText = ""
        originalDraftText = ""
    }

    private func saveEdit(field: Field) async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = originalDraftText.trimmingCharacters(in: .whitespacesAndNewlines)

        // No changes — just dismiss the editor
        if trimmed == original {
            await MainActor.run { cancelEditing() }
            return
        }

        guard !trimmed.isEmpty else {
            await MainActor.run { cancelEditing() }
            return
        }

        let sourceType: NoteSourceType = (field == .profile) ? .profileSeed : .purposeSeed
        let title = (field == .profile) ? "Your Profile" : "Your Purpose"
        let toast = (field == .profile) ? "EEON learned that" : "EEON is tuning itself to you"

        await MainActor.run { isSaving = true }

        upsertSeed(sourceType: sourceType, title: title, content: trimmed)
        await KnowledgeCompiler.shared.recompileDirtyArticles(context: modelContext, force: true)

        await MainActor.run {
            ContextAssembler.shared.refresh(from: modelContext)
            isSaving = false
            withAnimation(.easeInOut(duration: 0.3)) { savedConfirmation = toast }
            cancelEditing()
        }

        try? await Task.sleep(for: .milliseconds(1400))
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) { savedConfirmation = nil }
        }
    }

    private func upsertSeed(sourceType: NoteSourceType, title: String, content: String) {
        let existingSeeds: [Note]
        switch sourceType {
        case .profileSeed: existingSeeds = profileSeedNotes
        case .purposeSeed: existingSeeds = purposeSeedNotes
        default: existingSeeds = []
        }

        if let existing = existingSeeds.first {
            existing.content = content
            existing.title = title
            existing.updatedAt = Date()
            try? modelContext.save()
            KnowledgeCompiler.shared.markAffectedArticles(note: existing, context: modelContext)
        } else {
            let seed = Note(title: title, content: content)
            seed.sourceType = sourceType
            modelContext.insert(seed)
            try? modelContext.save()
            KnowledgeCompiler.shared.markAffectedArticles(note: seed, context: modelContext)
        }

        let keptId = existingSeeds.first?.id ?? UUID()
        KnowledgeCompiler.replacePriorSeeds(for: sourceType, keeping: keptId, in: modelContext)
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                errorMessage = "Microphone permission is required to record."
                showingError = true
                return
            }
            do {
                currentAudioFileName = try audioRecorder.startRecording()
                await MainActor.run { isRecording = true }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording."
            showingError = true
            isRecording = false
            return
        }
        isRecording = false
        isTranscribing = true
        Task { await transcribeAndAppend(url: url) }
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        isRecording = false
        currentAudioFileName = nil
    }

    private func transcribeAndAppend(url: URL) async {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "OpenAI API key is not configured."
                showingError = true
                isTranscribing = false
            }
            return
        }
        let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
        do {
            let transcript = try await service.transcribe(audioURL: url)
            await MainActor.run {
                draftText = draftText.isEmpty ? transcript : draftText + "\n\n" + transcript
                isTranscribing = false
            }
            if let fileName = currentAudioFileName {
                audioRecorder.deleteRecording(fileName: fileName)
                await MainActor.run { currentAudioFileName = nil }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showingError = true
                isTranscribing = false
            }
        }
    }
}

#Preview {
    TuneConversationView()
        .modelContainer(for: [Note.self, KnowledgeArticle.self], inMemory: true)
}
