# Founder voice-to-agent workflow

Direction from Shawn, 2026-10-08: founders and business owners capture ideas and project updates by voice, then use their coding tools or agents to build or do the work.

Three outcomes guide this implementation:
1. Capture an idea or update quickly; recording remains the primary action.
2. Keep the project's source context and distinguish ideas, decisions, and unfinished work.
3. Hand an explicit, reviewable request to an agent and get a result with evidence and unresolved questions.

## First slice — seeded native handoff exercised

Note Detail now opens an Agent brief sheet. Plan / Build / Draft / Review provide editable starting requests; a custom request survives changing the work type. The sheet previews the exact prompt and copies it to the clipboard. The primary source and up to eight recent matching project notes are included, with bounded excerpts and stable IDs. Explicit project IDs are preferred; exact inferred project names are the fallback. This is a handoff to the user's agent workspace, not an EEON execution queue or an automatic deployment authorization.

No SwiftData schema changes. No release or metadata upload performed for this feature. The previous brain-dump ASO draft is superseded as a direction by this founder workflow; competitor evidence does not establish an exclusive niche or verified download demand.

## Evidence

- `connector-proof.log`: 20 checks passed against https://www.eeon.com using the existing backend `scripts/e2e-agent-oauth.mjs`. A disposable phone connection uploads a note; an approved agent can find/read it, cannot modify the mirror, and loses access after Disconnect. Test cleanup completed. This proves connector access, not agent execution.
- Formatter check compiles and executes the actual app helper:
  `swiftc 'voice notes/AgentHandoff.swift' scripts/founder/main.swift -o /private/tmp/eeon-founder-formatter && /private/tmp/eeon-founder-formatter`
  Passed request preservation, project context, truncation, source IDs, connected/offline wording, and planned/completed boundaries.
- Standing native regression: `ScreenshotTests.testFounderAgentBrief` passed on signed disposable iPad and iPhone26.2 simulators. Actual clipboard/SwiftData source fidelity passed independently for both. The earlier iPhone navigation failure remains unexplained; no product navigation fix is claimed. Phone-only QA excluded Watch embedding; shipping configuration is unchanged. See native-ipad/ and native-iphone/.

## Next slice

The actual iPad packet was consumed by installed Codex to produce a local source-cited artifact, with actual desktop/phone browser checks and independent review (copied-packet/). Both seeded native sizes now produce faithful clipboard packets. Physical recording, connected-note UI, native OAuth login, Gemini/Grokbot execution, and release remain incomplete.

Result return is the next project-workflow gap. Existing text/file ingest and project-linked notes are reusable, but they have not been proven to preserve agent-result provenance or associate returned work with its source. See result-return-design.md; the choice between reviewed paste and direct connector writes is pending Shawn's preference. Never silently treat agent-reported completion as verified completion.

## Source fidelity — 2026-10-08

The handoff now includes the original transcript (or note content) first, plus a separately labeled AI rewrite or user-edited note. User edits carry their existing edit timestamp. If original text is absent, the brief labels that explicitly; an all-empty capture says no source text is available. No stored model fields changed. The helper itself caps related context at eight notes, including for non-UI callers.

Actual formatter regression: source text containing a closing quotation tag failed before the fix (`source-fidelity/red.txt`). The same check passes after escaping quotation markup. A fresh refuter also found unescaped note-title metadata; titles and project labels now escape markup and flatten line breaks, and the refuter's exact case passed on recheck. Formatter checks cover differing transcript/AI rewrite, user edits, empty/absent originals, bounds, body quotation and metadata. Receipt `source-fidelity/green.txt`. Quotation formatting is not a guarantee against semantic prompt injection; notes remain reference material.

This proves the Foundation helper and its source-selection behavior on real supplied values. The caller is wired to existing Note fields; actual SwiftData selection, native rendering/clipboard, and a named agent acting on the packet remain unverified while the platform gate persists.
