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
