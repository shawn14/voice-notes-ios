# Persistent Transforms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make transforms persist on the Note model so the transformed version becomes the primary content, with the original transcript always accessible.

**Architecture:** Add `activeRewriteText` and `activeRewriteType` optional fields to the Note model. Update `generateAIContent` to write through to the model instead of ephemeral `@State`. Modify the Insights tab to show the rewrite as primary content when it exists, with a toggle to view the original.

**Tech Stack:** SwiftUI, SwiftData, existing OpenAI integration

---

### Task 1: Add rewrite fields to Note model

**Files:**
- Modify: `voice notes/Note.swift:95-160`

- [ ] **Step 1: Add the two new properties**

After line 131 (`var mentionedPeopleJSON: String?`), add:

```swift
    // Active rewrite (transform output)
    var activeRewriteText: String?     // The transformed content (nil = no transform applied)
    var activeRewriteType: String?     // "Summary", "Tweet", "PRD", etc.
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

These are optional properties on an existing SwiftData model — no migration needed, no schema array changes needed.

- [ ] **Step 3: Commit**

```bash
git add "voice notes/Note.swift"
git commit -m "feat: add activeRewriteText and activeRewriteType to Note model"
```

---

### Task 2: Update generateAIContent to persist transforms

**Files:**
- Modify: `voice notes/NoteDetailView.swift:767-804`

- [ ] **Step 1: Update generateAIContent to write to the Note model**

Replace the entire `generateAIContent` function (lines 767-804):

```swift
    private func generateAIContent(type: AITransformType, customPrompt: String? = nil) {
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else {
            aiError = "OpenAI API key not configured"
            return
        }

        let sourceText = note.transcript ?? note.content
        guard !sourceText.isEmpty else {
            aiError = "No content to transform"
            return
        }

        let prompt = customPrompt ?? type.prompt

        isGeneratingAI = true

        Task {
            do {
                let result = try await generateWithOpenAI(
                    prompt: prompt,
                    content: sourceText,
                    apiKey: apiKey
                )

                await MainActor.run {
                    note.activeRewriteText = result
                    note.activeRewriteType = type.rawValue
                    note.updatedAt = Date()
                    isGeneratingAI = false
                    // Switch to insights tab to show the result
                    selectedTab = .insights
                }
            } catch {
                await MainActor.run {
                    aiError = "Failed to generate: \(error.localizedDescription)"
                    isGeneratingAI = false
                }
            }
        }
    }
```

Key changes:
- Writes `result` to `note.activeRewriteText` instead of `@State var aiOutput`
- Writes `type.rawValue` to `note.activeRewriteType` instead of `@State var aiOutputType`
- Sets `note.updatedAt`
- Switches to `.insights` tab after completion
- Removed `aiOutputType = type` from the pre-request state (no longer needed)

- [ ] **Step 2: Remove unused @State variables**

Remove these three lines (around lines 89-91):

```swift
    @State private var aiOutput: String?
    @State private var aiOutputType: AITransformType?
```

Keep `@State private var isGeneratingAI = false` and `@State private var aiError: String?` — those are still used.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

This will likely have compile errors from the transform tab still referencing `aiOutput` and `aiOutputType`. That's expected — we fix those in Task 3.

- [ ] **Step 4: Commit (even if there are compile errors — this is an intermediate step)**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: generateAIContent now persists transforms to Note model"
```

---

### Task 3: Update Transform tab to use model fields

**Files:**
- Modify: `voice notes/NoteDetailView.swift:540-630` (transformView)

- [ ] **Step 1: Replace the transform tab output section**

The `transformView` currently reads from `aiOutput` and `aiOutputType`. Update it to read from `note.activeRewriteText` and `note.activeRewriteType`.

Find the `transformView` computed property and replace the output section. The transform chip grid stays the same, but the output section changes.

Replace the entire section from `// Output section` (around line 577) through the closing of the `else` empty state (around line 620) with:

```swift
            // Output section
            if isGeneratingAI {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.blue)
                    Text("Generating...")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let output = note.activeRewriteText, let typeRaw = note.activeRewriteType, !output.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let type = AITransformType(rawValue: typeRaw) {
                            Image(systemName: type.icon)
                                .foregroundStyle(.blue)
                            Text(type.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        // Copy button
                        Button {
                            UIPasteboard.general.string = output
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }

                        // Clear button
                        Button {
                            note.activeRewriteText = nil
                            note.activeRewriteType = nil
                            note.updatedAt = Date()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("Clear")
                            }
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                    }

                    Text(output)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("Select a transform above")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    Text("AI will generate content from your note")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
```

- [ ] **Step 2: Update chip highlighting to use model field**

In the transform chip grid, the chip highlighting currently checks `aiOutputType == type`. Update it to check against the model:

Find:
```swift
                        .foregroundStyle(aiOutputType == type ? .white : .blue)
```
Replace with:
```swift
                        .foregroundStyle(note.activeRewriteType == type.rawValue ? .white : .blue)
```

Find:
```swift
                        .background(aiOutputType == type ? Color.blue : Color.blue.opacity(0.15))
```
Replace with:
```swift
                        .background(note.activeRewriteType == type.rawValue ? Color.blue : Color.blue.opacity(0.15))
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: transform tab reads from persisted model fields"
```

---

### Task 4: Update Insights tab to show rewrite as primary

**Files:**
- Modify: `voice notes/NoteDetailView.swift:366-381` (insightsView content card)

- [ ] **Step 1: Add showingOriginal state**

Add to the state variables block (around line 82, near the other `@State` vars):

```swift
    @State private var showingOriginal = false
```

- [ ] **Step 2: Replace the main content card in insightsView**

Replace the main content card section (lines 368-381):

```swift
            if !note.content.isEmpty || note.transcript != nil {
                VStack(alignment: .leading, spacing: 12) {
                    let displayText = !note.content.isEmpty ? note.content : (note.transcript ?? "")
                    Text(String(displayText.prefix(300)) + (displayText.count > 300 ? "..." : ""))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(12)
            }
```

with:

```swift
            if note.activeRewriteText != nil || !note.content.isEmpty || note.transcript != nil {
                VStack(alignment: .leading, spacing: 8) {
                    // Toggle between rewrite and original
                    if let rewriteType = note.activeRewriteType, note.activeRewriteText != nil {
                        HStack {
                            // Type badge
                            HStack(spacing: 4) {
                                if let type = AITransformType(rawValue: rewriteType) {
                                    Image(systemName: type.icon)
                                        .font(.caption2)
                                }
                                Text(rewriteType)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(6)

                            Spacer()

                            Button {
                                showingOriginal.toggle()
                            } label: {
                                Text(showingOriginal ? "View Rewrite" : "View Original")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    // Content
                    let displayText: String = {
                        if let rewrite = note.activeRewriteText, !showingOriginal {
                            return rewrite
                        }
                        return !note.content.isEmpty ? note.content : (note.transcript ?? "")
                    }()

                    Text(showingOriginal ? displayText : (String(displayText.prefix(500)) + (displayText.count > 500 ? "..." : "")))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(12)
            }
```

Key behaviors:
- If a rewrite exists: shows type badge ("Summary") + "View Original" toggle
- Default shows the rewrite text (up to 500 chars with ellipsis)
- Toggling to "View Original" shows the full transcript
- If no rewrite: shows content/transcript as before (no badge, no toggle)

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: insights tab shows rewrite as primary with original toggle"
```

---

### Task 5: Update autoTransform to work with new model

**Files:**
- Modify: `voice notes/NoteDetailView.swift:241-247`

- [ ] **Step 1: Update the onAppear auto-transform**

The current `onAppear` triggers `generateAIContent` which now writes to the model. This should work as-is, but we should also skip auto-transform if the note already has a rewrite of the same type (to avoid re-generating on every appear).

Replace the onAppear block:

```swift
        .onAppear {
            if let transform = autoTransform {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    generateAIContent(type: transform)
                }
            }
        }
```

with:

```swift
        .onAppear {
            if let transform = autoTransform,
               note.activeRewriteType != transform.rawValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    generateAIContent(type: transform)
                }
            }
        }
```

This skips re-generating if the note already has the same transform type active.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual test on device/simulator**

1. Record a voice note
2. After PostCaptureCard appears, tap "Summary"
3. Should navigate to NoteDetailView — Insights tab shows the summary with a "Summary" badge
4. Tap "View Original" — should show the raw transcript
5. Tap "View Rewrite" — back to summary
6. Go to Transform tab — "Summary" chip should be highlighted
7. Tap "Tweet" — should regenerate, switch back to Insights tab showing tweet
8. Leave the note, come back — the tweet should still be there (persisted!)
9. On Transform tab, tap "Clear" — rewrite removed, original transcript shows

- [ ] **Step 4: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: skip auto-transform if note already has the same rewrite type"
```
