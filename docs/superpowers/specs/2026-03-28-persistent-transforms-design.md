# Persistent Transform as Primary Display

**Date:** 2026-03-28
**Status:** Approved

## Goal

Make transforms the primary content of a note. When a user transforms a voice note into a summary, tweet, or brief, that transformed version becomes what they see by default. The original transcript is always accessible via a toggle.

## Current Problem

Transforms are ephemeral `@State` variables in `NoteDetailView`. The output disappears when you leave the note. The transform lives in a buried 3rd tab. Users see it as a gimmick, not a core feature.

## Design: Source + One Active Rewrite

### Data Model Changes (Note.swift)

Add two fields to the `Note` model:

```swift
var activeRewriteText: String?    // The transformed content (nil = no transform)
var activeRewriteType: String?    // "Summary", "Tweet", "PRD", etc.
```

Both default to `nil`. CloudKit-compatible (optional strings).

### Display Logic

When viewing a note, the primary content area shows:

1. **If `activeRewriteText` exists**: Show the rewritten version with a type label (e.g. "Summary") and a "View Original" toggle
2. **If `activeRewriteText` is nil**: Show `transcript` / `content` as today (no change)

The toggle switches between "Rewritten" and "Original" views. This is a local UI toggle — it does not modify any data.

### Transform Flow

1. User taps a transform chip (PostCaptureCard or Transform tab)
2. AI generates the output (existing `generateAIContent` function)
3. Output saved to `note.activeRewriteText`, type saved to `note.activeRewriteType`
4. `note.updatedAt` set to `Date()`
5. View immediately shows the rewritten version as primary
6. User can tap a different transform → replaces both fields
7. User can tap "Clear" → sets both fields to nil, original transcript shows again

### NoteDetailView Changes

**Insights tab (primary view):**
- If `note.activeRewriteText != nil`:
  - Show a small pill/badge: "Summary" (or whatever `activeRewriteType` is)
  - Display `activeRewriteText` as the main content
  - Show a "View Original" text button that toggles to the transcript
  - Show a "Clear Transform" option (sets both fields to nil)
- If `note.activeRewriteText == nil`:
  - Show transcript/content as today (unchanged)

**Transform tab:**
- Same grid of transform chips as today
- `generateAIContent` now writes to `note.activeRewriteText` and `note.activeRewriteType` instead of `@State` variables
- After transform completes, automatically switch to Insights tab to show the result as primary
- The `@State private var aiOutput` / `aiOutputType` are removed — the Note model is the source of truth

**Transcript tab:**
- Always shows the raw transcript (unchanged)
- This is the "View Original" destination

### PostCaptureCard Integration

When a user taps a transform chip on the PostCaptureCard:
- Navigates to `NoteDetailView` with `autoTransform` set
- Transform runs and saves to the model
- User lands on the Insights tab seeing the transformed content as primary

### What Does NOT Change

- `transcript` field is never modified — always the raw Whisper output
- Intelligence extraction (decisions, actions, commitments) still uses `transcript`
- Daily briefs, project matching, all other AI features use `transcript`
- `content` field behavior unchanged
- Tags, title generation, all other processing unchanged
- The `AITransformType` enum unchanged
- The `generateWithOpenAI` function unchanged

### Edge Cases

- **No transcript**: If there's no transcript (recording failed), transforms are disabled (button disabled state)
- **Re-transform**: Tapping a new transform type replaces the existing one — only one active rewrite at a time
- **Widget preview**: `SharedDefaults.lastNotePreview` continues to use `note.displayTitle` — does not show transform text
- **Search**: Search should match both `activeRewriteText` and `transcript` so transformed notes are still findable by original words

### Migration

No data migration needed. New fields default to `nil`. Existing notes show transcript as before. The schema array in `voice_notesApp.swift` does not need updating since we're adding optional properties to an existing model (SwiftData handles this automatically).
