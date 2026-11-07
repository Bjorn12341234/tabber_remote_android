import XCTest

/// The Mixer's Routing view against DemoHost: move a track's output to a bus
/// and back, add a send, set it to Pre-fader, take it away, and Undo.
final class RoutingScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws {
        launch(["-demo", "-screen", "mixer"])
        app.segmentedControls["mixer-page"].buttons["Routing"].tap()
        XCTAssertTrue(appears("route-Vocals"))
    }

    @MainActor
    func testAnOutputMovesToABusAndBack() {
        XCTAssertTrue(waitFor("output-Vocals", "Master"))
        tap("output-Vocals")
        app.buttons["Reverb"].firstMatch.tap()
        XCTAssertTrue(waitFor("output-Vocals", "Reverb"), "the computer confirms the new output")
        XCTAssertTrue(waitFor("fed-Reverb", "Output from Vocals"))
        tap("output-Vocals")
        app.buttons["Master"].firstMatch.tap()
        XCTAssertTrue(waitFor("output-Vocals", "Master"))
    }

    @MainActor
    func testASendIsAddedSetAndTakenAwayAndUndoBringsItBack() {
        XCTAssertTrue(waitFor("fed-Reverb", "Sends from Lead guitar and Vocals"))
        tap("add-send-Guitar")
        app.buttons["Send to Reverb"].firstMatch.tap()
        XCTAssertTrue(waitFor("fed-Reverb", "Sends from Guitar, Lead guitar and Vocals"), "the new send shows")
        XCTAssertTrue(waitFor("send-Guitar-Reverb", "-6.0 decibels"), "a new send starts at -6 dB, as in Tabber Studio")
        tap("pre-Guitar-Reverb")
        XCTAssertTrue(waitSelected("pre-Guitar-Reverb"), "Pre-fader is on")
        tap("remove-send-Guitar-Reverb")
        XCTAssertTrue(waitFor("fed-Reverb", "Sends from Lead guitar and Vocals"), "the send is gone")
        XCTAssertTrue(waitFor("undo", "Remove send → Reverb"))
        tap("undo")
        XCTAssertTrue(waitFor("fed-Reverb", "Sends from Guitar, Lead guitar and Vocals"), "Undo brings it back")
        XCTAssertTrue(waitSelected("pre-Guitar-Reverb"), "as it was, Pre-fader and all")
    }
}
