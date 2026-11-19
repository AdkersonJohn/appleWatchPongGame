import Foundation
import Combine
import StoreKit

enum PurchaseError: Error {
    case unverified
    case productUnavailable
    /// Quantity outside 1...PurchaseService.maxQuantity. Rejected, never clamped:
    /// clamping would charge a different amount than the screen showed.
    case invalidQuantity
}

/// What a purchase attempt came to, so the screen never reports a credited
/// purchase as a cancellation (the launch listener can win the race).
enum PurchaseOutcome: Equatable {
    case credited(points: Int)
    case cancelled
    case pending
    /// Another path (the launch listener) already credited it, or it isn't ours.
    case alreadyCredited
}

/// Sells point packs through StoreKit 2 and credits them to the wallet.
@MainActor
final class PurchaseService: ObservableObject {
    @Published private(set) var packs: [(pack: PointPack, product: Product)] = []
    @Published private(set) var isPurchasing = false
    /// Items a refund or sync re-locked, until the player has been told. Mirrors a
    /// list the store persists, so it survives a relaunch.
    @Published private(set) var relocked: [Unlockable] = []
    /// Bumped whenever the wallet changes here, so open screens can redraw.
    @Published private(set) var walletChanges = 0

    private let store: ProgressionStore
    private var updatesTask: Task<Void, Never>?

    init(store: ProgressionStore) {
        self.store = store
        relocked = store.pendingRelockNotice
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        guard let products = try? await Product.products(for: PointPack.all.map(\.id)) else { return }
        packs = PointPack.all.compactMap { pack in
            products.first { $0.id == pack.id }.map { (pack, $0) }
        }
    }

    /// Units per transaction. Believed to be Apple's limit but UNCONFIRMED; Task 7
    /// checks it against real sandbox products (at the bound and one above).
    static let maxQuantity = 10

    func refreshRelocked() { relocked = store.pendingRelockNotice }

    func dismissRelocked() {
        store.clearRelockNotice()
        relocked = []
    }

    /// A pending purchase arrives later through the updates listener.
    func purchase(_ pack: PointPack, quantity: Int = 1) async throws -> PurchaseOutcome {
        // Before the first await: two taps in one frame would otherwise both get past.
        guard !isPurchasing else { return .cancelled }
        guard (1...Self.maxQuantity).contains(quantity) else { throw PurchaseError.invalidQuantity }
        guard let product = packs.first(where: { $0.pack == pack })?.product else {
            throw PurchaseError.productUnavailable
        }
        isPurchasing = true
        defer { isPurchasing = false }
        let options: Set<Product.PurchaseOption> = quantity > 1 ? [.quantity(quantity)] : []
        switch try await product.purchase(options: options) {
        case .success(let verification):
            return try await credit(verification)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
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
    @discardableResult
    private func credit(_ verification: VerificationResult<Transaction>) async throws -> PurchaseOutcome {
        guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
        guard let points = PointPack.pointsToCredit(productID: transaction.productID,
                                                    quantity: transaction.purchasedQuantity) else {
            // Not ours: finish it, or StoreKit redelivers it on every launch.
            await transaction.finish()
            return .alreadyCredited
        }
        let id = String(transaction.id)
        var credited = false
        if transaction.revocationDate == nil {
            credited = store.recordPurchase(points: points, transactionID: id)
        } else {
            // A refund reverses the whole purchase, even points already spent.
            store.revoke(points: points, transactionID: id)
        }
        refreshRelocked()
        walletChanges += 1
        await transaction.finish()
        return credited ? .credited(points: points) : .alreadyCredited
    }
}
