import Foundation
import Combine

/// Turns a Network.framework failure reason into something a tester can act on
/// without opening the log. Kept free of Network types so it can be tested.
enum MPIssue {
    static func hint(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("policy") || s.contains("denied") || s.contains("65555") {
            return "Local Network access is off. Settings → Pong Pal Showdown → Local Network."
        }
        if s.contains("network is down") || s.contains("nonetwork") || s.contains("wifi") {
            return "Turn Wi-Fi on for both devices, ideally the same network."
        }
        return "Trouble starting: \(raw)"
    }
}

enum MPConnectionState: Equatable {
    case idle
    case discovering
    case inviting(DiscoveredPeer)
    case receivingInvite(fromDisplayName: String)
    case connected(peer: DiscoveredPeer, role: PeerRole)
    case disconnected
    case failed(String)
}

protocol MultiplayerServiceProtocol: AnyObject, ObservableObject {
    var discoveredPeers: [DiscoveredPeer] { get }
    /// Non-nil when discovery can't run. Shown in the lobby so a permission
    /// problem doesn't just look like an empty room.
    var lastIssue: String? { get }
    var connectionState: MPConnectionState { get }
    var role: PeerRole? { get }
    var incomingMessages: AsyncStream<NetworkMessage> { get }
    /// Type-erased publisher that fires whenever any service state changes.
    /// Conformers can implement this as `objectWillChange.eraseToAnyPublisher()`.
    var statePublisher: AnyPublisher<Void, Never> { get }

    func startAdvertising()
    func stopAdvertising()
    func startBrowsing()
    func stopBrowsing()
    func invite(_ peer: DiscoveredPeer)
    func respondToInvite(accept: Bool)
    func send(_ message: NetworkMessage, reliable: Bool)
    func disconnect()
}
