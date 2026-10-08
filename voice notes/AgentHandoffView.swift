import SwiftUI
import UIKit

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
