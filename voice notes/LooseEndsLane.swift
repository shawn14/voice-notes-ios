//
//  LooseEndsLane.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct LooseEndsLane: View {
    @Environment(\.modelContext) private var modelContext
    let openItems: [UnresolvedItem]
    var onTapItem: (UnresolvedItem) -> Void

    var body: some View {
        if openItems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Loose Ends")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(openItems.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonTextTertiary)
                }
                .padding(.horizontal, 16)

                ForEach(openItems.prefix(5)) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.content)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.eeonTextTertiary)
                        }
                        Spacer()
                        Button {
                            item.resolvedAt = Date()
                            try? modelContext.save()
                        } label: {
                            Text("Resolve")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.eeonAccent.opacity(0.15))
                                .foregroundStyle(Color.eeonAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(12)
                    .background(Color.eeonCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapItem(item) }
                }

                if openItems.count > 5 {
                    Text("+\(openItems.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.eeonTextTertiary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }
}
