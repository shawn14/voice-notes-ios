//
//  ShareView.swift
//  EEONShareExtension
//
//  SwiftUI share sheet UI — title preview, content snippet, annotation field, save button.
//

import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let extensionContext: NSExtensionContext?

    @State private var title: String = ""
    @State private var contentPreview: String = ""
    @State private var url: String?
    @State private var fullText: String?
    @State private var annotation: String = ""
    @State private var isSaving = false
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoaded {
                    // Title
                    Text(title.isEmpty ? "Shared Content" : title)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Content preview
                    if !contentPreview.isEmpty {
                        Text(contentPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // URL indicator
                    if let url = url {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(URL(string: url)?.host ?? url)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Annotation
                    TextField("Why are you saving this?", text: $annotation, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Spacer()
                } else {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
            .navigationTitle("Save to EEON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        extensionContext?.completeRequest(returningItems: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveToEEON()
                    }
                    .disabled(isSaving || !isLoaded)
                    .bold()
                }
            }
        }
        .task {
            await extractSharedContent()
        }
    }

    // MARK: - Extract Shared Content

    private func extractSharedContent() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            isLoaded = true
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Check for URL
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let urlItem = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let sharedURL = urlItem as? URL {
                        url = sharedURL.absoluteString
                        title = item.attributedContentText?.string ?? sharedURL.host ?? "Shared Link"
                        contentPreview = sharedURL.absoluteString
                    }
                }

                // Check for plain text
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let textItem = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let text = textItem as? String {
                        fullText = text
                        if title.isEmpty {
                            title = String(text.prefix(50))
                        }
                        contentPreview = String(text.prefix(200))
                    }
                }
            }
        }

        await MainActor.run { isLoaded = true }
    }

    // MARK: - Save

    private func saveToEEON() {
        isSaving = true

        let ingest = SharedDefaults.PendingIngest(
            id: UUID().uuidString,
            url: url,
            text: fullText,
            title: title.isEmpty ? nil : title,
            annotation: annotation.isEmpty ? nil : annotation,
            createdAt: Date()
        )

        SharedDefaults.addPendingIngest(ingest)

        extensionContext?.completeRequest(returningItems: nil)
    }
}
