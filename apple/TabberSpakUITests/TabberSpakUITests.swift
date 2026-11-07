import XCTest

/// TR5: the app reaches DemoHost and shows the confirmed session.
final class TabberSpakUITests: XCTestCase {
    /// A row by its identifier; SwiftUI joins a row's label and value in one element.
    @MainActor
    func row(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func waitFor(_ element: XCUIElement, toShow text: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else { return false }
            return "\(element.label) \(element.value as? String ?? "")".contains(text)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testTheComputerTabShowsTheConnection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        app.tabBars.buttons["Computer"].tap()
        XCTAssertTrue(waitFor(row(app, "host-name"), toShow: "Demo Studio"))
        XCTAssertTrue(waitFor(row(app, "link-state"), toShow: "Connected"))
    }
}
