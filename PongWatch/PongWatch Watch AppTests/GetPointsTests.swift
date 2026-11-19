import XCTest
@testable import PongWatch_Watch_App

/// When the Get Points screen may sell. The layout itself is checked by eye in the simulator.
final class GetPointsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "GetPointsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeStore() -> ProgressionStore {
        ProgressionStore(defaults: defaults, cloud: NoCloudStore())
    }

    private var remainingCost: Int { UnlockCatalog.all.map(\.cost).reduce(0, +) }

    func test_thePacksAreSellableWhileAnythingRemainsUnaffordable() {
        let s = makeStore()
        XCTAssertEqual(GetPointsAvailability.current(store: s), .sellable)
        s.award(remainingCost - 1)
        XCTAssertEqual(GetPointsAvailability.current(store: s), .sellable)
    }

    /// The spec's anti-goal: never sell currency that buys nothing.
    func test_thereIsNothingLeftToBuyOnceTheBalanceCoversEverythingUnowned() {
        let s = makeStore()
        s.award(remainingCost)
        XCTAssertEqual(GetPointsAvailability.current(store: s), .nothingLeftToBuy)
    }

    func test_owningEverythingAlsoMeansNothingLeftToBuy() {
        let s = makeStore()
        s.award(remainingCost)
        for item in UnlockCatalog.all { s.buy(item) }
        XCTAssertEqual(s.availablePoints, 0)
        XCTAssertEqual(GetPointsAvailability.current(store: s), .nothingLeftToBuy)
    }

    func test_ownedItemsNoLongerCountTowardWhatIsLeftToBuy() {
        let s = makeStore()
        let cheapest = UnlockCatalog.all.filter { $0.cost > 0 }.min { $0.cost < $1.cost }!
        s.award(cheapest.cost)
        s.buy(cheapest)
        s.award(remainingCost - cheapest.cost - 1)
        XCTAssertEqual(GetPointsAvailability.current(store: s), .sellable)
    }

    @MainActor
    private func assertRejected(quantity: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let service = PurchaseService(store: makeStore())
        do {
            _ = try await service.purchase(PointPack.custom, quantity: quantity)
            XCTFail("quantity \(quantity) should be rejected", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PurchaseError, .invalidQuantity, file: file, line: line)
        }
    }

    func test_purchaseRejectsOneMoreThanTheMaximumQuantity() async {
        await assertRejected(quantity: PurchaseService.maxQuantity + 1)
    }

    func test_purchaseRejectsZeroAndNegativeQuantities() async {
        await assertRejected(quantity: 0)
        await assertRejected(quantity: -1)
    }

    /// Accepting needs a live Product, so only the rejections are testable here:
    /// a quantity in range gets past the guard and fails later, as productUnavailable.
    @MainActor
    func test_aQuantityWithinRangeIsNotRejectedAsInvalid() async {
        let service = PurchaseService(store: makeStore())
        do {
            _ = try await service.purchase(PointPack.custom, quantity: PurchaseService.maxQuantity)
            XCTFail("no products are loaded")
        } catch {
            XCTAssertEqual(error as? PurchaseError, .productUnavailable)
        }
    }
}
