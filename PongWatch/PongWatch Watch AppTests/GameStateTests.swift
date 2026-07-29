import XCTest
@testable import PongWatch_Watch_App

final class FakeHapticPlayer: HapticPlayer {
    var playedCount = 0
    var successCount = 0
    func playClick() { playedCount += 1 }
    func playSuccess() { successCount += 1 }
}

final class GameStateTests: XCTestCase {
    func test_resetPutsGameInStartPhaseAndCenteredBall() {
        let state = GameState()
        state.phase = .gameOver
        state.score = 42

        state.reset()

        XCTAssertEqual(state.phase, .start)
        XCTAssertEqual(state.score, 0)
        XCTAssertEqual(state.ball.position.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.ball.position.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.playerPaddleX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.aiPaddleX, 0.5, accuracy: 0.0001)
    }

    func test_startGameMovesToPlayingPhase() {
        let state = GameState()
        state.startGame()
        XCTAssertEqual(state.phase, .playing)
    }

    func test_startGameStartsCountdownWithBallStationary() {
        let state = GameState()
        state.startGame()
        XCTAssertEqual(state.countdownRemaining, GameConstants.countdownStart)
        XCTAssertEqual(state.ball.velocity.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(state.ball.velocity.dy, 0, accuracy: 0.0001)
    }

    func test_countdownLaunchesBallAfterElapsedTime() {
        let state = GameState()
        state.startGame()

        // Tick through the full countdown
        state.update(dt: CGFloat(GameConstants.countdownStart))

        XCTAssertNil(state.countdownRemaining)
        let mag = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
        XCTAssertEqual(mag, GameConstants.initialBallSpeed, accuracy: 0.0001)
    }

    func test_updateMovesBallByVelocityTimesDt() {
        let state = GameState()
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.2, dy: -0.1))

        state.update(dt: 0.5)

        XCTAssertEqual(state.ball.position.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(state.ball.position.y, 0.45, accuracy: 0.0001)
    }

    func test_updateDoesNothingWhenNotPlaying() {
        let state = GameState()
        state.phase = .start
        state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.2, dy: 0.0))

        state.update(dt: 0.5)

        XCTAssertEqual(state.ball.position.x, 0.5, accuracy: 0.0001)
    }

    func test_ballBouncesOffLeftWall() {
        let state = GameState()
        state.phase = .playing
        // Ball near left wall moving further left
        state.ball = Ball(position: CGPoint(x: GameConstants.ballRadius * 0.5, y: 0.5),
                          velocity: CGVector(dx: -0.5, dy: 0))

        state.update(dt: 0.01)

        XCTAssertGreaterThan(state.ball.velocity.dx, 0, "Velocity.dx should flip to positive")
        XCTAssertGreaterThanOrEqual(state.ball.position.x, GameConstants.ballRadius)
    }

    func test_ballBouncesOffRightWall() {
        let state = GameState()
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 1.0 - GameConstants.ballRadius * 0.5, y: 0.5),
                          velocity: CGVector(dx: 0.5, dy: 0))

        state.update(dt: 0.01)

        XCTAssertLessThan(state.ball.velocity.dx, 0, "Velocity.dx should flip to negative")
        XCTAssertLessThanOrEqual(state.ball.position.x, 1.0 - GameConstants.ballRadius)
    }

    func test_ballHitsPlayerPaddleAndBouncesUp() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Ball just above paddle, moving down into it
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertLessThan(state.ball.velocity.dy, 0, "Should bounce upward")
        XCTAssertEqual(state.score, 0, "Paddle hit does not change score")
    }

    func test_ballMissesPlayerPaddleWhenOffsetHorizontally() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.2  // Paddle on left
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Ball at x=0.8, clearly not above paddle
        state.ball = Ball(
            position: CGPoint(x: 0.8, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertGreaterThan(state.ball.velocity.dy, 0, "Ball should keep moving down")
        XCTAssertEqual(state.score, 0)
    }

    func test_ballHitEdgeOfPaddleDeflectsAtAngle() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        // Hit the right edge of the paddle
        let hitX = 0.5 + GameConstants.paddleWidth / 2 - 0.005
        state.ball = Ball(
            position: CGPoint(x: hitX, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertLessThan(state.ball.velocity.dy, 0, "Bounces up")
        XCTAssertGreaterThan(state.ball.velocity.dx, 0, "Deflects to the right")
    }

    func test_ballHitsAIPaddleAndBouncesDown() {
        let state = GameState()
        state.phase = .playing
        state.aiPaddleX = 0.5
        let paddleY = GameConstants.paddleMarginY
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: paddleY + GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: -0.5)
        )

        state.update(dt: 0.05)

        XCTAssertGreaterThan(state.ball.velocity.dy, 0, "Should bounce down")
        XCTAssertEqual(state.score, 0, "AI hit does not change score")
    }

    func test_ballExitTopScoresPointAndStartsCountdown() {
        let state = GameState()
        state.phase = .playing
        state.score = 3
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: -0.01),
            velocity: CGVector(dx: 0, dy: -0.5)
        )

        state.update(dt: 0.01)

        XCTAssertEqual(state.phase, .playing)
        XCTAssertEqual(state.score, 4, "Ball past AI paddle = player scores a point")
        XCTAssertEqual(state.countdownRemaining, GameConstants.countdownStart)
        XCTAssertEqual(state.ball.position.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.ball.position.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.ball.velocity.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(state.ball.velocity.dy, 0, accuracy: 0.0001)
    }

    func test_ballExitBottomTransitionsToGameOver() {
        let state = GameState()
        state.phase = .playing
        state.score = 7
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: 1.01),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.01)

        XCTAssertEqual(state.phase, .gameOver)
        XCTAssertEqual(state.score, 7, "Final score preserved for display")
    }

    func test_aiPaddleMovesTowardBall() {
        let state = GameState()
        state.phase = .playing
        state.aiPaddleX = 0.3
        // Ball in upper half, to the right
        state.ball = Ball(
            position: CGPoint(x: 0.8, y: 0.3),
            velocity: CGVector(dx: 0, dy: 0)
        )

        state.update(dt: 0.1)

        XCTAssertGreaterThan(state.aiPaddleX, 0.3, "AI paddle should move right toward ball")
        // And it shouldn't teleport — capped by aiMaxSpeed * dt
        let maxMove = GameConstants.aiMaxSpeed * 0.1
        XCTAssertLessThanOrEqual(state.aiPaddleX - 0.3, maxMove + 0.0001)
    }

    func test_aiPaddleStaysInBounds() {
        let state = GameState()
        state.phase = .playing
        state.aiPaddleX = GameConstants.paddleWidth / 2 + 0.001
        state.ball = Ball(
            position: CGPoint(x: 0.0, y: 0.3),
            velocity: .zero
        )

        // Simulate many frames
        for _ in 0..<100 {
            state.update(dt: 0.1)
        }

        XCTAssertGreaterThanOrEqual(state.aiPaddleX, GameConstants.paddleWidth / 2)
    }

    func test_ballSpeedIncreasesAfterFifthHit() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY

        // Drive exactly 5 paddle hits. Between hits, reset the ball to just-above-paddle
        // moving straight down at initial speed so each update triggers a fresh collision.
        // The 5th hit should trigger a speed-tier bump and rescale the post-bounce velocity.
        for _ in 0..<5 {
            state.ball = Ball(
                position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
                velocity: CGVector(dx: 0, dy: GameConstants.initialBallSpeed)
            )
            state.update(dt: 0.01)
        }

        let newSpeed = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
        let expected = GameConstants.initialBallSpeed * (1 + GameConstants.speedIncreasePerTier)
        XCTAssertEqual(newSpeed, expected, accuracy: 0.0001)
    }

    func test_ballSpeedDoesNotExceedMax() {
        let state = GameState()
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY

        // Drive many paddle hits. Each iteration resets the ball to above-paddle
        // moving downward at its CURRENT speed, preserving the running speed bumps.
        // Speed bumps every 5 hits; after ~12 tiers it should saturate at maxBallSpeed.
        for _ in 0..<100 {
            let currentSpeed = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
            let effectiveSpeed = max(currentSpeed, GameConstants.initialBallSpeed)
            state.ball = Ball(
                position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
                velocity: CGVector(dx: 0, dy: effectiveSpeed)
            )
            state.update(dt: 0.01)
        }

        let finalSpeed = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
        XCTAssertLessThanOrEqual(finalSpeed, GameConstants.maxBallSpeed + 0.0001)
    }

    func test_setPlayerPaddleClampsToLeft() {
        let state = GameState()
        state.setPlayerPaddle(normalizedCrown: -0.2)
        XCTAssertEqual(state.playerPaddleX, GameConstants.paddleWidth / 2, accuracy: 0.0001)
    }

    func test_setPlayerPaddleClampsToRight() {
        let state = GameState()
        state.setPlayerPaddle(normalizedCrown: 1.2)
        XCTAssertEqual(state.playerPaddleX, 1 - GameConstants.paddleWidth / 2, accuracy: 0.0001)
    }

    func test_setPlayerPaddleNormalRange() {
        let state = GameState()
        state.setPlayerPaddle(normalizedCrown: 0.5)
        XCTAssertEqual(state.playerPaddleX, 0.5, accuracy: 0.0001)
    }

    func test_gameOverUpdatesHighScore() {
        let suiteName = "GameStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HighScoreStore(defaults: defaults)
        let state = GameState(highScoreStore: store)
        state.phase = .playing
        state.score = 15
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: 1.01),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.01)

        XCTAssertEqual(state.phase, .gameOver)
        XCTAssertEqual(store.current, 15)
        XCTAssertTrue(state.lastRunWasRecord, "Beating previous high score should flag as record")
    }

    func test_gameOverTiedScoreDoesNotFlagAsRecord() {
        let suiteName = "GameStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HighScoreStore(defaults: defaults)
        _ = store.updateIfHigher(newScore: 10)  // existing high score

        let state = GameState(highScoreStore: store)
        state.phase = .playing
        state.score = 10  // tied, not beaten
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: 1.01),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.01)

        XCTAssertEqual(state.phase, .gameOver)
        XCTAssertEqual(store.current, 10)
        XCTAssertFalse(state.lastRunWasRecord, "Tying previous high score must not flag as record")
    }

    func test_startGameClearsLastRunWasRecordFlag() {
        let state = GameState()
        state.lastRunWasRecord = true  // simulate prior game-over state
        state.startGame()
        XCTAssertFalse(state.lastRunWasRecord)
    }

    func test_playerPaddleHitPlaysHaptic() {
        let haptic = FakeHapticPlayer()
        let state = GameState(hapticPlayer: haptic)
        state.phase = .playing
        state.playerPaddleX = 0.5
        let paddleY = 1.0 - GameConstants.paddleMarginY
        state.ball = Ball(
            position: CGPoint(x: 0.5, y: paddleY - GameConstants.paddleHeight),
            velocity: CGVector(dx: 0, dy: 0.5)
        )

        state.update(dt: 0.05)

        XCTAssertEqual(haptic.playedCount, 1)
    }

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

    func test_resetClearsParticles() {
        let state = GameState()
        state.spawnScoreBurst(atX: 0.5)
        XCTAssertFalse(state.particles.isEmpty)  // sanity

        state.reset()

        XCTAssertTrue(state.particles.isEmpty)
    }

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

    func test_powerUpTimersFrozenDuringCountdown() {
        let state = GameState()
        state.startGame()                       // countdown running
        let before = state.powerUps.timeUntilNextSpawn
        state.update(dt: 1.0)                   // still counting down
        XCTAssertEqual(state.powerUps.timeUntilNextSpawn, before, accuracy: 0.0001)
    }

    func test_powerUpSpawnTimerRunsDuringLiveRally() {
        let state = GameState()
        state.startGame()
        state.update(dt: CGFloat(GameConstants.countdownStart)) // finish countdown
        let before = state.powerUps.timeUntilNextSpawn
        state.update(dt: 0.05)
        XCTAssertLessThan(state.powerUps.timeUntilNextSpawn, before)
    }

    func test_collectingPickupFiresSuccessHaptic() {
        let haptics = FakeHapticPlayer()
        let state = GameState(hapticPlayer: haptics)
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: CGVector(dx: 0, dy: 0.1))
        state.setPickupForTests(Pickup(kind: .widePaddle,
                                       position: CGPoint(x: 0.5, y: 1.0 - GameConstants.paddleMarginY - 0.02),
                                       driftSign: 1))
        state.update(dt: 0.02)   // paddle default 0.5 → intercepts
        XCTAssertEqual(haptics.successCount, 1)
        XCTAssertEqual(state.pickupCollectedThisTick, .bottom)
        XCTAssertTrue(state.powerUps.effects(for: .bottom).isWide)
    }

    func test_widePaddleWidensPlayerCollisionWindow() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.widePaddle, to: .bottom)
        // x-offset 0.13: outside base half-width (0.10) but inside wide half (0.15).
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5 + 0.13, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)
        XCTAssertLessThan(state.ball.velocity.dy, 0, "wide paddle should have bounced the ball")
    }

    func test_resetClearsPowerUps() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.shield, to: .bottom)
        state.reset()
        XCTAssertFalse(state.powerUps.hasShield(for: .bottom))
        XCTAssertNil(state.powerUps.pickup)
    }

    func test_shieldSavesBottomExitAndIsConsumed() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.shield, to: .bottom)
        state.ball = Ball(position: CGPoint(x: 0.9, y: 0.995),
                          velocity: CGVector(dx: 0, dy: 0.5))
        state.update(dt: 0.05)
        XCTAssertEqual(state.phase, .playing, "shield should prevent game over")
        XCTAssertLessThan(state.ball.velocity.dy, 0, "ball should bounce back up")
        XCTAssertFalse(state.powerUps.hasShield(for: .bottom), "shield is one-use")
    }

    func test_shieldSavesTopExitWithoutScoring() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.shield, to: .top)
        state.ball = Ball(position: CGPoint(x: 0.9, y: 0.005),
                          velocity: CGVector(dx: 0, dy: -0.5))
        state.update(dt: 0.05)
        XCTAssertEqual(state.score, 0, "shielded save is not a point")
        XCTAssertGreaterThan(state.ball.velocity.dy, 0)
        XCTAssertFalse(state.powerUps.hasShield(for: .top))
    }

    func test_bottomExitWithoutShieldStillEndsGame() {
        let state = GameState()
        state.phase = .playing
        state.ball = Ball(position: CGPoint(x: 0.9, y: 0.995),
                          velocity: CGVector(dx: 0, dy: 0.5))
        state.update(dt: 0.05)
        XCTAssertEqual(state.phase, .gameOver)
    }

    func test_stickyArmedPaddleCatchesBall() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .bottom)
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.55, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)
        XCTAssertNotNil(state.stuckBall)
        XCTAssertEqual(state.stuckBall?.side, .bottom)
        XCTAssertEqual(state.ball.velocity.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(state.ball.velocity.dy, 0, accuracy: 0.0001)
        XCTAssertFalse(state.powerUps.stickyArmed(for: .bottom), "one catch per pickup")
    }

    func test_stuckBallRidesPaddle() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .bottom)
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)          // catch at offset ~0
        state.setPlayerPaddle(normalizedCrown: 0.8)
        state.update(dt: 0.05)
        XCTAssertEqual(state.ball.position.x, state.playerPaddleX, accuracy: 0.001)
    }

    func test_tapReleaseLaunchesUpwardAtCurrentSpeed() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .bottom)
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)
        XCTAssertNotNil(state.stuckBall)
        state.tapRelease(side: .bottom)
        XCTAssertNil(state.stuckBall)
        XCTAssertLessThan(state.ball.velocity.dy, 0, "bottom release goes upward")
        let mag = hypot(state.ball.velocity.dx, state.ball.velocity.dy)
        XCTAssertEqual(mag, GameConstants.initialBallSpeed, accuracy: 0.001)
    }

    func test_tapReleaseWrongSideIsIgnored() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .bottom)
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)
        state.tapRelease(side: .top)
        XCTAssertNotNil(state.stuckBall, "top tap must not release a bottom-stuck ball")
    }

    func test_playerAutoReleaseAfterHoldSeconds() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .bottom)
        let paddleTopY = 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleTopY - GameConstants.ballRadius - 0.001),
                          velocity: CGVector(dx: 0, dy: 0.3))
        state.update(dt: 0.05)
        var elapsed: CGFloat = 0
        while elapsed < GameConstants.stickyHoldSeconds + 0.1 {
            state.update(dt: 0.05); elapsed += 0.05
        }
        XCTAssertNil(state.stuckBall)
        XCTAssertLessThan(state.ball.velocity.dy, 0)
    }

    func test_aiCatchAutoReleasesAfterOneSecond() {
        let state = GameState()
        state.phase = .playing
        state.grantPowerUpForTests(.stickyBall, to: .top)
        let paddleBottomY = GameConstants.paddleMarginY + GameConstants.paddleHeight / 2
        state.ball = Ball(position: CGPoint(x: 0.5, y: paddleBottomY + GameConstants.ballRadius + 0.001),
                          velocity: CGVector(dx: 0, dy: -0.3))
        state.update(dt: 0.05)
        XCTAssertEqual(state.stuckBall?.side, .top)
        var elapsed: CGFloat = 0
        while elapsed < GameConstants.aiStickyHoldSeconds + 0.1 {
            state.update(dt: 0.05); elapsed += 0.05
        }
        XCTAssertNil(state.stuckBall)
        XCTAssertGreaterThan(state.ball.velocity.dy, 0, "top release goes downward")
    }
}
