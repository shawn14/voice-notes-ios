//
//  CompletedItemsView.swift
//  voice notes
//
//  Historical log of completed tasks and commitments
//

import SwiftUI
import SwiftData

struct CompletedItemsView: View {
    @Query(filter: #Predicate<ExtractedAction> { $0.isCompleted },
           sort: \ExtractedAction.completedAt, order: .reverse)
    private var completedActions: [ExtractedAction]
    
    @Query(filter: #Predicate<ExtractedCommitment> { $0.isCompleted },
           sort: \ExtractedCommitment.completedAt, order: .reverse)
    private var completedCommitments: [ExtractedCommitment]
    
    @State private var selectedTab = 0
    
    private var allCompletedItems: [(date: Date, type: String, content: String, owner: String?)] {
        var items: [(date: Date, type: String, content: String, owner: String?)] = []
        
        for action in completedActions {
            if let completedAt = action.completedAt {
                items.append((completedAt, "action", action.content, action.owner))
            }
        }
        
        for commitment in completedCommitments {
            if let completedAt = commitment.completedAt {
                items.append((completedAt, "commitment", commitment.what, commitment.who))
            }
        }
        
        return items.sorted { $0.date > $1.date }
    }
    
    private var groupedByDate: [(date: Date, items: [(type: String, content: String, owner: String?)])] {
        let calendar = Calendar.current
        var groups: [Date: [(type: String, content: String, owner: String?)]] = [:]
        
        for item in allCompletedItems {
            let dayStart = calendar.startOfDay(for: item.date)
            if groups[dayStart] == nil {
                groups[dayStart] = []
            }
            groups[dayStart]?.append((item.type, item.content, item.owner))
        }
        
        return groups.map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
    }
    
    var body: some View {
        Group {
            if allCompletedItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedByDate, id: \.date) { group in
                        Section {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
                                CompletedItemRow(
                                    type: item.type,
                                    content: item.content,
                                    owner: item.owner
                                )
                            }
                        } header: {
                            Text(formatDateHeader(group.date))
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Completed")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(allCompletedItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No completed items yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("When you check off tasks and commitments, they'll appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"  // Day name
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Completed Item Row

struct CompletedItemRow: View {
    let type: String
    let content: String
    let owner: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Label(type == "action" ? "Task" : "Commitment", systemImage: type == "action" ? "checkmark.square" : "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let owner = owner, owner != "Me" && !owner.isEmpty {
                        Text("• \(owner)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CompletedItemsView()
    }
}
