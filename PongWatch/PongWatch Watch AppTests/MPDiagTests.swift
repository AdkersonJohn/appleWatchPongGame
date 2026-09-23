import XCTest
@testable import PongWatch_Watch_App

@MainActor
final class MPDiagTests: XCTestCase {
    override func setUp() async throws { MPDiag.shared.reset() }

    /// The log is the only evidence we get back from a real two-device test,
    /// so it has to survive a long session without eating memory.
    func test_logKeepsTheNewestLinesAndDropsTheOldest() {
        for i in 0..<(MPDiag.capacity + 25) { MPDiag.shared.event("line \(i)") }
        let lines = MPDiag.shared.lines
        XCTAssertEqual(lines.count, MPDiag.capacity)
        XCTAssertTrue(lines.last!.contains("line \(MPDiag.capacity + 24)"), "newest must survive")
        XCTAssertFalse(lines.contains { $0.contains("line 0 ") }, "oldest must be dropped")
    }

    func test_resetStampsDeviceAndBuildSoAPhotoOfTheLogIdentifiesTheDevice() {
        MPDiag.shared.reset()
        let first = MPDiag.shared.lines.first ?? ""
        XCTAssertTrue(first.contains("proto"), "header should name the protocol version: \(first)")
        #if os(watchOS)
        XCTAssertTrue(first.contains("watchOS"), "header should name the platform: \(first)")
        #endif
    }

    /// Snapshots run at 30Hz. Logging each one would bury the connection events
    /// that actually matter, so they roll up into one line every few seconds.
    func test_highRateEventsRollUpInsteadOfFloodingTheLog() {
        MPDiag.shared.reset()
        let t0 = Date()
        for _ in 0..<90 { MPDiag.shared.tally("snap rx", now: t0) }
        XCTAssertEqual(MPDiag.shared.lines.filter { $0.contains("snap rx") }.count, 0,
                       "must not emit a line per event")

        MPDiag.shared.tally("snap rx", now: t0.addingTimeInterval(MPDiag.tallyFlushSeconds + 0.1))
        let rolled = MPDiag.shared.lines.filter { $0.contains("snap rx") }
        XCTAssertEqual(rolled.count, 1, "one summary line")
        XCTAssertTrue(rolled[0].contains("91"), "summary carries the count: \(rolled[0])")
    }

    func test_shareTextIsEveryLineSoItCanBePastedFromThePhone() {
        MPDiag.shared.reset()
        MPDiag.shared.event("alpha")
        MPDiag.shared.event("beta")
        XCTAssertTrue(MPDiag.shared.shareText.contains("alpha"))
        XCTAssertTrue(MPDiag.shared.shareText.contains("beta"))
    }
}

final class ProtoCompatibilityTests: XCTestCase {
    /// A watch on an older build talking to a phone on a newer one is the most
    /// likely cross-platform failure, and it looks like a dead match otherwise.
    func test_differentProtocolVersionsAreFlaggedNotSilentlyAccepted() {
        XCTAssertFalse(ProtoCheck.isCompatible(GameConstants.multiplayerProtocolVersion + 1))
        XCTAssertTrue(ProtoCheck.isCompatible(GameConstants.multiplayerProtocolVersion))
    }
}

final class MessageFramingFailureTests: XCTestCase {
    /// A payload we can't decode used to vanish without trace. On a two-device
    /// test that reads as "connected but nothing happens".
    func test_undecodablePayloadIsCountedSoTheLogCanReportIt() {
        let decoder = MessageFraming.Decoder()
        var junk = Data([0, 0, 0, 3])
        junk.append(contentsOf: [0x7b, 0x7d, 0x21])   // "{}!" — not a NetworkMessage
        XCTAssertTrue(decoder.feed(junk).isEmpty)
        XCTAssertEqual(decoder.failureCount, 1)
    }

    func test_goodMessagesStillDecodeAndDoNotCount() throws {
        let decoder = MessageFraming.Decoder()
        let data = try MessageFraming.encode(.clientReady)
        XCTAssertEqual(decoder.feed(data), [.clientReady])
        XCTAssertEqual(decoder.failureCount, 0)
    }
}
