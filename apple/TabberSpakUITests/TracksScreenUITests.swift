import XCTest

/// The Tracks screen and the transport, against DemoHost: choose a track,
/// hear one alone, mute, arm, record, and Studio's toggles.
final class TracksScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch() }

    @MainActor
    func testChooseHearAloneAndMute() {
        XCTAssertTrue(waitSelected("track-Guitar"))
        tap("track-Bass")
        XCTAssertTrue(waitSelected("track-Bass"))
        XCTAssertTrue(waitSelected("track-Guitar", false))
        tap("solo-Bass")
        XCTAssertTrue(waitSelected("solo-Bass"))
        XCTAssertTrue(waitFor("track-Guitar", "not heard"), "a solo silences the other tracks")
        tap("solo-Bass")
        XCTAssertTrue(waitSelected("solo-Bass", false))
        tap("mute-Drums")
        XCTAssertTrue(waitSelected("mute-Drums"))
        XCTAssertTrue(waitFor("track-Drums", "not heard"))
    }

    @MainActor
    func testTheToggles() {
        for id in ["loop", "count-in", "click"] {
            tap(id)
            XCTAssertTrue(waitSelected(id), "\(id) did not turn on")
            tap(id)
            XCTAssertTrue(waitSelected(id, false), "\(id) did not turn off")
        }
    }

    @MainActor
    func testArmRecordAndStop() {
        XCTAssertTrue(appears("record-hint"))
        XCTAssertTrue(waitFor("record", "Record"))
        recordOneTake()
        XCTAssertTrue(gone("record-hint"), "with a track armed the hint goes")
        XCTAssertTrue(appears("take-Vocals take 1"), "the take joins the list")
    }

    @MainActor
    func testRecordWithNothingArmedSaysWhatToDo() {
        tap("record")
        XCTAssertTrue(waitFor("problem", "Arm a track first"))
    }

    @MainActor
    func testPlayStopAndBackToTheStart() {
        tap("play")
        XCTAssertTrue(waitSelected("play"))
        tap("stop")
        XCTAssertTrue(waitSelected("play", false))
        XCTAssertTrue(waitFor("stop", "Go to the start"))
        tap("stop")
        XCTAssertTrue(waitFor("readout", "Bar 1, beat 1"))
    }

    @MainActor
    func testTheComputersViewButtons() {
        let editors = app.segmentedControls["view-editor"]
        XCTAssertTrue(editors.waitForExistence(timeout: 8))
        XCTAssertTrue(editors.buttons["Tab"].isSelected, "the demo computer shows Tab")
        editors.buttons["Arrange"].tap()
        XCTAssertTrue(waitSelectedSegment(editors, "Arrange"))
        tap("view-split")
        XCTAssertTrue(waitSelected("view-split"), "Split is on")
        XCTAssertTrue(waitSelectedSegment(editors, "Tab"), "beside Arrange, the Tab")
        tap("view-split")
        XCTAssertTrue(waitSelected("view-split", false))
        XCTAssertTrue(waitSelectedSegment(editors, "Arrange"), "Split off goes back to Arrange")
        editors.buttons["Piano Roll"].tap()
        XCTAssertTrue(waitSelectedSegment(editors, "Piano Roll"))
    }

    @MainActor
    func waitSelectedSegment(_ control: XCUIElement, _ title: String) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: control.buttons[title])],
                                timeout: 8) == .completed
    }
}
