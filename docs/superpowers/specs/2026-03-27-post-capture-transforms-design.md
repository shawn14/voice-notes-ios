# Post-Capture Transform Surface

**Date:** 2026-03-27
**Status:** Approved
**Inspired by:** Letterly's rewrite-after-transcription flow

## Goal

Surface the existing Transform feature immediately after transcription completes, so users discover and use it without navigating to a buried tab.

## Current Flow

1. User stops recording
2. Full-screen `HomeTranscribingOverlay` shows "Understanding your note..."
3. Overlay dismisses when transcription + title generation complete
4. User returns to home screen
5. To transform: tap note → NoteDetailView → Transform tab (3rd tab) → pick type

**Problem:** Transform is invisible. Users don't know it exists unless they explore the 3rd tab on a note.

## Proposed Flow

1. User stops recording
2. `HomeTranscribingOverlay` shows "Understanding your note..." (unchanged)
3. When transcription + title complete, overlay **transitions** into a `PostCaptureCard`
4. Card shows:
   - Note title
   - Transcript preview (2 lines)
   - Horizontal scroll row of transform chips (existing `AITransformType` cases)
   - "View Note" button
5. User interactions:
   - **Tap a transform chip** → navigate to `NoteDetailView(note:, initialTab: .transform, autoTransform: type)`
   - **Tap "View Note"** → navigate to `NoteDetailView(note:)` on Insights tab
   - **Swipe down or wait ~8s** → dismiss to home (note already saved)
6. If transcription fails, overlay dismisses as before (no card shown)

## Components to Modify

### `AIHomeView.swift`
- Add `@State private var completedNote: Note?` to track the just-finished note
- In `saveNote()`, after `isTranscribing = false`, set `completedNote = note`
- Replace direct overlay dismissal with transition to `PostCaptureCard`

### New: `PostCaptureCard.swift`
- Receives: `note: Note`, `onTransform: (AITransformType) -> Void`, `onViewNote: () -> Void`, `onDismiss: () -> Void`
- Horizontal chip row uses existing `AITransformType.allCases` (minus `.custom` for simplicity)
- Auto-dismiss timer: 8 seconds, cancelled on any interaction
- Visual: slides up from bottom, dark glass background, matches existing app aesthetic

### `NoteDetailView.swift`
- Add optional `initialTab: NoteTab` parameter (default `.insights`)
- Add optional `autoTransform: AITransformType?` parameter (default `nil`)
- On appear, if `autoTransform` is set, auto-trigger `generateAIContent(type:)`

## What Does NOT Change

- `AITransformType` enum stays as-is (no new types)
- Transform tab UI stays as-is
- `HomeTranscribingOverlay` stays as-is (just gets a successor state)
- No new data models, no persistence changes
- AI processing pipeline unchanged

## Edge Cases

- **Very fast transcription (< 1s):** Card still shows — minimum display time of the card is user-initiated dismissal or 8s timer
- **User backgrounds app during transcription:** When app returns, if transcription finished, show card
- **Multiple rapid recordings:** Each recording gets its own card sequence; previous card dismissed when new recording starts
- **Free tier limit reached during transform:** Transform still works (it uses the existing API call path which checks for API key, not subscription)

## Success Criteria

- Transform usage increases (currently likely near-zero discovery)
- No new API calls added — transforms only fire if user taps a chip
- No disruption to existing capture flow speed
