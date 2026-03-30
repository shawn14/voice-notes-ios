//
//  TagManagementSheet.swift
//  voice notes
//
//  Tag management sheet — view, add, rename, delete tags
//

import SwiftUI
import SwiftData

struct TagManagementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var notes: [Note]

    @State private var isEditing = false
    @State private var showingAddAlert = false
    @State private var newTagName = ""
    @State private var renamingTag: Tag?
    @State private var renameText = ""

    /// Built-in filter names (not real Tag objects)
    private let builtInFilters = ["All", "Archive"]

    /// Note count for a given tag
    private func noteCount(for tag: Tag) -> Int {
        (tag.notes ?? []).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Built-in filters
                    VStack(spacing: 0) {
                        ForEach(builtInFilters, id: \.self) { name in
                            HStack {
                                Image(systemName: name == "All" ? "tray.full" : "archivebox")
                                    .font(.body)
                                    .foregroundStyle(.gray)
                                    .frame(width: 28)

                                Text(name)
                                    .font(.body)
                                    .foregroundStyle(.white)

                                Spacer()

                                Text(builtInCount(for: name))
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)

                            Divider()
                                .background(Color.white.opacity(0.08))
                        }
                    }

                    // User tags
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tags) { tag in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: tag.colorHex) ?? .blue)
                                        .frame(width: 10, height: 10)

                                    if renamingTag?.id == tag.id {
                                        TextField("Tag name", text: $renameText)
                                            .font(.body)
                                            .foregroundStyle(.white)
                                            .textFieldStyle(.plain)
                                            .onSubmit {
                                                commitRename(tag: tag)
                                            }
                                    } else {
                                        Text(tag.name)
                                            .font(.body)
                                            .foregroundStyle(.white)
                                            .onTapGesture {
                                                if isEditing {
                                                    renamingTag = tag
                                                    renameText = tag.name
                                                }
                                            }
                                    }

                                    Spacer()

                                    Text("\(noteCount(for: tag))")
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)

                                    if isEditing {
                                        Button {
                                            deleteTag(tag)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)

                                Divider()
                                    .background(Color.white.opacity(0.08))
                            }
                        }
                    }

                    // Add tag button
                    Button {
                        showingAddAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Add a tag")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6).opacity(0.2))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            isEditing.toggle()
                            if !isEditing {
                                renamingTag = nil
                            }
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.gray)
                    }
                }
            }
            .alert("New Tag", isPresented: $showingAddAlert) {
                TextField("Tag name", text: $newTagName)
                Button("Add") {
                    addTag()
                }
                Button("Cancel", role: .cancel) {
                    newTagName = ""
                }
            } message: {
                Text("Enter a name for the new tag.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func builtInCount(for name: String) -> String {
        switch name {
        case "All":
            return "\(notes.filter { !$0.isArchived }.count)"
        case "Archive":
            return "\(notes.filter { $0.isArchived }.count)"
        default:
            return ""
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { newTagName = ""; return }
        // Avoid duplicates
        guard !tags.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { newTagName = ""; return }
        let tag = Tag(name: trimmed.capitalized)
        modelContext.insert(tag)
        try? modelContext.save()
        newTagName = ""
    }

    private func commitRename(tag: Tag) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            tag.name = trimmed
            try? modelContext.save()
        }
        renamingTag = nil
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
    }
}

// MARK: - Note Tag Picker Sheet (assign tags to a note)

struct NoteTagPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var note: Note
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var showingAddAlert = false
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Current tags on note
                        if !note.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CURRENT TAGS")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 20)

                                FlowLayout(spacing: 8) {
                                    ForEach(note.tags) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag.name)
                                                .font(.subheadline)
                                                .foregroundStyle(.blue)
                                            Button {
                                                removeTag(tag)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.gray)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.12))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.vertical, 16)

                            Divider()
                                .background(Color.white.opacity(0.08))
                        }

                        // AI-suggested topics
                        if !note.topics.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SUGGESTED FROM AI")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 20)

                                FlowLayout(spacing: 8) {
                                    ForEach(note.topics.filter { topic in
                                        !note.tags.contains(where: { $0.name.lowercased() == topic.lowercased() })
                                    }, id: \.self) { topic in
                                        Button {
                                            addOrCreateTag(name: topic)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus.circle")
                                                    .font(.caption2)
                                                Text(topic)
                                                    .font(.subheadline)
                                            }
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.vertical, 16)

                            Divider()
                                .background(Color.white.opacity(0.08))
                        }

                        // All tags
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ALL TAGS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.gray)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                            ForEach(allTags) { tag in
                                let isAssigned = note.tags.contains(where: { $0.id == tag.id })
                                Button {
                                    if isAssigned {
                                        removeTag(tag)
                                    } else {
                                        note.tags.append(tag)
                                        try? modelContext.save()
                                    }
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: tag.colorHex) ?? .blue)
                                            .frame(width: 10, height: 10)

                                        Text(tag.name)
                                            .font(.body)
                                            .foregroundStyle(.white)

                                        Spacer()

                                        if isAssigned {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .alert("New Tag", isPresented: $showingAddAlert) {
                TextField("Tag name", text: $newTagName)
                Button("Add") {
                    addOrCreateTag(name: newTagName)
                    newTagName = ""
                }
                Button("Cancel", role: .cancel) {
                    newTagName = ""
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func removeTag(_ tag: Tag) {
        note.tags.removeAll(where: { $0.id == tag.id })
        try? modelContext.save()
    }

    private func addOrCreateTag(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Find existing tag or create new
        if let existing = allTags.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            if !note.tags.contains(where: { $0.id == existing.id }) {
                note.tags.append(existing)
            }
        } else {
            let newTag = Tag(name: trimmed.capitalized)
            modelContext.insert(newTag)
            note.tags.append(newTag)
        }
        try? modelContext.save()
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
