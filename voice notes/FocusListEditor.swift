//
//  FocusListEditor.swift
//  voice notes
//
//  List editor for FocusItems — shown as a sheet from TuneConversationView's
//  Focus card. Drag to reorder, swipe to delete, tap to edit, "+ Add" button
//  for new items. Auto-saves on every change via the onCommit closure.
//

import SwiftUI

struct FocusListEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var items: [FocusItem]
    let onCommit: ([FocusItem]) -> Void

    @State private var editingItem: FocusItem?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            row(for: item)
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }

                Button {
                    showingAdd = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add focus")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Color("EEONAccent"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color("EEONAccent").opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color.eeonBackground.ignoresSafeArea())
            .navigationTitle("Your Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                FocusItemEditor(initialItem: item) { updated in
                    if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                        items[idx] = updated
                    }
                    commit()
                }
            }
            .sheet(isPresented: $showingAdd) {
                FocusItemEditor(initialItem: nil) { newItem in
                    items.append(newItem)
                    commit()
                }
            }
        }
    }

    private func row(for item: FocusItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .italic()
                }
            }
            Spacer()
            weightBadge(for: item.weight)
        }
        .padding(.vertical, 4)
    }

    private func weightBadge(for weight: FocusWeight) -> some View {
        Text(weight.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor(for: weight))
            .foregroundStyle(badgeText(for: weight))
            .cornerRadius(6)
    }

    private func badgeColor(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return Color("EEONAccent")
        case .secondary: return Color("EEONAccent").opacity(0.18)
        case .tertiary: return Color.eeonTextSecondary.opacity(0.15)
        }
    }

    private func badgeText(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return .white
        case .secondary: return Color("EEONAccent")
        case .tertiary: return Color.eeonTextSecondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color("EEONAccent").opacity(0.5))
            Text("Declare what matters right now.")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            Text("EEON will surface what's moving against your stated priorities — and call out drift.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        commit()
    }

    private func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        commit()
    }

    private func commit() {
        onCommit(items)
    }
}
