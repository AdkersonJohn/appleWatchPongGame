import XCTest
@testable import PongWatch_Watch_App

final class GameTypesTests: XCTestCase {
    func test_ballInitialization() {
        let ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                        velocity: CGVector(dx: 0.1, dy: -0.2))
        XCTAssertEqual(ball.position.x, 0.5)
        XCTAssertEqual(ball.position.y, 0.5)
        XCTAssertEqual(ball.velocity.dx, 0.1)
        XCTAssertEqual(ball.velocity.dy, -0.2)
    }

    func test_gamePhaseIsEquatable() {
        XCTAssertEqual(GamePhase.start, GamePhase.start)
        XCTAssertNotEqual(GamePhase.start, GamePhase.playing)
    }
}
