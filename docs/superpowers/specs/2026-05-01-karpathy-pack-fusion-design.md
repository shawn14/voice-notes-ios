# Karpathy-Pack Fusion — Design Spec

**Date:** 2026-05-01
**Status:** Approved
**Inspired by:** [Andrej Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

## Overview

EEON's `KnowledgeCompiler` is built on Karpathy's LLM Wiki pattern (raw sources → wiki pages → schema; ingest / query / lint operations). After auditing our implementation against the gist, two gaps stand out: there is no **LLM-compiled index article** synthesizing prose about the wiki's *shape*, and **note-level connections** are missing (connections render in article detail only). Both are cheap UX wins that make the existing wiki visibly compounding.

Once those gaps close, deepen EEON Tune via the **Personalization Pack** (Priorities → Feedback → Quiz persistence) — a user-facing surface for teaching the Karpathy LLM what matters.

**One-line pitch:** Make the wiki feel alive, then let users teach it what to prioritize.

## Steps

### Step 1 — Compiled Index Article

A singleton `KnowledgeArticle` of type `.index`. The LLM compiles a 3-5 sentence prose overview of the user's whole knowledge base ("12 people, 5 projects, 8 topics. Most active: hiring, fundraising. Drifting: product strategy."). Renders as a hero card at the top of `KnowledgeOverviewView`. Injected into RAG context for "what have I been working on"-style queries.

**Trigger:** after each Tier 2.5 compile pass when ≥3 articles have changed since last index compile, throttled to min 1h between compiles. Tier 3 forces a recompile if stale >24h.

### Step 2 — Note-level Connections Panel

In `NoteDetailView`, render a horizontal chip row of `KnowledgeArticle`s that this note touched (reverse-lookup via `linkedNoteIds`). Tap → navigate to article detail. Hide chrome when empty.

### Step 3 — Priorities Ledger (Personalization Pack hero)

New `.priorities` `KnowledgeArticleType`. User states ≤3 active priorities (label + optional why + optional deadline). Wired into:
- `ContextAssembler` (RAG injection)
- `SummaryService` extraction (tag actions/decisions with `priorityAlignedTo`)
- `ProactiveAlertService.detectDrift` (priority-aligned items get higher severity)
- `TodaysThreeSection` (suggested intentions auto-pulled)

Note model gets `priorityAlignmentJSON` (lightweight tag list).

### Step 4 — In-line 👍/👎 Feedback

New `FeedbackEvent` SwiftData model. Affordance on extraction chips, transform output, and alert cards. Negative feedback compiles into a `preferences` field on `.self` article. Future prompts inject preferences.

### Step 5 — Quiz-Answer Persistence

Persist `OnboardingQuizView`'s 6-screen answers into `.self` article fields (role, primary intent). `RewriteService` default template ordering and `SummaryService` extraction emphasis vary by role.

## Data Model Changes

- `KnowledgeArticleType`: add `.index`, `.priorities`
- `KnowledgeArticle`: optional `articleStatsJSON` (skipped if `summary` is enough)
- New `FeedbackEvent` SwiftData model: `id`, `targetType`, `targetId`, `signal`, `note?`, `createdAt`
- `Note`: add `priorityAlignmentJSON`
- `.self` article: add `preferences` field (compiled from feedback)

Adding new types requires schema seed re-run (`cloudKitSchemaSeedDidRun_v*` key bump per `CLAUDE.md`).

## Token Budget

Index compile: 1 LLM call per pass (max 1/hour). Input ≈ all article summaries (~3-8K tokens at typical scale). Output ≈ 200-400 tokens. Cost ≈ $0.001 per compile, $0.024/day worst-case (24 compiles, in practice closer to 5-10).

Personalization Pack injections: priorities (~150 tokens) + preferences (~200 tokens) + role (~50 tokens) ≈ 400 tokens added to extraction/RAG/rewrite calls. Acceptable overhead.

## Files Touched

| Step | New | Modified |
|---|---|---|
| 1 | — | `KnowledgeArticle.swift`, `KnowledgeCompiler.swift`, `SummaryService.swift`, `ContextAssembler.swift`, `KnowledgeOverviewView.swift`, `voice_notesApp.swift` |
| 2 | `NoteWikiConnectionsView.swift` | `NoteDetailView.swift` |
| 3 | `PrioritiesEditorView.swift` | `KnowledgeArticle.swift`, `IdentityView.swift`, `Note.swift`, `ContextAssembler.swift`, `SummaryService.swift`, `ProactiveAlertService.swift`, `TodaysThreeSection.swift` |
| 4 | `FeedbackEvent.swift`, `FeedbackService.swift` | `ExtractionChipsView.swift`, `RewriteService.swift` view layer, `ProactiveAlertService.swift`, `KnowledgeArticle.swift`, `SummaryService.swift` |
| 5 | — | `OnboardingQuizView.swift`, `RewriteService.swift`, `SummaryService.swift` |

## Verification

End-to-end manual testing (simulator + real device for CloudKit sync):

1. **Step 1 — Index**: With ≥3 articles, trigger compile → confirm `.index` article exists with non-empty summary; hero card renders; ask "what have I been working on" → confirm index referenced.
2. **Step 2 — Note connections**: Open a note that mentioned 2+ entities → confirm chips; tap chip → correct article opens; empty note → no chrome.
3. **Step 3 — Priorities**: Set 3 priorities → record a touching note → confirm `priorityAlignedTo` tag → confirm Today's 3 suggestions reflect priorities → confirm RAG answer leads with priority context.
4. **Step 4 — Feedback**: 👎 a transform → trigger `.self` recompile → confirm new transform respects the preference.
5. **Step 5 — Quiz**: Fresh install → complete quiz as Founder → confirm `.self` reflects role; rewrite picker default ordering reflects role.
6. **Schema seed**: All new types/fields registered through `voice_notesApp` schema; CloudKit Dashboard deploy.
7. **No regressions**: existing `.self` / `.purpose` compilation, RAG injection, Today's 3, Proactive Alerts, rewrite picker all work for users with no priorities / no feedback / no quiz answers.

## Out of scope

- Voice & Tone library (`.voice` article + writing-sample ingest)
- "Model of You" quarterly mirror
- Automated Query→file-back loop
- Externalized schema/config doc (Karpathy gap; partially addressed by user-facing Tune)
- Idea 2 features (Meeting Prep Cards, Sunday Digest, Promise Tracker)
- Idea 5 hard pieces (audio search, speaker diarization, on-this-day)
- Idea 1 (Watch, AirPods, long-meeting mode)

## Risks

- **Index compile cost creep** if throttle isn't enforced. Mitigation: hard 1-hour floor + ≥3-article-change gate.
- **Empty-state flicker** on fresh install. Mitigation: hide hero card until first compile completes.
- **Reverse-lookup perf** for Step 2. Mitigation: in-memory filter on `@Query` of all articles (acceptable at typical scale; revisit if >500 articles).
- **Token budget creep** as more `ContextAssembler` injections accrue. Mitigation: budget audit before Step 4 + per-injection char caps.
