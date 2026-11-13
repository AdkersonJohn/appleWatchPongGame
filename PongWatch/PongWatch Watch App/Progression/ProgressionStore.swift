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
        // 1.1 keys, read once by the migration. `equipped` below is unchanged.
        static let legacyAvailable = "progress.availablePoints"
        static let legacyLifetime = "progress.lifetimePoints"
        static let legacyUnlocked = "progress.unlocked"
        static let equipped = "progress.equipped"
    }

    private let defaults: UserDefaults
    private let cloud: LedgerCloudStore

    /// Only the app's real defaults sync by default; an isolated suite (tests,
    /// previews) stays local so it can't write into the player's iCloud wallet.
    init(defaults: UserDefaults = .standard, cloud: LedgerCloudStore? = nil) {
        self.defaults = defaults
        self.cloud = cloud ?? (defaults === UserDefaults.standard ? CloudKitValueStore() : NoCloudStore())
        if let data = defaults.data(forKey: Key.ledger) {
            // Keep what we can't read: the next write would otherwise replace it.
            if (try? JSONDecoder().decode(PointsLedger.self, from: data)) == nil {
                defaults.set(data, forKey: Key.unreadableLedger)
            }
        } else {
            migrateLegacyKeys()
        }
        mergeRemote(self.cloud.loadLedger())
        self.cloud.startWatching { [weak self] in self?.mergeRemote($0) }
    }

    /// Folds another device's ledger into ours. Writes only when that changes
    /// something, so two devices can't keep echoing the same value at each other.
    private func mergeRemote(_ remote: PointsLedger?) {
        guard let remote else { return }
        let local = ledger
        let merged = PointsLedger.merge(local, remote)
        if merged != local { ledger = merged }
    }

    /// Builds the ledger from the 1.1 keys so nobody's balance changes on upgrade.
    private func migrateLegacyKeys() {
        let keys = [Key.legacyAvailable, Key.legacyLifetime, Key.legacyUnlocked]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        var l = PointsLedger()
        l.earned[PointsLedger.deviceKind] = defaults.integer(forKey: Key.legacyLifetime)
        for id in defaults.stringArray(forKey: Key.legacyUnlocked) ?? [] {
            guard let item = UnlockCatalog.item(id: id), item.cost > 0 else { continue }
            l.owned[id] = OwnedItem(costPaid: item.cost, boughtAt: .distantPast)
        }
        // The balance the player last saw wins. If lifetime disagrees (a price
        // changed, or the data was inconsistent), restate earned in either direction.
        l.earned[PointsLedger.deviceKind, default: 0] += defaults.integer(forKey: Key.legacyAvailable) - l.balance
        ledger = l
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
        // A failed encode must not reach `set`: nil would delete the wallet.
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.ledger)
            cloud.save(newValue)
        }
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
        l.purchased[PointsLedger.deviceKind, default: 0] += points
        ledger = l
        return true
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

    private var equippedByCategory: [String: String] {
        get { defaults.dictionary(forKey: Key.equipped) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.equipped) }
    }

    func equipped(in category: UnlockCategory) -> String? {
        equippedByCategory[category.rawValue]
    }

    /// Equipping something you don't own is ignored rather than trusted.
    func equip(_ item: Unlockable) {
        guard isUnlocked(item) else { return }
        equippedByCategory[item.category.rawValue] = item.id
    }

    /// What's equipped in a category, falling back to that category's free item
    /// so callers never have to deal with an empty slot.
    func equippedItem(in category: UnlockCategory) -> Unlockable? {
        if let id = equipped(in: category), let item = UnlockCatalog.item(id: id) { return item }
        return UnlockCatalog.all.first { $0.category == category && $0.cost == 0 }
    }
}
