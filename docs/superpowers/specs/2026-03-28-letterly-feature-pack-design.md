# Letterly Feature Pack — Filler Removal, Offline Queue, Audio Import

**Date:** 2026-03-28
**Status:** Approved

## Goal

Add three high-impact, low-effort features inspired by Letterly's success: filler word removal (their #1 review driver), offline transcription retry queue, and audio file import.

---

## Feature 1: Filler Word Removal

### What
After Whisper transcribes audio, run a GPT-4o-mini pass to remove filler words (um, uh, like, you know, so, basically, actually, I mean, right, sort of, kind of) while preserving meaning, tone, and speaker intent.

### Implementation
Add a static function to `SummaryService` (or a new small utility) that takes raw transcript text and returns cleaned text. Call it in `AIHomeView.transcribeAndSave()` right after Whisper returns and before `saveNote()`.

```
Record → Whisper transcribe → cleanFillerWords(transcript) → saveNote(cleaned)
```

### Prompt
System: "Remove filler words and verbal tics (um, uh, like, you know, so, basically, actually, I mean, right, sort of, kind of, well) from this transcript. Preserve all meaning, tone, and sentence structure. Do not summarize, rephrase, or change the content. Return only the cleaned text."

### UX
Always-on. No toggle. The cleaned transcript is what gets saved to `note.transcript`. Raw Whisper output is not stored separately.

### Cost
One GPT-4o-mini call per note, ~100-300 tokens. Sub-$0.001 per note.

### Edge Cases
- Very short notes (< 10 words): skip cleaning, save as-is
- API failure during cleaning: save the uncleaned Whisper transcript (don't lose the note)
- Note with no filler words: GPT returns it unchanged

---

## Feature 2: Offline Transcription Queue

### What
When transcription fails due to no network or API error, save the note with a pending status and automatically retry when connectivity returns.

### Data Model
Add to `Note.swift`:
```swift
var transcriptionStatus: String = "completed"  // "completed", "pending", "failed"
```

Defaults to `"completed"` for backward compatibility with all existing notes.

### Flow — Recording While Offline
1. User stops recording → audio file saved to Documents (as today)
2. Whisper API call fails (network error)
3. Instead of showing error and saving with nil transcript:
   - Save note with `transcript = nil`, `transcriptionStatus = "pending"`
   - No error alert shown to user
4. Note appears in list with a "Pending transcription" indicator

### Flow — Retry on Reconnect
1. On `scenePhase == .active` in `voice_notesApp.swift`, check for pending notes
2. Query: `notes.filter { $0.transcriptionStatus == "pending" }`
3. For each pending note that has an `audioFileName`:
   - Attempt transcription via Whisper
   - On success: run filler word removal → save transcript → run full intelligence pipeline (title, tags, intent extraction, processNoteSave)
   - On success: set `transcriptionStatus = "completed"`
   - On failure: leave as `"pending"` (will retry next time)

### UI Indicators
- Notes list: pending notes show a small clock icon or "Transcribing..." label instead of the usual preview text
- Note detail: show "Waiting for connection to transcribe..." message where transcript would be

### What Does NOT Change
- Successful transcription flow is unchanged
- Intelligence extraction still runs from transcript (just delayed for pending notes)
- Widget updates happen after retry succeeds

---

## Feature 3: Audio File Import

### What
Import existing audio files from the Files app, then run them through the standard transcription + intelligence pipeline.

### Supported Formats
.m4a, .mp3, .wav, .caf — formats Whisper accepts natively.

### Implementation
Add a `.fileImporter()` modifier to `AIHomeView`. Triggered by a new "Import Audio" button — either in a "+" menu or as a secondary action near the record button.

### Flow
1. User taps "Import Audio"
2. System file picker opens (filtered to audio types)
3. User selects a file
4. App copies the file to Documents directory with a UUID filename (same pattern as recordings)
5. Creates a new Note with `audioFileName` set
6. Runs transcription → filler removal → save → intelligence pipeline
7. Shows the same PostCaptureCard flow as a normal recording

### File Handling
- Copy file to Documents (don't reference in-place — the source may be iCloud/external)
- Generate UUID-based filename: `{UUID}.m4a` (convert extension if needed, or keep original)
- Get audio duration via `AVAudioPlayer` for the `audioDuration` field

### Button Placement
Add an "Import" button to the `HomeBottomBar` or as a long-press option on the record button. Keep it secondary to recording — import is a power-user feature.

### Edge Cases
- File too large for Whisper (>25MB): existing chunking logic in `TranscriptionService` handles this
- Unsupported format: show error alert
- Import while offline: create note with pending transcription status (Feature 2 handles retry)
- User cancels file picker: no-op

---

## What Does NOT Change Across All Three Features
- The recording flow for normal in-app recording
- The intelligence extraction pipeline (still runs from transcript)
- The transform/rewrite system
- Widget behavior
- CloudKit sync
- Subscription/paywall logic
