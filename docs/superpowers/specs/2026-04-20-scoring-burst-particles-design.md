# Scoring Burst Particles — Design

**Status:** Approved
**Date:** 2026-04-20
**Project:** PongWatch (watchOS)

## Summary

When the player scores (ball exits top past the AI paddle), emit a short-lived particle burst at the impact site to create a celebratory reward moment. The burst plays out during the existing 3-2-1 countdown that precedes the next serve.

## Goals

- Reinforce the "you scored!" feeling with a visual reward
- Stay within watchOS rendering budget (lightweight, ~20 particles per burst, all drawn in the existing `Canvas`)
- Keep integration surface small: one new struct, one new state array on `GameState`, one new draw pass in `GameView`

## Non-goals

- Particles on paddle hits (the design flow is reserved for scoring only)
- Particle interactions with walls, paddles, or gravity
- Configurable palettes or intensity scaling over time
- Sound (out of scope; haptics unchanged)

## Trigger and location

- **When:** inside `stepPhysics`, in the `ball.position.y < 0` branch, immediately before `startCountdown()` is called
- **Where:** `(ball.position.x, 0.0)` — the exact normalized x-coordinate where the ball crossed the top edge

## Particle model

```swift
struct Particle {
    var position: CGPoint       // normalized 0…1 in both axes
    var velocity: CGVector      // normalized units per second
    var ageRemaining: CGFloat   // seconds until removal
    var totalAge: CGFloat       // original lifespan, for alpha fade
    var radius: CGFloat         // normalized fraction of screen width
    var color: Color            // SwiftUI Color
}
```

Stored on `GameState` as `@Published var particles: [Particle] = []`.

## Burst parameters

| Property   | Value                                                              |
| ---------- | ------------------------------------------------------------------ |
| Count      | 20 per burst                                                       |
| Direction  | Sampled per particle as `dx ∈ [-1, 1]` uniform random, `dy ∈ [0.1, 1.0]` uniform random, then normalized to unit length and scaled by a random Speed. This produces a fan biased downward into the playfield (since `dy > 0` always) while allowing wide lateral spread. |
| Speed      | Uniform random in `[0.4, 1.2]` normalized units/sec                |
| Lifespan   | Uniform random in `[0.4, 0.8]` seconds                             |
| Radius     | `GameConstants.ballRadius * 0.4` (fragment-like, smaller than ball)|
| Palette    | Uniform random pick per particle from: gold `#FFD700`, orange `#FF8C00`, red-orange `#FF4500`, yellow `#FFEA00` |
| Gravity    | None                                                               |
| Alpha fade | `opacity = ageRemaining / totalAge` (linear fade to 0)             |

The downward bias is intentional: the ball came from below, so a burst that emits primarily into the playfield (not off-screen above) reads as an impact on the top edge rather than a generic explosion.

## Lifecycle

- `spawnScoreBurst(at x: CGFloat)` — appends 20 new particles to `particles` at `(x, 0)` with random properties per the table above
- `updateParticles(dt: CGFloat)` — for each particle: `position += velocity * dt`; `ageRemaining -= dt`; then filter out particles with `ageRemaining <= 0`. Called on every `update(dt:)` tick, including while the countdown is active (so the burst plays out during "3-2-1")
- `reset()` — clears the array

## Rendering

In `GameView.drawPlayfield`, after paddles and before/after the ball/countdown branch, iterate `state.particles`:

```swift
for p in state.particles {
    let center = CGPoint(x: p.position.x * size.width, y: p.position.y * size.height)
    let r = p.radius * size.width
    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    let alpha = max(0, p.ageRemaining / p.totalAge)
    context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(alpha)))
}
```

## Integration with existing systems

- The countdown continues to freeze ball physics; particle updates run in both the countdown branch and the physics branch of `update(dt:)`. Concretely: `updateParticles(dt:)` is called unconditionally at the top of `update(dt:)` (after the `phase == .playing` guard), before the countdown short-circuit
- `reset()` clears particles so a restarted game begins empty
- Particles do not interact with collision logic at all

## Constants

Add to `GameConstants`:

```swift
static let particlesPerBurst: Int = 20
static let particleMinSpeed: CGFloat = 0.4
static let particleMaxSpeed: CGFloat = 1.2
static let particleMinLifespan: CGFloat = 0.4
static let particleMaxLifespan: CGFloat = 0.8
static let particleRadiusFactor: CGFloat = 0.4   // fraction of ballRadius
```

## Testing

Unit tests in `GameStateTests`:

1. `test_scoringSpawnsParticleBurst` — drive a ball-past-top event, assert `state.particles.count == GameConstants.particlesPerBurst` and all particles start at `(lastBallX, 0)` within tolerance
2. `test_particlesExpireAfterLifespan` — spawn burst, call `update(dt: GameConstants.particleMaxLifespan + 0.01)`, assert `particles.isEmpty`
3. `test_particlesMoveWithTheirVelocity` — spawn a single known particle, tick, verify position advanced by `velocity * dt`
4. `test_resetClearsParticles` — spawn burst, call `reset()`, assert `particles.isEmpty`

No visual tests; acceptance is by-eye on real device.

## Performance note

At 60 FPS with 20 active particles, each frame does 20 arithmetic updates + 20 Canvas circle fills. Negligible for watchOS. Bursts don't overlap much in practice because each lasts ≤0.8s and the countdown between serves is 3s.

## Risks / open items

None open. Count is tuned but easy to adjust in `GameConstants.particlesPerBurst` post-ship if the effect feels too sparse or busy.
