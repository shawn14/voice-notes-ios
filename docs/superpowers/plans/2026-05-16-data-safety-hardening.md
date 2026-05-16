# Data Safety Hardening — Enforce "Never Delete User Notes"

**Date filed:** 2026-05-16
**Motivation:** Shawn's hard rule: *"We need to make sure that we never delete people's notes. That would really piss people off."* (See memory: `feedback_never_delete_user_notes.md`)

## Context

The current SwiftData container fallback in `voice notes/voice_notesApp.swift:38-105` is much safer than `CLAUDE.md` describes — past-you already replaced the destructive "delete and recreate" logic with a backup-then-recreate flow (see comment on `voice_notesApp.swift:64`: *"Previous code deleted the store here which destroyed all local notes"*).

But there are still residual paths that can lose user data silently. This plan closes those gaps.

Priority ordering: 1 is a doc fix (5 min), 2 is a 1-line code change (15 min), 3 is real UX work (~half a day).

## Phase 1 — Update CLAUDE.md to match reality

**File:** `CLAUDE.md`, "SwiftData + CloudKit Constraints" section.

**Current (stale) text:**

> **Container fallback hierarchy.** CloudKit → local SQLite → delete store and recreate. See `voice_notesApp.init()`.

**Should be:**

> **Container fallback hierarchy.** CloudKit → local SQLite → **backup-then-recreate-with-CloudKit** → in-memory (last resort). The "delete store" behavior was removed; the current logic at `voice_notesApp.swift:38-105` copies the old store to `Documents/default-backup-<timestamp>.store` before deleting, and then recreates a fresh CloudKit-backed store so iCloud-synced notes resync down. The in-memory last-resort path means a launch never crashes but new notes that session are not persisted.

**Acceptance:** docs match the code. Future agents reading CLAUDE.md don't reason from a false premise.

## Phase 2 — Make the backup-copy failure loud, not silent

**File:** `voice notes/voice_notesApp.swift`, lines 67-81 (third-fallback recovery path).

**Problem:** Line 74 uses `try?` on the backup copy:

```swift
try? FileManager.default.copyItem(at: storeURL, to: backupURL)
```

If the copy fails (disk full, sandbox permissions, anything), the error is swallowed. The very next block (lines 78-81) then calls `removeItem` and deletes the store anyway — so a failed backup means data is wiped with no recourse.

**Change:** Replace `try?` with proper error handling. If the backup copy throws, **do not proceed with the deletion**. Instead, fall straight through to the in-memory fallback so the user's on-disk data is preserved untouched. Log the backup failure to `cloudKitInitError` UserDefaults so we have telemetry.

Sketch:

```swift
do {
    try FileManager.default.copyItem(at: storeURL, to: backupURL)
    print("Backed up store to: \(backupURL.path)")

    // Only delete after a confirmed backup.
    for ext in ["", ".wal", ".shm"] {
        let fileURL = ext.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + ext)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // ... recreate fresh CloudKit container as today ...
} catch {
    // Backup failed — DO NOT delete the user's data.
    // Surface to in-memory fallback and persist the error for diagnostics.
    UserDefaults.standard.set("backupFailed:\(error)", forKey: "cloudKitInitError")
    throw error  // caught by the outer catch on line 92, drops to in-memory
}
```

**Acceptance:**
- A simulated backup-copy failure (e.g., point `backupURL` at a non-writable path in a debug test) results in the original store still existing on disk after launch.
- `cloudKitInitOutcome = "inMemory"` and `cloudKitInitError` contains the backup-failure message.
- No `.wal`/`.shm`/store file removed when backup failed.

**Verification:** unit-testable in a tear-down/setup harness, or manually via simulator with a forced-failure injection.

## Phase 3 — Surface recovery to the user via a sheet (consent + visibility)

**Files:** new `RecoverySheet.swift` (or similar), `voice notes/voice_notesApp.swift`, and the home view to gate showing the sheet.

**Problem:** When the fallback path runs, the user sees no UI explanation. They open the app and may find fewer notes (or none) with no indication anything happened. They can't tell "I lost data" from "this is a fresh install" or "iCloud sync is just slow." That's the worst failure mode for trust.

**Change:** When `cloudKitInitOutcome` is `localFallback`, `recoveredCloudKit`, or `inMemory`, surface a non-dismissible sheet on app launch that explains what happened, shows the backup file path (and a "Reveal in Files" action), and provides next steps. Examples:

- **localFallback:** "EEON couldn't connect to iCloud this launch. Your notes are still on this device. Sign in to iCloud / check your network / try again." (No data loss — just a warning.)
- **recoveredCloudKit:** "EEON had to repair its local data store. Your notes are safely backed up at `[path]`. We're now syncing your notes back from iCloud — this can take a minute. Tap [Open Backup Folder] to view the local backup."
- **inMemory:** "⚠️ EEON couldn't open the data store on this device. Notes you create this session **will not be saved.** Tap [Retry] to attempt recovery, or [Open Backup Folder] if a backup exists."

**Acceptance:**
- Sheet appears on first launch after any fallback occurs (gated by `cloudKitInitOutcome` UserDefaults).
- User cannot silently get into a destructive-recovery state without seeing this UI.
- Each sheet variant has copy that matches the actual outcome, not "something went wrong."
- A dismiss + "don't show again this session" flag prevents nagging on every foreground.

**Verification:**
- Run all three fallback paths in dev (force CloudKit failure, force SQLite failure, force backup failure) and confirm correct sheet shows.
- Copy reviewed for clarity — non-technical user can understand what to do.

## Out of Scope

- Restoring from the local backup file. The `.store` backup is currently just an artifact; no UI imports it back. That's a separate (bigger) feature: a "recover from backup" tool that reads the backup `.store`, opens it as a secondary `ModelContainer`, and copies records into the live store. Worth doing eventually but not on this plan's scope.
- CloudKit conflict resolution UX (when local + iCloud diverge). Already handled by NSPersistentCloudKitContainer's default merge policies.
- Audio file (`.m4a`) recovery. The audio file lives in `Documents/` and is not part of the SwiftData store, so it's not affected by this fallback path. Separate concern.

## When to Execute

Not urgent. The recording fix (3.5.1 build 131) ships safely without these changes — that fix doesn't touch this code path. Take Phase 1 + 2 next time you're in this area (~30 min total). Phase 3 deserves its own focused session and possibly a spec.

## References

- Memory: `feedback_never_delete_user_notes.md`
- Code: `voice notes/voice_notesApp.swift:38-105`
- Stale doc: `CLAUDE.md` "Container fallback hierarchy"
- Commit context: `c3403f9` → `87c2b62` → `85a6b0f` (recording fix shipped in 3.5.1 build 131; this plan was filed in the same session as a follow-up)
