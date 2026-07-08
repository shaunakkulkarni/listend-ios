//
//  ListendUITests.swift
//  ListendUITests
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import XCTest

final class ListendUITests: XCTestCase {
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
    func testCreateEditDeleteLogAndProfileStatsUpdate() throws {
        launchResetApp()

        createSOSLog(rating: "4.5", review: "UI flow review.", tags: "ui flow")

        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        openLog(title: "SOS")

        app.buttons["Edit"].tap()
        selectRating("5.0")
        appendText(in: reviewTextInput(), text: " Edited review.")
        appendText(in: app.textFields["tagsTextField"], text: ", edited")
        app.buttons["saveLogButton"].tap()

        let ratingValue = app.descendants(matching: .any)["ratingValueText"]
        XCTAssertTrue(ratingValue.waitForExistence(timeout: 5))
        XCTAssertEqual(ratingValue.label, "5.0")
        let reviewValue = app.descendants(matching: .any)["reviewValueText"]
        XCTAssertTrue(reviewValue.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewValue.label.contains("Edited review."))

        let tagsValue = app.descendants(matching: .any)["tagsValueText"]
        XCTAssertTrue(tagsValue.waitForExistence(timeout: 5))
        XCTAssertTrue(tagsValue.label.contains("ui flow"))
        XCTAssertTrue(tagsValue.label.contains("edited"))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTab("Profile")
        XCTAssertTrue(app.descendants(matching: .any)["totalLogsValueText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["totalLogsValueText"].label, "1")
        XCTAssertTrue(app.descendants(matching: .any)["averageRatingValueText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["averageRatingValueText"].label, "5.0")
        XCTAssertTrue(app.descendants(matching: .any)["topTagsValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["topTagsValueText"].label.contains("edited"))

        openTab("Logs")
        openLog(title: "SOS")
        app.buttons["deleteLogButton"].tap()
        XCTAssertTrue(app.buttons["cancelDeleteLogButton"].waitForExistence(timeout: 5))
        app.buttons["cancelDeleteLogButton"].tap()
        XCTAssertTrue(app.buttons["deleteLogButton"].waitForExistence(timeout: 5))
        app.buttons["deleteLogButton"].tap()
        app.buttons["confirmDeleteLogButton"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["SOS"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLogPersistsAfterRelaunch() throws {
        launchResetApp()
        createSOSLog(rating: "4.0", review: "Persistence review.", tags: "persistent")
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))

        app.terminate()
        launchAppPreservingData()

        openTab("Logs")
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Persistence review."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeDashboardShowsPrimarySurfaces() throws {
        launchResetApp()

        XCTAssertTrue(app.staticTexts["Listend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addLogButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recently Played"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["recentLogsSection"].exists)
        XCTAssertFalse(app.staticTexts["Blonde"].exists)
    }

    @MainActor
    func testLogsTabStartsEmptyAndShowsCreatedLogs() throws {
        launchResetApp()

        openTab("Logs")
        XCTAssertTrue(app.staticTexts["No Logs Yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Blonde"].exists)

        createSOSLog(rating: "4.0", review: "Logs tab review.", tags: "history")

        openTab("Logs")
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Logs tab review."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeShowsLatestLogPreviewOnly() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Dashboard preview review.", tags: "dashboard")

        openTab("Home")
        XCTAssertTrue(app.descendants(matching: .any)["latestLogPreviewLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["recentLogsSection"].exists)
    }

    @MainActor
    func testHomeRecentlyPlayedAlbumOpensPreselectedLogEditor() throws {
        launchResetApp()

        app.buttons["loadRecentlyPlayedAlbumsButton"].tap()

        let recentAlbum = app.buttons["recentlyPlayedAlbum-mock.frank-ocean.blonde"]
        XCTAssertTrue(recentAlbum.waitForExistence(timeout: 5))
        recentAlbum.tap()

        XCTAssertTrue(app.navigationBars["New Log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selectedAlbumSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Blonde"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Frank Ocean"].waitForExistence(timeout: 5))

        selectRating("4.5")
        XCTAssertTrue(app.buttons["saveLogButton"].isEnabled)
    }

    @MainActor
    func testAddLogChooserAutoLoadsRecentAlbumAndOpensEditor() throws {
        launchResetApp()

        app.buttons["addLogButton"].tap()

        XCTAssertTrue(app.navigationBars["Choose Album"].waitForExistence(timeout: 5))
        let recentAlbum = app.buttons["albumSelectionRecent-mock.frank-ocean.blonde"]
        XCTAssertTrue(recentAlbum.waitForExistence(timeout: 5))
        recentAlbum.tap()

        XCTAssertTrue(app.navigationBars["New Log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selectedAlbumSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Blonde"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveLogButton"].isEnabled)

        selectRating("4.5")
        XCTAssertTrue(app.buttons["saveLogButton"].isEnabled)
    }

    @MainActor
    func testAddLogChooserSearchResultOpensEditor() throws {
        launchResetApp()

        app.buttons["addLogButton"].tap()
        XCTAssertTrue(app.navigationBars["Choose Album"].waitForExistence(timeout: 5))

        let searchField = app.searchFields["Album, artist, or genre"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("SOS")

        let result = app.buttons["albumSelectionSearchResult-mock.sza.sos"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        XCTAssertTrue(app.navigationBars["New Log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SZA"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNewLogRequiresStarRatingAndSavesSelectedRating() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        XCTAssertFalse(app.buttons["saveLogButton"].isEnabled)

        selectRating("4.5")
        XCTAssertTrue(app.buttons["saveLogButton"].isEnabled)
        app.buttons["saveLogButton"].tap()

        openTab("Logs")
        openLog(title: "SOS")

        let ratingValue = app.descendants(matching: .any)["ratingValueText"]
        XCTAssertTrue(ratingValue.waitForExistence(timeout: 5))
        XCTAssertEqual(ratingValue.label, "4.5")
    }

    @MainActor
    func testLogEditorSuggestedTagChipAppendsTag() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")

        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Late night vocals.")

        let tagsTextField = app.textFields["tagsTextField"]
        reveal(tagsTextField)
        XCTAssertTrue(tagsTextField.waitForExistence(timeout: 5))
        tagsTextField.tap()

        let lateNightTag = app.buttons["suggestedTag-late-night"]
        XCTAssertTrue(lateNightTag.waitForExistence(timeout: 5))
        lateNightTag.tap()

        XCTAssertTrue((tagsTextField.value as? String)?.contains("late night") == true)
    }

    @MainActor
    func testJournalAssistDraftRequiresExplicitAcceptance() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")

        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Original manual review.")

        tapAssistButton(app.descendants(matching: .any)["helpMeWriteButton"])
        let generateDraftButton = app.buttons["helpWriteGenerateJournalDraftButton"]
        reveal(generateDraftButton)
        XCTAssertTrue(generateDraftButton.waitForExistence(timeout: 5))
        generateDraftButton.tap()
        XCTAssertTrue(app.textViews["journalAssistDraftEditor"].waitForExistence(timeout: 5))

        XCTAssertTrue((reviewTextEditor.value as? String)?.contains("Original manual review.") == true)
        XCTAssertFalse((reviewTextEditor.value as? String)?.contains("I rated SOS") == true)

        let acceptDraftButton = app.buttons["acceptJournalDraftButton"]
        reveal(acceptDraftButton)
        XCTAssertTrue(acceptDraftButton.waitForExistence(timeout: 5))
        acceptDraftButton.tap()

        XCTAssertTrue((reviewTextEditor.value as? String)?.contains("I rated SOS") == true)
    }

    @MainActor
    func testJournalAssistTagsRequireExplicitTap() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")

        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Late night vocals.")

        let tagsTextField = app.textFields["tagsTextField"]
        reveal(tagsTextField)
        XCTAssertTrue(tagsTextField.waitForExistence(timeout: 5))
        tagsTextField.tap()
        tagsTextField.typeText("manual")
        XCTAssertFalse((tagsTextField.value as? String)?.contains("late night") == true)

        tapAssistButton(app.descendants(matching: .any)["journalSuggestTagsButton"])
        let generateTagsButton = app.buttons["generateJournalTagsButton"]
        reveal(generateTagsButton)
        XCTAssertTrue(generateTagsButton.waitForExistence(timeout: 5))
        generateTagsButton.tap()
        let journalAssistTag = app.buttons["journalAssistTag-late-night"]
        XCTAssertTrue(journalAssistTag.waitForExistence(timeout: 5))
        XCTAssertFalse((tagsTextField.value as? String)?.contains("late night") == true)

        journalAssistTag.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue((tagsTextField.value as? String)?.contains("late night") == true)
    }

    @MainActor
    func testTrackHighlightsPersistAndUpdateInLogDetail() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")
        openTrackHighlightsSection()

        let favoriteSnooze = app.buttons["favoriteTrackOption-snooze"]
        reveal(favoriteSnooze)
        XCTAssertTrue(favoriteSnooze.waitForExistence(timeout: 5))
        favoriteSnooze.tap()

        let skipGoodDays = app.buttons["skipTrackOption-good-days"]
        reveal(skipGoodDays)
        XCTAssertTrue(skipGoodDays.waitForExistence(timeout: 5))
        skipGoodDays.tap()

        let standoutMomentField = app.textFields["standoutMomentTextField"]
        reveal(standoutMomentField)
        XCTAssertTrue(standoutMomentField.waitForExistence(timeout: 5))
        standoutMomentField.tap()
        standoutMomentField.typeText("The final chorus opens up.")

        app.buttons["saveLogButton"].tap()
        openTab("Logs")
        openLog(title: "SOS")

        XCTAssertTrue(app.staticTexts["Track Highlights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].label.contains("Snooze"))
        XCTAssertTrue(app.descendants(matching: .any)["lessFavoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["lessFavoriteTracksValueText"].label.contains("Good Days"))
        XCTAssertTrue(app.descendants(matching: .any)["standoutMomentValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["standoutMomentValueText"].label.contains("final chorus"))

        app.buttons["Edit"].tap()
        let selectedSnooze = app.buttons["favoriteTrackOption-snooze"]
        reveal(selectedSnooze)
        XCTAssertTrue(selectedSnooze.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedSnooze.value as? String, "Selected")
        let selectedGoodDays = app.buttons["skipTrackOption-good-days"]
        reveal(selectedGoodDays)
        XCTAssertTrue(selectedGoodDays.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedGoodDays.value as? String, "Selected")
        app.buttons["favoriteTrackOption-kill-bill"].tap()
        app.buttons["saveLogButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].label.contains("Kill Bill"))
    }

    @MainActor
    func testTrackHighlightsFallbackAllowsManualTracksWhenTracklistUnavailable() throws {
        launchResetApp()

        app.buttons["loadRecentlyPlayedAlbumsButton"].tap()
        let recentAlbum = app.buttons["recentlyPlayedAlbum-mock.frank-ocean.blonde"]
        XCTAssertTrue(recentAlbum.waitForExistence(timeout: 5))
        recentAlbum.tap()

        XCTAssertTrue(app.navigationBars["New Log"].waitForExistence(timeout: 5))
        selectRating("4.5")
        openTrackHighlightsSection()

        XCTAssertTrue(app.staticTexts["tracklistUnavailableText"].waitForExistence(timeout: 5))

        let favoriteTracksField = app.textFields["favoriteTracksTextField"]
        reveal(favoriteTracksField)
        XCTAssertTrue(favoriteTracksField.waitForExistence(timeout: 5))
        favoriteTracksField.tap()
        favoriteTracksField.typeText("Nights")

        let lessFavoriteTracksField = app.textFields["lessFavoriteTracksTextField"]
        reveal(lessFavoriteTracksField)
        XCTAssertTrue(lessFavoriteTracksField.waitForExistence(timeout: 5))
        lessFavoriteTracksField.tap()
        lessFavoriteTracksField.typeText("Solo (Reprise)")

        app.buttons["saveLogButton"].tap()
        openTab("Logs")
        openLog(title: "Blonde")

        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].label.contains("Nights"))
        XCTAssertTrue(app.descendants(matching: .any)["lessFavoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["lessFavoriteTracksValueText"].label.contains("Solo"))
    }

    @MainActor
    func testEmptyTrackHighlightsDoNotShowDetailClutter() throws {
        launchResetApp()
        createSOSLog(rating: "4.0", review: "No highlight review.", tags: "simple")

        openTab("Logs")
        openLog(title: "SOS")

        XCTAssertFalse(app.staticTexts["Track Highlights"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.descendants(matching: .any)["favoriteTracksValueText"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["lessFavoriteTracksValueText"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["standoutMomentValueText"].exists)
    }

    @MainActor
    func testNewLogSaveDismissesImmediatelyAfterLocalSave() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")

        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Fast save review.")

        app.buttons["saveLogButton"].tap()

        XCTAssertTrue(app.staticTexts["Already logged"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.navigationBars["New Log"].exists)
    }

    @MainActor
    func testTodayPickFeedbackClearsActiveRecommendation() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Today pick anchor.", tags: "anchor")

        openTab("Home")
        XCTAssertTrue(app.staticTexts["Today's Pick"].waitForExistence(timeout: 5))
        app.buttons["todayPickLink"].tap()
        app.buttons["findTodayPickButton"].tap()

        XCTAssertTrue(app.buttons["likeRecommendationButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple Music freshness was unavailable, so this pick is based on your Listend logs."].waitForExistence(timeout: 5))
        app.buttons["likeRecommendationButton"].tap()

        XCTAssertTrue(app.staticTexts["Feedback saved. You can generate the next eligible pick."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Active Pick"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAlbumDetailShowsPreviewUnavailableWithMockService() throws {
        launchResetApp()

        openAlbumDetailFromSearch()
        assertPreviewUnavailableAfterTap()
    }

    @MainActor
    func testTodayPickShowsPreviewUnavailableWithMockService() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Preview pick anchor.", tags: "anchor")

        openTab("Home")
        app.buttons["todayPickLink"].tap()
        app.buttons["findTodayPickButton"].tap()

        XCTAssertTrue(app.buttons["likeRecommendationButton"].waitForExistence(timeout: 5))
        assertPreviewUnavailableAfterTap()
    }

    private func launchResetApp() {
        app.launchArguments = ["-ui-testing", "-reset-ui-testing-data"]
        configureUITestingStore()
        app.launch()
    }

    private func launchAppPreservingData() {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        configureUITestingStore()
        app.launch()
    }

    private func configureUITestingStore() {
        app.launchEnvironment["LISTEND_UI_TEST_STORE_ID"] = uiTestingStoreID
    }

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func createSOSLog(rating: String, review: String, tags: String) {
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating(rating)

        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText(review)

        let tagsTextField = app.textFields["tagsTextField"]
        reveal(tagsTextField)
        tagsTextField.tap()
        tagsTextField.typeText(tags)

        app.buttons["saveLogButton"].tap()

        openTab("Home")
    }

    private func reviewTextInput() -> XCUIElement {
        app.descendants(matching: .any)["reviewTextEditor"]
    }

    private func openAlbumDetailFromSearch(query: String = "SOS", resultID: String = "mock.sza.sos") {
        openTab("Search")
        let searchField = app.searchFields["Album, artist, or genre"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(query)

        let result = app.buttons["albumSearchResult-\(resultID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
    }

    private func assertPreviewUnavailableAfterTap() {
        let previewButton = app.buttons["albumPreviewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        previewButton.tap()

        let unavailablePredicate = NSPredicate(format: "label CONTAINS %@", "Preview unavailable")
        let unavailableExpectation = XCTNSPredicateExpectation(predicate: unavailablePredicate, object: previewButton)
        wait(for: [unavailableExpectation], timeout: 5)
    }

    private func openLog(title: String) {
        let log = app.staticTexts[title]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
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
        let stepCount = abs(halfStepDelta)

        for _ in 0..<stepCount {
            if halfStepDelta >= 0 {
                control.swipeUp()
            } else {
                control.swipeDown()
            }
        }
    }

    private func openTrackHighlightsSection() {
        let disclosure = app.buttons["trackHighlightsDisclosure"]
        if !disclosure.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()
    }

    private func reveal(_ element: XCUIElement, maxSwipes: Int = 3) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
    }

    private func dismissKeyboardIfNeeded() {
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 1) {
            doneButton.tap()
        }
    }

    private func tapAssistButton(_ element: XCUIElement) {
        dismissKeyboardIfNeeded()
        reveal(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func currentRatingValue(from control: XCUIElement) -> Double? {
        guard let value = control.value as? String else {
            return nil
        }

        return Double(value.components(separatedBy: " ").first ?? "")
    }

    private func appendText(in element: XCUIElement, text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        element.typeText(text)
    }
}
