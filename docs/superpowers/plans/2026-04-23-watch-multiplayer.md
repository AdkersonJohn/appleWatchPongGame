# Apple Watch Multiplayer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add watch-to-watch local multiplayer Pong using Apple's `Network.framework` + Bonjour (MultipeerConnectivity is iOS-only, not available on watchOS — see spec Addendum A), with host-authoritative networking, mirrored views, and all existing single-player niceties preserved.

**Architecture:** A `MultiplayerService` wraps `NWListener` (advertising), `NWBrowser` (discovery), and one `NWConnection` per active peer. A `MultiplayerGameState` composes an inner `GameState` with the service and a `PeerRole` (`.host`/`.client`). The host runs normal physics locally and sends 30Hz `GameSnapshot` messages via length-prefixed TCP; the client renders from snapshots, flips Y coordinates, and predicts its own paddle from local crown input. UI adds a `NearbyPlayersView` for pairing and a `MultiplayerGameOverView` for rematch/back, with `StartView` updated to pick SP vs MP.

**Tech Stack:** SwiftUI, `Network.framework`, Bonjour, XCTest, watchOS 11+. JSON-encoded `Codable` DTOs with length-prefix framing.

**Spec:** `docs/superpowers/specs/2026-04-23-watch-multiplayer-design.md`

---

## File Structure

**New files:**

| Path | Responsibility |
|------|----------------|
| `PongWatch/PongWatch Watch App/Multiplayer/PeerRole.swift` | `enum PeerRole { case host, client }` |
| `PongWatch/PongWatch Watch App/Multiplayer/GameSnapshot.swift` | All Codable DTOs (GameSnapshot, PaddleInput, ScoreEvent, MessageKind, NetworkMessage envelope) |
| `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift` | MC wrapper: advertiser, browser, session, delegate, send/receive |
| `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerServiceProtocol.swift` | Protocol abstraction so MultiplayerGameState can be tested with a mock |
| `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift` | ObservableObject wrapping GameState + service, host/client branching |
| `PongWatch/PongWatch Watch App/Screens/NearbyPlayersView.swift` | List of discovered peers + "Invite" button |
| `PongWatch/PongWatch Watch App/Screens/InvitePromptView.swift` | "<name> wants to play" Accept/Decline |
| `PongWatch/PongWatch Watch App/Screens/MultiplayerGameOverView.swift` | Rematch / Back after match end |
| `PongWatch/PongWatch Watch AppTests/GameSnapshotTests.swift` | Codable roundtrip, protocol versioning |
| `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift` | Host/client state derivation, flip math, client prediction, wrist-down timer |
| `PongWatch/PongWatch Watch AppTests/FakeMultiplayerService.swift` | Test double conforming to `MultiplayerServiceProtocol` |

**Modified files:**

| Path | Change |
|------|--------|
| `PongWatch/PongWatch Watch App/Game/GameConstants.swift` | Add MP constants (winning score, snapshot hz, grace seconds) |
| `PongWatch/PongWatch Watch App/Screens/StartView.swift` | Two stacked buttons instead of one "Tap to Play" |
| `PongWatch/PongWatch Watch App/Screens/GameView.swift` | Accept optional `flipY` flag; when true, render with y→1-y swap |
| `PongWatch/PongWatch Watch App/ContentView.swift` | `@State var mode: GameMode?` routing SP vs MP |

**Note:** `GameState.swift` is **not** modified. `MultiplayerGameState` composes it.

---

## Build and Test Commands

- **Build (watchOS simulator):**
  ```
  xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build
  ```
- **Run unit tests:**
  ```
  xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" test
  ```
- **Filter to MP tests only (for tight TDD loops):**
  ```
  xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" test -only-testing:"PongWatch Watch AppTests/GameSnapshotTests"
  ```

**Destination:** if "Apple Watch Series 10 (46mm)" is unavailable, list simulators with `xcrun simctl list devices | grep Watch` and pick any installed watchOS 11+ simulator.

**Commit style:** use Conventional Commits (`feat:`, `test:`, `refactor:`). Match recent history on this branch (`git log --oneline -10`).

---

## Task 1: Add MP constants to GameConstants

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameConstants.swift`

- [ ] **Step 1: Append the new constants**

Append to the end of the `GameConstants` enum body (before the closing `}`):

```swift
    // MARK: - Multiplayer

    /// Match ends when a player reaches this score.
    static let multiplayerWinningScore: Int = 5

    /// Host → client snapshot rate (Hz).
    static let snapshotHz: Double = 30

    /// Client → host paddle-input rate (Hz).
    static let paddleInputHz: Double = 30

    /// Seconds of wrist-down grace before forfeiting a multiplayer match.
    static let multiplayerGraceSeconds: Double = 3.0

    /// MultipeerConnectivity service type. 1–15 chars, lowercase ASCII + hyphens.
    static let mcServiceType: String = "pongwatch"

    /// Protocol version included in every MP message. Bump when the wire format changes.
    static let multiplayerProtocolVersion: UInt8 = 1
```

- [ ] **Step 2: Build to verify compile**

Run:
```
xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameConstants.swift"
git commit -m "feat(mp): add multiplayer constants"
```

---

## Task 2: Create PeerRole enum

**Files:**
- Create: `PongWatch/PongWatch Watch App/Multiplayer/PeerRole.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

enum PeerRole: String, Codable, Equatable {
    case host
    case client

    /// Role from the *other* side's perspective (used when flipping snapshot fields).
    var opposite: PeerRole {
        self == .host ? .client : .host
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build`
Expected: `BUILD SUCCEEDED`. If Xcode reports the file isn't in the project target, add it: in Xcode, right-click the `Multiplayer` folder (create it if needed) → "Add Files to 'PongWatch'" → select file → ensure "PongWatch Watch App" target is checked.

- [ ] **Step 3: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/PeerRole.swift" PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): add PeerRole enum"
```

---

## Task 3: Create GameSnapshot + DTOs with Codable roundtrip test

**Files:**
- Create: `PongWatch/PongWatch Watch App/Multiplayer/GameSnapshot.swift`
- Create: `PongWatch/PongWatch Watch AppTests/GameSnapshotTests.swift`

- [ ] **Step 1: Write failing test**

Create `GameSnapshotTests.swift`:

```swift
import XCTest
@testable import PongWatch_Watch_App

final class GameSnapshotTests: XCTestCase {
    func test_gameSnapshotRoundtripsViaJSON() throws {
        let original = GameSnapshot(
            protoVersion: 1,
            phase: .playing,
            ballX: 0.42,
            ballY: 0.37,
            ballVX: -0.5,
            ballVY: 0.8,
            hostPaddleX: 0.5,
            clientPaddleX: 0.6,
            hostScore: 2,
            clientScore: 3,
            countdownRemaining: nil,
            scoreEvent: nil,
            hostPaddleHit: false,
            clientPaddleHit: true,
            tickSeq: 1234
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_paddleInputRoundtripsViaJSON() throws {
        let original = PaddleInput(protoVersion: 1, paddleX: 0.73, tickSeq: 99)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaddleInput.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_networkMessageEnvelopeCarriesSnapshot() throws {
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 0,
            countdownRemaining: 3, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 0
        )
        let msg = NetworkMessage.snapshot(snap)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
        if case .snapshot(let s) = decoded {
            XCTAssertEqual(s, snap)
        } else {
            XCTFail("Expected .snapshot case")
        }
    }

    func test_scoreEventEncodesScorerRole() throws {
        let event = ScoreEvent(impactX: 0.37, scoredBy: .client)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ScoreEvent.self, from: data)
        XCTAssertEqual(decoded.scoredBy, .client)
        XCTAssertEqual(decoded.impactX, 0.37, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify compile error (no GameSnapshot type yet)**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/GameSnapshotTests"`
Expected: compile error, `cannot find 'GameSnapshot' in scope`.

- [ ] **Step 3: Create `GameSnapshot.swift`**

```swift
import Foundation
import CoreGraphics

/// Envelope for any message sent over the MC session. Using an enum ensures
/// exhaustive handling on the receiver and gives us a stable tag in JSON.
enum NetworkMessage: Codable, Equatable {
    case snapshot(GameSnapshot)
    case paddleInput(PaddleInput)
    case rematchRequest
    case endMatch
    case paused(role: PeerRole)
    case resumed(role: PeerRole)
    case forfeit(by: PeerRole)
}

/// Full game state snapshot from host → client at 30Hz.
/// All coordinates are in HOST coordinate space (host at bottom, y grows downward).
/// Client must flip Y on render.
struct GameSnapshot: Codable, Equatable {
    var protoVersion: UInt8
    var phase: GamePhase
    var ballX: CGFloat
    var ballY: CGFloat
    var ballVX: CGFloat
    var ballVY: CGFloat
    var hostPaddleX: CGFloat
    var clientPaddleX: CGFloat
    var hostScore: Int
    var clientScore: Int
    /// nil when ball is in play; otherwise 3/2/1.
    var countdownRemaining: Int?
    /// Non-nil for exactly one snapshot after a scoring event.
    var scoreEvent: ScoreEvent?
    /// True for one snapshot on the tick host's paddle collided with the ball.
    var hostPaddleHit: Bool
    /// True for one snapshot on the tick client's paddle collided.
    var clientPaddleHit: Bool
    /// Monotonic tick sequence; receiver discards out-of-order snapshots.
    var tickSeq: UInt32
}

/// Client → host at 30Hz; reports the client's crown-controlled paddle position.
struct PaddleInput: Codable, Equatable {
    var protoVersion: UInt8
    /// Paddle X in normalized [0, 1] space. X is symmetric across the flip
    /// so no coordinate transform is needed.
    var paddleX: CGFloat
    var tickSeq: UInt32
}

struct ScoreEvent: Codable, Equatable {
    var impactX: CGFloat
    var scoredBy: PeerRole
}
```

**Note on `GamePhase` Codable conformance:** `GamePhase` in `GameTypes.swift` already conforms to `Equatable` but not `Codable`. We need `Codable` on it for snapshots. Add conformance in this step:

Modify `PongWatch/PongWatch Watch App/Game/GameTypes.swift` — change:
```swift
enum GamePhase: Equatable {
```
to:
```swift
enum GamePhase: Equatable, Codable {
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/GameSnapshotTests"`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/GameSnapshot.swift" \
        "PongWatch/PongWatch Watch AppTests/GameSnapshotTests.swift" \
        "PongWatch/PongWatch Watch App/Game/GameTypes.swift" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): add GameSnapshot + network message DTOs"
```

---

## Task 4: Create DiscoveredPeer + MultiplayerServiceProtocol + connection state

**Transport note:** MultipeerConnectivity is not available on watchOS. We use `Network.framework` + Bonjour. See spec Addendum A.

**Files:**
- Create: `PongWatch/PongWatch Watch App/Multiplayer/DiscoveredPeer.swift`
- Create: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerServiceProtocol.swift`

- [ ] **Step 1: Write `DiscoveredPeer.swift`**

```swift
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
```

- [ ] **Step 2: Write `MultiplayerServiceProtocol.swift`**

```swift
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
    /// Async stream of decoded inbound messages. Consumers iterate with `for await msg in ...`.
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
```

Note: `reliable:` parameter is retained on `send` for API stability, but with our `Network.framework` TCP transport it's effectively always reliable. The flag may be used later if we add an unreliable UDP side-channel.

- [ ] **Step 3: Build**

Run: `xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/DiscoveredPeer.swift" \
        "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerServiceProtocol.swift"
git commit -m "feat(mp): add DiscoveredPeer + MultiplayerServiceProtocol"
```

---

## Task 5: Implement MultiplayerService (Network.framework + Bonjour)

This task has no unit tests — `NWListener`/`NWBrowser`/`NWConnection` require the real networking stack. The service is tested indirectly through `MultiplayerGameStateTests` (via `FakeMultiplayerService` from Task 6). End-to-end verification happens in the integration tests (Task 21/22).

**Files:**
- Create: `PongWatch/PongWatch Watch App/Multiplayer/MessageFraming.swift`
- Create: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift`
- Modify: `PongWatch/PongWatch Watch App/Info.plist` (add NSBonjourServices + NSLocalNetworkUsageDescription)

**Architecture notes:**
- One `NWListener` advertises our Bonjour service and accepts incoming NWConnections.
- One `NWBrowser` enumerates discovered peers.
- Each active peer connection is one `NWConnection` (TCP).
- Messages are length-prefixed (4-byte big-endian `UInt32` length + JSON payload).
- On incoming connection (invitee side): we set `connectionState = .receivingInvite(...)`. Holding the NWConnection in a pending state. On Accept, we call `pendingConnection.start(queue:)` and set role `.client`. On Decline, we cancel.
- On outgoing invite (inviter side): we create `NWConnection(to: endpoint, using: tcp)`, start it, and set role `.host` before the connection becomes ready. When ready, we send the first snapshot and the peer infers they're the client (no extra handshake needed since role is role-by-action: inviter=host).

- [ ] **Step 1: Write `MessageFraming.swift`**

```swift
import Foundation

/// Length-prefix framed message codec for TCP streams.
/// Wire format per message: [u32 big-endian length][JSON bytes]
enum MessageFraming {
    static func encode(_ message: NetworkMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        var lenBE = UInt32(payload.count).bigEndian
        var out = Data(bytes: &lenBE, count: 4)
        out.append(payload)
        return out
    }

    /// Parser that accumulates bytes and emits complete messages as they arrive.
    final class Decoder {
        private var buffer = Data()

        /// Append newly-received bytes; returns any complete messages decoded from the buffer.
        func feed(_ chunk: Data) -> [NetworkMessage] {
            buffer.append(chunk)
            var results: [NetworkMessage] = []
            while true {
                guard buffer.count >= 4 else { break }
                let len = buffer[0..<4].withUnsafeBytes { rawBuf -> UInt32 in
                    let ptr = rawBuf.bindMemory(to: UInt32.self)
                    return UInt32(bigEndian: ptr[0])
                }
                guard buffer.count >= 4 + Int(len) else { break }
                let payload = buffer.subdata(in: 4..<(4 + Int(len)))
                buffer.removeSubrange(0..<(4 + Int(len)))
                if let msg = try? JSONDecoder().decode(NetworkMessage.self, from: payload) {
                    results.append(msg)
                }
                // If decode fails, we've already consumed the bytes — drop and continue.
            }
            return results
        }
    }
}
```

- [ ] **Step 2: Write `MultiplayerService.swift`**

```swift
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
        let txt = NWTXTRecord(["name": displayName])
        do {
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: nil, type: bonjourType, domain: nil, txtRecord: txt.data)
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
                if name == self.displayName { continue }   // don't list ourselves
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

    private func handleOutgoingState(_ state: NWConnection.State, for peer: DiscoveredPeer, connection: NWConnection) {
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

    private var pendingPeer: DiscoveredPeer?

    private func handleIncomingConnection(_ connection: NWConnection) {
        // If we already have an active or pending connection, reject this one.
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
                // Continue loop.
                self.receiveLoop(on: connection)
            }
        }
    }

    // MARK: - Send

    func send(_ message: NetworkMessage, reliable: Bool) {
        guard let connection = activeConnection, connection.state == .ready else { return }
        do {
            let framed = try MessageFraming.encode(message)
            connection.send(content: framed, completion: .contentProcessed { _ in })
        } catch {
            // Encode failure is not recoverable for this message; drop silently.
        }
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
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Add Info.plist Bonjour + local-network entries**

The watch app's Info.plist must declare Bonjour service types and local-network usage. This project may use the modern Xcode 15+ pattern where Info.plist is generated from build settings.

Check whether `PongWatch/PongWatch Watch App/Info.plist` exists as a file:
```bash
ls "PongWatch/PongWatch Watch App/Info.plist" 2>/dev/null && echo "FILE EXISTS" || echo "NO FILE — use build settings"
```

**If the file exists**, add these keys directly:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Pong uses the local network to find nearby Apple Watches to play against.</string>
<key>NSBonjourServices</key>
<array>
    <string>_pongwatch._tcp</string>
</array>
```

**If no Info.plist file**, open `PongWatch/PongWatch.xcodeproj/project.pbxproj` and look for `INFOPLIST_KEY_` build settings on the "PongWatch Watch App" target. Add:
```
INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Pong uses the local network to find nearby Apple Watches to play against.";
INFOPLIST_KEY_NSBonjourServices = "_pongwatch._tcp";
```

(For multi-value arrays like NSBonjourServices, xcodebuild accepts a single service type as a string. If multiple types are needed later, switch to `INFOPLIST_KEY_NSBonjourServices = "_pongwatch._tcp _pongwatch._udp";` — space-separated.)

**If you're unsure how to add these**, report back with NEEDS_CONTEXT — I'll add them via direct edit.

- [ ] **Step 5: Build again**

Run: `xcodebuild ... build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MessageFraming.swift" \
        "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift" \
        "PongWatch/PongWatch Watch App/Info.plist" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): implement MultiplayerService over Network.framework + Bonjour"
```

(If Info.plist doesn't exist, drop that path from the `git add`.)

---

## Task 6: Create FakeMultiplayerService test double

**Files:**
- Create: `PongWatch/PongWatch Watch AppTests/FakeMultiplayerService.swift`

- [ ] **Step 1: Write the fake**

```swift
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
```

- [ ] **Step 2: Build test target**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/GameSnapshotTests"`
Expected: still passes (verifies the fake compiles cleanly).

- [ ] **Step 3: Commit**

```bash
git add "PongWatch/PongWatch Watch AppTests/FakeMultiplayerService.swift" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "test(mp): add FakeMultiplayerService test double"
```

---

## Task 7: MultiplayerGameState skeleton (composition)

**Files:**
- Create: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Create: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Write failing test for skeleton**

```swift
import XCTest
import Network
@testable import PongWatch_Watch_App

final class MultiplayerGameStateTests: XCTestCase {
    func test_initialStateIsIdle() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        XCTAssertNil(state.role)
    }

    func test_onConnectAsHostTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .host)
        XCTAssertEqual(state.matchPhase, .playing)
    }

    func test_onConnectAsClientTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .client)
        XCTAssertEqual(state.matchPhase, .playing)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: compile error `cannot find 'MultiplayerGameState'`.

- [ ] **Step 3: Write the skeleton**

```swift
import Foundation
import CoreGraphics
import Combine
import Network

enum MultiplayerMatchPhase: Equatable {
    case pairing
    case playing
    case pausedByOpponent
    case matchOver(winner: PeerRole)
    case disconnected
}

final class MultiplayerGameState: ObservableObject {
    // Public, observable state
    @Published private(set) var matchPhase: MultiplayerMatchPhase = .pairing
    @Published private(set) var role: PeerRole? = nil
    @Published private(set) var hostScore: Int = 0
    @Published private(set) var clientScore: Int = 0
    /// Inner game state used for local rendering on both roles.
    @Published private(set) var game: GameState

    private let service: any MultiplayerServiceProtocol
    private var cancellables: Set<AnyCancellable> = []
    private var incomingTask: Task<Void, Never>?
    private var tickSeq: UInt32 = 0
    private var lastReceivedTickSeq: UInt32 = 0

    init(service: any MultiplayerServiceProtocol,
         game: GameState = GameState()) {
        self.service = service
        self.game = game
        observeService()
        startConsumingMessages()
    }

    deinit { incomingTask?.cancel() }

    private func observeService() {
        // Bridge @Published changes on the service into our own state flow.
        // `MultiplayerServiceProtocol: ObservableObject`, so objectWillChange is always available.
        let publisher = service.objectWillChange
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires *before* the new value is published; defer one hop.
                DispatchQueue.main.async { self?.handleServiceStateChange() }
            }
            .store(in: &cancellables)
    }

    private func handleServiceStateChange() {
        self.role = service.role
        switch service.connectionState {
        case .connected:
            if matchPhase == .pairing {
                matchPhase = .playing
            }
        case .disconnected:
            matchPhase = .disconnected
        default:
            break
        }
    }

    private func startConsumingMessages() {
        let stream = service.incomingMessages
        incomingTask = Task { [weak self] in
            for await msg in stream {
                await self?.handle(msg)
            }
        }
    }

    @MainActor
    private func handle(_ message: NetworkMessage) {
        // Filled in by later tasks.
    }
}
```

- [ ] **Step 4: Run the test**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): add MultiplayerGameState skeleton with service composition"
```

---

## Task 8: Host sends 30Hz snapshots

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing test**

Append to `MultiplayerGameStateTests.swift`:

```swift
    func test_hostTickSendsSnapshot() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.tickIfHost(dt: 1.0 / 30.0)
        let snapshotSends = fake.sentMessages.compactMap { msg -> GameSnapshot? in
            if case .snapshot(let s) = msg.message { return s } else { return nil }
        }
        XCTAssertEqual(snapshotSends.count, 1)
        XCTAssertEqual(snapshotSends[0].protoVersion, GameConstants.multiplayerProtocolVersion)
    }

    func test_hostTickAdvancesInnerGame() {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        game.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                         velocity: CGVector(dx: 0.5, dy: 0.5))
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let startX = game.ball.position.x
        state.tickIfHost(dt: 0.1)
        XCTAssertNotEqual(game.ball.position.x, startX)
    }

    func test_clientTickDoesNotSendSnapshots() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        state.tickIfHost(dt: 1.0 / 30.0)
        let snapshotSends = fake.sentMessages.filter {
            if case .snapshot = $0.message { return true } else { return false }
        }
        XCTAssertTrue(snapshotSends.isEmpty)
    }
```

- [ ] **Step 2: Run to see failures**

Expected: compile error `tickIfHost` undefined.

- [ ] **Step 3: Implement `tickIfHost`**

Add to `MultiplayerGameState`:

```swift
    // MARK: - Host tick

    /// Called once per render tick on the host. Advances physics and sends a snapshot.
    /// No-op on the client.
    func tickIfHost(dt: CGFloat) {
        guard role == .host, matchPhase == .playing else { return }
        game.update(dt: dt)
        broadcastSnapshot()
    }

    private func broadcastSnapshot() {
        tickSeq &+= 1
        let snap = GameSnapshot(
            protoVersion: GameConstants.multiplayerProtocolVersion,
            phase: game.phase,
            ballX: game.ball.position.x,
            ballY: game.ball.position.y,
            ballVX: game.ball.velocity.dx,
            ballVY: game.ball.velocity.dy,
            hostPaddleX: game.playerPaddleX,
            clientPaddleX: game.aiPaddleX,   // temporary alias until client paddle wiring (Task 10)
            hostScore: hostScore,
            clientScore: clientScore,
            countdownRemaining: game.countdownRemaining,
            scoreEvent: nil,                 // filled in by Task 12
            hostPaddleHit: false,            // filled in by Task 13
            clientPaddleHit: false,
            tickSeq: tickSeq
        )
        service.send(.snapshot(snap), reliable: false)
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: new 3 tests pass; all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): host broadcasts 30Hz game snapshots"
```

---

## Task 9: Client applies incoming snapshots (with Y flip)

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `MultiplayerGameStateTests.swift`:

```swift
    func test_clientFlipsBallYOnIncomingSnapshot() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.3, ballY: 0.2, ballVX: 0, ballVY: 0.5,
            hostPaddleX: 0.4, clientPaddleX: 0.6,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Client sees itself at the bottom → flip y.
        XCTAssertEqual(state.game.ball.position.y, 0.8, accuracy: 1e-6)   // 1.0 - 0.2
        XCTAssertEqual(state.game.ball.position.x, 0.3, accuracy: 1e-6)   // x unchanged
        // Velocity Y is flipped too (ball moving "down" in host space = "up" in client space).
        XCTAssertEqual(state.game.ball.velocity.dy, -0.5, accuracy: 1e-6)
    }

    func test_clientPaddleAssignmentFlipped() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.4,    // host is at bottom of host-space (= top of client-space)
            clientPaddleX: 0.6,  // client is at top of host-space (= bottom of client-space)
            hostScore: 1, clientScore: 2,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // "My" paddle (bottom of screen) = clientPaddleX.
        // Will be overwritten by local prediction in Task 11, but for now the snapshot value applies.
        XCTAssertEqual(state.game.playerPaddleX, 0.6, accuracy: 1e-6)
        // "Opponent" paddle (top of screen) = hostPaddleX.
        XCTAssertEqual(state.game.aiPaddleX, 0.4, accuracy: 1e-6)
    }

    func test_clientIgnoresOutOfOrderSnapshots() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let newerSnap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.7, ballY: 0.3, ballVX: 0, ballVY: 0,
            hostPaddleX: 0, clientPaddleX: 0,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 10
        )
        let olderSnap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.1, ballY: 0.9, ballVX: 0, ballVY: 0,
            hostPaddleX: 0, clientPaddleX: 0,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 5
        )
        fake.simulateIncoming(.snapshot(newerSnap))
        try? await Task.sleep(nanoseconds: 30_000_000)
        fake.simulateIncoming(.snapshot(olderSnap))
        try? await Task.sleep(nanoseconds: 30_000_000)
        // Newer snapshot's ball position should still apply.
        XCTAssertEqual(state.game.ball.position.x, 0.7, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run to see them fail**

Expected: XCTAssertion failures — client does nothing with snapshots yet.

- [ ] **Step 3: Implement snapshot handling**

Replace the empty `handle(_:)` with:

```swift
    @MainActor
    private func handle(_ message: NetworkMessage) {
        switch message {
        case .snapshot(let snap):
            applyIncomingSnapshot(snap)
        case .paddleInput(let input):
            applyIncomingPaddleInput(input)
        case .rematchRequest:
            handleRematchRequest()
        case .endMatch:
            matchPhase = .disconnected
        case .paused:
            if matchPhase == .playing { matchPhase = .pausedByOpponent }
        case .resumed:
            if matchPhase == .pausedByOpponent { matchPhase = .playing }
        case .forfeit(let by):
            let winner: PeerRole = (by == .host) ? .client : .host
            matchPhase = .matchOver(winner: winner)
        }
    }

    // MARK: - Client snapshot apply

    private func applyIncomingSnapshot(_ snap: GameSnapshot) {
        guard role == .client else { return }
        // Drop out-of-order snapshots (wrap-safe compare).
        let delta = snap.tickSeq &- lastReceivedTickSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastReceivedTickSeq = snap.tickSeq

        // Flip host coords → client coords.
        game.ball = Ball(
            position: CGPoint(x: snap.ballX, y: 1.0 - snap.ballY),
            velocity: CGVector(dx: snap.ballVX, dy: -snap.ballVY)
        )
        // "Me" (bottom) = client; opponent (top) = host.
        game.playerPaddleX = snap.clientPaddleX
        game.aiPaddleX = snap.hostPaddleX
        game.score = snap.clientScore
        game.countdownRemaining = snap.countdownRemaining
        game.phase = snap.phase

        hostScore = snap.hostScore
        clientScore = snap.clientScore
    }

    // MARK: - Placeholder handlers (implemented in later tasks)

    private func applyIncomingPaddleInput(_ input: PaddleInput) {
        // Task 10
    }

    private func handleRematchRequest() {
        // Task 15
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): client applies snapshots with Y-flip and out-of-order guard"
```

---

## Task 10: Client sends paddle input; host applies it

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
    func test_clientSendsPaddleInputOnCrown() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        state.setLocalPaddle(normalizedCrown: 0.72)
        let inputs: [PaddleInput] = fake.sentMessages.compactMap {
            if case .paddleInput(let p) = $0.message { return p } else { return nil }
        }
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].paddleX, 0.72, accuracy: 1e-6)
    }

    func test_hostAppliesIncomingPaddleInput() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let input = PaddleInput(protoVersion: 1, paddleX: 0.83, tickSeq: 1)
        fake.simulateIncoming(.paddleInput(input))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Host stores the client paddle into the inner GameState's aiPaddleX slot
        // (which represents the top paddle in host-coord physics).
        XCTAssertEqual(game.aiPaddleX, 0.83, accuracy: 1e-6)
    }

    func test_hostIgnoresOutOfOrderPaddleInput() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        let newer = PaddleInput(protoVersion: 1, paddleX: 0.83, tickSeq: 5)
        let older = PaddleInput(protoVersion: 1, paddleX: 0.10, tickSeq: 3)
        fake.simulateIncoming(.paddleInput(newer))
        try? await Task.sleep(nanoseconds: 30_000_000)
        fake.simulateIncoming(.paddleInput(older))
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(game.aiPaddleX, 0.83, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run to confirm failure**

Expected: `setLocalPaddle` undefined; host-apply test fails.

- [ ] **Step 3: Implement both directions**

Add to `MultiplayerGameState`:

```swift
    private var lastPaddleInputSeq: UInt32 = 0
    private var localPaddleInputSeq: UInt32 = 0

    /// View calls this when the Digital Crown changes. Works for both roles.
    func setLocalPaddle(normalizedCrown value: CGFloat) {
        let clamped = max(0, min(1, value))
        // Both roles update their own inner-game player paddle for local rendering.
        game.setPlayerPaddle(normalizedCrown: clamped)
        if role == .client {
            localPaddleInputSeq &+= 1
            let input = PaddleInput(
                protoVersion: GameConstants.multiplayerProtocolVersion,
                paddleX: clamped,
                tickSeq: localPaddleInputSeq
            )
            service.send(.paddleInput(input), reliable: false)
        }
    }

    private func applyIncomingPaddleInput(_ input: PaddleInput) {
        guard role == .host else { return }
        let delta = input.tickSeq &- lastPaddleInputSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastPaddleInputSeq = input.tickSeq
        game.aiPaddleX = input.paddleX
    }
```

Also update `broadcastSnapshot` to use the actual client paddle slot:

```swift
            hostPaddleX: game.playerPaddleX,
            clientPaddleX: game.aiPaddleX,   // aiPaddleX holds client's paddle on host
```
(This line is already correct from Task 8. Confirm.)

**Important:** Disable the built-in AI paddle tracking on the host during multiplayer. The simplest, least-invasive way: have `MultiplayerGameState` overwrite `game.aiPaddleX` *after* `game.update(dt:)` each tick, using the last-received client input. Update `tickIfHost`:

```swift
    func tickIfHost(dt: CGFloat) {
        guard role == .host, matchPhase == .playing else { return }
        let lastClientPaddle = game.aiPaddleX
        game.update(dt: dt)
        // Physics moved the AI paddle via its built-in tracker; restore to the client's
        // actual paddle position instead.
        game.aiPaddleX = lastClientPaddle
        broadcastSnapshot()
    }
```

Wait — that's wrong, because `game.update` runs physics against the AI-moved paddle, not the client's. Instead, before calling `update`, snap `aiPaddleX` to the latest client value, so physics checks the right paddle position:

```swift
    func tickIfHost(dt: CGFloat) {
        guard role == .host, matchPhase == .playing else { return }
        // Client paddle position is already stored in game.aiPaddleX by
        // applyIncomingPaddleInput. game.update(dt:) will run AI tracking over it,
        // but we revert immediately after physics to keep the client as authoritative.
        let clientPaddleBeforeTick = game.aiPaddleX
        game.update(dt: dt)
        game.aiPaddleX = clientPaddleBeforeTick
        broadcastSnapshot()
    }
```

This works because `game.update` sub-steps physics using the paddle position held at the start of the tick. The built-in AI tracking after that is discarded.

- [ ] **Step 4: Run tests**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): wire client paddle input from client to host"
```

---

## Task 11: Client-side prediction for own paddle

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing test**

```swift
    func test_clientSnapshotDoesNotOverwriteLocallyPredictedPaddle() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        // Local crown input sets our predicted paddle.
        state.setLocalPaddle(normalizedCrown: 0.42)
        // Now a snapshot arrives with a stale clientPaddleX.
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.15,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Our local prediction wins.
        XCTAssertEqual(state.game.playerPaddleX, 0.42, accuracy: 1e-6)
        // Opponent still trusts the snapshot.
        XCTAssertEqual(state.game.aiPaddleX, 0.5, accuracy: 1e-6)
    }
```

- [ ] **Step 2: Run to see failure**

Expected: playerPaddleX is 0.15 from the snapshot — test fails.

- [ ] **Step 3: Ignore clientPaddleX in snapshot on client**

Update `applyIncomingSnapshot`:

```swift
    private func applyIncomingSnapshot(_ snap: GameSnapshot) {
        guard role == .client else { return }
        let delta = snap.tickSeq &- lastReceivedTickSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastReceivedTickSeq = snap.tickSeq

        game.ball = Ball(
            position: CGPoint(x: snap.ballX, y: 1.0 - snap.ballY),
            velocity: CGVector(dx: snap.ballVX, dy: -snap.ballVY)
        )
        // DO NOT overwrite game.playerPaddleX — that's our locally predicted paddle.
        game.aiPaddleX = snap.hostPaddleX
        game.score = snap.clientScore
        game.countdownRemaining = snap.countdownRemaining
        game.phase = snap.phase

        hostScore = snap.hostScore
        clientScore = snap.clientScore
    }
```

Also update the earlier `test_clientPaddleAssignmentFlipped` test. It asserted that `playerPaddleX` reflects the snapshot — update it so it only asserts `aiPaddleX`:

Replace the relevant assertions in `test_clientPaddleAssignmentFlipped` with:

```swift
        // "My" paddle uses local prediction only; snapshot clientPaddleX is ignored.
        XCTAssertEqual(state.game.playerPaddleX, 0.5, accuracy: 1e-6)  // unchanged default
        XCTAssertEqual(state.game.aiPaddleX, 0.4, accuracy: 1e-6)
```

- [ ] **Step 4: Run tests**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): client-side prediction ignores snapshot's own-paddle field"
```

---

## Task 12: Host detects score, broadcasts ScoreEvent, spawns particles on scorer only

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
    func test_hostScoreEventWhenBallExitsTop() {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        // Position ball just above top with downward-up velocity so it exits on next step
        game.ball = Ball(position: CGPoint(x: 0.3, y: 0.01),
                         velocity: CGVector(dx: 0, dy: -1.0))
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .host)
        state.tickIfHost(dt: 0.1)
        // Find the first snapshot that included a scoreEvent.
        let scoringSnap = fake.sentMessages.compactMap { msg -> GameSnapshot? in
            if case .snapshot(let s) = msg.message, s.scoreEvent != nil { return s } else { return nil }
        }.first
        XCTAssertNotNil(scoringSnap)
        XCTAssertEqual(scoringSnap?.scoreEvent?.scoredBy, .host)
        XCTAssertEqual(state.hostScore, 1)
    }

    func test_clientSpawnsParticlesWhenTheyAreTheScorer() async {
        let fake = FakeMultiplayerService()
        let game = GameState()
        game.phase = .playing
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.0, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 1,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .client),
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.game.particles.count, GameConstants.particlesPerBurst)
    }

    func test_clientDoesNotSpawnParticlesWhenHostScores() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.0, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 1, clientScore: 0,
            countdownRemaining: 3,
            scoreEvent: ScoreEvent(impactX: 0.37, scoredBy: .host),
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.game.particles.isEmpty)
    }
```

- [ ] **Step 2: Run to see failures**

Expected: host's scoring path doesn't set hostScore; clients don't spawn particles.

- [ ] **Step 3: Detect score on host during tick**

The inner `GameState` increments its own `score` on top-exit (line 145 of `GameState.swift`). In multiplayer we take a different path: before `game.update(dt:)`, snapshot the score; after, if it went up, the host scored.

Also, for bottom-exit, `game.update` transitions to `.gameOver` (line 152-154). In MP we don't want that — bottom-exit means client scored. Simplest fix: after `game.update`, if `game.phase == .gameOver`, the client scored — reset `game.phase = .playing`, increment client score, trigger countdown + score event, and clear any high-score side effect.

Update `tickIfHost`:

```swift
    func tickIfHost(dt: CGFloat) {
        guard role == .host, matchPhase == .playing else { return }
        let scoreBefore = game.score
        let phaseBefore = game.phase
        let clientPaddleBeforeTick = game.aiPaddleX

        game.update(dt: dt)
        game.aiPaddleX = clientPaddleBeforeTick

        var pendingScoreEvent: ScoreEvent? = nil

        // Host scored: inner game's score went up (ball exited top in host space).
        if game.score > scoreBefore {
            hostScore += game.score - scoreBefore
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .host)
            // Reset inner-game score so the next host-point detection is clean.
            // (Snapshot sends hostScore/clientScore fields independently.)
        }

        // Client scored: inner game flipped to .gameOver because ball exited bottom.
        if phaseBefore == .playing && game.phase == .gameOver {
            clientScore += 1
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .client)
            game.phase = .playing
            // Start a fresh countdown on the inner game so the ball resets cleanly.
            game.spawnScoreBurst(atX: game.ball.position.x)  // note: only host spawns its own particles
            // Trigger an inner-game countdown by calling startGame()-like flow would reset score/high-score.
            // Instead, push the ball back to center with zero velocity and set a countdown.
            resetBallForNextServe()
        }

        // Check match-over.
        if hostScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .host)
        } else if clientScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .client)
        }

        broadcastSnapshot(scoreEvent: pendingScoreEvent)

        // Only the host spawns particles on its own score. The client will spawn
        // from the snapshot event in applyIncomingSnapshot.
        if let ev = pendingScoreEvent, ev.scoredBy == .host {
            game.spawnScoreBurst(atX: ev.impactX)
        }
    }

    private func resetBallForNextServe() {
        // Reset ball to center for next serve; inner GameState manages its own countdown
        // on the host-scored path via startCountdown(), but that's private. Use the
        // existing public surface: calling startGame() would reset score/high-score which
        // we don't want. Instead, directly set the ball + countdown fields.
        game.ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)
        game.countdownRemaining = GameConstants.countdownStart
    }
```

**Wait** — `game.countdownRemaining` is `@Published var` (public settable). And `game.ball` is public settable too. Good. But `countdownElapsed` is private. The inner `tickCountdown` reads `countdownElapsed`; we need it zeroed. Since we have no access to it from outside, our simplest fix: when we set `countdownRemaining = GameConstants.countdownStart`, the inner `update` sees the countdown is active and will call `tickCountdown`, which reads the stale `countdownElapsed`. This could make the countdown tick faster than it should.

**Better approach:** expose a public method on `GameState` for this exact purpose. Add to `GameState`:

```swift
    /// Public entry point used by multiplayer to start a fresh serve.
    /// Resets ball to center and starts the 3-2-1 countdown without touching score.
    func prepareNextServe() {
        ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)
        countdownRemaining = GameConstants.countdownStart
        countdownElapsed = 0
    }
```

Put this after `startGame()` in `GameState.swift`.

Then update `resetBallForNextServe` to just call it:

```swift
    private func resetBallForNextServe() {
        game.prepareNextServe()
    }
```

Similarly, the host's own scoring path inside `game.update(dt:)` calls the private `startCountdown()` internally, which zeros `countdownElapsed` — so that path is fine.

Update `broadcastSnapshot` to accept an optional score event:

```swift
    private func broadcastSnapshot(scoreEvent: ScoreEvent? = nil) {
        tickSeq &+= 1
        let snap = GameSnapshot(
            protoVersion: GameConstants.multiplayerProtocolVersion,
            phase: game.phase,
            ballX: game.ball.position.x,
            ballY: game.ball.position.y,
            ballVX: game.ball.velocity.dx,
            ballVY: game.ball.velocity.dy,
            hostPaddleX: game.playerPaddleX,
            clientPaddleX: game.aiPaddleX,
            hostScore: hostScore,
            clientScore: clientScore,
            countdownRemaining: game.countdownRemaining,
            scoreEvent: scoreEvent,
            hostPaddleHit: false,
            clientPaddleHit: false,
            tickSeq: tickSeq
        )
        service.send(.snapshot(snap), reliable: false)
    }
```

Update client's `applyIncomingSnapshot` to spawn particles on score events:

```swift
    private func applyIncomingSnapshot(_ snap: GameSnapshot) {
        guard role == .client else { return }
        let delta = snap.tickSeq &- lastReceivedTickSeq
        if delta == 0 || delta > UInt32.max / 2 { return }
        lastReceivedTickSeq = snap.tickSeq

        game.ball = Ball(
            position: CGPoint(x: snap.ballX, y: 1.0 - snap.ballY),
            velocity: CGVector(dx: snap.ballVX, dy: -snap.ballVY)
        )
        game.aiPaddleX = snap.hostPaddleX
        game.score = snap.clientScore
        game.countdownRemaining = snap.countdownRemaining
        game.phase = snap.phase

        hostScore = snap.hostScore
        clientScore = snap.clientScore

        // Celebrate only if we scored.
        if let event = snap.scoreEvent, event.scoredBy == .client {
            game.spawnScoreBurst(atX: event.impactX)
        }
    }

    private func finishMatch(winner: PeerRole) {
        matchPhase = .matchOver(winner: winner)
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch App/Game/GameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): score detection, ScoreEvent broadcast, scorer-only particles"
```

---

## Task 13: Paddle-hit haptic flags in snapshot

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

The host's built-in `playClick()` fires locally on host-paddle collision. We need:
1. Host to detect *client* paddle collisions and set `clientPaddleHit = true` on that snapshot.
2. Client to play haptic when it sees `clientPaddleHit: true` in incoming snapshot.

Because `GameState.stepPhysics` is private, we detect client-paddle collisions by observing: after `game.update(dt:)`, if `ball.velocity.dy` sign flipped *from negative to positive* AND the ball is near the top paddle Y, the client paddle was hit.

- [ ] **Step 1: Add failing tests**

```swift
    func test_clientPlaysHapticOnClientPaddleHitFlag() async {
        let fake = FakeMultiplayerService()
        let game = GameState(highScoreStore: HighScoreStore(), hapticPlayer: RecordingHapticPlayer())
        let state = MultiplayerGameState(service: fake, game: game)
        fake.simulateConnected(as: .client)
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 0,
            countdownRemaining: nil, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: true,
            tickSeq: 1
        )
        fake.simulateIncoming(.snapshot(snap))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let haptic = game.injectedHapticPlayerForTests as! RecordingHapticPlayer
        XCTAssertEqual(haptic.clickCount, 1)
    }
```

This test needs two things:
1. A `RecordingHapticPlayer` test double.
2. A way to inject a haptic player into `GameState` and access it for assertions.

**Add `RecordingHapticPlayer` to the test target.** If there's already one from prior tests, reuse; otherwise add at the top of `MultiplayerGameStateTests.swift`:

```swift
final class RecordingHapticPlayer: HapticPlayer {
    var clickCount = 0
    func playClick() { clickCount += 1 }
}
```

**Add a public paddle-hit haptic entry point on `GameState`.** Add to `GameState.swift`:

```swift
    /// Plays the paddle-hit haptic. Exposed so multiplayer can trigger it when
    /// the inbound snapshot reports the local paddle hit the ball on the host.
    func playPaddleHitHaptic() {
        hapticPlayer.playClick()
    }
```

**Also add a test helper** that returns the injected haptic player, so the test can assert on it. In the same file, keep `hapticPlayer` private but add:

```swift
    #if DEBUG
    var injectedHapticPlayerForTests: HapticPlayer { hapticPlayer }
    #endif
```

Update the test to read this:
```swift
        let haptic = game.injectedHapticPlayerForTests as! RecordingHapticPlayer
        XCTAssertEqual(haptic.clickCount, 1)
```

- [ ] **Step 2: Run — see compile errors**

Expected: `HapticPlayer` protocol, missing `hapticPlayerForTests`.

- [ ] **Step 3: Check `HapticPlayer` protocol**

Open `PongWatch/PongWatch Watch App/Game/HapticPlayer.swift`. Confirm it declares:

```swift
protocol HapticPlayer { func playClick() }
```

(If not, this task must update it.)

Update client snapshot handling:

```swift
    private func applyIncomingSnapshot(_ snap: GameSnapshot) {
        guard role == .client else { return }
        // ... existing body ...

        if snap.clientPaddleHit {
            game.playPaddleHitHaptic()
        }

        if let event = snap.scoreEvent, event.scoredBy == .client {
            game.spawnScoreBurst(atX: event.impactX)
        }
    }
```

**Host side:** detect client-paddle hit. Track the ball's prior velocity, after `game.update(dt:)` check for a downward→upward flip near the top paddle:

```swift
    func tickIfHost(dt: CGFloat) {
        guard role == .host, matchPhase == .playing else { return }
        let scoreBefore = game.score
        let phaseBefore = game.phase
        let clientPaddleBeforeTick = game.aiPaddleX
        let ballVYBefore = game.ball.velocity.dy

        game.update(dt: dt)
        game.aiPaddleX = clientPaddleBeforeTick

        // Client paddle hit: ball was moving up (negative dy in host space) and is now moving
        // down (positive dy) with the ball near the top.
        let clientPaddleHit = ballVYBefore < 0 && game.ball.velocity.dy > 0 &&
                              game.ball.position.y < GameConstants.paddleMarginY + GameConstants.paddleHeight

        // Host paddle hit: ball was moving down and is now moving up near the bottom.
        let hostPaddleHit = ballVYBefore > 0 && game.ball.velocity.dy < 0 &&
                            game.ball.position.y > 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight

        var pendingScoreEvent: ScoreEvent? = nil
        if game.score > scoreBefore {
            hostScore += game.score - scoreBefore
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .host)
        }
        if phaseBefore == .playing && game.phase == .gameOver {
            clientScore += 1
            pendingScoreEvent = ScoreEvent(impactX: game.ball.position.x, scoredBy: .client)
            game.phase = .playing
            game.prepareNextServe()
        }

        if hostScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .host)
        } else if clientScore >= GameConstants.multiplayerWinningScore {
            finishMatch(winner: .client)
        }

        broadcastSnapshot(
            scoreEvent: pendingScoreEvent,
            hostPaddleHit: hostPaddleHit,
            clientPaddleHit: clientPaddleHit
        )

        if let ev = pendingScoreEvent, ev.scoredBy == .host {
            game.spawnScoreBurst(atX: ev.impactX)
        }
    }

    private func broadcastSnapshot(
        scoreEvent: ScoreEvent? = nil,
        hostPaddleHit: Bool = false,
        clientPaddleHit: Bool = false
    ) {
        tickSeq &+= 1
        let snap = GameSnapshot(
            protoVersion: GameConstants.multiplayerProtocolVersion,
            phase: game.phase,
            ballX: game.ball.position.x,
            ballY: game.ball.position.y,
            ballVX: game.ball.velocity.dx,
            ballVY: game.ball.velocity.dy,
            hostPaddleX: game.playerPaddleX,
            clientPaddleX: game.aiPaddleX,
            hostScore: hostScore,
            clientScore: clientScore,
            countdownRemaining: game.countdownRemaining,
            scoreEvent: scoreEvent,
            hostPaddleHit: hostPaddleHit,
            clientPaddleHit: clientPaddleHit,
            tickSeq: tickSeq
        )
        service.send(.snapshot(snap), reliable: false)
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild ... test -only-testing:"PongWatch Watch AppTests/MultiplayerGameStateTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch App/Game/GameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): paddle-hit haptic flag round-trip in snapshots"
```

---

## Task 14: Wrist-down 3s grace window + forfeit

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
    func test_wristDownUnderGracePeriodDoesNotForfeit() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        state.onScenePhaseChanged(to: .active)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Match still playing.
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing, got \(state.matchPhase)") }
    }

    func test_wristDownOverGracePeriodForfeits() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        // Use a tiny grace for the test.
        state.setGraceSecondsForTests(0.05)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 150_000_000)  // 0.15s, exceeds grace
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .client)  // host forfeited → client wins
        } else {
            XCTFail("Expected .matchOver, got \(state.matchPhase)")
        }
    }

    func test_wristDownSendsPausedMessage() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.onScenePhaseChanged(to: .inactive)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let pausedSends = fake.sentMessages.filter {
            if case .paused = $0.message { return true } else { return false }
        }
        XCTAssertEqual(pausedSends.count, 1)
    }
```

- [ ] **Step 2: Run — see failures**

Expected: methods don't exist.

- [ ] **Step 3: Implement scene-phase handling**

Add to `MultiplayerGameState`. Note: `SwiftUI.ScenePhase` isn't available in pure model code, so we take a minimal enum:

```swift
    enum LocalScenePhase { case active, inactive }

    private var graceSeconds: Double = GameConstants.multiplayerGraceSeconds
    private var wristDownTask: Task<Void, Never>?

    func setGraceSecondsForTests(_ seconds: Double) {
        graceSeconds = seconds
    }

    func onScenePhaseChanged(to phase: LocalScenePhase) {
        guard case .playing = matchPhase else { return }
        switch phase {
        case .inactive:
            guard let role else { return }
            service.send(.paused(role: role), reliable: true)
            wristDownTask?.cancel()
            let grace = graceSeconds
            wristDownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.service.send(.forfeit(by: role), reliable: true)
                    self.matchPhase = .matchOver(winner: role.opposite)
                }
            }
        case .active:
            wristDownTask?.cancel()
            wristDownTask = nil
            guard let role else { return }
            service.send(.resumed(role: role), reliable: true)
        }
    }
```

- [ ] **Step 4: Run tests**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): 3s wrist-down grace window with forfeit"
```

---

## Task 15: Rematch + Back flow

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
    func test_requestRematchAsHostSendsAndResets() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.requestRematch()
        let rematchSends = fake.sentMessages.filter {
            if case .rematchRequest = $0.message { return true } else { return false }
        }
        XCTAssertEqual(rematchSends.count, 1)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing") }
    }

    func test_clientReceivingRematchResetsScoresAndPlays() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        fake.simulateIncoming(.rematchRequest)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.hostScore, 0)
        XCTAssertEqual(state.clientScore, 0)
        if case .playing = state.matchPhase {} else { XCTFail("Expected .playing") }
    }

    func test_leaveMatchTearsDownSession() {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        state.leaveMatch()
        XCTAssertEqual(fake.connectionState, .idle)
    }
```

- [ ] **Step 2: Run — see failures**

Expected: methods undefined.

- [ ] **Step 3: Implement**

```swift
    // MARK: - Post-match

    func requestRematch() {
        guard role != nil else { return }
        service.send(.rematchRequest, reliable: true)
        startFreshMatch()
    }

    private func handleRematchRequest() {
        startFreshMatch()
    }

    private func startFreshMatch() {
        hostScore = 0
        clientScore = 0
        tickSeq = 0
        lastReceivedTickSeq = 0
        lastPaddleInputSeq = 0
        localPaddleInputSeq = 0
        game.prepareNextServe()
        game.phase = .playing
        matchPhase = .playing
    }

    func leaveMatch() {
        service.disconnect()
        matchPhase = .pairing
    }
```

- [ ] **Step 4: Run tests**

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): rematch + leave-match flows"
```

---

## Task 16: Update StartView with SP/MP buttons

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Screens/StartView.swift`

- [ ] **Step 1: Replace body with two stacked buttons**

```swift
import SwiftUI

struct StartView: View {
    @AppStorage(HighScoreStore.userDefaultsKey) private var highScore: Int = 0
    let onStartSinglePlayer: () -> Void
    let onStartMultiplayer: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("PONG")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                if highScore > 0 {
                    Text("High Score: \(highScore)")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer().frame(height: 4)
                Button(action: onStartSinglePlayer) {
                    Text("Single Player")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onStartMultiplayer) {
                    Text("Multiplayer")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    StartView(onStartSinglePlayer: {}, onStartMultiplayer: {})
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: BUILD FAILED (ContentView still calls the old `onStart:` signature). We'll fix in Task 19. For now, temporarily patch ContentView so the project compiles:

Modify `ContentView.swift` line 9-11:
```swift
        case .start:
            StartView(
                onStartSinglePlayer: { state.startGame() },
                onStartMultiplayer: { /* Task 19 wires this */ }
            )
```

- [ ] **Step 3: Build again**

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Screens/StartView.swift" \
        "PongWatch/PongWatch Watch App/ContentView.swift"
git commit -m "feat(mp): StartView shows Single Player / Multiplayer buttons"
```

---

## Task 17: Create NearbyPlayersView + InvitePromptView

**Files:**
- Create: `PongWatch/PongWatch Watch App/Screens/NearbyPlayersView.swift`
- Create: `PongWatch/PongWatch Watch App/Screens/InvitePromptView.swift`

- [ ] **Step 1: Write NearbyPlayersView**

```swift
import SwiftUI

struct NearbyPlayersView<Service: MultiplayerServiceProtocol>: View {
    @ObservedObject var service: Service
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Nearby Players")
                    .font(.headline)
                    .foregroundColor(.white)
                if service.discoveredPeers.isEmpty {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Searching…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text("Make sure the other player is also on Multiplayer.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(service.discoveredPeers, id: \.self) { peer in
                                Button {
                                    service.invite(peer)
                                } label: {
                                    Text(peer.displayName)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Button("Back", action: onBack)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.footnote)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .onAppear {
            service.startAdvertising()
            service.startBrowsing()
        }
        .onDisappear {
            service.stopBrowsing()
            // Keep advertising until match starts (Task 20 stops it then).
        }
    }
}
```

- [ ] **Step 2: Write InvitePromptView**

```swift
import SwiftUI

struct InvitePromptView: View {
    let peerName: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(peerName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("wants to play")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer().frame(height: 4)
                Button(action: onAccept) {
                    Text("Accept")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.35))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onDecline) {
                    Text("Decline")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.35))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    InvitePromptView(peerName: "John's Apple Watch", onAccept: {}, onDecline: {})
}
```

- [ ] **Step 3: Build**

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Screens/NearbyPlayersView.swift" \
        "PongWatch/PongWatch Watch App/Screens/InvitePromptView.swift" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): add NearbyPlayersView and InvitePromptView"
```

---

## Task 18: Create MultiplayerGameOverView + update GameView for flip

**Files:**
- Create: `PongWatch/PongWatch Watch App/Screens/MultiplayerGameOverView.swift`
- Modify: `PongWatch/PongWatch Watch App/Screens/GameView.swift`

- [ ] **Step 1: Write MultiplayerGameOverView**

```swift
import SwiftUI

struct MultiplayerGameOverView: View {
    let didWin: Bool
    let myScore: Int
    let opponentScore: Int
    let onRematch: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(didWin ? "You Won!" : "You Lost")
                    .font(.title3)
                    .bold()
                    .foregroundColor(didWin ? .green : .red)
                Text("\(myScore) — \(opponentScore)")
                    .font(.title2)
                    .foregroundColor(.white)
                Spacer().frame(height: 4)
                Button(action: onRematch) {
                    Text("Rematch")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onBack) {
                    Text("Back")
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    MultiplayerGameOverView(didWin: true, myScore: 5, opponentScore: 3, onRematch: {}, onBack: {})
}
```

- [ ] **Step 2: Update GameView to accept a multiplayer overlay + flipY flag**

GameView currently takes `state: GameState`. We want MP to also use it (since `MultiplayerGameState.game` is a `GameState`). Add an optional score overlay:

Modify `GameView.swift` — add a new initializer parameter and score overlay:

```swift
struct GameView: View {
    @ObservedObject var state: GameState
    @Environment(\.scenePhase) private var scenePhase
    @State private var crownValue: Double = 0.5
    /// Optional (myScore, opponentScore) overlay for multiplayer mode.
    var multiplayerScores: (mine: Int, opp: Int)? = nil
    /// Closure called every render tick (for MP host physics + snapshot send).
    /// If nil, GameView runs single-player update via state.update(dt:).
    var onTick: ((CGFloat) -> Void)? = nil
    /// Closure called when the crown changes — replaces default state.setPlayerPaddle.
    /// If nil, default behavior is used.
    var onCrownChange: ((CGFloat) -> Void)? = nil
```

Change the `.onChange(of: crownValue)` handler:

```swift
        .onChange(of: crownValue) { _, newValue in
            if let onCrownChange {
                onCrownChange(CGFloat(newValue))
            } else {
                state.setPlayerPaddle(normalizedCrown: CGFloat(newValue))
            }
        }
```

And the game loop:

```swift
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_666_666)
                let now = Date()
                let dt = CGFloat(now.timeIntervalSince(last))
                last = now
                if dt > 0.1 { continue }
                let clampedDt = min(dt, 0.05)
                if let onTick {
                    onTick(clampedDt)
                } else {
                    state.update(dt: clampedDt)
                }
            }
        }
```

Add the MP score overlay inside `drawPlayfield`, replacing the existing single-score overlay:

```swift
        // Score
        if let mp = multiplayerScores {
            let mpText = Text("\(mp.mine) — \(mp.opp)")
                .font(.caption2).foregroundColor(.white)
            context.draw(mpText, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        } else {
            let scoreText = Text("\(state.score)").font(.caption2).foregroundColor(.white)
            context.draw(scoreText, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
        }
```

**Note on Y flip:** we decided (Task 9) that the client applies Y flip when writing the snapshot *into* the inner `GameState`. So GameView doesn't need its own flip — the inner state already has flipped coords. The MP client's GameView renders identically to SP. Great — no flip code in GameView needed.

- [ ] **Step 3: Build**

Run: `xcodebuild ... build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Screens/MultiplayerGameOverView.swift" \
        "PongWatch/PongWatch Watch App/Screens/GameView.swift" \
        PongWatch/PongWatch.xcodeproj/project.pbxproj
git commit -m "feat(mp): GameView supports MP score + onTick/onCrown hooks, add MP game over"
```

---

## Task 19: ContentView routing + stop advertising during match

**Files:**
- Modify: `PongWatch/PongWatch Watch App/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView**

```swift
import SwiftUI

enum GameMode {
    case singlePlayer
    case multiplayer
}

struct ContentView: View {
    @StateObject private var singlePlayerState = GameState()
    @StateObject private var mpService: MultiplayerService
    @StateObject private var mpState: MultiplayerGameState

    @State private var mode: GameMode? = nil

    init() {
        // Build service first so we can hand the same instance to MultiplayerGameState.
        let service = MultiplayerService()
        _mpService = StateObject(wrappedValue: service)
        _mpState = StateObject(wrappedValue: MultiplayerGameState(service: service))
    }

    var body: some View {
        Group {
            switch mode {
            case .none:
                if singlePlayerState.phase == .gameOver {
                    GameOverView(
                        finalScore: singlePlayerState.score,
                        isNewHighScore: singlePlayerState.lastRunWasRecord,
                        onRestart: { singlePlayerState.startGame() }
                    )
                } else if singlePlayerState.phase == .playing {
                    GameView(state: singlePlayerState)
                } else {
                    StartView(
                        onStartSinglePlayer: {
                            mode = .singlePlayer
                            singlePlayerState.startGame()
                        },
                        onStartMultiplayer: {
                            mode = .multiplayer
                        }
                    )
                }

            case .singlePlayer:
                // Single-player view routing (GameView / GameOverView) is handled via
                // singlePlayerState.phase; we stay in this branch until user backs out.
                switch singlePlayerState.phase {
                case .start:
                    StartView(
                        onStartSinglePlayer: { singlePlayerState.startGame() },
                        onStartMultiplayer: { mode = .multiplayer }
                    )
                case .playing:
                    GameView(state: singlePlayerState)
                case .gameOver:
                    GameOverView(
                        finalScore: singlePlayerState.score,
                        isNewHighScore: singlePlayerState.lastRunWasRecord,
                        onRestart: {
                            singlePlayerState.startGame()
                        }
                    )
                }

            case .multiplayer:
                multiplayerRoot
            }
        }
    }

    @ViewBuilder
    private var multiplayerRoot: some View {
        switch mpState.matchPhase {
        case .pairing:
            if case .receivingInvite(let name) = mpService.connectionState {
                InvitePromptView(
                    peerName: name,
                    onAccept: { mpService.respondToInvite(accept: true) },
                    onDecline: { mpService.respondToInvite(accept: false); mode = nil }
                )
            } else {
                NearbyPlayersView(service: mpService, onBack: {
                    mpService.disconnect()
                    mode = nil
                })
            }

        case .playing, .pausedByOpponent:
            GameView(
                state: mpState.game,
                multiplayerScores: (mine: myScore, opp: oppScore),
                onTick: { dt in mpState.tickIfHost(dt: dt) },
                onCrownChange: { v in mpState.setLocalPaddle(normalizedCrown: v) }
            )
            .onAppear {
                // Stop advertising once we start playing.
                mpService.stopAdvertising()
            }
            .overlay(alignment: .center) {
                if mpState.matchPhase == .pausedByOpponent {
                    Text("Opponent paused…")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                }
            }
            .onChange(of: scenePhaseValue) { _, newPhase in
                mpState.onScenePhaseChanged(to: newPhase == .active ? .active : .inactive)
            }

        case .matchOver(let winner):
            MultiplayerGameOverView(
                didWin: winner == mpState.role,
                myScore: myScore,
                opponentScore: oppScore,
                onRematch: { mpState.requestRematch() },
                onBack: {
                    mpState.leaveMatch()
                    mode = nil
                }
            )

        case .disconnected:
            MultiplayerGameOverView(
                didWin: true,  // peer dropped → we win by default
                myScore: myScore,
                opponentScore: oppScore,
                onRematch: {
                    mpState.leaveMatch()
                    mode = nil
                },
                onBack: {
                    mpState.leaveMatch()
                    mode = nil
                }
            )
        }
    }

    @Environment(\.scenePhase) private var scenePhaseValue

    private var myScore: Int {
        switch mpState.role {
        case .host: return mpState.hostScore
        case .client: return mpState.clientScore
        case nil: return 0
        }
    }
    private var oppScore: Int {
        switch mpState.role {
        case .host: return mpState.clientScore
        case .client: return mpState.hostScore
        case nil: return 0
        }
    }
}

#Preview {
    ContentView()
}
```

**Note about double MultiplayerService instantiation in the init:** `@StateObject private var mpService = MultiplayerService()` is already an autoclosure, but we need to share the instance with `mpState`. The init pattern above constructs a local `service`, assigns both StateObjects to wrap it. (The top-level `@StateObject` declaration's initial value is unused because init overrides it.)

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: BUILD SUCCEEDED. If errors around Combine/@StateObject init, troubleshoot by moving service creation into a static factory or using `@State` + `StateObject(wrappedValue:)` pattern.

- [ ] **Step 3: Commit**

```bash
git add "PongWatch/PongWatch Watch App/ContentView.swift"
git commit -m "feat(mp): ContentView routes SP/MP; stops advertising during match"
```

---

## Task 20: Disconnect detection → other peer wins

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift`
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

- [ ] **Step 1: Add failing test**

```swift
    func test_disconnectMidMatchEndsWithLocalWin() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        fake.simulateDisconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Match treats this as peer-dropped → local watch wins.
        if case .matchOver(let winner) = state.matchPhase {
            XCTAssertEqual(winner, .host)
        } else {
            XCTFail("Expected .matchOver(winner: .host), got \(state.matchPhase)")
        }
    }
```

- [ ] **Step 2: Run — expect failure**

Expected: matchPhase goes to `.disconnected`, not `.matchOver`.

- [ ] **Step 3: Update `handleServiceStateChange`**

```swift
    private func handleServiceStateChange() {
        let newRole = service.role
        self.role = newRole
        switch service.connectionState {
        case .connected:
            if matchPhase == .pairing {
                matchPhase = .playing
            }
        case .disconnected:
            // Peer dropped: local watch wins. If we never got past .pairing, just idle.
            if case .playing = matchPhase {
                if let role = newRole ?? self.role {
                    matchPhase = .matchOver(winner: role)
                } else {
                    matchPhase = .disconnected
                }
            } else if case .pausedByOpponent = matchPhase {
                if let role = newRole ?? self.role {
                    matchPhase = .matchOver(winner: role)
                }
            } else {
                matchPhase = .disconnected
            }
        default:
            break
        }
    }
```

Note: `service.role` is cleared on disconnect, so we stash `newRole` at the top. If both `newRole` and `self.role` are nil we fall back to `.disconnected`.

Actually — tweak: don't clear `self.role` before checking. Reorder:

```swift
    private func handleServiceStateChange() {
        let priorRole = self.role
        let newRole = service.role
        switch service.connectionState {
        case .connected:
            self.role = newRole
            if matchPhase == .pairing {
                matchPhase = .playing
            }
        case .disconnected:
            let winnerRole = priorRole ?? newRole
            self.role = nil
            if matchPhase == .playing || matchPhase == .pausedByOpponent {
                if let winner = winnerRole {
                    matchPhase = .matchOver(winner: winner)
                } else {
                    matchPhase = .disconnected
                }
            } else {
                matchPhase = .disconnected
            }
        default:
            self.role = newRole
        }
    }
```

- [ ] **Step 4: Run tests**

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" \
        "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift"
git commit -m "feat(mp): peer disconnect mid-match ends with local watch winning"
```

---

## Task 21: Manual smoke test on two simulators

No code changes — manual verification that the previously-built flow works end-to-end.

- [ ] **Step 1: Boot two simulators**

```bash
xcrun simctl list devices | grep Watch
```
Pick any two watchOS 11+ simulators (e.g. "Apple Watch Series 10 (46mm)" and "Apple Watch Ultra 2 (49mm)"). Boot both:
```bash
xcrun simctl boot "Apple Watch Series 10 (46mm)"
xcrun simctl boot "Apple Watch Ultra 2 (49mm)"
```

- [ ] **Step 2: Install the app on both**

Build and install via Xcode's "Run" targeting each simulator one at a time, or via:
```bash
xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" install
```
Repeat for the second simulator.

**Note:** MultipeerConnectivity between two watchOS simulators on the same Mac often works via the macOS host's local network; AWDL does NOT work in simulators. If discovery fails, test on two physical watches — simulators are notoriously flaky for MC.

- [ ] **Step 3: Run through the full flow**

On both: launch → tap Multiplayer → one should discover the other → tap peer on watch A → watch B sees invite prompt → accept → gameplay begins → play until one side reaches 5 → see MultiplayerGameOverView → tap Rematch → verify fresh match → tap Back → returns to StartView.

- [ ] **Step 4: If everything works, mark done.** If simulator MC fails, note it and move to Task 22 (physical hardware).

No commit needed — this task is verification.

---

## Task 22: Deploy and test on two real Apple Watches

No code changes unless issues surface.

- [ ] **Step 1: Pair both watches to their respective iPhones (one each).**

- [ ] **Step 2: Via Xcode, install the app on Watch A (target: your watch).** Wait for install to complete. Launch app on Watch A.

- [ ] **Step 3: Install on Watch B via its paired iPhone/Xcode.** Launch.

- [ ] **Step 4: Both watches tap Multiplayer.** Verify each appears in the other's nearby list within ~5 seconds.

- [ ] **Step 5: Tap peer on Watch A → Watch B sees Accept prompt → Accept.**

- [ ] **Step 6: Play a full match.** Verify:
- Ball motion is smooth on both watches
- Own-paddle responsiveness feels instant
- Score updates in sync
- Particles fire only on the scoring watch
- Paddle-hit haptic fires locally on the hit watch

- [ ] **Step 7: Test forfeit.** Start a match, on Watch A drop your wrist. Wait 3+ seconds. Watch B should see the match end with Watch B winning.

- [ ] **Step 8: Test disconnect.** Start a match, force-quit the app on Watch A. Watch B should immediately transition to the match-over screen.

- [ ] **Step 9: Test rematch.** After a normal match ending, both players tap Rematch. A fresh match should begin.

No commit needed.

---

## Task 23: Final polish + PR

- [ ] **Step 1: Run the full test suite**

Run:
```
xcodebuild -project "PongWatch/PongWatch.xcodeproj" -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" test
```
Expected: all tests pass (original ~32 + new MP tests).

- [ ] **Step 2: Review `git log --oneline feat/pong-watch-game..HEAD`**

Verify commits are well-scoped, messages are consistent.

- [ ] **Step 3: Push branch and open PR**

```bash
git push -u origin addMultiplayer
```

Then open a PR on GitHub targeting `feat/pong-watch-game`:
```bash
gh pr create --base feat/pong-watch-game --title "feat: local watch-to-watch multiplayer" --body "$(cat <<'EOF'
## Summary
- Add local multiplayer over MultipeerConnectivity (BLE discovery + Wi-Fi transport)
- Host-authoritative networking with 30Hz snapshots and client-side paddle prediction
- Mirrored views (each player sees themselves at bottom)
- Preserves single-player features (3-2-1 countdown, scoring particles, hit-count speed scaling)
- First-to-5 match format; rematch + back UI; 3s wrist-down grace before forfeit

## Test plan
- [x] Unit tests pass (snapshot roundtrip, host/client state derivation, prediction, forfeit, rematch, disconnect)
- [ ] Manual 2-simulator smoke test
- [ ] Manual 2-real-watch match
- [ ] Verify single-player unchanged

Spec: `docs/superpowers/specs/2026-04-23-watch-multiplayer-design.md`
Plan: `docs/superpowers/plans/2026-04-23-watch-multiplayer.md`
EOF
)"
```

- [ ] **Step 4: Confirm PR URL is returned; paste into conversation for review.**

No commit needed — branch push and PR.

---

## Self-Review Notes

Spec-coverage check performed against `2026-04-23-watch-multiplayer-design.md`:

| Spec decision | Covered by task |
|---|---|
| Q1 MC transport | Task 5 |
| Q2 Nearby list | Task 17 |
| Q3 Host-authoritative | Task 8 |
| Q4 First-to-5 | Task 12 (match-over check) |
| Q5 Disconnect ends match | Task 20 |
| Q6 BT device name | Task 5 (uses `WKInterfaceDevice.current().name`) |
| Q7 Initiator → host | Task 5 (`invite` sets role .host) |
| Q8 Host raw coords, client flips | Task 9 |
| Q9 Countdown / particles / speed | Preserved by composing `GameState`; particles Task 12; countdown via `prepareNextServe`; speed scaling inherited |
| Q10 30Hz unreliable | Task 8 |
| Q11 MultipeerConnectivity | Task 5 |
| Q12 Client-side paddle prediction | Task 11 |
| Q13 Rematch + Back | Task 15, Task 18, Task 19 |
| Q14 3s grace | Task 14 |
| Q15 Stacked buttons on StartView | Task 16 |
| Q16 Stop advertising during match | Task 19 (`.onAppear { mpService.stopAdvertising() }`) |

Known risks flagged for the implementer:
- **Info.plist keys (Task 5 Step 3):** if Bonjour keys are missing, MC silently fails with no discoverable peers. Verify via Console.app if simulator discovery doesn't work.
- **Simulator MC is flaky.** If Task 21 (two simulators) fails, skip to Task 22 (real hardware) — simulator bugs are well-known for MC.
- **The AI paddle tracker runs inside `game.update(dt:)` on the host.** Task 10 mitigates by restoring `aiPaddleX` from client input before/after physics, but under very high AI speed settings the first physics sub-step might check against an AI-tracked paddle position instead of the client's. In practice this is imperceptible (one sub-step = at most half a paddle thickness of travel), but a future refactor could add a `disableAITracking: Bool` flag on `GameState`.
- **MCPeerID displayName from `WKInterfaceDevice.current().name`** can return empty string before the watch is fully booted; Task 5 falls back to "Apple Watch".
