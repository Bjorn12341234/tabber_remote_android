import XCTest

/// TR7: every control on the Session screen, against DemoHost.
final class SessionScreenUITests: XCTestCase {
    var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(waitFor("connection", "Demo Studio"))
    }

    /// The element by identifier (the app gives the accessory's inline copy its own).
    @MainActor
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Wait until the control can be hit, then tap it.
    @MainActor
    func tap(_ id: String) {
        let target = element(id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed, "\(id) never became tappable")
        target.tap()
    }

    @MainActor
    func waitFor(_ id: String, _ text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else { return false }
            return "\(element.label) \(element.value as? String ?? "")".contains(text)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element(id))],
                                timeout: timeout) == .completed
    }

    @MainActor
    func gone(_ id: String, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(id))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testMarkersJumpAndLoop() {
        element("marker-Chorus").tap()
        XCTAssertTrue(waitFor("playhead", "Bar 25, beat 1"))
        XCTAssertTrue(waitFor("section", "Chorus"))
        element("marker-Verse").press(forDuration: 0.8)
        XCTAssertTrue(waitFor("marker-Verse", "looping"))
        XCTAssertTrue(waitFor("loop", "On"))
    }

    @MainActor
    func testTheToggles() {
        element("click").tap()
        XCTAssertTrue(waitFor("click", "On"))
        element("click").tap()
        XCTAssertTrue(waitFor("click", "Off"))
        element("count-in").tap()
        XCTAssertTrue(waitFor("count-in", "Count-in 1 bar"))
        element("count-in").tap()
        XCTAssertTrue(waitFor("count-in", "Count-in 2 bars"))
        element("count-in").tap()
        XCTAssertTrue(waitFor("count-in", "No count-in"))
        element("loop").tap()
        XCTAssertTrue(waitFor("loop", "On"))
    }

    @MainActor
    func testArmRecordStopAndGoAgain() {
        tap("record")
        XCTAssertTrue(waitFor("problem", "Arm a track first"))
        element("arm-Vocals").tap()
        XCTAssertTrue(waitFor("armed-track", "Vocals"))
        XCTAssertTrue(waitFor("record", "Record on Vocals"))
        element("marker-Chorus").tap()
        tap("record")
        XCTAssertTrue(waitFor("rec-lamp", "Recording"))
        XCTAssertTrue(waitFor("record", "Stop recording"))
        tap("record")
        XCTAssertTrue(gone("rec-lamp"))
        tap("go-again")
        XCTAssertTrue(waitFor("rec-lamp", "Recording"))
        XCTAssertTrue(waitFor("section", "Chorus"))
        tap("record")
        XCTAssertTrue(gone("rec-lamp"))
    }

    @MainActor
    func testPlayAndStop() {
        tap("play")
        XCTAssertTrue(waitFor("play", "Stop"))
        tap("play")
        XCTAssertTrue(waitFor("play", "Play"))
    }
}
