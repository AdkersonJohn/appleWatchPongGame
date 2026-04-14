import SwiftUI

struct GameOverView: View {
    let finalScore: Int
    let isNewHighScore: Bool
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 6) {
                if isNewHighScore {
                    Text("🏆 New High Score!")
                        .font(.footnote)
                        .foregroundColor(.yellow)
                }
                Text("Game Over")
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
                Text("Score: \(finalScore)")
                    .font(.body)
                    .foregroundColor(.white)
                Spacer().frame(height: 12)
                Text("Tap to Play Again")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onRestart()
        }
    }
}

#Preview("New High Score") {
    GameOverView(finalScore: 42, isNewHighScore: true, onRestart: {})
}

#Preview("Normal") {
    GameOverView(finalScore: 5, isNewHighScore: false, onRestart: {})
}
