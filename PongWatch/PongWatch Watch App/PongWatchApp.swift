//
//  PongWatchApp.swift
//  PongWatch Watch App
//
//  Created by John Adkerson on 4/14/26.
//

import SwiftUI

@main
struct PongWatch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(watchOS)
            ContentView()
            #else
            // Screens are laid out for a watch; larger text and side margins
            // make the same views read naturally on a phone.
            ContentView()
                .dynamicTypeSize(.accessibility2)
                .padding(.horizontal, 24)
                .background(Color.black.ignoresSafeArea())
                .preferredColorScheme(.dark)
                .statusBarHidden()
            #endif
        }
    }
}
