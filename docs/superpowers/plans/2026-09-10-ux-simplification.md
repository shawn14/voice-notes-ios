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
- [x] 5. Bottom bar + recording: "Note" / "AI prompt" labels, distinct
      AI-prompt recording state, recording bar copy.
- [x] 6. Settings: regroup to Account · Calendar · Reminders · AI access ·
      Subscription · Data; move Tune EEON / Knowledge / vocabulary / templates
      under one "Advanced" group.
- [x] 7. Note detail: trim toolbar and chips to transcript / enhanced /
      tasks / share / delete; AI transforms behind one menu.
- [x] 8. Library ("See All"): plain chronological list + search, no
      collections carousel.
- [x] 9. Onboarding: cut to sign-in + permissions + first record.
- [x] 10. Final: full build, docs (CLAUDE.md + AGENTS.md mirror, MEMORY.md
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

- **Loop 5 (08:02–08:14)** Bottom bar is now `Note` (wide, accent) · `AI Prompt`
  (same capsule shape, AI colour, labelled — the bare brain circle is gone) · Ask.
  While one records the other dims; the recorder that ran says "Working…" while
  transcribing. The recording bar reads "Recording note" / "Recording AI prompt";
  `HomeRecordingOverlay` titles and hints name the capture (`captureNoun`);
  `HomeTranscribingOverlay(isAIPrompt:)` shows two honest steps for a prompt
  ("Writing the prompt", "Queuing for your AI agents") instead of the four memory
  steps. Bug fixed: cancelling an AI prompt (Discard) or bouncing off the paywall
  left `capturingOrder = true`, so the NEXT Note would have saved as an Order.
  Restored a route to the non-voice inputs: long-press Note → Type a note / Import
  a recording / Add a link or document (the SourcePickerSheet had no entry point
  at all before these loops, and loop 1 removed the last route to audio import).
  Build exit 0; only pre-existing `Text +` deprecation warnings in HomeView.swift.

- **Loop 6 (08:14–08:24)** Settings root: Account · Assistant · Connections ·
  Advanced · Data · Help. Kept Shawn's 09-01/09-02 decisions (plan card first,
  calendar/reminder toggles on the root, Answer style inline). The one-toggle
  Notifications section folded into Assistant as "Proactive reminders";
  Personalization / Capture / People & Speakers moved to a new Advanced group with
  a **Knowledge** row (→ `KnowledgeOverviewView`, article count + Memory Map) —
  loop 1's carousel removal had left the knowledge base and Memory Map with no
  entry point at all. Subtitles and the Connections footer shortened; the footer
  also stops calling Reminders "read-only" (EEON writes tasks there). Build exit 0.

- **Loop 7 (08:24–08:36)** `NoteDetailView` 2324 → 2116 lines. Found that the
  "Extractions" chips, "Show what I said" transcript, Next Step card and transform
  output sections were defined but never rendered — a note showed none of its own
  to-dos. Added a **Tasks** card under the body (checkbox rows identical to the
  Tasks screen; completion mirrors to Reminders + export) and deleted the dead
  sections, their state, the Ask sheet they fed, and three SwiftData queries
  (decisions, commitments, URLs). The "Clean up recording" card that sat under
  EVERY note with a transcript is now a menu item ("Clean Up Recording…"); its
  progress shows in the shared indicator. Practice/quiz card kept (it is gated to
  study-like notes and was a deliberate 08-20 decision). Build exit 0, no warnings.

- **Loop 8 (08:36–08:46)** New `AllNotesView` behind Home › Notes › See All (and
  the iPad sidebar link): every note newest-first in month sections, `.searchable`,
  one filter menu (All notes / Favorites / Archived). Archived notes have a surface
  again — the old collections library (`LibraryView`, projects/people/topics
  cards) lost its only entry point in loop 2 and is left in the file unreachable.
  Reuses the existing month sections and swipe rows. Build exit 0, no warnings.

- **Loop 9 (08:46–08:54)** `OnboardingQuizView` 727 → 487 lines. Flow is now
  welcome → "What do you do?" (persona preset — the one answer that changes
  behaviour) → paywall. Removed the intent question (its answer was stored in local
  state and never read anywhere), the six-card feature grid, and the two private
  enums nobody else used. Paywall screen untouched (pricing, sign-in, Restore,
  legal links are Shawn's / App Review's). Build exit 0, no warnings.

- **Loop 10 (08:54–09:05)** Docs + gates. `CLAUDE.md` (view hierarchy, Tune EEON
  `homeLayoutJSON` note, order invariant, kill list, screenshot-label warning)
  mirrored to `AGENTS.md`; `MEMORY.md` kill list gained the 2026-09-10 section with
  the two rules this pass taught (a feature is real only if grep finds a call site;
  removing an entry point means checking what else it was the only route to).
  `ScreenshotTests` re-pointed at the renamed `Calendar options` / `All tasks`
  labels; `voice notes UITests` scheme builds for generic iOS (exit 0). Main scheme
  exit 0 after every loop. Incident + outcome logged in `~/projects/LOG.md`.

## Totals

Net −2,900 lines across `AIHomeView`, `CalendarMeetingsView`, `TasksView`,
`NoteDetailView`, `OnboardingQuizView`, `HomeView` (Settings/overlays),
`LibraryView` (+`AllNotesView`). 10 local commits on `main`, **not pushed**.

## NOT verified — needs Shawn

- Nothing has run on a device or simulator. Every loop is compiler-verified
  only. First device pass should check: bottom bar labels at Dynamic Type sizes,
  long-press Note menu, AI Prompt → Discard → Note saves as a note (the
  `capturingOrder` fix), calendar menu, Tasks card on a note, See All search and
  Archived scope, onboarding's three screens on a fresh install.
- `fastlane snap` (screenshot lane) was not run; only its test target compiled.

## Option A — the front screen, second pass (Shawn, 09:40: "overly complex… keep the very front screen extremely clean")

Shawn's brief: see calendar, then notes; separate AI prompts from notes; tasks
low-key. Chosen over a single Otter-style timeline (B) and a tab bar (C).

- **Header** is one line: date · Ask icon · avatar. No greeting.
- **Setup** is one dismissable line ("Connect your calendar and Reminders ›" →
  Settings) instead of a three-row checklist card.
- **Calendar** is a strip: "Today · 3 meetings ›" (opens the new pushed
  `CalendarScreen` = the full view with Today/Week/Month + options) and today's
  meetings as chips (time · title · video glyph; "Now" tinted; tap opens the call).
  `CalendarMeetingsView(compact:)` is the same view, same data path, same reauth
  banner (one line + Reconnect). Not connected → the strip title says so and the
  tap lands on the connect card.
- **Tasks** are one quiet line: "2 tasks due today ›" (due today or overdue, else
  "N open tasks"), gone when nothing is open. Tap → Tasks.
- **Notes | AI Prompts** segmented switch. Notes: newest-first by capture time, day
  headers, one row per note = title + time, swipe Edit/Share/Delete, 20 shown then
  "All N notes ›" → `AllNotesView`. AI Prompts: the Order/OrderDone notes only,
  with a Queued/Done pill — they never appear among notes any more.
- **One record button.** It records into whichever list is showing: Notes → accent
  "Record"; AI Prompts → AI-colour "Record AI prompt" (sets `capturingOrder`).
  Long-press keeps Type / Import / Add link. Ask lives in the header.
- Removed: the three-row task preview, note cards, "See All" section headers,
  the second recorder button. `ScreenshotTests` follows the strip → screen flow.
- Build: main scheme + UI-test scheme exit 0, no warnings in touched files.
  Installed on Shawn's iPhone (install seq 7184); launch refused because the
  phone was locked — Shawn opens it. **Built, not verified** on device.

- **Option A follow-ups (10:00–10:12).** (1) Calendar range persists —
  `@AppStorage("calendarMeetingScope")` replaces the view-local scope, so
  Today / Week / Month stays chosen across visits and launches, and Home's strip
  follows it ("This Week · 12 meetings ›"; chips show weekday or date for other
  days). ScreenshotTests resets it to Today. (2) Note rows reformatted: each day's
  notes are one inset-grouped card with inset hairlines; row = bold title over
  "time · length · topic", chevron; prompts keep the Queued/Done pill. Build exit 0;
  installed on the phone (seq 7192) and launched. **Built, not verified** by Shawn.

- **Option A follow-ups, second round (10:12–10:30).** Calendar on Home is a
  vertical inset-grouped card (time column · title · Now pill or call icon) —
  Shawn: "horizontal is strange". Everything shows three then a "More N ›" row
  (Shawn: "only show the recent three and then a More button"): 3 meetings → the
  Calendar screen; 3 notes → `AllNotesView(kind: .notes)`; 3 prompts →
  `AllNotesView(kind: .prompts)`. `AllNotesView` gained the `kind` so the full
  notes list no longer mixes prompts in (prompts have no Favorites/Archived menu).
  Home note rows lost their day headers; the meta line carries the day when it is
  not today ("Yesterday · 4:12 PM · 3m · Pricing"). Build exit 0; installed (seq
  7208) and launched. **Built, not verified** by Shawn.

## Resume protocol (if the disk fills again)

Each cron fire: `df -h /System/Volumes/Data`; if free < 1 GB, say so in one line
and stop (incremental builds need little, the products already exist). Otherwise
build, commit the staged loop, continue. One infra failure = stop and report.
