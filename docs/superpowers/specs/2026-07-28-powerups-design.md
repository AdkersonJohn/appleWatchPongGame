# Power-Ups — Design

**Status:** Approved
**Date:** 2026-07-28
**Project:** PongWatch / Pong Pal Showdown (watchOS)

## Summary

Pickups spawn at the center of the playfield during rallies and drift slowly toward the top or bottom paddle. If the paddle they drift toward intercepts them, that side gains the associated power-up. Four power-ups ship in the initial set: wide paddle, shield, sticky ball, and multi-ball. The feature applies to **both single-player and multiplayer**; multiplayer stays host-authoritative and inherits the whole system through the snapshot.

## Goals

- Add an occasional, legible power-up layer without changing Pong's core feel
- Keep the model layer pure and unit-testable (no rendering or networking dependencies)
- Preserve existing single-ball behavior exactly when no power-ups are active
- Contain the multi-ball engine refactor (`ball` → `balls: [Ball]`) so it lands last, on top of a proven system

## Non-goals

- Sound effects (game has none; haptics only)
- Power-up settings/toggles, difficulty tuning UI
- More than one pickup on screen at a time
- Backward wire-protocol compatibility (nothing has shipped; both watches must run the same build)

## Spawning and interception

- Pickups spawn only during active play — never during a 3-2-1 serve countdown.
- At most one pickup on screen. After the previous pickup resolves (caught or despawned), a random **12–20 s of live rally time** elapses before the next spawn. The spawn timer does not accrue during countdowns or pause.
- Spawn position is center screen `(0.5, 0.5)`. Kind is chosen with equal weights. Drift direction is a random side (top or bottom), at **0.08 normalized units/s**.
- The ball passes through pickups; there is no ball–pickup interaction.
- Only the paddle the pickup drifts toward can intercept it: AABB overlap between the paddle (current width) and the pickup (radius = **1.5 × ball radius**). Interception grants the power-up to that side and fires a success haptic (distinct from the paddle-hit click).
- If the pickup passes the paddle line uncaught, it despawns.
- When a point resets the serve, any on-screen pickup despawns; active effects persist.

## The four power-ups

| Power-up | Effect | Duration / consumption | Same-kind re-catch |
|---|---|---|---|
| Wide paddle | Intercepting side's paddle width × **1.5** | **10 s** of live rally time (timer frozen during serve countdowns and pause) | Refreshes timer |
| Shield | One-use full-width barrier just behind the paddle; a ball that would exit that side bounces off it, then the shield vanishes | Until used | No-op |
| Sticky ball | Next ball contact sticks the ball to the paddle; it rides the paddle. Tap the screen to release; release uses normal impact-offset steering from the ball's position on the paddle. Auto-release after **3 s** | One catch per pickup | Refreshes (re-arms) |
| Multi-ball | Ball splits into **3** (two clones at ±20°, same speed). Effect ends when one ball remains | Until one ball remains | Tops ball count back up to 3 (hard cap 3) |

Multi-ball rules: every ball obeys normal rules. In multiplayer, each ball that crosses a goal line scores for the opponent of that side and is removed; the serve countdown only triggers when the last ball scores. In single-player, a ball past the AI scores a point and is removed; a ball past the player is lost with no penalty unless it was the **last** ball, which is game over — multi-ball therefore doubles as a survival buffer.

Stacking: different kinds may be active simultaneously on the same side, and both sides may hold effects at once. In single-player the AI can intercept pickups drifting its way and receives identical effects; the AI's sticky release is automatic after **1 s**, aimed by its normal tracking position.

Edge behaviors:

- A stuck ball counts as in play (it cannot trigger a serve reset, and it cannot be saved by/consume a shield).
- With sticky + multi-ball, only the ball that touches the armed paddle sticks; others keep flying.
- If wide paddle expires while a ball is stuck, the ball's offset clamps to the new width.
- `reset()`, rematch, and game over clear the entire power-up system.
- Wrist-down pause freezes the host simulation, which freezes pickup drift, effect timers, and the sticky hold clock — no special handling.

## Architecture

### `Game/PowerUpSystem.swift` (new)

A pure model type owned by `GameState`. Owns: spawn timer, the drifting pickup (kind, position, drift direction), and per-side active effects. Side is expressed as bottom/top; single-player maps this to player/AI, multiplayer maps it to host/client.

- Driven by one call per physics tick from `GameState` (advance timers, move pickup, test interception against current paddle rects).
- Query surface read by `GameState` and rendering: `paddleWidth(for:)`, `hasShield(for:)`, `stickyArmed(for:)`, current pickup, active effects.
- Mutations invoked by `GameState` on game events: `consumeShield(for:)`, sticky arm/consume, multi-ball grant.
- Randomness (spawn interval, kind, side) flows through an injectable seeded RNG, mirroring the injectable `HapticPlayer` pattern, so tests are deterministic.

### `GameState` changes

1. `ball: Ball` becomes `balls: [Ball]`. Physics, wall/paddle collision, and exit checks loop over the array. With one ball the behavior is bit-for-bit today's behavior; existing tests must pass unchanged.
2. Paddle collision reads per-side width from `PowerUpSystem` instead of `GameConstants.paddleWidth`; exit checks consult shield (bounce + consume) before scoring/game-over.
3. New entry points: `tapRelease(side:)` for sticky release; serve/countdown paths reset to a single centered ball.

### Rendering and input (`GameView`)

- Canvas draws: all balls, the pickup (colored circle + SF Symbol glyph), the shield line, per-side paddle widths, and a green tint on a sticky-armed/holding paddle. Colors per kind: wide = gold, shield = blue, sticky = green, multi-ball = orange (drawn from the particle palette family).
- `.onTapGesture` on the playfield calls the sticky release for the local side.
- No new screens or navigation.

### `GameConstants` additions

Spawn interval range, drift speed, pickup radius factor, wide factor (1.5) and duration (10 s), sticky auto-release (3 s player / 1 s AI), multi-ball count (3) and split angle (±20°), pickup colors.

## Multiplayer data flow

- **Host simulates everything.** `PowerUpSystem` runs only inside the host's `GameState`. The client renders snapshot state and never simulates power-ups.
- **`GameSnapshot` changes:** `ballX/Y/VX/VY` becomes `balls: [BallState]` (position + velocity). New fields: `pickup: PickupState?` (kind, position), `effects: [SideEffectState]` (kind, side, remaining seconds where applicable), and one-shot `pickupCollected: PeerRole?` (mirroring `hostPaddleHit`) so the client fires the success haptic for its own catches. Client Y-flips ball and pickup positions as it does today.
- **New message:** `NetworkMessage.stickyRelease`, client → host, sent on the client's screen tap. Host validates (ignored unless the client actually holds a stuck ball) and performs the release in simulation. The 3 s auto-release runs host-side for both roles, so a lost message cannot stall the match.
- **Protocol version:** `multiplayerProtocolVersion` bumps **1 → 2**. No compatibility shims.
- Pause/forfeit/disconnect/rematch paths are unchanged; rematch resets the system via `startGame()`.

## Testing

- **`PowerUpSystemTests` (new):** seeded spawn timing and kind selection; drift and despawn geometry; interception vs. current paddle width; effect lifecycle — wide expiry/refresh, shield consume/no-op, sticky arm/consume/auto-release clocks, multi-ball top-up and cap; timer freeze during countdown/pause.
- **`GameStateTests` (additions):** existing suite passes unchanged after the `balls` refactor; multi-ball scoring/removal/last-ball game-over; wide-paddle collision window; shield save bounce; sticky catch, tap release steering, auto-release.
- **`MultiplayerGameStateTests` (additions):** snapshot round-trip with balls/pickup/effects; client applies them Y-flipped; `stickyRelease` ignored when not armed; pickup-collected haptic on the client; protocol v2.
- **Manual:** two-simulator multiplayer match; physical-watch pass for tap-gesture feel and pickup legibility at 40–46 mm sizes.

## Delivery order

1. `PowerUpSystem` scaffold + spawn/drift/interception + wide paddle (proves the whole pipeline end-to-end)
2. Shield, then sticky ball (adds tap input + new network message)
3. Multi-ball last: `balls` refactor + snapshot array + scoring rules
4. Protocol bump, multiplayer snapshot integration, and the manual two-sim pass close it out
