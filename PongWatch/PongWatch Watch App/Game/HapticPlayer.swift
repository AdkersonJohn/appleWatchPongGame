import Foundation
#if canImport(WatchKit)
import WatchKit
#endif

protocol HapticPlayer {
    func playClick()
    func playSuccess()
}

struct WatchHapticPlayer: HapticPlayer {
    func playClick() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
    func playSuccess() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}
