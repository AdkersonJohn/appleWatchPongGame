import Foundation

struct OwnedItem: Codable, Equatable {
    let costPaid: Int
    let boughtAt: Date
}

/// A re-locked purchase. Keyed by when it was bought as well as by item, so
/// buying the item again later (a newer `boughtAt`) isn't killed by it.
struct Tombstone: Codable, Hashable {
    let itemID: String
    let boughtAt: Date
}

struct EquippedChoice: Codable, Equatable {
    let itemID: String
    let changedAt: Date
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
    /// The one field that isn't grow-only: keyed by `UnlockCategory.rawValue`,
    /// and merged by the later `changedAt`.
    var equipped: [String: EquippedChoice] = [:]
    /// Separate sets: a StoreKit revocation reuses the purchase's transaction
    /// id, so one shared set would make every refund look already handled.
    var creditedTransactions: Set<String> = []
    var revokedTransactions: Set<String> = []
    /// Grow-only: owned entries a refund re-locked, so a device that still
    /// carries them can't merge them back.
    var relocked: Set<Tombstone> = []

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
        m.relocked = a.relocked.union(b.relocked)
        // Drop tombstoned entries before merging: the merge keeps the earlier boughtAt,
        // which would otherwise let a stale copy shadow a later re-purchase.
        let live = { (l: PointsLedger) in l.owned.filter { !m.relocked.contains(Tombstone(itemID: $0.key, boughtAt: $0.value.boughtAt)) } }
        m.owned = live(a).merging(live(b)) { $0.boughtAt <= $1.boughtAt ? $0 : $1 }
        // An exact tie falls to the larger id so the result doesn't depend on argument order.
        m.equipped = a.equipped.merging(b.equipped) {
            ($0.changedAt, $0.itemID) >= ($1.changedAt, $1.itemID) ? $0 : $1
        }
        m.creditedTransactions = a.creditedTransactions.union(b.creditedTransactions)
        m.revokedTransactions = a.revokedTransactions.union(b.revokedTransactions)
        return m
    }
}

/// Tolerant of missing fields, so adding one later can't make old data
/// undecodable and wipe a balance.
extension PointsLedger {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        earned = try c.decodeIfPresent([String: Int].self, forKey: .earned) ?? [:]
        purchased = try c.decodeIfPresent([String: Int].self, forKey: .purchased) ?? [:]
        refunded = try c.decodeIfPresent([String: Int].self, forKey: .refunded) ?? [:]
        owned = try c.decodeIfPresent([String: OwnedItem].self, forKey: .owned) ?? [:]
        equipped = try c.decodeIfPresent([String: EquippedChoice].self, forKey: .equipped) ?? [:]
        creditedTransactions = try c.decodeIfPresent(Set<String>.self, forKey: .creditedTransactions) ?? []
        revokedTransactions = try c.decodeIfPresent(Set<String>.self, forKey: .revokedTransactions) ?? []
        relocked = try c.decodeIfPresent(Set<Tombstone>.self, forKey: .relocked) ?? []
    }
}
