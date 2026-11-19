//
//  PongWatchApp.swift
//  PongWatch Watch App
//
//  Created by John Adkerson on 4/14/26.
//

import SwiftUI

@main
struct PongWatch_Watch_AppApp: App {
    @StateObject private var purchases = PurchaseService(store: ProgressionStore())

    init() {
        #if DEBUG
        // Seed here, not in the view: a @ViewBuilder is evaluated more than
        // once, so seeding there awarded the points on every pass and the
        // captured balance came out as a multiple of what was asked for.
        // The simulator also keeps its wallet between runs, hence the wipe.
        if let points = ScreenshotRoute.seededPoints {
            if let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: id)
            }
            // The cloud wallet has to go too. Wiping only the local copy left
            // the simulator's iCloud key-value store holding the old ledger,
            // which merged straight back on the next launch — the grow-only
            // merge working exactly as designed, and defeating the reset.
            let cloud = NSUbiquitousKeyValueStore.default
            cloud.removeObject(forKey: "progress.ledger")
            cloud.synchronize()
            ProgressionStore().award(points)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(purchases)
                // At launch, not when the store opens: a purchase finished while
                // the app was dead is credited without a visit to the store.
                .task {
                    // The unit-test host launches the app; keep it off the real App Store.
                    guard NSClassFromString("XCTestCase") == nil else { return }
                    purchases.listenForTransactions()
                    await purchases.creditUnfinished()
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        // Screenshot harness: a launch argument opens one screen directly.
        // Falls through to the normal app when no -screen is passed.
        if let route = ScreenshotRoute.current {
            screenshotScreen(route)
        } else {
            normalRoot
        }
        #else
        normalRoot
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func screenshotScreen(_ route: ScreenshotRoute) -> some View {
        let store = ProgressionStore()
        switch route {
        case .getPoints:
            // Chase the cheapest thing the seeded balance can't cover, so the
            // "N more to go" line has something real to say.
            GetPointsView(
                chasing: UnlockCatalog.all
                    .filter { $0.cost > store.availablePoints }
                    .min(by: { $0.cost < $1.cost }),
                onDone: {}
            )
        case .unlocks:
            UnlocksView(onBack: {})
        }
    }
    #endif

    @ViewBuilder
    private var normalRoot: some View {
        #if os(watchOS)
        ContentView()
        #else
        // Screens are laid out for a watch; larger text makes the same
        // views read naturally on a phone.
        ContentView()
            .dynamicTypeSize(.accessibility2)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .statusBarHidden()
        #endif
    }
}
