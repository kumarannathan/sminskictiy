# The store

**Status: 11 of 12 created and live. One left — COIN JAR.**

All three new passes and eight of the nine developer products have real ids
in `game/Config.lua`, and each one was checked against
`MarketplaceService:GetProductInfo` — every id resolves, and every real price
matches what Config claims. All of them appear in both shops.

**An id of 0 is hidden everywhere in the game** — the shop skips it, the
purchase button is never drawn, and nothing can prompt a purchase for asset 0.
So the one missing item is invisible rather than broken.

Images are rendered at **512 × 512** in `art/store/`, one per row below.
Re-render any of them with:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/store_icons.py -- coins1,vault
```

---

## 1. Developer products

Creator Dashboard → your experience → **Monetization → Developer Products → Create**.
Paste each id into `Config.Products` (`productId = ...`).

### Cash bundles

The value curve is deliberate: **coins per Robux climbs with every tier**, so
the big one is always the obvious buy and nobody feels punished for going up.

| Image | Name | Price | Gives | Coins per R$ | Product id |
|---|---|---|---|---|---|
| `coins1.png` | **POCKET CHANGE** | R$ 49 | 3,000 coins | 61 | `3713946196` |
| `coins2.png` | **COIN JAR** | R$ 99 | 7,500 coins | 76 *(+25%)* | ⚠️ **not created** |
| `coins3.png` | **BRIEFCASE** | R$ 249 | 22,000 coins | 88 *(+47%)* | `3713946250` |
| `coins4.png` | **VAULT** | R$ 499 | 50,000 coins | 100 *(best value)* | `3713946313` |

> **COIN JAR is the one still to make.** Without it the ladder jumps straight
> from R$49 to R$249, which is a 5x step — the tier most people would actually
> buy is missing, and the +25% badge that sells the whole "bigger is better
> value" idea never appears. Create it at **R$ 99** with `coins2.png`, then put
> its id into `Config.Products` next to `id = "coins2"`.

**Descriptions** (paste into the dashboard's description field):

- **POCKET CHANGE** — 3,000 coins, straight into your wallet. Enough for a
  couple of outfits or a deposit on your first shop.
- **COIN JAR** — 7,500 coins. 25% more per Robux than Pocket Change. Buys a
  car, a skin and change.
- **BRIEFCASE** — 22,000 coins. Nearly 50% more per Robux. Enough for a
  downtown flat, or the Toy Store with money left over.
- **VAULT** — 50,000 coins. The best value in the game: twice the coins per
  Robux of Pocket Change. Buy the Cinema, buy the penthouse, buy both.

### Skips

The city has two real waits — shops banking up a shift, garden plots ripening.
These end one of them now.

| Image | Name | Price | Does | Config id |
|---|---|---|---|---|
| `skipbiz.png` | **COLLECT NOW** | R$ 25 | every shop you own jumps to a finished shift | `3713946288` |
| `skipfarm.png` | **RIPEN NOW** | R$ 25 | every planted garden plot ripens | `3713946335` |

- **COLLECT NOW** — Every shop you own jumps to a finished shift, completion
  bonus and all. Don't wait out the clock — cash out now.
- **RIPEN NOW** — Every seed you've planted finishes growing this second.
  Harvest the whole garden at once.

### Boosts

Server-wide ones announce who bought them. That is the point of them.

| Image | Name | Price | Does | Config id |
|---|---|---|---|---|
| `boost2x.png` | **2x COINS – 15 MIN** | R$ 75 | double coins, 15 min, just you | `3713947044` |
| `boost2xs.png` | **2x FOR EVERYONE** | R$ 199 | double coins, 15 min, whole server | `3713946975` |
| `boost2xs30.png` | **2x FOR EVERYONE – 30 MIN** | R$ 349 | double coins, 30 min, whole server | `3713947011` |

- **2x COINS – 15 MIN** — Everything you earn pays double for the next 15
  minutes. Jobs, races, shop collections, runs, the lot. Stacks with your
  passes.
- **2x FOR EVERYONE** — 15 minutes of double coins for **every player on this
  server**, with your name on the announcement. Be the hero.
- **2x FOR EVERYONE – 30 MIN** — The same thing, twice as long. Half an hour
  of double coins for the whole server.

---

## 2. Game passes to create

Creator Dashboard → your experience → **Monetization → Passes → Create**.
Paste each id into `Config.Passes` (`gamePassId = ...`).

All three are **created and verified working**.

| Image | Name | Price | Pass id |
|---|---|---|---|
| `starter.png` | **STARTER PACK** | R$ 49 | `1986537277` |
| `auto.png` | **AUTO-COLLECT** | R$ 199 | `1987281225` |
| `speed.png` | **QUICK FEET** | R$ 149 | `1981269868` |

- **STARTER PACK** — Everything a new Sminski needs: 5,000 coins, the Sminski
  Van, and a garden plot unlocked. One purchase, granted once, worth far more
  than it costs. *(Grant is one-time and recorded in save data, so it can
  never be claimed twice.)*
- **AUTO-COLLECT** — Your shops cash themselves out at the end of every shift,
  so you never miss the +50% completion bonus again — including while you're
  offline. The server checks once a minute and only ever collects a *finished*
  shift.
- **QUICK FEET** — Walk 1.6× faster everywhere in the city, and every car you
  own drives 15% quicker.

### Passes that already exist (nothing to do)

VIP (R$299), 2x COINS (R$399), ALL MAPS (R$249), SECOND WIND (R$149),
DREAM GARAGE (R$349), CITY PRO (R$249), TYCOON (R$449), GREEN THUMB (R$129).

---

## 3. What was verified in Play

- Every id resolves through `GetProductInfo`, and every live price matches
  what `Config` says it is.
- City **SHOP**: COINS 3 rows, BOOSTS 5, PASSES 11. Lobby **Toy Shop** COINS
  tab: the same 8. COIN JAR is absent everywhere, as intended.
- **STARTER PACK** granted once: `StarterClaimed` set, the van added, garden
  plots unlocked, coins paid. It cannot pay twice.
- **QUICK FEET**: WalkSpeed 16 → 26. The car half (`CarMult`) was being
  published by the server and read by nothing — half the pass did nothing
  until `carSpeed()` was fixed to apply it.
- **AUTO-COLLECT**: the once-a-minute tick fired and paid 894 coins for one
  finished shift, the client got the event, and the balance moved by exactly
  that amount. (Tested by temporarily dropping `ShiftMinutes` to 0.2; it is
  back at 20.)

## 4. To add COIN JAR

1. Create the product at **R$ 99**, image `art/store/coins2.png`.
2. Put the id into `Config.Products` beside `id = "coins2"`.
3. Sync (`_G.SR_sync()` from the command bar, with `python3 -m http.server
   8765` running in `game/`). It appears in both shops with no other change.

Every grant happens **server-side in `ProcessReceipt`**, and every receipt is
recorded by `PurchaseId` in save data, because Roblox re-calls `ProcessReceipt`
after a failed save and a player would otherwise be paid twice for one
purchase.
