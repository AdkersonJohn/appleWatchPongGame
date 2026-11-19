#if DEBUG
import SwiftUI

/// Opens a single screen straight from a launch argument, so a headless
/// simulator can capture a deep screen without anyone tapping through to it.
///
/// **This is the simulator screenshot harness. Do not delete it.** A previous
/// version of this hook was written as a throwaway, removed after use, and the
/// capability was lost — see CLAUDE.md, "Simulator screenshot harness".
///
/// `DEBUG` only, so it never reaches a release build. App Store builds compile
/// without this file's contents at all.
///
///     xcrun simctl launch <udid> <bundle-id> -screen getPoints -points 17
enum ScreenshotRoute: String {
    case getPoints
    case unlocks

    /// The route named by `-screen <name>`, or nil for the normal app.
    static var current: ScreenshotRoute? {
        value(for: "-screen").flatMap(ScreenshotRoute.init(rawValue:))
    }

    /// Points to seed before the screen opens, via `-points <n>`. A fresh
    /// simulator has an empty wallet, which makes for a misleading screenshot.
    static var seededPoints: Int? {
        value(for: "-points").flatMap(Int.init)
    }

    private static func value(for flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
#endif
