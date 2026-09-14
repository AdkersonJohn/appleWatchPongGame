import SwiftUI

struct StartView: View {
    @AppStorage(HighScoreStore.userDefaultsKey) private var highScore: Int = 0
    let onStartSinglePlayer: () -> Void
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

                // Multiplayer is parked until two-watch discovery is reliable.
                // Flip `.disabled` and drop the overlay to bring it back.
                Button(action: onStartMultiplayer) {
                    Text("Multiplayer")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .overlay(
                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .cornerRadius(4)
                        .rotationEffect(.degrees(-8))
                )
                .accessibilityLabel("Multiplayer, coming soon")
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    StartView(onStartSinglePlayer: {}, onStartMultiplayer: {})
}
