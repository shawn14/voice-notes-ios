# Design Spec: Onboarding Redesign + Multi-Source Note Creation

**Date:** 2026-04-13
**Status:** Approved
**Inspired by:** Coconote competitive review

---

## Overview

Two features shipping together:

1. **Onboarding Redesign** — Replace the current 3-screen informational onboarding (`OnboardingPaywallView`) with a 6-screen progressive profiling quiz optimized for conversion.
2. **Multi-Source Note Creation** — Add a "+" button beside the record button that opens a source picker sheet with 4 input types: Record Audio, Upload Audio, PDF/File, Web Link. All sources run the full AI pipeline.

---

## Feature 1: Onboarding Redesign

### Goal

Increase free trial conversion rate by replacing informational slides with interactive questions that build psychological commitment before the paywall.

### Approach

**Conversion theater only.** User answers are used to display tailored social proof and use cases during onboarding but are NOT stored or used to personalize the product after onboarding completes. This can be revisited later.

### Screen Flow (6 screens)

Progress bar runs across the top of all screens (linear, like Coconote).

#### Screen 1: Hero / Landing
- EEON app icon (centered, prominent)
- Tagline: "Your AI memory for everything you say"
- "try for $0" callout with arrow pointing to CTA
- **CTA:** "Continue" (full-width dark button)
- "Already have an account?" link below

#### Screen 2: Role Selection
- Header: "Personalizing your EEON..."
- Question: "Which best describes you?"
- Options (single-select, each is a tappable row with emoji + label):
  - 💼 Working professional — "Meetings, ideas, decisions"
  - 📚 Student — "Lectures, study notes, research"
  - 🎨 Creator — "Ideas, scripts, content planning"
  - 🚀 Founder / entrepreneur — "Strategy, pitches, team notes"
  - 🔧 Something else
- Selection stored in local `@State` variable (not persisted)

#### Screen 3: Intent
- Header: "Personalizing your EEON..."
- Question: "What brings you to EEON?"
- Options (single-select):
  - 🎙 Capture ideas on the go
  - 📋 Never forget what was said in meetings
  - 🧠 Build a searchable second brain
  - ✍️ Think out loud, get organized text back
  - 🔍 Something else
- **CTA:** "Continue →"

#### Screen 4: Tailored Social Proof
- Header: "You're in good company!"
- Dynamically selected based on Screen 2 role:
  - **Professional:** "EEON has helped me stop losing action items from meetings. I just talk, and everything is organized."
  - **Student:** "I record lectures and EEON extracts all the key concepts. It's like having a study partner."
  - **Creator:** "I dump ideas all day and EEON turns them into structured notes I can actually use."
  - **Founder:** "Every decision, every commitment — it's all captured and searchable. Game changer."
  - **Default:** "I never realized how much I was forgetting until EEON started remembering for me."
- 5-star rating display
- Attributed to a role-matching persona (name + role)
- Below testimonial: 3 checkmarks with role-relevant use cases
- **CTA:** "Continue →"

#### Screen 5: Feature Highlight
- Header: "What EEON does for you"
- Visual grid (2x3) of capabilities with icons:
  - 🎙 Voice capture — "Talk, we handle the rest"
  - 🧠 AI memory — "Search everything you've ever said"
  - ⚡ Instant extraction — "Decisions, actions, commitments"
  - ✨ Enhanced notes — "Your words, polished and organized"
  - 🔗 Multi-source — "Add links, PDFs, files"
  - 💬 Ask anything — "Query your entire memory"
- **CTA:** "Continue →"

#### Screen 6: Paywall
- Header: "Start capturing with EEON"
- Feature comparison table:
  - **Free column:** 5 free notes ✓, AI extraction ✓, Voice capture ✓
  - **Pro column:** All free features ✓, Unlimited notes ✓, Multi-source ingest ✓, AI memory search ✓, Post-capture transforms ✓, Priority support ✓
- Pricing options (from existing `SubscriptionManager`):
  - `pro_monthly` — $9.99/month
  - `pro_annual` — $79.99/year ("Save 33%")
- **CTA:** "Start my FREE week" (if trial available) or "Start free" (5 notes)
- "View all plans" link
- Small print: terms, privacy, restore purchases

### Architecture

- **New file:** `OnboardingQuizView.swift` — replaces `OnboardingPaywallView.swift`
- Uses `@State` for current step and quiz answers (not persisted to UserDefaults or SwiftData)
- `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` for swipe + button navigation
- Each screen is a private sub-view within the file
- Progress bar is a simple `GeometryReader` + `Rectangle` with animation
- Paywall screen reuses `SubscriptionManager.shared` for StoreKit 2 integration
- Gate logic in `voice_notesApp.swift` stays the same — just points to new view

### What It Replaces

- `OnboardingPaywallView.swift` — fully replaced (can be deleted or kept as dead code)
- No changes to `PaywallView.swift` (in-app paywall for users who exhaust free tier stays separate)

---

## Feature 2: Multi-Source Note Creation

### Goal

Let users feed EEON from any source — not just voice — while keeping voice recording as the primary, zero-friction interaction.

### UI Design

#### "+" Button Placement
- Small circular button (40pt) positioned to the left of the existing record button
- Uses SF Symbol `plus.circle.fill` or similar
- Matches EEON's design system (EEONAccent color)
- Tapping opens `SourcePickerSheet` as a `.sheet` (bottom sheet)

#### Source Picker Sheet
- Title: "New Note"
- Close button (X) top-right
- 4 rows, each tappable:
  1. **🎙 Record audio** — Dismisses sheet, triggers existing `toggleRecording()` flow
  2. **📤 Upload audio** — Opens file picker (`.audio` UTType), existing import flow
  3. **📄 PDF, file, or text** — Opens file picker (`.pdf`, `.plainText` UTTypes)
  4. **🔗 Web link** — Opens inline text field to paste a URL

### Input Flows

#### Record Audio (existing)
- Sheet dismisses → `toggleRecording()` fires → existing flow unchanged

#### Upload Audio (existing, surfaced)
- File picker (already in AIHomeView line 274-287)
- Selected file → copies to documents → `TranscriptionService.transcribe()` → full AI pipeline
- Note created with `sourceType = .voice` (same as recorded)

#### Web Link (existing service, new UI)
- User pastes URL into text field within the sheet
- "Add" button triggers:
  1. Show loading indicator ("Fetching content...")
  2. `WebContentService.fetchArticle(url:)` extracts title + content (capped at 3000 words)
  3. Create `Note` with:
     - `text` = extracted content
     - `sourceTypeRaw` = "web"
     - `originalURL` = the pasted URL
     - `title` = extracted page title
  4. Run full AI pipeline: `IntelligenceService.processNoteSave()` → extraction + embedding
  5. Dismiss sheet, show note in list
- Error handling: if fetch fails, show inline error "Couldn't load that link. Check the URL and try again."

#### PDF / File (new)
- File picker accepts `.pdf` and `.plainText` UTTypes
- Selected file → `PDFExtractionService.extractText(from:)`:
  1. **PDFKit first:** Load `PDFDocument`, iterate pages, extract `string` from each page
  2. **Check result quality:** If extracted text is < 50 characters per page on average, likely a scanned document
  3. **Vision OCR fallback:** Use `VNRecognizeTextRequest` on each page rendered as image. Concatenate recognized text.
  4. **Cap at 5000 words** to bound downstream API costs
- Plain text files: read directly, no extraction needed
- Create `Note` with:
  - `text` = extracted text
  - `sourceTypeRaw` = "web" (reuse existing type, or add "document" to `NoteSourceType`)
  - `title` = filename without extension
- Run full AI pipeline: extraction + embedding
- Error handling: if PDF has no extractable text even after OCR, show "Couldn't extract text from this PDF."

### New Service: PDFExtractionService

```
PDFExtractionService (actor, for thread safety)
├── extractText(from url: URL) async throws -> ExtractedDocument
├── struct ExtractedDocument
│   ├── text: String
│   ├── title: String
│   ├── pageCount: Int
│   └── wasOCR: Bool
├── private extractWithPDFKit(document: PDFDocument) -> String?
└── private extractWithVisionOCR(document: PDFDocument) async throws -> String
```

- Frameworks: `PDFKit`, `Vision`
- No external dependencies or API calls
- Thread-safe via `actor` (matches pattern of `TranscriptionService`)

### Note Source Type

The `Note` model already has `sourceTypeRaw` with values "voice", "web", "derived". Options:

- **Option A:** Add "document" and "audioImport" to the `NoteSourceType` enum for distinct badges
- **Option B:** Reuse "web" for links and use "voice" for uploaded audio

**Decision:** Option A — add `document` and `audioImport` cases to `NoteSourceType`. This lets the UI show appropriate badges ("PDF", "Audio Import", "Web Source") and enables filtering by source type later.

### Changes to Existing Files

| File | Change |
|------|--------|
| `AIHomeView.swift` | Add "+" button next to record button. Add `SourcePickerSheet` presentation. |
| `Note.swift` | Add `document` and `audioImport` cases to `NoteSourceType` enum. |
| `WebContentService.swift` | No changes — used as-is. |
| `IntelligenceService.swift` | No changes — `processNoteSave()` already handles any note. |
| `voice_notesApp.swift` | No model schema changes needed (no new SwiftData models). |

### New Files

| File | Purpose |
|------|---------|
| `OnboardingQuizView.swift` | 6-screen onboarding flow with progressive profiling |
| `SourcePickerSheet.swift` | Bottom sheet with 4 input source options |
| `PDFExtractionService.swift` | PDF text extraction with PDFKit + Vision OCR fallback |

---

## What's NOT In Scope

- Flashcards and quizzes (deferred)
- Storing onboarding quiz answers for personalization
- YouTube video ingestion
- Photo/image OCR notes
- Preview step before saving web links or PDFs
- In-app web browser for links

---

## Dependencies

- `PDFKit` framework (built-in, needs to be linked)
- `Vision` framework (built-in, needs to be linked)
- No new third-party dependencies
- No new API endpoints or backend changes
- No new SwiftData models (just enum cases on existing Note model)
