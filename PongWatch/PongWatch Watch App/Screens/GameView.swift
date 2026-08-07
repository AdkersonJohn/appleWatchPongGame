import SwiftUI
import WatchKit

/// Integrates Digital Crown angular velocity into paddle position. The crown
/// reports velocity in rotations/second, so `widthPerRotation` alone sets the
/// mapping — no unit guesswork like the raw accumulated-value binding, whose
/// scale is undocumented. Position advances only while the crown is actually
/// turning, so the paddle stops dead when rotation stops.
struct CrownIntegrator {
    var position: CGFloat = 0.5
    /// Rotations/second from the latest crown event; zeroed on idle.
    var velocity: Double = 0
    /// When the last crown event arrived — a stale velocity means the crown
    /// stopped without onIdle having landed yet.
    var lastEventAt: TimeInterval = 0

    mutating func advance(dt: CGFloat, now: TimeInterval,
                          widthPerRotation: CGFloat = GameConstants.crownWidthPerRotation,
                          maxSpeed: CGFloat = GameConstants.crownMaxPaddleSpeed,
                          staleAfter: TimeInterval = GameConstants.crownVelocityStaleAfter) -> CGFloat {
        if now - lastEventAt > staleAfter { velocity = 0 }
        let speed = min(maxSpeed, max(-maxSpeed, CGFloat(velocity) * widthPerRotation))
        position = min(1, max(0, position + speed * dt))
        return position
    }
}

/// Decides when a crown haptic tick fires. One tick per `step` of paddle
/// travel makes the rate linear in crown speed; `minInterval` caps that rate
/// so fast spins stay a train of discernible taps instead of a buzz.
struct CrownHaptics {
    private var travel: CGFloat = 0
    private var lastTick: TimeInterval = -.greatestFiniteMagnitude

    mutating func shouldTick(travelDelta: CGFloat, now: TimeInterval,
                             step: CGFloat = GameConstants.crownHapticStep,
                             minInterval: Double = GameConstants.crownHapticMinInterval) -> Bool {
        travel += abs(travelDelta)
        guard travel >= step, now - lastTick >= minInterval else { return false }
        travel = 0
        lastTick = now
        return true
    }
}

struct GameView: View {
    @ObservedObject var state: GameState
    @Environment(\.scenePhase) private var scenePhase
    /// Bound because the modifier requires it; the event velocity is what drives
    /// the paddle, not this accumulated value.
    @State private var crownValue: Double = 0
    @State private var crown = CrownIntegrator()
    @State private var haptics = CrownHaptics()
    /// Optional (myScore, opponentScore) overlay for multiplayer mode.
    var multiplayerScores: (mine: Int, opp: Int)? = nil
    /// Closure called every render tick (for MP host physics + snapshot send).
    /// If nil, GameView runs single-player update via state.update(dt:).
    var onTick: ((CGFloat) -> Void)? = nil
    /// Closure called when the crown changes — replaces default state.setPlayerPaddle.
    /// If nil, default behavior is used.
    var onCrownChange: ((CGFloat) -> Void)? = nil
    /// Called on a screen tap. If nil, single-player default: release a bottom-stuck ball.
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Canvas { context, size in
                    drawPlayfield(context: context, size: size)
                }
                .background(Color.black)
            }
            .ignoresSafeArea()

            // Score overlay — lives outside the ignoreSafeArea region so the
            // watch's curved corner doesn't clip the digits.
            VStack {
                HStack {
                    if let mp = multiplayerScores {
                        Text("\(mp.mine) — \(mp.opp)")
                            .font(.caption2)
                            .foregroundColor(.white)
                    } else {
                        Text("\(state.score)")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 4)
        }
        .focusable()
        .onTapGesture {
            if let onTap { onTap() } else { state.tapRelease(side: .bottom) }
        }
        // Velocity-driven: paddle speed tracks crown speed, and onIdle stops it
        // outright — no SwiftUI flick-deceleration anywhere in the path.
        .digitalCrownRotation(
            $crownValue,
            onChange: { event in
                crown.velocity = event.velocity
                crown.lastEventAt = Date().timeIntervalSinceReferenceDate
            },
            onIdle: { crown.velocity = 0 }
        )
        .task(id: scenePhase) {
            // Restarts on scenePhase change. When the user drops their wrist
            // (scenePhase → .inactive/.background) the loop bails so physics
            // don't advance while the app is dimmed or suspended. On return to
            // .active, a fresh task starts with fresh timing.
            guard scenePhase == .active else { return }

            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_666_666) // ~60fps
                let now = Date()
                let dt = CGFloat(now.timeIntervalSince(last))
                last = now
                // A large gap means the task was throttled by the OS
                // (wrist-down, Always-On). Treat this tick as a resume and
                // skip it so the ball doesn't teleport.
                if dt > 0.1 { continue }
                let clampedDt = min(dt, 0.05)
                // Paddle advances on frame time from crown velocity, so slow
                // rotation yields slow, continuous motion.
                let previousX = crown.position
                let x = crown.advance(dt: clampedDt, now: now.timeIntervalSinceReferenceDate)
                if x != previousX {
                    if let onCrownChange {
                        onCrownChange(x)
                    } else {
                        state.setPlayerPaddle(normalizedCrown: x)
                    }
                    // Distance-based clicks instead of system detents; see CrownHaptics.
                    if haptics.shouldTick(travelDelta: x - previousX,
                                          now: now.timeIntervalSinceReferenceDate) {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
                if let onTick {
                    onTick(clampedDt)
                } else {
                    state.update(dt: clampedDt)
                }
            }
        }
    }

    private func drawPlayfield(context: GraphicsContext, size: CGSize) {
        let bottomSticky = state.powerUps.stickyArmed(for: .bottom) || state.stuckBall?.side == .bottom || state.remoteStuckSide == .bottom
        let topSticky = state.powerUps.stickyArmed(for: .top) || state.stuckBall?.side == .top || state.remoteStuckSide == .top

        // Player paddle (bottom)
        drawPaddle(context: context, size: size,
                   centerX: state.playerPaddleX,
                   centerY: 1.0 - GameConstants.paddleMarginY,
                   width: state.powerUps.paddleWidth(for: .bottom),
                   color: bottomSticky ? .green : .white)
        // AI paddle (top)
        drawPaddle(context: context, size: size,
                   centerX: state.aiPaddleX,
                   centerY: GameConstants.paddleMarginY,
                   width: state.powerUps.paddleWidth(for: .top),
                   color: topSticky ? .green : .white)

        if let count = state.countdownRemaining {
            // Countdown: hide ball, show big number in center.
            let countText = Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            context.draw(countText,
                         at: CGPoint(x: size.width / 2, y: size.height / 2),
                         anchor: .center)
        } else {
            // Balls
            for b in state.balls {
                let ballPx = CGPoint(x: b.position.x * size.width,
                                     y: b.position.y * size.height)
                let ballRadiusPx = GameConstants.ballRadius * size.width
                let ballRect = CGRect(x: ballPx.x - ballRadiusPx, y: ballPx.y - ballRadiusPx,
                                      width: ballRadiusPx * 2, height: ballRadiusPx * 2)
                context.fill(Path(ellipseIn: ballRect), with: .color(.white))
            }
        }

        // Score is now drawn as a SwiftUI overlay in `body` so the watch's
        // curved corner doesn't clip the digits.

        // Scoring burst particles
        for p in state.particles {
            let center = CGPoint(x: p.position.x * size.width, y: p.position.y * size.height)
            let r = p.radius * size.width
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let alpha = max(0, min(1, p.ageRemaining / p.totalAge))
            let color = Color(red: p.red, green: p.green, blue: p.blue).opacity(alpha)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }

        // Power-up pickup — distinct shape + color per kind, flashing to stand out.
        // Canvas redraws every game tick, so wall-clock time drives the blink.
        if let pickup = state.powerUps.pickup {
            let c = GameConstants.pickupColor(for: pickup.kind)
            let center = CGPoint(x: pickup.position.x * size.width,
                                 y: pickup.position.y * size.height)
            let r = GameConstants.powerUpPickupRadius * size.width
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let t = Date().timeIntervalSinceReferenceDate
            var flashCtx = context
            flashCtx.opacity = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 14))  // ~2.2 Hz blink
            flashCtx.fill(pickupShape(for: pickup.kind, center: center, r: r),
                          with: .color(Color(red: c.0, green: c.1, blue: c.2)))
            let symbol = flashCtx.resolve(
                Image(systemName: GameConstants.pickupSymbol(for: pickup.kind))
            )
            flashCtx.draw(symbol, in: rect.insetBy(dx: r * 0.45, dy: r * 0.45))
        }

        // Shields — thin line just behind each protected paddle
        if state.powerUps.hasShield(for: .bottom) {
            let rect = CGRect(x: 0, y: size.height - 3, width: size.width, height: 3)
            context.fill(Path(rect), with: .color(.blue))
        }
        if state.powerUps.hasShield(for: .top) {
            let rect = CGRect(x: 0, y: 0, width: size.width, height: 3)
            context.fill(Path(rect), with: .color(.blue))
        }
    }

    /// Per-kind silhouette: wide capsule / rounded square / circle / diamond,
    /// so kinds read at a glance even before the color registers.
    private func pickupShape(for kind: PowerUpKind, center: CGPoint, r: CGFloat) -> Path {
        switch kind {
        case .widePaddle:
            return Path(roundedRect: CGRect(x: center.x - r * 1.4, y: center.y - r * 0.65,
                                            width: r * 2.8, height: r * 1.3),
                        cornerRadius: r * 0.65)
        case .shield:
            return Path(roundedRect: CGRect(x: center.x - r, y: center.y - r,
                                            width: r * 2, height: r * 2),
                        cornerRadius: r * 0.3)
        case .stickyBall:
            return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                          width: r * 2, height: r * 2))
        case .multiBall:
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - r * 1.25))
            p.addLine(to: CGPoint(x: center.x + r * 1.25, y: center.y))
            p.addLine(to: CGPoint(x: center.x, y: center.y + r * 1.25))
            p.addLine(to: CGPoint(x: center.x - r * 1.25, y: center.y))
            p.closeSubpath()
            return p
        }
    }

    private func drawPaddle(context: GraphicsContext, size: CGSize,
                            centerX: CGFloat, centerY: CGFloat,
                            width: CGFloat, color: Color = .white) {
        let wPx = width * size.width
        let hPx = GameConstants.paddleHeight * size.height
        let rect = CGRect(
            x: centerX * size.width - wPx / 2,
            y: centerY * size.height - hPx / 2,
            width: wPx,
            height: hPx
        )
        let path = Path(roundedRect: rect, cornerRadius: hPx / 2)
        context.fill(path, with: .color(color))
    }
}

#Preview {
    let state = GameState()
    state.phase = .playing
    state.ball = Ball(position: CGPoint(x: 0.5, y: 0.5),
                      velocity: .zero)
    state.score = 3
    return GameView(state: state)
}
