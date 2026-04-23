import Foundation
import Network
import WatchKit
import Combine

@MainActor
final class MultiplayerService: MultiplayerServiceProtocol {
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var connectionState: MPConnectionState = .idle
    @Published private(set) var role: PeerRole? = nil

    let incomingMessages: AsyncStream<NetworkMessage>
    private let messageContinuation: AsyncStream<NetworkMessage>.Continuation

    var statePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    private let displayName: String
    private let bonjourType: String
    private let queue = DispatchQueue(label: "mp.service.queue")

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: NWConnection?
    private var pendingIncoming: NWConnection?
    private var decoder = MessageFraming.Decoder()

    init() {
        let name = WKInterfaceDevice.current().name
        self.displayName = name.isEmpty ? "Apple Watch" : name
        self.bonjourType = "_\(GameConstants.mcServiceType)._tcp"

        var cont: AsyncStream<NetworkMessage>.Continuation!
        self.incomingMessages = AsyncStream { cont = $0 }
        self.messageContinuation = cont
    }

    // MARK: - Advertising

    func startAdvertising() {
        stopAdvertising()
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        var txtRecord = NWTXTRecord()
        txtRecord["name"] = displayName
        do {
            let l = try NWListener(using: params)
            l.service = NWListener.Service(
                name: nil,
                type: bonjourType,
                domain: nil,
                txtRecord: txtRecord
            )
            l.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }
            l.start(queue: queue)
            self.listener = l
            self.connectionState = .discovering
        } catch {
            self.connectionState = .failed("listener: \(error.localizedDescription)")
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Browsing

    func startBrowsing() {
        stopBrowsing()
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: bonjourType, domain: nil)
        let b = NWBrowser(for: descriptor, using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.updateDiscoveredPeers(from: results)
            }
        }
        b.start(queue: queue)
        self.browser = b
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func updateDiscoveredPeers(from results: Set<NWBrowser.Result>) {
        var peers: [DiscoveredPeer] = []
        for result in results {
            if case .bonjour(let txt) = result.metadata {
                let name = txt["name"] ?? displayFallback(for: result.endpoint)
                if name == self.displayName { continue }
                let id = endpointID(result.endpoint)
                peers.append(DiscoveredPeer(id: id, displayName: name, endpoint: result.endpoint))
            } else {
                let name = displayFallback(for: result.endpoint)
                if name == self.displayName { continue }
                let id = endpointID(result.endpoint)
                peers.append(DiscoveredPeer(id: id, displayName: name, endpoint: result.endpoint))
            }
        }
        self.discoveredPeers = peers
    }

    private func endpointID(_ endpoint: NWEndpoint) -> String {
        if case .service(let name, let type, let domain, _) = endpoint {
            return "\(name).\(type).\(domain)"
        }
        return "\(endpoint)"
    }

    private func displayFallback(for endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint { return name }
        return "Apple Watch"
    }

    // MARK: - Invite (outgoing)

    func invite(_ peer: DiscoveredPeer) {
        disconnectActive()
        self.role = .host
        self.connectionState = .inviting(peer)

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let c = NWConnection(to: peer.endpoint, using: params)
        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleOutgoingState(state, for: peer, connection: c)
            }
        }
        c.start(queue: queue)
        self.activeConnection = c
        receiveLoop(on: c)
    }

    private func handleOutgoingState(
        _ state: NWConnection.State,
        for peer: DiscoveredPeer,
        connection: NWConnection
    ) {
        switch state {
        case .ready:
            self.connectionState = .connected(peer: peer, role: .host)
        case .failed(let err):
            self.connectionState = .failed(err.localizedDescription)
            self.role = nil
        case .cancelled:
            if case .connected = self.connectionState {
                self.connectionState = .disconnected
            }
        default:
            break
        }
    }

    // MARK: - Invite (incoming)

    private func handleIncomingConnection(_ connection: NWConnection) {
        guard activeConnection == nil, pendingIncoming == nil else {
            connection.cancel()
            return
        }
        let peerName = displayFallback(for: connection.endpoint)
        self.pendingIncoming = connection
        self.connectionState = .receivingInvite(fromDisplayName: peerName)
    }

    func respondToInvite(accept: Bool) {
        guard let connection = pendingIncoming else { return }
        self.pendingIncoming = nil
        if accept {
            self.role = .client
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleIncomingState(state, connection: connection)
                }
            }
            connection.start(queue: queue)
            self.activeConnection = connection
            receiveLoop(on: connection)
        } else {
            connection.cancel()
            self.connectionState = .discovering
        }
    }

    private func handleIncomingState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            let peerName = displayFallback(for: connection.endpoint)
            let id = endpointID(connection.endpoint)
            let peer = DiscoveredPeer(id: id, displayName: peerName, endpoint: connection.endpoint)
            self.connectionState = .connected(peer: peer, role: .client)
        case .failed(let err):
            self.connectionState = .failed(err.localizedDescription)
            self.role = nil
        case .cancelled:
            if case .connected = self.connectionState {
                self.connectionState = .disconnected
            }
        default:
            break
        }
    }

    // MARK: - Receive loop + framing

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    let messages = self.decoder.feed(data)
                    for msg in messages {
                        self.messageContinuation.yield(msg)
                    }
                }
                if error != nil || isComplete {
                    self.disconnectActive()
                    return
                }
                self.receiveLoop(on: connection)
            }
        }
    }

    // MARK: - Send

    func send(_ message: NetworkMessage, reliable: Bool) {
        guard let connection = activeConnection, isReady(connection) else { return }
        do {
            let framed = try MessageFraming.encode(message)
            connection.send(content: framed, completion: .contentProcessed { _ in })
        } catch {
            // Encode failure is not recoverable for this message; drop silently.
        }
    }

    private func isReady(_ connection: NWConnection) -> Bool {
        if case .ready = connection.state { return true }
        return false
    }

    // MARK: - Disconnect

    func disconnect() {
        disconnectActive()
        stopAdvertising()
        stopBrowsing()
        self.connectionState = .idle
        self.role = nil
        self.discoveredPeers = []
    }

    private func disconnectActive() {
        activeConnection?.cancel()
        activeConnection = nil
        pendingIncoming?.cancel()
        pendingIncoming = nil
        decoder = MessageFraming.Decoder()
    }
}
