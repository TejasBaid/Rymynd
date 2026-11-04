import XCTest

final class SwipeToDeleteTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-seedDemo"]
        app.launch()
    }

    /// The row itself: its combined label carries the title and the time (the undo toast only carries the title).
    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", title, ":")).firstMatch
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A short swipe leaves the row open on Delete; tapping the row closes it again.
    func testPartialSwipeRevealsDelete() {
        let plants = row("Water the plants")
        XCTAssertTrue(plants.waitForExistence(timeout: 8))
        let start = plants.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.05)
        sleep(1)
        snapshot("open")
        XCTAssertTrue(plants.exists, "A short swipe should not delete")
        plants.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        sleep(1)
        snapshot("closed")
    }

    /// A long swipe deletes in one motion.
    func testFullSwipeDeletes() {
        let plants = row("Water the plants")
        XCTAssertTrue(plants.waitForExistence(timeout: 8))
        let start = plants.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -330, dy: 0)), withVelocity: .default, thenHoldForDuration: 0)
        sleep(1)
        snapshot("deleted")
        XCTAssertFalse(row("Water the plants").exists, "A full swipe should delete the row")
    }

    /// Vertical drags that start on a row still scroll the list.
    func testVerticalDragStillScrolls() {
        let plants = row("Water the plants")
        XCTAssertTrue(plants.waitForExistence(timeout: 8))
        let before = plants.frame.minY
        let start = plants.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: -12, dy: -260)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        snapshot("scrolled")
        XCTAssertLessThan(plants.frame.minY, before - 100, "The list should have scrolled")
    }
}
