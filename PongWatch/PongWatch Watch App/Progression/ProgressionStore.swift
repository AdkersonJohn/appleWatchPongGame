import Foundation

/// Points earned, things unlocked, and what's currently equipped.
///
/// UserDefaults-backed like HighScoreStore: this is a handful of ids and two
/// integers, and it has to survive a relaunch — losing it would erase the only
/// reason to keep playing.
final class ProgressionStore {
    private enum Key {
        static let available = "progress.availablePoints"
        static let lifetime = "progress.lifetimePoints"
        static let unlocked = "progress.unlocked"
        static let equipped = "progress.equipped"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Points

    private(set) var availablePoints: Int {
        get { defaults.integer(forKey: Key.available) }
        set { defaults.set(newValue, forKey: Key.available) }
    }

    /// Everything ever earned. A record for titles and bragging, never spent.
    private(set) var lifetimePoints: Int {
        get { defaults.integer(forKey: Key.lifetime) }
        set { defaults.set(newValue, forKey: Key.lifetime) }
    }

    func award(_ points: Int) {
        guard points > 0 else { return }
        availablePoints += points
        lifetimePoints += points
    }

    // MARK: - Unlocks

    private var unlockedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.unlocked) ?? []).union(UnlockCatalog.freeIDs) }
        set { defaults.set(Array(newValue), forKey: Key.unlocked) }
    }

    func isUnlocked(_ item: Unlockable) -> Bool { unlockedIDs.contains(item.id) }

    /// Returns false when it's already owned or unaffordable, charging nothing
    /// either way.
    @discardableResult
    func buy(_ item: Unlockable) -> Bool {
        guard !isUnlocked(item), availablePoints >= item.cost else { return false }
        availablePoints -= item.cost
        unlockedIDs.insert(item.id)
        return true
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
