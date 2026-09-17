import XCTest

extension XCUIApplication {
    /// iPad exposes its top tab controls as buttons outside a TabBar container.
    func listendTab(_ title: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
}
