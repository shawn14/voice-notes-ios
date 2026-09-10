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
- [ ] 2. Dead-code sweep in `AIHomeView`: browseFeed / conversationsHeader /
      FeedMode / search field / category cards / week strip / date picker /
      tag sheets / AI tab / drift banner / why-this-home. Compiler is the gate.
- [ ] 3. Calendar section: one header row, no options/refresh icon clutter in
      the embedded view; meeting rows tap → record about this meeting.
- [ ] 4. Tasks: home preview + `TasksView` share one row style; clear
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
