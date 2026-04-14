import SwiftUI

struct StartView: View {
    @AppStorage(HighScoreStore.userDefaultsKey) private var highScore: Int = 0
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("PONG")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                if highScore > 0 {
                    Text("High Score: \(highScore)")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer().frame(height: 16)
                Text("Tap to Play")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onStart()
        }
    }
}

#Preview {
    StartView(onStart: {})
}
