import XCTest
import StoreKit
import StoreKitTest
@testable import PongWatch

/// The refund path, against real StoreKit rather than ProgressionStore alone.
///
/// This exists to answer one question that unit tests cannot: **does StoreKit
/// deliver a revocation for a consumable that has already been finished?** The
/// whole refund-reversal apparatus — tombstones, the settle pass, the re-lock
/// notice — is dead weight if it never does, and it sits in the money path.
///
/// Runs on an **iOS** host, not the watch. On a watchOS unit-test host
/// `product.purchase()` never returns: StoreKit wants to present a purchase
/// sheet and there is no UI to present it in. That cost two hung runs on
/// 2026-11-20 before the host turned out to be the problem rather than the
/// test. The app's sources build for both platforms, so the code under test
/// is the same code that ships on the watch.
@MainActor
final class RefundIntegrationTests: XCTestCase {
    private var session: SKTestSession!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // Opt in with REFUND_INTEGRATION=1. `product.purchase()` never returns
        // under XCTest — verified on a watchOS host and again on this iOS one,
        // so it is not a platform quirk. StoreKit appears to need an active UI
        // scene to present its sheet, and a unit-test host does not provide
        // one; SKTestSession.disableDialogs suppresses the confirmation prompt,
        // not the presentation itself.
        //
        // What is known to work: the configuration loads, products resolve, and
        // the purchase reaches StoreKit (the "no listener attached" runtime
        // warning fired, and stopped once the listener moved ahead of the
        // purchase). Only the await never completes.
        //
        // The untried route is an XCUITest, where the app is fully launched and
        // can present the sheet. That is a different harness, not another tweak
        // to this one.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REFUND_INTEGRATION"] == "1",
                          "Opt in with REFUND_INTEGRATION=1 - purchase() does not return under XCTest")

        // Located from this file's own path rather than copied into the test
        // bundle: a second Points.storekit would be a second source of truth
        // for prices. `configurationFileNamed:` cannot see the scheme's config.
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PongWatchTests
            .deletingLastPathComponent()   // PongWatch
            .appendingPathComponent("Points.storekit")
        session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.clearTransactions()
        suiteName = "RefundTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeStore() -> ProgressionStore {
        ProgressionStore(defaults: defaults, cloud: NoCloudStore())
    }

    /// Buy points, spend them on an item, then refund the purchase and expect
    /// the item to re-lock — the full reversal the owner asked for.
    func test_aRefundedPurchaseRevokesPointsAndRelocksWhatTheyBought() async throws {
        let store = makeStore()
        let purchases = PurchaseService(store: store)

        // Before any purchase, as the app does at launch. StoreKit warns when a
        // purchase is made with no listener attached, and the test host does not
        // start one (PongWatchApp skips it under XCTest).
        purchases.listenForTransactions()

        await purchases.load()
        try XCTSkipIf(purchases.packs.isEmpty,
                      "No products: Points.storekit is not reaching the test run")

        // 100 points, enough for a real catalogue item.
        let pack = try XCTUnwrap(PointPack.all.first { $0.points == 100 })
        let outcome = try await purchases.purchase(pack)
        guard case .credited(let points) = outcome else {
            return XCTFail("Purchase did not credit: \(outcome)")
        }
        XCTAssertEqual(points, 100)
        XCTAssertEqual(store.availablePoints, 100)

        let item = try XCTUnwrap(UnlockCatalog.all.first { $0.cost > 0 && $0.cost <= 100 })
        XCTAssertTrue(store.buy(item))
        XCTAssertTrue(store.isUnlocked(item))
        let spent = store.availablePoints

        let tx = try XCTUnwrap(session.allTransactions().first)
        try await session.refundTransaction(identifier: tx.identifier)

        // Poll rather than sleep: the revocation arrives on its own schedule.
        var relocked = false
        for _ in 0..<100 where !relocked {
            try await Task.sleep(nanoseconds: 100_000_000)
            relocked = !store.isUnlocked(item)
        }

        XCTAssertTrue(relocked,
                      "StoreKit never revoked the finished consumable — the refund "
                      + "reversal never ran. Balance stayed at \(store.availablePoints), "
                      + "was \(spent) after spending.")
        XCTAssertLessThan(store.availablePoints, 100)
    }
}
