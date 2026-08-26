//
//  ScreenshotTests.swift
//  voice notes UITests
//
//  App Store screenshot automation (fastlane snap). Five shots that tell the
//  same story as eeon.com — say it once, EEON remembers:
//    01 Home          the feed, blue, dropdown header
//    02 Highlights    what mattered, what's open, what's next
//    03 Tasks         every to-do, inline
//    04 Note detail   "Standup with Lena" — calendar row, decision, format chips
//    05 Remind me     the confirmation sheet for a spoken reminder
//
//  Backed by ScreenshotSeed (DEBUG-only, -SeedScreenshotData): the hero note
//  with calendar context, its action item, and today's brief — no API calls.
//  Every step is guarded so a missed element skips a shot instead of failing
//  the run (Snapfile: stop_after_first_error).
//

import XCTest

final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments.append("-UITestMode")
        app.launchArguments.append("-SkipOnboarding")
        app.launchArguments.append("-SeedScreenshotData")
        setupSnapshot(app)
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    func testCaptureScreenshots() throws {
        sleep(3)
        dismissGatesIfNeeded()
        sleep(2)
        snapshot("01_Home")

        if openFeedMenu(), tapMenuItem("Highlights") {
            sleep(2)
            snapshot("02_Highlights")
            backToAllNotes()
        }

        if openFeedMenu(), tapMenuItem("Tasks") {
            sleep(2)
            snapshot("03_Tasks")
            backToAllNotes()
        }

        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'remind me to send lena'")
        ).firstMatch
        if row.waitForExistence(timeout: 4) {
            row.tap()
            sleep(2)
            snapshot("04_NoteDetail")
        }

        // 05: relaunch with the demo flag so the confirmation sheet presents itself.
        app.terminate()
        app.launchArguments.append("-ShowReminderDemo")
        app.launch()
        sleep(3)
        dismissGatesIfNeeded()
        if app.buttons["Add to Reminders"].waitForExistence(timeout: 8) {
            sleep(1)
            snapshot("05_RemindMe")
        }
    }

    // MARK: - Helpers

    private func dismissGatesIfNeeded() {
        let continueButton = app.buttons["Continue without account"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
            sleep(1)
        }
        let debugSkip = app.buttons["Debug: Skip to signed in"]
        if debugSkip.exists {
            debugSkip.tap()
            sleep(1)
        }
    }

    /// The left dropdown on the feed header is a Menu whose label names the
    /// current view: "All notes", "Highlights", "Tasks", or a category.
    private func openFeedMenu() -> Bool {
        let menu = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'All notes' OR label BEGINSWITH 'Highlights' OR label BEGINSWITH 'Tasks'"
        )).firstMatch
        guard menu.waitForExistence(timeout: 3) else { return false }
        menu.tap()
        sleep(1)
        return true
    }

    private func tapMenuItem(_ title: String) -> Bool {
        // Menu items live above the label; the last match is the item, not the label.
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        guard matches.count > 0 else { return false }
        let item = matches.element(boundBy: max(0, matches.count - 1))
        guard item.waitForExistence(timeout: 3) else { return false }
        item.tap()
        return true
    }

    private func backToAllNotes() {
        if openFeedMenu() { _ = tapMenuItem("All notes") }
        sleep(1)
    }

    // MARK: - Individual Screen Tests (for debugging)

    func testHomeOnly() throws {
        sleep(3)
        snapshot("Home")
    }
}
