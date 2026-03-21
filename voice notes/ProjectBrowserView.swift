//
//  ProjectBrowserView.swift
//  voice notes
//
//  Browse all projects
//

import SwiftUI
import SwiftData

struct ProjectBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query private var allNotes: [Note]

    private func noteCount(for project: Project) -> Int {
        allNotes.filter { $0.projectId == project.id }.count
    }

    var body: some View {
        NavigationStack {
            List {
                let activeProjects = projects.filter { !$0.isArchived }
                if activeProjects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(activeProjects) { project in
                        NavigationLink(destination: ProjectDetailView(project: project)) {
                            HStack(spacing: 12) {
                                Text(project.icon)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.body.weight(.medium))
                                    let count = noteCount(for: project)
                                    Text("\(count) note\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
