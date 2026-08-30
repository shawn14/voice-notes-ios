# Notes Reorganization Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make four hidden AI-extraction dimensions tappable as primary navigation surfaces on the EEON home screen — intent type, unresolved questions, emotional tone, and decisions — without inventing new schema or new AI calls.

**Architecture:** Each of the four features uses metadata that `IntelligenceService` already extracts onto `Note`, `UnresolvedItem`, and `ExtractedDecision`. The pack is additive: a chip row above the feed, a section card below Today, a view-mode toggle in the feed, and a sheet for the decision log. No model changes except one additive optional field on `UnresolvedItem` (`resolvedAt: Date?`). All four features ship behind the existing `AIHomeView` entry point — no new screens in the navigation graph.

**Tech Stack:** SwiftUI + SwiftData (CloudKit sync), iOS 26.2 deployment target, Xcode 16+. Project uses file-system-synchronized groups so new `.swift` files are auto-discovered by the build.

**Testing approach:** Per CLAUDE.md, this codebase has UI tests only — no unit test target. Pure helpers in this plan are verified via Xcode `#Preview` blocks plus a sanity-check `assert()` at file-load time in DEBUG builds. View behavior is verified by running the app on a physical iPhone (CloudKit needs real iCloud account to attach properly — see `memory/project_cloudkit_setup.md`).

---

## File structure

**New files:**
- `voice notes/IntentFilterChips.swift` — chip row component, multi-select state owned by parent
- `voice notes/LooseEndsLane.swift` — section card listing unresolved questions
- `voice notes/MoodTimelineHelpers.swift` — pure functions: `moodColor(for:)`, `moodSparkline(notes:)`
- `voice notes/DecisionLogView.swift` — sheet with weekly grouping
- `voice notes/NotesReorgHelpers.swift` — pure functions used across the pack: intent counts, intent filter, week bucketing

**Modified files:**
- `voice notes/AIHomeView.swift` — add intent chip row, Loose Ends section, view-mode toggle, Decision Log sheet trigger
- `voice notes/ExtractedItem.swift` — add `resolvedAt: Date?` to `UnresolvedItem`
- `voice notes.xcodeproj/project.pbxproj` — bump `CURRENT_PROJECT_VERSION` 98 → 99

**Schema implications:** Adding an optional `Date?` field to an `@Model` is a non-breaking SwiftData migration; CloudKit will treat it as a new optional field on `CD_UnresolvedItem`. Since `CD_UnresolvedItem` is already deployed in Production (verified during the CloudKit debug session), no Dashboard action is required — the new field auto-registers on first push and CloudKit accepts unknown optional fields.

---

## Task 1: Pure helpers for intent counts and filtering

**Files:**
- Create: `voice notes/NotesReorgHelpers.swift`

- [ ] **Step 1: Create the helpers file**

```swift
//
//  NotesReorgHelpers.swift
//  voice notes
//
//  Pure helpers shared by the notes-reorganization pack
//  (intent chips, loose ends, mood timeline, decision log).
//

import Foundation
import SwiftUI

enum NotesReorgHelpers {
    /// All intent types the user can filter by, excluding `.unknown`
    /// (used for chips that count classified notes).
    static let filterableIntents: [NoteIntent] = [
        .action, .decision, .idea, .update, .reminder
    ]

    /// Counts how many notes have each intent. Skips `.unknown`.
    static func intentCounts(notes: [Note]) -> [NoteIntent: Int] {
        var counts: [NoteIntent: Int] = [:]
        for intent in filterableIntents { counts[intent] = 0 }
        for note in notes {
            let intent = note.intent
            if filterableIntents.contains(intent) {
                counts[intent, default: 0] += 1
            }
        }
        return counts
    }

    /// Filters notes to those whose intent is in the selected set.
    /// If selected is empty, returns all notes (no filter).
    static func filterByIntents(notes: [Note], selected: Set<NoteIntent>) -> [Note] {
        guard !selected.isEmpty else { return notes }
        return notes.filter { selected.contains($0.intent) }
    }

    /// Returns the start-of-week date for a given date (Monday-based ISO weeks).
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Groups any items by week-of-year, returning [(weekStart, items)] sorted descending.
    static func groupByWeek<T>(items: [T], dateKey: (T) -> Date) -> [(Date, [T])] {
        let grouped = Dictionary(grouping: items, by: { weekStart(for: dateKey($0)) })
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }
}

#if DEBUG
// Sanity checks — run at module load in Debug to catch regressions.
@MainActor private let _notesReorgHelpersChecks: Void = {
    // intentCounts on empty input returns zero for every filterable intent.
    let empty = NotesReorgHelpers.intentCounts(notes: [])
    assert(empty.count == NotesReorgHelpers.filterableIntents.count)
    for intent in NotesReorgHelpers.filterableIntents {
        assert(empty[intent] == 0, "Empty notes should yield 0 count for \(intent)")
    }

    // filterByIntents with empty selection is a passthrough.
    let n = Note(title: "x", content: "y")
    let pass = NotesReorgHelpers.filterByIntents(notes: [n], selected: [])
    assert(pass.count == 1, "Empty selection should not filter")

    // weekStart is monotonic — same week input → same output.
    let d1 = Date()
    let d2 = d1.addingTimeInterval(60)
    assert(NotesReorgHelpers.weekStart(for: d1) == NotesReorgHelpers.weekStart(for: d2),
           "Two timestamps in the same minute should share a week start")
}()
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run from `/Users/shawncarpenter/projects/voice notes`:
```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/NotesReorgHelpers.swift"
git commit -m "feat: pure helpers for notes-reorganization pack"
```

---

## Task 2: Intent filter chip row

**Files:**
- Create: `voice notes/IntentFilterChips.swift`
- Modify: `voice notes/AIHomeView.swift` (add `@State`, render the row)

- [ ] **Step 1: Create the chip row component**

```swift
//
//  IntentFilterChips.swift
//  voice notes
//

import SwiftUI

struct IntentFilterChips: View {
    let counts: [NoteIntent: Int]
    @Binding var selected: Set<NoteIntent>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotesReorgHelpers.filterableIntents, id: \.self) { intent in
                    let count = counts[intent] ?? 0
                    if count > 0 {
                        chip(intent: intent, count: count)
                    }
                }
                if !selected.isEmpty {
                    Button {
                        selected.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(intent: NoteIntent, count: Int) -> some View {
        let isOn = selected.contains(intent)
        return Button {
            if isOn { selected.remove(intent) } else { selected.insert(intent) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: intent.icon)
                    .font(.caption2)
                Text(intent.rawValue)
                Text("(\(count))")
                    .font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? Color.eeonAccent : Color.eeonCard)
            .foregroundStyle(isOn ? .white : .eeonTextSecondary)
            .cornerRadius(16)
        }
    }
}

#Preview {
    @Previewable @State var selected: Set<NoteIntent> = [.action]
    return VStack {
        IntentFilterChips(
            counts: [.action: 12, .decision: 4, .idea: 7, .update: 2, .reminder: 1],
            selected: $selected
        )
        Text("Selected: \(selected.map(\.rawValue).joined(separator: \", \"))")
    }
    .padding()
}
```

- [ ] **Step 2: Verify the preview renders**

Open `IntentFilterChips.swift` in Xcode. Click the canvas/preview pane (⌥⌘↩ if hidden). Confirm:
- 5 chips visible (Action, Decision, Idea, Update, Reminder) with counts
- "Action" chip is highlighted (matches initial state)
- Tapping toggles selection
- "Clear" button appears when at least one is selected

- [ ] **Step 3: Add state to AIHomeView**

In `voice notes/AIHomeView.swift`, find the existing `@State` declarations near the top (around line 45). Add:

```swift
@State private var selectedIntents: Set<NoteIntent> = []
```

- [ ] **Step 4: Apply intent filter in `filteredNotes`**

In `voice notes/AIHomeView.swift`, locate the `filteredNotes` computed property (around line 117). Find the line that applies the tag filter:

```swift
        // Apply tag filter if selected
        if let tag = selectedTagFilter {
            base = base.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        }
```

Immediately after that block (before the `if sortNewestFirst` block), add:

```swift
        // Apply intent filter if any selected
        base = NotesReorgHelpers.filterByIntents(notes: base, selected: selectedIntents)
```

- [ ] **Step 5: Render the chip row above the feed**

In `voice notes/AIHomeView.swift`, locate the existing tag chip strip (around line 818, the `if selectedTab != .ai && !tags.isEmpty {` block). Immediately AFTER the tag strip's closing brace and `.padding(.bottom, 4)`, insert the intent chips:

```swift
            // Intent filter chips (hidden on AI tab)
            if selectedTab != .ai {
                IntentFilterChips(
                    counts: NotesReorgHelpers.intentCounts(notes: filteredNotes),
                    selected: $selectedIntents
                )
                .padding(.bottom, 4)
            }
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

Run on physical iPhone via Xcode. Open the All tab. Confirm:
- A chip row appears below the existing tag strip
- Each chip shows a count > 0
- Tapping a chip filters the feed
- Selecting multiple chips ORs them (notes matching ANY selected intent appear)
- "Clear" button removes the filter

- [ ] **Step 7: Commit + bump build to 101**

```bash
git add "voice notes/IntentFilterChips.swift" "voice notes/AIHomeView.swift"
git commit -m "feat: intent filter chips above notes feed"
sed -i '' 's/CURRENT_PROJECT_VERSION = 100/CURRENT_PROJECT_VERSION = 101/g' "voice notes.xcodeproj/project.pbxproj"
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to build 101 for intent filter chips"
```

---

## Task 3: Loose Ends lane

**Files:**
- Modify: `voice notes/ExtractedItem.swift` (add `resolvedAt: Date?` to `UnresolvedItem`)
- Create: `voice notes/LooseEndsLane.swift`
- Modify: `voice notes/AIHomeView.swift` (render the lane)

- [ ] **Step 1: Add `resolvedAt` to UnresolvedItem**

In `voice notes/ExtractedItem.swift`, find the `UnresolvedItem` `@Model` class (around line 154). It currently looks like:

```swift
@Model
final class UnresolvedItem {
    var id: UUID = UUID()
    var content: String = ""
    var reason: String = ""  // "No decision", "No owner", "Ambiguous"
    var createdAt: Date = Date()
    var sourceNoteId: UUID?

    init(content: String, reason: String, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.reason = reason
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
    }
}
```

Replace with:

```swift
@Model
final class UnresolvedItem {
    var id: UUID = UUID()
    var content: String = ""
    var reason: String = ""  // "No decision", "No owner", "Ambiguous"
    var createdAt: Date = Date()
    var sourceNoteId: UUID?
    /// Set when the user marks the question answered. nil = still open.
    var resolvedAt: Date?

    init(content: String, reason: String, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.content = content
        self.reason = reason
        self.createdAt = Date()
        self.sourceNoteId = sourceNoteId
        self.resolvedAt = nil
    }

    var isOpen: Bool { resolvedAt == nil }
}
```

- [ ] **Step 2: Build to verify schema migration is non-breaking**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`. SwiftData's lightweight migration handles adding optional fields automatically — no schema version bump needed.

- [ ] **Step 3: Create the lane component**

```swift
//
//  LooseEndsLane.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct LooseEndsLane: View {
    @Environment(\.modelContext) private var modelContext
    let openItems: [UnresolvedItem]
    var onTapItem: (UnresolvedItem) -> Void

    var body: some View {
        if openItems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Loose Ends")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(openItems.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.eeonTextTertiary)
                }
                .padding(.horizontal, 16)

                ForEach(openItems.prefix(5)) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.content)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.eeonTextTertiary)
                        }
                        Spacer()
                        Button {
                            item.resolvedAt = Date()
                            try? modelContext.save()
                        } label: {
                            Text("Resolve")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.eeonAccent.opacity(0.15))
                                .foregroundStyle(Color.eeonAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(12)
                    .background(Color.eeonCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapItem(item) }
                }

                if openItems.count > 5 {
                    Text("+\(openItems.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.eeonTextTertiary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }
}
```

- [ ] **Step 4: Render the lane in AIHomeView**

In `voice notes/AIHomeView.swift`, find where notes content begins after the chip rows (search for `ScrollView` near the feed grid, or find the line right above where `notesByMonth` is rendered — probably around line 920).

Just BEFORE the `ScrollView` containing the notes grid, add:

```swift
                // Loose Ends — surfaces unresolved questions extracted from voice notes.
                // Hidden on AI/Favorites/Archive tabs to keep them focused.
                if selectedTab == .all {
                    LooseEndsLane(
                        openItems: unresolvedItems.filter { $0.isOpen }
                            .sorted { $0.createdAt > $1.createdAt }
                    ) { item in
                        // Tap: open source note if available
                        if let id = item.sourceNoteId,
                           let note = notes.first(where: { $0.id == id }) {
                            navigateToNote = note
                        }
                    }
                }
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

Run on physical iPhone. Open the All tab. Verify:
- If you have any unresolved items extracted by the AI, a "Loose Ends" section appears above the notes feed
- Each row shows the question, the reason, and a "Resolve" button
- Tapping "Resolve" makes the row disappear (it's now resolved, no longer included in the lane)
- Tapping the row opens the source note
- Lane is hidden when there are no unresolved items
- Lane is hidden on AI / Favorites / Archive tabs

- [ ] **Step 6: Commit + bump build to 102**

```bash
git add "voice notes/ExtractedItem.swift" "voice notes/LooseEndsLane.swift" "voice notes/AIHomeView.swift"
git commit -m "feat: Loose Ends lane surfaces unresolved questions"
sed -i '' 's/CURRENT_PROJECT_VERSION = 101/CURRENT_PROJECT_VERSION = 102/g' "voice notes.xcodeproj/project.pbxproj"
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to build 102 for Loose Ends lane"
```

---

## Task 4: Mood timeline view mode

**Files:**
- Create: `voice notes/MoodTimelineHelpers.swift`
- Modify: `voice notes/AIHomeView.swift` (view-mode toggle, conditional row treatment)

- [ ] **Step 1: Create the mood helpers**

```swift
//
//  MoodTimelineHelpers.swift
//  voice notes
//

import SwiftUI

enum MoodTimelineHelpers {
    /// Map an emotionalTone string (positive / negative / neutral / mixed)
    /// to a tint color. Unknown tones return clear (no tint).
    static func moodColor(for tone: String?) -> Color {
        switch tone?.lowercased() {
        case "positive": return Color.green
        case "negative": return Color.red
        case "neutral":  return Color.gray
        case "mixed":    return Color.orange
        default:         return Color.clear
        }
    }

    /// Returns one mood color per day for the last 7 days, oldest → newest.
    /// Uses the dominant tone of the day's notes. Empty days return clear.
    static func moodSparkline(notes: [Note], today: Date = Date()) -> [Color] {
        let calendar = Calendar.current
        var days: [Color] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                days.append(.clear); continue
            }
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let dayNotes = notes.filter { $0.createdAt >= start && $0.createdAt < end }
            if dayNotes.isEmpty {
                days.append(.clear)
            } else {
                let dominant = Dictionary(grouping: dayNotes, by: { ($0.emotionalTone ?? "neutral").lowercased() })
                    .max { $0.value.count < $1.value.count }?.key
                days.append(moodColor(for: dominant))
            }
        }
        return days
    }
}

#if DEBUG
@MainActor private let _moodTimelineChecks: Void = {
    assert(MoodTimelineHelpers.moodColor(for: "positive") == .green)
    assert(MoodTimelineHelpers.moodColor(for: "POSITIVE") == .green, "Case-insensitive")
    assert(MoodTimelineHelpers.moodColor(for: nil) == .clear)
    assert(MoodTimelineHelpers.moodColor(for: "garbage") == .clear)

    let empty = MoodTimelineHelpers.moodSparkline(notes: [])
    assert(empty.count == 7, "Sparkline always has 7 days")
    assert(empty.allSatisfy { $0 == .clear }, "Empty notes → all clear")
}()
#endif
```

- [ ] **Step 2: Add the view mode enum and state to AIHomeView**

In `voice notes/AIHomeView.swift`, near the top of the file (after `import SwiftUI`, before `struct AIHomeView`), add:

```swift
enum NotesViewMode: String, CaseIterable {
    case list = "List"
    case mood = "Mood"
}
```

In the `@State` declarations of `AIHomeView` (around line 45), add:

```swift
@State private var viewMode: NotesViewMode = .list
```

- [ ] **Step 3: Add the mode toggle next to the existing sort button**

In `voice notes/AIHomeView.swift`, find the sort toggle button (around line 803-812):

```swift
                // Sort toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sortNewestFirst.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        ...
```

Immediately BEFORE that Button, add a Picker:

```swift
                // View mode toggle
                Picker("View", selection: $viewMode) {
                    ForEach(NotesViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .padding(.trailing, 8)
```

- [ ] **Step 4: Show sparkline header in mood mode**

In `voice notes/AIHomeView.swift`, find where `IntentFilterChips` was added in Task 2. Immediately AFTER its closing `.padding(.bottom, 4)`, add:

```swift
            if viewMode == .mood && selectedTab != .ai {
                HStack(spacing: 6) {
                    Text("Last 7 days")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextTertiary)
                    ForEach(Array(MoodTimelineHelpers.moodSparkline(notes: filteredNotes).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color == .clear ? Color.eeonCard : color)
                            .frame(width: 10, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
```

- [ ] **Step 5: Add the mood color edge to NoteFeedCard**

In `voice notes/AIHomeView.swift`, locate the `NoteFeedCard` struct (around line 1823). Find its `body` and the outermost VStack/HStack. We want to add a 4-pt-wide colored bar on the leading edge when in mood mode.

The simplest drop-in: at the call site of `NoteFeedCard` (where it's used inside the LazyVGrid loop), wrap it in an HStack with a leading rectangle. Find the loop that renders cards (search for `NoteFeedCard(note:` or the ForEach inside the grid). The card creation likely looks like:

```swift
NoteFeedCard(note: note, ...)
```

Wrap with:

```swift
HStack(spacing: 0) {
    if viewMode == .mood {
        Rectangle()
            .fill(MoodTimelineHelpers.moodColor(for: note.emotionalTone))
            .frame(width: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
    NoteFeedCard(note: note, ...)
}
```

(The `...` represents whatever existing parameters are already passed — keep them intact.)

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

Run on physical iPhone. On the All tab:
- Segmented control at top toggles List ↔ Mood
- Mood mode adds: a 7-day sparkline header (7 colored circles, gray for empty days), and a colored edge bar on each note card (green/red/gray/orange or transparent)
- List mode shows the original layout with no edges
- Toggle does not affect the feed contents — same notes, same order

- [ ] **Step 7: Commit + bump build to 103**

```bash
git add "voice notes/MoodTimelineHelpers.swift" "voice notes/AIHomeView.swift"
git commit -m "feat: mood timeline view mode for notes feed"
sed -i '' 's/CURRENT_PROJECT_VERSION = 102/CURRENT_PROJECT_VERSION = 103/g' "voice notes.xcodeproj/project.pbxproj"
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to build 103 for mood timeline mode"
```

---

## Task 5: Decision Log sheet

**Files:**
- Create: `voice notes/DecisionLogView.swift`
- Modify: `voice notes/AIHomeView.swift` (sheet trigger)

- [ ] **Step 1: Create the Decision Log view**

```swift
//
//  DecisionLogView.swift
//  voice notes
//

import SwiftUI
import SwiftData

struct DecisionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExtractedDecision.createdAt, order: .reverse) private var decisions: [ExtractedDecision]
    @Query private var projects: [Project]
    @Query private var notes: [Note]

    private var grouped: [(Date, [ExtractedDecision])] {
        NotesReorgHelpers.groupByWeek(items: decisions, dateKey: { $0.createdAt })
    }

    private func projectName(for decision: ExtractedDecision) -> String? {
        guard let noteId = decision.sourceNoteId,
              let note = notes.first(where: { $0.id == noteId }),
              let projectId = note.projectId,
              let project = projects.first(where: { $0.id == projectId }) else {
            return nil
        }
        return project.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if decisions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 40))
                                .foregroundStyle(.eeonTextTertiary)
                            Text("No decisions yet")
                                .font(.headline)
                            Text("As you capture voice notes, EEON will extract decisions here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }

                    ForEach(grouped, id: \.0) { weekStart, items in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(weekHeader(weekStart))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.eeonTextSecondary)
                                .padding(.horizontal, 16)

                            ForEach(items) { d in
                                decisionRow(d)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Decisions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func decisionRow(_ d: ExtractedDecision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(d.content)
                .font(.body)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if let proj = projectName(for: d) {
                    Label(proj, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextTertiary)
                }
                Text(d.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.eeonTextTertiary)
                if d.confidence != "Medium" {
                    Text(d.confidence)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.eeonCard)
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func weekHeader(_ weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Week of \(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }
}
```

- [ ] **Step 2: Add the sheet trigger to AIHomeView**

In `voice notes/AIHomeView.swift`, add a state var alongside the others (around line 45):

```swift
@State private var showingDecisionLog = false
```

Find an existing toolbar / menu / accessible button location. The simplest drop-in is the existing settings sheet trigger area. Search for `showingSettings = true` to find the menu where Settings is opened. Add a sibling button — for example, if Settings is opened from a menu, add:

```swift
Button {
    showingDecisionLog = true
} label: {
    Label("Decisions", systemImage: "checkmark.seal")
}
```

Then attach the sheet at the same level as `showingSettings`'s sheet (around line 307):

```swift
.sheet(isPresented: $showingDecisionLog) {
    DecisionLogView()
        .modelContainer(modelContext.container)
}
```

(Use the existing pattern in this file for sheet presentation — `.modelContainer(modelContext.container)` should match how other sheets in this file inherit the container; if other sheets don't use that modifier, omit it.)

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme "voice notes" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

Run on physical iPhone. Open the menu where you added the trigger → tap "Decisions". Verify:
- Sheet opens with title "Decisions"
- Decisions are grouped under "Week of MMM d – MMM d" headers
- Each row shows the decision content, optional project label, date, and a confidence pill if not Medium
- Empty state shows when there are no decisions yet
- Done button dismisses the sheet

- [ ] **Step 4: Commit + bump build to 104**

```bash
git add "voice notes/DecisionLogView.swift" "voice notes/AIHomeView.swift"
git commit -m "feat: decision log sheet grouped by week"
sed -i '' 's/CURRENT_PROJECT_VERSION = 103/CURRENT_PROJECT_VERSION = 104/g' "voice notes.xcodeproj/project.pbxproj"
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to build 104 for decision log"
```

---

## Task 6: Final verification and ship

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` (CURRENT_PROJECT_VERSION)

- [ ] **Step 1: Bump the build number**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
sed -i '' 's/CURRENT_PROJECT_VERSION = 98/CURRENT_PROJECT_VERSION = 99/g' "voice notes.xcodeproj/project.pbxproj"
grep -c "CURRENT_PROJECT_VERSION = 99" "voice notes.xcodeproj/project.pbxproj"
```
Expected: `8` (one occurrence per target).

- [ ] **Step 2: Final clean build**

```bash
xcodebuild -scheme "voice notes" -configuration Release -destination 'generic/platform=iOS' build 2>&1 | grep -E "(error:|BUILD )"
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Smoke test on physical iPhone**

Run the app from Xcode (Debug) one final time on the physical iPhone. Walk through:
- All tab: intent chips visible, tag chips still visible above them, both filter independently
- Loose Ends section appears if you have any unresolved items; Resolve button works
- Mood toggle in segmented control switches list ↔ mood; sparkline shows; edge bars colored
- Open the menu / button you wired for Decisions → sheet renders with weekly groups
- Sync still works: save a fresh note, watch CloudKit CD_Note count rise (in Debug builds with diagnostics panel)

- [ ] **Step 4: Archive and ship to TestFlight**

In Xcode:
- Top destination selector → **Any iOS Device (arm64)**
- Product → **Archive**
- Wait ~5 min for archive to complete
- Organizer opens → **Distribute App** → **App Store Connect** → **Upload**

After upload, wait for Apple's email (~15–20 min). Then verify build 103 appears in App Store Connect → TestFlight tab. Update on iPad and iPhone via TestFlight; confirm all four features render correctly on both devices.

---

## Self-review

**Spec coverage:**
- Intent filter chips → Task 2 ✓
- Loose Ends lane → Task 3 ✓
- Mood timeline view mode → Task 4 ✓
- Decision Log → Task 5 ✓
- Pure helpers shared across features → Task 1 ✓
- Build/ship → Task 6 ✓

**Placeholder scan:** No "TBD," "implement later," or vague "appropriate handling" instructions. Every code block is complete and copy-pasteable. The one place using `...` in code (Task 4 Step 5, wrapping `NoteFeedCard(note: note, ...)`) is explicitly explained — the `...` represents existing parameters that the engineer is preserving, not new code to invent.

**Type/name consistency:**
- `NotesReorgHelpers.filterableIntents`, `intentCounts`, `filterByIntents`, `weekStart`, `groupByWeek` — defined once, referenced consistently in Tasks 2, 4, 5
- `IntentFilterChips(counts:selected:)` — same signature in component file (Task 2 Step 1) and call site (Task 2 Step 5)
- `LooseEndsLane(openItems:onTapItem:)` — same in component file and call site
- `MoodTimelineHelpers.moodColor(for:)`, `moodSparkline(notes:)` — consistent across Task 4
- `UnresolvedItem.resolvedAt` and `isOpen` — defined in Task 3 Step 1, used in Task 3 Steps 3 and 4

**Schema migration risk:** Adding `resolvedAt: Date?` is a non-breaking SwiftData migration (lightweight, automatic). CloudKit's `CD_UnresolvedItem` record type already exists in Production from the schema-deploy work earlier this week; CloudKit accepts unknown optional fields, so no Dashboard action is needed.

**Effort estimate:** Each task is small enough to land in 30–60 min including verification. Full pack is ~3–5 hours of focused work, plus ~30 min for archive/upload/TestFlight verification.
