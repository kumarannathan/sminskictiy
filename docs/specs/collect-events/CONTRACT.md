# CONTRACT — collect-events (short loops phase B)

Lead-written, 2026-09-21. Merges `ux.md` and `audio.md`. **This file wins any
conflict with either spec.** Builders build to this; if it is wrong, say so in
your report rather than improvising around it.

Read first: `BRIEF.md`, then your own lane's spec.

---

## 0. Lead decisions (the three conflicts, and why)

**D1. `mine` is renamed `myCount` everywhere.** `ux.md` §8D proposes a claim
reply field `mine` meaning "my new total". But `ev.mine` already exists in
`CityEvents.lua` as FIND's *boolean* "I claimed this", and `headline()`
(`CityEvents.lua:307`) skips any event with it set — `ux.md` itself warns that
a collect event must never set it. Two meanings, one word, one module is a bug
waiting to be written.

> **`myCount` (integer) is the player's item count. `ev.mine` stays strictly
> FIND's boolean and is never set on a collect event.**

**D2. Progress is flat fields, not `ev.progress`.** `audio.md` assumes
`ev.progress = { count, total }`; `ux.md` specifies flat `got` / `goal` /
`left` / `top`. The flat shape wins — it distinguishes cooperative from
competitive, which a single `count/total` pair cannot. Audio's logic maps:

| audio.md wrote | reads as |
|---|---|
| `progress.count / progress.total` (milestones, goal) | `got / goal`, cooperative only |
| `progress.count == progress.total` (last bag, `gold`) | `left == 0`, competitive only |

**D3. Auto-pickup gets its own rate bucket and a one-in-flight rule.**
`ux.md` §5 replaces the prompt with automatic pickup inside 6 studs. That is
right for 40 items, but it turns claiming from a button press into a movement
side effect, and the existing budget is `allow(s, "Events", 0.25)` — 4/s, which
a player running a dense scatter can brush against. See §3 and §5.

**D4. A live `collect` event outranks a `find` event for the strip** (added
2026-09-21, after QA's third pass). `headline()` has always picked the
soonest-ending event, so an ambient `SMINSKI SIGHTING` with 51s left evicted a
180s Balloon Festival — measured taking the tray away at **t = 3.01s into its
own 5-second finish celebration**, with `WE DID IT!` still on screen. The
shared counter *is* phase B, a FIND is live most of the time on a real server,
and the FIND loses nothing (it stays fully listed on the phone with its clock
and GO row).

> Among events of the same kind, keep the soonest-ending rule. The finish
> window between `done` and `end` must additionally be safe from eviction by
> any newly-starting event.

`renderTray`'s early return for a non-headline event is unchanged and correct —
this changes *which* event is the headline, not how many trays exist.

### Decided, and flagged for the human at review (not blocking)

All eight open questions from the two specs are decided here so the build can
run. Every one is reversible; the human overrules any of them at the gate.

| # | Question | Decision |
|---|---|---|
| UX1 | `CITY` as the shared-number label | **Keep.** It is the idea in four letters and matches CITY JOBS / CITY NEWS. |
| UX2 | `WE DID IT!` as the coop finish line | **Keep.** Warmest, and collective is the point of the phase. |
| UX3 | `heart` icon for Balloon Festival | **Keep** for phase B. Swapping is one line in `Config.Events`; a balloon icon is a Blender job and no new art ships here. |
| UX4 | Bystanders see the big line | **Keep.** It is the city's moment, not yours — hiding it re-privatises the thing phase B exists to fix. |
| UX5 | Auto-pickup with no prompt | **Keep**, with D3's guards. QA tests it specifically. |
| A1 | Brighter announce for competitive | **Keep.** One branch on `def.shared == false`. |
| A2 | Consolation `Chime` for 1–2 contributors | **Keep.** The finish card shows a small reward; a silent card reads as broken. |
| A3 | `gold` accent on Cash Drop's last bag | **Keep.** Free — reuses the existing `gold` flag. |

---

## 1. Geometry — measured, and binding

The server cannot raycast (the world is built on the client, `HANDOFF.md` §2),
so every position must be clear **by construction**. These numbers are not
negotiable at build time.

**The slot grid.** Each eligible lot offers exactly **4 slots**:

```
pos = lot.door + n * 2 + t * a,   a ∈ { -12, -4, +4, +12 }
n = Vector3.new(math.sin(lot.face), 0, math.cos(lot.face))   -- out from the door
t = Vector3.new(n.Z, 0, -n.X)                                 -- along the frontage
```

`+2` is the strip that measured **0/105 blocked with open sky** (`HANDOFF.md`
§5). `a` stays inside the brief's `[-13, 13]`. Spacing is ≥ 8 by construction:
within a lot the slots are 8 apart; adjacent lots' doors are 32 apart along a
street, so lot A's `+12` and lot B's `-12` are exactly 8 apart.

**The eligible-lot pool** is the existing `streetLots` filter
(`SminskiServer.server.lua` ~2182) — unchanged, do not touch it.

**Centre-lot viability — build this, it is a real failure mode.** I modelled
the 291 street-wall lots' door geometry (a lower bound; the real filtered pool
is ~381, so density is better than this):

| lots within 170 studs of a centre lot | |
|---|---|
| min | **3** |
| p10 | 10 |
| median | 15 |
| max | 25 |

At 4 slots per lot, 24 bags need 6 lots and a 48-item goal needs 12. **At the
worst-case centre lot only 3 are in range**, so a naive "pick a random centre,
scatter N" is sometimes unsatisfiable and a retry loop would spin. Therefore:

> At server start, precompute for each eligible lot the list of eligible lots
> within 170 studs. Keep as **centre candidates** only those with
> **≥ 12 neighbours** (capacity 48 ≥ any event's count). Pick centres from that
> set only. One-time O(n²) over ~381 lots at startup; do not compute it per
> event.

Requiring ≥ 12 keeps **80%** of lots as centres — a large pool, no clustering
concern.

**Two exclusions when placing each item** (cheap, ≤ 48 items, O(n²)):

1. Reject a slot within **8 studs** of an already-placed item this event.
   (Redundant with the grid inside a street, but it covers corner lots where
   two frontages meet at an angle the grid does not reason about.)
2. Reject a slot within **12 studs** of any live event's `ev.pos`. A hidden
   FIND spot is `door + t*±11 + n*2.5`; a collect item at `a = +12, n = +2`
   lands **0.5 studs** from it. Two claimable things in one place is a bug,
   and it will happen without this check.

If after both exclusions fewer than `count` slots remain, **place what fits and
set `goal`/`count` to the number actually placed.** Never loop waiting for a
slot, and never place an item you could not verify.

---

## 2. Config — exact tables

Added to `Config.Events` (`game/Config.lua`, after the existing `List` rows —
**append only**, FIND's three rows are untouched):

```lua
Config.Events.PickupRadius = 6      -- client auto-claims inside this
Config.Events.PickupServer = 9      -- server validates at this, to absorb latency + streaming
Config.Events.Zone = 170            -- scatter radius from the centre lot
Config.Events.SlotsPerLot = 4
Config.Events.MinCentreLots = 12    -- see §1; supports the 48-item cap
```

Three new rows in `Config.Events.List`:

```lua
{ id = "cashdrop", kind = "collect", open = true, shared = false,
  title = "CASH DROP!", icon = "coin", noun = "bags", verb = "GRAB",
  warn = 45, lasts = 150, weight = 10, minPlayers = 2,
  count = 24, each = 60, xp = 3 },

{ id = "balloons", kind = "collect", open = true, shared = true,
  title = "BALLOON FESTIVAL", icon = "heart", noun = "balloons", verb = "POP",
  warn = 45, lasts = 180, weight = 10, minPlayers = 1,
  base = 12, per = 8, maxCount = 48, each = 8, xp = 2,
  bonusAt = 3, bonus = 220, bonusXp = 20 },

{ id = "cleanup", kind = "collect", open = true, shared = true,
  title = "CITY CLEANUP", icon = "bag", noun = "litter", verb = "BIN",
  warn = 45, lasts = 180, weight = 10, minPlayers = 1,
  base = 12, per = 8, maxCount = 48, each = 8, xp = 2,
  bonusAt = 3, bonus = 220, bonusXp = 20, credits = "cleaner" },
```

**Goal scaling** (cooperative only), computed once at `start()` from players
with `Activity == "city"`:

```lua
goal = math.clamp(def.base + def.per * (nCity - 1), def.base, def.maxCount)
-- 1 player -> 12,  2 -> 20,  3 -> 28,  4 -> 36,  5 -> 44,  6+ -> 48
```

Then clamp again to the number of items actually placed (§1).

### Economy check (`LOOPS.md` §6: a paced job is ~187 coins/min)

| Case | Coins | Minutes | Rate |
|---|---|---|---|
| Coop, 4 players, goal 36, even split (9 each) | 9×8 + 220 = **292** | 2.5 | **117/min** |
| Coop, solo, goal 12, all 12 | 12×8 + 220 = **316** | 2.5 | **126/min** |
| Cash Drop, 4 players, 6 bags each | **360** | 2.5 | **144/min** |

All under the job rate, as `LOOPS.md` §6 requires.

**One flagged risk.** A solo player who swept all 24 bags would earn 1,440 in
2.5 min = **576/min**, three times the job rate. The brief fixes 24 × 60, so I
have **not** changed it; instead `cashdrop` gets `minPlayers = 2`, which is what
"split across the server" means and uses the director's existing filter. **QA
must measure how many bags one player can actually reach in 150s** (§6) so the
human tunes from a number rather than from this paragraph.

---

## 3. Remotes — no new remote, no new RemoteEvent

Everything rides the existing `Events` RemoteFunction and `CityEvent`
RemoteEvent. **FIND's payload shapes are untouched.**

### `Events:InvokeServer("state")` — reply gains, per collect event

```
got = 17, goal = 40, left = nil, myCount = 0, top = nil
```
`goal` is cooperative only (nil otherwise); `left` is competitive only.
`myCount` is per-player, so a mid-event joiner gets 0.

### `Events:InvokeServer("claim", uid, itemId)` — collect only

`itemId` is an integer, server-assigned, unique within the event.

Reply: `{ ok = true, coins, xp, myCount, got, left, goal, top }`
or `{ ok = false, reason = <string> }` where `reason` is **exactly one of**:

| reason | when |
|---|---|
| `"too far away"` | beyond `PickupServer` (9 studs) |
| `"already gone"` | that `itemId` is already claimed — **including losing a race** |
| `"it's over"` | event ended, or a cooperative goal is already met |

Lower case, no other strings — `ux.md` §5 renders these verbatim in the tray.
FIND's existing reasons are unchanged.

**Rate limit (D3).** Collect claims use their own bucket,
`allow(s, "EventsPickup", 0.1)` (10/s), not the 4/s `"Events"` bucket. A
refused claim still consumes budget; exceeding it returns
`{ ok = false }` with no reason (silent, same as today).

### `CityEvent` broadcasts

| Event | Payload | Notes |
|---|---|---|
| `"start"` | existing `publicEv` + `got`, `goal`, `left`, `top`, and `items = { { id, x, z }, ... }` | `spot` = **zone centre**, existing shape, so `mark()` and GO work unchanged. Collect is `open`, so there is no `reveal` and no secret. |
| `"progress"` | `{ uid, got, left, goal, top }` | **Coalesced server-side to ≤ 4/s per event**, sent only when `got` changes. |
| `"taken"` | `{ uid, itemId, by }` | So every client removes that item. `by` is a DisplayName, used only to decide the `C.sky` "someone else" pulse. |
| `"done"` | `{ uid, why, got, goal, top }` | `why` ∈ `"goal"` / `"empty"` / `"time"`. |
| `"end"` | existing shape | Fires ~5s after `"done"` (§4). Existing teardown. |

Per-player at the finish: `FireClient(p, "reward", { uid, myCount, bonus })` to
**every player with `myCount > 0`**. `bonus` is coins actually paid, 0 if none.

---

## 4. Server behaviour

- **Payment** goes through the existing `pay(player, s, coins, xp, "EventsDone")`
  so passes and boosts multiply it exactly as in phase A. Per item: `def.each`.
  Completion bonus: `def.bonus`, paid once, only to players with
  `myCount >= def.bonusAt`, only when `why == "goal"`.
- **Cleanup credits a shift.** Every successful `cleanup` item additionally
  calls `creditWorld(player, s, "cleaner", 1, got)` (`SminskiServer.server.lua:2068`)
  where `got` is the coins that claim just paid. `creditWorld` no-ops unless the
  player is clocked in as a cleaner, so this is safe unconditionally.
- **One claim per item, ever.** `ev.taken[itemId] = userId`, checked and set in
  the same synchronous block as the payment — no yield between the check and the
  set, or two claims race through it. This is the exploit QA tests.
- **There is no once-per-player limit** on a collect event — a player may take
  many items. Do not reuse `ev.claimed`.
- **Ending.** Cooperative: on `got >= goal` fire `"done"` with `why = "goal"`,
  then end the event **5s later**. Competitive: on `left == 0` fire `"done"`
  with `why = "empty"`, end 5s later. Either on timeout: `"done"` with
  `why = "time"`, end immediately. The 5s is what gives the finish moment room
  to play before teardown.
- **After a cooperative goal is met**, further claims return `"it's over"`.
  Remaining items despawn with the event.
- `ev.quiet` is never set on a collect event; they are public by design.

---

## 5. Client behaviour

- **Auto-pickup.** Inside `PickupRadius` (6), the client claims automatically.
  **One claim in flight at a time**, and **never retry an `itemId` that was
  refused** — remember refused ids for the life of the event. Without both, a
  player standing on a claimed item generates a claim every frame.
- **`ev.mine` is never set on a collect event** (D1) — it would delete the strip
  via `headline()`.
- **`E.prompt` gains `ev.def.kind ~= "collect"`** (`CityEvents.lua:285`).
- **`claim()`'s trailing `Audio.play("BigChime", 1.25, 0.8)`
  (`CityEvents.lua:281`) branches on `ev.def.kind`.** FIND keeps that line
  byte-for-byte; collect uses `audio.md`'s pickup run instead. This is the one
  behaviour change to shared code, and it is required — without it every
  balloon fires FIND's finale sound.
- **Do not use `UI.toast`, `UI.popText` or `UI.banner`.** They do not render in
  the city: `popLayer` and `banner` are children of `hud` (`UI.lua:515, 538`),
  `hud.Visible = mode == "run"` (`UI.lua:2259`), and the city runs
  `UI.setMode("none")` (`SminskiRunner.client.lua:1245`). Verified by the lead.
  Refusals go in the tray (`ux.md` §5). **Fixing this is out of scope here** —
  see §9.
- **The litter helper.** Factor the recipe inlined in `City.lua` `applyState`
  (~434) into `function City.litterModel(cf, kind)` in `City.lua`, and call it
  from both `applyState` and `CityEvents.lua`. `City.Events` is constructed at
  `City.lua:1859` and receives the `City` table, so `City.litterModel` is
  reachable. **Do not copy the recipe.** Both files are client-engineer's.
- **No new GUI or light per item** (`performance.md`). Balloons reuse the fun
  park recipe (`CityBuild.lua` ~2009: 2.4 ball, `Reflectance = 0.15`, thin
  string, `K.CAR_COLORS`); coins reuse `StarCoin` via `Models.rigMesh`
  (`World.lua` ~1222). Pool the parts.
- UI geometry, strings, colours, timings: **`ux.md` §2–§7 verbatim.**
  Sounds, pitches, volumes, the run/reset logic and the silence list:
  **`audio.md` verbatim**, with D2's field mapping.

---

## 6. Test hooks (QA cannot verify what it cannot trigger)

Extend the Studio-only `EventsDev` (`SminskiServer.server.lua:2436`):

1. `EventsDev:InvokeServer(id, atMe)` — for a collect event the reply gains
   `items = { { id, x, z }, ... }`, **every** item, so QA can sample real
   positions without guessing. With `atMe`, the zone centre is the eligible
   centre lot nearest the caller.
2. `EventsDev:InvokeServer("raceTest", uid, itemId)` — **new.** Resolves two
   claims against the same `itemId` concurrently, server-side, and returns
   `{ a = <reply>, b = <reply> }`. This is how the two-claims-racing-one-bag
   exploit gets tested without two Studio clients.
3. `EventsDev:InvokeServer("endNow", uid)` — **new.** Ends a live event
   immediately, so the after-the-event claim path is testable in seconds.

All three are inside the existing `if RunService:IsStudio()` guard.

---

## 7. Work split

Every file already has exactly one owner in `.claude/team/ownership.json`.
**No new files, so no ownership-map change is needed.**

| File | Owner | Changes |
|---|---|---|
| `game/Config.lua` | `server-engineer` | §2 in full: five tunables, three `List` rows. Append only. |
| `game/SminskiServer.server.lua` | `server-engineer` | §1 centre-lot precompute + slot grid + two exclusions; §3 remote shapes; §4 director, claim, payment, `creditWorld`, ending; §6 three dev hooks. |
| `game/CityEvents.lua` | `client-engineer` | §5 auto-pickup, the `kind` branches, drawing/pooling for three item types, the progress tray, the finish moment, phone rows — `ux.md` §2–§7, `audio.md` in full. |
| `game/City.lua` | `client-engineer` | `City.litterModel(cf, kind)` factored out of `applyState`; `applyState` calls it. Nothing else. |
| `game/_sr_sync.lua` | `client-engineer` | **Only if** a new module is added. None is expected — `CityEvents` is already in the list. |

**Assets: none.** All three events reuse approved geometry (§5). Nothing goes
to the human for art approval in this feature.

**Saved data: none.** No new fields on the save. `data.City.spotted` is
untouched. Collect state is per-event and session-only, so there is no
migration and nothing to roll back.

---

## 8. Acceptance — the measurable checks

1. Three collect events start from the **existing** director; no second
   director, no new remote, no new RemoteEvent.
2. **Six or more real item positions**, read from the `EventsDev` `items`
   reply, are each: within 2.5 studs of the pavement `y`, not inside geometry,
   ≥ 8 studs from every other item, and ≥ 12 studs from any live FIND spot.
3. `got` moves on **every** connected client within 0.25s of a pickup; a
   second player's pickup moves the first player's tray.
4. `myCount` and `got` are never confused: after player A takes 3 and player B
   takes 2, A's tray reads `YOU 3` and `CITY 5`.
5. **The four exploit paths all fail closed:**
   - same item twice → second reply `{ ok = false, reason = "already gone" }`, no second payment
   - from 40 studs → `"too far away"`, no payment
   - after the event ends → `"it's over"`, no payment
   - two claims racing one bag (`raceTest`) → exactly one `ok = true`, exactly one payment, the other `"already gone"`
6. Cooperative goal reached → `"done"` with `why = "goal"`, bonus paid **only**
   to `myCount >= 3`, event gone ~5s later, models removed.
7. Cleanup items credit a clocked-in cleaner (shift `tasks`/`earned` move);
   they no-op for a player who is not clocked in.
8. FIND is unregressed: sighting / pup / ice cream still announce, claim, pay
   and expire, and still play `BigChime` 1.25/0.8 on claim.
9. Console clean through a whole event, start to teardown.
10. **Measurement, not pass/fail:** how many of the 24 bags can one player
    reach in 150s? Report the number — it decides whether 24 × 60 needs tuning.

---

## 9. Known, out of scope, needs an owner

**`UI.toast` / `UI.popText` / `UI.banner` do not render in the city.** Found by
`ux-designer`, verified by the lead against `UI.lua:515, 538, 2259` and
`SminskiRunner.client.lua:1245`. Phase A's three toasts
(`CityEvents.lua:236, 401, 406`) and the confirmation inside `earned()`
(`City.lua:1760`) are silently invisible today. `HANDOFF.md` §5 records the
"get closer" refusal as verified — the server did refuse, but the player was
never told why.

Not fixed here: the fix is either reparenting `popLayer`/`banner` in `UI.lua`
or removing the city's calls, both of which touch the runner's HUD layering and
risk regressing phase A and the runner. **This feature depends on neither.**
Raised separately for the human.
