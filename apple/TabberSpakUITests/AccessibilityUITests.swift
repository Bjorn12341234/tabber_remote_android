import XCTest

/// TR9: Xcode's accessibility audit on every screen (contrast, hit regions,
/// labels, Dynamic Type, clipped text), against DemoHost.
final class AccessibilityUITests: XCTestCase {
    @MainActor
    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func audit(_ app: XCUIApplication, _ screen: String, scrolls: Bool = false, within region: CGRect? = nil,
               diagram: CGRect? = nil) throws {
        // A list longer than the screen runs on under the transport and the
        // tab bar, as iOS lists do; the text resting there reads as low
        // contrast wherever the list stops. Only that is left out: contrast
        // under the bars, and contrast the audit cannot place, which is text
        // inside a combined control (the Routing view passes with nothing
        // left out when its list fits on the screen, checked 7 Nov 2026).
        // The bottom of what reads: the take card when it shows, else the transport.
        var barTop = CGFloat.infinity
        if scrolls {
            let card = element(app, "take-card"), play = element(app, "play")
            barTop = (card.exists ? min(card.frame.minY, play.frame.minY) : play.frame.minY) - 16
        }
        try app.performAccessibilityAudit { issue in
            // A second look at part of a screen: the rest had its own audit just before.
            if let region, !(issue.element.map { region.intersects($0.frame) } ?? false) { return true }
            // The routing Flow is a diagram: its words grow with a pinch, not with
            // the text size, and the Routing page says the same in text that grows.
            if let diagram, [.dynamicType, .textClipped].contains(issue.auditType),
               diagram.intersects(issue.element?.frame ?? .zero) { return true }
            // The sheet's Done is iOS's own toolbar button, whose largest sizes iOS caps.
            if issue.auditType == .dynamicType, issue.element?.identifier == "done" { return true }
            // The audit flags rows at the foot of the long Computer sheet: "Leave the
            // demo" failed there too, and passes higher up (8 Nov 2026). Those rows'
            // growth is checked at the largest text by ComputerSheetUITests instead.
            if issue.auditType == .dynamicType,
               ["response-again", "response-note"].contains(issue.element?.identifier ?? "") { return true }
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

    /// A song of only audio: the Tab screen's "+ Add Tab Track" (TR36).
    @MainActor
    func testASongOfOnlyAudio() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-only-audio", "-reset-input", "-screen", "tab"]
        app.launch()
        XCTAssertTrue(element(app, "add-tab-track").waitForExistence(timeout: 8))
        try audit(app, "Tab, no tab tracks")
    }

    /// The Tab screen with Tabber Studio's "MIDI part" card (TR39).
    @MainActor
    func testTheMidiPartCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-reset-input"]
        app.launch()
        XCTAssertTrue(element(app, "track-Drums").waitForExistence(timeout: 8))
        element(app, "track-Drums").tap()
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(element(app, "midi-part").waitForExistence(timeout: 8))
        try audit(app, "Tab, a MIDI part")
    }

    /// The routing Flow (TR42).
    @MainActor
    func testTheFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-reset-input", "-screen", "mixer"]
        app.launch()
        XCTAssertTrue(app.segmentedControls["mixer-page"].waitForExistence(timeout: 8))
        app.segmentedControls["mixer-page"].buttons["Flow"].tap()
        XCTAssertTrue(element(app, "flow-Master").waitForExistence(timeout: 8))
        try audit(app, "Flow", diagram: element(app, "flow").frame)
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
        element(app, "loop").tap()                          // Loop on shows the Speed Trainer
        XCTAssertTrue(element(app, "trainer").waitForExistence(timeout: 8))
        element(app, "trainer").tap()
        let toggles = element(app, "loop").frame, trainer = element(app, "trainer-row").frame
        try audit(app, "Tracks with the trainer",
                  within: CGRect(x: 0, y: toggles.minY - 8, width: app.frame.width, height: trainer.maxY - toggles.minY + 16))
        element(app, "loop").tap()
        element(app, "arm-Vocals").tap()
        element(app, "record").tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Recording'"), object: element(app, "readout"))
        XCTAssertEqual(XCTWaiter().wait(for: [recording], timeout: 12), .completed)
        element(app, "record").tap()
        XCTAssertTrue(element(app, "take-card").waitForExistence(timeout: 8))
        try audit(app, "Take card", scrolls: true)        // the takes list runs on under the card
        element(app, "keep").tap()
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(element(app, "fretboard").waitForExistence(timeout: 8))
        try audit(app, "Tab")
        // As for Routing below: right after an audit puts the text size back,
        // a tap can land while the screen lays out again; tap again if needed.
        for _ in 0..<3 where !element(app, "piano").exists {
            app.segmentedControls["input"].buttons["Piano"].tap()
            _ = element(app, "piano").waitForExistence(timeout: 4)
        }
        XCTAssertTrue(element(app, "piano").exists)
        try audit(app, "Piano")
        app.tabBars.buttons["Mixer"].tap()
        XCTAssertTrue(element(app, "fader-Guitar").waitForExistence(timeout: 8))
        try audit(app, "Mixer")
        // Right after the Mixer's audit puts the text size back, a tap can land
        // while the screen lays out again; tap again if the page did not turn.
        for _ in 0..<3 where !element(app, "route-Vocals").exists {
            app.segmentedControls["mixer-page"].buttons["Routing"].tap()
            _ = element(app, "route-Vocals").waitForExistence(timeout: 4)
        }
        XCTAssertTrue(element(app, "route-Vocals").exists)
        try audit(app, "Routing", scrolls: true)
        app.segmentedControls["mixer-page"].buttons["Mixer"].tap()
        app.tabBars.buttons["Tuner"].tap()
        XCTAssertTrue(element(app, "tuner-dial").waitForExistence(timeout: 8))
        try audit(app, "Tuner")
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(element(app, "unlock-chat").waitForExistence(timeout: 8))
        try audit(app, "Chat locked")
        element(app, "unlock-chat").tap()
        let field = element(app, "chat-field")
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Mute the drums")
        element(app, "chat-send").tap()
        XCTAssertTrue(element(app, "chat-plan").waitForExistence(timeout: 8))
        try audit(app, "Chat")
        element(app, "connection").tap()
        XCTAssertTrue(element(app, "done").waitForExistence(timeout: 8))
        try audit(app, "Computer")
    }
}
