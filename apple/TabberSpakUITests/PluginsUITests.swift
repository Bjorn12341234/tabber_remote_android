import XCTest

/// Plug-ins on the Mixer's strips against DemoHost (TR44). The owner: "should
/// you be able to insert plugins on tracks from the app?", then "yes". Each
/// strip's INSERTS, as Tabber Studio's strip lists them; its "＋ Plugin" opens
/// Studio's Insert Plugin browser, with its tabs, format filter and search;
/// a plug-in goes in at the end of the chain, and its menu bypasses and
/// removes it; an instrument becomes a MIDI track's sound source.
final class PluginsUITests: SpakUITestCase {
    @MainActor
    override func setUp() async throws {
        launch(["-demo", "-screen", "mixer"])
    }

    @MainActor
    func testAnEffectIsInsertedBypassedAndRemoved() {
        XCTAssertTrue(waitFor("insert-Guitar-Tabber Amp", "Tabber Amp on Guitar, on"), "the guitar plays through Tabber Amp")
        tap("add-plugin-Bass")
        XCTAssertTrue(app.navigationBars["Insert Plugin"].waitForExistence(timeout: 8))
        tap("plugin-Tabber Compressor")
        XCTAssertTrue(waitFor("insert-Bass-Tabber Compressor", "Tabber Compressor on Bass, on"), "it goes in")
        XCTAssertFalse(app.navigationBars["Insert Plugin"].exists, "the browser closes once it is in")
        tap("insert-Bass-Tabber Compressor")
        app.buttons["Bypass"].tap()
        XCTAssertTrue(waitFor("insert-Bass-Tabber Compressor", "bypassed"), "the hollow dot")
        tap("insert-Bass-Tabber Compressor")
        app.buttons["Remove"].tap()
        XCTAssertTrue(gone("insert-Bass-Tabber Compressor"), "and it is gone")
    }

    @MainActor
    func testTheBrowsersTabsFormatsAndSearch() {
        tap("add-plugin-Guitar")
        XCTAssertTrue(appears("plugin-Tabber Amp"), "Tabber Plugins first, as in Tabber Studio")
        XCTAssertFalse(element("plugin-Plate Reverb").exists)
        app.segmentedControls["plugin-source"].buttons["Plugins"].tap()
        XCTAssertTrue(appears("plugin-Plate Reverb"))
        XCTAssertTrue(appears("plugin-Tape Echo"))
        app.segmentedControls["plugin-format"].buttons["CLAP"].tap()
        XCTAssertTrue(gone("plugin-Plate Reverb"), "the format filter")
        XCTAssertTrue(element("plugin-Tape Echo").exists)
        app.segmentedControls["plugin-format"].buttons["All"].tap()
        app.segmentedControls["plugin-source"].buttons["Tabber Plugins"].tap()
        let field = app.searchFields["Search plugins"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("lim")
        XCTAssertTrue(appears("plugin-Tabber Limiter"), "the search")
        XCTAssertTrue(gone("plugin-Tabber Amp"))
    }

    @MainActor
    func testAnInstrumentBecomesAMidiTracksSoundSource() {
        tap("add-plugin-Guitar")
        tap("plugin-Tabber Synth")
        XCTAssertTrue(waitFor("plugin-notice", "Tabber Synth is now the sound source of Guitar."))
        XCTAssertFalse(element("insert-Guitar-Tabber Synth").exists, "an instrument is no insert")
    }
}
