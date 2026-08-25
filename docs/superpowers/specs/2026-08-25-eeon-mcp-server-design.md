# EEON MCP Server — Design

**Date:** 2026-08-25
**Status:** Approved in conversation (Shawn), pending written review
**Closes:** TODOS.md #4 — "MCP server over EEON memory (every conversation becomes AI context)"
**Companion:** `docs/pocket-teardown-thesis.md` → Gap status; Pocket ships ChatGPT / Claude / Cursor / MCP under "every conversation becomes AI context".

## 1. Goal

Any AI assistant on Shawn's Mac — Claude Code first, then Claude Desktop and Cursor — can ask EEON's memory questions ("what did I decide about the pricing page", "what's still open with Lena", "what did I capture this week") and get answers grounded in the user's notes, the compiled knowledge articles, and the extracted decisions / actions / commitments.

EEON's edge over Pocket here is not the protocol; it is that EEON's context is **pre-synthesized** — compiled `KnowledgeArticle`s per person / project / topic — where Pocket exposes raw transcripts.

## 2. Non-goals (v1)

- **No writes.** No tool creates, edits, completes, or deletes anything in EEON. (A v2 may add an inbox folder the app ingests.)
- **No hosted server.** Nothing runs off the user's devices; ChatGPT and other remote-only clients are out of scope until a hosted variant is specced separately. The tool schema below is designed so a hosted variant would be the same interface.
- **No new backend, no accounts, no API keys for EEON itself.**
- **Not a Mac app.** The server is a command-line process a client launches over stdio.

## 3. Decisions locked (and why)

| Decision | Choice | Why |
|---|---|---|
| Where it runs | Local on the Mac, over the folder EEON already exports to | Zero infra; notes never leave the user's devices; Claude Code is the client that matters and it launches stdio servers natively. A hosted variant would change EEON's "on-device + iCloud, no third-party" posture and needs its own spec. |
| Data source | The markdown export folder (iCloud Drive / Google Drive / Obsidian via Files) | `DocumentExportService` already writes a file per note on every save. No second sync path; the folder stays human-readable in Obsidian. |
| Scope | Notes **with structured frontmatter** + compiled articles + extractions | The compiled view is the differentiator; extractions are what "what's open" questions need. |
| Direction | Read-only | Simplest trust story; consistent with "never delete user notes". |
| Search | BM25 first; semantic optional when `OPENAI_API_KEY` is set | Works offline with no key; semantic uses the same embedding model the app already sends note text to. |
| Manifest | **None.** Every file carries its own `id` in frontmatter | A manifest rewritten per note save is O(notes) per save (rule 19); the server derives everything from the files. |
| Language | Node 22 + TypeScript, `@modelcontextprotocol/sdk` | Same SDK as `stock-alarm-pro-v2`'s hosted MCP; Node 22.23 is on the Mac. |
| Location | `mcp/` in this repo | Ships with the app version whose export format it reads; git stays the source of truth (rule 0.1). |

## 4. Export format (app side)

`DocumentExportService` is upgraded; filenames and the never-delete rule are unchanged.

### 4.1 Note file — `YYYY-MM-DD-<slug>-<id4>.md`

```markdown
---
eeon: 1
id: 6F1C…-…                      # Note.id (full UUID)
kind: note
created: 2026-08-25T14:02:11Z
updated: 2026-08-25T14:09:40Z
title: Standup with Lena
source: voice                     # voice | web | document | audioImport | derived
project: EEON                     # Project.name via Note.projectId, if any
people: [Lena Ortiz, Marco]       # Note.mentionedPeople
topics: [pricing, onboarding]     # Note.topics
tone: focused                     # Note.emotionalTone, if any
format: Meeting Minutes           # Note.summaryFormat, if any
calendar_event: Standup           # Note.calendarContext?.title
attendees: [Lena Ortiz, Marco]    # Note.calendarContext?.attendees
audio_seconds: 412
decisions:
  - text: Ship the blue icon this week
    status: Active
actions:
  - text: Send Lena the pricing draft
    done: false
    due: Friday
    owner: Me
commitments:
  - who: Lena
    what: Review the onboarding copy
    done: false
---

# Standup with Lena

_25 August 2026 at 2:02 PM · EEON_

<enhancedNoteText, else content>

---

**Original transcript**

<transcript, when different from the body>
```

- Extractions are looked up by `sourceNoteId == note.id` at export time (`ExtractedDecision`, `ExtractedAction`, `ExtractedCommitment`). Empty lists are omitted.
- Strings are YAML-quoted when they contain `:`/`#`/quotes/leading symbols; the writer escapes, never trusts.
- `eeon: 1` is the schema version. The server treats files without frontmatter as **legacy notes** (§6.5).

### 4.2 Article file — `articles/<kind>-<slug>-<id4>.md`

One per compiled `KnowledgeArticle` (kinds: person, project, topic, self, purpose, reference, index).

```markdown
---
eeon: 1
id: 3B…                           # KnowledgeArticle.id
kind: article
article_type: person              # KnowledgeArticleType raw value
name: Lena Ortiz
updated: 2026-08-25T13:50:00Z     # lastCompiledAt
mentions: 14
last_mentioned: 2026-08-24T…
open_threads:
  - thread: Pricing page copy
    status: waiting
    days_open: 6
timeline:
  - date: 2026-08-19
    event: Agreed to split onboarding into two screens
connections:
  - article: Onboarding
    reason: Lena owns the copy
decisions:
  - decision: Blue accent, not coral
    status: resolved
    date: 2026-08-20
linked_notes: [6F1C…, 91A0…]      # linkedNoteIds
---

# Lena Ortiz

<summary>

## Relationship context   (when present)
## Thinking evolution     (when present)
```

- Written by `KnowledgeCompiler` at each of the three sites that set `isDirty = false` / `lastCompiledAt`, through one `DocumentExportService.shared.export(article:)`.
- `.self` and `.purpose` articles are exported too — they are the user's own profile and are useful context — but the raw seed notes (`profileSeed` / `purposeSeed` source types) are **never** exported, same as today's feed rule.

### 4.3 When the app exports

Today only the post-extraction pass exports. v1 adds `export(note:)` at every site that changes what a reader would see:

| Change | Site |
|---|---|
| Extraction finished (exists) | `IntelligenceService.processNoteSave` |
| Hand edit saved | `NoteDetailView.saveEnhancedEdit` |
| Adjust / format switch succeeded | `NoteDetailView.applyAdjustment`, `handleRewriteTemplate` |
| Title, project, favorite, archive changed | the respective setters in `NoteDetailView` / feed context menu |
| Action completed / added | `TasksView.toggle`, `TasksView.addTask` (exports the source note) |
| Article recompiled | `KnowledgeCompiler` (three sites) |
| "Export all notes now" | `SettingsView` (exists) — now also exports all articles |

Each is a no-op unless export is enabled and a folder is set. Export is synchronous file I/O on the main actor today; if profiling shows a stall on large notes, move the write to a background task — not before.

## 5. Server architecture (`mcp/`)

```
mcp/
  package.json          # name eeon-mcp, private, "bin": dist/index.js
  tsconfig.json
  src/
    index.ts            # CLI: --vault <path> | EEON_VAULT; starts stdio server
    vault.ts            # scan folder, parse frontmatter (gray-matter), watch (chokidar)
    model.ts            # NoteDoc / ArticleDoc types; legacy-note adapter
    search.ts           # MiniSearch (BM25-style) + optional embeddings + RRF fusion
    embeddings.ts       # OpenAI text-embedding-3-small, dimensions 256, disk cache
    tools.ts            # tool + resource registration
    icloud.ts           # .icloud placeholder detection + `brctl download`
  test/
    fixtures/vault/     # 6 notes (2 legacy), 3 articles, 1 .icloud placeholder
    e2e.test.ts         # node --test; drives the server through the SDK client
  README.md             # install for Claude Code / Claude Desktop / Cursor
```

- **Startup:** scan `*.md` and `articles/*.md`, parse, index. Thousands of small files parse in well under a second; there is no cross-file dependency.
- **Live updates:** chokidar on the vault; add/change re-parses one file and updates the index; unlink removes it from the index (the app never deletes, but the user might in Obsidian).
- **Index:** MiniSearch over fields `title`(boost 3), `body`, `people`(2), `topics`(2), `project`(2), `name`; prefix + fuzzy 0.2. Articles and notes share one index with a `kind` field for filtering.
- **Semantic (optional):** if `OPENAI_API_KEY` is present, embed `title + body` (first 6k chars) with `text-embedding-3-small`, `dimensions: 256`. Cache: `~/.eeon-mcp/<vault-hash>/embeddings.bin` (Float32, 256 per row) + `embeddings.json` (content-hash → row). Only changed content is re-embedded. Search fuses BM25 and cosine rankings with reciprocal rank fusion (k = 60) — no score normalization to get wrong.
- **Memory:** ~2 KB per note for the index + 1 KB for the 256-dim vector; 10k notes ≈ 30 MB. Fine.
- **Never writes into the vault.** The only writes are the embeddings cache under `~/.eeon-mcp/`.

## 6. Tools and resources

All tools are read-only. Results are JSON text (the StockAlarm precedent) except `get_note` / `get_article`, which return the markdown so the model reads it directly.

### 6.1 Tools

| Tool | Input | Output |
|---|---|---|
| `search_memory` | `query: string`, `limit?: 1–50 (10)`, `kind?: note\|article\|any (any)`, `since?: ISO date` | `[{ id, kind, title, date, project, score, snippet, file }]` ranked |
| `get_note` | `id: string` (UUID, or legacy `file:<name>`) | the note's markdown incl. frontmatter |
| `recent_notes` | `days?: number (7)`, `limit?: 1–100 (20)` | `[{ id, title, date, project, people, topics, first_line }]` newest first |
| `list_articles` | `article_type?: person\|project\|topic\|self\|purpose\|reference\|index` | `[{ id, name, article_type, updated, mentions, open_thread_count }]` |
| `get_article` | `name: string` (case-insensitive; `id` also accepted) | the article's markdown incl. frontmatter |
| `open_loops` | `person?: string`, `project?: string` | `{ actions: [{ text, due, owner, note_id, note_title, date }], commitments: [{ who, what, note_id, date }], threads: [{ article, thread, status, days_open }] }` — only incomplete / open |
| `people` | — | `[{ name, mentions, last_mentioned, open_commitments }]` from person articles, most recent first |
| `vault_status` | — | `{ vault, notes, legacy_notes, articles, last_change, icloud_placeholders, semantic: on\|off }` |

- `snippet` is ~200 characters around the best-matching term, or the first line for semantic-only hits.
- Errors are returned as tool errors with one plain sentence ("Vault not found at <path>. Pass --vault or set EEON_VAULT."), never as thrown exceptions that kill the process.

### 6.2 Resources

- `eeon://note/{id}` and `eeon://article/{name}` as resource templates, returning the same markdown as the tools.
- `resources/list` returns all articles plus the 50 most recent notes (lists must stay small; search is the way in).

## 7. Configuration and install

- Vault path: `--vault <path>` argument or `EEON_VAULT` env. No default: iCloud Drive folders live at `~/Library/Mobile Documents/com~apple~CloudDocs/<folder>` and the folder name is the user's choice in Files.
- Optional: `OPENAI_API_KEY` env (semantic search). `EEON_MCP_CACHE` overrides the cache dir.
- Build once: `cd mcp && npm ci && npm run build`.
- Claude Code: `claude mcp add eeon -- node "<repo>/mcp/dist/index.js" --vault "<path>"`.
- Claude Desktop: `mcpServers.eeon = { command: "node", args: ["<repo>/mcp/dist/index.js", "--vault", "<path>"] }` in `~/Library/Application Support/Claude/claude_desktop_config.json`.
- Cursor: same shape in `.cursor/mcp.json`. The README carries all three verbatim.

## 8. Failure modes

| Condition | Behaviour |
|---|---|
| Vault path missing / not a directory | Server starts; every tool returns the one-sentence error; `vault_status` reports it. Never exits. |
| iCloud "Optimize Mac Storage" placeholders (`.<name>.icloud`) | Counted in `vault_status`; the server runs `brctl download <file>` for each (fire-and-forget, macOS built-in) and indexes the file when the watcher sees it materialize. |
| Malformed frontmatter | File indexed as a legacy note (title from `# heading` or filename, body = whole file); one warning line to stderr; nothing else affected. |
| Notes exported before the upgrade (no frontmatter) | Legacy notes: searchable, `get_note` by `file:<name>`; no people/topics/extractions until "Export all notes now" rewrites them in place. `vault_status.legacy_notes` shows how many. |
| `OPENAI_API_KEY` set but the API fails | Semantic silently off for that run (stderr warning); BM25 keeps working. |
| Vault with 0 files | Tools return empty results, not errors. |
| Watcher lost (folder renamed) | Same as missing vault until the path exists again; no crash. |

## 9. Testing

1. **End-to-end (the proof, built first):** `mcp/test/e2e.test.ts` spawns `dist/index.js --vault test/fixtures/vault` and drives it with `@modelcontextprotocol/sdk`'s `Client` over `StdioClientTransport`. Asserts: `search_memory("pricing")` ranks the pricing note first; `get_note` returns frontmatter round-tripped; `open_loops` returns exactly the incomplete action and open thread in the fixtures; legacy notes are searchable and counted; a `.icloud` placeholder is counted; `vault_status` is correct; a bad `--vault` yields the error text, not a crash. `node --test`, no extra test framework.
2. **Watcher:** the e2e test writes a new note into a temp copy of the fixture vault and asserts it is searchable within 2 s.
3. **App side:** exporting a real note from a DEBUG build and reading the file back with the server's parser (`vault_status.legacy_notes == 0` for that file). This is the only step that needs a device/simulator run.
4. **Real system:** `claude mcp add eeon …` against the actual vault and one real question in Claude Code. Reported as done only when observed, not when the tests pass (rule 21).

## 10. Privacy and security

- Read-only by construction: no tool has a write path; the vault is opened read-only; the only writes are the embeddings cache under `~/.eeon-mcp/`.
- No network unless `OPENAI_API_KEY` is set — then note text goes only to OpenAI's embeddings endpoint, which the app already sends the same text to.
- No listener, no port: stdio only; the client process owns the server's lifetime.
- The export folder already reflects the user's choice to put notes in Files; the server adds no new copy of the data.

## 11. Rollout

1. App: export upgrade (frontmatter, articles, re-export sites) — ships with the next EEON build; existing users see no change until they tap "Export all notes now".
2. Server: `mcp/` builds and passes e2e on the Mac; README install for the three clients.
3. Shawn's Mac: install for Claude Code; verify one real question; then Claude Desktop / Cursor.
4. Docs: CLAUDE.md gains a `mcp/` section; CAPABILITIES.md gets a 4-line entry ("local MCP over a markdown vault") since the pattern is reusable for any app that exports markdown.

## 12. Out of scope, explicitly

Hosted/remote variant · write tools · ChatGPT · Windows/Linux · a Mac app UI · full-text of audio · indexing Obsidian files EEON did not write (only `eeon: 1` files and legacy EEON-named files are indexed; the server ignores other markdown in the folder so a shared vault stays clean).
