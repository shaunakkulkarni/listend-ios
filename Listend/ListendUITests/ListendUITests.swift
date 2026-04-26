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
        XCTAssertEqual(app.descendants(matching: .any)["totalLogsValueText"].label, "4")
        XCTAssertTrue(app.descendants(matching: .any)["averageRatingValueText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["averageRatingValueText"].label, "4.6")
        XCTAssertTrue(app.descendants(matching: .any)["topTagsValueText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["topTagsValueText"].label.contains("edited"))

        openTab("Home")
        openLog(title: "SOS")
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

        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Persistence review."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTonightPickFeedbackClearsActiveRecommendation() throws {
        launchResetApp()

        openTab("Home")
        app.buttons["tonightPickLink"].tap()
        app.buttons["findTonightPickButton"].tap()

        XCTAssertTrue(app.buttons["likeRecommendationButton"].waitForExistence(timeout: 5))
        app.buttons["likeRecommendationButton"].tap()

        XCTAssertTrue(app.staticTexts["Feedback saved. You can generate the next eligible pick."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Active Pick"].waitForExistence(timeout: 5))
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
        openTab("Search")

        let searchField = app.searchFields["Album, artist, or genre"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("SOS")

        let result = app.buttons["albumSearchResult-mock.sza.sos"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        app.buttons["logThisAlbumButton"].tap()
        selectRating(rating)

        let reviewTextEditor = app.textViews["reviewTextEditor"]
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText(review)

        let tagsTextField = app.textFields["tagsTextField"]
        tagsTextField.tap()
        tagsTextField.typeText(tags)

        app.buttons["saveLogButton"].tap()

        openTab("Home")
    }

    private func openLog(title: String) {
        let log = app.staticTexts[title]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
    }

    private func selectRating(_ rating: String) {
        let picker = app.pickers["ratingPicker"]
        if picker.waitForExistence(timeout: 2) {
            picker.tap()
        } else {
            app.buttons["ratingPicker"].tap()
        }

        let buttonOption = app.buttons[rating].firstMatch
        if buttonOption.waitForExistence(timeout: 2) {
            buttonOption.tap()
            return
        }

        let staticTextOption = app.staticTexts[rating].firstMatch
        if staticTextOption.waitForExistence(timeout: 2) {
            staticTextOption.tap()
            return
        }

        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 2))
        wheel.adjust(toPickerWheelValue: rating)
        app.buttons["Done"].firstMatch.tap()
    }

    private func appendText(in element: XCUIElement, text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        element.typeText(text)
    }
}
