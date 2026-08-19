# EEON Modes + Auto-Summarize — Design Spec

**Date:** 2026-08-19
**Status:** Approved direction (doc pending Shawn's review)
**Goal:** Close the visible gap with Pocket's profession "mods" (student, lawyer, therapist…) and their auto-summaries — using EEON's existing persona compiler instead of canned templates. Pocket ships presets; EEON ships presets that *compile into a bespoke persona*.

## Product decisions (locked)

1. **Presets are seeds, not cages.** A preset is curated profile + purpose text pushed through the **existing Tune EEON compile path** (seed Notes + force-compile of `.self` and `.purpose` articles). After one tap the user has a tuned home layout, profession-specific extraction categories, and voice/tone — and can still re-dictate Tune EEON any time, which simply re-compiles over the seed.
2. **Auto-summarize is Pro-only** (Shawn's call, 2026-08-19). Free users keep the baseline enhancement (`enhancedNoteText`), which already exists and is good. The persona-shaped auto-summary is a paywall reason — same packaging as Pocket's Pro custom templates ($199/yr) at $79.99/yr.
3. **Auto-summarize does exactly what a manual transform does today** — overwrite `note.enhancedNoteText` with the template output (`NoteDetailView.swift:1123-1133` pattern), transcript always preserved as canonical. No new storage, no new display surface.
4. **Baseline extraction is permanent** (standing rule): the auto-summary runs *after* and *in addition to* baseline enhancement + extraction; it never replaces the extraction pipeline.

## The preset catalog (initial 6)

Founder/Builder (first — matches the vibe-coder pivot), Student, Lawyer, Therapist, Sales, Realtor. Each preset is pure content:

```swift
struct PersonaPreset: Identifiable {
    let id: String            // "founder", "student", …
    let name: String          // "Founder / Builder"
    let icon: String          // SF Symbol
    let blurb: String         // one-line picker description
    let profileText: String   // curated dictation → Tune profile field
    let purposeText: String   // curated dictation → Tune purpose field
    let defaultTemplateKey: String?  // auto-summary template (Pro)
}
```

The `purposeText` explicitly names the extraction categories the profession needs (e.g. Lawyer: matters, deadlines, citations, billable moments; Student: concepts, assignments, exam dates, questions to ask) so the compiled `PersonaExtractionSchema` reflects the profession. The LLM compiler does what it already does — presets just feed it professional-grade dictation.

## Surfaces

- **Onboarding:** a "What do you do?" step in `OnboardingQuizView` showing the preset grid + "I'll describe it myself" (routes to Tune EEON later). Selecting a preset applies it after onboarding completes.
- **Tune EEON:** `TuneConversationView` gains a preset row above the dictation fields — same apply path, usable any time.
- Applying a preset = the existing Tune save flow (persist seed Notes, force-compile profile + purpose articles) plus writing `defaultTemplateKey` into the extraction schema (below).

## Auto-summary wiring

- **Storage:** add `var defaultRewriteTemplateKey: String?` to `PersonaExtractionSchema` (`PersonaExtractionTypes.swift`). It rides the existing `noteExtractionSchemaJSON` field on the `.purpose` article — **no SwiftData schema change, no CloudKit migration** (optional Codable field decodes nil on old data, syncs with the article).
- **Recompile survival:** the key is user/preset-set, not LLM-emitted — when a re-tune recompiles the `.purpose` article and writes a fresh schema JSON, the compiler wiring must carry the existing `defaultRewriteTemplateKey` forward onto the new schema (only a preset apply or an explicit future setting changes it). Without this, any later re-tune silently kills auto-summaries.
- **Pipeline:** in `IntelligenceService.processNoteSave`, after baseline enhancement + extraction complete: if `SubscriptionManager.shared.isPro` AND the user's compiled schema has a `defaultRewriteTemplateKey` AND the note is a capture (not a question), resolve the template and run `RewriteService.rewrite(transcript: enhancedOrTranscript, template:)`, writing the result to `note.enhancedNoteText` (and `updatedAt`). Failure = silent skip; the baseline enhancement already on the note stays. Never blocks or fails the save.
- **Hand-edit respect:** if `note.enhancedNoteEdited == true` (user corrected the text), the auto-summary must NOT overwrite it — same courtesy the re-run pipeline shows.
- **Templates:** map preset → existing built-in `RewriteTemplate`s where they fit; add profession templates where they don't (Case Notes, Lecture Notes, Session Notes, Deal Notes — exact set decided in the plan after reading the built-in template catalog in `RewriteService.swift`). Templates already honor Tune voice/tone.
- **Cost:** +1 GPT call per note for tuned Pro users. Free users: zero change.

## Non-goals

- No new SwiftData models, no CloudKit schema seed bump, no new navigation surfaces.
- No per-note template picker changes (manual transforms in NoteDetailView stay as-is).
- No "mode switching" UI beyond re-applying a preset — the persona system is already the mode.

## Error handling

- Preset apply while offline / compile fails: same behavior as a failed Tune save today (retryable; seed notes persist).
- Auto-summary failure: log + keep baseline enhancement. Never surface an error for an automatic enhancement.

## Verification

- Build gate per task (`xcodebuild`, simulator destination).
- Manual: apply Lawyer preset in simulator → confirm compiled schema categories + home layout change; save a note as Pro (debug sign-in + StoreKit config) → enhanced text arrives in template shape; save as free user → baseline enhancement only; hand-edit a note then re-save → edit not clobbered.
- On-device (with capture pack): a locked-phone capture through `BackgroundCaptureService.saveAndProcess` gets the same auto-summary (it calls the same `processNoteSave`) — spot-check during the capture-pack device gate.
