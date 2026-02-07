# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice Notes is a native iOS app (SwiftUI + SwiftData) that records voice notes, transcribes them via OpenAI Whisper, and uses GPT to extract actionable insights (decisions, actions, commitments). Features CloudKit sync, Sign in with Apple, and StoreKit 2 subscriptions.

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

### Three-Tier Intelligence System (IntelligenceService.swift)

The app uses a tiered AI refresh strategy to minimize API calls:

- **Tier 1 (Instant)**: On note save — Whisper transcription + GPT extraction. One API call per note. Updates `StatusCounters` immediately.
- **Tier 2 (Session)**: On app foreground — local aggregation only, zero API calls. Cached 15-60 min. Produces `SessionBrief`.
- **Tier 3 (Daily)**: Once per calendar day — generates `DailyBrief`. One API call per day.

App-active refresh is triggered in `voice_notesApp.swift` via `scenePhase` change, which calls `IntelligenceService` for Tier 2 and Tier 3 checks.

### Key Services

| Service | Purpose |
|---------|---------|
| `IntelligenceService` | Orchestrates AI processing across all tiers |
| `SummaryService` | OpenAI API integration (extraction, analysis) — static methods, no instance state |
| `TranscriptionService` | Whisper API for audio transcription (`actor` for thread safety) |
| `AuthService` | Sign in with Apple authentication |
| `SubscriptionManager` | StoreKit 2 subscription management |
| `UsageService` | Free tier usage tracking (5 free notes, then paywall) |
| `StatusCounters` | Real-time UI counters, persisted to UserDefaults |
| `CloudKitShareService` | Note sharing via CloudKit |
| `ProjectMatcher` | Three-layer project matching (alias → fuzzy → AI) |

### Data Models (SwiftData)

All models registered in `voice_notesApp.init()` schema:
`Note`, `Tag`, `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`, `KanbanItem`, `KanbanMovement`, `WeeklyDebrief`, `Project`, `DailyBrief`

**Adding a new model requires updating the schema array in `voice_notesApp.swift`.**

### View Hierarchy

- `voice_notesApp.swift` → onboarding gate → `HomeView` (main hub)
- `HomeView.swift` — Notes list, recording, filter tabs (`NoteFilter` enum), project browsing
- `NoteEditorView.swift` — Note editing with transcription and extraction
- `CommandCenterView.swift` — Metrics dashboard
- `KanbanBoardView.swift` — OODA workflow board (Thinking → Decided → Doing → Waiting → Done)
- `PaywallView.swift` — Subscription purchase flow with StoreKit 2

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
- `UsageService` tracks note count via UserDefaults (5 free notes limit)
- `canCreateNote` gates note creation; `shouldShowPaywall()` triggers `PaywallView`
- `SubscriptionManager` handles StoreKit 2 products (`pro_monthly`, `pro_annual`)
- `isPro` requires both active subscription AND `AuthService.shared.isSignedIn`

### OpenAI API Integration
Direct URLSession calls (no SDK) in `SummaryService.swift`:
- **Whisper**: `POST /v1/audio/transcriptions` — audio chunked if >25MB (10-min segments)
- **GPT**: `POST /v1/chat/completions` with `gpt-4o-mini` for intent extraction and daily briefs
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

`ContentView.swift` is unused (noted in the file itself). The actual entry point is `voice_notesApp` → `HomeView`.
