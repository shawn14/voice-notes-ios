import SwiftUI
import SwiftData
import UIKit

/// Settings → "AI agents". Lets Claude Code, Codex, or Cursor read the user's
/// notes so they can say "read my note about this project and build it".
///
/// Status comes from the server (`/api/connect/status`), never from "a token
/// exists": a stored token proves nothing about what an agent can read.
struct AIAccessSetupView: View {
    @State private var ai = AIAccessService.shared
    @State private var mirror = AgentMirrorService.shared
    @State private var tool: AgentTool = .claudeCode
    @State private var showShare = false
    @State private var justCopied: String?

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query private var projects: [Project]

    var body: some View {
        List {
            if ai.isConnected {
                statusSection
                accessSection
                addToToolSection
                tryItSection
                disconnectSection
            } else {
                introSection
                setupSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI agents")
        .navigationBarTitleDisplayMode(.inline)
        .task { await mirror.refreshStatus() }
        .refreshable {
            await mirror.syncNow()
            await mirror.refreshStatus()
        }
        .sheet(isPresented: $showShare) {
            ActivityViewControllerRepresentable(activityItems: [shareText])
        }
    }

    // MARK: - Not connected

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your notes, in every AI agent")
                    .font(.headline)
                Text("Record a note about a project. Then in Claude Code, Codex, or Cursor, say:")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
                Text("“\(examplePrompt)”")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.eeonTextPrimary)
                Text("The agent finds the note, reads it, and gets to work.")
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var setupSection: some View {
        Group {
            Section {
                Toggle("Keep notes available to agents", isOn: Binding(
                    get: { mirror.isEnabled },
                    set: { mirror.isEnabled = $0 }
                ))
                Button {
                    Task { await ai.connect() }
                } label: {
                    HStack(spacing: 12) {
                        if ai.isConnecting {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                                .foregroundStyle(.eeonAccentAI)
                        }
                        Text(ai.isConnecting ? "Connecting…" : "Connect with Apple")
                            .fontWeight(.semibold)
                            .foregroundStyle(.eeonAccentAI)
                    }
                }
                .disabled(ai.isConnecting)
            } footer: {
                Text(mirrorFooter)
            }

            if let error = ai.lastError {
                Section {
                    Text(error).font(EEONType.meta).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Connected

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
                Spacer(minLength: 0)
                if mirror.isSyncing { ProgressView() }
            }
            .padding(.vertical, 2)

            if mirror.status?.state == .notConnected {
                Button("Reconnect") { Task { await ai.connect() } }
                    .fontWeight(.semibold)
            }
            if let error = mirror.lastError {
                Text(error).font(EEONType.meta).foregroundStyle(.orange)
            }
        } header: {
            Text("What your agents can see")
        }
    }

    private var accessSection: some View {
        Section {
            Toggle("Keep notes available to agents", isOn: Binding(
                get: { mirror.isEnabled },
                set: { on in Task { on ? await mirror.enable() : await mirror.disable() } }
            ))
        } footer: {
            Text(mirrorFooter)
        }
    }

    private var addToToolSection: some View {
        Section {
            Picker("Tool", selection: $tool) {
                ForEach(AgentTool.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if let setup = setupText(for: tool) {
                copyRow(label: tool.instruction, value: setup, mono: true)
            }
            Button {
                showShare = true
            } label: {
                Label("Send to my computer", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Add EEON to your agent")
        } footer: {
            Text("Do this once on each computer. The setup includes your private access token, so only send it to yourself.")
        }
    }

    private var tryItSection: some View {
        Section {
            copyRow(label: "Then ask your agent", value: examplePrompt)
        } header: {
            Text("Try it")
        } footer: {
            Text("Or open any note, tap ⋯ → Send to an agent.")
        }
    }

    private var disconnectSection: some View {
        Section {
            Button(role: .destructive) {
                ai.disconnect()
                Task { await mirror.refreshStatus() }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
        } footer: {
            Text("Stops every connected agent and deletes EEON's copy of your notes.")
        }
    }

    // MARK: - Status copy

    private var statusTitle: String {
        switch mirror.status?.state {
        case .ready: return "Ready · \(mirror.status?.notes ?? 0) notes"
        case .syncing: return "Uploading your notes…"
        case .proxyOnly: return "Limited: needs Apple sign-in"
        case .notConnected: return "Reconnect needed"
        case nil: return "Checking…"
        }
    }

    private var statusDetail: String? {
        guard let status = mirror.status else { return nil }
        switch status.state {
        case .ready:
            var parts: [String] = []
            if let synced = status.lastSyncAt { parts.append("updated \(relative(synced))") }
            if let read = status.lastAgentReadAt {
                parts.append("last read by an agent \(relative(read))")
            } else {
                parts.append("no agent has read them yet")
            }
            return parts.joined(separator: " · ")
        case .syncing:
            return "Agents can read your notes as soon as this finishes."
        case .proxyOnly:
            return "Agents can only read notes while Apple's sign-in lasts (up to 2 weeks). Turn on “Keep notes available” below."
        case .notConnected:
            return "This connection was revoked. Agents can't read your notes until you reconnect."
        }
    }

    private var statusIcon: String {
        switch mirror.status?.state {
        case .ready: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .proxyOnly, .notConnected: return "exclamationmark.triangle.fill"
        case nil: return "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch mirror.status?.state {
        case .ready: return .green
        case .proxyOnly, .notConnected: return .orange
        default: return .eeonTextSecondary
        }
    }

    private var mirrorFooter: String {
        "When on, EEON keeps an encrypted copy of your notes' text (never audio) so agents can read them anytime, even when your phone is off. Read-only. Turning this off or disconnecting deletes the copy."
    }

    // MARK: - Helpers

    /// A real project name makes the example feel like the user's own.
    private var examplePrompt: String {
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let recent = notes.lazy.compactMap { note -> String? in
            let name = note.projectId.flatMap { names[$0] } ?? note.inferredProjectName
            return (name?.isEmpty == false) ? name : nil
        }.first
        return "Read my latest EEON note about \(recent ?? "my project") and do it."
    }

    private func setupText(for tool: AgentTool) -> String? {
        switch tool {
        case .claudeCode: return ai.claudeCommand
        case .codex: return ai.codexCommand
        case .cursor: return ai.cursorConfig
        }
    }

    private var shareText: String {
        let setup = setupText(for: tool) ?? ai.mcpURL
        return "EEON for \(tool.label): \(tool.instruction)\n\n\(setup)\n\nThen ask: \(examplePrompt)"
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyRow(label: String, value: String, mono: Bool = false) -> some View {
        Button {
            UIPasteboard.general.string = value
            justCopied = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if justCopied == label { justCopied = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(EEONType.badge)
                        .foregroundStyle(.eeonTextSecondary)
                    Text(mono ? masked(value) : value)
                        .font(mono ? .system(.footnote, design: .monospaced) : EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(4)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: justCopied == label ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(justCopied == label ? .green : .eeonAccentAI)
            }
        }
        .buttonStyle(.plain)
    }

    /// Show the command's shape without printing the secret on screen.
    private func masked(_ value: String) -> String {
        guard let token = ai.connectorToken, !token.isEmpty else { return value }
        return value.replacingOccurrences(of: token, with: "••••••")
    }
}

enum AgentTool: String, CaseIterable, Identifiable {
    case claudeCode, codex, cursor
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var instruction: String {
        switch self {
        case .claudeCode: return "Run in Terminal"
        case .codex: return "Run in Terminal"
        case .cursor: return "Add to ~/.cursor/mcp.json"
        }
    }
}
