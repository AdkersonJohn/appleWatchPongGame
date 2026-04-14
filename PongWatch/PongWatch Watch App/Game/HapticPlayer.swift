import Foundation
#if canImport(WatchKit)
import WatchKit
#endif

protocol HapticPlayer {
    func playClick()
}

struct WatchHapticPlayer: HapticPlayer {
    func playClick() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}
