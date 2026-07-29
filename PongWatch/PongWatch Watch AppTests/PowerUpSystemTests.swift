import XCTest
@testable import PongWatch_Watch_App

final class PowerUpSystemTests: XCTestCase {
    /// Ticks the system with paddles parked far from center so nothing intercepts.
    private func tickThrough(_ sys: inout PowerUpSystem, seconds: CGFloat, step: CGFloat = 0.1) {
        var remaining = seconds
        while remaining > 0 {
            _ = sys.tick(dt: min(step, remaining), bottomPaddleX: 0.05, topPaddleX: 0.05)
            remaining -= step
        }
    }

    func test_noPickupBeforeSpawnIntervalElapses() {
        var sys = PowerUpSystem(seed: 1)
        tickThrough(&sys, seconds: GameConstants.powerUpSpawnIntervalMin - 1)
        XCTAssertNil(sys.pickup)
    }

    func test_spawnsPickupAtCenterXAfterInterval() {
        var sys = PowerUpSystem(seed: 1)
        tickThrough(&sys, seconds: GameConstants.powerUpSpawnIntervalMax + 0.2)
        XCTAssertNotNil(sys.pickup)
        XCTAssertEqual(sys.pickup!.position.x, 0.5, accuracy: 0.0001)
    }

    func test_pickupDriftsTowardItsTargetSide() {
        var sys = PowerUpSystem(seed: 1)
        tickThrough(&sys, seconds: GameConstants.powerUpSpawnIntervalMax + 0.2)
        guard let before = sys.pickup else { return XCTFail("no pickup spawned") }
        _ = sys.tick(dt: 1.0, bottomPaddleX: 0.05, topPaddleX: 0.05)
        guard let after = sys.pickup else { return XCTFail("pickup vanished early") }
        let dy = after.position.y - before.position.y
        XCTAssertEqual(dy, before.driftSign * GameConstants.powerUpDriftSpeed, accuracy: 0.0001)
        XCTAssertEqual(before.targetSide, before.driftSign > 0 ? .bottom : .top)
    }

    func test_pickupDespawnsPastPaddleLineAndTimerRearms() {
        var sys = PowerUpSystem(seed: 1)
        tickThrough(&sys, seconds: GameConstants.powerUpSpawnIntervalMax + 0.2)
        XCTAssertNotNil(sys.pickup)
        // 0.45 of travel at 0.08 u/s ≈ 5.6s; give it 8s to cross and despawn
        tickThrough(&sys, seconds: 8)
        XCTAssertNil(sys.pickup)
        XCTAssertGreaterThan(sys.timeUntilNextSpawn, 0)
    }

    func test_sameSeedProducesSameSpawn() {
        var a = PowerUpSystem(seed: 99), b = PowerUpSystem(seed: 99)
        tickThrough(&a, seconds: GameConstants.powerUpSpawnIntervalMax + 0.2)
        tickThrough(&b, seconds: GameConstants.powerUpSpawnIntervalMax + 0.2)
        XCTAssertEqual(a.pickup?.kind, b.pickup?.kind)
        XCTAssertEqual(a.pickup?.driftSign, b.pickup?.driftSign)
    }

    /// Puts a pickup directly above the bottom paddle line at x = 0.5.
    private func plantPickup(_ kind: PowerUpKind, in sys: inout PowerUpSystem,
                             towardBottom: Bool = true) {
        let y: CGFloat = towardBottom ? 1.0 - GameConstants.paddleMarginY - 0.05
                                      : GameConstants.paddleMarginY + 0.05
        sys.setPickupForTests(Pickup(kind: kind,
                                     position: CGPoint(x: 0.5, y: y),
                                     driftSign: towardBottom ? 1 : -1))
    }

    func test_targetPaddleInterceptsAndGainsWidePaddle() {
        var sys = PowerUpSystem(seed: 1)
        plantPickup(.widePaddle, in: &sys)
        var event: PowerUpEvent?
        for _ in 0..<20 where event == nil {
            event = sys.tick(dt: 0.05, bottomPaddleX: 0.5, topPaddleX: 0.05)
        }
        XCTAssertEqual(event, .collected(kind: .widePaddle, by: .bottom))
        XCTAssertEqual(sys.paddleWidth(for: .bottom),
                       GameConstants.paddleWidth * GameConstants.widePaddleFactor,
                       accuracy: 0.0001)
        XCTAssertEqual(sys.paddleWidth(for: .top), GameConstants.paddleWidth, accuracy: 0.0001)
        XCTAssertNil(sys.pickup)
    }

    func test_nonTargetPaddleCannotIntercept() {
        var sys = PowerUpSystem(seed: 1)
        // Drifting toward TOP but positioned at the bottom paddle: no interception.
        sys.setPickupForTests(Pickup(kind: .widePaddle,
                                     position: CGPoint(x: 0.5, y: 1.0 - GameConstants.paddleMarginY),
                                     driftSign: -1))
        let event = sys.tick(dt: 0.02, bottomPaddleX: 0.5, topPaddleX: 0.05)
        XCTAssertNil(event)
    }

    func test_wideExpiresAfterDuration() {
        var sys = PowerUpSystem(seed: 1)
        sys.grant(.widePaddle, to: .bottom)
        tickThrough(&sys, seconds: GameConstants.widePaddleDuration + 0.2)
        XCTAssertEqual(sys.paddleWidth(for: .bottom), GameConstants.paddleWidth, accuracy: 0.0001)
    }

    func test_wideRecatchRefreshesTimer() {
        var sys = PowerUpSystem(seed: 1)
        sys.grant(.widePaddle, to: .bottom)
        tickThrough(&sys, seconds: 6)
        sys.grant(.widePaddle, to: .bottom)
        tickThrough(&sys, seconds: 6)
        XCTAssertTrue(sys.effects(for: .bottom).isWide) // 6 < refreshed 10
        tickThrough(&sys, seconds: 5)
        XCTAssertFalse(sys.effects(for: .bottom).isWide)
    }

    func test_shieldGrantConsumeAndSecondCatchNoOps() {
        var sys = PowerUpSystem(seed: 1)
        sys.grant(.shield, to: .top)
        XCTAssertTrue(sys.hasShield(for: .top))
        sys.grant(.shield, to: .top)   // no-op, still exactly one shield
        sys.consumeShield(for: .top)
        XCTAssertFalse(sys.hasShield(for: .top))
    }

    func test_stickyArmAndConsume() {
        var sys = PowerUpSystem(seed: 1)
        sys.grant(.stickyBall, to: .bottom)
        XCTAssertTrue(sys.stickyArmed(for: .bottom))
        sys.consumeSticky(for: .bottom)
        XCTAssertFalse(sys.stickyArmed(for: .bottom))
    }
}
