# Pong Pal Showdown — App Store Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the working multiplayer Apple Watch Pong app from feature-complete on `main` to live in the Apple App Store as the paid $0.99 watchOS app "Pong Pal Showdown," via a TestFlight external beta.

**Architecture:** Four-phase rollout — code polish → App Store assets → TestFlight beta → submission. Code changes are minor (lower deployment target, strip debug logs, fix tests). Most of the effort is non-code: marketing copy, screenshot captures, GitHub Pages hosting, App Store Connect form-filling, beta coordination.

**Tech Stack:** Xcode (Swift / SwiftUI / watchOS), App Store Connect, TestFlight, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-04-27-app-store-submission-design.md`

---

## File Structure

**Modified:**
- `PongWatch/PongWatch.xcodeproj/project.pbxproj` — build settings: deployment target, display name, network description, build number
- `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift` — remove 4 `NSLog("[MP] …")` lines
- `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift` — remove 2 `NSLog("[MP] …")` lines
- `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift` — update 9 stale tests, add 7 new tests for the configuration flow

**Created:**
- `docs/index.html` — GitHub Pages landing page
- `docs/privacy.html` — privacy policy
- `docs/support.html` — support / FAQ page
- `docs/marketing-copy-draft.md` — App Store listing copy (subtitle, description, keywords) for tracking and copy-paste into App Store Connect
- `docs/screenshots/` — directory containing 5 PNG captures from the 49mm Ultra simulator

**Suggested PR boundaries:**
- PR 1: Tasks 1–8 (Phase 1 technical polish)
- PR 2: Tasks 9–15 (Phase 2 assets + GitHub Pages)
- Tasks 16–25 are App Store Connect / TestFlight runbooks — mostly outside the repo, no PRs

---

# PHASE 1 — Pre-submission technical polish

## Task 1: Lower watchOS deployment target to 10.0

**Files:**
- Modify: `PongWatch/PongWatch.xcodeproj/project.pbxproj` — three occurrences of `WATCHOS_DEPLOYMENT_TARGET = 26.4;`

- [ ] **Step 1: Confirm current deployment target lines**

Run:
```bash
grep -n "WATCHOS_DEPLOYMENT_TARGET" "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/PongWatch.xcodeproj/project.pbxproj"
```

Expected: 3 lines, all `WATCHOS_DEPLOYMENT_TARGET = 26.4;`

- [ ] **Step 2: Replace all three with 10.0**

Use Edit tool with `replace_all: true` on the file:
- Old: `WATCHOS_DEPLOYMENT_TARGET = 26.4;`
- New: `WATCHOS_DEPLOYMENT_TARGET = 10.0;`

- [ ] **Step 3: Confirm replacement**

Run the same grep — expected: 3 lines, all `= 10.0;`.

- [ ] **Step 4: Build to verify the project still compiles**

Run:
```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "generic/platform=watchOS Simulator" -derivedDataPath ./build build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If any "is only available in watchOS 11.0 or newer" errors appear, those are real API-availability issues — see Task 4 for handling. For now, fix any straightforward issues by adding `if #available(watchOS X, *) { ... }` guards or by switching to a watchOS 10-supported alternative.

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add PongWatch/PongWatch.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
chore: lower watchOS deployment target from 26.4 to 10.0

Expands install base for the App Store launch. All APIs in use
(Network framework, SwiftUI Canvas, Combine, async/await, digital
crown rotation) have been available since watchOS 8-10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Update CFBundleDisplayName to "Pong Pal Showdown"

The on-watch display name (under the home screen icon) currently reads "PongWatch". Update for App Store consistency.

**Files:**
- Modify: `PongWatch/PongWatch.xcodeproj/project.pbxproj` — `INFOPLIST_KEY_CFBundleDisplayName = PongWatch;` lines (two occurrences for watch app target's Debug + Release)

- [ ] **Step 1: Find the two watch-app display name lines**

Run:
```bash
grep -n 'INFOPLIST_KEY_CFBundleDisplayName' "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/PongWatch.xcodeproj/project.pbxproj"
```

Expected: at least 2 lines reading `INFOPLIST_KEY_CFBundleDisplayName = PongWatch;`. The first two (around lines 460 and 495) belong to the watch app target. There's also one around line 527 for the iOS shell target — leave that one unchanged (the iOS target is a placeholder, not user-facing).

- [ ] **Step 2: Update only the watch-app target lines**

Use Edit tool. Note: the value must be quoted because of the spaces.

- Old: `INFOPLIST_KEY_CFBundleDisplayName = PongWatch;` (occurs in watch app's Debug and Release configs around lines 460 and 495)
- New: `INFOPLIST_KEY_CFBundleDisplayName = "Pong Pal Showdown";`

You'll need to do this surgically with two separate Edit calls (don't use `replace_all` — it would also hit the iOS target's display name). Use the surrounding context (e.g., a few preceding lines) to disambiguate.

- [ ] **Step 3: Build and run on a sim, verify the home-screen label**

Run:
```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "platform=watchOS Simulator,id=91914947-67A1-4AFC-91FD-C242370CB9E6" -derivedDataPath ./build build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. Install + launch on a sim, then back out to the home screen and confirm the label under the icon now reads "Pong Pal Showdown" (it may wrap across two lines on a 41mm watch — that's acceptable).

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add PongWatch/PongWatch.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
chore: rename watch app display name to "Pong Pal Showdown"

Aligns the on-watch home-screen label with the App Store listing
name. The iOS shell target's display name stays as PongWatch since
it isn't user-facing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Refine NSLocalNetworkUsageDescription copy

The current text reads `"Pong uses the local network to find nearby Apple Watches to play against."` which is fine but uses the unbranded "Pong" name. Update to match the new app branding and explicitly call out the no-server posture (better trust signal at the iOS consent prompt).

**Files:**
- Modify: `PongWatch/PongWatch.xcodeproj/project.pbxproj` — two `INFOPLIST_KEY_NSLocalNetworkUsageDescription` lines (Debug + Release for watch app target)

- [ ] **Step 1: Replace both occurrences**

Use Edit tool with `replace_all: true`:
- Old: `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Pong uses the local network to find nearby Apple Watches to play against.";`
- New: `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Pong Pal Showdown finds nearby Apple Watches over Wi-Fi to start a multiplayer match. No data leaves your local network.";`

- [ ] **Step 2: Build to verify**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "generic/platform=watchOS Simulator" -derivedDataPath ./build build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add PongWatch/PongWatch.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
chore: refine local-network usage description for App Store

Updates the user-facing string Apple shows when granting local
network access. Adds the branded app name and the explicit
"no data leaves your local network" reassurance.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Smoke-test on watchOS 11.5 simulator

Verify nothing broke when we lowered the deployment target. We don't have a watchOS 10 runtime installed, but watchOS 11.5 is older than the current 26.4 and uses APIs strictly within our new floor. The compiler in Task 1 already enforces deployment-target API availability — this task verifies *runtime behavior* on a non-current OS.

**Files:** none (this is a manual verification task)

- [ ] **Step 1: Boot the watchOS 11.5 sim**

Run:
```bash
xcrun simctl list devices | grep "watchOS 11.5" -A 5
```

Pick any 49mm Ultra entry; copy its UDID (column inside parentheses). If it's `(Shutdown)`, boot it:
```bash
xcrun simctl boot <UDID>
```

- [ ] **Step 2: Build for that sim, install, and launch**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && \
xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "platform=watchOS Simulator,id=<UDID>" -derivedDataPath ./build build 2>&1 | tail -3
```

If BUILD SUCCEEDED:
```bash
xcrun simctl install <UDID> "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/build/Build/Products/Debug-watchsimulator/PongWatch Watch App.app" && \
xcrun simctl launch <UDID> com.johnadkerson.PongWatch.watchkitapp && \
open -a Simulator
```

- [ ] **Step 3: Test plan (single-player path)**

Manually verify on the watchOS 11.5 sim:

1. Start screen renders with "Single Player" / "Multiplayer" buttons
2. Tap Single Player → game starts with countdown 3-2-1
3. Move paddle with arrow keys (sim crown), bounce ball off paddle a few times
4. Intentionally miss the ball → game over screen with score and "Restart"
5. Tap Restart → fresh game

Any crash or visible regression: investigate. Most likely fixes are `if #available(watchOS X, *) { … }` guards around any watchOS 12+ API found.

- [ ] **Step 4: Test plan (multiplayer — needs a second sim)**

Boot a second watchOS sim (any version ≥ 11.5 will do). Install the same build:
```bash
xcrun simctl install <UDID2> "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/build/Build/Products/Debug-watchsimulator/PongWatch Watch App.app" && \
xcrun simctl launch <UDID2> com.johnadkerson.PongWatch.watchkitapp
```

Then walk the multiplayer flow:
1. Both sims: tap Multiplayer → see Nearby Players list, each one finds the other
2. One sim: tap the other peer → that sim shows "Waiting for opponent" view
3. Other sim: tap Accept → first sim shows "Play to" picker
4. Pick "First to 3" → countdown starts on both → match plays
5. Score until someone wins → match-over screen with correct winner
6. Tap Rematch → match restarts

Any failure: capture sim logs and investigate.

- [ ] **Step 5: Commit (placeholder commit if no fixes needed)**

If everything passed without code changes, no commit is needed for this task — it's purely verification. If you had to add `#available()` guards or other small fixes, commit them with:

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add -A && git commit -m "$(cat <<'EOF'
chore: watchOS 10 compatibility fixes from smoke test

<list specific fixes here>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Strip `[MP]` debug NSLog instrumentation

There are 6 `NSLog("[MP] …")` lines committed during the multiplayer bug hunts. Production builds shouldn't emit per-state-change logs.

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift` — lines 156, 175, 186, 206
- Modify: `PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift` — lines 69, 295

- [ ] **Step 1: Remove the MultiplayerService logs**

Use Edit tool four times on `MultiplayerService.swift`. For each, the old string is the NSLog line plus enough surrounding context to be unique. The new string is just the surrounding context (NSLog line removed, any leading whitespace gone).

For example, line 156 (around `handleOutgoingState`):
- Old:
```
        connection: NWConnection
    ) {
        NSLog("[MP] handleOutgoingState(\(state))")
        switch state {
```
- New:
```
        connection: NWConnection
    ) {
        switch state {
```

Repeat the same pattern for the other three lines (175 — `handleIncomingConnection`, 186 — `respondToInvite`, 206 — `handleIncomingState`).

- [ ] **Step 2: Remove the MultiplayerGameState logs**

Use Edit tool twice on `MultiplayerGameState.swift`:

Line 69 (in `handleServiceStateChange`):
- Old:
```
        let priorRole = self.role
        let newRole = service.role
        NSLog("[MP] handleServiceStateChange connState=\(service.connectionState) priorRole=\(String(describing: priorRole)) newRole=\(String(describing: newRole)) matchPhase=\(matchPhase)")
        switch service.connectionState {
```
- New:
```
        let priorRole = self.role
        let newRole = service.role
        switch service.connectionState {
```

Line 295 (in `tick(dt:)` watchdog):
- Old:
```
               Date().timeIntervalSince(last) > peerSilenceTimeout,
               let myRole = service.role {
                NSLog("[MP] WATCHDOG FIRING matchPhase=\(matchPhase) since=\(Date().timeIntervalSince(last))s role=\(myRole)")
                matchPhase = .matchOver(winner: myRole)
```
- New:
```
               Date().timeIntervalSince(last) > peerSilenceTimeout,
               let myRole = service.role {
                matchPhase = .matchOver(winner: myRole)
```

- [ ] **Step 3: Verify all `[MP]` logs are gone**

Run:
```bash
grep -rn '\[MP\]' "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/PongWatch Watch App/" 2>/dev/null
```

Expected: **no output**. If anything remains, repeat Step 1 or Step 2 for the missed ones.

- [ ] **Step 4: Build and verify nothing else broke**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "generic/platform=watchOS Simulator" -derivedDataPath ./build build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerService.swift" "PongWatch/PongWatch Watch App/Multiplayer/MultiplayerGameState.swift" && git commit -m "$(cat <<'EOF'
chore(mp): strip [MP] debug NSLogs before App Store submission

Removes the per-state-change instrumentation added during the
pairing/match-end bug hunts. Production builds don't need them
and they would clutter the device console for end users.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update stale unit tests for the new state machine

After the `.configuringMatch` / `.waitingForOpponentAccept` / `.clientReady` / `startMatch` refactor, several tests still drive into `.playing` via the old direct `.connected` → `.playing` path. Update each.

**Files:**
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift`

The pattern: after `simulateConnected(as: .host)`, insert a synchronous host-side `state.startMatch(winningScore: 5)` call (with a brief sleep). After `simulateConnected(as: .client)`, insert a `fake.simulateIncoming(.startMatch(winningScore: 5))` call (with a brief sleep).

- [ ] **Step 1: Update `test_onConnectAsHostTransitionsToPlaying` → expect `.waitingForOpponentAccept`**

Find:
```swift
    func test_onConnectAsHostTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .host)
        XCTAssertEqual(state.matchPhase, .playing)
    }
```

Replace with:
```swift
    func test_onConnectAsHostTransitionsToWaitingForOpponentAccept() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .host)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
    }
```

- [ ] **Step 2: Update `test_onConnectAsClientTransitionsToPlaying` → expect `.configuringMatch` and `.clientReady` sent**

Find:
```swift
    func test_onConnectAsClientTransitionsToPlaying() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .client)
        XCTAssertEqual(state.matchPhase, .playing)
    }
```

Replace with:
```swift
    func test_onConnectAsClientTransitionsToConfiguringMatchAndSendsClientReady() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.role, .client)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        let clientReadySends = fake.sentMessages.filter {
            if case .clientReady = $0.message { return true } else { return false }
        }
        XCTAssertEqual(clientReadySends.count, 1)
    }
```

- [ ] **Step 3: Update `test_wristDownUnderGracePeriodDoesNotForfeit` to drive into `.playing`**

The test currently does `simulateConnected(as: .host)` and expects `.playing` after 100ms. Now we need to call `state.startMatch(...)` to transition.

Find:
```swift
    func test_wristDownUnderGracePeriodDoesNotForfeit() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)  // let matchPhase settle to .playing
        state.onScenePhaseChanged(to: .inactive)
```

Replace with:
```swift
    func test_wristDownUnderGracePeriodDoesNotForfeit() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)  // let matchPhase settle to .waitingForOpponentAccept
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.onScenePhaseChanged(to: .inactive)
```

Note: `startMatch` requires being in `.configuringMatch`, but after `simulateConnected(as: .host)` the state is `.waitingForOpponentAccept`. We need to also send a fake `clientReady` to advance. Update the helper insertion to:

```swift
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Drive through the new pairing handshake: client-ready, then host starts match.
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.onScenePhaseChanged(to: .inactive)
```

- [ ] **Step 4: Apply the same drive-into-playing helper to `test_wristDownOverGracePeriodForfeits` and `test_wristDownSendsPausedMessage`**

Both tests have the same pattern as Step 3. Insert the same three lines (`simulateIncoming(.clientReady)` + sleep + `startMatch` + sleep) immediately after the existing `simulateConnected` + sleep.

- [ ] **Step 5: Update `test_disconnectMidMatchEndsWithLocalWin`**

Same pattern: drive into `.playing` before calling `simulateDisconnect()`.

Find:
```swift
    func test_disconnectMidMatchEndsWithLocalWin() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateDisconnect()
```

Replace with:
```swift
    func test_disconnectMidMatchEndsWithLocalWin() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 5) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateDisconnect()
```

- [ ] **Step 6: Update `test_clientTransitionsToMatchOverWhenSnapshotShowsWinningScore`**

For client tests, drive into `.playing` via `simulateIncoming(.startMatch(...))`.

Find:
```swift
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let snap = GameSnapshot(
```

Replace with:
```swift
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.startMatch(winningScore: 5))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let snap = GameSnapshot(
```

Also, in this test the snapshot uses `GameConstants.multiplayerWinningScore` which equals 5 by default — but now the threshold is the runtime `winningScore`. Since we're injecting `winningScore: 5`, the existing assertion still works. Verify the snapshot's `hostScore` equals 5 (matches `multiplayerWinningScore`). No change needed beyond inserting the two lines.

- [ ] **Step 7: Update `test_peerSilenceTimeoutEndsMatchForLocalRole`**

Same pattern as Step 6 — insert `simulateIncoming(.startMatch(winningScore: 5))` + sleep after `simulateConnected(as: .client)`.

- [ ] **Step 8: Update `test_recentPeerActivityDoesNotTriggerSilenceTimeout`**

Same pattern as Step 7.

- [ ] **Step 9: Run all tests and verify they pass**

Run:
```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,id=91914947-67A1-4AFC-91FD-C242370CB9E6" -derivedDataPath ./build test 2>&1 | tail -40
```

Expected: `Test Suite 'MultiplayerGameStateTests' passed`. If any test fails, address inline before moving on.

- [ ] **Step 10: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift" && git commit -m "$(cat <<'EOF'
test(mp): update state-machine tests for configuring-match flow

After the .configuringMatch / .waitingForOpponentAccept / .clientReady
refactor, tests that drive into .playing must now go through the new
handshake (simulateIncoming(.clientReady) → startMatch on host;
simulateIncoming(.startMatch(...)) on client) instead of relying on
the old direct .connected → .playing transition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add new tests for the configuration flow

Cover the new transitions: `.clientReady` arriving on host, host's `startMatch` round-trip, client receiving `.startMatch`, both cancel paths, and disconnect during the new phases.

**Files:**
- Modify: `PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift` — add 7 tests

- [ ] **Step 1: Write the failing tests**

Insert these 7 test methods at the end of the test class, just before the closing `}` of `final class MultiplayerGameStateTests`:

```swift
    func test_hostReceivingClientReadyTransitionsToConfiguringMatch() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
    }

    func test_hostStartMatchSendsAndPlaysWithStoredWinningScore() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { state.startMatch(winningScore: 3) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        // Phase advanced to .playing
        XCTAssertEqual(state.matchPhase, .playing)
        // Stored target
        XCTAssertEqual(state.winningScore, 3)
        // Sent .startMatch with the same target
        let starts: [Int?] = fake.sentMessages.compactMap {
            if case .startMatch(let s) = $0.message { return s } else { return nil }
        }
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts[0], 3)
        // Inner game phase primed for play
        XCTAssertEqual(state.game.phase, .playing)
    }

    func test_clientReceivingStartMatchTransitionsToPlayingWithWinningScore() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        fake.simulateIncoming(.startMatch(winningScore: 7))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .playing)
        XCTAssertEqual(state.winningScore, 7)
    }

    func test_clientReceivingStartMatchWithNilWinningScoreEntersNoLimitMode() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.startMatch(winningScore: nil))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .playing)
        XCTAssertNil(state.winningScore)
    }

    func test_cancelMatchConfigurationFromConfiguringDisconnectsAndReturnsToPairing() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.simulateIncoming(.clientReady)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        await MainActor.run { state.cancelMatchConfiguration() }
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(fake.connectionState, .idle)
    }

    func test_cancelMatchConfigurationFromWaitingForOpponentAcceptDisconnectsAndReturnsToPairing() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .host)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .waitingForOpponentAccept)
        await MainActor.run { state.cancelMatchConfiguration() }
        XCTAssertEqual(state.matchPhase, .pairing)
        XCTAssertEqual(fake.connectionState, .idle)
    }

    func test_disconnectDuringConfiguringMatchReturnsToPairingNotMatchOver() async {
        let fake = FakeMultiplayerService()
        let state = MultiplayerGameState(service: fake)
        fake.simulateConnected(as: .client)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.matchPhase, .configuringMatch)
        fake.simulateDisconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Should NOT show "you win" — play hasn't started.
        XCTAssertEqual(state.matchPhase, .pairing)
    }
```

- [ ] **Step 2: Run the new tests**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,id=91914947-67A1-4AFC-91FD-C242370CB9E6" -derivedDataPath ./build test 2>&1 | grep -E "(Test Case.*passed|Test Case.*failed|error:)" | tail -30
```

Expected: all 7 new tests show `passed`. If any fail, the corresponding production code path has a bug — investigate and fix before proceeding (likely the bug is in the production code, not the test).

- [ ] **Step 3: Run the full test suite**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -destination "platform=watchOS Simulator,id=91914947-67A1-4AFC-91FD-C242370CB9E6" -derivedDataPath ./build test 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add "PongWatch/PongWatch Watch AppTests/MultiplayerGameStateTests.swift" && git commit -m "$(cat <<'EOF'
test(mp): add coverage for configuring-match flow

Adds 7 tests covering the new state machine: client-ready arrival on
host, startMatch send/store/play round-trip, client receiving
startMatch (both finite and nil winning scores), cancel from both
pre-match phases, and disconnect-during-configuring landing in
.pairing rather than .matchOver.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Bump build number

**Files:**
- Modify: `PongWatch/PongWatch.xcodeproj/project.pbxproj` — `CURRENT_PROJECT_VERSION = 1;` lines (multiple — update all that belong to the watch app target)

- [ ] **Step 1: Find the version lines**

Run:
```bash
grep -n "CURRENT_PROJECT_VERSION" "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/PongWatch.xcodeproj/project.pbxproj"
```

You'll see multiple lines, one per target × configuration. We want to bump only the watch app target's lines (Debug + Release). Find them by their proximity to `PRODUCT_BUNDLE_IDENTIFIER = com.johnadkerson.PongWatch.watchkitapp;` — that's the watch app target.

- [ ] **Step 2: Bump those lines from 1 to 2**

Use Edit tool with surrounding context to disambiguate. Each watch-app target line:
- Old: `CURRENT_PROJECT_VERSION = 1;` (with bundle id `.watchkitapp` nearby)
- New: `CURRENT_PROJECT_VERSION = 2;`

Leave the iOS shell target's `CURRENT_PROJECT_VERSION` and the test targets' versions at 1.

- [ ] **Step 3: Build to verify**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "generic/platform=watchOS Simulator" -derivedDataPath ./build build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add PongWatch/PongWatch.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
chore: bump build number to 2 for first TestFlight upload

MARKETING_VERSION stays at 1.0; CURRENT_PROJECT_VERSION moves to 2
on the watch app target so App Store Connect accepts the upload as
a new build (build numbers must monotonically increase per version).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1 PR

- [ ] Open a pull request from `postToAppleStore` (or whatever branch this work was on) → `main` titled "App Store submission prep — Phase 1: Technical polish."

PR description should mention: deployment target lowered, display name updated, network description refined, debug NSLogs stripped, tests updated for new state machine, build number bumped, smoke-tested on watchOS 11.5.

---

# PHASE 2 — App Store assets

## Task 9: Create `docs/` folder structure for GitHub Pages

**Files:**
- Create: `docs/` directory at the repo root (it already exists for the spec/plan files; we're adding HTML files alongside)

Note: `docs/superpowers/` will coexist with `docs/index.html` in the same folder. GitHub Pages serves the static HTML; the `superpowers/` subdirectory just sits there unused by the static site (which is fine — it's just markdown for our internal use).

- [ ] **Step 1: Verify docs/ exists**

```bash
ls -la "/Volumes/bingobango/code/appleWatchPongGame/docs/"
```

Expected: directory exists with `superpowers/` subfolder. We'll add `index.html`, `privacy.html`, `support.html` inside `docs/`.

No commit yet — proceed to Task 10.

---

## Task 10: Write `docs/index.html`

A minimal landing page that links to privacy and support — also serves as the App Store Connect "Marketing URL" if you want one (optional field).

**Files:**
- Create: `docs/index.html`

- [ ] **Step 1: Write the file**

Create `/Volumes/bingobango/code/appleWatchPongGame/docs/index.html` with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pong Pal Showdown</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 540px; margin: 4rem auto; padding: 0 1.5rem; color: #1a1a1a; background: #fafafa; line-height: 1.55; }
    h1 { font-size: 2rem; margin-bottom: 0.25rem; }
    .subtitle { color: #555; margin-top: 0; }
    .links { margin-top: 2.5rem; }
    .links a { display: inline-block; margin-right: 1.5rem; color: #0a6; text-decoration: none; border-bottom: 1px solid #0a6; }
    footer { margin-top: 4rem; color: #888; font-size: 0.85rem; }
  </style>
</head>
<body>
  <h1>Pong Pal Showdown</h1>
  <p class="subtitle">Play Pong head-to-head on two Apple Watches.</p>
  <p>Pong Pal Showdown is a watchOS game that lets you play classic Pong against another Apple Watch over local Wi-Fi. No ads, no in-app purchases, no data collection.</p>
  <p>Available on the Apple Watch App Store for $0.99.</p>
  <div class="links">
    <a href="privacy.html">Privacy Policy</a>
    <a href="support.html">Support &amp; FAQ</a>
  </div>
  <footer>
    &copy; 2026 John Adkerson. All rights reserved.
  </footer>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add docs/index.html && git commit -m "$(cat <<'EOF'
docs(site): add GitHub Pages landing page

Lightweight landing for pong-pal-showdown marketing URL. Links to
privacy and support pages.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Write `docs/privacy.html`

Required by App Store Connect.

**Files:**
- Create: `docs/privacy.html`

- [ ] **Step 1: Write the file**

Create `/Volumes/bingobango/code/appleWatchPongGame/docs/privacy.html` with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Privacy Policy — Pong Pal Showdown</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 720px; margin: 4rem auto; padding: 0 1.5rem; color: #1a1a1a; background: #fafafa; line-height: 1.6; }
    h1 { font-size: 1.75rem; }
    h2 { font-size: 1.15rem; margin-top: 2rem; }
    a { color: #0a6; }
    .meta { color: #666; font-size: 0.9rem; margin-bottom: 2rem; }
  </style>
</head>
<body>
  <p><a href="index.html">&larr; Pong Pal Showdown</a></p>
  <h1>Privacy Policy</h1>
  <p class="meta">Effective 2026-04-27</p>

  <p><strong>Pong Pal Showdown does not collect, store, or transmit any personal information.</strong> The short version: there is no server. There are no analytics SDKs. There is no tracking. The app runs entirely on your Apple Watch.</p>

  <h2>What the app does on your device</h2>
  <p>Pong Pal Showdown stores your single-player high score on your Apple Watch using <code>UserDefaults</code> (the standard local-storage system on iOS and watchOS). This data never leaves your watch.</p>

  <h2>Local Wi-Fi multiplayer</h2>
  <p>The multiplayer feature uses Bonjour (also known as mDNS) to discover other Apple Watches running Pong Pal Showdown on the same local Wi-Fi network. When you start a match, the two watches exchange paddle positions and game state directly with each other over the local network. <strong>This data does not travel over the internet, is not collected by us, and is not stored anywhere after the match ends.</strong></p>
  <p>The first time you use multiplayer, watchOS will ask for permission to access the local network. You can revoke this permission at any time in your Apple Watch's Settings &gt; Privacy &amp; Security &gt; Local Network.</p>

  <h2>Third-party SDKs</h2>
  <p>None. Pong Pal Showdown has no third-party analytics, advertising, crash-reporting, or tracking SDKs.</p>

  <h2>Children's privacy</h2>
  <p>Pong Pal Showdown is rated 4+ and contains no content directed at or restricted from children. Because we collect no information of any kind, the app complies with the U.S. Children's Online Privacy Protection Act (COPPA) by virtue of having no covered data collection at all.</p>

  <h2>Changes to this policy</h2>
  <p>If this policy changes — for example, if a future version adds an opt-in feature that involves data collection — we will update this page and note the effective date. Material changes will also be reflected in the App Store listing's privacy nutrition label.</p>

  <h2>Contact</h2>
  <p>Privacy questions: <a href="mailto:john.adkerson.software@gmail.com">john.adkerson.software@gmail.com</a></p>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add docs/privacy.html && git commit -m "$(cat <<'EOF'
docs(site): add privacy policy

Required for App Store Connect submission. Reflects the actual
data posture: zero collection, local Bonjour multiplayer, no SDKs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Write `docs/support.html`

Required by App Store Connect.

**Files:**
- Create: `docs/support.html`

- [ ] **Step 1: Write the file**

Create `/Volumes/bingobango/code/appleWatchPongGame/docs/support.html` with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Support — Pong Pal Showdown</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 720px; margin: 4rem auto; padding: 0 1.5rem; color: #1a1a1a; background: #fafafa; line-height: 1.6; }
    h1 { font-size: 1.75rem; }
    h2 { font-size: 1.15rem; margin-top: 2rem; }
    a { color: #0a6; }
  </style>
</head>
<body>
  <p><a href="index.html">&larr; Pong Pal Showdown</a></p>
  <h1>Support &amp; FAQ</h1>

  <p>Pong Pal Showdown is a small, single-developer hobby project. The fastest way to reach me is email — I read every message, but please be patient on response time.</p>

  <h2>How do I play multiplayer?</h2>
  <ol>
    <li>Make sure both Apple Watches are on the same Wi-Fi network and both running watchOS 10 or later.</li>
    <li>On both watches, open Pong Pal Showdown and tap <strong>Multiplayer</strong>.</li>
    <li>Wait until each watch sees the other in the "Nearby Players" list.</li>
    <li>One player taps the other player's name to send an invite. The other player taps Accept.</li>
    <li>The inviting player picks a target score: First to 3, First to 5, or No limit.</li>
    <li>The match begins after a 3-2-1 countdown.</li>
  </ol>

  <h2>My friend's watch doesn't appear in the list. What's wrong?</h2>
  <ul>
    <li>Confirm both watches are on the <strong>same</strong> Wi-Fi network — some routers create separate networks for 2.4 GHz and 5 GHz, or for "guest" networks.</li>
    <li>The first time you use multiplayer, watchOS asks permission to access the local network. If you tapped Don't Allow, multiplayer won't work. Re-enable it in Settings &gt; Privacy &amp; Security &gt; Local Network.</li>
    <li>Both watches must be running watchOS 10 or later.</li>
    <li>Public Wi-Fi networks (coffee shops, airports) often block peer-to-peer connections. Try a home or trusted Wi-Fi network.</li>
  </ul>

  <h2>Is there an iPhone version?</h2>
  <p>No. Pong Pal Showdown is a standalone Apple Watch app — there is no iPhone companion required, and no iPhone version available.</p>

  <h2>The Digital Crown isn't moving my paddle.</h2>
  <ul>
    <li>Make sure the watch face is the active focus (tap the screen once to ensure focus is on the game, not the system).</li>
    <li>If you're playing in the simulator on Mac, click the simulator window first, then use the left/right arrow keys.</li>
  </ul>

  <h2>How do I report a bug?</h2>
  <p>Email me with:</p>
  <ul>
    <li>What watch model you have (e.g., Series 9 / Ultra 2)</li>
    <li>What watchOS version (Settings &gt; General &gt; About)</li>
    <li>What you were doing when it happened</li>
    <li>A screen recording if you can capture one</li>
  </ul>

  <h2>Contact</h2>
  <p><a href="mailto:john.adkerson.software@gmail.com">john.adkerson.software@gmail.com</a></p>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add docs/support.html && git commit -m "$(cat <<'EOF'
docs(site): add support / FAQ page

Required for App Store Connect submission. Covers multiplayer
setup, common router/Wi-Fi gotchas, no-iPhone-app FAQ, crown
input troubleshooting, and bug-report contact.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Enable GitHub Pages and verify URLs

**Files:** none — this is GitHub web UI work.

- [ ] **Step 1: Push the docs/ commits**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git push origin postToAppleStore
```

Then merge the Phase 2 PR (or push to main if reviewed) — GitHub Pages sources from `main` branch by default.

- [ ] **Step 2: Enable GitHub Pages in repo settings**

In a browser, go to: `https://github.com/AdkersonJohn/appleWatchPongGame/settings/pages`

- Under **Source**, choose `Deploy from a branch`
- Branch: `main`
- Folder: `/docs`
- Click Save
- Wait ~1 minute for first deployment

- [ ] **Step 3: Verify URLs are live**

Check in browser:
- `https://adkersonjohn.github.io/appleWatchPongGame/` — landing page
- `https://adkersonjohn.github.io/appleWatchPongGame/privacy.html` — privacy policy
- `https://adkersonjohn.github.io/appleWatchPongGame/support.html` — support page

If 404s appear, double-check the GitHub Pages source branch/folder, wait a bit more, or check for case-sensitivity in your username (URL is generally lowercased).

- [ ] **Step 4: Save the URLs**

Copy the privacy and support URLs to your notes — you'll paste them into App Store Connect in Phase 4.

---

## Task 14: Capture 5 screenshots from 49mm Ultra simulator

**Files:**
- Create: `docs/screenshots/01-gameplay.png`
- Create: `docs/screenshots/02-pairing.png`
- Create: `docs/screenshots/03-score-picker.png`
- Create: `docs/screenshots/04-match-over.png`
- Create: `docs/screenshots/05-start-menu.png`

The capture command for Apple Watch sims is `xcrun simctl io <UDID> screenshot <path.png>`.

- [ ] **Step 1: Create the directory**

```bash
mkdir -p "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots"
```

- [ ] **Step 2: Boot the 49mm Ultra 3 sim and a second sim, install latest build, walk to each scene**

```bash
xcrun simctl boot 91914947-67A1-4AFC-91FD-C242370CB9E6  # Ultra 3
xcrun simctl boot 28E8A73F-FF74-4D77-9E4E-CFCA22C01633  # Series 11 (for multiplayer scenes)
open -a Simulator
```

Build & install latest:
```bash
cd "/Volumes/bingobango/code/appleWatchPongGame/PongWatch" && \
xcodebuild -project PongWatch.xcodeproj -scheme "PongWatch Watch App" -configuration Debug -destination "platform=watchOS Simulator,id=91914947-67A1-4AFC-91FD-C242370CB9E6" -derivedDataPath ./build build && \
xcrun simctl install 91914947-67A1-4AFC-91FD-C242370CB9E6 "./build/Build/Products/Debug-watchsimulator/PongWatch Watch App.app" && \
xcrun simctl install 28E8A73F-FF74-4D77-9E4E-CFCA22C01633 "./build/Build/Products/Debug-watchsimulator/PongWatch Watch App.app" && \
xcrun simctl launch 91914947-67A1-4AFC-91FD-C242370CB9E6 com.johnadkerson.PongWatch.watchkitapp && \
xcrun simctl launch 28E8A73F-FF74-4D77-9E4E-CFCA22C01633 com.johnadkerson.PongWatch.watchkitapp
```

- [ ] **Step 3: Capture screenshot 5 first (Start menu — easiest, the launch screen)**

```bash
xcrun simctl io 91914947-67A1-4AFC-91FD-C242370CB9E6 screenshot "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/05-start-menu.png"
```

- [ ] **Step 4: Capture screenshot 1 (mid-rally gameplay)**

On the Ultra 3 sim, tap Single Player, wait for countdown, play until score is interesting (e.g., 2). Capture during a rally:

```bash
xcrun simctl io 91914947-67A1-4AFC-91FD-C242370CB9E6 screenshot "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/01-gameplay.png"
```

You may need a few attempts — game state changes fast. Best timing: ball is mid-flight, both paddles visible, score is non-zero.

- [ ] **Step 5: Capture screenshot 2 (NearbyPlayersView)**

On both sims, return to start screen, tap Multiplayer. Wait until each sees the other in the peer list. On the Ultra 3:

```bash
xcrun simctl io 91914947-67A1-4AFC-91FD-C242370CB9E6 screenshot "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/02-pairing.png"
```

- [ ] **Step 6: Capture screenshot 3 (MatchConfigView score picker)**

On Ultra 3, tap Series 11 in peer list. On Series 11, tap Accept. Ultra 3 should now show "Play to" with three buttons. Capture:

```bash
xcrun simctl io 91914947-67A1-4AFC-91FD-C242370CB9E6 screenshot "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/03-score-picker.png"
```

- [ ] **Step 7: Capture screenshot 4 (Match-over)**

Tap First to 3 to start the match. Play (you can intentionally let one side win for speed) until match-over screen appears. Capture:

```bash
xcrun simctl io 91914947-67A1-4AFC-91FD-C242370CB9E6 screenshot "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/04-match-over.png"
```

- [ ] **Step 8: Verify all 5 captures exist and look right**

```bash
ls -la "/Volumes/bingobango/code/appleWatchPongGame/docs/screenshots/"
```

Open each PNG in Preview to confirm content is correct. Re-capture any that didn't catch the right moment.

- [ ] **Step 9: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add docs/screenshots/ && git commit -m "$(cat <<'EOF'
docs(assets): add 5 App Store screenshots from 49mm Ultra sim

Captures for App Store Connect listing: gameplay, pairing,
score picker, match-over, start menu. Apple auto-fits these
for smaller display sizes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Draft App Store marketing copy

Save the listing copy to a file in the repo for reference and copy-paste into App Store Connect later.

**Files:**
- Create: `docs/marketing-copy-draft.md`

- [ ] **Step 1: Write the file**

Create `/Volumes/bingobango/code/appleWatchPongGame/docs/marketing-copy-draft.md` with:

````markdown
# Pong Pal Showdown — App Store Listing Copy

This file is the source of truth for the App Store Connect listing. Update here first, paste into App Store Connect.

## Name (max 30 chars)

`Pong Pal Showdown` (17 chars)

## Subtitle (max 30 chars)

`Play Pong head-to-head` (22 chars)

## Promotional text (max 170 chars, editable post-launch)

```
The classic on your wrist — now with real-time multiplayer between two Apple Watches. Spin the crown, save the ball, beat your friend. No ads, no IAP.
```

(149 chars)

## Description (max 4000 chars)

```
Classic Pong, rebuilt for Apple Watch — and now with the killer feature it always wanted: real-time wireless multiplayer with a friend across the room.

HOW MULTIPLAYER WORKS

Both players open the game on their Apple Watch and tap Multiplayer. The watches find each other automatically over your local Wi-Fi. One player invites, the other accepts, and the host picks the target score: First to 3, First to 5, or no limit. Then the match begins — paddle vs. paddle, in real time, on two screens.

FEATURES

• Real-time wireless multiplayer between two Apple Watches over local Wi-Fi
• Single-player vs. AI with progressive difficulty
• Digital Crown precision paddle control
• Persistent local high-score tracking
• Quick 60-second matches — perfect for a coffee break
• No ads. No in-app purchases. No data collection.

HOW IT FEELS

Spin the crown to slide your paddle. Hit the ball cleanly to send it screaming back. Miss, and your opponent scores. The first player to the target score wins the match — or play with no limit and see who folds first.

REQUIREMENTS

• Apple Watch running watchOS 10.0 or later
• For multiplayer: two Apple Watches on the same Wi-Fi network
• No iPhone required — Pong Pal Showdown is a standalone watchOS app

A small, single-developer game. Bring a friend.
```

## Keywords (max 100 chars, comma-separated, no spaces between)

```
pong,multiplayer,paddle,classic,retro,arcade,two player,casual,friends,head-to-head
```

(83 chars — 17 chars headroom for tweaks)

## Support URL

`https://adkersonjohn.github.io/appleWatchPongGame/support.html`

## Privacy Policy URL

`https://adkersonjohn.github.io/appleWatchPongGame/privacy.html`

## Marketing URL (optional)

`https://adkersonjohn.github.io/appleWatchPongGame/`

## Category

- Primary: Games / Casual
- Secondary: Games / Arcade

## Age Rating

4+ (auto-assigned by Apple's questionnaire — no objectionable content)

## Pricing

Tier 1 ($0.99 USD), all countries available, no scheduled price changes.

## App Privacy questionnaire (App Store Connect "App Privacy" section)

- Data Types Collected: **None**
- Data Used to Track You: **No**
- Data Linked to You: **No**
- Data Not Linked to You: **No**

Resulting label: "The developer does not collect any data from this app."

## Reviewer notes (App Store Connect "App Review Information")

```
Multiplayer requires two Apple Watches on the same Wi-Fi network. Single-player works on one watch — tap "Single Player" on the start screen to test gameplay solo.
```

## What's New (only for v1.x updates, not 1.0)

N/A for first release.
````

- [ ] **Step 2: Commit**

```bash
cd "/Volumes/bingobango/code/appleWatchPongGame" && git add docs/marketing-copy-draft.md && git commit -m "$(cat <<'EOF'
docs(assets): draft App Store Connect listing copy

Source-of-truth for the listing fields: name, subtitle,
promo text, description, keywords, URLs, category, pricing,
privacy answers, reviewer notes. Paste into App Store Connect
when filling out the listing in Phase 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 PR

- [ ] Open a pull request titled "App Store submission prep — Phase 2: Assets" with the docs/ files (HTML pages + screenshots + marketing copy draft).

Once merged, the GitHub Pages site goes live with the privacy and support URLs that you'll need in Phase 4.

---

# PHASE 3 — TestFlight beta

These tasks are operational — happen mostly in App Store Connect's web UI and on real devices. Code changes only happen if a beta tester surfaces a bug.

## Task 16: Create App Store Connect record

**Files:** none (App Store Connect web UI work).

- [ ] **Step 1: Sign in to App Store Connect**

Go to <https://appstoreconnect.apple.com>. Sign in with the Apple ID associated with team `373QNLTN7Q`.

- [ ] **Step 2: Create new app record**

Apps → My Apps → "+" button (top-left) → New App. Fill out:

- **Platforms:** check `watchOS` only
- **Name:** `Pong Pal Showdown`
- **Primary language:** English (U.S.)
- **Bundle ID:** select from dropdown — `com.johnadkerson.PongWatch.watchkitapp` (must already be registered as an App ID in your developer account; if it's not in the dropdown, register it via the Certificates, Identifiers & Profiles portal first)
- **SKU:** `pong-pal-showdown-1` (any unique-to-account identifier; this never appears to users)
- **User access:** Full Access

Click Create.

- [ ] **Step 3: Confirm the record exists**

You should now see "Pong Pal Showdown" in My Apps with a 1.0 Prepare for Submission status. Don't fill out any listing fields yet — those happen in Phase 4.

---

## Task 17: Archive the build and upload to App Store Connect

**Files:** none (Xcode UI work).

- [ ] **Step 1: Open the project in Xcode**

```bash
open "/Volumes/bingobango/code/appleWatchPongGame/PongWatch/PongWatch.xcodeproj"
```

- [ ] **Step 2: Select the archive destination**

In Xcode's scheme/destination dropdown (top toolbar), pick "Any watchOS Device (arm64)" — this is the generic archive destination, distinct from the simulator destinations.

- [ ] **Step 3: Archive**

Product menu → Archive. Wait for build (~30 seconds to a few minutes).

If it fails:
- "Could not find an iOS provisioning profile" → make sure team `373QNLTN7Q` is selected in target signing & capabilities
- "Cannot archive watch app target" → ensure scheme is set to release-config build for the watch app

- [ ] **Step 4: Distribute App via App Store Connect**

When archive completes, the Organizer window opens. Select your archive → click `Distribute App` → choose `App Store Connect` → choose `Upload` → click through default options (Automatic signing, Include bitcode if asked, Upload symbols for crash reporting) → click `Upload`.

Wait for upload to complete (~2-5 minutes).

- [ ] **Step 5: Wait for build processing**

Apple needs ~15–30 minutes to process the upload. Refresh App Store Connect → My Apps → Pong Pal Showdown → TestFlight tab → iOS Builds (which on watchOS apps shows watch builds). The build appears with status "Processing" → eventually becomes "Ready to Submit" or similar.

If it lands in "Missing Compliance" status, click into the build and answer the export-compliance question:
- "Does your app use encryption?" → **Yes** (HTTPS / Network framework counts as encryption)
- "Does it qualify for any of the exemptions?" → **Yes** (uses standard encryption, App Store standard exemption applies)
- This puts the build into a state ready for TestFlight distribution.

---

## Task 18: Submit for Beta App Review

External TestFlight testers (anyone outside your developer team, including Friends & Family invites) require Apple's Beta App Review approval before they can install. Internal testers don't.

**Files:** none.

- [ ] **Step 1: In App Store Connect → TestFlight tab → Test Information**

Fill out the Test Information section (this stays the same across builds):

- **What to Test:**
  ```
  Multiplayer Pong on two Apple Watches over local Wi-Fi.

  Things to try:
  • Single-player on one watch
  • Pair two watches running watchOS 10 or later — both must be on the same Wi-Fi
  • Try First to 3, First to 5, and No Limit modes
  • Try wrist-down mid-match — match should pause and resume; if you stay wrist-down past the grace timeout, the other player wins
  • Try the Back / Cancel buttons during pairing and score selection
  ```
- **App Description:** copy from `docs/marketing-copy-draft.md` description section, trimmed if needed
- **Feedback Email:** `john.adkerson.software@gmail.com`
- **Marketing URL** (optional): `https://adkersonjohn.github.io/appleWatchPongGame/`
- **Privacy Policy URL:** `https://adkersonjohn.github.io/appleWatchPongGame/privacy.html`

Save.

- [ ] **Step 2: Submit the build for Beta App Review**

Click into the Build 2 row → click `Submit For Review` (might be labeled `Start External Testing` depending on UI version).

Apple's reviewer questions:
- **Demo account / sign-in?** No
- **Reviewer notes:** Use the same text as in `docs/marketing-copy-draft.md` "Reviewer notes" section
- Submit.

Approval typically arrives in **24 hours**. You'll get an email when it's done.

- [ ] **Step 3: Set status to "Ready"**

Once approved, the build flips to "Ready to Test" status. External testers can now be invited.

---

## Task 19: Set up beta tester groups

**Files:** none.

- [ ] **Step 1: Create the Internal group**

App Store Connect → TestFlight tab → "Internal Testing" group is automatic. Add yourself + any owned Apple IDs as Internal Testers. Internal testers get the build immediately, no review.

- [ ] **Step 2: Create "Friends & Family" external group**

TestFlight tab → External Testing section → click "+" → Add New Group. Name: `Friends & Family`. Set status to: associated with Build 2.

Don't invite anyone yet — wait for Step 4.

- [ ] **Step 3: Create "Public" external group with public link**

External Testing → "+" → Add New Group. Name: `Public`. Toggle "Enable public link" → set max testers to **100** (manageable feedback volume). Don't share the link yet.

- [ ] **Step 4: Once Beta App Review is approved (Task 18 Step 2), invite Friends & Family**

Inside the Friends & Family group, click `Add Testers` → enter 5–10 email addresses of people who have Apple Watches. Apple sends them invitation emails with TestFlight install instructions.

For each invitee, also send them a casual personal message (text/iMessage) saying:
- You're testing a small Apple Watch game
- Look for an email from Apple/TestFlight
- Once installed, look for "Pong Pal Showdown" on their watch and play around
- Send feedback via TestFlight's screenshot+text feature (open TestFlight on the iPhone → Pong Pal Showdown → "Send Beta Feedback")
- It's a hobby project, no formal QA expected — just play it casually

---

## Task 20: Friends & Family beta — Week 1

**Files:** none. Code commits happen if a bug surfaces and needs fixing.

- [ ] **Step 1: Monitor TestFlight feedback**

Daily, App Store Connect → TestFlight tab → Feedback. Read all new feedback items. Categorize:

- **Crash** — investigate immediately, fix, upload Build 3+
- **Match doesn't start / can't pair** — same priority, fix and re-upload
- **Cosmetic / minor / nice-to-have** — log to a `docs/known-issues.md` for v1.1, don't block

- [ ] **Step 2: If a fix is needed, the dev cycle is**

```bash
git checkout main
git checkout -b fix/<bug-name>
# make code change(s) on the branch
# run tests, verify
git push origin fix/<bug-name>
# open PR, merge to main
git checkout main
git pull
```

Then bump build number (`CURRENT_PROJECT_VERSION = 3`, then 4, etc.), commit, archive in Xcode, upload to App Store Connect. Beta testers get the new build automatically (TestFlight pushes updates).

Beta App Review is generally **not required again** for incremental updates inside the same major version, unless Apple flags something specific.

- [ ] **Step 3: Run for at least 5 calendar days, even if no bugs**

Passive playtime exposes session-length and intermittent bugs. Don't compress this phase.

- [ ] **Step 4: Decide whether to open the public link**

After 5+ days of friends/family beta:
- If 0 reproducible blocker bugs → proceed to Task 21
- If blocker bugs are still being found → stay in friends/family for another few days, fix, re-upload

---

## Task 21: Public link beta — Weeks 2-3

**Files:** none.

- [ ] **Step 1: Promote the latest build to the Public group**

App Store Connect → TestFlight → Public group → assign latest approved build.

- [ ] **Step 2: Share the public link**

Locations to post:
- **r/AppleWatch:** short post: "I made a multiplayer Pong game for Apple Watch. TestFlight beta open — looking for feedback before launch. [link]" — include 1-2 screenshots
- **GitHub README:** add a "Beta" badge at the top of the repo's README pointing to the TestFlight public link
- **Personal social** (Twitter/Bluesky/Mastodon if you have one): one-line announcement with screenshot

- [ ] **Step 3: Monitor feedback daily**

Same triage rules as Task 20 Step 1. Bug fixes follow the same dev cycle as Task 20 Step 2.

- [ ] **Step 4: Run for 2 calendar weeks unless exit criteria met sooner**

**Exit criteria — all must be true to advance to Phase 4:**
- Zero reproducible crashes in last 5 days
- Zero blocker bugs in last 5 days (multiplayer fails to pair, match doesn't start, paddle doesn't move, app freezes mid-match, etc.)
- ≥ 3 different testers have completed at least one full multiplayer match end-to-end
- ≥ 1 tester pair on a network the developer doesn't control (real Wi-Fi diversity)
- All open feedback items either fixed, deferred to v1.1 with a note, or judged not-a-bug

If a blocker is found late: hold launch, fix, return to friends/family group for one more verification week, then re-promote to public.

---

# PHASE 4 — App Store submission

## Task 22: Finalize App Store Connect listing

**Files:** none — copy-paste from `docs/marketing-copy-draft.md` into App Store Connect web UI.

- [ ] **Step 1: Go to App Store Connect → My Apps → Pong Pal Showdown → "1.0 Prepare for Submission"**

- [ ] **Step 2: Fill out App Information section**

- **Bundle ID:** already set
- **Primary Category:** Games
- **Secondary Category:** Games (subcategory selection happens at submission level)
- **Content Rights:** "Does your app contain, show, or access third-party content?" → **No**
- **Age Rating:** Click Edit → walk through the questionnaire, answer "None" / "No" / "Never" to all categories (no violence, no sexual content, no language, etc.). Final rating: **4+**

- [ ] **Step 3: Fill out Pricing & Availability**

- **Price Schedule:** select **Tier 1 ($0.99 USD)**
- **Availability:** Available in all territories (default)
- **App Distribution Methods:** App Store only

- [ ] **Step 4: Fill out App Privacy**

App Privacy → Get Started → answer all data-collection questions:
- "Do you or your third-party partners collect data from this app?" → **No**
- This bypasses the rest; final label = "The developer does not collect any data from this app."

- [ ] **Step 5: Fill out Version 1.0 listing fields**

In the 1.0 record:

- **Promotional Text:** paste from `docs/marketing-copy-draft.md` "Promotional text" section
- **Description:** paste from `docs/marketing-copy-draft.md` "Description" section
- **Keywords:** paste from `docs/marketing-copy-draft.md` "Keywords" section
- **Support URL:** `https://adkersonjohn.github.io/appleWatchPongGame/support.html`
- **Marketing URL** (optional): `https://adkersonjohn.github.io/appleWatchPongGame/`
- **Build:** click "+" near Build → select the latest TestFlight-approved build that passed Phase 3 exit criteria
- **Screenshots:** drag in the 5 PNGs from `docs/screenshots/` to the 49mm Ultra screenshots panel. Apple auto-fits these for smaller Apple Watch sizes — no separate uploads needed.
- **Subcategories:** Casual (primary), Arcade (secondary)

- [ ] **Step 6: Save all changes**

Click Save (top-right). The 1.0 record now shows "Ready for Review" or similar status pending submission.

---

## Task 23: Verify all listing fields

Pre-submit double-check.

- [ ] **Step 1: Walk through every field**

In App Store Connect, verify each piece is filled and correct:

- App name = "Pong Pal Showdown"
- Subtitle = "Play Pong head-to-head"
- Promotional text matches `docs/marketing-copy-draft.md`
- Description matches `docs/marketing-copy-draft.md`
- Keywords matches `docs/marketing-copy-draft.md`
- Support URL is live and clickable: `https://adkersonjohn.github.io/appleWatchPongGame/support.html`
- Privacy Policy URL is live and clickable: `https://adkersonjohn.github.io/appleWatchPongGame/privacy.html`
- All 5 screenshots uploaded
- Age rating shows 4+
- Category Casual / Arcade
- Pricing Tier 1 ($0.99)
- Privacy nutrition: "Developer does not collect any data"
- Build: latest TestFlight-approved build selected

- [ ] **Step 2: Open both GitHub Pages URLs in a browser**

Manually click through `support.html` and `privacy.html`. Make sure they render and don't 404. If they do, troubleshoot Pages config (Task 13).

---

## Task 24: Submit for App Store review

- [ ] **Step 1: In App Store Connect → 1.0 record → click "Add for Review" or "Submit for Review"**

- [ ] **Step 2: Answer reviewer questions**

- **Sign-in required?** No
- **Demo account?** N/A
- **Notes for the App Review team:**
  ```
  Multiplayer requires two Apple Watches on the same Wi-Fi network. Single-player works on one watch — tap "Single Player" on the start screen to test gameplay solo. The reviewer will only have one device available, so they should focus on the single-player flow to verify functionality.
  ```
- **Contact info:** your name, email, phone number

- [ ] **Step 3: Choose release option**

- **Release this version:** Automatically release this version (matches our spec decision)

- [ ] **Step 4: Click Submit**

App enters Apple's queue. Status: "Waiting for Review" → eventually "In Review" → eventually "Ready for Sale" (auto-released as soon as approved) or "Pending Developer Release" (if you accidentally chose manual).

Apple's typical timing: **24–72 hours**, sometimes faster.

- [ ] **Step 5: Monitor status emails from Apple**

Apple emails you on every status change. If rejected, the email links to the rejection reason in App Store Connect's Resolution Center.

---

## Task 25: Handle rejection (if it happens) or release

- [ ] **Step 1a: If rejected on the "Pong" trademark**

- Go to App Store Connect → Pong Pal Showdown → 1.0 record → edit Name field
- Pick a new name from the brainstorming alternates: e.g., "Bounce With Friends" or "Crown Rally" — whichever you prefer
- Save, resubmit. Same build, no re-archive needed. Same-day cycle typically.

- [ ] **Step 1b: If rejected for some other reason**

Read the Resolution Center note carefully. Common cases:
- **Missing demo / reviewer can't test multiplayer** — strengthen the reviewer notes pointing them to single-player. Resubmit.
- **Privacy mismatch** — verify the privacy questionnaire matches what the app actually does (it should, since the app collects nothing).
- **Metadata rejection** (description / keywords) — adjust copy and resubmit.

- [ ] **Step 1c: If approved**

App goes live in the App Store automatically (per our automatic-release decision). Apple emails you.

- [ ] **Step 2: Verify it's live**

- Open App Store on an iPhone or Apple Watch, search "Pong Pal Showdown"
- Confirm the listing shows: correct name, subtitle, screenshots, $0.99 price, "Get" button (not "Buy" — that's the iOS terminology; Apple Watch App Store uses "Get" + price)
- Buy a copy with a real Apple ID (or use your sandbox test account)
- Install on a real watch
- Run through Single Player and Multiplayer flows one more time

- [ ] **Step 3: Announce**

Whatever channels you choose. The launch is hobby-tier so this is optional.

- [ ] **Step 4: Update memory & internal docs**

Add memories or update the project README to reflect "Pong Pal Showdown" is live in the App Store with build 2 (or whichever build was the final approved one). Mark MP Tasks 21–23 as completed in the task tracker.

---

## Self-Review

After writing, I checked the spec against this plan:

- ✅ Phase 1 spec items (1.1–1.6) → Tasks 1–8
- ✅ Phase 2 spec items (2.1–2.3) → Tasks 9–15
- ✅ Phase 3 spec items (3.0–3.6) → Tasks 16–21
- ✅ Phase 4 spec items (4.1–4.5) → Tasks 22–25
- ✅ All locked decisions reflected (name, subtitle, watchOS 10, $0.99, GitHub Pages hosting, automatic release, etc.)
- ✅ No placeholders in steps — every code/HTML block contains the actual content
- ✅ Type consistency: `winningScore: Int?`, `MultiplayerMatchPhase` cases, `NetworkMessage.startMatch / .clientReady` all match between tasks
- ✅ Frequent commits (one per task, sometimes per sub-step within larger tasks)
- ✅ TDD where applicable — tests first in Task 7
