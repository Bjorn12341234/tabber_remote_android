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
        XCTAssertTrue(waitFor("play", "Play"))
        tap("play")
        XCTAssertTrue(waitSelected("play"))
        XCTAssertTrue(waitFor("play", "Pause"), "Play turns into Pause while playing, as in Tabber Studio")
        tap("play")
        XCTAssertTrue(waitSelected("play", false))
        XCTAssertTrue(waitFor("play", "Play"), "and back")
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

    /// S6: the Speed Trainer shows only with Loop on, as in Tabber Studio;
    /// a field's menu sets it, and Loop off turns it off.
    @MainActor
    func testTheSpeedTrainerShowsWithLoop() {
        XCTAssertTrue(gone("trainer"), "no trainer while Loop is off")
        tap("loop")
        XCTAssertTrue(appears("trainer"), "Loop on shows the trainer")
        XCTAssertTrue(waitFor("trainer-speed", "100"))
        tap("trainer")
        XCTAssertTrue(waitSelected("trainer"), "the trainer is on")
        XCTAssertTrue(waitFor("trainer-speed", "50"), "it starts at the start speed, 50% in the demo")
        tap("trainer-start")
        let seventy = app.buttons["70%"]
        XCTAssertTrue(seventy.waitForExistence(timeout: 8))
        seventy.tap()
        XCTAssertTrue(waitFor("trainer-start", "70"))
        XCTAssertTrue(waitFor("trainer-speed", "70"), "a changed start starts the ramp again")
        tap("loop")
        XCTAssertTrue(gone("trainer"), "Loop off hides the trainer")
        tap("loop")
        XCTAssertTrue(appears("trainer"))
        XCTAssertTrue(waitSelected("trainer", false), "and Loop off turned it off")
    }

    /// At the largest text the toggles stack and the trainer's fields grow,
    /// one to a line, within the screen.
    @MainActor
    func testTheTogglesAndTrainerAtTheLargestText() {
        launch(["-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap("loop")
        tap("trainer")
        XCTAssertTrue(waitSelected("trainer"))
        XCTAssertGreaterThan(element("count-in").frame.minY, element("loop").frame.maxY - 1, "stacked, not side by side")
        let start = element("trainer-start").frame, step = element("trainer-step").frame
        XCTAssertGreaterThan(start.height, 50, "the field grows with the text (44 points at the default size)")
        XCTAssertGreaterThan(step.minY, start.maxY - 1, "one field to a line")
        XCTAssertLessThanOrEqual(start.maxX, app.frame.maxX, "within the screen")
    }

    /// TR36: "+ Add Track" under the last track asks what kind, as Tabber
    /// Studio's chooser does. A tab track comes in after the last tab or MIDI
    /// track, selected, with Undo for a moment; an audio track goes last, and
    /// the computer turns from Tab to Arrange to show it.
    @MainActor
    func testAddATrackOfEachKind() {
        reveal("add-track")
        tap("add-track")
        let tab = app.buttons["Tab track"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "the chooser asks what kind")
        XCTAssertTrue(app.buttons["MIDI track"].exists && app.buttons["Audio track"].exists)
        tab.tap()
        XCTAssertTrue(waitSelected("track-Track 4"), "the new tab track comes selected")
        XCTAssertTrue(app.staticTexts["Track 4 added"].waitForExistence(timeout: 8))
        XCTAssertLessThan(element("track-Track 4").frame.minY, element("track-Lead guitar").frame.minY,
                          "before the audio tracks, as the computer lists them")
        tap("undo-delete")
        XCTAssertTrue(gone("track-Track 4"), "Undo takes it back")
        XCTAssertTrue(waitSelectedSegment(app.segmentedControls["view-editor"], "Tab"))
        reveal("add-track")
        tap("add-track")
        let audio = app.buttons["Audio track"]
        XCTAssertTrue(audio.waitForExistence(timeout: 8))
        audio.tap()
        XCTAssertTrue(appears("track-Audio 3"))
        XCTAssertTrue(waitSelectedSegment(app.segmentedControls["view-editor"], "Arrange"),
                      "the computer turns from Tab to Arrange to show the new audio track")
    }

    @MainActor
    func waitSelectedSegment(_ control: XCUIElement, _ title: String) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: control.buttons[title])],
                                timeout: 8) == .completed
    }
}
