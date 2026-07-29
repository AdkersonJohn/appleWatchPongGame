import Foundation
import CoreGraphics
import Combine

final class GameState: ObservableObject {
    @Published var phase: GamePhase = .start
    @Published var ball: Ball
    @Published var playerPaddleX: CGFloat
    @Published var aiPaddleX: CGFloat
    @Published var score: Int = 0
    @Published var lastRunWasRecord: Bool = false
    // nil = no countdown, ball is in play. Otherwise the number (3, 2, 1) to show.
    @Published var countdownRemaining: Int?
    @Published var particles: [Particle] = []
    @Published private(set) var powerUps = PowerUpSystem()
    /// Set for exactly one update() when a pickup was collected; consumed by MP snapshots.
    private(set) var pickupCollectedThisTick: PaddleSide?

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
        self.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                         velocity: .zero)
        self.playerPaddleX = 0.5
        self.aiPaddleX = 0.5
    }

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
        hitCount = 0
        powerUps.reset()
        pickupCollectedThisTick = nil
    }

    func startGame() {
        reset()
        phase = .playing
        startCountdown()
    }

    /// Public entry point used by multiplayer to start a fresh serve.
    /// Resets ball to center and starts the 3-2-1 countdown without touching score.
    func prepareNextServe() {
        ball = Ball(position: CGPoint(x: 0.5, y: 0.5), velocity: .zero)
        countdownRemaining = GameConstants.countdownStart
        countdownElapsed = 0
        powerUps.clearPickup()
    }

    func setPlayerPaddle(normalizedCrown value: CGFloat) {
        let half = powerUps.paddleWidth(for: .bottom) / 2
        playerPaddleX = max(half, min(1 - half, value))
    }

    func update(dt: CGFloat) {
        guard phase == .playing else { return }
        pickupCollectedThisTick = nil

        updateParticles(dt: dt)

        // While the 3-2-1 countdown is running, the ball sits at center with
        // zero velocity. Advance the countdown and skip physics this tick.
        if countdownRemaining != nil {
            tickCountdown(dt: dt)
            return
        }

        tickPowerUps(dt: dt)

        // Sub-step physics so a single fast-ball frame can't skip past a paddle.
        // Cap each sub-step's travel to half a paddle's thickness, which
        // guarantees the collision window is sampled at least once per pass.
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        let maxStepDistance = GameConstants.paddleHeight / 2
        let substeps: Int = {
            guard speed > 0 else { return 1 }
            return max(1, Int(ceil(speed * dt / maxStepDistance)))
        }()
        let subDt = dt / CGFloat(substeps)

        for _ in 0..<substeps {
            guard phase == .playing else { return }
            stepPhysics(dt: subDt)
        }
    }

    private func stepPhysics(dt: CGFloat) {
        ball.position.x += ball.velocity.dx * dt
        ball.position.y += ball.velocity.dy * dt

        // Left wall
        if ball.position.x < GameConstants.ballRadius {
            ball.position.x = GameConstants.ballRadius
            ball.velocity.dx = -ball.velocity.dx
        }
        // Right wall
        if ball.position.x > 1.0 - GameConstants.ballRadius {
            ball.position.x = 1.0 - GameConstants.ballRadius
            ball.velocity.dx = -ball.velocity.dx
        }

        // Player paddle (bottom)
        let playerHalfW = powerUps.paddleWidth(for: .bottom) / 2
        let playerPaddleY = 1.0 - GameConstants.paddleMarginY
        let playerPaddleTop = playerPaddleY - GameConstants.paddleHeight / 2
        if ball.velocity.dy > 0,
           ball.position.y + GameConstants.ballRadius >= playerPaddleTop,
           ball.position.y + GameConstants.ballRadius <= playerPaddleY + GameConstants.paddleHeight / 2,
           abs(ball.position.x - playerPaddleX) <= playerHalfW {
            bouncePaddleHit(paddleX: playerPaddleX)
            hapticPlayer.playClick()
            hitCount += 1
            if hitCount % GameConstants.hitsPerSpeedTier == 0,
               currentBallSpeed < GameConstants.maxBallSpeed {
                let bumped = currentBallSpeed * (1 + GameConstants.speedIncreasePerTier)
                currentBallSpeed = min(bumped, GameConstants.maxBallSpeed)
                rescaleBallSpeed(to: currentBallSpeed)
            }
        }

        // AI paddle (top)
        let aiHalfW = powerUps.paddleWidth(for: .top) / 2
        let aiPaddleY = GameConstants.paddleMarginY
        let aiPaddleBottom = aiPaddleY + GameConstants.paddleHeight / 2
        if ball.velocity.dy < 0,
           ball.position.y - GameConstants.ballRadius <= aiPaddleBottom,
           ball.position.y - GameConstants.ballRadius >= aiPaddleY - GameConstants.paddleHeight / 2,
           abs(ball.position.x - aiPaddleX) <= aiHalfW {
            bouncePaddleHit(paddleX: aiPaddleX)
        }

        // AI paddle tracks the ball
        let aiDelta = ball.position.x - aiPaddleX
        let maxStep = GameConstants.aiMaxSpeed * dt
        let step: CGFloat
        if abs(aiDelta) < maxStep {
            step = aiDelta
        } else {
            step = aiDelta > 0 ? maxStep : -maxStep
        }
        let half = powerUps.paddleWidth(for: .top) / 2
        aiPaddleX = max(half, min(1 - half, aiPaddleX + step))

        // Ball exits top (AI missed) — player scores a point, start countdown.
        if ball.position.y < 0 {
            if powerUps.hasShield(for: .top) {
                powerUps.consumeShield(for: .top)
                ball.position.y = 0
                ball.velocity.dy = abs(ball.velocity.dy)
            } else {
                score += 1
                spawnScoreBurst(atX: ball.position.x)
                startCountdown()
            }
        }

        // Ball exits bottom — game over (unless shielded)
        if ball.position.y > 1.0 {
            if powerUps.hasShield(for: .bottom) {
                powerUps.consumeShield(for: .bottom)
                ball.position.y = 1.0
                ball.velocity.dy = -abs(ball.velocity.dy)
            } else {
                lastRunWasRecord = highScoreStore.updateIfHigher(newScore: score)
                phase = .gameOver
            }
        }
    }

    private func bouncePaddleHit(paddleX: CGFloat) {
        ball.velocity.dy = -ball.velocity.dy
        // Impact offset: -1 (left edge) to +1 (right edge)
        let offset = (ball.position.x - paddleX) / (GameConstants.paddleWidth / 2)
        let clamped = max(-1, min(1, offset))
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        // Steer dx toward offset while preserving overall speed
        let steerAmount: CGFloat = 0.7
        let newDx = clamped * speed * steerAmount
        // Recompute dy to preserve speed magnitude
        let newDySquared = max(0, speed * speed - newDx * newDx)
        let newDy = (ball.velocity.dy < 0 ? -1 : 1) * sqrt(newDySquared)
        ball.velocity.dx = newDx
        ball.velocity.dy = newDy
    }

    private func rescaleBallSpeed(to targetSpeed: CGFloat) {
        let currentMag = hypot(ball.velocity.dx, ball.velocity.dy)
        guard currentMag > 0 else { return }
        let scale = targetSpeed / currentMag
        ball.velocity.dx *= scale
        ball.velocity.dy *= scale
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
        ball.position = CGPoint(x: 0.5, y: 0.5)
        ball.velocity = .zero
        countdownRemaining = GameConstants.countdownStart
        countdownElapsed = 0
        powerUps.clearPickup()
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
            ball.velocity = randomInitialVelocity(speed: currentBallSpeed)
        }
    }

    private func tickPowerUps(dt: CGFloat) {
        guard let event = powerUps.tick(dt: dt,
                                        bottomPaddleX: playerPaddleX,
                                        topPaddleX: aiPaddleX) else { return }
        switch event {
        case .collected(_, let side):
            pickupCollectedThisTick = side
            if side == .bottom { hapticPlayer.playSuccess() }
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

    #if DEBUG
    /// Test-only accessor to the injected haptic player (for assertions).
    var injectedHapticPlayerForTests: HapticPlayer { hapticPlayer }
    func grantPowerUpForTests(_ kind: PowerUpKind, to side: PaddleSide) {
        powerUps.grant(kind, to: side)
    }
    func setPickupForTests(_ p: Pickup?) {
        powerUps.setPickupForTests(p)
    }
    #endif
}
