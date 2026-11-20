import XCTest
import StoreKit
import StoreKitTest
@testable import PongWatch_Watch_App

/// The refund path, against real StoreKit rather than ProgressionStore alone.
///
/// This exists to answer one question that unit tests cannot: **does StoreKit
/// deliver a revocation for a consumable that has already been finished?** The
/// whole refund-reversal apparatus — tombstones, the settle pass, the re-lock
/// notice — is dead weight if it never does, and it sits in the money path.
///
/// Products come from `Points.storekit` via the scheme's Test action.
@MainActor
final class RefundIntegrationTests: XCTestCase {
    private var session: SKTestSession!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // Opt-in only. `product.purchase()` never returns in a watchOS unit-test
        // host: StoreKit wants to present a purchase sheet, there is no UI to
        // present it in, and `disableDialogs` does not help. Verified twice on
        // 2026-11-20 — both runs hung and were killed at the time allowance,
        // after the config had loaded and the purchase had reached StoreKit.
        //
        // Kept because the question it asks is still open and the setup is
        // correct; only the watchOS host defeats it. Run with
        // REFUND_INTEGRATION=1 if a future Xcode presents the sheet, or port it
        // to an iOS test host. Until then the refund path is exercised by hand
        // through a sandbox tester.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REFUND_INTEGRATION"] == "1",
                          "Opt in with REFUND_INTEGRATION=1 - purchase() hangs on a watchOS test host")

        // Located from this file's own path rather than copied into the test
        // bundle: a second Points.storekit would be a second source of truth
        // for prices. `configurationFileNamed:` cannot see the scheme's config.
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PongWatch Watch AppTests
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

        // The listener is what a real refund arrives through.
        purchases.listenForTransactions()

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
