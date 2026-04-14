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
            // By the time this arm renders, GameState.update(dt:) has already
            // called HighScoreStore.updateIfHigher, so a record run means
            // state.score == HighScoreStore().current.
            let isNewHigh = state.score > 0 && state.score == HighScoreStore().current
            GameOverView(
                finalScore: state.score,
                isNewHighScore: isNewHigh,
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
