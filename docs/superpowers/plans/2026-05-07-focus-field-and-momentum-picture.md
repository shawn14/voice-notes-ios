# Focus Field + Momentum Picture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a structured `focus` field to Tune EEON (user-declared list of priorities with weights), wire it through `ContextAssembler` and the `.purpose` compile so it influences every AI surface, and add a new `momentumPicture` home section that observes capture activity against stated focus and surfaces drift.

**Architecture:** One nullable JSON field on `KnowledgeArticle` (`focusItemsJSON`) holds an ordered list of `FocusItem` structs. Tune EEON gains a third card with a list editor; tapping a row opens an editor sheet (extends the existing mic+save pattern with weight chips). `ContextAssembler` caches the items and injects them into AI calls that benefit from priority awareness. `MomentumPictureSection` reads `focusItems` and notes to render an activity bar per item plus a drift narration. Everything else stays.

**Tech Stack:** SwiftUI, SwiftData, OpenAI API for compile-time narration only (no per-render LLM calls). CloudKit additive nullable field — no schema deploy required (per project memory `project_extraction_baseline_persona_rule.md`).

**Out of scope:** Voice-parse-from-transcript magic (e.g., parsing "StockAlarm — primary" into structured fields). For v1, mic fills content; user picks weight via chips. Persona-specific momentum primitives beyond builder shape (e.g., `recurringImagery` for dream users — those existing sections suffice). Drag-to-reorder gesture polish (use SwiftUI's built-in `.onMove`).

---

## Background

Conversation on 2026-05-07 reframed the persona-platform architecture: the tune drives every meaningful surface, but `focus` (what the user is prioritizing right now) needs to be explicit user input — not LLM-inferred. It changes weekly, the system needs structure to compute against it, and reordering should be a drag, not a paragraph rewrite.

The mockup at `docs/eeon-tune-focus-mockup.html` defines the visual target. The architectural design at `docs/eeon-persona-platform-mockup.html` defines the broader system. This plan implements the minimum slice that makes the architecture real for the two known users (founder/builder, dream interpreter), without committing to the full catalog expansion yet.

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `voice notes/FocusItem.swift` | new | `FocusItem` struct + `FocusWeight` enum + Codable + JSON helpers |
| `voice notes/KnowledgeArticle.swift` | modify | Add `focusItemsJSON: String?` field + computed `focusItems: [FocusItem]` accessor |
| `voice notes/FocusListEditor.swift` | new | List editor view — drag-to-reorder, tap to edit, "+ Add" affordance |
| `voice notes/FocusItemEditor.swift` | new | Single-item editor sheet — mic + transcript + weight chips + save |
| `voice notes/TuneConversationView.swift` | modify | Add third review card "Your Focus Right Now"; route Edit to list editor |
| `voice notes/ContextAssembler.swift` | modify | Cache `focusItems`; add `AICallContext.includesFocus`; inject into prefix(for:) |
| `voice notes/SummaryService.swift` | modify | Include `focusItems` text in `.purpose` compile prompt context (so LLM knows priorities when picking layout) |
| `voice notes/HomeLayout.swift` | modify | Add `momentumPicture` case to `HomeSectionKind`; add to compile prompt's allowed kindRaw list |
| `voice notes/MomentumPictureSection.swift` | new | The home section view — reads focusItems + notes, renders activity bars + drift narration |
| `voice notes/AIHomeView.swift` | modify | Add dispatch case for `momentumPicture` |
| `voice notes.xcodeproj/project.pbxproj` | modify | Version bump 3.4.0 → 3.5.0, build → 113 |

No SwiftData schema changes that require a CloudKit re-deploy — `focusItemsJSON: String?` is a nullable field on existing model, follows the same pattern as `homeLayoutJSON`, `noteExtractionSchemaJSON`, `voiceAndTone`.

## Testing strategy

Project convention: UI tests only, no unit tests (`CLAUDE.md` → "Testing"). Each task verified by:
1. `xcodebuild -scheme "voice notes" -configuration Debug build` succeeds
2. Manual smoke check on simulator (described per task)

No new test files. No XCTest cases.

---

## Task 1: Define `FocusItem` and `FocusWeight` types

**Files:**
- Create: `voice notes/FocusItem.swift`

**Why:** A typed model with JSON encoding so it can persist to a String field on `KnowledgeArticle` (CloudKit-friendly) and decode synchronously from `ContextAssembler` cache.

- [ ] **Step 1: Create FocusItem.swift**

```swift
//
//  FocusItem.swift
//  voice notes
//
//  Structured user-declared priority item — lives on the .purpose KnowledgeArticle
//  as a JSON-encoded list. Read by ContextAssembler (for prompt injection) and
//  MomentumPictureSection (for activity computation).
//

import Foundation

enum FocusWeight: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
    case tertiary

    var label: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .tertiary: return "Tertiary"
        }
    }
}

struct FocusItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var content: String
    var weight: FocusWeight
    var note: String?

    init(id: UUID = UUID(), content: String, weight: FocusWeight, note: String? = nil) {
        self.id = id
        self.content = content
        self.weight = weight
        self.note = note
    }
}

extension Array where Element == FocusItem {
    /// JSON-encode for persistence on KnowledgeArticle.focusItemsJSON
    var encodedJSON: String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Decode from JSON string. Returns [] on any parse failure.
    static func decode(from json: String?) -> [FocusItem] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([FocusItem].self, from: data)) ?? []
    }
}
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds (file is standalone — no other files reference it yet).

- [ ] **Step 3: Add to Xcode project**

Open `voice notes.xcodeproj` in Xcode, drag `FocusItem.swift` into the `voice notes` group so it gets included in the build target. Save the project. Re-run the build to confirm the file is now compiled.

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds with FocusItem.swift in the compiled set.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/FocusItem.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: add FocusItem + FocusWeight types

Codable struct with JSON helpers for persistence on KnowledgeArticle
and synchronous decoding in ContextAssembler. Three weight tiers:
primary, secondary, tertiary."
```

---

## Task 2: Add `focusItemsJSON` field to `KnowledgeArticle`

**Files:**
- Modify: `voice notes/KnowledgeArticle.swift` — add field next to `noteExtractionSchemaJSON` and `voiceAndTone`

**Why:** Persistence. Mirrors the additive-nullable pattern shipped this morning for `voiceAndTone`.

- [ ] **Step 1: Add field + computed accessor**

In `voice notes/KnowledgeArticle.swift`, locate the existing fields block:

```swift
    // Free-text "voice & tone" directive (only populated on .purpose article — LLM-compiled).
    // ...
    var voiceAndTone: String?
```

Immediately after, add:

```swift
    // Ordered list of user-declared priorities (only populated on .purpose article).
    // JSON-encoded array of FocusItem. Drives MomentumPictureSection and feeds
    // ContextAssembler so AI calls know what the user is currently prioritizing.
    // Independent of voiceAndTone / homeLayoutJSON — those are LLM-compiled,
    // this is user-declared structured input.
    var focusItemsJSON: String?

    /// Typed accessor — decodes focusItemsJSON. Returns [] when unset or invalid.
    @Transient
    var focusItems: [FocusItem] {
        get { [FocusItem].decode(from: focusItemsJSON) }
        set { focusItemsJSON = newValue.encodedJSON }
    }
```

Note: `@Transient` is required because computed properties on SwiftData models are not stored — only the underlying `focusItemsJSON` String is persisted.

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add "voice notes/KnowledgeArticle.swift"
git commit -m "feat: add focusItemsJSON + focusItems accessor on KnowledgeArticle

Nullable JSON-encoded list of user-declared priorities. Additive
field on .purpose article; no schema migration needed (matches
voiceAndTone / homeLayoutJSON / noteExtractionSchemaJSON pattern)."
```

---

## Task 3: Cache `focusItems` in `ContextAssembler`

**Files:**
- Modify: `voice notes/ContextAssembler.swift`

**Why:** Synchronous access from AI call sites without per-call SwiftData fetches.

- [ ] **Step 1: Add cached property**

In `voice notes/ContextAssembler.swift`, in the `@Observable final class ContextAssembler` body, after the `voiceAndTone` declaration, add:

```swift
    /// User-declared focus list — injected into AI calls that benefit from priority awareness
    /// (extraction, RAG, daily brief, analysis). Read by MomentumPictureSection directly
    /// from the .purpose article (this cache is for prompt injection only).
    private(set) var focusItems: [FocusItem] = []
```

- [ ] **Step 2: Add static loader**

In the loaders section, after `loadVoiceAndTone(in:)`, add:

```swift
    @MainActor
    private static func loadFocusItems(in context: ModelContext) -> [FocusItem] {
        let purposeRaw = KnowledgeArticleType.purpose.rawValue
        let descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.articleTypeRaw == purposeRaw }
        )
        guard let article = (try? context.fetch(descriptor))?.first else { return [] }
        return article.focusItems
    }
```

- [ ] **Step 3: Wire into refresh()**

In `refresh(from:)`, add the load call after the voiceAndTone line:

```swift
    @MainActor
    func refresh(from context: ModelContext) {
        purposeDirective = Self.loadPurposeDirective(in: context) ?? ""
        profileContext = Self.loadProfileContext(in: context) ?? ""
        indexContext = Self.loadIndexContext(in: context) ?? ""
        voiceAndTone = Self.loadVoiceAndTone(in: context) ?? ""
        focusItems = Self.loadFocusItems(in: context)
        print("[ContextAssembler] refreshed — purpose=\(String(purposeDirective.prefix(80))) profile=\(String(profileContext.prefix(60))) index=\(String(indexContext.prefix(60))) voice=\(String(voiceAndTone.prefix(60))) focus=\(focusItems.count) items")
    }
```

- [ ] **Step 4: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/ContextAssembler.swift"
git commit -m "feat: cache focusItems in ContextAssembler

Read on launch + after each compile pass. Dispatch to call sites
follows in next commit."
```

---

## Task 4: Inject focus context into AI prompts

**Files:**
- Modify: `voice notes/ContextAssembler.swift`

**Why:** Without dispatch, the cached items are dead weight. Focus belongs in the system message for any call site that benefits from priority awareness — extraction (so the LLM knows what to lift in persona chips), RAG (so answers respect priorities), daily brief (so it leads with the user's stated #1).

- [ ] **Step 1: Add `includesFocus` predicate to AICallContext**

In `voice notes/ContextAssembler.swift`, in the `AICallContext` enum, after `includesVoiceAndTone`, add:

```swift
    /// Whether this call site benefits from the user's declared focus / priorities.
    /// Broad on purpose: priority awareness improves most call sites that work
    /// with the user's actual material. Skipped only for trivial classifiers.
    var includesFocus: Bool {
        switch self {
        case .extraction, .rag, .dailyBrief, .analysis, .rewrite: return true
        case .intent, .title, .tags, .fillerWords: return false
        }
    }
```

- [ ] **Step 2: Build focus-context string + inject into prefix(for:)**

In the same file, the current `prefix(for:)` builds `systemParts`. Replace the current implementation:

```swift
    static func prefix(for callContext: AICallContext) -> AIContextPrefix {
        let shared = ContextAssembler.shared

        var systemParts: [String] = []
        if callContext.includesPurpose && !shared.purposeDirective.isEmpty {
            systemParts.append(shared.purposeDirective)
        }
        if callContext.includesVoiceAndTone && !shared.voiceAndTone.isEmpty {
            systemParts.append(shared.voiceAndTone)
        }
        if callContext.includesFocus && !shared.focusItems.isEmpty {
            systemParts.append(formatFocus(shared.focusItems))
        }
        let system = systemParts.isEmpty ? "" : systemParts.joined(separator: "\n\n") + "\n\n"

        var userPrefixParts: [String] = []
        if callContext.includesProfile {
            if !shared.profileContext.isEmpty {
                userPrefixParts.append(shared.profileContext)
            } else {
                let legacy = AuthService.shared.eeonContextPrefix
                if !legacy.isEmpty { userPrefixParts.append(legacy) }
            }
        }
        if callContext.includesIndex && !shared.indexContext.isEmpty {
            userPrefixParts.append(shared.indexContext)
        }

        let userPrefix = userPrefixParts.isEmpty ? "" : userPrefixParts.joined(separator: "\n\n") + "\n\n"

        return AIContextPrefix(system: system, userPrefix: userPrefix)
    }

    /// Format focus items as a compact directive for prompt injection.
    private static func formatFocus(_ items: [FocusItem]) -> String {
        let lines = items.map { item -> String in
            let note = item.note.flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""
            return "- \(item.content) [\(item.weight.rawValue)]\(note)"
        }
        return "User's current focus, in priority order:\n\(lines.joined(separator: "\n"))"
    }
```

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/ContextAssembler.swift"
git commit -m "feat: dispatch focus context into AI call sites

AICallContext.includesFocus is true for extraction, rag, dailyBrief,
analysis, rewrite. Composes into the system message via prefix(for:)
alongside purposeDirective and voiceAndTone."
```

---

## Task 5: Pass focus to the `.purpose` compile prompt

**Files:**
- Modify: `voice notes/SummaryService.swift` — `compileArticle` body around line 870 where `existingContext` is built

**Why:** When the LLM compiles the `.purpose` article (re-deriving `homeLayoutJSON`, `voiceAndTone`, etc.), it needs to know the user's stated priorities so it can prioritize sections that surface them. Without this, the LLM picks layouts based on only profile + purpose paragraphs and ignores the user's most-current priority statement.

- [ ] **Step 1: Pass focus to compileArticle from KnowledgeCompiler**

This task spans two files because `compileArticle` doesn't currently know about focus. Approach: read focus from the `.purpose` article being compiled and pass it as a separate parameter.

In `voice notes/SummaryService.swift`, locate the `compileArticle` signature (~line 786):

```swift
    static func compileArticle(
        existingSummary: String?,
        existingOpenThreads: [OpenThread],
        existingTimeline: [TimelineEvent],
        existingConnections: [ArticleConnection],
        existingSentimentArc: String?,
        existingDecisions: [ArticleDecision],
        existingRelationshipContext: String?,
        existingThinkingEvolution: String?,
        articleName: String,
        articleType: KnowledgeArticleType,
        newNoteTexts: [String],
        apiKey: String
    ) async throws -> CompileArticleResponse {
```

Add one parameter:

```swift
    static func compileArticle(
        existingSummary: String?,
        existingOpenThreads: [OpenThread],
        existingTimeline: [TimelineEvent],
        existingConnections: [ArticleConnection],
        existingSentimentArc: String?,
        existingDecisions: [ArticleDecision],
        existingRelationshipContext: String?,
        existingThinkingEvolution: String?,
        existingFocusItems: [FocusItem] = [],
        articleName: String,
        articleType: KnowledgeArticleType,
        newNoteTexts: [String],
        apiKey: String
    ) async throws -> CompileArticleResponse {
```

The default `[]` makes existing call sites continue to work without changes.

- [ ] **Step 2: Inject focus into existingContext for `.purpose` compiles**

Inside `compileArticle`, locate where `existingContext` is built (around line 819-845, where it builds the prose context fed to the LLM). After the existing `if let evolution = existingThinkingEvolution` block, add:

```swift
        if articleType == .purpose && !existingFocusItems.isEmpty {
            let focusLines = existingFocusItems.map { item -> String in
                let note = item.note.flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""
                return "- \(item.content) [\(item.weight.rawValue)]\(note)"
            }
            existingContext += "User's currently declared focus (priority order):\n\(focusLines.joined(separator: "\n"))\n"
        }
```

- [ ] **Step 3: Update KnowledgeCompiler call site**

In `voice notes/KnowledgeCompiler.swift`, locate the call to `SummaryService.compileArticle` (search for `compileArticle(`). Modify the call to pass `existingFocusItems`:

```swift
                    let response = try await SummaryService.compileArticle(
                        existingSummary: article.summary.isEmpty ? nil : article.summary,
                        existingOpenThreads: article.openThreads,
                        existingTimeline: article.timeline,
                        existingConnections: article.connections,
                        existingSentimentArc: article.sentimentArc,
                        existingDecisions: article.decisions,
                        existingRelationshipContext: article.relationshipContext,
                        existingThinkingEvolution: article.thinkingEvolution,
                        existingFocusItems: article.focusItems,
                        articleName: article.name,
                        articleType: article.articleType,
                        newNoteTexts: newNotes.map { $0.transcript ?? $0.content },
                        apiKey: apiKey
                    )
```

(Add the `existingFocusItems: article.focusItems` line; leave everything else.)

- [ ] **Step 4: Update the .purpose compile prompt instruction**

In `voice notes/SummaryService.swift`, locate the `.purpose` block in `typeSpecificFields` (around line 858 where the existing instructions for `homeLayoutJSON` and `noteExtractionSchemaJSON` live). Add a sentence to the `homeLayoutJSON` description so the LLM knows to honor focus when it picks sections. Append to the existing `homeLayoutJSON` instruction:

```
" If the user has declared focus items above, the layout should surface sections that make those priorities visible — e.g., if their primary focus is a specific project or theme, lift the section that shows it (priorityProjects for builders, recurringPatterns for dream users, etc.). The user's stated focus is the strongest signal for what to lift."
```

(Edit the `"homeLayoutJSON"` value string at SummaryService.swift line 860 to append this sentence to the existing description, just before the closing quote.)

- [ ] **Step 5: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add "voice notes/SummaryService.swift" "voice notes/KnowledgeCompiler.swift"
git commit -m "feat: pass focusItems as context to .purpose compile

LLM can now read user's declared priorities when (re)compiling
homeLayoutJSON, voiceAndTone, and noteExtractionSchemaJSON, so
the compiled layout surfaces what the user is actively focused on."
```

---

## Task 6: Build `FocusItemEditor` sheet

**Files:**
- Create: `voice notes/FocusItemEditor.swift`

**Why:** Single-item editor matching the existing TuneConversationView editor pattern (mic + transcript + save) plus three weight chips. Reused for both Add and Edit flows.

- [ ] **Step 1: Create FocusItemEditor.swift**

```swift
//
//  FocusItemEditor.swift
//  voice notes
//
//  Sheet editor for one FocusItem — used for both Add and Edit flows
//  in TuneConversationView's third card. Mirrors the existing
//  editor pattern (mic + transcript + save) with weight chips added.
//

import SwiftUI

struct FocusItemEditor: View {
    @Environment(\.dismiss) private var dismiss

    let initialItem: FocusItem?
    let onSave: (FocusItem) -> Void

    @State private var content: String = ""
    @State private var note: String = ""
    @State private var weight: FocusWeight = .primary

    @State private var audioRecorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var currentAudioFileName: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    init(initialItem: FocusItem? = nil, onSave: @escaping (FocusItem) -> Void) {
        self.initialItem = initialItem
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.eeonTextSecondary)
                Spacer()
                Text(initialItem == nil ? "Add Focus" : "Edit Focus")
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
                Spacer()
                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Prompt
                    Text("What do you want EEON to weight as your focus?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.eeonTextPrimary)

                    // Content textarea
                    contentField

                    // Optional note
                    Text("Optional note")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.top, 8)
                    noteField

                    // Weight selector
                    Text("Weight")
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .padding(.top, 8)
                    weightChips
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }

            // Mic + Save dock
            actionBar
        }
        .background(Color.eeonBackground.ignoresSafeArea())
        .overlay { recordingOverlays }
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if let item = initialItem {
                content = item.content
                note = item.note ?? ""
                weight = item.weight
            }
        }
    }

    private var contentField: some View {
        ZStack(alignment: .topLeading) {
            if content.isEmpty {
                Text("StockAlarm…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
            }
            TextEditor(text: $content)
                .font(.body)
                .foregroundStyle(.eeonTextPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 100)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.eeonCard))
    }

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text("Where I want to spend most of my time")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
            }
            TextEditor(text: $note)
                .font(.subheadline)
                .foregroundStyle(.eeonTextPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 60)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.eeonCard))
    }

    private var weightChips: some View {
        HStack(spacing: 8) {
            ForEach(FocusWeight.allCases, id: \.self) { w in
                Button {
                    weight = w
                } label: {
                    Text(w.label)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(weight == w ? Color("EEONAccent") : Color.eeonCard)
                        .foregroundStyle(weight == w ? .white : .eeonTextPrimary)
                        .cornerRadius(10)
                }
            }
            Spacer()
        }
    }

    private var actionBar: some View {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !trimmed.isEmpty

        return HStack(spacing: 12) {
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(Color("EEONAccent"))
                        .frame(width: 56, height: 56)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Button(action: save) {
                Text("Save")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(canSave ? Color("EEONAccent") : Color("EEONAccent").opacity(0.4))
                    )
            }
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.eeonBackground)
    }

    @ViewBuilder
    private var recordingOverlays: some View {
        if isRecording {
            HomeRecordingOverlay(
                onStop: stopRecording,
                onCancel: cancelRecording,
                audioRecorder: audioRecorder
            )
        } else if isTranscribing {
            HomeTranscribingOverlay()
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = FocusItem(
            id: initialItem?.id ?? UUID(),
            content: trimmed,
            weight: weight,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        onSave(item)
        dismiss()
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                errorMessage = "Microphone permission is required."
                showingError = true
                return
            }
            do {
                currentAudioFileName = try audioRecorder.startRecording()
                await MainActor.run { isRecording = true }
            } catch {
                errorMessage = "Could not start recording: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func stopRecording() {
        guard let url = audioRecorder.stopRecording() else {
            errorMessage = "Could not save recording."
            showingError = true
            isRecording = false
            return
        }
        isRecording = false
        isTranscribing = true
        Task { await transcribeAndAppend(url: url) }
    }

    private func cancelRecording() {
        _ = audioRecorder.stopRecording()
        if let fileName = currentAudioFileName {
            audioRecorder.deleteRecording(fileName: fileName)
        }
        isRecording = false
        currentAudioFileName = nil
    }

    private func transcribeAndAppend(url: URL) async {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "OpenAI API key is not configured."
                showingError = true
                isTranscribing = false
            }
            return
        }
        let service = TranscriptionService(apiKey: apiKey, language: LanguageSettings.shared.selectedLanguage)
        do {
            let transcript = try await service.transcribe(audioURL: url)
            await MainActor.run {
                // If content is empty, fill content; else append to note.
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content = transcript
                } else {
                    note = note.isEmpty ? transcript : note + " " + transcript
                }
                isTranscribing = false
            }
            if let fileName = currentAudioFileName {
                audioRecorder.deleteRecording(fileName: fileName)
                await MainActor.run { currentAudioFileName = nil }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showingError = true
                isTranscribing = false
            }
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Drag `FocusItemEditor.swift` into the `voice notes` group in Xcode so it joins the build target.

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/FocusItemEditor.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: FocusItemEditor sheet for add/edit single focus

Reuses existing mic+transcript+save pattern from TuneConversationView,
extends with three weight chips (Primary / Secondary / Tertiary).
Voice fills content first, then appends to optional note."
```

---

## Task 7: Build `FocusListEditor` view

**Files:**
- Create: `voice notes/FocusListEditor.swift`

**Why:** Drag-to-reorder list view shown when the user taps Edit on the Focus card. Uses SwiftUI's built-in `.onMove` and `.onDelete` for native list behavior.

- [ ] **Step 1: Create FocusListEditor.swift**

```swift
//
//  FocusListEditor.swift
//  voice notes
//
//  List editor for FocusItems — shown as a sheet from TuneConversationView's
//  Focus card. Drag to reorder, swipe to delete, tap to edit, "+ Add" button
//  for new items. Auto-saves on every change via the onCommit closure.
//

import SwiftUI

struct FocusListEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var items: [FocusItem]
    let onCommit: ([FocusItem]) -> Void

    @State private var editingItem: FocusItem?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            row(for: item)
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }

                Button {
                    showingAdd = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add focus")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Color("EEONAccent"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color("EEONAccent").opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color.eeonBackground.ignoresSafeArea())
            .navigationTitle("Your Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                FocusItemEditor(initialItem: item) { updated in
                    if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                        items[idx] = updated
                    }
                    commit()
                }
            }
            .sheet(isPresented: $showingAdd) {
                FocusItemEditor(initialItem: nil) { newItem in
                    items.append(newItem)
                    commit()
                }
            }
        }
    }

    private func row(for item: FocusItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .italic()
                }
            }
            Spacer()
            weightBadge(for: item.weight)
        }
        .padding(.vertical, 4)
    }

    private func weightBadge(for weight: FocusWeight) -> some View {
        Text(weight.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor(for: weight))
            .foregroundStyle(badgeText(for: weight))
            .cornerRadius(6)
    }

    private func badgeColor(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return Color("EEONAccent")
        case .secondary: return Color("EEONAccent").opacity(0.18)
        case .tertiary: return Color.eeonTextSecondary.opacity(0.15)
        }
    }

    private func badgeText(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return .white
        case .secondary: return Color("EEONAccent")
        case .tertiary: return Color.eeonTextSecondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color("EEONAccent").opacity(0.5))
            Text("Declare what matters right now.")
                .font(.headline)
                .foregroundStyle(.eeonTextPrimary)
            Text("EEON will surface what's moving against your stated priorities — and call out drift.")
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        commit()
    }

    private func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        commit()
    }

    private func commit() {
        onCommit(items)
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Drag `FocusListEditor.swift` into the `voice notes` group.

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/FocusListEditor.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: FocusListEditor — drag-to-reorder list of focus items

Native SwiftUI .onMove + .onDelete. Tap row to edit via
FocusItemEditor sheet. + Add affordance opens the same editor
in new-item mode. Auto-commits on every change."
```

---

## Task 8: Add Focus card to TuneConversationView

**Files:**
- Modify: `voice notes/TuneConversationView.swift`

**Why:** Surfaces focus to the user. Lives between "About You" and "What EEON Is For You" in the review mode, matching the mockup.

- [ ] **Step 1: Add @Query for purpose article (already there) + new state**

In `voice notes/TuneConversationView.swift`, the file already has `@Query private var purposeArticles: [KnowledgeArticle]`. Reuse it.

In the state declarations section near the top of the struct, after `@State private var lastReextractMessage: String?`, add:

```swift
    // Focus list editor presentation
    @State private var showingFocusEditor = false
```

- [ ] **Step 2: Add a derived accessor for focusItems**

Near `compiledPurposeDirective` (~line 71), add:

```swift
    private var focusItems: [FocusItem] {
        purposeArticles.first?.focusItems ?? []
    }
```

- [ ] **Step 3: Insert the Focus card into review mode**

Locate the `reviewView` body in `TuneConversationView.swift` (~line 135) where the two existing `reviewCard` calls render the Profile and Purpose cards. Insert a new card between them:

```swift
                    reviewCard(
                        icon: "person.crop.circle.fill",
                        iconColor: Color("EEONAccent"),
                        title: "About You",
                        emptyHint: "Tell EEON who you are so it can tailor every answer.",
                        content: profileText,
                        onEdit: { beginEditing(.profile) }
                    )

                    focusReviewCard

                    reviewCard(
                        icon: "scope",
                        iconColor: .indigo,
                        title: "What EEON Is For You",
                        emptyHint: "Your role, your methodology — what EEON should be for you.",
                        content: purposeText,
                        compiledDirective: compiledPurposePreview,
                        onEdit: { beginEditing(.purpose) }
                    )
```

- [ ] **Step 4: Build the focusReviewCard**

Add this private computed view to the struct (anywhere among the other view-builder computed properties):

```swift
    @ViewBuilder
    private var focusReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color("EEONAccent"))
                    .frame(width: 36, height: 36)
                    .background(Color("EEONAccent").opacity(0.12))
                    .cornerRadius(10)
                Text("Your Focus Right Now")
                    .font(.headline)
                    .foregroundStyle(.eeonTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                Button {
                    showingFocusEditor = true
                } label: {
                    Text(focusItems.isEmpty ? "Add" : "Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("EEONAccent"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color("EEONAccent").opacity(0.12))
                        .cornerRadius(10)
                        .fixedSize()
                }
            }

            if focusItems.isEmpty {
                Text("A short list of what you're focused on. EEON shows where you've got traction — and where you're drifting.")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(focusItems) { item in
                        focusRow(for: item)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .sheet(isPresented: $showingFocusEditor) {
            FocusListEditor(items: focusItems) { updated in
                saveFocusItems(updated)
            }
        }
    }

    private func focusRow(for item: FocusItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.eeonTextSecondary)
                        .italic()
                }
            }
            Spacer()
            Text(item.weight.label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor(for: item.weight))
                .foregroundStyle(badgeText(for: item.weight))
                .cornerRadius(6)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.eeonBackground)
        .cornerRadius(8)
    }

    private func badgeColor(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return Color("EEONAccent")
        case .secondary: return Color("EEONAccent").opacity(0.18)
        case .tertiary: return Color.eeonTextSecondary.opacity(0.15)
        }
    }

    private func badgeText(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return .white
        case .secondary: return Color("EEONAccent")
        case .tertiary: return Color.eeonTextSecondary
        }
    }

    private func saveFocusItems(_ items: [FocusItem]) {
        // Find or create the .purpose article
        let purposeArticle: KnowledgeArticle
        if let existing = purposeArticles.first {
            purposeArticle = existing
        } else {
            purposeArticle = KnowledgeArticle(name: "Your Purpose", articleType: .purpose)
            modelContext.insert(purposeArticle)
        }
        purposeArticle.focusItems = items
        purposeArticle.updatedAt = Date()
        // Mark dirty so the next compile picks up the new focus and recompiles homeLayoutJSON
        purposeArticle.isDirty = true
        try? modelContext.save()
        // Refresh ContextAssembler so AI calls in this session see new focus immediately
        ContextAssembler.shared.refresh(from: modelContext)
    }
```

- [ ] **Step 5: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 6: Manual smoke check**

Launch app on simulator → Settings → Tune EEON. The new Focus card should appear between About You and What EEON Is For You. Tap Edit (or Add if empty), add an item, set weight, save. Confirm the row appears in the card with the correct weight badge. Re-open editor, drag-to-reorder, confirm the order persists. Check that `purposeArticles.first?.focusItemsJSON` now contains the JSON via Xcode debugger.

- [ ] **Step 7: Commit**

```bash
git add "voice notes/TuneConversationView.swift"
git commit -m "feat: Focus card in Tune EEON

Third review card between About You and What EEON Is For You.
Tap Edit to open FocusListEditor sheet — drag-to-reorder, tap row
to edit via FocusItemEditor, swipe to delete, + Add. Saves to
.purpose article's focusItems and marks article dirty so next
compile picks up new priorities."
```

---

## Task 9: Add `momentumPicture` section kind to `HomeLayout`

**Files:**
- Modify: `voice notes/HomeLayout.swift`
- Modify: `voice notes/SummaryService.swift` — update the `homeLayoutJSON` prompt's `kindRaw` enumeration

**Why:** The new section needs to be a known kind in the catalog so the LLM can pick it during `.purpose` compile, and the decoder accepts it.

- [ ] **Step 1: Add the case to HomeSectionKind**

In `voice notes/HomeLayout.swift`, in the `enum HomeSectionKind`, add a new case in the project/execution-oriented group (after `openThreads`):

```swift
    case openThreads         // Cross-article open threads (from KnowledgeArticle.openThreads)
    case momentumPicture     // Per-focus-item activity ranking — observation surface for builders/execs
```

- [ ] **Step 2: Add defaultTitle**

In the `defaultTitle` switch, add a case:

```swift
        case .openThreads: return "Open Threads"
        case .momentumPicture: return "Where You Are"
```

- [ ] **Step 3: Update the compile prompt's allowed kindRaw list**

In `voice notes/SummaryService.swift`, find the giant `homeLayoutJSON` instruction string at line ~860. Locate the substring:

```
Allowed kindRaw values: todayThree, priorityProjects, silentProjects, openDecisions, ideaInbox, openThreads, clientRoster, followUpsPerClient, relationshipArcs, recurringPatterns, emotionalToneArc, referenceResonance, activeInquiries, contradictionLedger, knowledgeCarousel, recentNotes, dailyBrief
```

Add `momentumPicture` after `openThreads`:

```
Allowed kindRaw values: todayThree, priorityProjects, silentProjects, openDecisions, ideaInbox, openThreads, momentumPicture, clientRoster, followUpsPerClient, relationshipArcs, recurringPatterns, emotionalToneArc, referenceResonance, activeInquiries, contradictionLedger, knowledgeCarousel, recentNotes, dailyBrief
```

In the same string, find the `FOUNDER example:` substring and update it to include `momentumPicture` first, since this is the new headline section for builders:

```
FOUNDER example: momentumPicture, priorityProjects, openDecisions, ideaInbox, silentProjects, recentNotes
```

- [ ] **Step 4: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds. AIHomeView's switch statement has `@unknown default` (or will fall through to the existing `EmptyView` for unknown cases at lines 1241-1242), so no AIHomeView change is required yet — Task 10 will wire the actual rendering.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/HomeLayout.swift" "voice notes/SummaryService.swift"
git commit -m "feat: add momentumPicture to HomeSectionKind catalog

New section kind that observes per-focus-item capture activity.
Catalog entry + compile-prompt allowlist + FOUNDER example update
so the LLM picks it for builder personas. View dispatch follows
in next commit."
```

---

## Task 10: Build `MomentumPictureSection` view

**Files:**
- Create: `voice notes/MomentumPictureSection.swift`
- Modify: `voice notes/AIHomeView.swift` — add dispatch case

**Why:** The view that actually renders the observation surface — activity bars per focus item, drift narration when capture density doesn't match weight order.

- [ ] **Step 1: Create MomentumPictureSection.swift**

```swift
//
//  MomentumPictureSection.swift
//  voice notes
//
//  Home section that observes capture activity against the user's declared
//  focus items. Renders an activity bar per item plus a one-line drift
//  callout when the user's stated #1 priority doesn't match observed
//  capture density. Pure local computation — no LLM calls.
//

import SwiftUI
import SwiftData

struct MomentumPictureSection: View {
    let title: String
    let rationale: String?
    let focusItems: [FocusItem]
    let notes: [Note]

    private static let lookbackDays: Int = 14

    var body: some View {
        if focusItems.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let activity = computeActivity()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.eeonTextPrimary)
                Spacer()
            }

            if let rationale = rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
                    .padding(.bottom, 4)
            }

            VStack(spacing: 8) {
                ForEach(activity) { row in
                    activityRow(row)
                }
            }

            if let drift = driftMessage(activity) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(drift)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }

    private func activityRow(_ row: ActivityRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                Text("\(row.item.weight.label) · \(row.activityLabel)")
                    .font(.caption2)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Activity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.eeonTextSecondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: row.item.weight))
                        .frame(width: geo.size.width * row.normalizedScore)
                }
            }
            .frame(width: 80, height: 6)
        }
        .padding(.vertical, 4)
    }

    private func barColor(for weight: FocusWeight) -> Color {
        switch weight {
        case .primary: return Color("EEONAccent")
        case .secondary: return Color("EEONAccent").opacity(0.55)
        case .tertiary: return Color.eeonTextSecondary.opacity(0.45)
        }
    }

    // MARK: - Computation

    private struct ActivityRow: Identifiable {
        let item: FocusItem
        let noteCount: Int
        let normalizedScore: Double
        var id: UUID { item.id }
        var activityLabel: String {
            switch noteCount {
            case 0: return "silent"
            case 1: return "1 note"
            default: return "\(noteCount) notes"
            }
        }
    }

    private func computeActivity() -> [ActivityRow] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? Date()
        let recentNotes = notes.filter { $0.createdAt >= cutoff }

        let counts: [FocusItem: Int] = focusItems.reduce(into: [:]) { acc, item in
            let needle = item.content.lowercased()
            let count = recentNotes.filter { note in
                let proj = note.inferredProject?.lowercased() ?? ""
                let content = note.content.lowercased()
                return proj.contains(needle) || content.contains(needle)
            }.count
            acc[item] = count
        }

        let maxCount = max(counts.values.max() ?? 0, 1)
        return focusItems.map { item in
            let count = counts[item] ?? 0
            let normalized = Double(count) / Double(maxCount)
            return ActivityRow(item: item, noteCount: count, normalizedScore: normalized)
        }
    }

    private func driftMessage(_ rows: [ActivityRow]) -> String? {
        // Drift = primary item has fewer captures than a non-primary item.
        guard let primary = rows.first(where: { $0.item.weight == .primary }) else { return nil }
        let dominant = rows.max(by: { $0.noteCount < $1.noteCount })
        guard let dominant else { return nil }

        if dominant.item.id != primary.item.id, dominant.noteCount > primary.noteCount {
            let primaryLabel = primary.noteCount == 0
                ? "hasn't been touched"
                : "got \(primary.noteCount) note\(primary.noteCount == 1 ? "" : "s")"
            return "\(primary.item.content) is your stated primary, but \(dominant.item.content) dominated this week (\(dominant.noteCount) notes). \(primary.item.content) \(primaryLabel)."
        }
        return nil
    }
}
```

- [ ] **Step 2: Wire dispatch in AIHomeView**

In `voice notes/AIHomeView.swift`, locate the `sectionView(for:section:)` switch (line ~1206-1244). Add a new case for `.momentumPicture` (alphabetical order doesn't matter, place after `.openThreads`):

```swift
        case .momentumPicture:
            MomentumPictureSection(
                title: t,
                rationale: section.rationale,
                focusItems: purposeArticles.first?.focusItems ?? [],
                notes: notes
            )
```

- [ ] **Step 3: Add to Xcode project**

Drag `MomentumPictureSection.swift` into the `voice notes` group.

- [ ] **Step 4: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 5: Manual smoke check**

In simulator:
1. Tune EEON → Focus → add 3 items (e.g., "StockAlarm" primary, "EEON" secondary, "Flash AI Cards" tertiary)
2. Capture a few notes mentioning "EEON" and none mentioning "StockAlarm"
3. Recompile (Tune EEON → Generate/Regenerate the lens, or just save the purpose to mark dirty)
4. Return to home — `momentumPicture` should appear with three rows showing different activity levels and a drift callout: "StockAlarm is your stated primary, but EEON dominated this week..."

If `momentumPicture` isn't in the LLM-compiled `homeLayoutJSON` yet, this is expected — re-tune to trigger a recompile and the LLM should pick it up since the FOUNDER example was updated to include it.

- [ ] **Step 6: Commit**

```bash
git add "voice notes/MomentumPictureSection.swift" "voice notes/AIHomeView.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: MomentumPictureSection — observation surface for focus

Per-focus-item activity bars over a 14-day window, with drift
callout when stated primary lags behind observed capture density.
Pure local computation, no LLM calls. Renders only when focusItems
is non-empty."
```

---

## Task 11: Version bump to 3.5.0

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj`

**Why:** Per project memory `feedback_version_bump.md` — bump both marketing version and build number for release. This is a feature release (focus + momentum picture), warrants a minor version bump.

- [ ] **Step 1: Bump versions**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
sed -i '' 's/CURRENT_PROJECT_VERSION = 112;/CURRENT_PROJECT_VERSION = 113;/g; s/MARKETING_VERSION = 3.4.0;/MARKETING_VERSION = 3.5.0;/g' "voice notes.xcodeproj/project.pbxproj"
```

(Note: build 112 was the last shipped iOS build via fastlane on 2026-05-07. Verify current state with the grep below before running sed — if pbxproj has been bumped further by a fastlane lane in the meantime, adjust the source numbers.)

- [ ] **Step 2: Verify all 16 lines bumped**

```bash
grep -nE "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "voice notes.xcodeproj/project.pbxproj" | sort -u
```

Expected: 8 lines `CURRENT_PROJECT_VERSION = 113;` and 8 lines `MARKETING_VERSION = 3.5.0;`. No remaining old values.

- [ ] **Step 3: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to 3.5.0 (build 113) for focus field + momentum picture"
```

---

## Task 12: Ship via Fastlane

**Files:**
- No source modifications. Uses existing `~/projects/fastlane-configs/fastlane/Fastfile` lanes (`beta`, `beta_mac`).

**Why:** Get the build to TestFlight on both platforms. Note: Mac Catalyst lane has a known failure from the previous batch (task #13 in the running todo list — diagnose & fix `beta_mac` packaging) that may need to be resolved before this step can complete for Mac.

- [ ] **Step 1: Ship iOS to TestFlight**

```bash
cd "/Users/shawncarpenter/projects/fastlane-configs"
fastlane beta app:voice-notes
```

Expected: build succeeds, archive completes, upload to TestFlight succeeds. Build number will auto-increment via fastlane's `increment_build_number` (so the local pbxproj will go from 113 to 114).

- [ ] **Step 2: Commit the fastlane build bump**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump build to 114 via fastlane beta upload"
```

- [ ] **Step 3: Diagnose & fix Mac Catalyst lane (task #13)**

The Mac Catalyst `beta_mac` lane failed last batch with a generic packaging error. Investigate via:

```bash
cd "/Users/shawncarpenter/projects/fastlane-configs"
fastlane beta_mac app:voice-notes 2>&1 | tee /tmp/fastlane-mac-debug.log
```

Read the full `/tmp/fastlane-mac-debug.log` for the actual xcodebuild error (the previous run was `tail`-truncated and the real cause was lost). Likely candidates: provisioning profile platform mismatch, signingCertificate identity not found for Mac, or `catalyst_platform` parameter incompatibility with current fastlane version. Fix the lane and re-run.

- [ ] **Step 4: Ship Mac Catalyst once lane is fixed**

```bash
cd "/Users/shawncarpenter/projects/fastlane-configs"
fastlane beta_mac app:voice-notes
```

- [ ] **Step 5: Final verification**

Confirm in App Store Connect that build 113+ for both iOS and macOS appears in TestFlight processing. Promote to App Store via App Store Connect when ready (manual — not part of this plan).

---

## Self-Review

**Spec coverage check:**
- ✅ FocusItem + FocusWeight types — Task 1
- ✅ KnowledgeArticle field + accessor — Task 2
- ✅ ContextAssembler cache + dispatch — Tasks 3, 4
- ✅ Compile prompt awareness — Task 5
- ✅ FocusItemEditor sheet — Task 6
- ✅ FocusListEditor list — Task 7
- ✅ TuneConversationView third card — Task 8
- ✅ HomeLayout catalog entry — Task 9
- ✅ MomentumPictureSection view + dispatch — Task 10
- ✅ Version bump — Task 11
- ✅ Ship — Task 12

**Placeholder scan:** No "TBD", "implement later", or "similar to" without code. All file paths are exact. All code blocks contain the actual code an engineer would type.

**Type consistency:**
- `FocusItem` shape consistent across all references (id/content/weight/note?)
- `FocusWeight` has three cases: `.primary`, `.secondary`, `.tertiary` — used consistently in editor, list, badge color, and bar color
- `focusItemsJSON` (String?) on KnowledgeArticle, computed `focusItems: [FocusItem]` accessor
- `ContextAssembler.focusItems` (Array, not optional)
- `AICallContext.includesFocus` predicate used in `prefix(for:)`
- `MomentumPictureSection` reads `focusItems` and `notes` from AIHomeView's existing queries
- `momentumPicture` is the single name used everywhere — `HomeSectionKind.momentumPicture`, kindRaw `"momentumPicture"`, dispatch case `.momentumPicture`

**Risks called out:**
- Task 11 assumes pbxproj is at 112 — verify before sed.
- Task 12 has a known-broken Mac Catalyst lane (task #13 from prior batch). Don't block on Mac if iOS ships clean.
- Manual smoke checks rely on the LLM picking `momentumPicture` during compile — if it doesn't, re-tune the purpose to trigger a fresh compile pass.
