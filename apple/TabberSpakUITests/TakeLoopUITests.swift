import XCTest

/// After a take, against DemoHost: keep it, delete it with one tap and undo,
/// go again (the newer take plays, the earlier one waits in its lane), and
/// delete from the takes list.
final class TakeLoopUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws { launch() }

    @MainActor
    func testDeleteIsOneTapAndUndoBringsItBack() {
        recordOneTake()
        tap("delete")
        XCTAssertTrue(appears("undo-banner"))
        XCTAssertTrue(gone("take-Vocals take 1"), "the deleted take leaves the list")
        tap("undo-delete")
        XCTAssertTrue(appears("take-Vocals take 1"), "Undo brings the take back")
    }

    @MainActor
    func testKeepAndGoAgain() {
        recordOneTake()
        tap("keep")
        XCTAssertTrue(gone("take-card"))
        recordOneTake()
        tap("card-go-again")
        XCTAssertTrue(waitFor("readout", "Recording", timeout: 12))
        tap("record")
        XCTAssertTrue(appears("take-card"))
        XCTAssertTrue(waitFor("take-detail", "from bar 25"))
    }

    @MainActor
    func testGoingAgainShowsWhichTakePlays() {
        recordOneTake()
        tap("card-go-again")
        XCTAssertTrue(waitFor("readout", "Recording", timeout: 12))
        sleep(2)                                // longer than the first take, so it covers it
        tap("record")
        XCTAssertTrue(appears("take-card"))
        tap("keep")
        XCTAssertTrue(gone("take-card"))
        XCTAssertTrue(waitFor("take-info-Vocals take 1", "not playing"), "the earlier take waits in its lane")
        XCTAssertFalse(element("take-info-Vocals take 2").label.contains("not playing"), "the newest plays")
    }

    @MainActor
    func testDeleteFromTheTakesList() {
        recordOneTake()
        tap("keep")
        XCTAssertTrue(gone("take-card"), "the card has left before the list is tapped")
        sleep(1)                                // the list settles where the card was
        tap("delete-Vocals take 1")
        XCTAssertTrue(appears("undo-banner"))
        XCTAssertTrue(gone("take-Vocals take 1"))
    }
}
