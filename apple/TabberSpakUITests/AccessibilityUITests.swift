import XCTest

/// TR9: Xcode's accessibility audit on every screen (contrast, hit regions,
/// labels, Dynamic Type, clipped text), against DemoHost.
final class AccessibilityUITests: XCTestCase {
    @MainActor
    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            print("AUDIT \(screen): \(issue.auditType) \(issue.compactDescription) | \(issue.detailedDescription) on \(issue.element?.debugDescription.prefix(160) ?? "the screen")")
            return false
        }
    }

    @MainActor
    func testWelcomeAndFindYourComputer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]
        app.launch()
        XCTAssertTrue(element(app, "get-started").waitForExistence(timeout: 8))
        try audit(app, "Welcome")
        element(app, "get-started").tap()
        XCTAssertTrue(element(app, "continue").waitForExistence(timeout: 8))
        try audit(app, "Explainer")
        element(app, "continue").tap()
        XCTAssertTrue(element(app, "scan").waitForExistence(timeout: 8))
        try audit(app, "Find")
    }

    @MainActor
    func testTheSessionAndItsTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let connection = element(app, "connection")
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Demo Studio'"), object: connection)
        XCTAssertEqual(XCTWaiter().wait(for: [connected], timeout: 8), .completed)
        try audit(app, "Session")
        for tab in ["Takes", "Tracks", "Computer"] {
            app.tabBars.buttons[tab].tap()
            try audit(app, tab)
        }
    }
}
