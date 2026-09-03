# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EEON is a voice-first AI memory app (SwiftUI + SwiftData) for iOS. Users talk into a single button — the AI classifies whether it's a note or a question, transcribes via OpenAI Whisper, extracts structured intelligence (decisions, actions, commitments, people, topics, emotional tone), generates an enhanced version of what the user said, embeds the note for vector search, and lets users query their entire memory via natural language. Features CloudKit sync, Sign in with Apple, StoreKit 2 subscriptions, a Home Screen / Lock Screen widget, and a Share Extension for ingesting URLs and text from other apps.

## Locked Product Direction — Privacy-First Integrations

EEON's default integration posture is privacy-first: Sign in with Apple, SwiftData/CloudKit private sync, Calendar read context through iOS Calendar, direct read-only Google Calendar OAuth when configured, Reminders sync, Share Extension ingest, and a read-only EEON CloudKit MCP connector that each AI workspace authorizes with Apple. Do not present iPhone Files picking, exported folders, same-Wi-Fi receivers, or "AI Access Ready" as the primary setup. Folder/markdown export is only an "Export My Data" fallback. A management CloudKit token proves schema/admin access only; private-note reads require explicit user CloudKit auth for the Apple ID that owns the notes. Direct Gmail/Drive/task-app write-back is allowed only as a deliberate product/auth build with scoped consent, token storage, and App Review/privacy disclosure.

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
| `TranscriptionService` | Whisper API for audio transcription (`actor` for thread safety). Sends Whisper's `prompt` field from `TranscriptionVocabulary` on every request, including chunked long files. Requests `verbose_json` and drops silence hallucinations (segments with high `no_speech_prob`+low `avg_logprob`, or high `compression_ratio`) via `cleanedTranscript`; a too-short (<0.8s) or fully-filtered clip throws `noSpeechDetected` so no fabricated note is saved |
| `TranscriptionVocabulary` | Custom vocabulary for Whisper: user terms (Settings → Capture → "Words EEON should know") + names learned from `MentionedPerson`/`Project`, capped under the 224-token prompt limit. `nonisolated`, UserDefaults-only — refreshed on app-active and after extraction |
| `CalendarContextService` | Read-only EventKit lookup of the calendar event a recording overlapped (Settings → Connections → iPhone Calendar). Covers iCloud, Google, and Outlook calendars that are visible in the iPhone Calendar app; EEON does not need a separate Google login for this path. Stores `CalendarContext` on `Note.calendarContextJSON`; feeds `generateTitle`/`extractIntent` `context:`. `attachIfNeeded` is idempotent and called from every voice path |
| `GoogleCalendarService` | Direct read-only Google Calendar OAuth for events that are not synced into iPhone Calendar. Uses `calendar.readonly`, PKCE via `ASWebAuthenticationSession`, Keychain token storage, and maps Google Calendar API events into the same `CalendarMeeting` surface as EventKit. Requires `GoogleCalendarOAuthClientID` in `voice-notes-Info.plist` plus that client ID's reversed `com.googleusercontent.apps...` URL scheme in `CFBundleURLTypes`; redirect URI is `<reversed-client-id>:/oauth2redirect` |
| `ReminderCommandParser` | On-device, no API call: `nonisolated` regex trigger ("remind me to…", "set a reminder for…") + `NSDataDetector` date. Runs in `AIHomeView.transcribeAndSave` before the IntentClassifier; a match is still saved as a note, then `ReminderConfirmSheet` offers one-tap "Add to Reminders" via `EventKitSyncService.createReminder`. `markHandledByCommand` stops the extraction pass from pushing the same reminder twice |
| `EventKitSyncService` | Pushes extracted actions to the EEON Reminders list and stores a local action->reminder map. Task toggles call `updateCompletion(for:)` so completion/reopen changes made in EEON mirror back to already-created Apple Reminders; task deletes call `deleteReminder(forActionID:)` to remove the paired reminder; swipe-Edit renames call `updateTitle(for:)` |
| `NoteAdjustment` | Shorter / Longer / Simpler / More formal — the "Adjust" menu on the note. In-place on `enhancedNoteText` (compounds; one-level undo in `NoteDetailView`), unlike format chips which regenerate from the transcript. Pro, like every non-Enhance template |
| `LiveTranscriptionService` | On-device live transcript shown during recording (`SFSpeechRecognizer`) — Whisper still runs on the saved audio for the canonical transcript. Manual Pause stops the live preview until Resume; interruption pauses still auto-resume |
| `EmbeddingService` | Generates OpenAI embedding vectors for notes on save |
| `VectorSearchService` | Cosine similarity search across note embeddings (Accelerate framework) |
| `IntentClassifier` | Classifies voice input as note capture vs question/query |
| `RAGService` | Retrieval-augmented generation — vector search + GPT synthesis for answering questions. Home header opens Ask with explicit memory scope chips; `AnswerSheet` shows follow-up suggestions, prior turns, prior sources, and preserves active date scope through short follow-ups. Settings -> Ask EEON controls the answer mode: Fast (`gpt-4o-mini`), Balanced/Thorough (`gpt-4o` with more answer budget for Thorough) |
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
| `DocumentExportService` | Markdown/file export fallback for user-owned data portability. It must not be presented as the primary AI Access flow. Old `documentExportEnabled` state is legacy; current auto-export uses `markdownVaultAutoExportEnabled` and should stay off unless the user explicitly exports data. If this fallback is used, verify the Mac-side file path actually contains notes before claiming an AI can read them |
| `PeopleSpeakersSettingsView` | Settings -> Preferences -> People & Speakers. Global rename surface for extracted `MentionedPerson` records and saved per-note `speakerLabels`; merges duplicate person records, updates action owners, commitments, person knowledge articles, refreshed transcription vocabulary, and re-exports changed notes/articles. This is not automatic voice-print diarization |
| `AuthService` | Sign in with Apple authentication |
| `SubscriptionManager` | StoreKit 2 subscription management |
| `UsageService` | Free tier usage tracking (5 free notes, then paywall) |
| `StatusCounters` | Real-time UI counters, persisted to UserDefaults |
| `CloudKitShareService` | Note sharing via CloudKit |
| `CloudKitEventLog` | Diagnostic log for CloudKit sync events |
| `ProjectMatcher` | Three-layer project matching (alias → fuzzy → AI) |

### Data Models (SwiftData)

All models registered in `voice_notesApp.init()` schema (17 types as of seed key `cloudKitSchemaSeedDidRun_v6` — v6 added no type, it registers the `speakerLabelsJSON` field on `CD_Note`):
`Note`, `Tag`, `ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`, `UnresolvedItem`, `KanbanItem`, `KanbanMovement`, `WeeklyDebrief`, `Project`, `DailyBrief`, `ExtractedURL`, `MentionedPerson`, `KnowledgeArticle`, `KnowledgeEvent`, `DailyIntention`, `CustomRewriteTemplate`

**Default actor isolation is MainActor** for this target: any unannotated class/struct is main-actor-isolated. Types read from actors or from `@Model` accessors (`TranscriptionVocabulary`, `CalendarContext`) must be declared `nonisolated` or the build warns (an error under Swift 6 mode).

**Note extraction fields** (stored on the Note model):
- `topicsJSON` — extracted topic tags as JSON
- `emotionalTone` — detected emotional tone of the note
- `enhancedNoteText` — AI-expanded, cleaned-up version of what the user said
- `embeddingData` — vector embedding for semantic search
- `personaExtractionsJSON` — persona-schema extractions (only when the user's `.purpose` article has a `noteExtractionSchemaJSON`)
- `calendarContextJSON` — `CalendarContext` (event title, attendees, times, location) when Calendar context is on and the recording overlapped an event. Seed v5 registers the field in Development; a Production schema without the field rejects the first synced note that has one
- `speakerLabelsJSON` — user-named speaker labels for transcripts with speaker markers. Seed v6 registers the field in Development; **release gate: run a DEBUG build once, then Deploy Schema Changes in the CloudKit Dashboard before the App Store build** — a Production schema without the field rejects the first synced note that has one

**Promoting schema to Production (runbook, re-verified 2026-09-03):** `~/projects/fastlane-configs/scripts/cloudkit_schema_sync.sh` (dry run) / `APPLY=1 …` exports the prod + dev schemas with `xcrun cktool`, diffs **every `@Model` class's stored fields against every record type** via `cloudkit_model_diff.py`, adds whatever Production lacks, validates against Development, imports into **Development**, re-exports and verifies. Then the one step only the Dashboard can do: iCloud.aivoiceeeon → Development → left rail → **Deploy Schema Changes…** → review the diff → Deploy. Re-run the script afterwards; it exports Production and says "nothing to do" when the deploy landed. Commit the `.ckdb` exports (`fastlane/apps/voice-notes/cloudkit/`).
Auth: a CloudKit **management** token (Dashboard → account menu → Settings → Tokens → *Create Management Token*), saved with `xcrun cktool save-token --type management --force <token>`. Gotchas: `cktool` cannot `validate-schema` or `import-schema` against production ("endpoint not applicable"); a stale file token at `~/.config/cktool` shadows the keychain one and makes every command say "Session has expired" — move it aside. Team `BYRK5RUS4U`, container `iCloud.aivoiceeeon`. Fields register in Development only when some record syncs a non-nil value, so optional fields nobody filled on a dev device never reach Production unless added this way. EEON MCP/private-note reads are separate from schema auth: `cktool get-teams` proves the management token, but `query-records --database-type private` needs a CloudKit **user** token (`xcrun cktool save-token --type user` or `CLOUDKIT_USER_TOKEN`) or CloudKit Web Services user auth.

**A missing Production field silently stops ALL sync — check every record type, never just `CD_Note` (incident 2026-06-16 → 2026-09-03).** Production was missing 15 stored fields across six record types (`CD_CustomRewriteTemplate`, `CD_ExtractedURL`, `CD_KanbanItem`, `CD_KnowledgeArticle`, `CD_Project`, `CD_UnresolvedItem`). CloudKit rejected every export with `CKError.partialFailure`, so nothing synced for 2.5 months: 15 notes stranded on the device, the connector reading a frozen 74-note vault, and no user-visible error anywhere. The sync script's own check was a hand-maintained list of `CD_Note` fields, so it kept reporting "nothing to do" — an allowlist can only prove the fields someone remembered are present. It is now a closed-world diff derived from the models. Two consequences worth keeping: **adding a stored field to ANY `@Model` class is a schema change**, not just `Note`; and **a schema deploy is not the end** — the device still has to retry its export (Settings → iCloud → **Sync Now**), so verify the vault's note count and `last_change` actually moved instead of trusting the Dashboard's "Changes Deployed".

**Adding a new model requires updating the schema array in `voice_notesApp.swift`** AND incrementing the `cloudKitSchemaSeedDidRun_v*` key so the seed routine re-runs and registers the new record types in the CloudKit Dashboard. Without this, CloudKit silently rejects the new type. After seeding completes (logs say "Done. … 17 CD_* types"), promote in CloudKit Dashboard → Development → Deploy Schema Changes.

### View Hierarchy

- `voice_notesApp.swift` → onboarding gate (`OnboardingQuizView`) → `AIHomeView` (main hub)
- `AIHomeView.swift` — Single-button voice capture, query interface, recent notes; persona-tuned sections rendered per `homeLayoutJSON` (see `HomeSections.swift`). The feed header (`conversationsHeader`) is two dropdowns: left = All notes / Tasks / Highlights / categories (`FeedMode`), right = dates. Tasks renders `TasksView(embedded: true)` inline; Highlights renders `TodayHighlightsView` (today's `DailyBrief`) inline — nothing leaves the main screen
- `TodayHighlightsView.swift` — Today's Tier-3 `DailyBrief` inline (what matters, highlights, tickable next steps, going-stale), with "Full brief" → `DailyBriefSheet`
- `AssistantView.swift` — AI assistant / query response view
- `TuneConversationView.swift` — Tune EEON personalization (profile + purpose fields)
- `KnowledgeBaseView.swift` — Reference material upload/browse (in Settings); `KnowledgeOverviewView` includes Memory Map, a visual graph of compiled people/projects/topics; `KnowledgeArticleDetailView` renders compiled articles
- `NoteDetailView.swift` — Note viewing with enhanced text, speaker labels, extraction chips, and selected-excerpt cleanup for noisy recordings
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
Direct URLSession calls (no SDK) in `SummaryService.swift` and sibling services:
- **Whisper**: `POST /v1/audio/transcriptions` — audio chunked if >25MB (10-min segments)
- **GPT**: `POST /v1/chat/completions` with `gpt-4o-mini` for intent extraction and daily briefs
- **Ask EEON**: the home header opens Ask with Everything / Today / 7 days / 30 days scope chips. `AnswerSheet` displays suggested follow-ups and prior turns. Settings -> Ask EEON controls model mode: Fast uses `gpt-4o-mini`; Balanced and Thorough use `gpt-4o`; Thorough increases answer budget for synthesis-heavy questions.
- **Embeddings**: `POST /v1/embeddings` via `EmbeddingService` for note vector generation
- API key loaded from `APIKeys.openAI`

### Audio Recording
`AudioRecorder.swift` records to Documents directory: AAC `.m4a`, 44.1kHz, mono. Files stored as `{UUID}.m4a`, referenced by `note.audioFileName`. It distinguishes manual pause from call/Siri interruption pause: manual Pause stays paused until Resume; interruption pauses auto-resume when the audio session frees.

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

**`fastlane deliver` can report success and apply nothing.** On 2026-08-26 the `metadata` and `screenshots` lanes printed "finished successfully" but ASC 3.8.0 kept the old name/description/keywords and a stale screenshot set. Root cause: deliver tried to set name/subtitle on the app's appInfo, hit the **live** (READY_FOR_SALE) appInfo, got a 409 INVALID_STATE, and abandoned the whole upload silently. **Always verify against the ASC API, not deliver's exit code** (Rule #29). The reliable path is `~/projects/fastlane-configs/scripts/asc_push.py --version 3.8.0` — it PATCHes only the editable (PREPARE_FOR_SUBMISSION) appInfo + version localization, replaces screenshots per display slot (APP_IPHONE_67/65, APP_IPAD_PRO_3GEN_129), retries Apple 5xx, fails on ASC write errors, and reads every field back including screenshot filenames/checksums. `--verify-only` reads without writing. If the version is already in review, explicitly approve pulling it from review, run `~/projects/fastlane-configs/scripts/asc_cancel_review.py voice-notes --version 3.8.0 --apply`, then rerun `asc_push.py`; do not resubmit to App Review unless Shawn separately says to. Auth is the App Manager `.p8` in `~/.appstoreconnect/private_keys/`.

**Fastlane snapshot can mis-resolve simulator OS versions.** On 2026-08-31 `fastlane snap app:voice-notes` passed `OS=26.3` to `xcodebuild` while Xcode only accepted the available simulator as `OS=26.3.1`, causing exit 70 before UI tests ran. Known fallback: run `xcrun simctl list devices available`, then run `xcodebuild test` directly with `-destination "id=<simulator-uuid>"`, `-only-testing:"voice notes UITests/ScreenshotTests/testCaptureScreenshots"`, and `-resultBundlePath /private/tmp/<name>.xcresult FASTLANE_SNAPSHOT=YES FASTLANE_LANGUAGE=en-US`. Export screenshots with `xcrun xcresulttool export attachments --path /private/tmp/<name>.xcresult --output-path ~/projects/fastlane-configs/fastlane/apps/voice-notes/screenshots-raw/en-US/<run-id>`, then run `~/projects/fastlane-configs/scripts/compose_screenshots.py`. Before claiming App Store screenshots are updated, compare ASC screenshot filenames/checksums, not just set counts.

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
