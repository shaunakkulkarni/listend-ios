//
//  TasteInsightsScreenshotTests.swift
//  ListendUITests
//
//  QA capture for the "Your Taste So Far" insights screen. Drives the real logging flow
//  (mock catalog, no network) to reach the empty / early / full states and attaches a
//  screenshot of each. Screenshots are saved into the result bundle as keepAlways
//  attachments named taste-01-empty / taste-02-early / taste-03-full.
//

import XCTest

final class TasteInsightsScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let uiTestingStoreID = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing-data"]
        app.launchEnvironment["LISTEND_UI_TEST_STORE_ID"] = uiTestingStoreID
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testCaptureTasteInsightsStates() throws {
        // 0 logs — empty state.
        openTasteInsights()
        XCTAssertTrue(app.staticTexts["Nothing Logged Yet"].waitForExistence(timeout: 5))
        snapshot("taste-01-empty")
        popToProfileRoot()

        // 1–4 logs — early state.
        logAlbum(query: "Blonde", resultID: "mock.frank-ocean.blonde", rating: "5.0", tags: "lush, warm")
        logAlbum(query: "Madvillainy", resultID: "mock.madvillain.madvillainy", rating: "4.5", tags: "dense, raw")
        logAlbum(query: "In Rainbows", resultID: "mock.radiohead.in-rainbows", rating: "4.0", tags: "moody, lush")
        openTasteInsights()
        XCTAssertTrue(app.staticTexts["Top Rated Albums"].waitForExistence(timeout: 5))
        snapshot("taste-02-early")
        popToProfileRoot()

        // 5+ logs — full state.
        logAlbum(query: "Titanic Rising", resultID: "mock.weyes-blood.titanic-rising", rating: "4.5", tags: "lush, nostalgic")
        logAlbum(query: "good kid", resultID: "mock.kendrick-lamar.good-kid-maad-city", rating: "5.0", tags: "raw, replayable")
        openTasteInsights()
        XCTAssertTrue(app.staticTexts["Taste Notes"].waitForExistence(timeout: 5))
        snapshot("taste-03-full")

        // Scroll to reveal the Rating Distribution bars and Taste Notes card.
        app.swipeUp()
        app.swipeUp()
        snapshot("taste-04-full-bottom")
    }

    // MARK: - Navigation

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func openTasteInsights() {
        openTab("Profile")
        let link = app.descendants(matching: .any)["tasteInsightsLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tasteInsightsScreen"].waitForExistence(timeout: 5))
    }

    private func popToProfileRoot() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }
    }

    // MARK: - Logging flow

    private func logAlbum(query: String, resultID: String, rating: String, tags: String) {
        openAlbumDetailFromSearch(query: query, resultID: resultID)

        app.buttons["logThisAlbumButton"].tap()
        selectRating(rating)

        let tagsTextField = app.textFields["tagsTextField"]
        reveal(tagsTextField)
        tagsTextField.tap()
        tagsTextField.typeText(tags)

        app.buttons["saveLogButton"].tap()
    }

    private func openAlbumDetailFromSearch(query: String, resultID: String) {
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        searchTab.tap()

        // A prior log left the Search tab pushed on an album detail. Re-tapping the
        // already-selected tab pops its navigation stack back to the search root.
        let searchField = app.searchFields["Album, artist, or genre"]
        if !searchField.waitForExistence(timeout: 2) {
            searchTab.tap()
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()

        let clearButton = searchField.buttons["Clear text"]
        if clearButton.exists {
            clearButton.tap()
        }

        searchField.typeText(query)

        let result = app.buttons["albumSearchResult-\(resultID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
    }

    private func selectRating(_ rating: String) {
        let stepButton = app.buttons["starRatingStep-\(rating)"]
        XCTAssertTrue(stepButton.waitForExistence(timeout: 5))
        stepButton.tap()
    }

    private func reveal(_ element: XCUIElement, maxSwipes: Int = 4) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
    }

    // MARK: - Screenshot

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
