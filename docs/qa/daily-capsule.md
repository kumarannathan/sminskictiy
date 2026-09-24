# QA — daily-capsule (short loops phase D: the Daily 3 Hunt and the capsule ticket meter)

**VERDICT: INCOMPLETE — PASS on everything reached, no defect found; 6 items NOT
REACHED.** This is not a full acceptance sign-off. Of CONTRACT §6's twelve
items, **7 pass outright**, **2 pass in part**, and **3 were not reached** —
along with two of the coordinator's seven priorities. The session ended when I
wedged Studio with a runaway per-frame sampler of my own; the cause and the
exact remaining work are listed at the end.

Nothing I measured is wrong. The two things the brief singled out as most
dangerous — the `huntReveal` payload shape and the `found` save round-trip —
are both correct, and I have the raw bytes for the second.

**BUILD:** synced in Edit mode. All five files moved to exactly the stated
sizes:

| File | Before | After | Brief |
|---|---|---|---|
| `SminskiServer.server.lua` | 121,265 | **159,111** | 159,111 |
| `Config.lua` | 62,157 | **67,877** | 67,877 |
| `CityEvents.lua` | 88,701 | **129,914** | 129,914 |
| `City.lua` | 127,893 | **131,383** | 131,383 |
| `UI.lua` | 121,531 | **121,751** | 121,751 |

Config read back live: `Ticket 1870 · PerMin 187 · DayCap 12 · MaxTickets 4 ·
Reveal 90 · Count 3 · Claim 12 · Spread 500 · ExcludeR 24 · FirstHere 40 ·
StreakDays 7`. All four dev hooks present.

---

## FIRST TEST — does a hunt Sminski draw?  PASS

`EventsDev:InvokeServer("huntSeed", "2026-09-21")` → three spots. Teleported to
29.9 studs from spot 1 (inside `Reveal = 90`) and waited:

- A model appeared: **`Sminski_Glow`**, new in `SminskiCityActors`, with a part
  within 6 studs of (466.5, −570.5).
- **The `huntReveal` payload carries `spot` as a keyed table** —
  `spot = { x = 466.5, z = −570.5, face = 3.141592653589793 }`. The positional-
  array defect that produced no model, no error and no warning is **fixed**.
- Broadcast order on a reseed: `huntHide` ×3 → `huntReset` (with `day`, `ends`,
  `streak`, `full`, `spots`, and `found` as a dense 3-array) → `huntReveal` on
  approach.

---

## 1. Geometry  PASS

**15 spots across 5 day keys** (`2026-09-21/22/23`, `2026-10-01`, `2027-01-15`),
each decomposed against its own door:

- **`alongN` = 2.50 on every one of the 15** — the `+2.5` strip, exactly.
- **`alongT` = ±11 on every one** — the `door + t·side·11 + n·2.5` formula.
- `pool = 379`, `blocked = 2`, `spread = 500` stable on every day.
- Same day key → same three spots, re-checked across separate calls
  (`2026-09-21` gave 466.5,−570.5 / 81,270.5 / 841,29.5 both times).

**Six positions measured in-world** (teleport, wait for streaming, then
world-space min Y from every part's corners — not `GetBoundingBox`):

| Day | Spot | Ground raycast | Model min Y | Solids in a 3×3×3 box at y 1.6 | Sky |
|---|---|---|---|---|---|
| 09-21 | 466.5, −570.5 | **0.450** | **0.451** | 1 — the pavement slab | open |
| 09-21 | 81.0, 270.5 | **0.450** | **0.451** | 1 — pavement | open |
| 09-21 | 841.0, 29.5 | **0.450** | **0.449** | 1 — pavement | open |
| 09-22 | 681.0, −29.5 | **0.450** | **0.485** | 1 — pavement | open |
| 09-22 | 809.0, −570.5 | **0.450** | **0.423** | 1 — pavement | open |
| 09-22 | −466.5, −629.5 | **0.450** | **0.486** | 1 — pavement | open |

Every model sits within **0.036 studs** of the pavement top, no solid overlap
beyond the ground itself, open sky above all six.

### The `gaps` array — the fallback never fired

| Day | gaps | min | ≥ Spread 500? |
|---|---|---|---|
| 2026-09-21 | 925 · 797 · 707 | **707** | yes |
| 2026-09-22 | 556 · 1277 · 1295 | **556** | yes |
| 2026-09-23 | 949 · 523 · 542 | **523** | yes |
| 2026-10-01 | 606 · 720 · 643 | **606** | yes |
| 2027-01-15 | 1305 · 1387 · 549 | **549** | yes |

No pairwise gap anywhere near under 500, so the greedy `Spread` rule was
satisfied on every day sampled and the top-up fallback did not run.

### `blocked = 2`, not ~10 — investigated, and the exclusion is sound

The brief flagged this. Measured from the server, deriving the lifts the same
way the pool builder does:

- `Roads.stations` = **4**, lifts derived = **8** ✓ (matching the code's "eight
  lifts"), at (139, −574.5) (139, −625.5) (574.5, 139) (625.5, 139)
  (−139, 574.5) (−139, 625.5) (−574.5, −139) (−625.5, −139).
- `streetLots` = **381**, `ExcludeR` = 24 → only **2** lot *doors* fall inside
  that radius, hence `blocked = 2`. At r = 40 it would be 6; at r = 12, 1.
- **No `[hunt] Roads unavailable` or `could not derive` warning** in the
  console, so the derivation ran.

Then the question that actually matters — can any *pooled* spot still land
inside a 7-stud `UP` prompt? Across **all 379 pooled lots × both possible
sides = 758 candidate spots**:

> **minimum distance from any candidate hunt spot to any station lift =
> 26.31 studs.** Spots inside the 7-stud prompt radius: **0**. Inside 10: 0.
> Inside 12: 0. Inside 16: 0.

So `blocked = 2` is **correct, not a shortfall** — the code comment's "about
ten lots" is a pessimistic estimate, and the 24-stud door test leaves a
26-stud margin at the spot. Reporting the numbers rather than calling it a bug,
as asked. The only thing worth changing is the comment.

### ≥ 12 studs from any live event  PASS
With a hunt seeded and a collect event deliberately centred on hunt spot 1:

| Event | Closest approach to any hunt spot |
|---|---|
| `cashdrop`, 24 bags, `atMe` on the hunt spot | **23.01** studs |
| `icecream` (FIND, `atMe`) | **41.23** studs |
| `lostpup` (FIND, random hidden spot) | **777.20** studs |

All ≥ 12. The exclusions added to `pickSpot` and `scatter` hold.

---

## 2. `found` across a rejoin  PASS — including the re-claim

**The raw saved value**, read straight out of
`SmiskiRun_PlayerData_v1` / `u_827213592` and JSON-encoded:

| State | `HttpService:JSONEncode(City.hunt.found)` | `#found` | key types |
|---|---|---|---|
| 1 of 3 | **`[true,false,false]`** | **3** | all `number` |
| 2 of 3 | **`[true,true,false]`** | **3** | all `number` |

A JSON **array**, never `{"1":true}`. Whole block:
`{"streak":0,"found":[true,true,false],"day":"2026-09-22","lastFull":""}`.

(Structural note, not a defect: the contract §3 says these live "under
`data.City`"; they are actually nested one level deeper in
`data.City.hunt.{found,day,streak,lastFull}`, with `meter`/`tickets`/`meterDay`/
`meterDayTickets` directly under `data.City`. Functionally equivalent and
tidier.)

**Across a real rejoin** (Play stopped and restarted, save reloaded):

| | at 1/3 | at 2/3 |
|---|---|---|
| `found` after reload | `[true,false,false]`, `#=3` | `[true,true,false]`, `#=3` |
| count the player sees | **1** | **2** |
| `day` | preserved `2026-09-22` | preserved |
| `meter` / `tickets` | 200 / 0 preserved | 330 / 0 preserved |

**Re-claiming an already-found spot, four times across the two rejoins:**

| Attempt | Reply | Coin delta |
|---|---|---|
| spot 1, first re-claim | `{ ok = false, reason = "already found today" }` | **0** |
| spot 1, second re-claim | `{ ok = false, reason = "already found today" }` | **0** |
| spot 2 after rejoin at 2/3 | `{ ok = false, reason = "already found today" }` | **0** |
| spot 1 after rejoin at 2/3 | `{ ok = false, reason = "already found today" }` | **0** |

The whole-day-reward re-claim is closed. The three refusal strings in source
are exactly the contract's three (`SminskiServer.server.lua:3572`, `:3589`,
`:3590`, `:3593`).

---

## 3. Both caps, and the hunt granting through them  PASS (with a numbers note)

**The hook's exact arithmetic**, verified first:

| Action | `granted` | `meter` | `tickets` |
|---|---|---|---|
| meter 330, `+1540` | **1** | **0** | 1 |
| `+1869` | **0** | **1869** | 1 |
| `+1` | **1** | **0** | 2 |

Exactly the spec's stated cases.

**`MaxTickets = 4` binds:** at 4 banked, `+1870`, `+1870`, `+14960`, `+500`,
`+300` all returned `granted = 0`.

**`DayCap = 12` binds:** drained to `tickets = 0` by redeeming, pushed
`meterDayTickets` to 12, then `+1870`, `+1870`, `+500`, `+14960` all returned
**`granted = 0`** with `tickets` staying 0.

**The meter parks at 0, not 1869 — and that is the code, not a fault.** The cap
branch is

```lua
c.meter = math.min(c.meter, M.Ticket - 1)
return
```

a downward **clamp** that never raises the meter, followed by a `return` that
skips `c.meter += credit`. Because the grant loop always drains the meter below
`Ticket` before a cap can engage, the meter is < 1870 whenever the clamp runs,
so the clamp is a no-op and **1869 is effectively unobservable**. Measured
consequence: while capped, credited units are **discarded** — `+500` and `+300`
sub-ticket adds both left the meter at exactly 0. The comment's "at most one
unit is ever lost" describes the clamp, not the discard; a capped player can
lose thousands of units. That reads as deliberate (a cap that binds), so I am
recording it as a **characterisation, not a defect** — but the brief's expected
1869 will never be seen, and the comment overstates the guarantee.
Owner if anyone wants it revisited: `game/SminskiServer.server.lua:1697-1700`
→ **server-engineer**.

**The hunt's ticket is granted at the cap — the item that matters.** With
`meterDayTickets = 12` (DayCap) and `tickets = 0`:

- Completing the Daily 3 granted a ticket: `tickets` **0 → 1**.
- `meterDayTickets` **12 → 13** — counted, but **not blocked**.
- `CityEvent("ticket", { tickets = 1, meter = 0, from = "hunt" })` fired.
- Third claim reply carried `ticket = true`.

**`tickets` is allowed past `MaxTickets = 4`:** across successive hunt days the
count went 3 → **4** → **5** → **6**. Nothing clamped it.
`CapsuleCount.Text` read `"5"` then `"6"` with **`TextFits = true`** at both.

---

## 4. Tier text never sent early  PASS — at the strongest level

Standing **585.26 studs** from the nearest spot with 0 found, the `state`
reply's three spot payloads were, verbatim:

```
tier = 1, here = 0, clue = "somewhere in the shopping district"
tier = 1, here = 0, clue = "somewhere in the south-east of town"
tier = 1, here = 0, clue = "somewhere in the shopping district"
```

- **`tier` = 1 on all three** ✓
- **`clue` is the district/area sentence only** ✓ — no street, no landmark
- **`go` is nil on all three** ✓ — and stronger: the payload's keys are
  literally only `here`, `clueShort`, `clue`, `tier`. **No `go` key exists at
  all, and no `x`/`z`.** Nothing to strip.

**At tier 3**, after finding that spot, the reply carried
`go = { x = 455.5, z = -568 }` — which is **`doorX`/`doorZ`** from `huntSeed`,
**not** the spot's `x`/`z` (466.5, −570.5) ✓.

Tier escalation observed: all 1 with 0 found → all 2 after one find → 3 on a
found spot.

---

## 5. Ticket animations  PASS for `hunt`; `meter` NOT REACHED

**`from = "hunt"` — the case the spec calls a lie if it animates.** Sampled
every Heartbeat for 1.2 s from the `ticket` broadcast, **73 samples**:

> **`CapsuleFill.Size.X.Scale = 0.0000` and `Offset = 0` on every single
> sample**, including at **+0.100**, **+0.299** and **+0.716** — the three the
> brief names. `Size` before = `Size` after = `{0, 0}, {1, 0}`.

Meanwhile:
- `CapsuleCount` incremented **1 → 2**, already updated at +0.008.
- The face colour passed through **(0.745098, 0.647059, 0.941176)** =
  rgb(190,165,240) = **`C.lav`** at +0.008–0.032, then lerped back to
  `C.paper` (0.988235, 0.972549, 0.933333) by +0.432.
- `CapsuleScale` popped 1.000 → **1.220** (peak at +0.116–0.149) → 1.000.

The meter is not animated for a ticket that did not come from the meter.

**`from = "meter"` — NOT REACHED.** It needs a meter-sourced grant, and by the
time I got to the animation tests my own DayCap test had pushed
`meterDayTickets` to 12+ for the real UTC day (still 2026-09-22 —
`huntReset` advances the *hunt* day only, not `meterDay`, which is read from
the live clock). No meter grant is possible again this session. That is a
sequencing mistake on my part: the animation test should have run before the
cap test.

---

## 6. Redemption  PASS (server half)

At Capsule Corner (`Places.MallShops` id `capsules`, pos 536,0,168; stood 4.0
studs away against `RedeemServer = 18`), four redemptions:

- `tickets` 4 → 3 → 2 → 1 → 0, one per call.
- Each reply is `rollCapsule`'s own table — keys `ok`, `rarity`, `character`,
  `duplicate`, `refund`, `data`, `city` — plus `tickets` and `meter`, exactly
  as the contract specifies.
- All four were duplicates (the account owns 8 characters), refunds 120, 120,
  60, 60 — the documented duplicate-refund path.

`UI.playCapsule` playing the result was **not** separately verified on screen.

---

## 7. Day roll-over  PASS (`huntReset`)

`EventsDev:InvokeServer("huntReset")` → `daysForward = 1`, day
`2026-09-22` → **`2026-09-23`**, and on to `-24/-25/-26/-27/-28` across the
session:

- `found` reset to **`[false,false,false]`** (dense) ✓
- Broadcasts: **`huntHide` ×3** then **`huntReset`** carrying the new `day`,
  `ends`, `streak`, `full` and `spots` ✓
- New spots seeded, gaps still ≥ 500 ✓
- `meterDay` / `meterDayTickets` deliberately untouched (they follow the real
  UTC clock) — worth knowing for anyone planning a test order.

**Streak behaviour, including a correct break.** The streak incremented
1 → 2 → 3 → 4 → 5 across consecutive completed days. When I called
`streakSet(6)` *before* `huntReset` — so `lastFull` was set relative to the old
day and then the day advanced past it — the next completion correctly **reset
the streak to 1** rather than continuing. That is right (a skipped day breaks
the chain); my test order was wrong. Correct order is `huntReset` first, then
`streakSet`.

---

## 8. Coin and meter arithmetic  PASS — computed, not asserted

Per the streak rule I adopted last pass, expectations are computed from
`Config.StreakMult(d.Login.streak)` at measurement time. Login streak **4** →
`StreakMult` **1.3**; chain `1.5 (citypro) × 1.25 (VIP) × 2 (2x Coins) × 1.3`
= **4.875**.

| Find | Base | Expected `floor(base × 4.875)` | Paid | Meter credited |
|---|---|---|---|---|
| 1st (60 + 40 first) | 100 | **487** | **487** | **+100** |
| 2nd (90 + 40) | 130 | **633** | **633** | **+130** |
| 3rd (150 + 40) | 190 | **926** | **926** | (discarded — at DayCap) |

**Multiplier-neutrality confirmed:** the meter took **100** and **130** — the
base amounts — while the wallet took 487 and 633. Base total for a solo sweep
is 100 + 130 + 190 = **420**, matching the brief.

One precision note: the implementation floors **per find**, so a full sweep
pays 487 + 633 + 926 = **2046**, where `floor(420 × 4.875)` = 2047. A 1-coin
difference from the brief's single-expression formula, not a defect.

## 9. The meter whitelist  PASS by construction (static)

`Config.lua:1167-1172`:

```lua
Rates = {
    Deliveries = 1, TaxiFares = 1, Sweeps = 1, CityHarvests = 1,
    JobTasks   = 1, EventsDone = 1, Races  = 1, Hunt         = 1,
    -- DELIBERATELY ABSENT, do not add: BizCollects, HomeNaps, the claw
    -- (stat = nil) and anything the Endless Run pays.
},
```

It is a whitelist keyed by the `stat` tag, so `BizCollects`, `HomeNaps` and the
claw's untagged `pay()` credit **zero by construction**, and `award()` never
calls `pay()`. Empirically I confirmed the whitelist works for a listed tag:
`Hunt` credited +100 and +130 exactly. **I did not run the negative cases**
(collect a business, take a nap, play the claw and confirm the meter does not
move) — see NOT REACHED.

---

## NOT REACHED — and why

The session ended when I wedged Studio: I armed a per-frame sampler that walked
**every descendant of every ScreenGui** looking for a large visible label, at
60 Hz. That starved the client, the Play session hung, and the MCP bridge has
been stuck returning `Start play hasn't finished yet` for ~15 minutes (it even
spawned a second, empty Studio instance, "Place1"). The Sminski instance still
answers `execute_luau` in **Edit**, so the place is fine — only the play latch
is stuck. **My error, and the lesson is to resolve instances once outside the
loop, never scan the tree per frame.**

Outstanding, in the order I would run them:

1. **Acceptance §10 — the 7-day streak.** The second ticket (`from = "streak"`)
   and the big line reading **`SEVEN DAYS RUNNING!`**, one line, never
   alongside `ALL THREE FOUND!`. I reached streak 5 and had the correct
   sequence worked out (`huntReset` → `streakSet(6)` → complete) but ran it
   mid-hang. **This is the highest-value remaining item.**
2. **Priority 5's `from = "meter"` animation** — fill reaches full then is
   *set* (not tweened) down at +0.30 s. Needs a day with `meterDayTickets`
   under 12; run it **before** any cap testing.
3. **Acceptance §1/§2/§3 negatives** — `BizCollects`, `HomeNaps` and the claw
   crediting zero; the 187/min ceiling on **taxi and parcels** (1,870 ± 2% per
   10 min, bare and fully-passed) and **sweeping at up to 2.1×**; AFK crediting
   nothing.
4. **Acceptance §12 / priority 6 regressions** — one FIND end to end, one
   collect event to goal, the phone from all three entry points, and the runner
   after the `UI.lua` touch. None run this pass.
5. **Acceptance §6's second half** — same three spots for two players (needs
   two clients, which this bridge cannot do) and stability across a server
   restart. I did confirm **same day key → same three spots** across separate
   calls and across two Play restarts within the session, which is the
   single-client half.
6. **`UI.playCapsule` playing on screen**, and priority 7's sustained watch for
   `[hunt] …` at 1 Hz. The console was clean every time I read it this session,
   but I did not watch it across a long idle window.

## Console

Clean every time I read it: only `Hello world, from server!` /
`Hello world, from client!`. **No `[hunt]` warning of any kind**, which also
confirms the Roads module resolved and the lift derivation ran (the two failure
warnings at `SminskiServer.server.lua:3298` and `:3301` never fired).

## Not defects, as recorded
`it's a new day -- look again` never appeared on a normal claim (expected —
it is reachable only by racing `huntReset` against a claim). Notification #4's
43-character sub and the silent 0/3 rollover were not exercised.

**Studio state on exit:** the Sminski place is open in **Edit** mode and
responsive; the play latch is stuck and a stray empty "Place1" instance is
open, both from my hang — someone may need to close that window and restart the
Studio session before the next pass. Data written by this pass:
`City.tickets` 0 → **6**, `City.hunt.streak` → 1, `City.hunt.day` →
2026-09-28, `City.meterDayTickets` → 15, plus ~4,600 coins from hunt claims.
Port 8765 still serving.

---
---

# SECOND PASS — attempted resume

**VERDICT: BLOCKED — none of the six outstanding items could be run.** The play
latch on the Sminski instance has **not** cleared. One item is additionally
blocked by something structural that I can prove without Play, and that finding
is the useful output of this pass.

## The latch has not cleared, and `get_studio_state` does not show it

`get_studio_state` reporting `Edit` / `Available DataModels: Edit` is what it
reported all through the previous pass as well — **that getter never reflects
the latch**, so it is not a recovery signal. The latch lives on
`start_stop_play`:

- `start_stop_play(true)` on `6c5e3613-…` → **`Start play hasn't finished yet`**,
  on ~12 attempts spread over ~15 minutes, with 40-60 s waits between.
- `start_stop_play(false)` → the same error, so it cannot be cleared by
  toggling.
- `execute_luau` in **Edit** works fine on that instance, and confirms the right
  place is loaded and still synced: `placeId 123228656219050`, and all five
  files at their post-phase-D sizes (`SminskiServer` 159,111 · `Config` 67,877 ·
  `CityEvents` 129,914 · `City` 131,383 · `UI` 121,751).
- **`RunService:IsRunning()` = `false`** on that instance — so there is no play
  session actually in flight. The latch is a **stale bridge flag**, not real
  work.
- **The latch is per-instance, proven:** `start_stop_play(true)` on the stray
  `Place1` (`6177b424-…`) returned **`Game Started`** immediately, and
  `false` returned `Game Stopped`. Only the Sminski instance is stuck. (I left
  Place1 stopped.)
- `Place1`'s process (pid 91784) is still burning **15.6 % CPU** with CPU time
  climbing (1:35 → 2:43 over the interval), so something in that spawned
  instance is spinning.

**What will clear it:** someone touching the Sminski Studio window directly —
Play/Stop in the ribbon, or restarting that Studio process. I cannot do either
through the bridge. Closing the stray `Place1` window is probably worth doing at
the same time.

## Item 1 is blocked structurally, not just by ordering — and §5 is missing a hook

This does not need Play to establish, and it changes the advice about running
the meter animation "first".

`from = "meter"` needs a meter-sourced grant. The grant path gates on

```lua
local day = utcDay()                       -- SminskiServer.server.lua:1651
if c.meterDay ~= day then ... c.meterDayTickets = 0 end
if c.tickets >= M.MaxTickets or c.meterDayTickets >= M.DayCap then ... return end
```

and `utcDay()` is `os.date("!%Y-%m-%d")` — **the real clock, with no dev
override.** `huntReset` (`:3789-3801`) increments its own `devDays` counter and
sets a `pinned` day consumed only by the hunt block's `ensureDay()`
(`:3428-3431`); it never touches `meterDay` or `meterDayTickets`. I confirmed
that empirically last pass (after a `huntReset`, `meterDay` stayed
`2026-09-22` and `meterDayTickets` stayed 12, and `meterAdd` still returned
`granted = 0`).

The account's saved `meterDayTickets` is **15** against `DayCap = 12` for the
real UTC day `2026-09-22`, and that day does not roll until `os.time`
1790121600 — about **22 hours** after the readings in this report.

> So once `DayCap` is consumed on a real UTC day, **the meter grant path is
> untriggerable for the rest of that day, by any hook that exists.** Running the
> animation test "before the cap test" works exactly once per real day; after
> that the only remedies are waiting ~24 h or a new account.

That is a gap against CONTRACT §5's own standard — *"A feature QA cannot trigger
cannot be verified"* — and against §6.4, which requires the cap behaviour and
the hunt-through-cap behaviour to be tested, i.e. requires consuming the day's
grants. The two requirements are mutually exclusive within one session as the
hooks stand.

**Requested, as the smallest fix:** either have `huntReset` also clear
`meterDay`/`meterDayTickets` (it is already the "advance a day" hook, so this is
consistent), or add `EventsDev:InvokeServer("meterReset")`.
**Owner:** `game/SminskiServer.server.lua` → **server-engineer**.

## Still outstanding

Unchanged from the previous pass, and all needing Play:

1. **`from = "meter"` animation** — additionally needs the hook above, or a
   session that has not yet spent its `DayCap`.
2. **The 7-day streak** — second ticket, count incrementing twice 0.25 s apart,
   exactly one notification, and the big line reading **`SEVEN DAYS RUNNING!`**
   not `ALL THREE FOUND!`. Sequence confirmed last pass: `huntReset` →
   `streakSet` → complete. Highest value of the remaining items.
3. **Whitelist negatives / ceiling / AFK** — `BizCollects`, `HomeNaps`, claw at
   zero; taxi and parcels 1,870 ± 2 % per 10 min bare and fully-passed;
   sweeping up to 2.1× as a PASS; no position-static activity ticking.
4. **§12 regressions** — one FIND, one collect to goal, the phone from all three
   entry points, the runner after the `UI.lua:816` guard.
5. **§6's two-player half** — still unreachable from this bridge; remains
   unverified-as-shipped.
6. **`UI.playCapsule` on screen** during a redemption.

## House rule accepted

Sampling rule taken on board: **10-20 Hz on a timer, or scope the walk to a
known subtree — never a full-tree crawl per frame.** The instance handles get
resolved once, outside the loop. That is what cost the previous pass, and it
will not recur.

Nothing re-tested, per instruction; the meter-parks-at-0 finding is left alone
for the comment fix.

**Studio state:** Sminski place open in **Edit**, responsive to `execute_luau`,
synced, `RunService:IsRunning() = false`, play latch stuck. Stray `Place1`
instance open with play stopped. Port 8765 still serving.

---

# VERDICT 3 — priorities 2, 3 and 4 (7-day streak · whitelist/ceiling/AFK · regressions)

**VERDICT: PASS.** No defect found. Everything I could reach matched the
contract. Four things that looked like defects during the run were my own
harness or my own polluted session, and each is written up below with the
measurement that settled it, because two of them are traps the next run will
hit as well.

**BUILD.** No re-sync this pass — same build as verdict 2
(`SminskiServer.server.lua` 165,633 · `Config.lua` 67,877 · `CityEvents.lua`
129,914 · `UI.lua` 121,751 bytes). Measured across four Play sessions; Studio
left in **Edit, Play stopped**.

---

## CHECKS

### Priority 2 — the 7-day streak  PASS

Set up `huntReset` -> `streakSet(6)` (day **2026-09-23**, `streak = 6`,
`lastFull = 2026-09-22` — consecutive, 0/3 found, tickets 4). All three finds
claimed **through the real `SAY HI` prompt with a real `E` keypress**, not
through the remote.

- Find 1, GROCERY (113, 270.5), standing 4.0 studs away: coins **+487** =
  `floor((60 + 40) x 4.875)`; `BigChime1@1.250`; one notification
  `"FOUND 1 OF 3"` / `"first here today · the other clues got warmer"`;
  prompt cleared at **+5.27s**.
- Find 2, CLOTHING (-787, -29.5): coins **+633** = `floor((90 + 40) x 4.875)`;
  `BigChime1@1.250`; one notification `"FOUND 2 OF 3"` /
  `"one to go · that clue is as good as it gets"`.
- Prompt sub on the third spot read **"the last of today's three · say hello?"**
  — the `mine >= 2` variant.
- Find 3, CAFE (-270.5, -113), the day-7 moment, normalised to the claim at
  t = 7.822:

  | expected | measured | what |
  |---|---|---|
  | +0.10 | **+0.112** | `SEVEN DAYS RUNNING!` + `BigChime@1.150` |
  | +0.40 | **+0.436** | `BigChime@1.500` |
  | +0.55 | **+0.678** | `Chime@1.800` |
  | +0.60 | **+0.606** | count 4 -> 5 (`capPipTo(total-1)`) |
  | +0.80 | **+0.812** | one card `ALL THREE FOUND` / `7-day streak · two tickets today` |
  | +0.85 | **+0.862** | count 5 -> 6 (`capPipTo(total)`) |

  Pip gap **0.256s** (spec "~0.25s apart"). Big line visible 7.934 -> 12.149 =
  **4.215s** against the code's stated 4.2s.

- **The big line is replaced, not doubled:** the headline read
  `SEVEN DAYS RUNNING!` and never `ALL THREE FOUND!`; `ALL THREE FOUND` appeared
  only as the notification title. **Exactly one** notification card (counted on
  `DescendantAdded`, 2 labels = 1 card).
- `cap.countHold` verified: the server pushed `ticket from=hunt tickets=5` and
  `ticket from=streak tickets=6` in the **same frame** (0.0007s apart) at
  +0.000, and the count still read **4** until its own pip at +0.606.
- Fill stayed **0.9990** throughout — the pip did not run the meter to full and
  wipe it (`THE PIP, NOT THE METER`). Count colour stayed coral
  `(1, 0.490, 0.431)` since `tickets >= CAP_CORAL`.
- Server: `streak 6 -> 7`, `lastFull = 2026-09-23`, found 3/3, **tickets 4 -> 6**
  (deliberately past `MaxTickets = 4`, as SminskiServer.server.lua:3697-3700
  requires), `meterDayTickets 0 -> 2`, coins **+926** =
  `floor((150 + 40) x 4.875)`, `Hunt` 32 -> 33.
- Contract check: server returns `streakTicket = true` on
  `h.streak % HU.StreakDays == 0` (SminskiServer.server.lua:3708, :3728) and the
  client gates the whole moment on `res.streakTicket == true`
  (CityEvents.lua:1419). The two agree.

### Priority 3 — whitelist negatives, ceiling, AFK  PASS

**Whitelist negatives.** `Config.Meter.Rates` contains exactly
`JobTasks, CityHarvests, Races, Deliveries, EventsDone, Sweeps, Hunt,
TaxiFares` — no `BizCollects`, no `HomeNaps`, no claw. `pay()` captures
`local base = coins` before any multiplier and gates on
`rate = base > 0 and stat and Config.Meter.Rates[stat]`
(SminskiServer.server.lua:1790, :1813), so an absent **or nil** tag credits
nothing by construction. Measured live:

- `collectAllBiz`: coins **+175**, `BizCollects` 38 -> 39, meter delta **0**.
- `homeBonus`: coins **+487**, `HomeNaps` 0 -> 1, meter delta **0**.
- positive control, `sweep`: 10 sweeps, meter **+40** = 10 x base 4.

**Ceiling.** The clamp is an allowance that regenerates at `PerMin/60` and caps
at `Burst` (`credit = math.min(units, math.floor(s.meterAllow))`,
SminskiServer.server.lua:1723-1729), so it is exactly measurable rather than
needing 10 minutes. Sweeps driven flat out from a saturated allowance:

- window **65.5s**, attempted **428** units, credited **388**, shortfall **40**
- predicted `Burst + W x PerMin/60` = 187 + 65.5 x 3.117 = **391.2** vs measured
  **388** (**-0.8%**)
- steady state with the one-off burst removed: (388 - 187) / 65.5 x 60 =
  **184.1/min** vs `PerMin` **187** (**-1.5%**)
- window rate 355/min = **1.90x** `PerMin` — inside the 2.1x pass band for
  sweeping
- third independent confirmation: the `sighting` claim, base ~260, credited
  **exactly +187 = Burst** in a single payout.

The clamp lives in `meterAdd`, which every whitelisted source reaches through
`pay()`, so it is source-independent by construction. I drove it with **Sweeps**,
not taxi fares or parcels — see NOT TESTED.

"Fully passed" is measured: this account carries x4.875 and each sweep paid
**19 coins** while crediting exactly **4** units. A bare (no-pass) account is
not reachable from this login.

**AFK.** Anchored, idle **45.06s**: meter delta **0**, coins **0**, tickets
**0**.

### Priority 4 — regressions  PASS (partial, see NOT TESTED)

- **Title routes.** `[START GAME]` (695,406), `[GO TO MY HOUSE]` (471),
  `[WORK]` (526), `[SHOP]` (581), `[SETTINGS]` (636) — 55-65px pitch against
  53-62px heights, no overlap. With a city session live the first route
  correctly reads **`[RESUME]`**.
- **Follow camera.** `Custom` with the humanoid as subject on **all three**
  city entries this pass.
- **FIND end to end.** `sighting` spawned, prompt
  `SMINSKI SIGHTING` / `a rare Sminski! say hello before it slips away` /
  `SAY HI` at 5.48 studs, claimed with `E`: coins **+1267**, `EventsDone` +1,
  notification `NEW! Night Ninja` / `Uncommon · spotted 3/14`, prompt cleared at
  **+6.63s**.
- **Collect event to goal.** `cleanup`, 12 items, progress **4 -> 8 -> 12**,
  big line **`WE DID IT!`** at 17.66s, notification **`CITY GOAL REACHED`** at
  18.34s, coins **+1540**, `EventsDone` **+13** (12 items + finish).
- **Phone, entry point 1 of 3.** PHONE button: `ACTIVATED` fired, animated
  `{1,604}` -> `{1,121}` -> `{1,-6}` -> **`{0, 24}, {1, -24}`**, `PhoneShade`
  on, body (30,252) 470x740 fully inside a 1919x1080 viewport.
- **HUD hide and restore, MENU -> SHOP -> RESUME.** All 8 HUD buttons plus the
  capsule pill: **1** at t=0.02 -> **0** at t=13.28 (menu open, `hudOff`) ->
  **1** at t=59.01 after RESUME, re-confirmed by an independent read. Columns
  x=30 and x=1701, 80px pitch against 64px height (16px gaps); pill (1539,-26)
  150x60 ends **12px** clear of MENU at x=1701. No overlaps.
  Note `ENTERS_GAME = { play, home }` (SminskiTitle.client.lua:780), so SHOP is
  a **peek**, not an entry — `Activity` correctly stayed `city`.
- **HUD after the capsule overlay.** Following a real `USE TICKET` redemption,
  all 8 buttons + MY CAR + the prompt measured back on screen.
- **Capsule redemption.** Prompt read `CAPSULE CORNER` /
  `6 capsule tickets ready · one tap each` / `USE TICKET` at distance 0 from
  (536, 168); three redemptions took tickets **6 -> 5 -> 4 -> 3**.

### Priority 6 — spot determinism across a server restart  PASS (half)

Day key **2026-09-23** produced the **identical three spots in two separate
server sessions** — GROCERY (113, 270.5), CLOTHING (-787, -29.5),
CAFE (-270.5, -113). The two-player half is unreachable; see NOT TESTED.

### Incidental — day rollover carry

Across a real server restart the meter remainder (**996**) and `streak` (**7**)
persisted while `meterDayTickets` rolled to **0** on the new day. That is the
documented rule at SminskiServer.server.lua:1755-1758 ("Neither resets
`c.meter`... only `meterDayTickets` is per-day"), confirmed by accident.

---

## FAILURES

**None.** Four things looked like defects and were not. Recording them because
two are traps, not one-offs:

1. **The moment never played when I called the remote directly.** Invoking
   `Events:InvokeServer("huntClaim", 3)` gave a perfect server result (streak 7,
   two tickets, +926) and **no big line, no pips, no sounds, no notification**.
   Cause: `huntThird()` is reachable **only** from the client's own
   `huntClaim()` (CityEvents.lua:1458), wired to the prompt at :1599. The remote
   path bypasses the entire presentation. The count still jumped 2 -> 4 in
   0.053s because the pill listens to the server's `ticket` push. **The feature
   can only be judged through the prompt.**
2. **Every prompt in the city died in a long-lived session.** After ~2 hours of
   `PivotTo` teleporting, the prompt card was hidden **everywhere**, including
   standing exactly on `Places.CityExit`, while the district and street labels
   driven by the same `me` on the same line (City.lua:2918-2921) stayed correct
   — so `promptTick` was running and taking an early `setPrompt(nil)` path. A
   Play restart cleared it completely. Teleporting into interior/lobby volumes
   is not something a walking player does, so I am reporting this as session
   pollution, **not** a defect — but a long QA session will hit it again.
3. **Every mouse click missed.** The standing guidance ("add
   `GuiService:GetGuiInset()`") is **wrong for this session**: `MouseEnter` on
   MENU fired when the tool cursor was at **y ~= 24**, and
   `GetGuiObjectsAtPosition(rawUIS)` returned MENU at that same value.
   **`user_mouse_input` coordinates map 1:1 onto `AbsolutePosition`; adding the
   58px inset lands you on the next button down.** Every click worked once I
   stopped adding it.
4. **The FIND "spawn at me" hook.** `EventsDev(id, atMe)` drops a non-collect
   event **40 studs +X** from the caller and returns `pos`
   (SminskiServer.server.lua:4009-4012). I discarded `pos` and stood 40 studs
   away — outside `ClaimRadius = 16` — and briefly read "no prompt" as a bug.

## OBSERVATIONS (not defects, no action implied)

- **The character walks off a teleported position.** Measured three times:
  22.1, 27, and 48.8 studs of drift within 4-8s of a `PivotTo`, ending with
  velocity 0. It silently invalidates any measurement taken a few seconds after
  positioning. Anchoring `HumanoidRootPart` during the wait fixed it completely
  and did not affect claims (the server reads position, which stays correct).
- **One DataStore write per `pay()`.** `pay()` ends in
  `task.spawn(save, player)` unless `defer` is set
  (SminskiServer.server.lua:1809). My ~110 sweeps in 40s produced ~90 console
  warnings (`DataStore request was added to queue...`). **That rate is not
  player-reachable** — a real player must walk to each litter piece — so this is
  an artefact of my harness, recorded only so the next run does not mistake the
  warnings for a game fault.
- **Play stopped by itself three times**, mid-session, with an **empty console**
  each time (the log is cleared on stop, so nothing was captured). Unattributed.
  Each restart was clean. Flagging it as an environment risk, not a game defect.
- The meter does not accrue **at all** while `tickets >= MaxTickets`: three hunt
  finds and a `homeBonus` all left the meter at 424. This is the already-routed
  comment-vs-behaviour item; **not re-tested**, per instruction, but it dictated
  the test order — tickets had to be redeemed down to 3 before the ceiling and
  whitelist work could measure anything at all.

## NOT TESTED

- **Taxi fares and parcel deliveries at rate.** The ceiling was driven with
  **Sweeps** only. The clamp is in `meterAdd`, shared by every source through
  `pay()`, so I believe it is source-independent — but I did not drive taxi or
  parcels, so the "1,870 +/- 2% per 10 min" figure for those two sources is
  **not** measured. What I measured is the underlying allowance law, to -0.8%.
- **A bare, no-pass account.** Not reachable from this login (x4.875 throughout).
  Meter-neutrality of the passes is shown by base-vs-paid on every payout, not
  by a second account.
- **Phone entry points 2 and 3** (`EventTrayTap`, strip tap). Both need a live
  event; Play stopped while I was spawning one. Entry point 1 passed, and all
  three passed in the phone-ui feature pass.
- **The endless runner.** Reached only through the arcade prompt at
  `Places.CityExit`; I ran out of a stable Play session. The `UI.lua:816` guard
  is therefore **unverified at runtime**.
- **Leave-city cleanup of hunt rigs.** My test was invalid twice over: the
  height filter (0.80-1.15) also catches 0.55-scale NPC babies, and
  `SR_ShowMenu:Fire()` leaves `Activity = "city"` because the title is an
  overlay. I did measure cleanup **on claim** — the rig is undrawn and the
  prompt goes false at +5.27s and +6.63s — but not on leaving.
- **The two-player half of §6** (same three spots for two players). Still
  unreachable: the bridge drives one client. Determinism across a **server
  restart** is measured above and passes.

## CONSOLE

Final session, verbatim and complete:

```
Hello world, from server!
Hello world, from client!
```

No errors and no warnings. Earlier in the pass the log carried ~90 repetitions
of one line, all self-inflicted by the sweep-rate test:

```
DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.Key = u_827213592
```

## OWNERSHIP

No failures to assign. Files read this pass:
`game/SminskiServer.server.lua`, `game/Config.lua` — **server-engineer**;
`game/CityEvents.lua`, `game/City.lua`, `game/UI.lua`,
`game/SminskiTitle.client.lua` — **client-engineer**.

**Studio state:** Sminski place in **Edit**, Play stopped, all `QA_*` scaffolding
instances destroyed, character unanchored. Final account state: coins 173,815 ·
meter 1,421 · tickets 3 · streak 7 · day 2026-09-23 · `meterDayTickets` 0.
