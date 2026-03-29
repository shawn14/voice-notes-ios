# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EEON is a voice-first AI memory app (SwiftUI + SwiftData) for iOS. Users talk into a single button — the AI classifies whether it's a note or a question, transcribes via OpenAI Whisper, extracts structured intelligence (decisions, actions, commitments, people, topics, emotional tone), generates an enhanced version of what the user said, embeds the note for vector search, and lets users query their entire memory via natural language. Features CloudKit sync, Sign in with Apple, and StoreKit 2 subscriptions.

## Build Commands

```bash
# Build the app
xcodebuild -scheme "voice notes" -configuration Debug build

# Run UI tests (screenshot automation)
xcodebuild test -scheme "voice notes UITests" -configuration Debug

# Run specific UI test
xcodebuild test -scheme "voice notes UITests" -only-testing:"voice notes UITests/ScreenshotTests/testCaptureScreenshots"

# Clean build
xcodebuild clean -scheme "voice notes"
```

Open in Xcode 15+ and build/run from there for development.

## Setup

1. Copy `voice notes/APIKeys.template` to `voice notes/APIKeys.swift`
2. Add your OpenAI API key to `APIKeys.swift`
3. Configure signing team in Xcode

## Architecture

### Single-Button Interaction Model (IntentClassifier)

The app presents one record button. `IntentClassifier` analyzes the transcription to determine if the user is:
- **Capturing a note** — routed to extraction + embedding pipeline
- **Asking a question** — routed to RAG pipeline for answer synthesis

This removes all cognitive overhead from the user. They just talk.

### RAG Pipeline (Embedding → Vector Search → GPT Synthesis)

1. **On note save**: `EmbeddingService` generates an embedding vector via OpenAI embeddings API (cloud-based, not on-device) and stores it in the `embeddingData` field on the Note model.
2. **On query**: `VectorSearchService` performs cosine similarity search across all note embeddings using Core Data with Accelerate framework for fast vector math.
3. **Synthesis**: `RAGService` takes the top-k relevant notes and sends them as context to GPT for natural language answer generation.

### Enhanced Notes

When a note is saved, the AI generates an `enhancedNoteText` — a cleaned-up, expanded version of what the user said. This turns rambling voice input into clear, readable prose while preserving the user's intent and meaning. The original transcription is always preserved.

### Three-Tier Intelligence System (IntelligenceService.swift)

The app uses a tiered AI refresh strategy to minimize API calls:

- **Tier 1 (Instant)**: On note save — Whisper transcription + GPT extraction + embedding generation. Updates `StatusCounters` immediately.
- **Tier 2 (Session)**: On app foreground — local aggregation only, zero API calls. Cached 15-60 min. Produces `SessionBrief`.
- **Tier 3 (Daily)**: Once per calendar day — generates `DailyBrief`. One API call per day.

App-active refresh is triggered in `voice_notesApp.swift` via `scenePhase` change, which calls `IntelligenceService` for Tier 2 and Tier 3 checks.

### Key Services

| Service | Purpose |
|---------|---------|
| `IntelligenceService` | Orchestrates AI processing across all tiers |
| `SummaryService` | OpenAI API integration (extraction, analysis) — static methods, no instance state |
| `TranscriptionService` | Whisper API for audio transcription (`actor` for thread safety) |
| `EmbeddingService` | Generates OpenAI embedding vectors for notes on save |
| `VectorSearchService` | Cosine similarity search across note embeddings (Accelerate framework) |
| `IntentClassifier` | Classifies voice input as note capture vs question/query |
| `RAGService` | Retrieval-augmented generation — vector search + GPT synthesis for answering questions |
| `AuthService` | Sign in with Apple authentication |
| `SubscriptionManager` | StoreKit 2 subscription management |
| `UsageService` | Free tier usage tracking (10 free notes, then paywall) |
| `StatusCounters` | Real-time UI counters, persisted to UserDefaults |
| `CloudKitShareService` | Note sharing via CloudKit |
| `ProjectMatcher` | Three-layer project matching (alias → fuzzy → AI) |

### Data Models (SwiftData)

All models registered in `voice_notesApp.init()` schema:
`Note`, `Tag`, `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`, `KanbanItem`, `KanbanMovement`, `WeeklyDebrief`, `Project`, `DailyBrief`

**Note extraction fields** (stored on the Note model):
- `topicsJSON` — extracted topic tags as JSON
- `emotionalTone` — detected emotional tone of the note
- `enhancedNoteText` — AI-expanded, cleaned-up version of what the user said
- `embeddingData` — vector embedding for semantic search

**Adding a new model requires updating the schema array in `voice_notesApp.swift`.**

### View Hierarchy

- `voice_notesApp.swift` → onboarding gate → `AIHomeView` (main hub)
- `AIHomeView.swift` — Single-button voice capture, query interface, recent notes
- `AssistantView.swift` — AI assistant / query response view
- `NoteDetailView.swift` — Note viewing with enhanced text and extraction chips
- `NoteEditorView.swift` — Note editing with transcription and extraction
- `ExtractionChipsView.swift` — Visual chips for extracted decisions, actions, commitments, people
- `PaywallView.swift` — Subscription purchase flow with StoreKit 2
- `OnboardingPaywallView.swift` — First-launch onboarding with paywall

**Views still in codebase but removed from navigation** (legacy v1 dashboard views):
- `CommandCenterView.swift` — Former metrics dashboard
- `KanbanBoardView.swift` — Former OODA workflow board
- `HomeView.swift` — Former notes list / home hub
- `ReportsView.swift`, `PersonalizedReports.swift` — Former report views
- `DecisionLogView.swift`, `PeopleView.swift`, `CompletedItemsView.swift` — Former detail views
- `ProjectBrowserView.swift`, `ProjectDetailView.swift` — Former project views
- `WeeklyDebriefView.swift`, `MyEEONView.swift` — Former summary views

These are kept in the codebase for potential future use but are not accessible from the current navigation flow.

## Key Patterns

### Observable Singletons
`@Observable` classes with `static let shared`: `AuthService`, `SubscriptionManager`, `IntelligenceService`, `UsageService`, `StatusCounters`. Views access these directly (not via `@Environment`).

### SwiftData + CloudKit Constraints
- **CloudKit requires optional relationships.** `Tag.notes` is `[Note]?` with a non-optional computed `tags` accessor on `Note` that wraps the optional.
- **JSON-encoded complex fields.** SwiftData can't store nested types, so `ExtractedSubject`, `MissingInfoItem` are stored as JSON strings with `fromJSON`/`toJSON` computed property accessors on `Note`.
- **Foreign keys over relationships.** Extracted items (`ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`) use `sourceNoteId: UUID?` instead of `@Relationship` to prevent cascade deletes of AI intelligence when notes are deleted.
- **Enum fields stored as raw strings.** `Note.intentType` stores `NoteIntent.rawValue`, `Note.column` stores `KanbanColumn.rawValue`, etc. — with computed property getters/setters for typed access.
- **Container fallback hierarchy.** CloudKit → local SQLite → delete store and recreate. See `voice_notesApp.init()`.

### Monetization Flow
- `UsageService` tracks note count via UserDefaults (10 free notes limit)
- `canCreateNote` gates note creation; `shouldShowPaywall()` triggers `PaywallView`
- `SubscriptionManager` handles StoreKit 2 products (`pro_monthly`, `pro_annual`)
- Pricing: $9.99/mo, $79.99/yr
- `isPro` requires both active subscription AND `AuthService.shared.isSignedIn`

### OpenAI API Integration
Direct URLSession calls (no SDK) in `SummaryService.swift`:
- **Whisper**: `POST /v1/audio/transcriptions` — audio chunked if >25MB (10-min segments)
- **GPT**: `POST /v1/chat/completions` with `gpt-4o-mini` for intent extraction and daily briefs
- **Embeddings**: `POST /v1/embeddings` via `EmbeddingService` for note vector generation
- API key loaded from `APIKeys.openAI`

### Audio Recording
`AudioRecorder.swift` records to Documents directory: AAC `.m4a`, 44.1kHz, mono. Files stored as `{UUID}.m4a`, referenced by `note.audioFileName`.

## CloudKit & Entitlements

- Container: `iCloud.aivoiceeeon`
- URL scheme: `voicenotes://share/{id}` for shared notes
- Separate entitlements for Debug (`voice notes.entitlements`) and Release (`voice notesRelease.entitlements`)

## StoreKit Products

- `pro_monthly` ($9.99), `pro_annual` ($79.99)
- Configured in `Products.storekit`

## Testing

UI tests only (no unit tests). Screenshot automation via Fastlane:
- Launch args: `-UITestMode`, `-SkipOnboarding` for test-specific behavior
- `AuthService.debugSignIn()` available in DEBUG builds

## Dead Code

`ContentView.swift` is unused (noted in the file itself). The actual entry point is `voice_notesApp` → `AIHomeView`. Many v1 dashboard views remain in the codebase but are disconnected from navigation (see View Hierarchy section above).
