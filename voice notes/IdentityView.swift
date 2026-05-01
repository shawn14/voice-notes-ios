//
//  IdentityView.swift
//  voice notes
//
//  "Tune EEON" settings screen — lets the user shape the app by editing their:
//    1. Profile seed  → compiled into a .self KnowledgeArticle (bio, LinkedIn, links)
//    2. Purpose seed  → compiled into a .purpose KnowledgeArticle (role + how EEON should serve them)
//    3. Knowledge base → list of .reference articles + upload entry
//
//  Seeds flow through the existing KnowledgeCompiler. ContextAssembler injects the
//  compiled results into every AI call site.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct IdentityView: View {
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

    @State private var profileText: String = ""
    @State private var purposeText: String = ""
    @State private var hasProfileChanges = false
    @State private var hasPurposeChanges = false
    @State private var isRecompiling = false
    @State private var showFilePicker = false
    @State private var showAddReferenceDialog = false
    @State private var showURLInput = false
    @State private var pastedURL = ""
    @State private var isFetchingURL = false
    @State private var importError: String?
    @State private var isRegeneratingSchema = false
    @State private var showReextractConfirm = false
    @State private var pendingReextractCount: Int = 0
    @State private var pendingReextractCostCents: Int = 0
    @State private var isReextracting = false
    @State private var reextractProgress: (current: Int, total: Int) = (0, 0)
    @State private var lastReextractMessage: String?

    private static let reextractWindowDays: Int = 30
    /// Token-cost estimate per note for persona extraction (rough: gpt-4o-mini at ~$0.0001/note).
    /// Used only for the confirmation dialog — not authoritative billing.
    private static let reextractEstimatedCentsPerNote: Double = 0.1

    private let profileCharGuide = 800
    private let purposeCharGuide = 400

    private var profilePlaceholder: String {
        "I'm a [role] working on [what you're building]. My focus is [current priorities]. You can find my work at [links, LinkedIn, GitHub, website]."
    }

    private var purposePlaceholder: String {
        // When the onboarding quiz starts persisting `UserRole`, a future revision can
        // pre-seed this from that selection. For now, a neutral founder example.
        "I'm a founder — help me prioritize projects, rank them by execution readiness, and flag decisions that unblock work."
    }

    private var compiledPurposePreview: String? {
        guard let article = purposeArticles.first else { return nil }
        if let directive = article.thinkingEvolution, !directive.isEmpty { return directive }
        if !article.summary.isEmpty { return article.summary }
        return nil
    }

    var body: some View {
        Form {
            profileSection
            purposeSection
            extractionLensSection
            knowledgeBaseSection
            footerSection
        }
        .navigationTitle("Tune EEON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveAll() }
                    .disabled(!hasProfileChanges && !hasPurposeChanges)
            }
        }
        .onAppear { loadSeeds() }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
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
            Button("Cancel", role: .cancel) {
                pastedURL = ""
            }
            Button("Add") {
                let trimmed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                pastedURL = ""
                guard !trimmed.isEmpty else { return }
                Task { await ingestReferenceURL(trimmed) }
            }
        } message: {
            Text("We'll fetch the page and add it to your knowledge base.")
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
        .alert("Re-extract recent notes?", isPresented: $showReextractConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Re-extract") { runReextraction() }
        } message: {
            Text(reextractConfirmMessage)
        }
    }

    private var reextractConfirmMessage: String {
        if pendingReextractCount == 0 {
            return "No notes from the last \(Self.reextractWindowDays) days to re-extract."
        }
        let cents = Double(pendingReextractCount) * Self.reextractEstimatedCentsPerNote
        let costStr = cents < 1 ? String(format: "less than 1¢") : String(format: "≈%.0f¢", cents)
        return "Re-extract \(pendingReextractCount) note\(pendingReextractCount == 1 ? "" : "s") from the last \(Self.reextractWindowDays) days through your current lens. Estimated cost: \(costStr). Existing chips on each note are kept if the new pass returns nothing."
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if profileText.isEmpty {
                    Text(profilePlaceholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                }
                TextEditor(text: $profileText)
                    .font(.body)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .onChange(of: profileText) { _, newValue in
                        hasProfileChanges = newValue != (profileSeedNotes.first?.content ?? "")
                    }
            }
        } header: {
            Text("Your Profile")
        } footer: {
            HStack {
                Text("\(profileText.count) chars")
                    .foregroundStyle(profileText.count > profileCharGuide ? .orange : .secondary)
                Spacer()
                Text("Bio, links, LinkedIn — compiled into an evolving profile.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var purposeSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if purposeText.isEmpty {
                    Text(purposePlaceholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                }
                TextEditor(text: $purposeText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .onChange(of: purposeText) { _, newValue in
                        hasPurposeChanges = newValue != (purposeSeedNotes.first?.content ?? "")
                    }
            }

            if let compiled = compiledPurposePreview {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                        Text("What EEON has internalized")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(compiled)
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(10)
                        .background(Color.indigo.opacity(0.08))
                        .cornerRadius(8)
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("What EEON Is For You")
        } footer: {
            HStack {
                Text("\(purposeText.count) chars")
                    .foregroundStyle(purposeText.count > purposeCharGuide ? .orange : .secondary)
                Spacer()
                Text("Your role. Auto-refines from usage.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var extractionLensSection: some View {
        Section {
            if let schema = purposeArticles.first?.noteExtractionSchema, !schema.categories.isEmpty {
                ForEach(schema.categories) { category in
                    HStack(spacing: 10) {
                        Image(systemName: category.icon)
                            .foregroundStyle(.eeonAccent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label)
                                .font(.subheadline.weight(.medium))
                            Text(category.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !schema.extractionPromptFragment.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How I'll read your notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(schema.extractionPromptFragment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    regeneratePurposeSchema()
                } label: {
                    Label(isRegeneratingSchema ? "Regenerating..." : "Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.eeonAccent)
                }
                .disabled(isRegeneratingSchema || isReextracting)

                Button {
                    prepareReextract()
                } label: {
                    if isReextracting {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Re-extracting \(reextractProgress.current) of \(reextractProgress.total)…")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Label("Re-extract last \(Self.reextractWindowDays) days", systemImage: "arrow.counterclockwise.circle")
                            .foregroundStyle(.eeonAccent)
                    }
                }
                .disabled(isRegeneratingSchema || isReextracting)

                if let message = lastReextractMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.eeonAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not yet tuned")
                            .font(.subheadline)
                        Text("Save your purpose above and EEON will compile a personalized lens for your notes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if purposeArticles.first != nil {
                    Button {
                        regeneratePurposeSchema()
                    } label: {
                        Label(isRegeneratingSchema ? "Generating..." : "Generate now", systemImage: "sparkles")
                            .foregroundStyle(.eeonAccent)
                    }
                    .disabled(isRegeneratingSchema)
                }
            }
        } header: {
            Text("How EEON sees your notes")
        } footer: {
            Text("Your tuned lens. EEON adds these chips to every note alongside the standard ones — never replacing them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var knowledgeBaseSection: some View {
        Section {
            if referenceArticles.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(.brown)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No reference material yet")
                            .font(.subheadline)
                        Text("Import PDFs or articles to give EEON canon to draw from.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(referenceArticles) { article in
                    HStack(spacing: 10) {
                        Image(systemName: article.articleType.icon)
                            .foregroundStyle(.brown)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.name)
                                .font(.subheadline.weight(.medium))
                            if !article.summary.isEmpty {
                                Text(article.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(article.mentionCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                showAddReferenceDialog = true
            } label: {
                Label("Add reference material", systemImage: "plus.circle.fill")
                    .foregroundStyle(.brown)
            }
            .disabled(isFetchingURL)

            if isFetchingURL {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Fetching link...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Knowledge Base")
        } footer: {
            Text("Uploaded canon (books, essays, domain expertise). EEON cites these when answering related questions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerSection: some View {
        Section {
            if isRecompiling {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Recompiling your EEON...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Your profile and purpose are injected into every AI call — extractions, answers, daily briefs. As you capture voice notes, EEON refines both automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func prepareReextract() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.reextractWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.sourceTypeRaw != "profileSeed"
                && note.sourceTypeRaw != "purposeSeed"
                && note.createdAt >= cutoff
            }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        pendingReextractCount = notes.count
        showReextractConfirm = true
    }

    private func runReextraction() {
        guard let purpose = purposeArticles.first,
              let schemaJSON = purpose.noteExtractionSchemaJSON,
              !schemaJSON.isEmpty,
              let apiKey = APIKeys.openAI,
              !apiKey.isEmpty else {
            lastReextractMessage = "Tune your purpose first."
            return
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.reextractWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.sourceTypeRaw != "profileSeed"
                && note.sourceTypeRaw != "purposeSeed"
                && note.createdAt >= cutoff
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        guard !notes.isEmpty else {
            lastReextractMessage = "Nothing to re-extract in the window."
            return
        }

        isReextracting = true
        lastReextractMessage = nil
        reextractProgress = (0, notes.count)

        // Snapshot the persistent IDs + transcripts upfront so the async loop doesn't
        // race against the live SwiftData query (which can shuffle as we mutate).
        let payloads: [(noteId: PersistentIdentifier, transcript: String)] = notes.compactMap { note in
            let text = note.enhancedNoteText ?? note.transcript ?? note.content
            guard !text.isEmpty else { return nil }
            return (note.persistentModelID, text)
        }

        Task {
            var updated = 0
            for (idx, payload) in payloads.enumerated() {
                let items = await SummaryService.extractPersonaItems(
                    text: payload.transcript,
                    schemaJSON: schemaJSON,
                    apiKey: apiKey
                )

                await MainActor.run {
                    reextractProgress = (idx + 1, payloads.count)
                    if !items.isEmpty,
                       let note = modelContext.model(for: payload.noteId) as? Note {
                        note.personaExtractions = items
                        note.updatedAt = Date()
                        updated += 1
                    }
                }
            }

            await MainActor.run {
                try? modelContext.save()
                isReextracting = false
                lastReextractMessage = "Re-extracted \(updated) of \(payloads.count) note\(payloads.count == 1 ? "" : "s")."
            }
        }
    }

    private func regeneratePurposeSchema() {
        guard let purpose = purposeArticles.first, !isRegeneratingSchema else { return }
        isRegeneratingSchema = true

        purpose.isDirty = true
        purpose.updatedAt = Date()
        try? modelContext.save()

        Task {
            await KnowledgeCompiler.shared.recompileDirtyArticles(context: modelContext, force: true)
            await MainActor.run { isRegeneratingSchema = false }
        }
    }

    private func loadSeeds() {
        profileText = profileSeedNotes.first?.content ?? ""
        purposeText = purposeSeedNotes.first?.content ?? ""
        hasProfileChanges = false
        hasPurposeChanges = false
    }

    private func saveAll() {
        let trimmedProfile = profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purposeText.trimmingCharacters(in: .whitespacesAndNewlines)

        if hasProfileChanges {
            upsertSeed(sourceType: .profileSeed, title: "Your Profile", content: trimmedProfile)
        }
        if hasPurposeChanges {
            upsertSeed(sourceType: .purposeSeed, title: "Your Purpose", content: trimmedPurpose)
        }

        hasProfileChanges = false
        hasPurposeChanges = false

        // Kick off recompile so the .self / .purpose articles update now, not on next foreground
        isRecompiling = true
        Task {
            await KnowledgeCompiler.shared.recompileDirtyArticles(context: modelContext)
            await MainActor.run {
                isRecompiling = false
                ContextAssembler.shared.refresh(from: modelContext)
                dismiss()
            }
        }
    }

    private func upsertSeed(sourceType: NoteSourceType, title: String, content: String) {
        let existingSeeds: [Note]
        switch sourceType {
        case .profileSeed: existingSeeds = profileSeedNotes
        case .purposeSeed: existingSeeds = purposeSeedNotes
        default: existingSeeds = []
        }

        if content.isEmpty {
            // User cleared the seed — delete existing
            for seed in existingSeeds { modelContext.delete(seed) }
            try? modelContext.save()
            return
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

        // Clean up any duplicate seeds of this type (defensive — shouldn't happen, but keeps DB tidy)
        let keptId = existingSeeds.first?.id ?? UUID()
        KnowledgeCompiler.replacePriorSeeds(for: sourceType, keeping: keptId, in: modelContext)
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await ingestReferenceFile(url: url)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// Fetch a URL via WebContentService (same pipeline used for share-extension web ingests),
    /// create a Note with sourceType .document (so markAffectedArticles routes it to .reference),
    /// and run it through the extraction pipeline.
    private func ingestReferenceURL(_ urlString: String) async {
        let normalized: String = {
            if urlString.lowercased().hasPrefix("http") { return urlString }
            return "https://\(urlString)"
        }()

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
                importError = "Couldn't fetch that link: \(error.localizedDescription)"
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

                // Run through the intelligence pipeline — extraction will mark dirty articles,
                // and because sourceType is .document, topics become .reference articles.
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
                importError = "Could not import: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        IdentityView()
    }
    .modelContainer(for: [Note.self, KnowledgeArticle.self], inMemory: true)
}
