import SwiftUI
import SwiftData
import UIKit

/// Settings → "AI agents". One switch lets Claude Code, Codex, Cursor, or
/// Claude read the user's notes, so they can say "read my note about this
/// project and build it". Agents are added with a URL (no token) and approved
/// here by QR or code.
///
/// Status comes from the server (`/api/connect/status`), never from "a token
/// exists": a stored token proves nothing about what an agent can read.
struct AIAccessSetupView: View {
    @State private var ai = AIAccessService.shared
    @State private var mirror = AgentMirrorService.shared
    @State private var tool: AgentTool = .claudeCode
    @State private var justCopied: String?
    @State private var showCodeEntry = false
    @State private var typedCode = ""
    @State private var confirmTurnOff = false
    @State private var showScanner = false
    @State private var scannedCode: String?

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query private var projects: [Project]

    var body: some View {
        List {
            switchSection
            if ai.isConnected {
                statusSection
                addToToolSection
                agentsSection
                tryItSection
            } else {
                introSection
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
        .alert("Enter the code from your computer", isPresented: $showCodeEntry) {
            TextField("ABC-DEF", text: $typedCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Continue") {
                let code = typedCode
                typedCode = ""
                if !AIAccessService.normalize(code).isEmpty { ai.pendingPairCode = code }
            }
            Button("Cancel", role: .cancel) { typedCode = "" }
        }
        // Hand the code to the app-level approval sheet only after the
        // scanner sheet has gone, so two sheets never fight.
        .sheet(isPresented: $showScanner, onDismiss: {
            if let code = scannedCode { ai.pendingPairCode = code }
            scannedCode = nil
        }) {
            AgentQRScannerView { code in scannedCode = code }
        }
        .confirmationDialog("Turn off AI agents?", isPresented: $confirmTurnOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { Task { await ai.disconnect() } }
        } message: {
            Text("Every connected agent loses access and EEON deletes its copy of your notes.")
        }
    }

    // MARK: - Sections

    private var switchSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { ai.isConnected || ai.isConnecting },
                set: { on in
                    if on { Task { await ai.connect() } } else { confirmTurnOff = true }
                }
            )) {
                Label("Let AI agents read my notes", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(ai.isConnecting)
            if let error = ai.lastError {
                Text(error).font(EEONType.meta).foregroundStyle(.orange)
            }
        } footer: {
            Text("EEON keeps an encrypted copy of your notes' text (never audio) so agents can read them anytime, even with your phone off. Read-only. Turning this off deletes the copy and disconnects every agent.")
        }
    }

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
                Button("Turn on again") { Task { await ai.disconnect(); await ai.connect() } }
                    .fontWeight(.semibold)
            }
            if let error = mirror.lastError {
                Text(error).font(EEONType.meta).foregroundStyle(.orange)
            }
        } header: {
            Text("What your agents can see")
        }
    }

    private var addToToolSection: some View {
        Section {
            Picker("Tool", selection: $tool) {
                ForEach(AgentTool.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            copyRow(label: tool.instruction, value: setupText(for: tool), mono: true)

            // The primary action once the agent's page is open.
            Button {
                if AgentQRScannerView.isAvailable { showScanner = true } else { showCodeEntry = true }
            } label: {
                Label("Scan QR code", systemImage: "qrcode.viewfinder")
                    .fontWeight(.semibold)
                    .foregroundStyle(.eeonAccentAI)
            }
        } header: {
            Text("Add EEON to your agent")
        } footer: {
            // Scanning is the path; typing the code is only the fallback, so
            // it's a quiet link rather than a row (Shawn, 2026-09-29).
            VStack(alignment: .leading, spacing: 6) {
                Text("1. On your computer, run the command above. Your agent opens a page with a QR code.\n2. Tap Scan QR code and point your phone at that page. It reads it live, no photo needed.\n3. Tap Allow.")
                Button("Can't scan? Enter the code") { showCodeEntry = true }
                    .font(EEONType.meta)
                    .foregroundStyle(.eeonAccentAI)
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        if let agents = mirror.status?.agents, !agents.isEmpty {
            Section {
                ForEach(agents, id: \.self) { agent in
                    LabeledContent(agent.name, value: "since \(agent.connectedAt.formatted(date: .abbreviated, time: .omitted))")
                }
            } header: {
                Text("Connected agents")
            } footer: {
                Text("To remove them all, turn off AI agents above.")
            }
        }
    }

    private var tryItSection: some View {
        Section {
            copyRow(label: "Then ask your agent", value: examplePrompt)
        } header: {
            Text("Try it")
        } footer: {
            Text("Or open any note, tap ⋯ → Send to an Agent.")
        }
    }

    // MARK: - Status copy

    private var statusTitle: String {
        switch mirror.status?.state {
        case .ready: return "Ready · \(mirror.status?.notes ?? 0) notes"
        case .syncing, .proxyOnly: return "Uploading your notes…"
        case .notConnected: return "Turned off on the server"
        case nil: return mirror.isSyncing ? "Uploading your notes…" : "Checking…"
        }
    }

    private var statusDetail: String? {
        guard let status = mirror.status else { return nil }
        switch status.state {
        case .ready:
            guard let read = status.lastAgentReadAt else { return "No agent has read them yet." }
            return "Last read by \(status.lastAgentName ?? "an agent") \(relative(read))"
        case .syncing, .proxyOnly:
            return "Agents can read your notes as soon as this finishes."
        case .notConnected:
            return "Agents can't read your notes. Turn it on again."
        }
    }

    private var statusIcon: String {
        switch mirror.status?.state {
        case .ready: return "checkmark.circle.fill"
        case .notConnected: return "exclamationmark.triangle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch mirror.status?.state {
        case .ready: return .green
        case .notConnected: return .orange
        default: return .eeonTextSecondary
        }
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

    private func setupText(for tool: AgentTool) -> String {
        switch tool {
        case .claudeCode: return ai.claudeCommand
        case .codex: return ai.codexCommand
        case .other: return ai.mcpURL
        }
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
                    Text(value)
                        .font(mono ? .system(.footnote, design: .monospaced) : EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(4)
                }
                Spacer(minLength: 8)
                Image(systemName: justCopied == label ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(justCopied == label ? .green : .eeonAccentAI)
            }
        }
        .buttonStyle(.plain)
    }
}

enum AgentTool: String, CaseIterable, Identifiable {
    case claudeCode, codex, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .other: return "Other apps"
        }
    }

    var instruction: String {
        switch self {
        case .claudeCode: return "Run once in Terminal, then /mcp → eeon → Authenticate"
        case .codex: return "Run once in Terminal"
        case .other: return "Cursor, Claude, ChatGPT: add a custom connector with this URL"
        }
    }
}
