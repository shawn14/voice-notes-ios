# Native Claude Code source-to-plan proof

Actual Claude Code2.1.294 signed in through its existing Max subscription, in restricted mode with only builtin Write and the authorized get_note read allowed. Strict MCP config limits the run to the disposable EEON connection; no session persists. SDK OAuth issues the temporary bearer, held in a0600 file inside the throwaway workspace and removed in finally. No installed client settings change.

Standing command: `node mcp/test/hosted-client.mjs https://www.eeon.com --native-claude --receipt-dir=<absolute-output-folder>`.

Builder and fresh independent runs passed. Tool-use and matching successful tool-result show the exact note UUID and returned Orbit source; Write produced the saved launch-plan.md. Both artifacts cite the source, retain unknown scope/date/owners, and avoid invented completions. Disconnect returned401 for former credentials; connection cleanup completed. Receipts stay in the chosen directory for inspection; test workspace and temporary config are removed.

Proven: actual native Claude note read and local draft production. Not proven: native Claude MCP OAuth login, phone clipboard/context path, arbitrary project execution, Gemini, Grokbot, or any release. The default SDK test still makes no model calls; native options consume existing client usage.
