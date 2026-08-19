# Capture Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pocket-style capture without the device — press the Action Button / Control Center / Lock Screen control / Siri with the phone locked, and EEON records in the background until the user stops it, no matter what the phone does, with a mandatory Live Activity as the "device screen."

**Architecture:** A `ToggleRecordingIntent` conforming to `AudioRecordingIntent` (iOS 18+) runs in the app process launched in the background (`openAppWhenRun = false`). It drives a new `BackgroundCaptureService` singleton that owns an `AudioRecorder`, starts the mandatory Live Activity, and on stop saves a **pending** note — converging on the app's existing pending-transcription drain (`voice_notesApp.swift:392-445`) so no new retry machinery exists. `AudioRecorder` itself is hardened (interruption pause/auto-resume, crash-safe in-flight marker) so the fixes cover the in-app path too.

**Tech Stack:** SwiftUI, SwiftData, AppIntents (`AudioRecordingIntent`, `LiveActivityIntent`, `AppShortcutsProvider`), ActivityKit, WidgetKit (`ControlWidget`), AVFoundation.

**Spec:** `docs/superpowers/specs/2026-08-19-capture-pack-design.md`

## Global Constraints

- Deployment target is iOS 26.2 — no availability guards needed for iOS 18 APIs.
- Xcode project uses **file-system synchronized groups** (`objectVersion = 77`): creating a `.swift` file inside `voice notes/`, `VoiceNotesWidget/`, or `EEONShareExtension/` automatically adds it to that folder's target. No pbxproj edits to add files.
- Cross-target shared types are **duplicated by file copy** per folder (existing pattern: `SharedDefaults.swift` exists in 3 folders). Duplicated copies must stay byte-identical apart from the header comment.
- Scheme names contain spaces — always quote: `xcodebuild -scheme "voice notes" -configuration Debug build`. Never `clean`.
- **No unit-test target exists** (TODOS.md #1). Verification per task = the build gate above; final verification = the on-device gate in Task 7. Do not stand up test infrastructure in this plan.
- **Never delete user notes or audio files.** Failure paths must save partial data, never discard it.
- Recording must continue until the user stops it: **no duration cap anywhere**.
- Work directly on `main`. Commit per task. **Never push** — Shawn authorizes each push explicitly.
- App Group: `group.com.eeon.voicenotes`. Free-tier gate: `UsageService.shared.canCreateNote`.

---

### Task 1: AudioRecorder hardening — interruption pause/resume, in-flight marker

**Files:**
- Modify: `voice notes/AudioRecorder.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (later tasks rely on these exact names):
  - `AudioRecorder.isPaused: Bool` (observable state)
  - `AudioRecorder.onPauseStateChange: ((Bool) -> Void)?` (fired on pause/resume)
  - `enum InFlightRecordingMarker { static var fileName: String?; static func set(fileName: String); static func clear() }`

**Why:** Two live bugs (verified 2026-08-19): no `AVAudioSession.interruptionNotification` observer — a phone call pauses the recorder forever while `isRecording` stays `true` (UI lies, capture lost); and lock-survival is only `isIdleTimerDisabled` screen-pinning. Both the in-app path (13 `AudioRecorder()` instances) and the new background path get fixed here.

- [ ] **Step 1: Add state, marker enum, and observer plumbing**

At the top of `AudioRecorder.swift` (file scope, below the imports, above `class AudioRecorder`), add:

```swift
/// Crash-safe marker for a recording in flight. Set when recording starts,
/// cleared on clean stop. If it survives to next launch, the audio file is
/// orphaned and gets recovered as a pending note (see voice_notesApp).
enum InFlightRecordingMarker {
    private static let fileNameKey = "inflight_recording_fileName"

    static var fileName: String? {
        UserDefaults.standard.string(forKey: fileNameKey)
    }
    static func set(fileName: String) {
        UserDefaults.standard.set(fileName, forKey: fileNameKey)
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: fileNameKey)
    }
}
```

Inside `class AudioRecorder`, next to the existing `var isRecording = false`, add:

```swift
    var isPaused = false
    /// Fired on pause/resume so an owner (BackgroundCaptureService) can
    /// mirror the state into a Live Activity.
    var onPauseStateChange: ((Bool) -> Void)?

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var resumeRetryTask: Task<Void, Never>?
```

- [ ] **Step 2: Install observers and marker in startRecording, tear down in stopRecording**

In `startRecording()`, immediately after `currentFileName = fileName` add:

```swift
        InFlightRecordingMarker.set(fileName: fileName)
        installInterruptionObservers()
```

In `stopRecording()`, immediately after `audioRecorder?.stop()` add:

```swift
        removeInterruptionObservers()
        resumeRetryTask?.cancel()
        resumeRetryTask = nil
        isPaused = false
        InFlightRecordingMarker.clear()
```

- [ ] **Step 3: Implement pause/resume handling**

Add these methods to `AudioRecorder` (below `setIdleTimerDisabled`):

```swift
    // MARK: - Interruption handling (calls, Siri, alarms, other apps' audio)
    //
    // Requirement: recording continues until the user stops it. Any
    // interruption pauses; resume is attempted unconditionally (not gated
    // on .shouldResume) and retried until the session frees or the user
    // stops. AVAudioRecorder.pause() keeps the file open, so record()
    // resumes appending to the same file.

    private func installInterruptionObservers() {
        removeInterruptionObservers()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            // A route change (BT mic dropped, etc.) can silently stop the
            // recorder. If we think we're recording but the recorder isn't,
            // treat it like an interruption and re-arm.
            guard let self, self.isRecording, !self.isPaused else { return }
            if self.audioRecorder?.isRecording == false {
                self.markPaused()
                self.attemptResume()
            }
        }
    }

    private func removeInterruptionObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        interruptionObserver = nil
        routeChangeObserver = nil
    }

    private func handleInterruption(_ notification: Notification) {
        guard isRecording else { return }
        guard let userInfo = notification.userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            markPaused()
        case .ended:
            attemptResume()
        @unknown default:
            break
        }
    }

    private func markPaused() {
        audioRecorder?.pause()
        timer?.invalidate()
        timer = nil
        isPaused = true
        onPauseStateChange?(true)
    }

    private func attemptResume() {
        resumeRetryTask?.cancel()
        resumeRetryTask = Task { @MainActor [weak self] in
            while let self, self.isPaused, self.isRecording, !Task.isCancelled {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    if self.audioRecorder?.record() == true {
                        self.isPaused = false
                        self.restartTimer()
                        self.onPauseStateChange?(false)
                        return
                    }
                } catch {
                    // Session still owned by the interruptor (e.g. an active
                    // call). Keep retrying until it frees or the user stops.
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingTime += 1
        }
    }
```

- [ ] **Step 4: Clean up observers in deinit**

In `deinit`, add as the first lines:

```swift
        removeInterruptionObservers()
        resumeRetryTask?.cancel()
```

- [ ] **Step 5: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add "voice notes/AudioRecorder.swift"
git commit -m "fix: AudioRecorder survives interruptions — pause on call/Siri, unconditional auto-resume, crash-safe in-flight marker"
```

---

### Task 2: Crash recovery on launch — orphaned recording becomes a pending note

**Files:**
- Modify: `voice notes/voice_notesApp.swift`

**Interfaces:**
- Consumes: `InFlightRecordingMarker` (Task 1), `Note(title:content:transcript:audioFileName:)`, `Note.transcriptionStatus`.
- Produces: `recoverOrphanedRecording(in:)` called from `init()`. The existing pending-transcription drain at `voice_notesApp.swift:392-445` (runs on foreground) finishes the job — do NOT modify it.

- [ ] **Step 1: Add the recovery function**

Add this private method to `struct voice_notesApp` (place it near `handleIncomingURL`):

```swift
    /// If the app died mid-recording (crash, jetsam), the audio written so
    /// far is on disk and InFlightRecordingMarker survived. Recover it as a
    /// pending note; the existing pending-transcription drain transcribes
    /// and processes it on foreground. Never discards audio.
    private func recoverOrphanedRecording(in context: ModelContext) {
        guard let fileName = InFlightRecordingMarker.fileName else { return }
        InFlightRecordingMarker.clear()

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // Skip if a note already references this file (clean stop raced the marker).
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.audioFileName == fileName }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        let note = Note(title: "", content: "", transcript: nil, audioFileName: fileName)
        note.transcriptionStatus = "pending"
        context.insert(note)
        try? context.save()
        print("🎙️ Recovered orphaned recording as pending note: \(fileName)")
    }
```

- [ ] **Step 2: Call it at the end of init()**

At the very end of `init()` (after all container-fallback paths have assigned `container`, after the CloudKit seed block), add:

```swift
        recoverOrphanedRecording(in: container.mainContext)
```

- [ ] **Step 3: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/voice_notesApp.swift"
git commit -m "feat: recover orphaned in-flight recordings as pending notes on launch"
```

---

### Task 3: Capture intents + bridge (shared file, app + widget targets)

**Files:**
- Create: `voice notes/CaptureIntents.swift`
- Create: `VoiceNotesWidget/CaptureIntents.swift` (byte-identical copy, different header comment)

**Interfaces:**
- Consumes: nothing from other tasks (compiles standalone in both targets — that is the point).
- Produces:
  - `enum CaptureBridge { static var toggleHandler: (@Sendable () async throws -> Void)?; static var stopHandler: (@Sendable () async throws -> Void)? }`
  - `struct ToggleRecordingIntent: AudioRecordingIntent` — Task 6's control button and AppShortcut use it.
  - `struct StopRecordingIntent: AudioRecordingIntent, LiveActivityIntent` — Task 4's Live Activity stop button uses it.
  - `enum CaptureIntentError: Error` with cases `.appNotReady`, `.micPermissionNeeded`, `.freeLimitReached` — Task 5 throws the latter two.

**Design note (why a bridge):** The file is duplicated into the app and widget targets (the repo's `SharedDefaults.swift` pattern) because the widget extension needs the intent *types* at compile time for `Button(intent:)` / `ControlWidgetButton(action:)`. But `AudioRecordingIntent`/`LiveActivityIntent` conformers always *perform* in the **app process** — where `voice_notesApp.init()` has installed the handlers. The extension's copy compiles with nil handlers that never run. This keeps `BackgroundCaptureService` (which drags in SwiftData + the whole pipeline) out of the extension.

- [ ] **Step 1: Create `voice notes/CaptureIntents.swift`**

```swift
//
//  CaptureIntents.swift
//  voice notes
//
//  App Intents for Pocket-style background capture. This file is duplicated
//  into the VoiceNotesWidget target (SharedDefaults.swift pattern) — keep
//  both copies identical. perform() always runs in the app process, where
//  voice_notesApp.init() installs the CaptureBridge handlers.
//

import AppIntents
import Foundation

/// Runtime bridge between the intents (compiled into both targets) and
/// BackgroundCaptureService (app target only). Set in voice_notesApp.init().
enum CaptureBridge {
    static var toggleHandler: (@Sendable () async throws -> Void)?
    static var stopHandler: (@Sendable () async throws -> Void)?
}

/// One press from anywhere — Action Button, Control Center, Lock Screen,
/// Siri, Shortcuts, Back Tap. Not recording → start (phone stays locked,
/// Live Activity appears). Recording → stop and save.
struct ToggleRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Record EEON Note"
    static var description = IntentDescription(
        "Start or stop an EEON voice note without opening the app."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let handler = CaptureBridge.toggleHandler else {
            throw CaptureIntentError.appNotReady
        }
        try await handler()
        return .result()
    }
}

/// Stop button on the Live Activity. LiveActivityIntent ⇒ runs in the app
/// process even though the button lives in the widget extension.
struct StopRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop EEON Recording"
    static var description = IntentDescription("Stop and save the current EEON recording.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let handler = CaptureBridge.stopHandler else {
            throw CaptureIntentError.appNotReady
        }
        try await handler()
        return .result()
    }
}

enum CaptureIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case micPermissionNeeded
    case freeLimitReached

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "EEON isn't ready yet — open the app once, then try again."
        case .micPermissionNeeded:
            return "Open EEON and allow microphone access first."
        case .freeLimitReached:
            return "Free note limit reached — open EEON to upgrade."
        }
    }
}
```

- [ ] **Step 2: Duplicate into the widget folder**

Copy the file to `VoiceNotesWidget/CaptureIntents.swift`, changing only the header comment's target line (`//  VoiceNotesWidget`). The synchronized group adds each copy to its folder's target automatically.

```bash
sed 's|^//  voice notes$|//  VoiceNotesWidget|' "voice notes/CaptureIntents.swift" > "VoiceNotesWidget/CaptureIntents.swift"
```

- [ ] **Step 3: Build gate (both targets — build the app scheme, which builds the widget as a dependency)**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/CaptureIntents.swift" "VoiceNotesWidget/CaptureIntents.swift"
git commit -m "feat: ToggleRecordingIntent + StopRecordingIntent (AudioRecordingIntent) with CaptureBridge indirection"
```

---

### Task 4: Live Activity — attributes, lock screen + Dynamic Island UI, plist key

**Files:**
- Create: `voice notes/RecordingActivityAttributes.swift`
- Create: `VoiceNotesWidget/RecordingActivityAttributes.swift` (byte-identical copy)
- Create: `VoiceNotesWidget/RecordingLiveActivity.swift`
- Modify: `VoiceNotesWidget/VoiceNotesWidgetBundle.swift`
- Modify: `voice notes.xcodeproj/project.pbxproj` (app-target `INFOPLIST_KEY_NSSupportsLiveActivities`)

**Interfaces:**
- Consumes: `StopRecordingIntent` (Task 3).
- Produces: `RecordingActivityAttributes: ActivityAttributes` with `ContentState { startedAt: Date; isPaused: Bool; pausedReason: String? }` — Task 5 requests/updates/ends activities with exactly this shape.

**Design note:** The timer renders via `Text(startedAt, style: .timer)` so the Live Activity needs **zero updates while recording** — only pause/resume transitions push a new content state. On resume, Task 5 re-baselines `startedAt` so the timer shows true recorded time, not wall-clock.

- [ ] **Step 1: Create `voice notes/RecordingActivityAttributes.swift`**

```swift
//
//  RecordingActivityAttributes.swift
//  voice notes
//
//  ActivityKit attributes for the recording Live Activity. Duplicated into
//  the VoiceNotesWidget target (SharedDefaults.swift pattern) — keep both
//  copies identical.
//

import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Baseline for the on-screen timer. Re-baselined on resume so the
        /// timer shows recorded time, not wall-clock time across pauses.
        var startedAt: Date
        var isPaused: Bool
        var pausedReason: String?
    }
}
```

- [ ] **Step 2: Duplicate into the widget folder**

```bash
sed 's|^//  voice notes$|//  VoiceNotesWidget|' "voice notes/RecordingActivityAttributes.swift" > "VoiceNotesWidget/RecordingActivityAttributes.swift"
```

- [ ] **Step 3: Create `VoiceNotesWidget/RecordingLiveActivity.swift`**

```swift
//
//  RecordingLiveActivity.swift
//  VoiceNotesWidget
//
//  The "device screen": lock screen + Dynamic Island UI for an in-flight
//  recording. Required by AudioRecordingIntent — recording stops if no
//  Live Activity is active.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen banner
            HStack(spacing: 12) {
                recordingIndicator(isPaused: context.state.isPaused)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EEON")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if context.state.isPaused {
                        Text(context.state.pausedReason ?? "Paused")
                            .font(.headline)
                    } else {
                        Text(context.state.startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                    }
                }
                Spacer()
                Button(intent: StopRecordingIntent()) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    recordingIndicator(isPaused: context.state.isPaused)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("Paused").font(.headline)
                    } else {
                        Text(context.state.startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: 60)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let reason = context.state.pausedReason, context.state.isPaused {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(intent: StopRecordingIntent()) {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "phone.fill").foregroundStyle(.secondary)
                } else {
                    Text(context.state.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func recordingIndicator(isPaused: Bool) -> some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
            .font(.title2)
            .foregroundStyle(isPaused ? .secondary : Color.red)
            .symbolEffect(.pulse, isActive: !isPaused)
    }
}
```

- [ ] **Step 4: Register in the widget bundle**

In `VoiceNotesWidget/VoiceNotesWidgetBundle.swift`, add to the bundle body:

```swift
    var body: some Widget {
        VoiceNotesSmallWidget()
        VoiceNotesLockScreenWidget()
        RecordingLiveActivity()
    }
```

- [ ] **Step 5: Declare Live Activity support in the app's generated Info.plist**

In `voice notes.xcodeproj/project.pbxproj`, the app target's Debug and Release build configurations both contain the line:

```
INFOPLIST_KEY_UIBackgroundModes = "audio remote-notification fetch";
```

Using Edit with `replace_all: true`, replace it (both occurrences) with:

```
INFOPLIST_KEY_NSSupportsLiveActivities = YES;
				INFOPLIST_KEY_UIBackgroundModes = "audio remote-notification fetch";
```

(Tab-indentation must match the surrounding lines — pbxproj uses tabs.)

- [ ] **Step 6: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Then verify the key landed in the **built artifact** (not just source):

```bash
BUILT_PLIST=$(find ~/Library/Developer/Xcode/DerivedData -path "*voice notes*" -name "Info.plist" -path "*Debug-iphonesimulator/voice notes.app/Info.plist" 2>/dev/null | head -1)
plutil -extract NSSupportsLiveActivities raw "$BUILT_PLIST"
```
Expected: `true` (if the DerivedData path finds nothing, note it and verify in Task 7's device build instead — do not skip silently).

- [ ] **Step 7: Commit**

```bash
git add "voice notes/RecordingActivityAttributes.swift" "VoiceNotesWidget/RecordingActivityAttributes.swift" "VoiceNotesWidget/RecordingLiveActivity.swift" "VoiceNotesWidget/VoiceNotesWidgetBundle.swift" "voice notes.xcodeproj/project.pbxproj"
git commit -m "feat: recording Live Activity — lock screen + Dynamic Island with timer, paused state, stop button"
```

---

### Task 5: BackgroundCaptureService + app wiring

**Files:**
- Create: `voice notes/BackgroundCaptureService.swift`
- Modify: `voice notes/voice_notesApp.swift` (end of `init()`)

**Interfaces:**
- Consumes: `AudioRecorder` (+ Task 1's `isPaused`/`onPauseStateChange`), `RecordingActivityAttributes` (Task 4), `CaptureBridge`/`CaptureIntentError` (Task 3), `Note`, `UsageService.shared.canCreateNote`/`.incrementNoteCount()`, `TranscriptionService(apiKey:language:)`, `SummaryService.cleanFillerWords(from:apiKey:)`/`.generateTitle(for:apiKey:)`, `IntelligenceService.shared.processNoteSave(note:transcript:projects:tags:context:)`, `EmbeddingService.shared.generateAndStoreEmbedding(for:)`, `SharedDefaults.updateLastNote(preview:date:intent:)`, `LanguageSettings.shared.selectedLanguage`, `APIKeys.openAI`.
- Produces: `BackgroundCaptureService.shared` with `isCapturing: Bool`, `recorder: AudioRecorder` (read by Task 7's banner), `configure(container:)`, `toggle()`, `stop()`.

**Design note:** stop() saves the note as **pending first**, then processes inline. If iOS reaps the process mid-pipeline, the note is already on disk in exactly the shape the existing foreground drain (`voice_notesApp.swift:392-445`) retries. Convergence, not duplication of retry logic.

- [ ] **Step 1: Create `voice notes/BackgroundCaptureService.swift`**

```swift
//
//  BackgroundCaptureService.swift
//  voice notes
//
//  Owns Pocket-style background capture sessions started from App Intents
//  (Action Button / Control Center / Siri) while the phone stays locked.
//  The Live Activity it starts is REQUIRED by AudioRecordingIntent — iOS
//  kills the recording if none is active.
//

import Foundation
import SwiftData
import AVFoundation
import ActivityKit
import WidgetKit

@Observable
final class BackgroundCaptureService {
    static let shared = BackgroundCaptureService()

    private(set) var isCapturing = false
    /// Exposed so AIHomeView can render live state (elapsed time, paused).
    let recorder = AudioRecorder()

    private var activity: Activity<RecordingActivityAttributes>?
    private var container: ModelContainer?

    private init() {}

    /// Called once from voice_notesApp.init() after the container resolves.
    func configure(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func toggle() async throws {
        if isCapturing {
            try await stop()
        } else {
            try await start()
        }
    }

    @MainActor
    func start() async throws {
        guard !isCapturing else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw CaptureIntentError.micPermissionNeeded
        }
        guard UsageService.shared.canCreateNote else {
            throw CaptureIntentError.freeLimitReached
        }

        _ = try recorder.startRecording()
        isCapturing = true

        // Mirror recorder pause/resume into the Live Activity.
        recorder.onPauseStateChange = { [weak self] paused in
            Task { @MainActor [weak self] in
                await self?.updateActivityPauseState(paused: paused)
            }
        }

        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date(), isPaused: false, pausedReason: nil
        )
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
        if activity == nil {
            // Per the AudioRecordingIntent contract iOS will kill a
            // recording with no Live Activity. Don't record silently-doomed
            // audio: save nothing yet, stop cleanly, and surface the error.
            _ = recorder.stopRecording()
            isCapturing = false
            throw CaptureIntentError.appNotReady
        }
    }

    @MainActor
    private func updateActivityPauseState(paused: Bool) async {
        guard let activity else { return }
        // Re-baseline the timer on resume so it shows recorded time,
        // not wall-clock time across the pause.
        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-recorder.recordingTime),
            isPaused: paused,
            pausedReason: paused ? "Paused — audio in use (call?) · auto-resumes" : nil
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    @MainActor
    func stop() async throws {
        guard isCapturing else { return }
        recorder.onPauseStateChange = nil
        let url = recorder.stopRecording()
        isCapturing = false

        if let activity {
            let finalState = RecordingActivityAttributes.ContentState(
                startedAt: Date(), isPaused: false, pausedReason: nil
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            self.activity = nil
        }

        guard let url else { return }
        await saveAndProcess(url: url)
    }

    /// Save-first, process-second. The note lands as "pending" before any
    /// network call, so a reaped process loses nothing — the existing
    /// foreground drain (voice_notesApp) finishes pending notes.
    @MainActor
    private func saveAndProcess(url: URL) async {
        guard let container else { return }
        let context = container.mainContext
        let fileName = url.lastPathComponent

        let note = Note(title: "", content: "", transcript: nil, audioFileName: fileName)
        note.transcriptionStatus = "pending"
        context.insert(note)
        UsageService.shared.incrementNoteCount()
        try? context.save()

        SharedDefaults.updateLastNote(
            preview: "Processing voice note…",
            date: note.createdAt,
            intent: note.intentType
        )
        WidgetCenter.shared.reloadAllTimelines()

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return }

        do {
            let service = TranscriptionService(
                apiKey: apiKey,
                language: LanguageSettings.shared.selectedLanguage
            )
            let rawTranscript = try await service.transcribe(audioURL: url)
            let transcript: String
            do {
                transcript = try await SummaryService.cleanFillerWords(from: rawTranscript, apiKey: apiKey)
            } catch {
                transcript = rawTranscript
            }

            note.transcript = transcript
            note.content = transcript
            note.transcriptionStatus = "completed"
            note.updatedAt = Date()
            try? context.save()

            if let title = try? await SummaryService.generateTitle(for: transcript, apiKey: apiKey) {
                note.title = title
            }

            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
            await IntelligenceService.shared.processNoteSave(
                note: note,
                transcript: transcript,
                projects: projects,
                tags: tags,
                context: context
            )
            await EmbeddingService.shared.generateAndStoreEmbedding(for: note)

            SharedDefaults.updateLastNote(
                preview: note.displayTitle,
                date: note.createdAt,
                intent: note.intentType
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Note stays "pending" with its audio — the foreground drain
            // retries it. Nothing is lost.
            print("🎙️ Background capture processing deferred: \(error)")
        }
    }
}
```

- [ ] **Step 2: Wire the bridge in voice_notesApp.init()**

At the very end of `init()` in `voice notes/voice_notesApp.swift` — after the `recoverOrphanedRecording(in:)` call added in Task 2 — add:

```swift
        // Pocket-style background capture: intents perform in this process,
        // reaching the service through CaptureBridge (see CaptureIntents.swift).
        BackgroundCaptureService.shared.configure(container: container)
        CaptureBridge.toggleHandler = {
            try await BackgroundCaptureService.shared.toggle()
        }
        CaptureBridge.stopHandler = {
            try await BackgroundCaptureService.shared.stop()
        }
```

- [ ] **Step 3: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/BackgroundCaptureService.swift" "voice notes/voice_notesApp.swift"
git commit -m "feat: BackgroundCaptureService — locked-phone capture with Live Activity, save-first pending-note pipeline"
```

---

### Task 6: Control Center / Lock Screen / Action Button control + Siri App Shortcuts

**Files:**
- Create: `VoiceNotesWidget/RecordControl.swift`
- Modify: `VoiceNotesWidget/VoiceNotesWidgetBundle.swift`
- Create: `voice notes/EEONAppShortcuts.swift`

**Interfaces:**
- Consumes: `ToggleRecordingIntent` (Task 3).
- Produces: user-facing surfaces only — nothing downstream consumes these.

- [ ] **Step 1: Create `VoiceNotesWidget/RecordControl.swift`**

```swift
//
//  RecordControl.swift
//  VoiceNotesWidget
//
//  iOS 18 control: one button for Control Center, the Lock Screen, and the
//  Action Button. Runs ToggleRecordingIntent — start/stop background capture
//  without opening the app.
//

import WidgetKit
import SwiftUI

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.eeon.voicenotes.recordControl") {
            ControlWidgetButton(action: ToggleRecordingIntent()) {
                Label("Record EEON Note", systemImage: "mic.fill")
            }
        }
        .displayName("Record EEON Note")
        .description("Start or stop an EEON voice note.")
    }
}
```

- [ ] **Step 2: Register in the widget bundle**

In `VoiceNotesWidget/VoiceNotesWidgetBundle.swift`:

```swift
    var body: some Widget {
        VoiceNotesSmallWidget()
        VoiceNotesLockScreenWidget()
        RecordingLiveActivity()
        RecordControl()
    }
```

- [ ] **Step 3: Create `voice notes/EEONAppShortcuts.swift`**

```swift
//
//  EEONAppShortcuts.swift
//  voice notes
//
//  Siri / Shortcuts / Spotlight surface for capture. "Hey Siri, record a
//  note with EEON" works with the phone locked — the intent performs in
//  the background app process.
//

import AppIntents

struct EEONAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Record a note with \(.applicationName)",
                "New \(.applicationName) note",
                "Start recording in \(.applicationName)",
                "Stop recording in \(.applicationName)"
            ],
            shortTitle: "Record Note",
            systemImageName: "mic.fill"
        )
    }
}
```

- [ ] **Step 4: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add "VoiceNotesWidget/RecordControl.swift" "VoiceNotesWidget/VoiceNotesWidgetBundle.swift" "voice notes/EEONAppShortcuts.swift"
git commit -m "feat: Control Center / Action Button record control + Siri App Shortcuts"
```

---

### Task 7: In-app reconciliation + on-device verification gate

**Files:**
- Modify: `voice notes/AIHomeView.swift` (`toggleRecording()` at ~line 1556; banner near the `.onChange(of: shouldStartRecording)` modifier at ~line 445)

**Interfaces:**
- Consumes: `BackgroundCaptureService.shared.isCapturing`, `.recorder` (its `recordingTime`, `isPaused`, `formattedTime`), `.stop()`.
- Produces: nothing downstream.

- [ ] **Step 1: Guard toggleRecording against a live background capture**

In `AIHomeView.toggleRecording()` (~line 1556), add as the FIRST statement of the function:

```swift
        // A background capture (Action Button / Control Center) owns the mic.
        // The big button becomes its stop button instead of fighting for the
        // session.
        if BackgroundCaptureService.shared.isCapturing {
            Task { try? await BackgroundCaptureService.shared.stop() }
            return
        }
```

- [ ] **Step 2: Add the background-capture banner**

On the same view that carries `.onChange(of: shouldStartRecording)` (~line 445), attach:

```swift
            .safeAreaInset(edge: .top) {
                if backgroundCapture.isCapturing {
                    backgroundCaptureBanner
                }
            }
```

Add to AIHomeView's properties (near `private var intelligenceService = IntelligenceService.shared`):

```swift
    private var backgroundCapture = BackgroundCaptureService.shared
```

Add this computed view to AIHomeView (near the bottom of the view builders):

```swift
    private var backgroundCaptureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: backgroundCapture.recorder.isPaused ? "pause.circle.fill" : "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !backgroundCapture.recorder.isPaused)
            Text(backgroundCapture.recorder.isPaused
                 ? "Paused — auto-resumes"
                 : "Recording · \(backgroundCapture.recorder.formattedTime)")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                Task { try? await backgroundCapture.stop() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
```

- [ ] **Step 3: Build gate**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: AIHomeView reflects background capture — banner + big-button stop routing"
```

- [ ] **Step 5: ON-DEVICE VERIFICATION GATE (Shawn's phone — nothing is "working" until these pass)**

Simulators structurally cannot disprove any of this. Install a device build, then:

1. Add the "Record EEON Note" control to Control Center; assign it to the Action Button (Settings → Action Button → Controls).
2. **Locked capture:** lock phone → press Action Button → talk 30s → stop from the Live Activity → open EEON → note exists with transcript.
3. **Lock survival:** start recording in-app → press side button (lock) → keep talking 2+ min → unlock, stop → transcript contains the post-lock speech.
4. **Call interruption:** start recording → receive/place a phone call ≥1 min → observe "Paused" on the Live Activity → hang up → recording auto-resumes with no taps → stop → audio contains pre- AND post-call speech.
5. **No cap:** record 15+ min → stop → full transcript (crosses the Whisper chunking path).
6. **Crash recovery:** start recording → force-quit EEON from the app switcher → relaunch → pending note exists with the partial audio; foreground drain transcribes it.
7. **Built artifact:** confirm the device build's Info.plist has `NSSupportsLiveActivities` and `UIBackgroundModes` containing `audio` (Xcode → Report navigator, or `plutil` on the built .app).

Report each as observed pass/fail. Any claim not exercised on device is reported verbatim as **"built, not verified"**.

---

## Self-Review Notes

- **Spec coverage:** locked-capture intent (T3/T5), every-surface press (T6), no cap + unconditional resume + crash recovery (T1/T2/T5), mandatory Live Activity with paused state (T4/T5), in-app reconciliation (T7), plist plumbing (T4), device gate (T7). Mic-permission and free-tier error paths (T3/T5). Pending-note convergence replaces the spec's "queue drain" wording — same mechanism, already existing at `voice_notesApp.swift:392-445`.
- **Type consistency:** `CaptureBridge.toggleHandler`/`stopHandler` are `() async throws -> Void` in T3 and consumed as such in T5. `ContentState(startedAt:isPaused:pausedReason:)` identical in T4/T5. `recorder` property name consistent T5/T7.
- **Known judgment calls:** `Activity.request` failure aborts the start (Apple kills LA-less recordings — better a loud error than doomed audio); background-capture notes skip the `navigateToNote` UX on purpose (app may not be foreground).
