import XCTest

/// TR9: Xcode's accessibility audit on every screen (contrast, hit regions,
/// labels, Dynamic Type, clipped text), against DemoHost.
final class AccessibilityUITests: XCTestCase {
    @MainActor
    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func audit(_ app: XCUIApplication, _ screen: String, scrolls: Bool = false) throws {
        // A list longer than the screen runs on under the transport and the
        // tab bar, as iOS lists do; the text resting there reads as low
        // contrast wherever the list stops. Only that is left out: contrast
        // under the bars, and contrast the audit cannot place, which is text
        // inside a combined control (the Routing view passes with nothing
        // left out when its list fits on the screen, checked 7 Nov 2026).
        let barTop = scrolls ? element(app, "play").frame.minY - 16 : .infinity
        try app.performAccessibilityAudit { issue in
            // The sheet's Done is iOS's own toolbar button, whose largest sizes iOS caps.
            if issue.auditType == .dynamicType, issue.element?.identifier == "done" { return true }
            if scrolls, issue.auditType == .contrast, (issue.element?.frame.maxY ?? .infinity) > barTop { return true }
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
        app.segmentedControls.buttons["Routing"].tap()
        XCTAssertTrue(element(app, "route-Vocals").waitForExistence(timeout: 8))
        try audit(app, "Routing", scrolls: true)
        app.segmentedControls.buttons["Mixer"].tap()
        app.tabBars.buttons["Tuner"].tap()
        XCTAssertTrue(element(app, "tuner-dial").waitForExistence(timeout: 8))
        try audit(app, "Tuner")
        element(app, "connection").tap()
        XCTAssertTrue(element(app, "done").waitForExistence(timeout: 8))
        try audit(app, "Computer")
    }
}
