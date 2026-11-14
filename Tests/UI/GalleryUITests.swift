import XCTest

final class GalleryUITests: XCTestCase {
    @MainActor
    func testSwipeBackAndCancelSmallDrag() {
        let app = launch()
        let title = app.staticTexts["artwork-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Первая картина")
        let surface = app.buttons["open-artwork"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -35, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(title.label, "Первая картина")
        surface.swipeLeft()
        expectTitle("Вторая картина", in: app)
        surface.swipeRight()
        expectTitle("Первая картина", in: app)
    }

    @MainActor
    func testViewerAndFavoriteDetail() {
        let app = launch()
        let image = app.buttons["open-artwork"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        image.tap()
        let close = app.buttons["close-artwork"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        app.buttons["toggle-favorite"].firstMatch.tap()
        app.buttons["favorites"].tap()
        let row = app.staticTexts["Первая картина"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        expectTitle("Первая картина", in: app)
    }

    @MainActor
    func testAccessibilityTextSizeAndNavigationButtons() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        expectTitle("Первая картина", in: app)
        app.buttons["next-artwork"].tap()
        expectTitle("Вторая картина", in: app)
        app.buttons["previous-artwork"].tap()
        expectTitle("Первая картина", in: app)
    }

    @MainActor private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extraArguments
        app.launch()
        return app
    }

    @MainActor private func expectTitle(_ value: String, in app: XCUIApplication) {
        let title = app.staticTexts.containing(NSPredicate(format: "identifier == %@ AND label == %@", "artwork-title", value)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 6))
    }
}
