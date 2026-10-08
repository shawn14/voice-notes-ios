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

## Explicit project and next-handoff gate — later run

`testFounderAgentResultExplicitProject` uses DEBUG+simulator+UITestMode-only `-SeedFounderExplicitProject`. It creates two real SwiftData Project records both named EEON with different UUIDs, assigns the primary and three related source notes to the intended ID, and adds a same-name wrong-project note. This is reserved QA data, never a production or physical-phone fixture.

The flow shares the existing result-save/relaunch test, then actually taps Open source note, requires the original title, prepares and copies the next brief. The result should appear in that brief's project memory, while the other same-name project's note must not.

Run on a fresh signed disposable simulator when disk reserve is restored; focus only this explicit-project case plus ReadOnlyFailure. Use capture-native-result-baseline.py with `--require-explicit-project` so the snapshot cannot race and capture the initial unassigned seed. After both tests, verify-native-result.py with `--check-next-brief` requires real source/result IDs, unchanged original/task/project fields, two real same-name project records, exact intended-project clipboard set, exact quoted originals, and returned result included. Save actual clipboard/screens/receipts and obtain fresh independent verification before claiming this boundary passed.

Only Swift source syntax and Python syntax were parsed for this extension. Neither native fixture/type checking nor either new script option has been exercised against runtime state. The previous637a0d3 proof remains inferred-project/excerpt-only and is not retroactively expanded.

The later actual explicit-ID/source-link/next-brief proof is recorded separately in [native-explicit-project](../native-explicit-project/README.md). Earlier evidence in this folder remains inferred-name/excerpt only. The baseline entrypoint and extended guard were actually exercised in that later run.
