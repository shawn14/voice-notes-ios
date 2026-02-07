//
//  voice_notesApp.swift
//  voice notes
//
//  Created by Shawn Carpenter on 1/24/26.
//

import SwiftUI
import SwiftData

@main
struct voice_notesApp: App {
    let container: ModelContainer
    @State private var authService = AuthService.shared
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var hasSeenOnboardingPaywall = UserDefaults.standard.bool(forKey: "hasSeenOnboardingPaywall")
    @State private var isSignedInDuringOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    // Shared note handling
    @State private var sharedNoteToShow: SharedNote?
    @State private var showingSharedNote = false
    @State private var sharedNoteError: String?
    @State private var showingSharedNoteError = false

    init() {
        let schema = Schema([Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self, Project.self, DailyBrief.self, ExtractedURL.self, MentionedPerson.self])

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
                // Last resort - delete store and recreate
                print("Migration failed, recreating store: \(error)")

                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                let url = config.url
                try? FileManager.default.removeItem(at: url)

                do {
                    container = try ModelContainer(for: schema)
                } catch {
                    fatalError("Failed to create ModelContainer: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    AIHomeView()
                        .task {
                            // Check if Apple ID credential is still valid
                            await authService.checkCredentialState()
                            // Check subscription status
                            await subscriptionManager.updateSubscriptionStatus()
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                Task {
                                    await triggerAppActiveRefresh()
                                }
                            }
                        }
                } else if isSignedInDuringOnboarding || hasSeenOnboardingPaywall {
                    // Step 2: Show onboarding paywall after sign-in
                    OnboardingPaywallView {
                        // Complete onboarding (whether they subscribed or skipped)
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboardingPaywall")
                        hasCompletedOnboarding = true
                        hasSeenOnboardingPaywall = true
                    }
                } else {
                    // Step 1: Sign in first
                    SignInView {
                        // Move to paywall step instead of completing onboarding
                        isSignedInDuringOnboarding = true
                    }
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .sheet(isPresented: $showingSharedNote) {
                if let note = sharedNoteToShow {
                    SharedNoteDetailView(sharedNote: note)
                }
            }
            .alert("Couldn't Open Link", isPresented: $showingSharedNoteError) {
                Button("OK") { }
            } message: {
                Text(sharedNoteError ?? "Unknown error")
            }
        }
        .modelContainer(container)
    }

    private func handleIncomingURL(_ url: URL) {
        // Handle voicenotes://share/{id}
        guard url.scheme == "voicenotes",
              url.host == "share",
              let noteId = url.pathComponents.last, !noteId.isEmpty else {
            return
        }

        Task {
            do {
                if let note = try await CloudKitShareService.shared.fetchSharedNote(id: noteId) {
                    await MainActor.run {
                        sharedNoteToShow = note
                        showingSharedNote = true
                    }
                } else {
                    await MainActor.run {
                        sharedNoteError = "This note has expired or been deleted."
                        showingSharedNoteError = true
                    }
                }
            } catch {
                await MainActor.run {
                    sharedNoteError = "Couldn't load the shared note: \(error.localizedDescription)"
                    showingSharedNoteError = true
                }
            }
        }
    }

    /// Trigger intelligence refresh on app becoming active
    @MainActor
    private func triggerAppActiveRefresh() async {
        let context = container.mainContext

        // Fetch all required data
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<KanbanItem>())) ?? []
        let movements = (try? context.fetch(FetchDescriptor<KanbanMovement>())) ?? []
        let actions = (try? context.fetch(FetchDescriptor<ExtractedAction>())) ?? []
        let commitments = (try? context.fetch(FetchDescriptor<ExtractedCommitment>())) ?? []
        let unresolved = (try? context.fetch(FetchDescriptor<UnresolvedItem>())) ?? []

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
