import Foundation
import Network
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif
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
    ///
    /// A result can arrive before its TXT record resolves, which leaves no id
    /// at all. Falling back to the endpoint we ourselves published keeps that
    /// window from listing us as our own opponent.
    static func isSelf(txtID: String?, endpointID: String, myID: String, myEndpointID: String?) -> Bool {
        if let txtID { return txtID == myID }
        guard let myEndpointID else { return false }  // unknown either way: show it; a duplicate row beats an empty list
        return endpointID == myEndpointID
    }
}

/// Holds on to peers that have briefly dropped out of the browse results.
///
/// Bonjour over AWDL flaps: a watch sitting a foot away resolves, un-resolves,
/// and vanishes from the result set within a couple of seconds, then comes
/// back. Rebuilding the list from each callback makes the row disappear from
/// under the player's finger mid-tap, which is what an empty lobby actually
/// looked like on two real watches.
struct PeerCache {
    static let graceSeconds: TimeInterval = 10

    private var seen: [String: (peer: DiscoveredPeer, at: Date)] = [:]

    /// Returns the peers to show: everything seen within the grace window,
    /// ordered stably so rows don't jump around between callbacks.
    // ponytail: pruning only happens when the browser calls back, so the last
    // peer can linger past the window. Add a timer if a stale row bites.
    mutating func merge(_ fresh: [DiscoveredPeer], now: Date) -> [DiscoveredPeer] {
        for peer in fresh { seen[peer.id] = (peer, now) }
        seen = seen.filter { now.timeIntervalSince($0.value.at) < Self.graceSeconds }
        return seen.values
            .sorted { ($0.peer.displayName, $0.peer.id) < ($1.peer.displayName, $1.peer.id) }
            .map(\.peer)
    }

    mutating func removeAll() { seen.removeAll() }
}

@MainActor
final class MultiplayerService: MultiplayerServiceProtocol {
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var lastIssue: String? = nil
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
    /// The endpoint our own listener published, learned from the registration
    /// handler. Used to recognise ourselves before the TXT record resolves.
    private var myEndpointID: String?
    private var peerCache = PeerCache()
    private var activeConnection: NWConnection?
    private var pendingIncoming: NWConnection?
    private var decoder = MessageFraming.Decoder()

    init() {
        #if os(watchOS)
        let name = WKInterfaceDevice.current().name
        #else
        let name = UIDevice.current.name
        #endif
        self.displayName = name.isEmpty ? "Apple Watch" : name
        self.bonjourType = "_\(GameConstants.mcServiceType)._tcp"

        var cont: AsyncStream<NetworkMessage>.Continuation!
        self.incomingMessages = AsyncStream { cont = $0 }
        self.messageContinuation = cont

        MPDiag.shared.lastIssueSink = { [weak self] raw in
            Task { @MainActor in self?.lastIssue = MPIssue.hint(raw) }
        }
        MPDiag.shared.event("init name=\"\(self.displayName)\" id=\(instanceID.prefix(8)) type=\(bonjourType)")
    }

    // MARK: - Advertising

    func startAdvertising() {
        // Don't restart while a connection is live or being received — would
        // overwrite connectionState back to .discovering and tear down the link.
        if activeConnection != nil || pendingIncoming != nil { return }
        // Already published? Leave it alone. Tearing the listener down and
        // rebuilding it withdraws the Bonjour service, and the lobby view's
        // onAppear fires again every time the diagnostics sheet is dismissed.
        if listener != nil { return }
        MPDiag.shared.event("advertise: starting")
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        var txtRecord = NWTXTRecord()
        txtRecord["name"] = displayName
        txtRecord["id"] = instanceID
        // Tells the other side what it found, and catches a build mismatch —
        // the likeliest reason a watch and a phone connect but never play.
        txtRecord["plat"] = MPDiag.platformTag
        txtRecord["proto"] = String(GameConstants.multiplayerProtocolVersion)
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
                    case .ready:
                        MPDiag.shared.event("advertise: READY")
                    case .waiting(let e):
                        MPDiag.shared.event("advertise: WAITING \(e)")
                        MPDiag.shared.lastIssueSink?("\(e)")
                    case .failed(let e):
                        MPDiag.shared.event("advertise: FAILED \(e)")
                        MPDiag.shared.lastIssueSink?("\(e)")
                    case .cancelled:        MPDiag.shared.event("advertise: cancelled")
                    @unknown default:       MPDiag.shared.event("advertise: unknown state")
                    }
                }
            }
            l.serviceRegistrationUpdateHandler = { [weak self] change in
                Task { @MainActor in
                    switch change {
                    case .add(let endpoint):
                        self?.myEndpointID = self?.endpointID(endpoint)
                        MPDiag.shared.event("advertise: PUBLISHED \(endpoint)")
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
        if browser != nil { return }
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
                case .ready:
                    MPDiag.shared.event("browse: READY")
                case .waiting(let e):
                    MPDiag.shared.event("browse: WAITING \(e) — check local network permission")
                    MPDiag.shared.lastIssueSink?("\(e)")
                case .failed(let e):
                    MPDiag.shared.event("browse: FAILED \(e)")
                    MPDiag.shared.lastIssueSink?("\(e)")
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
        var fresh: [DiscoveredPeer] = []
        for result in results {
            var txtID: String? = nil
            var txtName: String? = nil
            var txtPlat: String? = nil
            var txtProto: String? = nil
            if case .bonjour(let txt) = result.metadata {
                txtID = txt["id"]
                txtName = txt["name"]
                txtPlat = txt["plat"]
                txtProto = txt["proto"]
            } else {
                MPDiag.shared.event("  · no TXT record on \(result.endpoint)")
            }
            let id = endpointID(result.endpoint)
            // Bonjour's service instance name carries the *real* device name
            // ("Tarique's Apple Watch"); WKInterfaceDevice.name — what the TXT
            // record holds — is the generic "Apple Watch" on modern watchOS.
            // Prefer the endpoint so players can tell each other apart.
            let name = serviceName(for: result.endpoint) ?? txtName ?? "Apple Watch"

            if PeerIdentity.isSelf(txtID: txtID, endpointID: id,
                                   myID: instanceID, myEndpointID: myEndpointID) {
                MPDiag.shared.event("  · self, hidden (\(name))")
                continue
            }
            let plat = txtPlat ?? "?"
            MPDiag.shared.event("  · peer \"\(name)\" [\(plat)] id=\(txtID?.prefix(8) ?? "none") proto=\(txtProto ?? "?")")
            if let txtProto, let theirs = UInt8(txtProto), !ProtoCheck.isCompatible(theirs) {
                MPDiag.shared.event("  · MISMATCH proto \(theirs) vs ours \(GameConstants.multiplayerProtocolVersion) — update one device")
            }
            fresh.append(DiscoveredPeer(id: id, displayName: name, endpoint: result.endpoint, platform: txtPlat))
        }
        let shown = peerCache.merge(fresh, now: Date())
        let held = shown.count - fresh.count
        MPDiag.shared.event("browse: showing \(shown.count) peer(s)\(held > 0 ? " (\(held) held)" : "")")
        if !shown.isEmpty { self.lastIssue = nil }
        self.discoveredPeers = shown
    }

    /// Which physical link the match is actually running over. On a
    /// watch-to-phone test this is the difference between "same Wi-Fi" and
    /// AWDL peer-to-peer, and it decides what to change when it fails.
    private func logPath(_ connection: NWConnection, tag: String) {
        guard let path = connection.currentPath else {
            MPDiag.shared.event("\(tag): no path yet")
            return
        }
        let ifaces = path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
        MPDiag.shared.event("\(tag): via [\(ifaces)] expensive=\(path.isExpensive) constrained=\(path.isConstrained)")
        if let remote = path.remoteEndpoint { MPDiag.shared.event("\(tag): remote \(remote)") }
    }

    private func endpointID(_ endpoint: NWEndpoint) -> String {
        if case .service(let name, let type, let domain, _) = endpoint {
            return "\(name).\(type).\(domain)"
        }
        return "\(endpoint)"
    }

    /// Bonjour escapes spaces on the wire as `\032`; undo that for display.
    private func serviceName(for endpoint: NWEndpoint) -> String? {
        guard case .service(let name, _, _, _) = endpoint else { return nil }
        return name.replacingOccurrences(of: "\\032", with: " ")
    }

    private func displayFallback(for endpoint: NWEndpoint) -> String {
        serviceName(for: endpoint) ?? "Apple Watch"
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
            logPath(connection, tag: "outgoing")
            MPDiag.shared.event("CONNECTED as host to \(peer.displayName) [\(peer.platform ?? "?")]")
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
        MPDiag.shared.event("invite received from \(peerName)")
        self.pendingIncoming = connection
        self.connectionState = .receivingInvite(fromDisplayName: peerName)
    }

    func respondToInvite(accept: Bool) {
        MPDiag.shared.event("invite \(accept ? "accepted" : "declined")")
        guard let connection = pendingIncoming else {
            MPDiag.shared.event("  · no pending connection to respond to")
            return
        }
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
            logPath(connection, tag: "incoming")
            let peerName = displayFallback(for: connection.endpoint)
            MPDiag.shared.event("CONNECTED as client to \(peerName)")
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
                    let before = self.decoder.failureCount
                    let messages = self.decoder.feed(data)
                    if self.decoder.failureCount > before {
                        MPDiag.shared.event("rx UNDECODABLE payload (\(self.decoder.failureCount) total) — build mismatch?")
                    }
                    for msg in messages {
                        if Self.isHighRate(msg) {
                            MPDiag.shared.tally("rx \(Self.kind(msg))")
                        } else {
                            MPDiag.shared.event("rx \(Self.kind(msg))")
                        }
                        self.messageContinuation.yield(msg)
                    }
                }
                if let error {
                    MPDiag.shared.event("rx FAILED \(error) — link dropped")
                    self.disconnectActive()
                    return
                }
                if isComplete {
                    MPDiag.shared.event("rx stream closed by peer")
                    self.disconnectActive()
                    return
                }
                self.receiveLoop(on: connection)
            }
        }
    }

    // MARK: - Send

    func send(_ message: NetworkMessage, reliable: Bool) {
        guard let connection = activeConnection, isReady(connection) else {
            MPDiag.shared.event("send \(Self.kind(message)) DROPPED — no ready connection")
            return
        }
        do {
            let framed = try MessageFraming.encode(message)
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    Task { @MainActor in MPDiag.shared.event("send FAILED \(Self.kind(message)): \(error)") }
                }
            })
            // Snapshots and paddle input run at 30Hz; only the rare, meaningful
            // messages get a line of their own.
            if Self.isHighRate(message) {
                MPDiag.shared.tally("tx \(Self.kind(message))")
            } else {
                MPDiag.shared.event("send \(Self.kind(message))")
            }
        } catch {
            MPDiag.shared.event("send ENCODE FAILED \(Self.kind(message)): \(error)")
        }
    }

    static func kind(_ m: NetworkMessage) -> String {
        switch m {
        case .snapshot:      return "snapshot"
        case .paddleInput:   return "paddleInput"
        case .rematchRequest:return "rematchRequest"
        case .endMatch:      return "endMatch"
        case .paused:        return "paused"
        case .resumed:       return "resumed"
        case .forfeit:       return "forfeit"
        case .startMatch:    return "startMatch"
        case .clientReady:   return "clientReady"
        case .stickyRelease: return "stickyRelease"
        }
    }

    static func isHighRate(_ m: NetworkMessage) -> Bool {
        switch m {
        case .snapshot, .paddleInput: return true
        default: return false
        }
    }

    private func isReady(_ connection: NWConnection) -> Bool {
        if case .ready = connection.state { return true }
        return false
    }

    // MARK: - Disconnect

    func disconnect() {
        MPDiag.shared.event("disconnect requested")
        MPDiag.shared.flushTallies()
        disconnectActive()
        stopAdvertising()
        stopBrowsing()
        self.connectionState = .idle
        self.role = nil
        peerCache.removeAll()
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
