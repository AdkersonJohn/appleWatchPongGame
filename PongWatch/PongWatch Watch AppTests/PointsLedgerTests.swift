import XCTest
@testable import PongWatch_Watch_App

final class PointsLedgerTests: XCTestCase {
    func test_balanceIsEarnedPlusPurchasedMinusRefundedMinusSpent() {
        var l = PointsLedger()
        l.earned = ["watch": 100, "phone": 40]
        l.purchasedByTx = ["t1": 500]
        l.refundedByTx = ["t1": 50]
        l.creditedTransactions = ["t1"]
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
        var a = PointsLedger(); a.earned = ["watch": 5]; a.purchasedByTx = ["t1": 9]
        a.creditedTransactions = ["t1"]; a.revokedTransactions = ["r1"]
        let tie = Date(timeIntervalSince1970: 10)
        a.owned = ["x": OwnedItem(costPaid: 40, boughtAt: tie)]
        var b = PointsLedger(); b.earned = ["watch": 8, "phone": 2]; b.refundedByTx = ["t2": 1]
        b.creditedTransactions = ["t2"]
        b.owned = ["x": OwnedItem(costPaid: 60, boughtAt: tie)]   // same instant, different cost
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

    // MARK: - Migration from the 1.1 keys

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ledger.\(UUID().uuidString)")!
    }

    /// Costs 40 + 300 + 100 + 400 = 840, and 1180 - 840 = 340: real 1.1 data is consistent.
    private static let legacyUnlocked = ["celebration.explosion", "celebration.rainbow", "title.rallyking", "title.crownholder"]

    func test_anExistingPlayerKeepsTheirBalanceAndItems() {
        let defaults = freshDefaults()
        defaults.set(340, forKey: "progress.availablePoints")
        defaults.set(1180, forKey: "progress.lifetimePoints")
        defaults.set(Self.legacyUnlocked, forKey: "progress.unlocked")
        let s = ProgressionStore(defaults: defaults)
        XCTAssertEqual(s.availablePoints, 340)
        XCTAssertEqual(s.lifetimePoints, 1180)
        XCTAssertTrue(s.isUnlocked(UnlockCatalog.item(id: "celebration.explosion")!))
    }

    func test_migrationRunsOnceAndDoesNotDoubleCountOnReopen() {
        let defaults = freshDefaults()
        defaults.set(340, forKey: "progress.availablePoints")
        defaults.set(1180, forKey: "progress.lifetimePoints")
        defaults.set(Self.legacyUnlocked, forKey: "progress.unlocked")
        ProgressionStore(defaults: defaults).award(10)
        let reopened = ProgressionStore(defaults: defaults)
        XCTAssertEqual(reopened.availablePoints, 350)
        XCTAssertEqual(reopened.lifetimePoints, 1190)
    }

    func test_aFreshInstallWithNoLegacyKeysStartsEmpty() {
        let s = ProgressionStore(defaults: freshDefaults())
        XCTAssertEqual(s.availablePoints, 0)
        XCTAssertEqual(s.lifetimePoints, 0)
    }

    func test_migrationKeepsTheBalanceThePlayerSawEvenWhenLifetimeDisagrees() {
        let item = UnlockCatalog.item(id: "celebration.explosion")!
        let defaults = freshDefaults()
        defaults.set(5, forKey: "progress.availablePoints")
        defaults.set(item.cost + 10, forKey: "progress.lifetimePoints")
        defaults.set([item.id], forKey: "progress.unlocked")
        let s = ProgressionStore(defaults: defaults)
        XCTAssertEqual(s.availablePoints, 5)
        XCTAssertEqual(s.lifetimePoints, item.cost + 5, "lifetime is restated to fit")
    }

    // MARK: - Durability

    func test_ledgerSurvivesAJSONRoundTrip() throws {
        var l = PointsLedger()
        l.earned = ["watch": 3]; l.purchasedByTx = ["t1": 500]; l.refundedByTx = ["t1": 1]
        l.owned = ["x": OwnedItem(costPaid: 40, boughtAt: Date(timeIntervalSince1970: 1_700_000_000))]
        l.creditedTransactions = ["t1", "t2"]; l.revokedTransactions = ["t1"]
        l.relocked = [Tombstone(itemID: "y", boughtAt: Date(timeIntervalSince1970: 1_600_000_000))]
        l.equipped = ["paddleSkin": EquippedChoice(itemID: "x", changedAt: Date(timeIntervalSince1970: 1_700_000_100))]
        let back = try JSONDecoder().decode(PointsLedger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
    }

    func test_decodingToleratesFieldsMissingFromOlderData() throws {
        let json = Data(#"{"earned":{"watch":5}}"#.utf8)
        let l = try JSONDecoder().decode(PointsLedger.self, from: json)
        XCTAssertEqual(l.earned, ["watch": 5])
        XCTAssertTrue(l.owned.isEmpty)
    }

    func test_anUnreadableLedgerIsKeptAsideRatherThanOverwritten() {
        let defaults = freshDefaults()
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: "progress.ledger")
        let s = ProgressionStore(defaults: defaults)
        s.award(5)
        XCTAssertEqual(defaults.data(forKey: "progress.ledger.unreadable"), junk)
    }
}
