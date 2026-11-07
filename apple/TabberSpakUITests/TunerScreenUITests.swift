import XCTest

/// Tabber Tuner against DemoHost: in the demo a guitar is tuned string by
/// string, so the dial names notes and says how far off they are, against the
/// chosen track's strings.
final class TunerScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch(["-demo", "-screen", "tuner"]) }

    /// The note the dial names: "A2" from "A2, 24 cents flat".
    @MainActor
    func note() -> String {
        String((element("tuner-dial").value as? String ?? "").split(separator: ",").first ?? "")
    }

    @MainActor
    func testTheDialNamesTheStringAndHowFarOff() {
        XCTAssertTrue(appears("tuner-dial"))
        XCTAssertTrue(waitFor("tuner-dial", "in tune", timeout: 6), "a string settles in tune")
        let first = note()
        XCTAssertTrue(["E2", "A2", "D3", "G3", "B3", "E4"].contains(first), "a string of the guitar, not \(first)")
        let deadline = Date().addingTimeInterval(6)
        while note() == first && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertNotEqual(note(), first, "then the next string")
        XCTAssertTrue(waitFor("tuner-strings", "Strings of Guitar"))
    }

    @MainActor
    func testAnAudioTrackTunesToAStandardGuitar() {
        app.tabBars.buttons["Tracks"].tap()
        tap("track-Bass")
        XCTAssertTrue(waitSelected("track-Bass"))
        app.tabBars.buttons["Tuner"].tap()
        XCTAssertTrue(waitFor("tuner-strings", "Strings of Bass"), "the bass's four strings")
        app.tabBars.buttons["Tracks"].tap()
        tap("track-Vocals")
        app.tabBars.buttons["Tuner"].tap()
        XCTAssertTrue(waitFor("tuner-strings", "Standard tuning"))
    }
}
