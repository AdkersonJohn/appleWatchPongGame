import Foundation
import CoreGraphics
import Combine

struct StuckBall: Equatable {
    var side: PaddleSide
    /// Ball x-offset from paddle center, clamped to the paddle half-width.
    var offset: CGFloat
    var holdRemaining: CGFloat
    var ballIndex: Int = 0
}

final class GameState: ObservableObject {
    @Published var phase: GamePhase = .start
    @Published var balls: [Ball]
    /// Single-ball proxy. Reads/writes balls[0]; kept so existing call sites,
    /// tests, and the MP host path stay simple when only one ball is in play.
    var ball: Ball {
        get { balls[0] }
        set { balls[0] = newValue }
    }
    @Published var playerPaddleX: CGFloat
    @Published var aiPaddleX: CGFloat
    @Published var score: Int = 0
    @Published var lastRunWasRecord: Bool = false
    // nil = no countdown, ball is in play. Otherwise the number (3, 2, 1) to show.
    @Published var countdownRemaining: Int?
    @Published var particles: [Particle] = []
    @Published private(set) var powerUps = PowerUpSystem()
    @Published private(set) var stuckBall: StuckBall?
    /// MP client only: which side (per the host's snapshot) currently holds a
    /// stuck ball. stuckBall itself is host-only and index-based, so the
    /// client can't reconstruct one — this just drives the green "holding" cue.
    var remoteStuckSide: PaddleSide?
    /// False in multiplayer, where the top paddle is the remote human.
    var topSideIsAI: Bool = true
    /// Set for exactly one update() when a pickup was collected; consumed by MP snapshots.
    private(set) var pickupCollectedThisTick: PaddleSide?
    /// MP host mode: a ball exiting the bottom scores for the opponent and
    /// re-serves instead of ending the game. Single-player leaves this false.
    var bottomExitScoresOpponent: Bool = false
    private(set) var opponentScoredThisTick: Int = 0
    private(set) var bottomPaddleHitThisTick: Bool = false
    private(set) var topPaddleHitThisTick: Bool = false

    private var currentBallSpeed: CGFloat = GameConstants.initialBallSpeed
    private var countdownElapsed: CGFloat = 0
    // Internal rally counter — every hitsPerSpeedTier paddle hits, ball speed bumps.
    // Not @Published; not exposed to the UI.
    private var hitCount: Int = 0
    private let highScoreStore: HighScoreStore
    private let hapticPlayer: HapticPlayer

    init(highScoreStore: HighScoreStore = HighScoreStore(),
         hapticPlayer: HapticPlayer = WatchHapticPlayer()) {
        self.highScoreStore = highScoreStore
        self.hapticPlayer = hapticPlayer
        self.balls = [Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)]
        self.playerPaddleX = 0.5
        self.aiPaddleX = 0.5
    }

    func reset() {
        phase = .start
        score = 0
        lastRunWasRecord = false
        currentBallSpeed = GameConstants.initialBallSpeed
        balls = [Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)]
        playerPaddleX = 0.5
        aiPaddleX = 0.5
        countdownRemaining = nil
        countdownElapsed = 0
        particles = []
        hitCount = 0
        powerUps.reset()
        pickupCollectedThisTick = nil
        stuckBall = nil
        remoteStuckSide = nil
    }

    func startGame() {
        reset()
        phase = .playing
        startCountdown()
    }

    /// Public entry point used by multiplayer to start a fresh serve.
    /// Resets ball to center and starts the 3-2-1 countdown without touching score.
    func prepareNextServe() {
        balls = [Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)]
        countdownRemaining = GameConstants.countdownStart
        countdownElapsed = 0
        powerUps.clearPickup()
        stuckBall = nil
        remoteStuckSide = nil
    }

    func setPlayerPaddle(normalizedCrown value: CGFloat) {
        let half = powerUps.paddleWidth(for: .bottom) / 2
        playerPaddleX = max(half, min(1 - half, value))
    }

    func update(dt: CGFloat) {
        guard phase == .playing else { return }
        pickupCollectedThisTick = nil
        opponentScoredThisTick = 0
        bottomPaddleHitThisTick = false
        topPaddleHitThisTick = false

        updateParticles(dt: dt)

        // While the 3-2-1 countdown is running, the ball sits at center with
        // zero velocity. Advance the countdown and skip physics this tick.
        if countdownRemaining != nil {
            tickCountdown(dt: dt)
            return
        }

        tickPowerUps(dt: dt)
        tickStuckBall(dt: dt)

        // Sub-step physics so a single fast-ball frame can't skip past a paddle.
        // Cap each sub-step's travel to half a paddle's thickness, which
        // guarantees the collision window is sampled at least once per pass.
        let maxSpeed = balls.map { hypot($0.velocity.dx, $0.velocity.dy) }.max() ?? 0
        let maxStepDistance = GameConstants.paddleHeight / 2
        let substeps: Int = {
            guard maxSpeed > 0 else { return 1 }
            return max(1, Int(ceil(maxSpeed * dt / maxStepDistance)))
        }()
        let subDt = dt / CGFloat(substeps)

        for _ in 0..<substeps {
            guard phase == .playing else { return }
            stepPhysics(dt: subDt)
        }
    }

    private func stepPhysics(dt: CGFloat) {
        for i in balls.indices {
            if stuckBall?.ballIndex == i { continue }   // stuck ball rides the paddle
            balls[i].position.x += balls[i].velocity.dx * dt
            balls[i].position.y += balls[i].velocity.dy * dt

            // Walls
            if balls[i].position.x < GameConstants.ballRadius {
                balls[i].position.x = GameConstants.ballRadius
                balls[i].velocity.dx = -balls[i].velocity.dx
            }
            if balls[i].position.x > 1.0 - GameConstants.ballRadius {
                balls[i].position.x = 1.0 - GameConstants.ballRadius
                balls[i].velocity.dx = -balls[i].velocity.dx
            }

            // Player paddle (bottom)
            let playerPaddleY = 1.0 - GameConstants.paddleMarginY
            let playerPaddleTop = playerPaddleY - GameConstants.paddleHeight / 2
            let playerHalfW = powerUps.paddleWidth(for: .bottom) / 2
            if balls[i].velocity.dy > 0,
               balls[i].position.y + GameConstants.ballRadius >= playerPaddleTop,
               balls[i].position.y + GameConstants.ballRadius <= playerPaddleY + GameConstants.paddleHeight / 2,
               abs(balls[i].position.x - playerPaddleX) <= playerHalfW {
                if powerUps.stickyArmed(for: .bottom) {
                    stickBall(at: i, to: .bottom)
                } else {
                    bouncePaddleHit(ballIndex: i, paddleX: playerPaddleX)
                    hapticPlayer.playClick()
                    bottomPaddleHitThisTick = true
                    hitCount += 1
                    if hitCount % GameConstants.hitsPerSpeedTier == 0,
                       currentBallSpeed < GameConstants.maxBallSpeed {
                        let bumped = currentBallSpeed * (1 + GameConstants.speedIncreasePerTier)
                        currentBallSpeed = min(bumped, GameConstants.maxBallSpeed)
                        rescaleBallSpeed(ballIndex: i, to: currentBallSpeed)
                    }
                }
            }

            // AI paddle (top)
            let aiPaddleY = GameConstants.paddleMarginY
            let aiPaddleBottom = aiPaddleY + GameConstants.paddleHeight / 2
            let aiHalfW = powerUps.paddleWidth(for: .top) / 2
            if balls[i].velocity.dy < 0,
               balls[i].position.y - GameConstants.ballRadius <= aiPaddleBottom,
               balls[i].position.y - GameConstants.ballRadius >= aiPaddleY - GameConstants.paddleHeight / 2,
               abs(balls[i].position.x - aiPaddleX) <= aiHalfW {
                if powerUps.stickyArmed(for: .top) {
                    stickBall(at: i, to: .top)
                } else {
                    bouncePaddleHit(ballIndex: i, paddleX: aiPaddleX)
                    topPaddleHitThisTick = true
                }
            }
        }

        // AI tracks the ball nearest its side (smallest y), ignoring stuck balls.
        let targetX = balls.indices
            .filter { stuckBall?.ballIndex != $0 }
            .min { balls[$0].position.y < balls[$1].position.y }
            .map { balls[$0].position.x } ?? balls[0].position.x
        let aiDelta = targetX - aiPaddleX
        // Single-player only: the AI reacts faster the more the player has
        // scored on it. In multiplayer the top paddle is a human, so leave it.
        let aiSpeed = topSideIsAI ? GameConstants.aiSpeed(playerScore: score)
                                  : GameConstants.aiMaxSpeed
        let maxStep = aiSpeed * dt
        let step: CGFloat
        if abs(aiDelta) < maxStep {
            step = aiDelta
        } else {
            step = aiDelta > 0 ? maxStep : -maxStep
        }
        let half = powerUps.paddleWidth(for: .top) / 2
        aiPaddleX = max(half, min(1 - half, aiPaddleX + step))

        handleExits()
    }

    private func handleExits() {
        var i = 0
        while i < balls.count {
            let b = balls[i]
            if b.position.y < 0 {
                if powerUps.hasShield(for: .top) {
                    powerUps.consumeShield(for: .top)
                    balls[i].position.y = 0
                    balls[i].velocity.dy = abs(balls[i].velocity.dy)
                } else {
                    score += 1
                    spawnScoreBurst(atX: b.position.x)
                    if balls.count == 1 { startCountdown(); return }
                    removeBall(at: i); continue
                }
            } else if b.position.y > 1.0 {
                if powerUps.hasShield(for: .bottom) {
                    powerUps.consumeShield(for: .bottom)
                    balls[i].position.y = 1.0
                    balls[i].velocity.dy = -abs(balls[i].velocity.dy)
                } else if bottomExitScoresOpponent {
                    opponentScoredThisTick += 1
                    if balls.count == 1 { startCountdown(); return }
                    removeBall(at: i); continue
                } else if balls.count > 1 {
                    removeBall(at: i); continue
                } else {
                    lastRunWasRecord = highScoreStore.updateIfHigher(newScore: score)
                    phase = .gameOver
                    return
                }
            }
            i += 1
        }
    }

    private func removeBall(at index: Int) {
        balls.remove(at: index)
        if var stuck = stuckBall, stuck.ballIndex > index {
            stuck.ballIndex -= 1
            stuckBall = stuck
        }
    }

    private func bouncePaddleHit(ballIndex: Int, paddleX: CGFloat) {
        balls[ballIndex].velocity.dy = -balls[ballIndex].velocity.dy
        // Impact offset: -1 (left edge) to +1 (right edge)
        let offset = (balls[ballIndex].position.x - paddleX) / (GameConstants.paddleWidth / 2)
        let clamped = max(-1, min(1, offset))
        let speed = hypot(balls[ballIndex].velocity.dx, balls[ballIndex].velocity.dy)
        // Steer dx toward offset while preserving overall speed
        let steerAmount: CGFloat = 0.7
        let newDx = clamped * speed * steerAmount
        // Recompute dy to preserve speed magnitude
        let newDySquared = max(0, speed * speed - newDx * newDx)
        let newDy = (balls[ballIndex].velocity.dy < 0 ? -1 : 1) * sqrt(newDySquared)
        balls[ballIndex].velocity.dx = newDx
        balls[ballIndex].velocity.dy = newDy
    }

    private func rescaleBallSpeed(ballIndex: Int, to targetSpeed: CGFloat) {
        let currentMag = hypot(balls[ballIndex].velocity.dx, balls[ballIndex].velocity.dy)
        guard currentMag > 0 else { return }
        let scale = targetSpeed / currentMag
        balls[ballIndex].velocity.dx *= scale
        balls[ballIndex].velocity.dy *= scale
    }

    private func stickBall(at index: Int, to side: PaddleSide) {
        // A different ball may already be held (multi-ball + both paddles
        // sticky-armed). Release it first so it doesn't get orphaned at zero
        // velocity forever when we overwrite the single-optional stuckBall.
        if stuckBall != nil {
            releaseStuckBall()
        }
        powerUps.consumeSticky(for: side)
        let paddleX = side == .bottom ? playerPaddleX : aiPaddleX
        let halfW = powerUps.paddleWidth(for: side) / 2
        let offset = max(-halfW, min(halfW, balls[index].position.x - paddleX))
        let hold = (side == .top && topSideIsAI)
            ? GameConstants.aiStickyHoldSeconds
            : GameConstants.stickyHoldSeconds
        stuckBall = StuckBall(side: side, offset: offset, holdRemaining: hold, ballIndex: index)
        balls[index].velocity = .zero
    }

    private func tickStuckBall(dt: CGFloat) {
        guard var stuck = stuckBall else { return }
        let paddleX = stuck.side == .bottom ? playerPaddleX : aiPaddleX
        let halfW = powerUps.paddleWidth(for: stuck.side) / 2
        stuck.offset = max(-halfW, min(halfW, stuck.offset))
        let y = stuck.side == .bottom
            ? 1.0 - GameConstants.paddleMarginY - GameConstants.paddleHeight / 2 - GameConstants.ballRadius
            : GameConstants.paddleMarginY + GameConstants.paddleHeight / 2 + GameConstants.ballRadius
        balls[stuck.ballIndex].position = CGPoint(x: paddleX + stuck.offset, y: y)
        balls[stuck.ballIndex].velocity = .zero
        stuck.holdRemaining -= dt
        stuckBall = stuck
        if stuck.holdRemaining <= 0 { releaseStuckBall() }
    }

    private func releaseStuckBall() {
        guard let stuck = stuckBall else { return }
        stuckBall = nil
        let halfW = powerUps.paddleWidth(for: stuck.side) / 2
        let clamped = max(-1, min(1, stuck.offset / halfW))
        let speed = currentBallSpeed
        let dx = clamped * speed * 0.7
        let dyMag = sqrt(max(0, speed * speed - dx * dx))
        balls[stuck.ballIndex].velocity = CGVector(dx: dx, dy: stuck.side == .bottom ? -dyMag : dyMag)
    }

    /// Tap-to-release entry point (GameView tap / MP stickyRelease message).
    func tapRelease(side: PaddleSide) {
        guard let stuck = stuckBall, stuck.side == side else { return }
        releaseStuckBall()
    }

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

    func updateParticles(dt: CGFloat) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.dx * dt
            particles[i].position.y += particles[i].velocity.dy * dt
            particles[i].ageRemaining -= dt
        }
        particles.removeAll { $0.ageRemaining <= 0 }
    }

    private func startCountdown() {
        balls = [Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)]
        countdownRemaining = GameConstants.countdownStart
        countdownElapsed = 0
        powerUps.clearPickup()
        stuckBall = nil
        remoteStuckSide = nil
    }

    private func tickCountdown(dt: CGFloat) {
        guard var remaining = countdownRemaining else { return }
        countdownElapsed += dt
        while countdownElapsed >= 1.0 && remaining > 0 {
            countdownElapsed -= 1.0
            remaining -= 1
        }
        if remaining > 0 {
            countdownRemaining = remaining
        } else {
            countdownRemaining = nil
            balls[0].velocity = randomInitialVelocity(speed: currentBallSpeed)
        }
    }

    private func tickPowerUps(dt: CGFloat) {
        powerUps.alwaysDriftToBottom = topSideIsAI
        guard let event = powerUps.tick(dt: dt,
                                        bottomPaddleX: playerPaddleX,
                                        topPaddleX: aiPaddleX) else { return }
        switch event {
        case .collected(let kind, let side):
            pickupCollectedThisTick = side
            if side == .bottom { hapticPlayer.playSuccess() }
            if kind == .multiBall { splitBalls() }
        }
    }

    private func splitBalls() {
        let cap = GameConstants.multiBallCount
        guard balls.count < cap else { return }
        let sourceIndex = balls.firstIndex { $0.velocity != CGVector.zero } ?? 0
        let src = balls[sourceIndex]
        let srcSpeed = hypot(src.velocity.dx, src.velocity.dy)
        let speed = srcSpeed > 0 ? srcSpeed : currentBallSpeed
        // Angle measured from straight-down (+y): atan2(dx, dy).
        let baseAngle = srcSpeed > 0 ? atan2(src.velocity.dx, src.velocity.dy) : CGFloat.pi
        var offsets: [CGFloat] = [GameConstants.multiBallSplitAngle,
                                  -GameConstants.multiBallSplitAngle]
        while balls.count < cap, !offsets.isEmpty {
            let a = baseAngle + offsets.removeFirst()
            balls.append(Ball(position: src.position,
                              velocity: CGVector(dx: sin(a) * speed, dy: cos(a) * speed)))
        }
    }

    private func randomInitialVelocity(speed: CGFloat) -> CGVector {
        // Angle between 30° and 60° off vertical, random quadrant
        let angle = CGFloat.random(in: (.pi / 6)...(.pi / 3))
        let dx = sin(angle) * speed * (Bool.random() ? 1 : -1)
        let dy = cos(angle) * speed * (Bool.random() ? 1 : -1)
        return CGVector(dx: dx, dy: dy)
    }

    /// Plays the paddle-hit haptic. Exposed so multiplayer can trigger it when
    /// the inbound snapshot reports the local paddle hit the ball on the host.
    func playPaddleHitHaptic() {
        hapticPlayer.playClick()
    }

    /// Plays the pickup-collected haptic. Exposed so multiplayer can trigger it
    /// when the inbound snapshot reports the local side collected a pickup.
    func playPowerUpHaptic() { hapticPlayer.playSuccess() }

    /// MP client: apply host-simulated power-up state for rendering.
    func applyRemotePowerUps(pickup: Pickup?, bottom: SidePowerUps, top: SidePowerUps) {
        powerUps.applyRemote(pickup: pickup, bottom: bottom, top: top)
    }

    /// Clears all power-up state. Called by MP on match start/rematch.
    func resetPowerUps() {
        powerUps.reset()
        stuckBall = nil
        remoteStuckSide = nil
    }

    #if DEBUG
    /// Test-only accessor to the injected haptic player (for assertions).
    var injectedHapticPlayerForTests: HapticPlayer { hapticPlayer }
    func grantPowerUpForTests(_ kind: PowerUpKind, to side: PaddleSide) {
        powerUps.grant(kind, to: side)
    }
    func setPickupForTests(_ p: Pickup?) {
        powerUps.setPickupForTests(p)
    }
    /// Simulates collecting a pickup, including ball-splitting side effects.
    func collectPowerUpForTests(_ kind: PowerUpKind, by side: PaddleSide) {
        powerUps.grant(kind, to: side)
        if kind == .multiBall { splitBalls() }
    }
    #endif
}
