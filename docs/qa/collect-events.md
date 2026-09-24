# QA — collect-events (short loops phase B, COLLECT archetype)

**VERDICT: FAIL** — 8 of 10 CONTRACT §8 acceptance items pass. Two fail:
§8.6 (the cooperative/competitive **timeout** finish is silently dropped on the
client — no notification, no sound, no dimmed tray) and §8.9 (console is not
clean: one DataStore write per collected item floods the queue warning).
Everything else measured clean, including all four exploit paths.

**BUILD:** synced 2026-09-21 from `~/Desktop/SminskiCity/game` via
`python3 -m http.server 8765` + `_G.SR_sync()` loaded from
`http://127.0.0.1:8765/_sr_sync.lua`. Byte counts confirmed identical to disk
after sync: `CityEvents` 62,382 · `Config` 59,721 · `SminskiServer` 111,076.
Studio: `Sminski City: Explore, Work, Run, Shop` (placeId 123228656219050),
viewport **1160 × 719**, `UI` scale **0.90625** (design canvas 1280 × 793.6),
`UI.compact()` = false, GuiInset (0, 58).
Studio account holds every pass (`citypro`, `double`, `vip`, …): every payout
came back at **×4.5** the base. Base figures are quoted throughout with the
multiplier stated.

---

## CHECKS

### §8.1 — three collect events from the existing director  PASS (with a caveat)
- `Config.Events.List` carries `cashdrop` / `balloons` / `cleanup` exactly as
  CONTRACT §2 specifies; FIND's three rows untouched; the five tunables
  (`PickupRadius 6`, `PickupServer 9`, `Zone 170`, `SlotsPerLot 4`,
  `MinCentreLots 12`) are present.
- No new remote: claims ride `SminskiRemotes.Events` (RemoteFunction) and
  broadcasts ride `SminskiRemotes.CityEvent` (RemoteEvent). Remote list
  enumerated in Play — 32 remotes, no additions beyond `EventsDev` (Studio-only).
- All three started and ran end to end. **Caveat:** I never observed a
  *naturally scheduled* collect headline — `sighting`, `lostpup` and `icecream`
  appeared unprompted, collect events were always started through the
  documented `EventsDev` hook. `cashdrop` **cannot** be scheduled with one
  player (`minPlayers = 2`) by design; `balloons`/`cleanup` are `minPlayers = 1`
  and simply did not come up on the roll.

### §8.2 — geometry, 24 real item positions  PASS
Read from the `EventsDev` `items` reply; nothing guessed.

| Measure | Required | Measured |
|---|---|---|
| items placed (cashdrop) | 24 | **24** (3 separate events: 24, 24, 24 — exclusions ate nothing) |
| closest pair, squared | ≥ 63.5 | **64.000** (8.000 studs), pair ids 1↔2 |
| furthest item from zone centre | ≤ 170 | **155.21** |
| ground under item (raycast down) | pavement `CITY.Y + 0.45` | **0.450** on all 22 items measured in-world |
| world-space min Y of item model | within 2.5 of pavement | **1.350** = 0.900 above pavement top (deliberate coin hover) |
| solids in a 3×3×3 box at y 1.6 | none but ground | **1**, and it is `SminskiCity.Ground.Part` (the 260×0.45×260 pavement slab) on all 22 |
| open sky (raycast +300 up) | clear | **open** on all 22 |
| nearest bag to the pup's spot | ≥ 12 | **46.17** (`lostpup` started first, `cashdrop` second, both `atMe`) |

Positions sampled (city-local x,z): (-98,-870) (-90,-870) (-82,-870)
(-74,-870) (-66,-870) (-58,-870) (-38.5,-870) (98,-870) (143.5,-870)
(159.5,-870) (167.5,-870) (30,-690) (30,-706) (30,-743.5) (30,-759.5)
(30,-802) (-30,-658) (-30,-674) (-30,-682) (-30,-698) (-30,-786) (-30,-810)
(-30,-818) (-30,-826).
22 of 24 were inside client draw range at the two sample points; the two I
could not draw were measured analytically only (spacing + radius).

Note on the 12-stud FIND exclusion: 46.17 studs satisfies it, but with the pup
46 studs from the zone centre the exclusion was never actually *exercised* —
no candidate slot was inside 12 of it. The rule itself is unverified under
pressure. Also measured, unchanged from phase A: pup model world min Y
**0.4516** (0.0016 above pavement) and sighting NPC min Y **0.392**
(0.058 *below* pavement — pre-existing, not phase B).

### §8.3 — `got` moves on every client within 0.25 s  PASS (single client)
A claim resolved **server-side, outside the client's own claim path**
(`Events:InvokeServer("claim", …)` from the test VM) moved the tray text
`23 BAGS LEFT` → `22 BAGS LEFT` **51.8 ms** after the call was issued (1.7 ms
after the reply landed). Same mechanism on a `raceTest` claim: `left` 24 → 23
on my tray while my own `myCount` stayed 0.
Two Studio clients were not run — see NOT TESTED.

### §8.4 — `myCount` and `got` never confused; `ev.mine` never set  PASS
- 21 consecutive pickups on one cashdrop: strip `Visible = false` for
  **0 frames**, tray `Visible = false` for **0 frames** (Heartbeat-sampled
  across the whole 44 s sweep). `ev.mine` is never written for a collect event.
- The two numbers are provably distinct fields: after a `raceTest` claim moved
  `got` 0→1 and `left` 24→23, `trayMine` still read `YOU 0 BAGS`.
- Tray strings observed, all matching ux.md: `CITY 0 of 12` / `YOU 0 of 3` →
  `YOU 1 of 3` → `YOU 2 of 3` → `BONUS LOCKED` (mintDark) → `YOU 5 · BONUS` →
  `HALFWAY!` (mintDark, at got = 6 of 12) → `YOU 12 · PAID`;
  competitive: `24 BAGS LEFT` (ink) → `3 BAGS LEFT` (coral, ≤25 %) →
  `ALL GONE` (coral), `YOU 21 · LEADING` → `YOU 24 · TOP`.
- Phone `GO` visibility was not measured directly (it is gated on
  `not ev.mine` and `ev.spot ~= nil`, both of which hold).

### §8.5 — the four exploit paths  ALL PASS
| Path | Reply | Payment |
|---|---|---|
| same item claimed 2nd and 3rd time | `{ ok = false, reason = "already gone" }` both times | coins **73837 → 74107 → 74107 → 74107** (Δ 270, 0, 0) |
| from 40.00 studs (stand point 32 studs from the nearest *other* item) | `{ ok = false, reason = "too far away" }` | Δ **0** |
| after `endNow` (valid id **and** id 9999) | `{ ok = false, reason = "it's over" }` both | Δ **0** |
| in the ~5 s between `done` and `end` (goal met; taken id **and** id 9999) | `{ ok = false, reason = "it's over" }` both | Δ **0** |
| `raceTest` on one bag | `a.ok = true`, `b = { ok = false, reason = "already gone" }` | `paid` = **270** = exactly one bag (60 base × 4.5), `got` 0 → 1 |

Absurd arguments, all on a **live** event while standing 7.5 studs from an
item, all returned `{ ok = false, reason = "already gone" }` with **0 coins**:
`9999`, `-1`, `0`, `"abc"`, `1e18`, `0/0` (NaN), `{ score = 9999 }`, `nil`.
An unknown `uid` returns FIND's pre-existing `"too late -- it has gone"` — the
server cannot know the kind of an event it has never heard of, so this is not
one of the three collect strings and is correct; a *recently ended* collect uid
correctly returns `"it's over"` from the `gone[uid]` map.

### Refusal recoverability  PASS
Sprinting a bag at WalkSpeed 200 produced a genuine client-side refusal:
`trayCity` read **`too far away`** in coral for **43 frames (~0.72 s)** in a
visible tray. At that moment the item was still listed by the server
(`got` 0, `myCount` 0 — no payment). After backing off 0.8 s and standing on
it, the item was collected (`got` 0 → 2, `myCount` 0 → 2) and no longer
listed. The refusal did not kill the item. At the normal WalkSpeed **26** no
refusal fired at all across a full 24-bag walking sweep.

### Tray, numerically  PASS
| Property | Expected | Measured |
|---|---|---|
| `EventTray.Size` | (340, 46) desktop | **{0,340},{0,46}** |
| `EventTray.Position` | (0, 50) | **{0,0},{0,50}** |
| `EventTray.ZIndex` | 4 | **4** |
| `AbsolutePosition` | ≈ (470, 202) at scale 1 | **(425.9375, 125.0625)** → design **(470.0, 202.0)** after dividing by scale 0.90625 and adding the 58 px inset |
| bottom | ≈ 248 | design **248.0** (`absSize` 308.125 × 41.6875 = 340 × 46 × 0.90625) |
| `EventTrayTrack` | (308, 10) at (16, 30) | **{0,308},{0,10}** at **{0,16},{0,30}**; design abs (486, 232) |
| ancestors clipping the tray | none | `ClipsDescendants = false` on every ancestor |
| hit test at tray centre | tray present | `GetGuiObjectsAtPosition` returns `EventTray`, `EventTrayTap`, `EventTrayCity` |
| overlap with neighbours | none | nothing but full-screen root frames at y 172.75 (just below) or in the tray rows; the row above (y 121) is the strip's own card |
| gap between `CITY` and `YOU` labels | — | **0.0 px** (CITY right edge 656 design = YOU left edge 656). They touch but do not overlap; both carry `TextTruncate.AtEnd`. |

### Instance count does not scale with item count  PASS
`#tray:GetDescendants() + 1` = **12** during a 12-item `balloons` event,
**12** during a 12-item `cleanup` event, and **12** during a 24-item
`cashdrop` event — identical. Children: UICorner, UIScale, `EventTrayTap`,
`EventTrayCity` + UIScale, `EventTrayMine` + UIScale, `EventTrayTrack` +
UICorner, `EventTrayFill` + UICorner. The big line (`EventBigLine`,
`EventBigText` + its UIStroke + `UIScale`) adds 4, created once in `E.init`.

Per-item world cost, measured on live items:
- balloon: **2** parts (ball + string)
- cash bag: **1** part
- litter: **3** parts × 7 models, **2** parts × 4 models
- `BillboardGui` / `SurfaceGui` / `PointLight` / `ParticleEmitter` among items:
  **0** of each, on all three item types.
- After teardown the pool is parked in an unparented Folder — 0 event models
  left in `workspace` (see Cleanup).

### §8.6 — the finish, timed  FAIL (goal and empty pass; **time** fails)

**Cooperative goal**, t = 0 at `sClock` becoming `DONE` (Heartbeat-sampled):

| t (measured) | Spec | What happened |
|---|---|---|
| 0.00 | 0.00 | `sClock` = `DONE`; fill tween starts from 0.9167 |
| 0.21 | 0.18 | `trayFill` reaches 1.0 |
| 0.09 | 0.10 | `bigText` = **`WE DID IT!`**, `bigHolder.Visible = true`, `TextTransparency` 0 |
| 0.25 | 0.25 | `trayMine` → `YOU 12 · PAID` |
| 0.43 | **0.00** | `trayCity` → `CITY 12 of 12` — **late, see FAILURE 3** |
| — | 0.60 | `City.popCoins(990)` fired: a `BillboardGui` appeared in `PlayerGui` for **104 frames (~1.7 s)** |
| — | 0.80 | one notification (`Click@1.3` in the sound log at +0.817) |
| 3.88 → 4.34 | 3.70 + 0.5 s | `TextTransparency` **and** `UIStroke.Transparency` ramped together: 0.248 / 0.461 / 0.640 / 0.781 / 0.888 / 0.971 / 0.995 / **1.000** — both properties, in lockstep |
| 4.31 | 4.20 | `bigHolder.Visible = false` |
| 5.01 | ~5.0 | tray `Visible = false`, event removed, models gone |

Bonus paid **only** through the `myCount ≥ 3` gate: coins moved
**85177 → 86203 = +1026** = 36 (one balloon, 8 base × 4.5) + **990**
(bonus 220 base × 4.5). Nothing paid to the two refused claims in the window.

**Cash Drop empty**, t = 0 at `GONE`:
`sClock` = **`GONE`** at 0.00 · `bigText` = **`YOU TOOK THE MOST!`** (gold) at
0.11 · `trayMine` → `YOU 24 · TOP` at 0.26 · `trayCity` → **`ALL GONE`** at
0.43 · fade 3.84 → 4.24 on both transparencies · `Visible = false` at 4.31 ·
event gone at ~5.04. **`popCoins` did not fire** — 0 BillboardGui frames on
the character across the whole sequence, as required.

**Cooperative timeout** (`why = "time"`, via `endNow`, which calls the
identical `finishCollect(ev, "time")` the 1-second tick loop calls):
no big line (**0 frames visible**, correct), no `popCoins` (**0 frames**,
correct), no bonus (**coin delta 0**, correct) — **and also no notification and
no sound at all**, which is wrong. See FAILURE 1.

### Audio call counts  PASS
Measured by connecting `Sound.Played` on every voice in
`SoundService.SminskiAudio` and by sampling `BigChime1.PlaybackSpeed` per
Heartbeat (necessary: `BigChime` has one voice, so `Played` does not re-fire
when `Audio.play` restarts an already-playing sound — a measurement trap, not
a bug).

| Cue | Expected | Measured |
|---|---|---|
| milestone `Chime` | ≤ 3 per event, 1.00 / 1.15 / 1.30 | exactly **3**: pitch **1.000** at got 3/12, **1.149** at 6/12, **1.299** at 9/12 |
| goal sequence | `BigChime` 1.15/0.7 + `BigChime` 1.50/0.9 (+0.30) + `Chime` 1.80/0.45 (+0.55), once | `BigChime` pitch **1.149** vol **0.28** (= 0.4 × 0.7) at t 0; `PlaybackSpeed` **1.50** from +0.29 to +0.84; `Chime` pitch **1.799** vol **0.1574** (= 0.35 × 0.45) at **+0.567**. Fired exactly once. |
| personal bonus | `BigChime` 1.35/0.85, ~+0.85 after the fanfare | `PlaybackSpeed` **1.35** from +0.86 to +1.19 |
| announce, cooperative | `BigChime` 1.05/0.6 | pitch **1.049** vol **0.2399** |
| pickup run | `Tick` at 1.5 × pentatonic, 12 pickups | **12** Ticks, pitches 1.5 / 1.682 / 1.889 / 2.246 / 2.523 / 3.0 / 3.367 / 3.779 then wrapping to 1.5 |
| **rejected claim** | zero `Audio.play` | 3 consecutive refused claims (`already gone`) → **0 sounds** |
| after the event is killed 0.1 s past the goal | nothing at +0.30 / +0.55 | killed at **+0.165**: `PlaybackSpeed` stayed **1.14** for **140 frames (~2.3 s)** — the +0.30 `BigChime` dropped; **no** `Chime@1.80` |
| after the event is killed 0.4 s past the goal | nothing at +0.55 | killed at **+0.483**: `PlaybackSpeed` 1.14 → **1.50** (the +0.30 note, correctly already played) then held; **no** `Chime@1.80` |
| after the player leaves the city, then the event ends | nothing | sound log across the exit: only `Lobby@1` (hub music) and `Whoosh@1.1` (transition); after `endNow` while in the hub: **0 sounds over 6 s** |

### §8.7 — cleaner credit  PASS
Clocked in with `Job:InvokeServer("start","cleaner")` (`weight = 0.12`), then
collected 12 `cleanup` items one at a time:

`shift.earned` after each pickup: **72, 108, 144, 180, 216, 252, 288, 324,
360, 396, 432** — exactly **+36 per item** (8 base × 4.5).
`shift.tasks`: 0 for pickups 1–8, ticks to **1 on the 9th** (1 / 0.12 = 8.33),
final `tasks = 1, earned = 432, score = 100`.
The completion bonus is deliberately **not** credited to the shift (432 = 12 × 36).

Not clocked in: `Job:InvokeServer("quit")`, then two `cleanup` pickups →
`jobs.shift` **nil before and after** (no shift created, nothing credited),
while the coins still paid normally (**+72**). `creditWorld` no-ops as
designed.

### §8.8 — FIND unregressed  PASS
| Event | Claim | Paid (base × 4.5) | Sound |
|---|---|---|---|
| `icecream` | clicked the real `ORDER` prompt button (145 × 51.66 at abs 635.28, 536.5) → `found = 1`, `firstBy` = me | **+1440** = (200 + 120 first) × 4.5 | — (masked by a following announce; see `lostpup`) |
| `lostpup` | clicked the real `RESCUE` prompt → `found = 1`, `firstBy` = me, pup model removed 3 s later | **+2070** = (260 + 200 first) × 4.5, i.e. **460 base × 4.5** | **`BigChime` pitch 1.25, vol 0.3199** = `Audio.play("BigChime", 1.25, 0.8)`, byte-for-byte FIND's finale |
| `sighting` | reveal fired at range, NPC drawn (`Sminski_Lemon`), claim from 4.47 studs → `ok`, `skin = "chef"`, `tier = "common"`, `isNew = true`, collection grew to 2 | **+810** = (100 + 80 first) × 4.5 | — |
| second claim, same player | `{ ok = false }` silently (`ev.claimed`) | **Δ 0** | — |
| expiry | `endNow` → models and beacon removed | — | — |

### §8.9 — console  FAIL
No error or warn from `CityEvents.lua`, `City.lua`, `Config.lua` or
`SminskiServer.server.lua` across ~12 collect events (three ids, goal /
empty / timeout finishes, teardown, and leaving the city mid-event) — and
notably no `streamStep` warns, so no world-builder breakage.
But 21 engine warnings accumulated (see FAILURE 2). Verbatim log in CONSOLE
below.

### §8.10 — how many bags can one player reach in 150 s?  **24 of 24**
Measurement, not pass/fail, and the number is decisive.

- Greedy nearest-neighbour tour over all 24 bags from the zone centre:
  **945.85 studs**. At the player's actual `WalkSpeed` **26** that is
  **36.4 seconds** of pure walking.
- Empirical walk (`Humanoid:MoveTo`, greedy nearest unclaimed, real
  navigation, no teleporting): **21 of 24 in 44.1 s** with **86.0 s still on
  the clock**, then **all 24 in a further 9.7 s** — **24 of 24 in ~54 s of
  a 150 s window**.
- Economy consequence, at base rates: 24 × 60 = **1,440 coins in 0.9 min ≈
  1,600 coins/min**, against `LOOPS.md` §6's paced-job rate of **187/min** —
  about **8.5×**. CONTRACT §2 estimated a solo sweep at 576/min assuming the
  full 2.5 min; the sweep actually takes a third of that. `minPlayers = 2`
  does not help much: two players splitting 24 bags still clear the pool in
  under a minute and earn ~800 coins/min each.
- The route is not even hard — the scatter clusters along two street walls
  (11 bags on one 130-stud run at z = -870, 5 more on a straight x = 30 run).

### Cleanup  PASS
- After a goal finish: **0** `EventBalloon` / `EventCashBag` / `EventLitter` /
  `EventBeacon` anywhere in `workspace`; tray `Visible = false`.
- After `endNow`: same, **0** of each.
- **Leaving the city mid-event** (walked into `Places.CityExit`, 24 bags and a
  beacon live at the time): `Activity` → `hub`, `SminskiCityActors`
  unparented, **0** event models in `workspace`, tray hidden, big line hidden,
  and ending the event afterwards produced no sound and no visible card.

### Regression  PASS
- `City.hudOff`: with a collect event live, opening SHOP from the menu hid all
  **8** HUD buttons (MENU / HOME / MAP / HELP / WORK / SHOP / TOWN / PHONE)
  *and* the tray (`EventTray.Visible` stayed `true`, ancestor chain went
  `false` — swept by `City.hudVisible`, exactly as ux.md intends).
- **MENU → SHOP → close → RESUME**: after RESUME all **8** HUD buttons are
  visible again at their original `AbsolutePosition`s, and the tray is
  restored (`own = true`, chain `true`, abs (425.94, 125.06) — unchanged).
  No HUD loss.
- Title menu renders and routes all five options: `[RESUME]`,
  `[GO TO MY HOUSE]`, `[WORK]`, `[SHOP]`, `[SETTINGS]`; SHOP opened and closed
  through real clicks.
- Follow camera after entering the city: `CameraType = Custom`,
  `CameraSubject = Workspace.indiannarwhal.Humanoid` — checked on first entry,
  after RESUME, and after the hub transition.

---

## FAILURES

### FAILURE 1 — the timeout finish is silently dropped on the client (§8.6)
**What happened.** When a collect event ends on `why = "time"` the player is
told nothing at all. ux.md §4 requires one notification —
`("hourglass", "BALLOON FESTIVAL OVER", "the city got 31 of 40 · no bonus this
time", C.inkSoft)` — plus `trayCity` dimming to `C.inkSoft` with the bar left
where it got to, and audio.md's consolation `Chime` 1.15/0.5 for a contributor
who missed the bonus.

**Measurement.** `balloons`, goal 12, `myCount = 4`, ended with 8 items still
out. Over the 7 s after the `done` broadcast: **0 sounds** on any pool
(`J.notify` always plays `Click@1.3`, so zero Clicks means zero
notifications), **0 popCoins** frames, **0 big-line** frames, coin delta
**0**. Repeated on a second event with the same result. Contrast the goal
path, where the notification's `Click@1.3` is logged at **+0.817 s**.

**Most likely cause.** On the timeout path the server tears the event down in
the same frame it announces it:

- `game/SminskiServer.server.lua:2543-2544` — `if why == "time" then finish(ev)`,
  so `FireAllClients("done", …)` and `FireAllClients("end", …)` arrive in the
  same client frame (the other two paths get `task.delay(5, …)` at :2546).
- `game/CityEvents.lua:708-710` — `runFinish`'s notification is
  `task.delay(0.80, function() if E.list[ev.uid] == ev then finishNotify(…) end end)`,
  and `onEnd` has already done `E.list[info.uid] = nil` by then, so it drops.
- `game/CityEvents.lua:953-958` — `onReward`'s consolation sound is behind the
  same `E.list[info.uid] ~= ev` guard, with `wait = 0` on a timeout
  (`ev.fanfareAt` is nil), so it also drops on the next frame.
- `game/CityEvents.lua:845` — the intended fallback
  `if not ev.finished then finishNotify(ev, "time") end` cannot fire, because
  `onDone` → `runFinish` (`CityEvents.lua:681`) has already set
  `ev.finished = "time"`.

Either side can fix it: delay `finish(ev)` ~1 s on the timeout path, or call
`finishNotify` synchronously when `why == "time"`.
**Owners:** `game/SminskiServer.server.lua` → **server-engineer**;
`game/CityEvents.lua` → **client-engineer**. Needs one of them, not both.

### FAILURE 2 — one DataStore write per collected item (§8.9)
**What happened.** The console filled with
`DataStore request was added to queue. If request queue fills, further
requests will be dropped.` — **21 occurrences**, all keyed `u_827213592` (my
user). They accumulated only while I was sweeping collect items and stopped
growing the moment the sweeps stopped.

**Measurement.** 24 bags collected in 44 s = 24 `pay()` calls in 44 s. A
48-item cooperative event with six players is up to 288 saves inside three
minutes, against Roblox's ~(60 + 10 × players) requests/minute budget.

**Most likely cause.** `game/SminskiServer.server.lua:1465` — `pay()` ends with
`task.spawn(save, player)`, and `collectClaim` calls `pay()` once **per item**
(`game/SminskiServer.server.lua:2589`). Nothing else in the game pays at this
rate. A debounced/coalesced save for collect claims (or saving on the
`done`/`reward` boundary only) would fix it.
**Attribution caveat:** other `pay()` callers ran in the same session (three
FIND claims, one business collect). Those are a handful of calls; the 21
warnings track the sweeps. I did not isolate it with a before/after burst,
because by the time I found it I had already left the city and could not get
back in (see NOT TESTED).
**Owner:** `game/SminskiServer.server.lua` → **server-engineer**.

### FAILURE 3 — a pending refusal hold delays the finish text by up to 1.0 s
**What happened.** ux.md §4 puts `trayCity` → `CITY 40 of 40` (coop) /
`ALL GONE` (competitive) at **t = 0.00** of the finish sequence. If a refusal
hold is still running, the finish text is not drawn until the hold expires.

**Measurement.** Coop goal run: `trayCity` read **`too far away`** in coral at
t = 0.00 and only became `CITY 12 of 12` at **t = 0.43**. Cash Drop empty run:
`too far away` at t = 0.00, `ALL GONE` at **t = 0.43**. Worst case is the full
**1.0 s** hold. The big line and `trayMine` were both correct and on time, so
the finish reads as "we did it" next to "too far away".

**Most likely cause.** `game/CityEvents.lua:471` — `renderTray` prefers
`ev.cityHoldText` whenever `os.clock() < ev.cityHold`, and `runFinish`
(`game/CityEvents.lua:679-685`) does not clear `ev.cityHold` before calling
`renderTray`. One line: clear `ev.cityHold` (and `ev.mineHold`) at the top of
`runFinish`.
**Owner:** `game/CityEvents.lua` → **client-engineer**.

Severity note: this only bites when a refusal fires within 1 s of the finish.
At normal walking speed no refusal fired at all in a 24-bag sweep; it showed
up here because the last pickup was a teleport, which reproduces a latency
spike. It is cosmetic, but it lands on the one moment the feature exists for.

---

## NOT TESTED

1. **Two Studio clients / the shared-counter beat (§8.3, §8.4).** I could not
   launch a second client: the MCP bridge only toggles Play, and Studio's
   "Start Server + 2 Players" is not reachable from it. So the headline claim
   of the phase — *another player's pickup moves your tray, with the `C.sky`
   "that was not me" flash* — is **unverified in the form it ships**. What I
   did verify: a claim resolved server-side outside my client's claim path
   moved my tray in **51.8 ms**, `got` and `myCount` are separate fields on
   the reply and did not contaminate each other, and `taken`/`progress` are
   `FireAllClients`. The specific case "A takes 3, B takes 2, A's tray reads
   `CITY 5` / `YOU 3 · BONUS`" was not run.
2. **A 48-item event.** `goal = clamp(12 + 8 × (n−1), 12, 48)` needs **6**
   players with `Activity == "city"`; I had one, so every cooperative event
   placed 12. The instance-count invariant was instead measured at 12 items
   vs 24 items (`cashdrop`) — **12 descendants+1 in both** — which tests the
   same property but not at the 48 cap.
3. **A cooperative goal met with items still on the ground.** Unreachable with
   one player (goal 12 = items placed 12), so the "further claims return
   `it's over` while balloons are still lying there" branch was only exercised
   via the 5-second `done`→`end` window, where it did return `"it's over"`.
4. **A claim during the 45 s warn window.** `EventsDev` sets
   `startT = now()`, so the pre-start path (`return { ok = false }`, silent) is
   not reachable through the hook, and no collect headline came up naturally.
   Static reading only: `game/SminskiServer.server.lua:2568`.
5. **Milestone/goal audio arriving while the player is outside the city.**
   `E.leave()` (`game/CityEvents.lua:1448`) does **not** clear `E.list`, so the
   `E.list[ev.uid] == ev` guards on every delayed sound still pass after you
   leave. I could only test the case where the event *ends* while I am away
   (which clears `E.list` via `onEnd`, and correctly produced **0 sounds**).
   The case that worries me — another player crossing a 25 %/50 %/75 %
   milestone, or hitting the goal, while I am in the hub — needs two clients.
   Flagging it as a code-path risk found by reading, not a measured bug.
6. **Re-entering the city after exiting through `Places.CityExit`.** Neither
   `SR_TestPick("play")` from the hub (3 attempts), nor a real mouse click on
   the title's `[RESUME]`, nor walking the `Places.HubGateX/HubGateZ` gate
   (X = −8, Z = −116.9, inside the `|X+8| < 11` and `−152 < Z < −114` window
   at `Hub.lua:1504`) put me back in the city — `Activity` stayed `hub`.
   Related: the title's `[RESUME]` button does **not** answer
   `GetGuiObjectsAtPosition` at its own `AbsolutePosition` (tried y = 276,
   310, 334; only Frames come back), whereas the city HUD's buttons do. This
   may be my harness rather than the game, it is outside this feature, and I
   did verify RESUME works *from inside the city*. Raised only so someone can
   look: `game/Hub.lua` → **world-builder**, `game/SminskiTitle.client.lua` →
   **client-engineer**.
7. **The 12-stud FIND exclusion under pressure.** The pup landed 46 studs from
   the zone centre, so no candidate slot was ever inside 12 of it and the
   rejection branch (`game/SminskiServer.server.lua:2356-2358`) never ran.
8. **Play-mode screenshots.** Not attempted — they come back magenta here.
   Everything visual above is numeric.

---

## CONSOLE

Complete output for the session, verbatim. Nothing from `CityEvents`, `City`,
`Config` or `SminskiServer`; no `streamStep` warns.

```
Hello world, from server!
Hello world, from client!
Visible is not a valid member of ScreenGui "Players.indiannarwhal.PlayerGui.SminskiCityUI"
Stack Begin
Script 'AssistantCommand', Line 32
Stack End
DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.Key = u_827213592
   ... the same line, 21 times in total, all Key = u_827213592 ...
```

The `Visible is not a valid member of ScreenGui` error is **mine** —
`Script 'AssistantCommand'` is the QA console, from a first pass that walked
an ancestor chain without checking for `ScreenGui`. It is not game code.

Earlier in the session, before the first sync:
```
indiannarwhal joined live editing session.
[Rojo-Warn] Disconnected from an error: WebSocket error: 400 - Failed ws recv - err: 0 "No error", curlErrBuf: ""
```
Pre-existing Rojo/live-editing noise, unrelated to this feature.

---

**Studio left in Edit mode with Play stopped.** The local file server
(`python3 -m http.server 8765` in `game/`) is still running in the background.

---
---

# SECOND PASS — re-test of the three fixes

**VERDICT: BLOCKED — Roblox Studio has no place open, and the MCP bridge cannot
open one.** None of the three fixes could be re-measured. What follows is
(a) a static verification that the fixes are on disk and do what the
coordinator describes, (b) the §8.1 remote-scope question, which is a static
question and is now **closed**, and (c) the exact harness for every
measurement still owed, so the next run does not have to rediscover it.

**Nothing below upgrades FAILURE 1, 2 or 3 to PASS.** They remain unverified
as fixed. The first-pass verdict stands until someone can run the numbers.

## How it blocked

`stop Play → sync` was the first step. The Studio instance
`6c5e3613-953c-456b-be07-f99a36fcbdd3` answers `list_roblox_studios` but now
reports `"name": null` (it read
`Sminski City: Explore, Work, Run, Shop (placeId: 123228656219050)` all through
the first pass), and every call — `get_studio_state`, `execute_luau` in `Edit`,
even `return "alive"` — returns **`Place is not open`**.

- The Studio process is alive: `RobloxStudio` pid 27636, plus two `StudioMCP`
  helpers. So the bridge is up and the editor is running with no place loaded.
- Polled for ~5 minutes across 8 calls. No change.
- I left Studio correctly at the end of the first pass: Play stopped,
  `get_studio_state` confirmed `Edit`. I ran nothing against Studio between
  that confirmation and this re-test — only file writes to this report. The
  close did not come from me, and I have no way to undo it.
- **The bridge has no "open place" tool**, and `execute_luau` needs a
  DataModel, so I cannot recover this from my side. Someone with the Studio
  window needs to reopen the place (File → Recent, or the published place
  123228656219050). The port 8765 file server is still up and serving 200.

The **sync did not happen either** — so Studio, whenever it reopens, is still
running the pre-fix build from the first pass. The next run must sync before
testing, or it will re-measure the old defects.

## Closed without Studio

### §8.1 — the remote-count discrepancy  CLOSED, and the server engineer is right
My "32 remotes" was a **whole-tree runtime count**: the children of
`ReplicatedStorage.SminskiRemotes` enumerated in Play — every remote in the
game, every feature — which is 31 remotes plus a `Leaderboards` StringValue.
It was never scoped to this feature, and quoting it under §8.1 was
misleading. The feature-scoped count, from
`game/SminskiServer.server.lua`:

- `Instance.new("RemoteEvent")` inside the whole city-events block: **exactly
  one**, `:2177`, named `CityEvent` at `:2178`.
- `rf()` calls in the block: **exactly two**, `:2674` (`Events`) and `:2867`
  (`EventsDev`, inside the `RunService:IsStudio()` guard).
- File-wide totals for context: 8 `Instance.new("RemoteEvent")` and 24 `rf()`
  calls, all 24 names distinct.

All three event objects are phase A. **Phase B added no RemoteEvent and no
RemoteFunction** — it changed two handler signatures and added branches, as
stated. §8.1 passes with no caveat on this point. (The separate §8.1 caveat
stands unchanged: I never saw a *naturally scheduled* collect headline.)

## Static verification of the three fixes

Present on disk and consistent with the description. Line numbers confirmed
against `SminskiServer.server.lua` (2,947 lines) and `CityEvents.lua`
(1,493 lines).

### FIX 1 — timeout grace
- `:2584-2585` `local grace = why == "time" and 2 or 5` then
  `ev.tearAt = now() + grace`, both **before** the `"done"` broadcast at
  `:2586`. `:2611-2613` is a single `task.delay(grace, …)` for all three
  endings; the same-frame `finish(ev)` is gone.
- **The race I went looking for is not there.** `ev.over = why` is set at
  `:2572` and `ev.tearAt` at `:2585`; lines 2573-2585 contain no yield, so the
  once-a-second loop cannot observe `over` set with `tearAt` still nil and
  tear the event down against `t >= 0`. This was the one way the fix could
  have been worse than the bug.
- `:2756-2770` branches `if ev.over then … if t >= (ev.tearAt or 0) then
  finish(ev) end elseif t >= ev.endT then …`, so FIND keeps its original path
  and only collect events (the only setters of `over`) reach the new branch.
- The 2 s window clears the client's floor: on a timeout `ev.fanfareAt` is nil
  so `onReward`'s `wait` is **0** (`CityEvents.lua:953`) and the notification
  is at **0.80** (`:708`) — both well inside 2.0.
- No double notification: `onEnd`'s fallback (`CityEvents.lua:845`) is gated on
  `not ev.finished`, which `runFinish` has set by then.

### FIX 2 — deferred saves
- `:1498` `pay(player, s, coins, xp, stat, defer)`; `:1511-1515`
  `if defer then s.payDirty = true else task.spawn(save, player) end`. Default
  path byte-equivalent.
- **Exactly two callers pass it**, both in the collect path: `:2656` (per item)
  and `:2596` (the completion bonus, immediately followed by
  `s.payDirty = nil; task.spawn(save, player)` at `:2600-2601`). Every other
  `pay()` call site still passes 5 arguments — including FIND's claim `:2719`,
  the cleaner sweep `:1654`, job tasks `:2091` and **`creditWorld`'s streak
  bonus `:2143`**, so §8.7's roughly-every-9th-piece write is structurally
  unchanged.
- Four write paths cover the dirty flag: the 10 s flush loop `:1333-1346`,
  leaving the city `:1204-1210`, `PlayerRemoving` → unconditional
  `save(player)` `:1309-1312`, and `BindToClose` `:1314-1320`. The
  quit-mid-event durability case is covered **by construction** —
  `PlayerRemoving` saves whether or not `payDirty` is set — but it still wants
  measuring, because that is the path where a mistake eats money silently.
- One residual, worth a line to the owner and not a blocker: all three flush
  sites clear `s.payDirty` **before** the spawned `save` completes
  (`:1207`, `:1341`, `:2600`). If that save errors, those coins are no longer
  queued for the flush loop and wait for the next unrelated save. Clearing the
  flag *after* a successful write would close it. Owner: **server-engineer**.

### FIX 3 — stale tray holds
- `CityEvents.lua:685-692` clears `cityHold`/`cityHoldText`/`cityHoldColor`,
  `mineHold`/`mineHoldText`/`mineHoldColor` and `skyHold` **before** the
  `renderTray(ev, 0.18)` at `:693`. Correct order, and it covers the two holds
  I did not find (the 1.6 s `BONUS LOCKED`, which would have eaten the whole
  `YOU n · PAID` line, and the 0.30 s `skyHold`, which would have drawn the
  finish number in sky blue).
- `:1048` `if why and not ev.finished then holdCity(ev, why, C.coral, 1.0) end`
  and `:1105` the same guard on `holdMine("BONUS LOCKED", …)`.
- **Refusal recovery is structurally untouched**, which was the thing to check:
  `ev.refused[id]` / `ev.noMore` / `ev.retryAt = os.clock() + 0.5`
  (`CityEvents.lua:1063-1079`) all sit *after* the `holdCity` line and outside
  the new `not ev.finished` condition, so the 43-frames-then-recover behaviour
  I measured depends on none of it.

Static review is not measurement. This project's standard is measurement, and
on this pass I have none.

## Still owed, with the harness

Sync first (`_G.SR_sync()` in Edit, then Play) — Studio is still on the
pre-fix build. Get into the city, then end all live events
(`EventsDev:InvokeServer("endNow", uid)` for each `state` entry) before each
test, or a FIND event steals the headline and `renderTray` returns early
because `ev ~= liveEv` — that cost me two runs in the first pass.

1. **FIX 1, the measurement that decides it.** Connect `CityEvent.OnClientEvent`
   and stamp `os.clock()` on `"done"` and on `"end"`. Coop event, `myCount ≥ 1`,
   let it time out (or `endNow`, same code path). Expect **`end` − `done` ≈ 2.0 s**;
   anything under ~1.7 s is the old bug. Then a goal run: expect **≈ 5.0 s**.
2. **FIX 1, the user-visible half.** Same run, with `Sound.Played` connected on
   every voice in `SoundService.SminskiAudio`: expect **one `Click` at pitch
   1.299** (that is `J.notify`, `CityJobs.lua:73`, the only way to detect a
   notification) and **one `Chime` at pitch 1.15, volume 0.1749** (0.35 × 0.5),
   the consolation. First pass measured **zero of both** over 7 s.
   Caution: `BigChime` has one voice, so `Played` does not re-fire on a
   restart — sample `BigChime1.PlaybackSpeed` per Heartbeat instead, as I did.
3. **FIX 2 (a).** Read `get_console_output`, sweep 24 bags on foot
   (`Humanoid:MoveTo`, greedy nearest, ~44 s), read again. Expect **~5** new
   `DataStore request was added to queue` lines against the first pass's
   **21**.
4. **FIX 2 (b), the one that matters.** `GetData:InvokeServer().Coins`, collect
   6-8 items **mid-event, nowhere near the finish**, record the reply's
   `data.Coins`, then stop Play (that is the hard-stop case; `PlayerRemoving`
   should still fire), restart, and compare `Coins`. Must be equal. Also worth
   the softer path: walk out through `Places.CityExit` mid-sweep, which should
   flush at `:1204-1210`, then re-read.
5. **FIX 3.** Heartbeat-sample `EventTrayCity.Text` from the moment `sClock`
   turns `DONE`/`GONE`. Expect the finish string at **t = 0.00**; first pass
   measured **t = 0.43** with `too far away` sitting there. To land a refusal
   on top of the finish, make the last pickup a teleport onto the item — that
   reproduced it reliably. The `BONUS LOCKED` variant needs the 3rd and final
   pickups inside 1.6 s of each other, which with `goal = 12` means ~0.15 s
   teleports; if that will not land, say so rather than passing it.
6. **Re-run, because the claim path changed:** all four §8.5 exploit paths
   (same item twice → `"already gone"` Δ0; 40 studs → `"too far away"` Δ0;
   after the end → `"it's over"` Δ0; `raceTest` → one `ok`, `paid` = one item)
   and §8.7 cleaner credit (`earned` +36/item, `tasks` ticking on the **9th**).
7. **FIX 1 regression:** `sighting`, `lostpup` and `icecream` still expire and
   remove their models — the teardown loop they share now has the `ev.over`
   branch ahead of their path.

Two Studio clients and the 48-item event: not retried, as instructed. Nothing
I saw on this pass changes that assessment — the bridge exposes only a Play
toggle, and `goal = clamp(12 + 8 × (n−1), 12, 48)` still needs six players in
the city.

**Studio state on exit:** no place open, so nothing to leave clean; Play is not
running. The port 8765 file server is still up.

---
---

# THIRD PASS — the three fixes verified

**VERDICT: PASS — all 10 CONTRACT §8 acceptance items now pass.** FAILURE 1,
FAILURE 2 and FAILURE 3 are all fixed and measured as fixed. The §8.1 caveat
from the first pass is also closed: a collect headline was scheduled by the
existing director with no dev hook. One new observation, pre-existing and not
caused by these fixes, is recorded at the end.

**BUILD:** synced in Edit mode after stopping Play. Byte counts in Studio,
before and after the sync, prove the build changed:

| File | in Studio before | in Studio after | disk |
|---|---|---|---|
| `SminskiServer.server.lua` | 111,076 | **116,305** | 116,305 |
| `CityEvents.lua` | 62,382 | **63,240** | 63,240 |
| `Config.lua` | 59,721 | 59,721 | 59,721 |

Viewport 1160 × 719, UI scale 0.90625, payouts still ×4.5 (every pass held).

---

## save() signature change — tested first, PASS

`save()` now returns a boolean and 25 callers discard it, so this was the thing
that could break everything rather than just collect.

Clocked in as `cleaner` and swept three litter pieces through the real
proximity path (not a direct remote call), then **stopped and restarted Play**:

| Field | before restart | after restart |
|---|---|---|
| `Coins` | 98,581 | **98,581** |
| `Sweeps` | 177 (from 174) | **177** |
| `TotalCoins` | 122,601 | **122,601** |
| `Jobs.Earned` | 13,230 | **13,230** |
| `Saveable` | true | **true** |

Console clean — no `[SminskiServer] save failed` or `load failed`. The new
signature compiles and persists.

---

## FIX 1 — timeout grace  PASS

Measured as `end` − `done` from `CityEvent.OnClientEvent` timestamps. The old
bug shows as anything under ~1.7 s; first pass it was same-frame.

| Run | Path | `why` | `done` → `end` | Result |
|---|---|---|---|---|
| balloons, `myCount = 4`, `endNow` | timeout | `time` | **2.000035 s** | PASS |
| cleanup, `myCount = 3`, `endNow` | timeout | `time` | **1.999102 s** | PASS |
| cleanup, `myCount = 3`, `endNow` | timeout | `time` | **1.999804 s** | PASS |
| balloons, goal reached | goal | `goal` | **5.015040 s** | PASS, 5 s did not regress |
| **cleanup#15, NATURAL 180 s timeout, no dev hook** | timeout | `time` | **2.016 s** | PASS |

**The two things that were silent are now audible**, measured on the natural
timeout of a director-scheduled event (`Sound.Played` on every voice in
`SoundService.SminskiAudio`, timestamps relative to `done`):

```
done@10245.600 why=time;  reward@10245.600 bonus=0 my=2;  end@10247.616;
+0.001  Chime@1.150/0.1750     <- the consolation chime (0.35 base x 0.5)
+0.819  Click@1.300/0.1400     <- J.notify's click, i.e. the finish notification
```

First pass: **zero of both** over 7 s. The consolation `Chime` 1.15/0.5 fires at
**+0.001** and the notification at **+0.819** (spec +0.80), both inside the 2 s
window with margin. `reward` carries `bonus = 0` on a timeout, correct. All
litter models removed, **0** leftovers in `workspace`.

The natural-path run matters most: it exercised the once-a-second loop's
`finishCollect(ev, "time")` and then the new `ev.over` / `ev.tearAt` branch, not
just `endNow`.

Also checked statically, because it was the one way the fix could have been
worse than the bug: `ev.over = why` (`:2572`) and `ev.tearAt` (`:2585`) have **no
yield between them**, so the 1 s loop cannot observe `over` set with `tearAt`
still nil and tear down against `t >= 0`.

---

## FIX 2 — deferred DataStore writes  PASS

Instrumented on the **server** by sampling
`DataStoreService:GetRequestBudgetForRequestType(UpdateAsync)` every Heartbeat
and recording every change: regeneration shows as `+1`/`+2` steps (~1.67/s), a
write as a `-1` step. (A first attempt sampling at 10 Hz undercounted a single
write, because regen can land in the same window — the per-frame trace is the
instrument to use.)

**(a) Write count across a full 24-bag sweep.**

| Measure | First pass | Third pass |
|---|---|---|
| bags claimed | 24 | **24** |
| `UpdateAsync` calls | not instrumented | **7** |
| `DataStore request was added to queue` warnings | **21** | **0** for the sweep; **1** for the entire session |

Raw drop trace for the sweep (seconds into the window):
`3.56 · 23.84 · 34.59 · 43.86 · 53.93 · 63.89 · 82.09` — evenly spaced on the
**10 s `PAY_FLUSH` cadence**, not on the 24 claims. That is the property that
matters: the write count is bounded by elapsed time ÷ 10 s, never by items
collected. Sweep took 88 s over two calls, giving 8-9 flush opportunities and
7 writes.

Isolated mechanism, 3-claim cleanup event, per-frame trace showing exactly one
`-1` step in 40 s:

| Point | writes |
|---|---|
| 3 item claims | **0** |
| after one 10 s flush interval | **1** |
| at the finish (`flushPay`, timeout so no bonus) | **+0** |

**The finish costs zero writes when the flush loop already wrote** — exactly the
claim. `flushPay` sees `paySeq == paySaved` and no-ops.

**(b) Durability, the path where a mistake eats money.** Collected 5 balloons in
5.08 s (+180 coins = 5 × 8 base × 4.5) and **hard-stopped Play 5.8 s after the
first claim** — inside the 10 s flush window, mid-event, nowhere near the
finish, so the coins were still deferred. Restarted:

| Field | before stop | after restart |
|---|---|---|
| `Coins` | 106,807 | **106,807** |
| `TotalCoins` | 130,827 | **130,827** |

Nothing lost. `PlayerRemoving`'s unconditional `save(player)` (`:1332-1335`)
covers it, and it is deliberately not routed through `flushPay`.

**DataStore-failure bounded retry: NOT measured.** I cannot make `UpdateAsync`
fail from the test VM (it runs in its own Luau VM, so I cannot stub
`DataStoreService`, and the Studio API-access toggle is not reachable from
Luau). Verified structurally instead: `flushPay` (`:227-231`) reads `paySeq`
before the write and assigns `paySaved` **only** when `save()` returns true, so
a failure leaves the session queued and the retry rate is the 10 s flush
interval — one retry per interval, never one per item. The residual I raised on
the second pass (clearing the flag before the write was confirmed) is closed by
this shape.

---

## FIX 3 — stale tray holds  PASS

The condition had to be reproduced, not assumed. Immediately before the final
pickup the tray was measurably **mid-refusal**:

```
beforeLast: city = "too far away"   colour = 1, 0.490196, 0.431373  (C.coral)
            mine = "YOU 11 · BONUS"
```

Timeline from `sClock` turning `DONE` (t = 0), Heartbeat-sampled:

| t | `trayCity` | colour | `trayMine` | big line |
|---|---|---|---|---|
| **0.00** | **`CITY 12 of 12`** | **0.227451, 0.243137, 0.196078 = `C.ink`** | `YOU 12 · BONUS` | hidden |
| 0.11 | `CITY 12 of 12` | `C.ink` | `YOU 12 · BONUS` | `WE DID IT!` visible |
| 0.26 | `CITY 12 of 12` | `C.ink` | `YOU 12 · PAID` | visible |

**The finish string is at t = 0.00, not t = 0.43.** The live `too far away`
hold was dropped rather than painting over the finish. Notification captured on
screen this time: **`CITY GOAL REACHED`** / **`you got 12 of 12 · bonus paid`**,
exactly ux.md's contributor receipt.

**The `BONUS LOCKED` variant is NOT REACHABLE with one player, and I am not
passing it silently.** It needs the 3rd and the goal-completing pickup inside
the 1.6 s hold — with `goal = 12` that is 10 pickups in 1.6 s. Teleport-chaining
at 0.16 s intervals produced mostly `too far away` refusals, and each one
correctly arms the per-event 0.5 s `ev.retryAt` back-off, so the attempt
collected only 3 of 12 in the window. The back-off is intended behaviour and it
makes this case unreachable from a single client. What I can say: `mineHold` is
cleared in the same three-line block as `cityHold`
(`CityEvents.lua:690-692`), the mechanism I *did* measure, and `trayMine`
rendered its finish string correctly at t = 0.26.

Refusal recovery, re-confirmed as untouched: refusals still fire and still
arm the 0.5 s back-off (that is what defeated the test above), and the
`ev.refused` / `ev.retryAt` logic sits outside the new `not ev.finished`
condition.

---

## Regressions, all re-run

### §8.5 — four exploit paths, after the claim path gained `defer`  ALL PASS
| Path | Reply | Payment |
|---|---|---|
| from 40.00 studs (nearest other item 40.79) | `{ ok = false, reason = "too far away" }` | Δ **0** |
| same item twice | 1st `ok` **+270**, 2nd `{ ok = false, reason = "already gone" }` | Δ **270**, then **0** |
| `raceTest` one bag | `a.ok = true`, `b = { ok = false, reason = "already gone" }` | `paid` = **270** = one bag (60 base × 4.5); `got` 1 → 2, moved by exactly 1 |
| after `endNow` (valid id **and** 9999) | `{ ok = false, reason = "it's over" }` both | Δ **0** |

### §8.7 — cleaner credit  PASS, identical to pre-fix
`shift.earned` per pickup: **36, 72, 108, 144, 180, 216, 252, 288, 324, 360** —
+36 each (8 base × 4.5). `shift.tasks` 0 for pickups 1-8, ticks to **1 on the
9th** (1 / 0.12 = 8.33). `creditWorld`'s streak-bonus `pay` still passes no
`defer`, so its write behaviour is unchanged.

### FIND expiry through the shared teardown loop  PASS
The loop now tests `ev.over` ahead of FIND's path, so a natural FIND expiry was
run rather than `endNow`. `sighting#14`, `lasts = 110`, NPC `Sminski_Night`
drawn on arrival:

| elapsed | event in `state` | NPC model |
|---|---|---|
| +4 s | live | drawn |
| +64.9 s (`endIn` 40) | live | drawn |
| **+125.96 s** | **gone** | **removed** |

### Tray geometry on the new client build  PASS, unchanged
`Size {0,340},{0,46}` · `Position {0,0},{0,50}` · `ZIndex 4` ·
`AbsolutePosition (425.9375, 125.0625)` → design **(470, 202)**, bottom
**248** · `EventTrayTrack {0,308},{0,10}` at `{0,16},{0,30}` ·
`#tray:GetDescendants()` = **11**, so **12** with the tray, during a 12-item
event — identical to the first pass. `EventBigLine` + 3 descendants = **4**, as
specified. Balloons: **2** parts each × 12, and **0** BillboardGui / SurfaceGui
/ PointLight / ParticleEmitter. Strings `CITY 0 of 12` / `YOU 0 of 3`.

### Cleanup and console  PASS
All events ended: **0** live, **0** `EventLitter` / `EventBalloon` /
`EventCashBag` / `EventBeacon` in `workspace`, tray hidden. Complete console for
the third pass:

```
Hello world, from server!
Hello world, from client!
DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.Key = u_827213592
```

**One** queue warning for the whole session — which included a 24-bag sweep,
five 12-item cooperative events, cleaner sweeps and three Play restarts (each
restart itself forces `PlayerRemoving` + `BindToClose` + load writes). First
pass: 21 warnings for one sweep. No game-code error or warn of any kind.

## §8.1 caveat — CLOSED
`cleanup#15` was **scheduled by the existing director with no dev hook**, ran
its full 180 s and timed out naturally (this is the run in the FIX 1 table).
So a collect event has now been observed arriving through the real schedule,
not only through `EventsDev`. Combined with the second pass's static count —
one `RemoteEvent` (`:2177` `CityEvent`) and two `rf()` calls (`:2674` `Events`,
`:2867` `EventsDev`), all phase A — §8.1 passes with no caveat.

## New observation, pre-existing, not caused by these fixes

**A collect event's tray vanishes mid-event whenever a FIND event with an
earlier `endT` is live.** Measured during a goal finish: the tray went
`Visible = false` at **t = 3.01 s** into the 5-second celebration, while
`WE DID IT!` was still on screen. Cause: `headline()` picks the live event with
the smallest `endT`, and a `SMINSKI SIGHTING` with `endIn` 51.7 s outranked the
balloons event's 180 s, so `renderTray` hid the tray. `renderTray` returning
early for a non-headline event is by design (`ux.md` gives the strip to "the one
live headline"), but the consequence is that the shared counter — the thing
phase B exists to add — can disappear at the exact moment its finish is being
celebrated, and on a busy server a FIND is often live. This is a design
question for ux-designer, and a `CityEvents.lua` change if they want the
finishing event to hold the slot for its grace window.
Owners: `docs/specs/collect-events/ux.md` → **ux-designer**;
`game/CityEvents.lua` → **client-engineer**. It also cost me two invalid test
runs across the two passes, which is a decent sign it will confuse players.

## Not tested

- **Two Studio clients** and the **48-item event** — not retried, as
  instructed. Nothing on this pass changes that assessment.
- **`BONUS LOCKED` still held at the finish** — unreachable from one client;
  reason measured and given above.
- **A DataStore write failing** — cannot be induced from the test VM; verified
  structurally that the retry is bounded by the flush interval, not by items.

**Studio left in Edit mode with Play stopped.** My test artifacts
(`QA_Writes`, `QA_Trace`, `QA_Stamps`, `QA_Sounds`, `QA_Expect`, `QA_Budget`)
were destroyed before exit and were runtime-only in any case. The port 8765
file server is still running.

---
---

# FOURTH PASS — tray eviction fix (narrow)

**VERDICT: PASS with one defect.** The eviction defect is fixed and the FIND
strip is unregressed. One new defect found, in the part of the fix the
coordinator asked me to check specifically: **`takeStrip` writes the wrong
`sSub`** for a collect event, because the premise that "collect has no clues"
is false. It is cosmetic and lasts one tick (measured 82 ms), but it is wrong
text at the moment of the celebration. The two-collect residual the engineer
named is **reachable** via `EventsDev` and is measured below.

Third-pass results are untouched; nothing here re-runs them.

**BUILD:** re-synced in Edit mode. `CityEvents.lua` in Studio **63,240 →
65,085**; `Config.lua` 59,721 and `SminskiServer.server.lua` 116,305 both
unchanged. `rank(ev)` and `takeStrip(ev)` both confirmed present in the synced
source.

> **Byte-count discrepancy, flagged not resolved:** the brief said
> `CityEvents.lua` is **65,157** bytes. Disk and Studio both read **65,085** —
> 72 bytes short. `rank` and `takeStrip` are both present and behave as
> described, so I tested what is there; but if a further edit was expected to
> land, it did not.

---

## 1. The original scenario, reproduced  PASS

Set up the exact first-pass condition — a FIND ending well before the collect
event:

```
icecream#3   endIn 131.2s      <- FIND, ends 46s SOONER
balloons#4   endIn 177.9s      <- collect
lostpup#2    endIn 198.2s
```

While running, the collect event owned the strip: `sTitle` =
**`BALLOON FESTIVAL`**, `sClock` = `2:58` (the collect event's clock),
`tray.Visible = true`, `CITY 0 of 12` / `YOU 0 of 3`. Under phase A's
"soonest-ending wins" this was `ICE CREAM TRUCK` and the tray was hidden.

Tray visibility across the finish, Heartbeat-sampled from the `done` broadcast,
**422 frames over 7 s**:

| Measure | Value |
|---|---|
| `done` → `end` | **5.0329 s** |
| frames with `tray.Visible == true` | **302** (≈ 5.03 s at ~60 fps) |
| frames with `tray.Visible == false` | **120** (all *after* `end`) |
| strip title at t = 0.000 and t = 0.082 | **`BALLOON FESTIVAL`** |
| strip title at t = 5.284 | `ICE CREAM TRUCK` (correct — the event has left `E.list`) |
| big line | `WE DID IT!` |

**The tray stays visible for the entire 5.03 s celebration and hands the strip
back only after `end`.** First pass it went hidden at **t = 3.01 s**, two
seconds into the celebration. Fixed.

## 2. Strip identity, and what the FIND kept  PASS

With `cleanup#3` (endIn 176.9) and `icecream#2` (endIn 165.3) both live, the
strip read `CITY CLEANUP`. The evicted FIND lost nothing else — phone opened
through the real tray tap (`GetGuiObjectsAtPosition` confirmed the click hit
`EventTrayTap` before clicking):

| Row | Title | Clock | GO | Count line |
|---|---|---|---|---|
| 1 (y 130) | **ICE CREAM TRUCK** | **2:22** | **visible** | `nobody is there yet -- be first` |
| 2 (y 225) | CITY CLEANUP | 2:33 | visible | `CITY 0 of 12  ·  YOU 0 of 3` |
| 3 (y 319) | — | — | hidden | — (only two events) |

`E.refreshPhone` sorts by `endT` and never calls `headline()`, so the FIND is
still first in the list with its own clock and its own GO. Confirmed, not
inferred.

## 3. `takeStrip`'s synchronous draw  PASS

Measured from the `done` broadcast timestamp to the first frame on which
`trayCity` showed the finish string:

> **`done` → `CITY 12 of 12` = 0.000365 s** (0.37 ms — the same frame).

Not up to 0.25 s. `takeStrip` does what it claims.

**One caveat on the precondition.** The brief asks to "land a finish while a
FIND owns the strip". After this fix that is **unreachable by construction**: a
live collect event is rank 2 and a FIND is rank 1, so a FIND can never own the
strip while a collect event is live and unfinished. The seam `takeStrip` closes
is therefore no longer reachable through that route — I verified the outcome it
guarantees (finish drawn in the same frame) rather than the failure it prevents.

## 4. FIND regression, no collect event live  PASS

| Case | Strip | Title | Clock | Tray |
|---|---|---|---|---|
| one FIND (`lostpup`, `lasts` 240) | **visible** | `LOST PUP` | `3:57`, colour `1, 0.490196, 0.431373` = `C.coral` | **hidden** |
| two FINDs: `icecream#3` endIn **166.9** vs `lostpup#2` endIn **233.8** | **visible** | **`ICE CREAM TRUCK`** (the soonest-ending) | `2:47` | **hidden** |

FIND-vs-FIND ordering is unchanged: rank ties at 1 and the tie breaks on
soonest `endT`, exactly as phase A. `sSub` on the one-FIND case read
`the shopping district` (the pup is hidden, so `latestClue` is nil at t = 0 and
it falls through to `ev.area`) and on the icecream case read its clue,
`on Cloud St, near the Kart Track`. Phase A's strip is intact.

## 5. `sSub`  **FAIL** — the "collect has no clues" premise is false

**Measured, frame by frame, across the finish of `balloons#4`:**

| When | `sSub` |
|---|---|
| while running, and immediately before the finish | `on Main St, near the City Gate` |
| **t = 0.000** (the frame `takeStrip` ran) | **`the south of town`** |
| **t = 0.082** (the next 0.25 s tick) | `on Main St, near the City Gate` |

So the sub line flips to the area and back within ~82 ms, at the exact moment
the celebration lands.

**Cause.** All three collect rows are `open = true`
(`Config.lua:1020, 1025, 1031`), and the server gives **every** open event one
clue (`SminskiServer.server.lua:2510-2512`:
`if def.open then ev.clues = { { t = t0, text = "on " .. streetOf(lot) .. ", near " .. lm.name } } end`).
A collect event therefore always has exactly one clue, and it is what the strip
normally shows. `CityEvents.lua:690` writes `sSub.Text = ev.area or ""`, while
the 0.25 s tick at `CityEvents.lua:1493` writes
`latestClue(ev) or ev.area or ""`. Those are not the same string for a collect
event.

**Fix.** `latestClue` is declared at `CityEvents.lua:1212`, below `takeStrip` at
`:683` — which is presumably why it was inlined, and it is this project's
recurring "a `local function` is invisible above its declaration" hazard
(`HANDOFF.md` §3). Hoisting `latestClue` above `takeStrip`, or forward-declaring
it with the other mutable handles at the top of the module as this file already
does for `strip`/`tray`/`liveEv`, lets `:690` use the same expression as
`:1493`.
**Owner:** `game/CityEvents.lua` → **client-engineer**.

Severity: cosmetic, one tick, and self-correcting. Not a blocker for the
eviction fix.

## The named residual — reachable, and measured

`EventsDev` does let two collect events run at once (it bypasses the director's
`headlineLive` check), so I measured it.

`cleanup#4` (endIn 176.9, `myCount` 3) and `balloons#5` (endIn 177.9,
`myCount` 2), both live; `endNow` on cleanup at t = 0, on balloons at t = 0.8,
so both sat inside their 2 s finish windows together. Heartbeat-sampled:

| t | strip title | `trayCity` | tray |
|---|---|---|---|
| 0.000 | CITY CLEANUP | `CITY 3 of 12` | visible |
| **0.912** | **BALLOON FESTIVAL** | **`CITY 2 of 12`** | visible |
| **1.229** | **CITY CLEANUP** | **`CITY 3 of 12`** | visible |
| 2.046 | CITY CLEANUP | `CITY 3 of 12` | hidden (cleanup's `end`) |
| 2.479 | BALLOON FESTIVAL | `CITY 2 of 12` | visible |
| 2.912 | BALLOON FESTIVAL | `CITY 2 of 12` | hidden (balloons' `end`) |

**Three switches in 2.9 s.** Every number shown was real — `CITY 3 of 12` and
`CITY 2 of 12` are the two events' true finals — so nothing false is displayed,
as the engineer said.

Worth adding to the engineer's description: the flip is not only the rank-3
`endT` tie. `takeStrip` sets `liveEv` **unconditionally**, so the second event's
`runFinish` seizes the strip at t = 0.912 even though cleanup has the earlier
`endT` and should win the tie; the next 0.25 s tick then recomputes `headline()`
and hands it back at t = 1.229. The two halves of this fix disagree for one
tick. Making `takeStrip` defer when the current `liveEv` already outranks the
caller would close it.

**Reachability:** dev-hook only. The director runs one headline at a time
(`headlineLive()` gates `pickHeadline`), and across four passes I have never
seen two concurrent collect events arise naturally. Not a shipping bug.
**Owner:** `game/CityEvents.lua` → **client-engineer**, if they want it closed.

## One unrelated copy defect, noticed while reading the phone

The phone's collect clue is missing a preposition. Measured verbatim from the
row: **`12 pieces of litter the south of town · walk over them to grab them`**.
`CityEvents.lua:754` joins `noun .. " " .. area`, and `areaOf()` returns
`"the south of town"` / `"the <name> district"` — neither of which reads as a
place without `in`. ux.md's example, `40 balloons around Maple Row`, had the
preposition baked into the area string. One word.
**Owner:** `game/CityEvents.lua` → **client-engineer**.

## Console and cleanup  PASS
Complete console for the fourth pass:

```
Hello world, from client!
Hello world, from server!
```

Nothing else — no error, no warn, and no DataStore queue warning this pass.
After ending everything: **0** live events, **0** `EventLitter` /
`EventBalloon` / `EventCashBag` / `EventBeacon` in `workspace`, tray hidden,
strip hidden.

## Not tested
Two Studio clients, the 48-item event, and `BONUS LOCKED` at the finish — all
three unchanged from earlier passes and already with the human.

**Studio left in Edit mode with Play stopped.** Play was stopped once
mid-session by something outside my control; I restarted it and re-ran the
affected checks. Port 8765 still serving.

---
---

# FIFTH PASS — the three pass-four defects (narrow)

**VERDICT: PASS.** All three defects are fixed and measured as fixed, with no
new defect found. The load-bearing ordering claim inside DEFECT 2's fix holds in
behaviour, not just on disk.

**BUILD:** re-synced in Edit mode. `CityEvents.lua` in Studio **65,085 →
66,974** — matching the corrected figure exactly. `Config.lua` 59,721 and
`SminskiServer.server.lua` 116,305 unchanged. All six markers confirmed in the
synced source: `local latestClue, rank` forward block, `local function
stripSub(ev, soon)`, `function rank(ev)` and `function latestClue(ev)` (assigning
the forward locals rather than shadowing them), `local held, want =
rank(liveEv), rank(ev)`, and the `"in " .. ev.area` prefix.

---

## DEFECT 1 — `sSub` at the finish  PASS

Same condition as pass four, deliberately: a FIND ending sooner than the
collect event — `icecream#2` endIn **166.1 s**, `balloons#3` endIn **177.4 s**.
The event's `ev.area` from the server was **`the south of town`**, i.e. the
exact wrong string that appeared in pass four was available to be printed.

`sSub` sampled every frame for 6 s from the `done` broadcast — only **two**
distinct states in the whole window:

| t | `sSub` | strip title |
|---|---|---|
| **0.0005** | **`on Main St, near the City Gate`** (the clue) | `BALLOON FESTIVAL` |
| 5.2831 | `on Sunny St, near the City Gate` | `ICE CREAM TRUCK` (after `end`, the FIND's own clue) |

**No flicker.** Pass four measured `the south of town` at t = 0.000 and a
correction at t = 0.082; there is now no frame on which the area is shown.
Running-state sub line is unchanged from pass four
(`on Main St, near the City Gate`), and it is identical to the value at
t = 0.0005 — both writers now produce the same string because both call
`stripSub`.

## DEFECT 2 — `takeStrip` deferring  PASS, both directions

**(a) The load-bearing claim: a finishing collect must still take the strip from
a running one.** Set up so the incumbent was a *different, running* collect
event — `balloons#5` started first (endIn **176.2**, so it held the strip) and
`cleanup#6` second (endIn **177.44**); a `sighting#4` at endIn 84.38 was also
live throughout and correctly never took the strip from either.

| t | strip title | `trayCity` | tray |
|---|---|---|---|
| before | `BALLOON FESTIVAL` | — | visible |
| **0.0006** | **`CITY CLEANUP`** | `CITY 2 of 12` | visible |
| 2.0079 | `CITY CLEANUP` | `CITY 2 of 12` | hidden (cleanup's `end`) |
| 2.2503 | `BALLOON FESTIVAL` | `CITY 0 of 12` | visible (back to the running event) |

The finishing event (rank 3) took the strip from the running one (rank 2) **in
the same frame**, despite having the *later* `endT`. So `ev.finished` is set
before `takeStrip` in practice, not just in the source — if the order were
reversed, `rank(ev)` would have returned 2, the `held == want and
liveEv.endT <= ev.endT` branch would have fired, and the celebration would
never have reached the strip.

**(b) Two overlapping finishes: zero switches.** Pass four's scenario
replicated exactly — `cleanup#7` endIn **176.38** (incumbent, earlier `endT`),
`balloons#8` endIn **177.43**; `endNow` cleanup at t = 0, balloons at t = 0.8;
`myCount` 3 and 2.

| t | strip title | `trayCity` | tray |
|---|---|---|---|
| 0.0001 | `CITY CLEANUP` | `CITY 3 of 12` | visible |
| 2.0517 | `CITY CLEANUP` | `CITY 3 of 12` | hidden (cleanup's `end`) |
| 2.1502 | `BALLOON FESTIVAL` | `CITY 3 of 12` | visible |
| 2.9002 | `BALLOON FESTIVAL` | `CITY 3 of 12` | hidden (balloons' `end`) |

> **Title switches during the overlap window (t < 2.0): 0.**
> Pass four: **3 switches in 2.9 s** (`CITY 3 of 12` at t = 0 → `CITY 2 of 12`
> at 0.912 → back at 1.229).

At t = 0.8 balloons' `runFinish` called `takeStrip` and it returned: held = 3,
want = 3, `176.38 <= 177.43`. Cleanup's celebration kept the strip for its whole
window and handed over only after its own `end`.

*One number I did not pin down:* after the handover the pair read
`BALLOON FESTIVAL` / `CITY 3 of 12`, and I had intended balloons to be at 2. The
two events were both started with `atMe` from the same spot, so their zones
overlapped and one teleport can collect an item from each — balloons' `got` was
most likely genuinely 3. I did not re-read the server state at that instant to
confirm, and it does not bear on the zero-switch result. Overlapping zones are a
dev-hook artifact; the director never runs two collect events at once.

## DEFECT 3 — the preposition  PASS, all four shapes

Both `areaOf()` shapes were located first by starting a `cashdrop` at five
positions and reading `ev.area`: `the residential district`,
`the downtown district`, `the entertainment district` (the
`"the <district> district"` shape) and **`the south-east of town`** (the
`"the <compass> of town"` shape).

Phone rows read through the real tray tap (`GetGuiObjectsAtPosition` confirmed
the click landed on `EventTrayTap` first), verbatim:

| Case | Measured row |
|---|---|
| comp, compass | `24 cash bags dropped in the south-east of town · first one there keeps it` |
| coop, compass | `12 pieces of litter in the south-east of town · walk over them to grab them` |
| comp, district | `24 cash bags dropped in the downtown district · first one there keeps it` |
| coop, district | `12 balloons in the downtown district · walk over them to grab them` |

All four match the claimed strings. The cooperative district row reads `12`
rather than the brief's illustrative `40` because `goal = 12` with one player,
which is correct. `GO` was visible on every row; count lines read
`24 bags out there · nobody has one yet` and `CITY 0 of 12  ·  YOU 0 of 3`.

The competitive branch is confirmed separately from the cooperative one, as
asked — both now route through the single `local area = ev.area and ("in " ..
ev.area) or "in town"` at `CityEvents.lua:772`.

## Out of scope, as instructed
A **FIND** whose `sSub` shows a bare `the south of town` before its first clue
unlocks is phase A behaviour and is not reported as a regression. For the
record, the one-FIND case I measured in pass four (`LOST PUP`, sub
`the shopping district`) is exactly that, and it is unchanged.

## Console and cleanup  PASS
Complete console for the fifth pass:

```
Hello world, from client!
Hello world, from server!
```

No error, no warn, no DataStore queue warning. After ending everything: **0**
live events, **0** `EventLitter` / `EventBalloon` / `EventCashBag` /
`EventBeacon` in `workspace`, tray hidden, strip hidden.

## A harness note, so the numbers above are trustworthy
Midway through the DEFECT 3 work I closed the phone modal by writing
`Visible = false` on the wrong instance in the chain, then compounded it while
trying to recover and briefly hid the HUD root
(`SminskiCityUI.Frame`). That was my test script, not game code — no game file
was touched. Rather than measure through UI state I had hand-patched, I
**restarted Play for a pristine client** and re-ran the district-shape reading
from scratch; the four rows quoted above all come from that clean run. The
compass-shape rows were taken before any of that and are unaffected.

## Not tested
Two Studio clients, the 48-item event, and `BONUS LOCKED` at the finish —
unchanged from earlier passes, already with the human.

**Studio left in Edit mode with Play stopped.** Port 8765 still serving.
