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

    init() {
        do {
            container = try ModelContainer(for: Note.self, Tag.self)
            cleanupDuplicateTags(in: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NotesListView()
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
                    for note in duplicate.notes {
                        if !tagToKeep.notes.contains(where: { $0.id == note.id }) {
                            tagToKeep.notes.append(note)
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
