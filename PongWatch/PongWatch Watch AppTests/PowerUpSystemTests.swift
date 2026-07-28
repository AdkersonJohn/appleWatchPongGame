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
}
