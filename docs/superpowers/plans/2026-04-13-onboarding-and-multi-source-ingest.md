# Onboarding Redesign + Multi-Source Note Creation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current 3-screen onboarding with a 6-screen progressive profiling quiz, and add a "+" button to AIHomeView that opens a source picker sheet for creating notes from audio files, PDFs, and web links.

**Architecture:** Two independent features that share no code dependencies. Onboarding is a full replacement of `OnboardingPaywallView.swift` with a new `OnboardingQuizView.swift` that uses `TabView` paging. Multi-source ingest adds a `SourcePickerSheet` to `AIHomeView`, a new `PDFExtractionService` actor, and two new `NoteSourceType` enum cases. All note sources run through the existing AI pipeline (`IntelligenceService.processNoteSave` + `EmbeddingService`).

**Tech Stack:** SwiftUI, SwiftData, PDFKit, Vision, StoreKit 2

**Design Spec:** `docs/superpowers/specs/2026-04-13-onboarding-and-multi-source-ingest-design.md`

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `voice notes/OnboardingQuizView.swift` | 6-screen progressive profiling onboarding with paging TabView |
| `voice notes/SourcePickerSheet.swift` | Bottom sheet with 4 input source options |
| `voice notes/PDFExtractionService.swift` | PDF text extraction via PDFKit + Vision OCR fallback |

### Modified Files
| File | Change |
|------|--------|
| `voice notes/Note.swift` | Add `document` and `audioImport` cases to `NoteSourceType` |
| `voice notes/AIHomeView.swift` | Add "+" button to bottomBar, add sheet presentation, add `saveWebNote()` and `savePDFNote()` methods |
| `voice notes/voice_notesApp.swift` | Point `needsPaywall` case to `OnboardingQuizView` instead of `OnboardingPaywallView` |

---

## Task 1: Add `document` and `audioImport` to NoteSourceType

**Files:**
- Modify: `voice notes/Note.swift:45-65`

This task extends the existing `NoteSourceType` enum so the new input sources get distinct badges in the UI.

- [ ] **Step 1: Add enum cases and update computed properties**

In `voice notes/Note.swift`, replace the `NoteSourceType` enum (lines 45-65):

```swift
enum NoteSourceType: String, CaseIterable {
    case voice = "voice"
    case webArticle = "web"
    case derived = "derived"
    case document = "document"
    case audioImport = "audioImport"

    var badgeIcon: String? {
        switch self {
        case .voice: return nil
        case .webArticle: return "link"
        case .derived: return "sparkles"
        case .document: return "doc.text"
        case .audioImport: return "square.and.arrow.down"
        }
    }

    var label: String? {
        switch self {
        case .voice: return nil
        case .webArticle: return "Web Source"
        case .derived: return "Saved from Assistant"
        case .document: return "PDF"
        case .audioImport: return "Audio Import"
        }
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/Note.swift"
git commit -m "$(cat <<'EOF'
feat: add document and audioImport source types to NoteSourceType

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create PDFExtractionService

**Files:**
- Create: `voice notes/PDFExtractionService.swift`

A thread-safe actor that extracts text from PDFs. Tries PDFKit first (fast, free), falls back to Vision OCR for scanned documents.

- [ ] **Step 1: Create PDFExtractionService.swift**

```swift
//
//  PDFExtractionService.swift
//  voice notes
//
//  Extracts text from PDF files using PDFKit with Vision OCR fallback
//  for scanned documents. Caps output at 5000 words.
//

import Foundation
import PDFKit
import Vision
import CoreGraphics

struct ExtractedDocument {
    let text: String
    let title: String
    let pageCount: Int
    let wasOCR: Bool
}

enum PDFExtractionError: LocalizedError {
    case cannotLoadPDF
    case noTextExtracted
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotLoadPDF: return "Could not open the PDF"
        case .noTextExtracted: return "No readable text found in the PDF"
        case .ocrFailed(let msg): return "OCR failed: \(msg)"
        }
    }
}

actor PDFExtractionService {
    static let shared = PDFExtractionService()
    private let maxWords = 5000

    func extractText(from url: URL) async throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError.cannotLoadPDF
        }

        let pageCount = document.pageCount
        let title = url.deletingPathExtension().lastPathComponent

        // Try PDFKit text extraction first
        if let pdfKitText = extractWithPDFKit(document: document), !pdfKitText.isEmpty {
            let capped = capWords(pdfKitText)
            return ExtractedDocument(text: capped, title: title, pageCount: pageCount, wasOCR: false)
        }

        // Fallback to Vision OCR for scanned documents
        let ocrText = try await extractWithVisionOCR(document: document)
        guard !ocrText.isEmpty else {
            throw PDFExtractionError.noTextExtracted
        }
        let capped = capWords(ocrText)
        return ExtractedDocument(text: capped, title: title, pageCount: pageCount, wasOCR: true)
    }

    private func extractWithPDFKit(document: PDFDocument) -> String? {
        var pages: [String] = []
        var totalChars = 0

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string, !text.isEmpty else { continue }
            pages.append(text)
            totalChars += text.count
        }

        // If average chars per page is very low, likely a scanned doc
        let avgCharsPerPage = document.pageCount > 0 ? totalChars / document.pageCount : 0
        if avgCharsPerPage < 50 {
            return nil
        }

        return pages.joined(separator: "\n\n")
    }

    private func extractWithVisionOCR(document: PDFDocument) async throws -> String {
        var pages: [String] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            guard let cgImage = context.makeImage() else { continue }

            let text = try await recognizeText(in: cgImage)
            if !text.isEmpty {
                pages.append(text)
            }
        }

        return pages.joined(separator: "\n\n")
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: PDFExtractionError.ocrFailed(error.localizedDescription))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PDFExtractionError.ocrFailed(error.localizedDescription))
            }
        }
    }

    private func capWords(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if words.count <= maxWords { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/PDFExtractionService.swift"
git commit -m "$(cat <<'EOF'
feat: add PDFExtractionService with PDFKit + Vision OCR fallback

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create SourcePickerSheet

**Files:**
- Create: `voice notes/SourcePickerSheet.swift`

A bottom sheet presenting 4 input source options. Record audio and Upload audio dismiss the sheet and trigger callbacks. PDF opens a file picker. Web link shows an inline URL text field.

- [ ] **Step 1: Create SourcePickerSheet.swift**

```swift
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
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/SourcePickerSheet.swift"
git commit -m "$(cat <<'EOF'
feat: add SourcePickerSheet for multi-source note creation

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire SourcePickerSheet into AIHomeView

**Files:**
- Modify: `voice notes/AIHomeView.swift`

Add a "+" button to the bottom bar, present the source picker sheet, and add `saveWebNote()` and `savePDFNote()` methods that create notes and run the full AI pipeline.

- [ ] **Step 1: Add state variables for the source picker**

In `voice notes/AIHomeView.swift`, after the existing `@State private var showingAudioImporter = false` line (line 56), add:

```swift
    // Source picker
    @State private var showingSourcePicker = false
```

- [ ] **Step 2: Add "+" button to bottomBar**

In `voice notes/AIHomeView.swift`, replace the `bottomBar` computed property (lines 574-624) with:

```swift
    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Write button (left)
            Button {
                showingTypeNote = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity)

            // "+" source picker (left of mic)
            Button {
                showingSourcePicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(width: 44)

            // Mic button (center, elevated)
            Button(action: {
                toggleRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.eeonAccent)
                        .frame(width: 64, height: 64)

                    if isTranscribing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isTranscribing)
            .offset(y: -6)

            // Search button (right)
            Button {
                showingAssistant = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .background(
            Color.eeonBackground
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.eeonTextPrimary.opacity(0.08), radius: 4, y: -2)
        )
    }
```

- [ ] **Step 3: Add sheet presentation for SourcePickerSheet**

In `voice notes/AIHomeView.swift`, find the `.fileImporter(` modifier block (around line 274). After the closing `}` of that `.fileImporter` block (line 287), add:

```swift
            .sheet(isPresented: $showingSourcePicker) {
                SourcePickerSheet(
                    onRecordAudio: {
                        toggleRecording()
                    },
                    onImportAudio: {
                        showingAudioImporter = true
                    },
                    onImportPDF: { url in
                        savePDFNote(from: url)
                    },
                    onWebLink: { urlString in
                        saveWebNote(from: urlString)
                    }
                )
            }
```

- [ ] **Step 4: Add saveWebNote method**

In `voice notes/AIHomeView.swift`, after the `createTypedNote` method (after line 1204), add:

```swift
    // MARK: - Create Web Note

    private func saveWebNote(from urlString: String) {
        isTranscribing = true

        Task {
            do {
                let webContent = try await WebContentService.fetchArticle(from: urlString)

                await MainActor.run {
                    let note = Note(
                        title: webContent.title,
                        content: webContent.text,
                        transcript: webContent.text,
                        audioFileName: nil
                    )
                    note.sourceTypeRaw = NoteSourceType.webArticle.rawValue
                    note.originalURL = webContent.url
                    modelContext.insert(note)
                    UsageService.shared.incrementNoteCount()
                    try? modelContext.save()

                    isTranscribing = false
                    navigateToNote = note

                    // AI processing
                    if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                        let existingTags = tags
                        let allProjects = projects
                        let context = modelContext

                        Task {
                            do {
                                let extractor = TagExtractor(apiKey: apiKey)
                                let tagNames = try await extractor.extractTags(from: webContent.text)

                                await MainActor.run {
                                    for tagName in tagNames {
                                        if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                            if !note.tags.contains(where: { $0.id == existingTag.id }) {
                                                note.tags.append(existingTag)
                                            }
                                        } else {
                                            let newTag = Tag(name: tagName.capitalized)
                                            context.insert(newTag)
                                            note.tags.append(newTag)
                                        }
                                    }

                                    if let match = ProjectMatcher.findMatch(for: webContent.text, in: allProjects) {
                                        note.projectId = match.project.id
                                    }
                                }

                                await intelligenceService.processNoteSave(
                                    note: note,
                                    transcript: webContent.text,
                                    projects: allProjects,
                                    tags: existingTags,
                                    context: context
                                )

                                await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                            } catch {
                                print("Error processing web note: \(error)")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    errorMessage = "Couldn't load that link: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
```

- [ ] **Step 5: Add savePDFNote method**

In `voice notes/AIHomeView.swift`, after the `saveWebNote` method, add:

```swift
    // MARK: - Create PDF/Document Note

    private func savePDFNote(from sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file"
            showingError = true
            return
        }

        isTranscribing = true

        Task {
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            do {
                // Copy file to documents first for reliable access
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
                let localURL = documentsPath.appendingPathComponent(fileName)
                try FileManager.default.copyItem(at: sourceURL, to: localURL)

                let extracted: ExtractedDocument
                if sourceURL.pathExtension.lowercased() == "pdf" {
                    extracted = try await PDFExtractionService.shared.extractText(from: localURL)
                } else {
                    // Plain text file
                    let text = try String(contentsOf: localURL, encoding: .utf8)
                    extracted = ExtractedDocument(
                        text: text,
                        title: sourceURL.deletingPathExtension().lastPathComponent,
                        pageCount: 1,
                        wasOCR: false
                    )
                }

                await MainActor.run {
                    let note = Note(
                        title: extracted.title,
                        content: extracted.text,
                        transcript: extracted.text,
                        audioFileName: nil
                    )
                    note.sourceTypeRaw = NoteSourceType.document.rawValue
                    modelContext.insert(note)
                    UsageService.shared.incrementNoteCount()
                    try? modelContext.save()

                    isTranscribing = false
                    navigateToNote = note

                    // AI processing
                    if let apiKey = APIKeys.openAI, !apiKey.isEmpty {
                        let existingTags = tags
                        let allProjects = projects
                        let context = modelContext

                        Task {
                            do {
                                let title = try await SummaryService.generateTitle(for: extracted.text, apiKey: apiKey)
                                let extractor = TagExtractor(apiKey: apiKey)
                                let tagNames = try await extractor.extractTags(from: extracted.text)

                                await MainActor.run {
                                    note.title = title

                                    for tagName in tagNames {
                                        if let existingTag = existingTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                                            if !note.tags.contains(where: { $0.id == existingTag.id }) {
                                                note.tags.append(existingTag)
                                            }
                                        } else {
                                            let newTag = Tag(name: tagName.capitalized)
                                            context.insert(newTag)
                                            note.tags.append(newTag)
                                        }
                                    }

                                    if let match = ProjectMatcher.findMatch(for: extracted.text, in: allProjects) {
                                        note.projectId = match.project.id
                                    }
                                }

                                await intelligenceService.processNoteSave(
                                    note: note,
                                    transcript: extracted.text,
                                    projects: allProjects,
                                    tags: existingTags,
                                    context: context
                                )

                                await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                            } catch {
                                print("Error processing PDF note: \(error)")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    errorMessage = "Couldn't extract text: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add "voice notes/AIHomeView.swift" "voice notes/SourcePickerSheet.swift"
git commit -m "$(cat <<'EOF'
feat: wire source picker into AIHomeView with web and PDF note creation

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create OnboardingQuizView

**Files:**
- Create: `voice notes/OnboardingQuizView.swift`

Full replacement for `OnboardingPaywallView`. 6 screens with paging TabView, progress bar, role-based social proof, and paywall with StoreKit 2 integration.

- [ ] **Step 1: Create OnboardingQuizView.swift**

```swift
//
//  OnboardingQuizView.swift
//  voice notes
//
//  6-screen progressive profiling onboarding quiz.
//  Screens: Hero → Role → Intent → Social Proof → Features → Paywall
//  Answers are used for in-session social proof only (not persisted).
//

import SwiftUI
import StoreKit

// MARK: - Quiz Data

private enum UserRole: String, CaseIterable {
    case professional = "Working professional"
    case student = "Student"
    case creator = "Creator"
    case founder = "Founder / entrepreneur"
    case other = "Something else"

    var emoji: String {
        switch self {
        case .professional: return "💼"
        case .student: return "📚"
        case .creator: return "🎨"
        case .founder: return "🚀"
        case .other: return "🔧"
        }
    }

    var subtitle: String {
        switch self {
        case .professional: return "Meetings, ideas, decisions"
        case .student: return "Lectures, study notes, research"
        case .creator: return "Ideas, scripts, content planning"
        case .founder: return "Strategy, pitches, team notes"
        case .other: return ""
        }
    }

    var testimonial: String {
        switch self {
        case .professional:
            return "EEON has helped me stop losing action items from meetings. I just talk, and everything is organized."
        case .student:
            return "I record lectures and EEON extracts all the key concepts. It's like having a study partner."
        case .creator:
            return "I dump ideas all day and EEON turns them into structured notes I can actually use."
        case .founder:
            return "Every decision, every commitment — it's all captured and searchable. Game changer."
        case .other:
            return "I never realized how much I was forgetting until EEON started remembering for me."
        }
    }

    var personaName: String {
        switch self {
        case .professional: return "Sarah M., Product Manager"
        case .student: return "Alex K., Graduate Student"
        case .creator: return "Jordan L., Content Creator"
        case .founder: return "Mike R., Startup Founder"
        case .other: return "Taylor S., EEON User"
        }
    }

    var useCases: [String] {
        switch self {
        case .professional: return ["Capture meeting action items", "Search past decisions", "Never miss a follow-up"]
        case .student: return ["Record and review lectures", "Extract key concepts", "Build study notes automatically"]
        case .creator: return ["Capture ideas on the go", "Turn voice into polished drafts", "Organize creative projects"]
        case .founder: return ["Track every decision", "Capture investor call notes", "Search your entire history"]
        case .other: return ["Voice-first note capture", "AI-powered organization", "Searchable memory"]
        }
    }
}

private enum UserIntent: String, CaseIterable {
    case captureIdeas = "Capture ideas on the go"
    case meetings = "Never forget what was said in meetings"
    case secondBrain = "Build a searchable second brain"
    case thinkOutLoud = "Think out loud, get organized text back"
    case other = "Something else"

    var emoji: String {
        switch self {
        case .captureIdeas: return "🎙"
        case .meetings: return "📋"
        case .secondBrain: return "🧠"
        case .thinkOutLoud: return "✍️"
        case .other: return "🔍"
        }
    }
}

// MARK: - OnboardingQuizView

struct OnboardingQuizView: View {
    @State private var currentStep = 0
    @State private var selectedRole: UserRole?
    @State private var selectedIntent: UserIntent?
    @State private var selectedPlan: SubscriptionProduct = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let subscriptionManager = SubscriptionManager.shared
    private let totalSteps = 6

    var body: some View {
        ZStack {
            Color("EEONBackground").ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (hidden on hero screen)
                if currentStep > 0 {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                // Screen content
                TabView(selection: $currentStep) {
                    heroScreen.tag(0)
                    roleScreen.tag(1)
                    intentScreen.tag(2)
                    socialProofScreen.tag(3)
                    featureScreen.tag(4)
                    paywallScreen.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color("EEONAccent"))
                    .frame(width: geo.size.width * CGFloat(currentStep) / CGFloat(totalSteps - 1), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Screen 1: Hero

    private var heroScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon placeholder — use the app's accent color circle with mic
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color("EEONAccent"))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 24)

            Text("Your AI memory for\neverything you say")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color("EEONTextPrimary"))
                .padding(.bottom, 12)

            Text("try for $0")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("EEONAccent"))
                .padding(.bottom, 8)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation { currentStep = 1 }
                } label: {
                    Text("Continue")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color("EEONTextPrimary"))
                        .foregroundStyle(Color("EEONBackground"))
                        .cornerRadius(14)
                }

                Button {
                    OnboardingState.set(.completed)
                } label: {
                    Text("Already have an account?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 2: Role

    private var roleScreen: some View {
        quizScreen(
            header: "Personalizing your EEON...",
            question: "Which best describes you?"
        ) {
            ForEach(UserRole.allCases, id: \.self) { role in
                quizOption(
                    emoji: role.emoji,
                    title: role.rawValue,
                    subtitle: role.subtitle,
                    isSelected: selectedRole == role,
                    action: {
                        selectedRole = role
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { currentStep = 2 }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Screen 3: Intent

    private var intentScreen: some View {
        quizScreen(
            header: "Personalizing your EEON...",
            question: "What brings you to EEON?"
        ) {
            ForEach(UserIntent.allCases, id: \.self) { intent in
                quizOption(
                    emoji: intent.emoji,
                    title: intent.rawValue,
                    subtitle: nil,
                    isSelected: selectedIntent == intent,
                    action: {
                        selectedIntent = intent
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { currentStep = 3 }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Screen 4: Social Proof

    private var socialProofScreen: some View {
        let role = selectedRole ?? .other

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 24)

                    Text("You're in good company!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))

                    // Testimonial card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(role.testimonial)
                            .font(.body)
                            .foregroundStyle(Color("EEONTextPrimary"))
                            .italic()

                        HStack(spacing: 2) {
                            ForEach(0..<5) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                        }

                        Text("— \(role.personaName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Use cases
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(role.useCases, id: \.self) { useCase in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                Text(useCase)
                                    .font(.body)
                                    .foregroundStyle(Color("EEONTextPrimary"))
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            continueButton { withAnimation { currentStep = 4 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 5: Features

    private var featureScreen: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 24)

                    Text("What EEON does for you")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        featureCard(emoji: "🎙", title: "Voice capture", subtitle: "Talk, we handle the rest")
                        featureCard(emoji: "🧠", title: "AI memory", subtitle: "Search everything you've said")
                        featureCard(emoji: "⚡", title: "Instant extraction", subtitle: "Decisions, actions, commitments")
                        featureCard(emoji: "✨", title: "Enhanced notes", subtitle: "Your words, polished")
                        featureCard(emoji: "🔗", title: "Multi-source", subtitle: "Add links, PDFs, files")
                        featureCard(emoji: "💬", title: "Ask anything", subtitle: "Query your entire memory")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            continueButton { withAnimation { currentStep = 5 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 6: Paywall

    private var paywallScreen: some View {
        VStack(spacing: 0) {
            // Close/skip button
            HStack {
                Spacer()
                Button {
                    OnboardingState.set(.completed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Text("Start capturing\nwith EEON")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color("EEONTextPrimary"))
                        .padding(.top, 8)

                    // Feature comparison
                    featureComparisonTable

                    // Plan selector
                    HStack(spacing: 12) {
                        planButton(plan: .annual, label: "Annual", price: "$79.99/yr", perMonth: "$6.67/mo")
                        planButton(plan: .monthly, label: "Monthly", price: "$9.99/mo", perMonth: nil)
                    }

                    // Purchase CTA
                    Button {
                        purchaseSubscription()
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Start my FREE week")
                                    .font(.body.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color("EEONAccent"))
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isPurchasing)

                    // Skip
                    Button {
                        OnboardingState.set(.completed)
                    } label: {
                        Text("Start free with 5 notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Legal
                    Text("Terms of Service • Privacy Policy • Restore Purchases")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Paywall Helpers

    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.caption.weight(.semibold))
                    .frame(width: 50)
                Text("Pro")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color("EEONAccent"))
                    .frame(width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            let features: [(String, Bool, Bool)] = [
                ("Voice capture", true, true),
                ("AI extraction", true, true),
                ("5 free notes", true, true),
                ("Unlimited notes", false, true),
                ("Multi-source ingest", false, true),
                ("AI memory search", false, true),
                ("Post-capture transforms", false, true),
            ]

            ForEach(features, id: \.0) { feature, free, pro in
                HStack {
                    Text(feature)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    featureCheck(enabled: free)
                        .frame(width: 50)
                    featureCheck(enabled: pro)
                        .frame(width: 50)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureCheck(enabled: Bool) -> some View {
        Image(systemName: enabled ? "checkmark.circle.fill" : "minus")
            .font(.subheadline)
            .foregroundStyle(enabled ? Color("EEONAccent") : .secondary)
    }

    private func planButton(plan: SubscriptionProduct, label: String, price: String, perMonth: String?) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(price)
                    .font(.caption.weight(.medium))
                if let perMonth = perMonth {
                    Text(perMonth)
                        .font(.caption2)
                        .foregroundStyle(selectedPlan == plan ? .white.opacity(0.7) : .secondary)
                }
            }
            .foregroundStyle(selectedPlan == plan ? .white : Color("EEONTextPrimary"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedPlan == plan ? Color("EEONAccent") : Color(.systemGray5).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedPlan == plan ? Color("EEONAccent") : Color(.systemGray4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func purchaseSubscription() {
        isPurchasing = true
        Task {
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
            if let product = subscriptionManager.products.first(where: { $0.id == selectedPlan.rawValue }) {
                do {
                    let _ = try await subscriptionManager.purchase(product)
                    await MainActor.run {
                        isPurchasing = false
                        OnboardingState.set(.completed)
                    }
                } catch {
                    await MainActor.run {
                        isPurchasing = false
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            } else {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = "Could not load subscription. Try again."
                    showError = true
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func quizScreen<Content: View>(header: String, question: String, @ViewBuilder options: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer().frame(height: 16)

                    Text(header)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color("EEONAccent"))

                    Text(question)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))
                        .padding(.bottom, 8)

                    options()
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func quizOption(emoji: String, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("EEONTextPrimary"))
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color("EEONAccent"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color("EEONAccent").opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color("EEONAccent").opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func featureCard(emoji: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 32))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("EEONTextPrimary"))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("Continue")
                    .font(.body.weight(.bold))
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color("EEONTextPrimary"))
            .foregroundStyle(Color("EEONBackground"))
            .cornerRadius(14)
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/OnboardingQuizView.swift"
git commit -m "$(cat <<'EOF'
feat: add OnboardingQuizView with 6-screen progressive profiling

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire OnboardingQuizView into voice_notesApp

**Files:**
- Modify: `voice notes/voice_notesApp.swift:118-119`

Point the `needsPaywall` onboarding state to the new quiz view.

- [ ] **Step 1: Update the onboarding switch case**

In `voice notes/voice_notesApp.swift`, find line 118-119:

```swift
                case .needsPaywall:
                    OnboardingPaywallView()
```

Replace with:

```swift
                case .needsPaywall:
                    OnboardingQuizView()
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/voice_notesApp.swift"
git commit -m "$(cat <<'EOF'
feat: wire OnboardingQuizView as the onboarding flow entry point

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Verify and Version Bump

**Files:**
- Verify: Full build and manual review

- [ ] **Step 1: Clean build**

Run: `xcodebuild clean build -scheme "voice notes" -configuration Debug 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify all new files are tracked**

Run: `git status`
Expected: Clean working tree, all files committed.

- [ ] **Step 3: Bump build number**

Find the current build number in the project and increment it. Update version if appropriate per the project convention.

- [ ] **Step 4: Final commit with version bump**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: bump build number for onboarding + multi-source ingest

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```
