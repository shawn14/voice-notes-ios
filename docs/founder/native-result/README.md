# Native reviewed agent result proof

2026-10-08: signed phone-only QA app on disposable iPhone16Pro/iOS26.2(23C52), built with Xcode26.2. `testFounderAgentResult` and `testFounderAgentResultReadOnlyFailure` passed, exit0,2tests/86.301seconds. Actual screenshots saved-result.png and save-failure.png are exported XCTest attachments.

The successful flow pastes a verbatim excerpt of the actual Codex report, rejects blank saving, saves, terminates and relaunches without reseeding, opens the result, and sees its source link. The failure flow uses an actual SwiftData configuration with allowsSave=false against the same disposable database, not a mocked save or a synthetic thrown error; its rejected write displays a permission error and keeps the editable exact draft. The proof path is DEBUG+simulator+UITestMode only. It cannot activate on physical devices or release builds.

Standing scripts/founder/verify-native-result.py compares real post-test SQLite with before-database.json, a real pre-save snapshot captured after seeding and before the first result existed. Read-only live WAL included. Exactly one new result; source UUID matches Standup with Lena; exact returned excerpt; inferred EEON association; all11originals’ captured text/source/project/annotation fields and all4task rows unchanged. The rejected write adds no second note. Actual source projectId is null, so explicit project-ID association is not exercised.

Receipts: test-summary.json, database-check.json, before-database.json and native-test.log. The screenshot of success shows the result after relaunch; failure shows the retained draft and actual permission error.

Boundaries: seeded simulator only, an excerpt rather than the full3918character report through the UI. The full report has formatter-level proof separately. No physical recording/transcription, native OAuth, CloudKit sync, connector writes, general project filtering, source-link tap/destination proof, main merge or release. The older brief-navigation failure remains unexplained. An explicit-project case remains required. Screens expose raw sourceUUID twice and raw Markdown; those are product polish gaps, not proof of an ultimate finished founder experience.

## Repeat the proof

Use a fresh disposable simulator and signed phone-only QA project, with the same two focused tests and downloads disabled. While that existing test run starts, `python3 scripts/founder/capture-native-result-baseline.py <QA-device> <before.json>` captures the seeded database before any result exists. The current proof used this same read-only capture logic inline; the checked-in entry point is syntax checked but has not been separately rerun. Require successful baseline capture before accepting a result check. Then `python3 scripts/founder/verify-native-result.py <QA-device> <before.json> docs/founder/copied-packet/handoff-result.md` checks the actual database. Capture uses a bounded5minute wait on only this QA device; no service/daemon is installed. Never run on the physical phone.

Independent evidence is in independent-evidence.json. guard-red-green.json records actual reserved SQLite corruption rejected and exact restoration accepted; mutation was after independent live reads, and restored in finally before cleanup.

Owned simulator/build/temp data were removed after all receipts were saved. Source and QA project are retained; no release.
