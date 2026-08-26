//
//  NoteDetailView.swift
//  voice notes
//
//  Simplified note detail view - clean Letterly-inspired design
//

import SwiftUI
import StoreKit
import SwiftData
import AVFoundation
import PhotosUI
import LinkPresentation

enum NoteTab: String, CaseIterable {
    case insights = "Insights"
    case transcript = "Transcript"
    case transform = "Transform"
}

// MARK: - AI Transform Types

// Professional transform set (2026-08-19, Shawn): summaries and
// profession-shaped notes — school, clinical, legal, meetings — instead of
// social-media output. Old saved outputs with retired type names ("Tweet",
// "PRD", "CEO Report") still render; they just lose their header label.
enum AITransformType: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case executiveSummary = "Executive Summary"
    case schoolNotes = "School Notes"
    case clinicalNote = "Clinical Note"
    case caseNote = "Case Note"
    case meetingSummary = "Meeting Minutes"
    case custom = "Custom..."

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .executiveSummary: return "briefcase"
        case .schoolNotes: return "graduationcap"
        case .clinicalNote: return "stethoscope"
        case .caseNote: return "building.columns"
        case .meetingSummary: return "person.3"
        case .custom: return "wand.and.stars"
        }
    }

    var prompt: String {
        switch self {
        case .summary:
            return "Summarize this voice note in 2-3 concise sentences, capturing the key points."
        case .executiveSummary:
            return "Create a brief executive summary of this voice note. Include: key points, decisions made, and action items. Format with bullet points."
        case .schoolNotes:
            return "Transform this into clear study notes. Include: topic headings, key concepts with short definitions, important facts and examples, and 2-3 review questions at the end. Keep every fact from the original — organize, don't drop."
        case .clinicalNote:
            return "Structure this dictation as a clinical note. Include: Subjective (what was reported), Objective (findings or observations mentioned), Assessment, and Plan. Preserve all clinical details, names, dosages, and figures exactly as stated. Never invent findings that were not dictated."
        case .caseNote:
            return "Structure this as a legal case note. Include: Matter/Parties, Key Facts, Issues, Analysis or Positions discussed, and Action Items with any deadlines. Preserve names, dates, citations, and figures exactly as stated."
        case .meetingSummary:
            return "Format this as meeting minutes. Include: Attendees (if mentioned), Discussion Points, Decisions Made, Action Items with owners, and Next Steps."
        case .custom:
            return "" // User provides custom prompt
        }
    }
}

struct NoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.requestReview) private var requestReview

    @Bindable var note: Note
    var initialTab: NoteTab = .insights
    var autoTransform: AITransformType? = nil

    @Query private var allProjects: [Project]
    @Query private var allDecisions: [ExtractedDecision]
    @Query private var allActions: [ExtractedAction]
    @Query private var allExtractedURLs: [ExtractedURL]
    @Query private var allCommitments: [ExtractedCommitment]

    @State private var audioRecorder = AudioRecorder()
    @State private var showingDeleteConfirm = false
    @State private var showingShareSheet = false
    @State private var showingTextShareSheet = false
    @State private var showingProjectPicker = false
    @State private var isGeneratingSummary = false

    // AI Transform state
    @State private var showingAIMenu = false
    @State private var showingCustomPrompt = false
    @State private var customPromptText = ""
    @State private var isGeneratingAI = false
    @State private var aiError: String?
    @State private var showingOriginal = false

    // Image attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var selectedImageForFullscreen: String?
    @State private var showingFullscreenImage = false
    @State private var showingBottomPhotoPicker = false

    // Transcript collapsed state
    @State private var showingTranscript = false

    // Extraction collapsed state
    @State private var showingExtractions = false

    // Tag picker
    @State private var showingTagPicker = false

    // Navigation to AnswerSheet with pre-filled query
    @State private var assistantQuery: String?
    @State private var showingAssistant = false

    // Rewrite sheet state
    @State private var showingRewriteSheet = false
    @State private var showingQuiz = false
    @State private var isGeneratingQuiz = false
    @State private var quizError: String?
    @State private var isRewriting = false
    @State private var rewriteError: String?
    /// The text an adjustment replaced — one level of undo (tap again to redo).
    @State private var adjustmentUndoText: String?

    // Enhanced-text inline edit + re-run state
    @State private var isEditingEnhanced = false
    @State private var enhancedDraft = ""
    @State private var isReprocessing = false
    @State private var reprocessError: String?

    // Tag assignment sheet state
    @State private var showingTagSheet = false

    // Copy feedback
    @State private var showCopiedFeedback = false

    // Paywall for PRO rewrite templates
    @State private var showingPaywall = false

    init(note: Note, initialTab: NoteTab = .insights, autoTransform: AITransformType? = nil) {
        self.note = note
        self.initialTab = initialTab
        self.autoTransform = autoTransform
    }

    /// Formatted text for sharing via system share sheet
    private var shareableText: String {
        var parts: [String] = []
        if !note.title.isEmpty {
            parts.append(note.title)
        }
        let body = note.enhancedNoteText ?? note.transcript ?? note.content
        if !body.isEmpty {
            parts.append(body)
        }
        parts.append("Shared from EEON")
        return parts.joined(separator: "\n\n")
    }

    // Computed summary from transcript
    private var summary: String {
        var parts: [String] = []

        if let subject = note.extractedSubject {
            parts.append(subject.topic)
            if let action = subject.action, !action.isEmpty {
                parts.append(action)
            }
        }

        if let nextStep = note.suggestedNextStep, !nextStep.isEmpty {
            parts.append("Next: \(nextStep)")
        }

        if parts.isEmpty {
            let text = !note.content.isEmpty ? note.content : (note.transcript ?? "")
            return text.isEmpty ? "No summary available" : text
        }

        return parts.joined(separator: ". ")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color.eeonBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. Audio pill + date line (+ calendar context when present)
                        VStack(alignment: .leading, spacing: 8) {
                            audioPillAndDateRow
                            calendarContextRow
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                        // 2. Title + favorite
                        titleRow
                            .padding(.bottom, 24)

                        // 3. Enhanced / Original toggle
                        if note.enhancedNoteText != nil && !(note.enhancedNoteText?.isEmpty ?? true),
                           let transcript = note.transcript, !transcript.isEmpty {
                            enhancedOriginalToggle
                                .padding(.bottom, 12)
                        }

                        // 3b. Format + Adjust, one menu labelled with the
                        // current format (2026-08-26). See formatMenu.
                        formatMenu
                            .padding(.bottom, 12)

                        // 4. Body text (hero content)
                        noteBodySection
                            .padding(.bottom, 20)

                        // 4b. Practice (2026-08-20). Deliberately a visible
                        // card, not a menu item — the transform control was
                        // missed for exactly that reason.
                        quizSection
                            .padding(.bottom, 20)

                        // 4a. Image attachments
                        if note.hasImages {
                            ImageGalleryView(
                                imageFileNames: note.imageFileNames,
                                onImageTap: { fileName in
                                    selectedImageForFullscreen = fileName
                                    showingFullscreenImage = true
                                },
                                onImageDelete: { fileName in
                                    deletePhoto(fileName)
                                }
                            )
                            .padding(.bottom, 20)
                        }

                        // 4b. Persona chips — persona schema-driven extraction (additive to baseline)
                        PersonaChipsView(note: note)
                            .padding(.bottom, 20)

                        // 4c. Wiki connections — which articles this note touched (wiki index)
                        NoteWikiConnectionsView(noteId: note.id)
                            .padding(.bottom, 20)

                        // 5. AI generating indicator
                        if isGeneratingAI || isRewriting {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(.eeonAccentAI)
                                Text(isRewriting ? "Rewriting..." : "Transforming...")
                                    .font(.subheadline)
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80) // Space for bottom toolbar
                    .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }

            // Bottom toolbar
            VStack(spacing: 0) {
                bottomToolbar
            }

            // Copied feedback toast
            if showCopiedFeedback {
                VStack {
                    Spacer()
                    Text("Copied!")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray3))
                        .cornerRadius(20)
                        .padding(.bottom, 80)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.eeonTextPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5).opacity(0.5))
                        .clipShape(Circle())
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Share button — shares note text directly
                    Button(action: { showingTextShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.eeonTextPrimary)
                    }

                    // More menu
                    Menu {
                        // Share as CloudKit link
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share as Link", systemImage: "link")
                        }

                        Divider()

                        // Project assignment
                        Button {
                            showingProjectPicker = true
                        } label: {
                            Label("Assign Project", systemImage: "folder")
                        }

                        // Tag assignment
                        Button {
                            showingTagPicker = true
                        } label: {
                            Label("Manage Tags", systemImage: "tag")
                        }

                        // Photo picker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(isProcessingImage ? "Processing..." : "Add Photo", systemImage: "photo.badge.plus")
                        }
                        .disabled(isProcessingImage)

                        Divider()

                        // Favorite toggle
                        Button {
                            note.isFavorite.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(
                                note.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                            )
                        }

                        // Archive toggle
                        Button {
                            note.isArchived.toggle()
                            try? modelContext.save()
                            if note.isArchived {
                                dismiss()
                            }
                        } label: {
                            Label(
                                note.isArchived ? "Unarchive" : "Archive",
                                systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox"
                            )
                        }

                        Divider()

                        // Audio controls (speed, skip) — moved here from removed player bar
                        if note.audioURL != nil {
                            Menu {
                                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                                    Button {
                                        audioRecorder.setPlaybackRate(Float(rate))
                                    } label: {
                                        HStack {
                                            Text(rate == 1.0 ? "1x" : "\(rate, specifier: "%.2g")x")
                                            if audioRecorder.playbackRate == Float(rate) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("Playback Speed", systemImage: "speedometer")
                            }
                        }

                        Divider()

                        // Delete
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.eeonTextPrimary)
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }
            processPhoto(newItem)
        }
        .fullScreenCover(isPresented: $showingFullscreenImage) {
            if let fileName = selectedImageForFullscreen {
                FullscreenImageView(fileName: fileName) {
                    showingFullscreenImage = false
                    selectedImageForFullscreen = nil
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Delete Note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareNoteView(note: note)
        }
        .sheet(isPresented: $showingTextShareSheet) {
            // Use a UIActivityItemSource so iMessage/Slack/Mail get a real preview
            // (title + snippet + app icon) instead of a generic text card.
            ActivityViewControllerRepresentable(activityItems: [
                NoteShareItemSource(
                    title: note.displayTitle,
                    body: note.enhancedNoteText ?? note.transcript ?? note.content,
                    sharedText: shareableText
                )
            ])
        }
        .sheet(isPresented: $showingAssistant) {
            if let query = assistantQuery, !query.isEmpty {
                AnswerSheet(initialQuery: query)
            }
        }
        .sheet(isPresented: $showingQuiz) {
            QuizView(note: note, questions: note.quizQuestions)
        }
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerSheet(
                selectedProjectId: $note.projectId,
                projects: allProjects.filter { !$0.isArchived },
                noteContent: note.transcript ?? note.content
            )
        }
        .sheet(isPresented: $showingTagPicker) {
            NoteTagPickerSheet(note: note)
        }
        .sheet(isPresented: $showingCustomPrompt) {
            CustomPromptSheet(
                promptText: $customPromptText,
                isPresented: $showingCustomPrompt,
                onSubmit: {
                    generateAIContent(type: .custom, customPrompt: customPromptText)
                    customPromptText = ""
                }
            )
        }
        .photosPicker(isPresented: $showingBottomPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: $showingRewriteSheet) {
            RewriteTemplatePickerSheet { template in
                handleRewriteTemplate(template)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(onDismiss: { showingPaywall = false })
        }
        .onAppear {
            // Rating ask at the transformation moment (see ReviewPrompter).
            if let enhanced = note.enhancedNoteText, !enhanced.isEmpty,
               ReviewPrompter.noteEnhancedShown() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { requestReview() }
            }
        }
        .alert("AI Error", isPresented: .init(
            get: { aiError != nil },
            set: { if !$0 { aiError = nil } }
        )) {
            Button("OK") { aiError = nil }
        } message: {
            Text(aiError ?? "Unknown error")
        }
        .alert("Rewrite Error", isPresented: .init(
            get: { rewriteError != nil },
            set: { if !$0 { rewriteError = nil } }
        )) {
            Button("OK") { rewriteError = nil }
        } message: {
            Text(rewriteError ?? "Unknown error")
        }
        .onAppear {
            if let transform = autoTransform,
               note.activeRewriteType != transform.rawValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    generateAIContent(type: transform)
                }
            }
        }
    }

    // MARK: - Calendar Context Row

    /// "During Standup · with Lena, Marco" — the event this recording
    /// overlapped (CalendarContextService). Renders nothing when there isn't one.
    @ViewBuilder
    private var calendarContextRow: some View {
        if let ctx = note.calendarContext {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                Text(ctx.attendeesLabel.map { "During \(ctx.title) \u{00B7} \($0)" } ?? "During \(ctx.title)")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Audio Pill + Date Row

    private var audioPillAndDateRow: some View {
        HStack(spacing: 12) {
            // Audio pill (tappable play/pause with duration)
            if note.audioURL != nil {
                Button(action: togglePlayback) {
                    HStack(spacing: 6) {
                        Image(systemName: audioRecorder.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)

                        if audioRecorder.isPlaying {
                            // Show elapsed / total while playing
                            Text(formatDuration(audioRecorder.currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.eeonTextPrimary.opacity(0.9))
                        } else {
                            Text(formatDuration(audioRecorder.duration > 0 ? audioRecorder.duration : note.audioDuration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.eeonTextPrimary.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(audioRecorder.isPlaying ? Color.eeonAccentAI : Color(.systemGray4))
                    )
                }
            }

            // Date
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)

            // Intent badge
            if note.intent != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: note.intent.icon)
                        .font(.caption2)
                    Text(note.intentType)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(note.intent.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(note.intent.color.opacity(0.12))
                .cornerRadius(6)
            }

            Spacer()
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text(note.displayTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(4)

                Spacer()

                // Favorite button
                Button(action: {
                    note.isFavorite.toggle()
                    try? modelContext.save()
                }) {
                    Image(systemName: note.isFavorite ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(note.isFavorite ? .eeonAccent : .eeonTextTertiary)
                }
                .padding(.top, 4)
            }

            // Source type chip
            if let label = note.sourceType.label {
                HStack(spacing: 4) {
                    if let icon = note.sourceType.badgeIcon {
                        Image(systemName: icon)
                            .font(.caption2)
                    }
                    Text(label)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.eeonTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.eeonCard)
                .cornerRadius(6)
            }

            // Tappable original URL for web articles
            if let urlString = note.originalURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                        Text(url.host ?? urlString)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.blue)
                }
            }

            // Annotation if present
            if let annotation = note.annotation, !annotation.isEmpty {
                Text(annotation)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .italic()
            }
        }
    }

    // MARK: - Computed Properties

    private var noteDecisions: [ExtractedDecision] {
        allDecisions.filter { $0.sourceNoteId == note.id }
    }

    private var noteActions: [ExtractedAction] {
        allActions.filter { $0.sourceNoteId == note.id }
    }

    private var noteCommitments: [ExtractedCommitment] {
        allCommitments.filter { $0.sourceNoteId == note.id }
    }

    private var noteURLs: [ExtractedURL] {
        allExtractedURLs.filter { $0.sourceNoteId == note.id }
    }

    private var hasExtractions: Bool {
        !noteDecisions.isEmpty || !noteActions.isEmpty || !noteCommitments.isEmpty ||
        !note.mentionedPeople.isEmpty || !note.topics.isEmpty
    }

    // MARK: - Enhanced / Original Toggle

    private var enhancedOriginalToggle: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingOriginal = false
                }
            } label: {
                Text("Enhanced")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(!showingOriginal ? .white : .gray)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(!showingOriginal ? Color(.systemGray4) : Color.clear)
                    )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditingEnhanced = false
                    showingOriginal = true
                }
            } label: {
                Text("Original")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(showingOriginal ? .white : .gray)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showingOriginal ? Color(.systemGray4) : Color.clear)
                    )
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.eeonCard)
        )
    }

    // MARK: - Note Body Section (Hero Content)

    @ViewBuilder
    private var noteBodySection: some View {
        let displayText: String = {
            if showingOriginal {
                return note.transcript ?? note.content
            } else {
                return note.enhancedNoteText ?? note.transcript ?? note.content
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            if isEditingEnhanced {
                TextEditor(text: $enhancedDraft)
                    .font(.body.leading(.loose))
                    .foregroundStyle(.eeonTextPrimary)
                    .lineSpacing(6)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color.eeonCard)
                    .cornerRadius(12)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isEditingEnhanced = false
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)

                    Spacer()

                    Button("Save") {
                        saveEnhancedEdit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.eeonAccentAI))
                }
            } else {
                if !displayText.isEmpty {
                    // Enhanced notes carry light inline markdown (**bold**
                    // section labels on longer notes). Render it; fall back to
                    // the raw string if parsing ever fails.
                    Text(inlineMarkdown(displayText))
                        .font(.body.leading(.loose))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Edit + re-run controls — only on the Enhanced view of a note
                // that actually has enhanced text to edit / re-run.
                if !showingOriginal, let enhanced = note.enhancedNoteText, !enhanced.isEmpty {
                    enhancedEditControls
                }
            }
        }
    }

    /// One-tap summary styles — the most-used transforms as a horizontal chip
    /// row above the body. Each tap rewrites the note text via the existing
    /// rewrite path (voice/tone-aware); "More…" opens the full template picker
    /// including custom templates.
    /// The formats a note can be rendered in. "Summary" is the baseline
    /// enhanced note; the rest are profession/meeting formats.
    private static let summaryFormats: [AITransformType] = [
        .summary, .schoolNotes, .clinicalNote, .caseNote,
        .meetingSummary, .executiveSummary
    ]

    /// Formats that only make sense for one profession. A founder has no use
    /// for "Clinical Note" and a doctor none for "Case Note", so these appear
    /// as chips ONLY when they are the user's own persona default. Everyone
    /// else still reaches them through "More" — hidden, not deleted.
    private static let professionLocked: Set<AITransformType> = [
        .schoolNotes, .clinicalNote, .caseNote
    ]

    /// The chips THIS user should see. Summary always leads (every note has
    /// one), then their persona's default, then formats useful to anyone.
    ///
    /// Reordering alone wasn't enough: a founder still had to scroll past two
    /// other professions' formats. If no preset has been chosen we show
    /// everything, because guessing wrong and hiding a format the user wanted
    /// is worse than a slightly longer row.
    private var orderedFormats: [AITransformType] {
        let all = Self.summaryFormats
        let preferred: AITransformType? = {
            guard let raw = PersonaPresetStore.defaultTransformRaw,
                  let type = AITransformType(rawValue: raw),
                  type != .summary,
                  all.contains(type)
            else { return nil }
            return type
        }()

        guard let preferred else { return all }

        var out: [AITransformType] = [.summary, preferred]
        for format in all where format != .summary && format != preferred {
            if Self.professionLocked.contains(format) { continue }
            out.append(format)
        }
        return out
    }

    private var currentFormatName: String {
        note.summaryFormat ?? "Summary"
    }

    /// The format control — one Pocket-style menu labelled with the CURRENT
    /// format ("Summary ⌄"). Formats are persona-filtered (a founder never
    /// sees Clinical Note); "More formats…" reaches the full catalog and
    /// custom templates; the Adjust actions live in the same menu.
    ///
    /// History: a "Summary ⌄" menu became visible chips on 2026-08-20 because
    /// the menu hid that transforming was possible. The chips then put
    /// profession formats (School Notes, Clinical Note, Case Note) in front
    /// of users who had never chosen a profession — the fallback showed
    /// everything. 2026-08-26, Shawn: one menu, the way Pocket does it.
    private var formatMenu: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Format") {
                    ForEach(orderedFormats) { format in
                        Button {
                            applyFormat(format)
                        } label: {
                            if currentFormatName == format.rawValue {
                                Label(format.rawValue, systemImage: "checkmark")
                            } else {
                                Label(format.rawValue, systemImage: format.icon)
                            }
                        }
                    }
                    Button {
                        showingRewriteSheet = true
                    } label: {
                        Label("More formats…", systemImage: "ellipsis.circle")
                    }
                }
                Section("Adjust") {
                    ForEach(NoteAdjustment.allCases) { adjustment in
                        Button {
                            applyAdjustment(adjustment)
                        } label: {
                            Label(adjustment.title, systemImage: adjustment.icon)
                        }
                    }
                    if adjustmentUndoText != nil {
                        Button {
                            undoAdjustment()
                        } label: {
                            Label("Undo adjustment", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentFormatName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.eeonAccentAI)
                .padding(.horizontal, 14)
                .frame(minHeight: EEONLayout.minTarget)
                .background(Capsule().fill(Color.eeonAccentAI.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color.eeonAccentAI.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
            }
            .disabled(isRewriting)

            if isRewriting {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Rewriting…")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Quiz

    /// Entry point for flashcard practice. Hidden only when the note is too
    /// short to quiz on, so a two-line grocery note doesn't get study chrome.
    @ViewBuilder
    private var quizSection: some View {
        if note.quizSourceText.trimmingCharacters(in: .whitespacesAndNewlines).count
            >= QuizService.minimumCharacters {
            VStack(alignment: .leading, spacing: EEONLayout.snug) {
                HStack(spacing: EEONLayout.snug) {
                    Image(systemName: "graduationcap.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.eeonAccentAI)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.quizQuestions.isEmpty ? "Test yourself" : "Quiz ready")
                            .font(EEONType.itemTitle)
                            .foregroundStyle(.eeonTextPrimary)
                        Text(note.quizQuestions.isEmpty
                             ? "Turn this note into flashcards"
                             : "\(note.quizQuestions.count) questions")
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: EEONLayout.tight)
                }

                Button {
                    if note.quizQuestions.isEmpty {
                        generateQuiz()
                    } else {
                        showingQuiz = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingQuiz {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                            Text("Writing questions…")
                        } else {
                            Image(systemName: note.quizQuestions.isEmpty ? "sparkles" : "play.fill")
                                .font(.caption.weight(.bold))
                            Text(note.quizQuestions.isEmpty ? "Make a quiz" : "Start quiz")
                        }
                    }
                    .font(EEONType.control)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: EEONLayout.minTarget)
                    .background(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .fill(Color.eeonAccentAI)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingQuiz)

                if !note.quizQuestions.isEmpty {
                    Button {
                        generateQuiz()
                    } label: {
                        Text("Write new questions")
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                            .frame(minHeight: EEONLayout.minTarget)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingQuiz)
                }

                if let quizError {
                    Text(quizError)
                        .font(EEONType.meta)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EEONLayout.standard)
            .background(
                RoundedRectangle(cornerRadius: EEONLayout.cardRadius)
                    .fill(Color.eeonAccentAI.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: EEONLayout.cardRadius)
                    .strokeBorder(Color.eeonAccentAI.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func generateQuiz() {
        guard !isGeneratingQuiz else { return }
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            quizError = "No OpenAI API key configured."
            return
        }
        isGeneratingQuiz = true
        quizError = nil
        let source = note.quizSourceText

        Task {
            do {
                let questions = try await QuizService.generateQuiz(for: source, apiKey: apiKey)
                await MainActor.run {
                    note.quizQuestions = questions
                    isGeneratingQuiz = false
                    showingQuiz = true
                }
            } catch {
                await MainActor.run {
                    quizError = error.localizedDescription
                    isGeneratingQuiz = false
                }
            }
        }
    }

    /// Apply a summary format to this note and remember it.
    private func applyFormat(_ format: AITransformType) {
        note.summaryFormat = format.rawValue
        let template = RewriteTemplate(
            id: "format-" + format.rawValue,
            name: format.rawValue,
            emoji: "",
            section: .summary,
            isPro: format != .summary,
            systemPrompt: format.prompt
        )
        handleRewriteTemplate(template)
    }

    /// Renders the light inline markdown enhanced notes carry (**bold** labels),
    /// preserving line breaks. Plain text passes through unchanged.
    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// Always-visible Edit + Re-run controls shown beneath the enhanced text.
    @ViewBuilder
    private var enhancedEditControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    enhancedDraft = note.enhancedNoteText ?? note.transcript ?? note.content
                    reprocessError = nil
                    isEditingEnhanced = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonAccentAI)
                }
                .disabled(isReprocessing)

                Button {
                    runEnhancementRerun()
                } label: {
                    Label("Re-run enhancement", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonAccentAI)
                }
                .disabled(isReprocessing)

                if isReprocessing {
                    ProgressView().scaleEffect(0.7)
                }

                Spacer()
            }

            if note.enhancedNoteEdited {
                Text("Edited")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)
            }

            if let reprocessError {
                Text(reprocessError)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Transform Output Section

    private func transformOutputSection(output: String, typeRaw: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let type = AITransformType(rawValue: typeRaw) {
                    Image(systemName: type.icon)
                        .foregroundStyle(.eeonAccentAI)
                    Text(type.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.eeonAccentAI)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = output
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(.eeonAccentAI)
                }

                Button {
                    note.activeRewriteText = nil
                    note.activeRewriteType = nil
                    note.updatedAt = Date()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("Clear")
                    }
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                }
            }

            Text(output)
                .font(.body)
                .foregroundStyle(.eeonTextPrimary)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.eeonCard)
                .cornerRadius(12)
                .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
        }
    }

    // MARK: - Next Step Card

    private func nextStepCard(nextStep: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(.eeonAccentAI)

            VStack(alignment: .leading, spacing: 2) {
                Text("Next Step")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)
                Text(nextStep)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.eeonTextPrimary)
            }

            Spacer()

            Button {
                note.resolveNextStep(with: "Completed")
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.eeonAccentAI)
            }
        }
        .padding()
        .background(Color.eeonAccentAI.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Extraction Section (Collapsed by Default)

    private var extractionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingExtractions.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showingExtractions ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Extractions")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    // Count badge
                    let count = noteDecisions.count + noteActions.count + noteCommitments.count + note.mentionedPeople.count + note.topics.count
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .foregroundStyle(.eeonTextSecondary)
            }

            if showingExtractions {
                ExtractionChipsSection(
                    decisions: noteDecisions,
                    actions: noteActions,
                    commitments: noteCommitments,
                    people: note.mentionedPeople,
                    topics: note.topics,
                    onChipTap: { query in
                        assistantQuery = query
                        showingAssistant = true
                    },
                    onActionToggle: { action in
                        if action.isCompleted {
                            action.markIncomplete()
                        } else {
                            action.markComplete()
                        }
                    }
                )
                .padding()
                .background(Color.eeonCard)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Transcript Section (Collapsed)

    private func transcriptSection(transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingTranscript.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showingTranscript ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Show what I said")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(transcript.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .foregroundStyle(.eeonTextSecondary)
            }

            if showingTranscript {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(.eeonTextPrimary.opacity(0.8))
                    .lineSpacing(4)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.eeonCard)
                    .cornerRadius(12)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Bottom Toolbar

    /// One shape for every action in the note toolbar: icon over label,
    /// 44pt minimum, equal width, secondary tint.
    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarLabel(icon: icon, label: label)
        }
    }

    private func toolbarLabel(icon: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.body)
            Text(label)
                .font(EEONType.badge)
        }
        .foregroundStyle(.eeonTextSecondary)
        .frame(maxWidth: .infinity, minHeight: EEONLayout.minTarget)
        .padding(.vertical, EEONLayout.tight)
        .contentShape(Rectangle())
    }


    private var bottomToolbar: some View {
        // Rebuilt 2026-08-20. The floating violet "AI" circle is gone: it
        // opened the template picker, which the `Summary v` switcher at the
        // top of the note already does — two controls, one job. What remains
        // is four evenly-weighted actions in the app's own language, each a
        // 44pt target with a label so nothing is a guess.
        HStack(spacing: 0) {
            toolbarButton(icon: "doc.on.doc", label: showCopiedFeedback ? "Copied" : "Copy") {
                UIPasteboard.general.string = note.enhancedNoteText ?? note.transcript ?? note.content
                withAnimation { showCopiedFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showCopiedFeedback = false }
                }
            }

            toolbarButton(icon: "number", label: "Tags") {
                showingTagPicker = true
            }

            toolbarButton(icon: "square.and.arrow.up", label: "Share") {
                showingTextShareSheet = true
            }

            Menu {
                // Share as CloudKit link
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share as Link", systemImage: "link")
                }

                Divider()

                // Project assignment
                Button {
                    showingProjectPicker = true
                } label: {
                    Label("Assign Project", systemImage: "folder")
                }

                // Photo picker
                Button {
                    showingBottomPhotoPicker = true
                } label: {
                    Label("Add Photo", systemImage: "photo.badge.plus")
                }

                // Favorite toggle
                Button {
                    note.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Label(
                        note.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                    )
                }

                // Archive toggle
                Button {
                    note.isArchived.toggle()
                    try? modelContext.save()
                    if note.isArchived {
                        dismiss()
                    }
                } label: {
                    Label(
                        note.isArchived ? "Unarchive" : "Archive",
                        systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }

                Divider()

                // Delete
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            } label: {
                toolbarLabel(icon: "ellipsis", label: "More")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(Color.eeonBackgroundSecondary)
        )
    }

    // MARK: - Adjustments (in place, undoable)

    private func applyAdjustment(_ adjustment: NoteAdjustment) {
        let template = adjustment.template
        if template.isPro && !SubscriptionManager.shared.isSubscribed {
            showingPaywall = true
            return
        }

        // Work on what is on screen: the enhanced note when there is one,
        // otherwise the transcript — never a stale format.
        let source: String = {
            if let enhanced = note.enhancedNoteText, !enhanced.isEmpty { return enhanced }
            return note.transcript ?? note.content
        }()
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rewriteError = "No content to adjust"
            return
        }

        isRewriting = true
        Task {
            do {
                let result = try await RewriteService.rewrite(transcript: source, template: template)
                await MainActor.run {
                    adjustmentUndoText = source
                    note.enhancedNoteText = result
                    note.updatedAt = Date()
                    showingOriginal = false
                    isRewriting = false
                }
            } catch {
                await MainActor.run {
                    rewriteError = error.localizedDescription
                    isRewriting = false
                }
            }
        }
    }

    /// Swap the adjusted text with what it replaced. Swapping again redoes.
    private func undoAdjustment() {
        guard let previous = adjustmentUndoText else { return }
        adjustmentUndoText = note.enhancedNoteText
        note.enhancedNoteText = previous
        note.updatedAt = Date()
    }

    // MARK: - Rewrite Handling

    private func handleRewriteTemplate(_ template: RewriteTemplate) {
        // Check PRO gating
        if template.isPro && !SubscriptionManager.shared.isSubscribed {
            showingPaywall = true
            return
        }

        // Always regenerate from the original transcript so switching formats
        // never transforms a transform (Pocket regenerates from source too).
        // The one exception: a hand-corrected note keeps the user's wording as
        // the source, because their correction is the truth.
        let sourceText: String = {
            if note.enhancedNoteEdited, let edited = note.enhancedNoteText, !edited.isEmpty {
                return edited
            }
            return note.transcript ?? note.enhancedNoteText ?? note.content
        }()
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rewriteError = "No content to rewrite"
            return
        }

        isRewriting = true

        Task {
            do {
                let result = try await RewriteService.rewrite(
                    transcript: sourceText,
                    template: template
                )

                await MainActor.run {
                    note.enhancedNoteText = result
                    note.updatedAt = Date()
                    isRewriting = false
                }
            } catch {
                await MainActor.run {
                    rewriteError = error.localizedDescription
                    isRewriting = false
                }
            }
        }
    }

    // MARK: - Actions

    /// Persist an inline edit of the enhanced text. No API calls — the user's
    /// text is kept verbatim and the note is marked as hand-edited.
    private func saveEnhancedEdit() {
        let trimmed = enhancedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingEnhanced = false
            return
        }
        note.enhancedNoteText = trimmed
        note.enhancedNoteEdited = true
        note.enhancedNoteEditedAt = Date()
        note.updatedAt = Date()
        try? modelContext.save()
        isEditingEnhanced = false
        reprocessError = nil
    }

    /// Re-run the full AI pipeline from the current enhanced text. Used by the
    /// always-visible "Re-run enhancement" control. The enhanced text (which may
    /// have been hand-corrected) is the source — never the stale transcript.
    private func runEnhancementRerun() {
        let source = note.enhancedNoteText ?? note.transcript ?? note.content
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reprocessError = "Nothing to re-run."
            return
        }
        reprocessError = nil
        isReprocessing = true

        Task {
            let ok = await IntelligenceService.shared.reprocessNote(
                note: note,
                sourceText: source,
                context: modelContext
            )
            await MainActor.run {
                isReprocessing = false
                if !ok {
                    reprocessError = "Couldn't re-run. Check your connection and try again."
                }
            }
        }
    }

    private func togglePlayback() {
        guard let url = note.audioURL else { return }

        if audioRecorder.isPlaying {
            audioRecorder.pausePlaying()
        } else if audioRecorder.currentTime > 0 {
            audioRecorder.resumePlaying()
        } else {
            try? audioRecorder.playAudio(url: url)
        }
    }

    private func deleteNote() {
        if let fileName = note.audioFileName {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        // Delete image files
        note.deleteImageFiles()
        modelContext.delete(note)
        try? modelContext.save()
        dismiss()
    }

    private func deletePhoto(_ fileName: String) {
        ImageService.deleteImage(fileName: fileName)
        note.removeImageFileName(fileName)
        note.updatedAt = Date()
        try? modelContext.save()
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - AI Generation

    private func generateAIContent(type: AITransformType, customPrompt: String? = nil) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            aiError = "OpenAI API key not configured"
            return
        }

        let sourceText = note.transcript ?? note.content
        guard !sourceText.isEmpty else {
            aiError = "No content to transform"
            return
        }

        let prompt = customPrompt ?? type.prompt

        isGeneratingAI = true

        Task {
            do {
                let result = try await generateWithOpenAI(
                    prompt: prompt,
                    content: sourceText,
                    apiKey: apiKey
                )

                await MainActor.run {
                    note.activeRewriteText = result
                    note.activeRewriteType = type.rawValue
                    note.updatedAt = Date()
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiError = "Failed to generate: \(error.localizedDescription)"
                    isGeneratingAI = false
                }
            }
        }
    }

    // MARK: - Photo Processing

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingImage = true

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        aiError = "Could not load image"
                        isProcessingImage = false
                        selectedPhotoItem = nil
                    }
                    return
                }

                let fileName = try ImageService.saveImage(image, noteId: note.id)

                await MainActor.run {
                    note.addImageFileName(fileName)
                    note.updatedAt = Date()
                    try? modelContext.save()
                    isProcessingImage = false
                    selectedPhotoItem = nil
                }

                // Try OCR if note has no content
                if note.content.isEmpty {
                    let extractedText = try await ImageService.extractText(from: image)
                    if !extractedText.isEmpty {
                        await MainActor.run {
                            note.content = extractedText
                            note.updatedAt = Date()
                            try? modelContext.save()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    aiError = "Failed to process image: \(error.localizedDescription)"
                    isProcessingImage = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func generateWithOpenAI(prompt: String, content: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                // Route through ContextAssembler so the quick transforms honor the
                // user's tuned voice/tone, purpose, and focus — same .rewrite context
                // the rewrite templates use. Without this they ignored Tune EEON.
                ["role": "system", "content": ContextAssembler.flatPrefix(for: .rewrite) + prompt],
                ["role": "user", "content": content]
            ],
            "max_tokens": 1000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No response generated"
    }
}

// MARK: - Project Picker Sheet

struct ProjectPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProjectId: UUID?
    let projects: [Project]
    var noteContent: String = ""  // For learning from corrections

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedProjectId = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.eeonTextSecondary)
                        Text("No Project")
                        Spacer()
                        if selectedProjectId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(projects) { project in
                    Button {
                        // Learn from this assignment if changing to a different project
                        if selectedProjectId != project.id && !noteContent.isEmpty {
                            ProjectMatcher.learnFromCorrection(text: noteContent, assignedTo: project)
                        }
                        selectedProjectId = project.id
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: project.icon)
                                .foregroundStyle(.blue)
                            Text(project.name)
                            Spacer()
                            if selectedProjectId == project.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Image Gallery View

struct ImageGalleryView: View {
    let imageFileNames: [String]
    let onImageTap: (String) -> Void
    let onImageDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.eeonAccentAI)
                Text("Attachments")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)
                Spacer()
                Text("\(imageFileNames.count) image\(imageFileNames.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(imageFileNames, id: \.self) { fileName in
                        ImageThumbnailView(
                            fileName: fileName,
                            onTap: { onImageTap(fileName) },
                            onDelete: { onImageDelete(fileName) }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.eeonCard)
        .cornerRadius(12)
    }
}

struct ImageThumbnailView: View {
    let fileName: String
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        if let image = ImageService.loadImage(fileName: fileName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .cornerRadius(8)
                .clipped()
                .onTapGesture { onTap() }
                .contextMenu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .confirmationDialog("Delete Image?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    Button("Cancel", role: .cancel) { }
                }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.eeonTextSecondary)
                }
        }
    }
}

struct FullscreenImageView: View {
    let fileName: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = ImageService.loadImage(fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.eeonTextPrimary.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - URL Preview Card

struct URLPreviewCard: View {
    let extractedURL: ExtractedURL

    var body: some View {
        Button {
            if let url = URL(string: extractedURL.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                // Favicon or image placeholder
                if let imageURLString = extractedURL.imageURL,
                   let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        case .failure:
                            urlPlaceholderIcon
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        @unknown default:
                            urlPlaceholderIcon
                        }
                    }
                } else {
                    urlPlaceholderIcon
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(extractedURL.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let description = extractedURL.urlDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.eeonTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(extractedURL.displayHost)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(12)
            .background(Color.eeonCard)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var urlPlaceholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.15))
                .frame(width: 60, height: 60)

            Image(systemName: "link")
                .font(.title2)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Activity View Controller (UIKit wrapper for sharing text)

struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Rich Note Share Item Source

/// Wraps a note's text for UIActivityViewController so the share sheet shows a
/// real preview (title + snippet + icon) instead of generic text.
/// iMessage bubbles, Mail headers, Slack cards all use LPLinkMetadata to render.
final class NoteShareItemSource: NSObject, UIActivityItemSource {
    let title: String
    let body: String
    let sharedText: String

    init(title: String, body: String, sharedText: String) {
        self.title = title
        self.body = body
        self.sharedText = sharedText
    }

    // Placeholder shown while the share sheet decides how to render
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        sharedText
    }

    // The actual payload sent to the chosen destination
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        sharedText
    }

    // Email subject line (Mail app uses this)
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title.isEmpty ? "Note from EEON" : title
    }

    // Rich preview metadata — iMessage, Slack, Mail render this as a title + icon card
    // using the actual note's title instead of a generic "Shared with you" fallback.
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title.isEmpty ? "Note from EEON" : title
        metadata.originalURL = URL(string: "https://eeon.com")

        if let icon = Self.appIconImage() {
            metadata.iconProvider = NSItemProvider(object: icon)
        }

        return metadata
    }

    /// Pulls the primary AppIcon out of the bundle for use as the preview icon.
    private static func appIconImage() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let lastIcon = files.last else {
            return UIImage(named: "AppIcon")
        }
        return UIImage(named: lastIcon) ?? UIImage(named: "AppIcon")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NoteDetailView(note: Note(
            title: "Reflecting Loss and Change in Neighborhood",
            content: "A person reflects on the end of 2008, expressing a sense of finality and possibly loss.",
            transcript: "Feel like they took the shot of no. Can I ride through the hood?"
        ))
    }
    .modelContainer(for: [Note.self, Project.self], inMemory: true)
}
