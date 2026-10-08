import SwiftUI
import UIKit
import SwiftData

struct AgentHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    let brief: AgentHandoffBrief
    @State private var work: AgentHandoffWork = .plan
    @State private var request = AgentHandoffWork.plan.request
    @State private var copied = false

    private var prompt: String { brief.prompt(work: work, request: request) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should your agent do?").font(.title2.bold())
                        Text("Prepare a brief, then paste it into your coding tool or AI agent.")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Work", selection: $work) {
                        ForEach(AgentHandoffWork.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: work) { old, new in
                        if request == old.request { request = new.request }
                        copied = false
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your request").font(.headline)
                        TextEditor(text: $request)
                            .frame(minHeight: 110)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
                            .accessibilityIdentifier("agentHandoffRequest")
                            .onChange(of: request) { _, _ in copied = false }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Included context").font(.headline)
                        Text(brief.primary.title)
                        if let project = brief.project { Text(project).foregroundStyle(.secondary) }
                        Text(brief.related.isEmpty ? "This note" : "This note and \(brief.related.count) recent project notes")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(brief.connected ? "An agent with your EEON connector can read the full source notes." : "Source text is included. Connect an agent in Settings for access to your note library.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Divider()
                    DisclosureGroup("Preview brief") {
                        Text(prompt).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("agentHandoffPreview")
                    }
                    Text("Copying prepares the handoff. Work starts when you send it in your agent’s workspace.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    UIPasteboard.general.string = prompt
                    copied = true
                } label: {
                    Label(copied ? "Brief copied" : "Copy agent brief", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("copyAgentBrief")
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("Agent brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Explicit reviewed paste; no connector write, extraction or task mutations.
struct AgentResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let source: Note
    @State private var report = ""
    @State private var saveError: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save the report from your agent beside this note.")
                Text(source.displayTitle).font(.headline)
                Text("Claims remain agent-reported. Your original capture and task status stay unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $report)
                    .accessibilityIdentifier("agentResultReport")
                    .overlay(Rectangle().stroke(.secondary.opacity(0.3)))
                if let saveError { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("agentResultError") }
            }
            .padding()
            .navigationTitle("Add agent result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save result") { save() }
                        .disabled(saving || report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveAgentResult")
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let draft = try AgentResultDraft(sourceID: source.id, sourceTitle: source.displayTitle, report: report)
            let result = Note(title: draft.title, content: draft.content, projectId: source.projectId)
            result.inferredProjectName = source.inferredProjectName
            result.sourceType = .derived
            result.annotation = draft.annotation
            var saveContext = modelContext
            #if DEBUG
            // Exercise a real rejected SwiftData write only on a simulator.
            // The physical phone and release app cannot select this store.
            #if targetEnvironment(simulator)
            var proofContainer: ModelContainer?
            if ProcessInfo.processInfo.arguments.contains("-UITestMode"),
               ProcessInfo.processInfo.arguments.contains("-AgentResultReadOnlyProof"),
               let config = modelContext.container.configurations.first {
                let readOnly = ModelConfiguration(schema: modelContext.container.schema,
                                                  url: config.url, allowsSave: false,
                                                  cloudKitDatabase: .none)
                proofContainer = try ModelContainer(for: modelContext.container.schema, configurations: [readOnly])
                saveContext = proofContainer!.mainContext
                saveContext.autosaveEnabled = false
            }
            defer { withExtendedLifetime(proofContainer) {} }
            #endif
            #endif
            saveContext.insert(result)
            do { try saveContext.save() }
            catch {
                // Remove only this attempted insert; do not roll back other edits.
                saveContext.delete(result)
                throw error
            }
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
