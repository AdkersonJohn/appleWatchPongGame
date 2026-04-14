# Apple Watch Pong — Design

**Date:** 2026-04-14
**Status:** Approved design, ready for implementation plan
**Target platform:** watchOS (native), SwiftUI

## Goal

A single-player Pong game for Apple Watch that the user can play to kill time when their phone and computer are not available. The Digital Crown controls the paddle. The game is endless mode: the ball speeds up over time and the user tries to beat their high score.

## Scope

**In:**
- Single-player vs AI opponent
- Endless mode (ball speeds up over time, no win condition)
- High score persisted across app launches
- Digital Crown paddle control with haptic feedback
- Start screen, game screen, game-over screen

**Out (deferred for v1):**
- Settings screen, sound effects, pause UI, difficulty levels, onboarding, multiplayer

## Architecture

Native watchOS app, single target, SwiftUI. Rendering via `Canvas`; game loop via `TimelineView(.animation)`. Game physics is pure Swift in an `ObservableObject`, independent of SwiftUI so it can be unit tested.

### File layout

```
PongWatch/
├── PongWatchApp.swift          // @main entry point
├── ContentView.swift           // Routes between StartView / GameView / GameOverView by phase
├── Game/
│   ├── GameState.swift         // ObservableObject: ball, paddles, score, phase, update(dt:)
│   ├── GameView.swift          // Canvas renderer + TimelineView loop + crown input
│   └── GameConstants.swift     // Paddle dimensions, initial ball speed, speed scaling curve
├── Screens/
│   ├── StartView.swift         // "Tap to Play" + high score display
│   └── GameOverView.swift      // Final score, new-high-score indicator, tap to restart
└── Persistence/
    └── HighScore.swift         // @AppStorage wrapper
```

### Layout orientation

Vertical Pong: paddles on top (AI) and bottom (player); ball bounces off the left and right walls. The Digital Crown moves the player paddle horizontally along the bottom edge.

## Data Model

```swift
enum GamePhase { case start, playing, gameOver }

struct Ball {
    var position: CGPoint   // normalized 0...1
    var velocity: CGVector  // normalized units per second
}

class GameState: ObservableObject {
    @Published var phase: GamePhase = .start
    @Published var ball: Ball
    @Published var playerPaddleX: CGFloat   // normalized center x, bottom paddle
    @Published var aiPaddleX: CGFloat       // normalized center x, top paddle
    @Published var score: Int = 0
}
```

### Key modeling decisions

1. **Normalized coordinates (0.0–1.0)** for all positions and velocities. The `Canvas` multiplies by `size.width` / `size.height` at render time so the game scales across watch sizes (40mm through Ultra) without per-device math.

2. **Score = successful player paddle hits only.** Every time the player paddle returns the ball, `score += 1`. Ball exit off the bottom ends the game. Ball exit off the top (AI missed) resets the ball to center but keeps the game going and does not change the score. This produces a clean "how long can you survive" feel that matches endless mode.

3. **Ball speed scales with score.** Every 5 hits, the ball velocity magnitude increases ~10% up to a cap of roughly 3× the initial speed. This is the endless-mode difficulty curve.

4. **AI paddle behavior.** Simple tracking: AI paddle x lerps toward `ball.position.x` at a capped speed slightly below the ball's maximum horizontal speed. Tuned so the AI is beatable but competent. Difficulty comes from ball speed, not from AI getting smarter.

5. **High score** lives separately in `@AppStorage("highScore")`. It is not part of `GameState`; `GameState` only reads it and requests writes on game over.

## Game Loop

`TimelineView(.animation)` drives the loop at ~60 Hz. `Canvas` renders each frame after `GameState.update(dt:)` runs:

```swift
TimelineView(.animation) { timeline in
    Canvas { context, size in
        gameState.update(dt: computedDt, screenSize: size)
        // draw background, paddles, ball, score
    }
}
```

### `GameState.update(dt:)` per frame

1. Move ball by `velocity * dt`.
2. Collide with left/right walls → flip `velocity.x`, clamp position.
3. Collide with player paddle (ball overlaps paddle rect at the bottom):
   - Flip `velocity.y`.
   - Adjust angle based on impact point on paddle (center = straight, edge = sharp angle).
   - `score += 1`.
   - If the new score is a multiple of 5 and the ball is below its speed cap, bump speed by 10%.
   - Play `.click` haptic via `WKInterfaceDevice.current().play(.click)`.
4. Collide with AI paddle (top): flip `velocity.y`, apply the same impact-point angle adjustment as the player paddle. No haptic and no score change.
5. If ball exits top → reset ball to center, keep `phase = .playing`, score unchanged.
6. If ball exits bottom → `phase = .gameOver`, check and update persisted high score.

`dt` is computed from timeline timestamps so physics is framerate-independent if watchOS throttles below 60fps.

### AI paddle update

Each frame, move `aiPaddleX` toward `ball.position.x` by up to `aiMaxSpeed * dt`, clamped to the valid paddle range.

## Input

Digital Crown via SwiftUI's native modifier:

```swift
.focusable()
.digitalCrownRotation(
    $crownValue,
    from: 0, through: 1,
    by: 0.01,
    sensitivity: .medium,
    isContinuous: false,
    isHapticFeedbackEnabled: true
)
.onChange(of: crownValue) { newValue in
    gameState.playerPaddleX = clamp(newValue, paddleHalfWidth, 1 - paddleHalfWidth)
}
```

Crown value maps directly to paddle x-position (0 = all the way left, 1 = all the way right). `sensitivity: .medium` gives a proportional feel — small turns move the paddle small amounts, fast turns move it fast. Haptic clicks come for free on rotation. Paddle hit haptic (`.click`) fires in addition on every successful return.

## Rendering

- Background: black.
- Paddles: white rounded rectangles, roughly 20% of screen width and 3% of screen height.
- Ball: white circle, roughly 4% of screen width.
- Score: small white text in the top-left during play; unobtrusive.

All sizes are ratios of the `Canvas` size, so layout is responsive across watch models.

## Screens & Navigation

`ContentView` switches on `gameState.phase`. No `NavigationStack`, no back buttons — Pong on a watch should be zero-friction.

### StartView (`phase == .start`)
- Title: "PONG" (large, centered).
- Below: "High Score: N" (hidden if high score is 0).
- Below: "Tap to Play" (small, subtle).
- Tap anywhere → reset ball to center with randomized initial direction, set `phase = .playing`.

### GameView (`phase == .playing`)
- The `Canvas` + `TimelineView` loop described above.
- Score displayed in top-left corner.
- Digital Crown focused on appear.
- No chrome beyond the score.

### GameOverView (`phase == .gameOver`)
- "Game Over" (large).
- "Score: N" (final score).
- If this run beat the persisted high score: "🏆 New High Score!" line above the score.
- "Tap to Play Again" at the bottom.
- Tap anywhere → reset game state, `phase = .playing`.

## Persistence

`@AppStorage("highScore")` wrapped in a tiny `HighScore` helper. On game over, if `score > storedHighScore`, update storage. Survives app backgrounding and device restart automatically via `UserDefaults`.

## Testing Strategy

### Unit tests (XCTest)

`GameState` is pure Swift and has no SwiftUI or WatchKit dependencies, so it is fully unit-testable. Target cases:

- Ball bounces off left/right walls: `velocity.x` flips, position stays in bounds.
- Ball hits player paddle: `velocity.y` flips, `score += 1`.
- Ball exits bottom: `phase` transitions to `.gameOver`.
- Ball exits top: ball resets to center, `phase` stays `.playing`, score unchanged.
- Speed scaling: after N hits, `|velocity|` increases within the expected range and is capped at the maximum.
- High score update: a score greater than the stored value updates storage; a score lower than the stored value does not.
- Paddle clamp: `playerPaddleX` stays within `[paddleHalfWidth, 1 - paddleHalfWidth]`.

### Manual testing — watchOS Simulator

- Tap-to-start transitions correctly.
- Digital Crown moves paddle smoothly (simulator offers a crown slider).
- Haptics fire on paddle hit (simulator shows a haptic events panel).
- Game over transition works.
- High score persists across app relaunches in the simulator.

### Manual testing — real Apple Watch

Before calling v1 done, pair a physical watch to Xcode, deploy, and play. Two things you can only validate on-device:

- Haptic feel on crown rotation.
- Whether paddle / ball sizes feel right on the physical screen.

### Explicitly not doing

- No UI snapshot tests (overkill at this scope; watchOS snapshot tooling is thin).
- No Playwright tests (native app, not web — the repo's Playwright rule is about web debugging).
- No performance benchmarks (60 fps on four moving shapes is not a concern).

## Open questions

None — all design decisions confirmed with user during brainstorming.

## Next step

An implementation plan (writing-plans skill) to break this design into ordered, testable build steps appropriate for a first-time watchOS developer.
