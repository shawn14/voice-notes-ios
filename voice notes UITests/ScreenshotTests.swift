//
//  ScreenshotTests.swift
//  voice notes UITests
//
//  App Store screenshot automation (fastlane snap). Five shots that tell the
//  same story as eeon.com — your personal AI assistant:
//    01 Home          private memory from the phone in your pocket
//    02 Calendar      meetings from iCloud, Google, and Outlook on the phone
//    03 Ask EEON      chat with notes, tasks, people, and projects
//    04 Note detail   "Standup with Lena" — calendar row, decision, format chips
//    05 Tasks         every to-do you said out loud, inline
//
//  Backed by ScreenshotSeed (DEBUG-only, -SeedScreenshotData): the hero note
//  with calendar context, its action item, and today's brief — no API calls.
//  Every step is guarded so a missed element skips a shot instead of failing
//  the run (Snapfile: stop_after_first_error).
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        launchApp()
    }

    private func launchApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments.append("-UITestMode")
        app.launchArguments.append("-SkipOnboarding")
        app.launchArguments.append("-SeedScreenshotData")
        for argument in extraArguments {
            app.launchArguments.append(argument)
        }
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
        shot("01_Home")

        if selectCalendarRange("This Week") {
            sleep(2)
            shot("02_Calendar")
            _ = selectCalendarRange("Today")
        }

        if tapAskEEON() {
            sleep(2)
            shot("03_AskEEON")
            closeAskSheet()
        }

        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'remind me to send lena'")
        ).firstMatch
        if row.waitForExistence(timeout: 4) {
            row.tap()
            sleep(2)
            shot("04_NoteDetail")
            backFromPushedPage()
        }

        if tapAllActionItems() {
            sleep(2)
            shot("05_Tasks")
        }
    }

    // MARK: - Helpers

    /// fastlane's snapshot() for the snap lane, plus a keepAlways attachment so
    /// the PNGs can also be exported from the .xcresult with
    /// `xcrun xcresulttool export attachments` when running xcodebuild directly.
    private func shot(_ name: String) {
        snapshot(name)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// System permission alerts (notifications, reminders) belong to
    /// SpringBoard, not the app — tap Allow so they never sit on a shot.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 2) { allow.tap(); sleep(1) } else { break }
        }
    }

    private func dismissGatesIfNeeded() {
        dismissSystemAlerts()
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

    private func tapAskEEON() -> Bool {
        let ask = app.buttons["Ask EEON"]
        guard ask.waitForExistence(timeout: 3) else { return false }
        ask.tap()
        return true
    }

    private func closeAskSheet() {
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }
        sleep(1)
    }

    private func tapSegment(_ title: String) -> Bool {
        let segment = app.buttons[title]
        guard segment.waitForExistence(timeout: 3) else { return false }
        if segment.isSelected { return true }
        segment.tap()
        return true
    }

    private func selectCalendarRange(_ title: String) -> Bool {
        let range = app.buttons["Calendar range"]
        guard range.waitForExistence(timeout: 3) else { return false }
        range.tap()
        let option = app.buttons[title]
        guard option.waitForExistence(timeout: 3) else { return false }
        option.tap()
        return true
    }

    private func tapAllActionItems() -> Bool {
        let button = app.buttons["All action items"]
        guard button.waitForExistence(timeout: 4) else { return false }
        button.tap()
        return true
    }

    private func backFromPushedPage() {
        let backButtons = app.navigationBars.buttons
        if backButtons.count > 0 {
            backButtons.element(boundBy: 0).tap()
        }
        sleep(1)
    }

    // MARK: - Individual Screen Tests (for debugging)

    func testHomeOnly() throws {
        sleep(3)
        snapshot("Home")
    }
}
