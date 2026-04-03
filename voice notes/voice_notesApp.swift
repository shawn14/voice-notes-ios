//
//  voice_notesApp.swift
//  voice notes
//
//  Created by Shawn Carpenter on 1/24/26.
//

import SwiftUI
import SwiftData
import WidgetKit
import BackgroundTasks

@main
struct voice_notesApp: App {
    let container: ModelContainer
    @State private var authService = AuthService.shared
    @State private var subscriptionManager = SubscriptionManager.shared
    @AppStorage("onboardingState") private var onboardingState: String = OnboardingState.needsSignIn.rawValue
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    // Shared note handling
    @State private var sharedNoteToShow: SharedNote?
    @State private var showingSharedNote = false
    @State private var sharedNoteError: String?
    @State private var showingSharedNoteError = false
    @State private var isLoadingSharedNote = false

    // Deep link: auto-start recording
    @State private var shouldStartRecording = false

    // Background task identifier for proactive alerts
    static let proactiveAlertsTaskId = "com.eeon.proactiveAlerts"

    init() {
        let schema = Schema([Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self, Project.self, DailyBrief.self, ExtractedURL.self, MentionedPerson.self, KnowledgeArticle.self])

        do {
            // Configure for CloudKit sync
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.aivoiceeeon")
            )

            container = try ModelContainer(for: schema, configurations: [config])
            cleanupDuplicateTags(in: container.mainContext)
        } catch {
            // If CloudKit fails, try without CloudKit
            print("CloudKit container failed, trying local: \(error)")

            do {
                let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                container = try ModelContainer(for: schema, configurations: [localConfig])
                cleanupDuplicateTags(in: container.mainContext)
            } catch {
                // Last resort — back up the old store before recreating
                // Previous code deleted the store here which destroyed all local notes
                print("Migration failed, attempting safe recovery: \(error)")

                do {
                    // Back up the old store so data isn't permanently lost
                    let defaultConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                    let storeURL = defaultConfig.url
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let backupURL = storeURL.deletingLastPathComponent()
                        .appendingPathComponent("default-backup-\(timestamp).store")
                    try? FileManager.default.copyItem(at: storeURL, to: backupURL)
                    print("Backed up store to: \(backupURL.path)")

                    // Remove old store files
                    for ext in ["", ".wal", ".shm"] {
                        let fileURL = ext.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + ext)
                        try? FileManager.default.removeItem(at: fileURL)
                    }

                    // Recreate WITH CloudKit so notes sync back from iCloud
                    let freshConfig = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        cloudKitDatabase: .private("iCloud.aivoiceeeon")
                    )
                    container = try ModelContainer(for: schema, configurations: [freshConfig])
                    print("Recovery succeeded — notes will re-sync from CloudKit")
                } catch {
                    // Absolute last resort — in-memory so app doesn't crash
                    print("All storage options failed, using in-memory: \(error)")
                    do {
                        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                        container = try ModelContainer(for: schema, configurations: [memConfig])
                    } catch {
                        fatalError("Failed to create ModelContainer: \(error)")
                    }
                }
            }
        }

        // Background task for proactive alerts is registered via .backgroundTask(.appRefresh) modifier on the Scene
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch OnboardingState(rawValue: onboardingState) ?? .needsSignIn {
                case .completed:
                    AIHomeView(shouldStartRecording: $shouldStartRecording)
                        .task {
                            await authService.checkCredentialState()
                            await subscriptionManager.updateSubscriptionStatus()
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                Task {
                                    await triggerAppActiveRefresh()
                                }
                            }
                        }
                case .needsPaywall:
                    OnboardingPaywallView()
                case .needsSignIn:
                    SignInView()
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .sheet(isPresented: $showingSharedNote) {
                sharedNoteToShow = nil
                isLoadingSharedNote = false
                sharedNoteError = nil
            } content: {
                NavigationStack {
                    Group {
                        if isLoadingSharedNote {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Loading shared note...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let note = sharedNoteToShow {
                            SharedNoteDetailView(sharedNote: note)
                        } else if let error = sharedNoteError {
                            ContentUnavailableView(
                                "Couldn't Open Link",
                                systemImage: "exclamationmark.triangle",
                                description: Text(error)
                            )
                        }
                    }
                    .toolbar {
                        if isLoadingSharedNote || sharedNoteError != nil {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingSharedNote = false }
                            }
                        }
                    }
                }
            }
            .preferredColorScheme(appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : nil)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(voice_notesApp.proactiveAlertsTaskId)) {
            await handleProactiveAlertsBackgroundTask()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Handle custom scheme: voicenotes://
        if url.scheme == "voicenotes" {
            if url.host == "record" {
                shouldStartRecording = true
                return
            }
            if url.host == "share",
               let noteId = url.pathComponents.last, !noteId.isEmpty {
                fetchAndShowSharedNote(id: noteId)
                return
            }
            return
        }

        // Handle Universal Links: https://eeon.com/share/{id} or https://www.eeon.com/share/{id}
        if url.scheme == "https", (url.host == "eeon.com" || url.host == "www.eeon.com") {
            let components = url.pathComponents // ["/" , "share", "{id}"]
            if components.count >= 3, components[1] == "share" {
                let noteId = components[2]
                fetchAndShowSharedNote(id: noteId)
                return
            }
        }
    }

    private func fetchAndShowSharedNote(id: String) {
        // Show sheet immediately with loading state
        sharedNoteToShow = nil
        sharedNoteError = nil
        isLoadingSharedNote = true
        showingSharedNote = true

        Task {
            do {
                if let note = try await CloudKitShareService.shared.fetchSharedNote(id: id) {
                    await MainActor.run {
                        sharedNoteToShow = note
                        isLoadingSharedNote = false
                    }
                } else {
                    await MainActor.run {
                        sharedNoteError = "This note has expired or been deleted."
                        isLoadingSharedNote = false
                    }
                }
            } catch {
                await MainActor.run {
                    sharedNoteError = "Couldn't load the shared note: \(error.localizedDescription)"
                    isLoadingSharedNote = false
                }
            }
        }
    }

    /// Trigger intelligence refresh on app becoming active
    @MainActor
    private func triggerAppActiveRefresh() async {
        let context = container.mainContext

        // Sync widget shared defaults
        SharedDefaults.updateNoteCount(UsageService.shared.noteCount)
        SharedDefaults.updateProStatus(UsageService.shared.isPro)

        // Fetch all required data
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<KanbanItem>())) ?? []
        let movements = (try? context.fetch(FetchDescriptor<KanbanMovement>())) ?? []
        let actions = (try? context.fetch(FetchDescriptor<ExtractedAction>())) ?? []
        let commitments = (try? context.fetch(FetchDescriptor<ExtractedCommitment>())) ?? []
        let unresolved = (try? context.fetch(FetchDescriptor<UnresolvedItem>())) ?? []

        // Update widget with latest note
        SharedDefaults.updateTotalNotes(notes.count)
        if let latestNote = notes.first {
            SharedDefaults.updateLastNote(
                preview: latestNote.displayTitle,
                date: latestNote.updatedAt,
                intent: latestNote.intentType
            )
        }
        WidgetCenter.shared.reloadAllTimelines()

        // Tier 2: Refresh session brief (local computation, no AI)
        await IntelligenceService.shared.refreshSessionBriefIfNeeded(
            notes: notes,
            projects: projects,
            items: items,
            movements: movements,
            actions: actions,
            commitments: commitments,
            unresolved: unresolved
        )

        // Tier 2.5: Recompile dirty knowledge articles (API calls, pro only)
        await KnowledgeCompiler.shared.recompileDirtyArticles(context: context)

        // Tier 3: Check and generate daily brief if needed (one AI call per day)
        await IntelligenceService.shared.checkAndGenerateDailyBrief(
            context: context,
            notes: notes,
            projects: projects,
            items: items,
            movements: movements,
            actions: actions,
            commitments: commitments,
            unresolved: unresolved
        )

        // Proactive alerts: scan and schedule notifications on foreground
        await runProactiveAlertScan(context: context)

        // Retry pending transcriptions
        let pendingNotes = notes.filter { $0.transcriptionStatus == "pending" && $0.audioFileName != nil }
        if !pendingNotes.isEmpty, let apiKey = APIKeys.openAI, !apiKey.isEmpty {
            let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []

            for note in pendingNotes {
                guard let audioURL = note.audioURL else { continue }

                do {
                    let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
                    let rawTranscript = try await service.transcribe(audioURL: audioURL)

                    // Clean filler words
                    let transcript: String
                    do {
                        transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
                    } catch {
                        transcript = rawTranscript
                    }

                    note.transcript = transcript
                    note.content = transcript
                    note.transcriptionStatus = "completed"
                    note.updatedAt = Date()
                    try? context.save()

                    // Run intelligence pipeline
                    let title = try? await SummaryService.generateTitle(for: transcript, apiKey: apiKey)
                    if let title = title {
                        note.title = title
                    }

                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: transcript,
                        projects: projects,
                        tags: tags,
                        context: context
                    )

                    // Generate embedding for semantic search (non-blocking, failure-tolerant)
                    Task {
                        await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                    }

                    // Update widget
                    SharedDefaults.updateLastNote(
                        preview: note.displayTitle,
                        date: note.updatedAt,
                        intent: note.intentType
                    )
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    // Still offline or API error — leave as pending, will retry next time
                    continue
                }
            }
        }
    }

    // MARK: - Proactive Alerts

    /// Run proactive alert scan and schedule notifications (foreground)
    @MainActor
    private func runProactiveAlertScan(context: ModelContext) async {
        let alertService = ProactiveAlertService.shared
        guard alertService.shouldScan else { return }

        // Request notification permission naturally after 3rd note
        await NotificationScheduler.shared.requestPermissionIfReady()

        let alerts = alertService.generateAlerts(using: context)
        alertService.recordScan()

        guard !alerts.isEmpty else { return }
        await NotificationScheduler.shared.scheduleAlerts(alerts)

        // Also ensure daily brief reminder is scheduled if enabled
        let briefEnabled = UserDefaults.standard.object(forKey: "dailyBriefEnabled") as? Bool ?? true
        if briefEnabled {
            let hour = NotificationScheduler.shared.dailyBriefHour
            let minute = NotificationScheduler.shared.dailyBriefMinute
            await NotificationScheduler.shared.scheduleDailyBriefReminder(at: hour, minute: minute)
        }

        // Schedule next background task
        scheduleProactiveAlertsBackgroundTask()
    }

    /// Handle the BGAppRefresh task for proactive alerts
    private func handleProactiveAlertsBackgroundTask() async {
        let context = ModelContext(container)
        let alertService = ProactiveAlertService.shared
        let alerts = alertService.generateAlerts(using: context)
        alertService.recordScan()

        if !alerts.isEmpty {
            await NotificationScheduler.shared.scheduleAlerts(alerts)
        }

        // Re-schedule for tomorrow
        scheduleProactiveAlertsBackgroundTask()
    }

    /// Schedule a background app refresh task for the next day
    private func scheduleProactiveAlertsBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: voice_notesApp.proactiveAlertsTaskId)
        // Run once per day — earliest: 6 hours from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[ProactiveAlerts] Failed to schedule background task: \(error)")
        }
    }

    /// Removes duplicate tags, keeping one of each name and updating note references
    private func cleanupDuplicateTags(in context: ModelContext) {
        do {
            let allTags = try context.fetch(FetchDescriptor<Tag>())

            // Group tags by lowercase name
            var tagsByName: [String: [Tag]] = [:]
            for tag in allTags {
                let key = tag.name.lowercased()
                tagsByName[key, default: []].append(tag)
            }

            // For each group with duplicates, keep the first and merge others
            for (_, tags) in tagsByName where tags.count > 1 {
                let tagToKeep = tags[0]
                let duplicates = tags.dropFirst()

                for duplicate in duplicates {
                    // Move all notes from duplicate to the kept tag
                    for note in duplicate.notes ?? [] {
                        if !(tagToKeep.notes ?? []).contains(where: { $0.id == note.id }) {
                            var keepNotes = tagToKeep.notes ?? []
                            keepNotes.append(note)
                            tagToKeep.notes = keepNotes
                        }
                        note.tags.removeAll { $0.id == duplicate.id }
                        if !note.tags.contains(where: { $0.id == tagToKeep.id }) {
                            note.tags.append(tagToKeep)
                        }
                    }
                    // Delete the duplicate
                    context.delete(duplicate)
                }
            }

            try context.save()
        } catch {
            print("Tag cleanup failed: \(error)")
        }
    }
}
