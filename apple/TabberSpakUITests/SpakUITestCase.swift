import XCTest

/// What every screen's UI tests share: launching against DemoHost and
/// finding, tapping and waiting for controls by identifier.
class SpakUITestCase: XCTestCase {
    var app: XCUIApplication!

    @MainActor
    func launch(_ arguments: [String] = ["-demo"]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = arguments + ["-reset-input"]
        app.launch()
        XCTAssertTrue(waitFor("connection", "Demo Studio"), "the demo computer never connected")
    }

    /// The element by identifier (the app gives the accessory's inline copy its own).
    @MainActor
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Wait until the control is on screen, then tap it. iOS can keep an
    /// offscreen copy of the transport (an infinite frame), so the copy that
    /// is on screen is the one tapped.
    @MainActor
    func tap(_ id: String) {
        let query = app.descendants(matching: .any).matching(identifier: id)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let shown = query.allElementsBoundByIndex.first { element in
                let frame = element.frame
                return element.exists && !frame.isEmpty && frame.origin.x.isFinite && frame.origin.y.isFinite
                    && app.frame.intersects(frame)
            }
            if let shown, shown.isHittable {
                shown.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("\(id) never became tappable")
    }

    /// Scroll the screen until the control is in view, as a thumb would.
    @MainActor
    func reveal(_ id: String) {
        for _ in 0..<4 where !element(id).isHittable { app.swipeUp() }
    }

    /// Wait until the element's label or value says this.
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
    func waitSelected(_ id: String, _ selected: Bool = true, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND selected == %@", NSNumber(value: selected))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element(id))],
                                timeout: timeout) == .completed
    }

    @MainActor
    func appears(_ id: String, timeout: TimeInterval = 8) -> Bool { element(id).waitForExistence(timeout: timeout) }

    /// Wait until nothing on screen has this identifier.
    @MainActor
    func gone(_ id: String, timeout: TimeInterval = 8) -> Bool {
        let query = app.descendants(matching: .any).matching(identifier: id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == 0 { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return query.count == 0
    }

    /// Arm Vocals, record a moment from the chorus and stop: the take card shows.
    @MainActor
    func recordOneTake() {
        if !element("arm-Vocals").isSelected { tap("arm-Vocals") }
        XCTAssertTrue(waitFor("record", "Record on Vocals"))
        tap("readout")
        tap("goto-Chorus")
        XCTAssertTrue(waitFor("readout", "Bar 25"))
        tap("record")
        XCTAssertTrue(waitFor("readout", "Recording", timeout: 12))
        tap("record")
        XCTAssertTrue(appears("take-card"))
    }
}
