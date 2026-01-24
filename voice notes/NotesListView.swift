//
//  NotesListView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var tags: [Tag]

    @State private var searchText = ""
    @State private var selectedTag: Tag?
    @State private var showingNewNote = false
    @State private var showingRecording = false

    let noteColors: [Color] = [
        Color(red: 1.0, green: 0.95, blue: 0.7),   // Yellow sticky
        Color(red: 1.0, green: 0.85, blue: 0.85),  // Pink sticky
        Color(red: 0.95, green: 0.95, blue: 0.9),  // Cream/white
        Color(red: 0.85, green: 0.9, blue: 1.0),   // Light blue
    ]

    var filteredNotes: [Note] {
        var result = notes

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                ($0.transcript?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Tag filter pills
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    TagPill(
                                        name: "All",
                                        isSelected: selectedTag == nil,
                                        action: { selectedTag = nil }
                                    )

                                    ForEach(tags) { tag in
                                        TagPill(
                                            name: tag.name,
                                            isSelected: selectedTag == tag,
                                            action: { selectedTag = tag }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Notes grid
                        if filteredNotes.isEmpty {
                            VStack(spacing: 16) {
                                Spacer()
                                    .frame(height: 100)
                                Image(systemName: "note.text")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("No Notes Yet")
                                    .font(.title2.bold())
                                    .foregroundStyle(.secondary)
                                Text("Tap + to create a note or start recording")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(filteredNotes.enumerated()), id: \.element.id) { index, note in
                                    NavigationLink(destination: NoteEditorView(note: note)) {
                                        StickyNoteCard(
                                            note: note,
                                            color: noteColors[index % noteColors.count]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteNote(note)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
            }
            .searchable(text: $searchText, prompt: "Search notes")
            .navigationTitle("Voice Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showingNewNote = true }) {
                            Label("New Text Note", systemImage: "square.and.pencil")
                        }
                        Button(action: { showingRecording = true }) {
                            Label("New Recording", systemImage: "mic.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $showingNewNote) {
                NavigationStack {
                    NoteEditorView(note: nil)
                }
            }
            .fullScreenCover(isPresented: $showingRecording) {
                RecordingView()
            }
        }
    }

    private func deleteNote(_ note: Note) {
        if let fileName = note.audioFileName {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(note)
    }
}

struct StickyNoteCard: View {
    let note: Note
    let color: Color

    @State private var rotation: Double = Double.random(in: -2...2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(note.displayTitle)
                .font(.system(.headline, design: .serif))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(.black.opacity(0.8))

            // Content preview
            if !note.content.isEmpty {
                Text(note.content)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(4)
            } else if let transcript = note.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.black.opacity(0.6))
                    .lineLimit(4)
            }

            Spacer()

            // Bottom row: date + audio indicator
            HStack {
                Text(note.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.black.opacity(0.4))

                Spacer()

                if note.hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.5))
                }
            }

            // Tags
            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(2)) { tag in
                        Text(tag.name)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.1))
                            .cornerRadius(4)
                    }
                    if note.tags.count > 2 {
                        Text("+\(note.tags.count - 2)")
                            .font(.system(size: 9))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
            }
        }
        .padding(12)
        .frame(minHeight: 150)
        .background(color)
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 2)
        .rotationEffect(.degrees(rotation))
    }
}

struct TagPill: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.red : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Note.self, Tag.self], inMemory: true)
}
