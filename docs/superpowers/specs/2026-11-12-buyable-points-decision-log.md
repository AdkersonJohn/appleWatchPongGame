# SDD ledger — plan: docs/superpowers/plans/2026-11-12-buyable-points.md

Spec: docs/superpowers/specs/2026-11-12-buyable-points-design.md (read)
Base: ed383df on branch postToAppleStore

Ruling: work in place on `postToAppleStore` rather than a new worktree — it is
already a feature branch off `feat/pong-watch-game`, not main, and the Xcode
toolchain, simulators and DerivedData are wired to this checkout. Cost if
wrong: the user's working tree carries in-progress code during execution.

## Pre-flight scan

### Task pairs sharing a file or interface

| Pair | Produces → consumes | Finding |
|------|--------------------|---------|
| T1 ↔ T2 | `ProgressionStore` internals, `"progress.ledger"` key | Clean — T1 writes the key, T2 migrates when absent |
| T1 ↔ T3 | `ProgressionStore.init` | Clean *if* T3's new `cloud:` parameter keeps a default; T1 and T2 tests call `ProgressionStore(defaults:)`. T3's Produces block specifies a default |
| T1 ↔ T4 | `recordPurchase(points:transactionID:)` | Clean — declared in T1, implemented T1 step 5, tested T4 |
| T1 ↔ T5 | `creditedTransactions`, `owned[].boughtAt` | **Conflict — see Ruling 2** |
| T2 ↔ T5 | `boughtAt: .distantPast` on migrated items | Clean — makes refunds re-lock genuinely newer purchases first, as T5 requires |
| T3 ↔ T5 | ledger mutation → cloud push | **Gap — see Ruling 3** |
| T4 ↔ T5 | `PurchaseService` transaction loop | Clean — T4 builds the loop, T5 adds the revocation branch |
| T4 ↔ T6 | `PointPack`, `PurchaseService` | Clean |
| T1 ↔ T6 | balance, `UnlockCatalog` costs | Clean |
| T3 ↔ T6 | `UnlocksView` constructs `ProgressionStore()` | Clean given T3's defaulted parameter |

### Task self-consistency

| Task | Finding |
|------|---------|
| T1 | Clean — test arithmetic checks out (140 + 500 − 50 − 90 = 500) |
| T2 | **Conflict — see Ruling 1** |
| T3 | Clean |
| T4 | Clean |
| T5 | Clean apart from Ruling 2 |
| T6 | Clean |
| T7 | Clean — manual steps, no code contradictions |

### Rulings

Ruling 1 (T2): the plan's migration says `earned[deviceKind] = availablePoints +
cost of migrated items`, but its own test asserts `lifetimePoints == 1180` while
`lifetimeEarned` is defined as the sum of `earned`. Those cannot both hold —
340 + 40 = 380, not 1180. Migration instead seeds `earned[deviceKind]` from the
legacy `progress.lifetimePoints`, rebuilds `owned` from `progress.unlocked` at
catalog cost, and then tops `earned` up by any shortfall so the derived balance
equals the legacy `availablePoints` exactly. Lifetime and balance both land on
the number the player last saw. Cost if wrong: a player's lifetime figure is
restated once, visible only in the "Earned all-time" line.

Ruling 2 (T1/T5): the plan has `revoke` guard on `creditedTransactions`, but a
StoreKit revocation carries the *same* transaction id as the purchase it
reverses — so that guard would see the id already present and no-op every
refund. The ledger gets a second grow-only set, `revokedTransactions`, and
`revoke` guards on that one. Cost if wrong: refunds silently do nothing, which
is the failure this task exists to prevent.

Ruling 3 (T3/T5): T3 defines "every mutation writes local then pushes to the
cloud", and T5 adds `revoke` as a new mutation after T3 is built. `revoke` must
route through the same save-and-push path, not write the ledger directly. Cost
if wrong: a refund applies on one device and is undone by the next sync.

## Progress
Task 1: dispatched (implementer, sonnet) — BASE ed383df — brief task-1-brief.md
Task 1: implemented DONE_WITH_CONCERNS (commit 80f8aa5) — concerns were observations only:
  UI-test runner won't launch in this simulator (pre-existing), and a `points <= 0`
  guard on recordPurchase that matches the existing `award` guard. Proceeded to review.
Task 1: task reviewer dispatched (sonnet) over ed383df..80f8aa5
Task 1: review clean — spec compliant, quality Approved, 0 Critical / 0 Important.
Task 1: minor (deferred): ledger decode failure returns an empty PointsLedger and the
  next write overwrites it — a future added field would wipe stored balances on upgrade.
  Carried into Task 2's dispatch as a requirement, since Task 2 owns this code path.
Task 1: minor (deferred): ledger encode failure writes nil, which deletes the key.
  Also carried into Task 2.
Task 1: minor (deferred): merge tie-break when two owned entries share boughtAt but
  differ on costPaid is order-dependent. Corner case; left for final review triage.
Task 1: minor (deferred): no JSON round-trip test for the ledger (Date/Set encoding).
Task 1: resolved the reviewer's one ⚠️ — the diff touches no existing test file, and the
  implementer's run reported them passing untouched. Accepted on that evidence.
Task 1: complete (commits ed383df..80f8aa5, review clean)
Task 2: dispatched (implementer, sonnet) — BASE 80f8aa5 — brief task-2-brief.md
  Carries Ruling 1 (seed earned from legacy lifetime, then top up so the derived
  balance equals the legacy availablePoints exactly) plus Task 1's two deferred
  decode/encode hardening minors, which live in the code Task 2 edits.
Task 2: NEEDS_CONTEXT — implementer correctly showed Ruling 1 cannot satisfy the brief's
  own fixture, because that fixture is internally inconsistent: lifetime 1180 with one
  40-point item implies 1140 available, not 340. Real 1.1 data always satisfies
  lifetime - sum(owned costs) = available; my invented fixture did not.
Ruling 4 (supersedes Ruling 1's asymmetry): migration seeds earned[kind] from the legacy
  lifetime, rebuilds owned from the legacy unlocked list at catalog cost, then adjusts
  earned in EITHER direction so the derived balance equals the legacy availablePoints
  exactly. The balance a player last saw is the number that must survive; the lifetime
  figure is a brag line and may be restated in the rare inconsistent case. For consistent
  data no adjustment occurs and both figures land naturally.
  Cost if wrong: a player with corrupt 1.1 data sees their all-time total restated once.
Ruling 5: the brief's fixture is corrected to consistent numbers that keep both real
  observed values — available 340, lifetime 1180, unlocked = explosion(40) +
  rainbow(300) + rallyking(100) + crownholder(400) = 840 spent. 1180 - 840 = 340.
  Rejected the implementer's option A (recording the excess as `refunded`) — that field
  means money returned by Apple and must not be overloaded.
  Cost if wrong: the migration test exercises a fixture unlike real data.
Task 2: implemented DONE (commit 3c8244d) after Rulings 4 and 5. Task reviewer dispatched
  (sonnet) over 80f8aa5..3c8244d.
Task 2: review clean — spec compliant as amended, quality Approved, 0 Critical / 0 Important.
Task 2: resolved ⚠️ #1 — migration skipping zero-cost items drops nothing: isUnlocked
  (ProgressionStore.swift:85-86) ORs the ledger against UnlockCatalog.freeIDs
  (Unlocks.swift:200), so free items are owned regardless. Not a gap.
Task 2: resolved ⚠️ #2 — lifetimeEarned (PointsLedger.swift:35) is an unclamped sum, so a
  negative `earned` would surface as a negative lifetime. Only reachable from legacy data
  real 1.1 cannot produce. Confirmed minor, deferred, not a real gap.
Task 2: minor (deferred): the progress.ledger.unreadable backup is never read and a second
  corruption overwrites it; the legacy 1.1 keys could serve as a fallback.
Task 2: minor (deferred): no test for legacy availablePoints of 0 or negative; consider a
  max(0,) clamp on lifetimeEarned.
Task 2: minor (deferred): the upward adjustment path is untested (mirror of the tested
  downward case); it is also the path taken when `unlocked` holds an unknown id.
Task 2: minor (deferred): the unreadable-ledger test asserts only the backup contents, not
  that the store reads as empty afterwards.
Task 2: minor (deferred): OwnedItem decoding is still strict, so adding a field to it later
  would wipe the ledger — the tolerant decode covers PointsLedger only.
Task 2: complete (commits 80f8aa5..3c8244d, review clean)
Task 3: dispatched (implementer, sonnet) — BASE 3c8244d — brief task-3-brief.md
Task 3: implemented DONE_WITH_CONCERNS (commit 4484489), 7 self-reported concerns.
  Task reviewer dispatched (sonnet) over 3c8244d..4484489, with four of the concerns
  named for its specific judgement (missing TDD RED, shared kvstore id, equip not
  syncing, the cloud: default resolution rule).
Task 3: controller-verified concern 3 (shared kvstore identifier) — both
  PongWatch.entitlements and PongWatchWatch.entitlements declare
  $(TeamIdentifierPrefix)com.johnadkerson.PongWatch. That is CORRECT, not a concern:
  per-target identifiers would give the watch and the phone separate stores and defeat
  the whole task. No action.
Ruling 6: defer the developer.apple.com check that iCloud is enabled on the two App IDs
  to Task 7, rather than doing it now. Evidence it is already enabled: both the iOS and
  watchOS builds succeed with -allowProvisioningUpdates, which cannot mint a valid
  profile for an entitlement the App ID lacks. Task 7 needs a portal login anyway for
  the IAP products. Cost if wrong: a device build fails at Task 7 and needs one
  checkbox in the portal.
Task 3: review ❌ Needs fixes — 0 Critical, 3 Important:
  (1) existing tests reach real NSUbiquitousKeyValueStore via GameState() ->
      ProgressionStore() with .standard — violates a hard spec constraint;
  (2) init never pushes when the cloud is empty/older, so a second device sees nothing
      until the first mutation — brief says load, merge, write both;
  (3) migrateLegacyKeys assigns through the setter BEFORE the remote is loaded, so a
      1.1 device upgrading can overwrite another device's cloud ledger. Data loss.
Ruling 7: upgrade the reviewer's Minor "mid-session test is vacuous" into the fix round.
  The reviewer graded it Minor, but the plan assigns Review Focus 3 (iCloud off
  mid-session) to this task, and a test that would pass against any implementation does
  not discharge it. Cost if wrong: one extra test written.
Ruling 8: `equip` not syncing is OUT of scope for this task. The spec's goal is the
  wallet — points and owned items — following the player; equipped selection is never
  mentioned. Recorded as a product follow-up for John, not a defect.
  Cost if wrong: a skin equipped on the phone shows unequipped (but owned) on the watch.
Task 3: minor (deferred): 77/340 test uses a synthetic device key, not the real one.
Task 3: minor (deferred): didChangeExternallyNotification ignores the change reason, so
  an iCloud account switch would merge another Apple ID's wallet in.
Task 3: minor (deferred): StartView builds two throwaway stores per appearance, each with
  its own observer and synchronize().
Task 3: minor (deferred): a cloud ledger that fails to decode returns nil, so an older
  app version can overwrite a newer version's ledger on push.
Task 3: fix round 1 dispatched — resuming the original implementer with 4 findings.
Ruling 9 (reverses Ruling 8): John asked for equipped cosmetics to sync too, so it is now
  in scope. Added as Task 3b in the plan (commit follows), running after Task 3 closes
  rather than folded into its fix round — a scoped re-review verifies findings, and
  slipping a new feature into that diff would muddy the gate.
  Equipped state is the one non-grow-only field: each category carries a changedAt and the
  later choice wins, item id breaking an exact tie so merge stays order-independent.
  Cost if wrong: two devices that equip different skins while apart resolve to the more
  recent one rather than some other rule John might prefer.
Task 3: fix round 1 complete (commit 982f638) — all 4 findings addressed per implementer;
  scoped re-review dispatched (sonnet) over 4484489..982f638.
Task 3: fix round 1/5 (4 addressed, 0 open; commits 4484489..982f638)
Task 3: minor (deferred): fix report gave prose test evidence rather than pasted output.
Task 3: minor (deferred): the XCTest-presence heuristic means a UI test, which launches
  the app in a separate process without XCTest, would use real iCloud. The UI runner does
  not launch in this simulator, so it is latent.
Task 3: complete (commits 3c8244d..982f638, review clean after 1 fix round)
Task 3b: implemented DONE_WITH_CONCERNS (commit 09a21e1), TDD RED observed this time.
  Task reviewer dispatched (sonnet) over 958bf27..09a21e1, with the implementer's four
  concerns named for its judgement (notably: legacy equipped choices migrated without
  re-checking ownership, and a test suite left undeleted).
Task 3b: review — spec ✅, quality Needs fixes. 0 Critical, 2 Important.
Ruling 10 (on the plan-mandated RED finding): the brief itself prescribed the compile
  failure as the expected RED, and in Swift you cannot write a behavioural test against a
  type that does not exist yet without stubbing it, so a compile-level RED is legitimate
  here and I am not treating it as a defect. BUT the reviewer's underlying point stands:
  no new test has been shown capable of failing, and the tie-break/recency logic is
  exactly the subtle kind that needs it. Required instead: a bite check — mutate merge to
  always return $0, confirm the recency and order-independence tests fail, restore.
  Cost if wrong: a subtly wrong merge ships behind tests that never could have caught it.
Ruling 11: the ownership finding is load-bearing, not deferrable. equipped(in:)/
  equippedItem will return a synced or migrated choice naming an item this device does
  not own, and Task 5's spec requires that anything re-locked by a refund falls back to
  its category's free item. The read-side guard closes both. Fixing now so Task 5 can
  rely on it. Cost if wrong: a refunded skin stays equipped.
Task 3b: minor (deferred): re-equipping the already-equipped item re-stamps changedAt and
  pushes, so a stale device could beat another device's newer real choice.
Task 3b: minor (deferred): wall-clock last-writer-wins is open to clock skew — inherent to
  the design John approved.
Task 3b: minor (deferred): the migration test leaks a UserDefaults suite and bundles two
  scenarios.
Task 3b: minor (deferred): no test for migrating equipped state when the stored ledger is
  unreadable.
Task 3b: minor (deferred): init now has three order-dependent steps and deserves a comment.
Task 3b: fix round 1 dispatched — resuming the implementer with 2 findings.
Task 3b: fix round 1/5 (2 addressed, 0 open; commits 09a21e1..07f1225). Bite check
  confirmed: mutating merge to {x,_ in x} failed 3 tests, restored and all pass. Full
  unit bundle re-run after the fix — only the known flake.
Task 3b: minor (deferred): the amended cross-device test dropped the old
  XCTAssertNil(cloud.stored?.equipped[...]) no-push assertion; the equip guard still
  prevents the write but nothing now asserts it.
Task 3b: complete (commits 958bf27..07f1225, review clean after 1 fix round)
Task 4: dispatched (implementer, sonnet) — BASE 07f1225 — brief task-4-brief.md
Task 4: implemented DONE_WITH_CONCERNS (commit a77af85), 253 unit tests pass, 5 concerns.
Ruling 12 (plan gap found by the Task 4 implementer): the plan never says who starts the
  StoreKit transaction listener. Task 6 only wires the Get Points screen. If
  listenForTransactions() and creditUnfinished() are only called when that screen opens,
  a purchase that completed while the app was killed is credited only if the player
  happens to visit the store again — which defeats Review Focus 1, the failure mode Task 4
  was built around. Both must be started at app launch, in the app entry points
  (PongWatchApp and the iOS app struct). Carrying this into Task 6's dispatch as a
  requirement. Cost if wrong: a paid-for purchase sits uncredited until the player
  reopens the store.
Task 4: task reviewer dispatched (sonnet) over 07f1225..a77af85.
Task 4: review ❌ Needs fixes — 0 Critical, 2 Important. Reviewer confirmed the crediting
  logic itself is correct and race-free: one finish() call, reached only via credit(),
  recordPurchase runs synchronously before the await, quantity uses
  transaction.purchasedQuantity rather than the requested amount, unverified and revoked
  transactions are never credited.
  (1) the new money path has no test — PurchaseTests only exercises Task 1's
      recordPurchase, so credit() would pass its tests even if it finished before
      crediting, dropped the quantity multiplication, or used originalID;
  (2) Step 6 (attach Points.storekit to the schemes) was skipped, so Product.products
      returns nothing on a Run and the packs never load.
Ruling 13: do NOT hand the scheme attachment to John as a manual Xcode step. The project
  has no shared .xcscheme files — they are autogenerated into xcuserdata — so the
  StoreKit configuration currently cannot be committed at all. Generating shared schemes
  with a StoreKitConfigurationFileReference makes it reproducible for every checkout and
  for CI, and it is plain XML we can write and verify by building. Fall back to asking
  John only if the generated schemes misbehave. Cost if wrong: a hand-written scheme
  diverges from Xcode's and has to be regenerated from the UI once.
Ruling 14: for the untested money path, prefer extracting the pure decision — product id
  plus quantity plus revocation to a point total — over wiring SKTestSession. SKTestSession
  would need the .storekit config bound to the test plan, which is the very thing that
  needs the UI, and the pure function covers the quantity multiplication, the revocation
  guard and the unknown-product case. The credit-then-finish ordering stays verified by
  inspection (a single call site) and by the device run in Task 7.
  Cost if wrong: ordering regressions are caught on device rather than in CI.
Task 4: minor (deferred, carried to Task 6): purchase() returns false for cancelled,
  pending and already-credited alike, so the UI could report a successful purchase as a
  cancellation.
Task 4: minor (deferred, carried to Task 6/7): quantity above Apple's per-transaction cap
  will fail in the sheet, so the custom stepper must be bounded.
Task 4: minor (deferred): load() swallows the fetch error with try?, so the UI cannot tell
  "failed" from "no products".
Task 4: fix round 1 dispatched — resuming the implementer with 2 findings.
Task 4: fix round 1 (commit acfa794) — finding 1 fixed via the pure
  PointPack.pointsToCredit(productID:quantity:isRevoked:), 255 unit tests pass, both
  schemes build. Finding 2 partly: shared schemes now reference ../../../Points.storekit
  and xcodebuild -list sees both, but runtime product loading is unconfirmed.
  Controller-verified: the stray TmpProbe.swift is removed, the tree is clean, and the
  corrected path does resolve to the real file from the xcschemes directory.
Ruling 15: accept the unverified runtime product load rather than spending another round
  on it. The static facts are all good (path resolves, schemes build, config is valid
  JSON in Xcode's v3 consumable layout), and Task 6 puts the four packs on screen in the
  simulator — if products do not load, that is where it becomes obvious and unmissable,
  at no extra cost. Carrying it into Task 6's dispatch as an explicit check.
  Cost if wrong: Task 6 spends a few minutes discovering the config needs a pbxproj
  entry, or John ticks one box in Edit Scheme.
Task 4: scoped re-review dispatched (sonnet) over a77af85..acfa794.
Task 4: fix round 1/5 (1 addressed, 1 open; commits a77af85..acfa794)
Task 4: fix round 2/5 (1 addressed, 0 open; commits acfa794..71c1f89) — the schemes were
  written but gitignored by a blanket *.xcscheme rule, so the fix existed only locally.
  Rule removed (xcuserdata/ already covers per-user schemes); both schemes now tracked.
Task 4: controller-verified the re-reviewer's one open confirmation — Points.storekit IS
  tracked (git ls-files). A fresh clone now gets the config and both schemes. Tree clean.
Task 4: minor (deferred): Points.storekit absent from project.pbxproj, so it will not
  appear in Xcode's navigator.
Task 4: minor (deferred): scheme blueprint IDs not cross-checked against project.pbxproj;
  both schemes build, which is the stronger check.
Task 4: complete (commits 07f1225..71c1f89, review clean after 2 fix rounds)
Task 5: dispatched (implementer, sonnet) — BASE 71c1f89 — brief task-5-brief.md
Task 5: implemented DONE_WITH_CONCERNS (commit a18f00a), 268 passes + known flake, 7 new
  refund tests, bite check confirmed (guarding on credited / never re-locking failed all 7).
Ruling 16 (load-bearing, fixing before review): the implementer found that
  PointsLedger.merge unions `owned`, so a device that still holds a re-locked item merges
  it straight back and the balance goes negative again — sync silently undoes every
  refund. This defeats the task, so it is not deferrable. Smallest fix that keeps the
  CRDT property: a grow-only tombstone set on the ledger keyed by item id AND the
  re-locked purchase's boughtAt. merge drops an `owned` entry whose boughtAt matches a
  tombstone. Keying on boughtAt rather than id alone means a later re-purchase, which
  carries a newer boughtAt, is not killed by an old tombstone — an id-only tombstone
  would lock a re-bought item out forever.
  Cost if wrong: refunds survive sync but a re-bought item could be wrongly re-locked.
Ruling 17: accept the implementer's refund cap (refunded is capped at earned + purchased
  − already refunded). Without it a refund larger than everything ever granted could never
  reach a non-negative balance, which contradicts the brief's own requirement. It also
  bounds the damage from a refund that arrives before its credit has synced.
  Cost if wrong: a pathological refund removes less than Apple actually reversed.
Task 5: minor (deferred, carried to Task 6): credit() discards revoke's returned re-locked
  list, so the player is not told which items went away.
Task 5: minor (deferred): revoke does not verify the transaction was ever credited on this
  ledger; the cap bounds the exposure.
Task 5: pre-review fix dispatched (correctness concern) — tombstone set.
Ruling 16 CORRECTED by the implementer, and it was right: my design said merge should
  drop owned entries matching a tombstone, but merge keeps the EARLIER boughtAt, so a
  stale copy of a re-locked purchase would shadow the newer re-purchase and then be
  killed by the tombstone — losing the re-buy. It filters each side's owned against the
  unioned tombstones BEFORE merging owned instead. Bite-checked: id-only matching fails
  the re-bought test; ignoring tombstones fails both. Accepted as an improvement on my
  ruling.
Task 5: tombstones added (commit 2eda234), 272 passes + known flake.
Task 5: task reviewer dispatched (sonnet) over 71c1f89..2eda234.
Task 5: review — spec ✅, quality Approved, but 2 Important findings in a money path that
  the reviewer explicitly referred to the controller:
  (1) revoke subtracts points for a purchase THIS ledger never credited (refund arrives
      before the credit syncs), so a player can lose items bought with earned points;
  (2) refunded is keyed by device kind, so if the watch and the phone both process the
      same revocation before syncing, the player is refunded twice.
Ruling 18: fix both, with one unified change, rather than deferring. These are not product
  choices — nobody wants a double refund or a clawback of points never granted — and this
  is the last cheap moment to change the ledger's shape before the UI is built on it.
  The design:
    a. `refunded` becomes `refundedByTx: [String: Int]`, keyed by transaction id and
       merged per-key. Two devices recording the same revocation write the same key with
       the same value, so it counts once. Fixes (2).
    b. a refund counts toward the balance only when its transaction id is ALSO in
       creditedTransactions. A revocation that arrives first is recorded and simply does
       not bite until the matching credit syncs in, at which point it applies by itself.
       Fixes (1) without breaking the arrives-early ordering.
    c. re-locking moves out of revoke into a `settle()` that re-locks newest-first while
       the balance is negative, run after revoke, after recordPurchase and after a merge.
       Deferred refunds need re-locking at the moment they start counting, not at the
       moment they arrived, and running it after every mutation makes the ordering
       irrelevant. It is idempotent.
  Cost if wrong: the core money arithmetic is reshaped late, with 272 tests as the net.
Task 5: minor (deferred): reconcile can leave a negative balance when a stale device spends
  points another device refunded; the floor only holds at settle time.
Task 5: minor (deferred): the free-item exclusion test cannot fail — free items are never
  in `owned`.
Task 5: minor (deferred): a redundant refund test, and no JSON round-trip test for
  tombstones.
Task 5: fix round 1 dispatched — resuming the implementer with both findings.
Task 5: NEEDS_CONTEXT — my ruling 18 collides with the "no editing existing test files"
  constraint: PointsLedgerTests sets l.refunded directly at 3 places.
Ruling 19: authorise editing exactly those three tests. The no-edit rule exists to stop an
  implementer weakening tests so its code passes; here the ledger's shape is changing by my
  explicit instruction, so the tests must follow. Scope: only the three sites that touch
  `refunded`, and only to track the new shape — assertions on behaviour stay as they are,
  except test_balanceIs... whose expected value legitimately changes because an uncredited
  refund no longer counts. Cost if wrong: a test is weakened under cover of a refactor;
  mitigated by the reviewer seeing the test diff.
Ruling 20: accept the implementer's correction — the cap moves into `balance` as
  min(counted refunds, earned + purchased) rather than being applied when revoke records
  the refund. Applying it at record time would store 0 on a device that has not yet seen
  the credit, and the refund would then never count once the credit arrived. Right call.
Ruling 21 (scope extension): fix `purchased` the same way, as purchasedByTx. The
  implementer flagged that `purchased` is keyed by device kind, so if the watch and the
  phone both credit the same transaction from Transaction.updates — which StoreKit will
  deliver to every device on the Apple ID — the merge SUMS them and the player gets double
  points. It is the exact mirror of the refund bug, in the same code, and it predates
  Task 5. Fixing it now costs one more keyed map while the shape is already changing;
  leaving a known double-credit hole in a money ledger to fix only its twin would be
  indefensible. Cost if wrong: slightly more churn in a task already reshaping the ledger.
Task 5: fix round 1/5 (5 addressed, 0 open; commits 2eda234..0ea3b84). Re-reviewer traced
  credit/refund/spend/merge in every order and found no wallet error in either direction,
  and confirmed none of the three authorised test edits weakened an assertion.
Task 5: minor (deferred): nothing asserts recordPurchase keys by transaction id rather
  than device kind — both stores in the double-credit test share a device kind, so a
  per-device-kind key would still pass it. Merge-side keying is covered.
Task 5: minor (deferred): the cap is global (earned + purchased), not per transaction, so
  a revocation whose points exceeded that transaction's credit would eat earned points.
  Needs a caller bug to reach.
Task 5: resolved the re-reviewer's "confirm no shipped data carries the old purchased/
  refunded keys" — the ledger is entirely new in this unreleased branch. Shipped 1.1
  (build 21) stores the legacy progress.availablePoints keys, which Task 2 migrates. No
  shipped data has ever held a ledger. Not a release risk.
Task 5: complete (commits 71c1f89..0ea3b84, review clean after 1 fix round)
Task 6: dispatched (implementer, sonnet) — BASE 0ea3b84 — brief task-6-brief.md
Task 6: resumed after the session ended mid-task; implemented DONE_WITH_CONCERNS
  (commit e6aa6db). Requirement decisions: purchase() now returns a PurchaseOutcome
  (credited/cancelled/pending/alreadyCredited) so a listener-won race is never shown as a
  failure; the stepper is bounded to 10 units (100 points); a refund that re-locked items
  shows a red notice at the top of Unlocks. Two gaps: products never loaded, and the
  layout was never looked at on any simulator.
Diagnosis: the agent's simulator trouble was NOT its own doing — a parallel Claude session
  on a different project (appleWatchSpaceInvaders-challenge) is running xcodebuild test
  against the small watch A27E6AEB right now. That is the contention behind its hung
  SKTestSession probes. Use the 46mm 5593A6A6 for our checks.
Ruling 22: stop chasing simulator product loading inside Task 6. simctl launch cannot
  attach a StoreKit configuration at all, so half the evidence gathered was never going to
  mean anything, and the agent burned ~163k tokens, a hung Xcode and a force-quit on it.
  The authoritative test is real sandbox products on a real device, which is Task 7 and
  needs John regardless. The local .storekit config is a developer convenience, not a
  shipping requirement. Moving the verification to Task 7. Cost if wrong: simulator
  purchase testing stays unavailable and all purchase testing happens on device.
Ruling 23: I will do the layout check myself rather than spend another implementer round
  on it. Looking at a screen is verification, not implementation, and resolving unverified
  items is the controller's job. Cost if wrong: my context carries a few screenshots.
Task 6: task reviewer dispatched (sonnet) over 0ea3b84..e6aa6db.
Task 6: review ❌ Needs fixes — 0 Critical, 1 Important: the stepper bound is enforced only
  on the plus button, not at the purchase site, and its test merely asserts the constant
  equals 10, so it would pass with no enforcement at all. Everything else verified
  compliant: launch listener in the single shared @main entry point, PurchaseOutcome
  consumed so a listener-won race is never shown as failure, nothingLeftToBuy correct in
  both senses, no price string in Swift, both entry points present, refund notice wired.
Task 6: resolved ⚠️ "multiple ProgressionStore instances" — the private `ledger` property
  re-reads and re-decodes UserDefaults on every get (ProgressionStore.swift:87-91) with no
  in-memory cache, so separate instances cannot drift. Safe.
Ruling 24: do NOT keep chasing Apple's documented quantity cap. The doc pages are
  JavaScript-rendered so the fetch agent got empty bodies, and the chrome-devtools MCP
  would not attach a page. The empirical check in Task 7 — attempt a purchase at the bound
  and one above it against real sandbox products — is better evidence than the docs, and
  Task 7 is happening anyway. The value stays a single named constant so changing it is
  one line. Fix the enforcement now; confirm the number on device.
  Cost if wrong: the stepper offers slightly more or less than Apple allows until Task 7
  corrects the constant.
Task 6: fix round 1 dispatched — resuming the implementer with the enforcement finding.
Task 6: fix round 1 (commit 9ffbcde) — purchase() now throws PurchaseError.invalidQuantity
  outside 1...maxQuantity, before the product lookup, never clamping. Constant-equality
  test replaced with rejection tests for 11, 0 and -1 plus an in-range test.
Task 6: controller ran the full unit bundle myself, since the implementer only ran
  GetPointsTests after the fix: 284 passing, only the known MultiplayerGameStateTests
  flake. Verification, not a fix.
Task 6: scoped re-review dispatched (haiku) over e6aa6db..9ffbcde.
Task 6: fix round 1/5 (1 addressed, 0 open; commits e6aa6db..9ffbcde)
Ruling 23 REVISED — I could not do the layout check either. This machine's Xcode has no
  Simulator.app: `open -a Simulator` and `open -b com.apple.iphonesimulator` both fail,
  and mdfind/find across the Xcode bundle return nothing. simctl works headlessly (boot,
  install, launch, screenshot) but exposes no tap API, so there is no way to navigate into
  the Get Points screen without the GUI. The UI-test route is also closed — that runner
  does not launch in this simulator. I verified the app builds, installs, launches and
  renders its menu (screenshot), but the Get Points screen itself has still never been
  seen by anyone. Moving the visual verification to Task 7 alongside the product-loading
  check, both on John's real devices. Cost if wrong: a layout defect on the 42mm watch
  reaches John's hands rather than being caught here.
Task 6: minor (deferred): unverified-transaction wording may alarm a charged player.
Task 6: minor (deferred): @unknown default maps to .cancelled, which is silent.
Task 6: minor (deferred): double-tap window on Buy — isPurchasing is set inside the Task.
Task 6: minor (deferred): the refund notice is in-memory only and is lost on relaunch.
Task 6: minor (deferred): "already have enough" and "App Store unavailable" can show
  together.
Task 6: minor (deferred): "Try again" lacks a 44pt tap target; deprecated single-parameter
  onChange; NSClassFromString("XCTestCase") test guard sits in production code.
Task 6: complete (commits 0ea3b84..9ffbcde, review clean after 1 fix round; visual
  verification deferred to Task 7)
FINAL whole-branch review (opus, 17 commits): mergeable after named fixes. 1 Critical,
  8 Important/accepted, 6 Minor, plus triage of the 36 deferred minors into 7 must-fix.
Ruling 25: ACCEPT the reviewer's disagreement with Rulings 17/20. The refund cap becomes
  per transaction — min(refundedByTx[tx], purchasedByTx[tx]) summed over credited txs —
  rather than global against earned+purchased. Same amount of code, strictly safer (a
  refund can never reach earned points), and it subsumes a deferred minor instead of
  carrying it forward. My global cap was the lazier answer.
Ruling 26: ACCEPT the reviewer's disagreement with Ruling 18c. settle()-after-merge is
  the right mechanism and stays, but my ruling was half a ruling: if a merge can re-lock
  an honestly-bought item, the player must be told. The notice channel now covers
  reconcile as well as revoke. The test guarding Review Focus 4 also picks numbers that
  leave the balance positive, so settle() never fires in it — it must be made to fire.
Ruling 27: ACCEPT finding 6 deliberately rather than fix it. Two 1.1 devices that both
  own the same item get free points equal to that overlap on first merge, because legacy
  earned is seeded per device while owned is unioned. Always in the player's favour,
  one-time, and the only local fix would restate "Earned all-time" downward, which is
  worse. Documenting it in the code and telling John the number is the right trade.
Findings 8 (do revocations even arrive for finished consumables?) and 9 (maxQuantity
  contradicts the design's "no cap" decision) are not code fixes — both carry into Task 7
  as explicit go/no-go items.
Final fix wave dispatched (single agent, sonnet) — Critical 1; Important 2,3,4,5,7;
  comment for 6; minors 10,11,14,15; plus triaged tests (tombstone JSON round-trip,
  leaked defaults suite).
Final fix wave applied (commit 82806f9): all 12, 287 passing + known flake. Implementer
  honestly reported fix 1 (the Critical) as INCOMPLETE — after an account change the next
  local save still overwrites the new account's cloud value, and the next launch's
  reconcile merges the two anyway. Blocking the reason-check alone is not enough.
Ruling 28: complete fix 1 before the scoped re-review, rather than surfacing a half-fixed
  Critical to John as a merge-time choice. The process allows one fix wave, and this is
  not a second wave — it is finishing the one item the wave left undone, and it is the
  one finding that permanently corrupts a wallet belonging to a different Apple ID.
  The complete fix is the one the reviewer implied: persist FileManager's
  ubiquityIdentityToken alongside the wallet. On load, if the stored token differs from
  the current one, the local wallet belongs to a different account — do not merge and do
  not push; start clean for the new account and keep the old wallet under its own key so
  nothing is destroyed. Cost if wrong: one more targeted round before the gate.
Scoped re-review of the fix wave: findings 2-12 ADDRESSED, no new Critical breakage.
  Finding 1 (the account-switch Critical) PARTLY ADDRESSED — the designed paths are closed
  and tested, but four residual paths remain:
  (a) no token check on local saves, so a mutation while the process is alive across a
      switch pushes the old wallet into the new account's cloud;
  (b) the token check only runs when the notification reason is AccountChange;
  (c) a possible stale-KVS-cache ordering at cold launch — unverifiable without a device;
  (d) migrateLegacyEquipped runs after a switch, pushing the old account's equipped ids.
Controller-verified what the reviewer could not see: the `ledger` setter
  (ProgressionStore.swift:184) calls cloud.save on EVERY mutation, and persist() is
  local-only (:189-193). So residual (a) is real, not hypothetical.
Ruling 29: one more targeted round for (a), (b) and (d), then stop. Same basis as Ruling
  28 — this is finishing the Critical, not opening a new wave, and it is converging: the
  designed paths are closed and these are narrower. The setter is the single choke point,
  so (a) and (b) close in one place. (c) cannot be settled here and goes to Task 7 as a
  device check. If this round does not close them, the residue surfaces to John at the
  merge decision rather than spawning another loop.
  Cost if wrong: one more small round before the gate.
