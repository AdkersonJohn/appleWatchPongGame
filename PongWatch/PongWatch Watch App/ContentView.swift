import SwiftUI

enum GameMode {
    case singlePlayer
    case multiplayer
}

struct ContentView: View {
    @StateObject private var singlePlayerState = GameState()
    @StateObject private var mpService: MultiplayerService
    @StateObject private var mpState: MultiplayerGameState

    @State private var mode: GameMode? = nil
    @Environment(\.scenePhase) private var scenePhaseValue

    init() {
        // Build service first so we can hand the same instance to MultiplayerGameState.
        let service = MultiplayerService()
        _mpService = StateObject(wrappedValue: service)
        _mpState = StateObject(wrappedValue: MultiplayerGameState(service: service))
    }

    var body: some View {
        Group {
            switch mode {
            case .none:
                StartView(
                    onStartSinglePlayer: {
                        mode = .singlePlayer
                        singlePlayerState.startGame()
                    },
                    onStartMultiplayer: {
                        mode = .multiplayer
                    }
                )

            case .singlePlayer:
                switch singlePlayerState.phase {
                case .start:
                    StartView(
                        onStartSinglePlayer: { singlePlayerState.startGame() },
                        onStartMultiplayer: { mode = .multiplayer }
                    )
                case .playing:
                    GameView(state: singlePlayerState)
                case .gameOver:
                    GameOverView(
                        finalScore: singlePlayerState.score,
                        isNewHighScore: singlePlayerState.lastRunWasRecord,
                        onRestart: {
                            singlePlayerState.startGame()
                        }
                    )
                }

            case .multiplayer:
                multiplayerRoot
            }
        }
    }

    @ViewBuilder
    private var multiplayerRoot: some View {
        switch mpState.matchPhase {
        case .pairing:
            if case .receivingInvite(let name) = mpService.connectionState {
                InvitePromptView(
                    peerName: name,
                    onAccept: { mpService.respondToInvite(accept: true) },
                    onDecline: {
                        mpService.respondToInvite(accept: false)
                        mode = nil
                    }
                )
            } else {
                NearbyPlayersView(service: mpService, onBack: {
                    mpService.disconnect()
                    mode = nil
                })
            }

        case .playing, .pausedByOpponent:
            GameView(
                state: mpState.game,
                multiplayerScores: (mine: myScore, opp: oppScore),
                onTick: { dt in mpState.tickIfHost(dt: dt) },
                onCrownChange: { v in mpState.setLocalPaddle(normalizedCrown: v) }
            )
            .onAppear {
                // Stop advertising once we start playing.
                mpService.stopAdvertising()
            }
            .overlay(alignment: .center) {
                if mpState.matchPhase == .pausedByOpponent {
                    Text("Opponent paused…")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                }
            }
            .onChange(of: scenePhaseValue) { _, newPhase in
                mpState.onScenePhaseChanged(to: newPhase == .active ? .active : .inactive)
            }

        case .matchOver(let winner):
            MultiplayerGameOverView(
                didWin: winner == mpState.role,
                myScore: myScore,
                opponentScore: oppScore,
                onRematch: { mpState.requestRematch() },
                onBack: {
                    mpState.leaveMatch()
                    mode = nil
                }
            )

        case .disconnected:
            MultiplayerGameOverView(
                didWin: true,  // peer dropped → we win by default
                myScore: myScore,
                opponentScore: oppScore,
                onRematch: {
                    mpState.leaveMatch()
                    mode = nil
                },
                onBack: {
                    mpState.leaveMatch()
                    mode = nil
                }
            )
        }
    }

    private var myScore: Int {
        switch mpState.role {
        case .host: return mpState.hostScore
        case .client: return mpState.clientScore
        case nil: return 0
        }
    }
    private var oppScore: Int {
        switch mpState.role {
        case .host: return mpState.clientScore
        case .client: return mpState.hostScore
        case nil: return 0
        }
    }
}

#Preview {
    ContentView()
}
