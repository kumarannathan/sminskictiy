# QA — leaderboard-revive (distance board gate, paid-revive exclusion, clock)

**VERDICT: FAIL — one defect, and it is in the same feature's display path.**
Every gate works where it is enforced: all five reachable board cases, the
character gate, and the mid-run-swap exploit behave exactly as specified, and
the clock is fixed. **But the lobby leaderboard displays the excluded runs
anyway.** The gate is applied at `lbSubmit` and not at the point the board is
published, so a run the server correctly refused to submit still appears —
measured twice, at 1664 and 1682 against a stored 1658 and 1676.

**BUILD:** synced in Edit mode. `SminskiServer.server.lua` in Studio
**117,719 → 119,830** — the post-revive figure, and it confirms the drift you
flagged. `Config.lua` 62,157, `Weather.lua` 10,150, `UI.lua` 121,531,
`CityEvents.lua` 88,701 — all already current, all matching.

Markers confirmed in the synced source: `Config.DistancePassives`,
`Config.RanksForDistance`, `Config.ReviveProductId = 3713434937`,
`Config.StudioOwnPasses = false`, `SmiskiRun_LB_Distance_v2`,
`SmiskiRun_LB_ParkWins_v1`, `ranked = Config.RanksForDistance(...)` in
`StartRun`, `local robuxRevived = (run.freeRevives or 0) < (run.freeRobux or 0)`
in `EndRun`, and the rounded `clockText`.

---

## Method, stated up front

The board is an OrderedDataStore, and **the published lobby JSON is not a valid
observable** — the publisher merges every live session's `BestDistance`, which
is deliberately ungated (`SminskiServer.server.lua:1475`). So I read the
authoritative store directly from the Server datamodel:
`GetOrderedDataStore("SmiskiRun_LB_Distance_v2"):GetAsync("u_827213592")`.

Runs were driven through the **real remotes** — `Equip`, `BuyUpgrade`,
`StartRun`, `Revive`, `EndRun` — with a chosen `stats.distance`. `award` clamps
distance to `elapsed * MaxSpeed * 1.4 + 100`, so each case waited ~36 s and
submitted a value well inside the cap (verified uncapped every time by
`BestDistance` landing exactly on the submitted number). This exercises the
gate, the snapshot and the accounting exactly as a player does; the client-side
run simulation has no bearing on them. The `freeLeft` dialog and the phase
A/B/phone regressions were done by actually playing.

`Config.StudsPerMeter` = 3.4. My `BestDistance` started at 5567.59 studs, so
every case had to beat the previous one; the board only ever raises, so "did
not move" is only meaningful when the run was a personal best — it was, in
every case.

---

## The board, six cases

Baseline: v2 entry **nil (empty)** — the fresh store, as documented and not
reported. `Upgrades.SecondChance` = 0. `Passes.revive` = **true**.

| # | Case | Submitted | Personal best | v2 board | Verdict |
|---|---|---|---|---|---|
| 1 | no revive, Glow | 5580 studs | 5567.59 → **5580** | nil → **1641** | **PASS** |
| 2 | coin-cost revive only (250), Glow | 5600 | 5580 → **5600** | 1641 → **1647** | **PASS** |
| 3 | `SecondChance` only, **no revive pass** | — | — | — | **NOT REACHABLE** |
| 4 | revive pass's free revive consumed, Glow | 5620 | 5600 → **5620** | **1647, held** (would be 1652) | **PASS** |
| 5 | pass **and** upgrade, revive **once** | 5640 | 5620 → **5640** | 1647 → **1658** | **PASS** |
| 6 | pass **and** upgrade, revive **twice** | 5660 | 5640 → **5660** | **1658, held** (would be 1664) | **PASS** |

Every "board moved" figure is `floor(distance / 3.4)` exactly. Every "held"
figure was read **4-5 times over 8-12 s** to rule out a slow write, and never
moved. **The personal best moved in all six** — `d.BestDistance` is ungated, as
intended.

**Case 2, the one flagged as most likely inverted, is correct.** Exactly 250
coins were deducted (130,176 → 129,926), the reply carried `freeLeft = 1`
(untouched), and the board moved. `robuxRevived` = `(1 < 1)` = false.

**Cases 5 and 6 exercise the earned-first accounting, and it is exact.** With
`SecondChance` = 1 and the pass, `freeRevives` = 2 (`freeEarned` 1 +
`freeRobux` 1). One free revive → `freeLeft = 1`, and `1 < 1` is false, so it
ranks. Two → `freeLeft = 0`, and `0 < 1` is true, so it does not. A **third**
free revive was correctly refused with `{ ok = false }`.

**Case 3 is not reachable on this account.** It requires the revive pass *not*
owned. `Config.StudioOwnPasses` is `false`, so passes come from a real
`UserOwnsGamePassAsync` check — and this account genuinely owns `revive`
(`Passes.revive = true`). There is no remote that relinquishes a pass. Stating
it rather than passing it: the arithmetic case 3 tests (an earned revive
consumed, no Robux revive consumed, therefore ranks) is the *same* comparison
case 5 exercises and passes — with `freeRobux` = 0 instead of 1, `freeRevives`
after one consume would be 0 and `0 < 0` is false. But I did not measure it.

## The mid-run revive product — **NOT EXERCISED**

`Config.ReviveProductId` **is** set (**3713434937**), so the path exists. I
prompted it mid-run: `MarketplaceService:PromptProductPurchase` returned
without error, but it was never granted — the subsequent `Revive` reply read
`freeLeft = 1` (meaning `freeRevives` was still 2, not 3) and `data.Receipts`
stayed empty. Studio cannot complete a developer-product purchase without a
real Robux transaction, and the prompt is CoreGui, which a LocalScript cannot
drive.

So: **the third Robux revive path is unverified.** What I can say from the
code, labelled as reasoning and not measurement: `ProcessReceipt`
(`SminskiServer.server.lua:995-1007`) increments `s.run.freeRevives` **and**
`s.run.freeRobux` together, so consuming that revive leaves
`freeRevives = freeRobux - 1 < freeRobux` — the identical comparison that case
4 exercises and passes. Reporting it as untested is the honest outcome.

Side effect worth recording: **the CoreGui purchase prompt stayed up and
blocked all subsequent mouse input** ("position hits CoreGUI" on every point),
and Escape is permanently bound to CoreGui so `user_keyboard_input` cannot
dismiss it. Only a Play restart cleared it. Anyone repeating this should prompt
a product last, or budget a restart.

## The character gate

`Config.RanksForDistance` returns true for exactly **Glow, Peach, Galaxy,
Cocoa, Secret** and false for the other ten — matching the five named.

Ghost is not owned by this account, so I used **Night**, also non-ranking
(`RanksForDistance("Night")` = false).

| Case | Submitted | Personal best | v2 board | Verdict |
|---|---|---|---|---|
| Night, beats personal best | 5680 | 5660 → **5680** | **1658, held** (would be 1670) | **PASS** |
| Glow, beats it again | 5700 | 5680 → **5700** | 1658 → **1676** | **PASS** |
| **start Night → swap to Glow mid-run** | 5720 | 5700 → **5720** | **1676, held** (would be 1682) | **PASS** |

The exploit was genuinely attempted, not blocked upstream:
`Equip("Glow")` **succeeded mid-run** (`EquippedCharacter` read `Night` at
`StartRun`, `Glow` two seconds later and at `EndRun`), confirming `Equip` has
no mid-run guard — and the board still did not move, across five reads over
12.5 s. **The snapshot does exactly what it was added for.**

## `freeLeft` and the paying player's dialog  PASS

The server half, measured across five real `Revive` calls:

| Situation | `freeLeft` |
|---|---|
| coin-cost revive, allowance 1 | **1** (untouched) |
| free revive, allowance 1 | **0** |
| free revive, allowance 2 | **1** |
| second free revive, allowance 2 | **0** |
| third free revive, exhausted | `{ ok = false }` |

The dialog half, read verbatim off the revive card after a real caught death
(`intro → playing → caught → revive`), with `SecondChance` = 1 and the pass:

```
TextLabel   "ONE MORE RUN?"
TextLabel   "keep going from right here"
TextButton  "FREE REVIVE  (2 left)"
TextButton  "REVIVE  ◉ 250"
TextButton  "REVIVE  (Robux)"
TextButton  "no thanks"
```

`(2 left)` = 1 earned + 1 pass, `◉ 250` = `Config.ReviveBaseCost`, all four
buttons present, holder 460 x 420. Unchanged.

## The stores

- **v2 started empty** (`GetAsync` → nil) and no error was raised; the lobby
  JSON decoded cleanly with both `distance` and `wins` keys throughout. Not
  reported as a defect, as instructed.
- **`wins` is untouched**: store `SmiskiRun_LB_ParkWins_v1`, my entry **1**
  before and **1** after, and the published board still carries its ten real
  entries with `NoahLeKittyCat` on 2 at the top.
- v1 distance holds no entry for this account, so I could not compare v1 and v2
  contents; the store-name bump is confirmed in source and by v2 starting empty.

## The clock  PASS

`Weather.clockText` tested directly (it is a pure function):

| Input | Measured | Required |
|---|---|---|
| 19.4 | **`7:24 pm`** | `7:24 pm` (was `7:23 pm`) |
| 19.9999 | **`8:00 pm`** | `8:00 pm`, never `7:60` |
| 23.999 | **`12:00 am`** | `12:00 am`, never `24:00` |

Plus boundaries: 0.0 → `12:00 am`, 11.9999 → `12:00 pm`, 12.0 → `12:00 pm`,
23.5 → `11:30 pm`, 6.1 → `6:06 am`, 13.008333 → `1:00 pm`.

Swept **3,842** values (every whole minute of the day, and every 0.01 h from 0
to 24): **zero** outputs containing `:60`, or beginning `24:` or `0:`.

## Phases A, B and the phone — unregressed on the newest server build

- **Collect, end to end**: a 12-item `balloons` event swept to its goal.
  `sClock` = `DONE` and `CITY 12 of 12` at t = 0, **`WE DID IT!`** visible at
  **t = 0.11**, hidden at **t = 4.31**, `EventTray.Parent` still the strip card.
- **FIND**: `icecream` claimed → `ok`, `first = true`, **+1560 coins**
  (base 320 × 4.875 — the multiplier is now 4.875 rather than 4.5 because the
  login `StreakMult` moved 1.2 → 1.3), `found = 1`, `firstBy` = me.
- **Phone, all three entry points**: shade transition log
  `10.16:true; 12.23:false; 14.10:true; 16.10:false; 17.96:true` — three clean
  opens from the **PHONE button**, **`EventTrayTap`** and the **strip tap**,
  body at `{0, 24}, {1, -24}`.

---

## FAILURE — the lobby board displays the runs the gate excluded

**What happened.** Every exclusion works at submit time and none of them works
at display time. The lobby leaderboard publisher merges each live session's
`BestDistance`, which is ungated by design, so an excluded run is shown on the
board anyway — above the honest entry.

**Measurements**, both taken after the publisher's 60 s refresh:

| Occasion | Excluded because | Authoritative v2 store | Lobby board JSON |
|---|---|---|---|
| after case 6 | a Robux-granted revive was consumed | **1658** | **1664** |
| after the swap exploit | run started as a non-ranking character | **1676** | **1682** |

1664 = `floor(5660 / 3.4)` and 1682 = `floor(5720 / 3.4)` — in both cases
exactly the personal best of the run the server had just refused to submit. The
final state on exit: store **1676**, board showing **1682**.

**Cause.** `game/SminskiServer.server.lua:1475`:

```lua
local v = id == "distance" and math.floor((s.data.BestDistance or 0) / Config.StudsPerMeter) or (s.data.SurvivalWins or 0)
```

`d.BestDistance` is written unconditionally at `:468-469`, and only the
`lbSubmit` call inside it is gated by `ranked`. The merge then re-introduces
precisely what the gate removed. The merge itself is wanted — its comment says
it exists so a fresh best shows immediately and so the board still works where
DataStores are unavailable — but it needs a *ranked* value to merge.

**Scope, stated fairly.** The merge is over `sessions`, so the leak is visible
only on the server the player is on, and only while they are on it; the stored
cross-server board is correct and my five-read checks prove nothing was
written. But the feature exists because "Robux bought leaderboard rank", and a
player who buys a revive, sets a personal best and stays on that server is
displayed above players who did not — which is the same complaint in a smaller
blast radius.

**Fix shape.** Record a ranked-only best alongside the personal best — set it
in the same `if ranked then` branch at `:473` — and merge that at `:1475`
instead of `BestDistance`. Contained, and it keeps both properties the merge
was added for.

**Owner:** `game/SminskiServer.server.lua` → **server-engineer**.

---

## Console

Only one entry for the whole session, and it is not game code:

```
debug.profileEnd() - No active profile annotation. At: Stack Begin
Script 'MaterialManager.MaterialManager.Packages._Index.ReactReconciler...'
  ... 16 frames, all MaterialManager ...
Stack End
```

That is Roblox's own **MaterialManager Studio plugin**. **No error or warn from
`SminskiServer`, `Config`, `Weather`, `UI` or `CityEvents`** across: the clock
sweep, eight driven runs, five `Revive` calls, two played runs to a caught
death, a developer-product prompt, a collect event end to end, a FIND claim and
three phone opens.

## Not tested, and why

1. **Case 3 (no revive pass owned)** — this account genuinely owns the pass and
   `Config.StudioOwnPasses` is `false`, so ownership is real; no remote gives it
   up. Its comparison is the same one case 5 passes.
2. **The mid-run revive product** — the id is live (3713434937) but Studio
   cannot complete a developer-product purchase, and its prompt is CoreGui.
   Prompted without error, never granted. Path unexercised.
3. **Ghost specifically** — not owned by this account; used **Night**, also
   non-ranking, for the character gate.
4. **v1 vs v2 content comparison** — v1 holds no distance entry for this
   account, so there was nothing to compare against.

## Recorded as not-defects, not re-reported
The empty `_v2` board, `Secret.coin = 2`, and `UI.lua:816`'s missing guard.

**Studio left in Edit mode with Play stopped**, all city events ended, **0**
event models in `workspace`, and my `QA_*` test artifacts destroyed. Data
written by testing, for the record: `BestDistance` 5567.59 → 5720,
`Upgrades.SecondChance` 0 → 1 (bought for the test), v2 board entry
nil → 1676. Port 8765 still serving.

---
---

# SECOND PASS — the display defect, and the restructure

**VERDICT: PASS.** The display defect is fixed: the lobby JSON now shows the
ranked value while the personal best sits 56 metres above it. And the
regression the restructure exists for — the one my own suggested fix would have
introduced, and which none of my six revive cases could have caught — is
**absent**, measured on the very save state that would have exposed it.

**BUILD:** `SminskiServer.server.lua` in Studio **119,830 → 121,265**.
`Config.lua` 62,157, `UI.lua` 121,531, `Weather.lua` 10,150 — unmoved, as
stated.

> **Byte-count discrepancy:** the brief says **121,105**; disk and Studio both
> read **121,265** (+160). The code described is all present and behaves as
> described, so I tested what is there — but if a further edit was expected, it
> did not land.

Markers confirmed in the synced source: `BestRankedDistance = 0,` in the
defaults (`:50`), the separate
`if ranked and distance > (d.BestRankedDistance or 0) then` (`:490`), the merge
reading `s.data.BestRankedDistance` (`:1498`), and **no remaining
`id == "distance" and math.floor((s.data.BestDistance`** anywhere. `UI.lua`
references `d.BestDistance` exactly **twice** and `BestRankedDistance`
**zero** times.

---

## 1. The two failing occasions, re-run  PASS

Both were driven to a **new personal best** so the old code would have leaked,
and this time I read the JSON specifically.

| | Before the fix | Now |
|---|---|---|
| after a Robux-revived best | store 1658, **JSON 1664** | — |
| after a Night→Glow swap best | store 1676, **JSON 1682** | — |

Re-run on the fixed build:

| Step | `BestDistance` | `BestRankedDistance` | v2 store | lobby JSON |
|---|---|---|---|---|
| baseline | 5720 | **0** | 1676 | **1676** |
| Robux-revived best (two free revives, `freeLeft` 1 → 0) | 5720 → **5800** | **5710, held** | 1679 | — |
| Night→Glow swap best (swap confirmed: `Night` at `StartRun`, `Glow` mid-run and at `EndRun`) | 5800 → **5900** | **5710, held** | 1679 | — |
| final | **5900** = 1735 m | **5710** = 1679 m | **1679** | **1679** |

**The JSON reads 1679 — the ranked value — while the personal best is 1735 m.**
A 56-metre gap that the old merge would have leaked in full. `wins` still
carries its ten real entries with `NoahLeKittyCat` on 2 at the top.

Worth noting the baseline row on its own: at the very start of this pass
`BestRankedDistance` was 0 and `BestDistance` was 5720 (= 1682 m), and the JSON
already read **1676** rather than 1682. The merge had stopped leaking before I
ran anything.

## 2. The case the restructure exists for  PASS — and this is the one that matters

Preconditions verified first, on the real save:

- `BestDistance` = **5720** (inflated, from my previous pass's swap run)
- `BestRankedDistance` = **0** — the new field **inherited nothing** from
  `BestDistance`, which is what `reconcile()`'s default is for

Then a **ranked** run (Glow, no revive) finishing **well below** the personal
best:

| | Measured |
|---|---|
| submitted | **4000** studs (cap at 27.0 s elapsed was 4641, so uncapped) |
| `BestDistance` | **5720 → 5720**, unchanged |
| `BestRankedDistance` | **0 → 4000** |

**`BestRankedDistance` moved on a run that did not come near the personal
best.** Under my suggested nesting it would still be 0 and nothing would have
submitted — for this account, and for every account carrying an assisted best.
The engineer was right to decline it.

**And the board itself moves, not just the field.** The literal expectation in
the brief — "the board must show `floor(4000/3.4)` = 1176" — cannot hold on this
account, because `lbSubmit` only ever raises and the store already held **1676**
from the earlier passes. So I ran the discriminating version: a ranked run
**below the personal best but above the stored value**, in the 5699–5719 stud
window:

| | Measured |
|---|---|
| submitted | **5710** studs — below the 5720 personal best |
| `BestDistance` | **5720 → 5720**, unchanged |
| `BestRankedDistance` | 4000 → **5710** |
| **v2 store** | **1676 → 1679** |

That is the airtight form: **the real board moved on a run that was not a
personal best.** Nesting could not have produced it.

## 3a. A ranked run below the ranked best  PASS
Glow, no revive, **5000** studs (below the 5710 ranked best):

| | Measured |
|---|---|
| `BestRankedDistance` | **5710 → 5710**, not lowered |
| `BestDistance` | **5900 → 5900**, not lowered |
| would have been | 1470 m |

The `>` comparison refuses to lower either number.

## 3b. The player-facing number still reads `BestDistance`  PASS
- `UI.lua` references `d.BestDistance` exactly **twice** — `:1607`
  (`statTiles.BestDistance`) and `:2253` (`bestDistLabel`, inside
  `UI.refresh()`) — and `BestRankedDistance` **zero** times.
- Live, the rendered label reads **`1,682m`**. That is
  `floor(5720 / 3.4)` — my `BestDistance` at the moment `UI.refresh()` last
  ran. It is **not** 1,679m, the ranked value, and `BestRankedDistance` has
  never held 5720 at any point in its existence (0 → 4000 → 5710), so 1,682
  can only have come from `BestDistance`.

**One half not measured:** I could not get `UI.refresh()` to run again during
this pass (a throwaway run and opening/closing a screen did not trigger it), so
I did not watch the label advance 1,682m → 1,735m. The static count and the
provenance of the stale value are what I have; saying so rather than implying I
saw it update.

## Console  PASS
Complete output for this pass:

```
Hello world, from server!
Hello world, from client!
```

Nothing else — no error, no warn — across six driven runs, two free revives, a
mid-run character swap, five OrderedDataStore reads and a throwaway run.

## Carried forward, as agreed
- **Case 3** (revive pass not owned) stays unreachable and is accepted as
  covered by inference from cases 5 and 6.
- **The mid-run revive product** stays covered by inference, not measurement.
- My `PromptProductPurchase` / CoreGui-input note stands on the record.

## `StreakMult` — accepted, and adopted
Confirmed independently this pass: `Login.streak` = **4** →
`Config.StreakMult(4)` = **1.3**, so the chain
`1.5 × 1.3 × 1.25 × 2 = 4.875`. Nothing was edited. **I have stopped writing
coin totals down**: from here on any payout expectation is computed from
`Config.StreakMult(d.Login.streak)` at measurement time rather than asserted as
a constant, and I will say which streak a quoted figure assumes.

**Studio left in Edit mode with Play stopped.** State written by this pass, for
the record: `BestDistance` 5720 → **5900**, `BestRankedDistance` 0 → **5710**,
v2 board entry 1676 → **1679**. Port 8765 still serving.
