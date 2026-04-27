import Foundation
import Network
import Combine
@testable import PongWatch_Watch_App

final class FakeMultiplayerService: MultiplayerServiceProtocol {
    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var connectionState: MPConnectionState = .idle
    @Published var role: PeerRole? = nil

    private var continuation: AsyncStream<NetworkMessage>.Continuation!
    let incomingMessages: AsyncStream<NetworkMessage>

    var statePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    /// Messages the SUT sent via `send(...)`. Inspect in assertions.
    private(set) var sentMessages: [(message: NetworkMessage, reliable: Bool)] = []

    init() {
        var c: AsyncStream<NetworkMessage>.Continuation!
        self.incomingMessages = AsyncStream { c = $0 }
        self.continuation = c
    }

    func startAdvertising() {}
    func stopAdvertising() {}
    func startBrowsing() {}
    func stopBrowsing() {}
    func invite(_ peer: DiscoveredPeer) { role = .host }
    func respondToInvite(accept: Bool) { if accept { role = .client } }

    func send(_ message: NetworkMessage, reliable: Bool) {
        sentMessages.append((message, reliable))
    }

    func disconnect() {
        connectionState = .idle
        role = nil
    }

    // MARK: - Test helpers

    /// Simulate the peer sending us a message.
    func simulateIncoming(_ message: NetworkMessage) {
        continuation.yield(message)
    }

    /// Simulate becoming connected in a specific role.
    func simulateConnected(
        as role: PeerRole,
        peer: DiscoveredPeer = DiscoveredPeer(
            id: "test-peer",
            displayName: "Test Peer",
            endpoint: .service(name: "test", type: "_pongwatch._tcp", domain: "local.", interface: nil)
        )
    ) {
        self.role = role
        self.connectionState = .connected(peer: peer, role: role)
    }

    /// Simulate the peer disconnecting.
    func simulateDisconnect() {
        self.connectionState = .disconnected
        self.role = nil
    }
}
