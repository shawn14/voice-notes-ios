# Knowledge Index & Activity Log — Design Spec

**Date:** 2026-04-08
**Status:** Draft
**Builds on:** Living Knowledge Base (2026-04-03), Knowledge Compounding & Multi-Source Ingest (2026-04-06)
**Inspired by:** Karpathy's index.md + log.md pattern, AI Edge's Obsidian guide

## Overview

Two features that improve knowledge base visibility and RAG quality:

1. **Knowledge Overview (Index)** — Browsable screen showing all knowledge articles grouped by type, with stats and a "See All" entry point from AIHomeView. Also serves the RAG pipeline by injecting a lightweight article index into query context for better retrieval.

2. **Knowledge Activity Log** — A `KnowledgeEvent` model that records ingestion, compilation, and lint events. Surfaced to users as a "Recent Activity" feed showing how their knowledge base is growing.

**Core principle:** Same data serves two consumers — the RAG pipeline gets better article matching, users get the "your brain is growing" feeling.

## Data Model

### KnowledgeEvent (new SwiftData model)

```swift
@Model
final class KnowledgeEvent {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var eventTypeRaw: String = "ingest"    // ingest, compile, lint
    var title: String = ""                  // "Ingested FT article about Meta AI"
    var detail: String?                     // "Updated 3 articles: Sarah Chen, AI Strategy, Meta"
    var relatedArticleName: String?         // Primary article affected
    var sourceNoteId: UUID?                 // Note that triggered this event
}
```

**Event types:**
- `ingest` — new note/article entered the system (voice, web, derived)
- `compile` — article was recompiled with new data
- `lint` — lint sweep found issues

**Schema registration:** Add `KnowledgeEvent` to the schema array in `voice_notesApp.swift`.

**Auto-cleanup:** Delete events older than 30 days during the daily lint pass. ~200 bytes per event, ~10 events/day = negligible storage.

### Computed accessor pattern

```swift
enum KnowledgeEventType: String, CaseIterable {
    case ingest = "ingest"
    case compile = "compile"
    case lint = "lint"

    var icon: String {
        switch self {
        case .ingest: return "arrow.down.doc"
        case .compile: return "gearshape.2"
        case .lint: return "checkmark.shield"
        }
    }
}
```

## Event Logging Integration

Three places in `KnowledgeCompiler` append events:

### On ingest (markAffectedArticles)

After marking articles dirty, log one event per note:
- Title based on sourceType: "Recorded voice note" / "Ingested web article" / "Saved assistant answer"
- Detail: names of articles marked dirty (e.g., "Marked 3 articles: Sarah Chen, Pricing, Meta")
- `sourceNoteId` set to the note's ID

### On compile (recompileDirtyArticles)

After each successful article compile, log one event per article:
- Title: "Compiled {articleName}"
- Detail: "Incorporated {N} new notes"
- `relatedArticleName` set to the article name

### On lint (lintArticles)

After lint sweep completes, log one event if issues found:
- Title: "Knowledge health check"
- Detail: "Found {N} issues: {breakdown by type}"
- No event logged for clean sweeps (avoid noise)

## Knowledge Overview Screen

New `KnowledgeOverviewView` — browsable list of all knowledge articles.

### Entry Point

"See All" button on the existing knowledge cards horizontal scroll in `AIHomeView`. Pushes `KnowledgeOverviewView` onto the navigation stack.

### Layout

**Stats header:**
- Total article count
- "X articles updated today" (compiled within last 24h)
- "X notes ingested this week"

**Segmented picker:** All / People / Projects / Topics

**Article list:** Sorted by `lastMentionedAt` descending
- Each row: type icon, name, mention count badge, one-line summary (truncated), relative last-updated date
- Tapping pushes existing `KnowledgeArticleDetailView`

**Recent Activity section:** Last 5 `KnowledgeEvent` entries at the bottom
- Each row: event type icon, title, relative timestamp
- Tappable detail expansion (optional)

### Styling

Follows existing EEON design patterns — `Color.eeonCard` backgrounds, `.eeonTextPrimary`/`.eeonTextSecondary` typography, same card styling as note cards.

## RAG Pipeline Enhancement

### Current behavior

`RAGService.answerQuestion()` matches articles by name/alias against the query string. Misses articles where the topic is relevant but the name doesn't appear verbatim.

### Enhancement

Before the existing name-match block, build a lightweight index string from all articles and inject it into the RAG system prompt:

```
--- KNOWLEDGE INDEX ---
[Person] Sarah Chen — VP Engineering, leads platform team, 12 mentions
[Project] Pricing Strategy — exploring tiered model, 8 mentions
[Topic] AI Safety — regulatory concerns and team alignment, 5 mentions
```

This lets the LLM reference any article by context, not just by name match. Built dynamically from the same article query — no new data store.

**Token budget:** ~50 tokens per article. At 100 articles: ~5K extra tokens per query = ~$0.001 additional per question. Well within gpt-4o-mini budget.

## Cost & Performance

| Component | API Cost | Storage |
|-----------|----------|---------|
| KnowledgeEvent writes | $0 (local) | ~200 bytes/event, ~10/day |
| Knowledge Overview screen | $0 (local queries) | None |
| RAG index injection | ~$0.001/query extra | None |
| Event auto-cleanup | $0 (local delete) | Frees ~60KB/month |

**No new polling, no new background tasks.** Everything triggers off existing compile/lint lifecycle.

## Integration Points

### Files Modified

| File | Change |
|------|--------|
| `voice_notesApp.swift` | Add `KnowledgeEvent` to schema array |
| `KnowledgeCompiler.swift` | Append KnowledgeEvent after mark/compile/lint operations, auto-cleanup in lint |
| `RAGService.swift` | Build and inject knowledge index string into system prompt |
| `AIHomeView.swift` | Add "See All" button to knowledge cards section |

### New Files

| File | Purpose |
|------|---------|
| `KnowledgeEvent.swift` | SwiftData model + KnowledgeEventType enum |
| `KnowledgeOverviewView.swift` | Browse all articles + recent activity feed |

## Scope — What's NOT in This Spec

- Graph visualization (Obsidian-style) — list view is sufficient for v1
- Search within the overview — use RAG for that
- Event editing or deletion by user — append-only
- Notification badges for new events — keep it passive
- Export/share of knowledge overview
