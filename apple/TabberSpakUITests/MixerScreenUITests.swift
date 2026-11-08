import XCTest

/// The Mixer against DemoHost: S, M, a fader drag and a double tap back to 0 dB.
final class MixerScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch(["-demo", "-screen", "mixer"]) }

    /// TR41: the mixer header's "+ Bus" asks for the bus's name, as Tabber
    /// Studio's New Bus does, and the bus joins the mixer at once.
    @MainActor
    func testAddBusAsksForItsName() {
        tap("add-bus")
        let alert = app.alerts["New Bus"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "New Bus asks for a name")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertFalse(alert.buttons["Add Bus"].isEnabled, "not without one")
        field.typeText("Delay")
        alert.buttons["Add Bus"].tap()
        XCTAssertTrue(appears("fader-Delay"), "the bus joins the mixer")
    }

    @MainActor
    func testSoloMuteAndTheFader() {
        tap("strip-solo-Lead guitar")
        XCTAssertTrue(waitSelected("strip-solo-Lead guitar"))
        tap("strip-solo-Lead guitar")
        XCTAssertTrue(waitSelected("strip-solo-Lead guitar", false))
        tap("strip-mute-Bass")
        XCTAssertTrue(waitSelected("strip-mute-Bass"))

        let fader = element("fader-Guitar")
        XCTAssertTrue(waitFor("fader-Guitar", "0 decibels"))
        fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        XCTAssertTrue(waitFor("fader-Guitar", "minus"), "dragging down lowers the level")
        fader.doubleTap()
        XCTAssertTrue(waitFor("fader-Guitar", "0 decibels"), "a double tap is 0 dB")
    }
}
