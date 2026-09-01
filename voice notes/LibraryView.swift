//
//  LibraryView.swift
//  voice notes
//
//  Apple-style note retrieval surface: search first, smart collections second,
//  raw chronological browsing only after the user deliberately opens Recent.
//

import SwiftUI
import SwiftData

enum LibraryCollectionKind: String, CaseIterable, Identifiable {
    case recent
    case projects
    case people
    case topics
    case favorites
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .projects: return "Projects"
        case .people: return "People"
        case .topics: return "Topics"
        case .favorites: return "Favorites"
        case .archive: return "Archive"
        }
    }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .projects: return "folder"
        case .people: return "person.2"
        case .topics: return "tag"
        case .favorites: return "heart"
        case .archive: return "archivebox"
        }
    }

    var tint: Color {
        switch self {
        case .recent: return .eeonAccent
        case .projects: return .blue
        case .people: return .green
        case .topics: return .orange
        case .favorites: return .pink
        case .archive: return .gray
        }
    }
}

struct LibraryCollectionSummary: Identifiable {
    let kind: LibraryCollectionKind
    let title: String
    let subtitle: String
    let count: Int

    var id: String { kind.rawValue }
}

struct LibraryView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var searchQuery = ""

    private var visibleNotes: [Note] {
        libraryVisibleNotes(notes)
    }

    private var searchResults: [Note] {
        NoteKeywordSearch.match(query: activeSearchQuery, in: librarySearchableNotes(notes))
    }

    private var activeSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !activeSearchQuery.isEmpty
    }

    private var summaries: [LibraryCollectionSummary] {
        libraryCollectionSummaries(
            notes: notes,
            projects: projects
        )
    }

    private var collectionSummaries: [LibraryCollectionSummary] {
        summaries.filter { $0.kind != .recent }
    }

    var body: some View {
        List {
            if isSearching {
                if searchResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No notes match that search.")
                    )
                } else {
                    Section(searchResults.count == 1 ? "1 Result" : "\(searchResults.count) Results") {
                        ForEach(searchResults) { note in
                            LibraryNoteListRow(note: note)
                        }
                    }
                }
            } else if librarySearchableNotes(notes).isEmpty {
                ContentUnavailableView(
                    "No Library Yet",
                    systemImage: "waveform.circle",
                    description: Text("Record your first note to start your library.")
                )
            } else {
                if !visibleNotes.isEmpty {
                    Section("Recent") {
                        ForEach(Array(visibleNotes.prefix(12))) { note in
                            LibraryNoteListRow(note: note)
                        }

                        if visibleNotes.count > 12 {
                            NavigationLink(destination: LibraryCollectionView(kind: .recent)) {
                                Label("All Recent", systemImage: "clock")
                            }
                        }
                    }
                }

                if !collectionSummaries.isEmpty {
                    Section("Collections") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: EEONLayout.snug) {
                                ForEach(collectionSummaries) { summary in
                                    NavigationLink(destination: LibraryCollectionView(kind: summary.kind)) {
                                        LibraryCollectionSummaryCard(summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Library")
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }

}

struct LibraryCollectionView: View {
    let kind: LibraryCollectionKind

    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var articles: [KnowledgeArticle]
    @Query(sort: \MentionedPerson.lastMentionedAt, order: .reverse) private var people: [MentionedPerson]

    private var baseNotes: [Note] {
        switch kind {
        case .recent:
            return libraryVisibleNotes(notes)
        case .favorites:
            return libraryVisibleNotes(notes).filter { $0.isFavorite }
        case .archive:
            return libraryArchivedNotes(notes)
        case .projects:
            return flattenedNotes(projectGroups)
        case .people:
            return flattenedNotes(peopleGroups)
        case .topics:
            return flattenedNotes(topicGroups)
        }
    }

    var body: some View {
        List {
            content
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .recent, .favorites, .archive:
            if baseNotes.isEmpty {
                ContentUnavailableView(
                    "Nothing Here",
                    systemImage: kind.icon,
                    description: Text("This collection has no notes yet.")
                )
            } else {
                LibraryNoteSections(notes: baseNotes)
            }
        case .projects:
            namedCollectionSections(projectGroups)
        case .people:
            namedCollectionSections(peopleGroups)
        case .topics:
            namedCollectionSections(topicGroups)
        }
    }

    private var projectGroups: [LibraryNamedNoteGroup] {
        let visibleProjects = libraryVisibleProjects(projects)
        let projectLookup = Dictionary(uniqueKeysWithValues: visibleProjects.map { ($0.id, $0) })
        var buckets: [String: (name: String, notes: [Note])] = [:]

        for note in libraryVisibleNotes(notes) {
            let displayName: String?
            if let projectId = note.projectId,
               let project = projectLookup[projectId],
               !project.name.isEmpty {
                displayName = project.name
            } else if let inferred = note.inferredProjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !inferred.isEmpty,
                      !libraryIsSchemaSeedName(inferred) {
                displayName = inferred
            } else {
                displayName = nil
            }

            guard let displayName else { continue }
            let key = libraryNormalized(displayName)
            guard !key.isEmpty else { continue }
            var bucket = buckets[key] ?? (displayName, [])
            bucket.notes.append(note)
            buckets[key] = bucket
        }

        return buckets.values.map { bucket in
            LibraryNamedNoteGroup(
                id: "project-\(libraryNormalized(bucket.name))",
                title: bucket.name,
                subtitle: libraryNoteCountLabel(bucket.notes.count),
                icon: "folder",
                tint: .blue,
                notes: bucket.notes.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        .sorted(by: libraryGroupSort)
    }

    private var peopleGroups: [LibraryNamedNoteGroup] {
        var buckets: [String: (name: String, notes: [Note])] = [:]

        for person in libraryVisiblePeople(people) {
            let key = libraryNormalized(person.displayName)
            guard !key.isEmpty else { continue }
            buckets[key] = (person.displayName, [])
        }

        for note in libraryVisibleNotes(notes) {
            let names = Set(note.mentionedPeople.map(libraryNormalized).filter { !$0.isEmpty && !libraryIsSchemaSeedName($0) })
            for key in names {
                let displayName = libraryVisiblePeople(people).first(where: { libraryNormalized($0.displayName) == key })?.displayName
                    ?? note.mentionedPeople.first(where: { libraryNormalized($0) == key })
                    ?? key.capitalized
                var bucket = buckets[key] ?? (displayName, [])
                bucket.notes.append(note)
                buckets[key] = bucket
            }
        }

        return buckets.values
            .filter { !$0.notes.isEmpty }
            .map { bucket in
                LibraryNamedNoteGroup(
                    id: "person-\(libraryNormalized(bucket.name))",
                    title: bucket.name,
                    subtitle: libraryNoteCountLabel(bucket.notes.count),
                    icon: "person",
                    tint: .green,
                    notes: bucket.notes.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted(by: libraryGroupSort)
    }

    private var topicGroups: [LibraryNamedNoteGroup] {
        var buckets: [String: (name: String, notes: [Note])] = [:]

        let visibleArticles = libraryVisibleArticles(articles)
        for article in visibleArticles where article.articleType == .topic || article.articleType == .reference {
            let key = libraryNormalized(article.name)
            guard !key.isEmpty else { continue }
            buckets[key] = (article.name, [])
        }

        for note in libraryVisibleNotes(notes) {
            let topics = Set(note.topics.map(libraryNormalized).filter { !$0.isEmpty && !libraryIsSchemaSeedName($0) })
            for key in topics {
                let displayName = visibleArticles.first(where: { libraryNormalized($0.name) == key })?.name
                    ?? note.topics.first(where: { libraryNormalized($0) == key })
                    ?? key.capitalized
                var bucket = buckets[key] ?? (displayName, [])
                bucket.notes.append(note)
                buckets[key] = bucket
            }
        }

        return buckets.values
            .filter { !$0.notes.isEmpty }
            .map { bucket in
                LibraryNamedNoteGroup(
                    id: "topic-\(libraryNormalized(bucket.name))",
                    title: bucket.name,
                    subtitle: libraryNoteCountLabel(bucket.notes.count),
                    icon: "tag",
                    tint: .orange,
                    notes: bucket.notes.sorted { $0.updatedAt > $1.updatedAt }
                )
            }
            .sorted(by: libraryGroupSort)
    }

    @ViewBuilder
    private func namedCollectionSections(_ groups: [LibraryNamedNoteGroup]) -> some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "Nothing Here",
                systemImage: kind.icon,
                description: Text("This collection has no notes yet.")
            )
        } else {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: EEONLayout.snug) {
                        ForEach(groups) { group in
                            NavigationLink(destination: LibraryFilteredNotesView(title: group.title, notes: group.notes)) {
                                LibraryNamedCollectionCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func flattenedNotes(_ groups: [LibraryNamedNoteGroup]) -> [Note] {
        var seen = Set<UUID>()
        return groups
            .flatMap { $0.notes }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct LibraryFilteredNotesView: View {
    let title: String
    let notes: [Note]

    private var visibleNotes: [Note] {
        libraryVisibleNotes(notes)
    }

    var body: some View {
        List {
            if visibleNotes.isEmpty {
                ContentUnavailableView(
                    "Nothing Here",
                    systemImage: "doc.text",
                    description: Text("This collection has no notes yet.")
                )
            } else {
                LibraryNoteSections(notes: visibleNotes)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

private struct LibraryNoteSections: View {
    let notes: [Note]

    var body: some View {
        ForEach(libraryMonthGroups(notes), id: \.0) { month, monthNotes in
            Section(month) {
                ForEach(monthNotes) { note in
                    LibraryNoteListRow(note: note)
                }
            }
        }
    }

}

/// One Library note row: tap to open, swipe or long-press for favorite /
/// archive / delete. Delete always confirms first ("Delete Note?", same as
/// NoteDetailView) — a full swipe must never destroy a note and its audio.
private struct LibraryNoteListRow: View {
    @Environment(\.modelContext) private var modelContext

    let note: Note

    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationLink(destination: NoteDetailView(note: note)) {
            LibraryNoteRow(note: note)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                note.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(note.isFavorite ? "Unfavorite" : "Favorite", systemImage: note.isFavorite ? "heart.slash" : "heart.fill")
            }

            Button {
                withAnimation {
                    note.isArchived.toggle()
                    try? modelContext.save()
                }
            } label: {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
            }

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete Note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func deleteNote() {
        withAnimation(.easeInOut(duration: 0.2)) {
            note.deleteAudioFile()
            note.deleteImageFiles()
            modelContext.delete(note)
            try? modelContext.save()
        }
    }
}

private struct LibraryCollectionListRow: View {
    let summary: LibraryCollectionSummary

    var body: some View {
        HStack(spacing: EEONLayout.standard) {
            Image(systemName: summary.kind.icon)
                .font(EEONType.body)
                .foregroundStyle(summary.kind.tint)
                .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
                .background(Circle().fill(summary.kind.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(EEONType.body)
                    .foregroundStyle(.eeonTextPrimary)
                Text(summary.subtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LibraryCollectionSummaryCard: View {
    let summary: LibraryCollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: summary.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(summary.kind.tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(summary.kind.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(summary.subtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 86, alignment: .leading)
        .padding(12)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }
}

private struct LibraryNamedCollectionRow: View {
    let group: LibraryNamedNoteGroup

    var body: some View {
        HStack(spacing: EEONLayout.standard) {
            Image(systemName: group.icon)
                .font(EEONType.body)
                .foregroundStyle(group.tint)
                .frame(width: EEONLayout.minTarget, height: EEONLayout.minTarget)
                .background(Circle().fill(group.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(EEONType.body)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(group.subtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LibraryNamedCollectionCard: View {
    let group: LibraryNamedNoteGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: group.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(group.tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(group.tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text(group.subtitle)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 176, alignment: .leading)
        .frame(minHeight: 108, alignment: .leading)
        .padding(12)
        .background(Color.eeonCard)
        .clipShape(RoundedRectangle(cornerRadius: EEONLayout.cardRadius))
    }
}

private struct LibraryNoteRow: View {
    let note: Note

    private var meta: String {
        var parts = [note.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let seconds = note.audioDuration, seconds > 0 {
            parts.append(NoteFeedCard.durationText(seconds))
        }
        if let topic = note.topics.first, !topic.isEmpty {
            parts.append(topic.capitalized)
        }
        return parts.joined(separator: " - ")
    }

    private var preview: String {
        if let transcript = note.transcript, !transcript.isEmpty {
            return String((transcript.components(separatedBy: .newlines).first ?? transcript).prefix(90))
        }
        if !note.content.isEmpty {
            return String((note.content.components(separatedBy: .newlines).first ?? note.content).prefix(90))
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(EEONType.body)
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(meta)
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextSecondary)

            if !preview.isEmpty {
                Text(preview)
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LibraryNamedNoteGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let notes: [Note]
}

func libraryCollectionSummaries(
    notes: [Note],
    projects: [Project]
) -> [LibraryCollectionSummary] {
    let visible = libraryVisibleNotes(notes)
    let archived = libraryArchivedNotes(notes)
    let favorites = visible.filter { $0.isFavorite }
    let visibleProjects = libraryVisibleProjects(projects)
    let projectLookup = Dictionary(uniqueKeysWithValues: visibleProjects.map { ($0.id, $0) })

    let projectNames = Set(visible.compactMap { note -> String? in
        if let projectId = note.projectId,
           let project = projectLookup[projectId],
           !project.name.isEmpty {
            return libraryNormalized(project.name)
        }
        if let inferred = note.inferredProjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inferred.isEmpty,
           !libraryIsSchemaSeedName(inferred) {
            return libraryNormalized(inferred)
        }
        return nil
    }.filter { !$0.isEmpty })
    let projectCount = projectNames.count

    let peopleNames = Set(visible.flatMap { $0.mentionedPeople }.map(libraryNormalized).filter { !$0.isEmpty && !libraryIsSchemaSeedName($0) })
    let peopleCount = peopleNames.count

    let topicNames = Set(visible.flatMap { $0.topics }.map(libraryNormalized).filter { !$0.isEmpty && !libraryIsSchemaSeedName($0) })
    let topicCount = topicNames.count

    var out: [LibraryCollectionSummary] = [
        LibraryCollectionSummary(kind: .recent, title: "Recent", subtitle: libraryNoteCountLabel(visible.count), count: visible.count)
    ]

    if projectCount > 0 {
        out.append(LibraryCollectionSummary(kind: .projects, title: "Projects", subtitle: libraryItemCountLabel(projectCount, singular: "project"), count: projectCount))
    }
    if peopleCount > 0 {
        out.append(LibraryCollectionSummary(kind: .people, title: "People", subtitle: libraryItemCountLabel(peopleCount, singular: "person"), count: peopleCount))
    }
    if topicCount > 0 {
        out.append(LibraryCollectionSummary(kind: .topics, title: "Topics", subtitle: libraryItemCountLabel(topicCount, singular: "topic"), count: topicCount))
    }
    if !favorites.isEmpty {
        out.append(LibraryCollectionSummary(kind: .favorites, title: "Favorites", subtitle: libraryNoteCountLabel(favorites.count), count: favorites.count))
    }
    if !archived.isEmpty {
        out.append(LibraryCollectionSummary(kind: .archive, title: "Archive", subtitle: libraryNoteCountLabel(archived.count), count: archived.count))
    }

    return out
}

func librarySearchableNotes(_ notes: [Note]) -> [Note] {
    notes.filter {
        $0.sourceType != .profileSeed && $0.sourceType != .purposeSeed
        && !libraryIsSchemaSeedName($0.title)
        && !libraryIsSchemaSeedName($0.content)
    }
}

func libraryVisibleNotes(_ notes: [Note]) -> [Note] {
    librarySearchableNotes(notes).filter { !$0.isArchived }
}

func libraryArchivedNotes(_ notes: [Note]) -> [Note] {
    librarySearchableNotes(notes).filter { $0.isArchived }
}

func libraryVisibleProjects(_ projects: [Project]) -> [Project] {
    projects.filter { !$0.isArchived && !libraryIsSchemaSeedName($0.name) }
}

func libraryVisibleArticles(_ articles: [KnowledgeArticle]) -> [KnowledgeArticle] {
    articles.filter { !libraryIsSchemaSeedName($0.name) }
}

func libraryVisiblePeople(_ people: [MentionedPerson]) -> [MentionedPerson] {
    people.filter { !$0.isArchived && !libraryIsSchemaSeedName($0.displayName) }
}

nonisolated func libraryIsSchemaSeedName(_ raw: String) -> Bool {
    let trimmed = libraryNormalized(raw)
    guard !trimmed.isEmpty else { return false }
    if trimmed.contains("__seed") { return true }

    let readable = trimmed
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
    return readable == "seed" || readable == "schema seed"
}

func libraryNoteCountLabel(_ count: Int) -> String {
    count == 1 ? "1 note" : "\(count) notes"
}

func libraryItemCountLabel(_ count: Int, singular: String) -> String {
    count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
}

nonisolated func libraryNormalized(_ value: String) -> String {
    value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}

private func libraryMonthGroups(_ notes: [Note]) -> [(String, [Note])] {
    Dictionary(grouping: notes) { libraryMonthLabel($0.updatedAt) }
        .map { label, groupedNotes in
            (label, groupedNotes.sorted { $0.updatedAt > $1.updatedAt })
        }
        .sorted {
            ($0.1.first?.updatedAt ?? .distantPast) > ($1.1.first?.updatedAt ?? .distantPast)
        }
}

private func libraryMonthLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }

    let formatter = DateFormatter()
    if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
        formatter.dateFormat = "MMMM"
    } else {
        formatter.dateFormat = "MMMM yyyy"
    }
    return formatter.string(from: date)
}

private func libraryGroupSort(_ lhs: LibraryNamedNoteGroup, _ rhs: LibraryNamedNoteGroup) -> Bool {
    if lhs.notes.count != rhs.notes.count {
        return lhs.notes.count > rhs.notes.count
    }
    return (lhs.notes.first?.updatedAt ?? .distantPast) > (rhs.notes.first?.updatedAt ?? .distantPast)
}
