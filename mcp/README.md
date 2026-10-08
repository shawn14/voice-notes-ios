# EEON agent access

EEON is a voice and project memory source for the user's own agent. The primary connection is the hosted, URL-only OAuth connector at **https://www.eeon.com/api/mcp**. The phone uploads an opt-in encrypted text mirror; audio is not mirrored. Folder export and this local stdio package are optional data-export fallbacks.

## Connect an agent

On iPhone: EEON → Settings → AI agents → **Let AI agents read my notes**. Then add the hosted connector on the computer and approve the browser's QR/code from EEON. Do not paste tokens into an agent config or chat.

Claude Code (real terminal):

```sh
claude mcp add --transport http eeon https://www.eeon.com/api/mcp
claude mcp login eeon
```

Codex:

```sh
codex mcp add eeon --url https://www.eeon.com/api/mcp
codex mcp login eeon
```

Gemini CLI:

```sh
gemini mcp add --transport http eeon https://www.eeon.com/api/mcp
```

Then start Gemini and run `/mcp auth eeon`. Gemini's official docs describe OAuth for remote HTTP servers; this setup is not yet verified end to end with an actual Gemini session.

Grokbot or another agent: use its supported remote MCP HTTP + OAuth client with the same URL. No Grokbot installation or authoritative client configuration was found on this Mac; do not invent commands or claim tested compatibility. If that client cannot authenticate a remote connector, use the copyable agent brief or Markdown export instead. A fallback does not provide ongoing access to the note library.

## Founder workflow

Capture an idea or project update. On the founder handoff branch, Note Detail → **Prepare agent brief** lets the user choose Plan, Build, Draft, or Review, edit the request, inspect the source context, and copy it into the chosen agent workspace. This native UI remains unverified until Xcode's matching iOS platform is restored. The agent reads the cited source IDs through `get_note` when connected, works in its own project workspace, and reports output, verification, and unfinished work. EEON does not implicitly start an unattended execution queue.

## Verification and support status

- The deployed raw OAuth lifecycle has a standing 20-check test in `v0-eeon-app-design/scripts/e2e-agent-oauth.mjs`.
- Standard MCP SDK proof: `node mcp/test/hosted-client.mjs https://www.eeon.com`. It uses a disposable encrypted mirror, actual SDK OAuth discovery/PKCE and HTTP transport, lists tools, finds/reads the source, and revokes the connection. It never uses customer notes, saved agent settings, or model calls. A protocol pass is not a native-client pass.
- Native Codex read-and-plan proof is available with `node test/hosted-client.mjs https://www.eeon.com --native-codex --receipt-dir=<absolute-output-folder>`. It uses the installed signed-in CLI, temporary SDK-issued OAuth credentials, only get_note preapproved, ignored user config, and an ephemeral workspace. This is actual note reading and local artifact production, not native MCP login proof. The same script supports `--native-claude`: signed-in Claude Code with restricted Write and get_note, temporary0600 config and no session persistence. Native Claude read-and-plan passed independently; native OAuth login remains untested. Gemini and Grokbot execution still need receipts before advertised support. Installed CLI syntax was inspected for Claude Code2.1.294, Codex0.157.1, Gemini0.61.0 on2026-10-08.
- A stale Authorization header disables Claude Code OAuth. Remove the stale entry and re-add URL-only. Turning AI agents off on the phone revokes agents and deletes the mirror.

Official setup references: [Claude Code](https://code.claude.com/docs/en/mcp), [Codex](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Gemini CLI](https://geminicli.com/docs/tools/mcp-server/).

## Local fallback

```sh
cd mcp
npm ci
npm run build
npm test
node dist/src/index.js --vault "<EEON export folder>"
```

A client with stdio MCP support can launch that command. The export must already exist and be current; the local server does not sync the phone. This is optional export support, not the recommended connection.

**Superseded:** the old primary setup through `eeon-connect-claude`, `eeon-cloudkit-install-claude`, or a pasted CloudKit user token. Those utilities remain for explicit legacy diagnostics. CloudKit management tokens cannot read private notes; rotating web-auth tokens cannot promise durable unattended access. Do not use them as the default onboarding path.

## Tools

- `search_memory`
- `get_note`
- `recent_notes`
- `list_articles`
- `get_article`
- `open_loops`
- `people`
- `vault_status`

`list_articles`, `get_article`, `open_loops`, and `people` work in CloudKit mode and in the markdown fallback. CloudKit mode maps private `CD_Note` records plus compiled `CD_KnowledgeArticle` records into the same read-only memory document shape.

Native Gemini probe: `node test/hosted-client.mjs https://www.eeon.com --native-gemini --receipt-dir=<absolute-folder>`. Uses isolated Gemini storage and privately reuses existing Google OAuth login. Current native attempt is blocked by Google client eligibility before any source/task call; see `../docs/founder/native-gemini/`. This is not a compatibility pass.
