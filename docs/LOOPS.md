# Short loops — the plan for CCU

**Goal:** a player who has just finished something should, within about a
minute, be given a reason to go somewhere else in the city — and ideally run
into another player when they get there.

**Status:** phase A is **built, synced and tested in Play** (results in §9).
Phases B-G are plan only.

---

## 1. What the code says today

Read before designing, because it changes the plan:

| Fact | Where | Consequence |
|---|---|---|
| **City state is per-player.** Litter, fares, parcels and plots all live in `s.city` on that player's session. | `SminskiServer.server.lua` ~1416 | Two players on the same street are playing two private games. Nothing in the city is *shared*. This is the actual CCU gap — not a shortage of activities. |
| Four of the proposed loops already exist as jobs: parcels, taxi fares, litter, the pizzeria. | `Config.Jobs`, `City.lua`, `CityKitchen.lua` | "Delivery Rush", "Taxi Rush", "City Cleanup" and "Café Rush" are a **timed wrapper** around what is there, not four new systems. |
| The sky is a pure function of `workspace:GetServerTimeNow()` — every client computes the same rain with no replication. | `Weather.lua` | "Rainy day" events get their trigger for free, and everyone sees them at once. |
| A notification stack already exists. | `J.notify` in `CityJobs.lua` | That *is* the phone. It needs a history and a GO button, not a rebuild. |
| Beacons + the green-dot path already route a player to a position. | `beacon()`, `CityWayfind.lua` | Every event gets "take me there" for free. |
| Capsules cost 400 **earned** coins, are never paid, already handle duplicates (refund), and `rollCapsule` already has a free-gift path. | server ~504 | Free play-time capsules need a meter and a ticket, not a new reward system. |
| 15 whole-body skins exist and `buildSminski` takes a `skinDef`. | `Config.Skins`, `Models.lua` | A "rare Smiski sighting" is an NPC in a skin. **Zero new art.** |
| A server-wide announce path exists. | `feed()`, `boostEvent` | Event announcements reuse it. |
| Kart-race checkpoints exist. | `RACE_CPS` in `City.lua` | Races are a new course list, not a new system. |

---

## 2. One system, not seventeen

Seventeen bespoke features would be seventeen sets of bugs. Every idea on the
list is one of **five archetypes**, so build five things and express the rest
as data in `Config.Events`.

| Archetype | The verb | Covers |
|---|---|---|
| **FIND** | one hidden thing, clues, first/anyone to reach it | Smiski Sighting, Smiski Spotting, Lost Smiski, Lost Cat, Food Truck, Ice Cream Truck, Daily 3 Hunt |
| **COLLECT** | N things scattered in a zone, a shared server counter | Cash Drop, Balloon Festival, shared City Cleanup, rain-only items, Power Outage (fuse boxes) |
| **RUSH** | a timed, score-multiplied wrapper on an existing job | Delivery Rush, Taxi Rush, Pizza Rush, "café pays 2x for 5 minutes", the champion board |
| **RACE** | checkpoints, ranked finish | Bus Stop Race, Rooftop Race |
| **ROUND** | a rules minigame that needs a crowd | Hide & Seek, Red Light Green Light |

An event definition is data:

```lua
{ id = "cashdrop", kind = "collect", title = "CASH DROP!", icon = "coin",
  warn = 45, lasts = 120, minPlayers = 1, weight = 10,
  zone = "district", count = 24, each = 60, shared = false }
```

### The director (server, new: `CityEvents` section of the server script)

One loop per server. It is the only thing that starts events.

- **A headline event every ~6 minutes**, announced 45–60s ahead so there is
  time to travel. Never two headlines at once.
- **Ambient spottings between headlines** — a rare Smiski for 60–120s, no
  warning, announced only when someone finds it.
- Picks by weight, filtered by: player count (`minPlayers` — no Hide & Seek
  on an empty server), current weather, and "not one of the last three".
- **Server-authoritative.** The server picks the spot, keeps it secret, and
  validates every claim by character distance + event clock, then pays
  through the existing `pay()` so boosts and passes apply. Collectible ids are
  per-event; one claim per player per id. The client only draws.
- Spots come from `Places.cityLots()` / `CityLandmarks` /  a new hand-placed
  `Places.CityHideSpots` list (append-only, like lots).

### The client (`CityEvents.lua`, new module alongside `CityJobs.lua`)

Draws the event (pooled parts, no per-item lights — `performance.md`), the
timer strip, the shared counter, and the result card.

### The phone (extends `J.notify`)

A **PHONE** button on the left HUD column with WORK / SHOP / TOWN. It lists
what is live and what is coming, each with a **GO** button that lays the
green-dot path. Notifications keep arriving as toasts; the phone is where you
find the one you missed. Three feeds go through it:

- `EVENT` — from the director
- `JOB OFFER` — "the pizzeria is paying 2x for 5 minutes" (a RUSH modifier)
- `CITY NEWS` — "Alex found a rare Smiski near the park" (existing `feed()`)

---

## 3. The personal loops (fill the gaps between headlines)

These are always available, so a player is never waiting on the director.

- **Rush shifts.** Any world job gets a RUSH variant from the job board: 3
  parcels / 5 fares / 10 pizzas against a clock, payout scaled by time left,
  combo for consecutive perfect scores. Reuses the job remote and its
  anti-cheat (pace floor, score clamp) as-is.
- **10-minute champion.** The server already sees every `jobEvent` credit.
  Keep a rolling 10-minute total per category; show the top three on the
  phone and in TOWN; the champion wears a small crown until dethroned.
- **Capsule meter.** Fills from *doing things* (tasks, events), not idle
  time — AFK farming should not pay. Roughly one **capsule ticket** per 10
  active minutes, redeemed **at the Capsule Corner machine**, so it is also a
  reason to cross town. See §6 for why not every 5 minutes.
- **Daily 3 Hunt.** Three hidden Smiski, positions seeded from the date so
  **every player has the same three** — that makes them shareable ("the mall
  one is behind the escalator"). Saved per-day in player data; reward on the
  third. This is the returning-player hook.
- **NPC errands** (phase G). `npcSay` exists; an errand is a FIND with a
  single-player scope and a saved story index per NPC.

---

## 4. The five-minute cycle this produces

```
00:00  finish a pizza shift
00:20  PHONE  "rare Smiski spotted near Downtown"        (ambient FIND)
01:40  found it -> collectible + capsule meter ticks
02:00  PHONE  "FOOD TRUCK arriving at the park in 45s"   (headline FIND)
03:00  at the park with four other players
04:30  served -> coins + XP, meter full -> capsule ticket
04:40  walk to Capsule Corner, open it
05:30  PHONE  "DELIVERY RUSH -- 2x parcels for 5 min"    (JOB OFFER)
```

Nothing in that list is a new progression system. It is the existing city,
with a reason to move every ninety seconds.

---

## 5. Build order

Each phase ships something playable and is tested in Play before the next.

| Phase | Builds | Ships |
|---|---|---|
| **A — the spine** | director, `CityEvents.lua`, phone, **FIND** | Smiski Sighting (skins, no new art), Lost Cat, Food Truck |
| **B** | **COLLECT** + shared counter | Cash Drop, Balloon Festival, shared Cleanup |
| **C** | **RUSH** wrapper, job offers, champion board | Delivery / Taxi / Pizza Rush |
| **D** | dailies + capsule meter | Daily 3 Hunt, capsule tickets |
| **E** | **RACE** courses | Bus Stop Race, Rooftop Race |
| **F** | **ROUND** | Hide & Seek, Red Light Green Light |
| **G** | flavour | NPC errands, neighbour knocks, Photo Hunt, Power Outage |

**A first, and A alone is worth shipping**: it is the smallest thing that
makes the server feel shared, and B–F are all data + one archetype each on
top of it.

### Deferred, and why

- **Shopping Cart Race** — needs a new pushed-vehicle controller and a
  hill; the city is flat. High cost, one event.
- **Power Outage as pure ambience** — three dark minutes with nothing to do
  is not a loop. It comes back in G as a COLLECT (reset the fuse boxes).
- **Photo Hunt, full version** — "photograph someone working" needs a camera
  mode plus subject detection. The cheap version (stand at a viewpoint with
  the landmark inside the view cone) is in G.

---

## 6. Economy guardrails

Current earn rate is ~187 coins/min on a paced job. Events must not replace
jobs as the best income, or nobody works.

- A headline event pays about **one minute of job income per minute spent**
  (travel included) — the draw is novelty, collectibles and other players,
  not a better wage.
- Cash Drop: 24 bags × 60 = 1,440 coins **split across the server**, not per
  player.
- **Capsules every 5 minutes would be +400 coins of value per 5 minutes —
  roughly a 40% raise for everyone.** Hence one ticket per ~10 *active*
  minutes. Tune from data, not from this document.
- **Two different things were both called "collectibles" here, and only one of
  them is cosmetic.** The original line — "rare-Sminski collectibles are
  cosmetic, so they can be generous without touching the coin economy" — is
  **true of sightings and false of capsules**, and phase D's give-away leaned on
  it. Corrected:
  - **Rare *sightings*, recorded in `data.City.spotted`** (phase A): cosmetic.
    A found-skins list and a shelf in your flat, read by nothing that pays.
    **The exemption holds.** Be generous.
  - **Capsule *characters*: NOT cosmetic.** `Config.Passives`
    (`Config.lua:409-425`) gives all 15 a live gameplay passive — `Secret`
    (Golden) is `coin = 2`, *every coin worth double*; `Peach` gold ×1.5,
    `Cocoa` +25 coins a run, `Ghost` a free shield. Equipped at
    `SminskiRunner.client.lua:433`, applied at `:2000`, and the coins land in
    the shared wallet through `award()`. **No exemption.** A free capsule is a
    2%-per-roll lottery on run income, so the real value of a ticket is
    `E[refund] + 0.02 × R_future` — about **1,000 coins** for a player with
    50,000 coins of running left in them, not the ~100 a refund-only reading
    gives. Full derivation: `docs/specs/daily-capsule/loop.md` §N4.
  - Scope, exactly: `Config.Passive` is read only by `UI.lua` (display) and the
    runner. **No city code reads it**, so a capsule changes *run* income and not
    city job income — which is why the rest of this section survives the
    correction.
  - Consequence for tuning, recorded: at ~6 tickets/day a committed player holds
    Golden in **~5.7 days** without choosing to chase it. The ticket rate is a
    dial on how fast players acquire an **economic advantage**, not a costume.
    `Secret.coin = 2` is **deliberately kept** — considered and chosen, not a
    defect — and the distance leaderboard is being made passive-neutral
    separately (7 of 15 passives extend survival).

---

## 7. Measure it

`performance.md`: do not guess. Before phase A ships, log three numbers so
there is a baseline to beat:

- session length (median, and % of sessions under 3 minutes)
- event funnel: announced → travelled → completed
- players within 60 studs of another player, as a share of play time

If session length does not move after A + B, stop and rethink before
building C–G.

---

## 8. Pipeline notes

- New props (balloon, cat, money bag, food truck, ice-cream truck, crown,
  phone icon) are **Claude-built in `art/blender/`, human-approved**, and do
  not reach the map without `review = "approved"` in `Props.lua`. The two
  trucks are vehicles — hero assets, several review rounds. Phase A can ship
  with the Sighting alone while they are in review.
- No new geography: every event uses places that already exist, so this stays
  inside the downtown vertical slice.
- `Places.CityHideSpots` is append-only for the same reason lots are.

---

## 9. Phase A as built

| Piece | Where |
|---|---|
| Event definitions, rarity tiers | `Config.Events`, `Config.Event()`, `Config.SightingTier()` |
| The director, the `Events` remote, reveal loop, schedules | end of the city block in `SminskiServer.server.lua` |
| Drawing, prompts, claim, countdown strip, the phone | `game/CityEvents.lua` (new; added to `_sr_sync.lua`) |
| PHONE button (left column, 4th), prompt + step + leave hooks | `City.lua` |

Three events, all from art that already exists and is already approved:

- **SMINSKI SIGHTING** (ambient) -- an NPC in one of the whole-body skins,
  rarity bucketed by the skin's shop price. Starts unannounced; goes public
  when someone finds it or after 25s ("someone saw a rare Sminski in..."), and
  leaves 60s after the first find. Each skin you meet is recorded in
  `data.City.spotted` and counted on the phone.
- **LOST PUP** -- the dog rig at scale 0.18 (the hub already uses it at that
  size). Three clues unlock at 0 / 45 / 100s: district, street, compass
  bearing from the nearest landmark. **This replaces "Lost Cat": a cat is a
  new model, which means Blender + review. The pup ships today.**
- **ICE CREAM TRUCK** -- the existing `icecream` car, parked by a door with a
  beacon. Position is public; the first three there share a bonus.

Also changed while in there: the CITY JOBS card moved down on desktop (it
would have sat under the new fourth button) and, on compact screens, out from
on top of SHOP -- where the earlier left/right HUD split had left it.

### Verified in Play

- Director starts a headline by itself (ice cream truck, 48s warning) with
  the countdown strip on screen; console clean.
- Claim: refused from 40 studs ("get closer"), paid once at 6 studs, refused
  the second time. Payout runs through `pay()`, so passes multiply it like
  any job (460 base -> 2,070 on an account holding every pass).
- A quiet sighting is absent from the public list at +1s and present at +28s
  with two clues and **no spot in the public record**.
- Found skins persist (`spotted` survived a restart). Phone lists events with
  clocks, clues, news and working GO rows.
- Events end on time and remove their models: 4 trucks expired, 4 beacons gone.

### Three things measurement caught

1. **The pup hovered 1.83 studs.** `PUP_Y` was copied from the hub (1.9),
   which turned out to be the hub's floor height. Now +0.00 from the pavement.
2. **7 of 8 hidden spots were inside a shop window.** The facade plane sits
   exactly where "1.5 behind the door" put them. Now 2.5 in front: 6/6 clear.
3. **The truck parked on a post at every door** (a row of them runs 8 studs
   out). It now parks in the measured gutter between kerb (+12) and traffic
   (+18.9): 6/6 clear. Spots are limited to the 381 of 385 lots with the
   standard street section, since the server cannot see geometry.

Also fixed in passing: the title's failsafe tested `titleScreen.Visible`, which
is false in normal play too, so it warned 53s into every healthy session.

### Dev hook

`SminskiRemotes.EventsDev:InvokeServer(id, atMe)` (Studio only) starts an
event now; `atMe = true` drops it 40 studs from the caller.
