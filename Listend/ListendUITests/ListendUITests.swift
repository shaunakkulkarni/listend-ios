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
        appendText(in: app.textViews["reviewTextEditor"], text: " Edited review.")
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

        let reviewTextEditor = app.textViews["reviewTextEditor"]
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

        let reviewTextEditor = app.textViews["reviewTextEditor"]
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Original manual review.")

        app.buttons["helpMeWriteButton"].tap()
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

        let reviewTextEditor = app.textViews["reviewTextEditor"]
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Late night vocals.")

        let tagsTextField = app.textFields["tagsTextField"]
        reveal(tagsTextField)
        XCTAssertTrue(tagsTextField.waitForExistence(timeout: 5))
        tagsTextField.tap()
        tagsTextField.typeText("manual")
        XCTAssertFalse((tagsTextField.value as? String)?.contains("late night") == true)

        app.buttons["helpMeWriteButton"].tap()
        let generateTagsButton = app.buttons["helpWriteGenerateJournalTagsButton"]
        reveal(generateTagsButton)
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

        let favoriteTracksField = app.textFields["favoriteTracksTextField"]
        reveal(favoriteTracksField)
        XCTAssertTrue(favoriteTracksField.waitForExistence(timeout: 5))
        favoriteTracksField.tap()
        favoriteTracksField.typeText("Snooze, Good Days")

        let lessFavoriteTracksField = app.textFields["lessFavoriteTracksTextField"]
        reveal(lessFavoriteTracksField)
        XCTAssertTrue(lessFavoriteTracksField.waitForExistence(timeout: 5))
        lessFavoriteTracksField.tap()
        lessFavoriteTracksField.typeText("Too Late")

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
        XCTAssertTrue(app.descendants(matching: .any)["lessFavoriteTracksValueText"].label.contains("Too Late"))
        XCTAssertTrue(app.descendants(matching: .any)["standoutMomentValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["standoutMomentValueText"].label.contains("final chorus"))

        app.buttons["Edit"].tap()
        let expandedFavoriteTracksField = app.textFields["favoriteTracksTextField"]
        reveal(expandedFavoriteTracksField)
        XCTAssertTrue(expandedFavoriteTracksField.waitForExistence(timeout: 5))
        appendText(in: expandedFavoriteTracksField, text: ", Blind")
        app.buttons["saveLogButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["favoriteTracksValueText"].label.contains("Blind"))
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

        let reviewTextEditor = app.textViews["reviewTextEditor"]
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Fast save review.")

        app.buttons["saveLogButton"].tap()

        XCTAssertTrue(app.staticTexts["Already logged"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.navigationBars["New Log"].exists)
    }

    @MainActor
    func testTonightPickFeedbackClearsActiveRecommendation() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Tonight pick anchor.", tags: "anchor")

        openTab("Home")
        app.buttons["tonightPickLink"].tap()
        app.buttons["findTonightPickButton"].tap()

        XCTAssertTrue(app.buttons["likeRecommendationButton"].waitForExistence(timeout: 5))
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
    func testTonightPickShowsPreviewUnavailableWithMockService() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Preview pick anchor.", tags: "anchor")

        openTab("Home")
        app.buttons["tonightPickLink"].tap()
        app.buttons["findTonightPickButton"].tap()

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

        let reviewTextEditor = app.textViews["reviewTextEditor"]
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

    private func openAlbumDetailFromSearch() {
        openTab("Search")
        let searchField = app.searchFields["Album, artist, or genre"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("SOS")

        let result = app.buttons["albumSearchResult-mock.sza.sos"]
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

        let favoriteTracksField = app.textFields["favoriteTracksTextField"]
        if !favoriteTracksField.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
    }

    private func reveal(_ element: XCUIElement, maxSwipes: Int = 3) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
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
