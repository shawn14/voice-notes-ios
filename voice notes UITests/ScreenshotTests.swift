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

        let didSelectWeek = selectCalendarRange("This Week")
        sleep(2)
        shot("02_Calendar")
        if didSelectWeek {
            _ = selectCalendarRange("Today")
        }

        if tapAskEEON() {
            sleep(2)
            shot("03_AskEEON")
            if !closeAskSheet() {
                relaunchHome()
            }
        }

        if tapSeededNote() {
            sleep(2)
            shot("04_NoteDetail")
            if !backFromPushedPage() {
                relaunchHome()
            }
        }

        relaunchHome()
        guard openTasksFromHome() else {
            XCTFail("Tasks feed did not load for screenshot capture")
            return
        }
        sleep(2)
        shot("05_Tasks")
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

    private func closeAskSheet() -> Bool {
        for _ in 0..<3 {
            if !isAskSheetVisible { return true }

            let doneButtons = [
                app.navigationBars.buttons["Done"],
                app.buttons["Done"],
                app.buttons["Close"],
                app.buttons["Cancel"]
            ]

            if let button = doneButtons.first(where: { $0.waitForExistence(timeout: 1) }) {
                button.tap()
            } else {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
                start.press(forDuration: 0.05, thenDragTo: end)
            }

            if waitForAskSheetGone(timeout: 3) { return true }
        }

        return !isAskSheetVisible
    }

    private var isAskSheetVisible: Bool {
        app.staticTexts["Ask EEON"].exists
            || app.textFields["Ask EEON"].exists
            || app.buttons["Send question"].exists
    }

    private func waitForAskSheetGone(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAskSheetVisible { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !isAskSheetVisible
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

    private func openTasksFromHome() -> Bool {
        let button = app.buttons["All action items"]

        for _ in 0..<4 {
            if button.waitForExistence(timeout: 2), button.isHittable {
                button.tap()
                return waitForTasksScreen()
            }
            app.swipeUp()
            sleep(1)
        }

        return false
    }

    private func waitForTasksScreen() -> Bool {
        let navigationTitle = app.navigationBars["Tasks"].staticTexts["Tasks"]
        let visibleTitle = app.staticTexts["Tasks"]
        let seededTasks = [
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'send patrick the updated pricing deck'")).firstMatch,
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'write streaming pool config'")).firstMatch,
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'send lena the pricing deck'")).firstMatch
        ]

        for _ in 0..<4 {
            let hasTitle = navigationTitle.waitForExistence(timeout: 1) || visibleTitle.exists
            if hasTitle, seededTasks.contains(where: { $0.exists }) {
                return true
            }
            app.swipeUp()
            sleep(1)
        }

        return (navigationTitle.exists || visibleTitle.exists) && seededTasks.contains(where: { $0.exists })
    }

    private func tapSeededNote() -> Bool {
        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'remind me to send lena'")
        ).firstMatch

        for _ in 0..<4 {
            if row.waitForExistence(timeout: 2), row.isHittable {
                row.tap()
                return true
            }
            app.swipeUp()
            sleep(1)
        }

        if row.exists {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }

        return false
    }

    private func backFromPushedPage() -> Bool {
        let backButtons = app.navigationBars.buttons
        if backButtons.count > 0 {
            backButtons.element(boundBy: 0).tap()
        }
        sleep(1)
        return !app.staticTexts["Remind me to send Lena the pricing deck"].exists
    }

    private func relaunchHome(extraArguments: [String] = []) {
        app.terminate()
        launchApp(extraArguments: extraArguments)
        sleep(3)
        dismissGatesIfNeeded()
    }

    // MARK: - Individual Screen Tests (for debugging)

    func testHomeOnly() throws {
        sleep(3)
        snapshot("Home")
    }
}
