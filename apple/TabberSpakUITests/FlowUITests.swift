import XCTest

/// Wiring by hand in the routing Flow, against DemoHost (TR43). The owner:
/// "in flow, i dont seem to be able to move by hand the connections
/// manually". As in Studio's Flow: a wire dragged from a card's output port
/// onto a bus makes a track's output or a send there (Studio's plain or Option
/// drag), onto the Master it goes back there, and a bus that would loop is
/// refused in Studio's words. A card's menu takes a send away.
final class FlowUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws {
        launch(["-demo", "-screen", "mixer"])
    }

    @MainActor
    private func openFlow() {
        app.segmentedControls["mixer-page"].buttons["Flow"].tap()
        XCTAssertTrue(appears("flow-Master"))
    }

    /// Drag a wire from the source card's output port (its right edge) to the target card.
    @MainActor
    private func wire(_ source: String, to target: String) {
        let from = element("flow-\(source)").coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
        let to = element("flow-\(target)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    @MainActor
    private func pill(_ words: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    @MainActor
    func testATracksOutputIsWiredToABusAndBackToTheMaster() {
        openFlow()
        XCTAssertTrue(waitFor("flow-Guitar", "out to Master"))
        wire("Guitar", to: "Reverb")
        let output = app.buttons["Output to Reverb"]
        XCTAssertTrue(output.waitForExistence(timeout: 8), "a track's wire on a bus asks: output or send")
        output.tap()
        XCTAssertTrue(waitFor("flow-Guitar", "out to Reverb"), "the computer confirms the new output")
        wire("Guitar", to: "Master")
        XCTAssertTrue(waitFor("flow-Guitar", "out to Master"), "on the Master, the output goes back there")
    }

    @MainActor
    func testASendIsWiredByHandAndTheCardsMenuTakesItAway() {
        openFlow()
        XCTAssertFalse(pill("Bass sends to Reverb").exists)
        wire("Bass", to: "Reverb")
        let send = app.buttons["Send to Reverb"]
        XCTAssertTrue(send.waitForExistence(timeout: 8))
        send.tap()
        XCTAssertTrue(pill("Bass sends to Reverb at -6.0 dB").waitForExistence(timeout: 8),
                      "the new send's wire and pill, at Studio's -6 dB")
        XCTAssertTrue(waitFor("flow-Bass", "out to Master"), "a send leaves the output where it was")
        element("flow-Bass").press(forDuration: 1.2)
        let remove = app.buttons["Remove send to Reverb"]
        XCTAssertTrue(remove.waitForExistence(timeout: 8), "holding a card opens its menu")
        remove.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: pill("Bass sends to Reverb"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 8), .completed, "the send is gone")
    }

    @MainActor
    func testABusThatWouldLoopIsRefusedInStudiosWords() {
        tap("add-bus")
        let alert = app.alerts["New Bus"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.textFields.firstMatch.typeText("Delay")
        alert.buttons["Add Bus"].tap()
        XCTAssertTrue(appears("fader-Delay"))
        openFlow()
        XCTAssertTrue(appears("flow-Delay"))
        wire("Reverb", to: "Delay")
        XCTAssertTrue(waitFor("flow-Reverb", "out to Delay"), "a bus's wire moves its output, no question")
        wire("Delay", to: "Reverb")
        let refused = app.alerts["Not routed"]
        XCTAssertTrue(refused.waitForExistence(timeout: 8), "a loop is refused")
        XCTAssertTrue(refused.staticTexts["Reverb would loop: Delay → Reverb → Delay."].exists)
        refused.buttons["OK"].tap()
        XCTAssertTrue(waitFor("flow-Delay", "out to Master"), "and nothing changed")
    }
}
