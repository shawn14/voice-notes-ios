//
//  KnowledgeBaseView.swift
//  voice notes
//
//  Dedicated screen for reference material (books, articles, domain expertise).
//  Lives in Settings under Personalization, separately from Tune EEON.
//
//  Users add references here via:
//    - Paste a link → WebContentService fetches → becomes a .document Note
//    - Pick a file from Files → PDF / text → becomes a .document Note
//  Both flow through KnowledgeCompiler, which auto-routes them to .reference articles.
//
//  Note: the same references can also be added from the main + button on the home
//  screen (SourcePickerSheet). This screen shows them, lets you manage the library,
//  and provides the "canon / citable" framing.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct KnowledgeBaseView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<KnowledgeArticle> { $0.articleTypeRaw == "reference" },
           sort: [SortDescriptor(\.lastMentionedAt, order: .reverse)])
    private var referenceArticles: [KnowledgeArticle]

    @State private var showAddDialog = false
    @State private var showURLInput = false
    @State private var showFilePicker = false
    @State private var pastedURL = ""
    @State private var isFetchingURL = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        ZStack {
            Color.eeonBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerExplainer
                    addButton

                    if isFetchingURL {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Fetching link…")
                                .font(.caption)
                                .foregroundStyle(.eeonTextSecondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if referenceArticles.isEmpty {
                        emptyState
                    } else {
                        libraryList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Knowledge Base")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Add reference material", isPresented: $showAddDialog, titleVisibility: .visible) {
            Button("Paste a link") { showURLInput = true }
            Button("Pick a file from your phone") { showFilePicker = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add canon — books, articles, domain expertise — that EEON should draw on when answering your questions.")
        }
        .alert("Paste a link", isPresented: $showURLInput) {
            TextField("https://...", text: $pastedURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) { pastedURL = "" }
            Button("Add") {
                let trimmed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
                pastedURL = ""
                guard !trimmed.isEmpty else { return }
                Task { await ingestReferenceURL(trimmed) }
            }
        } message: {
            Text("We'll fetch the page and add it to your knowledge base.")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await ingestReferenceFile(url: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var headerExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your reference library")
                .font(.title2.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
                .lineLimit(nil)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Share books, essays, and domain expertise. EEON will cite these when they're relevant to your questions.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addButton: some View {
        Button {
            showAddDialog = true
        } label: {
            Label("Add reference material", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color("EEONAccent"))
                .cornerRadius(12)
        }
        .disabled(isFetchingURL)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36))
                .foregroundStyle(.brown.opacity(0.5))
            Text("No references yet")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            Text("Paste a link or pick a file to get started. EEON will remember what you add and cite it when it's relevant.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(referenceArticles.count) reference\(referenceArticles.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.eeonTextSecondary)

            ForEach(referenceArticles) { ref in
                NavigationLink(destination: KnowledgeArticleDetailView(article: ref)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "books.vertical.fill")
                            .font(.title3)
                            .foregroundStyle(.brown)
                            .frame(width: 40, height: 40)
                            .background(Color.brown.opacity(0.12))
                            .cornerRadius(10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ref.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.eeonTextPrimary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            if !ref.summary.isEmpty {
                                Text(ref.summary)
                                    .font(.caption)
                                    .foregroundStyle(.eeonTextSecondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 2) {
                            Text("\(ref.mentionCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.brown)
                            Text("uses")
                                .font(.caption2)
                                .foregroundStyle(.eeonTextSecondary)
                        }
                        .fixedSize()
                    }
                    .padding(12)
                    .background(Color.eeonCard)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Ingest

    private func ingestReferenceURL(_ urlString: String) async {
        let normalized = urlString.lowercased().hasPrefix("http") ? urlString : "https://\(urlString)"
        await MainActor.run { isFetchingURL = true }
        defer { Task { @MainActor in isFetchingURL = false } }

        do {
            let content = try await WebContentService.fetchArticle(from: normalized)
            await MainActor.run {
                let note = Note(title: content.title, content: content.text)
                note.sourceType = .document
                note.originalURL = normalized
                modelContext.insert(note)
                try? modelContext.save()

                Task {
                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: content.text,
                        projects: [],
                        tags: [],
                        context: modelContext
                    )
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't fetch that link: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func ingestReferenceFile(url: URL) async {
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let (title, text): (String, String)
            if isPDF {
                let extracted = try await PDFExtractionService.shared.extractText(from: url)
                title = extracted.title
                text = extracted.text
            } else {
                let data = try Data(contentsOf: url)
                title = url.deletingPathExtension().lastPathComponent
                text = String(data: data, encoding: .utf8) ?? ""
            }

            await MainActor.run {
                let note = Note(title: title, content: text)
                note.sourceType = .document
                modelContext.insert(note)
                try? modelContext.save()

                Task {
                    await IntelligenceService.shared.processNoteSave(
                        note: note,
                        transcript: text,
                        projects: [],
                        tags: [],
                        context: modelContext
                    )
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not import: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        KnowledgeBaseView()
            .modelContainer(for: [Note.self, KnowledgeArticle.self], inMemory: true)
    }
}
