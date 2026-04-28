//
//  IntentFilterChips.swift
//  voice notes
//

import SwiftUI

struct IntentFilterChips: View {
    let counts: [NoteIntent: Int]
    @Binding var selected: Set<NoteIntent>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotesReorgHelpers.filterableIntents, id: \.self) { intent in
                    let count = counts[intent] ?? 0
                    if count > 0 {
                        chip(intent: intent, count: count)
                    }
                }
                if !selected.isEmpty {
                    Button {
                        selected.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(intent: NoteIntent, count: Int) -> some View {
        let isOn = selected.contains(intent)
        return Button {
            if isOn { selected.remove(intent) } else { selected.insert(intent) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: intent.icon)
                    .font(.caption2)
                Text(intent.rawValue)
                Text("(\(count))")
                    .font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? Color.eeonAccent : Color.eeonCard)
            .foregroundStyle(isOn ? .white : .eeonTextSecondary)
            .cornerRadius(16)
        }
    }
}

#Preview {
    @Previewable @State var selected: Set<NoteIntent> = [.action]
    return VStack {
        IntentFilterChips(
            counts: [.action: 12, .decision: 4, .idea: 7, .update: 2, .reminder: 1],
            selected: $selected
        )
        Text("Selected: " + selected.map(\.rawValue).joined(separator: ", "))
    }
    .padding()
}
