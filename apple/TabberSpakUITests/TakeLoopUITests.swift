import XCTest

/// TR8: the take card, the Undo offer, the takes list and the tracks list, against DemoHost.
final class TakeLoopUITests: XCTestCase {
    var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(waitFor("connection", "Demo Studio"))
    }

    @MainActor
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

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
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element(id))], timeout: timeout) == .completed
    }

    @MainActor
    func appears(_ id: String) -> Bool { element(id).waitForExistence(timeout: 8) }

    @MainActor
    func gone(_ id: String) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(id))],
                         timeout: 8) == .completed
    }

    @MainActor
    func recordOneTake() {
        tap("arm-Vocals")
        XCTAssertTrue(waitFor("record", "Record on Vocals"))
        tap("marker-Chorus")
        tap("record")
        XCTAssertTrue(appears("rec-lamp"))
        tap("record")
        XCTAssertTrue(appears("take-card"))
    }

    @MainActor
    func testKeepDiscardUndoAndGoAgain() {
        recordOneTake()
        tap("keep")
        XCTAssertTrue(gone("take-card"))

        tap("record")
        XCTAssertTrue(appears("rec-lamp"))
        tap("record")
        XCTAssertTrue(appears("take-card"))
        element("discard").press(forDuration: 1.0)
        XCTAssertTrue(appears("undo-banner"))
        tap("undo-discard")
        XCTAssertTrue(gone("undo-banner"))

        app.tabBars.buttons["Takes"].tap()
        XCTAssertTrue(appears("take-Vocals take 1"))
        XCTAssertTrue(appears("take-Vocals take 2"))      // discarded, then brought back by Undo
        app.tabBars.buttons["Session"].tap()

        tap("record")
        tap("record")
        XCTAssertTrue(appears("take-card"))
        tap("card-go-again")
        XCTAssertTrue(appears("rec-lamp"))
        XCTAssertTrue(waitFor("section", "Chorus"))
    }

    @MainActor
    func testRateFlagAndTracks() {
        recordOneTake()
        tap("keep")
        app.tabBars.buttons["Takes"].tap()
        let stars = element("stars")
        XCTAssertTrue(stars.waitForExistence(timeout: 8))
        stars.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()   // the fourth star
        XCTAssertTrue(waitFor("stars", "4 of 5"))
        app.tabBars.buttons["Session"].tap()
        tap("flag")
        app.tabBars.buttons["Tracks"].tap()
        tap("track-arm-Guitar")
        XCTAssertTrue(waitFor("track-arm-Guitar", "Disarm Guitar"))
        app.tabBars.buttons["Session"].tap()
        XCTAssertTrue(appears("marker-Flag"))
    }
}
