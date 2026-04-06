# Knowledge Compounding & Multi-Source Ingest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two biggest knowledge base gaps — saved RAG answers feed back into knowledge articles (compounding loop), and users can share URLs/text from other apps into EEON (multi-source ingest).

**Architecture:** Unified pipeline — add `sourceType` field to Note model. All source types flow through the same IntelligenceService pipeline with extraction depth branching on sourceType. Share extension hands off via SharedDefaults (same pattern as widget). WebContentService fetches article text from URLs.

**Tech Stack:** SwiftUI, SwiftData, CloudKit, OpenAI API (gpt-4o-mini), iOS Share Extension, App Groups

**Spec:** `docs/superpowers/specs/2026-04-06-knowledge-compounding-multi-source-design.md`

---

## File Map

### New Files

| File | Purpose |
|------|---------|
| `voice notes/WebContentService.swift` | Fetch URL → extract article text (HTML strip, 3000 word cap) |
| `EEONShareExtension/ShareViewController.swift` | Share extension entry point (UIKit host for SwiftUI) |
| `EEONShareExtension/ShareView.swift` | SwiftUI share sheet UI (title, preview, annotation, save button) |
| `EEONShareExtension/Info.plist` | Extension configuration (activation rules, supported types) |
| `EEONShareExtension/EEONShareExtension.entitlements` | App Group entitlement |

### Modified Files

| File | Change |
|------|--------|
| `voice notes/Note.swift` | Add `NoteSourceType` enum, `sourceTypeRaw`, `originalURL`, `annotation`, `derivedFromQueryId` fields + computed accessors |
| `voice notes/SharedDefaults.swift` | Add `PendingIngest` struct, `pendingIngests` read/write |
| `voice notes/IntelligenceService.swift` | Branch extraction on sourceType, add pending ingest processing |
| `voice notes/KnowledgeCompiler.swift` | Add source prefix to noteTexts, update compile prompt |
| `voice notes/SummaryService.swift` | Add `extractIntentLightweight()` for web/derived sources |
| `voice notes/AssistantView.swift` | Set sourceType + derivedFromQueryId in `saveAsNote()` |
| `voice notes/AIHomeView.swift` | Add source type badge overlay to `NoteCardRow` |
| `voice notes/NoteDetailView.swift` | Add source type chip in `titleRow`, tappable URL for web articles |
| `voice notes/voice_notesApp.swift` | Add pending ingest check on foreground |

---

## Task 1: Add NoteSourceType and Note Model Fields

**Files:**
- Modify: `voice notes/Note.swift:12-41` (add enum after NoteIntent) and `:96-179` (add fields + accessors)

- [ ] **Step 1: Add NoteSourceType enum to Note.swift**

Add after the `NoteIntent` enum (after line 41):

```swift
// MARK: - Note Source Type

enum NoteSourceType: String, CaseIterable {
    case voice = "voice"
    case webArticle = "web"
    case derived = "derived"

    var badgeIcon: String? {
        switch self {
        case .voice: return nil
        case .webArticle: return "link"
        case .derived: return "sparkles"
        }
    }

    var label: String? {
        switch self {
        case .voice: return nil
        case .webArticle: return "Web Source"
        case .derived: return "Saved from Assistant"
        }
    }
}
```

- [ ] **Step 2: Add new fields to Note model**

Add after the `enhancedNoteText` field (after line 151):

```swift
    // Source type (voice, web article, derived from RAG answer)
    var sourceTypeRaw: String = "voice"
    var originalURL: String?               // For .webArticle — the shared URL
    var annotation: String?                // "Why I saved this" from share sheet
    var derivedFromQueryId: String?        // For .derived — UUID string of the query
```

- [ ] **Step 3: Add computed accessors to Note**

Add in the computed properties section (after the `embedding` computed property, around line 210+):

```swift
    var sourceType: NoteSourceType {
        get { NoteSourceType(rawValue: sourceTypeRaw) ?? .voice }
        set { sourceTypeRaw = newValue.rawValue }
    }
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add "voice notes/Note.swift"
git commit -m "feat: add NoteSourceType enum and source fields to Note model"
```

---

## Task 2: Update SharedDefaults for Pending Ingests

**Files:**
- Modify: `voice notes/SharedDefaults.swift`

- [ ] **Step 1: Add PendingIngest struct and SharedDefaults accessors**

Add at the bottom of `SharedDefaults.swift`, before the closing `}`:

```swift
    // MARK: - Pending Ingests (from Share Extension)

    private static let pendingIngestsKey = "shared_pendingIngests"

    struct PendingIngest: Codable {
        let id: String          // UUID string for deduplication
        let url: String?
        let text: String?
        let title: String?
        let annotation: String?
        let createdAt: Date
    }

    static var pendingIngests: [PendingIngest] {
        get {
            guard let data = suite.data(forKey: pendingIngestsKey) else { return [] }
            return (try? JSONDecoder().decode([PendingIngest].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            suite.set(data, forKey: pendingIngestsKey)
        }
    }

    static func addPendingIngest(_ ingest: PendingIngest) {
        var current = pendingIngests
        current.append(ingest)
        pendingIngests = current
    }

    static func clearPendingIngests() {
        suite.removeObject(forKey: pendingIngestsKey)
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/SharedDefaults.swift"
git commit -m "feat: add PendingIngest to SharedDefaults for share extension handoff"
```

---

## Task 3: Create WebContentService

**Files:**
- Create: `voice notes/WebContentService.swift`

- [ ] **Step 1: Create WebContentService.swift**

```swift
//
//  WebContentService.swift
//  voice notes
//
//  Fetches and extracts readable text content from URLs.
//  Used when processing web articles shared via the share extension.
//

import Foundation

struct WebContent {
    let title: String
    let text: String
    let url: String
}

enum WebContentService {
    enum WebContentError: LocalizedError {
        case invalidURL
        case fetchFailed(String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .fetchFailed(let msg): return "Fetch failed: \(msg)"
            case .noContent: return "No readable content found"
            }
        }
    }

    /// Fetch a URL and extract readable article text.
    /// Caps output at 3000 words to bound extraction + embedding costs.
    static func fetchArticle(from urlString: String) async throws -> WebContent {
        guard let url = URL(string: urlString) else {
            throw WebContentError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WebContentError.fetchFailed("HTTP \(status)")
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? ""

        guard !html.isEmpty else {
            throw WebContentError.noContent
        }

        let title = extractTitle(from: html) ?? url.host ?? "Web Article"
        let text = extractReadableText(from: html)

        guard !text.isEmpty else {
            throw WebContentError.noContent
        }

        // Cap at 3000 words
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let capped = words.prefix(3000).joined(separator: " ")

        return WebContent(title: title, text: capped, url: urlString)
    }

    // MARK: - HTML Extraction

    /// Extract <title> tag content
    private static func extractTitle(from html: String) -> String? {
        guard let titleStart = html.range(of: "<title", options: .caseInsensitive),
              let tagEnd = html.range(of: ">", range: titleStart.upperBound..<html.endIndex),
              let titleEnd = html.range(of: "</title>", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex)
        else { return nil }

        let title = String(html[tagEnd.upperBound..<titleEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Extract readable text from HTML, preferring <article> or <main> content
    private static func extractReadableText(from html: String) -> String {
        // Try <article> first, then <main>, then <body>
        let contentHTML: String
        if let articleContent = extractTagContent(from: html, tag: "article") {
            contentHTML = articleContent
        } else if let mainContent = extractTagContent(from: html, tag: "main") {
            contentHTML = mainContent
        } else if let bodyContent = extractTagContent(from: html, tag: "body") {
            contentHTML = bodyContent
        } else {
            contentHTML = html
        }

        // Remove script and style tags with their content
        var cleaned = contentHTML
        cleaned = removeTagWithContent(from: cleaned, tag: "script")
        cleaned = removeTagWithContent(from: cleaned, tag: "style")
        cleaned = removeTagWithContent(from: cleaned, tag: "nav")
        cleaned = removeTagWithContent(from: cleaned, tag: "header")
        cleaned = removeTagWithContent(from: cleaned, tag: "footer")

        // Strip remaining HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract content between opening and closing tags (first match)
    private static func extractTagContent(from html: String, tag: String) -> String? {
        guard let openStart = html.range(of: "<\(tag)", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: openStart.upperBound..<html.endIndex),
              let closeStart = html.range(of: "</\(tag)>", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex)
        else { return nil }

        return String(html[openEnd.upperBound..<closeStart.lowerBound])
    }

    /// Remove a tag and all its content (handles multiple occurrences)
    private static func removeTagWithContent(from html: String, tag: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/WebContentService.swift"
git commit -m "feat: add WebContentService for URL article text extraction"
```

---

## Task 4: Add Lightweight Extraction to SummaryService

**Files:**
- Modify: `voice notes/SummaryService.swift`

- [ ] **Step 1: Add lightweight extraction method**

Add after the `extractIntent` method (after line 598 in SummaryService.swift):

```swift
    // MARK: - Lightweight Extraction (for web articles and derived notes)

    /// Lighter extraction for non-voice sources — topics, people, summary only.
    /// Skips actions, commitments, unresolved items, next steps.
    static func extractIntentLightweight(text: String, apiKey: String) async throws -> IntentAnalysis {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Analyze this text and extract structured information.
        This is reference material (a web article or saved AI response), NOT a personal voice note.
        Extract topics and people mentioned, but do NOT extract personal actions, commitments, or unresolved items.

        Return ONLY valid JSON:
        {
            "intent": "Idea",
            "intentConfidence": 0.8,
            "mentionedPeople": ["name1", "name2"],
            "topics": ["topic1", "topic2"],
            "emotionalTone": "neutral",
            "enhancedNote": "A clean, concise summary of the content (2-4 sentences)",
            "summary": "One sentence summary",
            "keyPoints": ["point1", "point2"],
            "inferredProject": "project name or null"
        }
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": String(text.prefix(4000))]
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        let result = try JSONDecoder().decode(SummaryChatResponse.self, from: data)

        guard let content = result.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummaryError.parsingError
        }

        let parsed = try JSONDecoder().decode(IntentAnalysisResponse.self, from: jsonData)

        return IntentAnalysis(
            intent: parsed.intent,
            intentConfidence: parsed.intentConfidence,
            subject: nil,
            nextStep: nil,
            nextStepType: "simple",
            missingInfo: [],
            inferredProject: parsed.inferredProject,
            mentionedPeople: parsed.mentionedPeople ?? [],
            topics: parsed.topics ?? [],
            emotionalTone: parsed.emotionalTone,
            enhancedNote: parsed.enhancedNote,
            summary: parsed.summary,
            keyPoints: parsed.keyPoints,
            decisions: [],
            actions: [],
            commitments: [],
            unresolved: []
        )
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: add lightweight extraction for web articles and derived notes"
```

---

## Task 5: Update IntelligenceService for Source-Aware Processing

**Files:**
- Modify: `voice notes/IntelligenceService.swift:44-185`

- [ ] **Step 1: Branch extraction on sourceType in processNoteSave()**

In `IntelligenceService.swift`, replace the extraction call block. Find this code (around line 59-166):

```swift
        // Extract intent (existing SummaryService call)
        do {
            let result = try await SummaryService.extractIntent(text: transcript, apiKey: apiKey)
```

Replace the full `do` block (lines 60-166) with source-type-aware extraction:

```swift
        // Extract intent — branch on source type
        do {
            let result: IntentAnalysis
            if note.sourceType == .voice {
                result = try await SummaryService.extractIntent(text: transcript, apiKey: apiKey)
            } else {
                result = try await SummaryService.extractIntentLightweight(text: transcript, apiKey: apiKey)
            }

            await MainActor.run {
                // Apply extraction to note
                note.intentType = result.intent
                note.intentConfidence = result.intentConfidence

                if note.sourceType == .voice {
                    if let subject = result.subject {
                        note.extractedSubject = ExtractedSubject(
                            topic: subject.topic,
                            action: subject.action
                        )
                    }

                    note.suggestedNextStep = result.nextStep
                    note.nextStepTypeRaw = result.nextStepType
                    note.missingInfo = result.missingInfo.map {
                        MissingInfoItem(field: $0.field, description: $0.description)
                    }
                }

                note.inferredProjectName = result.inferredProject

                // Auto-match project (all source types)
                if let inferredName = result.inferredProject, !inferredName.isEmpty {
                    let textToMatch = "\(inferredName) \(note.content)"
                    if let match = ProjectMatcher.findMatch(for: textToMatch, in: projects) {
                        note.projectId = match.project.id

                        // Update project activity
                        match.project.lastActivityAt = Date()
                        match.project.noteCount += 1
                    }
                }

                // Persist extracted decisions, actions, commitments only for voice notes
                if note.sourceType == .voice {
                    for decision in result.decisions {
                        let item = ExtractedDecision(
                            content: decision.content,
                            affects: decision.affects,
                            confidence: decision.confidence,
                            sourceNoteId: note.id
                        )
                        context.insert(item)
                    }

                    for action in result.actions {
                        let extractedAction = ExtractedAction(
                            content: action.content,
                            owner: action.owner,
                            deadline: action.deadline,
                            sourceNoteId: note.id
                        )
                        context.insert(extractedAction)
                    }

                    for commitment in result.commitments {
                        let item = ExtractedCommitment(
                            who: commitment.who,
                            what: commitment.what,
                            sourceNoteId: note.id
                        )
                        context.insert(item)
                    }
                }

                // Store mentioned people on note (all source types)
                if !result.mentionedPeople.isEmpty {
                    note.mentionedPeople = result.mentionedPeople
                }

                // Store topics and emotional tone (all source types)
                if !result.topics.isEmpty {
                    note.topics = result.topics
                }
                if let tone = result.emotionalTone {
                    note.emotionalTone = tone
                }
                if let enhanced = result.enhancedNote, !enhanced.isEmpty {
                    note.enhancedNoteText = enhanced
                }

                // Persist unresolved items only for voice notes
                if note.sourceType == .voice {
                    for unresolved in result.unresolved {
                        let item = UnresolvedItem(
                            content: unresolved.content,
                            reason: unresolved.reason,
                            sourceNoteId: note.id
                        )
                        context.insert(item)
                    }
                }
            }
        } catch {
            print("Intent extraction failed: \(error)")
        }
```

- [ ] **Step 2: Add pending ingest processing method**

Add after `processNoteSave()` (after the knowledge compiler calls, around line 185):

```swift
    // MARK: - Pending Ingest Processing (from Share Extension)

    /// Process any pending ingests from the share extension.
    /// Called on app foreground before normal refresh.
    func processPendingIngests(context: ModelContext, projects: [Project], tags: [Tag]) async {
        let pending = SharedDefaults.pendingIngests
        guard !pending.isEmpty else { return }

        for ingest in pending {
            do {
                let note: Note

                if let urlString = ingest.url, !urlString.isEmpty {
                    // URL ingest — fetch article content
                    do {
                        let webContent = try await WebContentService.fetchArticle(from: urlString)
                        note = Note(
                            title: ingest.title ?? webContent.title,
                            content: webContent.text
                        )
                        note.originalURL = urlString
                    } catch {
                        // Fetch failed — create note with just the URL
                        print("[IntelligenceService] Web fetch failed for \(urlString): \(error)")
                        note = Note(
                            title: ingest.title ?? "Shared Link",
                            content: urlString
                        )
                        note.originalURL = urlString
                    }
                    note.sourceType = .webArticle
                } else if let text = ingest.text, !text.isEmpty {
                    // Text ingest
                    note = Note(
                        title: ingest.title ?? String(text.prefix(50)),
                        content: text
                    )
                    note.sourceType = .webArticle
                } else {
                    continue
                }

                note.annotation = ingest.annotation

                await MainActor.run {
                    context.insert(note)
                    try? context.save()
                }

                // Run extraction + embedding pipeline
                await processNoteSave(
                    note: note,
                    transcript: note.content,
                    projects: projects,
                    tags: tags,
                    context: context
                )

                // Generate embedding
                try? await EmbeddingService.shared.generateAndStoreEmbedding(for: note)
                await MainActor.run { try? context.save() }

            } catch {
                print("[IntelligenceService] Failed to process pending ingest: \(error)")
            }
        }

        SharedDefaults.clearPendingIngests()
    }
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "voice notes/IntelligenceService.swift"
git commit -m "feat: source-aware extraction branching and pending ingest processing"
```

---

## Task 6: Update KnowledgeCompiler with Source Prefixes

**Files:**
- Modify: `voice notes/KnowledgeCompiler.swift:131-155`

- [ ] **Step 1: Add source prefix to noteTexts in recompileDirtyArticles()**

In `KnowledgeCompiler.swift`, find this block (around line 151-155):

```swift
                let noteTexts = newNotes.map { note -> String in
                    let text = note.enhancedNoteText ?? note.transcript ?? note.content
                    let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
                    return "[\(dateStr)] \(String(text.prefix(500)))"
                }
```

Replace with:

```swift
                let noteTexts = newNotes.map { note -> String in
                    let text = note.enhancedNoteText ?? note.transcript ?? note.content
                    let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
                    let prefix: String
                    switch note.sourceType {
                    case .voice:
                        prefix = "[\(dateStr)]"
                    case .webArticle:
                        prefix = "[WEB SOURCE: \(dateStr)]"
                    case .derived:
                        prefix = "[DERIVED: \(dateStr)]"
                    }
                    return "\(prefix) \(String(text.prefix(500)))"
                }
```

- [ ] **Step 2: Update compile prompt in SummaryService**

In `SummaryService.swift`, find the compile prompt (around line 669-690). Add one line after "Be concise — summaries should be 2-3 sentences max.":

```swift
        WEB SOURCE and DERIVED entries are reference material. They may inform connections and context but should not override summaries or timelines established by primary voice notes.
```

The full line in context becomes:

```swift
        let systemPrompt = """
        You maintain a living knowledge article about a \(articleType.label.lowercased()) named "\(articleName)".
        Update the article with information from the new notes below.
        Preserve existing information unless contradicted by newer notes.
        Be concise — summaries should be 2-3 sentences max.
        WEB SOURCE and DERIVED entries are reference material. They may inform connections and context but should not override summaries or timelines established by primary voice notes.

        Return ONLY valid JSON with this structure:
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "voice notes/KnowledgeCompiler.swift" "voice notes/SummaryService.swift"
git commit -m "feat: add source type prefixes and additive-only prompt for knowledge compiler"
```

---

## Task 7: Update AssistantView saveAsNote for Compounding Loop

**Files:**
- Modify: `voice notes/AssistantView.swift:231-261`

- [ ] **Step 1: Update saveAsNote() to set sourceType**

In `AssistantView.swift`, find the `saveAsNote` method (line 231). Replace the note creation block:

```swift
        let note = Note(
            title: userPrompt,
            content: message.content
        )
        note.intent = .idea
```

With:

```swift
        let note = Note(
            title: userPrompt,
            content: message.content
        )
        note.intent = .idea
        note.sourceType = .derived

        // Link to the question that generated this answer
        if let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
           messageIndex > 0 {
            let previousMessage = messages[messageIndex - 1]
            if previousMessage.role == .user {
                note.derivedFromQueryId = previousMessage.id.uuidString
            }
        }
```

Note: The `userPrompt` variable and its `if let messageIndex` block right above already extracts the user's question as the title. The `derivedFromQueryId` block is separate — it stores the link for future reference. The existing `messageIndex` check for `userPrompt` (lines 233-241) stays as-is; this new block is inside the note configuration section after `note.intent = .idea`.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/AssistantView.swift"
git commit -m "feat: mark saved RAG answers as derived notes for knowledge compounding"
```

---

## Task 8: Add Source Type Badges to AIHomeView

**Files:**
- Modify: `voice notes/AIHomeView.swift:1273-1327` (NoteCardRow)

- [ ] **Step 1: Add source badge overlay to NoteCardRow body**

In `AIHomeView.swift`, find the `NoteCardRow` body (line 1273). The card is wrapped in a VStack with `.background(Color.eeonCard)` and `.cornerRadius(12)`. Add an overlay after `.cornerRadius(12)` (line 1325):

Replace:

```swift
        .cornerRadius(12)
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
```

With:

```swift
        .cornerRadius(12)
        .overlay(alignment: .topTrailing) {
            if let icon = note.sourceType.badgeIcon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.eeonTextSecondary)
                    .padding(6)
            }
        }
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: add source type badge icons to note cards"
```

---

## Task 9: Add Source Type Chip to NoteDetailView

**Files:**
- Modify: `voice notes/NoteDetailView.swift:501-522` (titleRow)

- [ ] **Step 1: Add source chip below the title**

In `NoteDetailView.swift`, find `titleRow` (line 503). Replace the entire `titleRow` computed property:

```swift
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text(note.displayTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(4)

                Spacer()

                // Favorite button
                Button(action: {
                    note.isFavorite.toggle()
                    try? modelContext.save()
                }) {
                    Image(systemName: note.isFavorite ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(note.isFavorite ? .eeonAccent : .eeonTextTertiary)
                }
                .padding(.top, 4)
            }

            // Source type chip
            if let label = note.sourceType.label {
                HStack(spacing: 4) {
                    if let icon = note.sourceType.badgeIcon {
                        Image(systemName: icon)
                            .font(.caption2)
                    }
                    Text(label)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.eeonTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.eeonCard)
                .cornerRadius(6)
            }

            // Tappable original URL for web articles
            if let urlString = note.originalURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                        Text(url.host ?? urlString)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.blue)
                }
            }

            // Annotation if present
            if let annotation = note.annotation, !annotation.isEmpty {
                Text(annotation)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .italic()
            }
        }
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: add source type chip, URL link, and annotation to note detail"
```

---

## Task 10: Wire Pending Ingest Processing into App Foreground

**Files:**
- Modify: `voice notes/voice_notesApp.swift`

- [ ] **Step 1: Find the triggerAppActiveRefresh function**

Search for `triggerAppActiveRefresh` in `voice_notesApp.swift` and locate where the foreground refresh is called.

- [ ] **Step 2: Add pending ingest processing before the existing refresh flow**

At the beginning of `triggerAppActiveRefresh()` (or in the `scenePhase` `.active` handler), add:

```swift
            // Process any pending ingests from share extension
            Task {
                let allProjects = (try? container.mainContext.fetch(FetchDescriptor<Project>())) ?? []
                let allTags = (try? container.mainContext.fetch(FetchDescriptor<Tag>())) ?? []
                await IntelligenceService.shared.processPendingIngests(
                    context: container.mainContext,
                    projects: allProjects,
                    tags: allTags
                )
            }
```

This should run before the existing intelligence refresh calls so any new notes from the share extension are available for the session brief.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "voice notes/voice_notesApp.swift"
git commit -m "feat: process pending share extension ingests on app foreground"
```

---

## Task 11: Create Share Extension Target

**Files:**
- Create: `EEONShareExtension/ShareViewController.swift`
- Create: `EEONShareExtension/ShareView.swift`
- Create: `EEONShareExtension/Info.plist`
- Create: `EEONShareExtension/EEONShareExtension.entitlements`

**Important:** This task requires Xcode project changes (adding a new target). The agent should create the source files, but the Xcode target setup (adding the target, embedding it, configuring signing) must be done in Xcode by the user.

- [ ] **Step 1: Create the share extension directory**

```bash
mkdir -p "EEONShareExtension"
```

- [ ] **Step 2: Create EEONShareExtension.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.eeon.voicenotes</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>NSExtensionActivationRule</key>
			<dict>
				<key>NSExtensionActivationSupportsText</key>
				<true/>
				<key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
				<integer>1</integer>
				<key>NSExtensionActivationSupportsWebPageWithMaxCount</key>
				<integer>1</integer>
			</dict>
		</dict>
		<key>NSExtensionMainStoryboard</key>
		<string>MainInterface</string>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.share-services</string>
	</dict>
	<key>CFBundleDisplayName</key>
	<string>EEON</string>
</dict>
</plist>
```

- [ ] **Step 4: Create ShareViewController.swift**

```swift
//
//  ShareViewController.swift
//  EEONShareExtension
//
//  Receives shared URLs and text from other apps,
//  writes a PendingIngest to SharedDefaults for main app pickup.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ShareView(
            extensionContext: extensionContext
        ))

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}
```

- [ ] **Step 5: Create ShareView.swift**

```swift
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
```

- [ ] **Step 6: Commit the extension source files**

```bash
git add EEONShareExtension/
git commit -m "feat: add EEON share extension source files for multi-source ingest"
```

- [ ] **Step 7: Manual Xcode setup (user action required)**

The following must be done in Xcode:
1. File → New → Target → Share Extension → name it "EEONShareExtension"
2. Replace generated files with the ones created above
3. Set App Group entitlement: `group.com.eeon.voicenotes`
4. Configure signing team (same as main app)
5. Ensure `SharedDefaults.swift` is included in both the main app target AND the share extension target (check Target Membership in the file inspector)
6. Build and test the share extension

---

## Task 12: Final Integration Build & Smoke Test

- [ ] **Step 1: Full clean build**

Run: `xcodebuild clean build -scheme "voice notes" -configuration Debug 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify no regressions in existing knowledge base**

Check that:
- `KnowledgeCompiler.markAffectedArticles()` still works for voice notes (sourceType defaults to `.voice`)
- `RAGService.answerQuestion()` is unchanged — no modifications needed
- `AssistantView` still functions normally with the added sourceType on save

- [ ] **Step 3: Commit version bump**

```bash
# Update version/build number per project convention
git add -A
git commit -m "chore: bump version for knowledge compounding + multi-source ingest"
```
