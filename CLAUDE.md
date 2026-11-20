# Pong Pal Showdown — project notes

## Simulator screenshot harness

**Do not delete any part of this. It has been lost once already.**

Deep app screens are captured headlessly, by launch argument. There is no way
to tap through to them on this machine:

- **Simulator.app is not installed** — not in `/Applications`, not in the Xcode
  bundle. Only the background `CoreSimulator` services exist, so there is no
  window to click.
- **`simctl` has no tap API.** It can boot, install, launch and screenshot, and
  that is all.
- **A physical Apple Watch has no tap API either**, and confirming an Apple
  payment there needs a hardware double-click that cannot be automated.

An earlier version of this hook was written as a throwaway, marked
"DELETE before commit", and duly deleted — taking the capability with it. Hence
this section.

### Running it

```bash
scripts/screenshots.sh [output-dir] [simulator-udid]
```

The UDID is optional and resolved by name when omitted, because stored UDIDs go
stale every time Xcode rotates simulator runtimes. PNGs land in the output
directory, one per captured screen (default `screenshots/`, which is gitignored).

### The three pieces

1. **`PongWatch Watch App/ScreenshotRoute.swift`** — reads `-screen <name>` and
   optional `-points <n>` from the launch arguments. `#if DEBUG`, so none of it
   reaches a release build.
2. **`PongWatch Watch AppUITests/ScreenshotTests.swift`** — launches the app
   with those arguments and attaches `XCUIScreen` captures. It *waits for a
   price to render* rather than sleeping, so it fails loudly instead of
   silently capturing an empty screen.
3. **`Points.storekit`, attached to the scheme's Test action** — without this
   the app finds no products and the Get Points screen renders its "App Store
   isn't available" fallback. The reference lives in
   `xcshareddata/xcschemes/PongWatch Watch App.xcscheme` under both
   `LaunchAction` and `TestAction`; the path `../../../Points.storekit` is
   relative to the scheme file.

### Adding a screen

Add a case to `ScreenshotRoute`, render it in `screenshotScreen(_:)` in
`PongWatchApp.swift`, and add a `capture(screen:points:named:)` call in
`ScreenshotTests`.

## Building and testing

- **Archive the `PongWatch` (iOS) scheme, never `PongWatch Watch App`.** The
  watch app is an embedded target with `SKIP_INSTALL = YES`, so archiving its
  own scheme prints `ARCHIVE SUCCEEDED` and produces an archive with an empty
  `Products/`. The failure surfaces one step later as a misleading
  `exportOptionsPlist error for key "method"`.
- **Test destinations must use a simulator UDID, not a name**, and the UDIDs
  change when Xcode updates. Resolve them with
  `xcodebuild -scheme "PongWatch Watch App" -showdestinations`.
- Two flaky tests live in `MultiplayerGameStateTests`, both timing races that
  predate current work:
  `test_disconnectDuringConfiguringMatchReturnsToPairingNotMatchOver` (a
  hardcoded ~50ms sleep) and `test_hostAppliesIncomingPaddleInput`. The second
  passed 3/3 in isolation on 2026-11-20 after failing in a full run. A run
  failing only these is green — but re-run the named test alone before
  believing that, rather than assuming.

## Test targets

- `PongWatch Watch AppTests` — the main suite, hosted by the watch app.
- `PongWatchTests` — an **iOS** unit-test target hosted by the iPhone app. It
  exists because StoreKit work needs a host that can present a purchase sheet.
  The app's sources build for both platforms, so code tested here is the code
  that ships on the watch.
- `RefundIntegrationTests` lives in the iOS target and is skipped unless
  `REFUND_INTEGRATION=1`: `product.purchase()` does not return under XCTest on
  either platform. See the comment in that file before trying again.
