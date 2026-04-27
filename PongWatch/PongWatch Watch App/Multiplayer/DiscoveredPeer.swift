import Foundation
import Network

/// A peer discovered via Bonjour browsing.
///
/// `id` is a stable identifier derived from the underlying NWEndpoint (Bonjour service name),
/// which is unique per advertiser. `displayName` comes from the TXT record's `name` key.
struct DiscoveredPeer: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let endpoint: NWEndpoint

    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
