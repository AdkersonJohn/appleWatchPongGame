import SwiftUI

struct ContentView: View {
    @StateObject private var state = GameState()

    var body: some View {
        switch state.phase {
        case .start:
            StartView(onStart: {
                state.startGame()
            })
        case .playing:
            GameView(state: state)
        case .gameOver:
            GameOverView(
                finalScore: state.score,
                isNewHighScore: state.lastRunWasRecord,
                onRestart: {
                    state.startGame()
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
