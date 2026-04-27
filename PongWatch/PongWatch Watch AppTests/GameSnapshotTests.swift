import XCTest
@testable import PongWatch_Watch_App

final class GameSnapshotTests: XCTestCase {
    func test_gameSnapshotRoundtripsViaJSON() throws {
        let original = GameSnapshot(
            protoVersion: 1,
            phase: .playing,
            ballX: 0.42,
            ballY: 0.37,
            ballVX: -0.5,
            ballVY: 0.8,
            hostPaddleX: 0.5,
            clientPaddleX: 0.6,
            hostScore: 2,
            clientScore: 3,
            countdownRemaining: nil,
            scoreEvent: nil,
            hostPaddleHit: false,
            clientPaddleHit: true,
            tickSeq: 1234
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_paddleInputRoundtripsViaJSON() throws {
        let original = PaddleInput(protoVersion: 1, paddleX: 0.73, tickSeq: 99)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PaddleInput.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_networkMessageEnvelopeCarriesSnapshot() throws {
        let snap = GameSnapshot(
            protoVersion: 1, phase: .playing,
            ballX: 0.5, ballY: 0.5, ballVX: 0, ballVY: 0,
            hostPaddleX: 0.5, clientPaddleX: 0.5,
            hostScore: 0, clientScore: 0,
            countdownRemaining: 3, scoreEvent: nil,
            hostPaddleHit: false, clientPaddleHit: false,
            tickSeq: 0
        )
        let msg = NetworkMessage.snapshot(snap)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(NetworkMessage.self, from: data)
        if case .snapshot(let s) = decoded {
            XCTAssertEqual(s, snap)
        } else {
            XCTFail("Expected .snapshot case")
        }
    }

    func test_scoreEventEncodesScorerRole() throws {
        let event = ScoreEvent(impactX: 0.37, scoredBy: .client)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ScoreEvent.self, from: data)
        XCTAssertEqual(decoded.scoredBy, .client)
        XCTAssertEqual(decoded.impactX, 0.37, accuracy: 1e-9)
    }
}
