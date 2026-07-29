import SwiftUI

struct GameView: View {
    @ObservedObject var state: GameState
    @Environment(\.scenePhase) private var scenePhase
    @State private var crownValue: Double = 0.5
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
        .digitalCrownRotation(
            $crownValue,
            from: 0.0,
            through: 1.0,
            by: 0.005,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            if let onCrownChange {
                onCrownChange(CGFloat(newValue))
            } else {
                state.setPlayerPaddle(normalizedCrown: CGFloat(newValue))
            }
        }
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
                if let onTick {
                    onTick(clampedDt)
                } else {
                    state.update(dt: clampedDt)
                }
            }
        }
    }

    private func drawPlayfield(context: GraphicsContext, size: CGSize) {
        let bottomSticky = state.powerUps.stickyArmed(for: .bottom) || state.stuckBall?.side == .bottom
        let topSticky = state.powerUps.stickyArmed(for: .top) || state.stuckBall?.side == .top

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

        // Power-up pickup
        if let pickup = state.powerUps.pickup {
            let c = GameConstants.pickupColor(for: pickup.kind)
            let center = CGPoint(x: pickup.position.x * size.width,
                                 y: pickup.position.y * size.height)
            let r = GameConstants.powerUpPickupRadius * size.width
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(Color(red: c.0, green: c.1, blue: c.2)))
            let symbol = context.resolve(
                Image(systemName: GameConstants.pickupSymbol(for: pickup.kind))
            )
            context.draw(symbol, in: rect.insetBy(dx: r * 0.45, dy: r * 0.45))
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
