# Restaurant Row — the restaurant tycoon

**Status:** built, synced and tested in Play (2026-09-22). One Row block,
twelve lots, one restaurant type in depth. The plan for sixty lots is in §7.

## 1. The loop

1. **Claim.** Walk up to a `FOR LEASE` gate on Restaurant Row (the block at
   750,750, the far corner of Green Valley Farms) and press **E · CLAIM**. The
   lot is yours for as long as you are on this server; the *restaurant* is in
   your save and comes with you to whichever lot you claim next time.
2. **Build.** Pads stand on the strip beside the gate, one per piece you can
   buy next — the classic tycoon vocabulary from the two kits the owner
   inserted: a pad with a price, a thing that appears when you pay. Fourteen
   pieces, a dependency tree, at most five pads at once (`Config.Tycoon.Pieces`).
3. **Stock.** Every dish is a recipe over `Config.Groceries`. The **stockroom**
   holds the ingredients: **RESTOCK** buys crates of ten from the supplier at
   80% of shelf price, **UNLOAD MY FRIDGE** tips your own pantry in (you paid
   at the market — the grocery loop feeds this one).
4. **Earn**, three ways, and they are deliberately three different kinds of
   money:
   - **Passive** — while stocked, it sells on its own, banking like a shop in
     the Mall (`CapMinutes`, the shift bonus, TYCOON and AUTO-COLLECT passes
     apply). When the stockroom runs bare, nothing sells. Collect at the
     register.
   - **Serve** — stand behind your own pass, a customer walks in with a
     ticket, **E · SERVE** plays two steps on the kitchen panel, the server
     pays `price × (0.5 + 0.5 × score)`. Paced (`ServeGap` 10s) and credited
     to the capsule meter like a job.
   - **Friends** — another player at your counter presses **E · ORDER**, picks
     a dish, and pays the menu price out of their wallet into your till. The
     tip jar takes 25. Zero-sum: no coins minted, the city moves them between
     friends. They get the meal and `price/2` XP.
5. **Grow.** Stars (1–5) from serving and from friends' orders — never from
   passive sales — add +5% each. **Chains** (3 stars, 8 pieces, 15,000 then
   +10,000 a time, max 3) add +25% each. Name it; the sign says so.

## 2. Balance

Every `rate` in `Config.Tycoon.Pieces` is **sales per minute**. Fully built:
130/min of dishes whose ingredients cost ~40%, so ~75/min net at full stock
— the Pizza Place (18,000 → 60/min) with a chore attached and a social loop
on top. Total build 36,450 coins. The stockroom (120, 300 with the piece)
lasts ~25–60 minutes of full-rate trade, so an absent owner earns one
stockroom's worth and then stops: "come back, restock, collect" is the
dropper-needs-fuel loop of a tycoon. Serving at a perfect score is ~195/min
before passes — job money against LOOPS.md §6's 187, not a new faucet.

Measured in Play (Studio account owns every pass, so wallet numbers are
×~3.25): 9 pieces → 138 sales/min; an hour backdated on 298 stock sold 125
dishes for 13,170 (TYCOON ×2) and ran dry with 58 odd items left; the shift
bonus was exactly half the bank; a corn chowder served at ~100% paid 45 base;
a self-order of a Fruit Cup moved 60 coins wallet→till and paid 30 XP; 4 stars
and one chain took the rate to 198.4 (138 × 1.15 × 1.25).

## 3. Who owns what

| Piece | Where |
|---|---|
| design: plot geometry, pieces, recipe book, rates, stars, chains, passes/products | `Config.Tycoon`, `Config.Passes` (`restaurateur`), `Config.Products` (`tycoonrush`, `tycoonpantry`, `tycoonchain`) |
| lots (positions from `Config.Tycoon.Blocks`), `tycoonPoint` / `tycoonSpot` | `Places.lua` — **not** part of `cityLots()` |
| the money: `rf("Tycoon")`, lazy accrual `tyDue`/`settle`, lot claims, attributes, products, auto-collect leg | `SminskiServer.server.lua`, "RESTAURANT ROW" block |
| the plots: apron, kerb, gate, FOR LEASE post, the Row's middle | `CityBuild.lua` `B.restaurantrow` (was `B.forest`) |
| the buildings, pads, prompts, three cards, customers | `game/CityTycoon.lua` |
| SERVE's minigame | `CityKitchen.lua` `Kit.play(ticket, steps, done)` |
| WORK card's third button, wiring | `City.lua` |

**Server-authoritative, always.** The client never prices anything. Every
action checks where you are standing (`Places.tycoonSpot` + `near`): the
gate to claim, a pad to buy, the stockroom to restock, the register to
collect, the pass to serve, *that* restaurant's pass to order.

**Lazy accrual.** Nothing ticks. `tyDue` replays what the kitchen would have
sold since `since` — orders/min from the rate, round-robin over cookable
dishes, each eating its ingredients out of a copy of the stock — and stops
when it runs dry. `settle` writes that back before any state change that
would alter the replay (buy, restock, unload, a friend's order), which is
what stops "restock then collect" counting new stock as if it had been there
all along. Two pots: `bank` (passive, shift-bonus-eligible) and `till`
(friends' coins, never multiplied).

**Replication.** `ReplicatedStorage.SminskiTycoon.Lot<i>` carries `Owner`,
`OwnerName`, `Name`, `Pieces` (csv), `Stars`, `Open`, `Chains`, `Gold`.
Every client draws every claimed lot from those; the owner's client also has
the full `data.City.tycoon`. Pads are drawn for the owner only.

## 4. Monetization

Existing passes apply as-is: **TYCOON** (×2 passive, 8h cap), **AUTO-COLLECT**
(the finished shift is banked with the shops'), **CITY PRO / VIP / 2x** on
serves through `pay()`. New, all with id 0 until created on the dashboard
(hidden, unpurchasable): pass **RESTAURATEUR** R$299 (stockroom ×2, +2 chain
slots, gold sign); products **RUSH HOUR** R$49 (15 min ×3 customers),
**FULL STOCKROOM** R$25, **FRANCHISE LICENSE** R$199 (+1 chain, skips the
gate). **COLLECT NOW** also settles the restaurant to a finished shift. None
of them buys a rate.

## 5. The kits

Both tycoon kits from the owner's inventory were inserted, read, and
curated by `_inventory_setup.lua` §TYCOON: **blackbot008's Tycoon Kit**
(233368931 — berezaa's, 82 parts, 12 scripts) and the **pizza hut tycoon kit**
(34943877 — 1,507 parts, 331 scripts). Their mechanics are what this
implements; their geometry is 2010 plastic. Copied out as templates:
`TycoonPad` and the appliances `Tyc_Oven / Tyc_Stove / Tyc_Fridge / Tyc_Sink /
Tyc_Soda / Tyc_Fryer / Tyc_Cashier` (fitted to a 7-stud footprint, since the
"fries maker" is a 33-stud cluster). A piece names its template in
`Pieces[].model`; drop a better model in the Inventory folder under the same
name and it stands there instead. All 343 scripts and the Humanoid name tags
were stripped; the raw kits were deleted from ServerStorage.

## 6. Testing

Studio hooks: `SminskiDev:Invoke("city", "tycoon", "goto:1" | "spot:1:till" |
"open" | "stock" | "menu:1" | "serve")` and the plain call returns state +
the prompt. Server: `Tycoon:InvokeServer("dev", { since = s, shift = s,
xp = n })` moves the clocks (Studio only). The `order` action lets a player
order at their **own** counter in Studio only, so both ends of the counter
can be tested by one client. Round 1 caught: the shift timer compared
seconds to minutes; a `state` poll inside 0.12s swallowed a BUY (separate
limiter now); the pad prompt picked the first pad in reach, not the nearest;
`spend()` per crate queued thirty DataStore writes (now one save per fill).

## 7. Sixty lots

`MaxPlayers` is 60, hence the number: one restaurant each on a full server.
A Row block holds **twelve** plots (44 × 38, three a side; a fourth a side
overlaps at the corners). Sixty is five Row blocks: add block keys to
`Config.Tycoon.Blocks` **and** set those keys to `"restaurantrow"` in
`Places.CityBlocks`. Candidates in the farm belt: `cows` (450,750),
`sunflowers` (150,750), `lake` (-150,750), `pumpkins` (-450,750) — which
would make the whole south road Restaurant Row. Decide with a Studio
measurement of what each block builder puts there; nothing else changes.
