import XCTest

/// The Tab screen against DemoHost: the fretboard and the piano write at the
/// cursor as Tabber Studio's do, Next moves on, Undo takes it back.
final class TabScreenUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch(["-demo", "-screen", "tab"]) }

    /// A point on the fretboard: a fret on a string (the board starts at fret 0).
    @MainActor
    func fret(_ fret: Int, string: Int) -> XCUICoordinate {
        let x = fret == 0 ? 19.0 : 38 + 6 + (Double(fret) - 0.5) * 58
        return element("fretboard").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: (Double(string) - 0.5) * 34))
    }

    /// TR36 and the owner's song of only audio files: the Tab screen adds a
    /// tab track, and writes on it at once.
    @MainActor
    func testASongOfOnlyAudioGetsATabTrackToWriteOn() {
        launch(["-demo", "-demo-only-audio", "-screen", "tab"])
        XCTAssertTrue(app.staticTexts["This song has no tab tracks yet. Add one to write on it here."]
            .waitForExistence(timeout: 8))
        tap("add-tab-track")
        XCTAssertTrue(appears("fretboard"), "the new track's tab, at once")
        XCTAssertTrue(app.navigationBars["Track 1"].waitForExistence(timeout: 8))
        fret(3, string: 2).tap()
        XCTAssertTrue(waitFor("bar-1", "string 2 fret 3"), "the fretboard writes on it")
    }

    /// TR39 and TR40: a MIDI track chosen while the computer shows Tab waits on
    /// Tabber Studio's "MIDI part" card; the phone answers it, so the computer
    /// is never left waiting, and then writes on the MIDI tab. Drums offer
    /// only standard notation.
    @MainActor
    func testTheMidiPartCardFromThePhone() {
        app.tabBars.buttons["Tracks"].tap()
        reveal("add-track")
        tap("add-track")
        let midi = app.buttons["MIDI track"]
        XCTAssertTrue(midi.waitForExistence(timeout: 8))
        midi.tap()
        XCTAssertTrue(waitSelected("track-MIDI Track 4"))
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(appears("midi-part"), "the computer's card, on the phone")
        XCTAssertTrue(appears("show-notation") && appears("show-midi-tab"))
        tap("show-midi-tab")
        XCTAssertTrue(appears("fretboard"), "the computer shows MIDI tab, and the phone writes on it")
        XCTAssertTrue(app.navigationBars["MIDI Track 4"].waitForExistence(timeout: 8))
        fret(3, string: 2).tap()
        XCTAssertTrue(waitFor("bar-1", "string 2 fret 3"), "a fret on the MIDI track's tab")
        app.tabBars.buttons["Tracks"].tap()
        tap("track-Drums")
        XCTAssertTrue(waitSelected("track-Drums"))
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(appears("show-notation"))
        XCTAssertTrue(gone("show-midi-tab"), "drums cannot show MIDI tab")
        tap("show-notation")
        XCTAssertTrue(waitFor("part-shows", "in standard notation"))
    }

    @MainActor
    func testAFretboardTapWritesAndASecondTakesItOff() {
        XCTAssertTrue(appears("bar-1"))
        XCTAssertTrue(waitFor("bar-1", "beat 1: string 6 fret 0, cursor"))
        fret(3, string: 2).tap()
        XCTAssertTrue(waitFor("bar-1", "beat 1: string 2 fret 3, string 6 fret 0"), "the note joins the beat")
        fret(3, string: 2).tap()
        XCTAssertTrue(waitFor("bar-1", "beat 1: string 6 fret 0, cursor"), "the same fret again takes it off")
    }

    @MainActor
    func testNextValuesAndUndo() {
        tap("next")
        XCTAssertTrue(waitFor("bar-1", "beat 2: string 4 fret 2, cursor"))
        tap("value-16")
        XCTAssertTrue(waitSelected("value-16"))
        XCTAssertTrue(waitFor("undo", "Undo Set duration"))
        tap("undo")
        XCTAssertTrue(waitFor("undo", "Undo") && !element("undo").label.contains("Set duration"))
    }

    @MainActor
    func testThePianoWritesThePitchOnItsLowestFret() {
        app.segmentedControls["input"].buttons["Piano"].tap()
        XCTAssertTrue(appears("piano"))
        // The piano opens at the guitar's low octave, a key before C2: G2 is the sixth key shown.
        element("piano").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 5.5 * 38, dy: 150)).tap()
        XCTAssertTrue(waitFor("bar-1", "beat 1: string 6 fret 3"), "G2 lands on the low E string, fret 3")
    }

    @MainActor
    func testAnAudioTrackOffersTheTabTracks() {
        app.tabBars.buttons["Tracks"].tap()
        tap("track-Vocals")
        XCTAssertTrue(waitSelected("track-Vocals"))
        app.tabBars.buttons["Tab"].tap()
        tap("write-Bass")
        XCTAssertTrue(appears("fretboard"))
        XCTAssertTrue(waitFor("bar-1", "string 4 fret 0"), "the bass's tab, on four strings")
    }

    /// The bar the cursor is in, from the staff's bars.
    @MainActor
    func cursorBar() -> Int? {
        let bars = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'bar-'"))
        for bar in bars.allElementsBoundByIndex where "\(bar.label) \(bar.value as? String ?? "")".contains("cursor") {
            return Int(bar.identifier.dropFirst(4))
        }
        return nil
    }

    @MainActor
    func testHoldingNextFastForwardsAndPreviousGoesBack() {
        XCTAssertTrue(waitFor("bar-1", "cursor"))
        element("next").press(forDuration: 3.0)
        let forward = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (self.cursorBar() ?? 0) >= 4 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [forward], timeout: 5), .completed, "a held Next goes on by itself, then bar by bar")
        element("previous").press(forDuration: 4.0)
        XCTAssertTrue(waitFor("bar-1", "beat 1: string 6 fret 0, cursor", timeout: 8), "a held Previous goes back to the start")
    }
}
