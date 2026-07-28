# Pong Pal Showdown — App Store Submission Design

**Date:** 2026-04-27
**Author:** John Adkerson (with Claude)
**Status:** Draft, pending review

## Goal

Take the working multiplayer Apple Watch Pong game (currently shipping as `PongWatch` on `main`) from "merged PR" to live in the Apple App Store as a paid $0.99 watchOS app under the name **"Pong Pal Showdown"**, via a TestFlight beta period that catches real-world multiplayer bugs before strangers can leave bad reviews.

## Locked decisions

| Decision | Value |
|---|---|
| App Store name | Pong Pal Showdown |
| Subtitle (30 chars) | Play Pong head-to-head |
| Bundle ID | `com.johnadkerson.PongWatch.watchkitapp` |
| Deployment target | watchOS 10.0 |
| Distribution | Standalone watchOS app (TARGETED_DEVICE_FAMILY = 4) |
| Pricing | $0.99 USD (Apple Tier 1) |
| Category | Games → Casual (primary), Arcade (secondary) |
| Age rating | 4+ (auto-assigned via Apple questionnaire — no objectionable content) |
| Distribution path | TestFlight external beta first, then App Store |
| Beta recruitment | Hybrid: friends & family week 1, public link weeks 2–3 |
| Beta feedback channel | TestFlight built-in feedback only |
| Blocker bug policy | Hold launch and fix; do not ship with known blockers |
| Support / Privacy URL hosting | GitHub Pages on existing `appleWatchPongGame` repo |
| App icon | Reuse current 1024×1024 `AppIcon.png` |
| Screenshots | 5 clean watch captures, no marketing-text overlays |
| Pong trademark posture | Accept the residual risk; address rejection or takedown if/when it happens |
| Release after approval | Automatic |

## Phase 1 — Pre-submission technical polish

**Branch posture:** all work on a `feat/app-store-prep` branch (or similar feature branches), merged to `main` via PR per the established branch workflow.

### 1.1 Lower deployment target
- Change `WATCHOS_DEPLOYMENT_TARGET` from `26.4` → `10.0` for the `PongWatch Watch App` target only. Leave the iOS `PongWatch` shell target unchanged.

### 1.2 watchOS 10 smoke test
- Boot a watchOS 10.x simulator (any 41/45/49mm device), install, run through:
  - Start screen → Single Player → Game Over → restart
  - Multiplayer pairing → invite → accept → score picker → match → match-over → rematch
  - Wrist-down/wake during a multiplayer match
- Any "Symbol not found" runtime error → use `#available()` guard or refactor to a watchOS 10-supported API. Most likely no issues; nothing in the codebase looks 11+-specific.

### 1.3 Info.plist local network keys
- Add `NSLocalNetworkUsageDescription` to the watch app's Info.plist:
  > "Pong Pal Showdown finds nearby Apple Watches over Wi-Fi to start a multiplayer match. No data leaves your local network."
- Add `NSBonjourServices` array with single entry: `_pongwatch._tcp` (matches `GameConstants.mcServiceType`).
- **Why critical:** without these keys, watchOS silently blocks `NWBrowser` from discovering peers on real devices. Sim is forgiving; production is not.

### 1.4 Strip `[MP]` debug instrumentation
- Remove all `NSLog("[MP] …")` lines committed in `c0d36de`. Approximately 15 lines across:
  - `MultiplayerService.swift` — `handleOutgoingState`, `handleIncomingConnection`, `respondToInvite`, `handleIncomingState`
  - `MultiplayerGameState.swift` — `handleServiceStateChange`, watchdog firing log

### 1.5 Fix and extend unit tests (option B — thorough)
After the `.configuringMatch` / `.waitingForOpponentAccept` / `.clientReady` / `startMatch` refactor, several existing tests assume the now-defunct direct `.connected` → `.playing` transition. **Update existing + add new tests.**

**Existing tests to update:**
- `test_onConnectAsHostTransitionsToPlaying` → rename to `test_onConnectAsHostTransitionsToWaitingForOpponentAccept`, expect `.waitingForOpponentAccept`
- `test_onConnectAsClientTransitionsToPlaying` → rename to `test_onConnectAsClientTransitionsToConfiguringMatchAndSendsClientReady`, expect `.configuringMatch` + verify `.clientReady` was sent
- `test_wristDownUnderGracePeriodDoesNotForfeit`, `test_wristDownOverGracePeriodForfeits`, `test_wristDownSendsPausedMessage` — insert `state.startMatch(winningScore: 5)` after `simulateConnected(as: .host)` to reach `.playing`
- `test_disconnectMidMatchEndsWithLocalWin` — same: drive into `.playing` via `startMatch` before simulating disconnect
- `test_clientTransitionsToMatchOverWhenSnapshotShowsWinningScore`, `test_peerSilenceTimeoutEndsMatchForLocalRole`, `test_recentPeerActivityDoesNotTriggerSilenceTimeout` — for client-side: `simulateIncoming(.startMatch(winningScore: 5))` after connect, before exercising downstream behavior

**New tests to add:**
- `test_hostReceivingClientReadyTransitionsToConfiguringMatch`
- `test_hostStartMatchSendsAndPlays` — verify message sent, `winningScore` stored, matchPhase `.playing`, inner game state primed
- `test_clientReceivingStartMatchTransitionsToPlaying` — verify `winningScore` stored, matchPhase `.playing`
- `test_cancelMatchConfigurationFromConfiguringDisconnectsAndReturnsToPairing`
- `test_cancelMatchConfigurationFromWaitingForOpponentAcceptDisconnectsAndReturnsToPairing`
- `test_disconnectDuringConfiguringMatchReturnsToPairing` — verify the host doesn't see a "you win" if they bail before play starts
- `test_disconnectDuringWaitingForOpponentAcceptReturnsToPairing`

### 1.6 Build number bump
- `CURRENT_PROJECT_VERSION = 2` for the first TestFlight upload. Increment per upload thereafter.
- `MARKETING_VERSION` stays at `1.0` until v1.1 release.

### Phase 1 exit criteria
- All unit tests pass
- watchOS 10 smoke test passes (Single Player + Multiplayer + wrist-down)
- No `[MP]` `NSLog` calls remaining (`grep -r "\[MP\]" PongWatch/` returns nothing)
- Info.plist has both local-network keys
- App archives cleanly in Xcode (Release config, generic watchOS device)

## Phase 2 — App Store assets

### 2.1 Marketing copy

**App name:** Pong Pal Showdown

**Subtitle (30 char):** Play Pong head-to-head

**Promotional text (170 char, editable post-launch):**
> The classic on your wrist — now with real-time multiplayer between two Apple Watches. Spin the crown, save the ball, beat your friend. No ads, no IAP.

**Description (4000 char, structured):**
1. **Hook (2-3 sentences)** — what it is, what makes it different from any other Pong clone
2. **Multiplayer how-it-works** — local Wi-Fi peer discovery, host picks first-to-3 / first-to-5 / no-limit, head-to-head until someone wins
3. **Features bullets:**
   - Real-time wireless multiplayer between two Apple Watches over local Wi-Fi
   - Single-player vs. AI with progressive difficulty
   - Digital Crown precision paddle control
   - Persistent local high-score tracking
   - Quick 60-second matches
   - **No ads, no in-app purchases, no data collection — ever**
4. **System requirements** — watchOS 10.0 or later, multiplayer requires two Apple Watches on the same Wi-Fi network
5. **Closing line** — "Bring a friend." + support email

**Keywords (100 char, comma-separated, no spaces):**
`pong,multiplayer,paddle,classic,retro,arcade,two player,casual,friends,head-to-head` (83 chars)

### 2.2 Screenshots (5, 49mm Ultra captures, no overlays)

Capture in this order from a 49mm Ultra simulator:
1. **Mid-rally gameplay** — paddles + ball in flight + visible "2 — 1" score (the hook visual)
2. **NearbyPlayersView** — "Nearby Players" header with one peer in the list (set up second sim with displayName visible)
3. **MatchConfigView** — "Play to" with all three buttons visible
4. **Match-over screen** — winner declaration with score (e.g., "5 — 3")
5. **StartView** — Single Player / Multiplayer choice

Apple auto-fits these for smaller display sizes; we don't need separate captures for 41/45mm.

### 2.3 GitHub Pages content

In existing `appleWatchPongGame` repo, add:

```
docs/
  index.html        (lightweight landing page that links to the other two)
  privacy.html      (privacy policy)
  support.html      (support / FAQ + contact)
```

Enable GitHub Pages in repo settings: source = `main` branch, folder = `/docs`.

**Resulting URLs:**
- Privacy Policy: `https://adkersonjohn.github.io/appleWatchPongGame/privacy.html`
- Support: `https://adkersonjohn.github.io/appleWatchPongGame/support.html`

**`privacy.html` content (key points):**
- Zero data collection
- No analytics SDKs, no third-party SDKs of any kind
- Multiplayer uses Bonjour (mDNS) over local Wi-Fi only — peer discovery and game state stays on the user's local network and is not transmitted to any server we control
- High scores stored on-device via `UserDefaults`
- No tracking
- Effective date + contact email for privacy questions

**`support.html` content:**
- One-paragraph app description
- FAQ entries:
  - "How do I play multiplayer?" (steps from StartView → invite flow)
  - "What if my friend's watch doesn't appear in the list?" (both on same Wi-Fi, both on Multiplayer screen, watchOS 10 minimum)
  - "Is there an iPhone app?" (no — this is a standalone watch app)
  - "How do I report a bug?" (email)
- Contact email at the bottom

### Phase 2 exit criteria
- All marketing copy drafted and committed to a temp file in `docs/` (for tracking; final copy lives in App Store Connect)
- 5 screenshots captured + saved to `docs/screenshots/` for reference
- GitHub Pages live and serving privacy.html and support.html

## Phase 3 — TestFlight beta (~2.5 weeks)

### 3.0 App Store Connect record creation
- Sign in to App Store Connect with the team that owns dev team `373QNLTN7Q`
- Create new app record:
  - Platforms: watchOS
  - Name: Pong Pal Showdown
  - Primary language: English (U.S.)
  - Bundle ID: `com.johnadkerson.PongWatch.watchkitapp`
  - SKU: `pong-pal-showdown-1` (any unique-to-account identifier)
  - User access: Full Access

### 3.1 First TestFlight upload (Day 0)
- Xcode → Product → Archive (generic watchOS device, Release config)
- Distribute → App Store Connect → Upload
- Wait ~10–30 min for build processing in App Store Connect
- Verify it appears under the app's TestFlight tab

### 3.2 Beta App Review submission (Day 0)
- Required only for **external** TestFlight testers (groups outside your team)
- Submit the build for Beta App Review with these answers:
  - **Demo account?** No
  - **Reviewer notes:** "Multiplayer requires two Apple Watches on the same Wi-Fi network. Single-player works on one watch."
- Approval typically arrives within 24 hours

### 3.3 Set up beta tester groups
- **Internal** group — yourself + any owned Apple IDs. Available immediately, no review
- **Friends & Family** group — set up Day 0; do not invite yet (wait for Beta App Review approval)
- **Public** group — set up Day 0 with public link generation; do not share the link yet

### 3.4 Week 1 — Friends & Family beta
- Once Beta App Review is approved, send 5–10 personal email invites via App Store Connect
- Send each tester a short text/email with:
  - Specific things to try (full match to 5, no-limit mode, wrist-down mid-match, host quitting picker, both invite + accept flows)
  - How to send feedback (TestFlight app → screenshot → annotate)
  - Acknowledgment that this is a hobby launch, no expectation of formal QA
- Sit on the beta for the full week even if no critical issues — passive playtime exposes session-length bugs
- If a real bug surfaces:
  - Fix on a feature branch, PR, merge to `main`
  - Bump `CURRENT_PROJECT_VERSION` (Build 3, 4, …)
  - Re-archive, re-upload, testers get the new build automatically

### 3.5 Week 2-3 — Public link
- Promote latest build to the **Public** group; share the public TestFlight link
- Cap at 50–100 tester slots in App Store Connect (manageable feedback volume)
- Share locations:
  - r/AppleWatch with a short post
  - GitHub README (badge linking to TestFlight)
  - Personal social if relevant
- Monitor TestFlight feedback + crash reports daily
- Bug triage:
  - **Crash** or **match-doesn't-start** → fix and re-upload immediately
  - **Cosmetic / minor** → log for v1.1, do not block launch

### 3.6 Phase 3 exit criteria (must all be true to advance to Phase 4)
- Zero reproducible crashes in the last 5 days
- Zero blocker bugs (multiplayer fails to pair, match doesn't start, paddle doesn't move, etc.) in the last 5 days
- ≥ 3 different testers have completed at least one full multiplayer match
- ≥ 1 tester pair on a network the developer doesn't control (real-world Wi-Fi diversity)
- All open feedback either resolved, deferred to v1.1 with a note, or judged not-a-bug

If any blocker bug emerges late: hold the launch, fix, return to friends-and-family beta for one more verification week.

## Phase 4 — App Store submission

### 4.1 Final listing finalization
Fill in App Store Connect for v1.0:
- **Name, subtitle, description, keywords, screenshots, support URL, privacy policy URL** — copy from Phase 2 deliverables
- **Category** — primary: Games / Casual; secondary: Games / Arcade
- **Age rating** — fill out questionnaire honestly. Expected outcome: 4+
- **Pricing & availability** — Tier 1 ($0.99 USD), all countries available, no scheduled price changes
- **App privacy** — answer the privacy nutrition questionnaire:
  - "Data Types Collected": **None**
  - "Data Used to Track You": **No**
  - "Data Linked to You": **No**
  - "Data Not Linked to You": **No**
  - Result label: "The developer does not collect any data from this app."

### 4.2 Submission for App Store review
- In App Store Connect, on the v1.0 record, "Add for Review" the same build that ended Phase 3
- Reviewer questions:
  - Demo account? No
  - Reviewer notes: same as Beta App Review notes — "Multiplayer requires two Apple Watches on the same Wi-Fi network. Single-player works on one watch."
- Submit
- Apple reviews in ~24–72 hrs typically

### 4.3 If rejected
- Read rejection reason carefully
- Most common rejection causes for our app:
  - **Trademark issue** (Atari/Pong) — rename the App Store listing only (the bundle ID stays the same), do not need to re-archive. Resubmit
  - **Missing privacy strings** — should have been caught in Phase 1, but verify Info.plist on rejection
  - **Reviewer can't test multiplayer** — reviewer has only one device. Reinforce reviewer notes that single-player is testable solo
- Address, resubmit, usually same-day cycle

### 4.4 Release
- Release setting: **Automatic** — goes live in App Store as soon as approved
- No coordination with social posts or blog launch — hobby launch, ship as approved

### 4.5 Phase 4 exit criteria
- App is live in the App Store
- Listing renders correctly (icon, screenshots, description, both URLs functional)
- Test purchase from a real Apple ID confirms install + run on a real watch

## Post-launch (out of scope for this spec, noted for awareness)

- TestFlight feedback channel stays open after public launch — continue to triage
- Monitor App Store reviews; respond to substantive ones
- v1.1 candidates likely include:
  - Any post-launch blocker bugs
  - watchOS 11/12 compatibility tweaks if Apple breaks something
  - User-requested score options ("First to 7," "First to 11")
  - Possibly Game Center leaderboard integration if local high-score persistence feels limiting after launch

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Apple rejects on "Pong" trademark | Low–Medium | Medium | Rename listing if it happens — bundle ID and code unchanged |
| Atari files a takedown post-launch | Low | High | Rename + reupload v1.1; precedent exists for this resolution |
| Multiplayer fails on certain home routers | Medium | High | Phase 3 public-link beta surfaces this; hold-and-fix policy means we don't ship through it |
| watchOS 10 compatibility breaks something | Low | High | Phase 1 smoke test catches it before any external testers |
| Privacy nutrition label challenged in review | Very Low | Low | Honest answers, no data is collected; documentation in privacy.html |
| TestFlight Beta App Review rejection | Low | Low | Resubmit with corrections; rarely blocks for >24 hrs |

## Out-of-scope explicitly

- Localization beyond English (US) — defer to v1.x if international interest emerges
- Game Center integration / global leaderboards — defer
- iPhone companion app — not building one; Pong Pal Showdown is standalone watchOS only
- Marketing-text screenshot overlays — defer to v1.1 if conversion is weak
- Custom domain / branded website — defer; GitHub Pages is enough for v1.0
- App Store preview videos — defer to v1.1; static screenshots are sufficient for launch
- Paid promotion or App Store Search Ads — defer; rely on organic discovery for v1.0
