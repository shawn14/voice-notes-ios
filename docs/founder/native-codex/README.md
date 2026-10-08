# Native Codex source-to-project proof

The standing script now optionally invokes actual Codex0.157.1, authenticated through its existing ChatGPT login. It ignores user config, stores no session, and operates in a throwaway workspace. It receives a short-lived-for-the-test agent credential from the actual SDK OAuth approval flow in child environment only. The only exposed EEON tool is get_note; this disposable read is explicitly preapproved, without bypassing shell/filesystem protections.

Initial runs failed acceptance despite CLI exit0: the noninteractive client cancelled its get_note approval. The test did not accept the model's status message as proof. With documented per-tool approval scoped to that read, native get_note completes and Codex creates launch-plan.md. The inspected output cites the source UUID/project and separates unfinished from completed work. Builder trace and artifact are preserved here; source data is synthetic, hosted storage is real.

Run from app root:

```
node mcp/test/hosted-client.mjs https://www.eeon.com --native-codex --receipt-dir=/private/tmp/eeon-native-proof
```

The default command without native-codex still makes no model calls. The native option uses the existing CLI account and consumes its normal usage. No installed agent settings are changed. Credentials and source connection are revoked; workspace is deleted in finally. Receipts deliberately remain in the specified output directory for inspection.

Scope: actual native source read and local plan production. Not proven: native Codex MCP login, iPhone/iPad copy/clipboard path, richer project execution, Claude Code/Gemini/Grokbot sessions, or any production publication/deployment. Claude Code is currently signed out on this Mac; Xcode has26.2 SDK and only26.5 runtime at preflight, leaving native app testing blocked.

Official per-tool settings: https://learn.chatgpt.com/docs/extend/mcp?surface=cli

Fresh independent rerun passed exit0. Refuter inspected actual tool result and produced artifact: matching source ID/project, practical next step, explicit “No completed work is verified,” and proposed unfinished tasks. Former credentials received401 after Disconnect; cleanup completed. Independent receipts are saved alongside builder receipts. The trace omits command bodies, so it does not independently prove every shell action; no broader safety or arbitrary-execution claim is made.
