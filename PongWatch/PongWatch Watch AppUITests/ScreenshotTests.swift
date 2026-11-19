import XCTest

/// The simulator screenshot harness. Captures deep screens headlessly, with no
/// Simulator.app and no tapping — this machine has neither a Simulator GUI nor
/// any tap API for a real watch.
///
/// **Do not delete.** See CLAUDE.md, "Simulator screenshot harness", for how to
/// run it and where the PNGs land.
///
/// Products come from `Points.storekit`, attached to this scheme's Test action,
/// so the packs render with prices exactly as they do in the shipped app.
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func test_captureGetPoints() {
        capture(screen: "getPoints", points: 17, named: "get-points")
    }

    func test_captureUnlocks() {
        capture(screen: "unlocks", points: 17, named: "unlocks")
    }

    private func capture(screen: String, points: Int, named name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", screen, "-points", String(points)]
        app.launch()

        // The packs arrive from StoreKit asynchronously; a fixed sleep would
        // either flake or waste time, so wait for a price to actually appear.
        let priced = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "$")
        ).firstMatch
        if screen == "getPoints" {
            XCTAssertTrue(priced.waitForExistence(timeout: 30),
                          "No price rendered — StoreKit products did not load")
        } else {
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 30)
        }

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
