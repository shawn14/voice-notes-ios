//
//  AITabView.swift
//  voice notes
//
//  Renders the AI-organized view of notes — all computed locally from SwiftData metadata.
//

import SwiftUI
import SwiftData

struct AITabView: View {
    let data: AITabData
    let noteCount: Int

    var body: some View {
        if noteCount < 5 {
            emptyState
        } else if data.totalItemCount == 0 {
            allClearState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Needs Attention
                if !data.attentionItems.isEmpty {
                    attentionSection
                }

                // Active Threads
                if !data.activeThreads.isEmpty {
                    threadsSection
                }

                // People
                if !data.peopleSummaries.isEmpty {
                    peopleSection
                }

                // Recent Decisions
                if !data.recentDecisions.isEmpty {
                    decisionsSection
                }

                // Stale (collapsed by default)
                if !data.staleItems.isEmpty {
                    staleSection
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color("EEONAccent"), .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Almost there")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)

            Text("Record a few more notes and EEON will start connecting the dots.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private var allClearState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Nothing slipping through")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)

            Text("No overdue actions, no stale commitments. You're on top of it.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    // MARK: - Needs Attention

    private var attentionSection: some View {
        AITabSection(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Needs Attention",
            count: data.attentionItems.count,
            defaultExpanded: true
        ) {
            ForEach(data.attentionItems) { item in
                NavigationLink(destination: NoteByIdDestination(noteId: item.sourceNoteId ?? UUID())) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.type.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(colorForAIAttentionType(item.type))
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(.eeonTextPrimary)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text(item.type.rawValue)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(colorForAIAttentionType(item.type))

                                Text("\u{00B7}")
                                    .foregroundStyle(.eeonTextSecondary)

                                Text(item.sourceNoteTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextSecondary)
                                    .lineLimit(1)

                                if item.ageDays > 0 {
                                    Text("\u{00B7}")
                                        .foregroundStyle(.eeonTextSecondary)
                                    Text("\(item.ageDays)d ago")
                                        .font(.caption2)
                                        .foregroundStyle(.eeonTextSecondary)
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Active Threads

    private var threadsSection: some View {
        AITabSection(
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: .blue,
            title: "Active Threads",
            count: data.activeThreads.count,
            defaultExpanded: true
        ) {
            ForEach(data.activeThreads) { thread in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(thread.topic)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.eeonTextPrimary)

                        Spacer()

                        Text("\(thread.noteCount) notes")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextSecondary)
                    }

                    ForEach(thread.recentNotes, id: \.id) { noteRef in
                        NavigationLink(destination: NoteByIdDestination(noteId: noteRef.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.eeonAccentAI.opacity(0.4))
                                    .frame(width: 4, height: 4)

                                Text(noteRef.title)
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextSecondary)
                                    .lineLimit(1)

                                Spacer()

                                Text(relativeDate(noteRef.date))
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - People

    private var peopleSection: some View {
        AITabSection(
            icon: "person.2.fill",
            iconColor: .green,
            title: "People",
            count: data.peopleSummaries.count,
            defaultExpanded: true
        ) {
            ForEach(data.peopleSummaries) { person in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // Initials circle
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Text(initialsFor(person.name))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }

                        Text(person.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.eeonTextPrimary)

                        Spacer()

                        Text("\(person.openCommitmentCount) open")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }

                    if !person.commitments.isEmpty {
                        ForEach(Array(person.commitments.prefix(2).enumerated()), id: \.offset) { _, commitment in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.eeonTextSecondary)
                                Text(commitment)
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Recent Decisions

    private var decisionsSection: some View {
        AITabSection(
            icon: "checkmark.seal.fill",
            iconColor: .purple,
            title: "Recent Decisions",
            count: data.recentDecisions.count,
            defaultExpanded: true
        ) {
            ForEach(data.recentDecisions) { decision in
                NavigationLink(destination: NoteByIdDestination(noteId: decision.sourceNoteId ?? UUID())) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 13))
                            .foregroundStyle(.purple)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(decision.content)
                                .font(.subheadline)
                                .foregroundStyle(.eeonTextPrimary)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                if let affects = decision.affects {
                                    Text("Affects: \(affects)")
                                        .font(.caption2)
                                        .foregroundStyle(.purple.opacity(0.8))
                                        .lineLimit(1)

                                    Text("\u{00B7}")
                                        .foregroundStyle(.eeonTextSecondary)
                                }

                                Text(relativeDate(decision.date))
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextSecondary)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stale Items

    private var staleSection: some View {
        AITabSection(
            icon: "clock.badge.questionmark",
            iconColor: .yellow,
            title: "Going Stale",
            count: data.staleItems.count,
            defaultExpanded: false
        ) {
            ForEach(data.staleItems) { item in
                NavigationLink(destination: NoteByIdDestination(noteId: item.noteId)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow.opacity(0.7))
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.noteTitle)
                                .font(.subheadline)
                                .foregroundStyle(.eeonTextPrimary)
                                .lineLimit(1)

                            if let step = item.unresolvedStep {
                                Text(step)
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextTertiary)
                                    .lineLimit(1)
                            }

                            Text("\(item.ageDays) days without action")
                                .font(.caption2)
                                .foregroundStyle(.yellow.opacity(0.6))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func colorForAIAttentionType(_ type: AIAttentionType) -> Color {
        switch type {
        case .overdueAction: return .red
        case .urgentAction: return .orange
        case .staleCommitment: return .yellow
        case .unresolvedStep: return .purple
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func initialsFor(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first?.prefix(1) ?? "")\(parts.last?.prefix(1) ?? "")".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

}

// MARK: - Note Lookup Destination

/// Resolves a note by ID from SwiftData and navigates to NoteDetailView
struct NoteByIdDestination: View {
    let noteId: UUID
    @Query private var notes: [Note]

    init(noteId: UUID) {
        self.noteId = noteId
    }

    var body: some View {
        if let note = notes.first(where: { $0.id == noteId }) {
            NoteDetailView(note: note)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.eeonTextSecondary)
                Text("Note not found")
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
    }
}

// MARK: - Collapsible Section Component

struct AITabSection<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let defaultExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    init(
        icon: String,
        iconColor: Color,
        title: String,
        count: Int,
        defaultExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.count = count
        self.defaultExpanded = defaultExpanded
        self.content = content
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)

                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.eeonTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.eeonDivider)
                        .cornerRadius(4)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.eeonCard)
        )
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}
