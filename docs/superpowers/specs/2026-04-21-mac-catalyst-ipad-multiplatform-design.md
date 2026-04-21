# EEON Multi-Platform: iPhone + iPad + Mac via Catalyst

**Date:** 2026-04-21
**Status:** Design approved, pending implementation plan

## Goal

Ship EEON on iPad and Mac from the existing iOS codebase so notes sync across all three platforms via the user's private iCloud. Distribute as Universal Purchase — one App Store listing, one paid subscription tier, same bundle ID on every platform.

Primary user goal: **sync**. A user captures a note on iPhone and finds it on Mac and iPad moments later. Polish beyond what Catalyst's "Optimize Interface for Mac" mode provides is explicitly out of scope for this spec.

## Non-goals

- Menu bar commands (File → New Note, Edit, View) — deferred to a future "Mac polish" spec.
- Custom keyboard shortcuts beyond what SwiftUI provides automatically.
- Multi-window support on macOS.
- A native macOS target (AppKit / SwiftUI-for-Mac) separate from Catalyst.
- UI tuning beyond what Catalyst's "Optimize Interface for Mac" renders by default.

## Architecture

One codebase, one bundle identifier (`voice.notes.voice-notes`), three supported platforms via Universal Purchase.

| Target | Current | Target state |
|---|---|---|
| Main app (`voice notes`) | iPhone only | iPhone + iPad + Mac Catalyst |
| Widget extension (`VoiceNotesWidget`) | iPhone only | iPhone + iPad + Mac Catalyst |
| Share extension (`EEONShareExtension`) | iPhone + iPad (no Mac) | iPhone + iPad + Mac Catalyst |
| UI Tests (`voice notes UITests`) | iPhone only | Unchanged — tests still run against iPhone simulator |

### Deployment targets

- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (unchanged) — this is the single source of truth for iPhone, iPad, and Mac Catalyst.
- iPad inherits from the iOS target — no separate flag required.
- Mac Catalyst ships to macOS 26+ by virtue of the iOS 26 deployment target (Apple's compatibility table). `IPHONEOS_DEPLOYMENT_TARGET_MACCATALYST` is only needed if we want a different floor for Mac, which we don't.

### Catalyst build settings

- `SUPPORTS_MACCATALYST = YES` on main app, widget extension, share extension.
- `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO` — keep identical bundle IDs across iOS and Catalyst so Universal Purchase resolves the same product.
- "Optimize Interface for Mac" (Catalyst idiom) rather than "Scaled to Match iPad". This is the Catalyst default for new apps and gives native-looking controls without extra code.

### Device family

Flip `TARGETED_DEVICE_FAMILY` from `1` (iPhone only) to `1,2` (iPhone + iPad) on:
- Main app target (Debug and Release configurations)
- Widget extension target (Debug and Release configurations)

Share extension is already `1,2` — no change.

## API compatibility

A grep of iOS-only APIs across the codebase returns one class of call that does not exist on Mac Catalyst: `AVAudioSession`. Everything else is Catalyst-compatible as of macOS 26.

### `AVAudioSession` shim — `voice notes/AudioRecorder.swift`

Two call sites need a `targetEnvironment` guard:

- **Lines 40–42** (`startRecording`) — set `.playAndRecord` category before the recorder starts.
- **Lines 81–83** (`playAudio`) — set `.playback` category before the player starts.

On Mac Catalyst, `AVAudioRecorder` and `AVAudioPlayer` handle audio routing through the macOS audio subsystem directly and do not require session category setup. The shim is a compile-time guard:

```swift
#if !targetEnvironment(macCatalyst)
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, mode: .default)
try audioSession.setActive(true)
#endif
```

### Audited as safe (no shim needed)

| API | Files | Status on Catalyst |
|---|---|---|
| `UIApplication.shared.open(url)` | HomeView, NoteDetailView, SharedNoteDetailView | Works |
| `UIApplication.shared.connectedScenes` | OnboardingPaywallView | Works |
| `BGTaskScheduler` / `BGAppRefreshTaskRequest` | voice_notesApp | Works (macOS 13+) |
| CloudKit + SwiftData `ModelConfiguration(cloudKitDatabase:)` | voice_notesApp | Native on all platforms |
| StoreKit 2 (`Product`, `Transaction`, subscription APIs) | SubscriptionManager | Native on all platforms |
| WidgetKit | VoiceNotesWidget | Native on all platforms (appears in Notification Center on Mac) |

## Entitlements

Four entitlement files exist. All four need Mac-specific sandbox entries added — Catalyst auto-enables App Sandbox, and macOS requires explicit declaration of sandboxed capabilities the app uses.

| File | Target | Additions |
|---|---|---|
| `voice notes/voice notes.entitlements` | Main app (Debug) | `com.apple.security.device.audio-input`, `com.apple.security.network.client` |
| `voice notes/voice notesRelease.entitlements` | Main app (Release) | Same as above |
| `VoiceNotesWidget/VoiceNotesWidget.entitlements` | Widget | `com.apple.security.network.client` (if widget fetches anything) |
| `EEONShareExtension/EEONShareExtension.entitlements` | Share extension | `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-only` |

Existing iCloud container and App Groups entries are cross-platform and carry over to Mac unchanged.

## iPad adaptive layout

Three SwiftUI views get layouts that branch on `@Environment(\.horizontalSizeClass)`. Compact (iPhone, iPad Slide Over) keeps the current design. Regular (iPad full-width, Mac) adopts a wider, desktop-appropriate layout.

### `AIHomeView.swift` — main hub

- **Compact**: current vertical scroll layout.
- **Regular**: `NavigationSplitView` with a sidebar listing recent notes and a main content area holding the record button and query interface. The sidebar is collapsible.

### `NoteDetailView.swift` — reading a note

- **Compact**: full-width.
- **Regular**: content centered in a column with `maxWidth: 720` so text doesn't span the full screen on iPad or a large Mac window.

### `NoteEditorView.swift` — editing a note

- Same centered-column treatment as `NoteDetailView`, max width 720pt.

### Intentionally unchanged

Sheets, modals, paywall, onboarding, and extraction chips all render well at larger sizes without modification. They stay on the iPhone layout.

## Data sync

No code changes. `voice_notesApp.swift:40-44` already configures `ModelConfiguration` with `cloudKitDatabase: .private("iCloud.aivoiceeeon")`. SwiftData's CloudKit integration handles sync across iPhone, iPad, and Mac identically once all three platforms point at the same private container and the user is signed into the same Apple ID.

### What syncs

All 16 SwiftData models registered in the schema: `Note`, `Tag`, `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`, `KanbanItem`, `KanbanMovement`, `WeeklyDebrief`, `Project`, `DailyBrief`, `ExtractedURL`, `MentionedPerson`, `KnowledgeArticle`, `KnowledgeEvent`, `DailyIntention`. Embeddings (`embeddingData` on `Note`) sync — vector search works on any device without regenerating.

### What does not sync

Audio files. `AudioRecorder.swift` writes `.m4a` files to the app's Documents directory, and only the filename (`note.audioFileName`) is persisted in SwiftData. On a second device, the note text and extractions appear but tapping play on an older note from a different device fails silently — the audio file isn't there.

Treating this as an accepted limitation for this spec. A future spec can move audio into iCloud Documents or CloudKit `CKAsset` to close the gap.

## Distribution

Universal Purchase via App Store Connect. Enabled by toggling "Mac App Store availability" on the existing app record. Apple auto-creates the Mac version under the same bundle ID. StoreKit products (`pro_monthly` $9.99, `pro_annual` $79.99) are shared automatically — users who own Pro on iPhone receive Pro on Mac and iPad without re-purchase.

Setup is configuration-only — no code changes. One App Store listing, one set of screenshots (iPhone, iPad, Mac), one review queue, one aggregate rating.

## Testing plan

Each gate must pass before the change lands.

1. **Catalyst build gate** — `xcodebuild -scheme "voice notes" -destination "platform=macOS,variant=Mac Catalyst" build` compiles with no errors or warnings beyond baseline.
2. **iPad build gate** — `xcodebuild -scheme "voice notes" -destination "generic/platform=iPadOS" build` compiles.
3. **Sync gate (manual)** — create a note on iPhone simulator, confirm it appears on Mac and iPad simulators within 30 seconds. Edit a note on iPad, confirm the edit appears on iPhone.
4. **Audio gate (Mac)** — record a voice note on Mac Catalyst, confirm microphone permission prompt, confirm playback works. Record a note, confirm transcription + extraction run.
5. **StoreKit gate (Mac)** — sign into a sandbox Apple ID that already owns `pro_monthly` on iPhone, launch Mac app, confirm `isPro` resolves to true without a purchase flow.
6. **iPad layout gate** — run on iPad Pro 12.9" simulator in portrait and landscape. Confirm `NavigationSplitView` sidebar in AIHomeView, centered-column layout in NoteDetailView and NoteEditorView. No text spanning full screen width.
7. **Regression gate** — iPhone build and UI tests (`xcodebuild test -scheme "voice notes UITests"`) continue to pass.

## Failure modes and fallbacks

- **User not signed into iCloud on Mac**: existing fallback chain in `voice_notesApp.init()` (CloudKit → local SQLite → recreate) applies to Mac too. App still works, just without sync.
- **Microphone permission denied on Mac**: existing error handling in `AudioRecorder` surfaces the failure. No new code required.
- **Catalyst runs an iOS API that was overlooked in audit**: caught at build time by `xcodebuild` with `SUPPORTS_MACCATALYST = YES`. Fix by adding a `#if !targetEnvironment(macCatalyst)` guard at the call site.

## Decision record

- **Catalyst over native macOS target**: 90% of the user-visible win (a functional Mac app with sync) for <25% of the work. A native target is a separate future project, not a prerequisite.
- **Universal Purchase over separate listings**: users who paid on iPhone should not pay again. Separate listings also fragment reviews and ratings.
- **iPad adaptive layouts over "ship as-is"**: user explicitly chose this over the cheaper option. Three views is a small, bounded pass that meaningfully improves iPad usability without creeping into a full responsive redesign.
- **Audio files don't sync in v1**: accepted limitation. Sync works for text/extractions/embeddings, which are the primary value. CloudKit asset sync is its own design problem.
