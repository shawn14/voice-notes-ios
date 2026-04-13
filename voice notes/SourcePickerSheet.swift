//
//  SourcePickerSheet.swift
//  voice notes
//
//  Bottom sheet for selecting note input source:
//  Record Audio, Upload Audio, PDF/File, Web Link
//

import SwiftUI
import UniformTypeIdentifiers

struct SourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onRecordAudio: () -> Void
    var onImportAudio: () -> Void
    var onImportPDF: (URL) -> Void
    var onWebLink: (String) -> Void

    @State private var showWebLinkInput = false
    @State private var webLinkText = ""
    @State private var showFilePicker = false
    @State private var isLoadingLink = false
    @State private var linkError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showWebLinkInput {
                    webLinkInputView
                } else {
                    sourceList
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                dismiss()
                onImportPDF(url)
            case .failure:
                linkError = "Could not open the file"
            }
        }
    }

    private var sourceList: some View {
        VStack(spacing: 12) {
            sourceRow(
                icon: "mic.fill",
                iconColor: .eeonAccent,
                title: "Record audio",
                action: {
                    dismiss()
                    onRecordAudio()
                }
            )

            sourceRow(
                icon: "square.and.arrow.down",
                iconColor: .blue,
                title: "Upload audio",
                action: {
                    dismiss()
                    onImportAudio()
                }
            )

            sourceRow(
                icon: "doc.text",
                iconColor: .green,
                title: "PDF, file, or text",
                action: {
                    showFilePicker = true
                }
            )

            sourceRow(
                icon: "link",
                iconColor: .purple,
                title: "Web link",
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWebLinkInput = true
                    }
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func sourceRow(icon: String, iconColor: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.eeonTextPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var webLinkInputView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste a web link")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("https://", text: $webLinkText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit { submitWebLink() }

                Text("Works with articles, blog posts, and web pages")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let error = linkError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWebLinkInput = false
                        webLinkText = ""
                        linkError = nil
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    submitWebLink()
                } label: {
                    HStack {
                        if isLoadingLink {
                            ProgressView().tint(.white)
                        } else {
                            Text("Add")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.eeonAccent)
                .disabled(webLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingLink)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func submitWebLink() {
        var urlString = webLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        // Add https:// if no scheme
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }

        guard URL(string: urlString) != nil else {
            linkError = "That doesn't look like a valid URL"
            return
        }

        dismiss()
        onWebLink(urlString)
    }
}
