# Sminski City — full release plan

Written 2026-10-01. Supersedes the "Still outstanding" lists scattered through
`ROADMAP.md`; those remain the record of how each system got built.

Read `SETUP.md` first if you have not: the repo owns scripts, the `.rbxl` owns
the world, and neither rebuilds the other.

---

# 0. The one thing that is not a feature

**`Config.CapsulesArePaid = false` is factually wrong, and it is a Roblox
policy violation, not a style note.**

`Config.lua:59` says capsules are not Paid Random Items because they cost only
earned coins. That was true when it was written. It is not true now: there are
**eight live Developer Product ids** selling coins for Robux
(`Config.Products`, `grep -c "productId = [0-9]\{6,\}"` → 8). Coins buy
capsules at `Config.CapsuleCost`, so capsules **are** indirectly purchasable
with Robux, which is Roblox's own definition of a Paid Random Item.

This repo already found it. `docs/specs/daily-capsule/monetization.md` finding
3 says the same thing, and adds two details worth repeating:

- **Tier odds are disclosed; per-outcome odds are not.** `Config.Rarities` is
  public (62 / 27 / 9 / 2) but which character inside a tier is never stated.
- **The claw machine has no disclosure at all.**

What has to happen before the game is advertised as released:

1. Set `Config.CapsulesArePaid = true`.
2. Gate every random-reward surface on
   `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`.
   The call already exists at `SminskiServer.server.lua:648-652` — it is read
   and then not used for this.
3. Publish per-outcome odds on the capsule UI, the claw machine, the wheel
   (§3.1) and every bag or crate added later.
4. Decide the restricted-player path. Blocking capsules outright for those
   players removes the whole retention layer below from a real share of the
   audience. **The better answer is to make the activity meter, not Robux, the
   only route to a capsule** — then capsules stop being paid random items for
   everybody and the problem dissolves instead of being gated around.

That fourth point is a design decision, not a code change, and it should be
made before §2 is built on top of capsules.

---

# 1. Release blockers that are plain work

| # | Thing | Where | Notes |
|---|---|---|---|
| 1 | 7 jobs are `soon = true` | `Config.Jobs` | bus, police, construction, fire, grocery, mechanic, photo. Either build them or remove them from the browser — a job list that is half "coming soon" reads as an unfinished game. |
| 2 | COIN JAR has `productId = 0` | `Config.Products` | the R$99 tier, the one most games sell most of. Create it on the dashboard. |
| 3 | Pixel UI art is not uploaded | `Art.lua` | four 9-slices and 34 icons. The code is pixel-ready (`ResampleMode`, quantised scale, integer slices); the art is still the old rounded-candy set, so **the HUD looks half-changed until these land**. |
| 4 | 60-player parcel streaming unproven | `CityBuild` | the one farming step that can genuinely fail. Needs a populated server. |
| 5 | Economy untuned in a live server | `tests/run.luau` | the headless check keeps farming in the same league as taxi (36/min starter, 110/min maxed vs ~50/min taxi). Real players will find the hole the test cannot. |

Everything in §1 needs Studio or the dashboard. Nothing in §2 and §3 does,
until its art and its playtest.

---

# 2. The retention layer

The loop today is **job → money → spend money**. That is complete and it runs
out: once a player has a car, a flat and a wardrobe, money stops meaning
anything. Everything below exists to answer *"I want that"* → *"how do I get
it?"* → *"fine, twenty more minutes."*

## 2.0 Most of the engine is already built

Before designing anything, know what is there — `docs/specs/daily-capsule/`
specified it and the server implements it:

| Already working | Where |
|---|---|
| An **activity meter** that fills from coins *earned*, capped at 187/min, so the fastest capsule is exactly 10 minutes | `SminskiServer.server.lua:1662-1790` (`c.meter`, `meterAdd`, `grantTicket`, `pushTicket`) |
| A **daily ticket cap** that a client cannot forge | `c.meterDay`, `c.meterDayTickets` |
| A **capsule pill** in the HUD with the charge meter | `City.lua` `H.capsule` |
| **Weighted rarity + duplicate refunds** | `Config.Rarities`, `rollCapsule` |
| A **reveal animation** | `UI.playCapsule` |
| A **date-seeded daily hunt**, same three on every server | `c.hunt` |

So the "Time Capsule / activity meter" idea is **done**. Do not build a second
one. What is missing is everything the capsule *contains* and everything that
remembers what you got.

## 2.1 What capsules can contain (the actual gap)

A capsule today can only yield **one of 15 characters**. That is why it stops
mattering after about twenty rolls: the pool is exhaustible and then every roll
is a refund.

Make the drop table a table of **categories**, not characters:

```
coins · outfit piece · hat/accessory · vehicle cosmetic · furniture ·
business decoration · pet/companion · character effect · job XP ·
limited collectible
```

Three rules that keep this from becoming slop:

- **A duplicate is never the main outcome.** Refunds exist, but a capsule whose
  usual result is coins is a slot machine, not a toy.
- **Every drop belongs to a set** (§2.2). An item that is only an item is
  forgettable; an item that is 6 of 8 is a reason to open another.
- **Furniture and business decorations must have somewhere to go.** `CityHome`
  and `CityTycoon` already place objects; a cosmetic with no surface to sit on
  is worse than no cosmetic.

## 2.2 Collections — build this first, it is the spine

Everything else in §2 hangs off this. A reward with nowhere to be recorded is
a number that scrolls past.

**Sets.** Six to eight themed items plus one chase at ~0.5%:

```
SMINSKI STREET SERIES              3 / 8
  traffic cone · fire hydrant · mailbox · trash can
  street sign · newspaper box · bus stop
  ★ golden fire hydrant            0.5%
```

Completing a set pays an exclusive that cannot drop — the only way to hold it
is to have finished the set, which is what makes it worth showing.

**The sticker album** is the container for every set, and the long-term number
a player is actually chasing: `SMINSKI CITY 47 / 100`. Pages complete, pages
pay.

This is `Config.Sets` + `Config.Album` as data, a `c.album` bitfield on the
save, and one new phone tab. **It is entirely headless work** and it is the
highest-leverage thing on this list.

## 2.3 Earn surfaces

**The prize wheel, physically in downtown.** Not a menu — a built object on a
real lot, so walking past it is the reminder. `K.place()` and the `Places`
registry already do this; it wants a plinth, a wheel that spins with real
easing, and the same per-outcome odds disclosure as everything else. One spin a
day, server-seeded by date so it cannot be re-rolled by rejoining.

**Daily login, 7-day cycle**, day 7 exclusive. Keep a limited streak-save,
because losing a 6-day streak to one missed evening makes people quit rather
than try again.

**Weekly limited item.** One item, 7 days, earned through play rather than
bought, then rotated out permanently. This is the single strongest retention
lever on the list and the cheapest to run once §2.2 exists.

**Monthly theme — and this one is time-critical.** It is **1 October today**,
so Halloween is *this month*. A Spooky Month that ships on the 28th has missed
it. If the theme is going to happen for October it needs to be a small, sharp
version — a themed capsule pool, a themed set in the album, pumpkin dressing
on the existing street kit — shipped inside two weeks, not a full seasonal
build. November can be the first properly planned one.

## 2.4 Job mastery

Each job gets its own level, which is where specialisation lives: `FARMER —
LV 23` unlocking farmer outfits, farm decorations, tractor skins, crop crates,
a title. It rides the counters that already exist (`JobTasks`, `TaxiFares`,
`Deliveries`, `CityHarvests`, and the lifetime `d.Stats` added for tasks), so
the data is there — it needs a curve and a reward table, not new tracking.

## 2.5 Social flex

Worth more in a Roblox game than anything private. In order of cost:

1. **Titles** above the character — `New Resident`, `Millionaire`, `Collector`.
   Cheap, and they make §2.4 visible.
2. **Profile showcase** — favourite character, rarest item, collections,
   achievements, playtime. Reuses the business-card screen that already exists.
3. **Subtle auras / name effects** for genuinely rare holdings. Subtle is the
   requirement; a glowing player is a worse-looking game.

## 2.6 Trading — last, and deliberately

Trading turns cosmetics into an economy, which is exactly why it is the most
dangerous thing on this list. It must not ship until:

- Every tradeable item is **server-authoritative** with a unique instance id.
  A cosmetic identified only by name can be duplicated the moment two trades
  interleave.
- Trades are **two-sided and confirmed on the server**, with the item list
  frozen at confirm time. The classic Roblox scam is swapping the offer after
  the other player has agreed.
- There is a **ledger**, the same way `ProcessReceipt` already records every
  `PurchaseId` before reporting success. Without one, a failed trade either
  loses an item or creates one.
- **No currency on either side** in v1. Item-for-item only. Coins in a trade
  invites real-money trading and everything that follows.

Nothing before §2.6 depends on it. Ship the rest and let the collection
economy prove itself first.

---

# 3. Interiors: make every building worth going inside

The city reads well from the street and thin from the doorway. `CityKit` has
the machinery already — `K.place()`, the room builders at `CityKit.lua:1107+`,
and the shop/cafe/counter pieces at `:1268+` that size themselves to the room.

What is missing is **use of the inventory we already curated**:
`docs/INVENTORY.md` lists **57 templates, 1,970 parts** sitting in
`ReplicatedStorage.SminskiAssets.Inventory` — farm pack, McDonald's interior,
park plaza, the tree set — placed by `K.place()` with a part-built fallback.
Interiors are the obvious consumer of that set and barely touch it.

The pass, per building type:

1. Inventory first. If a curated template fits, place it.
2. Kit pieces second — counters, shelving, seating, sized to the room.
3. Inline primitives only where neither reaches.

Order by how long a player stands there: café, grocery, clothing store, the
flats, mall, arcade, then everything else. Every room keeps its fallback, so
a place file without the Inventory folder still builds.

**This is the one track that is art-led and needs eyes in Studio**, so it runs
in parallel with §2 rather than behind it.

---

# 4. Sequencing

| Order | Work | Needs Studio? |
|---|---|---|
| 1 | §0 compliance decision + `CapsulesArePaid` | no |
| 2 | §2.2 collections / sticker album | no |
| 3 | §2.1 capsule contents | art upload only |
| 4 | §2.3 Halloween, small and fast — **October is now** | art upload |
| 5 | §2.3 wheel, daily login, weekly limited | art + a look |
| 6 | §1 blockers 1-3 | yes |
| 7 | §2.4 mastery, §2.5 flex | no |
| 8 | §3 interiors pass | yes, throughout |
| 9 | §1 blockers 4-5 (populated server) | yes |
| 10 | §2.6 trading | yes |

Batch the Studio work. Asset uploads, the interiors pass and the populated-server
tests are the only things that need it, and dipping in and out of Studio for
one icon at a time is how two days of divergence happened last week.

---

# 5. What "released" means

Not a date — a list that is true:

- No `soon = true` in the job browser.
- Every random reward discloses per-outcome odds, and restricted players have
  a real path through the game.
- A new player's first fifteen minutes are the guided task chain
  (`Config.TaskOpening`), and the goal widget is never empty.
- Every building a player can enter has an interior that justifies the door.
- The album gives a reason to play at hour 20, not just hour 2.
- `./tools/check.sh` and `lune run tests/run.luau` both clean.
