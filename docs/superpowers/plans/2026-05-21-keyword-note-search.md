# Keyword Note Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global keyword search to the `AIHomeView` note feed — a search field that instantly filters all notes by substring match across title and body text.

**Architecture:** A new pure helper `NoteKeywordSearch` does the matching and ranking with no UI or SwiftData dependency. `AIHomeView` (which already holds every `Note` in memory via `@Query`) gains a `searchQuery` state, a search field at the top of the feed, and a results grid that replaces the normal tabbed feed while a query is active. Entirely client-side — no new services, API calls, or embeddings.

**Tech Stack:** Swift, SwiftUI, SwiftData. Spec: `docs/superpowers/specs/2026-05-21-keyword-note-search-design.md`.

**Testing note:** This project has no unit-test target (UI tests only — see CLAUDE.md; standing one up is `TODOS.md` item #1). `NoteKeywordSearch` is a pure function and would be the ideal first unit test once that target exists, but this plan does not add the target. Each task is verified by `xcodebuild` build success plus manual in-app checks.

**Build command used throughout:**
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -6
```
Expected on success: `** BUILD SUCCEEDED **`

---

## Resolved: the spec's open implementation question

The spec flagged a choice between SwiftUI's `.searchable()` modifier and a manual `TextField`. **Decision: manual `TextField`.** `AIHomeView`'s feed is a section inside a custom `ScrollView`/`VStack` layout, not its own navigation screen; `.searchable()` expects a `NavigationStack` and would place the bar in nav chrome. A manual field placed at the top of the feed is controllable and fits the existing custom layout (tab bar, tag chips, intent chips are all hand-built here too).

---

## File Structure

| File | Change |
|------|--------|
| `voice notes/NoteKeywordSearch.swift` | **Create.** Pure, stateless matching + ranking. One public function. |
| `voice notes/AIHomeView.swift` | **Modify.** Add `searchQuery` state + search computeds; add `searchField` and `searchResultsSection` views; rename the existing `noteFeed` body to `browseFeed` and make `noteFeed` a thin router. |

The Xcode project uses file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so a new `.swift` file dropped in `voice notes/` is picked up automatically — no `.pbxproj` edit needed.

---

## Task 1: Create the `NoteKeywordSearch` pure helper

**Files:**
- Create: `voice notes/NoteKeywordSearch.swift`

- [ ] **Step 1: Create the file**

Create `voice notes/NoteKeywordSearch.swift` with exactly this content:

```swift
//
//  NoteKeywordSearch.swift
//  voice notes
//
//  Pure, stateless keyword search over notes. No UI, no SwiftData container
//  dependency — given a query and a list of notes, returns ranked matches.
//

import Foundation

enum NoteKeywordSearch {

    /// Returns the notes matching `query`, ranked.
    ///
    /// Matching: the query is split into whitespace-separated terms; a note
    /// matches when EVERY term appears (case- and diacritic-insensitive
    /// substring, via `localizedStandardContains`) somewhere in its combined
    /// searchable text — title + content + transcript + enhancedNoteText.
    ///
    /// An empty or whitespace-only query returns `[]` (search is inactive).
    ///
    /// Ranking: notes whose `title` contains any term sort first; ties break
    /// by `updatedAt` descending (most recently updated first).
    static func match(query: String, in notes: [Note]) -> [Note] {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        let matches = notes.filter { note in
            let haystack = searchableText(for: note)
            return terms.allSatisfy { haystack.localizedStandardContains($0) }
        }

        return matches.sorted { lhs, rhs in
            let lhsTitle = titleMatches(lhs, terms: terms)
            let rhsTitle = titleMatches(rhs, terms: terms)
            if lhsTitle != rhsTitle { return lhsTitle }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// The combined text a query is matched against for one note.
    private static func searchableText(for note: Note) -> String {
        [
            note.title,
            note.content,
            note.transcript ?? "",
            note.enhancedNoteText ?? ""
        ].joined(separator: " ")
    }

    /// True when any query term appears in the note's title.
    private static func titleMatches(_ note: Note, terms: [String]) -> Bool {
        terms.contains { note.title.localizedStandardContains($0) }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/NoteKeywordSearch.swift"
git commit -m "feat: add NoteKeywordSearch pure keyword-matching helper"
```

---

## Task 2: Wire keyword search into the AIHomeView feed

**Files:**
- Modify: `voice notes/AIHomeView.swift`

This task adds the search state, the search field, the results section, and converts `noteFeed` into a router that shows either search results or the existing browse feed. The existing feed content is **not rewritten** — it is renamed `browseFeed` (a one-line change) and the new `noteFeed` delegates to it.

- [ ] **Step 1: Add the `searchQuery` state property**

In `voice notes/AIHomeView.swift`, find this line (in the "Feed tabs & sorting" state block, ~line 105):

```swift
    @State private var selectedIntents: Set<NoteIntent> = []
```

Insert immediately after it:

```swift

    // Keyword search — global substring search across all notes
    @State private var searchQuery = ""
```

- [ ] **Step 2: Add the search computeds**

The `filteredNotes` computed property ends with this block (~line 156-161):

```swift
        if sortNewestFirst {
            return base // Already sorted newest first by @Query
        } else {
            return base.reversed()
        }
    }
```

Immediately after that closing `}` (and before the line `    /// Group notes by month for section headers`), insert:

```swift

    /// The query with surrounding whitespace removed. Empty when search is inactive.
    private var activeSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while the user has a non-empty search query entered.
    private var isSearching: Bool {
        !activeSearchQuery.isEmpty
    }

    /// Global keyword search results across every note (including archived),
    /// excluding only the Tune EEON seed notes — which are configuration, not
    /// memory, and must never appear in the feed or search (see `filteredNotes`).
    private var searchResults: [Note] {
        let visible = notes.filter {
            $0.sourceType != .profileSeed && $0.sourceType != .purposeSeed
        }
        return NoteKeywordSearch.match(query: activeSearchQuery, in: visible)
    }
```

- [ ] **Step 3: Rename the existing `noteFeed` to `browseFeed`**

Find this exact block (~line 826-829):

```swift
    private var noteFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar + sort button
            HStack(spacing: 0) {
```

Change only the property name on the first line:

```swift
    private var browseFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar + sort button
            HStack(spacing: 0) {
```

Nothing else in that property changes — the entire existing feed body is now `browseFeed`. Its call sites elsewhere in the file still say `noteFeed`; the new `noteFeed` added in Step 4 keeps them working.

- [ ] **Step 4: Add the router `noteFeed`, the `searchField`, and the `searchResultsSection`**

Immediately before the line `    private var browseFeed: some View {` (the line just renamed in Step 3), insert:

```swift
    // MARK: - Feed (search router)

    /// Feed entry point: the search field, then either search results or the
    /// normal tabbed browse feed depending on whether a query is active.
    private var noteFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal)
                .padding(.bottom, 8)

            if isSearching {
                searchResultsSection
            } else {
                browseFeed
            }
        }
    }

    /// Global keyword search input. Manual TextField (not `.searchable()`) so it
    /// fits AIHomeView's custom in-feed layout.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.eeonTextSecondary)

            TextField("Search notes", text: $searchQuery)
                .font(.subheadline)
                .foregroundStyle(.eeonTextPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.eeonTextSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.eeonCard)
        .cornerRadius(10)
    }

    /// Flat grid of keyword-search results, or an empty state. Replaces the
    /// tabbed browse feed while a query is active.
    @ViewBuilder
    private var searchResultsSection: some View {
        if searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.eeonTextTertiary)
                Text("No notes match \u{201C}\(activeSearchQuery)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(searchResults.count == 1 ? "1 result" : "\(searchResults.count) results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.eeonTextSecondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                let columns = [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(searchResults) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            NoteFeedCard(note: note)
                                .overlay(alignment: .topTrailing) {
                                    if note.isArchived {
                                        Text("Archived")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.eeonTextTertiary))
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

```

(The trailing blank line is intentional — it separates the new properties from `browseFeed`.)

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination "generic/platform=iOS" build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`

If the build fails with "cannot find `NoteFeedCard`" or "`eeonCard`/`eeonTextTertiary`" — these are pre-existing symbols used elsewhere in `AIHomeView.swift` (`NoteFeedCard` at the browse grid; the `.eeon*` colors throughout). A failure there means a typo in the inserted code; re-check against the blocks above. Do not redefine those symbols.

- [ ] **Step 6: Commit**

```bash
git add "voice notes/AIHomeView.swift"
git commit -m "feat: global keyword search field + results in the note feed"
```

- [ ] **Step 7: Manual verification**

Build and run on the iPhone (or simulator). On the home feed:
1. The search field appears at the top of the feed, above the tab bar.
2. Type a word you know is in a note's title — that note appears; title matches sort to the top.
3. Type a word that only appears in a note's body (content / transcript / enhanced text) — the note still appears.
4. Type two words — only notes containing **both** words anywhere appear.
5. Search is case-insensitive ("DENTIST" == "dentist").
6. A note you've archived still shows in results, with an "Archived" badge.
7. While searching, the tab bar / tag chips / intent chips are gone; the result count line shows ("3 results").
8. A query matching nothing shows the "No notes match …" empty state.
9. Tap the ✕ (or clear the field) — the feed returns to the exact tab you were on.
10. Tapping a result opens `NoteDetailView`.

---

## Self-Review

**Spec coverage:**
- Keyword substring search → Task 1 `NoteKeywordSearch.match`. ✓
- Match title + content + transcript + enhancedNoteText → `searchableText(for:)`. ✓
- Multi-word AND → `terms.allSatisfy`. ✓
- Case/diacritic-insensitive → `localizedStandardContains`. ✓
- Title-match ranks first, then `updatedAt` desc → `match`'s `sorted`. ✓
- Global scope incl. archived; excludes Tune EEON seeds → `searchResults` computed. ✓
- Search field at top of feed, manual TextField → Task 2 Step 4 `searchField`. ✓
- Feed swaps to flat results grid; tab/tag/intent chips hidden while searching → `noteFeed` router (`isSearching ? searchResultsSection : browseFeed`); the chips live inside `browseFeed` so they're inherently hidden. ✓
- Result count line → `searchResultsSection`. ✓
- Empty state → `searchResultsSection` `if searchResults.isEmpty`. ✓
- Archived badge on results → `.overlay` in `searchResultsSection`. ✓
- Clearing query restores prior tab → `selectedTab` is untouched by search; clearing `searchQuery` makes `isSearching` false and `browseFeed` renders with the unchanged `selectedTab`. ✓
- Client-side only, no API/network/embeddings → no service calls anywhere in the diff. ✓
- Edge cases (empty/whitespace query, no matches, nil transcript/enhanced text) → `guard !terms.isEmpty`, empty-state branch, `?? ""` in `searchableText`. ✓

**Placeholder scan:** No TBD/TODO; every step has complete code. ✓

**Type consistency:** `NoteKeywordSearch.match(query:in:)`, `searchQuery`, `activeSearchQuery`, `isSearching`, `searchResults`, `searchField`, `searchResultsSection`, `noteFeed`, `browseFeed` — names used identically across both tasks. `NoteFeedCard(note:)`, `NoteDetailView(note:)`, `Color.eeonCard`, `.eeonTextSecondary`, `.eeonTextTertiary`, `.eeonTextPrimary`, `Note.sourceType` / `.profileSeed` / `.purposeSeed`, `Note.isArchived` / `.updatedAt` / `.title` / `.content` / `.transcript` / `.enhancedNoteText` — all pre-existing symbols confirmed in `AIHomeView.swift` / `Note.swift`. ✓

**Decomposition:** 2 files, 1 new enum, 0 new services — minimal. `NoteKeywordSearch` is isolated and pure; `AIHomeView`'s existing 250-line feed body is preserved verbatim (renamed only), keeping the diff reviewable. ✓
