import SwiftUI
import VisionKit
import Vision

/// Settings → AI agents → "Scan QR code". Reads the QR on an agent's EEON
/// sign-in page (`voicenotes://pair?code=…`) and hands the code to the
/// approval sheet. Shawn (2026-09-29): "i dont even see a scan?" — pointing
/// the Camera app at the screen wasn't discoverable, so scanning lives here.
struct AgentQRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRDataScanner { payload in
                    guard let code = Self.pairCode(from: payload) else { return }
                    onCode(code)
                    dismiss()
                }
                .ignoresSafeArea()

                Text("Point at the QR code on your computer's EEON page")
                    .font(EEONType.meta)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 32)
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Accepts the deep link the page encodes, or a bare 6-character code.
    static func pairCode(from payload: String) -> String? {
        if let components = URLComponents(string: payload),
           components.scheme == "voicenotes", components.host == "pair",
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }
        let bare = AIAccessService.normalize(payload)
        return bare.count == 6 ? bare : nil
    }
}

private struct QRDataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        private var delivered = false

        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                   AgentQRScannerView.pairCode(from: payload) != nil {
                    delivered = true
                    dataScanner.stopScanning()
                    onPayload(payload)
                    return
                }
            }
        }
    }
}
