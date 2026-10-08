# Returning agent work to a project

## Observed evidence

The bounded AppleCharts pull on 2026-10-08 analyzed107reviews in a3month window across5apps. It found4reliability complaints,7pricing/subscription complaints and export/sharing in3listings. This small sample does not demonstrate demand for founder-agent automation. Its automatic classifications include questionable matches; use examples and counts cautiously. Raw output: result-return-market.md.

Shawn's explicit founder direction supplies the product requirement: captured ideas should lead to useful project work through the person's chosen agents. Actual Codex execution has produced index.html and handoff-result.md from an EEON packet; only the outgoing half is exercised.

## Core Three

1. Capture a usable idea quickly. Keep recording primary; returned reports must not displace capture. Verify physical recording/transcription separately, currently incomplete.
2. Keep reliable project context. Preserve source UUID, project association, original capture and returned text. Search/filtering appears in all5listings; project association is an explicit founder need, not proven market demand. Verify persistence/relaunch and project inclusion/exclusion against the real database.
3. Turn an explicit request into inspectable work. The source-grounded Codex artifact and existing sharing in3listings support portability; direct automated write-back is still an assumption. Verify actual result save/readback and later retrieval alongside its source, with agent claims separated from independent checks.

## Existing paths to reuse

- DataIntents Add to EEON/Add File enqueue into SharedDefaults.pendingIngests; IntelligenceService.processPendingIngests saves a Note then runs extraction/embedding. Generic ingest does not carry an explicit source-note or project ID and cannot by itself prove result association.
- Note already has projectId, inferredProjectName, content and annotation. Project is stable and user-created. Avoid a new queue or execution service.
- NoteEditorView inserts notes but does not currently present an explicit save failure. A result flow must use a throwing save and keep its draft on failure; merely calling insert/dismiss is insufficient.
- AgentHandoffBrief carries source IDs and requires a result report; current copied-packet/handoff-result.md is real input for the first return proof.

## First proposed slice: review and save

From the source note, open an Add agent result editor, paste the report and review it. Save a separate note in the same explicit project, retaining source UUID/title and a visible Agent-reported result label. Preserve the pasted report verbatim, including unresolved questions and verification limits. Saving must not complete tasks, replace the original transcript, publish artifacts, or trigger background execution. Reported checks remain claims unless independent evidence is attached.

Store association in existing metadata only if it remains reliably retrievable and does not confuse later project matching; otherwise a migration is a separate reviewed step. Do not encode an association only in a display title.

## Alternate slice: connector writes

Requires an explicit result-only schema, source/project ownership checks, duplicate retry handling, revocation proof, bounded payload, and phone readback. Existing memory-read OAuth proof is insufficient permission for broader writes. Keep reports distinct from orders, decisions and task-completion writes. This alternative is pending Shawn's product choice.

## Verification and first steps

1. Finalize reviewed-paste versus connector-write scope with Shawn; implement one path using existing model/ingest code.
2. Drive actual copied-packet/handoff-result.md through the real save path in a disposable app, then relaunch and read source/project association and exact report from SwiftData. Reject blank input; force a save error and retain draft; save must leave original note and task status untouched.
3. Fresh verifier checks real persisted result plus next handoff retrieval. Update standing UI proof and source receipts, then consider release scope separately.

## Local implementation checkpoint

Reviewed paste is implemented provisionally as the first local slice while Shawn's optional preference is unanswered. Source Note options opens Add agent result. AgentResultView creates a separate derived note, copies explicit projectId and inferredProjectName, and preserves the pasted report with a visible agent-reported disclaimer. Stable source metadata uses the existing annotation field; its exact two-line format round-trips through AgentResultDraft.sourceID. The result's title section can open its surviving visible source by UUID; deleted/missing source is labeled unavailable. No model schema changed.

Save uses a throwing ModelContext.save, removes only its attempted insert on failure, and retains the editor/report. No extraction, embedding, background execution, publishing or task-completion call is added.

The actual formatter compiled and preserved the3918character real Codex report from copied-packet/handoff-result.md, including its original browser-proof limitation. Blank/oversize inputs were rejected; exact source annotation round-tripped. Receipt result-formatter-check.json. This is formatter evidence only. SwiftUI/UITest source syntax parses; app type checking, native save/failure/relaunch, project readback and source navigation are not proven.

Standing native test ScreenshotTests.testFounderAgentResult uses a verbatim excerpt of that real report, checks blank save disabled, saves, relaunches without reseeding, and checks result/source link. It has not run. Disk is12.88GiB, below the15GiB heavy-build reserve; no build was started.

No connector write scope, schema migration, new service, main merge or release has been performed.
