import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#endif

protocol HapticPlayer {
    func playClick()
    func playSuccess()
}

struct WatchHapticPlayer: HapticPlayer {
    func playClick() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    func playSuccess() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #elseif canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
