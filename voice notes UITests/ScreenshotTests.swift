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

        // Home's calendar strip pushes the full Calendar screen (Option A,
        // 2026-09-10); Week is chosen there. Relaunch to get back Home.
        if openCalendarScreen(selecting: "This Week") {
            sleep(2)
            shot("02_Calendar")
            // The range persists across launches; put it back so Home's
            // strip and later runs start on Today.
            _ = selectCalendarRange("Today")
            relaunchHome()
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

    private func openCalendarScreen(selecting title: String) -> Bool {
        let strip = app.buttons["Calendar"]
        guard strip.waitForExistence(timeout: 3) else { return false }
        strip.tap()
        return selectCalendarRange(title)
    }

    /// On the pushed Calendar screen: open the options menu and pick a range.
    private func selectCalendarRange(_ title: String) -> Bool {
        let range = app.buttons["Calendar options"]
        guard range.waitForExistence(timeout: 3) else { return false }
        range.tap()
        let option = app.buttons[title]
        guard option.waitForExistence(timeout: 3) else { return false }
        option.tap()
        return true
    }

    private func openTasksFromHome() -> Bool {
        let button = app.buttons["All tasks"]

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
        // Home's Notes card rows are buttons labeled "<title>, <time> · …"
        // (Option A, 2026-09-10); the seeded standup is the recent one.
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Standup with Lena'")
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

    /// End-to-end: seeded note → ⋯ → Mind Map → a real gpt-4o map renders
    /// (live OpenAI call from the simulator, so it needs a working key).
    func testNoteMindMap() throws {
        sleep(3)
        dismissGatesIfNeeded()
        XCTAssertTrue(tapSeededNote(), "Seeded note not found")
        let options = app.buttons["Note options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5), "Note options menu missing")
        let mindMap = app.buttons["Mind Map"]
        // A tap during the push transition can land before the menu is live.
        for _ in 0..<3 where !mindMap.exists {
            options.tap()
            _ = mindMap.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(mindMap.exists, "Mind Map menu item missing")
        mindMap.tap()
        // The map is drawn once the options menu appears in the sheet.
        XCTAssertTrue(app.buttons["Mind map options"].waitForExistence(timeout: 60), "Mind map never rendered")
        XCTAssertFalse(app.staticTexts["No Mind Map"].exists)
        // It must stay open until Done (device report 2026-09-26: it showed
        // the map, then closed by itself).
        sleep(10)
        XCTAssertTrue(app.buttons["Mind map options"].exists, "Mind map sheet closed by itself")
        let map = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        map.name = "MindMap"
        map.lifetime = .keepAlways
        add(map)
    }

    /// End-to-end: a note with real two-voice audio → ⋯ → Identify Speakers
    /// → background upload to OpenAI → transcript split into turns → the
    /// Speakers editor opens with both speakers.
    func testIdentifySpeakers() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/two-speakers.m4a").path
        app.terminate()
        launchApp(extraArguments: ["-UITestPro", "-SeedSpeakerAudio", fixture])
        sleep(3)
        dismissGatesIfNeeded()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Paywall launch call'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded audio note not found")
        row.tap()
        let options = app.buttons["Note options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let identify = app.buttons["Identify Speakers"]
        XCTAssertTrue(identify.waitForExistence(timeout: 5), "Identify Speakers missing (no audio?)")
        identify.tap()

        // On success the Speakers editor opens by itself.
        let editor = app.navigationBars["Speakers"]
        XCTAssertTrue(editor.waitForExistence(timeout: 120), "Speakers editor never opened")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "SpeakersEditor"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Speaker A'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Speaker B'")).firstMatch.exists)
    }

    /// Paste from the Record long-press menu creates a note; a note exports
    /// as Markdown, PDF and its recording through the share sheet.
    func testPasteAndExport() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/two-speakers.m4a").path
        app.terminate()
        launchApp(extraArguments: ["-UITestPro", "-SeedSpeakerAudio", fixture])
        sleep(3)
        dismissGatesIfNeeded()

        // Paste. iOS asks "Allow Paste" when an app reads another app's copy.
        let pasted = "Pasted note: renew the passport before March"
        UIPasteboard.general.string = pasted
        let record = app.buttons["Record a note"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.press(forDuration: 1.2)
        let pasteItem = app.buttons["Paste"]
        XCTAssertTrue(pasteItem.waitForExistence(timeout: 5), "Paste missing from Record menu")
        pasteItem.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let pastedRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Pasted note'")).firstMatch
        XCTAssertTrue(pastedRow.waitForExistence(timeout: 30), "Pasted note never appeared on Home")

        // Export the audio note three ways.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Paywall launch call'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        for format in ["PDF", "Markdown", "Recording"] {
            let options = app.buttons["Note options"]
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            let exportMenu = app.buttons["Export As…"]
            for _ in 0..<3 where !exportMenu.exists {
                options.tap()
                _ = exportMenu.waitForExistence(timeout: 3)
            }
            exportMenu.tap()
            let item = app.buttons[format]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(format) export missing")
            item.tap()
            // The share sheet shows the file's name as its header.
            let sheet = app.otherElements["ActivityListView"]
            let close = app.buttons["Close"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 10) || close.waitForExistence(timeout: 2),
                          "\(format) share sheet never opened")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Export-\(format)"
            shot.lifetime = .keepAlways
            add(shot)
            if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
            sleep(1)
        }
    }

    // MARK: - Individual Screen Tests (for debugging)

    // MARK: - 2026-10-06 gap pass: tap-to-hear, Translate, Recently Deleted
    //
    // Written when this Mac had no iOS simulator runtime for Xcode 26.2, so
    // these three compiled but had not yet run. Run them before trusting them.

    private var speakerFixture: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/two-speakers.m4a").path
    }

    private func openSeededAudioNote() {
        app.terminate()
        launchApp(extraArguments: ["-UITestPro", "-SeedSpeakerAudio", speakerFixture])
        sleep(3)
        dismissGatesIfNeeded()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Paywall launch call'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded audio note not found")
        row.tap()
    }

    /// Text inside a SwiftUI Button surfaces as the button's label, not as a
    /// static text, so look for the label on any kind of element.
    private func anyElement(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Original → "Tap sentences to hear them" → live Whisper timings → the
    /// transcript becomes tappable sentences, and tapping one starts playback.
    func testTapToHearTranscript() throws {
        // The seeded audio note has no enhanced text, so its body is already
        // the transcript (there is no Enhanced / Original switch to tap).
        openSeededAudioNote()

        let sync = app.buttons["syncTranscriptButton"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5), "No offer to sync the transcript (audio missing?)")
        sync.tap()

        let sentence = app.links.firstMatch
        XCTAssertTrue(sentence.waitForExistence(timeout: 120), "Transcript never became tappable")
        XCTAssertGreaterThanOrEqual(app.links.count, 2, "Expected a tappable sentence per spoken line")
        XCTAssertFalse(sync.exists, "Sync button should go away once sentences are tappable")

        app.links.element(boundBy: 1).tap()
        sleep(1)
        keep("TapToHear")
        // The audio pill shows a running clock only while audio is loaded.
        XCTAssertTrue(anyElement(labelContaining: "0:0").exists, "Tapping a sentence did not start playback")
    }

    /// Format menu → Translate → Spanish rewrites the note; Undo brings it back.
    func testTranslateNote() throws {
        openSeededAudioNote()
        let menu = app.buttons["formatMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let translate = app.buttons["Translate"]
        XCTAssertTrue(translate.waitForExistence(timeout: 5), "Translate missing from the format menu")
        translate.tap()
        let spanish = app.buttons["Spanish"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        spanish.tap()

        let translated = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'lanzamiento' OR label CONTAINS[c] 'gracias'")).firstMatch
        XCTAssertTrue(translated.waitForExistence(timeout: 60), "Note was not translated to Spanish")
        keep("Translated")

        menu.tap()
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "No Undo after translating")
        undo.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'thanks for joining'")).firstMatch.waitForExistence(timeout: 5),
                      "Undo did not bring the original language back")
    }

    /// Delete → the note leaves Home → Notes filter › Recently Deleted shows
    /// it with days left → Restore puts it back.
    func testRecentlyDeletedRestore() throws {
        openSeededAudioNote()
        app.buttons["Note options"].tap()
        let delete = app.buttons["Delete Note"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let homeRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Paywall launch call'")).firstMatch
        XCTAssertTrue(homeRow.waitForNonExistence(timeout: 5), "Deleted note still on Home")

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Home has no More link to all notes")
        more.tap()
        let filter = app.buttons["Filter notes"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        app.buttons["Recently Deleted"].tap()

        // A bin row is one button whose label joins its title and subtitle.
        let binned = anyElement(labelContaining: "Paywall launch call")
        XCTAssertTrue(binned.waitForExistence(timeout: 5), "Deleted note is not in Recently Deleted")
        XCTAssertTrue(anyElement(labelContaining: "30 days left").exists)
        keep("RecentlyDeleted")

        binned.press(forDuration: 1.0)
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(binned.waitForNonExistence(timeout: 5), "Restored note still listed as deleted")

        filter.tap()
        app.buttons["All notes"].tap()
        XCTAssertTrue(anyElement(labelContaining: "Paywall launch call").waitForExistence(timeout: 5),
                      "Restored note did not come back")
    }

    func testHomeOnly() throws {
        sleep(3)
        snapshot("Home")
    }
}
