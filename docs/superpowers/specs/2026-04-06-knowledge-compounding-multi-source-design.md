# Knowledge Compounding & Multi-Source Ingest — Design Spec

**Date:** 2026-04-06
**Status:** Draft
**Builds on:** Living Knowledge Base (2026-04-03)
**Inspired by:** Andrej Karpathy's LLM Knowledge Base pattern — specifically the compounding loop and multi-source ingest

## Overview

Two features that close the biggest gaps between EEON's knowledge base and the Karpathy pattern:

1. **Query-Compounds-Back Loop** — When a user saves a RAG answer from AssistantView, it feeds back into the knowledge base as a `.derived` note. The compiler treats it as additive reference material — it enriches articles but never overrides primary voice captures.

2. **Multi-Source Ingest** — iOS Share Extension lets users share URLs and text from any app into EEON. URLs get fetched for article content. A lightweight extraction pipeline (topics + people + summary only) processes web content. Optional "why I saved this" annotation provides user context.

**Core principle:** Voice captures are primary sources. Web articles and saved answers are reference material. The compiler weights them accordingly via prompt instruction.

## Architecture: Unified Pipeline

Both features extend the existing Note model with a `sourceType` field. All notes flow through the same IntelligenceService pipeline, with extraction and compilation behavior branching on sourceType. No new SwiftData models needed.

### Why Unified Pipeline

- Minimal new infrastructure — extends existing pipeline
- All notes searchable via same RAG/vector search
- Share extension reuses existing SwiftData + CloudKit sync
- KnowledgeCompiler checks sourceType to decide weight via prompt, not code branching

## Data Model

### Note Model Additions

```swift
// New enum
enum NoteSourceType: String, CaseIterable {
    case voice = "voice"          // Default — existing behavior
    case webArticle = "web"       // Shared via share sheet, URL fetched
    case derived = "derived"      // Saved RAG answer
}

// New fields on Note
var sourceTypeRaw: String = "voice"    // NoteSourceType.rawValue
var originalURL: String?               // For .webArticle — the shared URL
var annotation: String?                // "Why I saved this" from share sheet
var derivedFromQueryId: UUID?          // For .derived — links back to the question
```

Follows existing pattern — raw string stored, computed property for typed access. Default value `"voice"` means existing notes require no migration — they're implicitly voice notes.

## Feature 1: Query-Compounds-Back Loop

### AssistantView.saveAsNote() Changes

Currently saves a plain Note with `.idea` intent. Enhanced version sets sourceType:

```swift
let note = Note(title: userPrompt, content: message.content)
note.intent = .idea
note.sourceType = .derived
note.derivedFromQueryId = userMessage.id
```

No other changes to AssistantView. The save button stays where it is, UX is identical from the user's perspective.

### Extraction Branching in IntelligenceService.processNoteSave()

When `note.sourceType == .derived` or `.webArticle`:
- **Still run:** topic extraction, people extraction, embedding generation, enhanced note text
- **Skip:** action extraction, commitment extraction, unresolved item extraction
- **Still call:** `KnowledgeCompiler.markAffectedArticles()`

This is a single `if` check early in `processNoteSave()`, not a separate code path.

### KnowledgeCompiler Changes

**markAffectedArticles()** — works identically for all sourceTypes. Web articles and derived notes still create/dirty articles for their topics and people.

**recompileDirtyArticles()** — when building the noteTexts array for the compile prompt, each note gets a source prefix:
- Voice: `[Apr 3, 2:30 PM] the note text...` (unchanged)
- Web: `[WEB SOURCE: Apr 3] article text...`
- Derived: `[DERIVED: Apr 3] saved answer text...`

**Compile prompt addition** — one line added to the system prompt:

> "WEB SOURCE and DERIVED entries are reference material. They may inform connections and context but should not override summaries or timelines established by primary voice notes."

The LLM does the weighting via prompt instruction rather than code branching.

### Compounding Mechanics

When a user asks "what's the status of the pricing project?" and saves the answer:
1. Answer saved as Note with `sourceType: .derived`
2. `processNoteSave()` runs lighter extraction — pulls topics ("pricing") and people mentioned
3. Embedding generated for vector search
4. `markAffectedArticles()` dirties the "Pricing" project article
5. Next compile pass sends the derived note with `[DERIVED]` prefix
6. Compiler enriches the article's connections and context without overwriting the summary

The saved answer is now searchable via RAG and feeds the knowledge graph, but primary voice captures remain authoritative.

## Feature 2: Multi-Source Ingest

### Share Extension Target: EEONShareExtension

New iOS share extension target using the same App Group (`group.com.eeon.voicenotes`).

**ShareViewController** — compact SwiftUI view:
- Title extracted from shared content (auto-populated)
- Content preview (2-3 lines, truncated)
- Optional text field: "Why are you saving this?" (annotation)
- "Save to EEON" button, EEON accent color

No project picker, no tags, no other controls. Maximum speed.

### Handoff via App Group

The extension writes a pending ingest record to shared UserDefaults (`SharedDefaults`), same pattern as the existing widget communication:

```swift
struct PendingIngest: Codable {
    let url: String?
    let text: String?
    let annotation: String?
    let createdAt: Date
}
```

Extension writes to `SharedDefaults.pendingIngests: [PendingIngest]`, then exits.

### Main App Pickup

On next app launch/foreground, `IntelligenceService` checks for pending ingests before the normal refresh flow:

1. Read `SharedDefaults.pendingIngests`
2. For each pending ingest:
   - If URL present: fetch article content via `WebContentService`
   - Create Note with `sourceType: .webArticle`, `originalURL`, `annotation`, fetched content
   - Run lighter extraction pipeline (topics + people + summary + embedding)
   - Mark knowledge articles dirty
3. Clear processed ingests from SharedDefaults

### WebContentService (new)

Single-purpose service for extracting readable text from URLs:

- Fetch HTML via URLSession
- Extract article text: look for `<article>` or main content block, fall back to `<body>` text, strip tags
- Cap at 3000 words (bounds extraction + embedding costs)
- Store extracted text as note's `content`, original URL as `originalURL`

No third-party dependencies. Lightweight approach sufficient for v1.

**Error handling:** If fetch fails (404, timeout, paywall), create the note with just the URL and annotation. The URL is still valuable as a reference even without fetched content.

### Share Extension Constraints

- iOS gives extensions ~120MB memory and ~30s execution time
- Extension only writes to UserDefaults (a few KB) — well within limits
- All heavy processing (fetch, extraction, embedding) happens in the main app
- Extension uses the same App Group and shared container as the widget

## UI Changes

### Note Card Badges (AIHomeView)

Small icon overlay on note cards, bottom-trailing corner:
- `.voice` — no badge (default, unchanged)
- `.webArticle` — `link` SF Symbol
- `.derived` — `sparkles` SF Symbol

Subtle, does not change card layout or size.

### NoteDetailView Header

Source type shown as a small chip below the title:
- Web articles: "Web Source" chip + tappable original URL link
- Derived: "Saved from Assistant" chip
- Voice: nothing (default, no chip)

### Share Extension UI

Standard iOS share sheet modal height:
- Auto-populated title from shared content
- 2-3 line content preview (truncated)
- "Why are you saving this?" text field with placeholder
- "Save to EEON" button in EEON accent color
- Minimal, fast — mirrors the app's voice-first philosophy

## Cost & Performance

### Per-Operation Costs

| Operation | Tokens | Cost (gpt-4o-mini) |
|-----------|--------|-------------------|
| Saved RAG answer (extraction + embedding + compile) | ~3.1K | ~$0.001 |
| Web article (fetch + lighter extraction + embedding + compile) | ~2.9K | ~$0.001 |

### No New Background Work

- No new polling or background tasks
- URL fetch happens once on app foreground when a pending ingest exists
- Share extension writes to UserDefaults and exits immediately
- Everything triggers on existing foreground refresh cadence

### Memory Budget

Share extension: ~120MB limit, we use a few KB (UserDefaults write only).
Main app: URL fetch + HTML parsing adds negligible memory overhead.

## Integration Points

### Files Modified

| File | Change |
|------|--------|
| `Note.swift` | Add `sourceTypeRaw`, `originalURL`, `annotation`, `derivedFromQueryId` fields + `NoteSourceType` enum + computed accessors |
| `IntelligenceService.swift` | Add sourceType check to gate extraction depth, add pending ingest processing on foreground |
| `KnowledgeCompiler.swift` | Add source prefix to noteTexts in `recompileDirtyArticles()`, update compile prompt |
| `SummaryService.swift` | Add lighter extraction prompt variant for web/derived sources |
| `AssistantView.swift` | Set `sourceType: .derived` and `derivedFromQueryId` in `saveAsNote()` |
| `AIHomeView.swift` | Add source type badge overlay to note cards |
| `NoteDetailView.swift` | Add source type chip to header, tappable URL for web articles |
| `SharedDefaults.swift` | Add `pendingIngests` key and `PendingIngest` struct |
| `voice_notesApp.swift` | No schema change needed — Note is already registered, and new optional fields are handled by SwiftData lightweight migration automatically |

### New Files

| File | Purpose |
|------|---------|
| `WebContentService.swift` | URL fetch + HTML text extraction |
| `EEONShareExtension/ShareViewController.swift` | Share extension entry point |
| `EEONShareExtension/ShareView.swift` | SwiftUI share sheet UI |
| `EEONShareExtension/Info.plist` | Extension configuration |
| `EEONShareExtension/EEONShareExtension.entitlements` | App Group entitlement |

### Xcode Project Changes

- New target: `EEONShareExtension` (Share Extension)
- App Group entitlement on extension target: `group.com.eeon.voicenotes`
- Extension embedded in main app target

## Scope — What's NOT in This Spec

- Document/PDF import (text and URLs only for v1)
- Image ingestion
- Automatic save of all RAG answers (user must explicitly tap Save)
- Advanced readability engine for URL fetching (basic HTML extraction sufficient for v1)
- Pro-only gating (deferred — same as v1 knowledge base)
- Standalone knowledge browse screen (still deferred to v2)
- Share extension voice recording (would require full audio pipeline in extension)
