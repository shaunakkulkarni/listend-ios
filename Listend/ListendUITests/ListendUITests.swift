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

        createSOSLog(rating: "4.5", review: "UI flow review.", reaction: "ui flow")

        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        openLog(title: "SOS")

        app.buttons["Edit"].tap()
        selectRating("5.0")
        addCustomReaction("edited")
        appendText(in: reviewTextInput(), text: " Edited review.")
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
        createSOSLog(rating: "4.0", review: "Persistence review.", reaction: "persistent")
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

        createSOSLog(rating: "4.0", review: "Logs tab review.", reaction: "history")

        openTab("Logs")
        XCTAssertTrue(app.staticTexts["SOS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Logs tab review."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeShowsLatestLogPreviewOnly() throws {
        launchResetApp()
        createSOSLog(rating: "4.5", review: "Dashboard preview review.", reaction: "dashboard")

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
    func testReactionPromptAdaptsToRatingAndChipSelectsAndDeselects() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["reactionPromptText"].exists)

        selectRating("4.5")
        assertReactionPrompt("What made it hit?")

        let chip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reactionChip-")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.value as? String, "Not selected")
        XCTAssertFalse(chip.isSelected)

        chip.tap()
        XCTAssertEqual(chip.value as? String, "Selected")
        XCTAssertTrue(chip.isSelected)

        chip.tap()
        XCTAssertEqual(chip.value as? String, "Not selected")
        XCTAssertFalse(chip.isSelected)

        selectRating("3.5")
        assertReactionPrompt("What worked—and what didn’t?")

        selectRating("2.5")
        assertReactionPrompt("What lost you?")
    }

    @MainActor
    func testReactionBrowserOpensBrowsesCategoriesAndCloses() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")
        openReactionBrowser()

        XCTAssertTrue(app.staticTexts["Mood & Vibe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reactionBrowserOption-mood.feel-good"].waitForExistence(timeout: 5))

        let browser = app.descendants(matching: .any)["reactionBrowser"]
        app.buttons["reactionBrowserDoneButton"].tap()
        XCTAssertTrue(browser.waitForNonExistence(timeout: 5))
        assertReactionPrompt("What made it hit?")
    }

    @MainActor
    func testReactionBrowserSearchResolvesCanonicalAndAliasLocally() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")
        openReactionBrowser()

        let searchField = reactionSearchField()
        replaceText(in: searchField, with: "hype")

        let canonicalResult = app.buttons["reactionResult-mood.hype"]
        XCTAssertTrue(canonicalResult.waitForExistence(timeout: 5))
        XCTAssertTrue(canonicalResult.label.contains("Canonical reaction"))
        XCTAssertEqual(canonicalResult.value as? String, "Not selected")
        canonicalResult.tap()
        XCTAssertEqual(canonicalResult.value as? String, "Selected")

        replaceText(in: searchField, with: "turnt")

        let aliasResult = app.buttons["reactionResult-mood.hype"]
        XCTAssertTrue(aliasResult.waitForExistence(timeout: 5))
        XCTAssertTrue(aliasResult.label.contains("maps to this canonical reaction"))
        XCTAssertEqual(aliasResult.value as? String, "Selected")
    }

    @MainActor
    func testReactionBrowserShowsExplicitAmbiguityChoices() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")
        openReactionBrowser()
        replaceText(in: reactionSearchField(), with: "icy")

        let ambiguityPrompt = app.descendants(matching: .any)["reactionAmbiguityPrompt"]
        XCTAssertTrue(ambiguityPrompt.waitForExistence(timeout: 5))
        XCTAssertEqual(
            ambiguityPrompt.label,
            "Does “icy” describe the sound, the attitude, or the mood?"
        )

        let expectedChoiceIDs = [
            "reactionAmbiguityOption-sonic.cold-production",
            "reactionAmbiguityOption-mood.confident",
            "reactionAmbiguityOption-mood.menacing"
        ]
        for identifier in expectedChoiceIDs {
            let choice = app.buttons[identifier]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "Missing ambiguity choice \(identifier)")
            XCTAssertEqual(choice.value as? String, "Not selected")
        }

        let attitudeChoice = app.buttons["reactionAmbiguityOption-mood.confident"]
        attitudeChoice.tap()
        XCTAssertEqual(attitudeChoice.value as? String, "Selected")
        XCTAssertTrue(app.buttons["keepCustomReactionButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomReactionSavesAndRestoresAsCustom() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")
        addCustomReaction("graduation summer")

        let customSelection = app.buttons["selectedReaction-custom-graduation-summer"]
        XCTAssertTrue(customSelection.waitForExistence(timeout: 5))
        XCTAssertEqual(customSelection.value as? String, "Selected")

        app.buttons["saveLogButton"].tap()
        openTab("Logs")
        openLog(title: "SOS")

        let tagsValue = app.descendants(matching: .any)["tagsValueText"]
        XCTAssertTrue(tagsValue.waitForExistence(timeout: 5))
        XCTAssertTrue(tagsValue.label.contains("graduation summer"))

        app.buttons["Edit"].tap()
        let restoredCustomSelection = app.buttons["selectedReaction-custom-graduation-summer"]
        XCTAssertTrue(restoredCustomSelection.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredCustomSelection.value as? String, "Selected")
    }

    @MainActor
    func testSeededExistingFloatyRemainsCustomAndReviewStartsExpanded() throws {
        launchResetApp(additionalArguments: ["-seed-reaction-existing-custom"])
        openTab("Logs")
        openLog(title: "SOS")

        app.buttons["Edit"].tap()

        let reviewDisclosure = app.buttons["reviewDisclosure"]
        XCTAssertTrue(reviewDisclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(reviewDisclosure.value as? String, "Expanded")

        let customSelection = app.buttons["selectedReaction-custom-floaty"]
        XCTAssertTrue(customSelection.waitForExistence(timeout: 5))
        XCTAssertEqual(customSelection.value as? String, "Selected")

        let existingReview = reviewTextInput()
        reveal(existingReview, maxSwipes: 5)
        XCTAssertTrue(existingReview.waitForExistence(timeout: 5))
        XCTAssertTrue((existingReview.value as? String)?.contains("atmosphere kept pulling me back") == true)

        openReactionBrowser()
        let browser = app.descendants(matching: .any)["reactionBrowser"].firstMatch
        let selectedCustom = browser.buttons["selectedReaction-custom-floaty"]
        XCTAssertTrue(selectedCustom.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedCustom.value as? String, "Selected")
        app.buttons["reactionBrowserDoneButton"].tap()

        app.buttons["saveLogButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tagsValueText"].label.contains("floaty"))

        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["selectedReaction-custom-floaty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["selectedReaction-canonical-mood-dreamy"].exists)
    }

    @MainActor
    func testNewLogReviewDisclosureStartsCollapsedAndExpandsOnTap() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()

        let disclosure = app.buttons["reviewDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(reviewTextInput().exists)

        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        let reviewInput = reviewTextInput()
        reveal(reviewInput, maxSwipes: 5)
        XCTAssertTrue(reviewInput.waitForExistence(timeout: 5))
    }

    @MainActor
    func testJournalAssistDraftRequiresExplicitAcceptance() throws {
        launchResetApp()
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating("4.5")

        let reactionChip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reactionChip-")
        ).firstMatch
        XCTAssertTrue(reactionChip.waitForExistence(timeout: 5))
        let selectedReactionName = reactionChip.label
        reactionChip.tap()

        openReviewDisclosure()
        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Original manual review.")

        tapAssistButton(identifier: "helpMeWriteButton", fallbackLabel: "Help me write")
        let generateDraftButton = app.buttons["helpWriteGenerateJournalDraftButton"]
        reveal(generateDraftButton)
        XCTAssertTrue(generateDraftButton.waitForExistence(timeout: 5), "Help Me Write sheet should expose generate draft action")
        generateDraftButton.tap()

        let draftEditor = app.descendants(matching: .any)["journalAssistDraftEditor"]
        reveal(draftEditor)
        XCTAssertTrue(draftEditor.waitForExistence(timeout: 10), "Journal Assist should show generated draft editor")
        XCTAssertTrue(
            (draftEditor.value as? String)?.localizedCaseInsensitiveContains(selectedReactionName) == true,
            "Journal Assist should receive the selected reactions as context"
        )
        XCTAssertFalse(app.buttons["generateJournalTagsButton"].exists)

        XCTAssertTrue((reviewTextEditor.value as? String)?.contains("Original manual review.") == true)
        XCTAssertFalse((reviewTextEditor.value as? String)?.contains("I rated SOS") == true)

        let acceptDraftButton = app.buttons["acceptJournalDraftButton"]
        reveal(acceptDraftButton)
        XCTAssertTrue(acceptDraftButton.waitForExistence(timeout: 5))
        acceptDraftButton.tap()

        XCTAssertTrue((reviewTextEditor.value as? String)?.contains("I rated SOS") == true)
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
        createSOSLog(rating: "4.0", review: "No highlight review.", reaction: "simple")

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

        openReviewDisclosure()
        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText("Fast save review.")

        app.buttons["saveLogButton"].tap()

        XCTAssertTrue(app.staticTexts["Already logged"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.navigationBars["New Log"].exists)
    }

    @MainActor
    func testTodayPickLockedStateShowsDistinctAlbumProgress() throws {
        launchResetApp()

        openTab("Home")
        XCTAssertTrue(app.staticTexts["Log 5 more distinct albums to unlock."].waitForExistence(timeout: 5))
        app.buttons["todayPickLink"].tap()

        XCTAssertTrue(app.staticTexts["Log 5 more distinct albums to unlock Today's Pick. Ratings alone count."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["findTodayPickButton"].isEnabled)
    }

    @MainActor
    func testTodayPickFeedbackClearsActiveRecommendation() throws {
        launchResetApp(additionalArguments: ["-seed-today-pick-eligible"])

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
    func testTodayPickSavePersistsInSavedPicksAndUsesSharedMatchLabel() throws {
        launchResetApp(additionalArguments: ["-seed-today-pick-eligible"])

        openTab("Home")
        app.buttons["todayPickLink"].tap()
        app.buttons["findTodayPickButton"].tap()

        let detailQuality = app.descendants(matching: .any)["todayPickMatchQualityText"]
        XCTAssertTrue(detailQuality.waitForExistence(timeout: 5))
        XCTAssertEqual(detailQuality.label, "Good match")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "match confidence:")).count, 0)

        let pickTitleElement = app.descendants(matching: .any)["todayPickStateText"]
        XCTAssertTrue(pickTitleElement.waitForExistence(timeout: 5))
        let pickTitle = pickTitleElement.label
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let homeQuality = app.descendants(matching: .any)["homeTodayPickMatchQualityText"]
        XCTAssertTrue(homeQuality.waitForExistence(timeout: 5))
        XCTAssertEqual(homeQuality.label, "Good match")

        app.buttons["todayPickLink"].tap()
        app.buttons["saveRecommendationButton"].tap()

        XCTAssertTrue(app.staticTexts["Saved to Saved Picks. You can generate another pick."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved Picks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveRecommendationButton"].exists)

        let savedPick = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "savedPickLink-")
        ).firstMatch
        XCTAssertTrue(savedPick.waitForExistence(timeout: 5))
        XCTAssertTrue(savedPick.label.contains(pickTitle))
        savedPick.tap()

        XCTAssertTrue(app.navigationBars["Album"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[pickTitle].waitForExistence(timeout: 5))

        app.terminate()
        launchAppPreservingData()
        openTab("Home")
        app.buttons["todayPickLink"].tap()

        XCTAssertTrue(app.staticTexts["Saved Picks"].waitForExistence(timeout: 5))
        let persistedSavedPick = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "savedPickLink-")
        ).firstMatch
        XCTAssertTrue(persistedSavedPick.waitForExistence(timeout: 5))
        XCTAssertTrue(persistedSavedPick.label.contains(pickTitle))
    }

    @MainActor
    func testTodayPickRecommendationModeSettingsPersistWithoutChangingActivePick() throws {
        launchResetApp(additionalArguments: ["-seed-today-pick-eligible"])

        openTab("Home")
        app.buttons["todayPickLink"].tap()
        XCTAssertTrue(app.buttons["todayPickSettingsLink"].waitForExistence(timeout: 5))
        app.buttons["todayPickSettingsLink"].tap()

        XCTAssertTrue(app.navigationBars["Today’s Pick Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Changes apply to your next pick. Your current pick won’t change."].exists)

        app.buttons["Familiar"].tap()
        XCTAssertTrue(app.staticTexts["Stays close to the artists, genres, eras, and tags you already love."].waitForExistence(timeout: 2))
        app.buttons["Balanced"].tap()
        XCTAssertTrue(app.staticTexts["Uses a mix of familiarity and discovery, matching Today's Pick's original behavior."].waitForExistence(timeout: 2))
        app.buttons["Adventurous"].tap()
        XCTAssertTrue(app.staticTexts["Explores new artists and adjacent sounds, always tied back to your logs."].waitForExistence(timeout: 2))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["findTodayPickButton"].tap()
        let pickTitle = app.descendants(matching: .any)["todayPickStateText"]
        XCTAssertTrue(pickTitle.waitForExistence(timeout: 5))
        let originalPickTitle = pickTitle.label

        app.buttons["todayPickSettingsLink"].tap()
        app.buttons["Familiar"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.descendants(matching: .any)["todayPickStateText"].label, originalPickTitle)

        app.terminate()
        launchAppPreservingData()
        openTab("Home")
        app.buttons["todayPickLink"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["todayPickStateText"].label, originalPickTitle)
        app.buttons["todayPickSettingsLink"].tap()
        XCTAssertTrue(app.buttons["Familiar"].isSelected)
    }

    @MainActor
    func testAlbumDetailShowsPreviewUnavailableWithMockService() throws {
        launchResetApp()

        openAlbumDetailFromSearch()
        assertPreviewUnavailableAfterTap()
    }

    @MainActor
    func testTodayPickShowsPreviewUnavailableWithMockService() throws {
        launchResetApp(additionalArguments: ["-seed-today-pick-eligible"])

        openTab("Home")
        app.buttons["todayPickLink"].tap()
        app.buttons["findTodayPickButton"].tap()

        XCTAssertTrue(app.buttons["likeRecommendationButton"].waitForExistence(timeout: 5))
        assertPreviewUnavailableAfterTap()
    }

    private func launchResetApp(additionalArguments: [String] = []) {
        app.launchArguments = ["-ui-testing", "-reset-ui-testing-data"] + additionalArguments
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

    private func createSOSLog(rating: String, review: String, reaction: String) {
        openAlbumDetailFromSearch()

        app.buttons["logThisAlbumButton"].tap()
        selectRating(rating)
        addCustomReaction(reaction)

        openReviewDisclosure()
        let reviewTextEditor = reviewTextInput()
        XCTAssertTrue(reviewTextEditor.waitForExistence(timeout: 5))
        reviewTextEditor.tap()
        reviewTextEditor.typeText(review)

        app.buttons["saveLogButton"].tap()

        openTab("Home")
    }

    private func reviewTextInput() -> XCUIElement {
        app.descendants(matching: .any)["reviewTextEditor"]
    }

    private func openReviewDisclosure() {
        let disclosure = app.buttons["reviewDisclosure"]
        makeEditorElementHittable(disclosure)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))

        if disclosure.value as? String != "Expanded" {
            disclosure.tap()
        }

        XCTAssertEqual(disclosure.value as? String, "Expanded")
        let reviewInput = reviewTextInput()
        reveal(reviewInput, maxSwipes: 5)
        XCTAssertTrue(reviewInput.waitForExistence(timeout: 5))
    }

    private func assertReactionPrompt(_ expectedPrompt: String) {
        let prompt = app.descendants(matching: .any)["reactionPromptText"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertEqual(prompt.label, expectedPrompt)
    }

    private func openReactionBrowser() {
        dismissKeyboardIfNeeded()

        let moreButton = app.buttons["reactionMoreButton"]
        makeEditorElementHittable(moreButton)
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5))
        XCTAssertTrue(moreButton.isHittable)
        moreButton.tap()

        XCTAssertTrue(app.navigationBars["More Reactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reactionBrowser"].waitForExistence(timeout: 5))
    }

    private func reactionSearchField() -> XCUIElement {
        let searchField = app.searchFields["Search reactions"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        return searchField
    }

    private func addCustomReaction(_ reaction: String) {
        openReactionBrowser()
        replaceText(in: reactionSearchField(), with: reaction)

        let keepCustomButton = app.buttons["keepCustomReactionButton"]
        reveal(keepCustomButton, maxSwipes: 5)
        XCTAssertTrue(keepCustomButton.waitForExistence(timeout: 5))
        XCTAssertTrue(keepCustomButton.isHittable)
        keepCustomButton.tap()

        let selectedIdentifier = reaction
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        XCTAssertTrue(
            app.buttons["selectedReaction-custom-\(selectedIdentifier)"].waitForExistence(timeout: 5)
        )

        dismissSearchKeyboardIfNeeded()
        let doneButton = app.buttons["reactionBrowserDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reactionBrowser"].waitForNonExistence(timeout: 5))
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()

        if let currentValue = element.value as? String,
           !currentValue.isEmpty,
           currentValue != element.placeholderValue {
            element.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            )
        }

        element.typeText(text)
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
        dismissKeyboardIfNeeded()

        let disclosure = app.buttons["trackHighlightsDisclosure"]
        makeEditorElementHittable(disclosure)
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.isHittable)
        disclosure.tap()
    }

    private func makeEditorElementHittable(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeDown()
        }

        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
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

    private func dismissSearchKeyboardIfNeeded() {
        guard app.keyboards.element.exists else {
            return
        }

        let closeButton = app.keyboards.buttons["Close"]
        if closeButton.waitForExistence(timeout: 1) {
            closeButton.tap()
        } else {
            app.swipeDown()
        }
    }

    private func tapAssistButton(identifier: String, fallbackLabel: String) {
        dismissKeyboardIfNeeded()

        var element = app.descendants(matching: .any)[identifier]
        if !element.waitForExistence(timeout: 2) {
            element = app.buttons[fallbackLabel]
        }

        reveal(element, maxSwipes: 5)

        let chipScroll = app.descendants(matching: .any)["reviewAssistChipScroll"]
        let nudgeLabel = app.staticTexts["Need a nudge?"]
        for _ in 0..<5 where !element.isHittable {
            if chipScroll.exists {
                chipScroll.swipeLeft()
            } else if nudgeLabel.exists {
                nudgeLabel.swipeLeft()
            }
        }

        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing assist button \(identifier)")
        if element.isHittable {
            element.tap()
        } else if element.frame.width > 0 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if chipScroll.exists {
            chipScroll.swipeLeft()
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Assist button \(identifier) remained offscreen")
            element.tap()
        } else {
            XCTFail("Assist button \(identifier) was not tappable")
        }
    }

    private func currentRatingValue(from control: XCUIElement) -> Double? {
        guard let value = control.value as? String else {
            return nil
        }

        return Double(value.components(separatedBy: " ").first ?? "")
    }

    private func appendText(in element: XCUIElement, text: String) {
        reveal(element, maxSwipes: 5)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        element.tap()
        element.typeText(text)
    }
}
