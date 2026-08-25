//
//  ScreenshotTests.swift
//  voice notes UITests
//
//  App Store Screenshot Automation
//
//  Captures the screens that highlight EEON's unique value:
//    1. Home with Knowledge anchored at the top (the AI compile layer)
//    2. KnowledgeArticle detail showing LLM-compiled summary + threads + decisions
//    3. Tune EEON sheet with the three-card structure (Profile / Focus / Purpose)
//    4. Focus list editor with priority items
//    5. Note detail with extracted intelligence chips
//
//  Backed by ScreenshotSeed (DEBUG-only) which seeds a curated founder persona
//  with pre-baked homeLayoutJSON so the LLM compile loop is bypassed for
//  deterministic, professional captures.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        // Wait for app + seed to settle
        sleep(3)

        // Dismiss any onboarding/sign-in screens defensively
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

        sleep(2)

        // Screenshot 01: Home with Knowledge anchored at top
        snapshot("01_HomeKnowledgeFirst")

        // Screenshot 02: Tap a knowledge article to show the LLM-compiled detail
        // Find the first knowledge card (.button with article name in horizontal scroll)
        // Try the StockAlarm card first
        let stockAlarmCard = app.staticTexts["StockAlarm"].firstMatch
        if stockAlarmCard.waitForExistence(timeout: 3) {
            stockAlarmCard.tap()
            sleep(2)
            snapshot("02_KnowledgeArticleDetail")

            // Go back to home
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
                sleep(1)
            } else {
                // Try a swipe-back gesture
                app.swipeRight()
                sleep(1)
            }
        }

        // Screenshot 03: Tune EEON — open via avatar menu
        // The avatar lives in the top-right of AIHomeView
        sleep(1)
        let tuneEntries = ["Tune EEON", "Tune Eeon", "Tune"]
        var openedTune = false

        // Try direct buttons first
        for label in tuneEntries {
            let btn = app.buttons[label]
            if btn.exists {
                btn.tap()
                sleep(2)
                openedTune = true
                break
            }
        }

        // If not found, try tapping the avatar (top-right) — usually the rightmost button in the header
        if !openedTune {
            // Look for an avatar-style button near top
            let avatarButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'U' OR label CONTAINS 'avatar' OR label CONTAINS 'profile'"))
            if avatarButtons.count > 0 {
                avatarButtons.element(boundBy: 0).tap()
                sleep(1)
                // Now look for Tune EEON in any presented menu/sheet
                for label in tuneEntries {
                    let btn = app.buttons[label]
                    if btn.exists {
                        btn.tap()
                        sleep(2)
                        openedTune = true
                        break
                    }
                }
            }
        }

        if openedTune {
            // Screenshot 03: Tune EEON review (3 cards)
            snapshot("03_TuneEEONReview")

            // Screenshot 04: Focus card editor
            // Tap "Edit" on the Focus card (Your Focus Right Now)
            let focusEditButton = app.buttons.matching(NSPredicate(format: "label == 'Edit'")).element(boundBy: 1)
            if focusEditButton.exists {
                focusEditButton.tap()
                sleep(2)
                snapshot("04_FocusListEditor")

                // Close the editor
                let doneBtn = app.buttons["Done"]
                if doneBtn.exists {
                    doneBtn.tap()
                    sleep(1)
                }
            }

            // Close Tune EEON sheet
            let closeBtn = app.buttons["xmark"].firstMatch
            if closeBtn.exists {
                closeBtn.tap()
                sleep(1)
            } else {
                // Swipe down to dismiss sheet
                app.swipeDown(velocity: .fast)
                sleep(1)
            }
        }

        // Screenshot 05: Note detail with extraction chips
        // Find a note in the recent notes feed at the bottom of home
        sleep(1)
        // Scroll down to find recent notes
        app.swipeUp()
        sleep(1)
        let noteRow = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS 'streaming' OR label CONTAINS 'EEON' OR label CONTAINS 'pricing'"
        )).firstMatch
        if noteRow.waitForExistence(timeout: 3) {
            noteRow.tap()
            sleep(2)
            snapshot("05_NoteDetailWithExtractions")
        }
    }

    // MARK: - Individual Screen Tests (for debugging)

    func testHomeOnly() throws {
        sleep(3)
        snapshot("Home")
    }
}
