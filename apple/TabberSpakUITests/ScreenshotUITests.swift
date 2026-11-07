import XCTest

/// TR9: screenshots of every screen in demo mode, for review and the App
/// Store. Runs only when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR
/// to xcodebuild); the PNGs are written there.
final class ScreenshotUITests: XCTestCase {
    var app: XCUIApplication!
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
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func shoot(_ name: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func waitFor(_ id: String, _ text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else { return false }
            return "\(element.label) \(element.value as? String ?? "")".contains(text)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element(id))],
                                timeout: timeout) == .completed
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
        element("arm-Vocals").tap()
        element("solo-Bass").tap()
        element("play").tap()
        sleep(2)
        try shoot("3-tracks-armed-playing")
        element("solo-Bass").tap()
        element("record").tap()
        XCTAssertTrue(waitFor("readout", "Recording", timeout: 12))
        sleep(3)
        try shoot("4-recording")
        element("record").tap()
        XCTAssertTrue(element("take-card").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("5-take-card")
        element("keep").tap()
        sleep(1)
        try shoot("6-takes")
        app.tabBars.buttons["Tab"].tap()
        XCTAssertTrue(element("fretboard").waitForExistence(timeout: 8))
        element("next").tap()
        sleep(1)
        try shoot("7-tab-fretboard")
        app.segmentedControls.buttons["Piano"].tap()
        sleep(1)
        try shoot("8-tab-piano")
        app.segmentedControls.buttons["Fretboard"].tap()
        app.tabBars.buttons["Mixer"].tap()
        element("play").tap()
        sleep(2)
        try shoot("9-mixer")
        element("play").tap()
        element("connection").tap()
        XCTAssertTrue(element("done").waitForExistence(timeout: 8))
        sleep(1)
        try shoot("10-computer")
    }
}
