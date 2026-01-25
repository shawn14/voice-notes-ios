//
//  ScreenshotTests.swift
//  voice notes UITests
//
//  App Store Screenshot Automation
//

import XCTest

final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Pass launch arguments for screenshot mode
        app.launchArguments.append("-UITestMode")
        app.launchArguments.append("-SkipOnboarding")

        setupSnapshot(app)
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    func testCaptureScreenshots() throws {
        // Wait for app to load
        sleep(2)

        // Screenshot 1: Home screen with record button
        snapshot("01_HomeScreen")

        // Tap "Continue without account" if onboarding is shown
        let continueButton = app.buttons["Continue without account"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
            sleep(1)
        }

        // Try debug skip if available
        let debugSkip = app.buttons["Debug: Skip to signed in"]
        if debugSkip.exists {
            debugSkip.tap()
            sleep(1)
        }

        // Screenshot 2: Main home view (ready to record)
        snapshot("02_RecordingReady")

        // Look for existing notes in the list
        let notesList = app.collectionViews.firstMatch
        if notesList.waitForExistence(timeout: 2) {
            // If there are notes, tap the first one
            let firstNote = notesList.cells.firstMatch
            if firstNote.exists {
                firstNote.tap()
                sleep(1)

                // Screenshot 3: Note detail/editor view
                snapshot("03_NoteDetail")

                // Look for Extract button
                let extractButton = app.buttons["Extract"]
                if extractButton.exists && extractButton.isEnabled {
                    // Screenshot showing extraction capability
                    snapshot("04_ExtractCapability")
                }

                // Go back
                let backButton = app.navigationBars.buttons.firstMatch
                if backButton.exists {
                    backButton.tap()
                    sleep(1)
                }
            }
        }

        // Look for Command Center / Dashboard tab
        let commandCenter = app.buttons["Command Center"]
        if commandCenter.exists {
            commandCenter.tap()
            sleep(1)
            snapshot("05_CommandCenter")
        }

        // Look for Projects/Kanban tab
        let projectsTab = app.buttons["Projects"]
        if projectsTab.exists {
            projectsTab.tap()
            sleep(1)
            snapshot("06_ProjectsKanban")
        }

        // Look for Settings
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            sleep(1)
            snapshot("07_Settings")
        }
    }

    // MARK: - Individual Screen Tests (for debugging)

    func testHomeScreen() throws {
        sleep(2)
        snapshot("Home")
    }
}
