//
//  PeopleView.swift
//  voice notes
//
//  People Tracker: View all mentioned people and their commitments

import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var people: [MentionedPerson]

    @State private var searchText = ""
    @State private var showArchived = false

    private var filteredPeople: [MentionedPerson] {
        var result = people.filter { showArchived || !$0.isArchived }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if filteredPeople.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.crop.square.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("No people yet")
                            .font(.headline)
                            .foregroundStyle(.gray)
                        Text("When you mention names in your notes,\nthey'll appear here automatically")
                            .font(.subheadline)
                            .foregroundStyle(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        ForEach(filteredPeople) { person in
                            NavigationLink(destination: PersonDetailView(person: person)) {
                                PersonRow(person: person)
                            }
                            .listRowBackground(Color(.systemGray6).opacity(0.2))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    person.isArchived.toggle()
                                } label: {
                                    Label(
                                        person.isArchived ? "Unarchive" : "Archive",
                                        systemImage: person.isArchived ? "tray.and.arrow.up" : "archivebox"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("People")
            .searchable(text: $searchText, prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle(isOn: $showArchived) {
                            Label("Show Archived", systemImage: "archivebox")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Person Row

struct PersonRow: View {
    let person: MentionedPerson

    var body: some View {
        HStack(spacing: 16) {
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
                    .frame(width: 48, height: 48)

                Text(person.initials)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Label("\(person.mentionCount)", systemImage: "quote.bubble")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    if person.openCommitmentCount > 0 {
                        Label("\(person.openCommitmentCount) open", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if person.isArchived {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Person Detail View

struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var person: MentionedPerson
    @Query private var allCommitments: [ExtractedCommitment]
    @Query private var allNotes: [Note]

    private var personCommitments: [ExtractedCommitment] {
        allCommitments.filter { $0.personName == person.normalizedName }
    }

    private var openCommitments: [ExtractedCommitment] {
        personCommitments.filter { !$0.isCompleted }
    }

    private var completedCommitments: [ExtractedCommitment] {
        personCommitments.filter { $0.isCompleted }
    }

    private var relatedNotes: [Note] {
        allNotes.filter { $0.mentionedPeople.contains { MentionedPerson.normalize($0) == person.normalizedName } }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)

                            Text(person.initials)
                                .font(.largeTitle.weight(.semibold))
                                .foregroundStyle(.white)
                        }

                        Text(person.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    // Stats
                    HStack(spacing: 24) {
                        StatItem(value: "\(person.mentionCount)", label: "Mentions", icon: "quote.bubble")
                        StatItem(value: "\(openCommitments.count)", label: "Open", icon: "circle", color: .orange)
                        StatItem(value: "\(completedCommitments.count)", label: "Done", icon: "checkmark.circle.fill", color: .green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)

                    // First/last seen
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("First mentioned")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Spacer()
                            Text(person.firstMentionedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        HStack {
                            Text("Last mentioned")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Spacer()
                            Text(person.lastMentionedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)

                    // Open Commitments
                    if !openCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Open Commitments")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ForEach(openCommitments) { commitment in
                                PersonCommitmentRow(commitment: commitment) {
                                    commitment.isCompleted = true
                                    person.openCommitmentCount = max(0, person.openCommitmentCount - 1)
                                }
                            }
                        }
                    }

                    // Completed Commitments
                    if !completedCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completed")
                                .font(.headline)
                                .foregroundStyle(.gray)

                            ForEach(completedCommitments.prefix(5)) { commitment in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(commitment.what)
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                        .strikethrough()
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6).opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }

                    // Related Notes
                    if !relatedNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Related Notes (\(relatedNotes.count))")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ForEach(relatedNotes.prefix(5)) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    HStack {
                                        Image(systemName: "note.text")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(note.displayTitle)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6).opacity(0.3))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PersonCommitmentRow: View {
    let commitment: ExtractedCommitment
    let onComplete: () -> Void

    var body: some View {
        HStack {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            Text(commitment.what)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(8)
    }
}

#Preview {
    PeopleView()
        .modelContainer(for: [MentionedPerson.self, ExtractedCommitment.self, Note.self], inMemory: true)
}
