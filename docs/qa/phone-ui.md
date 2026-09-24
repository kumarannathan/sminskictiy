# QA — phone-ui (the phone UI rebuild)

**VERDICT: FAIL — one defect, on the compact path.** 23 of the builder's 26
checks pass, 1 fails, 2 are not reachable from one client. **Phase B is not
regressed**: every one of checks 9-15 passes, including a full collect event
end to end. The two behaviours that had never rendered in the city before —
GO's `PATH SET` card and the no-address in-row hold — both work.

The one defect is check 1 on compact: **a viewport change while the phone is
open leaves it at `UIScale 0.752` instead of 1.0**, shrinking the home-bar
target to 99 x 23 real px against the 132 x 30 the design requires. It is
self-healing on the next open, and the cause is pinned to one line.

**BUILD:** synced in Edit mode after stopping Play. `CityEvents.lua` in Studio
**66,974 → 88,701** — matching the measured figure exactly. `Config.lua`
59,721 and `SminskiServer.server.lua` 116,305 unchanged. Markers confirmed in
the synced source: `modalCard(560, 560, "PHONE")` **gone**, `PhoneShade`,
`PhoneEat`, `PhoneHomeTap`, `E.closePhone`, `PATH SET`, and the two sections
built by `phoneSection(key, order, gap)` at orders **10** and **70**.

**Test environment.** Viewport 1160 x 719, root `UIScale` 0.90625, design
canvas **1280 x 793**, `UI.compact()` false, GuiInset (0, 58). The spec's
worked numbers assume a 760-tall canvas; where a check quotes a
canvas-dependent value I give the measured design-space number and the
expected value recomputed for this canvas.

---

## Geometry and tweens

### Check 1 — `UIScale == 1.0` exactly  **FAIL on compact** (desktop PASS)
| Case | Measured |
|---|---|
| desktop, 1280 x 793 canvas | **1.0** exactly — PASS |
| compact, opened fresh | **1.0** exactly, shell (376.0, 480.0) — PASS |
| **compact, viewport changed while the phone was open** | **0.7520** — FAIL |

See FAILURE 1 for the measurement, the cascade and the cause.

### Check 2 — parked off-canvas when closed  PASS (the check's own wording is off by the inset)
`S.Visible == false` ✓. `B.AbsolutePosition.Y` = **671.53**, viewport Y = 719,
so `671.53 >= 719` is **false** as literally written — but this ScreenGui has
`IgnoreGuiInset = true`, so `AbsolutePosition` is inset-relative and the true
screen top is **671.53 + 58 = 729.53**, which is below the 719-tall viewport.
Body spans 729.53-1266: genuinely off-canvas. Substance PASS; the check should
compare `AbsolutePosition.Y + inset.Y`.

### Check 3 — 0.4s after opening  PASS
| Property | Expected | Measured |
|---|---|---|
| `S.Visible` | true | **true** |
| `B.AbsolutePosition` design | (24, 144) on a 760 canvas | **(24, 177)**; expected for this 793 canvas = 793 − 24 − 592 = **177** |
| `B.AbsoluteSize` design | (376, 592) | **(376, 592)** |
| `B.Rotation` | 0 | **0** |
| `S.BackgroundTransparency` | 0.72 ± 0.01 | **0.7200000286** |

### Check 4 — exact positions, no drift over five cycles  PASS
`B.Position` open = `{0, 24}, {1, -24}` and `== UDim2.new(0,24,1,-24)` is
**true**; closed = `{0, 24}, {1, 604}` and `== UDim2.new(0,24,1,604)` is
**true**. Five open/close cycles driven through real clicks, then re-measured:
position `{0, 24}, {1, 604}`, `Rotation` 0, `AbsolutePosition` (21.75, 671.53)
— **identical to the first reading**. No drift, no stacked Position tweens.

### Check 5 — clear of the prompt card  PASS
Prompt card design X = **405**. Phone right edge design = **400**. **Clear by
5px**, exactly the arithmetic the 376 width was chosen for.

### Check 6 — SHOP button  PASS in substance
At the SHOP button's centre the hits include the SHOP `TextButton` and, among
`Phone*`, **only `PhoneShade`**. The phone **body** does not overlap SHOP:
`bodyOverlapsShop = false`, SHOP design y 86-137, phone top design y **177**.
The literal "no `Phone*`" cannot hold while the modal is open, because the
shade is a full-screen `TextButton` by design (and `City.anyModalOpen()`
requires exactly that shape).

### Check 7 — input ordering  PASS in substance; the RowGo clause is unsatisfiable as written
This was named the riskiest item, so here are the ZIndexes and the behaviour.

- **`PhoneHomeBar` centre returns `PhoneHomeTap(TextButton, z5)`** ✓, above
  `PhoneEat` (z2). PASS as written.
- **`RowGo` centre returns the GO `TextButton`** ✓ — **and also
  `RowTap(TextButton, z0)`**. `GetGuiObjectsAtPosition` returns *every* object
  whose rect contains the point regardless of input priority, and `RowTap`
  spans the whole row, so it will always be in that list for any correct
  implementation. The clause cannot pass.
- What actually decides the click is correct: GO is z1 inside `RowGo` (z1),
  `RowTap` is **z0**, so GO wins; and the whole `PhoneScreen` subtree is z3,
  above `PhoneEat` (z2), so row taps are not swallowed by the eat layer.
  Measured ZIndexes: `PhoneScreen` 3 · `PhoneEat` 2 · `PhoneHomeTap` 5 ·
  `PhoneHomeBar` 4 · GO 1 · `RowTap` 0.
- Verified behaviourally rather than by list membership: clicking GO ran GO's
  action (check 25 — path set, `PATH SET` card, phone closed), and clicking a
  GO-hidden row ran `RowTap`'s action (check 13 — one dull click, 1.2s hold).

Recommend restating the check as "the GO button's ZIndex exceeds `RowTap`'s".

### Check 8 — bezel vs shade  PASS
Bezel tap at x = body left + 8 design px, mid-height (top interactive hit
`PhoneEat`): `S.Visible` still **true**. Shade tap at (1120, 359), the only
hit being `PhoneShade`: **closed**, `B.Position` back to `{0,24},{1,604}`.
`PhoneEat` earns its place as the one over-budget instance.

---

## Phase B regression — the priority

### Check 9 — `RowCount.TextColor3`  PASS
| Row | Measured | Expected |
|---|---|---|
| CITY CLEANUP (collect) | **(0.227451, 0.243137, 0.196078)** = rgb(58,62,50) | `C.ink` |
| CASH DROP! (collect) | **(0.227451, 0.243137, 0.196078)** | `C.ink` |
| SMINSKI SIGHTING (find) | **(0.501961, 0.501961, 0.439216)** = rgb(128,128,112) | `C.inkSoft` |
| ICE CREAM TRUCK (find) | **(0.501961, 0.501961, 0.439216)** | `C.inkSoft` |

Also checked after a hold expired: the row reverted to
`nobody has found it yet` in **`C.inkSoft`** (see check 13), so the colour
survives the hold path.

### Check 10 — `RowClue.Text` keeps the `in ` prefix and the done variants  PASS
- coop, compass area: `12 pieces of litter in the south of town · walk over them to grab them`
- coop, district area: `12 balloons in the residential district · walk over them to grab them`
- comp: `24 cash bags dropped in the south of town · first one there keeps it`
- FIND, claimed: **`done -- nice one!`**

The `in ` prefix I verified in pass five of collect-events is intact on both
branches.

### Check 11 — `TextFits` with a 10-char leader name  PASS, desktop and compact
My DisplayName is 13 chars, so `clampName` truncates it — the exact test.

| | `RowCount.Text` | `clueFits` | `countFits` |
|---|---|---|---|
| desktop | `22 bags left · indiannarw… 2 · YOU 2` | **true** | **true** |
| compact | `23 left · indiannarw… 1 · YOU 1` | **true** | **true** |

Compact used the **short wording** (`23 left` not `23 bags left`), which is the
spec's own mitigation for the 234px compact slot. Both fit.

### Check 12 — `RowCount` clears `RowGo`  PASS
| | count bottom | GO top | gap | required |
|---|---|---|---|---|
| desktop | 296.34 | 298.16 | **2.0 design px** | 2 |
| compact | — | — | **3.01 design px** | 4 |

Desktop is exact. The compact gap read 3.01 rather than 4 **because it was
measured during the 0.752 transient** (4 × 0.752 = 3.01); `check12_ok` was
still true, so nothing overlapped. On a correctly-scaled compact phone the gap
is 4. Not a separate defect — a consequence of FAILURE 1.

### Check 13 — GO-hidden rows  PASS, both cases
**Claimed FIND** (ICE CREAM TRUCK after claiming it through the real world
prompt): `RowGo.Visible == false` ✓, `clue` = `done -- nice one!`. Tapping the
row produced **exactly one sound, `Click@0.600/0.2000`** — `Audio.play("Click",
0.6, 0.5)` with Click's 0.4 base volume — and **no text change** (the only
later change in the 13s log was the event expiring and the list re-sorting).
`S.Visible` stayed true.

**No address** (a sighting with no `spot` and no `hint`): tapping put
**`no address yet -- follow the clues`** in `RowCount` in
**(1, 0.490196, 0.431373) = `C.coral`** for **1.217 s** measured
(9.077 → 10.294), then reverted to `nobody has found it yet` in `C.inkSoft`.
**`S.Visible` stayed true for the entire hold** — the refusal did not close the
thing being read, which is the point.

### Check 14 — strip and tray untouched, one full collect event  PASS
`EventTray.Parent == card` (the strip's own card) throughout ✓.
`EventTrayFill.Size` stepped through **23 distinct fractional values** during
the sweep (0 → 0.082 → 0.122 → 0.148 → 0.163 → 0.205 → 0.243 → 0.288 → 0.329 …)
— tweening, not snapping ✓.

Finish, t = 0 at `sClock` becoming `DONE`:

| t | state |
|---|---|
| 0.00 | `DONE`, `CITY 12 of 12`, `YOU 12 · BONUS`, fill 0.916 |
| 0.11 | **`WE DID IT!`** visible |
| 0.26 | `YOU 12 · PAID`, fill **1.0** |
| 4.31 | big line hidden |
| 5.30 | tray hidden, clock back to a countdown |

Every phase B timing holds under the new phone.

### Check 15 — all three entry points  PASS
PHONE button ✓ (used throughout), **`EventTrayTap`** ✓ (clicked at the tray
centre, confirmed `EventTrayTap` was the hit first), **strip tap** ✓ (the
card's own z6 TextButton on the 50px row). All three opened it to
`{0, 24}, {1, -24}`.

---

## Feed and layout

### Check 16 — 1 live event  PASS
`PhoneRow1.Visible` true, rows 2 and 3 **false**,
`AbsoluteCanvasSize.Y` **396.94** <= `AbsoluteSize.Y` **396.94** — no scroll.

### Check 17 — 3 live events  PASS
`AbsolutePosition.Y` **218.41 < 350.72 < 483.03**, strictly increasing; gaps
**8.0 design px** between rows 1-2 and 2-3; canvas **563.69** > view **396.94**
— scrolls.

### Check 18 — section order  PASS, deviation confirmed
`PhoneSecNow.LayoutOrder` = **10**, `PhoneSecNews.LayoutOrder` = **70** (not
the spec's 30 — the recorded deviation), and news renders **below** Now
(y 354.34 > 171.28).

### Check 19 — the `3 of N` blurb  PASS
4 live → **`3 of 4 things happening in the city`**; 5 live → **`3 of 5 things
happening in the city`**; 1 live → `1 thing happening in the city`.

### Check 20 — status bar  PASS (with a one-minute note that is not the phone's)
`city("sky", 19.4)` forced 19.4h / `rain`. With the phone open:

| | Measured | Expected |
|---|---|---|
| `PhoneClock.Text` | **`7:23 pm`** | `7:24 pm` |
| `PhoneWx.Text` | **`Rain`** | one of the six state names |
| `PhoneWxIcon.Image` | **`rbxassetid://95676902868697`** | non-empty |
| clock font / size | FredokaOne / **15** | FredokaOne 15 desktop |

The icon also **changed** with the state (`…877366` for Clear →
`…868697` for Rain), so it tracks rather than being fixed.

The minute is not the phone's: `Weather.clockText` (`game/Weather.lua:192`)
does `math.floor((hour % 1) * 60)`, and `19.4 % 1` is 0.3999999999999986 in
float64, × 60 = 23.99999999999992, floored to **23**. The phone faithfully
prints `current().clock`. Owner of that line: **server-engineer**
(`game/Weather.lua`). Cosmetic, pre-existing, not this feature's defect.

**Not verified:** forcing `City.Weather = nil` to prove both labels go
`Visible = false` rather than printing a placeholder. `City.Weather` is a field
on the live City table and my console runs in a separate Luau VM, so I cannot
nil it. `city("sky", false)` releases a forced state but does not remove the
module.

---

## Modal contract and escape hatches

### Check 21 — modal contract  PASS
While open: `S.Visible`, `B.Visible`, `R.Visible`, `G.Enabled` all **true**.
The shade is a **`TextButton`, `ZIndex == 20`, direct child of `H.root`** —
`S.Parent == R` confirmed — so `City.anyModalOpen()`'s scan is satisfied. I
replicated that scan (a visible `TextButton` child of `H.root` with
`ZIndex == 20`): **true** while open. I could not call `City.anyModalOpen()`
itself from the test VM; the replication is of the literal implementation at
`City.lua:1299`.

### Check 22 — `City.hudOff` closes it within 0.1s  PASS
Watcher on `S.Visible` every Heartbeat; `SR_ShowMenu` fired at t = 1.0000 and
`SR_TestPick("shop")` ~50ms later. Shade went **false at t = 1.0805** —
**80.5 ms** after the first trigger, ~30 ms after the second. Inside the 0.1s
requirement. This is the bug shape the old build had, and `E.step` now catches
it above the 0.25s gate.

### Check 23 — reopen within 0.1s (the `phone.gen` guard)  **NOT REACHABLE from one client**
The close path deliberately keeps the shade alive for 0.20s after the slide
starts. Any click inside that window therefore lands on the shade and is read
as another close — the PHONE button, `EventTrayTap` and the strip tap are all
underneath it. There is no way to re-enter `openPhone()` within 100ms through
real input, and `E.openPhone` is not reachable from the test VM. What I can
say: five open/close cycles at ~600-700ms left no stuck state (check 4), and
the guard is the same `bigGen` idiom already verified on the finish line in
collect-events. Saying so rather than passing it.

### Check 24 — `City.Events.leave()` with the phone open  **NOT VERIFIED**
`E.leave()` is only reachable through `City.leave()`, and the route to that is
walking into `Places.CityExit`. With the phone open that does not happen: from
4 studs away, armed (I had been 120 studs out), not in a car, I sampled
`Activity` once a second for 8 seconds and it stayed **`city`** with the shade
**true** the whole time. In pass 1 of collect-events the same walk-out fired
immediately with no modal open, so the exit trigger appears to be suppressed
while a modal is up — which is reasonable behaviour, but it makes this check's
scenario unreachable by walking. I could not call `E.leave()` directly.
Adjacent evidence: the instant-close path is exercised and passing via check 22
(hudOff closed it in 80.5 ms with no tween).
Flagging the suppression as an observation only — **not isolated**, since I did
not re-confirm the no-modal walk-out in this session.

### Check 25 — GO's `PATH SET`  PASS — a surface that never rendered before
Clicking GO on the CASH DROP! row:

| t | what |
|---|---|
| 7.234 | notification appears bottom-right: **`PATH SET`** / **`CASH DROP! · follow the green dots`** at abs (902, 443) |
| 7.301-7.367 | slides up to (902, 428) — the `noteRoot` corner |
| **7.434** | **`S.Visible` → false**, the phone put itself away |
| 11.767 | card gone (≈4.3s, matching `J.notify`'s 4.5s) |

`B.Position` back to `{0, 24}, {1, 604}`. Routed through `City.Jobs.notify`,
so it does not pollute CITY NEWS.

---

## Compact

### Check 26 — compact  PASS except the transient
Forced via `StudioDeviceSimulatorService` (reachable from the PlayClient
context): iPhone 13, landscape. Viewport **749 x 367**, root `UIScale`
**0.60** (the touch floor), design canvas **1248 x 611**, `TouchEnabled` true,
`UI.compact()` → **true**.

Measured **after the phone was reopened on that viewport**:

| | Required | Measured |
|---|---|---|
| `B.AbsoluteSize` design | ≈ (376, 480) | **(376.0, 480.0)** |
| body `UIScale` | 1.0 | **1.0** |
| row height | 156 | **156.0** |
| `PhoneHomeTap.AbsoluteSize` real px | >= (132, 30) | **(132, 30.0)** |
| `PhoneNews.Text` lines | 3 (4 desktop) | **3** (desktop measured **4**) |
| `PhoneClock.TextSize` / `PhoneWx.TextSize` | 16 / 13 | **16 / 13** |
| check 12 ordering | count above GO | **true** |
| check 16 | row1 visible, rows 2/3 per event count | **row1+row2 visible for 2 events** |
| `B.Position` / `Rotation` / shade | `{0,24},{1,-24}` / 0 / 0.72 | **all as desktop** |

My own independent computation of `UI.fit(376, 480, 44)` on this canvas
returns **1** — so the metric table and the two-height approach are correct.
The design survives compact; only the transient is wrong.

---

## FAILURES

### FAILURE 1 — a viewport change while the phone is open leaves it at `UIScale 0.752`

**What happened.** The phone was open on desktop; I switched the viewport to
iPhone 13 (749 x 367). `applyPhoneSize()` re-ran — it correctly re-read
`UI.compact()` and applied the compact metric table — but the `fitScale` it
computed was wrong, and it stuck.

**Measurement**, immediately after the viewport change, phone still open:

| | Measured | Should be |
|---|---|---|
| body `UIScale` | **0.7520** | 1.0 |
| shell design size | **(282.76, 360.97)** | (376, 480) |
| row height | **117.31** | 156 |
| `RowCount`→`RowGo` gap | **3.01** | 4 |
| `PhoneNews` height | **49.63** | 66 |
| **`PhoneHomeTap` real px** | **(99.27, 22.56)** | **>= (132, 30)** |

Closing and reopening the phone on the *same* viewport corrected everything
exactly: scale **1.0**, shell **(376.0, 480.0)**, row **156.0**, home tap
**(132, 30.0)**.

**Cause, pinned by arithmetic.** `UI.fit` (`game/UI.lua:315-320`) is

```lua
function UI.fit(w, h, margin)
	local v = workspace.CurrentCamera.ViewportSize
	local sc = uiScale.Scale
	return math.min(1, (v.X / sc - margin) / w, (v.Y / sc - margin) / h)
end
```

It divides the **new** `ViewportSize` by the **stale** `uiScale.Scale`. Both
`UI.lua`'s own `rescale()` and `CityEvents`' handler
(`game/CityEvents.lua:1757-1760`) are connected to the same
`GetPropertyChangedSignal("ViewportSize")`, and on this change `applyPhoneSize`
ran while `uiScale.Scale` was still the desktop 0.90625:

> (367 / 0.90625 − 44) / 480 = (404.97 − 44) / 480 = **0.75201**

which is the 0.7520 measured, to five digits. On the next open, `rescale()` has
long since set the scale to 0.6 and `UI.fit` returns 1.

**Why it matters.** A player rotating their phone, or any viewport change, with
the phone open gets a phone at 75% size whose home bar — the phone's own
control, and the spec's answer to covering the thumbstick — is **99 x 23 real
px** instead of 132 x 30. That is below the 44px touch-target guidance in both
axes, on the one control the compact design leans on. It clears on the next
open, so it is not permanent.

**Fix, and it is one line either way.** Make `UI.fit` compute the scale from
the viewport itself rather than reading `uiScale.Scale` — which fixes every
`UI.fit` caller at once — or `task.defer` the `applyPhoneSize()` inside
`CityEvents`' viewport handler so it runs after `rescale()`.
**Owner:** both files are **client-engineer** (`game/UI.lua`,
`game/CityEvents.lua`). `UI.lua` is the broader fix.

---

## Known and out of scope, as instructed

The two remaining `UI.toast` calls are where they were recorded —
`game/CityEvents.lua:946` (`onReveal`'s "something is sparkling nearby…" /
"you are close -- look around!") and `:1066` (FIND's claim refusal). Both are
phase A code, both still render nowhere, and neither is this feature's defect.
Noted only so the count is on the record for whoever takes the toast-layer
task.

---

## Console

Complete output for the phone session:

```
Hello world, from server!
Hello world, from client!
UI is not a valid member of Folder "ReplicatedStorage.SminskiShared"
Stack Begin
Script 'AssistantCommand', Line 35
Stack End
Attempted to call require with invalid argument(s).
Stack Begin
Script 'AssistantCommand', Line 5
Stack End
```

**No error or warn from any game module** — nothing from `CityEvents.lua`,
`City.lua`, `UI.lua` or the server — across ~30 phone open/close cycles, three
entry points, five collect events, a device switch and a Play restart. Both
console entries are `Script 'AssistantCommand'`, i.e. my own test scripts (a
bad `require` path and a chain walk that hit a ScreenGui), both corrected in
the same session.

---

## Not tested, and why

1. **Check 23 (reopen within 0.1s).** Not reachable through real input: the
   shade deliberately outlives the slide by 0.20s, so every click in that
   window is read as a close. `E.openPhone` is not callable from the test VM.
2. **Check 24 (`E.leave()` with the phone open).** The only route to
   `City.leave()` is walking into `Places.CityExit`, and that does not fire
   while a modal is open — measured 8 seconds at 4 studs, armed, `Activity`
   stayed `city`. Reported as an observation, not isolated.
3. **Check 20's `City.Weather = nil` branch.** Cannot nil a field on the live
   City table from a separate Luau VM.
4. **Clicks while the device simulator is active.** After the compact
   measurements my click coordinates stopped landing — with the simulator's
   `FitToWindow` scaling, `AbsolutePosition` no longer maps 1:1 to the
   coordinates `user_mouse_input` takes. Everything compact above was measured
   numerically; no compact result depends on a click landing. Worth knowing for
   the next run.
5. Two Studio clients, the 48-item event and `BONUS LOCKED` at the finish
   remain unverified-as-shipped from the collect-events work; nothing here
   changes that.

**Studio left in Edit mode with Play stopped**, device simulator stopped
(`GetDeviceAsync()` = `"default"`) and the viewport restored to 1160 x 719.
Port 8765 still serving.

---
---

# SECOND PASS — the `UI.fit` fix, and the runner regression check

**VERDICT: PASS.** The defect I reported is fixed, measured across five
viewport changes in both directions. **The runner is not regressed**: all three
reachable `UI.fit` call sites in `UI.lua` settle at exactly the value an
independent computation gives, stay centred, and do not overflow — including a
results card held through three viewport changes. The two latent fixes
(`applyInsets`, `UI.fitPage`) both read the fresh canvas and produced no new
symptom. One call site (multiplayer results) is not reachable from one client.

**BUILD:** `UI.lua` in Studio **120,677 → 121,531** — the post-fix figure.
Markers confirmed: `canvasScale(v)`, `canvas()`, `UI.fit` opening with
`local cw, ch = canvas()`, and — the crux — **`uiScale.Scale` appears twice in
the file: once as the single write at `:324` and once inside a comment. Zero
reads.** The bug class is gone from the file.

### Three build discrepancies, flagged not resolved

1. **`Config.lua` and `SminskiServer.server.lua` are NOT unchanged.** The brief
   says 59,721 and 116,305; disk and Studio both read **62,157** (+2,436) and
   **117,719** (+1,414). Another lane's work has landed in both. I checked the
   parts that could affect my tests: `Config.Events.List` still holds exactly
   the same six rows (3 find, 3 collect), and the server still creates 24
   RemoteFunctions and 8 RemoteEvents — no new event kind, no new remote. My
   results are against those newer files.
2. **`UI.lua` in Studio before this sync was 120,677, not 121,015.** `UI.lua`
   had never been re-synced in any of my sessions (it was in the module list
   but out of scope), so Studio was carrying an older copy than the brief
   assumed. After = 121,531 = disk, so the pass is against the right build.
3. **`UI.fit` has 10 call sites, not 12** — `City.lua:721`,
   `CityEvents.lua:1380`, `CityGuide.lua:76`, `Garden.lua:580`,
   `Park.lua:632`, `Tour.lua:127`, `UI.lua:825`, `:1693`, `:1764`, `:2131`.
   This does not weaken the audit — the structural argument rests on
   `uiScale.Scale` having exactly one writer, which I verified — but the count
   should be right.

---

## 1. The original defect  PASS

Phone opened on the native desktop viewport and **left open** while the
viewport was switched five times, alternating direction. `bodyScale` is the
`UIScale` on `PhoneBody` that read **0.7520** before the fix.

| # | device | viewport | rootScale | **bodyScale** | shell design | rowH | `PhoneHomeTap` real px |
|---|---|---|---|---|---|---|---|
| 0 | native | 1160x696 | 0.9062 | **1.0000** | 376.0 x 592.0 | 138.0 | 199.4 x 45.3 |
| 1 | iPhone 13 | 749x367 | 0.6000 | **1.0000** | 376.0 x **480.0** | **156.0** | **132.0 x 30.0** |
| 2 | HD 1080 | 1919x1079 | 1.2500 | **1.0000** | 376.0 x **592.0** | **138.0** | 275.0 x 62.5 |
| 3 | iPhone 13 | 749x367 | 0.6000 | **1.0000** | 376.0 x 480.0 | 156.0 | **132.0 x 30.0** |
| 4 | HD 1080 | 1919x1079 | 1.2500 | **1.0000** | 376.0 x 592.0 | 138.0 | 275.0 x 62.5 |
| 5 | iPhone 13 | 749x367 | 0.6000 | **1.0000** | 376.0 x 480.0 | 156.0 | **132.0 x 30.0** |

- **`UIScale` is 1.0000 exactly at every step, with no reopen.** Before the fix
  the very first desktop→compact switch gave 0.7520.
- `PhoneHomeTap` is back to **132.0 x 30.0 real px** at the 0.6 floor — the
  requirement — from the 99.27 x 22.56 I measured, which was under the 44px
  touch guidance in both axes.
- The metric table flips correctly every time (rowH 138↔156, `PhoneNews`
  height 84↔66), so `UI.compact()` is being re-read as well as the fit.
- The phone stayed open (`S.Visible` true) through all five.

## 2. The runner — new scope, no regression

### `UI.open` screens (`UI.lua:825`)  PASS
Opened through the runner's own dev hook on a 1280x768 canvas:

| screen | design | settled scale | off-centre X | expected `UI.fit` |
|---|---|---|---|---|
| shop | 900 x 590 | **1** | **0** | 1 |
| maps | 960 x 540 | **1** | **0** | 1 |
| settings | 560 x 580 | **1** | **0** | 1 |

None scaled below 1.0, all exactly centred. (`chars` and `help` are not real
screen names — see CONSOLE.)

### Revive card (`UI.lua:1693`)  PASS
Reached by playing properly: held W ~9s, released, and let the chaser catch me.
State machine went `intro → playing → caught (12.41) → revive (14.94) →
results`. The holder is resized at show time — `460 x (150 + rows*70 + 60)` —
so it measured 460 x 420 with three buttons, which is why a `460,400` matcher
misses it.

| | Measured |
|---|---|
| scale on the first visible frame | 0.7000 (the deliberate pop-in start) |
| **settled scale** | **1.0000** |
| independent `UI.fit(460, 400)` on this canvas | **1.0000** |
| `AbsoluteSize` | 416.875 x 380.625 = 460 x 420 x 0.90625 |
| off-centre X | **0.0** |
| bottom overflow | **0.0** |

### Results card (`UI.lua:1764`)  PASS, and held through three resizes
Settled **scale 1**, independent `UI.fit(560, 600)` = **1**, `AbsoluteSize`
507.5 x 543.75 = 560 x 600 x 0.90625, off-centre X **0**. (The 0.7000 my first
watcher caught was the first frame, mid-`Back` tween — worth knowing for
anyone re-running this.)

Then, **with the card on screen**, three viewport changes:

| state | canvas | rootScale | card scale | `AbsoluteSize` | off-centre X | top clipped | bottom overflow |
|---|---|---|---|---|---|---|---|
| before | 1280x768 | 0.906 | **1** | 507.5 x 543.75 | 0 | no | **0** |
| → compact | 1248x611 | 0.600 | **1** | 336 x 360 | 0 | no | **0** |
| → HD 1080 | 1535x863 | 1.250 | **1** | 700 x 750 | 0 | no | **0** |
| → restored | 1280x768 | 0.906 | **1** | 507.5 x 543.75 | 0 | no | **0** |

This confirms the audit's claim rather than assuming it: these sites **fire on
show, never on resize**, so the scale is retained and nothing rescales it
wrongly. Returning to the original viewport reproduced the original numbers
exactly — no drift. Worst case I could produce: on compact the "correct if
shown now" fit would be 0.9717 against the retained 1, a 2.8% difference that
produced **zero** measured overflow.

### Multiplayer results (`UI.lua:2131`)  **NOT REACHED**
Needs a multiplayer match, which needs other players; the bridge reaches one
client. It is the same `tween(scale, 0.35, { Scale = UI.fit(...) }, Back)`
shape as the revive and results cards, both of which I did verify, and it is in
the same "fires on show" group — but I did not measure it and am not passing it.

## 3. `applyInsets` and `UI.fitPage`  PASS, no new symptom

**`applyInsets` (`UI.lua:2301`).** The `TopInset` padding lives in the
runner's tree, not the city's. With `GetGuiInset().Y` = 58:

| viewport | rootScale | `TopInset.PaddingTop` | expected `(58-20)/sc` |
|---|---|---|---|
| desktop 1919x1079 | 1.250 | **30.000** | 30.4 |
| compact 749x367 | 0.600 | **63.000** | 63.33 |

The value **swaps with the viewport** — 30 on desktop, 63 on compact — which is
the thing to check: a stale read would have left the desktop 30 on a compact
viewport. The fractional difference (30.000 vs 30.4) is `UIPadding`'s integer
offset, not a scale error.

**`UI.fitPage` (`UI.lua:353`).** The paged screen is
`SminskiRunnerUI.Frame.Frame`:

| viewport | canvas | page scale | page Size |
|---|---|---|---|
| desktop 1919x1079 | 1535x863 | **1.0000** | {0,1535},{0,863} |
| compact 749x367 | 1248x611 | **0.8495** | {0,1469},{0,720} |

0.8495 is `min(1, 1248/1280, 611/720)` = 0.8486 to within 0.1%, and
`1248 / 0.8495 = 1469`, `611 / 0.8495 = 719.2 ≈ 720` — every number derived
from the **current** canvas. Fresh, not stale.

## 4. Phone checks that touch scale, re-run

- **Check 1** — `UIScale == 1.0` exactly: **PASS**, desktop and compact, and now
  also across viewport changes (§1).
- **Check 3** — design position: compact **(24.00, 107.00)** against expected
  611−24−480 = **107.0**; desktop **(24, 247)** against 863−24−592 = **247**.
  `Position` exactly `{0, 24}, {1, -24}` both, `Rotation` 0 both, shade
  `BackgroundTransparency` **0.72** both. **PASS**
- **Check 12** — `RowCount` clears `RowGo`: desktop gap **2** design px,
  compact gap **3.99999 ≈ 4**. **PASS** — the compact gap read 3.01 last pass
  purely because it was measured inside the 0.752 transient; it is 4 now, as
  specified.
- **Check 16** — with 2 live events, rows 1 and 2 visible and row 3 false on
  both viewports; feed canvas > view so it scrolls. **PASS**
- **Check 26** — compact shell **(376.0, 480.0)**, row **156.0**,
  `PhoneHomeTap` **(132.0, 30.0)** real px, `PhoneNews` height **66** (84
  desktop), clock/weather text sizes 16/13. **PASS** — every item that failed
  or read low last pass is now exact.

Phase B spot-check, since I was in the city: a `cleanup` event ran, 4 items
collected, tray read `CITY 4 of 12`, and `EventTray.Parent` is still the strip
card. No change.

## 5. Console

```
Hello world, from server!
Hello world, from client!
Players.indiannarwhal.PlayerScripts.SminskiRunner.UI:816: attempt to index nil with 'face'
  Script '...SminskiRunner.UI', Line 816 - function open
  Script '...SminskiRunner.UI', Line 2364 - function open
  Script '...SminskiRunner', Line 2550 - function open
  Script '...SminskiRunner', Line 2709
  (twice)
```

**Both errors are mine.** `SminskiRunner:2550` is `SRdev.open = function(name)
UI.open(name) end` and `:2709` is the dev BindableFunction — I passed two
screen names that do not exist (`chars`, `help`) while enumerating `UI.open`
screens. Nothing else: no error or warn through five viewport changes, two full
runs, a revive, two results cards, three `UI.open` screens, a tour start and a
collect event.

Worth one line anyway: **`UI.lua:816` does `screens[name].face` with no
existence guard**, so an unknown name throws before reaching the `UI.fit` call
at `:824`. Pre-existing, unrelated to this change, and only reachable through
the dev hook — a player can only get there via buttons that pass valid names.
A `local s = screens[name] if not s then return end` at the top would close it.
**Owner:** `game/UI.lua` → **client-engineer**. Not a regression.

## Carried forward, unchanged

- **Check 7** stated as you accepted it: `GetGuiObjectsAtPosition` is
  ZIndex-blind, so "returns GO and not `RowTap`" is unsatisfiable by any correct
  implementation. The assertion that holds, and that I measured, is
  **`RowGo` z1 > `RowTap` z0** and **`PhoneScreen` z3 > `PhoneEat` z2**.
- **Checks 23 and 24 remain unreached, not passed.**

## Incidental — `Tour.lua:127`, not measured

I started a tour (`city("tour")` returned step 1) but could not locate a
visible Frame of the tour card's 660 design width in any ScreenGui, so I had
nothing to read and skipped it as permitted. Note that on a desktop canvas the
line is undiscriminating anyway — `UI.fit(660, 178)` = 1 and the compact factor
is 1, so the composed value is 1 either way; only a compact viewport would show
the 0.82. From the code it is now internally consistent, since both
`UI.fit` and `UI.compact()` derive from the live viewport.

## A correction to my own pass-four sign-off

I reported the device simulator "stopped (`GetDeviceAsync()` = `default`)" at
the end of the phone pass. That getter was called from the **Edit** datamodel
and returned `"default"` while the simulator was in fact still on
`iphone_13` — this pass opened with the viewport still at 749x367 and the
PlayClient getter reporting `active = "iphone_13"`. **`StopSimulationAsync`
from the Edit context did not take effect; from the Client context it did.**
Worth knowing for anyone using the simulator here. It did not affect any
pass-four measurement (all of those were taken with the viewport read live),
but the sign-off sentence was wrong and I am correcting it rather than leaving
it.

**Studio left in Edit mode with Play stopped**, device simulator verified off
from the Client context before exit, viewport 1160x696, all events ended, **0**
event models in `workspace`, and my `QA_*` test artifacts destroyed. Port 8765
still serving.
