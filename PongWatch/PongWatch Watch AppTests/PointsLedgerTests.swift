import XCTest
@testable import PongWatch_Watch_App

final class PointsLedgerTests: XCTestCase {
    func test_balanceIsEarnedPlusPurchasedMinusRefundedMinusSpent() {
        var l = PointsLedger()
        l.earned = ["watch": 100, "phone": 40]
        l.purchased = ["phone": 500]
        l.refunded = ["phone": 50]
        l.owned = ["a": OwnedItem(costPaid: 90, boughtAt: .distantPast)]
        XCTAssertEqual(l.balance, 500)
        XCTAssertEqual(l.lifetimeEarned, 140, "purchased points are not earned")
    }

    func test_mergeTakesTheHigherCountPerDeviceAndUnionsOwnedItems() {
        var a = PointsLedger(); a.earned = ["watch": 77, "phone": 340]
        a.owned = ["x": OwnedItem(costPaid: 40, boughtAt: Date(timeIntervalSince1970: 10))]
        var b = PointsLedger(); b.earned = ["watch": 90]
        b.owned = ["y": OwnedItem(costPaid: 60, boughtAt: Date(timeIntervalSince1970: 20))]
        let m = PointsLedger.merge(a, b)
        XCTAssertEqual(m.earned, ["watch": 90, "phone": 340])
        XCTAssertEqual(Set(m.owned.keys), ["x", "y"])
    }

    func test_mergeKeepsTheEarlierPurchaseTimeForTheSameItem() {
        var a = PointsLedger()
        a.owned = ["x": OwnedItem(costPaid: 40, boughtAt: .distantPast)]
        var b = PointsLedger()
        b.owned = ["x": OwnedItem(costPaid: 40, boughtAt: Date(timeIntervalSince1970: 500))]
        XCTAssertEqual(PointsLedger.merge(a, b).owned["x"]?.boughtAt, .distantPast)
        XCTAssertEqual(PointsLedger.merge(b, a).owned["x"]?.boughtAt, .distantPast)
    }

    func test_mergeIsOrderIndependent() {
        var a = PointsLedger(); a.earned = ["watch": 5]; a.purchased = ["phone": 9]
        a.creditedTransactions = ["t1"]; a.revokedTransactions = ["r1"]
        var b = PointsLedger(); b.earned = ["watch": 8, "phone": 2]; b.refunded = ["phone": 1]
        b.creditedTransactions = ["t2"]
        XCTAssertEqual(PointsLedger.merge(a, b), PointsLedger.merge(b, a))
    }

    func test_mergeUnionsBothTransactionSetsSeparately() {
        var a = PointsLedger(); a.creditedTransactions = ["t1"]
        var b = PointsLedger(); b.revokedTransactions = ["t1"]
        let m = PointsLedger.merge(a, b)
        XCTAssertEqual(m.creditedTransactions, ["t1"])
        XCTAssertEqual(m.revokedTransactions, ["t1"])
    }

    func test_recordPurchaseCreditsOnceAndIgnoresARepeatedTransaction() {
        let defaults = UserDefaults(suiteName: "ledger.\(UUID().uuidString)")!
        let store = ProgressionStore(defaults: defaults)
        XCTAssertTrue(store.recordPurchase(points: 500, transactionID: "t1"))
        XCTAssertFalse(store.recordPurchase(points: 500, transactionID: "t1"))
        XCTAssertEqual(store.availablePoints, 500)
        XCTAssertEqual(store.lifetimePoints, 0, "purchased points are not earned")
    }
}
