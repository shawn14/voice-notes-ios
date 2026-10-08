# Account deletion on iPad — App Review 2.1(a)

Apple reported an unresponsive Delete Account & Data row in 3.10.0 (170), submission be240327-3bd6-46f9-8f5f-f479adefa264 on October 7, 2026. The screenshots show the pressed row without a confirmation.

On October 8 the real iPad Air 11-inch M4 simulator (iOS 26.5) reproduced the issue using rejected-source commit 21b504a: Account opens, the deletion button receives the tap, but Cancel never appears. The unchanged presenter was a confirmationDialog on the parent Settings navigation root. The fix attaches a standard alert to the visible Account button. It retains the explicit destructive confirmation and existing deletion implementation.

Standing regression: ScreenshotTests.testAccountDeletionConfirmation, which checks open, cancel, and reopen. [Red receipt](red-summary.json) records the missing confirmation (and an initially overlong XCTest label query); [green receipt](green-summary.json) records the same interaction passing after the presenter fix and query correction.

Use the existing UITests scheme and cached build-for-testing / test-without-building path. Choose an available iPad UUID from simctl, explicitly boot it and wait for `xcrun simctl bootstatus <uuid> -b`, then use `-parallel-testing-enabled NO`. Do not rely on Xcode auto-boot/cloning: this run initially failed before test launch with SimError405/Mach308; explicit boot resolved it without a runtime download or service reset. Run simctl/xcodebuild outside the restricted filesystem sandbox.

This proves the simulator presentation path, not iPadOS 27 on a physical iPad or remote CloudKit/server data deletion. Independent runtime verification and release status are recorded in STATUS.md. The focused update is based on build170 source; later Watch/transcript work is preserved on main.

## Complete deletion and permanent proof

The fresh refuter found a second defect in rejected-source21b504a: only notes/projects were deleted; knowledge articles, extracted actions/decisions and other associated records survived. Reused the existing complete-deletion routine from commit04cceca (plus its small shared-file URL dependency) in the focused release. Main already contains that routine.

The final [full-flow UI receipt](full-flow-green-summary.json) and [actual persistence readback](persistence-green.json) pass. The proof checks every original primary key in all17 model tables, then restarts without fixture seeding and checks persisted sign-out. A fresh independent UI/SQLite inspection also found all17 tables empty after deletion; normal DEBUG launch subsequently inserted only empty schema placeholders, never the original data. Physical iPadOS27 and real remote CloudKit deletion remain unverified.

Standing real-system command, after building the selected release source's UITests scheme:

```sh
python3 scripts/prove-account-deletion.py --device <booted-ipad-uuid> --confirm-disposable-simulator --source <release-source> --derived-data <cached-build> --output /private/tmp/<fresh-proof-directory>
```

This actually deletes the disposable simulator fixture. It refuses physical devices/non-debug identities, requires explicit disposable-simulator confirmation, and reads the real app-group SwiftData store. No mock database or mocked services. Do not run against customer data. The initial preference write may flush asynchronously; the proof waits for the fixture identity instead of assuming launch completion is persistence. XCTest normally closes its app at teardown; 'found nothing to terminate' is accepted only for that exact expected shutdown condition.
