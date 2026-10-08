# Native Gemini attempt — not a compatibility pass

Installed Gemini CLI0.61.0 was invoked headlessly against a disposable EEON note with isolated GEMINI_CLI_HOME, private existing Google OAuth credentials, only local write_file and EEON get_note available. The hosted SDK approval/read path passed; native Gemini exited1 before any model/source read.

Actual client diagnostic: IneligibleTierError — “This client is no longer supported for Gemini Code Assist for individuals.” Google directs migration to Antigravity. No account/auth configuration was changed and no migration is inferred to satisfy this workflow. No further retries after this classified external eligibility failure. The disposable connection was revoked in finally and temporary client credentials/settings removed.

Standing probe: node mcp/test/hosted-client.mjs https://www.eeon.com --native-gemini --receipt-dir=<absolute-output-folder>. It must fail on this state; native Gemini remains unproven. An authorized supported authentication/client path is needed before claiming integration.

Configuration references: https://geminicli.com/docs/reference/configuration/ and https://geminicli.com/docs/tools/mcp-server/. Native-client failure diagnostics are saved privately by the probe so exit0 cannot substitute for a completed get_note and inspected source-cited artifact.
