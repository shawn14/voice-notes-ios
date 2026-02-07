//
//  AIHomeView.swift
//  voice notes
//
//  AI-forward home screen that feels like a chief of staff
//  Summarizes, organizes, and surfaces what matters most
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AIHomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var tags: [Tag]
    @Query(sort: \DailyBrief.briefDate, order: .reverse) private var dailyBriefs: [DailyBrief]
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var people: [MentionedPerson]
    @Query(sort: \ExtractedURL.createdAt, order: .reverse) private var extractedURLs: [ExtractedURL]
    @Query private var extractedCommitments: [ExtractedCommitment]
    @Query private var kanbanItems: [KanbanItem]
    @Query private var kanbanMovements: [KanbanMovement]
    @Query private var extractedActions: [ExtractedAction]
    @Query private var unresolvedItems: [UnresolvedItem]

    private var authService = AuthService.shared
    private var intelligenceService = IntelligenceService.shared

    @State private var showingSettings = false
    @State private var showingAllNotes = false
    @State private var showingPeopleView = false
    @State private var showPaywall = false
    @State private var showSignIn = false

    // Recording state
    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Photo state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    // Today's daily brief
    private var todaysBrief: DailyBrief? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyBriefs.first { $0.briefDate >= today }
    }

    // People needing attention (those with open commitments)
    private var peopleNeedingAttention: [MentionedPerson] {
        people.filter { $0.openCommitmentCount > 0 && !$0.isArchived }
            .sorted { $0.openCommitmentCount > $1.openCommitmentCount }
    }

    // Recent URLs with metadata
    private var recentLinks: [ExtractedURL] {
        extractedURLs.filter { $0.title != nil || $0.siteName != nil }
            .prefix(5)
            .map { $0 }
    }

    // Active topics - group notes by inferred project or tags
    private var activeTopics: [TopicGroup] {
        buildActiveTopics()
    }

    // Recent notes for quick access
    private var recentNotes: [Note] {
        Array(notes.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    if !authService.isSignedIn {
                        signedOutView
                    } else {
                        // Main scrollable content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                // Today's Focus card
                                todaysFocusSection

                                // People needing attention
                                if !peopleNeedingAttention.isEmpty {
                                    peopleSection
                                }

                                // Active topics
                                if !activeTopics.isEmpty {
                                    topicsSection
                                }

                                // Recent links
                                if !recentLinks.isEmpty {
                                    linksSection
                                }

                                // Quick access to recent notes
                                recentNotesSection

                                // Spacer for bottom bar
                                Color.clear.frame(height: 100)
                            }
                            .padding(.top, 16)
                        }
                    }
                }

                // Bottom record bar
                VStack {
                    Spacer()
                    HomeBottomBar(
                        isRecording: isRecording,
                        isTranscribing: isTranscribing,
                        isProcessingPhoto: isProcessingPhoto,
                        onRecord: toggleRecording,
                        selectedPhotoItem: $selectedPhotoItem
                    )
                }

                // Recording overlay
                if isRecording {
                    HomeRecordingOverlay(
                        onStop: stopRecording,
                        onCancel: cancelRecording,
                        audioRecorder: audioRecorder
                    )
                }

                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAllNotes) {
                AllNotesView()
            }
            .sheet(isPresented: $showingPeopleView) {
                PeopleView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onDismiss: { showPaywall = false })
            }
            .sheet(isPresented: $showSignIn) {
                SignInView(onSignedIn: { showSignIn = false })
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                processSelectedPhoto(newItem)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                if authService.isSignedIn, let session = intelligenceService.sessionBrief {
                    Text(session.freshnessLabel)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                if authService.isSignedIn {
                    UserAvatarView(name: authService.displayName, size: 36)
                } else {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = authService.isSignedIn ? authService.displayName.components(separatedBy: " ").first ?? "" : ""

        let timeGreeting: String
        if hour < 12 {
            timeGreeting = "Good morning"
        } else if hour < 17 {
            timeGreeting = "Good afternoon"
        } else {
            timeGreeting = "Good evening"
        }

        if name.isEmpty {
            return timeGreeting
        } else {
            return "\(timeGreeting), \(name)"
        }
    }

    // MARK: - Signed Out View

    private var signedOutView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Your AI-powered notes")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("Record your thoughts and I'll help you\ntrack decisions, commitments, and follow-ups")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button {
                showSignIn = true
            } label: {
                Text("Sign In to Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Today's Focus Section

    private var todaysFocusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Today's Focus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal)

            if intelligenceService.isRefreshingDaily {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.blue)
                    Text("Preparing your brief...")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(12)
                .padding(.horizontal)
            } else if let brief = todaysBrief {
                TodaysFocusCard(brief: brief)
                    .padding(.horizontal)
            } else if let session = intelligenceService.sessionBrief {
                SessionFocusCard(session: session)
                    .padding(.horizontal)
            } else if notes.isEmpty {
                EmptyFocusCard()
                    .padding(.horizontal)
            } else {
                QuickStatsCard(
                    notesCount: notes.count,
                    openCommitments: extractedCommitments.filter { !$0.isCompleted }.count,
                    peopleCount: people.count
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - People Section

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Text("People Needing Attention")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()

                Button {
                    showingPeopleView = true
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(peopleNeedingAttention.prefix(5)) { person in
                        PersonAttentionCard(person: person)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Topics Section

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Active Topics")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(activeTopics.prefix(4)) { topic in
                        TopicCard(topic: topic)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Links Section

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Recent Links")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(recentLinks.prefix(3)) { link in
                    LinkPreviewRow(url: link)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Recent Notes Section

    private var recentNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.headline)
                    .foregroundStyle(.gray)
                Text("Recent Notes")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()

                Button {
                    showingAllNotes = true
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(recentNotes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        AIRecentNoteRow(note: note)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Topic Building

    private func buildActiveTopics() -> [TopicGroup] {
        var topics: [TopicGroup] = []

        // Group by project
        let projectLookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var notesByProject: [UUID: [Note]] = [:]

        for note in notes.prefix(50) { // Limit to recent notes
            if let projectId = note.projectId {
                notesByProject[projectId, default: []].append(note)
            }
        }

        for (projectId, projectNotes) in notesByProject {
            if let project = projectLookup[projectId], projectNotes.count >= 2 {
                let topic = TopicGroup(
                    id: projectId,
                    name: project.name,
                    icon: project.icon,
                    color: .blue,
                    noteCount: projectNotes.count,
                    recentActivity: projectNotes.first?.updatedAt ?? Date()
                )
                topics.append(topic)
            }
        }

        // Group by top tags if not enough projects
        if topics.count < 3 {
            var notesByTag: [UUID: [Note]] = [:]
            for note in notes.prefix(50) {
                for tag in note.tags {
                    notesByTag[tag.id, default: []].append(note)
                }
            }

            for tag in tags {
                if let tagNotes = notesByTag[tag.id], tagNotes.count >= 2 {
                    let exists = topics.contains { $0.name.lowercased() == tag.name.lowercased() }
                    if !exists {
                        let topic = TopicGroup(
                            id: tag.id,
                            name: tag.name,
                            icon: "tag.fill",
                            color: .blue,
                            noteCount: tagNotes.count,
                            recentActivity: tagNotes.first?.updatedAt ?? Date()
                        )
                        topics.append(topic)
                    }
                }
            }
        }

        return topics.sorted { $0.recentActivity > $1.recentActivity }
    }

    // MARK: - Recording Methods

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            if !authService.isSignedIn {
                showSignIn = true
                return
            }
            if !UsageService.shared.canCreateNote {
                showPaywall = true
                return
            }
            startRecording()
        }
    }

    private func startRecording() {
        do {
            currentAudioFileName = try audioRecorder.startRecording()
            isRecording = true
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording"
            showingError = true
            isRecording = false
            return
        }

        isRecording = false
        isTranscribing = true
        transcribeAndSave(url: url)
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        currentAudioFileName = nil
        isRecording = false
    }

    private func transcribeAndSave(url: URL) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            saveNote(transcript: nil)
            return
        }

        Task {
            do {
                let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                let transcript = try await service.transcribe(audioURL: url)

                await MainActor.run {
                    saveNote(transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    saveNote(transcript: nil)
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func saveNote(transcript: String?) {
        let note = Note(
            title: "",
            content: transcript ?? "",
            transcript: transcript,
            audioFileName: currentAudioFileName
        )
        modelContext.insert(note)
        UsageService.shared.incrementNoteCount()
        try? modelContext.save()

        // AI processing
        if let transcript = transcript, !transcript.isEmpty,
           let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let existingTags = tags
            let context = modelContext
            let allProjects = projects

            Task {
                do {
                    let title = try await generateTitle(for: transcript, apiKey: apiKey)
                    let extractor = TagExtractor(apiKey: apiKey)
                    let tagNames = try await extractor.extractTags(from: transcript)

                    await MainActor.run {
                        note.title = title
                        for tagName in tagNames {
                            if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                note.tags.append(existingTag)
                            } else {
                                let newTag = Tag(name: tagName)
                                context.insert(newTag)
                                note.tags.append(newTag)
                            }
                        }
                        isTranscribing = false
                        currentAudioFileName = nil
                    }

                    await intelligenceService.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: allProjects,
                        tags: existingTags,
                        context: context
                    )
                } catch {
                    await MainActor.run {
                        isTranscribing = false
                        currentAudioFileName = nil
                    }
                }
            }
        } else {
            isTranscribing = false
            currentAudioFileName = nil
            StatusCounters.shared.incrementNotesToday()
            StatusCounters.shared.markSessionStale()
        }
    }

    private func generateTitle(for text: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
                ["role": "user", "content": text]
            ],
            "max_tokens": 20
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
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Voice Note"
    }

    // MARK: - Photo Processing

    private func processSelectedPhoto(_ item: PhotosPickerItem) {
        if !authService.isSignedIn {
            showSignIn = true
            selectedPhotoItem = nil
            return
        }

        if !UsageService.shared.canCreateNote {
            showPaywall = true
            selectedPhotoItem = nil
            return
        }

        isProcessingPhoto = true

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        errorMessage = "Could not load image"
                        showingError = true
                        isProcessingPhoto = false
                        selectedPhotoItem = nil
                    }
                    return
                }

                await MainActor.run {
                    createNoteWithImage(image)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to process image: \(error.localizedDescription)"
                    showingError = true
                    isProcessingPhoto = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func createNoteWithImage(_ image: UIImage) {
        let noteId = UUID()

        do {
            let fileName = try ImageService.saveImage(image, noteId: noteId)

            let note = Note(title: "Photo Note", content: "")
            note.addImageFileName(fileName)
            modelContext.insert(note)
            UsageService.shared.incrementNoteCount()

            Task {
                do {
                    let extractedText = try await ImageService.extractText(from: image)
                    if !extractedText.isEmpty {
                        await MainActor.run {
                            note.content = extractedText
                            note.title = String(extractedText.prefix(50))
                        }

                        if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                            let title = try await generateTitle(for: extractedText, apiKey: apiKey)
                            await MainActor.run {
                                note.title = title
                            }

                            await intelligenceService.processNoteSave(
                                note: note,
                                transcript: extractedText,
                                projects: projects,
                                tags: tags,
                                context: modelContext
                            )
                        }
                    }
                } catch {
                    print("OCR failed: \(error)")
                }
            }

            isProcessingPhoto = false
            selectedPhotoItem = nil

        } catch {
            errorMessage = "Failed to save image: \(error.localizedDescription)"
            showingError = true
            isProcessingPhoto = false
            selectedPhotoItem = nil
        }
    }
}

// MARK: - Topic Group Model

struct TopicGroup: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let color: Color
    let noteCount: Int
    let recentActivity: Date
}

// MARK: - Today's Focus Card

struct TodaysFocusCard: View {
    let brief: DailyBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main summary
            Text(brief.whatMattersToday)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(3)

            // Highlights
            if !brief.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(brief.highlights.prefix(3), id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(highlight)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .lineLimit(2)
                        }
                    }
                }
            }

            // Top priority action
            if let firstAction = brief.suggestedActions.first {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Text(firstAction.content)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }

            // Warnings
            if !brief.warnings.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(brief.warnings.count) item\(brief.warnings.count == 1 ? "" : "s") need attention")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}

// MARK: - Session Focus Card

struct SessionFocusCard: View {
    let session: SessionBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                StatBubble(value: "\(session.quickStats.notesToday)", label: "Today", color: .blue)
                StatBubble(value: "\(session.quickStats.openActions)", label: "Actions", color: .orange)
                StatBubble(value: "\(session.quickStats.stalledItemCount)", label: "Stalled", color: session.quickStats.stalledItemCount > 0 ? .red : .gray)
            }

            if !session.attentionWarnings.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(session.attentionWarnings.first?.title ?? "Items need attention")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }
}

// MARK: - Empty Focus Card

struct EmptyFocusCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 40))
                .foregroundStyle(.gray)

            Text("Record your first thought")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Text("I'll help you track decisions, commitments, and follow-ups")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }
}

// MARK: - Quick Stats Card

struct QuickStatsCard: View {
    let notesCount: Int
    let openCommitments: Int
    let peopleCount: Int

    var body: some View {
        HStack(spacing: 16) {
            StatBubble(value: "\(notesCount)", label: "Notes", color: .blue)
            StatBubble(value: "\(openCommitments)", label: "Open", color: .orange)
            StatBubble(value: "\(peopleCount)", label: "People", color: .purple)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(16)
    }
}

// MARK: - Stat Bubble

struct StatBubble: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Person Attention Card

struct PersonAttentionCard: View {
    let person: MentionedPerson

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Text(person.initials)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(person.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(person.openCommitmentCount) open")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(width: 100)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Topic Card

struct TopicCard: View {
    let topic: TopicGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: topic.icon)
                    .font(.headline)
                    .foregroundStyle(topic.color)
                Spacer()
                Text("\(topic.noteCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(topic.color.opacity(0.3))
                    .cornerRadius(8)
            }

            Text(topic.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(topic.recentActivity.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(12)
        .frame(width: 140)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Link Preview Row

struct LinkPreviewRow: View {
    let url: ExtractedURL

    var body: some View {
        Button {
            if let urlString = URL(string: url.url) {
                UIApplication.shared.open(urlString)
            }
        } label: {
            HStack(spacing: 12) {
                // Favicon or icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                        .frame(width: 40, height: 40)

                    Image(systemName: "link")
                        .font(.body)
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.title ?? url.siteName ?? url.url)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let siteName = url.siteName {
                        Text(siteName)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Recent Note Row

struct AIRecentNoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            // Intent-colored icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(note.intent.color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: note.hasAudio ? "mic.fill" : "note.text")
                    .font(.body)
                    .foregroundStyle(note.intent.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()

            if note.intent != .unknown {
                Text(note.intentType)
                    .font(.caption2)
                    .foregroundStyle(note.intent.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(note.intent.color.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - All Notes View

struct AllNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var tags: [Tag]

    @State private var searchText = ""
    @State private var selectedTag: Tag?

    private var filteredNotes: [Note] {
        var result = notes

        if !searchText.isEmpty {
            result = result.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains { $0.id == tag.id } }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.gray)
                        TextField("Search notes", text: $searchText)
                            .foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Tag filter
                    if let tag = selectedTag {
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(tag.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                selectedTag = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Notes list
                    if filteredNotes.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(.gray)
                            Text("No notes found")
                                .font(.headline)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredNotes) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    HomeNoteRow(note: note) { tag in
                                        selectedTag = tag
                                    }
                                }
                                .listRowBackground(Color(.systemGray6).opacity(0.2))
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        note.isFavorite.toggle()
                                    } label: {
                                        Label(
                                            note.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: note.isFavorite ? "heart.slash" : "heart.fill"
                                        )
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("All Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func deleteNote(_ note: Note) {
        note.deleteAudioFile()
        note.deleteImageFiles()
        modelContext.delete(note)
    }
}

#Preview {
    AIHomeView()
        .modelContainer(for: [Note.self, Tag.self, Project.self, DailyBrief.self, MentionedPerson.self, ExtractedURL.self, ExtractedCommitment.self], inMemory: true)
}
