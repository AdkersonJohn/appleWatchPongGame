import Foundation

/// Where the wallet is mirrored so it follows the player across devices and
/// reinstalls. Every method may be a no-op: the game never depends on it.
protocol LedgerCloudStore {
    func loadLedger() -> PointsLedger?
    func save(_ ledger: PointsLedger)
    /// Calls back whenever the stored ledger changes externally. `accountChanged`
    /// means the whole store was swapped for another iCloud account's, not that
    /// another device of this player wrote to it.
    func startWatching(_ onRemoteChange: @escaping (_ remote: PointsLedger, _ accountChanged: Bool) -> Void)
}

/// iCloud key-value storage. With no iCloud account the store simply keeps
/// returning nothing, so callers need no special case.
final class CloudKitValueStore: LedgerCloudStore {
    private static let key = "progress.ledger"
    private let kvs = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    func loadLedger() -> PointsLedger? {
        kvs.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(PointsLedger.self, from: $0) }
    }

    func save(_ ledger: PointsLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        kvs.set(data, forKey: Self.key)
    }

    func startWatching(_ onRemoteChange: @escaping (_ remote: PointsLedger, _ accountChanged: Bool) -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let accountChanged = reason == NSUbiquitousKeyValueStoreAccountChange
            if let ledger = self?.loadLedger() { onRemoteChange(ledger, accountChanged) }
        }
        kvs.synchronize()
    }
}

/// Used when iCloud is unavailable, and by anything that must stay local.
final class NoCloudStore: LedgerCloudStore {
    func loadLedger() -> PointsLedger? { nil }
    func save(_ ledger: PointsLedger) {}
    func startWatching(_ onRemoteChange: @escaping (_ remote: PointsLedger, _ accountChanged: Bool) -> Void) {}
}
