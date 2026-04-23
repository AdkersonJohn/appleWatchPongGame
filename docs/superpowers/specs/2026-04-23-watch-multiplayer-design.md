# Apple Watch Multiplayer — Design

**Status:** Approved
**Date:** 2026-04-23
**Project:** PongWatch (watchOS)
**Branch:** `addMultiplayer`

## Summary

Add local, watch-to-watch multiplayer to PongWatch. Two Apple Watch users in close physical proximity discover each other automatically, pair with one tap, and play a head-to-head Pong match where each player sees themselves at the bottom and the opponent at the top. One watch acts as the authoritative host; the other is a thin client. All networking goes over Apple's `MultipeerConnectivity` framework (BLE discovery + Wi-Fi transport, handled for us). Match ends on first-to-5 points or on disconnect.

## Goals

- Zero-configuration pairing between two nearby Apple Watches (no account, no code entry, no shared Wi-Fi SSID requirement)
- Low-latency gameplay (crown → paddle feels instant; ball motion is smooth at 60fps)
- Single source of truth for physics (host-authoritative) to eliminate desync
- Preserve single-player features in multiplayer mode (3-2-1 countdown, scoring particles, hidden hit-count speed scaling)
- Clean separation: multiplayer is a sibling mode of single-player, both sharing the same core rendering and game-state types

## Non-goals

- Matchmaking over the Internet (no cloud, no accounts)
- Spectator mode, 3+ player matches, tournaments
- Leaderboards across devices (single-player high score is unchanged and untouched)
- Voice chat, emoji reactions, or any non-gameplay social features
- Reconnect / resume after network drop (we explicitly forfeit — see Q5)

---

## Decision ledger (from brainstorming session)

| # | Decision |
|---|----------|
| Q1 | Hybrid BLE + Wi-Fi transport (via MultipeerConnectivity) |
| Q2 | Automatic nearby-players list (AirDrop-style pairing) |
| Q3 | Host-authoritative networking |
| Q4 | First-to-N points, N = 5 |
| Q5 | End match immediately on disconnect |
| Q6 | Bluetooth device name used as player identity |
| Q7 | Initiator of the pairing becomes the host |
| Q8 | Host sends raw state in host-coordinate-space; client flips on render |
| Q9 | Keep countdown, scoring particles, hit-count speed scaling in MP |
| Q10 | 30 Hz snapshots, MultipeerConnectivity unreliable send mode |
| Q11 | MultipeerConnectivity (not manual BLE + Bonjour) |
| Q12 | Client-side prediction for own paddle |
| Q13 | Rematch + Back buttons after match end |
| Q14 | 3-second grace window on wrist-down before forfeit |
| Q15 | Stacked "Single Player" / "Multiplayer" buttons on StartView |
| Q16 | Stop advertising peer visibility during match |

---

## User flows

### Entering multiplayer
1. User launches the app → StartView shows two stacked buttons: **Single Player** and **Multiplayer**.
2. User taps **Multiplayer** → `NearbyPlayersView` appears.
3. View begins advertising this watch (via MC `MCNearbyServiceAdvertiser`) and browsing for nearby peers (via MC `MCNearbyServiceBrowser`).
4. Discovered peers appear in a scrollable list, each row showing the peer's Bluetooth device name.

### Pairing
5. User taps a peer's row → this watch sends an invite. The peer's watch shows an **Accept / Decline** prompt.
6. On **Accept**, the MC session is established. The initiator is designated host.
7. Both watches transition to `GameView` in multiplayer mode. Host starts the 3-2-1 countdown.

### Playing
8. Host runs the full physics loop at 60 Hz locally. Every ~33 ms (30 Hz), host sends a `GameSnapshot` over MC to the client.
9. Client runs no physics. It receives snapshots, extrapolates the ball between snapshots using the last known velocity, and renders at 60 Hz.
10. Client renders its own paddle position from local Digital Crown input immediately (client-side prediction). Client also sends its paddle position up to the host at 30 Hz.
11. Host reads the client's paddle position from its socket and uses it as the top paddle in physics.
12. On every scoring event (ball exits top or bottom), host updates scores, triggers a new countdown, and includes a `scoreEvent` in the next snapshot so both watches spawn particle bursts at the impact site.
13. First watch to reach 5 points wins. Host sends a terminal snapshot with `phase = .gameOver`.

### Post-match
14. Both watches show the `MultiplayerGameOverView` with **Rematch** and **Back** buttons.
15. **Rematch** — both watches remain in the MC session; host resets scores and starts a new 3-2-1.
16. **Back** — teardown the MC session and return to StartView.

### Wrist-down / interruption
17. If either watch's `scenePhase` becomes `.inactive` for 3 seconds, the host ends the match and the other watch wins by forfeit.
18. If the watch returns to `.active` within 3 seconds, the match continues where it left off.

### Disconnect
19. If MC reports the session has lost the peer (underlying transport failure, out of range, app killed), the host immediately ends the match. Local watch wins by default; opponent gets no ceremony.

---

## Architecture

### New files (proposed)

```
PongWatch/PongWatch Watch App/
├── Multiplayer/
│   ├── MultiplayerService.swift       // MC wrapper (advertiser, browser, session)
│   ├── MultiplayerGameState.swift     // Extends or wraps GameState for MP semantics
│   ├── GameSnapshot.swift             // Codable protocol DTOs
│   └── PeerRole.swift                 // enum PeerRole { case host, client }
├── Screens/
│   ├── NearbyPlayersView.swift        // List of discovered peers + invite UI
│   ├── InvitePromptView.swift         // "PlayerX wants to play" Accept/Decline
│   └── MultiplayerGameOverView.swift  // Rematch / Back
```

### Changes to existing files

- **`StartView.swift`** — replace single "Tap to Play" with two stacked buttons.
- **`ContentView.swift`** — add a `GameMode` enum (`.singlePlayer` / `.multiplayer`) and route accordingly. Multiplayer path uses a `MultiplayerService` + `MultiplayerGameState` combo.
- **`GameView.swift`** — add an optional `isClient: Bool` (or `coordinateFlip: Bool`) flag. When true, flip all `y` coordinates via `y → 1 - y` and swap the "my paddle" / "opponent paddle" roles before rendering.
- **`GameState.swift`** — no breaking changes. `MultiplayerGameState` **wraps** it (composition): holds an inner `GameState` for local rendering plus the `MultiplayerService`. Host mode drives the inner `GameState` via its normal physics tick; client mode writes directly into the inner state from incoming snapshots (bypassing physics).

### Networking layer (`MultiplayerService`)

Wraps `MCSession`, `MCNearbyServiceAdvertiser`, `MCNearbyServiceBrowser`. Exposes:

```swift
@Published var discoveredPeers: [MCPeerID] = []
@Published var connectionState: ConnectionState     // .idle, .inviting, .connected, .failed
@Published var role: PeerRole?                       // set on connect based on who invited

func startAdvertising()
func stopAdvertising()
func startBrowsing()
func stopBrowsing()
func invite(_ peer: MCPeerID)
func respondToInvite(accept: Bool)
func send<T: Encodable>(_ message: T, reliability: SendMode)
var incomingMessages: AsyncStream<Data>             // decoded by consumer
```

Service type string: `"pongwatch"` (must be 1–15 chars, lowercase ASCII + hyphens, per MC requirements).

### Protocol

All messages are `Codable` structs, JSON-encoded (small enough that JSON overhead is fine; avoids custom binary encoding for v1).

```swift
enum MessageKind: String, Codable {
    case snapshot       // host → client, 30 Hz, unreliable
    case paddleInput    // client → host, 30 Hz, unreliable
    case rematchRequest // either direction, reliable
    case endMatch       // either direction, reliable
}

struct GameSnapshot: Codable {
    var phase: GamePhase                 // .countdown, .playing, .gameOver
    var ballX: CGFloat
    var ballY: CGFloat
    var ballVX: CGFloat                  // needed for client extrapolation
    var ballVY: CGFloat
    var hostPaddleX: CGFloat
    var clientPaddleX: CGFloat
    var hostScore: Int
    var clientScore: Int
    var countdownRemaining: Int?         // nil when not counting
    var scoreEvent: ScoreEvent?          // non-nil for one snapshot after a point is scored
    var tickSeq: UInt32                  // monotonic, for ordering
}

struct ScoreEvent: Codable {
    var impactX: CGFloat                 // in host coordinate space
    var scoredBy: PeerRole               // who scored this point
}

struct PaddleInput: Codable {
    var paddleX: CGFloat                 // client's paddle in host coord space (no flip needed — client sends raw crown value, host interprets)
    var tickSeq: UInt32
}
```

**Send modes:**
- Snapshots and paddle inputs use `MCSessionSendDataMode.unreliable` — drop old, don't retransmit
- Rematch and endMatch use `.reliable`

### Client rendering with flip

```swift
// Client transforms incoming host snapshot to its local "me at bottom" view.
func renderFromSnapshot(_ s: GameSnapshot) {
    let ballY_flipped = 1.0 - s.ballY
    let ballVY_flipped = -s.ballVY
    let myPaddleY = 1.0 - GameConstants.hostPaddleY   // my paddle is at the bottom
    let opponentPaddleY = GameConstants.hostPaddleY   // opponent at top
    // myPaddleX: use local prediction from crown input, not s.clientPaddleX
    // opponentPaddleX: s.hostPaddleX (no X flip needed; X axis is symmetric)
}
```

### Client extrapolation

Between snapshots (at 30 Hz, snapshots arrive every ~33 ms; at 60 fps render, we need one extra interpolated frame). Linear extrapolation is sufficient for a ball that only changes velocity at bounces:

```swift
let dt = CACurrentMediaTime() - lastSnapshotTime
let extrapolatedX = snapshot.ballX + snapshot.ballVX * dt
let extrapolatedY = snapshot.ballY + snapshot.ballVY * dt
```

When a new snapshot arrives, snap to its position (no smoothing) — bounces will cause a velocity change that extrapolation can't anticipate, so we trust the host's latest state on arrival.

### Host-side client-paddle authority

Host receives `PaddleInput` messages and uses the latest received `paddleX` as the top-paddle position in its physics tick. If inputs arrive out of order (`tickSeq` goes backwards), host ignores the older one.

### Haptics

Paddle-hit haptic stays purely local on the watch whose paddle got hit. No need to stream haptic events:
- Host plays `.click` when its physics detects a host-paddle collision
- Client plays `.click` when it observes a snapshot where the ball's `vy` sign just changed near the client-paddle `y`-line (heuristic) — OR, simpler, host adds a boolean flag `clientPaddleHit: Bool` to the snapshot for one frame, and client plays haptic on receiving it.

**Decision:** use the snapshot flag (simpler, exact). Extend `GameSnapshot`:
```swift
var hostPaddleHit: Bool
var clientPaddleHit: Bool
```

### Particles (celebrate the scorer only)

On a scoring snapshot (`scoreEvent != nil`), **only the watch that just scored** spawns a particle burst — reusing the existing `spawnScoreBurst(atX:)`. The burst appears at *that watch's own top edge* (the opponent's goal line from the scorer's POV), which is exactly where the existing single-player burst appears. The non-scoring watch renders no particles for that event — consistent with "celebration means you scored."

```swift
if let event = snapshot.scoreEvent, event.scoredBy == myRole {
    spawnScoreBurst(atX: event.impactX)   // X is symmetric; no flip needed
}
```

### Wrist-down grace window

Each watch tracks its own `scenePhase`. On `.inactive`, start a 3-second timer and send a reliable `paused` message (new `MessageKind.paused`) to the peer so they see a "Opponent paused..." indicator. If phase returns to `.active` within 3 s, send `resumed`. After 3 s, send `forfeit` and transition to game-over.

### Peer identity

Use `WKInterfaceDevice.current().name` as the `MCPeerID` display name when constructing the session. This is the Bluetooth device name the user sees in AirPods, AirDrop, etc.

---

## State machine

### Session state (owned by `MultiplayerService`)

```
       ┌──────────┐
       │   idle   │
       └────┬─────┘
            │ startBrowsing/Advertising
       ┌────▼──────────┐
       │  discovering  │
       └────┬──────────┘
            │ invite sent
       ┌────▼──────────┐
       │   inviting    │
       └────┬──────────┘
            │ invite accepted
       ┌────▼──────────┐
       │   connected   │  ← role determined: initiator = host
       └────┬──────────┘
            │ match end OR disconnect
       ┌────▼──────────┐
       │  disconnected │
       └────┬──────────┘
            │ Back button OR teardown
       ┌────▼─────┐
       │   idle   │
       └──────────┘
```

### Match state (owned by `MultiplayerGameState`)

Mirrors the existing `GamePhase` (`.countdown`, `.playing`, `.gameOver`) but driven by the host's snapshots on the client side and by local physics on the host side. Additions:
- `.pausedByOpponent` — other player's wrist is down; show indicator
- `.disconnected` — session dropped mid-match; this watch wins by default

---

## Open questions deferred to implementation

- Exact `MCNearbyServiceAdvertiser` discoveryInfo payload (probably empty; display name carries all we need)
- Whether to include a version byte in each message for forward compat — **yes**, add `var protoVersion: UInt8 = 1` to every message
- Maximum MC payload size: verify our snapshot stays well under the 64 KB unreliable-mode limit (ours is ~80 bytes JSON — no concern)
- Whether to pre-render both paddles identically or style the opponent's paddle differently (v1: identical)

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| MC Wi-Fi handoff slow (first ~1 s after pairing is BLE-only) | Show "Connecting..." overlay until first snapshot arrives |
| Watch Wi-Fi radio power draw | 30 Hz for limited match duration is acceptable; match is <5 min typically |
| Both watches not on iCloud-associated accounts (AWDL degradation) | MC still works over BLE fallback; document the iCloud recommendation in the Nearby view's empty state |
| Clock skew between watches | Not an issue — we use `tickSeq` for ordering, not timestamps |
| NAT / Wi-Fi isolation | Not applicable — MC uses AWDL (peer-to-peer) not infrastructure Wi-Fi |

---

## Testing strategy

- **Unit tests (`GameStateTests` / new `MultiplayerGameStateTests`):**
  - Snapshot encode/decode roundtrip
  - Client state derivation from snapshot (flip math correct)
  - Host applies client paddle input; out-of-order inputs ignored
  - Score event triggers particle burst on both roles
  - Wrist-down timer starts on `.inactive`, cancels on `.active` within 3 s, forfeits after 3 s

- **Integration tests (two simulators or simulator + real watch):**
  - Full pair flow: advertise → browse → invite → accept → first snapshot received
  - Gameplay: 10-second match, verify both watches stay in sync (scores match, ball positions within extrapolation tolerance)
  - Disconnect mid-match: kill app on one watch, verify other watch sees forfeit
  - Rematch flow: finish match, tap Rematch on both, verify fresh countdown

- **Manual testing (two real Apple Watches):**
  - Pair flow latency (<3 s to first snapshot on same iCloud, nearby)
  - Responsiveness of own paddle (feels local)
  - Responsiveness of opponent paddle (feels smooth, no stutter)
  - Match completion including rematch and back

---

## Rollout

Single feature branch `addMultiplayer`. Merge to `feat/pong-watch-game` via PR when complete. Single-player mode must be untouched behaviorally (regression bar: all existing tests pass, single-player playthrough unchanged).
