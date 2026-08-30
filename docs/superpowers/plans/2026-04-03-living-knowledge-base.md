# Living Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a KnowledgeArticle system that compiles cross-note intelligence into living profiles for people, projects, and topics — automatically maintained by the LLM.

**Architecture:** New `KnowledgeArticle` SwiftData model + `KnowledgeCompiler` Observable singleton. Tier 1 (note save) marks affected articles dirty with zero API calls. Tier 2.5 (app foreground) recompiles dirty articles via gpt-4o-mini. Tier 3 (daily) runs lint/heal sweep. Pro-only feature gated by `SubscriptionManager.shared.isPro`.

**Tech Stack:** SwiftUI, SwiftData, OpenAI gpt-4o-mini, existing SummaryService patterns

**Spec:** `docs/superpowers/specs/2026-04-03-living-knowledge-base-design.md`

---

## File Structure

### New files:
| File | Responsibility |
|------|---------------|
| `voice notes/KnowledgeArticle.swift` | SwiftData model + JSON accessor computed properties + supporting Codable structs |
| `voice notes/KnowledgeCompiler.swift` | Observable singleton — markAffectedArticles (Tier 1), recompileDirtyArticles (Tier 2.5), lintArticles (Tier 3) |
| `voice notes/KnowledgeArticleDetailView.swift` | Full article detail screen pushed from card tap |
| `voice notes/KnowledgeCardView.swift` | Compact card for horizontal scroll in AIHomeView |

### Modified files:
| File | Change |
|------|--------|
| `voice notes/voice_notesApp.swift:36` | Add `KnowledgeArticle.self` to schema array |
| `voice notes/IntelligenceService.swift:44-177` | Call `KnowledgeCompiler.markAffectedArticles()` at end of Tier 1 `processNoteSave()` |
| `voice notes/voice_notesApp.swift:254-276` | Call `KnowledgeCompiler.recompileDirtyArticles()` in `triggerAppActiveRefresh()` after Tier 2, before Tier 3 |
| `voice notes/SummaryService.swift` | Add `compileArticle()` and `lintArticles()` static methods (append to end of file) |
| `voice notes/RAGService.swift:39-86` | Inject KnowledgeArticle context before vector search in `answerQuestion()` |
| `voice notes/AIHomeView.swift:190-212` | Add knowledge cards horizontal scroll section between free tier warning and note feed |
| `voice notes/DailyBrief.swift:26` | Add `lintResultsData: Data` field |
| `voice notes/DailyBriefSheet.swift:36-37` | Add Knowledge Health section after warnings |

---

### Task 1: KnowledgeArticle SwiftData Model

**Files:**
- Create: `voice notes/KnowledgeArticle.swift`
- Modify: `voice notes/voice_notesApp.swift:36`

- [ ] **Step 1: Create KnowledgeArticle.swift with model and supporting types**

```swift
//
//  KnowledgeArticle.swift
//  voice notes
//
//  Living knowledge article — compiled by LLM from voice notes.
//  Types: person, project, topic. Auto-maintained, never manually edited.
//

import Foundation
import SwiftData

// MARK: - Article Type

enum KnowledgeArticleType: String, CaseIterable, Codable {
    case person = "person"
    case project = "project"
    case topic = "topic"

    var icon: String {
        switch self {
        case .person: return "person.fill"
        case .project: return "folder.fill"
        case .topic: return "lightbulb.fill"
        }
    }

    var label: String {
        switch self {
        case .person: return "Person"
        case .project: return "Project"
        case .topic: return "Topic"
        }
    }
}

// MARK: - JSON Supporting Types

struct OpenThread: Codable, Identifiable {
    var id: String { thread }
    let thread: String
    let status: String      // "open", "waiting", "stale"
    let daysOpen: Int
}

struct TimelineEvent: Codable, Identifiable {
    var id: String { "\(date)-\(event)" }
    let date: String        // ISO date or human-readable
    let event: String
}

struct ArticleConnection: Codable, Identifiable {
    var id: String { articleName }
    let articleName: String
    let reason: String
}

struct ArticleDecision: Codable, Identifiable {
    var id: String { decision }
    let decision: String
    let status: String      // "resolved", "open"
    let date: String?
}

struct KnowledgeLintResult: Codable, Identifiable {
    var id: String { content }
    let lintType: String    // "stale_thread", "contradiction", "connection", "gap"
    let content: String
    let severity: String    // "info", "warning", "urgent"
    let relatedArticleNames: [String]
}

// MARK: - KnowledgeArticle Model

@Model
final class KnowledgeArticle {
    var id: UUID = UUID()
    var name: String = ""
    var articleTypeRaw: String = "topic"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastCompiledAt: Date?
    var isDirty: Bool = true
    var mentionCount: Int = 0
    var lastMentionedAt: Date?

    // Core content (LLM-compiled)
    var summary: String = ""
    var openThreadsJSON: String?
    var timelineJSON: String?
    var connectionsJSON: String?
    var sentimentArc: String?

    // Type-specific fields
    var decisionsJSON: String?
    var relationshipContext: String?
    var thinkingEvolution: String?

    // Source tracking
    var linkedNoteIdsJSON: String?
    var lastCompiledNoteDate: Date?

    // Aliases for entity resolution
    var aliasesJSON: String?

    init(name: String, articleType: KnowledgeArticleType) {
        self.id = UUID()
        self.name = name
        self.articleTypeRaw = articleType.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDirty = true
        self.mentionCount = 0

        // Auto-generate initial aliases
        var initial = [name.lowercased()]
        let words = name.split(separator: " ")
        if words.count > 1 {
            // Add first name for people ("Sarah Chen" -> "sarah")
            initial.append(String(words[0]).lowercased())
        }
        self.aliases = initial
    }

    // MARK: - Computed Accessors

    var articleType: KnowledgeArticleType {
        get { KnowledgeArticleType(rawValue: articleTypeRaw) ?? .topic }
        set { articleTypeRaw = newValue.rawValue }
    }

    var openThreads: [OpenThread] {
        get {
            guard let json = openThreadsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([OpenThread].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            openThreadsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var timeline: [TimelineEvent] {
        get {
            guard let json = timelineJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TimelineEvent].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            timelineJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var connections: [ArticleConnection] {
        get {
            guard let json = connectionsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ArticleConnection].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            connectionsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var decisions: [ArticleDecision] {
        get {
            guard let json = decisionsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ArticleDecision].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            decisionsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var linkedNoteIds: [UUID] {
        get {
            guard let json = linkedNoteIdsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            linkedNoteIdsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var aliases: [String] {
        get {
            guard let json = aliasesJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            aliasesJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // MARK: - Entity Resolution

    func matches(name candidate: String) -> Bool {
        let normalized = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if self.name.lowercased() == normalized { return true }
        return aliases.contains { $0 == normalized || normalized.contains($0) || $0.contains(normalized) }
    }

    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var current = aliases
        if !current.contains(normalized) {
            current.append(normalized)
            aliases = current
        }
    }

    func addLinkedNote(id: UUID) {
        var current = linkedNoteIds
        if !current.contains(id) {
            current.append(id)
            linkedNoteIds = current
        }
    }

    var isRecentlyUpdated: Bool {
        guard let compiled = lastCompiledAt else { return false }
        return Date().timeIntervalSince(compiled) < 24 * 60 * 60
    }
}
```

- [ ] **Step 2: Add KnowledgeArticle to SwiftData schema**

In `voice notes/voice_notesApp.swift`, line 36, add `KnowledgeArticle.self` to the schema array:

```swift
let schema = Schema([Note.self, Tag.self, ExtractedDecision.self, ExtractedAction.self, ExtractedCommitment.self, UnresolvedItem.self, KanbanItem.self, KanbanMovement.self, WeeklyDebrief.self, Project.self, DailyBrief.self, ExtractedURL.self, MentionedPerson.self, KnowledgeArticle.self])
```

- [ ] **Step 3: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/KnowledgeArticle.swift" "voice notes/voice_notesApp.swift"
git commit -m "feat: add KnowledgeArticle SwiftData model for living knowledge base"
```

---

### Task 2: KnowledgeCompiler Service — Tier 1 (Mark Dirty)

**Files:**
- Create: `voice notes/KnowledgeCompiler.swift`
- Modify: `voice notes/IntelligenceService.swift`

- [ ] **Step 1: Create KnowledgeCompiler.swift with Tier 1 markAffectedArticles**

```swift
//
//  KnowledgeCompiler.swift
//  voice notes
//
//  Compiles cross-note intelligence into KnowledgeArticles.
//  Tier 1: mark dirty (local). Tier 2.5: recompile (API). Tier 3: lint/heal (API).
//

import Foundation
import SwiftData

@Observable
final class KnowledgeCompiler {
    static let shared = KnowledgeCompiler()

    var isCompiling = false
    var lastCompileAt: Date?

    private enum Keys {
        static let lastCompileDate = "knowledgeCompiler.lastCompileDate"
    }

    private init() {
        lastCompileAt = UserDefaults.standard.object(forKey: Keys.lastCompileDate) as? Date
    }

    // MARK: - Tier 1: Mark Affected Articles (on note save, local only)

    /// After extraction, identify which articles this note affects.
    /// Sets isDirty = true on each. Zero API calls.
    @MainActor
    func markAffectedArticles(note: Note, context: ModelContext) {
        // Only compile for pro users
        guard SubscriptionManager.shared.isPro else { return }

        let allArticles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []

        // People mentioned in this note
        for personName in note.mentionedPeople {
            let article = findOrCreate(
                name: personName,
                type: .person,
                existing: allArticles,
                context: context
            )
            markDirty(article: article, noteId: note.id)
        }

        // Topics extracted from this note
        for topic in note.topics {
            let article = findOrCreate(
                name: topic,
                type: .topic,
                existing: allArticles,
                context: context
            )
            markDirty(article: article, noteId: note.id)
        }

        // Inferred project
        if let projectName = note.inferredProjectName, !projectName.isEmpty {
            let article = findOrCreate(
                name: projectName,
                type: .project,
                existing: allArticles,
                context: context
            )
            markDirty(article: article, noteId: note.id)
        }

        try? context.save()
    }

    // MARK: - Entity Resolution

    private func findOrCreate(
        name: String,
        type: KnowledgeArticleType,
        existing: [KnowledgeArticle],
        context: ModelContext
    ) -> KnowledgeArticle {
        // Look for existing article of the same type that matches
        for article in existing where article.articleType == type {
            if article.matches(name: name) {
                return article
            }
        }

        // Create new article
        let article = KnowledgeArticle(name: name, articleType: type)
        context.insert(article)
        return article
    }

    private func markDirty(article: KnowledgeArticle, noteId: UUID) {
        article.isDirty = true
        article.mentionCount += 1
        article.lastMentionedAt = Date()
        article.updatedAt = Date()
        article.addLinkedNote(id: noteId)
    }
}
```

- [ ] **Step 2: Hook into IntelligenceService.processNoteSave()**

In `voice notes/IntelligenceService.swift`, add a call to `KnowledgeCompiler` at the end of `processNoteSave()`, just before the closing `}` of the function (after line 176, after `StatusCounters.shared.markSessionStale()`):

```swift
        // Mark knowledge articles dirty for Tier 2.5 compile
        await MainActor.run {
            KnowledgeCompiler.shared.markAffectedArticles(note: note, context: context)
        }
```

- [ ] **Step 3: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/KnowledgeCompiler.swift" "voice notes/IntelligenceService.swift"
git commit -m "feat: add KnowledgeCompiler Tier 1 — mark affected articles on note save"
```

---

### Task 3: SummaryService — Compile Article and Lint Methods

**Files:**
- Modify: `voice notes/SummaryService.swift` (append new methods at end of enum)

- [ ] **Step 1: Add compileArticle() static method to SummaryService**

Append the following inside the `enum SummaryService {` block, at the end of the file before the closing `}`:

```swift
    // MARK: - Knowledge Article Compilation

    /// Compile or update a KnowledgeArticle from new notes.
    /// Returns structured JSON matching article fields.
    static func compileArticle(
        existingSummary: String?,
        existingOpenThreads: [OpenThread],
        existingTimeline: [TimelineEvent],
        existingConnections: [ArticleConnection],
        existingSentimentArc: String?,
        existingDecisions: [ArticleDecision],
        existingRelationshipContext: String?,
        existingThinkingEvolution: String?,
        articleName: String,
        articleType: KnowledgeArticleType,
        newNoteTexts: [String],
        apiKey: String
    ) async throws -> CompileArticleResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build existing article context
        var existingContext = ""
        if let summary = existingSummary, !summary.isEmpty {
            existingContext += "Current summary: \(summary)\n"
        }
        if let arc = existingSentimentArc, !arc.isEmpty {
            existingContext += "Sentiment arc: \(arc)\n"
        }
        if let rel = existingRelationshipContext, !rel.isEmpty {
            existingContext += "Relationship context: \(rel)\n"
        }
        if let evolution = existingThinkingEvolution, !evolution.isEmpty {
            existingContext += "Thinking evolution: \(evolution)\n"
        }
        if !existingOpenThreads.isEmpty {
            let threads = existingOpenThreads.map { "- \($0.thread) (\($0.status), \($0.daysOpen)d)" }.joined(separator: "\n")
            existingContext += "Open threads:\n\(threads)\n"
        }
        if !existingDecisions.isEmpty {
            let decs = existingDecisions.map { "- \($0.decision) [\($0.status)]" }.joined(separator: "\n")
            existingContext += "Decisions:\n\(decs)\n"
        }

        let newNotesText = newNoteTexts.enumerated().map { "Note \($0.offset + 1): \($0.element)" }.joined(separator: "\n\n")

        let typeSpecificFields: String
        switch articleType {
        case .person:
            typeSpecificFields = """
            "relationshipContext": "Who this person is and your relationship (1-2 sentences)",
            "sentimentArc": "How the relationship tone has evolved (e.g. 'Cautious -> Warming up -> Trusted partner')",
            """
        case .project:
            typeSpecificFields = """
            "decisions": [{"decision": "what was decided", "status": "resolved or open", "date": "when"}],
            "thinkingEvolution": "How your approach has changed over time (1 sentence)",
            "sentimentArc": "Overall project mood trajectory",
            """
        case .topic:
            typeSpecificFields = """
            "thinkingEvolution": "How your thinking on this topic has evolved (1-2 sentences)",
            "sentimentArc": "Your emotional relationship with this topic over time",
            """
        }

        let systemPrompt = """
        You maintain a living knowledge article about a \(articleType.label.lowercased()) named "\(articleName)".
        Update the article with information from the new notes below.
        Preserve existing information unless contradicted by newer notes.
        Be concise — summaries should be 2-3 sentences max.

        Return ONLY valid JSON with this structure:
        {
            "summary": "2-3 sentence overview incorporating new information",
            "openThreads": [{"thread": "description of open item", "status": "open|waiting|stale", "daysOpen": 0}],
            "timeline": [{"date": "YYYY-MM-DD or description", "event": "what happened"}],
            "connections": [{"articleName": "name of related person/project/topic", "reason": "why connected"}],
            \(typeSpecificFields)
        }

        Rules:
        - Keep summaries factual and concise
        - Mark threads as "stale" if they seem forgotten (>5 days with no update)
        - Timeline should only include significant events, max 10 entries
        - Connections should link to other people, projects, or topics mentioned alongside this entity
        - Return ONLY valid JSON, no other text
        """

        let userContent: String
        if existingContext.isEmpty {
            userContent = "Create a new article from these notes:\n\n\(newNotesText)"
        } else {
            userContent = "Current article state:\n\(existingContext)\n\nNew notes to incorporate:\n\n\(newNotesText)"
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.3,
            "max_tokens": 1500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummaryError.apiError("Empty response")
        }

        return try JSONDecoder().decode(CompileArticleResponse.self, from: jsonData)
    }

    /// Lint all knowledge articles for stale threads, contradictions, connections, and gaps.
    static func lintArticles(
        articleSummaries: [(name: String, type: String, summary: String, openThreadCount: Int, daysSinceLastMention: Int)],
        apiKey: String
    ) async throws -> [KnowledgeLintResult] {
        guard !articleSummaries.isEmpty else { return [] }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let articlesText = articleSummaries.map { article in
            "[\(article.type)] \(article.name): \(article.summary) (open threads: \(article.openThreadCount), last mentioned: \(article.daysSinceLastMention)d ago)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a knowledge base health checker. Review these knowledge articles and find issues.

        Return JSON array of issues found:
        [
            {
                "lintType": "stale_thread|contradiction|connection|gap",
                "content": "Human-readable description of the issue",
                "severity": "info|warning|urgent",
                "relatedArticleNames": ["Article Name 1", "Article Name 2"]
            }
        ]

        Lint types:
        - stale_thread: Open commitments or threads with no follow-up (>5 days)
        - contradiction: Conflicting information across articles
        - connection: Articles that should be linked but aren't
        - gap: Missing information that seems important

        Rules:
        - Return 0-5 most important issues
        - Focus on actionable insights, not trivia
        - "urgent" = needs action today, "warning" = needs attention this week, "info" = nice to know
        - Return ONLY valid JSON array, no other text
        - If no issues found, return empty array []
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Review these knowledge articles:\n\n\(articlesText)"]
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryError.apiError(errorMessage)
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            return []
        }

        return (try? JSONDecoder().decode([KnowledgeLintResult].self, from: jsonData)) ?? []
    }
```

- [ ] **Step 2: Add CompileArticleResponse struct**

Add this at the top of `SummaryService.swift`, after the `IntentAnalysis` struct (around line 76):

```swift
// MARK: - Knowledge Article Compilation Response

struct CompileArticleResponse: Codable {
    let summary: String
    let openThreads: [OpenThread]?
    let timeline: [TimelineEvent]?
    let connections: [ArticleConnection]?
    let sentimentArc: String?
    let decisions: [ArticleDecision]?
    let relationshipContext: String?
    let thinkingEvolution: String?
}
```

- [ ] **Step 3: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: add compileArticle and lintArticles methods to SummaryService"
```

---

### Task 4: KnowledgeCompiler — Tier 2.5 (Recompile) and Tier 3 (Lint)

**Files:**
- Modify: `voice notes/KnowledgeCompiler.swift`
- Modify: `voice notes/voice_notesApp.swift`
- Modify: `voice notes/DailyBrief.swift`
- Modify: `voice notes/IntelligenceService.swift`

- [ ] **Step 1: Add Tier 2.5 recompileDirtyArticles to KnowledgeCompiler**

Append the following methods to `KnowledgeCompiler`, after the existing `markDirty()` method:

```swift
    // MARK: - Tier 2.5: Recompile Dirty Articles (on app foreground, API calls)

    /// Recompile articles marked dirty. Max 5 per pass, 15-min cooldown.
    func recompileDirtyArticles(context: ModelContext) async {
        // Only compile for pro users
        guard SubscriptionManager.shared.isPro else { return }

        // 15-minute cooldown
        if let lastCompile = lastCompileAt,
           Date().timeIntervalSince(lastCompile) < 15 * 60 {
            return
        }

        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return }
        guard !isCompiling else { return }

        await MainActor.run { isCompiling = true }

        defer {
            Task { @MainActor in
                isCompiling = false
                lastCompileAt = Date()
                UserDefaults.standard.set(Date(), forKey: Keys.lastCompileDate)
            }
        }

        // Fetch dirty articles, sorted by most recently mentioned
        var descriptor = FetchDescriptor<KnowledgeArticle>(
            predicate: #Predicate { $0.isDirty == true },
            sortBy: [SortDescriptor(\.lastMentionedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5

        guard let dirtyArticles = try? context.fetch(descriptor), !dirtyArticles.isEmpty else {
            return
        }

        // Fetch all notes for lookups
        let allNotes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let noteLookup = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })

        for article in dirtyArticles {
            do {
                // Get new notes since last compile
                let linkedIds = article.linkedNoteIds
                let newNotes: [Note]
                if let lastCompiled = article.lastCompiledNoteDate {
                    newNotes = linkedIds.compactMap { noteLookup[$0] }
                        .filter { $0.createdAt > lastCompiled }
                        .sorted { $0.createdAt < $1.createdAt }
                } else {
                    // First compile — include all linked notes
                    newNotes = linkedIds.compactMap { noteLookup[$0] }
                        .sorted { $0.createdAt < $1.createdAt }
                }

                guard !newNotes.isEmpty else {
                    await MainActor.run { article.isDirty = false }
                    continue
                }

                let noteTexts = newNotes.map { note -> String in
                    let text = note.enhancedNoteText ?? note.transcript ?? note.content
                    let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
                    return "[\(dateStr)] \(String(text.prefix(500)))"
                }

                let response = try await SummaryService.compileArticle(
                    existingSummary: article.summary.isEmpty ? nil : article.summary,
                    existingOpenThreads: article.openThreads,
                    existingTimeline: article.timeline,
                    existingConnections: article.connections,
                    existingSentimentArc: article.sentimentArc,
                    existingDecisions: article.decisions,
                    existingRelationshipContext: article.relationshipContext,
                    existingThinkingEvolution: article.thinkingEvolution,
                    articleName: article.name,
                    articleType: article.articleType,
                    newNoteTexts: noteTexts,
                    apiKey: apiKey
                )

                await MainActor.run {
                    article.summary = response.summary
                    if let threads = response.openThreads { article.openThreads = threads }
                    if let timeline = response.timeline { article.timeline = timeline }
                    if let connections = response.connections { article.connections = connections }
                    if let arc = response.sentimentArc { article.sentimentArc = arc }
                    if let decisions = response.decisions { article.decisions = decisions }
                    if let rel = response.relationshipContext { article.relationshipContext = rel }
                    if let evolution = response.thinkingEvolution { article.thinkingEvolution = evolution }

                    article.isDirty = false
                    article.lastCompiledAt = Date()
                    article.lastCompiledNoteDate = newNotes.last?.createdAt
                    article.updatedAt = Date()

                    try? context.save()
                }
            } catch {
                print("[KnowledgeCompiler] Failed to compile article '\(article.name)': \(error)")
            }
        }
    }

    // MARK: - Tier 3: Lint Articles (daily, one API call)

    /// Scan all articles for stale threads, contradictions, and gaps.
    func lintArticles(context: ModelContext) async -> [KnowledgeLintResult] {
        guard SubscriptionManager.shared.isPro else { return [] }
        guard let apiKey = APIKeys.openAI, !apiKey.isEmpty else { return [] }

        let allArticles = (try? context.fetch(FetchDescriptor<KnowledgeArticle>())) ?? []
        guard !allArticles.isEmpty else { return [] }

        let summaries = allArticles.map { article -> (name: String, type: String, summary: String, openThreadCount: Int, daysSinceLastMention: Int) in
            let daysSince: Int
            if let last = article.lastMentionedAt {
                daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            } else {
                daysSince = Int.max
            }
            return (
                name: article.name,
                type: article.articleType.label,
                summary: article.summary.isEmpty ? "(no summary yet)" : article.summary,
                openThreadCount: article.openThreads.count,
                daysSinceLastMention: daysSince
            )
        }

        do {
            return try await SummaryService.lintArticles(articleSummaries: summaries, apiKey: apiKey)
        } catch {
            print("[KnowledgeCompiler] Lint failed: \(error)")
            return []
        }
    }
```

- [ ] **Step 2: Add lintResultsData field to DailyBrief**

In `voice notes/DailyBrief.swift`, add after line 29 (`var warningsData: Data = Data()`):

```swift
    var lintResultsData: Data = Data()
```

And add the JSON accessor after the `warnings` computed property (after the `set` block around line 97):

```swift
    var lintResults: [KnowledgeLintResult] {
        get {
            guard !lintResultsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([KnowledgeLintResult].self, from: lintResultsData)) ?? []
        }
        set {
            lintResultsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
```

- [ ] **Step 3: Hook Tier 2.5 into triggerAppActiveRefresh**

In `voice notes/voice_notesApp.swift`, in the `triggerAppActiveRefresh()` method, add after the Tier 2 session brief refresh (after line 263, after the `refreshSessionBriefIfNeeded` call) and before the Tier 3 daily brief check:

```swift
        // Tier 2.5: Recompile dirty knowledge articles (API calls, pro only)
        await KnowledgeCompiler.shared.recompileDirtyArticles(context: context)
```

- [ ] **Step 4: Hook Tier 3 lint into daily brief generation**

In `voice notes/IntelligenceService.swift`, in the `checkAndGenerateDailyBrief()` method, add after the brief is inserted into context (after line 378, after `context.insert(brief)`):

```swift
                // Tier 3: Lint knowledge articles
                let lintResults = await KnowledgeCompiler.shared.lintArticles(context: context)
                if !lintResults.isEmpty {
                    brief.lintResults = lintResults
                }
```

- [ ] **Step 5: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add "voice notes/KnowledgeCompiler.swift" "voice notes/voice_notesApp.swift" "voice notes/IntelligenceService.swift" "voice notes/DailyBrief.swift"
git commit -m "feat: add KnowledgeCompiler Tier 2.5 recompile and Tier 3 lint"
```

---

### Task 5: RAG Integration — Article Context Injection

**Files:**
- Modify: `voice notes/RAGService.swift`

- [ ] **Step 1: Inject KnowledgeArticle context into RAG pipeline**

In `voice notes/RAGService.swift`, modify the `answerQuestion()` method. Add a new parameter and article context injection. Replace the method signature and add article lookup before the system prompt (around line 39):

Change the method signature to accept articles:

```swift
    func answerQuestion(query: String, allNotes: [Note], articles: [KnowledgeArticle] = []) async throws -> RAGResponse {
```

Then, after the merged notes are computed (after line 74, `let contextNotes = Array(mergedNotes.prefix(10))`), add article context:

```swift
        // Step 4.5: Find relevant knowledge articles by name/summary match
        let queryLower = query.lowercased()
        let relevantArticles = articles.filter { article in
            !article.summary.isEmpty && (
                queryLower.contains(article.name.lowercased()) ||
                article.name.lowercased().contains(queryLower) ||
                article.aliases.contains { queryLower.contains($0) }
            )
        }.prefix(3)

        let articleContext: String
        if !relevantArticles.isEmpty {
            articleContext = "\n\n--- COMPILED KNOWLEDGE ---\n\n" + relevantArticles.map { article in
                var text = "[\(article.articleType.label): \(article.name)]\n\(article.summary)"
                if !article.openThreads.isEmpty {
                    text += "\nOpen threads: " + article.openThreads.map { $0.thread }.joined(separator: "; ")
                }
                if let arc = article.sentimentArc, !arc.isEmpty {
                    text += "\nSentiment: \(arc)"
                }
                return text
            }.joined(separator: "\n\n")
        } else {
            articleContext = ""
        }
```

Then update the system prompt to include article context. Replace the existing system prompt (around line 88):

```swift
        let systemPrompt = """
        \(AuthService.shared.eeonContextPrefix)You are EEON, an AI memory assistant. Answer the user's question based on their compiled knowledge and notes below.
        Prefer compiled knowledge articles when available — they contain synthesized, up-to-date information.
        Always cite which note(s) or article(s) your answer comes from.
        If you can't find relevant information, say so honestly.
        After answering, provide exactly 2-3 follow-up questions on new lines prefixed with "FOLLOWUP: ".
        Do not use emojis.
        \(articleContext)

        --- USER'S NOTES ---

        \(notesContext)
        """
```

- [ ] **Step 2: Update RAG call site in AssistantView to pass articles**

Find where `answerQuestion` is called in the codebase and update to pass articles. Search for the call:

Run: `grep -n "answerQuestion" "voice notes/AssistantView.swift"`

Then update the call to include articles. The `AssistantView` already has access to `@Query` data — add a query for articles and pass them:

Add at the top of `AssistantView` with the other `@Query` declarations:

```swift
    @Query private var knowledgeArticles: [KnowledgeArticle]
```

Then at the `answerQuestion` call site, pass articles:

```swift
    let response = try await RAGService.shared.answerQuestion(query: query, allNotes: Array(notes), articles: Array(knowledgeArticles))
```

- [ ] **Step 3: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/RAGService.swift" "voice notes/AssistantView.swift"
git commit -m "feat: inject KnowledgeArticle context into RAG pipeline"
```

---

### Task 6: KnowledgeCardView and AIHomeView Integration

**Files:**
- Create: `voice notes/KnowledgeCardView.swift`
- Modify: `voice notes/AIHomeView.swift`

- [ ] **Step 1: Create KnowledgeCardView.swift**

```swift
//
//  KnowledgeCardView.swift
//  voice notes
//
//  Compact card for horizontal scroll in AIHomeView
//

import SwiftUI

struct KnowledgeCardView: View {
    let article: KnowledgeArticle

    @Environment(\.colorScheme) var colorScheme

    private var typeColor: Color {
        switch article.articleType {
        case .person: return .purple
        case .project: return .green
        case .topic: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: icon + name
            HStack(spacing: 8) {
                Image(systemName: article.articleType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(typeColor)
                    .frame(width: 28, height: 28)
                    .background(typeColor.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(article.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.eeonTextPrimary)
                        .lineLimit(1)

                    Text("\(article.mentionCount) mention\(article.mentionCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.eeonTextSecondary)
                }

                Spacer()

                if article.isRecentlyUpdated {
                    Circle()
                        .fill(typeColor)
                        .frame(width: 6, height: 6)
                }
            }

            // Summary
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(.eeonTextTertiary)
                    .lineLimit(3)
            }

            // Open threads count
            if !article.openThreads.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dotted")
                        .font(.caption2)
                    Text("\(article.openThreads.count) open thread\(article.openThreads.count == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .foregroundStyle(typeColor)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}
```

- [ ] **Step 2: Add knowledge cards section to AIHomeView**

In `voice notes/AIHomeView.swift`, add a `@Query` for knowledge articles at the top with the other queries (around line 30):

```swift
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var knowledgeArticles: [KnowledgeArticle]
```

Then add the knowledge cards section in the `body`. In the `ScrollView` `VStack` (around line 191), add between the free tier warning and the note feed (`// 3. Note feed with tabs`):

```swift
                            // Knowledge articles (pro only)
                            if UsageService.shared.isPro && !knowledgeArticles.isEmpty {
                                knowledgeCardsSection
                            }
```

Then add the computed property for the section. Add this as a new `@ViewBuilder` computed property on `AIHomeView` (near the other section properties):

```swift
    // MARK: - Knowledge Cards

    @ViewBuilder
    private var knowledgeCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Knowledge")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)

                Spacer()

                Text("\(knowledgeArticles.count) articles")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(knowledgeArticles.prefix(10)) { article in
                        NavigationLink(destination: KnowledgeArticleDetailView(article: article)) {
                            KnowledgeCardView(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
```

- [ ] **Step 3: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "voice notes/KnowledgeCardView.swift" "voice notes/AIHomeView.swift"
git commit -m "feat: add knowledge cards horizontal scroll to AIHomeView"
```

---

### Task 7: KnowledgeArticleDetailView

**Files:**
- Create: `voice notes/KnowledgeArticleDetailView.swift`

- [ ] **Step 1: Create KnowledgeArticleDetailView.swift**

```swift
//
//  KnowledgeArticleDetailView.swift
//  voice notes
//
//  Full detail view for a KnowledgeArticle — summary, threads, timeline, connections
//

import SwiftUI
import SwiftData

struct KnowledgeArticleDetailView: View {
    let article: KnowledgeArticle

    @Environment(\.colorScheme) var colorScheme
    @Query(sort: \Note.createdAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \KnowledgeArticle.lastMentionedAt, order: .reverse) private var allArticles: [KnowledgeArticle]

    private var linkedNotes: [Note] {
        let ids = Set(article.linkedNoteIds)
        return allNotes.filter { ids.contains($0.id) }
    }

    private var typeColor: Color {
        switch article.articleType {
        case .person: return .purple
        case .project: return .green
        case .topic: return .orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Summary
                if !article.summary.isEmpty {
                    summarySection
                }

                // Relationship context (person) or thinking evolution (topic/project)
                contextSection

                // Open Threads
                if !article.openThreads.isEmpty {
                    openThreadsSection
                }

                // Decisions (project only)
                if !article.decisions.isEmpty && article.articleType == .project {
                    decisionsSection
                }

                // Sentiment Arc
                if let arc = article.sentimentArc, !arc.isEmpty {
                    sentimentSection(arc: arc)
                }

                // Connections
                if !article.connections.isEmpty {
                    connectionsSection
                }

                // Timeline
                if !article.timeline.isEmpty {
                    timelineSection
                }

                // Source Notes
                if !linkedNotes.isEmpty {
                    sourceNotesSection
                }
            }
            .padding()
        }
        .background(Color("EEONBackground"))
        .navigationTitle(article.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: article.articleType.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(typeColor)
                .frame(width: 44, height: 44)
                .background(typeColor.opacity(0.12))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.articleType.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(typeColor)
                    .textCase(.uppercase)

                Text("\(article.mentionCount) mention\(article.mentionCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.eeonTextSecondary)
            }

            Spacer()

            if let compiled = article.lastCompiledAt {
                Text("Updated \(compiled.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.eeonTextTertiary)
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.summary)
                .font(.body)
                .foregroundStyle(.eeonTextPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Context (relationship / thinking evolution)

    @ViewBuilder
    private var contextSection: some View {
        if let rel = article.relationshipContext, !rel.isEmpty {
            labeledCard(label: "Relationship", text: rel, icon: "person.2.fill", color: .purple)
        }
        if let evolution = article.thinkingEvolution, !evolution.isEmpty {
            labeledCard(label: "How Your Thinking Evolved", text: evolution, icon: "arrow.triangle.swap", color: .blue)
        }
    }

    // MARK: - Open Threads

    @ViewBuilder
    private var openThreadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Open Threads", icon: "circle.dotted", color: typeColor)

            ForEach(article.openThreads) { thread in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(threadColor(status: thread.status))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.thread)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)

                        HStack(spacing: 8) {
                            Text(thread.status.capitalized)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(threadColor(status: thread.status))

                            if thread.daysOpen > 0 {
                                Text("\(thread.daysOpen)d open")
                                    .font(.caption2)
                                    .foregroundStyle(.eeonTextTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Decisions (project only)

    @ViewBuilder
    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Decisions", icon: "checkmark.seal.fill", color: .green)

            ForEach(article.decisions) { decision in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: decision.status == "resolved" ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(decision.status == "resolved" ? .green : .orange)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.decision)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)

                        if let date = decision.date {
                            Text(date)
                                .font(.caption2)
                                .foregroundStyle(.eeonTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Sentiment Arc

    @ViewBuilder
    private func sentimentSection(arc: String) -> some View {
        labeledCard(label: "Sentiment Arc", text: arc, icon: "waveform.path.ecg", color: typeColor)
    }

    // MARK: - Connections

    @ViewBuilder
    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Connected To", icon: "link", color: .blue)

            ForEach(article.connections) { connection in
                if let linked = allArticles.first(where: { $0.name == connection.articleName }) {
                    NavigationLink(destination: KnowledgeArticleDetailView(article: linked)) {
                        connectionRow(connection: connection)
                    }
                    .buttonStyle(.plain)
                } else {
                    connectionRow(connection: connection)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func connectionRow(connection: ArticleConnection) -> some View {
        HStack(spacing: 10) {
            Text(connection.articleName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.eeonTextPrimary)

            Spacer()

            Text(connection.reason)
                .font(.caption)
                .foregroundStyle(.eeonTextTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Timeline", icon: "clock.fill", color: .secondary)

            ForEach(article.timeline) { event in
                HStack(alignment: .top, spacing: 10) {
                    Text(event.date)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.eeonTextTertiary)
                        .frame(width: 70, alignment: .leading)

                    Text(event.event)
                        .font(.subheadline)
                        .foregroundStyle(.eeonTextPrimary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Source Notes

    @ViewBuilder
    private var sourceNotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Source Notes", icon: "doc.text.fill", color: .secondary)

            ForEach(linkedNotes.prefix(10)) { note in
                NavigationLink(destination: NoteDetailView(note: note)) {
                    HStack(spacing: 10) {
                        Text(note.displayTitle)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.eeonTextTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            if linkedNotes.count > 10 {
                Text("+ \(linkedNotes.count - 10) more notes")
                    .font(.caption)
                    .foregroundStyle(.eeonTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.eeonTextPrimary)
        }
    }

    @ViewBuilder
    private func labeledCard(label: String, text: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: label, icon: icon, color: color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.eeonTextSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eeonCard)
        .cornerRadius(14)
    }

    private func threadColor(status: String) -> Color {
        switch status.lowercased() {
        case "open": return .orange
        case "waiting": return .blue
        case "stale": return .red
        default: return .gray
        }
    }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/KnowledgeArticleDetailView.swift"
git commit -m "feat: add KnowledgeArticleDetailView for full article display"
```

---

### Task 8: DailyBriefSheet — Knowledge Health Section

**Files:**
- Modify: `voice notes/DailyBriefSheet.swift`

- [ ] **Step 1: Add Knowledge Health section to DailyBriefSheet**

In `voice notes/DailyBriefSheet.swift`, add a new section after the warnings section (after line 37, `WarningsSection`):

```swift
                    // Knowledge Health (lint results)
                    if !brief.lintResults.isEmpty {
                        KnowledgeHealthSection(lintResults: brief.lintResults)
                    }
```

Then add the `KnowledgeHealthSection` view at the bottom of the file:

```swift
// MARK: - Knowledge Health Section

struct KnowledgeHealthSection: View {
    let lintResults: [KnowledgeLintResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Knowledge Health")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
            }

            ForEach(lintResults) { result in
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(lintColor(severity: result.severity))
                        .frame(width: 3)
                        .cornerRadius(2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: lintIcon(type: result.lintType))
                                .font(.caption)
                                .foregroundStyle(lintColor(severity: result.severity))

                            Text(lintLabel(type: result.lintType))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(lintColor(severity: result.severity))
                                .textCase(.uppercase)
                        }

                        Text(result.content)
                            .font(.subheadline)
                            .foregroundStyle(.eeonTextPrimary)

                        if !result.relatedArticleNames.isEmpty {
                            Text(result.relatedArticleNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.eeonTextTertiary)
                        }
                    }
                }
                .padding(12)
                .background(Color.eeonCard)
                .cornerRadius(10)
            }
        }
    }

    private func lintColor(severity: String) -> Color {
        switch severity {
        case "urgent": return .red
        case "warning": return .orange
        default: return .blue
        }
    }

    private func lintIcon(type: String) -> String {
        switch type {
        case "stale_thread": return "clock.badge.exclamationmark"
        case "contradiction": return "exclamationmark.triangle"
        case "connection": return "link"
        case "gap": return "questionmark.circle"
        default: return "info.circle"
        }
    }

    private func lintLabel(type: String) -> String {
        switch type {
        case "stale_thread": return "Stale Thread"
        case "contradiction": return "Contradiction"
        case "connection": return "Connection"
        case "gap": return "Gap"
        default: return "Info"
        }
    }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "voice notes/DailyBriefSheet.swift"
git commit -m "feat: add Knowledge Health section to DailyBriefSheet"
```

---

### Task 9: Version Bump and Final Build Verification

**Files:**
- Modify: project version/build number

- [ ] **Step 1: Verify full build succeeds**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Bump version**

Increment the build number in the Xcode project. Check current version:

Run: `grep -A1 MARKETING_VERSION "voice notes.xcodeproj/project.pbxproj" | head -4`
Run: `grep -A1 CURRENT_PROJECT_VERSION "voice notes.xcodeproj/project.pbxproj" | head -4`

Bump the build number (e.g., 43 -> 44). Use sed to update all occurrences:

```bash
sed -i '' 's/CURRENT_PROJECT_VERSION = 43/CURRENT_PROJECT_VERSION = 44/g' "voice notes.xcodeproj/project.pbxproj"
```

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: Living Knowledge Base — KnowledgeArticle model, KnowledgeCompiler (Tier 1/2.5/3), article detail view, RAG integration, knowledge health in daily brief

Inspired by Andrej Karpathy's LLM Knowledge Base pattern. Adds cross-note compiled intelligence:
- KnowledgeArticle SwiftData model (person/project/topic types)
- KnowledgeCompiler service: mark dirty (Tier 1), recompile (Tier 2.5), lint (Tier 3)
- Knowledge cards in AIHomeView, full article detail view
- Article context injection in RAG pipeline
- Knowledge Health section in DailyBriefSheet
- Pro-only feature"
```
