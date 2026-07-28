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
        let r = GameConstants.powerUpPickupRadius
        let halfW = paddleWidth(for: p.targetSide) / 2
        if abs(p.position.x - paddleX) <= halfW + r,
           abs(p.position.y - paddleY) <= halfH + r {
            let kind = p.kind, side = p.targetSide
            grant(kind, to: side)
            resolvePickup()
            return .collected(kind: kind, by: side)
        }

        // Despawn once fully past the paddle line.
        if p.position.y < GameConstants.paddleMarginY - halfH - r ||
           p.position.y > 1.0 - GameConstants.paddleMarginY + halfH + r {
            resolvePickup()
        }
        return nil
    }

    // MARK: - Queries

    func effects(for side: PaddleSide) -> SidePowerUps { side == .bottom ? bottom : top }

    func paddleWidth(for side: PaddleSide) -> CGFloat {
        effects(for: side).isWide
            ? GameConstants.paddleWidth * GameConstants.widePaddleFactor
            : GameConstants.paddleWidth
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
            using: &rng)
    }

    private mutating func spawnPickup() {
        let kind = PowerUpKind.allCases.randomElement(using: &rng)!
        let sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
        pickup = Pickup(kind: kind, position: CGPoint(x: 0.5, y: 0.5), driftSign: sign)
    }
}
