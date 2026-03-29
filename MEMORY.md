# EEON Product Memory

Key product decisions and context from the v2 development cycle.

## The v2 Pivot

EEON v1 was "voice notes with dashboards" — a command center, kanban board, reports, project browser, weekly debriefs, and a dozen navigation destinations. Users had too many screens and not enough reason to come back.

v2 pivots to "voice-first AI memory" — one button, talk, AI remembers, ask anything. The core insight: the value isn't in dashboards showing what you said, it's in being able to ask questions about what you said and getting real answers.

## Single-Button Interaction Model

The entire app UI centers on a single record button. `IntentClassifier` analyzes each transcription to determine whether the user is capturing a note or asking a question. Notes go through the extraction + embedding pipeline. Questions go through the RAG pipeline. The user never has to choose a mode — the AI handles routing.

This was a deliberate decision to eliminate cognitive overhead. Voice apps fail when they make users think about categories, folders, or modes before speaking.

## Ghost Text Coaching System

Subtle placeholder text guides users on what to say, appearing in three contexts:
1. **First 5 sessions** — teaches the basic mental model ("Just talk — say what's on your mind")
2. **After gaps** — re-engages returning users ("Welcome back — what's happened since last time?")
3. **After 10+ notes with no queries** — teaches the query feature ("Try asking: what decisions have I made this week?")

Ghost text fades after the user demonstrates they understand the interaction. This replaces a traditional onboarding tutorial.

## Enhanced Notes

The `enhancedNoteText` field stores an AI-expanded version of what the user said. Raw voice transcriptions are often rambling, repetitive, and hard to read later. The enhanced version preserves intent and meaning but produces clear, readable prose. The original transcription is always kept — enhanced text is additive, not destructive.

## Kill List (Views Removed from Navigation)

The following views were removed from navigation in v2 but kept in the codebase:
- **CommandCenterView** — metrics dashboard. Removed because passive dashboards don't drive retention.
- **KanbanBoardView** — OODA workflow board. Too complex for a voice-first app; users never engaged with drag-and-drop.
- **HomeView** (original) — notes list with filter tabs. Replaced by AIHomeView with the single-button model.
- **ReportsView / PersonalizedReports** — scheduled reports. Replaced by on-demand queries via RAG.
- **DecisionLogView / PeopleView / CompletedItemsView** — detail drill-downs. Info now accessible via natural language queries.
- **ProjectBrowserView / ProjectDetailView** — project organization. Removed because manual project management adds friction; topics are auto-extracted instead.
- **WeeklyDebriefView / MyEEONView** — summary views. Replaced by proactive alerts and on-demand queries.

Rationale: every removed view was either a passive display (users look once and leave) or required manual organization (users don't bother). The replacement — asking questions in natural language — is both easier and more powerful.

## Pricing Change

**v1**: $9.99/mo, $79.99/yr, 5 free notes
**v2**: $9.99/mo, $79.99/yr, 10 free notes (pricing unchanged, free tier doubled)

Rationale for keeping pricing:
- $9.99/mo is already competitive for an AI-powered personal tool
- $79.99/yr annual discount (33% off monthly) incentivizes annual commitment
- 10 free notes (up from 5) gives users enough runway to experience the value of queries and enhanced notes before hitting the paywall
- At 10 notes, users have enough data density for RAG queries to feel magical

## Competitive Positioning

| Competitor | Their angle | EEON's differentiation |
|------------|-------------|----------------------|
| **Otter.ai** | Meeting transcription + collaboration | EEON is personal memory, not meeting notes. Single-user, not team. |
| **Letterly** | Voice-to-text with templates | EEON adds AI understanding — extraction, queries, enhanced notes. Letterly is just transcription with formatting. |
| **Audionotes** | Voice notes with AI summaries | EEON goes beyond summaries to full RAG queries across your entire history. Audionotes can't answer "what did I decide about X?" |
| **Voicenotes.com** | Voice journal with AI chat | Closest competitor. EEON differentiates on extraction quality (decisions/actions/commitments), enhanced notes, proactive alerts, and native iOS performance. |

Key positioning: EEON is not a transcription app. It's an AI memory. The competitor is not other voice apps — it's the act of forgetting.

## Key Technical Decisions

- **Cloud embeddings (OpenAI API), not on-device**: On-device embedding models are too large and too slow for real-time use on older iPhones. Cloud embeddings via OpenAI are fast, high-quality, and the marginal API cost per note is negligible.
- **Accelerate framework for vector search**: Apple's Accelerate framework provides SIMD-optimized vector math for cosine similarity. Fast enough for thousands of notes without needing a dedicated vector database. Keeps the architecture simple — embeddings stored as Data blobs in SwiftData, search runs locally.
- **SwiftData over Core Data**: Continued from v1. SwiftData's Swift-native API and CloudKit integration make it the right choice for a modern SwiftUI app despite some rough edges.
- **No dedicated vector database**: At the scale of personal voice notes (hundreds to low thousands), brute-force cosine similarity via Accelerate is fast enough. Adding SQLite-vec or similar would add complexity without meaningful performance gain.
- **GPT-4o-mini for all AI tasks**: Cost-effective, fast, and good enough for extraction, enhancement, intent classification, and RAG synthesis. No need for full GPT-4o at this stage.
