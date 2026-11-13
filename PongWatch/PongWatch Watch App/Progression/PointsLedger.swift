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
    /// Keyed by StoreKit transaction id, not device kind: every device signed into
    /// the Apple ID is handed the same transaction, and per-device counters would
    /// sum its points once per device.
    var purchasedByTx: [String: Int] = [:]
    /// Same keying, so two devices processing one revocation refund it once.
    var refundedByTx: [String: Int] = [:]
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

    private var granted: Int { earned.values.reduce(0, +) + purchasedByTx.values.reduce(0, +) }

    /// A refund counts only once its purchase's credit is known, so one that
    /// arrives early waits instead of eating points the player earned. Capped per
    /// transaction at what that transaction credited, so an oversized revocation
    /// can never reach earned points.
    private var countedRefunds: Int {
        creditedTransactions.reduce(0) { $0 + min(refundedByTx[$1] ?? 0, purchasedByTx[$1] ?? 0) }
    }

    var balance: Int {
        granted - countedRefunds - owned.values.reduce(0) { $0 + $1.costPaid }
    }

    /// Re-locks paid items, newest first, while the balance is negative, and
    /// returns their ids. Does nothing when the balance is whole, so it is safe to run
    /// after every change.
    @discardableResult
    mutating func settle() -> [String] {
        var relockedIDs: [String] = []
        let newestFirst = owned.filter { $0.value.costPaid > 0 }
            .sorted { ($0.value.boughtAt, $0.key) > ($1.value.boughtAt, $1.key) }
        for (id, item) in newestFirst where balance < 0 {
            owned[id] = nil
            relocked.insert(Tombstone(itemID: id, boughtAt: item.boughtAt))
            relockedIDs.append(id)
        }
        return relockedIDs
    }

    var lifetimeEarned: Int { earned.values.reduce(0, +) }

    static func merge(_ a: PointsLedger, _ b: PointsLedger) -> PointsLedger {
        var m = PointsLedger()
        m.earned = a.earned.merging(b.earned, uniquingKeysWith: max)
        m.purchasedByTx = a.purchasedByTx.merging(b.purchasedByTx, uniquingKeysWith: max)
        m.refundedByTx = a.refundedByTx.merging(b.refundedByTx, uniquingKeysWith: max)
        m.relocked = a.relocked.union(b.relocked)
        // Drop tombstoned entries before merging: the merge keeps the earlier boughtAt,
        // which would otherwise let a stale copy shadow a later re-purchase.
        let live = { (l: PointsLedger) in l.owned.filter { !m.relocked.contains(Tombstone(itemID: $0.key, boughtAt: $0.value.boughtAt)) } }
        m.owned = live(a).merging(live(b)) { ($0.boughtAt, $0.costPaid) <= ($1.boughtAt, $1.costPaid) ? $0 : $1 }
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
/// WARNING: this does not protect the nested types (OwnedItem, EquippedChoice,
/// Tombstone), which decode strictly: they may only ever gain optional fields.
extension PointsLedger {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        earned = try c.decodeIfPresent([String: Int].self, forKey: .earned) ?? [:]
        purchasedByTx = try c.decodeIfPresent([String: Int].self, forKey: .purchasedByTx) ?? [:]
        refundedByTx = try c.decodeIfPresent([String: Int].self, forKey: .refundedByTx) ?? [:]
        owned = try c.decodeIfPresent([String: OwnedItem].self, forKey: .owned) ?? [:]
        equipped = try c.decodeIfPresent([String: EquippedChoice].self, forKey: .equipped) ?? [:]
        creditedTransactions = try c.decodeIfPresent(Set<String>.self, forKey: .creditedTransactions) ?? []
        revokedTransactions = try c.decodeIfPresent(Set<String>.self, forKey: .revokedTransactions) ?? []
        relocked = try c.decodeIfPresent(Set<Tombstone>.self, forKey: .relocked) ?? []
    }
}
