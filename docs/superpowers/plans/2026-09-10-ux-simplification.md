# UX Simplification — 2026-09-10 (autonomous /loop, 10 passes)

**Ask (Shawn):** "make the app much simpler and cleaner UX but maintain note
recording and AI prompt recording plus calendar and to dos. just make clean."

**Keep (the four jobs):** 1) record a note, 2) record an AI prompt (order),
3) calendar, 4) to-dos. Everything else earns its place or leaves the main path.

**Method per loop:** one bounded cut → cached Debug `xcodebuild` (generic iOS)
→ commit locally (no push without Shawn's go). Each loop checks its box here
and appends to STATUS.md so a killed session resumes, not restarts.

**Rules honoured:** removed views stay in the codebase and go on the MEMORY.md
kill list (repo convention); never delete user notes; no schema changes.

## Loops

- [x] 1. Home = Calendar → Tasks → Notes, fixed order. Remove from home: Knowledge
      carousel, LLM persona sections (`HomeLayout` dispatch), Tune hero card,
      "Import a recording" checklist row. Rename "Action Items" → "Tasks",
      "Recent" → "Notes".
- [x] 2. Dead-code sweep in `AIHomeView`: browseFeed / conversationsHeader /
      FeedMode / search field / category cards / week strip / date picker /
      tag sheets / AI tab / drift banner / why-this-home. Compiler is the gate.
- [x] 3. Calendar section: one header row, no options/refresh icon clutter in
      the embedded view; meeting rows tap → record about this meeting.
- [x] 4. Tasks: home preview + `TasksView` share one row style; clear
      complete / due / open-note affordances; "All" → Tasks screen.
- [ ] 5. Bottom bar + recording: "Note" / "AI prompt" labels, distinct
      AI-prompt recording state, recording bar copy.
- [ ] 6. Settings: regroup to Account · Calendar · Reminders · AI access ·
      Subscription · Data; move Tune EEON / Knowledge / vocabulary / templates
      under one "Advanced" group.
- [ ] 7. Note detail: trim toolbar and chips to transcript / enhanced /
      tasks / share / delete; AI transforms behind one menu.
- [ ] 8. Library ("See All"): plain chronological list + search, no
      collections carousel.
- [ ] 9. Onboarding: cut to sign-in + permissions + first record.
- [ ] 10. Final: full build, docs (CLAUDE.md + AGENTS.md mirror, MEMORY.md
      kill list, STATUS.md), commit, stop loop, notify.

## Log

- **Loop 1 (00:05–00:12)** `AIHomeView` −183 lines. Home body is now greeting →
  sync banner → 3-row setup checklist (until done) → free-tier warning → Calendar →
  Tasks → Notes → bottom bar. Removed from home: Knowledge carousel, `HomeLayout`
  persona-section dispatch, Tune hero card, "Import a recording" row. Build: cached
  Debug generic-iOS `xcodebuild` exit 0 (25s). Not device-verified.
- **Loop 2 (00:15–00:45, verified 07:33 after ~6.5 h blocked on a full disk).** `AIHomeView`
  2948 → 2067 lines (−881): removed the unreachable feed machinery (FeedTab/FeedMode
  + segmented header, keyword search, category cards, week strip, date filter +
  picker sheet, tag sheets, AI tab, library collections carousel, drift banner +
  DriftDetector call, Tune/why-this-home sheets) and 9 `@Query`s home no longer
  reads. The verifying build died on infrastructure, not code: `xcodebuild` exit 65
  with `accessing build database … disk I/O error` — the Data volume had **805 MB
  free (100 %)**. The failure also emptied this project's DerivedData
  (`SourcePackages` and `Build/Products` gone, 39 MB left), so the next build is a
  full one that re-resolves SwiftPM packages. Nothing safe to delete without Shawn:
  every large `/private/tmp` workspace was written 2026-09-09 and two are held open
  by other sessions; the rest is his caches/simulators/archives. Loop 2 was
  un-committed (`git reset --soft`) so `main` carries only verified commits; the
  change is staged in the working tree.

- **Loop 2 verified 07:33.** Free space rose to 3.0 GB (not by me), the project has
  zero SwiftPM packages so the "full" build was cheap: `xcodebuild` exit 0, 0 errors,
  0 warnings in `AIHomeView`, ~41 s. Build products took the volume from 1.9 GB to
  597 MB free again — later loops are incremental, but the disk is still the risk.

- **Loop 3 (07:36–07:50)** `CalendarMeetingsView` 933 → 671 lines, embedded-only.
  It was only ever presented from Home, so the full-screen mode (split view,
  meeting detail pane with related notes, selection state, `onRecord`, the `notes`
  SwiftData query that fed it) was unreachable and is gone. Header now matches the
  Tasks/Notes headers: title + date line, and ONE menu holding Today/Week/Month,
  Refresh, and the Google/iPhone toggles (was three icons). Connect state is a
  compact card without the "Permission: …" line; empty state is one quiet line
  with a hint only when calendars are missing or events were filtered. Rows are
  tappable only when they have a call link. Build exit 0, no warnings in the two
  files. Not device-verified.

- **Loop 4 (07:50–08:02)** `TasksView` 550 → 449 lines, single mode. The `embedded`
  body was dead (Home renders its own 3-row preview) and the pushed screen wrapped
  its own NavigationStack, so it showed a back button AND a Done button. Now a plain
  pushed list: large title, ONE `ellipsis.circle` menu (show/hide completed, share
  list, complete/reopen all shown) instead of three toolbar icons, Add Task capsule
  kept as the primary action. Rows match Home's preview rows (checkbox · text ·
  due / owner / priority · chevron when tapping opens the note); the "From a note"
  / "Note" chips are gone on both screens, the chevron says it. Home's Tasks link
  reads "See All" like Notes. Build exit 0, no warnings in touched files.

## Resume protocol (if the disk fills again)

Each cron fire: `df -h /System/Volumes/Data`; if free < 1 GB, say so in one line
and stop (incremental builds need little, the products already exist). Otherwise
build, commit the staged loop, continue. One infra failure = stop and report.
