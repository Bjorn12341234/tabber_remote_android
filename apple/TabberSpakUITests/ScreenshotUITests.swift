import XCTest

/// TR9: screenshots of every screen in demo mode, for review and the App
/// Store. Runs only when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR
/// to xcodebuild); the PNGs are written there.
final class ScreenshotUITests: SpakUITestCase {
    var directory: URL!

    @MainActor
    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SCREENSHOT_DIR to take screenshots")
        }
        directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        continueAfterFailure = false
    }

    @MainActor
    func shoot(_ name: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testEveryScreen() throws {
        app = XCUIApplication()
        app.launchArguments = ["-reset"]
        app.launch()
        XCTAssertTrue(element("get-started").waitForExistence(timeout: 8))
        try shoot("1-welcome")
        app.terminate()

        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(waitFor("connection", "Demo Studio"))
        try shoot("2-tracks")
        tap("arm-Vocals")
        tap("solo-Bass")
        tap("play")
        sleep(2)
        try shoot("3-tracks-armed-playing")
        tap("solo-Bass")
        tap("record")
        XCTAssertTrue(waitFor("readout", "Recording", timeout: 12))
        sleep(3)
        try shoot("4-recording")
        tap("record")
        XCTAssertTrue(element("take-card").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("5-take-card")
        tap("keep")
        sleep(1)
        try shoot("6-takes")
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(element("fretboard").waitForExistence(timeout: 8))
        tap("next")
        sleep(1)
        try shoot("7-tab-fretboard")
        app.segmentedControls["input"].buttons["Piano"].tap()
        sleep(1)
        try shoot("8-tab-piano")
        app.segmentedControls["input"].buttons["Fretboard"].tap()
        app.tabBars.buttons["Mixer"].tap()
        tap("play")
        sleep(2)
        try shoot("9-mixer")
        tap("play")
        app.segmentedControls["mixer-page"].buttons["Routing"].tap()
        XCTAssertTrue(element("route-Vocals").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("9b-routing")
        app.segmentedControls["mixer-page"].buttons["Mixer"].tap()
        app.tabBars.buttons["Chat"].tap()
        tap("unlock-chat")
        let field = element("chat-field")
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Mute the drums")
        tap("chat-send")
        XCTAssertTrue(element("chat-plan").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("9c-chat")
        tap("connection")
        XCTAssertTrue(element("done").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("10-computer")
    }

    /// The Computer sheet at the largest text, with a measured tap: the
    /// response time rows grow and wrap rather than clip.
    @MainActor
    func testTheComputerSheetAtTheLargestText() throws {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(waitFor("connection", "Demo Studio"))
        tap("play")
        tap("connection")
        for _ in 0..<8 where !element("response-again").isHittable { app.swipeUp() }
        try shoot("computer-largest-text")
    }
}
