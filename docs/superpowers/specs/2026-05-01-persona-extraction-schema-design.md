# Persona Extraction Schema — Design Spec

**Date:** 2026-05-01
**Status:** Approved
**Inspired by:** [Andrej Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

## Overview

EEON's `.purpose` `KnowledgeArticle` already drives a per-user system-prompt directive (`thinkingEvolution`) and a per-user home layout (`homeLayoutJSON`) — both compiled by the Karpathy LLM from the user's seeds. This spec extends the same pattern to **note extraction**: when `.purpose` compiles, the LLM also produces a `noteExtractionSchemaJSON` that defines what to extract from the user's notes.

A founder gets `{businesses_touched, decisions, blockers, resource_pulls}`. A dream interpreter gets `{symbols, archetypes, recurring_imagery, dreamer_feeling}`. A coach gets `{client_session, session_theme, breakthroughs, follow_ups}`. Same Karpathy-LLM substrate; persona-shaped output.

**One-line pitch:** Tune EEON to who you are, and the chips on every note start speaking your language.

## Architectural rule (locked-in)

**Baseline extraction is permanent. Persona extraction is purely additive.**

- Existing `ExtractedDecision`/`Action`/`Commitment`/`UnresolvedItem`/`MentionedPerson`/`ExtractedURL` SwiftData models run for every note, every user, always — no migration, no deprecation.
- Persona extraction runs *in addition* to baseline when the user's `.purpose` article has a `noteExtractionSchemaJSON` field populated.
- Persona output goes to a separate `Note.personaExtractionsJSON` field — never overwrites baseline.
- If user clears their persona, persona extraction stops generating; baseline continues unchanged.
- Legacy UI surfaces (proactive alerts, daily brief, anything reading `ExtractedCommitment`) keep working forever.

This rule is captured in `~/.claude/projects/.../memory/project_extraction_baseline_persona_rule.md`.

## Data Model Changes

Both additions are **optional JSON string fields on existing models** — no new SwiftData classes, no CloudKit schema migration.

```swift
// KnowledgeArticle.swift — add field (only populated on .purpose articles)
var noteExtractionSchemaJSON: String?
// JSON shape:
// {
//   "version": 1,
//   "categories": [
//     {"key": "businesses_touched", "label": "Businesses", "icon": "building.2.fill", "description": "..."},
//     {"key": "decisions",         "label": "Decisions",  "icon": "checkmark.seal", "description": "..."},
//     ...
//   ],
//   "extractionPromptFragment": "Extract through the lens of a CEO/founder running multiple businesses..."
// }

// Note.swift — add field (populated post-extraction when persona schema exists)
var personaExtractionsJSON: String?
// JSON shape:
// [
//   {"category": "businesses_touched", "content": "StockAlarm", "metadata": {...}},
//   {"category": "decisions",         "content": "Pivot pricing tier", "metadata": {"confidence": "High"}}
// ]
```

Computed accessors on each model decode/encode to typed Swift structs (`PersonaExtractionSchema`, `[PersonaExtractionItem]`), mirroring existing patterns like `homeLayout`, `connections`, etc.

## Extraction Flow

```
Note saved
   │
   ├─► SummaryService.extractIntent(text)        ← baseline (unchanged, always runs)
   │      writes ExtractedDecision/Action/Commitment/etc.
   │
   └─► Optional: SummaryService.extractPersonaItems(text, schemaJSON)
          ↑ runs only if .purpose.noteExtractionSchemaJSON is non-empty
          writes Note.personaExtractionsJSON
```

Two distinct LLM calls. The persona call is gated; if the user has no persona schema, it never runs. Cost added for tuned users: ~1 extra extraction call per note (≈$0.001/note at gpt-4o-mini pricing).

## `.purpose` Compile Extension

The existing `.purpose` compile prompt (in `SummaryService.compileArticle` switch case `.purpose`) currently produces `summary`, `thinkingEvolution`, and `homeLayoutJSON`. Add a third output: `noteExtractionSchemaJSON`.

The prompt instructs the LLM to:
- Pick 4-6 category keys that fit the user's stated role
- Provide a concrete extraction-prompt fragment that the LLM will use when extracting from notes
- Match category icons to SF Symbols
- Use second-person language in descriptions

Example output for a founder:
```json
{
  "version": 1,
  "categories": [
    {"key": "businesses_touched", "label": "Businesses", "icon": "building.2.fill",
     "description": "Which of your businesses this note affects"},
    {"key": "decisions", "label": "Decisions", "icon": "checkmark.seal.fill",
     "description": "Choices made or pending"},
    {"key": "blockers", "label": "Blockers", "icon": "exclamationmark.triangle.fill",
     "description": "What's stuck and needs unblocking"},
    {"key": "resource_pulls", "label": "Resource Pulls", "icon": "arrow.left.arrow.right",
     "description": "Money, time, or people being requested"},
    {"key": "follow_ups", "label": "Follow-ups", "icon": "arrow.uturn.right",
     "description": "Things you owe someone"}
  ],
  "extractionPromptFragment": "You are extracting from a note by a founder running multiple businesses. Look for which business each item relates to, decisions, blockers, resource asks, and personal follow-ups. Be concise — extract only what's clearly present, do not infer."
}
```

## SummaryService Additions

```swift
struct PersonaExtractionItem: Codable {
    let category: String
    let content: String
    let metadata: [String: String]?
}

struct PersonaExtractionSchema: Codable {
    struct Category: Codable {
        let key: String
        let label: String
        let icon: String
        let description: String
    }
    let version: Int
    let categories: [Category]
    let extractionPromptFragment: String
}

extension SummaryService {
    static func extractPersonaItems(
        text: String,
        schemaJSON: String,
        apiKey: String
    ) async throws -> [PersonaExtractionItem]
}
```

System prompt for `extractPersonaItems`:
- Inject the user's `extractionPromptFragment` from the schema
- Provide the category keys + descriptions
- Ask LLM to return JSON array of `{category, content, metadata?}`
- Skip categories with nothing to extract — better empty than hallucinated

`gpt-4o-mini`, `temperature: 0.3`, `max_tokens: 800`.

## UI Changes

### `PersonaChipsView` (new)
Reads `note.personaExtractionsJSON`, groups items by category, renders one chip-row per category with the category's icon + label header. Tap-to-query (matches existing chip behavior). Hides cleanly when empty.

### `NoteDetailView` slot
Insert above the body's existing AI-generating indicator and below the new `NoteWikiConnectionsView` we just shipped. Persona chips appear *before* legacy chips in any view that renders both — they're the primary surface for tuned users.

### `IdentityView` (Tune EEON)
Add a "How EEON sees your notes" section that:
- Renders the current `noteExtractionSchemaJSON` as a readable category list ("Categories I'll watch for: Businesses, Decisions, Blockers, …")
- Shows last-compiled time
- "Regenerate" button → forces a `.purpose` recompile via `KnowledgeCompiler.recompileDirtyArticles(force: true)`
- Empty state when no schema: "Tune your purpose to teach EEON what to look for in your notes" → CTA to seed entry

## Out of scope (deferred)

- **Re-extract old notes on persona change** — opt-in batch action with token-cost preview. Layer on later.
- **User-authored schema** — power-user feature to directly write the JSON schema. Layer on later.
- **Persona-driven proactive alerts** — `ProactiveAlertService` adapting categories based on persona. Big lift; defer.
- **Conversational Tune** — dialogue-based onboarding/refinement. Polish layer; defer.

## Files Touched

| New | Modified |
|---|---|
| `voice notes/PersonaChipsView.swift` | `voice notes/KnowledgeArticle.swift` (add `noteExtractionSchemaJSON` field + accessor) |
| | `voice notes/Note.swift` (add `personaExtractionsJSON` field + accessor) |
| | `voice notes/SummaryService.swift` (extend `.purpose` compile prompt + add `extractPersonaItems` + types) |
| | `voice notes/KnowledgeCompiler.swift` (persist `noteExtractionSchemaJSON` from compile response) |
| | `voice notes/IntelligenceService.swift` or wherever `extractIntent` is called post-save (add gated persona call) |
| | `voice notes/NoteDetailView.swift` (slot `PersonaChipsView`) |
| | `voice notes/IdentityView.swift` (add "How EEON sees your notes" section) |

## Verification

1. **Existing users (no persona schema)**: install build, record note, confirm baseline chips/extractions identical to today. No persona work runs.
2. **Tune as Founder**: write a CEO/founder purpose seed → wait for `.purpose` compile → confirm `noteExtractionSchemaJSON` populated with founder-shaped categories → record a note about a meeting → confirm `Note.personaExtractionsJSON` populated and `PersonaChipsView` renders founder chips.
3. **Tune as Dream Interpreter**: clear, re-tune as dream interpreter → confirm new schema, new chips on next note.
4. **Clear persona**: blank out `.purpose` seed → confirm new notes only get baseline chips; old notes' persona chips remain (don't auto-delete).
5. **Schema seed**: only adds nullable fields, no new model classes — no `cloudKitSchemaSeedDidRun_v*` bump required.
6. **Cost sanity**: tuned user sees ~2x extraction tokens per note (baseline + persona). At scale this is acceptable insurance against schema brittleness.

## Risks

- **LLM-authored schema drift**: regenerating schema may produce different category keys than before, orphaning old `Note.personaExtractionsJSON` entries. Mitigation: chip view tolerates unknown category keys (renders generically with "tag" icon); document that schema changes don't retroactively touch old extractions.
- **Token-budget creep**: we now inject directive + profile + index + (eventually) priorities into many calls. Pre-MVP: audit total prompt size at typical scale; add per-injection char caps where missing.
- **Persona prompt quality**: if the LLM produces a vague `extractionPromptFragment`, persona chips will be vague. Mitigation: bake examples into the `.purpose` compile prompt the same way `homeLayoutJSON` examples are baked in.
- **First-run blank state in Tune**: existing users opening Tune will see the "How EEON sees your notes" section empty until they re-trigger compile. Surface a one-tap "Generate now" affordance.
