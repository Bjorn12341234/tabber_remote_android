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
        app.segmentedControls.buttons["Piano"].tap()
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
}
