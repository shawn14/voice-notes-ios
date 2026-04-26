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
        let schema = Schema([Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self, Project.self, DailyBrief.self, ExtractedURL.self, MentionedPerson.self, KnowledgeArticle.self, KnowledgeEvent.self, DailyIntention.self])

        do {
            // Configure for CloudKit sync
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.aivoiceeeon")
            )

            container = try ModelContainer(for: schema, configurations: [config])
            UserDefaults.standard.set("cloudKit", forKey: "cloudKitInitOutcome")
            UserDefaults.standard.removeObject(forKey: "cloudKitInitError")
            UserDefaults.standard.set(Date(), forKey: "cloudKitInitAt")
            cleanupDuplicateTags(in: container.mainContext)
        } catch {
            // If CloudKit fails, try without CloudKit
            print("CloudKit container failed, trying local: \(error)")
            UserDefaults.standard.set("localFallback", forKey: "cloudKitInitOutcome")
            UserDefaults.standard.set(String(describing: error), forKey: "cloudKitInitError")
            UserDefaults.standard.set(Date(), forKey: "cloudKitInitAt")

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
                    UserDefaults.standard.set("recoveredCloudKit", forKey: "cloudKitInitOutcome")
                    print("Recovery succeeded — notes will re-sync from CloudKit")
                } catch {
                    // Absolute last resort — in-memory so app doesn't crash
                    print("All storage options failed, using in-memory: \(error)")
                    UserDefaults.standard.set("inMemory", forKey: "cloudKitInitOutcome")
                    UserDefaults.standard.set(String(describing: error), forKey: "cloudKitInitError")
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

        // Capture CloudKit setup/import/export events into a rolling log we
        // surface in Settings → CloudKit diagnostics. This is the only
        // user-visible window into why pushes are silently failing.
        CloudKitEventLog.register()

        // Prime ContextAssembler cache from compiled .self / .purpose articles.
        // Also runs the one-time eeonContext → .profileSeed migration if needed.
        // Capture container locally — escaping the closure would capture mutating self.
        let mainContext = container.mainContext
        Task { @MainActor in
            AuthService.shared.migrateEeonContextToSeedIfNeeded(context: mainContext)
            ContextAssembler.shared.refresh(from: mainContext)
        }

        #if DEBUG
        // CloudKit schema registration seed (v3 — one record at a time).
        //
        // v2 inserted all 16 records in a single save, which CloudKit
        // batched into one or two upload operations. Per-record validation
        // failures on a few types collapsed the whole batch and only
        // 8 of 16 record types ended up registered in Development —
        // missing CD_Project, CD_ExtractedDecision, CD_ExtractedCommitment,
        // CD_KanbanMovement, CD_WeeklyDebrief, CD_ExtractedURL,
        // CD_MentionedPerson, CD_DailyIntention. v2 also deleted everything
        // 90s later, cutting off NSPersistentCloudKitContainer's retry.
        //
        // v3 saves one type at a time with a delay between each so each
        // record gets its own upload operation, one failure can't take
        // down others, and the framework has time to push each record
        // before any cleanup.
        let seedKey = "cloudKitSchemaSeedDidRun_v3"
        if !UserDefaults.standard.bool(forKey: seedKey) {
            let seedContext = container.mainContext
            Task { @MainActor in
                let seedNote = Note(title: "__seed_v3", content: "")
                seedNote.sourceType = .profileSeed

                let seeds: [(model: any PersistentModel, name: String)] = [
                    (seedNote, "Note"),
                    (Tag(name: "__seed_tag_v3"), "Tag"),
                    (Project(name: "__seed_project_v3"), "Project"),
                    (ExtractedDecision(content: "__seed_v3"), "ExtractedDecision"),
                    (ExtractedAction(content: "__seed_v3"), "ExtractedAction"),
                    (ExtractedCommitment(who: "__seed", what: "__seed_v3"), "ExtractedCommitment"),
                    (UnresolvedItem(content: "__seed", reason: "__seed_v3"), "UnresolvedItem"),
                    (KanbanItem(content: "__seed_v3"), "KanbanItem"),
                    (KanbanMovement(itemId: UUID(), fromColumn: .thinking, toColumn: .decided), "KanbanMovement"),
                    (WeeklyDebrief(weekStartDate: Date()), "WeeklyDebrief"),
                    (DailyBrief(briefDate: Date()), "DailyBrief"),
                    (ExtractedURL(url: "https://example.invalid/seed"), "ExtractedURL"),
                    (MentionedPerson(name: "__seed_v3"), "MentionedPerson"),
                    (KnowledgeArticle(name: "__seed_v3", articleType: .topic), "KnowledgeArticle"),
                    (KnowledgeEvent(eventType: .ingest, title: "__seed_v3"), "KnowledgeEvent"),
                    (DailyIntention(dateKey: "__seed_v3", order: 0, content: "__seed"), "DailyIntention"),
                ]

                var inserted: [any PersistentModel] = []
                for entry in seeds {
                    seedContext.insert(entry.model)
                    inserted.append(entry.model)
                    do {
                        try seedContext.save()
                        print("[Schema v3] Saved \(entry.name)")
                    } catch {
                        print("[Schema v3] FAILED to save \(entry.name): \(error)")
                    }
                    // Per-record delay so each push gets its own CloudKit operation.
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                }

                print("[Schema v3] All \(seeds.count) types saved. Waiting 60s for any in-flight pushes to complete…")
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s buffer

                for seed in inserted { seedContext.delete(seed) }
                try? seedContext.save()

                UserDefaults.standard.set(true, forKey: seedKey)
                print("[Schema v3] Done. CloudKit Dashboard → Development → Record Types should now list all 16 CD_* types. Click Deploy Schema Changes… to promote to Production.")
            }
        }
        #endif
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
                case .needsPaywall, .needsSignIn:
                    OnboardingQuizView()
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

        // Process any pending ingests from share extension
        print("[App] triggerAppActiveRefresh called — checking pending ingests")
        let allProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let allTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        await IntelligenceService.shared.processPendingIngests(
            context: context,
            projects: allProjects,
            tags: allTags
        )

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
