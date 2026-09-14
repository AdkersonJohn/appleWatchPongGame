import SwiftUI

struct StartView: View {
    @AppStorage(HighScoreStore.userDefaultsKey) private var highScore: Int = 0
    let onStartSinglePlayer: () -> Void
    // Unused while multiplayer is hidden for v1.0; restore the menu button to bring it back.
    let onStartMultiplayer: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("PONG")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                if highScore > 0 {
                    Text("High Score: \(highScore)")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer().frame(height: 4)
                Button(action: onStartSinglePlayer) {
                    Text("Single Player")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    StartView(onStartSinglePlayer: {}, onStartMultiplayer: {})
}
