import CoreGraphics

enum PowerUpKind: String, CaseIterable, Codable, Equatable {
    case widePaddle, shield, stickyBall, multiBall
}

/// bottom = player (single-player) / host (multiplayer); top = AI / client.
enum PaddleSide: String, Codable, Equatable {
    case bottom, top
}

struct Pickup: Equatable {
    var kind: PowerUpKind
    var position: CGPoint
    /// +1 drifts toward the bottom paddle, -1 toward the top.
    var driftSign: CGFloat
    var targetSide: PaddleSide { driftSign > 0 ? .bottom : .top }
}

struct SidePowerUps: Equatable {
    var wideRemaining: CGFloat = 0
    var hasShield: Bool = false
    var stickyArmed: Bool = false
    var isWide: Bool { wideRemaining > 0 }
}

/// SplitMix64 — deterministic, seedable RNG so spawn behavior is reproducible in tests.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum PowerUpEvent: Equatable {
    case collected(kind: PowerUpKind, by: PaddleSide)
}

/// Pure model for pickups and active effects. Owned by GameState; never ticked
/// during a serve countdown or pause, which is what freezes all its timers.
struct PowerUpSystem {
    private(set) var pickup: Pickup?
    private(set) var bottom = SidePowerUps()
    private(set) var top = SidePowerUps()
    private(set) var timeUntilNextSpawn: CGFloat = 0
    /// Single-player: every pickup drifts to the human (bottom) paddle.
    var alwaysDriftToBottom: Bool = false
    /// Permanent widening from the Long Paddle ability, applied to the
    /// player's paddle only. 1 = no ability.
    var baseWidthFactor: CGFloat = 1
    /// Lucky Drops shortens the spawn wait. 1 = no ability.
    var spawnIntervalFactor: CGFloat = 1
    /// Big Drops widens the catch radius. 1 = no ability.
    var pickupRadiusFactor: CGFloat = 1
    private var rng: SeededRandomNumberGenerator

    init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        rng = SeededRandomNumberGenerator(seed: seed)
        rearmSpawnTimer()
    }

    /// Advance spawn timer, pickup drift, and interception. Call once per
    /// physics tick, only during live rally.
    mutating func tick(dt: CGFloat, bottomPaddleX: CGFloat, topPaddleX: CGFloat) -> PowerUpEvent? {
        if bottom.wideRemaining > 0 { bottom.wideRemaining = max(0, bottom.wideRemaining - dt) }
        if top.wideRemaining > 0 { top.wideRemaining = max(0, top.wideRemaining - dt) }

        guard var p = pickup else {
            timeUntilNextSpawn -= dt
            if timeUntilNextSpawn <= 0 { spawnPickup() }
            return nil
        }

        p.position.y += p.driftSign * GameConstants.powerUpDriftSpeed * dt
        pickup = p

        // Only the paddle the pickup drifts toward can intercept it.
        let paddleX = p.targetSide == .bottom ? bottomPaddleX : topPaddleX
        let paddleY = p.targetSide == .bottom ? 1.0 - GameConstants.paddleMarginY
                                              : GameConstants.paddleMarginY
        let halfH = GameConstants.paddleHeight / 2
        let r = GameConstants.powerUpPickupRadius * pickupRadiusFactor
        let rY = GameConstants.powerUpPickupRadiusY * pickupRadiusFactor
        let halfW = paddleWidth(for: p.targetSide) / 2
        if abs(p.position.x - paddleX) <= halfW + r,
           abs(p.position.y - paddleY) <= halfH + rY {
            let kind = p.kind, side = p.targetSide
            grant(kind, to: side)
            resolvePickup()
            return .collected(kind: kind, by: side)
        }

        // Despawn once fully past the paddle line.
        if p.position.y < GameConstants.paddleMarginY - halfH - rY ||
           p.position.y > 1.0 - GameConstants.paddleMarginY + halfH + rY {
            resolvePickup()
        }
        return nil
    }

    // MARK: - Queries

    func effects(for side: PaddleSide) -> SidePowerUps { side == .bottom ? bottom : top }

    func paddleWidth(for side: PaddleSide) -> CGFloat {
        let base = GameConstants.paddleWidth * (side == .bottom ? baseWidthFactor : 1)
        return effects(for: side).isWide ? base * GameConstants.widePaddleFactor : base
    }

    func hasShield(for side: PaddleSide) -> Bool { effects(for: side).hasShield }
    func stickyArmed(for side: PaddleSide) -> Bool { effects(for: side).stickyArmed }

    // MARK: - Mutations

    private mutating func modify(_ side: PaddleSide, _ body: (inout SidePowerUps) -> Void) {
        if side == .bottom { body(&bottom) } else { body(&top) }
    }

    mutating func grant(_ kind: PowerUpKind, to side: PaddleSide) {
        switch kind {
        case .widePaddle: modify(side) { $0.wideRemaining = GameConstants.widePaddleDuration }
        case .shield:     modify(side) { $0.hasShield = true }
        case .stickyBall: modify(side) { $0.stickyArmed = true }
        case .multiBall:  break   // ball splitting lives in GameState (Task 8)
        }
    }

    mutating func consumeShield(for side: PaddleSide) { modify(side) { $0.hasShield = false } }
    mutating func consumeSticky(for side: PaddleSide) { modify(side) { $0.stickyArmed = false } }

    /// Client-side only: mirror host-simulated state for rendering.
    mutating func applyRemote(pickup: Pickup?, bottom: SidePowerUps, top: SidePowerUps) {
        self.pickup = pickup
        self.bottom = bottom
        self.top = top
    }

    #if DEBUG
    mutating func setPickupForTests(_ p: Pickup?) { pickup = p }
    #endif

    /// Removes any on-screen pickup and re-arms the spawn timer. Called on serve resets.
    mutating func clearPickup() {
        if pickup != nil { resolvePickup() }
    }

    mutating func reset() {
        pickup = nil
        bottom = SidePowerUps()
        top = SidePowerUps()
        rearmSpawnTimer()
    }

    private mutating func resolvePickup() {
        pickup = nil
        rearmSpawnTimer()
    }

    private mutating func rearmSpawnTimer() {
        timeUntilNextSpawn = CGFloat.random(
            in: GameConstants.powerUpSpawnIntervalMin...GameConstants.powerUpSpawnIntervalMax,
            using: &rng) * spawnIntervalFactor
    }

    private mutating func spawnPickup() {
        let kind = PowerUpKind.allCases.randomElement(using: &rng)!
        let sign: CGFloat = alwaysDriftToBottom ? 1 : (Bool.random(using: &rng) ? 1 : -1)
        pickup = Pickup(kind: kind, position: CGPoint(x: 0.5, y: 0.5), driftSign: sign)
    }
}
