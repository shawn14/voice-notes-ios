# Editable Enhanced Notes — Design

**Date:** 2026-05-21
**Status:** Design — pending implementation plan

## Problem

The AI enhancement pipeline sometimes gets details wrong — most commonly a
misheard name (Whisper transcribes "Tony Smith" when the user said a
different name). Today the user has no way to correct this: `enhancedNoteText`
is display-only. They can edit the raw `transcript` in `NoteEditorView`, but
that screen is buried, and the correction is invisible from where they
actually read the note.

Users need to: open a note, fix the wrong text in the enhanced version they
see, save the correction, and — optionally — have the AI redo the note from
the corrected text.

## Goal & User Flow

1. User opens a note in `NoteDetailView` and sees the enhanced text with a
   wrong name.
2. User taps **Edit**; the enhanced text becomes an editable field in place.
3. User fixes the name and taps **Save**. Their text is kept verbatim — no
   API calls. The note is marked as hand-edited.
4. Re-run controls are always visible on the note screen. The user may:
   - **Re-run enhancement** — the AI redoes the note from the corrected text
     (full redo: prose + extraction + embedding).
   - **Apply a template** — an existing rewrite template (Tweet, Email,
     Summary, custom) runs against the corrected text.
5. After a re-run, the note's enhanced text and AI-derived data reflect the
   correction.

## Key Decisions

These were settled during brainstorming and are not open for re-litigation in
the plan:

- **The user edits the enhanced text, not the transcript.** The raw
  `transcript` is never modified — it remains the historical record of the
  audio. All future AI operations on this note read the (corrected)
  `enhancedNoteText`, never the transcript.
- **Re-run is a full redo.** It regenerates the enhanced prose AND refreshes
  extracted people, topics, emotional tone, decisions/actions/commitments,
  and the search embedding — all from the corrected text. ~2 API calls.
- **Edit UI is inline.** An Edit button on `NoteDetailView` turns the
  enhanced text into an editable field in place, with Save/Cancel. No
  separate sheet or screen.
- **Re-run controls are always visible** on the note screen — not gated
  behind "you must edit first."
- **Completed action items are preserved** across a full redo.
- **Save and re-run are separate actions.** Save persists the text edit only.
  Re-run is an explicit, optional follow-up.

## Data Model Changes

Add two fields to the `Note` SwiftData model (`voice notes/Note.swift`):

- `enhancedNoteEdited: Bool = false` — set `true` when the user hand-edits
  the enhanced text.
- `enhancedNoteEditedAt: Date?` — timestamp of the last hand-edit.

**Why:** the app's Tier 2/Tier 3 background intelligence (and any future
automatic re-processing) must not silently overwrite a user's manual
correction. This flag is the guard: automatic processes check
`enhancedNoteEdited` and skip regenerating `enhancedNoteText` when it is
`true`. An explicit user-triggered re-run is the only thing allowed to
replace hand-edited text.

These are new *fields* on an existing model, not a new record *type*.
CloudKit handles added optional/defaulted fields via lightweight migration,
so no new entry in the schema array is required. The implementation plan
must still verify whether the `cloudKitSchemaSeedDidRun_v*` key needs
bumping for the new fields to register in the CloudKit Dashboard, and
confirm on a real CloudKit-backed store before shipping.

## Architecture

### Re-processing path — generalize the existing pipeline

`IntelligenceService.processNoteSave(note:transcript:projects:tags:context:)`
already runs the full chain: enhancement → extraction → embedding. Rather
than build a parallel re-processing service, generalize this so the source
text is a parameter rather than always the raw transcript.

- Introduce a re-run entry point — e.g.
  `IntelligenceService.reprocessNote(note:sourceText:projects:tags:context:)`
  — that runs the same chain using `sourceText` (the corrected
  `enhancedNoteText`) as input.
- First-save and re-run then share one orchestration path. There is one
  definition of "process a note," reducing drift.

### Components

| Component | Responsibility | Depends on |
|-----------|----------------|------------|
| `Note` (model) | New `enhancedNoteEdited` / `enhancedNoteEditedAt` fields | — |
| `NoteDetailView` | Inline edit mode for enhanced text; always-visible re-run controls; progress + error states | `IntelligenceService`, `RewriteService` |
| `IntelligenceService` | New `reprocessNote` re-run entry point reusing the existing chain; respects `enhancedNoteEdited` in background tiers | `SummaryService`, `EmbeddingService` |
| `RewriteService` | Unchanged — already accepts arbitrary input text | — |

### Data Flow

**Edit + Save (no API):**
```
NoteDetailView edit mode
  → working copy of enhancedNoteText
  → Save: write enhancedNoteText, set enhancedNoteEdited = true,
    enhancedNoteEditedAt = now, updatedAt = now
```

**Re-run enhancement (full redo):**
```
NoteDetailView "Re-run enhancement"
  → IntelligenceService.reprocessNote(note:, sourceText: note.enhancedNoteText)
  → SummaryService.extractIntent(text: corrected text)
       regenerates enhancedNoteText + people + topics + tone + intent
  → re-extraction: replace prior auto-extracted items (see below)
  → EmbeddingService re-embeds from corrected text
  → note saved. enhancedNoteEdited / enhancedNoteEditedAt are cleared
    ONLY when the AI actually returned new enhanced prose (i.e.
    enhancedNoteText was just replaced) — at that point the text is
    AI-generated again and no longer needs the hand-edit guard. If the
    re-run fails, or succeeds but returns no enhanced text, the flag
    stays true because enhancedNoteText is still the user's hand-edit
    and must remain protected. The flag tracks "is the current
    enhancedNoteText a hand-edit?", not "did a re-run happen?".
```

**Apply a template:**
```
NoteDetailView template picker
  → RewriteService.rewrite(transcript: note.enhancedNoteText, template:)
  → result stored as activeRewriteText / activeRewriteType
  → no extraction or embedding refresh — a template is a derived view,
    not a redo
```

## Re-extraction: replace without duplicating, preserve completed items

Extracted items (`ExtractedDecision`, `ExtractedAction`,
`ExtractedCommitment`, `MentionedPerson`) key off `sourceNoteId` rather than
SwiftData relationships. A naive re-run would append a second set and double
everything.

The full-redo re-extraction must:

1. **Preserve completed work.** `ExtractedAction` and `ExtractedCommitment`
   both expose `isCompleted: Bool` / `completedAt: Date?`. Items for this
   note where `isCompleted == true` are kept as-is and never deleted.
2. **Delete only stale, non-completed auto-extracted items** for this
   `sourceNoteId`.
3. **Re-create from the new extraction**, skipping any new item that
   duplicates a preserved completed item (text-similarity match, so a
   re-extraction of an already-done task does not resurrect it as a fresh
   open task).

**Open decision for the plan:** `ExtractedDecision` has no `isCompleted` —
it has a `status` field (Active / Pending / Superseded / Reversed). The
plan must decide whether a user-modified decision status counts as
"preserve-worthy" the same way a completed action does. Recommendation:
preserve `ExtractedDecision` records whose `status` is not the default
`"Active"`, by the same delete-only-defaults rule.

## Error Handling & Failure Modes

- **Save** never calls the network; it cannot fail on connectivity. The text
  edit is persisted immediately.
- **Re-run** is async with a visible progress state on the note screen.
- On API failure mid-re-run: the already-saved text edit is retained, an
  error is surfaced, derived data is left in its prior (stale) state, and
  the user can retry. A failed re-run never loses the user's correction.
- Partial failure (enhancement succeeds, embedding fails): the plan should
  define ordering so the most user-visible result (enhanced text) is
  persisted first and a failed embedding can be retried without redoing the
  prose.

## Testing

The project has no unit-test target (UI tests only, for screenshots). Verify
by exercising the real app:

- Edit enhanced text → Save → reopen the note → correction persists; the
  raw transcript still shows the original misheard text under the
  "Original" toggle.
- Re-run enhancement → enhanced text, people chips, topics, and tone all
  reflect the corrected name.
- Re-run with a completed action item present → the completed item survives;
  no duplicate open copy appears.
- Apply a template after editing → the template output uses the corrected
  text.
- Re-run with network disabled → error shown, saved edit intact.
- Confirm CloudKit sync of the new fields on a real device (per CLAUDE.md,
  the simulator cannot sync).

## Out of Scope (YAGNI)

- Version history / undo stack for enhanced text. Save overwrites; the
  transcript remains as the one historical anchor.
- Editing the raw transcript from the detail screen (already possible in
  `NoteEditorView`).
- Field-level editing of extracted chips (people, topics) directly — a
  re-run regenerates them.
