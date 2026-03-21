# AI Reports Screen — Design Spec

## Overview

A dedicated chat screen for account-level AI intelligence. Accessible from AIHomeView's top-right header. Combines pre-built report templates (scrollable pills) with free-form chat, pulling from the user's complete note history. Reports are ephemeral with save-on-demand.

## Entry Point

- New SF Symbol button (e.g. `sparkles` or `brain.head.profile`) in AIHomeView top-right header, next to the avatar
- Opens `ReportsView` as a full-screen navigation destination

## Screen Layout

```
┌─────────────────────────────┐
│  ← AI Reports               │
├─────────────────────────────┤
│ [📊 CEO] [🔍 SWOT] [🎯 Goals] [📅 Weekly] [👥 People] [📁 Projects] [📋 Decisions] [✅ Actions] [✨ Custom] →
├─────────────────────────────┤
│                             │
│         ✨                  │
│   Ask anything about        │
│     your notes              │
│   or tap a report above     │
│                             │
│                             │
│   (chat messages appear     │
│    here as conversation     │
│    progresses)              │
│                             │
├─────────────────────────────┤
│ [Ask about your notes...] ⬆ │
└─────────────────────────────┘
```

### Components

1. **Nav bar** — back button + "AI Reports" title + clear chat button
2. **Pill row** — single horizontal `ScrollView(.horizontal)` with tappable pills. Each pill has an emoji icon + short label, colored background per report type.
3. **Chat area** — `ScrollView` with `LazyVStack` of chat messages. User messages right-aligned, assistant messages left-aligned with markdown rendering.
4. **Input bar** — bottom-pinned `TextField` with send button, identical to AssistantView pattern.

## Report Types

| Type | Emoji | Pill Label | System Prompt Summary |
|------|-------|------------|----------------------|
| CEO Report | 📊 | CEO Report | High-level highlights, strategic implications, risks, recommended actions across all projects and notes |
| SWOT Analysis | 🔍 | SWOT | Strengths, weaknesses, opportunities, threats derived from decisions, actions, projects, and commitments |
| Goal Tracker | 🎯 | Goals | Progress against inferred goals, what's on track, what's drifting, suggested course corrections |
| Weekly Summary | 📅 | Weekly | What happened this week — new notes, decisions made, actions completed, items that stalled |
| People Report | 👥 | People | Who you owe things to, who owes you, open commitments, relationship health |
| Project Status | 📁 | Projects | Per-project health, active items, blockers, momentum direction, staleness |
| Decision Log | 📋 | Decisions | All decisions with status (Active/Pending/Superseded/Reversed), ones that need revisiting |
| Action Audit | ✅ | Actions | Open actions, overdue items, blocked work, items without owners |
| Custom | ✨ | Custom | Opens a prompt sheet for user to type a custom question/report request |

## Behavior

### Pill Interaction
- Tapping a pill inserts a pre-written user message (e.g. "Generate a CEO Report across all my notes and projects") and immediately triggers GPT generation
- The pill message appears as a user chat bubble, response as assistant bubble
- Multiple pills can be tapped in sequence (builds conversation)
- "Custom" pill simply focuses the text input bar with placeholder "What would you like to know?" — no separate sheet needed since the input bar already supports free-form text

### Chat Interaction
- Typing in the input bar and sending works identically to AssistantView
- Full conversation history is sent with each request (so GPT has context of prior messages)
- Auto-scrolls to newest message

### Response Actions
- **Copy** button on each assistant message (copies markdown text to clipboard)
- **Save as Note** button on each assistant message — creates a new `Note` with:
  - `title`: report type name + date (e.g. "CEO Report — Mar 17, 2026")
  - `content`: the generated markdown text
  - `intentType`: `.idea`
  - No audio, no transcription
- **Clear Chat** button in nav bar — resets all messages

### Empty State
- Centered sparkles icon
- "Ask anything about your notes"
- "or tap a report above"

## Data Context

### What Gets Sent to GPT

A structured context document built from all SwiftData records:

```
ACCOUNT CONTEXT:
================

NOTES (N total):
- [Date] Title: first 200 chars of transcript/content
- ...

PROJECTS (N total):
- ProjectName: N notes, N open actions, last activity: Date, status: active/stalled
- ...

DECISIONS (N total):
- [Date] Decision content (Status: Active/Pending/Superseded) — Project: X
- ...

ACTIONS (N total):
- [Date] Action content — Owner: X, Deadline: X, Status: open/completed/blocked
- ...

COMMITMENTS (N total):
- [Date] Who: what — Status: open/completed
- ...

PEOPLE (N total):
- Name: N mentions, N open commitments, last mentioned: Date
- ...

KANBAN ITEMS (N total):
- [Column] Content — Type: X, Days since update: N
- ...
```

### Context Building Strategy

- Context is built on `@MainActor` (SwiftData `ModelContext` is not `Sendable`). The caller builds the context string synchronously on the main thread, then passes the resulting `String` to the async API call.
- New static method: `SummaryService.buildAccountContext(notes:projects:decisions:actions:commitments:people:kanbanItems:)` → `String` — takes pre-fetched arrays of value data, not `ModelContext` directly. The view fetches via `@Query` and passes the data in.
- Each note summarized to first 150 characters (keeps token count manageable)
- Hard cap: total context string capped at **12,000 characters** (~3,000 tokens). Truncation priority: notes are trimmed first (most recent 50), then kanban items. Decisions, actions, commitments, projects, and people are always included in full (they are compact).
- For conversation history: keep last **10 messages** in the API payload. Older messages are still displayed in the UI but not sent to GPT.

### System Prompt Structure

Each report type has a specific system prompt that includes:
1. Role definition: "You are an AI assistant analyzing a founder's complete voice notes history"
2. The account context (built above)
3. Report-specific instructions (e.g. "Generate a SWOT analysis...")
4. Format instructions: "Use markdown. Be concise and actionable."

### API Call

- Same pattern as AssistantView: URLSession + `gpt-4o-mini`, using `APIKeys.openAI` directly in the view (matching AssistantView convention)
- Temperature: 0.7 (same as AssistantView for creative/analytical output)
- Max tokens: 2000
- Last 10 conversation messages included in messages array (older messages displayed but not sent)
- **Pills disabled while `isLoading` is true** — prevents concurrent requests. Tapping a pill while a response is streaming does nothing.

## Monetization

### Free Tier Gating
- Free users get **2 report generations** before paywall
- Tracked via new counter in `UsageService`: `reportGenerationCount` (UserDefaults)
- `canGenerateReport` computed property checks count < 2 OR `UsageService.shared.isPro`
- When limit hit: show `PaywallView` sheet (existing component)
- Counter persists across app launches (UserDefaults), does not reset

### Pro Users
- Unlimited report generations
- No restrictions

## New Files

| File | Purpose |
|------|---------|
| `ReportsView.swift` | Main chat screen — modeled on AssistantView |
| `ReportPrompts.swift` | Enum of report types with pills config + system prompts |

## Modified Files

| File | Change |
|------|--------|
| `AIHomeView.swift` | Add reports button to header, navigation destination |
| `SummaryService.swift` | Add `buildAccountContext(notes:projects:decisions:actions:commitments:people:kanbanItems:)` static method |
| `UsageService.swift` | Add `reportGenerationCount` counter + `canGenerateReport` |

## No New Data Models

- Chat messages stored in-memory as `[ChatMessage]` (same struct as AssistantView)
- Saved reports become `Note` objects via existing save pattern
- No new SwiftData models required
- No schema migration needed

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No notes yet | Show empty state: "Record some notes first to generate reports" |
| API failure | Alert with error message (existing pattern) |
| Very long response | ScrollView handles naturally |
| Token limit exceeded | Truncate context to most recent 100 notes (decisions/actions always included) |
| Not signed in | Reports button hidden or disabled (same as other AI features) |
| Free user hits limit | PaywallView sheet |
| Rapid pill tapping | Pills disabled while isLoading — only one request at a time |
| Long conversation history | Only last 10 messages sent to GPT; older messages visible in UI |
