#if ART_GALLERY_TEST_TARGET
import XCTest

final class GalleryUITests: XCTestCase {
    @MainActor
    func testSwipeBackAndCancelSmallDrag() {
        let app = launch()
        XCUIDevice.shared.orientation = .portrait
        let title = app.staticTexts["artwork-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Первая картина")
        let firstCount = app.staticTexts["Картина 1"]
        let secondCount = app.staticTexts["Картина 2"]
        XCTAssertTrue(firstCount.exists)
        let surface = app.buttons["open-artwork"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -35, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(title.label, "Первая картина")
        XCTAssertTrue(firstCount.exists)
        surface.swipeLeft()
        expectTitle("Вторая картина", in: app)
        XCTAssertTrue(secondCount.waitForExistence(timeout: 6))
        surface.swipeRight()
        expectTitle("Первая картина", in: app)
        XCTAssertTrue(firstCount.waitForExistence(timeout: 6))
    }

    @MainActor
    func testLandscapeSwipeAlignsNextCardToSamePosition() {
        let app = launch()
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft
        defer { device.orientation = .portrait }

        expectTitle("Первая картина", in: app)
        let title = app.staticTexts["artwork-title"].firstMatch
        let image = app.buttons["open-artwork"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertLessThan(image.frame.midX, title.frame.minX)
        let firstTitleX = title.frame.minX
        let firstTitleHeight = title.frame.height

        image.swipeLeft()
        expectTitle("Вторая картина", in: app)
        XCTAssertTrue(app.staticTexts["Картина 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.minX, firstTitleX, accuracy: 1)

        app.buttons["next-artwork"].tap()
        expectTitle("Длинное название картины с подробным описанием пейзажа и вечернего света", in: app)
        XCTAssertGreaterThan(title.frame.height, firstTitleHeight)
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
        let row = app.descendants(matching: .any).matching(identifier: "favorite-row-cleveland:0").firstMatch
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

    @MainActor
    func testLiveClevelandDownloadsArtworksThroughPageThree() throws {
        // Run explicitly against the real museum API.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_CLEVELAND_TEST"] == "1")
        let app = XCUIApplication()
        app.launchArguments = ["--live-cleveland-test"]
        app.launch()
        expectTitle("Nathaniel Hurd", in: app)
        let next = app.buttons["next-artwork"]
        for position in 2...42 {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
            guard XCTWaiter.wait(for: [ready], timeout: 25) == .completed else {
                XCTFail("Cleveland did not load enough artworks")
                return
            }
            next.tap()
            if let id = [34: 136510, 40: 149665, 41: 122338, 42: 171296][position] {
                let image = app.buttons.containing(NSPredicate(
                    format: "identifier == %@ AND value == %@", "open-artwork", "cleveland:\(id)"
                )).firstMatch
                XCTAssertTrue(image.waitForExistence(timeout: 25), "JPEG missing at artwork \(position)")
            }
        }
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
#endif
