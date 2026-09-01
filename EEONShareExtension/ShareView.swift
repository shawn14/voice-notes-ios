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
    @State private var sharedFileName: String?
    @State private var originalFileName: String?
    @State private var contentTypeIdentifier: String?
    @State private var annotation: String = ""
    @State private var isSaving = false
    @State private var isLoaded = false

    private var canSave: Bool {
        url != nil || fullText != nil || sharedFileName != nil
    }

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

                    if sharedFileName != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                            Text(originalFileName ?? "Recording")
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
                    .disabled(isSaving || !isLoaded || !canSave)
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
                if await extractRecordingAttachment(attachment, item: item) {
                    await MainActor.run { isLoaded = true }
                    return
                }

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

        if title.isEmpty && contentPreview.isEmpty {
            title = "Unsupported Content"
            contentPreview = "Share a link, text, or audio recording."
        }

        await MainActor.run { isLoaded = true }
    }

    private func extractRecordingAttachment(_ attachment: NSItemProvider, item: NSExtensionItem) async -> Bool {
        let recordingTypes: [UTType] = [.audio, .movie, .mpeg4Movie, .quickTimeMovie]

        for type in recordingTypes where attachment.hasItemConformingToTypeIdentifier(type.identifier) {
            guard let copied = await Self.copyFileRepresentation(
                from: attachment,
                typeIdentifier: type.identifier,
                suggestedName: attachment.suggestedName,
                preferredFilenameExtension: type.preferredFilenameExtension
            ) else {
                continue
            }

            sharedFileName = copied.fileName
            originalFileName = copied.originalName
            contentTypeIdentifier = type.identifier
            let baseTitle = copied.originalName.removingPathExtension
            title = item.attributedContentText?.string ?? (baseTitle.isEmpty ? "Imported Recording" : baseTitle)
            contentPreview = type.conforms(to: .movie) ? "Video recording ready to import." : "Audio recording ready to import."
            return true
        }

        return false
    }

    private static func copyFileRepresentation(
        from attachment: NSItemProvider,
        typeIdentifier: String,
        suggestedName: String?,
        preferredFilenameExtension: String?
    ) async -> (fileName: String, originalName: String)? {
        await withCheckedContinuation { continuation in
            attachment.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, _ in
                guard let sourceURL else {
                    continuation.resume(returning: nil)
                    return
                }

                let copied = copySharedFile(
                    from: sourceURL,
                    suggestedName: suggestedName,
                    preferredFilenameExtension: preferredFilenameExtension
                )
                continuation.resume(returning: copied)
            }
        }
    }

    private static func copySharedFile(
        from sourceURL: URL,
        suggestedName: String?,
        preferredFilenameExtension: String?
    ) -> (fileName: String, originalName: String)? {
        let manager = FileManager.default
        guard let containerURL = manager.containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName) else {
            return nil
        }

        let importsURL = containerURL.appendingPathComponent("Shared Imports", isDirectory: true)
        do {
            try manager.createDirectory(at: importsURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let sourceExtension = sourceURL.pathExtension
        let suggestedExtension = suggestedName.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        let fileExtension = [sourceExtension, suggestedExtension, preferredFilenameExtension, "m4a"]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "m4a"
        let originalName = suggestedName?.isEmpty == false ? suggestedName! : "Recording.\(fileExtension)"
        let fileName = "\(UUID().uuidString).\(fileExtension.lowercased())"
        let destinationURL = importsURL.appendingPathComponent(fileName)

        do {
            if manager.fileExists(atPath: destinationURL.path) {
                try manager.removeItem(at: destinationURL)
            }
            try manager.copyItem(at: sourceURL, to: destinationURL)
            return (fileName, originalName)
        } catch {
            return nil
        }
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
            sharedFileName: sharedFileName,
            originalFileName: originalFileName,
            contentTypeIdentifier: contentTypeIdentifier,
            createdAt: Date()
        )

        SharedDefaults.addPendingIngest(ingest)

        extensionContext?.completeRequest(returningItems: nil)
    }
}

private extension String {
    var removingPathExtension: String {
        URL(fileURLWithPath: self).deletingPathExtension().lastPathComponent
    }
}
