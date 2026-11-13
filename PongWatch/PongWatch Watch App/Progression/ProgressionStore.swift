import Foundation

/// Points earned, things unlocked, and what's currently equipped.
///
/// UserDefaults-backed like HighScoreStore: the points ledger is a few small
/// dictionaries, and it has to survive a relaunch — losing it would erase the only
/// reason to keep playing.
final class ProgressionStore {
    private enum Key {
        static let ledger = "progress.ledger"
        static let unreadableLedger = "progress.ledger.unreadable"
        /// Item ids a re-lock took, until the player taps OK on the notice.
        static let pendingRelockNotice = "progress.relockedNotice"
        // 1.1 keys, read by the migration. Never written or deleted afterwards.
        // Only `equipped` is useful to a downgrade: once progress.ledger exists, points
        // and unlocks earned on 1.1 are never read back from these keys.
        static let legacyAvailable = "progress.availablePoints"
        static let legacyLifetime = "progress.lifetimePoints"
        static let legacyUnlocked = "progress.unlocked"
        static let legacyEquipped = "progress.equipped"
    }

    private let defaults: UserDefaults
    private let cloud: LedgerCloudStore

    /// Tests default to local-only so nothing under test reaches the player's
    /// real iCloud wallet; the app gets the real store.
    init(defaults: UserDefaults = .standard, cloud: LedgerCloudStore? = nil) {
        self.defaults = defaults
        self.cloud = cloud ?? (NSClassFromString("XCTestCase") == nil ? CloudKitValueStore() : NoCloudStore())
        let remote = self.cloud.loadLedger()
        if let data = defaults.data(forKey: Key.ledger) {
            // Keep what we can't read: the next write would otherwise replace it.
            if (try? JSONDecoder().decode(PointsLedger.self, from: data)) == nil {
                defaults.set(data, forKey: Key.unreadableLedger)
            }
        } else if let migrated = legacyLedger() {
            // Local only: pushing before the remote is merged would overwrite it.
            persist(migrated)
        }
        migrateLegacyEquipped()
        reconcile(with: remote)
        self.cloud.startWatching { [weak self] remote, accountChanged in
            // A different iCloud account's wallet is a stranger's: merging would give
            // them our points, items and transaction ids for good (every field is
            // grow-only), and pushing the union would give us theirs. Keep local and
            // don't push, so neither wallet is touched.
            guard !accountChanged else { return }
            self?.reconcile(with: remote)
        }
    }

    /// Merges another device's ledger with ours, then brings both copies up to
    /// the result. Each side is written only if it changed, so two devices
    /// can't keep echoing the same value at each other.
    private func reconcile(with remote: PointsLedger?) {
        let local = ledger
        var merged = PointsLedger.merge(local, remote ?? PointsLedger())
        let relocked = merged.settle()
        if merged != local { persist(merged) }
        noteRelocked(relocked)
        if merged != (remote ?? PointsLedger()) { cloud.save(merged) }
    }

    /// Items waiting to be announced, persisted so a refund that lands at launch
    /// is still told to the player whenever they next open Unlocks.
    var pendingRelockNotice: [Unlockable] {
        (defaults.stringArray(forKey: Key.pendingRelockNotice) ?? []).compactMap(UnlockCatalog.item(id:))
    }

    func clearRelockNotice() { defaults.removeObject(forKey: Key.pendingRelockNotice) }

    private func noteRelocked(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var pending = defaults.stringArray(forKey: Key.pendingRelockNotice) ?? []
        pending += ids.filter { !pending.contains($0) }
        defaults.set(pending, forKey: Key.pendingRelockNotice)
    }

    /// Choices made before they lived in the ledger. `.distantPast` so any real
    /// choice, here or on another device, beats them; a category already in the
    /// ledger is never overwritten, which makes this safe to run every launch.
    private func migrateLegacyEquipped() {
        let old = defaults.dictionary(forKey: Key.legacyEquipped) as? [String: String] ?? [:]
        var l = ledger
        for (category, id) in old where l.equipped[category] == nil {
            l.equipped[category] = EquippedChoice(itemID: id, changedAt: .distantPast)
        }
        if l != ledger { persist(l) }
    }

    /// Builds the ledger from the 1.1 keys so nobody's balance changes on upgrade.
    private func legacyLedger() -> PointsLedger? {
        let keys = [Key.legacyAvailable, Key.legacyLifetime, Key.legacyUnlocked]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return nil }
        // ACCEPTED, don't "fix": earned includes the cost of this device's owned items.
        // Merging sums earned across device kinds but unions owned, so an item owned on
        // both a 1.1 watch and a 1.1 phone is counted twice in earned and subtracted
        // once: the player gets the overlap back as free points, once, on first merge.
        // That is always in their favour, and the only local fix would restate
        // "Earned all-time" downward, which is worse.
        var l = PointsLedger()
        l.earned[PointsLedger.deviceKind] = defaults.integer(forKey: Key.legacyLifetime)
        for id in defaults.stringArray(forKey: Key.legacyUnlocked) ?? [] {
            guard let item = UnlockCatalog.item(id: id), item.cost > 0 else { continue }
            l.owned[id] = OwnedItem(costPaid: item.cost, boughtAt: .distantPast)
        }
        // The balance the player last saw wins. If lifetime disagrees (a price
        // changed, or the data was inconsistent), restate earned in either direction.
        l.earned[PointsLedger.deviceKind, default: 0] += defaults.integer(forKey: Key.legacyAvailable) - l.balance
        return l
    }

    // MARK: - Points

    /// The balance is derived from this, never stored on its own. Every ledger
    /// mutation goes through this setter, which is the only place that writes
    /// locally and pushes to the cloud, so a new mutation can't skip the push.
    private var ledger: PointsLedger {
        get {
            defaults.data(forKey: Key.ledger)
                .flatMap { try? JSONDecoder().decode(PointsLedger.self, from: $0) } ?? PointsLedger()
        }
        set { if persist(newValue) { cloud.save(newValue) } }
    }

    /// False, writing nothing, when encoding fails: nil would delete the wallet.
    @discardableResult
    private func persist(_ l: PointsLedger) -> Bool {
        guard let data = try? JSONEncoder().encode(l) else { return false }
        defaults.set(data, forKey: Key.ledger)
        return true
    }

    var availablePoints: Int { ledger.balance }

    /// Everything ever earned by playing. A record for titles and bragging,
    /// never spent, and never inflated by purchased points.
    var lifetimePoints: Int { ledger.lifetimeEarned }

    func award(_ points: Int) {
        guard points > 0 else { return }
        ledger.earned[PointsLedger.deviceKind, default: 0] += points
    }

    /// Credits bought points once per StoreKit transaction. False, changing
    /// nothing, when that transaction was already credited.
    @discardableResult
    func recordPurchase(points: Int, transactionID: String) -> Bool {
        var l = ledger
        guard points > 0, l.creditedTransactions.insert(transactionID).inserted else { return false }
        l.purchasedByTx[transactionID] = points
        // A refund that arrived first starts counting now, so this can re-lock.
        let relocked = l.settle()
        ledger = l
        noteRelocked(relocked)
        return true
    }

    /// Records a refund. Guards on `revokedTransactions`, not the credited set: a
    /// revocation carries the purchase's own id. Returns the items re-locked now, so
    /// the player can be told; a refund that can't count yet re-locks later, in `settle()`.
    @discardableResult
    func revoke(points: Int, transactionID: String) -> [Unlockable] {
        var l = ledger
        guard points > 0, l.revokedTransactions.insert(transactionID).inserted else { return [] }
        l.refundedByTx[transactionID] = points
        let relocked = l.settle()
        ledger = l
        noteRelocked(relocked)
        return relocked.compactMap(UnlockCatalog.item(id:))
    }

    // MARK: - Unlocks

    func isUnlocked(_ item: Unlockable) -> Bool {
        ledger.owned[item.id] != nil || UnlockCatalog.freeIDs.contains(item.id)
    }

    /// Returns false when it's already owned or unaffordable, charging nothing
    /// either way.
    @discardableResult
    func buy(_ item: Unlockable) -> Bool {
        var l = ledger
        guard !isUnlocked(item), l.balance >= item.cost else { return false }
        l.owned[item.id] = OwnedItem(costPaid: item.cost, boughtAt: Date())
        ledger = l
        return true
    }

    /// How many of a category are owned, for the collapsed section header.
    func ownedCount(in category: UnlockCategory) -> Int {
        UnlockCatalog.all.filter { $0.category == category && isUnlocked($0) }.count
    }

    func totalCount(in category: UnlockCategory) -> Int {
        UnlockCatalog.all.filter { $0.category == category }.count
    }

    /// Items in a category you could buy right now. Drives the "ready" flag on
    /// a collapsed header, so the player knows which section to open.
    func affordableCount(in category: UnlockCategory) -> Int {
        UnlockCatalog.all.filter {
            $0.category == category && !isUnlocked($0) && $0.cost <= availablePoints
        }.count
    }

    // MARK: - Equipped

    func equipped(in category: UnlockCategory) -> String? {
        ledger.equipped[category.rawValue]?.itemID
    }

    /// Equipping something you don't own is ignored rather than trusted.
    func equip(_ item: Unlockable) {
        guard isUnlocked(item) else { return }
        ledger.equipped[item.category.rawValue] = EquippedChoice(itemID: item.id, changedAt: Date())
    }

    /// What's equipped in a category, falling back to that category's free item
    /// so callers never have to deal with an empty slot.
    func equippedItem(in category: UnlockCategory) -> Unlockable? {
        // Owned-ness is checked on read: a synced, migrated or refunded choice can name an item this device doesn't own.
        if let id = equipped(in: category), let item = UnlockCatalog.item(id: id), isUnlocked(item) { return item }
        return UnlockCatalog.all.first { $0.category == category && $0.cost == 0 }
    }
}
