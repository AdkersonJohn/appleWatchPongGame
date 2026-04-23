import SwiftUI

struct ContentView: View {
    @StateObject private var state = GameState()

    var body: some View {
        switch state.phase {
        case .start:
            StartView(
                onStartSinglePlayer: { state.startGame() },
                onStartMultiplayer: { /* Task 19 wires this */ }
            )
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
