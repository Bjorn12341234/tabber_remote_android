import XCTest

/// TR6: a fresh install, finding the computer, the scanner's paste fallback
/// (the Simulator has no camera), and the fix-it cards.
final class WelcomeUITests: XCTestCase {
    var app: XCUIApplication!

    /// A computer nobody answers for: port 1 on this machine.
    static let nowhere = #"{"id":"h-nowhere","name":"Nowhere Mac","pin":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","routes":[{"host":"127.0.0.1","port":1}]}"#
    static let nowhereLink = "tabber-remote://pair?v=1&id=h-nowhere&name=Nowhere%20Mac&spki=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&tok=AAAAAAAAAAAAAAAAAAAAAA&hosts=127.0.0.1:1"

    @MainActor
    func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    @MainActor
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func tap(_ id: String, timeout: TimeInterval = 8) {
        let target = element(id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: timeout), .completed, "\(id) never became tappable")
        target.tap()
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
    func testAFreshInstallWelcomesAndOffersTheDemo() {
        launch(["-reset"])
        XCTAssertTrue(element("get-started").waitForExistence(timeout: 8))
        tap("demo")
        XCTAssertTrue(waitFor("connection", "Demo Studio"))
        XCTAssertTrue(app.tabBars.buttons["Session"].exists)
    }

    @MainActor
    func testGetStartedExplainsThenScansAndSaysWhyPairingFailed() {
        launch(["-reset"])
        tap("get-started")
        tap("continue")                       // the explainer before iOS asks for the local network
        tap("scan")
        let field = element("pair-link-field")
        XCTAssertTrue(field.waitForExistence(timeout: 8), "no camera here, so the link can be pasted")
        field.tap()
        field.typeText("https://example.com")
        tap("pair-link-button")
        XCTAssertTrue(element("not-a-code").waitForExistence(timeout: 4))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
        field.typeText(Self.nowhereLink)
        tap("pair-link-button")
        let alert = app.alerts["Pairing did not work"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Can't reach Nowhere Mac")).firstMatch.exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(element("scan").waitForExistence(timeout: 4), "still on Find Your Computer, not paired")
    }

    @MainActor
    func testAnUnreachableComputerSaysWhatToCheck() {
        launch(["-reset", "-known-host", Self.nowhere])
        XCTAssertTrue(waitFor("fix-it-title", "Can't reach Nowhere Mac", timeout: 15))
        XCTAssertTrue(element("fix-it-retry").exists)
        tap("fix-it-pair")
        XCTAssertTrue(element("pair-link-field").waitForExistence(timeout: 8), "Pair Again opens the scanner")
    }

    @MainActor
    func testAnOlderTabberStudioIsNamed() {
        launch(["-reset", "-demo-speaks", "0.9"])
        XCTAssertTrue(waitFor("fix-it-title", "Update Tabber Studio", timeout: 10))
        tap("fix-it-retry")
        XCTAssertTrue(waitFor("fix-it-title", "Update Tabber Studio", timeout: 10))
    }

    @MainActor
    func testANewerTabberStudioAsksToUpdateThePhone() {
        launch(["-reset", "-demo-speaks", "2.0"])
        XCTAssertTrue(waitFor("fix-it-title", "Update Tabber Spak", timeout: 10))
    }
}
