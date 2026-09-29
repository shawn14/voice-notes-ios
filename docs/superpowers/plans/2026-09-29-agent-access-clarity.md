# Plan: "Your AI agents can read your notes" — make it real, then make it obvious

**Date:** 2026-09-29 · **Status:** proposed, nothing built · **Owner decision needed:** §4

## The use case (Shawn, 2026-09-29)

> If you have notes, any of my AI agents can access them. If I recorded a note about a
> project, it could read that and do it.

Concretely: record on the phone → open Claude Code / Codex / Cursor anywhere → "read my
latest EEON note about <project> and do it" → the agent finds it with `search_memory`,
reads it with `get_note`, and works. No repo, no Mac-specific setup, still works next week.

## 1. What is true today (verified live 2026-09-29, not from notes)

| Check | Observed |
|---|---|
| Hosted connector `POST https://www.eeon.com/api/mcp` `tools/list` | Up. 12 tools: search_memory, get_note, recent_notes, list_articles, get_article, open_loops, people, list_orders, claim_order, renew_lease, complete_order, vault_status |
| Same connector, `vault_status` / `recent_notes` with the token in `~/.claude.json` (global `eeon` entry) | `-32001 Connection not found or revoked. Reconnect at https://eeon.com/connect.` |
| Project-scoped local `eeon` stdio server (shadows the hosted one inside this repo) | Failed to connect this session: `mcp/dist` had never been built (no `node_modules`). Built it: `npm run doctor` → **blocked**, cktool CloudKit user token missing/expired |
| `/api/connect/refresh` calls in production, last 14 days (Vercel runtime logs) | **0** — the phone's foreground refresh (`AIAccessService.refreshCloudKitAccessIfPossible`) never reaches the server |
| `/api/mcp` requests, last 14 days | **383,605**, nearly all `GET 200`, several per second right now |
| In-app entry point | Settings → Connections → "Set up AI access" (4th row). Shows raw URL + masked token + a `claude mcp add` string. "Connected" = a token string exists in UserDefaults |
| App Store copy (3.9.0) | Agent/MCP framing deliberately removed during the 2026-09-10 ASO pass |

**Read of it:** the capability exists and was proven end to end on 2026-09-02/03 (74→94
real notes read from Production CloudKit). It is not *reliable*, because private-note reads
depend on an Apple CloudKit web-auth token that Apple limits to 30 minutes (2 weeks with
"Keep me signed in"), and the refresh that was supposed to keep it alive never fires. When
it dies, nothing in the app says so. You can't make a feature clear while it only works
some of the time, so reliability comes first in this plan.

## 2. Plumbing fixes (no product decision needed)

1. **Stop the GET reconnect storm.** `app/api/mcp/route.ts` `GET` returns `200` JSON. The
   MCP Streamable HTTP spec says a server that doesn't offer an SSE stream on GET must
   answer `405 Method Not Allowed`. Clients read our `200` as a stream that ended and
   reconnect immediately, which is where the 383k requests come from. Fix: `405` with `Allow: POST`.
   Proof: `GET` count per minute drops to ~0 in runtime logs within an hour of deploy.
2. **Find out why refresh never fires.** Candidates to check on the device, in order:
   (a) Debug/devicectl installs carry the unresolved `$(EEON_CLOUDKIT_API_TOKEN)`
   placeholder, so `cloudKitAPIToken` is nil and the function returns `false` without
   logging anything; (b) `CKFetchWebAuthTokenOperation` throws and only sets `lastError`;
   (c) no `connectorToken` on the phone. Pull the app prefs with `devicectl` (known
   technique, STATUS 2026-09-03) and log the outcome of each refresh attempt instead of failing silently.
3. **One connector entry, not two.** Remove the project-scoped stdio `eeon` entry for
   this repo (it shadows the hosted one and needs `cktool` user auth, a developer-only
   path), or keep it only as a documented dev fallback. Replace the revoked token in the
   global entry after Shawn reconnects.
4. **Add an MCP `instructions` string** on `initialize` so every agent knows the workflow
   without being told: *"When the user refers to a note, idea, or project they recorded,
   call search_memory, then get_note on the best match, then act on its content."*

## 3. Make it obvious in the app (after §2 is green)

- **Name the job, not the protocol.** Rename "Set up AI access" → **"Use notes in your AI
  agents"** and move it to its own top-level Settings section. Subtitle is live state, not token presence.
- **Honest status, driven by the server.** Add a cheap `GET /api/connect/status` (bearer)
  returning `{ state: ready | needs_reconnect, notes, lastReadAt, lastAgentCallAt }`.
  Row shows **Ready · 94 notes · last read by an agent 3 min ago**, or an orange
  **Reconnect needed** row. This replaces `isConnected = token exists`, the same
  mistake as `GoogleCalendarService.isConnected` before 2026-09-08.
- **Per-tool setup, one tap each.** Segmented picker: Claude Code (copy `claude mcp add …`),
  Codex (copy the `config.toml` block), Cursor (one-tap `cursor://` MCP install deeplink).
  Claude.ai and ChatGPT custom connectors expect OAuth rather than a pasted bearer
  header. Verify that before listing them. The current footer ("ChatGPT: add a custom
  connector with the same URL and header") is probably wrong.
- **"Try it" card** under setup, showing the exact sentence to type:
  *"Read my latest EEON note about <most recent project> and do it."* The project name
  is filled in from the user's real projects.
- **Hand-off from a note.** Note ⋯ → **"Send to an agent"** copies a ready prompt:
  `Use the EEON connector: get_note <id> ("<title>") and implement it.` This is the
  whole use case in one tap, and it teaches the capability exactly when someone needs it.
- **One-time Home hint** after the 3rd note that mentions a project: "Your AI agents can
  read this note →". Dismissible, not a permanent card.
- Website `eeon.com/connect` shows the same per-tool steps as the app.

## 4. The decision only Shawn makes: how durable is "anywhere"?

The CloudKit-proxy design cannot promise "connect once, works next week" (Apple token
lifetime). Two honest options:

- **A. Keep the proxy (current locked privacy posture).** Fix refresh, show Reconnect
  honestly. Agents keep working only if the phone opens EEON at least every ~2 weeks,
  and the user sometimes has to reconnect. No privacy change.
- **B. Opt-in "agent-readable notes" mirror (recommended).** Same pattern as the durable
  order queue, which already survived expired CloudKit auth on 2026-09-04: the phone
  pushes each new or edited note, encrypted per connection, to the hosted store, and
  `search_memory` / `get_note` read that store first. Off by default, one explicit toggle,
  Disconnect deletes the mirror. **This reverses the locked line "notes are never copied
  to EEON servers"**. It needs a privacy-label update, an App Review note, and new
  website copy. It is the only design that makes "any agent, anywhere, any time" true.
  Option: scope it to notes that mention a project, if full mirroring feels like too much.

## 5. Done means (proof gates)

1. Record a note about a project on the phone → within 2 min, from a machine with no
   repo, `search_memory` finds it and `get_note` returns the text.
2. The same check passes again **3 days later** with no reconnect (option B), or the app
   shows "Reconnect needed" before the agent fails (option A).
3. `/api/mcp` GET traffic ≈ 0; `/api/connect/refresh` shows real calls from the phone.
4. A fresh-context refuter (rule #29) runs gate 1 against production.

## Order of work
§2.1 + §2.4 (website, one deploy) → §2.2 diagnosis on device → decision §4 → §3 UI → gates.
