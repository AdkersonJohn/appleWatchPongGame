import SwiftUI

struct GameOverView: View {
    let finalScore: Int
    let isNewHighScore: Bool
    let onRestart: () -> Void
    let onMainMenu: () -> Void

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
                Spacer().frame(height: 6)

                Button(action: onRestart) {
                    Text("Play Again")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onMainMenu) {
                    Text("Main Menu")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
        }
    }
}

#Preview("New High Score") {
    GameOverView(finalScore: 42, isNewHighScore: true, onRestart: {}, onMainMenu: {})
}

#Preview("Normal") {
    GameOverView(finalScore: 5, isNewHighScore: false, onRestart: {}, onMainMenu: {})
}
