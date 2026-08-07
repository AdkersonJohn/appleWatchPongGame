import Foundation
import Network
import WatchKit
import Combine

/// Who a browse result belongs to. Kept free of Network types so it can be
/// tested without standing up a real browser.
enum PeerIdentity {
    /// True when a browse result is our own advertised service.
    ///
    /// Identity is the per-launch instance id carried in the TXT record, *not*
    /// the display name: two stock watches report the same device name, so a
    /// name comparison makes each side classify the other as itself and hide
    /// it — leaving both players staring at an empty lobby.
    static func isSelf(txtID: String?, myID: String) -> Bool {
        guard let txtID else { return false }  // unknown identity: show it; a duplicate row beats an empty list
        return txtID == myID
    }
}

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
    /// Unique per app launch. Advertised in the TXT record so we can recognise
    /// our own service without relying on the display name.
    private let instanceID = UUID().uuidString
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

        MPDiag.shared.event("init name=\"\(self.displayName)\" id=\(instanceID.prefix(8)) type=\(bonjourType)")
    }

    // MARK: - Advertising

    func startAdvertising() {
        // Don't restart while a connection is live or being received — would
        // overwrite connectionState back to .discovering and tear down the link.
        if activeConnection != nil || pendingIncoming != nil { return }
        stopAdvertising()
        MPDiag.shared.event("advertise: starting")
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        var txtRecord = NWTXTRecord()
        txtRecord["name"] = displayName
        txtRecord["id"] = instanceID
        do {
            let l = try NWListener(using: params)
            l.service = NWListener.Service(
                name: nil,
                type: bonjourType,
                domain: nil,
                txtRecord: txtRecord
            )
            // Without these two handlers a listener that never publishes looks
            // exactly like one that published fine — the failure that hid this
            // bug in the first place.
            l.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .setup:            MPDiag.shared.event("advertise: setup")
                    case .ready:            MPDiag.shared.event("advertise: READY")
                    case .waiting(let e):   MPDiag.shared.event("advertise: WAITING \(e)")
                    case .failed(let e):    MPDiag.shared.event("advertise: FAILED \(e)")
                    case .cancelled:        MPDiag.shared.event("advertise: cancelled")
                    @unknown default:       MPDiag.shared.event("advertise: unknown state")
                    }
                }
            }
            l.serviceRegistrationUpdateHandler = { change in
                Task { @MainActor in
                    switch change {
                    case .add(let endpoint):    MPDiag.shared.event("advertise: PUBLISHED \(endpoint)")
                    case .remove(let endpoint): MPDiag.shared.event("advertise: withdrawn \(endpoint)")
                    @unknown default:           MPDiag.shared.event("advertise: unknown registration")
                    }
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    MPDiag.shared.event("incoming connection from \(connection.endpoint)")
                    self?.handleIncomingConnection(connection)
                }
            }
            l.start(queue: queue)
            self.listener = l
            self.connectionState = .discovering
        } catch {
            MPDiag.shared.event("advertise: listener init threw \(error)")
            self.connectionState = .failed("listener: \(error.localizedDescription)")
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Browsing

    func startBrowsing() {
        // Don't restart browsing once we have a connection — pointless and
        // could re-fire result handlers in racy ways.
        if activeConnection != nil || pendingIncoming != nil { return }
        stopBrowsing()
        MPDiag.shared.event("browse: starting")
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: bonjourType, domain: nil)
        let b = NWBrowser(for: descriptor, using: params)
        // A denied local-network permission parks the browser in .waiting
        // forever and browseResultsChangedHandler simply never fires, so this
        // handler is the only place that failure is observable.
        b.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .setup:            MPDiag.shared.event("browse: setup")
                case .ready:            MPDiag.shared.event("browse: READY")
                case .waiting(let e):   MPDiag.shared.event("browse: WAITING \(e) — check local network permission")
                case .failed(let e):    MPDiag.shared.event("browse: FAILED \(e)")
                case .cancelled:        MPDiag.shared.event("browse: cancelled")
                @unknown default:       MPDiag.shared.event("browse: unknown state")
                }
            }
        }
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
        MPDiag.shared.event("browse: \(results.count) raw result(s)")
        var peers: [DiscoveredPeer] = []
        for result in results {
            var txtID: String? = nil
            var name: String
            if case .bonjour(let txt) = result.metadata {
                txtID = txt["id"]
                name = txt["name"] ?? displayFallback(for: result.endpoint)
            } else {
                name = displayFallback(for: result.endpoint)
                MPDiag.shared.event("  · no TXT record on \(result.endpoint)")
            }

            if PeerIdentity.isSelf(txtID: txtID, myID: instanceID) {
                MPDiag.shared.event("  · self, hidden (\(name))")
                continue
            }
            // The counterfactual: this is what the old name-based check would
            // have done. If this fires, the empty lobby is explained.
            if name == self.displayName {
                MPDiag.shared.event("  · NAME COLLISION with us — old build would have hidden this peer")
            }
            let id = endpointID(result.endpoint)
            MPDiag.shared.event("  · peer \"\(name)\" id=\(txtID?.prefix(8) ?? "none")")
            peers.append(DiscoveredPeer(id: id, displayName: name, endpoint: result.endpoint))
        }
        MPDiag.shared.event("browse: showing \(peers.count) peer(s)")
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
        MPDiag.shared.event("invite -> \(peer.displayName)")
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
        MPDiag.shared.event("outgoing: \(state) -> \(peer.displayName)")
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
        MPDiag.shared.event("incoming: \(state)")
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
