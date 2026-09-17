import XCTest
import UIKit

/// Captures the current interface using isolated sample data, never a user's journal.
final class LaunchScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureLaunchScreens() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-ui-testing-data", "-bypass-onboarding", "-seed-soundprint-reflection-ready"]
        app.launchEnvironment["LISTEND_UI_TEST_STORE_ID"] = "launch-capture-\(UUID())"
        app.launch()

        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func tab(_ title: String) {
            let button = app.listendTab(title)
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }

        XCTAssertTrue(app.buttons["homeActivationActionButton"].waitForExistence(timeout: 5))
        capture("release-01-home")
        tab("Logs")
        XCTAssertTrue(app.descendants(matching: .any)["logsHistoryList"].waitForExistence(timeout: 5))
        capture("release-02-journal")
        tab("Profile")
        let create = app.buttons["createSoundPrintButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let reflection = app.descendants(matching: .any)["soundPrintReflectionLink"].firstMatch
        XCTAssertTrue(reflection.waitForExistence(timeout: 15))
        capture("release-03-profile")
        reflection.tap()
        XCTAssertTrue(app.navigationBars["SoundPrint Reflection"].waitForExistence(timeout: 5))
        capture("release-04-reflection")
        tab("Home")
        app.buttons["todayPickLink"].tap()
        let find = app.buttons["findTodayPickButton"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        XCTAssertTrue(app.staticTexts["todayPickWhyText"].waitForExistence(timeout: 15))
        capture("release-05-todays-pick")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.staticTexts["todayPickWhyText"].waitForExistence(timeout: 5))
            capture("release-06-ipad-landscape")
        }
    }
}
