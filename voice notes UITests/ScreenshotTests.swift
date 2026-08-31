//
//  ScreenshotTests.swift
//  voice notes UITests
//
//  App Store screenshot automation (fastlane snap). Five shots that tell the
//  same story as eeon.com — your personal AI assistant:
//    01 Home          private memory from the phone in your pocket
//    02 Ask EEON      chat with notes, tasks, people, and projects
//    03 Note detail   "Standup with Lena" — calendar row, decision, format chips
//    04 Tasks         every to-do you said out loud, inline
//    05 Connections   iCloud, Reminders, and AI connector status
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
        shot("01_Home")

        if tapAskEEON() {
            sleep(2)
            shot("02_AskEEON")
            backFromPushedPage()
        }

        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'remind me to send lena'")
        ).firstMatch
        if row.waitForExistence(timeout: 4) {
            row.tap()
            sleep(2)
            shot("03_NoteDetail")
            backFromPushedPage()
        }

        if tapSegment("Tasks") {
            sleep(2)
            shot("04_Tasks")
            _ = tapSegment("Library")
        }

        if tapSettings(), tapSettingsRow("Connections") {
            sleep(2)
            shot("05_Connections")
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

    private func tapSegment(_ title: String) -> Bool {
        let segment = app.buttons[title]
        guard segment.waitForExistence(timeout: 3) else { return false }
        segment.tap()
        return true
    }

    private func tapSettings() -> Bool {
        let settings = app.buttons["Settings"]
        guard settings.waitForExistence(timeout: 3) else { return false }
        settings.tap()
        return true
    }

    private func tapSettingsRow(_ title: String) -> Bool {
        let row = app.buttons[title]
        if row.waitForExistence(timeout: 4) {
            row.tap()
            return true
        }
        let text = app.staticTexts[title]
        guard text.waitForExistence(timeout: 2) else { return false }
        text.tap()
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
