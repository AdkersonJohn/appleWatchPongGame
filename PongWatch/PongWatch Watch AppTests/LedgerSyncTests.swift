import XCTest
@testable import PongWatch_Watch_App

/// Stands in for iCloud: remembers what was pushed and lets a test play the
/// part of another device.
private final class FakeCloudStore: LedgerCloudStore {
    var stored: PointsLedger?
    var saves: [PointsLedger] = []
    private var handler: ((PointsLedger) -> Void)?
    /// iCloud signed out or switched off: saves vanish, nothing is returned or announced.
    var isOff = false

    func loadLedger() -> PointsLedger? { isOff ? nil : stored }
    func save(_ ledger: PointsLedger) { guard !isOff else { return }; stored = ledger; saves.append(ledger) }
    func startWatching(_ onRemoteChange: @escaping (PointsLedger) -> Void) { handler = onRemoteChange }

    func otherDeviceWrites(_ ledger: PointsLedger) {
        guard !isOff else { return }
        stored = ledger
        handler?(ledger)
    }
}

final class LedgerSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private let cheap = UnlockCatalog.all.first { $0.cost == 40 }!
    private let other = UnlockCatalog.all.first { $0.cost == 60 }!

    override func setUp() {
        super.setUp()
        let name = "ledger-sync-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
    }

    private func ledger(earned: [String: Int] = [:], owned: [Unlockable] = []) -> PointsLedger {
        var l = PointsLedger()
        l.earned = earned
        for item in owned { l.owned[item.id] = OwnedItem(costPaid: item.cost, boughtAt: Date()) }
        return l
    }

    /// The spec's worked example: neither device's total may replace the other's.
    func test_aRemoteLedgerMergesIntoTheLocalOneWithoutLosingPoints() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(77)
        XCTAssertEqual(s.availablePoints, 77)

        cloud.otherDeviceWrites(ledger(earned: ["phone-elsewhere": 340]))

        XCTAssertEqual(s.availablePoints, 417)
        XCTAssertEqual(s.lifetimePoints, 417)
    }

    func test_aLedgerAlreadyInTheCloudIsMergedInAtLaunch() {
        let cloud = FakeCloudStore()
        cloud.stored = ledger(earned: ["phone-elsewhere": 340])
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        XCTAssertEqual(s.availablePoints, 340)
        XCTAssertEqual(ProgressionStore(defaults: defaults, cloud: NoCloudStore()).availablePoints, 340,
                       "the merge was also written locally")
    }

    func test_anItemBoughtOnOneDeviceIsOwnedOnTheOtherAndChargedOnce() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(100)
        // The other device earned 50 and bought `cheap`; this one hasn't.
        cloud.otherDeviceWrites(ledger(earned: ["phone-elsewhere": 50], owned: [cheap]))
        XCTAssertTrue(s.isUnlocked(cheap))
        XCTAssertEqual(s.availablePoints, 100 + 50 - cheap.cost)

        XCTAssertFalse(s.buy(cheap), "already owned, so it can't be bought again")
        XCTAssertEqual(s.availablePoints, 100 + 50 - cheap.cost)
    }

    func test_everyLocalChangeIsPushedToTheCloudStore() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)

        s.award(100)
        XCTAssertEqual(cloud.stored?.balance, 100)
        s.recordPurchase(points: 500, transactionID: "t1")
        XCTAssertEqual(cloud.stored?.balance, 600)
        s.buy(cheap)
        XCTAssertEqual(cloud.stored?.balance, 600 - cheap.cost)
        XCTAssertNotNil(cloud.stored?.owned[cheap.id])
    }

    func test_aRemoteChangeThatAddsNothingIsNotPushedBack() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(10)
        let pushes = cloud.saves.count
        cloud.otherDeviceWrites(cloud.stored!)
        XCTAssertEqual(cloud.saves.count, pushes)
        XCTAssertEqual(s.availablePoints, 10)
    }

    /// Review Focus 3
    func test_withNoCloudStoreEarningBuyingAndSpendingAllStillWork() {
        let s = ProgressionStore(defaults: defaults, cloud: NoCloudStore())
        s.award(100)
        XCTAssertEqual(s.availablePoints, 100)
        XCTAssertTrue(s.buy(cheap))
        XCTAssertTrue(s.isUnlocked(cheap))
        XCTAssertEqual(s.availablePoints, 100 - cheap.cost)
        XCTAssertFalse(s.buy(UnlockCatalog.all.first { $0.cost == 750 }!), "unaffordable")
        XCTAssertEqual(s.lifetimePoints, 100)
    }

    /// iCloud turned off mid-session, then back on.
    func test_playContinuesWhileICloudIsOffAndReconcilesWhenItReturns() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(100)
        cloud.isOff = true

        s.award(60)
        XCTAssertTrue(s.buy(cheap))
        XCTAssertEqual(s.availablePoints, 160 - cheap.cost)
        XCTAssertEqual(cloud.stored?.balance, 100, "nothing reached the cloud while it was off")

        cloud.isOff = false
        cloud.otherDeviceWrites(ledger(earned: ["phone-elsewhere": 50]))
        XCTAssertEqual(s.availablePoints, 160 + 50 - cheap.cost)
        XCTAssertEqual(cloud.stored?.balance, 160 + 50 - cheap.cost, "the offline spending reached the cloud")
        XCTAssertNotNil(cloud.stored?.owned[cheap.id])
    }

    /// A wallet that existed before iCloud must reach the cloud at launch, so a
    /// second device installed meanwhile sees it.
    func test_aLocalWalletIsPushedAtLaunchWhenTheCloudIsEmpty() {
        let cloud = FakeCloudStore()
        ProgressionStore(defaults: defaults, cloud: NoCloudStore()).award(80)
        _ = ProgressionStore(defaults: defaults, cloud: cloud)
        XCTAssertEqual(cloud.stored?.balance, 80)
    }

    /// Upgrading from 1.1 with another device's wallet already in the cloud:
    /// the migrated local ledger must merge with it, never replace it.
    func test_migratingLegacyKeysNeverOverwritesALedgerAlreadyInTheCloud() {
        let cloud = FakeCloudStore()
        cloud.stored = ledger(earned: ["phone-elsewhere": 340])
        defaults.set(77, forKey: "progress.availablePoints")
        defaults.set(77, forKey: "progress.lifetimePoints")

        let s = ProgressionStore(defaults: defaults, cloud: cloud)

        XCTAssertEqual(s.availablePoints, 417)
        XCTAssertEqual(cloud.saves.count, 1, "one push, of the merged wallet")
        XCTAssertEqual(cloud.stored?.balance, 417)
    }

    /// Review Focus 4
    func test_twoDevicesThatBothSpentOfflineKeepBothItemsAndBothCharges() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(200)
        s.buy(cheap)

        var remote = ledger(earned: ["phone-elsewhere": 300], owned: [other])
        remote.earned[PointsLedger.deviceKind] = 200   // it had synced our earnings before going offline
        cloud.otherDeviceWrites(remote)

        XCTAssertTrue(s.isUnlocked(cheap))
        XCTAssertTrue(s.isUnlocked(other))
        XCTAssertEqual(s.availablePoints, 200 + 300 - cheap.cost - other.cost)
    }

    func test_bothDevicesBuyingTheSameItemChargesItOnce() {
        let cloud = FakeCloudStore()
        let s = ProgressionStore(defaults: defaults, cloud: cloud)
        s.award(200)
        s.buy(cheap)
        var remote = ledger(owned: [cheap])
        remote.earned[PointsLedger.deviceKind] = 200
        cloud.otherDeviceWrites(remote)
        XCTAssertEqual(s.availablePoints, 200 - cheap.cost)
    }
}
