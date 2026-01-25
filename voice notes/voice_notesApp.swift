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
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    init() {
        let schema = Schema([Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self, Project.self])

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
            if hasCompletedOnboarding {
                HomeView()
                    .task {
                        // Check if Apple ID credential is still valid
                        await authService.checkCredentialState()
                    }
            } else {
                SignInView {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    hasCompletedOnboarding = true
                }
            }
        }
        .modelContainer(container)
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
