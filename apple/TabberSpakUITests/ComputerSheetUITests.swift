import XCTest

/// TR7's gate on a device: the Computer sheet shows how long the computer
/// took to answer this phone's taps, and starts again for a second run.
final class ComputerSheetUITests: SpakUITestCase {
    @MainActor
    func testTheSheetMeasuresHowLongTheComputerTakesToAnswer() throws {
        launch()
        tap("connection")
        reveal("response-again")
        XCTAssertTrue(waitFor("response-typical", "Not yet"), "nothing tapped yet")
        XCTAssertTrue(waitFor("response-note", "Tap a control, like Play"))
        XCTAssertFalse(element("response-again").isEnabled, "nothing to start again")
        tap("done")
        tap("play")
        tap("connection")
        reveal("response-again")
        XCTAssertTrue(waitFor("response-typical", " ms"), "the tap on Play was timed")
        XCTAssertTrue(waitFor("response-p95", " ms"))
        XCTAssertTrue(waitFor("response-note", "over 1 tap"))
        tap("response-again")
        XCTAssertTrue(waitFor("response-typical", "Not yet"), "Start again forgets the times")
    }

    /// At the largest text the rows grow and wrap rather than clip (default
    /// size: Start again 52 points tall, the note two lines in 46).
    @MainActor
    func testTheResponseRowsGrowWithTheText() throws {
        launch(["-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap("play")
        tap("connection")
        reveal("response-again")
        XCTAssertTrue(waitFor("response-typical", " ms"))
        XCTAssertGreaterThan(element("response-again").frame.height, 70, "Start again grows")
        XCTAssertGreaterThan(element("response-note").frame.height, 120, "the note wraps over more lines")
    }
}
