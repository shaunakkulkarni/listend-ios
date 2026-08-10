//
//  ActivationUITests.swift
//  ListendUITests
//

import XCTest

final class ActivationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let uiTestingStoreID = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        configureUITestingStore()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testFreshOnboardingSkipPersistsAndLaunchOverridesStayDeterministic() throws {
        launchResetApp()

        XCTAssertTrue(onboardingElement("onboardingWelcomeStage").waitForExistence(timeout: 5))
        app.buttons["onboardingSkipButton"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))

        app.terminate()
        launchAppPreservingData()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(onboardingElement("onboardingView").exists)

        app.terminate()
        launchAppPreservingData(additionalArguments: ["-force-onboarding"])
        XCTAssertTrue(onboardingElement("onboardingWelcomeStage").waitForExistence(timeout: 5))

        app.terminate()
        launchAppPreservingData(
            additionalArguments: ["-force-onboarding", "-bypass-onboarding"]
        )
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(onboardingElement("onboardingView").exists)
    }

    @MainActor
    func testExistingLogBypassesOnboardingWithoutCompletionPreference() throws {
        launchResetApp(additionalArguments: ["-seed-reaction-existing-custom"])

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(onboardingElement("onboardingView").exists)
        let progress = app.descendants(matching: .any)["homeActivationProgressText"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.value as? String, "1 of 5 logs")

        openTab("Logs")
        app.staticTexts["SOS"].tap()
        app.buttons["deleteLogButton"].tap()
        app.buttons["confirmDeleteLogButton"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["logsEmptyState"].waitForExistence(timeout: 10))
        XCTAssertFalse(onboardingElement("onboardingView").exists)
    }

    @MainActor
    func testAppleMusicConnectIsExplicitAndMockAuthorizationSucceeds() throws {
        launchResetApp(additionalArguments: [
            "-apple-music-authorization-initial-state", "notDetermined",
            "-apple-music-authorization-request-result", "authorized"
        ])
        advanceToAppleMusic()

        let status = onboardingElement("onboardingAppleMusicStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("Not connected"))

        tapOnboardingButton("onboardingConnectAppleMusicButton")
        waitForLabel(of: status, toContain: "Apple Music connected")
        XCTAssertTrue(app.buttons["onboardingAppleMusicContinueButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppleMusicDenialDoesNotBlockOnboardingCompletion() throws {
        launchResetApp(additionalArguments: [
            "-apple-music-authorization-initial-state", "notDetermined",
            "-apple-music-authorization-request-result", "denied"
        ])
        advanceToAppleMusic()

        tapOnboardingButton("onboardingConnectAppleMusicButton")
        let status = onboardingElement("onboardingAppleMusicStatus")
        waitForLabel(of: status, toContain: "Access denied")

        tapOnboardingButton("onboardingAppleMusicNotNowButton")
        XCTAssertTrue(onboardingElement("onboardingJournalStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingDoThisLaterButton")
        XCTAssertTrue(onboardingElement("onboardingCompletionStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingOpenListendButton")

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFirstLogUsesCurrentFlowAndUpdatesOnboardingAndHomeProgress() throws {
        launchResetApp(additionalArguments: [
            "-apple-music-authorization-initial-state", "denied"
        ])
        advanceToAppleMusic()
        tapOnboardingButton("onboardingAppleMusicNotNowButton")
        tapOnboardingButton("onboardingAddFirstLogButton")

        XCTAssertTrue(app.navigationBars["Choose Album"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["loadAlbumSelectionRecentlyPlayedButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["albumSelectionRecent-mock.frank-ocean.blonde"].exists)

        let searchField = app.searchFields["Album, artist, or genre"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("SOS")

        let result = app.buttons["albumSelectionSearchResult-mock.sza.sos"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["New Log"].waitForExistence(timeout: 5))

        selectRating("4.5")
        app.buttons["saveLogButton"].tap()

        let onboardingProgress = onboardingElement("onboardingJournalProgress")
        XCTAssertTrue(onboardingProgress.waitForExistence(timeout: 5))
        XCTAssertEqual(onboardingProgress.value as? String, "1 of 5 logs")
        tapOnboardingButton("onboardingJournalContinueButton")
        tapOnboardingButton("onboardingOpenListendButton")

        let homeProgress = app.descendants(matching: .any)["homeActivationProgressText"]
        XCTAssertTrue(homeProgress.waitForExistence(timeout: 5))
        XCTAssertEqual(homeProgress.value as? String, "1 of 5 logs")
    }

    @MainActor
    func testHomeActivationCoversEmptyAndReadyRouting() throws {
        launchResetApp(additionalArguments: ["-bypass-onboarding"])

        XCTAssertTrue(app.descendants(matching: .any)["homeActivationModule"].waitForExistence(timeout: 5))
        let emptyAction = app.buttons["homeActivationActionButton"]
        XCTAssertTrue(emptyAction.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyAction.label, "Add Your First Log")

        app.terminate()
        launchResetApp(additionalArguments: [
            "-bypass-onboarding",
            "-seed-today-pick-eligible"
        ])

        let readyAction = app.buttons["homeActivationActionButton"]
        XCTAssertTrue(readyAction.waitForExistence(timeout: 5))
        XCTAssertEqual(readyAction.label, "Create My Reflection")

        openTab("Profile")
        app.buttons["generalSettingsLink"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openTab("Home")
        readyAction.tap()

        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["createSoundPrintButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsShowsMusicSoundPrintAndNonDestructiveReplay() throws {
        launchResetApp(additionalArguments: [
            "-bypass-onboarding",
            "-seed-reaction-existing-custom",
            "-apple-music-authorization-initial-state", "denied"
        ])

        openTab("Profile")
        let settingsLink = app.buttons["generalSettingsLink"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        settingsLink.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let musicStatus = app.descendants(matching: .any)["appleMusicSettingsStatus"]
        XCTAssertTrue(musicStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(musicStatus.label, "Access Denied")
        XCTAssertTrue(app.buttons["appleMusicOpenSystemSettingsButton"].exists)

        let soundPrintLink = app.buttons["generalSettingsSoundPrintLink"]
        XCTAssertTrue(soundPrintLink.waitForExistence(timeout: 5))
        soundPrintLink.tap()
        XCTAssertTrue(app.navigationBars["SoundPrint Settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let replayButton = app.buttons["replayIntroductionButton"]
        XCTAssertTrue(replayButton.waitForExistence(timeout: 5))
        replayButton.tap()
        XCTAssertTrue(onboardingElement("onboardingWelcomeStage").waitForExistence(timeout: 5))
        app.buttons["onboardingCloseButton"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let totalLogs = app.descendants(matching: .any)["totalLogsValueText"]
        XCTAssertTrue(totalLogs.waitForExistence(timeout: 5))
        XCTAssertEqual(totalLogs.label, "1")
    }

    @MainActor
    func testReplayRefreshesAppleMusicStatusInSettings() throws {
        launchResetApp(additionalArguments: [
            "-bypass-onboarding",
            "-apple-music-authorization-initial-state", "notDetermined",
            "-apple-music-authorization-request-result", "authorized"
        ])

        openTab("Profile")
        app.buttons["generalSettingsLink"].tap()

        let musicStatus = app.descendants(matching: .any)["appleMusicSettingsStatus"]
        XCTAssertTrue(musicStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(musicStatus.label, "Not Connected")

        app.buttons["replayIntroductionButton"].tap()
        advanceToAppleMusic()
        tapOnboardingButton("onboardingConnectAppleMusicButton")
        waitForLabel(
            of: onboardingElement("onboardingAppleMusicStatus"),
            toContain: "Apple Music connected"
        )
        app.buttons["onboardingCloseButton"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        waitForLabel(of: musicStatus, toContain: "Connected")
    }

    @MainActor
    func testOnboardingRemainsNavigableAtAccessibilityTextSize() throws {
        launchResetApp(additionalArguments: [
            "-force-onboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])

        XCTAssertTrue(onboardingElement("onboardingWelcomeStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingGetStartedButton")
        XCTAssertTrue(onboardingElement("onboardingTasteLoopStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingTasteLoopContinueButton")
        XCTAssertTrue(onboardingElement("onboardingAppleMusicStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingAppleMusicNotNowButton")
        XCTAssertTrue(onboardingElement("onboardingJournalStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingDoThisLaterButton")
        XCTAssertTrue(onboardingElement("onboardingCompletionStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingOpenListendButton")
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    private func launchResetApp(additionalArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing-data"] + additionalArguments
        configureUITestingStore()
        app.launch()
    }

    private func launchAppPreservingData(additionalArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + additionalArguments
        configureUITestingStore()
        app.launch()
    }

    private func configureUITestingStore() {
        app.launchEnvironment["LISTEND_UI_TEST_STORE_ID"] = uiTestingStoreID
    }

    private func onboardingElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func advanceToAppleMusic() {
        XCTAssertTrue(onboardingElement("onboardingWelcomeStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingGetStartedButton")
        XCTAssertTrue(onboardingElement("onboardingTasteLoopStage").waitForExistence(timeout: 5))
        tapOnboardingButton("onboardingTasteLoopContinueButton")
        XCTAssertTrue(onboardingElement("onboardingAppleMusicStage").waitForExistence(timeout: 5))
    }

    private func tapOnboardingButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing onboarding button \(identifier)")

        for _ in 0..<8 where !button.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(button.isHittable, "Onboarding button \(identifier) was not reachable")
        button.tap()
    }

    private func waitForLabel(of element: XCUIElement, toContain text: String) {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        wait(for: [expectation], timeout: 5)
    }

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func selectRating(_ rating: String) {
        guard let ratingValue = Double(rating) else {
            XCTFail("Invalid rating value: \(rating)")
            return
        }

        let control = app.descendants(matching: .any)["starRatingControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))

        let stepButton = app.buttons["starRatingStep-\(rating)"]
        if stepButton.waitForExistence(timeout: 1) {
            stepButton.tap()
            return
        }

        let currentRating = currentRatingValue(from: control) ?? 0
        let halfStepDelta = Int(((ratingValue - currentRating) * 2.0).rounded())

        for _ in 0..<abs(halfStepDelta) {
            if halfStepDelta >= 0 {
                control.swipeUp()
            } else {
                control.swipeDown()
            }
        }
    }

    private func currentRatingValue(from control: XCUIElement) -> Double? {
        guard let value = control.value as? String else {
            return nil
        }

        return Double(value.components(separatedBy: " ").first ?? "")
    }
}
