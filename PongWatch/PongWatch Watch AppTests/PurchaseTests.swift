import XCTest
@testable import PongWatch_Watch_App

/// The crediting rules, against ProgressionStore directly. StoreKit itself
/// (the sheet, replayed transactions) can only be exercised on a device.
final class PurchaseTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "PurchaseTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeStore() -> ProgressionStore {
        ProgressionStore(defaults: defaults, cloud: NoCloudStore())
    }

    func test_aCreditedPurchaseAddsPointsWithoutTouchingTheEarnedTotal() {
        let s = makeStore()
        s.award(20)
        XCTAssertTrue(s.recordPurchase(points: 500, transactionID: "tx-1"))
        XCTAssertEqual(s.availablePoints, 520)
        XCTAssertEqual(s.lifetimePoints, 20, "buying is not earning")
    }

    /// StoreKit can surface one transaction from both Transaction.updates and
    /// Transaction.unfinished.
    func test_theSameTransactionIdIsNeverCreditedTwice() {
        let s = makeStore()
        XCTAssertTrue(s.recordPurchase(points: 100, transactionID: "tx-7"))
        XCTAssertFalse(s.recordPurchase(points: 100, transactionID: "tx-7"))
        XCTAssertEqual(s.availablePoints, 100)
    }

    /// Killed before finish(): StoreKit replays the transaction next launch.
    func test_aTransactionCreditedOnOneLaunchIsNotRecreditedOnTheNext() {
        XCTAssertTrue(makeStore().recordPurchase(points: 50, transactionID: "tx-9"))
        let relaunched = makeStore()
        XCTAssertFalse(relaunched.recordPurchase(points: 50, transactionID: "tx-9"))
        XCTAssertEqual(relaunched.availablePoints, 50)
    }

    func test_everyPackIsAWholeNumberOfPointsAndTheyAscend() {
        XCTAssertEqual(PointPack.all.map(\.points), [10, 50, 100, 500])
        XCTAssertEqual(PointPack.all.map(\.points), PointPack.all.map(\.points).sorted())
        XCTAssertEqual(Set(PointPack.all.map(\.id)).count, 4)
    }

    func test_customBuysTheTenPointPack() {
        XCTAssertEqual(PointPack.custom.points, 10)
        XCTAssertEqual(PointPack.custom, PointPack.all.first)
    }

    /// A typo here only fails at runtime, as "no products".
    func test_productIdsAreExactlyTheOnesRegisteredInAppStoreConnect() {
        XCTAssertEqual(PointPack.all.map(\.id), [
            "com.johnadkerson.PongWatch.points10",
            "com.johnadkerson.PongWatch.points50",
            "com.johnadkerson.PongWatch.points100",
            "com.johnadkerson.PongWatch.points500",
        ])
    }

    func test_eachPackIsWorthItsOwnPointsForOneUnit() {
        for pack in PointPack.all {
            XCTAssertEqual(PointPack.pointsToCredit(productID: pack.id, quantity: 1, isRevoked: false), pack.points)
        }
    }

    func test_aQuantityPurchaseMultipliesThePackPoints() {
        XCTAssertEqual(PointPack.pointsToCredit(productID: PointPack.custom.id, quantity: 7, isRevoked: false), 70)
    }

    func test_aRevokedTransactionCreditsNothing() {
        XCTAssertNil(PointPack.pointsToCredit(productID: PointPack.all[3].id, quantity: 1, isRevoked: true))
    }

    func test_anUnknownProductCreditsNothing() {
        XCTAssertNil(PointPack.pointsToCredit(productID: "com.example.other", quantity: 1, isRevoked: false))
    }

    func test_aNonPositiveQuantityCreditsNothing() {
        XCTAssertNil(PointPack.pointsToCredit(productID: PointPack.custom.id, quantity: 0, isRevoked: false))
    }
}
