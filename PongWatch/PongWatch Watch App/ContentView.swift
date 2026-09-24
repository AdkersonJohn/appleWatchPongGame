import SwiftUI

enum GameMode {
    case singlePlayer
    case multiplayer
    case unlocks
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
                    },
                    onOpenUnlocks: { mode = .unlocks }
                )

            case .singlePlayer:
                switch singlePlayerState.phase {
                case .start:
                    StartView(
                        onStartSinglePlayer: { singlePlayerState.startGame() },
                        onStartMultiplayer: { mode = .multiplayer },
                        onOpenUnlocks: { mode = .unlocks }
                    )
                case .playing:
                    GameView(state: singlePlayerState)
                case .gameOver:
                    GameOverView(
                        finalScore: singlePlayerState.score,
                        isNewHighScore: singlePlayerState.lastRunWasRecord,
                        onRestart: {
                            singlePlayerState.startGame()
                        },
                        onMainMenu: {
                            mode = nil
                        }
                    )
                }

            case .unlocks:
                UnlocksView(onBack: { mode = nil })

            case .multiplayer:
                multiplayerRoot
            }
        }
    }

    @ViewBuilder
    private var multiplayerRoot: some View {
        switch mpState.matchPhase {
        case .pairing:
            switch PairingScreen.screen(for: mpService.connectionState) {
            case .invitePrompt(let name):
                InvitePromptView(
                    peerName: name,
                    onAccept: { mpService.respondToInvite(accept: true) },
                    onDecline: {
                        mpService.respondToInvite(accept: false)
                        mode = nil
                    }
                )
            case .waitingForAccept:
                // Without this the lobby stayed up while the invite connected,
                // so tapping a peer looked like nothing happened at all.
                WaitingForAcceptView(onCancel: { mpService.disconnect() })
            case .lobby:
                NearbyPlayersView(service: mpService, onBack: {
                    mpService.disconnect()
                    mode = nil
                })
            }

        case .waitingForOpponentAccept:
            WaitingForAcceptView(onCancel: { mpState.cancelMatchConfiguration() })

        case .configuringMatch:
            if mpState.role == .host {
                MatchConfigView(
                    onPick: { target in mpState.startMatch(winningScore: target) },
                    onBack: { mpState.cancelMatchConfiguration() }
                )
            } else {
                WaitingForHostView()
            }

        case .playing, .pausedByOpponent:
            GameView(
                state: mpState.game,
                matchAspect: mpState.fieldAspect,
                multiplayerScores: (mine: myScore, opp: oppScore),
                onTick: { dt in mpState.tick(dt: dt) },
                onCrownChange: { v in mpState.setLocalPaddle(normalizedCrown: v) },
                onTap: { mpState.localTapRelease() }
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
                allowRematch: isPeerStillConnected,
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
                allowRematch: false,
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

    /// True when the peer's connection is still alive — disables Rematch
    /// otherwise so we can't try to start a fresh match without a peer.
    private var isPeerStillConnected: Bool {
        if case .connected = mpService.connectionState { return true }
        return false
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
