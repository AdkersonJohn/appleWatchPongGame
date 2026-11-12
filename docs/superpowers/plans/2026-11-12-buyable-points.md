# Buyable Points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players buy the points the unlock system already runs on, with a wallet that survives a reinstall and syncs across their watch and phone.

**Architecture:** `ProgressionStore`'s public API stays exactly as it is — six call sites and the existing test suite depend on it. Its internals change from one mutable `availablePoints` integer to a grow-only ledger (earned, purchased, refunded, owned-with-price-paid, processed transaction ids) that derives the balance. The ledger is written to `UserDefaults` and mirrored into `NSUbiquitousKeyValueStore`, merging per-key-max and set-union so two devices can't overwrite each other. StoreKit 2 sells four consumable packs plus a quantity purchase of the smallest.

**Tech Stack:** Swift 5, SwiftUI, StoreKit 2, `NSUbiquitousKeyValueStore`, XCTest. iOS 17 / watchOS 10 deployment targets — no version bump needed.

**Spec:** `docs/superpowers/specs/2026-11-12-buyable-points-design.md`

## Global Constraints

- Packs are exactly: 10 points for $0.99, 50 for $3.99, 100 for $6.99, 500 for $19.99. Custom amount is a quantity purchase of the 10-point pack.
- Item prices in `UnlockCatalog` do not change. Earn rates in `PointsRules` do not change.
- `ProgressionStore`'s existing public API keeps its current signatures and behaviour; every existing test in `ProgressionTests.swift`, `AbilityEffectTests.swift` and `UnlockEffectsTests.swift` must still pass untouched.
- The app must work fully with no iCloud account: local wallet, purchases still possible, no blocking and no error shown for iCloud alone.
- A refund reverses the whole purchase: points removed, and items re-locked newest-first until the balance is non-negative. Anything re-locked that was equipped falls back to its category's free item.
- The custom stepper is never capped and never nudges toward a cheaper pack.
- "Earned all-time" (`lifetimePoints`) counts only points earned by playing.
- Ledger keys are per device *kind* — `"watch"` and `"phone"` — never per install.
- Product ids: `com.johnadkerson.PongWatch.points10`, `.points50`, `.points100`, `.points500`.
- Ship target is 1.2.

## Review Focus

Failure modes the spec implies that no obvious task test would catch. Each has a test assigned to the task that owns the code.

1. **A purchase completes while the app is being killed.** StoreKit replays the unfinished transaction next launch; points must be credited exactly once, not zero times and not twice. → Task 4.
2. **StoreKit delivers the same transaction twice** (listener plus `Transaction.unfinished` on launch). Crediting must be idempotent by transaction id. → Task 4.
3. **No iCloud account, or iCloud turned off mid-session.** Playing, buying and spending all still work against the local wallet. → Task 3.
4. **Two devices spend while out of sync**, then both come online. No points vanish and no item is charged for twice. → Task 3.
5. **A refund exceeds what's left.** Points go negative on paper; re-locking must stop at a non-negative balance, must never re-lock a free item, and must leave every category with something equipped. → Task 5.

---

### Task 1: Grow-only ledger behind the existing store API

**Files:**
- Create: `PongWatch/PongWatch Watch App/Progression/PointsLedger.swift`
- Modify: `PongWatch/PongWatch Watch App/Progression/ProgressionStore.swift` (replace the `Key` enum and the points/unlocks internals; public API unchanged)
- Test: `PongWatch/PongWatch Watch AppTests/PointsLedgerTests.swift`

**Interfaces:**
- Consumes: `UnlockCatalog`, `Unlockable` from `Unlocks.swift`.
- Produces:
  - `struct OwnedItem: Codable, Equatable { let costPaid: Int; let boughtAt: Date }`
  - `struct PointsLedger: Codable, Equatable` with `var earned: [String: Int]`, `var purchased: [String: Int]`, `var refunded: [String: Int]`, `var owned: [String: OwnedItem]`, `var creditedTransactions: Set<String>`
  - `var balance: Int { get }` on `PointsLedger` — `earned + purchased − refunded − spent`, where each counter sums its values and `spent` sums `owned` costs paid
  - `var lifetimeEarned: Int { get }` — sum of `earned` only
  - `static func merge(_ a: PointsLedger, _ b: PointsLedger) -> PointsLedger` — per-key `max` on the three counter dictionaries, union on `owned` (keeping the earlier `boughtAt` on collision) and on `creditedTransactions`
  - `static let deviceKind: String` — `"watch"` on watchOS, `"phone"` elsewhere
  - On `ProgressionStore`: `func recordPurchase(points: Int, transactionID: String) -> Bool` (false if already credited)

- [ ] **Step 1: Write the failing ledger tests**

```swift
func test_balanceIsEarnedPlusPurchasedMinusRefundedMinusSpent() {
    var l = PointsLedger()
    l.earned = ["watch": 100, "phone": 40]
    l.purchased = ["phone": 500]
    l.refunded = ["phone": 50]
    l.owned = ["a": OwnedItem(costPaid: 90, boughtAt: .distantPast)]
    XCTAssertEqual(l.balance, 500)
    XCTAssertEqual(l.lifetimeEarned, 140, "purchased points are not earned")
}

func test_mergeTakesTheHigherCountPerDeviceAndUnionsOwnedItems() {
    var a = PointsLedger(); a.earned = ["watch": 77, "phone": 340]
    a.owned = ["x": OwnedItem(costPaid: 40, boughtAt: Date(timeIntervalSince1970: 10))]
    var b = PointsLedger(); b.earned = ["watch": 90]
    b.owned = ["y": OwnedItem(costPaid: 60, boughtAt: Date(timeIntervalSince1970: 20))]
    let m = PointsLedger.merge(a, b)
    XCTAssertEqual(m.earned, ["watch": 90, "phone": 340])
    XCTAssertEqual(Set(m.owned.keys), ["x", "y"])
}

func test_mergeKeepsTheEarlierPurchaseTimeForTheSameItem() // collision keeps distantPast side
func test_mergeIsOrderIndependent()                        // merge(a,b) == merge(b,a)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `xcodebuild test -scheme "PongWatch Watch App" -destination "id=5593A6A6-C278-4D09-919D-D6EA852040D5" -only-testing:"PongWatch Watch AppTests/PointsLedgerTests"`
Expected: FAIL — `cannot find 'PointsLedger' in scope`

- [ ] **Step 3: Write `PointsLedger` in `PointsLedger.swift`**

Dictionaries keyed by device kind so merging is per-key `max`; `creditedTransactions` is a `Set<String>` so it unions. Nothing in the struct ever decreases.

- [ ] **Step 4: Run the ledger tests**

Expected: PASS

- [ ] **Step 5: Move `ProgressionStore` onto the ledger**

Store the whole ledger as JSON under one key, `"progress.ledger"`. `availablePoints` returns `ledger.balance`; `lifetimePoints` returns `ledger.lifetimeEarned`; `award(_:)` adds to `earned[deviceKind]`; `buy(_:)` writes an `OwnedItem` with the catalog cost and `Date()`; `isUnlocked` checks `owned` plus `UnlockCatalog.freeIDs`. Add `recordPurchase(points:transactionID:)`, which returns false and changes nothing when the id is already in `creditedTransactions`.

- [ ] **Step 6: Run the whole existing suite unchanged**

Run: `xcodebuild test -scheme "PongWatch Watch App" -destination "id=5593A6A6-C278-4D09-919D-D6EA852040D5"`
Expected: PASS, except the one known flake `MultiplayerGameStateTests.test_disconnectDuringConfiguringMatchReturnsToPairingNotMatchOver`. `ProgressionStoreTests` must pass with no edits — that is the point of this step.

- [ ] **Step 7: Commit**

```bash
git add "PongWatch/PongWatch Watch App/Progression/PointsLedger.swift" "PongWatch/PongWatch Watch App/Progression/ProgressionStore.swift" "PongWatch/PongWatch Watch AppTests/PointsLedgerTests.swift"
git commit -m "refactor(progression): derive the balance from a grow-only ledger"
```

---

### Task 2: Migration from the old keys

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Progression/ProgressionStore.swift`
- Test: `PongWatch/PongWatch Watch AppTests/PointsLedgerTests.swift`

**Interfaces:**
- Produces: nothing new public. On first load, when `"progress.ledger"` is absent and the legacy keys are present, the store builds a ledger from them and writes it.

Legacy keys, all still in the shipped 1.1 build: `progress.availablePoints`, `progress.lifetimePoints`, `progress.unlocked` (`[String]`), `progress.equipped` (`[String: String]`). `equipped` keeps its own key and is not part of the ledger.

- [ ] **Step 1: Write the failing migration tests**

```swift
func test_anExistingPlayerKeepsTheirBalanceAndItems() {
    defaults.set(340, forKey: "progress.availablePoints")
    defaults.set(1180, forKey: "progress.lifetimePoints")
    defaults.set(["celebration.explosion"], forKey: "progress.unlocked")
    let s = ProgressionStore(defaults: defaults)
    XCTAssertEqual(s.availablePoints, 340)
    XCTAssertEqual(s.lifetimePoints, 1180)
    XCTAssertTrue(s.isUnlocked(UnlockCatalog.item(id: "celebration.explosion")!))
}

func test_migrationRunsOnceAndDoesNotDoubleCountOnReopen()
func test_aFreshInstallWithNoLegacyKeysStartsEmpty()
```

The balance is carried as `earned[deviceKind] = availablePoints + cost of migrated items`, so that deriving `balance` reproduces the number the player last saw. `lifetimeEarned` is seeded to the recorded lifetime figure where that is larger.

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — balance comes back 0

- [ ] **Step 3: Implement the migration in `ProgressionStore`'s initialiser**

Migrated items get `costPaid` from the catalog and `boughtAt: .distantPast`, so a later refund re-locks genuinely newer purchases first.

- [ ] **Step 4: Run the tests**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(progression): carry existing balances into the ledger"
```

---

### Task 3: iCloud sync

**Files:**
- Create: `PongWatch/PongWatch Watch App/Progression/LedgerSync.swift`
- Modify: `PongWatch/PongWatch Watch App/Progression/ProgressionStore.swift`
- Test: `PongWatch/PongWatch Watch AppTests/LedgerSyncTests.swift`

**Interfaces:**
- Consumes: `PointsLedger.merge`, `ProgressionStore`.
- Produces:
  - `protocol LedgerCloudStore { func loadLedger() -> PointsLedger?; func save(_ ledger: PointsLedger); func startWatching(_ onRemoteChange: @escaping (PointsLedger) -> Void) }`
  - `final class CloudKitValueStore: LedgerCloudStore` — `NSUbiquitousKeyValueStore.default`, key `"progress.ledger"`, observing `didChangeExternallyNotification`
  - `final class NoCloudStore: LedgerCloudStore` — every method a no-op, used when iCloud is unavailable
  - `ProgressionStore.init(defaults:cloud:)` with `cloud: LedgerCloudStore = ...` defaulting to the real one

The iCloud entitlement (key-value store) must be added to both app targets.

- [ ] **Step 1: Write the failing sync tests**

Use an in-memory fake conforming to `LedgerCloudStore`.

```swift
func test_aRemoteLedgerMergesIntoTheLocalOneWithoutLosingPoints() {
    // local earned 77 on watch; remote earned 340 on phone
    // after merge: balance 417, matching the spec's worked example
}

func test_anItemBoughtOnOneDeviceIsOwnedOnTheOtherAndChargedOnce()
func test_everyLocalChangeIsPushedToTheCloudStore()

/// Review Focus 3
func test_withNoCloudStoreEarningBuyingAndSpendingAllStillWork() {
    let s = ProgressionStore(defaults: defaults, cloud: NoCloudStore())
    // award, buy, isUnlocked all behave exactly as the local-only tests expect
}

/// Review Focus 4
func test_twoDevicesThatBothSpentOfflineKeepBothItemsAndBothCharges()
```

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — `cannot find 'LedgerCloudStore' in scope`

- [ ] **Step 3: Implement `LedgerSync.swift` and wire it into `ProgressionStore`**

On init: load local, load remote, merge, write both. On every mutation: write local, then push. On remote change: merge and write local.

- [ ] **Step 4: Run the tests**

Expected: PASS

- [ ] **Step 5: Add the iCloud key-value entitlement to both targets, then build both**

Run: `xcodebuild -scheme PongWatch -destination "generic/platform=iOS" build` and the watch scheme equivalent.
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(progression): sync the wallet through iCloud"
```

---

### Task 4: Point packs and StoreKit purchasing

**Files:**
- Create: `PongWatch/PongWatch Watch App/Progression/PointPack.swift`
- Create: `PongWatch/PongWatch Watch App/Progression/PurchaseService.swift`
- Create: `PongWatch/Points.storekit` (local StoreKit configuration for testing without App Store Connect)
- Test: `PongWatch/PongWatch Watch AppTests/PurchaseTests.swift`

**Interfaces:**
- Consumes: `ProgressionStore.recordPurchase(points:transactionID:)` from Task 1.
- Produces:
  - `struct PointPack: Identifiable, Equatable { let id: String; let points: Int }` with `static let all: [PointPack]` — the four packs in ascending order, and `static let custom: PointPack` (the 10-point pack, bought with a quantity)
  - `@MainActor final class PurchaseService: ObservableObject` with `@Published private(set) var packs: [(pack: PointPack, product: Product)]`, `@Published private(set) var isPurchasing: Bool`, `func load() async`, `func purchase(_ pack: PointPack, quantity: Int = 1) async throws -> Bool`, `func listenForTransactions()`, `func creditUnfinished() async`
  - `enum PurchaseError: Error { case unverified, productUnavailable }`

Prices live in App Store Connect, never in code; `PointPack` carries only the point value. Display prices come from `Product.displayPrice`.

- [ ] **Step 1: Write the failing purchase-crediting tests**

These test the crediting rules against `ProgressionStore` directly; StoreKit itself is exercised by hand in Task 7.

```swift
func test_aCreditedPurchaseAddsPointsWithoutTouchingTheEarnedTotal() {
    let s = ProgressionStore(defaults: defaults, cloud: NoCloudStore())
    s.award(20)
    XCTAssertTrue(s.recordPurchase(points: 500, transactionID: "tx-1"))
    XCTAssertEqual(s.availablePoints, 520)
    XCTAssertEqual(s.lifetimePoints, 20, "buying is not earning")
}

/// Review Focus 2
func test_theSameTransactionIdIsNeverCreditedTwice() {
    XCTAssertTrue(s.recordPurchase(points: 100, transactionID: "tx-7"))
    XCTAssertFalse(s.recordPurchase(points: 100, transactionID: "tx-7"))
    XCTAssertEqual(s.availablePoints, 100)
}

/// Review Focus 1
func test_aTransactionCreditedOnOneLaunchIsNotRecreditedOnTheNext() {
    // same defaults, brand new ProgressionStore, same transaction id
}

func test_everyPackIsAWholeNumberOfPointsAndTheyAscend()
func test_customBuysTheTenPointPack()
```

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — `cannot find 'PointPack' in scope`

- [ ] **Step 3: Implement `PointPack.swift`**

- [ ] **Step 4: Implement `PurchaseService.swift`**

`purchase` calls `product.purchase(options:)`, adding `.quantity(quantity)` when quantity > 1. On `.success(let verification)`, take the verified transaction, call `recordPurchase` with `String(transaction.id)`, and only then `await transaction.finish()` — finishing before crediting is how a purchase gets lost. `listenForTransactions` runs `Transaction.updates` for the app's lifetime; `creditUnfinished` drains `Transaction.unfinished` at launch. Both route through the same crediting path, which is why it has to be idempotent.

- [ ] **Step 5: Run the tests**

Expected: PASS

- [ ] **Step 6: Create `Points.storekit`** with the four products at the spec's prices and attach it to both schemes' run configuration.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(iap): sell point packs through StoreKit"
```

---

### Task 5: Refund reversal

**Files:**
- Modify: `PongWatch/PongWatch Watch App/Progression/ProgressionStore.swift`
- Modify: `PongWatch/PongWatch Watch App/Progression/PurchaseService.swift`
- Test: `PongWatch/PongWatch Watch AppTests/PurchaseTests.swift`

**Interfaces:**
- Produces: `ProgressionStore.revoke(points: Int, transactionID: String) -> [Unlockable]`, returning the items it re-locked so the caller can tell the player.

- [ ] **Step 1: Write the failing refund tests**

```swift
func test_arefundRemovesUnspentPointsAndLeavesItemsAlone() {
    // bought 500, spent nothing, refund 500 -> balance 0, nothing re-locked
}

func test_arefundRelocksTheNewestItemsUntilTheBalanceIsWholeAgain() {
    // buy a 40-pt item then a 300-pt item, refund 500
    // the 300 goes first; returns [thatItem]
}

/// Review Focus 5
func test_arefundNeverRelocksAFreeItemAndNeverLeavesTheBalanceNegative() {
    // refund far more than was ever bought
    XCTAssertGreaterThanOrEqual(s.availablePoints, 0)
    XCTAssertTrue(s.isUnlocked(freeItem))
}

func test_anItemRelockedWhileEquippedFallsBackToTheCategorysFreeItem() {
    XCTAssertEqual(s.equippedItem(in: .celebration)?.cost, 0)
}

func test_theSameRefundIsNeverAppliedTwice()
```

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — `value of type 'ProgressionStore' has no member 'revoke'`

- [ ] **Step 3: Implement `revoke(points:transactionID:)`**

Add to `refunded[deviceKind]`, then while `balance < 0` remove the `owned` entry with the latest `boughtAt` whose `costPaid > 0`, restoring its cost to the balance as it goes. Guard on `creditedTransactions` the same way crediting does, so a replayed revocation is a no-op. Any category left with a non-owned item equipped falls back via the existing `equippedItem(in:)` rule.

- [ ] **Step 4: Handle revocation in `PurchaseService`**

In the `Transaction.updates` loop, a transaction with a non-nil `revocationDate` calls `revoke` instead of `recordPurchase`.

- [ ] **Step 5: Run the tests**

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(iap): reverse the whole purchase on a refund"
```

---

### Task 6: The Get Points screen

**Files:**
- Create: `PongWatch/PongWatch Watch App/Screens/GetPointsView.swift`
- Modify: `PongWatch/PongWatch Watch App/Screens/UnlocksView.swift`
- Test: `PongWatch/PongWatch Watch AppTests/GetPointsTests.swift`

**Interfaces:**
- Consumes: `PurchaseService`, `PointPack`, `ProgressionStore`.
- Produces: `struct GetPointsView: View` with `init(chasing: Unlockable?, onDone: @escaping () -> Void)`, and `enum GetPointsAvailability { case sellable, nothingLeftToBuy }` with `static func current(store: ProgressionStore) -> GetPointsAvailability`.

Layout, per the spec's chosen mock: balance at the top; the cost of the item being chased underneath when `chasing` is non-nil; the four packs with `Product.displayPrice`; the custom stepper in tens; a way back. Same view on both platforms.

- [ ] **Step 1: Write the failing availability tests**

```swift
func test_thePacksAreSellableWhileAnythingRemainsUnaffordable()

/// The spec's anti-goal: never sell currency that buys nothing.
func test_thereIsNothingLeftToBuyOnceTheBalanceCoversEverythingUnowned() {
    // award the full remaining catalog cost
    XCTAssertEqual(GetPointsAvailability.current(store: s), .nothingLeftToBuy)
}

func test_owningEverythingAlsoMeansNothingLeftToBuy()
```

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — `cannot find 'GetPointsAvailability' in scope`

- [ ] **Step 3: Implement `GetPointsAvailability` and `GetPointsView`**

When `nothingLeftToBuy`, the packs render disabled with a single line saying the player already has enough for everything left.

- [ ] **Step 4: Wire the two entry points in `UnlocksView`**

The unaffordable row — currently `.disabled(!owned && !affordable)` at the end of `row(for:)` — becomes tappable and opens `GetPointsView(chasing: item)`. The balance line at the top of the list opens `GetPointsView(chasing: nil)`. Bump `revision` on return so the list redraws with the new balance.

- [ ] **Step 5: Run the tests, then the whole suite**

Expected: PASS, bar the known flake.

- [ ] **Step 6: Look at it on both simulators**

Watch `5593A6A6-C278-4D09-919D-D6EA852040D5` (Series 12 46mm), phone `CC5D1267-B340-466B-8375-4D2472EC1584` (iPhone 18 Pro Max). Tap a locked item you can't afford on each; confirm the stepper is usable with a fingertip. Check the small watch too — Series 12 42mm `A27E6AEB-6596-40D8-B6D4-48D0DB466783` — since that is where the pack rows and prices run out of width.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(unlocks): a Get Points screen behind the locked items"
```

---

### Task 7: App Store Connect products and a real purchase

**Files:**
- Modify: `PongWatch/PongWatch.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION`, `MARKETING_VERSION` to 1.2)

Not code. This is the task that proves the feature works against Apple rather than against a local config file, and it can only run after John has signed the Paid Applications agreement.

- [ ] **Step 1: Create the four consumable products in App Store Connect**

Ids and point values from Global Constraints; price tiers $0.99 / $3.99 / $6.99 / $19.99. Each needs a display name, a description and a review screenshot.

- [ ] **Step 2: Confirm quantity purchasing**

Check whether the App Store still caps a quantity purchase at 10 units. If it does, the stepper reaches only 100 points through the 10-pack; register further pack products rather than capping the feature, and update `PointPack.custom` accordingly.

- [ ] **Step 3: Buy each pack in the sandbox on a real watch**

Including: kill the app mid-purchase and relaunch, and confirm the points land exactly once.

- [ ] **Step 4: Request a sandbox refund and confirm the reversal**

The points go and the newest items re-lock, per Task 5.

- [ ] **Step 5: Bump to 1.2, archive, upload, submit with the products attached**

New in-app purchases must be submitted alongside the build the first time.

- [ ] **Step 6: Commit**

```bash
git commit -am "chore(release): 1.2 with point packs"
```
