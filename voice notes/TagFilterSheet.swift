//
//  TagFilterSheet.swift
//  voice notes
//
//  Half-height sheet for filtering notes by tag
//

import SwiftUI
import SwiftData

struct TagFilterSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.name) private var tags: [Tag]

    @Binding var selectedTagFilter: Tag?
    @State private var searchText = ""
    @State private var showingTagManagement = false

    /// Tags sorted by note count descending
    private var sortedTags: [Tag] {
        tags.sorted { (($0.notes ?? []).count) > (($1.notes ?? []).count) }
    }

    /// Filtered by search text
    private var displayedTags: [Tag] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sortedTags
        }
        return sortedTags.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("EEONBackground").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar (show when 20+ tags)
                    if tags.count >= 20 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(Color("EEONTextSecondary"))

                            TextField("Search tags...", text: $searchText)
                                .font(.subheadline)
                                .foregroundStyle(Color("EEONTextPrimary"))
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color("EEONCardBackground"))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }

                    // Tag list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedTags) { tag in
                                let count = (tag.notes ?? []).count
                                Button {
                                    selectedTagFilter = tag
                                    dismiss()
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: tag.colorHex) ?? .blue)
                                            .frame(width: 10, height: 10)

                                        Text(tag.name)
                                            .font(.body)
                                            .foregroundStyle(Color("EEONTextPrimary"))

                                        Spacer()

                                        Text("\(count)")
                                            .font(.subheadline)
                                            .foregroundStyle(Color("EEONTextSecondary"))

                                        if selectedTagFilter?.id == tag.id {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color("EEONAccent"))
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }

                                Divider()
                                    .background(Color("EEONDivider"))
                            }
                        }
                    }

                    // Manage Tags button
                    Button {
                        showingTagManagement = true
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(Color("EEONAccent"))
                            Text("Manage Tags")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color("EEONAccent"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("EEONCardBackground"))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Filter by Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color("EEONTextSecondary"))
                    }
                }
            }
            .sheet(isPresented: $showingTagManagement) {
                TagManagementSheet()
            }
        }
    }
}
