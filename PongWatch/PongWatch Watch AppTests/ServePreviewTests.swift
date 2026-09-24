import XCTest
@testable import PongWatch_Watch_App

final class ServePreviewTests: XCTestCase {
    /// Players need to know which way the serve is going before it moves, so
    /// the direction has to be chosen when the countdown starts, not when it
    /// ends. Otherwise there is nothing to draw.
    func test_serveDirectionIsKnownDuringTheCountdown() {
        let state = GameState()
        state.startGame()
        XCTAssertNotNil(state.countdownRemaining)
        let serve = state.pendingServe
        XCTAssertNotNil(serve, "the serve must be decided up front")
        XCTAssertEqual(hypot(serve!.dx, serve!.dy), GameConstants.initialBallSpeed, accuracy: 0.001)
    }

    /// The preview would be a lie if the ball then launched somewhere else.
    /// Checked on the tick the ball launches: a further second of physics
    /// could bounce it off a wall and change the velocity legitimately.
    func test_theBallLaunchesAlongExactlyThePreviewedDirection() {
        let state = GameState()
        state.startGame()
        let previewed = state.pendingServe!
        for _ in 0..<GameConstants.countdownStart { state.update(dt: 1.0) }
        XCTAssertNil(state.countdownRemaining, "countdown should have finished")
        XCTAssertEqual(state.ball.velocity.dx, previewed.dx, accuracy: 0.0001)
        XCTAssertEqual(state.ball.velocity.dy, previewed.dy, accuracy: 0.0001)
    }

    func test_previewClearsOnceTheBallIsMoving() {
        let state = GameState()
        state.startGame()
        for _ in 0..<GameConstants.countdownStart { state.update(dt: 1.0) }
        XCTAssertNil(state.pendingServe, "nothing to preview once it's in play")
    }

    /// Each serve gets its own preview, including the ones after a point.
    func test_nextServeAfterAPointGetsAFreshPreview() {
        let state = GameState()
        state.startGame()
        state.prepareNextServe()
        XCTAssertNotNil(state.pendingServe)
    }
}
