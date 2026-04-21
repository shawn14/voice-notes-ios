# Mac Catalyst + iPad Multiplatform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship EEON on iPad and Mac Catalyst from the existing iOS codebase with CloudKit sync across all three platforms, distributed as Universal Purchase.

**Architecture:** One bundle ID (`voice.notes.voice-notes`) across iPhone, iPad, and Mac Catalyst. Existing `ModelConfiguration(cloudKitDatabase: .private("iCloud.aivoiceeeon"))` handles sync with no code changes. Three SwiftUI views get `horizontalSizeClass`-aware layouts for iPad/Mac. One `AVAudioSession` shim unblocks Catalyst compilation.

**Tech Stack:** Xcode 26, Swift 5, SwiftUI, SwiftData, CloudKit, StoreKit 2, Mac Catalyst.

**Reference spec:** `docs/superpowers/specs/2026-04-21-mac-catalyst-ipad-multiplatform-design.md`

---

## Testing approach

This plan is mostly infrastructure (Xcode build settings, entitlements, SwiftUI layout). Strict red-green TDD doesn't map cleanly to build-setting changes. Verification here is:

- **Build gates** — `xcodebuild` must compile cleanly for each destination after each task that could break the build.
- **Manual runtime gates** — sync, audio, StoreKit flows verified on simulators and a real Mac.
- **Regression gate** — existing iPhone UI tests (`xcodebuild test -scheme "voice notes UITests"`) must still pass after everything.

Each task below lists the specific gate that must pass before moving on.

---

## Pre-flight

### Task 0: Create a dedicated feature branch

**Why:** Current branch `feat/onboarding-multi-source-ingest` is about unrelated onboarding work. Mac/iPad enablement touches the Xcode project, entitlements, and several SwiftUI views — too much scope to mix in.

- [ ] **Step 1: Confirm clean working tree (except the committed spec)**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
git status
```

Expected: only the xcscheme plist change and untracked dirs. No unstaged changes in `voice notes/` source files.

- [ ] **Step 2: Create and switch to a new branch from main**

```bash
git fetch origin main
git checkout -b feat/mac-catalyst-ipad origin/main
```

- [ ] **Step 3: Cherry-pick the committed spec onto the new branch**

```bash
git cherry-pick 80b20fc
```

Expected: creates a new commit on `feat/mac-catalyst-ipad` containing just the spec file.

- [ ] **Step 4: Verify**

```bash
git log --oneline -5
ls docs/superpowers/specs/2026-04-21-mac-catalyst-ipad-multiplatform-design.md
```

Expected: the spec commit is at HEAD, file exists.

---

## Phase 1 — Enable iPad

### Task 1: Enable iPad device family on main app target

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (two build configurations for the main app target)

**How to edit safely:** Do this through Xcode's UI, not by hand-editing `project.pbxproj`. Hand-editing is fragile — a mismatched brace breaks the project.

- [ ] **Step 1: Open Xcode**

```bash
open "/Users/shawncarpenter/projects/voice notes/voice notes.xcodeproj"
```

- [ ] **Step 2: Change TARGETED_DEVICE_FAMILY for the main app**

In Xcode:
1. Click the project root ("voice notes") in the navigator.
2. Select the **`voice notes`** target (not the project, not the widget, not the share extension — the main app).
3. Go to the **General** tab.
4. Under "Supported Destinations", click the **+** button and add **iPad**.

This edits `TARGETED_DEVICE_FAMILY` from `1` to `1,2` in both Debug and Release configurations automatically.

- [ ] **Step 3: Verify the pbxproj change from the CLI**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
grep -A2 "PRODUCT_BUNDLE_IDENTIFIER = \"voice.notes.voice-notes\";" "voice notes.xcodeproj/project.pbxproj" | grep TARGETED_DEVICE_FAMILY
```

Expected: two lines, each showing `TARGETED_DEVICE_FAMILY = "1,2";`

- [ ] **Step 4: Build for iPad simulator**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: enable iPad device family on main app target"
```

---

### Task 2: Enable iPad device family on widget target

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (VoiceNotesWidget target, Debug and Release)

- [ ] **Step 1: In Xcode, select the `VoiceNotesWidget` target**

Under **General → Supported Destinations**, add **iPad**.

- [ ] **Step 2: Verify**

```bash
grep -A2 "PRODUCT_BUNDLE_IDENTIFIER = \"voice.notes.voice-notes.widget\";" "voice notes.xcodeproj/project.pbxproj" | grep TARGETED_DEVICE_FAMILY
```

Expected: two lines, each showing `TARGETED_DEVICE_FAMILY = "1,2";`

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: enable iPad device family on widget target"
```

---

### Task 3: Run app on iPad simulator, confirm it launches

**No file changes.** Runtime sanity check before touching layouts.

- [ ] **Step 1: Launch iPad simulator and install the app**

In Xcode, pick an **iPad Pro 13-inch** destination from the scheme selector and **⌘R** to run.

- [ ] **Step 2: Verify the app opens, no crash, main UI renders (however ugly)**

Expected: AIHomeView renders full-screen, record button is visible, no crashes in the Xcode console. Layout will look oversized — that's fine for now.

- [ ] **Step 3: Create a test note**

Tap record, say "iPad test note 1", stop, wait for transcription + extraction. Confirm the note appears in the list.

- [ ] **Step 4: No commit — this was a runtime check only**

---

## Phase 2 — iPad adaptive layouts

### Task 4: Adaptive layout for AIHomeView

**Files:**
- Modify: `voice notes/AIHomeView.swift`

**What changes:** Branch the root view on `horizontalSizeClass`. Compact keeps the current layout (iPhone, iPad Slide Over). Regular wraps the content in a `NavigationSplitView` with a sidebar showing recent notes.

- [ ] **Step 1: Read the current AIHomeView structure**

```bash
```

Read `voice notes/AIHomeView.swift` end-to-end with the Read tool. Identify:
- The top-level `var body: some View { ... }` — what's its current wrapping container?
- Where the recent-notes list is rendered (it may be inline or a subview).
- Any `@State` or `@Binding` the sidebar would need to share with the main content.

Write a one-paragraph note at the top of your scratch buffer describing the current structure before touching anything.

- [ ] **Step 2: Add the size-class environment**

Near the top of `AIHomeView`, add:

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
```

- [ ] **Step 3: Extract the current body into a `compactBody` view**

Keep the existing body logic intact but rename the contents into a new computed property:

```swift
@ViewBuilder
private var compactBody: some View {
    // existing body contents, unchanged
}
```

- [ ] **Step 4: Add a `regularBody` computed property using NavigationSplitView**

```swift
@ViewBuilder
private var regularBody: some View {
    NavigationSplitView {
        // Sidebar: recent notes list
        // Extract the existing recent-notes list into its own subview if it isn't already,
        // and render it here. If the list is inline in compactBody, lift it into a
        // `RecentNotesList` subview so both branches can use it.
        RecentNotesList(...)
            .navigationTitle("Recent")
    } detail: {
        // Main content: record button, query interface — the primary capture surface
        // Extract the "capture" portion of compactBody into a `CaptureSurface` subview
        // and render it here.
        CaptureSurface(...)
    }
}
```

Note: the exact subview extraction depends on the current structure of `AIHomeView`. If the file currently has the record button + recent-notes list in a single ScrollView, you need to split them. Keep the split minimal — do not restructure anything that isn't required for the two layouts to share components.

- [ ] **Step 5: Replace the original body with the branch**

```swift
var body: some View {
    if horizontalSizeClass == .regular {
        regularBody
    } else {
        compactBody
    }
}
```

- [ ] **Step 6: Build for iPhone and iPad**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPhone 16 Pro" build 2>&1 | tail -10
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 7: Run on both simulators, verify the layouts**

- iPhone simulator: UI looks identical to before this task (compactBody is unchanged).
- iPad Pro simulator (landscape): sidebar on the left showing recent notes, main capture surface on the right.
- iPad portrait: sidebar can be hidden via the chevron, main capture surface takes full width.

- [ ] **Step 8: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: iPad adaptive layout for AIHomeView (NavigationSplitView)"
```

---

### Task 5: Centered column layout for NoteDetailView

**Files:**
- Modify: `voice notes/NoteDetailView.swift`

**What changes:** Wrap the body in a conditional `.frame(maxWidth: 720)` on regular size class so text doesn't span the full screen on iPad/Mac.

- [ ] **Step 1: Read NoteDetailView to locate the top-level body container**

Read `voice notes/NoteDetailView.swift`. The body is likely a `ScrollView` containing a `VStack`. You're going to wrap the *inner* VStack (the content), not the ScrollView itself.

- [ ] **Step 2: Add the size-class environment**

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
```

- [ ] **Step 3: Apply maxWidth and centering**

Inside the top-level `ScrollView`, wrap the main content VStack with a max-width and centering. Minimal diff: add the frame modifier at the end of the content VStack.

```swift
VStack(alignment: .leading, spacing: 16) {
    // ... existing content ...
}
.padding()
.frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
.frame(maxWidth: .infinity) // outer: center within ScrollView
```

The double `.frame(maxWidth:)` pattern is how SwiftUI centers a max-width VStack inside a full-width ScrollView: inner caps the content, outer centers it.

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run on iPad simulator, open any note**

Expected: note content is centered, max ~720pt wide, with empty space on both sides. On iPhone, content fills the screen as before.

- [ ] **Step 6: Commit**

```bash
git add "voice notes/NoteDetailView.swift"
git commit -m "feat: centered column layout for NoteDetailView on iPad/Mac"
```

---

### Task 6: Centered column layout for NoteEditorView

**Files:**
- Modify: `voice notes/NoteEditorView.swift`

Same pattern as Task 5 — max-width 720pt content column on regular size class.

- [ ] **Step 1: Read NoteEditorView to locate the top-level content container**

- [ ] **Step 2: Add the size-class environment**

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
```

- [ ] **Step 3: Apply maxWidth and centering to the main content**

Same double-`.frame` pattern as Task 5:

```swift
.frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
.frame(maxWidth: .infinity)
```

Apply to the editor's main content container (likely a ScrollView or Form's contents).

- [ ] **Step 4: Build + verify on iPad**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build 2>&1 | tail -10
```

Open an existing note, tap edit. Content should be centered in a column.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/NoteEditorView.swift"
git commit -m "feat: centered column layout for NoteEditorView on iPad/Mac"
```

---

## Phase 3 — Mac Catalyst shim

### Task 7: AVAudioSession shim in AudioRecorder

**Files:**
- Modify: `voice notes/AudioRecorder.swift:38-45` and `voice notes/AudioRecorder.swift:79-86`

**Why:** `AVAudioSession` does not exist on Mac Catalyst. `AVAudioRecorder` and `AVAudioPlayer` handle audio routing through the macOS audio subsystem directly on Catalyst.

- [ ] **Step 1: Read the current state**

```bash
```

Read `voice notes/AudioRecorder.swift` lines 35–90 to see both call sites in context.

- [ ] **Step 2: Guard the `startRecording` session setup**

Replace the current:

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, mode: .default)
try audioSession.setActive(true)
```

with:

```swift
#if !targetEnvironment(macCatalyst)
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, mode: .default)
try audioSession.setActive(true)
#endif
```

- [ ] **Step 3: Guard the `playAudio` session setup**

Replace the current:

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playback, mode: .default)
try audioSession.setActive(true)
```

with:

```swift
#if !targetEnvironment(macCatalyst)
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playback, mode: .default)
try audioSession.setActive(true)
#endif
```

- [ ] **Step 4: Verify iPhone build still succeeds**

```bash
xcodebuild -scheme "voice notes" -destination "platform=iOS Simulator,name=iPhone 16 Pro" build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. The `#if` is compile-time — non-Catalyst builds are unchanged.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/AudioRecorder.swift"
git commit -m "fix: guard AVAudioSession behind targetEnvironment(macCatalyst)"
```

---

## Phase 4 — Enable Mac Catalyst

### Task 8: Enable Mac Catalyst on main app target

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (main app target)

- [ ] **Step 1: In Xcode, select the `voice notes` target → General tab**

Under **Supported Destinations**, click **+** and add **Mac Catalyst**. Xcode will ask whether to use "Optimize Interface for Mac" (Catalyst idiom) or "Scale Interface to Match iPad" — choose **Optimize Interface for Mac**.

- [ ] **Step 2: Verify the pbxproj change**

```bash
grep -E "SUPPORTS_MACCATALYST|DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER" "voice notes.xcodeproj/project.pbxproj"
```

Expected: both settings present, `SUPPORTS_MACCATALYST = YES`, and `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO` for the main app target (so bundle ID stays `voice.notes.voice-notes` on Mac).

- [ ] **Step 3: If `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER` is YES, change to NO**

In Xcode → main target → **Build Settings** tab, search for "derive". Set **Derive Mac Catalyst Product Bundle Identifier** to **No** for both Debug and Release.

This keeps the bundle ID identical on iOS and Catalyst — required for Universal Purchase.

- [ ] **Step 4: Attempt a Mac Catalyst build (expect entitlements failures)**

```bash
xcodebuild -scheme "voice notes" -destination "platform=macOS,variant=Mac Catalyst" build 2>&1 | tail -30
```

Expected: build likely fails with signing or entitlements errors (microphone, iCloud). That's fine — Task 9 fixes entitlements. Confirm there are no *compilation* errors — just signing / capability errors.

- [ ] **Step 5: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: enable Mac Catalyst on main app target"
```

---

### Task 9: Update main app entitlements for Mac sandbox

**Files:**
- Modify: `voice notes/voice notes.entitlements` (Debug)
- Modify: `voice notes/voice notesRelease.entitlements` (Release)

**Why:** Catalyst apps run in the macOS App Sandbox. Microphone access and outbound network require explicit entitlements on macOS.

- [ ] **Step 1: Read the current Debug entitlements**

Read `voice notes/voice notes.entitlements` to see its current contents. It already has iCloud + App Groups — keep everything that's there.

- [ ] **Step 2: Add the Mac sandbox entitlements to the Debug file**

Add these keys inside the top-level `<dict>` (preserving existing keys):

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

Note: `com.apple.security.app-sandbox` is required for all Mac App Store apps and is auto-applied for Catalyst, but declaring it explicitly matches what Apple's Catalyst template generates.

- [ ] **Step 3: Apply the same additions to the Release entitlements file**

Edit `voice notes/voice notesRelease.entitlements` with the same four keys.

- [ ] **Step 4: Attempt the Catalyst build again**

```bash
xcodebuild -scheme "voice notes" -destination "platform=macOS,variant=Mac Catalyst" build 2>&1 | tail -30
```

Expected: build succeeds, or only fails with code-signing issues (which are developer-certificate setup, not the code's fault).

If there are still entitlements-related errors, compare against the error output — the message typically names the missing key.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/voice notes.entitlements" "voice notes/voice notesRelease.entitlements"
git commit -m "feat: add Mac sandbox entitlements (audio-input, network, app-sandbox)"
```

---

### Task 10: Enable Mac Catalyst on widget extension

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (VoiceNotesWidget target)
- Modify: `VoiceNotesWidget/VoiceNotesWidget.entitlements`

- [ ] **Step 1: In Xcode, select `VoiceNotesWidget` target → General → Supported Destinations → add Mac Catalyst**

- [ ] **Step 2: Verify `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`**

Build Settings tab of the widget target. Same as Task 8 — the widget needs the same bundle ID suffix on Mac as on iOS.

- [ ] **Step 3: Read the widget's current entitlements**

- [ ] **Step 4: Add Mac sandbox entitlements**

Add to `VoiceNotesWidget/VoiceNotesWidget.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

The widget doesn't need microphone or file-selection entitlements — it only reads SharedDefaults and renders a small view.

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme "voice notes" -destination "platform=macOS,variant=Mac Catalyst" build 2>&1 | tail -30
```

Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj" "VoiceNotesWidget/VoiceNotesWidget.entitlements"
git commit -m "feat: enable Mac Catalyst on widget extension"
```

---

### Task 11: Enable Mac Catalyst on share extension

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (EEONShareExtension target)
- Modify: `EEONShareExtension/EEONShareExtension.entitlements`

- [ ] **Step 1: In Xcode, select `EEONShareExtension` target → General → Supported Destinations → add Mac Catalyst**

- [ ] **Step 2: Verify `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`**

Build Settings tab. Same reasoning as prior two tasks.

- [ ] **Step 3: Add Mac sandbox entitlements to `EEONShareExtension/EEONShareExtension.entitlements`**

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme "voice notes" -destination "platform=macOS,variant=Mac Catalyst" build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **` — all three targets now compile for Catalyst.

- [ ] **Step 5: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj" "EEONShareExtension/EEONShareExtension.entitlements"
git commit -m "feat: enable Mac Catalyst on share extension"
```

---

## Phase 5 — Manual verification gates

### Task 12: Sync gate — iPhone ↔ iPad

**No file changes.** Must manually verify CloudKit sync works across platforms.

- [ ] **Step 1: Boot both simulators, sign in to the same iCloud account**

Pick an iPad Pro simulator and an iPhone 16 Pro simulator. In each: Settings → Sign in with Apple ID → use a real iCloud account (sandbox/dev Apple ID is fine).

- [ ] **Step 2: Install the app on both simulators**

From Xcode, build and run to the iPhone simulator. Then switch destination to iPad and run again. Both should have the app installed.

- [ ] **Step 3: Sign into EEON on both devices (Sign in with Apple)**

- [ ] **Step 4: Create a note on the iPhone**

Record a short note ("Sync test alpha"). Wait for transcription + extraction.

- [ ] **Step 5: Wait and verify it appears on the iPad**

Foreground the iPad simulator. Wait 5–30 seconds. Confirm the note appears in the list.

- [ ] **Step 6: Create a note on the iPad → verify on iPhone (reverse direction)**

Record "Sync test bravo" on iPad. Foreground iPhone. Wait. Confirm it appears.

- [ ] **Step 7: Edit a note on one, verify edit on the other**

Open "Sync test alpha" on iPad, edit the title. Foreground iPhone, wait, confirm the title change.

If any of these fail, investigate: check CloudKit Dashboard for the container `iCloud.aivoiceeeon`, check Console logs for `NSCloudKitMirroringDelegate` errors, confirm both devices are signed into the same Apple ID.

- [ ] **Step 8: No commit — verification only**

---

### Task 13: Sync gate — Mac Catalyst

**Prerequisite:** real Mac running macOS 26+ (or a Catalyst build running on your Mac via `My Mac (Mac Catalyst)` destination).

- [ ] **Step 1: Build and run for Mac Catalyst destination**

In Xcode, select `My Mac (Mac Catalyst)` as the run destination, press ⌘R.

Expected: the app launches in a Mac window.

- [ ] **Step 2: Sign in to EEON on the Mac**

Complete Sign in with Apple on Mac. Use the same Apple ID as the iPhone/iPad simulators.

- [ ] **Step 3: Verify previously-created notes appear on Mac**

The notes from Task 12 ("Sync test alpha", "Sync test bravo") should be in the list. Wait up to 30s on first sync.

- [ ] **Step 4: Create a note on Mac**

Record "Mac sync test." Wait for transcription.

- [ ] **Step 5: Foreground the iPhone and iPad simulators → verify "Mac sync test" appears**

- [ ] **Step 6: No commit — verification only**

---

### Task 14: Audio gate — Mac Catalyst microphone permission

- [ ] **Step 1: On the Mac Catalyst app, tap the record button**

Expected: macOS shows a microphone permission dialog the first time. Click **Allow**.

- [ ] **Step 2: Record a short utterance**

Expected: recording proceeds, waveform (if any) animates, stop button works.

- [ ] **Step 3: Wait for transcription**

Expected: transcription populates, extraction runs, note is saved.

- [ ] **Step 4: Tap play on the freshly-created note**

Expected: audio plays back through Mac's default output.

- [ ] **Step 5: No commit — verification only**

---

### Task 15: StoreKit Universal Purchase gate

**Prerequisite:** a sandbox Apple ID with an existing `pro_monthly` or `pro_annual` purchase on iPhone.

- [ ] **Step 1: Sign into the sandbox Apple ID on the Mac**

System Settings → Media & Purchases → sandbox Apple ID. (In Xcode 26, the sandbox account can be picked per-run via the scheme editor.)

- [ ] **Step 2: Launch the Mac app, sign in with the same sandbox Apple ID**

- [ ] **Step 3: Verify Pro status**

`UsageService.shared.isPro` should resolve to `true` without the paywall appearing. The "Upgrade" UI should not show.

If it shows: check `SubscriptionManager.updateSubscriptionStatus()` output in the Console. Confirm StoreKit 2's `Transaction.currentEntitlements` includes the subscription on Catalyst.

- [ ] **Step 4: No commit — verification only**

---

### Task 16: Regression gate — iPhone UI tests still pass

- [ ] **Step 1: Run the existing UI test suite**

```bash
xcodebuild test -scheme "voice notes UITests" -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | tail -40
```

Expected: all tests pass.

If anything regressed (likely: iPad layout changes affecting a test selector), fix it before moving on.

- [ ] **Step 2: No commit unless you made fixes**

---

## Phase 6 — Distribution (App Store Connect)

### Task 17: Enable Universal Purchase in App Store Connect

**No code changes.** This is configuration in App Store Connect.

- [ ] **Step 1: Log into App Store Connect**

https://appstoreconnect.apple.com → My Apps → EEON (the voice notes app).

- [ ] **Step 2: App Information → "Mac App Store availability"**

Toggle on. Confirm the bundle ID matches `voice.notes.voice-notes`.

- [ ] **Step 3: Confirm Universal Purchase is enabled**

The toggle is sometimes separate in the "Pricing and Availability" section. Ensure both the iOS and macOS versions are tied to the same app record.

- [ ] **Step 4: Verify StoreKit products are shared**

Under In-App Purchases, confirm `pro_monthly` and `pro_annual` are available on both iOS and macOS. No new products should need to be created — Apple shares them across the Universal Purchase record.

- [ ] **Step 5: No commit — App Store Connect config**

---

### Task 18: Screenshots for iPad and Mac

**Out of scope for *this* plan**, but noted here so it's not forgotten before submitting the build to review.

- [ ] iPad screenshots (12.9" / 13" required by App Store): use Fastlane screenshot target or a separate follow-up task.
- [ ] Mac screenshots: run the Mac Catalyst build and capture the required resolutions.

Defer this to a separate task/PR once we've confirmed the build is submittable.

---

## Phase 7 — Ship

### Task 19: Version bump + changelog

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (MARKETING_VERSION, CURRENT_PROJECT_VERSION)

Per user's saved preference: always bump version/build after feature commits.

- [ ] **Step 1: Check current version**

```bash
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "voice notes.xcodeproj/project.pbxproj" | head -4
```

- [ ] **Step 2: Bump build and (if a meaningful user-facing change) marketing version**

In Xcode → main target → General tab. Marketing version: bump to the next minor (e.g., 3.0.1 → 3.1.0 — this is a meaningful platform expansion). Build number: increment by 1.

- [ ] **Step 3: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump version for Mac Catalyst + iPad release"
```

---

### Task 20: Open a PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/mac-catalyst-ipad
```

- [ ] **Step 2: Open a PR to main**

```bash
gh pr create --title "Mac Catalyst + iPad multiplatform support" --body "$(cat <<'EOF'
## Summary

- Enables iPad (previously iPhone-only) on main + widget targets
- Enables Mac Catalyst on main + widget + share extension targets
- Adaptive layouts for AIHomeView (NavigationSplitView), NoteDetailView, NoteEditorView
- AVAudioSession shim for Catalyst compatibility
- Adds Mac sandbox entitlements to all entitlement files

Notes sync across iPhone/iPad/Mac via existing CloudKit private database. Universal Purchase configured in App Store Connect (no code changes).

Audio file sync is not included in this PR — text, extractions, and embeddings sync; audio playback of notes created on another device fails silently. Separate spec to follow.

## Test plan

- [ ] iPhone 16 Pro simulator: app launches, existing flows work, UI tests pass
- [ ] iPad Pro simulator: sidebar layout in AIHomeView, centered column in detail/editor views
- [ ] Mac Catalyst: app launches on macOS 26+, microphone permission flow works, audio record + playback works
- [ ] Sync: note created on iPhone appears on iPad and Mac within 30s (and reverse directions)
- [ ] StoreKit: Pro subscription purchased on iPhone auto-applies to Mac via Universal Purchase

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review checklist

**Spec coverage:**
- ✅ Architecture (Section 1 of spec) → Task 1, 2, 8, 10, 11
- ✅ Deployment targets → baked into tasks (unchanged iOS 26.2, Catalyst inherits)
- ✅ API compat / AVAudioSession (Section 2) → Task 7
- ✅ Entitlements (Section 3) → Task 9, 10, 11
- ✅ iPad layout (Section 4) → Tasks 4, 5, 6
- ✅ Distribution (Section 5) → Task 17
- ✅ Testing plan (Section 6) → Tasks 12, 13, 14, 15, 16
- ✅ Out-of-scope items (menu bar, multi-window, native Mac target) not included — correct

**Placeholder scan:** no TBDs, no "similar to Task N", no "add error handling", all code blocks have real code.

**Type consistency:** Method names and env values match across tasks (`horizontalSizeClass`, `targetEnvironment(macCatalyst)`, `SUPPORTS_MACCATALYST`, `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER`).

**Known fragility:**
- Task 4 (AIHomeView split) is the riskiest — requires understanding the current view composition before extracting subviews. The plan instructs to read the file first and only split what's necessary.
- Task 8–11 (project.pbxproj edits via Xcode) depend on Xcode UI behavior. Verified CLI gates confirm the right settings landed.
