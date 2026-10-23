import XCTest

/// Drives the real panel: open, search, navigate, run, and audit accessibility.
/// The app is launched with `--open` so tests don't depend on the global hotkey.
@MainActor
final class GlinkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip onboarding via the NSArgumentDomain and open the panel at launch.
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-animationLevel", "off", "--ephemeral", "--open"]
        app.launch()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private var searchField: XCUIElement { app.textFields["searchField"] }

    /// `typeText` on this Xcode attaches ⌘ to synthesized keys (⌘Space then goes to Spotlight),
    /// so type one key at a time with explicitly empty modifiers.
    private func type(_ text: String) {
        for ch in text { searchField.typeKey(String(ch), modifierFlags: []) }
    }

    private func element(_ label: String) -> XCUIElement {
        // Buttons expose their text as the label; static text exposes it as the value.
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", label, label)).firstMatch
    }

    func testPanelOpensWithSuggestions() {
        XCTAssertTrue(element("Clipboard History").waitForExistence(timeout: 3))
    }

    func testCalculatorAnswersInline() {
        type("10 km to mi")
        XCTAssertTrue(element("10 km → mi equals 6.2137 mi").waitForExistence(timeout: 3))
    }

    func testAppSearchFindsFinder() {
        type("finder")
        XCTAssertTrue(app.descendants(matching: .any)["result.app:/System/Library/CoreServices/Finder.app"].waitForExistence(timeout: 3))
    }

    func testNoResultsOffersFallbacks() {
        type("qzxvwq")
        XCTAssertTrue(element("Search the web for “qzxvwq”").waitForExistence(timeout: 3))
    }

    func testEscapeClearsThenCloses() {
        type("safari")
        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(searchField.value as? String ?? "", "")
        searchField.typeKey(.escape, modifierFlags: [])
        let gone = NSPredicate(format: "isHittable == false")
        expectation(for: gone, evaluatedWith: searchField)
        waitForExpectations(timeout: 2)
    }

    func testArrowKeysMoveSelection() {
        type("window")
        let first = element("Left Half")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let selectedBefore = app.descendants(matching: .any).matching(NSPredicate(format: "selected == true")).firstMatch.label
        searchField.typeKey(.downArrow, modifierFlags: [])
        let selectedAfter = app.descendants(matching: .any).matching(NSPredicate(format: "selected == true")).firstMatch.label
        XCTAssertNotEqual(selectedBefore, selectedAfter)
    }

    func testClipboardHistoryOpensAndGoesBack() {
        type("clipboard history")
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 2))
        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("Clipboard History").waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Back"].exists)
    }

    func testScriptCommandShowsOutput() throws {
        let scripts = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Glink/Scripts/disk-usage.sh")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: scripts.path), "Example scripts not installed")
        type("disk usage")
        XCTAssertTrue(element("Disk Usage").waitForExistence(timeout: 3))
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("Finished").waitForExistence(timeout: 10))
    }

    func testFloatingNotesOpens() {
        type("floating notes")
        XCTAssertTrue(element("Floating Notes").waitForExistence(timeout: 3))
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.textViews["Note text"].waitForExistence(timeout: 3))
    }

    func testActionsPanelOpensWithCommandK() {
        type("finder")
        XCTAssertTrue(element("Finder").waitForExistence(timeout: 3))
        searchField.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("Show in Finder").waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(element("Show in Finder").waitForExistence(timeout: 1))
    }

    /// Audits what Glink draws: issues on elements inside the panel fail the test. AppKit's own pieces
    /// (the automatic text-field Touch Bar, input-method windows that aren't listed as the app's
    /// accessibility children) live outside it and are skipped.
    private func auditPanel(_ state: String) throws {
        let panelFrame = app.dialogs["Glink"].frame
        XCTAssertFalse(panelFrame.isEmpty, "panel missing in \(state)")
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .parentChild }
            let inPanel = panelFrame.intersects(element.frame)
            if inPanel { print("AUDIT-ISSUE [\(state)]: \(issue.compactDescription) | \(element.debugDescription.prefix(300))") }
            return !inPanel
        }
    }

    func testAccessibilityAudit() throws {
        // Contrast on a translucent panel depends on whatever is behind the window, which makes the
        // audit flaky. Audit Glink's own colors on the Solid style instead.
        app.terminate()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-animationLevel", "off", "-windowStyle", "solid", "--ephemeral", "--open"]
        app.launch()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        try auditPanel("root")

        type("finder")
        XCTAssertTrue(element("Finder").waitForExistence(timeout: 3))
        searchField.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element("Show in Finder").waitForExistence(timeout: 2))
        try auditPanel("actions")
        app.typeKey(.escape, modifierFlags: [])
        searchField.typeKey(.escape, modifierFlags: [])

        type("mcp config check")
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3))
        sleep(1)   // let the scan finish
        try auditPanel("mcp")
        searchField.typeKey(.escape, modifierFlags: [])   // back to root; the previous query is restored
        searchField.typeKey(.escape, modifierFlags: [])   // clear it
        XCTAssertEqual(searchField.value as? String ?? "", "")

        type("clipboard history")
        searchField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3))
        try auditPanel("clipboard")
    }
}
