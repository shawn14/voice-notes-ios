# Editable Enhanced Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit a note's AI-enhanced text inline to fix mistakes (e.g. a misheard name), save the correction, and optionally re-run the full AI pipeline from the corrected text.

**Architecture:** Two new `Note` fields track that the enhanced text was hand-edited. A new `IntelligenceService.reprocessNote` runs extraction + embedding from a supplied source text (the corrected enhanced text), reusing the existing `SummaryService` and `EmbeddingService`, and replacing stale extracted items while preserving completed ones. `NoteDetailView` gains an inline edit mode and always-visible re-run controls.

**Tech Stack:** Swift, SwiftUI, SwiftData, CloudKit. Spec: `docs/superpowers/specs/2026-05-21-editable-enhanced-notes-design.md`.

**Testing note:** This project has no unit-test target (UI tests only — see CLAUDE.md). Each task is verified by `xcodebuild` build success plus manual in-app checks. There are no `XCTest` steps.

**Build command used throughout:**
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected on success: `** BUILD SUCCEEDED **`

---

## Deviations from the spec (read before starting)

1. **`reprocessNote` is a focused sibling of `processNoteSave`, not a generalization of it.** The spec proposed threading a source-text parameter through `processNoteSave`. After reading the code, `processNoteSave` (IntelligenceService.swift:44-210) does first-save-only work that must NOT run on re-run: it increments the daily note counter, auto-creates `KanbanItem`s, runs additive persona extraction, and detects URLs. Threading a mode flag through 165 lines of load-bearing code with 6 call sites is riskier than a focused sibling function. `reprocessNote` reuses the *services* (`SummaryService.extractIntent`, `EmbeddingService`) — which is the substance of "reuse the pipeline" — with its own orchestration.

2. **Re-run does not touch `KanbanItem`s or `UnresolvedItem`s.** Kanban items carry user workflow state (column position, `KanbanMovement` history); duplicating or resetting them on re-run would destroy user work. `UnresolvedItem`s are left as-is to keep scope bounded. Only `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment` are replaced — exactly the spec's stated list.

3. **Re-run does not re-match the note's project.** `processNoteSave` can move a note into a project via `ProjectMatcher`. Re-running should not silently move a note the user has already filed. `reprocessNote` updates `inferredProjectName` (harmless metadata) but never changes `projectId`.

These keep the change bounded and low-risk. If the reviewer wants the broader generalization, that is a separate plan.

---

## File Structure

| File | Change |
|------|--------|
| `voice notes/Note.swift` | Add `enhancedNoteEdited: Bool` and `enhancedNoteEditedAt: Date?` fields |
| `voice notes/EmbeddingService.swift` | Add `generateAndStoreEmbedding(for:text:)` overload that embeds explicit text |
| `voice notes/IntelligenceService.swift` | Add `clearReprocessableItems` helper + `reprocessNote` entry point |
| `voice notes/NoteDetailView.swift` | Inline edit mode, edit/save/cancel controls, "Re-run enhancement" button, point template source at corrected text |

---

## Task 1: Add hand-edited tracking fields to the Note model

**Files:**
- Modify: `voice notes/Note.swift:186-192`

- [ ] **Step 1: Add the two fields after `enhancedNoteText`**

In `voice notes/Note.swift`, the current block at lines 186-192 is:

```swift
    // AI-enhanced version of the note (cleaned up, expanded, well-structured)
    var enhancedNoteText: String?

    // Persona extraction items (Karpathy persona schema). JSON array of {category, content, metadata?}.
    // Populated only when the user's .purpose article has a noteExtractionSchemaJSON.
    // Always additive to the baseline Extracted* models — never replaces them.
    var personaExtractionsJSON: String?
```

Change it to:

```swift
    // AI-enhanced version of the note (cleaned up, expanded, well-structured)
    var enhancedNoteText: String?

    // True when the user has hand-edited enhancedNoteText. Guards the enhanced
    // text from being treated as purely AI-generated, and drives the "edited"
    // UI affordance. Reset to false after a successful AI re-run.
    var enhancedNoteEdited: Bool = false

    // Timestamp of the last hand-edit to enhancedNoteText. nil when never edited
    // or after a successful re-run.
    var enhancedNoteEditedAt: Date?

    // Persona extraction items (Karpathy persona schema). JSON array of {category, content, metadata?}.
    // Populated only when the user's .purpose article has a noteExtractionSchemaJSON.
    // Always additive to the baseline Extracted* models — never replaces them.
    var personaExtractionsJSON: String?
```

Both have a default / are optional, which CloudKit requires for lightweight migration. The `init` does not need changes — Swift uses the declared defaults.

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/Note.swift"
git commit -m "feat: add enhancedNoteEdited tracking fields to Note model"
```

---

## Task 2: Add an explicit-text embedding overload

**Files:**
- Modify: `voice notes/EmbeddingService.swift:81-96`

The existing `generateAndStoreEmbedding(for:)` derives the text to embed from `note.content`/`note.transcript`. Re-run must embed the *corrected enhanced text*, so we need an overload that accepts explicit text.

- [ ] **Step 1: Add the overload after the existing `generateAndStoreEmbedding(for:)`**

In `voice notes/EmbeddingService.swift`, immediately after the closing brace of `generateAndStoreEmbedding(for note: Note)` (line 96) and before the final class closing brace (line 97), add:

```swift

    /// Generate an embedding from explicit text and store it on the note.
    /// Used by re-run, where the embedding must reflect the corrected enhanced
    /// text rather than the original transcript. Fails silently.
    func generateAndStoreEmbedding(for note: Note, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let embedding = try await generateEmbedding(for: trimmed)
            let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            await MainActor.run {
                note.embeddingData = data
            }
        } catch {
            print("[EmbeddingService] Failed to generate embedding (re-run): \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/EmbeddingService.swift"
git commit -m "feat: add explicit-text embedding overload for note re-run"
```

---

## Task 3: Add the re-processing entry point to IntelligenceService

**Files:**
- Modify: `voice notes/IntelligenceService.swift` (add two functions inside the `IntelligenceService` class)

This task adds `clearReprocessableItems` (deletes stale extracted items, preserving completed ones) and `reprocessNote` (the re-run orchestrator). Place both in the `// MARK: - Tier 1` region, immediately after `processNoteSave` ends (after line 210).

- [ ] **Step 1: Add `clearReprocessableItems`**

Insert after line 210 (the closing brace of `processNoteSave`):

```swift

    // MARK: - Re-run (re-process from corrected text)

    /// Result of clearing stale extracted items: the normalized text of the
    /// completed/user-modified items that were PRESERVED, so re-extraction can
    /// skip re-creating them as fresh open items.
    private struct PreservedItems {
        var actionTexts: Set<String> = []
        var commitmentTexts: Set<String> = []
        var decisionTexts: Set<String> = []
    }

    /// Delete the stale, non-completed extracted items for a note so re-extraction
    /// can replace them. Completed `ExtractedAction`/`ExtractedCommitment` and
    /// non-default-status `ExtractedDecision` are preserved (kept in the store)
    /// and their normalized text returned for dedup. Must be called on MainActor.
    private func clearReprocessableItems(for noteId: UUID, context: ModelContext) -> PreservedItems {
        var preserved = PreservedItems()

        let actionDescriptor = FetchDescriptor<ExtractedAction>(
            predicate: #Predicate { $0.sourceNoteId == noteId }
        )
        for action in (try? context.fetch(actionDescriptor)) ?? [] {
            if action.isCompleted {
                preserved.actionTexts.insert(Self.normalizeItemText(action.content))
            } else {
                context.delete(action)
            }
        }

        let commitmentDescriptor = FetchDescriptor<ExtractedCommitment>(
            predicate: #Predicate { $0.sourceNoteId == noteId }
        )
        for commitment in (try? context.fetch(commitmentDescriptor)) ?? [] {
            if commitment.isCompleted {
                preserved.commitmentTexts.insert(Self.normalizeItemText(commitment.what))
            } else {
                context.delete(commitment)
            }
        }

        let decisionDescriptor = FetchDescriptor<ExtractedDecision>(
            predicate: #Predicate { $0.sourceNoteId == noteId }
        )
        for decision in (try? context.fetch(decisionDescriptor)) ?? [] {
            // "Active" is the default status; any other value means the user
            // changed it (Superseded/Reversed/Pending) — preserve those.
            if decision.status == "Active" {
                context.delete(decision)
            } else {
                preserved.decisionTexts.insert(Self.normalizeItemText(decision.content))
            }
        }

        return preserved
    }

    /// Normalize extracted-item text for duplicate detection across a re-run.
    private static func normalizeItemText(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 2: Add `reprocessNote`**

Immediately after the `normalizeItemText` function added in Step 1, add:

```swift

    /// Re-run the AI pipeline on an existing note using `sourceText` (the user's
    /// corrected enhanced text) as input. Full redo: regenerates the enhanced
    /// prose, refreshes intent/subject/topics/tone/people, replaces the
    /// non-completed extracted decisions/actions/commitments, and re-embeds.
    ///
    /// Does NOT touch KanbanItems, UnresolvedItems, or the note's projectId, and
    /// does not increment counters — this is a re-run, not a new note.
    ///
    /// Returns true on success, false if the API key is missing, the source
    /// text is empty, or extraction failed.
    @discardableResult
    func reprocessNote(note: Note, sourceText: String, context: ModelContext) async -> Bool {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty,
              let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            return false
        }

        let result: IntentAnalysis
        do {
            result = try await SummaryService.extractIntent(text: trimmedSource, apiKey: apiKey)
        } catch {
            print("[IntelligenceService] reprocessNote extraction failed: \(error)")
            return false
        }

        await MainActor.run {
            // 1. Clear stale extracted items, keeping completed/user-modified ones.
            let preserved = clearReprocessableItems(for: note.id, context: context)

            // 2. Apply scalar extraction fields.
            note.intentType = result.intent
            note.intentConfidence = result.intentConfidence
            if let subject = result.subject {
                note.extractedSubject = ExtractedSubject(topic: subject.topic, action: subject.action)
            }
            note.suggestedNextStep = result.nextStep
            note.nextStepTypeRaw = result.nextStepType
            note.missingInfo = result.missingInfo.map {
                MissingInfoItem(field: $0.field, description: $0.description)
            }
            note.inferredProjectName = result.inferredProject
            if !result.mentionedPeople.isEmpty {
                note.mentionedPeople = result.mentionedPeople
            }
            if !result.topics.isEmpty {
                note.topics = result.topics
            }
            if let tone = result.emotionalTone {
                note.emotionalTone = tone
            }
            if let enhanced = result.enhancedNote, !enhanced.isEmpty {
                note.enhancedNoteText = enhanced
            }

            // 3. Re-create extracted items, skipping duplicates of preserved ones.
            for decision in result.decisions {
                guard !preserved.decisionTexts.contains(Self.normalizeItemText(decision.content)) else { continue }
                context.insert(ExtractedDecision(
                    content: decision.content,
                    affects: decision.affects,
                    confidence: decision.confidence,
                    sourceNoteId: note.id
                ))
            }
            for action in result.actions {
                guard !preserved.actionTexts.contains(Self.normalizeItemText(action.content)) else { continue }
                context.insert(ExtractedAction(
                    content: action.content,
                    owner: action.owner,
                    deadline: action.deadline,
                    sourceNoteId: note.id
                ))
            }
            for commitment in result.commitments {
                guard !preserved.commitmentTexts.contains(Self.normalizeItemText(commitment.what)) else { continue }
                context.insert(ExtractedCommitment(
                    who: commitment.who,
                    what: commitment.what,
                    sourceNoteId: note.id
                ))
            }

            // 4. The enhanced text is AI-generated again — clear the hand-edited flag.
            note.enhancedNoteEdited = false
            note.enhancedNoteEditedAt = nil
            note.updatedAt = Date()
            try? context.save()
        }

        // 5. Refresh MentionedPerson records from the new people list.
        await processMentionedPeople(for: note, context: context)

        // 6. Re-embed from the corrected source text so search reflects it.
        await EmbeddingService.shared.generateAndStoreEmbedding(for: note, text: trimmedSource)
        await MainActor.run { try? context.save() }

        return true
    }
```

Note: `processMentionedPeople` is a `private` instance method of this same class (IntelligenceService.swift:360), so `reprocessNote` can call it directly.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

If the build fails on a `#Predicate` type-inference error, give the predicate an explicit type: `FetchDescriptor<ExtractedAction>(predicate: #Predicate<ExtractedAction> { $0.sourceNoteId == noteId })`.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/IntelligenceService.swift"
git commit -m "feat: add reprocessNote re-run path with completed-item preservation"
```

---

## Task 4: Inline edit mode in NoteDetailView

**Files:**
- Modify: `voice notes/NoteDetailView.swift` — add state (near line 117), modify `noteBodySection` (lines 669-687), add an edit-controls view

- [ ] **Step 1: Add edit/re-run state**

In `voice notes/NoteDetailView.swift`, after the "Rewrite sheet state" block (lines 116-119):

```swift
    // Rewrite sheet state
    @State private var showingRewriteSheet = false
    @State private var isRewriting = false
    @State private var rewriteError: String?
```

add:

```swift

    // Enhanced-text inline edit + re-run state
    @State private var isEditingEnhanced = false
    @State private var enhancedDraft = ""
    @State private var isReprocessing = false
    @State private var reprocessError: String?
```

- [ ] **Step 2: Replace `noteBodySection` with an edit-aware version**

Replace the entire `noteBodySection` (lines 669-687) with:

```swift
    @ViewBuilder
    private var noteBodySection: some View {
        let displayText: String = {
            if showingOriginal {
                return note.transcript ?? note.content
            } else {
                return note.enhancedNoteText ?? note.transcript ?? note.content
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            if isEditingEnhanced {
                TextEditor(text: $enhancedDraft)
                    .font(.body.leading(.loose))
                    .foregroundStyle(.eeonTextPrimary)
                    .lineSpacing(6)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color.eeonCard)
                    .cornerRadius(12)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isEditingEnhanced = false
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)

                    Spacer()

                    Button("Save") {
                        saveEnhancedEdit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.eeonAccentAI))
                }
            } else {
                if !displayText.isEmpty {
                    Text(displayText)
                        .font(.body.leading(.loose))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Edit + re-run controls — only on the Enhanced view, not Original.
                if !showingOriginal {
                    enhancedEditControls
                }
            }
        }
    }
```

- [ ] **Step 3: Add the `enhancedEditControls` view**

Immediately after the new `noteBodySection` closing brace, add:

```swift

    /// Always-visible Edit + Re-run controls shown beneath the enhanced text.
    @ViewBuilder
    private var enhancedEditControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    enhancedDraft = note.enhancedNoteText ?? note.transcript ?? note.content
                    isEditingEnhanced = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonAccentAI)
                }
                .disabled(isReprocessing)

                Button {
                    runEnhancementRerun()
                } label: {
                    Label("Re-run enhancement", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonAccentAI)
                }
                .disabled(isReprocessing)

                if isReprocessing {
                    ProgressView().scaleEffect(0.7)
                }

                Spacer()
            }

            if note.enhancedNoteEdited {
                Text("Edited")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.eeonTextSecondary)
            }

            if let reprocessError {
                Text(reprocessError)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.top, 4)
    }
```

- [ ] **Step 4: Add the `saveEnhancedEdit` action**

In the `// MARK: - Actions` region (after line 1048), add:

```swift

    /// Persist an inline edit of the enhanced text. No API calls — the user's
    /// text is kept verbatim and the note is marked as hand-edited.
    private func saveEnhancedEdit() {
        let trimmed = enhancedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingEnhanced = false
            return
        }
        note.enhancedNoteText = trimmed
        note.enhancedNoteEdited = true
        note.enhancedNoteEditedAt = Date()
        note.updatedAt = Date()
        try? modelContext.save()
        isEditingEnhanced = false
        reprocessError = nil
    }
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

(Step 3 references `runEnhancementRerun()`, which is added in Task 5. If building this task alone fails on that, complete Task 5 before building. With subagent-driven execution, do Task 4 + Task 5 then build once.)

- [ ] **Step 6: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: inline edit mode for enhanced note text"
```

---

## Task 5: Wire the "Re-run enhancement" action

**Files:**
- Modify: `voice notes/NoteDetailView.swift` — add `runEnhancementRerun` in the `// MARK: - Actions` region

- [ ] **Step 1: Add the `runEnhancementRerun` action**

In the `// MARK: - Actions` region, immediately after `saveEnhancedEdit` (added in Task 4), add:

```swift

    /// Re-run the full AI pipeline from the current enhanced text. Used by the
    /// always-visible "Re-run enhancement" control. The enhanced text (which may
    /// have been hand-corrected) is the source — never the stale transcript.
    private func runEnhancementRerun() {
        let source = note.enhancedNoteText ?? note.transcript ?? note.content
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reprocessError = "Nothing to re-run."
            return
        }
        reprocessError = nil
        isReprocessing = true

        Task {
            let ok = await IntelligenceService.shared.reprocessNote(
                note: note,
                sourceText: source,
                context: modelContext
            )
            await MainActor.run {
                isReprocessing = false
                if !ok {
                    reprocessError = "Couldn't re-run. Check your connection and try again."
                }
            }
        }
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: re-run enhancement action wired to reprocessNote"
```

- [ ] **Step 4: Manual verification**

Build and run in the iOS Simulator (or Xcode). On a note with enhanced text:
1. Tap **Edit** — the enhanced text becomes an editable field with Save/Cancel.
2. Change a word, tap **Save** — text updates, "Edited" label appears, reopen the note: the change persisted. Toggle to **Original**: the transcript still shows the pre-edit text.
3. Tap **Re-run enhancement** — spinner shows, then the enhanced text regenerates and "Edited" disappears.
4. With a completed action item on the note, re-run again — confirm the completed item survives and is not duplicated as an open item.
5. Turn off network, tap **Re-run enhancement** — an inline error appears and the saved text is intact.

---

## Task 6: Point template rewrites at the corrected enhanced text

**Files:**
- Modify: `voice notes/NoteDetailView.swift:1019` (inside `handleRewriteTemplate`)

`handleRewriteTemplate` currently feeds `note.transcript ?? note.content` to `RewriteService`, so a template applied after a correction would re-introduce the misheard name. Point it at the corrected enhanced text.

- [ ] **Step 1: Change the `sourceText` line**

In `handleRewriteTemplate`, the current line 1019 is:

```swift
        let sourceText = note.transcript ?? note.content
```

Change it to:

```swift
        // Prefer the (possibly hand-corrected) enhanced text so templates use
        // the correction. Falls back to transcript/content for notes without
        // enhanced text.
        let sourceText = note.enhancedNoteText ?? note.transcript ?? note.content
```

Leave the rest of `handleRewriteTemplate` unchanged. (Note: it currently stores the template result back into `note.enhancedNoteText`. That pre-existing behavior is out of scope for this plan — see the handoff note. Do not change it here.)

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "fix: template rewrites use corrected enhanced text as source"
```

- [ ] **Step 4: Manual verification**

In the running app: edit a note's enhanced text to fix a name, Save, then open the rewrite sheet (sparkles button) and apply a template. Confirm the template output contains the corrected name.

---

## Task 7: CloudKit schema verification

**Files:** none — verification only.

The new `Note` fields (`enhancedNoteEdited`, `enhancedNoteEditedAt`) are added to an existing `@Model` type, not a new record type, so the schema array in `voice_notesApp.swift` does not change. CloudKit adds new fields to an existing record type via lightweight migration. This task confirms there is no regression and the fields sync.

- [ ] **Step 1: Confirm the schema array is unchanged**

Run:
```bash
grep -n "Note.self" "voice notes/voice_notesApp.swift"
```
Expected: `Note.self` already present in the `Schema([...])` array. No edit needed — adding fields to an existing model does not require a schema-array change or a `cloudKitSchemaSeedDidRun_v*` bump (that key gates new record *types*, per CLAUDE.md).

- [ ] **Step 2: Clean build + launch**

Run:
```bash
xcodebuild clean -scheme "voice notes" >/dev/null 2>&1
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual device verification (required before release)**

Per CLAUDE.md, the simulator cannot sync CloudKit. On a real device signed into iCloud:
1. Edit a note's enhanced text, Save.
2. Confirm the note (with the correction) syncs to a second device or survives an app relaunch.
3. In the CloudKit Dashboard (Development environment), confirm the `CD_Note` record type now lists `CD_enhancedNoteEdited` and `CD_enhancedNoteEditedAt`. Promote via **Deploy Schema Changes** before the production release.

- [ ] **Step 4: Final integration pass**

Re-run the Task 5 Step 4 manual checklist end to end on the clean build. Then confirm `git status` is clean.

---

## Self-Review

**Spec coverage:**
- Edit enhanced text inline → Task 4 (`noteBodySection` edit mode, `enhancedEditControls`, `saveEnhancedEdit`). ✓
- Transcript never modified; edit targets `enhancedNoteText` → `saveEnhancedEdit` writes only `enhancedNoteText`. ✓
- `enhancedNoteEdited` / `enhancedNoteEditedAt` fields + guard semantics → Task 1; set in `saveEnhancedEdit`, cleared in `reprocessNote`. (No background path rewrites `enhancedNoteText` today, so the flag drives the UI "Edited" label and re-run semantics — consistent with the spec, which notes the guard is forward-looking.) ✓
- Full-redo re-run: prose + people + topics + tone + decisions/actions/commitments + embedding → Task 3 `reprocessNote`. ✓
- Re-run controls always visible → `enhancedEditControls` renders whenever the Enhanced view is shown, not gated on prior edit. ✓
- Completed action items preserved → Task 3 `clearReprocessableItems` keeps `isCompleted` actions/commitments; `reprocessNote` skips duplicates. ✓
- `ExtractedDecision` open decision → resolved per spec recommendation: preserve non-`"Active"` status. ✓
- Apply a template uses corrected text → Task 6. ✓
- Re-extraction replaces, does not duplicate → `clearReprocessableItems` deletes non-completed before re-insert. ✓
- Failure handling: saved edit retained, error surfaced, retry possible → `runEnhancementRerun` keeps text, sets `reprocessError`; `reprocessNote` returns `false` on failure without mutating the note. ✓
- CloudKit field sync → Task 7. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Type consistency:** `reprocessNote(note:sourceText:context:)`, `generateAndStoreEmbedding(for:text:)`, `clearReprocessableItems(for:context:) -> PreservedItems`, `normalizeItemText(_:)`, `saveEnhancedEdit()`, `runEnhancementRerun()`, `enhancedEditControls`, `enhancedNoteEdited`/`enhancedNoteEditedAt` — names used identically across all tasks. `IntentAnalysis` field names (`intent`, `intentConfidence`, `subject`, `nextStep`, `nextStepType`, `missingInfo`, `inferredProject`, `decisions`, `actions`, `commitments`, `mentionedPeople`, `topics`, `emotionalTone`, `enhancedNote`) match `processNoteSave`'s usage in IntelligenceService.swift:79-184. ✓

**Known out-of-scope item flagged for the reviewer:** `handleRewriteTemplate` stores template output into `note.enhancedNoteText` rather than `activeRewriteText`/`activeRewriteType`. The spec's data-flow section assumed templates write `activeRewriteText`. This pre-existing inconsistency is left as-is (Task 6 only changes the *input*), to keep this plan bounded. Worth a separate cleanup decision.
