# Scoring Burst Particles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a short-lived, warm-palette particle burst that spawns at the impact site when the player scores, playing out during the existing 3-2-1 countdown.

**Architecture:** Pure-Swift data model (`Particle` struct) + particle array on `GameState`. Spawn on the scoring event (inside `stepPhysics`), integrate per-tick in `update(dt:)`, render in the existing `Canvas` draw closure. No new files are required.

**Tech Stack:** Swift 5.9+, SwiftUI (Canvas), XCTest.

**Spec:** `docs/superpowers/specs/2026-04-20-scoring-burst-particles-design.md`

---

## File Structure

No new files. All changes are additive edits to:

- `PongWatch/PongWatch Watch App/Game/GameTypes.swift` — add `Particle` struct
- `PongWatch/PongWatch Watch App/Game/GameConstants.swift` — add tunables + palette
- `PongWatch/PongWatch Watch App/Game/GameState.swift` — add `particles` array, `spawnScoreBurst`, `updateParticles`; wire into `reset`, `update(dt:)`, and the top-exit branch
- `PongWatch/PongWatch Watch App/Screens/GameView.swift` — render particles in `drawPlayfield`
- `PongWatch/PongWatch Watch AppTests/GameStateTests.swift` — unit tests

**Design note — color representation:** `Particle` stores raw `red`/`green`/`blue` components (not `SwiftUI.Color`) so the model layer (`GameState`) does not need a SwiftUI import. The view converts components to `Color` at render time.

---

## Task 1: Add Particle type and tunables

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameTypes.swift`
- Modify: `PongWatch/PongWatch Watch App/Game/GameConstants.swift`

Introduce the data shape and all tunable constants up-front. No tests — pure types/values with no behavior.

- [ ] **Step 1: Add `Particle` struct to `GameTypes.swift`**

Open `PongWatch/PongWatch Watch App/Game/GameTypes.swift`. Append below the existing `GamePhase` enum:

```swift
struct Particle: Equatable {
    var position: CGPoint       // normalized 0…1 in both axes
    var velocity: CGVector      // normalized units per second
    var ageRemaining: CGFloat   // seconds until removal
    var totalAge: CGFloat       // original lifespan (for alpha fade)
    var radius: CGFloat         // normalized fraction of screen width
    var red: CGFloat            // 0…1
    var green: CGFloat
    var blue: CGFloat
}
```

- [ ] **Step 2: Add particle tunables + palette to `GameConstants.swift`**

Open `PongWatch/PongWatch Watch App/Game/GameConstants.swift`. Append inside the `GameConstants` enum, after the existing `countdownStart`:

```swift
    // Scoring burst
    static let particlesPerBurst: Int = 20
    static let particleMinSpeed: CGFloat = 0.4
    static let particleMaxSpeed: CGFloat = 1.2
    static let particleMinLifespan: CGFloat = 0.4
    static let particleMaxLifespan: CGFloat = 0.8
    static let particleRadiusFactor: CGFloat = 0.4   // fraction of ballRadius

    // Warm palette: gold, orange, red-orange, yellow. Each entry is (r, g, b) in 0…1.
    static let particlePalette: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.843, 0.000),   // gold     #FFD700
        (1.00, 0.549, 0.000),   // orange   #FF8C00
        (1.00, 0.271, 0.000),   // red-orange #FF4500
        (1.00, 0.918, 0.000)    // yellow   #FFEA00
    ]
```

- [ ] **Step 3: Verify project still builds**

Run in Xcode: `⌘B` (Build). Expected: builds cleanly, no new warnings related to these additions.

- [ ] **Step 4: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameTypes.swift" "PongWatch/PongWatch Watch App/Game/GameConstants.swift"
git commit -m "feat(particles): add Particle type and burst tunables"
```

---

## Task 2: `spawnScoreBurst` + `particles` state

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameState.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`

Add the particle array and the spawn method. Test first.

- [ ] **Step 1: Write the failing test**

Open `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`. Add before the closing `}` of the class:

```swift
    func test_spawnScoreBurstCreatesExpectedCountAtGivenX() {
        let state = GameState()
        state.spawnScoreBurst(atX: 0.3)

        XCTAssertEqual(state.particles.count, GameConstants.particlesPerBurst)
        for p in state.particles {
            XCTAssertEqual(p.position.x, 0.3, accuracy: 0.0001)
            XCTAssertEqual(p.position.y, 0.0, accuracy: 0.0001)
        }
    }

    func test_spawnScoreBurstVelocitiesHaveDownwardBiasAndVariedSpeeds() {
        let state = GameState()
        state.spawnScoreBurst(atX: 0.5)

        for p in state.particles {
            // Every particle moves into the playfield (dy > 0)
            XCTAssertGreaterThan(p.velocity.dy, 0, "Particle dy should be positive (moving down)")
            // Speed magnitude within configured range
            let speed = hypot(p.velocity.dx, p.velocity.dy)
            XCTAssertGreaterThanOrEqual(speed, GameConstants.particleMinSpeed - 0.0001)
            XCTAssertLessThanOrEqual(speed, GameConstants.particleMaxSpeed + 0.0001)
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

In Xcode: `⌘U` to run the test target, or via CLI if set up. Expected:
- Both tests FAIL with a compile error: `Value of type 'GameState' has no member 'particles'` / `'spawnScoreBurst'`.

- [ ] **Step 3: Add `particles` state and `spawnScoreBurst` to `GameState.swift`**

Open `PongWatch/PongWatch Watch App/Game/GameState.swift`.

First, add the particles array with the other `@Published` properties (after `countdownRemaining`):

```swift
    @Published var particles: [Particle] = []
```

Next, add `spawnScoreBurst` as a new method. Place it just above `private func startCountdown()`:

```swift
    func spawnScoreBurst(atX x: CGFloat) {
        let origin = CGPoint(x: x, y: 0.0)
        var newParticles: [Particle] = []
        newParticles.reserveCapacity(GameConstants.particlesPerBurst)

        for _ in 0..<GameConstants.particlesPerBurst {
            // Direction: dx in [-1, 1], dy in [0.1, 1] — biases burst into the playfield.
            let rawDx = CGFloat.random(in: -1...1)
            let rawDy = CGFloat.random(in: 0.1...1.0)
            let mag = hypot(rawDx, rawDy)
            let ux = rawDx / mag
            let uy = rawDy / mag

            let speed = CGFloat.random(in: GameConstants.particleMinSpeed...GameConstants.particleMaxSpeed)
            let lifespan = CGFloat.random(in: GameConstants.particleMinLifespan...GameConstants.particleMaxLifespan)
            let color = GameConstants.particlePalette.randomElement()!

            newParticles.append(Particle(
                position: origin,
                velocity: CGVector(dx: ux * speed, dy: uy * speed),
                ageRemaining: lifespan,
                totalAge: lifespan,
                radius: GameConstants.ballRadius * GameConstants.particleRadiusFactor,
                red: color.0,
                green: color.1,
                blue: color.2
            ))
        }
        particles = newParticles
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

`⌘U`. Expected: both new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameState.swift" "PongWatch/PongWatch Watch AppTests/GameStateTests.swift"
git commit -m "feat(particles): spawn 20-particle burst at scoring impact site"
```

---

## Task 3: `updateParticles` lifecycle

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameState.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`

Add the per-tick update: integrate position, decay lifespan, drop dead particles. Test first.

- [ ] **Step 1: Write the failing tests**

Append inside the test class:

```swift
    func test_updateParticlesAdvancesPositionAndDecaysAge() {
        let state = GameState()
        let p = Particle(
            position: CGPoint(x: 0.5, y: 0.0),
            velocity: CGVector(dx: 0.2, dy: 0.5),
            ageRemaining: 1.0,
            totalAge: 1.0,
            radius: 0.01,
            red: 1, green: 1, blue: 1
        )
        state.particles = [p]

        state.updateParticles(dt: 0.1)

        XCTAssertEqual(state.particles.count, 1)
        let updated = state.particles[0]
        XCTAssertEqual(updated.position.x, 0.52, accuracy: 0.0001)
        XCTAssertEqual(updated.position.y, 0.05, accuracy: 0.0001)
        XCTAssertEqual(updated.ageRemaining, 0.9, accuracy: 0.0001)
    }

    func test_updateParticlesRemovesExpiredParticles() {
        let state = GameState()
        let p = Particle(
            position: CGPoint(x: 0.5, y: 0.0),
            velocity: CGVector(dx: 0, dy: 0),
            ageRemaining: 0.1,
            totalAge: 0.5,
            radius: 0.01,
            red: 1, green: 1, blue: 1
        )
        state.particles = [p]

        state.updateParticles(dt: 0.2)  // past the age

        XCTAssertTrue(state.particles.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

`⌘U`. Expected: both new tests FAIL with `no member 'updateParticles'`.

- [ ] **Step 3: Implement `updateParticles`**

In `GameState.swift`, add just above `private func startCountdown()`:

```swift
    func updateParticles(dt: CGFloat) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.dx * dt
            particles[i].position.y += particles[i].velocity.dy * dt
            particles[i].ageRemaining -= dt
        }
        particles.removeAll { $0.ageRemaining <= 0 }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

`⌘U`. Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameState.swift" "PongWatch/PongWatch Watch AppTests/GameStateTests.swift"
git commit -m "feat(particles): add per-tick motion and lifespan decay"
```

---

## Task 4: `reset()` clears particles

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameState.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside the test class:

```swift
    func test_resetClearsParticles() {
        let state = GameState()
        state.spawnScoreBurst(atX: 0.5)
        XCTAssertFalse(state.particles.isEmpty)  // sanity

        state.reset()

        XCTAssertTrue(state.particles.isEmpty)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

`⌘U`. Expected: FAIL — `particles` still populated after `reset()`.

- [ ] **Step 3: Update `reset()` to clear particles**

In `GameState.swift`, find the `reset()` function and add a new line at the end of the body (after `countdownElapsed = 0`):

```swift
        particles = []
```

The full resulting function body:

```swift
    func reset() {
        phase = .start
        score = 0
        lastRunWasRecord = false
        currentBallSpeed = GameConstants.initialBallSpeed
        ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)
        playerPaddleX = 0.5
        aiPaddleX = 0.5
        countdownRemaining = nil
        countdownElapsed = 0
        particles = []
    }
```

- [ ] **Step 4: Run the test to verify it passes**

`⌘U`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameState.swift" "PongWatch/PongWatch Watch AppTests/GameStateTests.swift"
git commit -m "feat(particles): clear particles on game reset"
```

---

## Task 5: `update(dt:)` ticks particles every frame

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameState.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`

Particles must animate during both physics and countdown phases. Simplest insertion point: call `updateParticles` at the top of `update(dt:)` (after the `phase == .playing` guard, before the countdown short-circuit).

- [ ] **Step 1: Write the failing test**

Append inside the test class:

```swift
    func test_updateTicksParticlesDuringCountdown() {
        let state = GameState()
        state.startGame()  // enters .playing with active countdown
        state.spawnScoreBurst(atX: 0.5)
        let initialAge = state.particles.first?.ageRemaining ?? 0
        XCTAssertGreaterThan(initialAge, 0)

        state.update(dt: 0.1)  // still mid-countdown

        XCTAssertNotNil(state.countdownRemaining, "Should still be counting down")
        XCTAssertFalse(state.particles.isEmpty, "Particles should still be alive")
        let newAge = state.particles.first!.ageRemaining
        XCTAssertLessThan(newAge, initialAge, "Particle age should have decayed")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

`⌘U`. Expected: FAIL — `updateParticles` is never called during countdown, so `ageRemaining` is unchanged.

- [ ] **Step 3: Wire `updateParticles` into `update(dt:)`**

In `GameState.swift`, modify `update(dt:)` to call `updateParticles` immediately after the `phase` guard, before the countdown short-circuit:

```swift
    func update(dt: CGFloat) {
        guard phase == .playing else { return }

        updateParticles(dt: dt)

        // While the 3-2-1 countdown is running, the ball sits at center with
        // zero velocity. Advance the countdown and skip physics this tick.
        if countdownRemaining != nil {
            tickCountdown(dt: dt)
            return
        }

        // …existing sub-stepped physics below unchanged…
```

- [ ] **Step 4: Run the test to verify it passes**

`⌘U`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameState.swift" "PongWatch/PongWatch Watch AppTests/GameStateTests.swift"
git commit -m "feat(particles): animate particles every game tick (incl. countdown)"
```

---

## Task 6: Spawn burst when the player scores

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Game/GameState.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GameStateTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside the test class:

```swift
    func test_scoringSpawnsBurstAtImpactX() {
        let state = GameState()
        state.phase = .playing
        let impactX: CGFloat = 0.37
        state.ball = Ball(
            position: CGPoint(x: impactX, y: -0.01),
            velocity: CGVector(dx: 0, dy: -0.5)
        )

        state.update(dt: 0.01)  // triggers scoring

        XCTAssertEqual(state.score, 1)
        XCTAssertEqual(state.particles.count, GameConstants.particlesPerBurst)
        // Every particle starts at (impactX, 0) before first tick of motion.
        // The same update(dt: 0.01) call also runs updateParticles once, so
        // allow a 1-tick displacement tolerance.
        let maxDisplacement = GameConstants.particleMaxSpeed * 0.01 + 0.0001
        for p in state.particles {
            XCTAssertEqual(p.position.x, impactX, accuracy: maxDisplacement)
            XCTAssertLessThanOrEqual(p.position.y, maxDisplacement)
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

`⌘U`. Expected: FAIL — `particles.count` is 0, no burst on scoring yet.

- [ ] **Step 3: Call `spawnScoreBurst` in the top-exit branch**

In `GameState.swift`, inside `stepPhysics`, locate the block:

```swift
        // Ball exits top (AI missed) — player scores a point, start countdown.
        if ball.position.y < 0 {
            score += 1
            if score % GameConstants.pointsPerSpeedTier == 0,
               currentBallSpeed < GameConstants.maxBallSpeed {
                let bumped = currentBallSpeed * (1 + GameConstants.speedIncreasePerTier)
                currentBallSpeed = min(bumped, GameConstants.maxBallSpeed)
            }
            startCountdown()
        }
```

Add a `spawnScoreBurst` call using the ball's x at crossing, before `startCountdown()` (which will reset the ball to center):

```swift
        // Ball exits top (AI missed) — player scores a point, start countdown.
        if ball.position.y < 0 {
            score += 1
            if score % GameConstants.pointsPerSpeedTier == 0,
               currentBallSpeed < GameConstants.maxBallSpeed {
                let bumped = currentBallSpeed * (1 + GameConstants.speedIncreasePerTier)
                currentBallSpeed = min(bumped, GameConstants.maxBallSpeed)
            }
            spawnScoreBurst(atX: ball.position.x)
            startCountdown()
        }
```

- [ ] **Step 4: Run the test to verify it passes**

`⌘U`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Game/GameState.swift" "PongWatch/PongWatch Watch AppTests/GameStateTests.swift"
git commit -m "feat(particles): spawn scoring burst at ball impact site"
```

---

## Task 7: Render particles in `GameView`

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Screens/GameView.swift`

No unit test — verification is visual on a real device / simulator.

- [ ] **Step 1: Add a particle draw pass in `drawPlayfield`**

Open `PongWatch/PongWatch Watch App/Screens/GameView.swift`. Locate the `drawPlayfield(context:size:)` method. After the `// Score` block at the bottom, append:

```swift
        // Scoring burst particles
        for p in state.particles {
            let center = CGPoint(x: p.position.x * size.width, y: p.position.y * size.height)
            let r = p.radius * size.width
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let alpha = max(0, min(1, p.ageRemaining / p.totalAge))
            let color = Color(red: p.red, green: p.green, blue: p.blue).opacity(alpha)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
```

- [ ] **Step 2: Build and run on the watch (or simulator)**

Run the app in Xcode: `⌘R`. Start a game, rally, and intentionally let the ball past the AI paddle.

**Expected:**
- A short burst of ~20 warm-colored dots erupts from the top edge at the ball's crossing x.
- Particles fan out into the playfield (downward bias), fading to transparent over 0.4–0.8 seconds.
- Burst is fully gone by the time the "3" in the countdown appears (or during the "3" at the latest).
- Ball does not appear until the countdown ends.

If the burst feels too sparse or too dense, adjust `GameConstants.particlesPerBurst`. If particles feel too fast/slow, adjust `particleMinSpeed`/`particleMaxSpeed`. If the color doesn't pop, tweak the palette RGB values.

- [ ] **Step 3: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Screens/GameView.swift"
git commit -m "feat(particles): render scoring burst in GameView"
```

---

## Self-review notes

This plan was self-reviewed against the spec. Coverage:

- **Trigger/location** — Task 6 (in top-exit branch, at `ball.position.x`, before `startCountdown`)
- **Particle model** — Task 1 (`Particle` struct with position/velocity/age/radius + RGB components instead of `Color` to keep model UI-free)
- **Burst parameters** — Task 1 (constants) + Task 2 (random sampling applying them)
- **Lifecycle** — `spawnScoreBurst` (Task 2), `updateParticles` (Task 3), `reset` clears (Task 4), wired into `update(dt:)` (Task 5)
- **Rendering** — Task 7 (Canvas draw pass with opacity fade)
- **Testing** — Tasks 2–6 add 7 unit tests covering spawn shape, velocity bias, motion, expiry, reset clearing, and scoring trigger integration
