# Post-Capture Transform Surface — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface transform options immediately after transcription so users discover and use them without navigating to a buried tab.

**Architecture:** After transcription completes, instead of dismissing the overlay to home, transition to a `PostCaptureCard` that shows the note title, transcript preview, and horizontal transform chips. Tapping a chip navigates to `NoteDetailView` with the Transform tab pre-selected and auto-triggered. `NoteDetailView` gains two optional init parameters (`initialTab`, `autoTransform`) to support this.

**Tech Stack:** SwiftUI, existing `AITransformType` enum, existing `NoteDetailView`

---

### Task 1: Add `initialTab` and `autoTransform` parameters to NoteDetailView

**Files:**
- Modify: `voice notes/NoteDetailView.swift:64-93`

- [ ] **Step 1: Add parameters to NoteDetailView**

Add two stored properties and update the init. The default values ensure all existing call sites continue to work with zero changes.

```swift
// In NoteDetailView, after line 68 (@Bindable var note: Note):
var initialTab: NoteTab = .insights
var autoTransform: AITransformType? = nil
```

Change the `selectedTab` default on line 74 from:
```swift
@State private var selectedTab: NoteTab = .insights
```
to:
```swift
@State private var selectedTab: NoteTab
```

Add an `init` that wires them together:
```swift
init(note: Note, initialTab: NoteTab = .insights, autoTransform: AITransformType? = nil) {
    self.note = note
    self.initialTab = initialTab
    self.autoTransform = autoTransform
    self._selectedTab = State(initialValue: initialTab)
}
```

- [ ] **Step 2: Add onAppear auto-transform trigger**

Find the `contentView` ViewBuilder (line 324-334). Add an `.onAppear` to the outer view body (or the transform tab's view) that auto-triggers the transform:

At the end of the `body` computed property (after the last modifier), add:

```swift
.onAppear {
    if let transform = autoTransform {
        // Small delay to let the view settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            generateAIContent(type: transform)
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

Verify: All existing `NoteDetailView(note: note)` call sites still compile with no changes (default parameters handle them).

- [ ] **Step 4: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: add initialTab and autoTransform params to NoteDetailView"
```

---

### Task 2: Create PostCaptureCard view

**Files:**
- Create: `voice notes/PostCaptureCard.swift`

- [ ] **Step 1: Create the PostCaptureCard view file**

```swift
//
//  PostCaptureCard.swift
//  voice notes
//
//  Shows transform options after transcription completes
//

import SwiftUI

struct PostCaptureCard: View {
    let note: Note
    let onTransform: (AITransformType) -> Void
    let onViewNote: () -> Void
    let onDismiss: () -> Void

    @State private var dismissTimer: Timer?
    @State private var appeared = false

    // Show these transforms as quick chips (exclude Custom)
    private let quickTransforms: [AITransformType] = [
        .summary, .tweet, .meetingSummary, .executiveSummary, .prd, .ceoReport
    ]

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    // Drag indicator
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 40, height: 5)
                        Spacer()
                    }
                    .padding(.top, 12)

                    // Success indicator + title
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.displayTitle.isEmpty ? "New Note" : note.displayTitle)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if let transcript = note.transcript, !transcript.isEmpty {
                                Text(transcript)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    // Transform chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transform into...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(quickTransforms) { type in
                                    Button {
                                        cancelTimer()
                                        onTransform(type)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: type.icon)
                                                .font(.caption)
                                            Text(type.rawValue)
                                                .font(.caption.weight(.medium))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // View Note button
                    Button {
                        cancelTimer()
                        onViewNote()
                    } label: {
                        HStack {
                            Spacer()
                            Text("View Note")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5).opacity(0.3))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemGray6).opacity(0.95))
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .offset(y: appeared ? 0 : 300)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            startDismissTimer()
        }
        .onDisappear {
            cancelTimer()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        onDismiss()
                    }
                }
        )
    }

    private func startDismissTimer() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { _ in
            DispatchQueue.main.async {
                onDismiss()
            }
        }
    }

    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

Open the project in Xcode or add via the file system — the file is in the `voice notes/` directory alongside other views. SwiftUI previews should pick it up automatically since it's in the same target.

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/PostCaptureCard.swift"
git commit -m "feat: add PostCaptureCard view for post-transcription transforms"
```

---

### Task 3: Wire PostCaptureCard into AIHomeView

**Files:**
- Modify: `voice notes/AIHomeView.swift:46-52` (state), `voice notes/AIHomeView.swift:146-149` (overlay), `voice notes/AIHomeView.swift:763-840` (saveNote)

- [ ] **Step 1: Add state properties**

After the existing recording state block (line 52, `@State private var showingError = false`), add:

```swift
    // Post-capture state
    @State private var completedNote: Note?
    @State private var navigateToNote: Note?
    @State private var navigateTransformType: AITransformType?
```

- [ ] **Step 2: Replace the transcribing overlay with conditional logic**

Replace lines 146-149:
```swift
                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay()
                }
```

with:
```swift
                // Transcribing overlay
                if isTranscribing {
                    HomeTranscribingOverlay()
                }

                // Post-capture transform card
                if let note = completedNote {
                    PostCaptureCard(
                        note: note,
                        onTransform: { type in
                            navigateTransformType = type
                            navigateToNote = note
                            completedNote = nil
                        },
                        onViewNote: {
                            navigateToNote = note
                            navigateTransformType = nil
                            completedNote = nil
                        },
                        onDismiss: {
                            withAnimation {
                                completedNote = nil
                            }
                        }
                    )
                }
```

- [ ] **Step 3: Add navigationDestination for programmatic navigation**

After the existing `.sheet` modifiers (around line 164, after the last `.sheet`), add:

```swift
            .navigationDestination(item: $navigateToNote) { note in
                NoteDetailView(
                    note: note,
                    initialTab: navigateTransformType != nil ? .transform : .insights,
                    autoTransform: navigateTransformType
                )
            }
```

- [ ] **Step 4: Update saveNote to show PostCaptureCard on success**

In the `saveNote` function, find the block where transcription succeeds (around line 808):
```swift
                        isTranscribing = false
                        currentAudioFileName = nil
```

Replace with:
```swift
                        isTranscribing = false
                        currentAudioFileName = nil
                        completedNote = note
```

Also in the error/catch block (around line 829):
```swift
                    await MainActor.run {
                        isTranscribing = false
                        currentAudioFileName = nil
                    }
```
Leave this block unchanged — on failure, no card is shown (as designed).

Also in the else branch for no transcript (around line 834-836):
```swift
            isTranscribing = false
            currentAudioFileName = nil
```
Leave unchanged — no transcript means no card.

- [ ] **Step 5: Clear navigateTransformType after navigation**

To prevent stale state, add an `.onChange` modifier near the other sheet/navigation modifiers:

```swift
            .onChange(of: navigateToNote) { oldValue, newValue in
                if newValue == nil {
                    navigateTransformType = nil
                }
            }
```

- [ ] **Step 6: Build and verify**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manual test on device/simulator**

1. Launch app
2. Record a short voice note
3. After "Understanding your note..." overlay, `PostCaptureCard` should slide up from bottom
4. Verify: note title appears, transcript preview shows, transform chips are visible
5. Tap "Summary" chip → navigates to NoteDetailView on Transform tab with Summary auto-running
6. Go back, record another note, this time tap "View Note" → lands on Insights tab
7. Record another note, wait 8 seconds → card auto-dismisses
8. Record another note, swipe down → card dismisses

- [ ] **Step 8: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: wire PostCaptureCard into post-transcription flow"
```

---

### Task 4: Handle edge case — title not yet generated when card shows

**Files:**
- Modify: `voice notes/AIHomeView.swift`

The title is generated asynchronously after `saveNote()`. The card might show before the title is ready.

- [ ] **Step 1: Observe title changes**

The `PostCaptureCard` takes a `Note` which is an `@Observable` SwiftData model. Since `note.displayTitle` is a computed property on the model, SwiftUI will re-render the card when `note.title` changes. No extra work needed — just verify this works.

**Verification:** Record a note. The card should initially show "New Note" (or whatever `displayTitle` returns for empty title), then update to the AI-generated title once it arrives.

- [ ] **Step 2: Commit (if any changes needed)**

If no code changes were needed (just verification), skip this step.

---

### Task 5: Handle edge case — new recording while card is showing

**Files:**
- Modify: `voice notes/AIHomeView.swift`

- [ ] **Step 1: Dismiss card when recording starts**

In the `toggleRecording()` function, at the start of the recording path, add:

Find the line where `isRecording = true` is set in `toggleRecording()`, and add before it:

```swift
completedNote = nil  // Dismiss any post-capture card
```

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "fix: dismiss post-capture card when new recording starts"
```
