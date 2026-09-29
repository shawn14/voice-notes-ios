import SwiftUI

/// "Allow Claude Code to read your notes?" — shown when the user scans the QR
/// on an agent's sign-in page (voicenotes://pair?code=…) or types its code.
struct AgentPairingView: View {
    let code: String
    let onDone: () -> Void

    @State private var clientName: String?
    @State private var error: String?
    @State private var working = false
    @State private var approved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 12)
                Image(systemName: approved ? "checkmark.circle.fill" : "sparkle.magnifyingglass")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(approved ? .green : .eeonAccentAI)

                if approved {
                    Text("\(clientName ?? "Your agent") can read your notes")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Go back to your computer. It finishes on its own.")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .multilineTextAlignment(.center)
                } else if let error {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.eeonTextPrimary)
                        .multilineTextAlignment(.center)
                } else if let clientName {
                    Text("Allow \(clientName) to read your EEON notes?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Read-only. It can search and read your notes' text, never audio. Remove it anytime in Settings → AI agents.")
                        .font(EEONType.meta)
                        .foregroundStyle(.eeonTextSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }

                Spacer()

                if approved || error != nil {
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if clientName != nil {
                    Button {
                        Task { await decide(true) }
                    } label: {
                        Text(working ? "Allowing…" : "Allow").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(working)

                    Button("Don't Allow") {
                        Task { await decide(false) }
                    }
                    .disabled(working)
                }
            }
            .padding(24)
            .navigationTitle("AI agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        switch await AIAccessService.shared.pairingClientName(code: code) {
        case .success(let name): clientName = name
        case .failure(let failure): error = failure.text
        }
    }

    private func decide(_ approve: Bool) async {
        working = true
        defer { working = false }
        switch await AIAccessService.shared.decidePairing(code: code, approve: approve) {
        case .success:
            if approve { approved = true } else { onDone() }
        case .failure(let failure):
            error = failure.text
        }
    }
}

private struct PairRequest: Identifiable {
    let code: String
    var id: String { code }
}

extension View {
    /// Presents the approval sheet whenever `AIAccessService.pendingPairCode`
    /// is set, from anywhere in the app.
    func agentPairingSheet() -> some View {
        modifier(AgentPairingSheetModifier())
    }
}

private struct AgentPairingSheetModifier: ViewModifier {
    @State private var ai = AIAccessService.shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { ai.pendingPairCode.map(PairRequest.init) },
            set: { ai.pendingPairCode = $0?.code }
        )) { request in
            AgentPairingView(code: request.code) { ai.pendingPairCode = nil }
                .presentationDetents([.medium])
        }
    }
}
