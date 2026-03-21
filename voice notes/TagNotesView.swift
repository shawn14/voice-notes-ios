//
//  TagNotesView.swift
//  voice notes
//
//  Notes filtered by a specific tag
//

import SwiftUI
import SwiftData

struct TagNotesView: View {
    let tag: Tag

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    private var filteredNotes: [Note] {
        allNotes.filter { note in
            note.tags.contains { $0.id == tag.id }
        }
    }

    var body: some View {
        List {
            if filteredNotes.isEmpty {
                Text("No notes with this tag yet")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredNotes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("#\(tag.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
