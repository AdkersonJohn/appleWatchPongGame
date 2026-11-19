# Buyable points — design

**Date:** 2026-11-12
**Status:** awaiting approval

## Intent

Pong Pal Showdown is free and stays free. The unlock system added in 1.1 gives
players a reason to keep playing — 50 collectibles across celebrations, paddle
skins, ball skins, titles and abilities, bought with points earned by playing.
This adds a second way to get those points: buying them.

The idea came from Juma — if the game is given away, the collectibles section is
a fair place to charge. The player who wants to grind still grinds. The player
who would rather pay can pay.

The model is the one Fortnite uses for V-Bucks: a single currency, earned or
bought, spent in a store whose prices don't change depending on how you got the
currency.

## Goals

- A player who can't afford a collectible can buy the shortfall without leaving
  the moment they're in.
- Buying works on the Apple Watch itself. Ease of purchase is the priority.
- Points a player paid for survive a reinstall, a new phone and a new watch, and
  show up on every device they own.
- The free game is untouched: same earn rates, same item prices.

## Non-goals

- No second currency, no premium tier, no subscription, no ads.
- No change to how many points playing earns.
- No change to what anything in the catalog costs.
- No server, no accounts, no login.
- No battle pass, daily rewards, streaks or other engagement machinery.

## Anti-goals

These are the two ways this fails even if every feature works. John named both.

1. **Players feel scammed.** Paying and then losing the points, being charged by
   accident, or buying currency that can't be spent on anything.
2. **App Review rejects it.**

Every decision below that looks over-careful is answering one of these.

## Decisions John made

- **The currency is the existing points.** Not a parallel "gem". Earned and
  purchased points are the same number and buy the same things at the same
  prices.
- **Packs:** $0.99 / 10, $3.99 / 50, $6.99 / 100, $19.99 / 500, plus a custom
  amount.
- **Everything in the catalog is buyable with money**, including abilities and
  titles. John was asked about each specifically. Abilities remain
  single-player-only, but as a gameplay rule that predates this work, not as a
  limit on what money reaches. Titles are written as achievements
  ("Untouchable: Still unbeaten") and are sellable anyway.
- **The way in** is tapping a locked collectible you can't afford in Unlocks.
- **The destination** is its own "Get Points" screen — not an inline expansion of
  the list, and not a shortfall-first upsell screen. Both alternatives were
  mocked up and rejected. The screen shows the current balance, what the item
  being chased costs, the four packs, the custom stepper, and a way back.
- **Purchase completes on the watch.** No "finish this on your phone" hand-off.
- **A refund takes everything back, items included.** If Apple refunds a pack,
  the points go, and if they've already been spent, the items bought with them
  re-lock. John was offered the softer option — claw back only unspent points and
  let the player keep what they'd bought — and chose the full reversal: a refund
  undoes the purchase completely. Mechanically that means removing the refunded
  points, then re-locking owned items newest-first until the balance is no longer
  negative; anything re-locked that was equipped falls back to its category's
  free item, so the game never has an empty slot. The refunded total is itself a
  grow-only figure, so this survives the merge rules.
- **The custom stepper has no cap and no nudge.** It will happily let someone
  build 500 points out of 10-point packs for about $49.50 when the 500-pack next
  to it is $19.99. John's call: let them buy what they asked for. Both the
  warning and the quiet cap were considered and rejected — the screen stays a
  plain store and doesn't editorialise about which row is better value.
- **iCloud for the wallet**, using the key-value store
  (`NSUbiquitousKeyValueStore`). John asked whether points could move between
  devices over Bluetooth. WatchConnectivity would do that, but only between one
  watch and one paired phone — it loses everything on reinstall or new hardware,
  which is anti-goal 1. iCloud is scoped to the Apple ID instead and covers both
  cases; John chose it once the trade-off was laid out. It needs the player to be
  signed into iCloud; nearly all are, and the app must still work for those who
  aren't (see Constraints).

## Decisions I made

Reversible, but they're mine, not John's. Flagged so they can be overruled on
reading.

- **A grow-only ledger instead of a running balance.** Two devices can both spend
  while out of sync, and a single mutable `availablePoints` integer resolves that
  by one device silently overwriting the other — which can destroy points someone
  paid for. Store instead:
  - points earned, per device (sum across devices = total earned)
  - points purchased, per device (sum = total purchased)
  - the set of unlocked item ids (union)

  Balance is derived: `earned + purchased − cost of everything owned`. Every one
  of those only ever grows, so merging two devices is per-key max and set union,
  and nothing is lost. This is the same storage and the same cost as today; only
  the shape differs.
- **Existing balances carry over, and they add up.** TestFlight players and John
  have points already, and because the devices never synced, the same person can
  hold different balances on each — John's phone shows 340 and his watch 77. The
  first merge sums them (417) rather than taking the larger. Taking the larger
  would silently delete points someone earned, which every existing player would
  see exactly once, as a loss.
- **Ledger keys are per device *kind*, not per install.** One key for watch, one
  for phone. Keying per install would grow the key set forever against iCloud's
  1,024-key ceiling, and pruning is the one thing a grow-only ledger can't do.
  Per-kind keys stay bounded, and a reinstall on the same kind merges by max
  rather than adding a key.
- **Owned items record what they cost at the time of purchase.** The balance is
  derived from the catalog, so re-pricing or removing an item later would quietly
  move every player's balance — including points they paid cash for. Storing the
  price paid alongside the item id means the catalog can change without touching
  anyone's wallet, and costs one extra field.
- **The Get Points screen stops selling when there's nothing left to buy.** Once
  a player's balance already covers everything they don't own, the packs are
  disabled with a line saying so. Selling currency that can't buy anything is
  named in anti-goal 1 and is a live App Review 3.1.1 concern.
- **"Earned N all-time" keeps meaning earned.** Purchased points don't inflate
  the lifetime figure shown in Unlocks; it stays a record of play.
- **The Get Points screen is also reachable from the balance at the top of
  Unlocks**, not only by tapping something unaffordable. Someone who wants to top
  up shouldn't have to pretend to buy something first.
- **Same screen on iPhone and watch**, laid out for each.

## Constraints

- **Apple only sells fixed, pre-registered products.** A free-text "how many
  points?" field is not possible. The custom amount is built as a quantity
  purchase of the 10-point pack — a stepper in tens, bought in one transaction.
- **Consumables cannot be restored by Apple, and finished consumable
  transactions drop out of the purchase history.** The app must own the record of
  what was bought. This is the reason the wallet has to be durable and synced,
  rather than something that can be rebuilt from StoreKit on a fresh install.
- **The app must work with no iCloud account.** It falls back to a local-only
  wallet; the player simply doesn't get cross-device sync. It must never block
  play or purchase on iCloud being available.
- **Deployment targets are iOS 17 and watchOS 10**, so StoreKit 2 is available
  everywhere with no version bump.
- **The newer Paid Applications agreement** on the account that owns the app
  (team `373QNLTN7Q`) was signed by John on 2026-11-12, after this design was
  drafted. Bank account and W-9 were already active. Until that signature
  landed, products couldn't be created in App Store Connect and nothing could be
  tested in the sandbox — worth knowing if the status ever reverts, because it
  blocks on-device testing entirely.
- **This ships as 1.2.** 1.1 — multiplayer, the unlock system, the effects — went
  live in the meantime and is `READY_FOR_SALE` alongside 1.0, so there is nothing
  to wait for and nothing to bundle into.
- **The catalog totals 8,055 points across 50 items**, 5 of which are free. At
  the 500-pack rate that is about $322 to own everything, and the dearest single
  item (the "Pong Legend" title, 750 points) is about $30.
- **Current earn rates, unchanged:** your score, plus 25 for winning a
  multiplayer match, plus 15 for beating your own best.
- **Today `ProgressionStore` is `UserDefaults.standard` and nothing else** — no
  iCloud, no App Group, no WatchConnectivity. The watch and the phone keep
  entirely separate balances right now; this was confirmed in the running app,
  where one showed 77 points and the other 340.

## Left to the builder

- How `ProgressionStore` is restructured for the ledger, and whether the sync
  layer sits behind its existing interface or replaces it.
- Product identifiers and how they map to point values.
- Whether the App Store still caps quantity purchases at 10 units per
  transaction. If it does, the stepper can only reach 100 points through the
  10-pack alone, and the answer is to register a few more pack products rather
  than cap the feature — not to drop it.
- StoreKit plumbing: transaction listener, finishing transactions, what happens
  when a purchase succeeds but the app is killed before the points are credited
  (the ledger must not lose it), and what the player sees when a purchase fails
  or is cancelled.
- Conflict handling details for the KVS merge, including the first sync after an
  install that already has local progress.
- Exact layout of the Get Points screen on each device, and the copy on it.
- Test strategy. The existing suite covers `ProgressionStore` and the catalog
  well, and the ledger rewrite should keep that coverage.

## Rejected alternatives

- **Inline "get points" under the tapped item** — no room for the stepper, and
  the list jumps under the player's finger.
- **Shortfall-first screen that pre-selects the cheapest pack covering the gap** —
  fastest to buy and the most obviously engineered to sell. Rejected in favour of
  the plain store.
- **Warning or capping the stepper when it costs more than a larger pack** —
  rejected as the same kind of editorialising, in the other direction.
- **Keeping purchased items after a refund** — rejected; a refund reverses the
  whole transaction.
- **WatchConnectivity for sync** — see above.
- **Deriving the purchased total from StoreKit's transaction history** — not
  possible for consumables.
