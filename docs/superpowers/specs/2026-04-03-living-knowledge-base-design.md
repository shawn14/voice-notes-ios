# Living Knowledge Base — Design Spec

**Date:** 2026-04-03
**Status:** Approved
**Inspired by:** Andrej Karpathy's LLM Knowledge Base pattern

## Overview

EEON captures per-note intelligence (people, topics, decisions, actions) but has no cross-note compiled knowledge layer. Notes are islands. This feature adds a **KnowledgeArticle** system — living profiles for people, projects, and topics that the LLM compiles and maintains automatically from your voice notes. Every note you capture makes every article richer.

**Core insight:** "You never write the wiki. The LLM writes everything. You just steer — every answer compounds."

**One-line pitch:** Today EEON remembers what you said. With this, EEON understands what you know.

## Architecture

### Intelligence Tier Integration

The knowledge compiler slots into the existing tiered intelligence system:

| Tier | Trigger | What happens | API calls |
|------|---------|-------------|-----------|
| 1 (Instant) | Note save | Existing extraction + mark affected articles dirty | 0 (local) |
| 2 (Session) | App foreground | Existing session brief | 0 (local) |
| **2.5 (Compile)** | App foreground, after Tier 2 | Recompile dirty KnowledgeArticles | 3-5 per pass |
| 3 (Daily) | Once per day | Existing daily brief + lint/heal sweep | 1 additional |

### Token Budget

| Component | Tokens/day | Cost/day (gpt-4o-mini) |
|-----------|-----------|----------------------|
| Compile (3 foreground events, ~4 articles each) | ~28K | ~$0.006 |
| Lint/heal | ~3.5K | ~$0.001 |
| **Total** | **~31.5K** | **~$0.007** |

Monthly cost per active user: ~$0.21. Adds ~5-10% on top of existing extraction pipeline costs.

Initial backfill for a user with 500 existing notes: ~$0.15-0.30 one-time, spread across several app opens.

## Data Model

### KnowledgeArticle (new SwiftData model)

```swift
@Model
final class KnowledgeArticle {
    var id: UUID
    var name: String                    // "Sarah Chen", "Pricing Strategy", "Hiring"
    var articleType: String             // "person", "project", "topic"
    var createdAt: Date
    var updatedAt: Date
    var lastCompiledAt: Date?           // When LLM last rewrote this article
    var isDirty: Bool                   // Needs recompile on next Tier 2.5 pass
    var mentionCount: Int               // How many notes reference this article
    var lastMentionedAt: Date?

    // Core content (LLM-compiled)
    var summary: String                 // 2-3 sentence overview
    var openThreadsJSON: String?        // [{thread, status, daysOpen}]
    var timelineJSON: String?           // [{date, event}] — key moments
    var connectionsJSON: String?        // [{articleId, articleName, reason}]
    var sentimentArc: String?           // "Optimistic -> Cautious -> Coming around"

    // Type-specific fields (JSON, nullable)
    var decisionsJSON: String?          // For projects: [{decision, status, date}]
    var relationshipContext: String?     // For people: role, how you know them
    var thinkingEvolution: String?      // For topics: how your view has changed

    // Source tracking
    var linkedNoteIdsJSON: String?      // [UUID] — all notes that feed this article
    var lastCompiledNoteDate: Date?     // Newest note included in last compile
}
```

**Design choices:**
- `isDirty` flag — Tier 1 sets true, Tier 2.5 picks up dirty articles for recompile
- `lastCompiledNoteDate` — compile prompt only sends notes newer than this, not full history
- JSON fields follow existing codebase pattern (`topicsJSON`, `mentionedPeopleJSON` on Note)
- `connectionsJSON` — links between articles (Sarah <-> Pricing Strategy)
- Type-specific fields are nullable — `decisionsJSON` only populated for projects, `relationshipContext` only for people

**Schema registration:** Add `KnowledgeArticle` to the schema array in `voice_notesApp.swift`.

## KnowledgeCompiler Service

New `@Observable` singleton following the existing service pattern.

```swift
@Observable
final class KnowledgeCompiler {
    static let shared = KnowledgeCompiler()

    var isCompiling = false
    var lastCompileAt: Date?
}
```

### Tier 1: markAffectedArticles (on note save, local only)

Called from `IntelligenceService.processNoteSave()` after existing extraction completes.

1. Read extracted data from note: `mentionedPeopleJSON`, `topicsJSON`, `inferredProjectName`
2. For each extracted person name: find or create a `KnowledgeArticle` with `articleType: "person"`
3. For each extracted topic: find or create with `articleType: "topic"`
4. For inferred project: find or create with `articleType: "project"`
5. On each matched article: set `isDirty = true`, increment `mentionCount`, update `lastMentionedAt`, append note ID to `linkedNoteIdsJSON`

**Entity resolution (finding vs creating):**
- Exact match on `name` (case-insensitive) first
- Fuzzy match using alias list stored on the article (same pattern as `ProjectMatcher`)
- If no match, create new article. Duplicate detection/merge happens during lint/heal.

### Tier 2.5: recompileDirtyArticles (on app foreground, API calls)

Called from `IntelligenceService` foreground refresh, after session brief, with a 15-minute cooldown.

1. Fetch all `KnowledgeArticle` where `isDirty == true`, sorted by `lastMentionedAt` descending
2. Take the first 5 (cap per foreground pass)
3. For each article:
   - Fetch notes from `linkedNoteIdsJSON` where `createdAt > lastCompiledNoteDate`
   - Call `SummaryService.compileArticle()` with existing article content + new notes
   - Parse structured JSON response back into article fields
   - Set `isDirty = false`, update `lastCompiledAt` and `lastCompiledNoteDate`

**Compile prompt structure:**
- System: "You maintain a living knowledge article about {type}. Update it with new information."
- Input: existing article JSON + new note transcripts
- Output: structured JSON matching article field schema
- Model: `gpt-4o-mini`

**Cost controls:**
- Max 5 recompiles per foreground event
- Only sends new notes since last compile, not full history
- 15-minute cooldown between compile passes
- Uses `gpt-4o-mini`
- `linkedNoteIdsJSON` stores all note IDs for source tracking, but the compile prompt only fetches notes newer than `lastCompiledNoteDate` — so prompt size stays constant regardless of article age

### Tier 3: lintArticles (daily, one API call)

Called after `DailyBrief` generation in the existing Tier 3 flow.

**Input:** All article summaries (~50 tokens each) + open threads older than 5 days + articles not mentioned in 14+ days with open threads.

**Output:** Array of `KnowledgeLintResult`:

```swift
struct KnowledgeLintResult: Codable, Identifiable {
    var id: String { content }
    let lintType: String        // "stale_thread", "contradiction", "connection", "gap"
    let content: String         // Human-readable description
    let severity: String        // "info", "warning", "urgent"
    let relatedArticleIds: [UUID]
}
```

**Four lint types:**

| Type | What it catches | Example |
|------|----------------|---------|
| `stale_thread` | Open threads with no activity | "You committed to Sarah's security review 8 days ago — no follow-up" |
| `contradiction` | Conflicting statements across articles | "Pricing article says 'no LTD' but you explored AppSumo last week" |
| `connection` | Unlinked articles that should be related | "Sarah and Dave both mentioned compliance — might be related" |
| `gap` | Missing information the system notices | "Project Alpha has 12 notes but no defined goal or deadline" |

Results stored on `DailyBrief` as new `lintResultsData: Data` field with JSON accessor.

## UI

### AIHomeView — Knowledge Cards Section

Horizontal scroll of article cards below recent notes. Sorted by `lastMentionedAt` descending.

Each card shows:
- Type icon (person/project/topic)
- Name
- Mention count badge
- One-line summary (truncated)
- Updated indicator dot if compiled within last 24h

Tapping opens `KnowledgeArticleDetailView`.

### KnowledgeArticleDetailView (new screen)

Pushed from card tap. Sections:
- **Header**: name, type badge, mention count, last updated
- **Summary**: 2-3 sentence compiled overview
- **Open Threads**: list with status indicators (same style as extraction chips)
- **Timeline**: key moments in reverse chronological order
- **Connections**: tappable links to related articles
- **Sentiment Arc / Thinking Evolution**: single line showing progression
- **Decisions** (project type only): resolved vs open
- **Source Notes**: collapsible list of linked notes, tappable to NoteDetailView

### DailyBriefSheet — Knowledge Health Section

New section below existing warnings. Renders `[KnowledgeLintResult]` with colored left border by severity, icon, description, tappable to related article.

### RAG Integration

When user asks a question via the assistant:
1. Before vector search, query `KnowledgeArticle` by name/summary match against the question
2. Inject matching article summaries as high-priority context in the RAG synthesis prompt
3. Results: better answers from compiled knowledge, fewer tokens needed from raw note snippets

## Monetization

**Pro-only feature.** Knowledge articles are the premium differentiator.

- Free users: notes + basic extraction (existing behavior)
- Pro users: compiled knowledge articles, lint/heal, article-enhanced RAG answers
- Gate check: `SubscriptionManager.shared.isPro` before running Tier 2.5 compile and before showing knowledge cards section

## Integration Points

### Files modified:

| File | Change |
|------|--------|
| `voice_notesApp.swift` | Add `KnowledgeArticle` to SwiftData schema array |
| `IntelligenceService.swift` | Call `KnowledgeCompiler.markAffectedArticles()` in Tier 1, `recompileDirtyArticles()` in Tier 2.5, `lintArticles()` in Tier 3 |
| `SummaryService.swift` | Add `compileArticle()` and `lintArticles()` static methods |
| `RAGService.swift` | Add article context injection before vector search (~10-15 lines) |
| `AIHomeView.swift` | Add horizontal scroll knowledge cards section |
| `DailyBrief.swift` | Add `lintResultsData: Data` field + JSON accessor |
| `DailyBriefSheet.swift` | Add "Knowledge Health" section |

### New files:

| File | Purpose |
|------|---------|
| `KnowledgeArticle.swift` | SwiftData model |
| `KnowledgeCompiler.swift` | Compile + lint service (Observable singleton) |
| `KnowledgeArticleDetailView.swift` | Article detail screen |
| `KnowledgeCardView.swift` | Card component for AIHomeView horizontal scroll |

### Files NOT touched:

`Note.swift`, `TranscriptionService.swift`, `AudioRecorder.swift`, `SubscriptionManager.swift`, `UsageService.swift`, `EmbeddingService.swift`, `VectorSearchService.swift`

## Scope — What's NOT in v1

- Query-compounds-back loop (answers filed back into articles) — v2
- Standalone "Knowledge" tab or browse-all screen — v2
- Manual article editing — the LLM writes everything
- Full-text search across articles — use RAG
- Article merge UI (duplicate resolution handled by lint/heal suggestions)
- Initial backfill optimization (basic sequential backfill is fine for v1)
