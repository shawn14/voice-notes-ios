//
//  TuneConversationView.swift
//  voice notes
//
//  Card-by-card conversational flow for personalizing EEON.
//  Three steps: profile, purpose, knowledge base.
//  Voice-first (reuses AudioRecorder + TranscriptionService + HomeRecordingOverlay)
//  with a text fallback. Each step saves on Next with a forced compile so the user
//  can see the LLM-compiled directive before advancing.
//
//  Replaces IdentityView's form-based screen.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TuneConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Note> { $0.sourceTypeRaw == "profileSeed" })
    private var profileSeedNotes: [Note]

    @Query(filter: #Predicate<Note> { $0.sourceTypeRaw == "purposeSeed" })
    private var purposeSeedNotes: [Note]

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "reference" },
           sort: [SortDescriptor(\.lastMentionedAt, order: .reverse)])
    private var referenceArticles: [KnowledgeArticle]

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "purpose" })
    private var purposeArticles: [KnowledgeArticle]

    // MARK: - State

    enum Step: Int, CaseIterable { case profile = 0, purpose = 1, knowledge = 2 }

    @State private var step: Step = .profile
    @State private var profileText: String = ""
    @State private var purposeText: String = ""

    // Voice capture state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Save / compile state
    @State private var isSaving = false
    @State private var savedConfirmation: String?

    // Knowledge base state
    @State private var showAddReferenceDialog = false
    @State private var showURLInput = false
    @State private var pastedURL = ""
    @State private var isFetchingURL = false
    @State private var showFilePicker = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.eeonBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.2)

                ScrollView {
                    VStack(spacing: 28) {
                        stepBody
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }

                footerNav
            }
            .disabled(isRecording || isTranscribing)
            .blur(radius: (isRecording || isTranscribing) ? 3 : 0)

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
        .onAppear(perform: loadSeeds)
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Add reference material", isPresented: $showAddReferenceDialog, titleVisibility: .visible) {
            Button("Paste a link") { showURLInput = true }
            Button("Pick a file from your phone") { showFilePicker = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add canon (articles, books, domain expertise) for EEON to cite.")
        }
        .alert("Paste a link", isPresented: $showURLInput) {
            TextField("https://...", text: $pastedURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) { pastedURL = "" }
            Button("Add") {
                let trimmed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                pastedURL = ""
                guard !trimmed.isEmpty else { return }
                Task { await ingestReferenceURL(trimmed) }
            }
        } message: {
            Text("We'll fetch the page and add it to your knowledge base.")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await ingestReferenceFile(url: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    // MARK: - Header + Step Indicator

    private var header: some View {
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
            Text("Step \(step.rawValue + 1) of 3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.eeonTextSecondary)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Step Body

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .profile: profileStep
        case .purpose: purposeStep
        case .knowledge: knowledgeStep
        }
    }

    // MARK: - Step 1: Profile

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepPrompt(
                title: "Tell me about yourself.",
                subtitle: "Your role, what you're working on, links, who you are in a paragraph. Tap the mic and talk — no need to write."
            )

            bigMicButton

            orTypeField(text: $profileText, placeholder: "I'm …")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Step 2: Purpose

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepPrompt(
                title: "What should EEON be for you?",
                subtitle: "A founder, a coach, a dream interpreter, a researcher — tell me the lens you want EEON to use when it processes your notes."
            )

            bigMicButton

            orTypeField(text: $purposeText, placeholder: "I want EEON to …")

            if let compiled = compiledPurposePreview {
                compiledPreview(compiled)
            }
        }
        .padding(.horizontal, 20)
    }

    private var compiledPurposePreview: String? {
        guard let article = purposeArticles.first else { return nil }
        if let directive = article.thinkingEvolution, !directive.isEmpty { return directive }
        if !article.summary.isEmpty { return article.summary }
        return nil
    }

    private func compiledPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                Text("What EEON now understands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
            }
            Text(text)
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
    }

    // MARK: - Step 3: Knowledge Base

    private var knowledgeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepPrompt(
                title: "Share anything you want EEON to draw on.",
                subtitle: "Books, articles, domain expertise. EEON will cite these when they're relevant to your questions."
            )

            HStack(spacing: 12) {
                Button {
                    showAddReferenceDialog = true
                } label: {
                    Label("Add reference", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("EEONAccent"))
                        .cornerRadius(12)
                }
                .disabled(isFetchingURL)
            }

            if isFetchingURL {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Fetching link…")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
            }

            if !referenceArticles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.eeonTextSecondary)
                    ForEach(referenceArticles) { ref in
                        HStack(spacing: 10) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(.brown)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ref.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.eeonTextPrimary)
                                if !ref.summary.isEmpty {
                                    Text(ref.summary)
                                        .font(.caption)
                                        .foregroundStyle(.eeonTextSecondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text("\(ref.mentionCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.brown)
                        }
                        .padding(10)
                        .background(Color.eeonCard)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Shared Step Elements

    private func stepPrompt(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 8)
    }

    private func orTypeField(text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or type — you can edit what EEON heard here.")
                .font(.caption)
                .foregroundStyle(.eeonTextSecondary)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.eeonCard)
            .cornerRadius(10)
        }
    }

    // MARK: - Footer Navigation

    private var footerNav: some View {
        HStack(spacing: 12) {
            if step != .profile {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .profile
                    }
                } label: {
                    Text("Back")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.eeonTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.eeonCard)
                        .cornerRadius(12)
                }
            }

            Button {
                Task { await advanceFromCurrentStep() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    }
                    Text(step == .knowledge ? "Done" : "Next")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color("EEONAccent"))
                .cornerRadius(12)
                .opacity(nextButtonDisabled ? 0.5 : 1.0)
            }
            .disabled(nextButtonDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.eeonBackground)
    }

    private var nextButtonDisabled: Bool {
        if isSaving { return true }
        switch step {
        case .profile: return profileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .purpose: return purposeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .knowledge: return false  // Knowledge base is optional — always allow Done
        }
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

    // MARK: - Load Seeds

    private func loadSeeds() {
        profileText = profileSeedNotes.first?.content ?? ""
        purposeText = purposeSeedNotes.first?.content ?? ""
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
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
                appendTranscript(transcript)
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

    private func appendTranscript(_ transcript: String) {
        switch step {
        case .profile:
            profileText = profileText.isEmpty ? transcript : profileText + "\n\n" + transcript
        case .purpose:
            purposeText = purposeText.isEmpty ? transcript : purposeText + "\n\n" + transcript
        case .knowledge:
            break  // No voice input on knowledge step
        }
    }

    // MARK: - Save + Advance

    private func advanceFromCurrentStep() async {
        switch step {
        case .profile:
            await saveStep(
                sourceType: .profileSeed,
                title: "Your Profile",
                content: profileText,
                toast: "EEON learned that"
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { step = .purpose }
            }
        case .purpose:
            await saveStep(
                sourceType: .purposeSeed,
                title: "Your Purpose",
                content: purposeText,
                toast: "EEON is tuning itself to you"
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { step = .knowledge }
            }
        case .knowledge:
            await MainActor.run { dismiss() }
        }
    }

    /// Upsert the seed Note and trigger a forced compile so the user immediately sees
    /// the LLM-compiled directive in the preview (bypassing the 15-min cooldown).
    private func saveStep(sourceType: NoteSourceType, title: String, content: String, toast: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run { isSaving = true }

        upsertSeed(sourceType: sourceType, title: title, content: trimmed)

        await KnowledgeCompiler.shared.recompileDirtyArticles(context: modelContext, force: true)

        await MainActor.run {
            ContextAssembler.shared.refresh(from: modelContext)
            isSaving = false
            withAnimation(.easeInOut(duration: 0.3)) { savedConfirmation = toast }
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

    // MARK: - Reference Ingest

    private func ingestReferenceURL(_ urlString: String) async {
        let normalized = urlString.lowercased().hasPrefix("http") ? urlString : "https://\(urlString)"
        await MainActor.run { isFetchingURL = true }
        defer { Task { @MainActor in isFetchingURL = false } }

        do {
            let content = try await WebContentService.fetchArticle(from: normalized)
            await MainActor.run {
                let note = Note(title: content.title, content: content.text)
                note.sourceType = .document
                note.originalURL = normalized
                modelContext.insert(note)
                try? modelContext.save()

                Task {
                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: content.text,
                        projects: [],
                        tags: [],
                        context: modelContext
                    )
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't fetch that link: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func ingestReferenceFile(url: URL) async {
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let (title, text): (String, String)
            if isPDF {
                let extracted = try await PDFExtractionService.shared.extractText(from: url)
                title = extracted.title
                text = extracted.text
            } else {
                let data = try Data(contentsOf: url)
                title = url.deletingPathExtension().lastPathComponent
                text = String(data: data, encoding: .utf8) ?? ""
            }

            await MainActor.run {
                let note = Note(title: title, content: text)
                note.sourceType = .document
                modelContext.insert(note)
                try? modelContext.save()

                Task {
                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: text,
                        projects: [],
                        tags: [],
                        context: modelContext
                    )
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not import: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

#Preview {
    TuneConversationView()
        .modelContainer(for: [Note.self, KnowledgeArticle.self], inMemory: true)
}
