# Make AI Access Real — EEON Connector for Claude / ChatGPT / Cursor

**Date:** 2026-09-02
**Why:** The in-app "AI access" screen advertises a capability no end user can
enable. The only working path is a Mac + repo + Terminal + pasted CloudKit
token (`mcp/src/connect-claude.ts`). A differentiator users can't turn on is
not a differentiator. Goal: a professional connects EEON's memory to their AI
tool in a few clicks, no repo, no Terminal.

## Locked-decision override (read first)
`CLAUDE.md` locks: "Do not add HeyPocket-style hosted remote MCP/API,
account-wide cloud vault, OAuth fan-out, or third-party write-back without
explicit product/security approval." Making this real for non-developers needs
a hosted remote MCP. Shawn approved overriding that on 2026-09-02. The design
below minimizes the exposure that rule was protecting.

## Privacy posture (the point that keeps the wedge)
The hosted server does NOT copy notes into an EEON database. It stores only a
per-user, revocable CloudKit **web-auth token** and *proxies read-only queries*
of the user's own private iCloud notes on demand. Notes stay in the user's
iCloud. EEON holds a scoped read token, encrypted, revocable, never the content.
This is the difference between "we host a proxy to your iCloud" and "we have
your notes." Say it plainly in the connect UI and the privacy policy.

## What already exists (reuse, don't rebuild)
- The MCP tool set (`search_memory`, `get_note`, `recent_notes`, `open_loops`,
  `people`, `list_articles`, `get_article`, `vault_status`) in `mcp/src/tools.ts`.
- CloudKit Web Services reader with web-auth token support
  (`loadCloudKitSnapshot`, `EEON_CLOUDKIT_WEB_AUTH_TOKEN`, token file rotation).
- A Sign-in-with-Apple CloudKit web-auth URL generator
  (`fetchCloudKitSignInURL`) — the foundation of the connect flow.
- The expired-token re-auth signal (2026-09-02).

What's missing: an HTTP/remote transport (server is stdio-only,
`index.ts:115`), hosting, a per-user auth handshake, and a real Connect UI.

## Phases

### Phase 1a (fast win, days) — publish the local installer, no repo
Publish the existing server to npm as `@eeon/mcp` so a Mac user runs
`npx @eeon/mcp connect` (no clone, no build). It edits the Claude/Cursor MCP
config and walks the CloudKit token, reusing `install-claude.ts` +
`connect-claude.ts`. Ships the current desktop path to non-repo users while
Phase 1+ is built. Privacy-first intact (local, on-device token).
Does NOT cover ChatGPT or non-Mac.

### Phase 1 — remote MCP transport
Add a streamable-HTTP/SSE transport to the server alongside stdio (same tools,
same CloudKit reader). Per-request bearer token identifies the user. Deploy to
Cloud Run or Vercel at `mcp.eeon.com`. Read-only; rate-limited; single-writer
never (reads only).

### Phase 2 — connect flow (Sign in with Apple -> token)
Web page `eeon.com/connect`: user signs in with Apple via CloudKit web auth
(reuse `fetchCloudKitSignInURL`), server captures their `ckWebAuthToken`, mints
an EEON connection token bound to that user, stores the CloudKit token
encrypted. Show the connector URL + token + a "Revoke" control. Never display
or transmit the raw CloudKit token to the client after capture.

### Phase 3 — one-click add per tool
- Claude (Desktop/Code): remote MCP connector by URL, or a `claude mcp add`
  deep link with the token.
- ChatGPT: add as a connector (URL + auth) — this is what Phase 1's HTTP
  transport unlocks.
- Cursor: MCP server-by-URL config snippet.
- In-app "Set up AI access": show the URL/token with copy buttons, per-tool
  steps, and Revoke. Replaces today's dead-end explainer.

### Phase 4 — trust controls
Per-connection audit ("last read at"), read-only scope shown, one-tap revoke,
the connection-health signal already added, and a privacy-policy update
describing the proxy-not-copy model.

## Verification gate (rule #0 / #32 — the check I missed)
"Done" = a fresh device with NO repo connects EEON to a real Claude/ChatGPT
account through the hosted flow and reads a real note. Not "the server runs" —
the end-user path completes from a machine that has never seen the source.

## Decisions Shawn still owns
1. Hosting target (Cloud Run vs Vercel) and the `mcp.eeon.com` subdomain.
2. Whether Phase 1a (npx local) ships first as a stopgap, or we go straight to
   hosted.
3. Token storage / KMS choice for the encrypted CloudKit web-auth tokens.
