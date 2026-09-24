import SwiftUI

struct StartView: View {
    @AppStorage(HighScoreStore.userDefaultsKey) private var highScore: Int = 0
    let onStartSinglePlayer: () -> Void
    let onStartMultiplayer: () -> Void
    let onOpenUnlocks: () -> Void
    /// Read fresh each time the menu appears, so a purchase shows immediately.
    @State private var points = ProgressionStore().availablePoints

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("PONG")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                // One line, not two: a third row of text pushed the title up
                // into the clock on a 40mm screen.
                HStack(spacing: 6) {
                    if highScore > 0 {
                        Text("Best \(highScore)")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text("\(points) pts")
                        .foregroundColor(.yellow.opacity(0.9))
                }
                .font(.footnote)
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

                Button(action: onOpenUnlocks) {
                    Text("Unlocks")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onStartMultiplayer) {
                    Text("Multiplayer")
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
        .onAppear { points = ProgressionStore().availablePoints }
    }
}

#Preview {
    StartView(onStartSinglePlayer: {}, onStartMultiplayer: {}, onOpenUnlocks: {})
}
