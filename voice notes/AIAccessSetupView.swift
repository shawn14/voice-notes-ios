import SwiftUI
import UIKit

/// Settings → "Set up AI access". In-app connect: tap Connect, sign in with
/// Apple inline, and get a connector URL + token to add to Claude / ChatGPT /
/// Cursor. Read-only, revocable. No browser, no leaving the app.
struct AIAccessSetupView: View {
    @State private var ai = AIAccessService.shared
    @State private var showShare = false
    @State private var justCopied: String?

    var body: some View {
        List {
            if ai.isConnected {
                connectedSections
            } else {
                setupSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI access")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            ActivityViewControllerRepresentable(activityItems: [shareText])
        }
    }

    // MARK: - Not connected

    private var setupSection: some View {
        Group {
            Section {
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
                        Text(ai.isConnecting ? "Connecting…" : "Connect an AI tool")
                            .foregroundStyle(.eeonTextPrimary)
                    }
                }
                .disabled(ai.isConnecting)
            } footer: {
                Text("Sign in with Apple to let Claude, ChatGPT, or Cursor read your EEON memory. Read-only, and you can disconnect anytime. Your notes stay in your iCloud — only a revocable access token is stored.")
            }

            if let error = ai.lastError {
                Section {
                    Text(error).font(EEONType.meta).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Connected

    private var connectedSections: some View {
        Group {
            Section {
                copyRow(label: "Connector URL", value: ai.mcpURL)
                copyRow(label: "Access token", value: ai.connectorToken ?? "", mono: true, masked: true)
            } header: {
                Text("Your connector")
            } footer: {
                Text("Add these in your AI tool on your computer. Send them over with Share.")
            }

            if let command = ai.claudeCommand {
                Section {
                    copyRow(label: "Claude Code command", value: command, mono: true)
                    Button {
                        showShare = true
                    } label: {
                        Label("Share to my computer", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Add to Claude")
                }
            }

            Section {
                Text("Cursor: add an MCP server with the URL above and header Authorization: Bearer <token>.")
                    .font(EEONType.meta).foregroundStyle(.eeonTextSecondary)
                Text("ChatGPT: add a custom connector with the same URL and header.")
                    .font(EEONType.meta).foregroundStyle(.eeonTextSecondary)
            } header: {
                Text("Other tools")
            }

            Section {
                Button(role: .destructive) {
                    ai.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } footer: {
                Text("Stops all connected AI tools from reading your memory and deletes the stored token.")
            }
        }
    }

    private var shareText: String {
        ai.claudeCommand ?? "EEON connector: \(ai.mcpURL)"
    }

    private func copyRow(label: String, value: String, mono: Bool = false, masked: Bool = false) -> some View {
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
                    Text(masked ? String(repeating: "•", count: 24) : value)
                        .font(mono ? .system(.footnote, design: .monospaced) : EEONType.meta)
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: justCopied == label ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(justCopied == label ? .green : .eeonAccentAI)
            }
        }
        .buttonStyle(.plain)
    }
}
