import Foundation
import Combine
import StoreKit

enum PurchaseError: Error {
    case unverified
    case productUnavailable
}

/// Sells point packs through StoreKit 2 and credits them to the wallet.
@MainActor
final class PurchaseService: ObservableObject {
    @Published private(set) var packs: [(pack: PointPack, product: Product)] = []
    @Published private(set) var isPurchasing = false

    private let store: ProgressionStore
    private var updatesTask: Task<Void, Never>?

    init(store: ProgressionStore) {
        self.store = store
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        guard let products = try? await Product.products(for: PointPack.all.map(\.id)) else { return }
        packs = PointPack.all.compactMap { pack in
            products.first { $0.id == pack.id }.map { (pack, $0) }
        }
    }

    /// True when points were credited; false when the player cancelled or the
    /// purchase is pending approval (it arrives later through the updates listener).
    func purchase(_ pack: PointPack, quantity: Int = 1) async throws -> Bool {
        guard let product = packs.first(where: { $0.pack == pack })?.product else {
            throw PurchaseError.productUnavailable
        }
        isPurchasing = true
        defer { isPurchasing = false }
        let options: Set<Product.PurchaseOption> = quantity > 1 ? [.quantity(quantity)] : []
        switch try await product.purchase(options: options) {
        case .success(let verification):
            return try await credit(verification)
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                _ = try? await self?.credit(update)
            }
        }
    }

    /// Transactions a previous launch was killed before finishing.
    func creditUnfinished() async {
        for await unfinished in Transaction.unfinished {
            _ = try? await credit(unfinished)
        }
    }

    /// The one crediting path. Credit first, finish second: if the app dies in
    /// between, StoreKit replays the transaction and the id check stops a double credit.
    private func credit(_ verification: VerificationResult<Transaction>) async throws -> Bool {
        guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
        // Refunds are Task 5; a revoked transaction must never add points.
        guard let points = PointPack.pointsToCredit(productID: transaction.productID,
                                                    quantity: transaction.purchasedQuantity,
                                                    isRevoked: transaction.revocationDate != nil) else { return false }
        let credited = store.recordPurchase(points: points, transactionID: String(transaction.id))
        await transaction.finish()
        return credited
    }
}
