import XCTest
@testable import PongWatch_Watch_App

final class HighScoreStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HighScoreStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_defaultHighScoreIsZero() {
        let store = HighScoreStore(defaults: defaults)
        XCTAssertEqual(store.current, 0)
    }

    func test_updateStoresHigherScore() {
        let store = HighScoreStore(defaults: defaults)
        let isNew = store.updateIfHigher(newScore: 10)
        XCTAssertTrue(isNew)
        XCTAssertEqual(store.current, 10)
    }

    func test_updateIgnoresLowerScore() {
        let store = HighScoreStore(defaults: defaults)
        _ = store.updateIfHigher(newScore: 10)
        let isNew = store.updateIfHigher(newScore: 5)
        XCTAssertFalse(isNew)
        XCTAssertEqual(store.current, 10)
    }

    func test_scorePersistsAcrossInstances() {
        let store1 = HighScoreStore(defaults: defaults)
        _ = store1.updateIfHigher(newScore: 42)

        let store2 = HighScoreStore(defaults: defaults)
        XCTAssertEqual(store2.current, 42)
    }
}
