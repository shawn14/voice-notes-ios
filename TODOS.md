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
