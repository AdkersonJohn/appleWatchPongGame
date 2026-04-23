import Foundation
import Combine

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
    var connectionState: MPConnectionState { get }
    var role: PeerRole? { get }
    var incomingMessages: AsyncStream<NetworkMessage> { get }

    func startAdvertising()
    func stopAdvertising()
    func startBrowsing()
    func stopBrowsing()
    func invite(_ peer: DiscoveredPeer)
    func respondToInvite(accept: Bool)
    func send(_ message: NetworkMessage, reliable: Bool)
    func disconnect()
}
