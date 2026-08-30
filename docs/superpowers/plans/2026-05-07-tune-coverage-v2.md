# Tune EEON Coverage v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gaps between "user tunes EEON" and "the AI pipeline reflects that tuning." Wire the remaining un-personalized AI call sites through `ContextAssembler`, and add a free-text `voiceAndTone` directive that flavors rewrites and titles.

**Architecture:** Extend the existing `ContextAssembler` / `AICallContext` pattern. Add one new nullable field on `KnowledgeArticle` (`voiceAndTone`), one new `CompileArticleResponse` field, one new `AICallContext` predicate (`includesVoiceAndTone`), one new persistence path in `KnowledgeCompiler`. Two stand-alone `flatPrefix` injections at previously-uncovered call sites (`compileArticle` for `.topic`/`.person`, `compileIndex`, `generateTitle`).

**Tech Stack:** SwiftUI, SwiftData, OpenAI Chat Completions API, CloudKit (no schema deploy needed — nullable field on existing type, per project memory `project_extraction_baseline_persona_rule.md`).

**Out of scope:** Tier C UI verbiage personalization (separate spec). Schema migration (additive nullable only). New extraction categories. Title generation getting full purpose context (only voice & tone).

---

## Background

Tier A and B pulled from `docs/superpowers/plans/2026-04-13-onboarding-and-multi-source-ingest.md`-era notes and the conversation on 2026-05-07 covering Tune EEON gaps. Already-shipped piece: `b5d9ec5 fix: inject ContextAssembler.rewrite prefix into transform prompts` (RewriteService now reads `.rewrite` prefix). Remaining gaps:

- **`SummaryService.compileArticle`** does not inject context for non-self/purpose article compiles, so user voice doesn't flavor `.topic` / `.person` article summaries.
- **`SummaryService.compileIndex`** has no context — wiki overview is generic.
- **`SummaryService.generateTitle`** has no context — titles are generic.
- **No "voice & tone" surface** — the rewrite prefix is the same purpose-directive system message; doesn't capture stylistic personality (e.g., "mythic language" for a Jungian dream interpreter).

## File Structure

| File | Change |
|------|--------|
| `voice notes/KnowledgeArticle.swift` | Add `var voiceAndTone: String?` field |
| `voice notes/SummaryService.swift` | Add `voiceAndTone` to `CompileArticleResponse`; request it in `.purpose` compile prompt; inject `ContextAssembler.flatPrefix(.analysis)` in `compileArticle` (for non-self/purpose/index types), `compileIndex`, `generateTitle` |
| `voice notes/HomeLayout.swift` | Defensive `todayThree` prepend in `decode(from:)` so it's guaranteed even when LLM drops it from the compiled JSON |
| `voice notes/KnowledgeCompiler.swift` | Persist `voiceAndTone` on `.purpose` article (alongside `homeLayoutJSON`/`noteExtractionSchemaJSON`) |
| `voice notes/ContextAssembler.swift` | Cache `voiceAndTone` string; add `AICallContext.includesVoiceAndTone`; compose into `prefix(for:).system` |
| `voice notes/TuneConversationView.swift` | Surface compiled `voiceAndTone` as a small preview card so user can see what got compiled |

No changes to `voice_notesApp.swift` (no new model type → no schema seed bump). No changes to `RewriteService.swift` (already wired in `b5d9ec5`; will start receiving voice & tone automatically once `AICallContext.rewrite.includesVoiceAndTone == true`).

## Testing strategy

Project convention: UI tests only, no unit tests (`CLAUDE.md` → "Testing"). Each task's verification is:

1. **Build verification:** `xcodebuild -scheme "voice notes" -configuration Debug build` must succeed.
2. **Manual smoke check** (described per task): run the app on simulator, exercise the changed path, observe the result.

No new test files. No XCTest cases. Commits land after build + smoke check passes.

---

## Task A1: Inject `.analysis` context in `compileArticle` for `.topic` / `.person`

**Files:**
- Modify: `voice notes/SummaryService.swift` — `compileArticle` body around line ~903 (where `systemPrompt` is constructed)

**Why:** Article compiles for `.topic` and `.person` should be written through the user's lens (purpose + profile). `.purpose`, `.self`, `.index` compiles are skipped to avoid circular self-reference (the very article being compiled IS what `ContextAssembler` reads from).

- [ ] **Step 1: Locate the systemPrompt construction in compileArticle**

Search `voice notes/SummaryService.swift` for `static func compileArticle` (~line 784) and find where `let systemPrompt = """` is built within its body. Note the exact line.

- [ ] **Step 2: Add a guarded `.analysis` prefix**

The injection must be conditional on article type so `.purpose` / `.self` / `.index` get an empty prefix. Pattern:

```swift
let analysisPrefix: String
switch articleType {
case .topic, .person:
    analysisPrefix = ContextAssembler.flatPrefix(for: .analysis)
case .purpose, .self, .index:
    analysisPrefix = ""
@unknown default:
    analysisPrefix = ""
}

let systemPrompt = """
\(analysisPrefix)You are an AI assistant that compiles knowledge articles...
[existing prompt content]
"""
```

(Replace the existing `let systemPrompt = """` opening with the prefix-prepended version. Leave the rest of the prompt body unchanged.)

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds with same warnings as baseline (Swift 6 actor-isolation warnings on `PersonaExtractionSchema`, no new errors).

- [ ] **Step 4: Manual smoke check**

Run the app on simulator. Tune EEON with a distinctive purpose (e.g., "I'm a researcher tracking contradictions"). Capture 2 notes about the same topic. Wait for `KnowledgeCompiler` to recompile (or trigger via TuneConversationView's Regenerate button). Open the resulting `.topic` article — its summary should reflect researcher-language. Confirm `.purpose` and `.self` articles still compile (no infinite loop, no empty articles).

- [ ] **Step 5: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: inject ContextAssembler in compileArticle for .topic/.person"
```

---

## Task A2: Inject `.analysis` context in `compileIndex`

**Files:**
- Modify: `voice notes/SummaryService.swift` — `compileIndex` body around line ~1007 (where `systemPrompt` is constructed)

**Why:** The wiki overview summary is the user's reading experience. It should be written in their voice.

- [ ] **Step 1: Locate the systemPrompt in compileIndex**

Search for `static func compileIndex` (~line 980). Find `let systemPrompt = """`.

- [ ] **Step 2: Prepend `.analysis` prefix**

```swift
let systemPrompt = """
\(ContextAssembler.flatPrefix(for: .analysis))You are an AI assistant that synthesizes...
[existing prompt content]
"""
```

(Single-line change at the start of the prompt string.)

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Manual smoke check**

In simulator: with a tuned purpose, accumulate ≥3 `.topic` articles. Trigger an index recompile (KnowledgeCompiler runs on schedule or via app foreground). Open the `.index` article on the home screen — its summary text should reflect the user's voice/role.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: inject ContextAssembler in compileIndex"
```

---

## Task A3: Inject `.title` context in `generateTitle`

**Files:**
- Modify: `voice notes/SummaryService.swift` — `generateTitle` around line 298 (function body, system message construction at ~line 309)

**Why:** Note titles are user-facing and benefit from voice & tone (handled in Task B5). Currently the prompt is hardcoded. Even before voice & tone lands, wiring through `ContextAssembler.flatPrefix(.title)` is a no-op safety: as long as `AICallContext.title.includesPurpose == false` (current state), the prefix returns empty string. Once Task B5 enables `.title.includesVoiceAndTone`, titles automatically pick up the new directive.

- [ ] **Step 1: Locate the system message in generateTitle**

Search for `static func generateTitle` (~line 298). Current line ~309 reads:

```swift
["role": "system", "content": "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
```

- [ ] **Step 2: Prepend `.title` prefix**

Change to:

```swift
["role": "system", "content": ContextAssembler.flatPrefix(for: .title) + "Generate a concise 3-6 word title for this voice note. No quotes or punctuation."],
```

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Manual smoke check**

In simulator: capture a note. Confirm the auto-generated title still appears (current behavior unchanged because `.title.includesVoiceAndTone` is still false — it'll change in Task B5).

- [ ] **Step 5: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: wire generateTitle through ContextAssembler"
```

---

## Task A4: Defensive `todayThree` guarantee in `HomeLayout.decode`

**Files:**
- Modify: `voice notes/HomeLayout.swift` — `decode(from:)` static, around line 115-126

**Why:** The prompt at `SummaryService.swift:856` instructs the LLM to "ALWAYS put `todayThree` as the FIRST section regardless of archetype" — but in practice GPT-4o-mini drops it sometimes (observed 2026-05-07: a tuned coach-archetype layout had `clientRoster` and `relationshipArcs` but no `todayThree`, even though the daily-intentions ritual is meant to be universal). The fallback `HomeLayout.default` has `todayThree` first, but only fires when there's no compiled layout at all — a compiled-but-incomplete layout currently slips through. Add a defensive prepend so `todayThree` is guaranteed regardless of LLM compliance.

This is a fix to a live bug surfacing as "Today's 3 disappeared after tuning." Belongs in this batch because it's the same `.purpose` article subsystem we're already touching.

- [ ] **Step 1: Update `HomeLayout.decode(from:)`**

In `voice notes/HomeLayout.swift`, the current `decode(from:)` (line 115-126) reads:

```swift
static func decode(from json: String?) -> HomeLayout {
    guard let json, let data = json.data(using: .utf8) else { return .default }
    do {
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)
        // Filter out unknown kinds (forward-compat — old layout referencing deleted section)
        let valid = decoded.sections.filter { $0.kind != nil }
        return HomeLayout(sections: valid, version: decoded.version)
    } catch {
        print("[HomeLayout] decode failed, using default: \(error)")
        return .default
    }
}
```

Replace with:

```swift
static func decode(from json: String?) -> HomeLayout {
    guard let json, let data = json.data(using: .utf8) else { return .default }
    do {
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)
        // Filter out unknown kinds (forward-compat — old layout referencing deleted section)
        var valid = decoded.sections.filter { $0.kind != nil }
        // Defensive: todayThree is the universal daily-intentions ritual. The compile
        // prompt instructs the LLM to always include it as the first section, but
        // GPT-4o-mini occasionally drops "ALWAYS" instructions in long prompts.
        // Prepend it here so it's guaranteed regardless of LLM compliance.
        if !valid.contains(where: { $0.kind == .todayThree }) {
            valid.insert(
                HomeSection(
                    kindRaw: HomeSectionKind.todayThree.rawValue,
                    title: nil,
                    rationale: nil,
                    limit: nil,
                    staleDaysThreshold: nil
                ),
                at: 0
            )
        }
        return HomeLayout(sections: valid, version: decoded.version)
    } catch {
        print("[HomeLayout] decode failed, using default: \(error)")
        return .default
    }
}
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds. No new warnings.

- [ ] **Step 3: Manual smoke check**

In simulator:

1. With a tuned `.purpose` whose compiled `homeLayoutJSON` lacks `todayThree` (reproduce by editing the article's `homeLayoutJSON` directly via debugger, or use a previously-compiled layout from a prior build): launch the app. The home screen should now render `todayThree` as the first section.
2. With a layout that already has `todayThree`: confirm no duplicate appears (the `contains(where:)` check guards against this).
3. With no compiled layout (fresh user, untuned): `.default` already includes `todayThree` — no regression.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/HomeLayout.swift"
git commit -m "fix: guarantee todayThree as first home section even when LLM drops it"
```

---

## Task B1: Add `voiceAndTone` field to `KnowledgeArticle`

**Files:**
- Modify: `voice notes/KnowledgeArticle.swift` — add field next to `homeLayoutJSON` (line 118) and `noteExtractionSchemaJSON` (line 122)

**Why:** The compiled directive needs storage. Following the project rule (memory: `project_extraction_baseline_persona_rule.md`): nullable field, additive only, no migration.

- [ ] **Step 1: Add the field**

In `voice notes/KnowledgeArticle.swift`, locate:

```swift
var homeLayoutJSON: String?
```

Add immediately after (or after `noteExtractionSchemaJSON`):

```swift
/// Free-text "voice & tone" directive — emitted only by `.purpose` compiles.
/// 1-3 sentences describing how the user wants AI output to *sound* (formality,
/// register, lyricism, vocabulary). Injected into `.rewrite` and `.title` system
/// prompts via ContextAssembler. Independent of `thinkingEvolution` (the
/// purpose directive), which describes WHAT the AI should focus on.
var voiceAndTone: String?
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds. SwiftData will pick up the new optional field automatically (no schema seed bump needed — additive nullable on existing type).

- [ ] **Step 3: Commit**

```bash
git add "voice notes/KnowledgeArticle.swift"
git commit -m "feat: add voiceAndTone field on KnowledgeArticle"
```

---

## Task B2: Request `voiceAndTone` in the `.purpose` compile prompt

**Files:**
- Modify: `voice notes/SummaryService.swift`
  - `CompileArticleResponse` struct at line 80 — add field
  - `compileArticle` `typeSpecificFields` block where `.purpose`-only fields are described (around line 856 where `homeLayoutJSON` is documented)

**Why:** The LLM has to be told to emit the field. It's `.purpose`-only — other article types should not return it.

- [ ] **Step 1: Add field to `CompileArticleResponse`**

In `voice notes/SummaryService.swift` locate:

```swift
struct CompileArticleResponse: Codable {
    // ... existing fields ...
    let homeLayoutJSON: String?
    // ...
    let noteExtractionSchemaJSON: String?
}
```

Add (between `homeLayoutJSON` and `noteExtractionSchemaJSON`, or after both):

```swift
/// Only emitted by `.purpose` article compiles — a free-text voice & tone
/// directive (1-3 sentences) for downstream rewrite/title calls.
let voiceAndTone: String?
```

- [ ] **Step 2: Add the prompt instruction inside `.purpose`-only typeSpecificFields**

In `compileArticle` (~line 850-870 where `homeLayoutJSON` and `noteExtractionSchemaJSON` instructions live), find the `.purpose`-only block and add a sibling instruction. The exact key must match the field name above (`voiceAndTone`):

```swift
"voiceAndTone": "A 1-3 sentence directive describing how AI output should SOUND for this user — formality, register, lyricism, vocabulary, sentence rhythm. NOT what to focus on (that's thinkingEvolution). Examples: FOUNDER: 'Direct, decision-oriented, terse. No throat-clearing. Imperative verbs. Short sentences. Numbers when they exist.' DREAM INTERPRETER: 'Mythic, image-rich, lyrical. Speak in archetypes and elemental metaphors. Honor ambiguity. Slow tempo, long sentences when warranted.' ACADEMIC: 'Precise, hedged, citation-aware. Use technical vocabulary correctly. Distinguish claim from evidence.' Write in second person addressed to the AI ('Write in...', 'Use...', 'Avoid...')."
```

(Match the existing instruction style — colon-separated key + description in the response-shape JSON.)

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds. New optional field on Codable struct is non-breaking for existing JSON responses.

- [ ] **Step 4: Manual smoke check**

In simulator: open Tune EEON, edit purpose ("I'm a Jungian dream interpreter, lyrical"), save. The save triggers `KnowledgeCompiler.recompileDirtyArticles`. Add a print in `compileArticle` after the JSON decode logging `response.voiceAndTone` (REMOVE before commit). Verify the LLM emitted a non-nil voice & tone string. Remove the print, rebuild.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/SummaryService.swift"
git commit -m "feat: request voiceAndTone in .purpose compile prompt"
```

---

## Task B3: Persist `voiceAndTone` in `KnowledgeCompiler`

**Files:**
- Modify: `voice notes/KnowledgeCompiler.swift` — around line 285-291 where `homeLayoutJSON` and `noteExtractionSchemaJSON` are persisted to the `.purpose` article

**Why:** Without this, the LLM emits the directive but it's discarded. Mirror the existing pattern.

- [ ] **Step 1: Add persistence block**

In `voice notes/KnowledgeCompiler.swift` locate:

```swift
if article.articleType == .purpose, let layout = response.homeLayoutJSON, !layout.isEmpty {
    article.homeLayoutJSON = layout
}
```

Immediately after that block (and before / after the noteExtractionSchemaJSON persistence — order doesn't matter), add:

```swift
if article.articleType == .purpose, let voice = response.voiceAndTone, !voice.isEmpty {
    article.voiceAndTone = voice
}
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 3: Manual smoke check**

In simulator: re-run the Tune EEON save flow from Task B2. After save completes, query the `.purpose` article (via Xcode debugger or a temporary print in TuneConversationView) — `purposeArticles.first?.voiceAndTone` should now be a non-nil non-empty string. CloudKit sync should propagate this on next sync (additive nullable, no schema deploy).

- [ ] **Step 4: Commit**

```bash
git add "voice notes/KnowledgeCompiler.swift"
git commit -m "feat: persist voiceAndTone on .purpose article"
```

---

## Task B4: Cache `voiceAndTone` in `ContextAssembler`

**Files:**
- Modify: `voice notes/ContextAssembler.swift` — add cached property, loader, and refresh wiring

**Why:** `ContextAssembler` is the synchronous, zero-SwiftData read path used by all AI call sites. The cached string lives here so call sites don't pay a per-call query.

- [ ] **Step 1: Add cached property and loader**

In `voice notes/ContextAssembler.swift`, in the `@Observable final class ContextAssembler` body, after `indexContext`, add:

```swift
/// Compiled voice & tone directive — injected into rewrite/title system prompts.
private(set) var voiceAndTone: String = ""
```

In the static loaders section (where `loadPurposeDirective`, `loadProfileContext`, `loadIndexContext` live), add:

```swift
@MainActor
private static func loadVoiceAndTone(in context: ModelContext) -> String? {
    let purposeRaw = "purpose"
    let descriptor = FetchDescriptor<KnowledgeArticle>(
        predicate: #Predicate { $0.articleTypeRaw == purposeRaw }
    )
    guard let article = (try? context.fetch(descriptor))?.first,
          let voice = article.voiceAndTone, !voice.isEmpty else { return nil }
    return "Write in this voice & tone:\n\(voice)"
}
```

In `refresh(from:)`, add the load call:

```swift
@MainActor
func refresh(from context: ModelContext) {
    purposeDirective = Self.loadPurposeDirective(in: context) ?? ""
    profileContext = Self.loadProfileContext(in: context) ?? ""
    indexContext = Self.loadIndexContext(in: context) ?? ""
    voiceAndTone = Self.loadVoiceAndTone(in: context) ?? ""
    print("[ContextAssembler] refreshed — purpose=\(String(purposeDirective.prefix(80))) profile=\(String(profileContext.prefix(60))) index=\(String(indexContext.prefix(60))) voice=\(String(voiceAndTone.prefix(60)))")
}
```

- [ ] **Step 2: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 3: Manual smoke check**

Run the app. The print on app launch (and after Tune EEON save) should now include `voice=Write in this voice & tone:...` for tuned users. Untuned users see `voice=` (empty), which is correct.

- [ ] **Step 4: Commit**

```bash
git add "voice notes/ContextAssembler.swift"
git commit -m "feat: cache voiceAndTone in ContextAssembler"
```

---

## Task B5: Compose `voiceAndTone` into `prefix(for:)` for `.rewrite` and `.title`

**Files:**
- Modify: `voice notes/ContextAssembler.swift` — add `AICallContext.includesVoiceAndTone`; update `prefix(for:)`

**Why:** The new cache is dead weight without a dispatch. `.rewrite` and `.title` are the only call sites that benefit — the rest already get the (heavier) `purposeDirective` which subsumes voice for non-stylistic calls.

- [ ] **Step 1: Add the predicate**

In `AICallContext` (in `voice notes/ContextAssembler.swift`), after `includesIndex`, add:

```swift
/// Whether this call site benefits from the user's voice & tone directive.
/// Narrow on purpose: only stylistic calls (rewrite + title) — analysis/extraction
/// already get the heavier `purposeDirective`.
var includesVoiceAndTone: Bool {
    switch self {
    case .rewrite, .title: return true
    case .extraction, .rag, .dailyBrief, .analysis, .intent, .tags, .fillerWords: return false
    }
}
```

- [ ] **Step 2: Update `prefix(for:)` to compose voice & tone into system**

In `prefix(for:)`, the current system construction is:

```swift
let system: String
if callContext.includesPurpose && !shared.purposeDirective.isEmpty {
    system = shared.purposeDirective + "\n\n"
} else {
    system = ""
}
```

Replace with:

```swift
var systemParts: [String] = []
if callContext.includesPurpose && !shared.purposeDirective.isEmpty {
    systemParts.append(shared.purposeDirective)
}
if callContext.includesVoiceAndTone && !shared.voiceAndTone.isEmpty {
    systemParts.append(shared.voiceAndTone)
}
let system = systemParts.isEmpty ? "" : systemParts.joined(separator: "\n\n") + "\n\n"
```

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Manual smoke check**

In simulator with a tuned purpose ("Jungian dream interpreter, lyrical"):

1. Capture a note ("had a weird dream about water and stairs").
2. Open the note → Rewrite → pick "Magic" or "Email". The rewrite should now reflect mythic/lyrical voice (not generic professional prose).
3. Auto-generated title should also reflect that voice (3-6 words, but stylistic).
4. Confirm baseline extraction (decisions, actions) still works — those don't get voice & tone.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/ContextAssembler.swift"
git commit -m "feat: dispatch voiceAndTone to .rewrite and .title call sites"
```

---

## Task B6: Surface compiled `voiceAndTone` in `TuneConversationView`

**Files:**
- Modify: `voice notes/TuneConversationView.swift` — add a third row to the existing extraction lens card (or add a new compact card) showing the compiled voice & tone directive

**Why:** The user can't trust what they can't see. Existing UX already shows `compiledPurposeDirective` ("What EEON now understands") below the purpose seed. Mirror that for voice & tone.

- [ ] **Step 1: Add a derived property**

In `voice notes/TuneConversationView.swift`, near the top of the struct where `compiledPurposeDirective` is defined (~line 71-76), add:

```swift
private var compiledVoiceAndTone: String? {
    guard let article = purposeArticles.first,
          let voice = article.voiceAndTone, !voice.isEmpty else { return nil }
    return voice
}
```

- [ ] **Step 2: Render it inside the purpose review card**

Find the `reviewCard` invocation for purpose (~line 150-158). The card already accepts a `compiledDirective` parameter. We can either:

**Option A (simpler):** Concatenate. Change:

```swift
compiledDirective: compiledPurposeDirective,
```

…to display both directives stacked:

```swift
compiledDirective: [compiledPurposeDirective, compiledVoiceAndTone]
    .compactMap { $0 }
    .joined(separator: "\n\n— Voice & tone —\n"),
```

**Option B (more polished):** Add a second, distinct row inside `reviewCard` (modify the function signature to accept `compiledVoiceAndTone: String?` as well, and render in its own indigo-tinted card with a "Voice & tone" subheader).

Pick Option A for v1 — it's a single-line change and matches the existing visual language. If user wants more polish later, that's Option B.

- [ ] **Step 3: Build verify**

Run: `xcodebuild -scheme "voice notes" -configuration Debug build`
Expected: succeeds.

- [ ] **Step 4: Manual smoke check**

In simulator with a tuned purpose: navigate to Tune EEON. The "What EEON now understands" preview under the purpose card should now show two paragraphs — the existing thinking-evolution directive, then a "— Voice & tone —" separator, then the new directive. Both update after Regenerate.

- [ ] **Step 5: Commit**

```bash
git add "voice notes/TuneConversationView.swift"
git commit -m "feat: surface compiled voiceAndTone in Tune EEON"
```

---

## Task W1: Version bump

**Files:**
- Modify: `voice notes.xcodeproj/project.pbxproj` — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (8 occurrences each across configs)

**Why:** Per project memory `feedback_version_bump.md`: always bump both. This is a feature release (Tune coverage v2), so a minor bump (3.4.0) is more honest than a patch (3.3.2). Build number rolls forward from the last shipped (109).

- [ ] **Step 1: Bump versions**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
sed -i '' 's/CURRENT_PROJECT_VERSION = 109;/CURRENT_PROJECT_VERSION = 110;/g; s/MARKETING_VERSION = 3.3.1;/MARKETING_VERSION = 3.4.0;/g' "voice notes.xcodeproj/project.pbxproj"
```

- [ ] **Step 2: Verify all 16 lines bumped**

```bash
grep -nE "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "voice notes.xcodeproj/project.pbxproj" | sort -u
```

Expected: 8 lines `CURRENT_PROJECT_VERSION = 110;` and 8 lines `MARKETING_VERSION = 3.4.0;`. No remaining `109` or `3.3.1`.

- [ ] **Step 3: Commit**

```bash
git add "voice notes.xcodeproj/project.pbxproj"
git commit -m "chore: bump to 3.4.0 (build 110) for Tune coverage v2"
```

---

## Task W2: Mac Catalyst archive

**Files:**
- No source modifications. Uses existing `build/ExportOptions-MacCatalyst.plist`.

**Why:** Produce the artifact for App Store distribution. Per the 2026-05-07 conversation, CLI export is blocked by stale Distribution profile cache, so the archive is built via CLI but the upload happens through Xcode Organizer.

- [ ] **Step 1: Clean prior archive**

```bash
cd "/Users/shawncarpenter/projects/voice notes"
rm -rf "./build/EEON-MacCatalyst.xcarchive"
```

- [ ] **Step 2: Archive**

```bash
xcodebuild archive \
  -scheme "voice notes" \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath "./build/EEON-MacCatalyst.xcarchive"
```

Expected: completes with exit 0 in ~5-15 minutes. Same Swift 6 actor-isolation warnings as baseline.

- [ ] **Step 3: Verify archive exists**

```bash
ls -la "./build/EEON-MacCatalyst.xcarchive"
```

Expected: directory exists with `.xcarchive` bundle structure (Info.plist, Products/, dSYMs/).

- [ ] **Step 4: Hand off to Xcode for upload**

- Open Xcode → **Window → Organizer** (`⌘⇧9`)
- If the archive doesn't appear, drag `build/EEON-MacCatalyst.xcarchive` onto the Organizer window
- Select the archive → **Distribute App** → **App Store Connect** → **Upload**
- Xcode regenerates the right Distribution profile via the IDE account integration
- Repeat for iOS variant if you want both platforms shipped on 3.4.0 / 110

This step is manual — no CLI command. The plan is complete once the upload is initiated.

---

## Self-Review

**Spec coverage check:**
- ✅ Tier A.1 (compileArticle context) — Task A1
- ✅ Tier A.2 (compileIndex context) — Task A2
- ✅ Tier A.3 (generateTitle context) — Task A3
- ✅ Tier A.4 (todayThree defensive guarantee) — Task A4
- ✅ Tier B.1 (voiceAndTone storage) — Tasks B1, B3
- ✅ Tier B.2 (compile prompt for voiceAndTone) — Task B2
- ✅ Tier B.3 (cache + dispatch) — Tasks B4, B5
- ✅ Tier B.4 (UI surface for compiled directive) — Task B6
- ✅ Wrap-up — Tasks W1, W2

**Placeholder scan:** No "TBD", "implement later", "similar to" without code shown. Each task has the exact code block or sed command needed.

**Type consistency:**
- `voiceAndTone: String?` consistent across `KnowledgeArticle`, `CompileArticleResponse`, `ContextAssembler`.
- `AICallContext.includesVoiceAndTone` referenced consistently in B5 prefix construction.
- `compiledVoiceAndTone` derived property name consistent in TuneConversationView (B6).
- Persist key naming matches: `response.voiceAndTone` → `article.voiceAndTone` (B3), parallel to existing `response.homeLayoutJSON` → `article.homeLayoutJSON`.

**Risks called out:**
- Task A1: avoid circular reference — explicit switch on article type, only inject for `.topic` / `.person`.
- Task B5: voice & tone for `.title` is new behavior; auto-titles will visibly change for tuned users. Acceptable per the goal of this batch.
- Task W2: CLI export blocked by signing profile staleness — handoff to Xcode Organizer is the documented path, not a workaround.
