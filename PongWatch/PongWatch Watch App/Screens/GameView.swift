import SwiftUI

struct GameView: View {
    @ObservedObject var state: GameState
    @State private var lastFrameTime: Date?
    @State private var crownValue: Double = 0.5

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    let dt: CGFloat
                    if let last = lastFrameTime {
                        dt = CGFloat(now.timeIntervalSince(last))
                    } else {
                        dt = 0
                    }
                    let cappedDt = min(dt, 0.05)
                    state.update(dt: cappedDt)
                    DispatchQueue.main.async {
                        lastFrameTime = now
                    }
                    drawPlayfield(context: context, size: size)
                }
                .background(Color.black)
            }
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
