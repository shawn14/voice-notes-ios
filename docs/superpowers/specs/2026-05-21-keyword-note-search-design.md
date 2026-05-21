# Keyword Note Search — Design

**Date:** 2026-05-21
**Status:** Design — pending implementation plan

## Problem

EEON has no user-facing way to find a specific note. It has a powerful
semantic Q&A system ("Ask EEON" → `RAGService` → synthesized answer) and a
`VectorSearchService`, but those answer *questions* — they do not let a user
*locate a note* and open it. The live `AIHomeView` feed offers tab filters
(All / AI / Favorites / Archive), tag chips, and intent chips, but no search.
A `.searchable()` keyword search exists in `NotesListView`, but that view is
legacy and unreachable from the shipping navigation.

Result: to find one note about "the dentist" among 200, a user must either
Ask EEON (a synthesized answer, an API call, and not a browsable list) or
scroll/tag-filter. There is a real gap: plain "find my note" search.

## Goal & User Flow

1. User is on the `AIHomeView` feed.
2. A search field sits at the top of the feed.
3. User types a query; the feed immediately swaps to a flat grid of every
   note matching the query, across *all* notes.
4. User taps a result → `NoteDetailView`, as from any feed card.
5. User clears the query → the feed returns to the exact tab/tag view they
   were on before searching.

## Key Decisions

Settled during brainstorming; not open for re-litigation in the plan:

- **Keyword search, not semantic.** Plain substring matching — fast, free,
  offline. The semantic path (`RAGService`) already exists for questions and
  is out of scope here.
- **Match fields:** `title`, `content`, `transcript`, and
  `enhancedNoteText`. The enhanced text is the body the user actually reads,
  so it must be searched — the legacy `NotesListView` search omitted it,
  which this design deliberately fixes.
- **Global scope.** A query searches every note regardless of the current
  tab/tag filter, **including archived notes**, so a note is never
  unfindable. Results replace the feed while a query is active.
- **Multi-word = AND.** All query terms must be present (anywhere in the
  searchable text), not an exact-phrase match.
- **Client-side only.** No new fetch, no API call, no network, no
  embeddings.

## Architecture

```
 AIHomeView (@Query loads all notes, already in memory)
   │
   │  @State searchQuery: String
   │
   ├─ searchQuery empty ──────▶ existing tabbed / month-grouped feed (unchanged)
   │
   └─ searchQuery non-empty ──▶ NoteKeywordSearch.match(query:, in: allNotes)
                                  │
                                  ▼
                                flat results grid (reuses existing note cards)
                                + result count + empty state
```

### Components

| Component | Responsibility | Depends on |
|-----------|----------------|------------|
| `NoteKeywordSearch` (new) | Pure, stateless matching + ranking. One function: `(query, [Note]) -> [Note]`. | `Note` only |
| `AIHomeView` (modify) | Search field UI; swap feed ↔ results; `@State` for the query | `NoteKeywordSearch` |

`NoteKeywordSearch` is a plain enum/struct with a static function — no
singleton, no observable state. It is independently testable: given notes
and a query, it returns the matches. This isolation is deliberate so the
matching/ranking logic can be unit-tested without any UI or SwiftData
container.

### Matching algorithm (`NoteKeywordSearch`)

```
match(query, notes):
  terms = query.lowercased().split(on: whitespace), drop empties
  if terms is empty: return []          // empty/whitespace query = no search
  for each note:
    haystack = (title + " " + content + " " + (transcript ?? "")
                + " " + (enhancedNoteText ?? "")).lowercased()
    note matches  ⇔  every term is a substring of haystack
  rank matches:
    1. notes whose `title` (lowercased) contains ANY term  → first
    2. then by `updatedAt` descending
  return ranked matches
```

Case- and diacritic-insensitive. No fuzzy/typo tolerance (out of scope).

### Data Flow

`AIHomeView` already holds every `Note` in memory via `@Query`. The feature
adds one `@State private var searchQuery = ""` and a computed
`searchResults` that calls `NoteKeywordSearch.match`. When `searchQuery` is
non-empty the view renders `searchResults`; otherwise it renders the
existing feed untouched. No persistence, no service, no async.

## UI Detail

- **Search field:** persistent, at the top of the feed above the tab bar —
  magnifying-glass icon, placeholder ("Search notes"), clear ("✕") button.
- **Active-search state:** tab bar, tag chips, and intent chips are hidden
  (they don't apply — search is global). The feed area shows a flat grid of
  result cards (the existing note-card component), not month-grouped.
- **Result count:** a line such as "12 results" above the grid.
- **Empty state:** "No notes match '<query>'".
- **Archived results:** shown with a small "Archived" badge, since a result
  pulled from the archive would otherwise be confusing.
- **Clearing the query** restores the prior tab/tag selection exactly.

**Open implementation detail (for the plan):** whether to use SwiftUI's
native `.searchable()` modifier or a manual `TextField`. `.searchable()` is
idiomatic but expects a `NavigationStack` and can fight `AIHomeView`'s
custom ZStack/ScrollView layout; a manual `TextField` is more controllable.
The plan must inspect `AIHomeView`'s view structure and choose. This does
not change the design — only the field's implementation.

## Edge Cases

- Empty or whitespace-only query → not an active search; normal feed shown.
- Query with no matches → empty state, no crash.
- Very long query → terms still split normally; harmless.
- A note with `nil` `transcript`/`enhancedNoteText` → those contribute empty
  string to the haystack; matching still works on the other fields.
- Archived notes → included in results (by decision), badged.

## Testing

The project currently has no unit-test target (UI tests only). Because
`NoteKeywordSearch` is a pure function with no UI or SwiftData dependency,
it is the ideal first unit test if a test target is stood up (see the
existing `TODOS.md` item for an XCTest target). At minimum, verify
manually in-app:

- Single-word match across title, content, transcript, and enhanced text.
- Multi-word AND (a note with both words anywhere matches; a note with only
  one does not).
- Case-insensitivity.
- An archived note appears in results, badged.
- Title-match ranks above body-only match.
- Clearing the query restores the prior tab.
- No-match query shows the empty state.

## Out of Scope (YAGNI)

- Match-term highlighting in results.
- Search history / recent searches.
- Fuzzy / typo-tolerant matching.
- Surfacing semantic (`VectorSearchService`) results as a note list — the
  semantic path stays question-answering only.
- Filtering search results by tab/tag/intent — search is global by design.
- Pagination — in-memory filtering is adequate at the realistic note count.
