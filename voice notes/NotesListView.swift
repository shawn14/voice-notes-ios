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
    @State private var pulseAnimation = false

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
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 60)

                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.red.opacity(0.3))

                                Text("No Notes Yet")
                                    .font(.title2.bold())
                                    .foregroundStyle(.secondary)

                                Text("Tap the record button to start")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)

                                // Arrow pointing down to record button
                                Image(systemName: "arrow.down")
                                    .font(.title)
                                    .foregroundStyle(.red.opacity(0.5))
                                    .padding(.top, 20)
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
                            .padding(.bottom, 100) // Space for floating button
                        }
                    }
                    .padding(.top)
                }

                // Floating Record Button
                VStack {
                    Spacer()

                    HStack {
                        // Text note button (smaller, left side)
                        Button(action: { showingNewNote = true }) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(Color(.systemGray))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }

                        Spacer()

                        // Big Record Button (center focus)
                        Button(action: { showingRecording = true }) {
                            ZStack {
                                // Outer pulse ring
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 90, height: 90)
                                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                    .opacity(pulseAnimation ? 0 : 0.6)

                                // Middle ring
                                Circle()
                                    .fill(Color.red.opacity(0.3))
                                    .frame(width: 80, height: 80)

                                // Main button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.red, Color(red: 0.8, green: 0, blue: 0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 70, height: 70)
                                    .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)

                                // Mic icon
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                pulseAnimation = true
                            }
                        }

                        Spacer()

                        // Placeholder for balance (invisible)
                        Color.clear
                            .frame(width: 50, height: 50)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                }
            }
            .searchable(text: $searchText, prompt: "Search notes")
            .navigationTitle("Voice Notes")
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
