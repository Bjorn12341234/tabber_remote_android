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
            // The sheet's Done is iOS's own toolbar button, whose largest sizes iOS caps.
            if issue.auditType == .dynamicType, issue.element?.identifier == "done" { return true }
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
    func testEveryScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-reset-input"]
        app.launch()
        let connection = element(app, "connection")
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Demo Studio'"), object: connection)
        XCTAssertEqual(XCTWaiter().wait(for: [connected], timeout: 8), .completed)
        try audit(app, "Tracks")
        element(app, "arm-Vocals").tap()
        element(app, "record").tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Recording'"), object: element(app, "readout"))
        XCTAssertEqual(XCTWaiter().wait(for: [recording], timeout: 12), .completed)
        element(app, "record").tap()
        XCTAssertTrue(element(app, "take-card").waitForExistence(timeout: 8))
        try audit(app, "Take card")
        element(app, "keep").tap()
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(element(app, "fretboard").waitForExistence(timeout: 8))
        try audit(app, "Tab")
        app.segmentedControls.buttons["Piano"].tap()
        XCTAssertTrue(element(app, "piano").waitForExistence(timeout: 8))
        try audit(app, "Piano")
        app.tabBars.buttons["Mixer"].tap()
        XCTAssertTrue(element(app, "fader-Guitar").waitForExistence(timeout: 8))
        try audit(app, "Mixer")
        element(app, "connection").tap()
        XCTAssertTrue(element(app, "done").waitForExistence(timeout: 8))
        try audit(app, "Computer")
    }
}
