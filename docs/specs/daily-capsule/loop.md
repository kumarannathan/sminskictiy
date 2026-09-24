# Daily 3 Hunt + capsule ticket meter — game-loop design (short loops, phase D)

Written 2026-09-21 by `loop-designer`, first and alone on this feature, so that
`ux-designer` and `monetization-designer` can work from real numbers.
Read `docs/LOOPS.md` §3/§5/§6 and `docs/specs/collect-events/CONTRACT.md` first;
this file is shaped like that contract on purpose.

**One-sentence summary.** Every coin you *earn* by doing something also fills a
meter at the reference job rate with a hard ceiling of 187 units a minute, so
the fastest possible capsule ticket takes exactly ten minutes; the ticket is
only spendable at Capsule Corner in the mall; and three date-seeded hidden
Sminski — the same three on every server — pay the day's fourth ticket to
anyone who finds all three.

**Revision note, read before quoting any number in here.** Three reviews have
corrected this file and one of them invalidated a premise:

1. **A capsule is not a cosmetic.** `Config.Passives` (`Config.lua:409-425`) gives
   all 15 characters a live passive; `Secret` is `coin = 2`. The first draft said
   the opposite and used `LOOPS.md` §6's cosmetics exemption to justify the
   give-away rate. **§6 has been corrected and so has N4** — the corrected value
   of a ticket is `E[refund] + 0.02 × R_future`, ~1,000 coins for a player with
   50,000 coins of running left, **11-14× what this file first published**. The
   city arithmetic survives (no city code reads a passive); the justification does
   not.
2. **Passes are not fully meter-neutral.** The coin multipliers are; QUICK FEET
   and DREAM GARAGE shorten time-to-ticket by up to 2.1× on sweeping and 0× on
   taxi and deliveries. **The ceiling is pass-proof, the floor is not** (D5).
3. **`c.hunt.found` had a save-corruption bug** — a sparse table does not
   round-trip through DataStore JSON (N3 rule 1).

`Ticket = 1870` ships regardless; that is the human's call, to be tuned after
measurement. What changed is *what the dial controls* — see N4's final block.

---

## WHAT EXISTS ALREADY

Nothing in phase D needs a new system. Every piece below already exists and is
already tested; this list is the design.

### The capsule machine, in full (read before touching any of it)

| Fact | Where | What it means here |
|---|---|---|
| `Config.CapsuleCost = 400`, coins only | `Config.lua:54` | A ticket is a 400-coin *sticker price* gift. Its coin-economy cost is much smaller — see NUMBERS §N4. |
| `Config.CapsulesArePaid = false` + `paidRandomRestricted()` | `Config.lua:59`, `SminskiServer.server.lua:518`, cached per player at `:1296-1300`, exposed as `d.CapsulesRestricted` at `:334` | Capsules are not "paid random items" today because coins cannot be bought. A ticket earned by playing is not one either, whatever the flag says — so the ticket path checks **neither** the flag nor `s.capsulesRestricted`, and that is deliberate. See N5; the first draft got this backwards. |
| `rf("OpenCapsule")` = rate limit, policy check, **coin check, coin spend**, then `rollCapsule` | `:529-538` | Exactly four lines of it are about coins. A ticket redemption is the same function with the coin check swapped for a ticket check — and it must not live here (see below). |
| `rollCapsule(player, s)` rolls rarity → character, **refunds duplicates into `s.data.Coins` directly**, `bump(s.data, "capsules", 1)`, feeds rare pulls, returns `{ ok, character, rarity, duplicate, refund, data }` | `:541-570` | The free-gift path already exists. Phase D adds a *caller*, not a branch. The refund at `:562` bypasses `pay()`, so it is **not** multiplied by passes. |
| The free-gift path already has two callers | `ClaimDaily` at `:595-597` (`Config.Daily` day 5 is literally a free capsule, `Config.lua:638`) and the claw at `:1755-1758` (8% chance) | **Precedent.** A free capsule for a once-a-day achievement is already in the game and shipped. The Daily 3's ticket is the same size of gift on the same cadence. |
| `bump(s.data, "capsules", 1)` at `:567` feeds the weekly challenge `wcaps` "Open 3/5 capsules" for 600/800 coins | `Config.lua:503` | A free ticket therefore also progresses a coin-paying challenge that used to be sink-gated. Quantified in N4; recommendation is to leave it. |
| The client path is `ctx.openCapsule()` → `call("OpenCapsule")` → `UI.playCapsule(res)` | `SminskiRunner.client.lua:766-776`, `UI.lua:1211` | If the ticket action returns the **same reply table**, the whole opening animation works untouched. Zero new reward UI. |
| Capsule Corner is a real place with a real prompt | `Places.MallShops[2]` = `V(536, 0, 168)`, `Places.lua:119`; prompt at `City.lua:2236-2241` with `near(me, sh.pos, 14)` | "Redeem at the machine" needs one `near()` call and one prompt branch. `setPrompt` takes exactly **one** button (`City.lua:1750`) — that constrains UX, see REQUESTS. |
| **15 characters, every one with a live gameplay passive — NOT cosmetic** | `Config.Passives`, `Config.lua:409-425`; equipped at `SminskiRunner.client.lua:433`; applied at `:2000`, `:575`, `:587` | **The first draft of this row said "purely cosmetic, no passives" and dismissed `Tour.lua:42` as aspirational. That was wrong, and it was the load-bearing error in this spec.** `Config.Passives` is a separate table from `Config.Characters`, which is why reading only the latter misled me. `Secret` (Golden) is `coin = 2` — *every coin worth double*. Also `Peach` gold ×1.5, `Galaxy` score ×1.15, `Cocoa` +25 coins a run, `Lemon` +1 Lucky Finds, `Ghost` a free shield. |
| **The passive's blast radius is the runner, not the city** | `Config.Passive` is read in exactly two places: `UI.lua:1302, 1323` (display) and `SminskiRunner.client.lua:360, 433, 575, 587, 691, 2000`. **No city code reads it.** | So a capsule changes **run** income and not city job income — and run coins land in the same wallet (`award()` → `d.Coins += coins`, `:431`). A free ticket is therefore a lottery ticket on *economic* power, bounded to one of the two games. |
| Run coins are server-clamped at `distance * 0.35 * 2 + 50` | `:419-420` | A partial brake on `Secret`: no passive can bank more than 0.7 coins/stud, and the clamp was written for the Doubler powerup, so **Golden + Doubler is already truncated**. It bounds the advantage; it does not remove it, and below the clamp `coin = 2` is realised in full. |
| Duplicate refunds: Common 60 / Rare 120 / Epic 250 / Secret 600 at weights 62/27/9/2 | `Config.lua:65-70` | Expected refund on a roll where *everything* is a duplicate = **104.1 coins**. That, not 400, is the ticket's coin-inflation number. |

### The payment funnel — the meter's only hook

`pay(player, s, coins, xp, stat, defer)` at `:1521` is the single door every
city payout goes through, and it already receives the **pre-multiplier base
amount** and a `stat` tag. Every call site:

| Line | `stat` | What it is |
|---|---|---|
| `:1640` | `Deliveries` | parcel dropped at the right door (`near(..., 24)` + `dist/CAR_MAX` pace floor at `:1637`) |
| `:1667` | `TaxiFares` | fare dropped at a landmark (`near(..., 40)` + pace floor at `:1665`) |
| `:1679` | `Sweeps` | litter swept (`(pos - p).Magnitude > 18`/`28` at `:1676`) |
| `:1696` | `CityHarvests` | crop harvested (`near(..., 28)` + 45s `RipeSeconds` at `:1693`) |
| `:1737`, `:1950` | `BizCollects` | **idle** business income, two call sites |
| `:1773` | *(nil)* | the claw machine paying out coins you gambled |
| `:1797` | `Races` | kart race finish (pace floor at `:1790`) |
| `:1841` | `HomeNaps` | 50 coins for sleeping at home, once per 20h |
| `:2116`, `:2168` | `JobTasks` | a pizzeria order + its streak bonus (pace floor `gap < par*0.5` at `:2094`, and the `paced` scaler at `:2097` that already makes rushing pay *less*) |
| `:2621`, `:2682`, `:2745` | `EventsDone` | phase A find claims, phase B item pickups, completion bonus (all distance-checked) |

`award()` (`:411`, the Endless Run payout) **does not go through `pay()`** — it
writes `d.Coins` directly at `:431`. So hooking `pay()` gives a city-only meter
for free, with no filter to write.

`publicData(s)` at `:324` does `table.clone(s.data)`, which includes
`data.City`. **Anything stored in `data.City` reaches the client on every
remote reply already.** The meter needs no new payload and no new remote.

### The FIND machinery the Daily 3 reuses

| Piece | Where | Reused how |
|---|---|---|
| `streetLots` — the 381-of-385 lots with the standard street section | `:2259-2267` | the hunt's candidate pool, unchanged |
| `pickSpot(hidden)` → `lot.door + t*side*11 + n*2.5` | `:2315-2322` | **the measured geometry.** `HANDOFF.md` §5: `-1.5` is inside the shop window (7 of 8 spots were embedded there in the first build), `+2` measured 0/105 blocked with open sky. 2.5 in front of the door with the back to the glass measured 6/6 clear. The hunt uses this exact formula with a *deterministic* side. |
| `nearestLandmark`, `compass`, `streetOf`, `areaOf` | `:2213-2236` | all three clue tiers, no new text machinery |
| `secret(ev)` / the 1 Hz reveal loop | `:2374-2376`, `:2778-2811` | position stays server-side until a player is close. The hunt rides **the same loop**, one extra inner pass over 3 spots — not a second timer (`performance.md`). |
| `cityPos(player)` | `:1466` | the claim distance check |
| The scatter's 12-stud exclusion against `live` event positions | `:2427-2434` | the reason a hunt spot and a collect item never land 0.5 studs apart — the bug the contract predicted |
| `Events:InvokeServer("state")` and the `CityEvent` RemoteEvent | `:2700`, `:2202-2204` | hunt state and hunt broadcasts, no new remote |
| Date-seeded content **already exists**: `hashKey` + `Random.new` + `os.date("!%Y-%m-%d")` | `:84-101`, `:104` | the daily challenge set is already "the same for everyone, seeded by the date". The Daily 3 is the same trick applied to positions. |
| UTC day boundary, three places, all agreeing | `refreshChallenges` `:104`, `refreshLogin` `:314` (`os.time()/86400`), `c.dayEnds` `:116` | **the timezone question is already answered.** No new convention. |
| `saved(s)` creates `data.City` sub-tables lazily with `type(...) ~= "table"` | `:1477-1489` | new fields need **no `defaultData()` change and no migration** |
| `feed()` server-wide announce | `:~290`, used at `:568`, `:2754` | "Sam found the one by the Bakery" — the social half, for free |

**What does not exist:** any telemetry. No `AnalyticsService`, no `LogService`
capture, no session logging anywhere in `game/` — verified, zero matches. Every
number below is therefore a starting value, and MEASURE (§M) says which ones I
distrust.

---

## THE DESIGN

### D0. The loop in one line

**The meter:** finish any piece of real work → the meter moves a visible notch →
at full it becomes a ticket → the ticket only opens at Capsule Corner → you
cross town, open it, see what you got → the meter is already refilling, because
the trip there passed a job board.

**The Daily 3:** log in → the phone says `TODAY'S HUNT 0/3` with a district
clue → you search, find one → the city hears about it and your other two clues
tighten → the third find pays a ticket → tomorrow there are three new ones and
you do not know where.

### D1. One full meter cycle, second by second

A real 11-minute slice, not a best case. Player is clocked in at the pizzeria,
no passes. `[meter]` is units out of 1,870.

```
0:00   clock in at SLICE OF LIFE                                    [meter    0]
0:52   order 1 served, 78 base coins                                [meter   78]
1:44   order 2, 71 base                                             [meter  149]
2:05   PHONE: "CASH DROP! in 45s, Shopping District"    (phase B headline)
2:12   quit the shift, drive east
2:58   arrive, 9 bags x 60 base over 70s                            [meter  689]
       -- 540 units arrive in 70s, but the ceiling only lets 218 of them
       -- through in that window. 471 credited, 69 discarded.       [meter  620]
4:10   drop-in at the Job Center, take 3 parcels
4:55   parcel 1, 104 base                                           [meter  724]
5:40   parcel 2, 121 base                                           [meter  845]
6:30   parcel 3, 96 base                                            [meter  941]
7:05   PHONE: "someone saw a rare Sminski near the park"  (ambient FIND)
8:20   said hi -- Uncommon, 180 base + 80 first                     [meter 1201]
9:10   two more parcels                                             [meter 1420]
10:35  pizzeria, three orders                                       [meter 1651]
11:18  parcel                                                       [meter 1870]
11:18  TOAST: "CAPSULE TICKET  x1  ->  Capsule Corner"    + save written
11:18  the phone's TOWN tab gains a GO row: CAPSULE CORNER, 340 studs
11:52  arrive at the mall, prompt reads USE TICKET (1)
11:54  the existing capsule animation plays. Sakura. New.           [meter    4]
```

Two things to notice, because they are the design:

1. **The cash drop overshot the ceiling and lost 69 units.** That is correct and
   intentional. A burst of income does not buy a burst of tickets; the meter
   measures minutes of activity, and 70 seconds cannot be worth more than 70
   seconds. The player is not told (see D5) because their meter is already
   moving at the maximum possible rate.
2. **The last 34 seconds of the cycle are a walk across the mall.** That is the
   whole reason the ticket is not redeemable from the SHOP button. It puts one
   more player in the mall, next to whoever else is holding a ticket.

### D2. One Daily 3 cycle

```
00:00  join. PHONE > TOWN: "TODAY'S HUNT  0/3"
       #1 "somewhere in Downtown"   #2 "somewhere in the Shopping District"
       #3 "somewhere in Sunny Homes"                      -- tier 1, all three
00:40  walking Downtown, a small plain Sminski is tucked beside a door
00:44  FOUND 1/3  -> 60 base coins, 15 XP
       feed: "Ari found the Downtown Sminski!"          -- the whole server sees
       the other two clues jump to tier 2:
       #2 "on Birch Ave, by the FLORIST"   #3 "on Sunny St, by a house"
01:05  chat: "the florist one is on birch"               -- the shareable moment
02:20  found 2/3 -> 90 base coins, 20 XP. #3 goes to tier 3:
       "south-west of the School, by a house on Sunny St"  + GO button enabled
04:10  found 3/3 -> 150 base coins, 60 XP, +1 CAPSULE TICKET
       feed: "Ari found all three! (2nd on this server today)"
       PHONE: "TODAY'S HUNT  3/3  ·  new ones in 6h 12m"
```

### D3. Which archetype

**FIND.** No sixth archetype, and — this is the part to get right — **not a row
in `Config.Events.List` either.**

The Daily 3 is FIND's *geometry, clue and claim* code with three properties the
director cannot express:

| | An event FIND | The Daily 3 |
|---|---|---|
| position | `pickSpot()`, random per event | seeded from the UTC date, identical on every server |
| lifetime | `def.lasts` seconds, then `finish()` | the whole UTC day, no `endT` |
| who may claim | `ev.claimed[userId]`, in memory, once ever | every player, once each, recorded **in the save** |
| scheduled by | the director's weighted pick | nothing. It exists whenever the date does. |

Forcing that into `Config.Events.List` would mean special cases in `start()`
(`:2461`), `finish()` (`:2530`), `pickHeadline()` (`:2831`), `publicEv()`
(`:2344`) and the reveal loop (`:2778`) — five special cases to avoid one small
table, in the one file phase A and B both live in. So:

> **The Daily 3 is a `Hunt` block placed beside the director, inside the same
> `do` block, so it shares `streetLots`, the door geometry, `nearestLandmark`,
> `compass`, `streetOf`, `areaOf`, `cityPos`, `pay` and `evRemote` — and shares
> no lifecycle with it.** Its tunables go in a new `Config.Hunt` table beside
> `Config.Events`. **Nothing is appended to `Config.Events.List`.**

The meter is not an archetype at all. It is a counter inside `pay()` and an
integer in the save.

### D4. Does the Daily 3 need the director? No.

Independent of the headline schedule, deliberately:

- It must be there **the instant a player joins** — that is what a
  returning-player hook is. The director waits `FirstAfter = 50`s
  (`Config.lua:1004`) and only runs while `anyoneInCity()` (`:2815`).
- It must not consume a headline slot, and `headlineLive()` (`:2821`) must stay
  false for it, or the hunt would suppress real headlines all day.
- It must not enter `lastHeadline`, whose length is computed from the size of
  `EV.List` (`:2861-2863`).

**The entire interface between the hunt and the director is two spot-exclusion
checks and one shared timer:**

1. `scatter()`'s exclusion loop (`:2431`) gains a second pass over the three
   hunt spots, same 12-stud / `144` squared test, same reason: a hidden FIND at
   `door + t*±11 + n*2.5` is 0.5 studs from a collect slot at `a = +12`.
2. `pickSpot()` (`:2315`) rejects a lot that is one of today's three, with a
   bounded retry (6 attempts, then accept). 3 lots out of 381 → the retry runs
   0.8% of the time and can never spin.
3. The 1 Hz reveal loop (`:2778`) gains a hunt pass: reveal inside 90 studs,
   and check for the UTC day rolling over. **No second `task.spawn`.**

### D5. The meter: what counts as an active minute

**The rule, in one sentence:** the meter is credited *one unit per base coin*
by the same `pay()` call that already paid you, from a **whitelist of `stat`
tags**, clamped to **187 units per rolling minute**.

```lua
-- inside pay(), Config.Meter.Rates is a WHITELIST: an absent tag credits 0
local r = base > 0 and stat and Config.Meter.Rates[stat]
if r then meterAdd(player, s, base * r) end
```

`base` is the `coins` **argument**, captured at the top of `pay()` before
`:1523` and `:1525` mutate it. Therefore:

> **The coin multipliers are meter-neutral.** CITY PRO (`cityJobMult`), VIP and
> 2x COINS (`coinMult`), the login streak (`StreakMult`) and all three boost
> paths change what you are paid and never how fast the meter fills.

**But the ceiling is pass-proof and the floor is not, and the first draft of
this spec got that wrong.** `monetization-designer` checked it: two passes
change *how much work you can physically do per minute*, which the meter
correctly counts.

- **QUICK FEET** (`Config.lua:538-539`): `walkMult = 1.6`, `carMult = 1.15`.
- **DREAM GARAGE** (`Config.lua:525-526`): all six cars, which on sweeping means
  the ice-cream truck's 28-stud pickup radius instead of 18 (`:1676`) and 6
  coins a piece instead of 4 (`:1679`), or the sports car at 115 studs/s instead
  of the free convertible's 72 (`Config.lua:674, 678`).

The effect is **entirely confined to the activities that do not already
saturate the 187/min ceiling**:

| activity | free convertible, no passes | with QUICK FEET + DREAM GARAGE | minutes/ticket |
|---|---|---|---|
| taxi, long fares | ~500-640 base/min — **already saturated** | more saturated | 10.0 → 10.0, **0× change** |
| parcels | ~230 base/min — **already saturated** | more saturated | 10.0 → 10.0, **0× change** |
| farm grid | ~160 base/min, just under | walk 1.6× | 11.7 → ~10.0, 1.2× |
| pizzeria at par | ~110-140 base/min | unaffected (a kitchen minigame) | 13-17 → 13-17, **0× change** |
| **sweeping litter** | ~90-120 base/min — the slowest whitelisted activity | radius 28, 6 coins, a faster car | **16-21 → ~10, up to 2.1×** |

So the honest statement is:

> **No pass can beat ten minutes, because the ceiling is applied to units and
> not to coins.** What passes can do is pull the *slowest* whitelisted activity
> up to the ceiling that deliveries and taxi already reach on the free
> convertible. The spread between the best and worst way to fill the meter
> narrows from ~2× to ~1× when you hold the two movement passes; the best case
> does not move at all.

That is a defensible outcome — a paid player does the same work faster and the
meter pays for work — and it is *why* the ceiling is expressed in units per
minute rather than as a per-action cap. It also means **QA item 6 has to name
the activity**, or it proves nothing (see QA 6).

#### Why this defeats AFK farming — three reasons, in order of strength

1. **The meter adds no new trust surface.** Every whitelisted tag is already
   gated by a server-side position check *and*, where it matters, a pace floor:
   `Deliveries` needs the right door within 24 studs and `dist/CAR_MAX` seconds
   (`:1636-1637`); `TaxiFares` the landmark within 40 and the same floor
   (`:1664-1665`); `Sweeps` within 18 (28 in the ice-cream truck) of a position
   *the server chose* (`:1676`); `CityHarvests` within 28 of a plot that ripens
   on a 45-second server clock (`:1693`); `JobTasks` refuses an order faster
   than half par and then scales the payout by how long it really took
   (`:2094-2100`); `EventsDone` distance-checks every claim. **The anti-AFK code
   for phase D was written in 2025. The meter inherits all of it by riding on
   the same line that pays out.**
2. **The whitelist is a whitelist.** `BizCollects` (both sites, `:1737` and
   `:1950`) credits **0** — it is the one genuinely idle income in the game and
   a single button press pays thousands. `HomeNaps` (`:1841`) credits 0 — it is
   a once-per-20-hours gift. The claw's payout (`:1773`) passes `stat = nil` and
   so credits 0 — a machine that hands out capsules must not fill the meter
   that hands out capsules. And any income path added later credits 0 **until
   somebody opts it in**, which is the failure mode you want.
3. **The 187/min ceiling removes the edge from every script.** The ceiling is
   set to the reference job rate, so the best achievable fill is 10 minutes and
   the optimal ticket-farming strategy *is* working a normal job. Concretely:

| A scripted loop | base coins/min | units/min after the ceiling | minutes/ticket |
|---|---|---|---|
| taxi, taxi car, long fares (`:1657-1658`) | ~500-640 | **187** | 10.0 |
| parcels, sports car | ~230 | **187** | 10.0 |
| pizzeria at par | ~110-140 | 110-140 | 13-17 |
| sweeping litter, free convertible | ~90-120 | 90-120 | 16-21 |
| sweeping litter, QUICK FEET + DREAM GARAGE | ~190 | **187** | 10.0 (the ceiling, never below it) |
| walking the 12-plot farm grid | ~160 | 160 | 11.7 |
| `collectBiz` on a loop | thousands | **0** | never |
| standing still, any pose, any car, HUD open | 0 | **0** | never |

The best line in that table is also the best way to earn coins, so a script
buys nothing a player does not already have. **The farm was checked
specifically:** the 12 plots are on a 60×70 grid (`Places.lua:498-506`) and the
claim radius is 28, so the midpoint between two plots is 30 studs from each —
**no standing position reaches two plots**, and the farm cannot be worked
without walking.

#### The allowance, exactly

```lua
-- session-only, NOT saved: s.meterAllow (units), s.meterT (os.clock())
local t = os.clock()                               -- same clock as allow() at :340
s.meterAllow = math.min(M.Burst, (s.meterAllow or M.Burst) + (t - (s.meterT or t)) * M.PerMin / 60)
s.meterT = t
local credit = math.min(math.floor(units), math.floor(s.meterAllow))
if credit <= 0 then return end
s.meterAllow -= credit
```

Allowance regenerates with wall time and is spent only by an action.
**Standing still accrues allowance and never accrues units** — that distinction
is the entire design. A full burst (187, one minute's worth) lets a single fat
payout like a 363-coin fare count in full, which is what makes the meter feel
honest; sustained rate is still 187/min. Allowance is session state, so a
rejoin hands you a full burst — not exploitable, because a burst is a ceiling
and not a currency: you still have to *do* 187 base coins of work to spend it,
and rejoining costs 20 seconds.

#### Grant, caps and the invariant

```lua
local day = os.date("!%Y-%m-%d")                   -- same key as refreshChallenges :104
if c.meterDay ~= day then c.meterDay = day; c.meterDayTickets = 0 end
if c.tickets >= M.MaxTickets or c.meterDayTickets >= M.DayCap then
    c.meter = math.min(c.meter, M.Ticket - 1)      -- park just below full; never discard silently
    return
end
c.meter += credit
while c.meter >= M.Ticket and c.tickets < M.MaxTickets and c.meterDayTickets < M.DayCap do
    c.meter -= M.Ticket; c.tickets += 1; c.meterDayTickets += 1
    grantTicket(player, s)                         -- notify + task.spawn(save, player)
end
```

Three caps, three different jobs:

- **`MaxTickets = 3` banked.** At 3, the meter parks one unit below full and
  stops. This is the cap that matters: it makes the mall trip *required* rather
  than optional, which is the only reason the redemption place was specified in
  `LOOPS.md` §3 at all. It also makes "40 tickets over a weekend" arithmetically
  impossible — the ceiling is 3 in the bank, ever.
- **`DayCap = 12` granted per UTC day** (both sources). 12 tickets is 120
  minutes of ceiling-rate activity. This is a circuit breaker on a scripted
  account that never logs off, not a brake on a real session, and it should only
  ever be *lowered* if measurement shows real accounts reaching it.
- **`Ticket = 1870` units.** Ten minutes at the reference rate. Literally
  `10 × 187`, so the constant documents itself.

**The invariant, stated precisely so nobody "fixes" it:** the *meter* grants
only while `c.tickets < MaxTickets`; the *Daily 3* grants unconditionally
(see D8). So the hard ceiling on `c.tickets` is **`MaxTickets + 1 = 4`**, and a
clamp to 3 would silently eat the hunt's reward.

#### Two states the UI must distinguish

- **Banked cap reached (3 tickets).** Actionable, so say it: the player should
  be told to go to the mall.
- **Per-minute ceiling saturated.** **Do not surface this.** A player hitting
  it is earning above the reference rate, so their meter is already moving as
  fast as a meter can move; a "capped" message is a punishment notice for
  playing well, and it invites a question with no good answer.

#### Redemption — where, and how, reusing what exists

Redemption is an action on the **existing `City` RemoteFunction** (`:1589`),
not on `OpenCapsule`. The reason is mechanical: `OpenCapsule` sits at file scope
(`:529`), where `cityPos`, `near` and `Places`-relative city coordinates are not
in scope — they are locals inside the city `do` block from `:1440`. The `City`
remote already has all of them, already runs the
`"you're not in the city"` guard at `:1600-1601`, and `rollCapsule` is a
file-level local declared at `:528`, so it **is** in scope there.

```
City:InvokeServer("capsuleTicket")
```

1. `allow(s, "City", 0.12)` — already applied at `:1591`.
2. `c.tickets >= 1`, else `{ ok = false, reason = "no capsule tickets yet" }`.
3. `near(pos, Places.MallShops[2].pos, Config.Meter.RedeemServer)` (18), else
   `{ ok = false, reason = "use tickets at Capsule Corner in the mall" }`.
4. **No policy check.** Unlike `OpenCapsule` (`:532-534`), the ticket path does
   **not** test `Config.CapsulesArePaid` or `s.capsulesRestricted`. A ticket is
   earned by playing, so it is not a paid random item, and a free-play route is
   the remedy the policy points restricted players at. See N5 — this omission is
   deliberate and must not be "fixed".
5. `c.tickets -= 1`, then `local res = rollCapsule(player, s)`, then
   `res.tickets, res.meter = c.tickets, c.meter`, `task.spawn(save, player)`,
   return `res`.

`rollCapsule` already returns `{ ok, character, rarity, duplicate, refund, data }`
and already saves, so `UI.playCapsule(res)` (`UI.lua:1211`) plays unchanged.
**Decrement before the roll**, never after: `rollCapsule` calls
`task.spawn(save, player)` at `:566` and a save that lands between the roll and
the decrement would persist a spent ticket as unspent.

**`rollCapsule` itself is not modified.** No `ticket` argument, no branch. It is
called by the paid path, `ClaimDaily` and the claw; adding a branch to it to
adjust duplicate refunds would put phase D's risk inside three unrelated
features to save 104 coins. See N4.

### D6. The Daily 3: seeding

```lua
local function lotKey(lot)        -- geometry, never a list index
    return string.format("%d,%d", math.round(lot.door.X), math.round(lot.door.Z))
end
local dayKey = os.date("!%Y-%m-%d")
-- score every eligible lot, take the three lowest, spread apart
for each lot in streetLots:  score = hashKey("hunt|" .. dayKey .. "|" .. lotKey(lot))
sort ascending by (score, lotKey)                     -- lotKey breaks hash ties
greedily accept a lot if it is >= Config.Hunt.Spread from every accepted lot
stop at 3
side  = (score % 2 == 0) and -1 or 1
pos   = lot.door + t * side * 11 + n * 2.5            -- the measured formula, :2320
face  = lot.face
```

Why it is this and not `Random.new(hashKey(dayKey))` picking three indices:

- **A per-lot hash does not depend on list order or list length.** `streetLots`
  is derived from `Places.cityLots()`, which is append-only *because saves store
  indices* (`Places.lua:280-282`, `:420-423`). An index-based seed would make
  today's answer move the moment a lot is appended. A per-lot hash only moves
  if a newly added lot's own hash lands in the accepted three: ~0.8% per lot
  added, and never for lots that already exist.
- **`hashKey` already exists** (`:84-88`) and is already the project's
  date-seeding primitive (`rollSet`, `:89-101`). No new hash.
- **`lotKey` is geometry**, so nothing in phase D saves a lot index. That is the
  append-only rule handled correctly rather than worked around.
- Stable across a restart: same date, same lots, same hash, same three. This is
  the whole point and it needs no persistence at all — the spots are a pure
  function of the date.

Cost: ~381 hashes plus a sort, once per UTC day per server, cached by `dayKey`.

**Spots are street-side only.** `+2.5` in front of a door on the 381 standard
lots is the only geometry the server can guarantee is clear — the world is built
on the client and the server cannot raycast (`HANDOFF.md` §2). `LOOPS.md`'s
"the mall one is behind the escalator" needs an interior spot list
(`Places.CityHideSpots`, anticipated in `LOOPS.md` §2 and never built); that is
deferred, and the hunt index survives it (see CUT/DEFER).

### D7. Clue tiers — where the social value lives

There are no clue timers. The tier is a function of progress, yours and the
server's:

```lua
tier(i, player) = math.clamp(1 + myFoundToday + math.min(foundHere[i], 2), 1, 3)
```

`foundHere[i]` is a **server-wide count of how many players on this server have
found spot `i` today** — three integers in memory, reset on restart. It is the
only shared state phase D adds, and it is exactly the thing `LOOPS.md`'s framing
asks for: *being near other players makes the hunt materially easier.*

| tier | text, built from the existing helpers | example |
|---|---|---|
| 1 | `"somewhere in " .. areaOf(lot, pos)` (`:2233`) | "somewhere in the shopping district" |
| 2 | `"on " .. streetOf(lot) .. ", by " .. thing(lot)` (`:2230`) | "on Birch Ave, by the FLORIST" |
| 3 | `compass(lm.pos, pos) .. " of " .. lm.name .. ", " .. tier2` (`:2214`, `:2222`) + **GO enabled** | "south-west of the School, on Sunny St, by a house" |

`thing(lot)` = `lot.name` where it exists (shop / midrise / corner / venue lots
all carry one, `Places.lua:307-348`), else by `lot.kind`:
`house`/`rowhouse` → `"a house"`, `apartment` → `"the apartments"`,
`jobcentre` → `"the Job Center"`, `workplace` → `lot.name`, anything else →
`"a doorway"`.

**Tier 2 is the shareable string.** "on Birch Ave, by the FLORIST" is what a
player types in chat, and it is the tier a player reaches after one find or
after one *other player's* find. That is not an accident — it is the reason the
tier function includes `foundHere`.

**Tier 3 enables the GO row, pointing at `lot.door`, never at `pos`.** Reuses
the beacon / green-dot path that `LOOPS.md` §1 says comes for free. The exact
position stays server-held until the player is within `Hunt.Reveal` (90 studs),
via the same `secret`/`reveal` mechanism as phase A (`:2374`, `:2800-2805`). So
a script reading the remotes from across town learns a street name, not a
coordinate.

### D8. The reward curve

All coins are **base**, through `pay(player, s, ..., "Hunt")` so passes multiply
them like any other find and the meter credits them like any other work.

| find | base coins | XP | plus |
|---|---|---|---|
| 1st | 60 | 15 | — |
| 2nd | 90 | 20 | — |
| 3rd | **150** | 60 | **1 capsule ticket** |
| first finder of a spot on this server today | +40 | — | the feed line |

**300 base coins for the whole hunt** — at phase A's measured pass stack that is
**1,350** on an account holding every pass (`HANDOFF.md` §5 records 460 → 2,070,
i.e. ×4.5), up to **1,688** at the maximum ×5.625 (1.5 CITY PRO × 1.25 VIP × 2
COINS × 1.5 streak). **The ticket is not multiplied by anything.**

Why this is inside §6's guardrail:

- 300 base coins over a realistic 4-8 minute first-time hunt = **38-75
  coins/min**, a fifth to a third of the job rate. A player who was *told* all
  three does it in 90-150s for 120-200 coins/min — still under 187, and that
  speed is the social payoff, not a leak.
- **The ticket is the reward, and it is NOT cosmetic.** The first draft leaned on
  `LOOPS.md` §6's exemption — *"Rare-Sminski collectibles are cosmetic … so they
  can be generous without touching the coin economy"* — and that exemption does
  not cover capsules. `Config.Passives` (`Config.lua:409-425`) gives all 15
  characters a live passive, `Secret` being `coin = 2`. §6 has been corrected to
  distinguish the two cases: a **rare sighting** recorded in `data.City.spotted`
  genuinely is cosmetic and keeps the exemption; a **capsule character** does
  not. So the hunt's third-find reward is justified by the *rate limit* (one per
  UTC day, hard) and by the existing precedent below — **not** by an exemption it
  does not qualify for.
- **Precedent.** `Config.Daily` day 5 is already a free capsule, granted by
  `ClaimDaily` at `:595-597` for the act of logging in. The Daily 3's ticket is
  the same gift on the same once-a-day cadence, for doing considerably more.
- It is granted **once per UTC day, hard**, keyed off `c.hunt.day`.

The hunt's ticket is granted even at `DayCap`, and even at `MaxTickets` (see the
invariant in D5). A once-a-day reward that silently does not arrive is worse
than any cap it protects.

### D9. Resolving the Daily 3 against phase A's ambient sighting

Two systems hiding a Sminski in the street is a real confusion risk and the
brief is right to ask. Resolved on four axes; the mechanical ones matter more
than the visual one.

**Mechanically separate, so neither can regress the other:**

1. The Daily 3 are **not events**. No `uid`, not in `live`, no `endT`, not in
   `publicEv`, never in the countdown strip, never in `lastHeadline`, invisible
   to `headline()` (`CityEvents.lua:307`) and `headlineLive()`. They get their
   own phone section.
2. **Different saved data, no overlap.** A sighting writes
   `data.City.spotted[skinId]` (`:2748-2752`) — a *skin* collection. The hunt
   writes `data.City.hunt` — a *per-day* found set. Neither reads the other.
3. **They can never be within 12 studs** of each other: D4's two exclusion
   checks, in both directions.
4. Different radii: hunt reveal 90 / claim 12, vs `RevealRadius = 130` /
   `ClaimRadius = 16` (`Config.lua:1007-1008`). A hunt Sminski appears later and
   must be approached closer, which is what makes it feel hidden rather than
   parked.

**Visually separate, with zero new art** — the same trick phase A used:

| | Ambient sighting | Daily 3 |
|---|---|---|
| model | `buildSminski` at scale 1 | `buildSminski` at **scale 0.5** |
| skin | one of 15 whole-body skins, rarity-bucketed | always `"none"` — the plain body |
| pose | its skin's idle | always the `hide` idle (`Config.Characters` `idle = "hide"`, `Config.lua:81`) |
| icon | `star` | `capsule` (an existing icon, `UI.lua:742`) |
| reads as | *a stranger in a costume you want to meet* | *a small plain Sminski hiding* |

All three hunt Sminski look **identical to each other and identical every day**,
which is what makes the category learnable at a glance. The one thing that must
be verified in Play: `buildSminski` at 0.5 sitting on the pavement at
`y = 0.45`. Phase A's `PUP_Y` bug (`LOOPS.md` §9: the pup hovered 1.83 studs
because a constant was copied from the hub's floor height) is exactly this
mistake, and the fix is to measure world-space min Y from part corners, not to
copy a number.

### D10. Session shape

| | with phase D in the game |
|---|---|
| **3 minutes** | No meter ticket — 10 minutes is a deliberate floor. What a 3-minute session *does* get: the hunt at 0/3 with three district clues, a reasonable chance at one find if a spot is near the route, and a meter notch that visibly moves on the very first payout (~60s in). **This is the weakest part of the design and I will say so:** `Places.CitySpawn` is `V(0,0,-955)`, the far south edge, and the three spots are ≥500 studs apart across a 2000-stud city, so a 3-minute session can honestly end 0/3 with a 15%-full meter. The mitigation is visible-progress-in-60-seconds, not a shortened hunt. |
| **15 minutes** | One meter ticket, one mall trip, 1-2 hunt finds. The phone has an unfinished 1/3 or 2/3 on it at logout — which is the hook. |
| **60 minutes** | 5-6 meter tickets + the hunt's 1 = **6-7 capsules**. Two or three mall trips, because 3 banked is the cap. About 7% of the 15-character collection per hour early on. |
| **the long arc** | A full collection is a weighted coupon-collector problem dominated by Secret at 2% (`Config.lua:69`) — roughly **60-80 rolls**, so ~10-12 hours of active play to complete the collection for free, or 24,000-32,000 coins to buy it. That is the retention arc phase D is actually selling. |

### D11. Social: 1, 5 and 20 players, and an empty server

**Phase D has no `minPlayers` anywhere, and that is the right answer to "a
social mode that starts with nobody in it is a bug."** It is the *personal*
layer `LOOPS.md` §3 asks for — always available so a player is never waiting on
the director — and its social value is emergent rather than gated.

- **Empty server.** The three spots are a pure function of the date; they exist
  whether or not anyone is there. Nothing waits, nothing is scheduled, no
  timer starts on the first join.
- **1 player.** Everything works. Clue tiers advance on your own finds, so a
  solo player always reaches tier 3 on the last spot (2 found → tier 3). Solo is
  slower, never blocked.
- **5 players.** `foundHere[i]` starts tightening clues; the feed carries "Ari
  found the Downtown Sminski"; the mall sees repeat ticket traffic. A player who
  joins at 2/3-found-by-others gets tier 3 immediately — a late joiner on a busy
  server is *rewarded*, not penalised.
- **20 players.** All three are found within a couple of minutes of the first
  finder and the hunt turns from a search into a race to be first. That is why
  `FirstHere = 40` base coins exists: on a full server there is still a prize,
  and it is small enough (40 coins) that missing it costs nothing.

The honest limit: the meter itself is private, and a private meter is exactly
what this project's core finding warns about. Its two social properties are
(a) redemption happens at one machine in one building, so ticket holders
converge, and (b) `feed()` already announces Epic and Secret pulls
(`:568`), so somebody else's good luck is visible. **If phase A+B did not move
"time near another player", the meter will not move it either** — the meter is a
*retention* device, and the hunt is the social one. Which brings us to:

### D12. What is conditional on A+B having worked

`LOOPS.md` §7 gates C-G on session length moving after A+B, and that
measurement does not exist. Designed anyway, and here is the split:

- **Not conditional.** The meter and the hunt both stand on their own as
  return-and-retain mechanics. They do not need events to be popular; they need
  *earning* to happen, which it already does. If A+B turn out to be duds, phase
  D is the part of the plan that still works, because it is attached to jobs.
- **Conditional.** The clue-tier acceleration from `foundHere` only pays off if
  servers actually have several concurrent players in the city. On a
  one-player-per-server game it is dead code that costs three integers. Ship it
  anyway at that price, but do not count it as a win.
- **Conditional, and worth cutting if A+B failed.** The 34-second walk to
  Capsule Corner is justified by "you will meet someone there". If A+B prove
  the city is empty, that walk is pure friction and the right change is to let a
  ticket redeem from the SHOP button. **Do not build that switch now; note that
  it is one `near()` call to remove.**

### D13. Where it sits in the city

No new geography, no new art, no new place.

- Hunt spots: the `+2.5` door strip on the existing 381 `streetLots`.
- Redemption: `Places.MallShops[2]`, `V(536, 0, 168)`, which already has a
  prompt (`City.lua:2236-2241`) and already sits in the mall block `"450,150"`.
- Meter and hunt UI: the existing HUD and the existing PHONE modal.
- The only new visual is `buildSminski` at a new scale in an existing skin.

Inside the downtown-slice scope: the spots span the whole built city, which is
already built.

---

## NUMBERS

### N1. `Config.Meter` — new table, appended after `Config.Events`

```lua
Config.Meter = {
    Ticket       = 1870,  -- units for one ticket = 10 x PerMin. Ten minutes at
                          -- the reference rate, and the constant says so.
    PerMin       = 187,   -- the ceiling: max units credited per rolling minute.
                          -- Set to LOOPS.md section 6's reference job rate, so
                          -- the fastest possible ticket is exactly 10 minutes
                          -- and the best ticket-farming strategy is working.
    Burst        = 187,   -- max bankable allowance = one minute's worth, so a
                          -- single fat payout (a 363-coin fare) counts in full.
    MaxTickets   = 3,     -- banked, unredeemed. The cap that forces the mall
                          -- trip; c.tickets may reach 4 via the Daily 3.
    DayCap       = 12,    -- tickets GRANTED per UTC day, both sources. 120
                          -- ceiling-rate minutes: a circuit breaker on a
                          -- scripted account, not a brake on a real session.
    Redeem       = 14,    -- studs: the client prompt radius. Matches the
                          -- existing Capsule Corner prompt (City.lua:2237).
    RedeemServer = 18,    -- studs: the server check, wider for latency and
                          -- streaming. Same pattern as PickupRadius 6 /
                          -- PickupServer 9 in phase B.
    Version      = 1,     -- unit-scale version. On mismatch: clear `meter`,
                          -- KEEP `tickets`.
    -- A WHITELIST. One unit per base coin. A stat tag that is absent credits
    -- ZERO -- including every stat tag added after this was written.
    Rates = {
        Deliveries = 1, TaxiFares = 1, Sweeps = 1, CityHarvests = 1,
        JobTasks   = 1, EventsDone = 1, Races    = 1, Hunt         = 1,
        -- DELIBERATELY ABSENT, do not add:
        --   BizCollects  idle business income (server :1737 and :1950)
        --   HomeNaps     a once-per-20h gift (server :1841)
        --   (nil)        the claw's payout (server :1773) -- a machine that
        --                hands out capsules must not fill the capsule meter
        --   award()      the Endless Run never calls pay() at all (server :431)
    },
}
```

### N2. `Config.Hunt` — new table, appended after `Config.Meter`

```lua
Config.Hunt = {
    Count     = 3,
    Spread    = 500,   -- min studs between any two of today's spots. Forces a
                       -- real trip across town; > one block + road (300).
    Reveal    = 90,    -- the model is only sent to players this close (events
                       -- use 130; tighter here because it is small and hidden)
    Claim     = 12,    -- claim radius. At 16 you could claim from the door
                       -- without spotting it; at 12 you must step to the
                       -- right side of the door.
    Scale     = 0.5,   -- buildSminski scale. Distinct from a sighting's 1.0.
    Skin      = "none",-- plain body, so it is never mistaken for a sighting
    Icon      = "capsule",
    Coins     = { 60, 90, 150 },  -- BASE coins for the 1st / 2nd / 3rd find
    Xp        = { 15, 20, 60 },
    FirstHere = 40,    -- extra BASE coins for the first finder of a spot on
                       -- this server today
    TicketAt  = 3,     -- which find grants the ticket
    Retries   = 6,     -- pickSpot() attempts before it accepts a hunt lot
}
```

### N3. Saved data — exact shape

All inside the existing `data.City` table, created lazily in `saved(s)`
(`:1477-1489`) with the same `type(...) ~= "table"` idiom. **No
`defaultData()` change. No migration. No `reconcile()` change.**

```lua
c.meter           = 0             -- integer units, 0 .. Meter.Ticket - 1
c.tickets         = 0             -- banked tickets, 0 .. 4 (see the invariant)
c.meterDay        = "2026-09-21"  -- UTC dayKey that meterDayTickets belongs to
c.meterDayTickets = 0             -- tickets GRANTED on meterDay, vs DayCap
c.meterV          = 1             -- = Config.Meter.Version
c.hunt = {
    day    = "2026-09-21",        -- UTC dayKey; a different key means reset
    found  = { false, true, false },  -- DENSE 3-element array, index = hunt 1..3
    streak = 4,                   -- consecutive UTC days completed 3/3
    lastFull = "2026-09-20",      -- last day completed, for the streak test
}
```

Rules the builder must not get wrong:

1. **`c.hunt.found` is a DENSE three-element boolean array, and this is a
   save-corruption bug, not a style preference.** The first draft of this spec
   wrote `found = { [1] = true, [3] = true }`. A sparse integer-keyed Lua table
   does **not** round-trip through the DataStore: it is JSON-encoded as the object
   `{"1":true,"3":true}` and comes back with **string** keys, so `found[1]` (a
   number) reads `nil` and a player who rejoins at 2/3 sees **0/3** and can claim
   all three again. Found by `ux-designer`. The fix is to always write all three
   slots:
   - initialise as `{ false, false, false }`, never `{}`;
   - set `c.hunt.found[i] = true`, never insert;
   - on load, coerce defensively — if `type(found) ~= "table"` or `#found ~= 3`,
     rebuild it as `{ false, false, false }`. A dense array of three booleans
     encodes as the JSON array `[false,true,false]` and round-trips exactly.
2. **The index is the hunt slot 1..3, never a lot index.** Nothing
   in phase D persists a lot index. `assignHouse` does, which is why
   `Places.cityLots()` is append-only (`Places.lua:280-282`) — phase D stays
   out of that hazard entirely.
3. **Nothing else in phase D may be a sparse table either.** `c.hunt.found` is
   the only list-shaped field in the design, but the same JSON round-trip applies
   to anything added later: string keys survive, sparse integer keys do not.
4. **The meter must not trigger a save.** It moves inside `pay()`, dozens of
   times a minute; `pay()`'s own `defer` argument and `flushPay` (`:227`,
   `:1521-1541`) already decide when a write happens, and the DataStore budget
   is ~60 + 10 per player per minute for the whole server (`:1516`).
5. **A ticket grant and a ticket redemption each write** (`task.spawn(save, player)`).
   400 coins of value must not be lost to a crash. That is at most ~8 extra
   writes per player-hour.
6. **Schema change:** if `Ticket` or the unit scale ever changes, `c.meterV ~= Config.Meter.Version`
   → set `c.meter = 0`, **keep `c.tickets`**, set `c.meterV`. Losing partial
   progress on a retune is acceptable; losing a banked ticket is not.
7. `c.hunt.streak` is computed the way `refreshLogin` computes the login streak
   (`:313-321`): on completing 3/3, `streak = (lastFull == yesterday) and streak+1 or 1`.
   **Nothing rewards it in phase D** — it is one integer now so that a later
   phase has the history, per this project's append-only habit.

### N4. What a ticket is worth, and what it does to the economy

**The mistake to avoid: a ticket is not 400 coins of inflation.** It is several
different numbers that differ by orders of magnitude, and the *refund* ones below
are only half the story — read the passive term that follows them before quoting
any of this.

| | number | how |
|---|---|---|
| **Sticker value** | 400 coins | `Config.CapsuleCost`. What the player feels they got. |
| **Minted coins, first ~10 rolls only** | **7.44 coins** | only duplicates mint coins. Owning Glow alone: `0.62 × (1/5) × 60` = 7.44 expected. |
| **Minted coins, mid-life (the typical case)** | **69.6 - 92.1 coins** | most of each rarity pool owned, the tail not. **Quote this range, not 7.44** — 7.44 evaporates after the first handful of rolls. |
| **Minted coins, complete collection** | **104.1 coins** | everything is a duplicate: `0.62×60 + 0.27×120 + 0.09×250 + 0.02×600`. This is the ceiling, forever. |
| **Sink displaced** | up to 400 coins | a player who would have *bought* a capsule now does not. A demand reduction on a sink, not new coins. |

All four reproduced independently by `monetization-designer`. The 7.44 figure is
the one to be careful with: it is true for a brand-new account's **first ~10
rolls** and is not a typical number. **69.6-92.1 is the honest middle** of the
*refund* term.

#### The refund term is not the whole value — corrected

**Everything above counts only duplicate refunds, because the first draft of this
spec believed capsule characters were cosmetic. They are not** (see WHAT EXISTS
ALREADY, and `Config.Passives` at `Config.lua:409-425`). A ticket is also a 2%
lottery ticket on `Secret` / Golden, whose passive is `coin = 2` — *every coin in
a run worth double*. So, from `monetization.md` Addendum A:

```
E[ticket] = E[refund]  +  0.02 x R_future
            ^^^^^^^^^     ^^^^^^^^^^^^^^^
            capped at     UNBOUNDED: scales with the player's
            104.1 coins   remaining lifetime RUN income
            forever
```

| player's remaining run income | E[ticket] | vs the 69.6-92.1 I published |
|---|---|---|
| 0 (never runs; city-only) | 69.6 - 92.1 | — |
| 10,000 coins | ~270 - 292 | 3-4× |
| **50,000 coins** | **~1,000** | **11-14×** |
| 200,000 coins | ~4,070 | 44-58× |

> **Say it plainly: the 69.6-92.1 figure understated the value of a free ticket,
> by an order of magnitude for any player who runs.** The refund term is bounded
> and I bounded it correctly; the passive term is unbounded and I did not know it
> existed. The corrected model is the one above.

Three things that are still true and keep this from being a crisis:

1. **It is confined to the runner.** No city code reads `Config.Passive`, so
   nothing here changes city job income — the 187 coins/min reference rate, the
   ceiling and the whitelist are all untouched.
2. **`award()`'s clamp bounds it.** Run coins cap at `distance * 0.35 * 2 + 50`
   (`:419-420`), so Golden cannot bank more than 0.7 coins/stud and Golden +
   Doubler is already truncated.
3. **`R_future` is only large for a player who keeps playing**, which means the
   term is largest exactly where it costs least to be generous.

**`Secret.coin = 2` is being kept — a documented choice, not a defect.** The
human considered neutralising it and chose not to, so a purchasable run-coin
advantage remains **by design**. Two related decisions for the record: the
distance leaderboard is being made passive-neutral (7 of 15 passives extend
survival, so Robux bought all-time rank) — assigned to `server-engineer`, not
phase D — and nothing else in `Config.Passives` changes.

#### What this does to the give-away rate

`Ticket = 1870` still ships (the human's call: tune after measuring). But what
the rate governs has changed, and a future tuning pass needs to know it:

> At ~6 tickets a day, a committed player holds **Golden in ~5.7 days without
> ever choosing to chase it** (`monetization.md`). So `Ticket` is no longer a dial
> on how fast players collect *costumes* — it is a dial on how fast they acquire
> an **economic advantage in the runner**. The 10-minute target was chosen to
> protect the city's coins/min, and it still does that correctly; it was not
> chosen with a 2%-per-roll shot at `coin = 2` in mind, and nobody should assume
> it was.

The honest consequence: the *upper* bound on a sensible `Ticket` value is now set
by two different things at once — city coin inflation (which says 1,870 is safe)
and time-to-Golden (which says 1,870 gives it away in under a week). If those two
ever conflict, they are not the same trade-off and should not be resolved with
one number. That is a tuning question for after the first measurement, flagged
here so it is not rediscovered later.

**Checking the brief's 21%.** One ticket per 10 active minutes = 40 coins/min of
sticker value against 187 coins/min of income = **21.4%**. The brief's
arithmetic is right. What it understates is that the 21.4% is *sink
displacement*, and the actual new coins entering the economy are (**refund term
only — the passive term above is a runner effect and does not belong in a
city coins/min figure**):

| | coins/min minted | as % of the 187 job rate |
|---|---|---|
| brand-new account (first ~10 rolls), one ticket / 10 min | 0.74 | **0.4%** |
| **mid-life account, one ticket / 10 min** | **7.0 - 9.2** | **3.7% - 4.9%** |
| complete collection, one ticket / 10 min | 10.4 | **5.6%** |
| complete collection, one ticket / **5** min | 20.8 | 11.2% |

**At 6 players, all at the ceiling** (a fiction: it needs all six earning 187+
base coins/min continuously):

| | per minute, server-wide |
|---|---|
| tickets granted | 0.6 |
| sticker value handed out | 240 coins = **21.4%** of the server's 1,122 base coins/min |
| coins actually minted, all brand-new accounts | 4.4 (**0.4%**) |
| **coins actually minted, all mid-life accounts** | **42 - 55 (3.7% - 4.9%)** |
| coins actually minted, all complete collections | 62.5 (**5.6%**) |
| `wcaps` weekly-challenge leak | **280 coins/week expected per player**, not 800: the challenge is drawn 2 weeks in 5 (`Config.ChallengeCounts.weekly = 2` from a 5-row pool, `Config.lua:499-507`), and only the first 3-5 tickets of a drawn week count. `monetization-designer`'s number, and the one the human decided on. |

**So §6's conclusion holds for the city's coin economy, which is what §6 is
about.** At 5 minutes a ticket the sticker figure is 42.8% — §6's "roughly a 40%
raise", confirmed. At 10 minutes it is 21.4%, and the *binding constraint is sink
displacement rather than inflation*. The thing that gets worse over an account's
lifetime is the minted-coin figure — 0.4% for the first handful of rolls,
**3.7%-4.9% for most of an account's life**, 5.6% once the collection is complete
— and 5.6% of the job rate is not worth a mechanism. Read the mid-life row, not
the 0.4% one; 0.4% is the reassuring end of the range and it is not typical.

**What does *not* hold is §6's reason for being relaxed about capsules.** §6 said
they were cosmetic and therefore free to give away; they are not, and §6 has been
corrected. The city arithmetic in this section survives that correction intact,
because the passive term lands in the runner. **The give-away rate is justified
by the city numbers and by the ~5.7-day time-to-Golden being an accepted
consequence — not by a cosmetics exemption.**

**Duplicates on a free roll — the decision.** `rollCapsule` is left exactly as
it is (`:558-565`), refund included. A duplicate from a free ticket therefore
mints coins, expected ≤104. The alternatives were halving the refund or zeroing
it; both mean a branch inside the one function that the paid path, `ClaimDaily`
(`:596`) and the claw (`:1757`) all call, and zeroing it makes a gift read like
a punishment. **Worst case is 104 coins × 12 tickets = 1,250 coins a day for a
player who has finished the collection — under seven paced minutes of work, for
a player with no capsule sink left anyway.** Not worth the risk of editing
shared code.

### N5. Restricted players — REJECTED, do not build

The first draft of this spec specified a 240-coin substitute for players where
`ArePaidRandomItemsRestricted` is true. **That was wrong and it is withdrawn.**
`monetization-designer` found the error and the lead confirmed it:

1. **The ticket path is exempt from the policy in the first place.** The policy
   covers *paid* random items. A ticket is earned by playing — no Robux, and not
   even coins — so `Config.CapsulesArePaid` does not reach it. The flag exists
   (`Config.lua:55-59`) for the day coins become purchasable, which would make
   the **400-coin** path paid-random. It would not make a free ticket paid.
2. **A free-play route to a random item is Roblox's own first-listed remedy for
   restricted players.** Substituting coins denies them the exact remedy the
   policy points at.
3. **It was 2.3× more inflationary than everyone else's stream.** 240 minted
   coins per ticket against a mid-life 69.6-92.1 — so the "safe" option was the
   only one that actually inflated.

> **Therefore: `"capsuleTicket"` does not check `s.capsulesRestricted` and does
> not check `Config.CapsulesArePaid`. Step 4 of D5's redemption sequence is
> deleted.** The paid path at `OpenCapsule` (`:532-534`) keeps its check,
> unchanged.

This is the one place phase D deliberately diverges from `OpenCapsule`'s guard
list, so it is written down here rather than left as an omission for someone to
"fix" later.

### N6. The Daily 3, timed

| | |
|---|---|
| time to find all three, first time, no help | **4-8 min** (three spots ≥500 apart, car at 76-115 studs/s, tier 1-2 clues) |
| time to find all three, told all three | **90-150s** |
| base coins for the whole hunt | 300 (= 38-75 coins/min first time, 120-200 if told) |
| the same, on an account with every pass | 1,350 at phase A's measured ×4.5; 1,688 at the max ×5.625 |
| tickets | 1, per UTC day, hard |
| reset | UTC midnight, the same boundary as `refreshChallenges` (`:104`) and `refreshLogin` (`:314`) |

---

## EDGE CASES

**Empty server.** The three hunt spots are a pure function of the UTC date, so
they exist with nobody connected. No timer starts on first join. The meter is
per-player and irrelevant. Nothing in phase D has a `minPlayers`.

**One player.** Clue tiers advance from their own finds (2 found → tier 3 on the
last), so solo is slower and never blocked. `foundHere[i]` stays 0 and
contributes nothing — a no-op, not a stall.

**A scripted player.** Covered at length in D5. Summary: the best line in the
exploit table fills at 187 units/min, which is the ceiling, which is also the
best way to earn coins — so a script buys nothing. Every whitelisted payout is
already position-checked and, where it matters, pace-floored, and the City
remote is already limited to ~8 calls/s by `allow(s, "City", 0.12)` (`:1591`).
Three specific loops were checked and none beats 10 minutes: taxi (ceiling),
sweep (16-21 min), farm (11.7 min, and the 60×70 plot grid means **no standing
position reaches two plots** at radius 28).

**An AFK player.** Zero units. The only two payouts reachable without moving are
`BizCollects` (both sites) and `HomeNaps`, and both credit 0 by whitelist.
Allowance accrues while idle; units do not, because allowance is a ceiling and
not a currency.

**Mid-hunt join.** Same three spots, tier 1 from your own progress, **plus the
server's `foundHere` tiers immediately**. Joining a server where two players
already found spot 2 hands you tier 3 on it. Intended.

**Mid-hunt leave.** `c.hunt.found` is per-day and saved, so progress resumes on
any server, including a different one.

**UTC day rollover mid-hunt.** Detected in the shared 1 Hz loop (`:2778`). On
change: recompute the three spots; broadcast `"huntReset"`; clear every
connected player's per-day found set; **remove and redraw the models**; reset
`foundHere` to 0. **Progress is not carried over** — 2/3 at 23:59:59 becomes
0/3. That is deliberate: grandfathering means two players on one server hunting
different spots, which destroys the shareability the feature exists for. The
mitigation is a warning, not a grace period: the phone shows
`new ones in 0:14` under 30 minutes, using the arithmetic `refreshChallenges`
already does for `c.dayEnds` (`:116`).

**A claim landing exactly at rollover.** The claim recomputes `dayKey` at the
top, before testing the found set, and writes the reward against the key it just
computed. No double reward, because `found` is keyed by the day.

**Server restart mid-day.** Spots recompute identically — that is what the hash
seed buys. `foundHere` resets to 0, so clue tiers drop back to whatever each
player's own progress gives them. Acceptable and worth knowing.

**Two servers on the same day.** Identical spots. The single thing that breaks
it is a **deploy that changes `Places.cityLots()` mid-day**: `streetLots` is
built at server start, so old servers keep old spots. The per-lot hash keeps the
damage to ~0.8% per appended lot, but the correct answer is a release note —
do not ship a lot-list change mid-day — not a code change.

**Tickets banked at `MaxTickets`.** The meter parks at `Ticket - 1` and stops;
at most one unit is lost. The player is told (it is actionable). The Daily 3
still grants, so `c.tickets` may reach 4. **Do not clamp it to 3.**

**`DayCap` reached.** The meter stops; the Daily 3 still grants.

**A complete collection.** Every roll is a duplicate: 104 expected coins, no new
character — and no further passive upside, since the player already holds Golden.
So the *most* coin-inflationary account is also the one where a ticket has the
*least* total value. Phase D does nothing special; noted for
monetization-designer as the one case where the meter measurably mints coins.

**Claiming a hunt Sminski from a car.** Allowed — the check is distance only.
Forcing a dismount is friction nobody asked for.

**Redeeming while the mall is streamed out.** `cityPos` returns nil without a
character and the existing `"you're not in the city"` guard (`:1601`) catches
it. Note the streaming gotcha from `HANDOFF.md` §2 for QA: teleport and wait ~3s
before measuring anything near the mall.

**A hunt spot landing on a live collect item or FIND spot.** Impossible by the
two exclusion checks in D4; the 12-stud number is reused from the contract,
which found the 0.5-stud collision analytically before it shipped.

**`rollCapsule` yielding.** It calls `task.spawn(save, player)` at `:566`.
Decrement the ticket **before** calling it, or a save landing between roll and
decrement persists a spent ticket as unspent.

---

## NEEDS FROM OTHER LANES

1. **`server-engineer`** — everything in D5, D6, D7, N1, N2, N3 and the two
   exclusion checks in D4. `Config.lua` (two new tables, appended, nothing in
   `Config.Events.List`), `SminskiServer.server.lua` (`meterAdd` above `pay`,
   the `pay()` hook, `"capsuleTicket"` on the `City` remote, the `Hunt` block
   beside the director, the shared reveal-loop pass). **`rollCapsule`,
   `OpenCapsule`, `Config.Events.List` and the director's schedule are not
   touched.**
   Two traps, both of which have already bitten this project:
   - `HANDOFF.md` §3 (six bugs in one session had this shape): **`meterAdd` is a
     `local function` and is invisible to code written above it** — it must be
     declared after `saved(s)` (`:1477`) and before `pay()` (`:1521`).
   - **`c.hunt.found` must be a dense 3-element boolean array.** A sparse
     integer-keyed table does not survive the DataStore JSON round-trip and a
     rejoining player would read 0/3 and re-claim the whole day's reward. N3 rule
     1 has the coercion to write on load.

   **Not phase D:** making the distance leaderboard passive-neutral is assigned to
   you separately. It is the right fix and it is not this feature's to make.
2. **`client-engineer`** — the hunt's drawing, prompt and phone section in
   `CityEvents.lua` (reusing `draw`/`mark`/`undraw`/`E.prompt` shapes but on its
   own list, never in `E.list`), the meter readout, and the Capsule Corner
   prompt branch in `City.lua`. The reply from `"capsuleTicket"` is
   `rollCapsule`'s own table, so `UI.playCapsule(res)` works unchanged. **Do not
   use `UI.toast` / `UI.popText` / `UI.banner`** — they do not render in the
   city (contract §9, still unfixed and still unowned).
3. **A telemetry owner, and this is the real dependency.** There is no
   analytics in the repo. §M cannot be answered without something that logs, at
   minimum, session length and one counter per stat tag. Phase D ships without
   it; §6's "tune from data" cannot.
4. **Art: none.** No Blender, no review gate, no `Props.lua` entry. The hunt
   Sminski is `buildSminski` at 0.5 in the `none` skin; the icon is the existing
   `capsule`.

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **Interior hunt spots** ("the mall one is behind the escalator", `LOOPS.md` §3) | Needs the hand-placed `Places.CityHideSpots` list that `LOOPS.md` §2 anticipated and phase A never built, plus per-spot clearance measurement in Play for every entry. The street-door strip is measured and free. The hunt *index* survives the change, so adding interior spots later is a bigger candidate pool and not a new feature. |
| **A reward for `c.hunt.streak`** | A 7-day streak reward is a strong hook and a money/taste call (what item, what value). The counter ships now at the cost of one integer; the reward waits for the human. |
| **Meter fill from the Endless Run** | `award()` (`:411`) never calls `pay()`, so the runner is excluded for free. Including it means a parallel hook and a second balance argument, and the runner already has its own reward loop. Flagged as an open question because it is a business call about who gets free capsules. |
| **An explicit pass multiplier on the meter** | Two passes already shorten time-to-ticket indirectly, by up to 2.1× on sweeping and 0× on taxi and deliveries (D5) — and the ceiling keeps that honest, because a pass can only close the gap up to 187/min and never cross it. An *explicit* `meterMult` would cross it, which makes the 10-minute target meaningless and turns a Robux purchase into a direct accelerator on a random-item roll. monetization-designer's call, with that distinction attached: **indirect acceleration is bounded by the ceiling; a multiplier is not.** |
| **Trading or gifting tickets** | Immediately becomes an alt-account funnel — and now that capsules are known to carry passives (`Config.Passives`), it would be a funnel for *gameplay advantage*, not costumes. Firmly out. |
| **A "capsule opened together" bonus for two players redeeming within 30s** | I wanted it; every version either hands out extra rolls (economy) or extra XP (progression) for standing next to someone, which is farmable with an alt. The co-location is the reward. |
| **Surfacing the per-minute ceiling** | D5: it can only fire on a player already filling at the maximum rate, so the message is a punishment notice for playing well. |
| **A second `task.spawn` for the hunt** | `performance.md`. The 1 Hz reveal loop already iterates; the hunt is one extra pass over three spots. |

---

## REQUESTS FOR OTHER OWNERS

### For `ux-designer` — what you inherit from me

- **The numbers are fixed:** `Ticket = 1870` units, ceiling `187`/min,
  `MaxTickets = 3`, `DayCap = 12`, ticket redeemed within `14` studs of
  `V(536, 0, 168)`.
- **The meter needs no new remote and no new payload.** `publicData(s)`
  (`:324`) clones `s.data`, so `data.City.meter` and `data.City.tickets` already
  arrive on every reply your client already handles. Read `meter / 1870` for the
  fill and `tickets` for the count.
- **The fill is bursty, not smooth.** It moves in jumps of 60-250 units when a
  payout lands, and does nothing in between. A smoothly-creeping bar would be a
  lie. It also sometimes jumps *less* than the coins just earned (the ceiling) —
  which is why I decided **not** to show the ceiling state at all; please do not
  add it back.
- **Two states you do need:** `tickets >= 3` (actionable: "go to the mall") and
  `tickets >= 1` (the redeem affordance exists somewhere).
- **The Capsule Corner prompt is a one-button widget.** `setPrompt(title, sub,
  btn, icon, action, at)` (`City.lua:1750`) has exactly one button, and today it
  is `BROWSE` → `UI.openShopTab("capsules")` (`City.lua:2238`). My
  recommendation: when `data.City.tickets > 0`, the button becomes
  **`USE TICKET (n)`** and BROWSE stays reachable from the SHOP HUD button. One
  branch, no new widget, and it makes the machine visibly the ticket's home.
  Overrule me if you want two buttons, but then the two-button prompt is a
  request on `client-engineer`.
- **The hunt gets its own phone section, not an event row.** Three rows,
  `0/3` header, the clue text at the player's current tier, a `resets in 6h 12m`
  line that goes prominent under 30 minutes, and a GO button that is **disabled
  below tier 3** and targets `lot.door` (never `pos`).
- **Tier 2's string is designed to be typed into chat** ("on Birch Ave, by the
  FLORIST"). Make it selectable/legible, not truncated.
- **Reward moment:** `"capsuleTicket"` returns `rollCapsule`'s exact table, so
  `UI.playCapsule(res)` (`UI.lua:1211`) plays unchanged — you should need **no
  new reward UI at all**, only the ticket-granted notification.

### For `monetization-designer` — what you inherit from me

*(Rewritten twice after `monetization-designer`'s reviews. Their corrections are
folded into WHAT EXISTS ALREADY, D5, D8, N4 and N5 — four of the five were things
this spec got wrong, and the biggest one invalidated the premise the whole
give-away rested on. The notes below are what is left for them.)*

- **The coin multipliers are meter-neutral; the movement passes are not.** The
  meter is credited from the *base* amount before `pay()` applies CITY PRO /
  VIP / 2x COINS / the login streak (`:1523-1525`), and `rollCapsule`'s
  duplicate refund writes `s.data.Coins` directly (`:562`), bypassing `pay()`.
  But **QUICK FEET + DREAM GARAGE shorten time-to-ticket by up to 2.1× on
  sweeping and by 0× on deliveries and taxi**, because those two saturate the
  187/min ceiling on the free convertible already. **The ceiling is pass-proof;
  the floor is not.** Full table in D5. If you want to change that, the lever is
  which activities sit below the ceiling — not the ceiling itself.
- **The refund numbers in N4 are yours, verified:** sticker 400; minted **7.44**
  for a brand-new account's first ~10 rolls, **69.6-92.1 mid-life**, **104.1** at
  a complete collection; sink displaced up to 400. The brief's "21% raise" is a
  *sink displacement* figure and it is correct; **minted coin inflation is
  3.7%-4.9% of the city job rate for most of an account's life**, 5.6% at the
  ceiling.
- **But your Addendum A supersedes all of them, and I have folded it in.** My
  original spec asserted capsule characters were cosmetic, citing
  `Config.Characters` — and missed `Config.Passives` (`Config.lua:409-425`),
  which is a separate table giving all 15 a live passive including `Secret`'s
  `coin = 2`. `E[ticket] = E[refund] + 0.02 × R_future` is now N4's model:
  **~1,000 coins at 50,000 coins of remaining run income, 11-14× the figure you
  and I previously agreed.** The 69.6-92.1 range understated a free ticket by an
  order of magnitude for any player who runs. The refund term is bounded and I
  bounded it right; the passive term is unbounded and I did not know it existed.
- **The three mitigations, so you do not have to rederive them:** the passive is
  read only by `UI.lua` and the runner — **no city code touches it**, so the
  187 coins/min reference rate and everything built on it survives; `award()`'s
  clamp (`:419-420`) caps run coins at 0.7/stud, truncating Golden + Doubler; and
  `R_future` is only large for a retained player.
- **`Ticket = 1870` now governs how fast players acquire an economic advantage,
  not a costume** (~5.7 days to Golden at ~6 tickets/day, your figure). N4 records
  that the upper bound on `Ticket` is set by two different constraints at once —
  city inflation says 1,870 is safe, time-to-Golden says it is generous — and
  that they should not be resolved with one number if they ever conflict. That is
  yours to take further.
- **The meter competes with a Robux product.** A player who gets 6-7 free
  capsules an hour has less reason to buy coins to buy capsules — and the
  **COIN JAR (R$99, 7,500 coins) is still uncreated** (`HANDOFF.md` §6.2,
  `docs/STORE.md` §4). The free-capsule rate and the coin-jar price are the same
  decision, and you get to make it before the product exists. 7,500 coins = 18.75
  capsules = about 3 hours of meter.
- **One interaction to rule on:** `rollCapsule` calls
  `bump(s.data, "capsules", 1)` (`:567`), which progresses the weekly challenge
  `wcaps` "Open 3/5 capsules" for 600/800 coins (`Config.lua:503`). A free
  ticket therefore completes a challenge that used to require spending
  1,200-2,000 coins. **Expected cost 280 coins/week per player** (your figure —
  the challenge is drawn 2 weeks in 5, which my first draft missed and quoted as
  800), and the human has decided to leave it. Recorded so it is a decision and
  not an oversight.
- **The restricted-player fallback is withdrawn** — see N5 for the three reasons.
  The ticket path checks no policy flag at all.
- **The retention arc you are pricing against:** ~60-80 rolls to complete the
  15-character collection (Secret at 2% dominates), so ~10-12 hours of active
  play free, or 24,000-32,000 coins to buy.

### For `server-engineer` and `client-engineer`

See NEEDS FROM OTHER LANES. The two sentences that matter most: **nothing is
appended to `Config.Events.List` and `rollCapsule` is not modified.**

---

## QA SHOULD CHECK

Exploit-focused, measurable, and each one provable in Studio. `EventsDev`
(`:2892`) is the pattern for the hooks; add the three in item 11.

**The meter cannot be farmed:**

1. **Idle for 5 minutes** in the city, standing, sitting, in a car, HUD open,
   phone open. `data.City.meter` must be **unchanged, exactly**. Not "roughly"
   — read the integer before and after.
2. **`collectBiz` 10 times** with businesses owned (both call sites: the world
   prompt at `:1737` and the business card at `:1950`). Coins move by thousands;
   `meter` must move by **0**.
3. **`HomeNaps`** once, and the **claw** 10 times. `meter` moves by **0** both
   times.
4. **Sustained-rate ceiling.** Earn ≥600 base coins inside 60 seconds (three
   long taxi fares in a taxi, or the `EventsDev` cash drop swept fast). Credited
   units in that window must be **≤ 187 + Burst = 374**, and units credited over
   any 10 consecutive minutes must be **≤ 1,870**. *This is the single most
   important test in the list* — if it fails, the whole economy argument fails.
5. **Fastest possible ticket.** Play as fast as the game allows for 12 minutes
   and report the wall-clock seconds to the first ticket. **Expected ≥ 600s. If
   it is under 540s, stop and report — the ceiling is leaking.**
6. **Passes and the ceiling — run this on THREE named activities, not on
   whatever is convenient.** The naive version of this test ("same activity,
   clean account vs every pass, expect no difference") is wrong and would either
   pass trivially or report a false failure. What is actually true: the coin
   *multipliers* are meter-neutral, but QUICK FEET and DREAM GARAGE change how
   much work fits in a minute, and that legitimately fills the meter faster on
   any activity not already at the ceiling. So measure **units credited per 10
   minutes**, clean account vs an account holding every pass, on each of:

   | activity | expected | this is a FAIL if |
   |---|---|---|
   | **taxi**, long fares in a taxi | **1,870 ± 2% both times** (saturated on the free convertible already) | either run exceeds 1,870 in 10 min — the ceiling leaked |
   | **parcels** from the Job Center | **1,870 ± 2% both times** | either run exceeds 1,870 |
   | **sweeping litter** — the one that moves, so name it | clean ~900-1,200; with passes **up to ~1,870, i.e. up to 2.1×**. **The 2.1× is the PASS condition.** | the passed run exceeds **1,870** in 10 minutes, or the *clean* run somehow exceeds it |

   In every case the number to assert against is **1,870 units per 10 minutes,
   never exceeded**. A pass may close the gap to the ceiling; nothing may cross
   it. Also confirm separately that CITY PRO / VIP / 2x COINS / a live boost
   change `coins` by ~4.5× while changing credited `units` by **0** — that is
   the multiplier-neutrality claim, and it is a different test from this one.
7. **Banked cap.** Reach 3 tickets, then keep earning for 3 minutes. `tickets`
   stays 3, `meter` parks at **1869** and does not wrap. Redeem one → the next
   payout immediately grants the 4th.
8. **Day cap.** Force `c.meterDayTickets = 12` (dev hook) and earn. `meter`
   stops. Then complete the Daily 3: the hunt ticket is **still granted**, and
   `c.tickets` is allowed to reach 4.
9. **Rejoin does not reset progress or grant anything.** Note `meter` and
   `tickets`, leave, rejoin: both identical. Then confirm a full burst of
   allowance on rejoin does not by itself credit a single unit.
10. **Redemption is position-gated.** `City:InvokeServer("capsuleTicket")` from
    the Fun Park → refused, ticket **not** consumed. From 40 studs from the
    machine → refused. From 6 studs → one roll, one ticket consumed, the
    existing capsule animation plays, `data` in the reply has the new
    `tickets`/`meter`.
11. **Double-redeem race.** With exactly **1** ticket, fire two
    `"capsuleTicket"` calls concurrently (build this the way phase B's
    `raceTest` hook does, `:2901-2917`): exactly one `ok = true`, exactly one
    `rollCapsule`, `tickets` ends at **0** and never at -1.
12. **The whitelist is a whitelist.** Add a temporary `pay(..., "FakeStat")`
    call in Studio and confirm it credits **0** with no warning and no crash.

**The Daily 3:**

13. **Same three, two servers.** Read the three spots from two Studio sessions
    on the same UTC day. Identical X/Z to the stud, identical `side`.
14. **Same three after a restart.** Stop and restart: identical.
15. **Spread.** All three pairwise distances **≥ 500** studs.
16. **Clear by construction, measured — do not trust the formula.** For **6 or
    more** real hunt spots across several days (force the date via a dev hook):
    world-space min Y within 0.3 of the pavement top (`y = 0.45`), not inside the
    facade plane, open sky above. Compute min Y **from part corners**, not
    `GetBoundingBox()` (`HANDOFF.md` §2). This is where phase A lost two rounds
    (the pup at 1.83 studs, 7 of 8 spots inside a shop window) and a `Scale =
    0.5` rig is a new number that has never been on the pavement.
17. **Never colliding with an event.** Start a collect event centred near a hunt
    spot (`EventsDev(id, atMe)`), read the `items` reply, and confirm **every**
    item is ≥ 12 studs from all three hunt spots. Then start 20 ambient
    sightings and confirm none lands on a hunt lot.
18. **Claim once per player per day, ACROSS A REJOIN.** Claim spot 1, claim it
    again → refused, no second payment. Then **leave the game entirely, rejoin,
    and read `c.hunt.found`**: it must still be `{ true, false, false }` and the
    phone must still say 1/3. This is the test that catches the sparse-table
    round-trip bug (N3 rule 1) — the spec's first draft would have shown **0/3**
    here and allowed all three to be claimed a second time, every session, for
    the full daily reward. Do the same at 2/3, which is the state that matters.
19. **`found` survives as an array, not an object.** Read the raw saved value
    back (Studio DataStore viewer or a dev hook) and confirm it is a **3-element
    JSON array**, e.g. `[true,false,false]`, and not `{"1":true}`. Also load a
    save written before phase D (no `hunt` field at all) and confirm `saved(s)`
    builds `{ false, false, false }` rather than throwing.
19. **Reward curve.** 1st/2nd/3rd pay 60/90/150 base and 15/20/60 XP; the third
    grants exactly **one** ticket; a second player on the same server also gets
    all three, and only the *first* finder of each spot gets the +40.
20. **Clue tiers.** Solo: tier 1 at 0 found, tier 2 at 1, tier 3 at 2. Two
    clients: after client A finds spot 2, client B's spot-2 clue is **tier 2
    within one second** without B having found anything.
21. **Day rollover.** Force the UTC day forward mid-hunt with 2/3 found. New
    spots appear, old models are **removed** (count them), `found` resets to 0/3,
    `foundHere` resets, `streak` behaves like `refreshLogin`'s, and a claim
    fired across the boundary pays exactly once.
22. **The hunt is not an event.** Through a full hunt: the countdown strip never
    appears for it, `headlineLive()` stays false, the director still starts
    headlines on schedule, `lastHeadline` is unaffected, and the phone's EVENT
    list never contains a hunt row.
23. **Phase A and B unregressed.** Sighting / pup / ice cream / cash drop /
    balloons / cleanup all still announce, claim, pay and expire; `BigChime`
    1.25/0.8 still fires on a FIND claim; `data.City.spotted` still persists.
24. **Console clean** through: a full meter cycle, a redemption, a full hunt and
    a day rollover.

**Two measurements, not pass/fail — report the number:**

25. **Base coins per minute**, per activity, over 10 minutes each of pizzeria /
    parcels / taxi / sweeping. This is the number every other number in this
    spec depends on and nobody has ever measured it.
26. **Wall-clock seconds between consecutive hunt finds**, first-time and
    when-told. Decides whether `Spread = 500` is right.

---

## MEASURE (§M) — and what would make me stop

Three numbers, then the one that would make me rethink.

1. **Minutes to first ticket** — median, and p5. Target median **10-14 min**.
   **Stop if p5 < 6 min**: something is filling faster than intended and the
   whitelist or the ceiling is leaking.
2. **Daily 3 funnel per UTC day** — share of sessions ending 0 / 1 / 2 / 3
   found, and median wall-clock from first clue to third find. Target **≥ 35%
   of returning players reach 3/3**. If **< 15%** reach 3/3, the spots are too
   far apart and `Spread = 500` is the first thing to relax.
3. **Tickets banked at disconnect** — median. **Stop and rethink if the median
   is ≥ 2**: nobody is crossing town, so the meter is free capsules with extra
   steps and "a reason to cross town" is a false premise. That is the finding
   that would kill the mall requirement, and it is one `near()` call to remove.

Plus two diagnostics:

- **Units credited per stat tag per player-hour.** A leak shows up as a tag
  nobody expected, and it is the only cheap way to catch a future income path
  that got added to the whitelist by accident.
- **Days-to-Golden, and the share of accounts holding `Secret`.** Added after the
  `Config.Passives` correction: `Ticket` is now a dial on how fast players acquire
  a `coin = 2` run advantage, and the predicted answer is **~5.7 days at ~6
  tickets/day**. If the measured share of active accounts holding Golden passes
  something like a third inside two weeks, `Ticket` needs raising for a reason
  that has nothing to do with city coins/min — which is exactly the two-constraint
  problem N4 flags.

**Which numbers I distrust, in order.** The brief asked for this and it matters
more than a confident guess:

1. **`PerMin = 187`, the ceiling.** It is `LOOPS.md` §6's reference rate, which
   is one blended figure, and reading the taxi payout (`base 25 + dist/6`, ×1.5
   in a taxi, `:1657-1658`, against landmarks up to ~1,300 studs away) suggests
   an optimising driver clears **500-640** base coins/min while the pizzeria at
   par clears **110-140**. That is a 4-5× spread across activities. **If the
   typical player earns ~120 base coins/min, the typical ticket takes 16
   minutes, not 10, and the feature under-delivers by 60%.** The fix would be to
   lower `Ticket` toward ~1,200 — **not** to raise the ceiling, because the
   ceiling is what defeats the optimiser. Settled by QA item 25: base coins per
   minute, per activity, per real player.
2. **`Spread = 500` studs.** Read off the map, never measured against travel
   time. Settled by QA item 26.
3. **`MaxTickets = 3`.** A pure judgement call about how hard to push the mall
   trip. Settled by measurement 3 above.
4. **`Ticket = 1870` itself, for a second and separate reason.** It was chosen to
   protect the city's coins/min and it does that correctly. It was *not* chosen
   knowing each roll is a 2% shot at `coin = 2`, and on that axis it is generous
   (~5.7 days to Golden). The city constraint and the time-to-Golden constraint
   pull in the same direction — both say "slower is safer" — but they have
   different right answers, and one number cannot satisfy both optimally. Settled
   by the days-to-Golden diagnostic above, not by the coins/min one.

I have no confidence problem with the whitelist, the 187/min ceiling mechanism,
or the date seeding: those are structural, and the first two are provable in
Studio without any telemetry at all (QA items 1-12).

---

## OPEN QUESTIONS FOR THE HUMAN

Taste and money only. Everything else above is decided.

1. **Does the Endless Run fill the city's capsule meter?** Today it does not,
   for free — `award()` (`:411`) never calls `pay()`. Keeping it that way makes
   the meter a *city* retention device and means a runner-only player earns no
   free capsules, even though the collection is shown in the runner's own
   COLLECTION page (`UI.lua:742`). That is a business call about who gets free
   cosmetics, not a design one. My lean: **city-only for phase D**, revisit once
   there is data on how many sessions never enter the city.
2. **`DayCap = 12` — is a hard daily ceiling wanted at all?** It only ever bites
   a scripted account or a 2-hour session, and the per-minute ceiling already
   holds the 21.4% ratio at every session length. I included it as a circuit
   breaker. Removing it is one line and makes a long session feel uncapped.
3. ~~**The restricted-player fallback: 240 coins per ticket, or no fallback?**~~
   **Withdrawn, not a question any more.** The fallback was my error; see N5.
   The ticket path checks no policy flag.
4. **What does a 7-day Daily 3 streak give?** `c.hunt.streak` ships as a counter
   with nothing attached (CUT/DEFER). The obvious candidates are an exclusive
   outfit or skin (`exclusive = true` already exists in `Config.Outfits` /
   `Config.Skins`) — outfits and skins genuinely **are** cosmetic (nothing reads
   a gameplay field off them, unlike `Config.Passives`), so they are inside the
   corrected §6 exemption in a way a capsule is not, and
   both are your call on what the game gives away.
5. ~~**Should the weekly `wcaps` challenge keep counting free tickets?**~~
   **Decided: yes, leave it.** 280 coins/week expected (not the 800 my first
   draft quoted — the challenge is drawn 2 weeks in 5). Kept here as a record of
   the decision, since it converts a sink-gated challenge into a free one.
