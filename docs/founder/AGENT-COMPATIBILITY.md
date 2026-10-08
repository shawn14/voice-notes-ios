# Agent interoperability evidence — 2026-10-08

Primary path: one remote MCP URL, OAuth browser approval on the phone, then bounded source reads. The user's chosen agent executes work in its own workspace. Copyable briefs and Markdown exports cover tools without this connector path.

| Client | Setup evidence | Native OAuth/source read/work execution |
| --- | --- | --- |
| Claude Code 2.1.294 | Installed CLI help and official HTTP/OAuth docs inspected. Prior repo runbook records native OAuth discovery. | Actual get_note and source-cited plan creation independently passed with temporary SDK-issued bearer; native OAuth login and phone path remain untested. |
| Codex 0.157.1 | Installed CLI exposes mcp add/login; official setup docs inspected. | Actual get_note + source-cited launch-plan creation passed in an isolated ephemeral run with a temporary SDK-issued agent token. Native MCP login remains untested. |
| Gemini CLI 0.61.0 | Installed CLI MCP help and official HTTP/OAuth docs inspected; login is interactive `/mcp auth eeon`. | Actual native attempt stopped before source read: existing personal Google login rejected with IneligibleTierError (unsupported Code Assist client). No task or native OAuth proof. |
| Grokbot | No installed binary or canonical configuration found in checked local sources. | Not exercised; no invented command. |
| MCP TypeScript SDK 1.30.0 (resolved lockfile package) | Actual SDK OAuth discovery, DCR, PKCE, initialize, tool schemas, search/get_note, revocation and cleanup passed against the deployed EEON connector. | Protocol only; does not execute a model or build a project. |

`sdk-proof.log` records all seven SDK checks. No customer notes, agent configuration, model API, or persistent client tokens were used. The first SDK run passed discovery/read, then the test mistakenly followed Disconnect's307 redirect as a POST into `/connect`, causing405. Corrected test uses manual redirects and then independently checks revoked credentials receive401. Cleanup is in `finally`.

The local export server builds and all12 existing tests pass. Fixture/CloudKit-adapter tests prove local code behavior, not live CloudKit sync or native-client integrations. The hosted SDK proof uses the actual deployed mirror and OAuth service.

Official references: [Claude Code MCP](https://code.claude.com/docs/en/mcp), [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/).

Remaining release requirements: iPhone handoff and connected-note checks, each named client's actual authorized source read, and richer project execution and result write-back. The exact iPad-copied packet now produced a source-cited local draft with independently verified desktop/phone browser output (copied-packet/); this is seeded offline context. The matching iOS26.2 runtime is restored; signed native iPad flow now passes with independent live clipboard/SwiftData verification (docs/founder/native-ipad/). Seeded simulation does not prove physical-device recording or native OAuth login. None of this branch's founder workflow has been merged or released.

Independent refuter reran the deployed SDK proof: exit0, all7 checks passed. It confirmed that the receipt proves revocation and denied access; it does not independently read storage to prove physical mirror deletion. Other tool behavior and untested native UI paths remain unproven. Native Claude/Codex source-to-plan execution is recorded separately above. No release or native-client support claim follows from this result.
