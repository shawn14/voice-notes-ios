# TODOS

Deferred work, captured with enough context to pick up cold.

---

## 1. Stand up an XCTest unit-test target; cover the re-run preservation/dedup logic

**What:** Add a unit-test target to the Xcode project and write `XCTest`
coverage for `IntelligenceService.clearReprocessableItems` and the
duplicate-skip logic in `reprocessNote`.

**Why:** The editable-enhanced-notes feature (shipped 2026-05-21) added the
re-run pipeline. Its subtlest, most regression-prone logic — preserving
completed `ExtractedAction`/`ExtractedCommitment` and non-`"Active"`
`ExtractedDecision` across a re-run, and skipping re-creation of duplicates
of preserved items — has zero automated coverage. The project currently
ships UI tests only (screenshot automation), no unit tests.

**Pros:** Locks down the riskiest paths against silent regressions; unlocks
unit testing for the whole app going forward.

**Cons:** Standing up the first unit-test target is project infrastructure,
not a quick task — scheme config, an in-memory `ModelContainer` test
fixture, and CI wiring. Larger than the feature it would test.

**Context:** Logic lives in `voice notes/IntelligenceService.swift` —
`clearReprocessableItems` (preserve/delete by `isCompleted` / `status`) and
`reprocessNote` (the `preserved.*Texts.contains(...)` skip guards). Tests
should build an in-memory `ModelContainer`, insert a `Note` plus completed
and non-completed `Extracted*` items, run `clearReprocessableItems`, and
assert the right items survive. No network needed — test the cleanup/dedup
in isolation, not the `SummaryService` call.

**Depends on / blocked by:** Nothing. This is the prerequisite for TODO #2.

---

## 2. Extract a shared `applyExtraction` helper to remove reprocessNote / processNoteSave duplication

**What:** Factor the ~40 lines of "apply an `IntentAnalysis` to a `Note`"
logic — scalar field assignment plus `ExtractedDecision`/`ExtractedAction`/
`ExtractedCommitment` insertion — into one private helper in
`IntelligenceService`, called by both `processNoteSave` and `reprocessNote`.

**Why:** `reprocessNote` (added 2026-05-21) re-implements that block, which
`processNoteSave` already had. A new field on `IntentAnalysis` must be
wired into both or they silently drift.

**Pros:** DRY — one definition of "map extraction onto a note."

**Cons:** `processNoteSave` is load-bearing (6 call sites, runs on every
note creation). A behavior-preserving extraction is lower-risk than it
sounds, but with no test target it cannot be verified automatically — a
subtle regression would ship silently.

**Context:** Duplication is in `voice notes/IntelligenceService.swift`:
`processNoteSave` ~lines 79-184 and `reprocessNote` ~lines 303-354. The
divergent parts must stay in each caller — `processNoteSave` also does
counter increments, `KanbanItem` creation, persona/URL processing;
`reprocessNote` does `clearReprocessableItems` + completed-item dedup. Only
the genuinely identical scalar-assignment + item-insertion belongs in the
helper.

**Depends on / blocked by:** TODO #1 — do this only once the test target
exists, so the refactor of untested load-bearing code has a safety net.

---

## 3. Audit all OpenAI call sites for ContextAssembler consistency

**What:** Do a systematic pass over every place the app calls the OpenAI
API and confirm each one routes the user's tuned context through
`ContextAssembler.flatPrefix(for:)` with the correct `AICallContext`.

**Why:** Investigating "Tune EEON doesn't tune things" (2026-05-21) turned
up `NoteDetailView.generateWithOpenAI` — a hand-rolled `URLSession` call to
`/v1/chat/completions` that used a static system prompt and bypassed
`ContextAssembler` entirely, so the quick transforms (Summary, Tweet, PRD,
CEO Report, etc.) ignored the user's tuning. That one is now fixed (routed
through `.rewrite` context). But a hand-rolled call site that drifted from
the assembler suggests others may exist — any AI call that bypasses
`ContextAssembler` silently ignores Tune EEON.

**Pros:** Guarantees tuning actually reaches every AI surface; removes a
whole class of "tuning has no effect here" bugs.

**Cons:** Requires judgment per call site — the right `AICallContext` varies
(`.rewrite`, `.extraction`, `.rag`, `.title`, etc.), and some trivial
classifier calls intentionally inject nothing.

**Context:** `ContextAssembler.flatPrefix(for: AICallContext)` is the single
entry point; `AICallContext` (in `ContextAssembler.swift`) defines per-context
toggles for purpose/profile/voice/focus/index. Reference implementation:
`RewriteService.rewrite` prepends `flatPrefix(for: .rewrite)` to its system
prompt. Grep for `chat/completions`, `URLSession`, and direct model strings
(`gpt-4o-mini`) to enumerate call sites; `SummaryService` centralizes most
but `NoteDetailView` had its own — check the other views too.

**Depends on / blocked by:** Nothing.

---

## 4. MCP server over EEON memory ("every conversation becomes AI context")

**What:** Expose the user's EEON memory — notes, compiled `KnowledgeArticle`s,
extractions — to external AI assistants (Claude, ChatGPT, Cursor) via an MCP
server, so any assistant can query "what did I say about X" against EEON.

**Why:** From the 2026-08-19 Pocket (heypocket.com) competitive review: Pocket
ships ChatGPT/Claude/MCP integration under "every conversation becomes AI
context," and it's the one integration in their spread that matches how Shawn
actually works (Claude Code all day). EEON's compiled knowledge is *better*
context than Pocket's raw transcripts — the Karpathy LLM articles are
pre-synthesized. Flagged as the natural v2 integration; one of the four gaps
not covered by the 2026-08-19 day plan.

**Pros:** Kills the "my notes are trapped in an app" objection; uniquely
strong fit for the vibe-coder audience in the pivot direction; compiled
articles make retrieval quality a differentiator.

**Cons:** Requires a server component or local bridge (EEON is an iOS app —
notes live in SwiftData/CloudKit on device); auth + privacy design is the
hard part, not the protocol. Needs its own spec.

**Context:** Data lives on-device (SwiftData) + CloudKit (`iCloud.aivoiceeeon`).
Options to explore in the spec: CloudKit web services read-only bridge, a
small sync target (export to a user-owned store), or Mac-side local MCP
reading an exported archive from `ExportService`.

**Depends on / blocked by:** Nothing technically; needs a spec/plan cycle.

---

## 5. Obsidian / markdown auto-export ("conversations become searchable files")

**What:** Auto-export notes (and optionally compiled `KnowledgeArticle`s) as
markdown files to a user-chosen folder — an Obsidian vault, iCloud Drive, or
any Files provider (Google Drive/OneDrive come free via the Files picker).

**Why:** Pocket review 2026-08-19: their "Documents" integration spread
(OneDrive, Drive, Obsidian) is one of the four gaps EEON doesn't cover.
`ExportService` today is manual bulk export only. Markdown-to-folder is the
cheapest of the document integrations — no OAuth, no per-service API; a
security-scoped bookmark to a folder + write-on-save covers all three logos.

**Pros:** One implementation covers Obsidian + Drive + OneDrive; markdown
with frontmatter (topics, extractions) makes EEON data portable and
grep-able; strong retention hook for PKM users.

**Cons:** Sync semantics need care (re-export on edit? filename stability?
deletions — never delete user files, mirror the never-delete-notes rule);
background export timing on iOS is best-effort.

**Context:** Start from `ExportService` (bulk export exists). Use
`UIDocumentPickerViewController` folder selection + security-scoped bookmark
persisted in UserDefaults; write `{note-date}-{slug}.md` on note save /
enhancement completion.

**Depends on / blocked by:** Nothing.

---

## 6. Third-party task app sync (Todoist / Linear / ClickUp / Asana / TickTick)

**What:** Push `ExtractedAction`s (and optionally commitments) into
third-party task managers beyond Apple Reminders, starting with whichever
one real users actually request first.

**Why:** Pocket review 2026-08-19: their task-management spread is seven
apps; EEON's 2026-08-19 day plan covers Apple Reminders/Calendar via
EventKit only. Each third-party app is its own OAuth + REST integration, so
this was deliberately deferred rather than half-built.

**Pros:** Completes the "one note updates all your apps" story for
non-Apple-native task users; Todoist alone covers a large share of them.

**Cons:** Per-service OAuth flows, token storage, API drift; ongoing
maintenance per integration; unclear which service EEON's actual users want
first — build on demand, not on spec.

**Context:** Prereq design lands in sub-project 2 (EventKit sync,
2026-08-19): the "extraction → external task" mapping layer built there
(what syncs, dedup keys, completion write-back or not) should be
service-agnostic so each new backend is an adapter, not a rethink.

**Depends on / blocked by:** Sub-project 2 (EventKit sync) shipping first —
its mapping layer is the foundation.

---

## 7. Mind-map / graph view over the Knowledge Base

**What:** A visual graph view of the user's memory — `KnowledgeArticle`s as
nodes (people/projects/topics), edges from shared `KnowledgeEvent`s /
co-mentions, tappable through to articles and notes.

**Why:** Pocket review 2026-08-19: "dynamic mind maps" is one of their three
AI feature cards and one of the four gaps EEON doesn't cover. Ranked lowest
of the four on purpose: the Knowledge Base already does the *connecting*
(the substance); this is presentation. Worth having eventually because it
demos brilliantly (screenshots, App Store, TikTok) even if daily utility is
modest.

**Pros:** High visual wow for marketing and onboarding ("look what EEON
knows about my life"); zero new data model — renders existing
articles/events.

**Cons:** Graph layout in SwiftUI is real work (force-directed layout or a
Canvas-based renderer); risk of building a pretty screen nobody revisits —
validate against screenshot/demo value, not retention claims.

**Context:** Data already exists: `KnowledgeArticle` (7 kinds),
`KnowledgeEvent` (per-topic accumulation), `MentionedPerson`, `topicsJSON`
on notes. Start as a read-only Canvas view fed by `KnowledgeCompiler`'s
article set; no new persistence.

**Depends on / blocked by:** Nothing.
