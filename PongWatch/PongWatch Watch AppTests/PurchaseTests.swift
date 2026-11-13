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

    // MARK: - Refunds

    private func item(_ id: String) -> Unlockable { UnlockCatalog.item(id: id)! }

    func test_aRefundRemovesUnspentPointsAndLeavesItemsAlone() {
        let s = makeStore()
        s.recordPurchase(points: 500, transactionID: "tx-1")
        XCTAssertEqual(s.revoke(points: 500, transactionID: "tx-1"), [])
        XCTAssertEqual(s.availablePoints, 0)
    }

    func test_aRefundRelocksTheNewestItemsUntilTheBalanceIsWholeAgain() {
        let s = makeStore()
        s.award(60)
        s.recordPurchase(points: 500, transactionID: "tx-1")
        XCTAssertTrue(s.buy(item("celebration.explosion")))   // 40
        XCTAssertTrue(s.buy(item("celebration.rainbow")))     // 300
        XCTAssertEqual(s.availablePoints, 220)

        let relocked = s.revoke(points: 500, transactionID: "tx-1")

        XCTAssertEqual(relocked.map(\.id), ["celebration.rainbow"])
        XCTAssertFalse(s.isUnlocked(item("celebration.rainbow")))
        XCTAssertTrue(s.isUnlocked(item("celebration.explosion")))
        XCTAssertEqual(s.availablePoints, 20, "60 earned + 500 bought - 500 refunded - 40 still spent")
    }

    /// Review Focus 5
    func test_aRefundNeverRelocksAFreeItemAndNeverLeavesTheBalanceNegative() {
        let s = makeStore()
        s.award(20)
        s.recordPurchase(points: 100, transactionID: "tx-1")
        XCTAssertTrue(s.buy(item("celebration.explosion")))
        XCTAssertTrue(s.buy(item("paddle.sky")))

        let relocked = s.revoke(points: 100_000, transactionID: "tx-1")

        XCTAssertEqual(Set(relocked.map(\.id)), ["celebration.explosion", "paddle.sky"])
        XCTAssertGreaterThanOrEqual(s.availablePoints, 0)
        XCTAssertTrue(relocked.allSatisfy { $0.cost > 0 })
        for category in UnlockCategory.allCases where category != .ability {
            XCTAssertNotNil(s.equippedItem(in: category), "\(category) must keep something equipped")
        }
        XCTAssertTrue(s.isUnlocked(item("celebration.sparks")))
    }

    func test_anItemRelockedWhileEquippedFallsBackToTheCategorysFreeItem() {
        let s = makeStore()
        s.recordPurchase(points: 40, transactionID: "tx-1")
        let explosion = item("celebration.explosion")
        XCTAssertTrue(s.buy(explosion))
        s.equip(explosion)
        XCTAssertEqual(s.equippedItem(in: .celebration)?.id, explosion.id)

        s.revoke(points: 40, transactionID: "tx-1")

        XCTAssertEqual(s.equippedItem(in: .celebration)?.cost, 0)
    }

    func test_theSameRefundIsNeverAppliedTwice() {
        let s = makeStore()
        s.award(100)
        s.recordPurchase(points: 50, transactionID: "tx-1")
        s.revoke(points: 50, transactionID: "tx-1")
        XCTAssertEqual(s.revoke(points: 50, transactionID: "tx-1"), [])
        XCTAssertEqual(s.availablePoints, 100)
        XCTAssertEqual(makeStore().availablePoints, 100, "and it was saved")
    }

    func test_aRefundDoesNotChangeTheEarnedTotal() {
        let s = makeStore()
        s.award(30)
        s.recordPurchase(points: 50, transactionID: "tx-1")
        s.revoke(points: 50, transactionID: "tx-1")
        XCTAssertEqual(s.lifetimePoints, 30)
    }

    /// A revocation carries the purchase's own id, so it must not be mistaken for a replay.
    func test_aRefundIsNotBlockedByTheCreditOfTheSameTransaction() {
        let s = makeStore()
        s.recordPurchase(points: 50, transactionID: "tx-1")
        s.revoke(points: 50, transactionID: "tx-1")
        XCTAssertEqual(s.availablePoints, 0)
    }

    func test_aRefundIsPushedToTheCloudLikeAnyOtherChange() {
        let cloud = RecordingCloud()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.recordPurchase(points: 50, transactionID: "tx-1")
        let before = cloud.saved.count
        s.revoke(points: 50, transactionID: "tx-1")
        XCTAssertEqual(cloud.saved.count, before + 1)
        XCTAssertEqual(cloud.saved.last?.balance, 0)
    }

    // MARK: - Re-locks survive sync

    private func ledger(owning id: String, boughtAt: Date, cost: Int = 40) -> PointsLedger {
        var l = PointsLedger()
        l.earned["watch"] = 1000
        l.owned[id] = OwnedItem(costPaid: cost, boughtAt: boughtAt)
        return l
    }

    func test_aRelockedItemDoesNotComeBackWhenAStaleDeviceMergesIn() {
        let t = Date(timeIntervalSince1970: 1000)
        let stale = ledger(owning: "celebration.explosion", boughtAt: t)
        var refunded = stale
        refunded.owned = [:]
        refunded.refunded["watch"] = 40
        refunded.relocked = [Tombstone(itemID: "celebration.explosion", boughtAt: t)]

        let merged = PointsLedger.merge(refunded, stale)

        XCTAssertNil(merged.owned["celebration.explosion"])
        XCTAssertGreaterThanOrEqual(merged.balance, 0)
    }

    func test_anItemReboughtAfterBeingRelockedSurvivesAMergeWithTheTombstone() {
        let old = Date(timeIntervalSince1970: 1000), new = Date(timeIntervalSince1970: 2000)
        var a = ledger(owning: "celebration.explosion", boughtAt: new)
        a.relocked = [Tombstone(itemID: "celebration.explosion", boughtAt: old)]
        let stale = ledger(owning: "celebration.explosion", boughtAt: old)

        for merged in [PointsLedger.merge(a, stale), PointsLedger.merge(stale, a)] {
            XCTAssertEqual(merged.owned["celebration.explosion"]?.boughtAt, new)
        }
    }

    func test_tombstoneMergingIsOrderIndependent() {
        let t = Date(timeIntervalSince1970: 1000)
        var a = ledger(owning: "paddle.sky", boughtAt: t, cost: 30)
        a.relocked = [Tombstone(itemID: "paddle.sky", boughtAt: t)]
        var b = ledger(owning: "celebration.explosion", boughtAt: t)
        b.relocked = [Tombstone(itemID: "celebration.rainbow", boughtAt: t)]
        XCTAssertEqual(PointsLedger.merge(a, b), PointsLedger.merge(b, a))
        XCTAssertEqual(PointsLedger.merge(a, b).relocked.count, 2)
    }

    func test_aRevokeRecordsATombstoneForEachItemItRelocks() {
        let s = makeStore()
        s.recordPurchase(points: 40, transactionID: "tx-1")
        XCTAssertTrue(s.buy(item("celebration.explosion")))
        let cloud = RecordingCloud()
        let s2 = ProgressionStore(defaults: defaults, cloud: cloud)
        s2.revoke(points: 40, transactionID: "tx-1")
        XCTAssertEqual(cloud.saved.last?.relocked.map(\.itemID), ["celebration.explosion"])
    }
}

private final class RecordingCloud: LedgerCloudStore {
    private(set) var saved: [PointsLedger] = []
    func loadLedger() -> PointsLedger? { nil }
    func save(_ ledger: PointsLedger) { saved.append(ledger) }
    func startWatching(_ onRemoteChange: @escaping (PointsLedger) -> Void) {}
}
