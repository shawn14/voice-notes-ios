# Recently Deleted (30-day recycle bin) — design

**Date:** 2026-10-01
**Status:** Awaiting a decision (Option A vs B below)
**Why:** Pocket keeps deleted recordings for 30 days. In EEON, Delete Note is
permanent and immediate, everywhere: the CloudKit private DB syncs the delete to
every device and the agent mirror prunes it. One mis-tap loses a recording.

## What the user sees (same for both options)

- Delete Note moves the note to **Recently Deleted** (Library → bottom of the
  list, or Settings). Confirmation copy changes from "This cannot be undone" to
  "You can restore it from Recently Deleted for 30 days."
- Recently Deleted lists notes with "N days left", **Restore**, **Delete Now**,
  and **Delete All**.
- After 30 days the note, its audio and its photos are removed for good. The
  purge runs on app foreground (no background work needed).
- **Delete Account & Data** skips the bin: everything goes immediately.
- Extracted items (actions, decisions, commitments) are untouched either way:
  they already outlive their note by design (`sourceNoteId`, no cascade).

## Option A — `deletedAt: Date?` on `Note` (synced trash)

The note stays in SwiftData with a timestamp; every surface filters it out.

- **Good:** works across devices: delete on iPad, restore on iPhone. Restore
  is one field write, with nothing lost or reconstructed.
- **Cost:**
  - **CloudKit schema change.** It needs seed v7 and a Production schema deploy
    before the App Store build. A missing Production field stops all sync
    silently (the 2026-06 → 09 incident in CLAUDE.md).
  - **Every reader must skip trashed notes.** That's 36 `@Query` /
    `FetchDescriptor<Note>` sites, plus RAG, `KnowledgeCompiler`,
    `AgentMirrorService` (it must prune trashed notes, so agents can't read
    them), widgets, App Intents, MCP export and the markdown vault export.
  - Any site that's missed leaks deleted notes back into answers, briefs or
    agents.
- **Size:** large, touching about 25 files. The release gate gets a new step.

## Option B — local trash folder (snapshot, then real delete)

Delete writes a snapshot of the note to `Application Support/Trash/<id>/`
(`note.plist`, plus the audio and image files moved there), then deletes the
note from SwiftData exactly as today. Restore re-inserts a `Note` with the same
`id` and moves the files back.

- **Good:**
  - No schema change and no release gate.
  - No query changes: the note really is gone, so the mirror, RAG, widgets,
    intents and exports are correct for free.
  - Small: one service, one list screen, and the delete call sites (7 files).
- **Cost:**
  - **The bin is per-device.** A note deleted on the iPad can only be restored
    on the iPad. Once restored, it syncs back everywhere.
  - **The snapshot must cover all 68 stored `Note` fields.** Map them by
    reflection over `Note.schemaMetadata` rather than by hand, so a field added
    later is captured automatically. Supported value types: String, Date, Bool,
    Int, Double, Data, UUID, and optionals of these.
  - **Restored notes lose their tag links.** The `Tag.notes` relationship isn't
    a stored field, so the snapshot keeps tag *names* and restore re-links them
    by name.

## Recommendation

**B.** It delivers the user-visible feature (undo a mistaken delete for 30
days) without touching CloudKit schema or the 36 read paths. The schema
incident shows that risk is real. The per-device limit rarely matters, because
people restore right after the mistaken delete, on the device they made it on.
If cross-device restore is ever needed, B's snapshot format can later seed an
A-style migration.

## Open questions

1. Should Recently Deleted live in Library or in Settings? Library is
   proposed: that's where notes live.
2. Should a Free user's deleted notes count against the 5-note limit while
   they're in the bin? Proposed **no**: the note was deleted, so it frees the
   slot. Restoring when at the limit shows the paywall.
