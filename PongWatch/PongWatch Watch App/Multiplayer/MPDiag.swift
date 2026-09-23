import Foundation
import Combine
import os
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// Diagnostics for the peer-to-peer lobby and match.
///
/// Two sinks on purpose. `os_log` is the good one, but it needs a Mac running
/// Console attached to the device — which a tester in another room does not
/// have. So every event also lands in an in-memory ring buffer the app can
/// draw on-screen, which is the only channel that reaches someone debugging
/// from their wrist.
@MainActor
final class MPDiag: ObservableObject {
    static let shared = MPDiag()

    /// Big enough to hold a whole pairing attempt plus a minute of play.
    static let capacity = 400
    /// How long high-rate events accumulate before one summary line is emitted.
    static let tallyFlushSeconds: TimeInterval = 3

    private let log = Logger(subsystem: "com.johnadkerson.PongWatch", category: "multiplayer")
    /// Newest last. Capped so a long session can't grow unbounded.
    @Published private(set) var lines: [String] = []
    private var origin = Date()

    /// High-rate events (snapshots, paddle inputs) counted rather than printed.
    private var counters: [String: Int] = [:]
    private var lastFlush = Date()

    func event(_ text: String) {
        // .notice, not .info: info-level messages are not persisted, so they
        // vanish before a tester can collect them off a real device.
        log.notice("\(text, privacy: .public)")
        let stamp = String(format: "%5.1f", Date().timeIntervalSince(origin))
        lines.append("\(stamp) \(text)")
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    /// Records one occurrence of a repeating event. Thirty snapshots a second
    /// would bury the connection events that actually explain a failure, so
    /// these surface as a periodic "snap rx=90, input tx=90" line instead.
    func tally(_ key: String, now: Date = Date()) {
        counters[key, default: 0] += 1
        if now.timeIntervalSince(lastFlush) >= Self.tallyFlushSeconds { flushTallies(now: now) }
    }

    func flushTallies(now: Date = Date()) {
        lastFlush = now
        guard !counters.isEmpty else { return }
        let summary = counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        counters.removeAll()
        event("rate: \(summary)")
    }

    /// Everything in the buffer as one blob, for the phone's Copy button.
    var shareText: String { lines.joined(separator: "\n") }

    /// Called when the lobby opens so each attempt reads as a fresh timeline.
    func reset() {
        lines.removeAll()
        counters.removeAll()
        origin = Date()
        lastFlush = origin
        event(Self.deviceHeader)
    }

    /// Identifies the device in a photo of the log — the cross-platform test
    /// produces two logs and they have to be told apart at a glance.
    static var deviceHeader: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        let platform = "watchOS \(device.systemVersion)"
        let model = device.model
        #else
        let device = UIDevice.current
        let platform = "\(device.systemName) \(device.systemVersion)"
        let model = device.model
        #endif
        return "=== \(platform) · \(model) · v\(version) (\(build)) · proto \(GameConstants.multiplayerProtocolVersion) ==="
    }

    /// Short tag advertised in the TXT record and shown beside a peer's name,
    /// so each side can see what it is actually talking to.
    static var platformTag: String {
        #if os(watchOS)
        return "watch"
        #else
        return "phone"
        #endif
    }
}
