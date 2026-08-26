# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EEON is a voice-first AI memory app (SwiftUI + SwiftData) for iOS. Users talk into a single button — the AI classifies whether it's a note or a question, transcribes via OpenAI Whisper, extracts structured intelligence (decisions, actions, commitments, people, topics, emotional tone), generates an enhanced version of what the user said, embeds the note for vector search, and lets users query their entire memory via natural language. Features CloudKit sync, Sign in with Apple, StoreKit 2 subscriptions, a Home Screen / Lock Screen widget, and a Share Extension for ingesting URLs and text from other apps.

## Build Targets

The Xcode project has three targets, all with spaces or capitals in the scheme name (always quote them):

| Target | Scheme | Purpose |
|--------|--------|---------|
| Main app | `voice notes` | The iOS app itself |
| Widget extension | `VoiceNotesWidgetExtension` | Home Screen + Lock Screen widgets, App Intent for one-tap recording |
| Share extension | `EEONShareExtension` | Receive URLs/text from other apps; queue them for ingestion |
| UI tests | `voice notes UITests` | Fastlane screenshot automation only — no unit tests |

The widget and share extension share state with the main app via the App Group `group.com.eeon.voicenotes` (see `SharedDefaults.swift`, which is duplicated into each target by file reference).

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

### Today's 3 / Daily Intention Loop (`DailyIntention`, `TodaysThreeSection`)

The primary daily UX is intention-setting: the user picks 3 things they want to focus on today. `DailyIntention` is a SwiftData model keyed by date; `TodaysThreeSection` renders the picker on the home screen. This is the core accountability loop and should not be hidden behind navigation.

### Knowledge Base / Living Articles (`KnowledgeArticle`, `KnowledgeEvent`, `KnowledgeCompiler`)

Notes that touch the same topic compound into evergreen articles. `KnowledgeCompiler` periodically re-synthesizes a `KnowledgeArticle` from all `KnowledgeEvent`s on a topic, so the article reflects the *current* state of the user's thinking rather than a stale draft. `ContextAssembler` primes a cache of compiled articles at app launch so RAG queries pull from compiled knowledge before raw notes.

`KnowledgeArticle.kind` has seven cases: `person`, `project`, `topic`, `self` (the user's profile), `purpose` (what EEON is *for* this user), `reference` (uploaded canon), and `index` (singleton wiki overview).

### Tune EEON / Persona Platform (`.purpose` article as personalization root)

`TuneConversationView` (presented by the Tune EEON button — `IdentityView` is preview-only, do not route to it) lets the user dictate two fields: **profile** and **purpose**. Saving persists each as a seed Note and force-compiles the corresponding article. The compiled `.purpose` article then carries the entire personalization state as JSON fields:

- `homeLayoutJSON` — LLM-compiled home screen layout. The section catalog (`HomeSectionKind` in `HomeLayout.swift`) is **intentionally closed**: the LLM only picks and orders sections; new section kinds require engineering.
- `noteExtractionSchemaJSON` — a `PersonaExtractionSchema` (categories with key/label/icon). Each note saved by a tuned user accrues `PersonaExtractionItem`s into `Note.personaExtractionsJSON`.
- `focusItemsJSON` — user-declared `FocusItem` priorities (primary/secondary/tertiary weights), read by `ContextAssembler` for prompt injection and `MomentumPictureSection` for activity ranking.
- `voiceAndTone` — free-text style directive injected into AI call prompts.

**Baseline extraction is permanent.** Persona extraction layers *additively* on top of the baseline decisions/actions/commitments pipeline — it never replaces or migrates it.

### Proactive Alerts (background tasks)

`ProactiveAlertService` scans for stale commitments, drift from intentions, and unresolved items. It runs on:
- App foreground (foreground scan in `voice_notesApp.swift`)
- A `BGAppRefresh` background task with identifier `com.eeon.proactiveAlerts` (registered via the `.backgroundTask(.appRefresh:)` Scene modifier — **not** `BGTaskScheduler.shared.register`)

Notifications are scheduled by `NotificationScheduler`. To enable background runs, the main target's Info.plist must include `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` must include `processing` and `remote-notification`.

### External Content Ingestion

| Service | Source |
|---------|--------|
| `WebContentService` | URL → fetched article text |
| `PDFExtractionService` | PDF → extracted text |
| `ImageService` | Image → OCR/description |
| `EEONShareExtension` | Hands off URL/text from other apps via `SharedDefaults.addPendingIngest`; the main app drains the queue on launch |

### Key Services

| Service | Purpose |
|---------|---------|
| `IntelligenceService` | Orchestrates AI processing across all tiers |
| `SummaryService` | OpenAI API integration (extraction, analysis) — static methods, no instance state |
| `TranscriptionService` | Whisper API for audio transcription (`actor` for thread safety). Sends Whisper's `prompt` field from `TranscriptionVocabulary` on every request, including chunked long files |
| `TranscriptionVocabulary` | Custom vocabulary for Whisper: user terms (Settings → Capture → "Words EEON should know") + names learned from `MentionedPerson`/`Project`, capped under the 224-token prompt limit. `nonisolated`, UserDefaults-only — refreshed on app-active and after extraction |
| `CalendarContextService` | Read-only EventKit lookup of the calendar event a recording overlapped (Settings → Connections → Calendar context). Stores `CalendarContext` on `Note.calendarContextJSON`; feeds `generateTitle`/`extractIntent` `context:`. `attachIfNeeded` is idempotent and called from every voice path |
| `ReminderCommandParser` | On-device, no API call: `nonisolated` regex trigger ("remind me to…", "set a reminder for…") + `NSDataDetector` date. Runs in `AIHomeView.transcribeAndSave` before the IntentClassifier; a match is still saved as a note, then `ReminderConfirmSheet` offers one-tap "Add to Reminders" via `EventKitSyncService.createReminder`. `markHandledByCommand` stops the extraction pass from pushing the same reminder twice |
| `NoteAdjustment` | Shorter / Longer / Simpler / More formal — the "Adjust" menu on the note. In-place on `enhancedNoteText` (compounds; one-level undo in `NoteDetailView`), unlike format chips which regenerate from the transcript. Pro, like every non-Enhance template |
| `LiveTranscriptionService` | On-device live transcript shown during recording (`SFSpeechRecognizer`) — Whisper still runs on the saved audio for the canonical transcript |
| `EmbeddingService` | Generates OpenAI embedding vectors for notes on save |
| `VectorSearchService` | Cosine similarity search across note embeddings (Accelerate framework) |
| `IntentClassifier` | Classifies voice input as note capture vs question/query |
| `RAGService` | Retrieval-augmented generation — vector search + GPT synthesis for answering questions |
| `ContextAssembler` | Pre-warms compiled knowledge articles at launch so RAG hits compiled knowledge first |
| `KnowledgeCompiler` | Recompiles `KnowledgeArticle`s from accumulated `KnowledgeEvent`s |
| `ProactiveAlertService` | Detects stale commitments / drift; schedules notifications via `NotificationScheduler` |
| `DriftDetector` | Compares stated intentions vs. actual capture activity |
| `MomentumService` | Streak / momentum scoring on the home screen |
| `HealthScoreService` | Aggregate "health" score across loops |
| `RewriteService` | Post-capture transforms (rewrite a note via templates). Built-in templates plus user-authored `CustomRewriteTemplate` SwiftData models, bridged to `RewriteTemplate` at use time. Transforms honor the Tune EEON voice/tone directive |
| `TagExtractor` | Suggests tags from note text |
| `WebContentService` / `PDFExtractionService` / `ImageService` | External content ingestion |
| `ExportService` | Bulk export of notes |
| `AuthService` | Sign in with Apple authentication |
| `SubscriptionManager` | StoreKit 2 subscription management |
| `UsageService` | Free tier usage tracking (5 free notes, then paywall) |
| `StatusCounters` | Real-time UI counters, persisted to UserDefaults |
| `CloudKitShareService` | Note sharing via CloudKit |
| `CloudKitEventLog` | Diagnostic log for CloudKit sync events |
| `ProjectMatcher` | Three-layer project matching (alias → fuzzy → AI) |

### Data Models (SwiftData)

All models registered in `voice_notesApp.init()` schema (17 types as of seed key `cloudKitSchemaSeedDidRun_v5` — v5 added no type, it registers the `calendarContextJSON` field on `CD_Note`):
`Note`, `Tag`, `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`, `KanbanItem`, `KanbanMovement`, `WeeklyDebrief`, `Project`, `DailyBrief`, `ExtractedURL`, `MentionedPerson`, `KnowledgeArticle`, `KnowledgeEvent`, `DailyIntention`, `CustomRewriteTemplate`

**Default actor isolation is MainActor** for this target: any unannotated class/struct is main-actor-isolated. Types read from actors or from `@Model` accessors (`TranscriptionVocabulary`, `CalendarContext`) must be declared `nonisolated` or the build warns (an error under Swift 6 mode).

**Note extraction fields** (stored on the Note model):
- `topicsJSON` — extracted topic tags as JSON
- `emotionalTone` — detected emotional tone of the note
- `enhancedNoteText` — AI-expanded, cleaned-up version of what the user said
- `embeddingData` — vector embedding for semantic search
- `personaExtractionsJSON` — persona-schema extractions (only when the user's `.purpose` article has a `noteExtractionSchemaJSON`)
- `calendarContextJSON` — `CalendarContext` (event title, attendees, times, location) when Calendar context is on and the recording overlapped an event. Seed v5 registers the field in Development; **release gate: run a DEBUG build once, then Deploy Schema Changes in the CloudKit Dashboard before the App Store build** — a Production schema without the field rejects the first synced note that has one

**Promoting schema to Production (runbook, verified 2026-08-26):** `~/projects/fastlane-configs/scripts/cloudkit_schema_sync.sh` (dry run) / `APPLY=1 …` exports the prod + dev schemas with `xcrun cktool`, adds any `CD_Note` fields Production lacks (typed list in the script), validates against Development, imports into **Development**, re-exports and verifies. Then the one step only the Dashboard can do: iCloud.aivoiceeeon → Development → left rail → **Deploy Schema Changes…** → review the diff → Deploy. Re-run the script afterwards; it exports Production and says "nothing to do" when the deploy landed. Commit the `.ckdb` exports (`fastlane/apps/voice-notes/cloudkit/`).
Auth: a CloudKit **management** token (Dashboard → account menu → Settings → Tokens → *Create Management Token*), saved with `xcrun cktool save-token --type management --force <token>`. Gotchas: `cktool` cannot `validate-schema` or `import-schema` against production ("endpoint not applicable"); a stale file token at `~/.config/cktool` shadows the keychain one and makes every command say "Session has expired" — move it aside. Team `BYRK5RUS4U`, container `iCloud.aivoiceeeon`. Fields register in Development only when some record syncs a non-nil value, so optional fields nobody filled on a dev device never reach Production unless added this way.

**Adding a new model requires updating the schema array in `voice_notesApp.swift`** AND incrementing the `cloudKitSchemaSeedDidRun_v*` key so the seed routine re-runs and registers the new record types in the CloudKit Dashboard. Without this, CloudKit silently rejects the new type. After seeding completes (logs say "Done. … 17 CD_* types"), promote in CloudKit Dashboard → Development → Deploy Schema Changes.

### View Hierarchy

- `voice_notesApp.swift` → onboarding gate (`OnboardingQuizView`) → `AIHomeView` (main hub)
- `AIHomeView.swift` — Single-button voice capture, query interface, recent notes; persona-tuned sections rendered per `homeLayoutJSON` (see `HomeSections.swift`). The feed header (`conversationsHeader`) is two dropdowns: left = All notes / Tasks / Highlights / categories (`FeedMode`), right = dates. Tasks renders `TasksView(embedded: true)` inline; Highlights renders `TodayHighlightsView` (today's `DailyBrief`) inline — nothing leaves the main screen
- `TodayHighlightsView.swift` — Today's Tier-3 `DailyBrief` inline (what matters, highlights, tickable next steps, going-stale), with "Full brief" → `DailyBriefSheet`
- `AssistantView.swift` — AI assistant / query response view
- `TuneConversationView.swift` — Tune EEON personalization (profile + purpose fields)
- `KnowledgeBaseView.swift` — Reference material upload/browse (in Settings); `KnowledgeArticleDetailView` renders compiled articles
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
- **Container fallback hierarchy.** CloudKit → local SQLite → **backup-then-recreate-with-CloudKit** → in-memory (last resort). The current logic at `voice_notesApp.swift:38-105` copies the existing store to `Documents/default-backup-<timestamp>.store` before deleting, then recreates a fresh CloudKit-backed store so iCloud-synced notes resync down. The in-memory last-resort path means a launch never crashes but new notes created that session are not persisted. **Never delete user notes — see `docs/superpowers/plans/2026-05-16-data-safety-hardening.md`.**

### Monetization Flow
- `UsageService` tracks note count via UserDefaults (5 free notes limit; `freeReportLimit = 2` for AI report generations)
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
- App Group: `group.com.eeon.voicenotes` (shared between main app, widget, and share extension)
- URL scheme: `voicenotes://share/{id}` for shared notes; `voicenotes://record` to auto-start recording (used by widget App Intent)
- Universal Link: `https://eeon.com/share/{id}` (and `www.eeon.com`) handled in `voice_notesApp.handleIncomingURL`
- Separate entitlements for Debug (`voice notes.entitlements`) and Release (`voice notesRelease.entitlements`); widget and share extension have their own `.entitlements` files that must include the same App Group

## StoreKit Products

- `pro_monthly` ($9.99), `pro_annual` ($79.99)
- Configured in `Products.storekit`

## Testing

UI tests only (no unit tests — see `TODOS.md` #1 for the planned first unit-test target). Screenshot automation via Fastlane:
- Launch args: `-UITestMode`, `-SkipOnboarding` for test-specific behavior; `-SeedScreenshotData` (DEBUG only) runs `ScreenshotSeed.swift`, which inserts a curated founder persona — compiled articles, focus items, sample notes, and a pre-baked `homeLayoutJSON` — so screenshots bypass the LLM compile loop
- `AuthService.debugSignIn()` available in DEBUG builds

## Releases (Fastlane)

Fastlane lives **outside this repo** in `~/projects/fastlane-configs`, keyed by app:

```bash
cd ~/projects/fastlane-configs
fastlane beta app:voice-notes         # build + upload to TestFlight (auto-increments build number)
fastlane screenshots app:voice-notes  # capture + upload App Store screenshots (lanes: snap, push_screenshots)
fastlane release app:voice-notes      # full release: build, upload, submit for review
fastlane metadata app:voice-notes version:3.8.0  # upload App Store metadata only — version: is required and must be the App Store version the metadata is for
```

When cutting a release, bump **both** the marketing version and the build number — bumping only the build fails App Store submission once a version train has closed.

## Git Workflow

Work happens directly on `main` — no feature branches. Never push without the user's explicit go-ahead.

## Planning Workflow (`docs/superpowers/`)

Significant features go through a written spec → plan → execute flow:
- `docs/superpowers/specs/YYYY-MM-DD-feature-design.md` — design doc
- `docs/superpowers/plans/YYYY-MM-DD-feature.md` — step-by-step implementation plan

When asked to build a non-trivial feature, check `docs/superpowers/plans/` first — there may already be a plan to execute. The plans tend to reference specs by filename.

## Other Repo Docs

- `MEMORY.md` (repo root) — product decision log: the v2 pivot rationale, the navigation "kill list", ghost-text coaching, competitive positioning. Read before questioning or redesigning an existing product decision.
- `TODOS.md` (repo root) — deferred work items written up with enough context to pick up cold.
- `docs/design-system.md` — brand identity, color tokens (coral accent / AI blue), and component styling. Use these tokens instead of inventing colors.

## Dead Code

`ContentView.swift` is unused (noted in the file itself). The actual entry point is `voice_notesApp` → `AIHomeView`. Many v1 dashboard views remain in the codebase but are disconnected from navigation (see View Hierarchy section above).
