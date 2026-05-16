# RAG Streaming + Answer Cache — Follow-up to Chat-with-Your-Notes Phase 1

**Date filed:** 2026-05-16
**Parent plan:** `~/.claude/plans/okay-now-can-you-lucky-cocoa.md` (approved + landed Days 1-3)
**Motivation:** Days 1-3 of the cost-efficient chat-with-your-notes plan landed (query router + 5 route handlers + route badge UI). The two remaining polish layers — streaming and answer caching — were deferred to keep the initial ship clean and low-risk. This plan captures both so they can be picked up in a focused follow-up session.

## What's already shipped (don't redo)

Reference commits live on `origin/main` of `shawn14/voice-notes-ios` after the Phase 1 ship. Specifically:

- `IntentClassifier.swift` has `QuestionRoute` enum + `classifyQuestionRoute(query:articleNames:)` with deterministic fast-paths (time-range regex, top-N regex, entity-name match, trends keywords) and an LLM fallback (`gpt-4o-mini`, 4-token output, ~$0.00003/query).
- `RAGService.swift` has 5 route handlers (`answerRanking`, `answerTrends`, `answerTimeRange`, `answerEntity`, `answerSemantic`) called by a dispatcher in `answerQuestion(...)`. Shared helpers `callLLM(...)` and `parseAnswerAndFollowUps(...)`.
- `AnswerSheet.swift` has the new `@Query private var projects: [Project]` + `@Query private var dailyBriefs: [DailyBrief]`, passes both through, and renders a small "From: ..." route badge via `response.route.badgeText`.

`RAGResponse` already has the `route: QuestionRoute` field. That's the hook streaming uses.

## Phase 4 — Streaming

### Goal

First-token latency drops from ~3-4s (current batched) to ~400ms by streaming OpenAI SSE chunks straight to the UI. No token-cost change — this is purely a perceived-latency win.

### Approach

The cleanest refactor that doesn't duplicate per-route prompt code:

1. Extract each route handler's prompt-building into a private `prepareXxx(...) -> RoutePreparation` function returning:

    ```swift
    struct RoutePreparation {
        let systemPrompt: String
        let userPrompt: String
        let route: QuestionRoute
        let sourceNotes: [Note]
        let defaultFollowUps: [String]
        let maxTokens: Int
        let temperature: Double
    }
    ```

2. Keep the existing `answerQuestion(...)` entry point. Internally it becomes:

    ```swift
    let prep = try await prepareForRoute(query:..., route: route)
    let raw = try await callLLM(systemPrompt: prep.systemPrompt, ...)
    let (answer, parsedFollowUps) = parseAnswerAndFollowUps(raw)
    return RAGResponse(answer: answer, sourceNotes: prep.sourceNotes,
                      suggestedFollowUps: parsedFollowUps.isEmpty ? prep.defaultFollowUps : parsedFollowUps,
                      route: prep.route)
    ```

3. Add a new public entry point:

    ```swift
    struct StreamingAnswer {
        let route: QuestionRoute
        let sourceNotes: [Note]
        let defaultFollowUps: [String]
        let stream: AsyncThrowingStream<String, Error>
    }

    func streamAnswer(query:..., dailyBriefs:...) async throws -> StreamingAnswer {
        let prep = try await prepareForRoute(...)
        let stream = streamLLM(systemPrompt: prep.systemPrompt,
                              userPrompt: prep.userPrompt,
                              maxTokens: prep.maxTokens,
                              temperature: prep.temperature)
        return StreamingAnswer(route: prep.route, sourceNotes: prep.sourceNotes,
                              defaultFollowUps: prep.defaultFollowUps, stream: stream)
    }
    ```

4. Add `streamLLM(systemPrompt:userPrompt:model:maxTokens:temperature:) -> AsyncThrowingStream<String, Error>` using `URLSession.bytes` + SSE parse:

    ```swift
    AsyncThrowingStream { continuation in
        Task {
            // POST with "stream": true
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { continuation.finish(); return }
                if let chunk = try? JSONDecoder().decode(StreamChunk.self,
                                       from: Data(payload.utf8)),
                   let delta = chunk.choices.first?.delta.content {
                    continuation.yield(delta)
                }
            }
            continuation.finish()
        }
    }
    ```

5. Add a public `finalize(streaming: StreamingAnswer, accumulated: String) -> RAGResponse` helper that parses the final follow-ups from the accumulated stream text and returns a full `RAGResponse`.

### `AnswerSheet.swift` changes

- Add a new state case `.streaming(question: String, partial: String, sourceNotes: [Note], route: QuestionRoute)` next to the existing `loading | answer | error` cases.
- `runQuery` becomes:

    ```swift
    Task {
        do {
            let streaming = try await RAGService.shared.streamAnswer(...)
            await MainActor.run {
                state = .streaming(question: trimmed, partial: "",
                                   sourceNotes: streaming.sourceNotes,
                                   route: streaming.route)
            }
            var accumulated = ""
            for try await token in streaming.stream {
                accumulated += token
                await MainActor.run {
                    if case .streaming(let q, _, let s, let r) = state {
                        state = .streaming(question: q, partial: accumulated,
                                           sourceNotes: s, route: r)
                    }
                }
            }
            let final = RAGService.shared.finalize(streaming: streaming, accumulated: accumulated)
            await MainActor.run { state = .answer(question: trimmed, response: final) }
        } catch {
            await MainActor.run { state = .error(error.localizedDescription) }
        }
    }
    ```

- Add a `streamingView(question:partial:route:sources:)` sub-view that renders the partial text + route badge (sources can show but be tappable only after finalization).

### Acceptance

- First token appears in `AnswerSheet` within 600ms of submit on a fast network.
- Tokens render incrementally without flicker.
- On stream completion, follow-ups parse correctly and the state transitions cleanly to `.answer`.
- If the stream errors mid-flight, state transitions to `.error` with what was accumulated discarded.
- Cancellation: navigating away from the sheet cancels the underlying `URLSession` task within 100ms.

## Phase 5 — Answer Cache

### Goal

Asking the same question twice in a session returns instantly (no API call, no waiting). Cache invalidates automatically when underlying data changes.

### Approach

Single Swift `actor` for thread-safe access. In-memory only — answers are conversational and cheap enough that cold-cache cost ($0.0007/query) doesn't justify SwiftData persistence.

```swift
actor RAGResponseCache {
    static let shared = RAGResponseCache()

    private struct Entry {
        let response: RAGResponse
        let createdAt: Date
    }

    private var store: [String: Entry] = [:]
    private var lruKeys: [String] = []
    private let maxEntries = 50

    func get(key: String) -> RAGResponse? {
        guard let entry = store[key] else { return nil }
        // Bump LRU
        if let idx = lruKeys.firstIndex(of: key) { lruKeys.remove(at: idx) }
        lruKeys.append(key)
        return entry.response
    }

    func put(key: String, response: RAGResponse) {
        store[key] = Entry(response: response, createdAt: Date())
        lruKeys.append(key)
        while lruKeys.count > maxEntries, let oldest = lruKeys.first {
            store.removeValue(forKey: oldest)
            lruKeys.removeFirst()
        }
    }

    func clear() { store.removeAll(); lruKeys.removeAll() }
}
```

### Key construction

```swift
let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
let dataVersion = await DataVersionTracker.shared.current()  // see below
let key = sha256("\(normalized)|\(route.label)|\(dataVersion)")
```

### `DataVersionTracker`

Lightweight singleton that fingerprints the underlying corpus:

```swift
actor DataVersionTracker {
    static let shared = DataVersionTracker()
    private var cached: String?
    private var lastComputed: Date = .distantPast

    func current() -> String {
        // Recompute at most once every 30 seconds
        let now = Date()
        if let cached, now.timeIntervalSince(lastComputed) < 30 {
            return cached
        }
        // Hash of (latest Note.updatedAt, latest DailyBrief.generatedAt,
        //          latest KnowledgeArticle.updatedAt). Pull via ModelContainer.
        let signature = computeSignature()
        cached = signature
        lastComputed = now
        return signature
    }
}
```

Compute signature by fetching one row each — `Note.updatedAt desc limit 1`, same for `DailyBrief`, same for `KnowledgeArticle`. Hash those three timestamps. Cheap (3 indexed reads). Cached for 30s to avoid hot-path overhead.

### Cache integration in `answerQuestion`

```swift
func answerQuestion(...) async throws -> RAGResponse {
    let route = try await IntentClassifier.shared.classifyQuestionRoute(...)
    let dataVersion = await DataVersionTracker.shared.current()
    let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let cacheKey = sha256("\(normalized)|\(route.label)|\(dataVersion)")

    if let cached = await RAGResponseCache.shared.get(key: cacheKey) {
        return cached
    }

    let response = // ... existing route dispatch ...
    await RAGResponseCache.shared.put(key: cacheKey, response: response)
    return response
}
```

### Sub-router micro-cache

In `IntentClassifier`, add a simple in-memory `[String: QuestionRoute]` dict keyed by normalized query, max 200 entries, session lifetime. The router's LLM fallback is $0.00003/query — micro-cache saves negligible cost but ~100ms latency. Worth doing.

### Cache invalidation triggers

The `dataVersion` signature auto-invalidates when any of the three watched tables changes. No manual invalidation needed in the normal flow. App background after 1h clears the whole cache (the cache is in-memory anyway, so this is mostly belt-and-suspenders for memory pressure).

### Acceptance

- Ask "top 10 projects" twice in 60 seconds — second call returns in <50ms with no API hit (log "cache hit").
- Create a new note, then ask same question — cache miss (log "cache miss: dataVersion changed").
- Cache size stays bounded at 50 entries; oldest entries evict on overflow.
- Background the app for 1h+, return, ask cached question — cache cold; API call made.

## SOW (estimate)

- **Day 1** — Extract per-route prep functions. Refactor existing route handlers to call shared finalizer. Build verifies clean.
- **Day 2** — Implement `streamLLM` + `streamAnswer` + `finalize`. Manual smoke test that tokens stream over network.
- **Day 3** — Add `.streaming` state to `AnswerSheet`. Render incrementally. Cancellation handling.
- **Day 4** — `RAGResponseCache` actor + `DataVersionTracker` actor + `sha256` helper. Wire into `answerQuestion`.
- **Day 5** — Sub-router micro-cache on `IntentClassifier`. Telemetry: log cache hit/miss + route distribution.
- **Day 6** — Cost ledger (sum estimated $ per session, expose in Settings → CloudKit diagnostics or new Settings → Usage). Manual integration test across all 4 query types.

## Critical files

- `/Users/shawncarpenter/projects/voice notes/voice notes/RAGService.swift` (refactor to prep + executor pattern, add `streamLLM`, add `streamAnswer`, add `finalize`)
- `/Users/shawncarpenter/projects/voice notes/voice notes/AnswerSheet.swift` (new `.streaming` state, incremental render, cancellation)
- `/Users/shawncarpenter/projects/voice notes/voice notes/IntentClassifier.swift` (sub-router micro-cache)
- New: `voice notes/RAGResponseCache.swift` (actor)
- New: `voice notes/DataVersionTracker.swift` (actor)

## Risks / open questions

- **`URLSession.bytes` on iOS 17+ behavior**: should be fine; if any quirks emerge, fall back to a manual `URLSessionDataTask` + delegate streaming.
- **OpenAI rate limits during streaming retries**: streaming connections that fail mid-flight could exhaust retries faster. Add a single retry on transient errors only.
- **Cache key collisions**: SHA256 of `query|route|dataVersion` is overkill-collision-safe at this volume, but normalize aggressively (strip punctuation, collapse whitespace) so semantically-equivalent queries hit the same key.
- **CloudKit + cache + multi-device**: if the user has EEON on iPhone + iPad, each device has its own in-memory cache. Acceptable. CloudKit-syncing the cache would be wrong — answers are ephemeral.

## References

- Parent plan with full architecture context: `~/.claude/plans/okay-now-can-you-lucky-cocoa.md`
- Memory rule that constrains this: `feedback_never_delete_user_notes.md` — caching is purely read-side, no risk to notes.
