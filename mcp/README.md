# EEON MCP

Read-only MCP server for EEON memory. The preferred source is the user's private CloudKit database; the markdown/iCloud Drive vault remains a local fallback.

## Why CloudKit

EEON already stores notes in SwiftData backed by the private CloudKit container `iCloud.aivoiceeeon`. Apple's CloudKit Web Services support user-authenticated access to that same private database, so an AI tool can read notes after the user signs in with Apple. That avoids the confusing iPhone Files picker and works even when the phone is not near the Mac.

The product model is:

- EEON for iPhone only needs private iCloud sync to be on.
- Each AI workspace adds the EEON connector and authorizes access with Apple.
- The connector reads the user's private CloudKit `CD_Note` records on demand.
- Folder export is only an "Export My Data" fallback, not the primary AI connection.

CloudKit requirements:

- Private-note access needs a CloudKit **user** token for the Apple ID that owns the EEON notes.
- A CloudKit **management** token is useful for schema/admin work, but it cannot read private notes.
- A CloudKit Web Services API token is only needed for the browser sign-in flow used by remote/non-local AI workspaces.
- Production environment for App Store/TestFlight notes; development for locally installed debug builds.

## Build

```bash
cd mcp
npm install
npm run build
npm test
```

## Doctor

Run the doctor before claiming that an AI can see EEON notes:

```bash
cd mcp
npm run doctor
```

The doctor checks:

- whether the local MCP package is built
- whether Claude's EEON MCP entry is still pointed at the old folder export
- whether the Mac has CloudKit management-token access
- whether private `CD_Note` records are readable in Production and Development CloudKit

It prints sample metadata only, not note bodies.

## CloudKit Setup

### Local Mac / `cktool`

This matches the existing Apple developer-tool setup. Save a CloudKit user token for `cktool`, then run the MCP in CloudKit mode:

```bash
xcrun cktool save-token --type user
EEON_SOURCE=cloudkit EEON_CLOUDKIT_ENVIRONMENT=production node "/Users/shawncarpenter/projects/voice notes/mcp/dist/src/index.js"
```

Check whether the MCP can see notes without printing note bodies:

```bash
EEON_SOURCE=cloudkit EEON_CLOUDKIT_ENVIRONMENT=production npm run check:cloudkit
```

If this reports that no user token is saved, the existing token is the management token, not private-note user auth.

### CloudKit Web Services

Create a CloudKit API token in CloudKit Console:

- Container: `iCloud.aivoiceeeon`
- Environment: `production` for TestFlight/App Store data, `development` for debug data
- Sign In Callback URL: `http://127.0.0.1:43777/callback`

Then authenticate the connector:

```bash
cd mcp
EEON_CLOUDKIT_API_TOKEN="<api token>" EEON_CLOUDKIT_ENVIRONMENT=production npm run auth
```

Run the MCP using CloudKit Web Services:

```bash
EEON_SOURCE=cloudkit EEON_CLOUDKIT_API_TOKEN="<api token>" node "/Users/shawncarpenter/projects/voice notes/mcp/dist/src/index.js"
```

The auth command stores the Apple user token in `~/.config/eeon-mcp/cloudkit.json` with `0600` permissions. The server is read-only. It does not write CloudKit records.

## Claude Code

Preferred local setup:

```bash
cd mcp
npm run build
npm run connect:claude
```

This rewrites the project-scoped Claude MCP entry to CloudKit mode, runs Apple's interactive `cktool` user-token prompt, then runs the doctor. It removes the old `--vault` folder dependency and does not store CloudKit API tokens or note contents in Claude config. Paste CloudKit tokens only into your Terminal prompt, never into chat.

If the user token is already saved, this lighter path is enough:

```bash
cd mcp
npm run build
npm run install:claude -- --apply
npm run doctor
```

## Hosted Connector Direction

For "AI agents anywhere," the product needs a hosted EEON connector. The iPhone app keeps syncing notes to private CloudKit. The AI client connects to EEON's hosted MCP endpoint, EEON starts Apple/CloudKit user auth, and the connector reads private `CD_Note` records on demand after the user approves access. The hosted connector must store CloudKit web auth tokens encrypted per user/workspace and rotate the token whenever Apple returns a replacement token.

Apple constraints that shape the UX:

- A CloudKit API token is reusable per container/environment.
- Private database reads require user authentication.
- CloudKit web auth tokens rotate after use and are short-lived.
- The user still needs to approve access in Apple sign-in; there is no silent "all AIs can read iCloud" mode.

CloudKit source via local `cktool` user token:

```bash
claude mcp add eeon --env EEON_SOURCE=cloudkit --env EEON_CLOUDKIT_ENVIRONMENT=production -- node "/Users/shawncarpenter/projects/voice notes/mcp/dist/src/index.js"
```

CloudKit source via Web Services:

```bash
claude mcp add eeon --env EEON_SOURCE=cloudkit --env EEON_CLOUDKIT_API_TOKEN="<api token>" --env EEON_CLOUDKIT_ENVIRONMENT=production -- node "/Users/shawncarpenter/projects/voice notes/mcp/dist/src/index.js"
```

Markdown fallback:

```bash
claude mcp add eeon -- node "/Users/shawncarpenter/projects/voice notes/mcp/dist/src/index.js" --vault "<EEON export folder>"
```

Known fallback paths:

- `~/Library/Mobile Documents/iCloud~aivoiceeeon/Documents/EEON Vault`
- `~/Library/Mobile Documents/com~apple~CloudDocs/EEON Vault`

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
