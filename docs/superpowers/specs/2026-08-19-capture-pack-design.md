# Capture Pack — Design Spec

**Date:** 2026-08-19
**Status:** Approved direction (this doc pending Shawn's review)
**Goal:** Make EEON capture work like the Pocket device without the device: press something physical, talk, done — phone locked or not — and recording continues until the user stops it, no matter what the phone does.

## Product requirements (locked)

1. **One press starts recording from anywhere** — Action Button, Control Center, Lock Screen control, Siri, Shortcuts, Back Tap — without unlocking or opening the app.
2. **Recording continues until the user stops it.** No duration cap. Lock, screen dark, backgrounding, app switching, Siri, alarms, other apps' audio — none of these end a recording. The only stop is the user's.
3. **Interruptions pause, never kill.** Any audio interruption pauses the recorder; it auto-resumes the moment the session frees, appending to the same file, with no user action. Physical limit acknowledged: during an active phone call iOS gives the mic exclusively to the call — EEON pauses and resumes the second the call ends. (Call audio itself arrives via iOS 18 native call recording + the audio share-ingest path, a separate sub-project.)
4. **Nothing is ever lost.** Audio is written to disk continuously; a crash or process kill mid-recording leaves a recoverable file that the next launch saves as a note automatically. Partial capture is always saved, never discarded (per the never-delete-user-notes rule).
5. **The lock screen is the device screen.** A Live Activity shows recording state (elapsed time, paused-on-call state, stop button) while capturing in the background.

## Architecture

### 1. `ToggleRecordingIntent` (new — main app target)

- Conforms to `AudioRecordingIntent` (App Intents, iOS 18+; verified against Apple docs 2026-08-19: *"you must start a Live Activity when you begin the audio recording and keep it active as long as you record audio. If you don't start a Live Activity, the audio recording stops."*)
- `openAppWhenRun = false` — the system launches the app process in the **background**; the phone stays locked and dark.
- Toggle semantics: not recording → start; recording → stop. A separate `StopRecordingIntent` (same conformance) drives the Live Activity stop button.
- Exposed via `AppShortcutsProvider` with phrases ("Record a note with EEON", "New EEON note") → Siri, Shortcuts, Back Tap for free.
- The existing widget deep link (`voicenotes://record`) is untouched.

### 2. Control Center / Lock Screen / Action Button control (new — widget extension)

- `ControlWidget` + `ControlWidgetButton` (SwiftUI/WidgetKit, iOS 18+; verified) running `ToggleRecordingIntent`.
- iOS lets users place the control in Control Center, on the Lock Screen, or on the **Action Button** — one control, three surfaces.

### 3. `BackgroundCaptureService` (new — main app)

Owns capture sessions started from intents:
- Configures `AVAudioSession` (`.playAndRecord`), starts `AudioRecorder`, starts the Live Activity, persists an in-flight marker (see crash recovery).
- On stop: ends the Live Activity, saves the note, and immediately runs the existing pipeline (Whisper → extraction → embedding) with whatever background runtime it has. If iOS reaps the process mid-pipeline, the note + audio are already saved; processing completes on next foreground via the existing drain pattern.
- If the app is opened mid-background-capture, `AIHomeView` reflects the live recording state (single source of truth: the shared `AudioRecorder`/service state).

### 4. `AudioRecorder` hardening (existing file — fixes two live bugs)

Current bugs (verified in code 2026-08-19): no `AVAudioSession.interruptionNotification` observer — a phone call pauses the recorder forever while `isRecording` stays `true` and the timer keeps counting (UI lies, capture lost); "survives lock" today is only `isIdleTimerDisabled = true` screen-pinning.

- **Interruption observer:** on `.began` → mark `isPaused` (UI + Live Activity show "paused — audio interrupted / on a call"); timer pauses. On `.ended` → reactivate session, `record()` to resume **appending to the same file**. Resume is attempted unconditionally (not gated on `.shouldResume`), with retry until the session frees or the user stops.
- **No duration cap.** Whisper chunking (>25MB → 10-min segments) already handles long files.
- **Crash recovery:** an in-flight recording marker (file name + start time) is persisted at record-start and cleared at clean stop. On launch, an orphaned marker + audio file on disk → auto-save as a note and process.
- **Background continuation:** `audio` is already in `UIBackgroundModes` (verified in pbxproj: `INFOPLIST_KEY_UIBackgroundModes = "audio remote-notification fetch"`). Keep the idle-timer pin for in-app recording as belt-and-suspenders; the on-device gate proves lock survival.
- Route changes (BT mic disconnect etc.): treat as interruption — pause, re-arm, resume.

### 5. Live Activity (new — widget extension + ActivityKit attributes shared with app)

- Content: EEON mark, elapsed timer, recording/paused state, stop button (`StopRecordingIntent`).
- Dynamic Island: compact = timer + mic glyph; expanded = full state + stop.
- Deliberately **no live transcript** (ActivityKit update budgets; background `SFSpeechRecognizer` unreliability). Live transcript remains in-app-only.
- Plumbing: `NSSupportsLiveActivities` in app + widget extension Info.plist settings.

## Data flow

Press (any surface) → `ToggleRecordingIntent.perform()` in background app process → `BackgroundCaptureService.start()` → `AudioRecorder` writes `{UUID}.m4a` to Documents continuously + Live Activity starts + in-flight marker persisted → [interruptions pause/resume ad infinitum] → user stops (press again / Live Activity button / in-app) → note saved with `audioFileName` → pipeline runs (now or on next foreground) → transcript, extraction, embedding land on the note as usual.

## Error handling

- Mic permission not granted: intent fails with a dialog directing to open EEON once (permission must be granted in-app first).
- Live Activity start failure: recording will be killed by the OS per the API contract → save whatever was captured, surface a local notification.
- Session activation failure at start: intent reports the error; nothing silently no-ops.
- Storage: AAC mono ≈ 30MB/hour; no special handling.

## Testing / verification (OS-gated — on-device only, per rule "say what was proven")

Simulator cannot disprove any of this. Device gate before claiming done:
1. Lock phone → Action Button → talk → stop from Live Activity → note appears with transcript.
2. Record → press side button (lock) mid-recording → keep talking 2+ min → stop → full audio present.
3. Record → receive/place a phone call → hang up → recording auto-resumed → stop → file contains pre- and post-call audio, UI/Live Activity showed paused state during the call.
4. Record 15+ min (past the old cap, past one Whisper chunk) → stop → full transcript.
5. Force-quit the app mid-recording → relaunch → partial note auto-saved.
6. Built-artifact check: background modes + `NSSupportsLiveActivities` present in the built app's Info.plist (not just source).

## Out of scope (this sub-project)

- Speaker diarization / meeting-grade summaries (sub-project 4).
- Audio-file share-extension ingest incl. iOS 18 call recordings (sub-project 3).
- EventKit Reminders/Calendar sync (sub-project 2).
- Apple Watch capture (separate day).
