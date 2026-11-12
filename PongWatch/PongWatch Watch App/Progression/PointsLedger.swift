import Foundation

struct OwnedItem: Codable, Equatable {
    let costPaid: Int
    let boughtAt: Date
}

/// The wallet as facts that only ever accumulate, so two devices can merge
/// their copies without one overwriting the other. The balance is derived,
/// never stored. Counters are keyed by device kind ("watch"/"phone"), not per
/// install, so merging is a per-key max.
struct PointsLedger: Codable, Equatable {
    var earned: [String: Int] = [:]
    var purchased: [String: Int] = [:]
    var refunded: [String: Int] = [:]
    var owned: [String: OwnedItem] = [:]
    /// Separate sets: a StoreKit revocation reuses the purchase's transaction
    /// id, so one shared set would make every refund look already handled.
    var creditedTransactions: Set<String> = []
    var revokedTransactions: Set<String> = []

    static let deviceKind: String = {
        #if os(watchOS)
        "watch"
        #else
        "phone"
        #endif
    }()

    var balance: Int {
        earned.values.reduce(0, +) + purchased.values.reduce(0, +)
            - refunded.values.reduce(0, +) - owned.values.reduce(0) { $0 + $1.costPaid }
    }

    var lifetimeEarned: Int { earned.values.reduce(0, +) }

    static func merge(_ a: PointsLedger, _ b: PointsLedger) -> PointsLedger {
        var m = PointsLedger()
        m.earned = a.earned.merging(b.earned, uniquingKeysWith: max)
        m.purchased = a.purchased.merging(b.purchased, uniquingKeysWith: max)
        m.refunded = a.refunded.merging(b.refunded, uniquingKeysWith: max)
        m.owned = a.owned.merging(b.owned) { $0.boughtAt <= $1.boughtAt ? $0 : $1 }
        m.creditedTransactions = a.creditedTransactions.union(b.creditedTransactions)
        m.revokedTransactions = a.revokedTransactions.union(b.revokedTransactions)
        return m
    }
}
