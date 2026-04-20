import SwiftUI

struct GameView: View {
    @ObservedObject var state: GameState
    @Environment(\.scenePhase) private var scenePhase
    @State private var crownValue: Double = 0.5

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawPlayfield(context: context, size: size)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
        .focusable()
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
            state.setPlayerPaddle(normalizedCrown: CGFloat(newValue))
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
                state.update(dt: min(dt, 0.05))
            }
        }
    }

    private func drawPlayfield(context: GraphicsContext, size: CGSize) {
        // Player paddle (bottom)
        drawPaddle(
            context: context,
            size: size,
            centerX: state.playerPaddleX,
            centerY: 1.0 - GameConstants.paddleMarginY
        )
        // AI paddle (top)
        drawPaddle(
            context: context,
            size: size,
            centerX: state.aiPaddleX,
            centerY: GameConstants.paddleMarginY
        )

        if let count = state.countdownRemaining {
            // Countdown: hide ball, show big number in center.
            let countText = Text("\(count)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            context.draw(countText,
                         at: CGPoint(x: size.width / 2, y: size.height / 2),
                         anchor: .center)
        } else {
            // Ball
            let ballPx = CGPoint(
                x: state.ball.position.x * size.width,
                y: state.ball.position.y * size.height
            )
            let ballRadiusPx = GameConstants.ballRadius * size.width
            let ballRect = CGRect(
                x: ballPx.x - ballRadiusPx,
                y: ballPx.y - ballRadiusPx,
                width: ballRadiusPx * 2,
                height: ballRadiusPx * 2
            )
            context.fill(Path(ellipseIn: ballRect), with: .color(.white))
        }

        // Score
        let scoreText = Text("\(state.score)").font(.caption2).foregroundColor(.white)
        context.draw(scoreText, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
    }

    private func drawPaddle(context: GraphicsContext, size: CGSize, centerX: CGFloat, centerY: CGFloat) {
        let wPx = GameConstants.paddleWidth * size.width
        let hPx = GameConstants.paddleHeight * size.height
        let rect = CGRect(
            x: centerX * size.width - wPx / 2,
            y: centerY * size.height - hPx / 2,
            width: wPx,
            height: hPx
        )
        let path = Path(roundedRect: rect, cornerRadius: hPx / 2)
        context.fill(path, with: .color(.white))
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
