import XCTest

/// The Mixer against DemoHost: S, M, a fader drag and a double tap back to 0 dB.
final class MixerScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch(["-demo", "-screen", "mixer"]) }

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
