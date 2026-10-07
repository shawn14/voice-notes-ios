//
//  RecentlyDeletedView.swift
//  voice notes
//
//  Library → Recently Deleted. Restore, delete now, or delete all.
//  Storage and the 30-day purge live in NoteTrash.swift.
//

import SwiftUI
import SwiftData

struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var entries: [TrashedNote] = []
    @State private var pendingDelete: TrashedNote?
    @State private var showingDeleteAllConfirm = false
    @State private var showingPaywall = false

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted Notes",
                    systemImage: "trash",
                    description: Text("Deleted notes stay here for 30 days, then they're removed for good.")
                )
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    restore(entry)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.eeonAccentAI)
                            }
                    }
                } footer: {
                    Text("Notes are removed for good after 30 days. Only notes deleted on this device appear here.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete All", role: .destructive) {
                        showingDeleteAllConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "Delete this note for good?",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = pendingDelete {
                    NoteTrash.deleteForever(entry.id)
                    reload()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The note and its recording will be removed. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete all \(entries.count) notes for good?",
            isPresented: $showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                NoteTrash.deleteAll()
                reload()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("These notes and their recordings will be removed. This cannot be undone.")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(onDismiss: { showingPaywall = false })
        }
        .onAppear(perform: reload)
    }

    private func row(_ entry: TrashedNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.hasAudio ? "waveform" : "doc.text")
                .foregroundStyle(.eeonTextSecondary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? "Untitled note" : entry.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                if !entry.preview.isEmpty, entry.preview != entry.title {
                    Text(entry.preview)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextSecondary)
                        .lineLimit(2)
                }
                Text(entry.daysLeft == 1 ? "1 day left" : "\(entry.daysLeft) days left")
                    .font(.caption)
                    .foregroundStyle(.eeonTextTertiary)
            }

            Spacer(minLength: 8)

            Button("Restore") { restore(entry) }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                .foregroundStyle(.eeonAccentAI)
        }
        .padding(.vertical, 4)
    }

    private func restore(_ entry: TrashedNote) {
        // A restored note counts toward the free limit again. Recount first:
        // deletes don't decrement the counter, so it can be stale here.
        let liveCount = (try? modelContext.fetchCount(FetchDescriptor<Note>(predicate: #Predicate { !$0.isArchived }))) ?? 0
        UsageService.shared.syncNoteCount(actualCount: liveCount)
        guard UsageService.shared.canCreateNote else {
            showingPaywall = true
            return
        }
        if NoteTrash.restore(entry.id, context: modelContext) != nil {
            UsageService.shared.incrementNoteCount()
        }
        reload()
    }

    private func reload() {
        entries = NoteTrash.entries()
    }
}
