# Founder voice-to-agent workflow

Direction from Shawn, 2026-10-08: founders and business owners capture ideas and project updates by voice, then use their coding tools or agents to build or do the work.

Three outcomes guide this implementation:
1. Capture an idea or update quickly; recording remains the primary action.
2. Keep the project's source context and distinguish ideas, decisions, and unfinished work.
3. Hand an explicit, reviewable request to an agent and get a result with evidence and unresolved questions.

## First slice — built, native UI unverified

Note Detail now opens an Agent brief sheet. Plan / Build / Draft / Review provide editable starting requests; a custom request survives changing the work type. The sheet previews the exact prompt and copies it to the clipboard. The primary source and up to eight recent matching project notes are included, with bounded excerpts and stable IDs. Explicit project IDs are preferred; exact inferred project names are the fallback. This is a handoff to the user's agent workspace, not an EEON execution queue or an automatic deployment authorization.

No SwiftData schema changes. No release or metadata upload performed for this feature. The previous brain-dump ASO draft is superseded as a direction by this founder workflow; competitor evidence does not establish an exclusive niche or verified download demand.

## Evidence

- `connector-proof.log`: 20 checks passed against https://www.eeon.com using the existing backend `scripts/e2e-agent-oauth.mjs`. A disposable phone connection uploads a note; an approved agent can find/read it, cannot modify the mirror, and loses access after Disconnect. Test cleanup completed. This proves connector access, not agent execution.
- Formatter check compiles and executes the actual app helper:
  `swiftc 'voice notes/AgentHandoff.swift' scripts/founder/main.swift -o /private/tmp/eeon-founder-formatter && /private/tmp/eeon-founder-formatter`
  Passed request preservation, project context, truncation, source IDs, connected/offline wording, and planned/completed boundaries.
- Standing native regression: `ScreenshotTests.testFounderAgentBrief`. Not run successfully: Xcode rejects all iOS destinations because the iOS 26.2 platform is missing, despite an installed iOS 26.5 simulator runtime. The disposable phone-only QA project excluded Watch embedding solely for testing; shipping project was untouched. No platform download or repeated infrastructure retries.

## Resume gate

Restore Xcode's matching iOS platform, then run the focused test on a freshly enumerated iPad and iPhone. Verify clipboard contents and related-project inclusion through the native app, not just the formatter. Exercise a real consenting user's agent using the copied brief against an appropriate project workspace and record what it actually produces. Only then extend project organization or result feedback, and decide the release scope separately from main's unverified Watch changes.
