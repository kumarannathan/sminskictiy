# Daily 3 Hunt + capsule ticket meter (phase D) -- UX / UI

Slug `daily-capsule` · lane `ux-designer` · written 2026-09-21
Reads, in order: `docs/specs/daily-capsule/loop.md` (my brief -- every number in
it is taken as given), `docs/specs/phone-ui/ux.md` (the phone I design against),
`game/CityEvents.lua`, `docs/specs/collect-events/ux.md` (§7 is my template for
the overlap arithmetic), `game/UI.lua`, `game/City.lua`, `game/CityJobs.lua`,
`game/Places.lua`, `.claude/rules/design.md`, `.claude/rules/performance.md`.

**One sentence.** The meter is a **120x48 capsule pill in the one free slot of
the HUD's top-right row** -- between the coin pill and MENU -- which is
motionless unless you are being paid and carries the ticket count as a number;
the Daily 3 is a **three-row phone section at `LayoutOrder` 50** whose badges go
paper -> **sky** (someone else found it) -> **mint** (you found it), so the
social clue-tiering is a colour you learn in one day; and the third find reuses
phase B's `bigHolder` for one 4.2s line and nothing else.

---

## WHAT EXISTS ALREADY

Everything in this spec is reuse except two new objects (the pill, the phone
section). No new component type. No new icon. No new remote.

### The free space, found rather than assumed

| Where | Fact | What it means here |
|---|---|---|
| `City.lua:572-580` | coin pill `170x48`, `AnchorPoint (1,0)`, `Position (1,-312,0,26)` | Its right edge is `canvasW-312`. |
| `City.lua:538-542, 550-564` | right nav column `150x56` at `Position (1,-24,0,y)` | Its left edge is `canvasW-174`. |
| -- | **so the band `canvasW-312` .. `canvasW-174` at y 26-74 is 138 design px of empty HUD, on every canvas width, because both neighbours are right-anchored** | This is where the meter goes. It is the coin pill's neighbourhood, in the money row, and it is the only free slot in the HUD that does not touch phase B. |
| `City.lua:693-697` | boost banner `340x54` at `(0.5,0,0,92)` | Rules out anything *below* the coin pill: a 200-wide plate at y 80-116 would clip the banner's x 470-810 on a 1280 canvas. Worked, and it is why the pill goes beside the coin pill rather than under it. |
| `CityEvents.lua:1221, 1256-1264` | event strip y 152-202 and progress tray y 202-248, both 340 wide, centred | **Shipped and tested. Not touched, not moved, not restyled.** Phase D takes nothing from the top-centre column. |
| `CityEvents.lua:1310-1321` | `bigHolder` `620x48` at `(0.5,0,0,256)`, `bigText` FredokaOne 34 stroke 3, `bigScale` | The city's existing "big news over the world" object. The Daily 3's third find borrows it. |
| `CityJobs.lua:92-97` | `noteRoot` `340x240` at `(1,-24,1,-200)`, notifications 320x66, **max 3**, 4.5s | Phase D's whole notification budget. |
| `CityJobs.lua:98` | shift strip `330x92` at `(0,24,1,-24)` | Bottom-left. Phase D puts nothing there (thumbstick). |

### The machinery phase D rides on

| Where | Fact | Reused how |
|---|---|---|
| `SminskiServer.server.lua:324-336` | `publicData(s)` is `table.clone(s.data)`, so `data.City` reaches the client on every reply that carries `data` | The meter needs **no new payload**. The pill reads `ctx.data.City.meter` / `.tickets`. |
| `City.lua:2863-2867` | the coin pill already re-reads `ctx.data.Coins` every frame and writes only on change | Exactly the pattern the pill copies, on the existing 0.25s gate instead. |
| `City.lua:1314-1338` | `City.hudVisible` sweeps **direct `Frame` children of `H.root` that are `Visible`**, remembers them, and only the restore clears the record | The pill is a direct `Frame` child of `H.root` and is **`Visible` once latched and never written again** -- so it inherits `City.hudOff` for free and cannot fight the record/restore. |
| `City.lua:2152-2178` | `promptTick` priority: Apts -> Home -> Roads -> Hang -> **`City.Events.prompt` (`:2170`)** -> Jobs -> Kitchen -> Venues -> arcade/depot/dealer -> businesses (`:2212`) -> **MallShops (`:2236`)** -> rides -> claw -> farm | **The hunt's claim prompt already outranks every shop and business door**, which is where the hunt's spots live (`door + 2.5`). Four modules outrank it -- see EDGE CASES / the one real risk. |
| `City.lua:1750-1766` | `setPrompt(title, sub, btn, icon, action, at)` -- exactly **one** button | The Capsule Corner redemption is one branch on the existing prompt. No new widget. |
| `City.lua:2236-2241` | MallShops prompt, `near(me, sh.pos, 14)`, `BROWSE` -> `UI.openShopTab(sh.tab)` | The one branch phase D adds to `City.lua`. |
| `City.lua:418-428` `beacon()`, `CityEvents.lua:325-334` `mark()` | the over-the-rooftops pillar | **The hunt never calls either.** A hidden thing has no beacon; that is the game. |
| `City.lua:869` | TOWN already lists `THE MALL` as a GO row with `City.Way.to` | A second, always-available route to the ticket's home. The pill's tap is a convenience, not the only way. |
| `CityEvents.lua:1380-1389` `E.go`, `CityWayfind.lua:1-8` `W.to(pos, name)` | the green ribbon on the road | Both the hunt's GO and the pill's tap use it. **No new pointer invented.** |
| `CityEvents.lua:65-69` | `notify(icon,title,sub,color)` pushes to `E.news` (6 deep) **then** calls `City.Jobs.notify` | Anything that is a receipt goes through this (survives `hudOff` in CITY NEWS). Anything that is a path confirmation goes through `City.Jobs.notify` **directly**, per `phone-ui/ux.md` §9. |
| `CityEvents.lua:503-533` | `pulse(sc, peak, upT, downT)`, `holdCity/holdMine/skyFlash` | The pill's pulses and the hunt row's 1.2s refusal hold are these functions' shape, verbatim. |
| `CityEvents.lua:536-546` | `applyTraySize()` + the `ViewportSize` connection at `:1373-1374` | Where the compact metrics for the pill and the hunt section are applied. `City.lua`'s `H.layout` is another lane's file and is not hooked. |
| `CityEvents.lua:605-635` | `showBig(ev, txt, col)`: `bigGen` guard, `City.hudOff` early return, 250-stud audience test, pop 0.30 Back / hold 3.40 / fade 0.50 | The third find needs the same object without the event argument. See REQUESTS item 2 (a pure extract-function, no behaviour change to phase B). |
| `CityEvents.lua:564-573` | `goalFanfare`: `BigChime` 1.15/0.7, +0.30s `BigChime` 1.50/0.9, +0.55s `Chime` 1.80/0.45 | The 3/3 moment's sound, guarded on "still in the city" instead of on an event. |
| `CityEvents.lua:1016-1042` `claim()` -> `earned(res, what)` (`City.lua:1770-1782`) | `setData` + `City.popCoins` + `Chime` | The hunt claim reuses `earned()` exactly, so the coin pop and the coin pill update for free. |
| `CityEvents.lua:1441-1500` | `E.step`'s `t - lastUi > 0.25` gate, and `if phone.shade.Visible then E.refreshPhone()` | The pill and the hunt section refresh on this gate. **No new timer, no new `task.spawn`** (`performance.md`). |
| `UI.lua:293` `DisplayOrder = 5` vs `City.lua:490` `DisplayOrder = 4`, and `UI.lua:1212` `capOverlay` is a child of UI's **`root`**, not `hud` | -- | **`UI.playCapsule(res)` renders correctly in the city and draws above the city HUD.** Verified, because `UI.toast`/`UI.banner` do not (`collect-events/ux.md` §WHAT EXISTS) and I had to know which side of that line the capsule reveal falls on. **Phase D needs no new reward UI.** |
| `SminskiRunner.client.lua:766-776` | `ctx.openCapsule`: `UI.playCapsule(res)` then `task.delay(1.6, setData)` | The redemption copies this, so the ticket count drops as the capsule starts shaking. |
| `SminskiServer.server.lua:121-130` | `bump()` only writes challenge progress -- **there is no lifetime `capsules` counter in `data`** | Kills my "teach the meter once per account" idea. See CUT / DEFER. |
| `Art.lua:18-42` | 23 icons | `capsule` for everything in phase D; `crown` for the 7-day streak; `pin` for paths; `hourglass` for the reset warning. **No new art requested.** |

---

## THE DESIGN

### 1. How visible is the meter? -- answered directly

The brief is right that this is the decision. A meter that is always on screen
becomes wallpaper; a meter that is hidden never motivates. The answer is not a
compromise between the two, it is a **split between the object and its motion**:

> **The object is permanent and silent. The motion is rare and caused.**

- The pill is **always on screen in the city**, like the coin pill, in the money
  row, 120x48. It is never a surprise, never animates itself in, never has to be
  found. That is the "motivates" half: you can always see how full it is, and
  you can always see that you hold two tickets.
- The pill is **completely motionless whenever you are not being paid.** The
  loop spec's fill is bursty by construction (`loop.md` D5: credited inside
  `pay()`, 60-250 units at a time, nothing in between, and zero while idle or
  driving). So the pill has no idle animation, no creep, no shimmer, no
  countdown, no pulsing "nearly!" state. Standing still, it is furniture that
  says two true numbers. That is the "not wallpaper" half: nothing about it
  competes for attention until something happened.
- **The exact unit number is never on screen.** `1240 / 1870` is not actionable
  (you cannot spend a partial meter), so it lives one tap away, in the
  notification corner, on demand only.

Two consequences I am committing to:

1. **I do not surface the per-minute ceiling**, per `loop.md` D5. There is no
   "capped" state, colour or message anywhere in this spec.
2. **I do surface the banked cap** (`tickets == 3`), because it is the one state
   where the player is losing something they can act on. One notification, one
   colour change, no modal.

### 2. The capsule pill -- geometry

A `UI.card`, direct child of `H.root`, created once in `E.init(root)`
(`CityEvents.lua:1220`) the way `bigHolder` already is -- so **`City.lua` gains
no HUD code at all**.

```
 1280 canvas, UIScale 1
 x=798        968  976              1096 1106            1256
  ┌────────────────┐ ┌────────────────┐  ┌────────────────┐   y=26
  │ ◉  1,240       │ │ ⬤  2          │  │  ⚙  MENU       │
  │  (coin pill)   │ │    ▓▓▓▓▓░░░░   │  │  (right nav)   │   y=74
  └────────────────┘ └────────────────┘  └────────────────┘
      existing            NEW                existing
```

`UI.card(root, UDim2.fromOffset(120, 48), UDim2.new(1, -184, 0, 26), Vector2.new(1, 0), C.paper)`
-> face x `canvasW-304` .. `canvasW-184`, y 26-74. On 1280: **x 976-1096**.

| Name | Class / kit | Size | Position (in the card face) | Style |
|---|---|---|---|---|
| `CapsulePill` | `UI.card` holder | 120 x 48 | `(1,-184,0,26)`, anchor (1,0) | `C.paper`. `Visible = false` until latched (§7 states). |
| `CapsuleScale` | `UIScale` on the holder | -- | -- | pulses only |
| `CapsuleIcon` | `UI.icon` `capsule` | 32 x 32 | `(8, 8)` | `ZIndex 3`. `ImageTransparency 0` always -- it is the label, not a state. |
| `CapsuleCount` | `UI.text` | 30 x 26 | `(46, 3)` | FredokaOne **22**, `TextXAlignment Left`, `ZIndex 3`. Colour per §7. |
| `CapsuleTrack` | `Frame` + `UICorner 3` | 66 x 6 | `(46, 34)` | `C.paper2`, `BorderSizePixel 0`, `ZIndex 3` |
| `CapsuleFill` | `Frame` + `UICorner 3` | `fromScale(f, 1)` | in the track | `C.mint`; `C.gold` at f >= 0.80; `C.coral` when `tickets >= 3` |
| `CapsuleTap` | `TextButton` | `fromScale(1,1)` | -- | `Text = ""`, `BackgroundTransparency 1`, `ZIndex 6` |

`ZIndex >= 3` on every direct child of the face because `UI.skin` parents its
two 9-slice images at the face's own ZIndex (`phone-ui/ux.md` §4, and
`H.district` at `City.lua:589` for the same reason).

**Compact** (`UI.compact()`, read in `applyTraySize`'s existing `ViewportSize`
connection, `CityEvents.lua:1373-1374`):

| | desktop | compact |
|---|---|---|
| pill | **120 x 48** @ `(1,-184,0,26)` | **120 x 52** @ `(1,-184,0,24)` |
| icon | 32 @ (8, 8) | 34 @ (8, 9) |
| count | FredokaOne 22 @ (46, 3), 30x26 | FredokaOne **24** @ (48, 4), 30x28 |
| track | 66 x 6 @ (46, 34) | 64 x **7** @ (48, 38) |

**The width is 120 on both sizes and cannot grow.** The slot is 138 design px
wide (§WHAT EXISTS); 120 leaves 8px to the coin pill and 10px to MENU. A wider
compact pill would overlap the coin pill -- worked: at 140 wide the left edge
lands at `canvasW-324`, 12px *inside* the coin pill's right edge at
`canvasW-312`. So compact buys legibility with height and type size, not width.
At the 0.6 scale floor the pill is 72 x 31 real pixels and its tap target is the
same 72 x 31 -- below a comfortable thumb target, and **accepted**, because the
tap is a convenience: the guaranteed routes to Capsule Corner are TOWN ->
THE MALL (`City.lua:869`) and the prompt at the machine itself.

### 3. The capsule pill -- every motion, and only these

| Trigger | What happens | Timing |
|---|---|---|
| a credit lands (`meter` grew) | `CapsuleFill.Size` tweens to the new fraction | 0.25s Quad (phase B's fill tween, `collect-events/ux.md` NUMBERS) |
| ...and, coalesced | `pulse(CapsuleScale, 1.06, 0.10, 0.16)` | at most **one pulse per 0.6s**, and **no pulse for a credit < 19 units** (1% of the bar) |
| the fill crosses 0.25 / 0.50 / 0.75 | `pulse(CapsuleScale, 1.10, 0.12, 0.18)` instead | once each per ticket cycle |
| the fill crosses 0.80 | `CapsuleFill.BackgroundColor3 = C.gold` (a state, not an animation) | -- |
| **a ticket completes** | see §4 | ~1.0s total |
| `tickets` reaches 3 | count -> `C.coral`, fill -> `C.coral`, parked at 1869/1870 | -- |
| `City.hudOff` is true | **no tween and no pulse** -- write the final `Size`/`Colour`/`Text` directly | -- |
| nothing happened | **nothing** | -- |

**Why a pulse and not a longer bar.** One credit is 60-250 units = 3.2%-13.4% of
the bar = **2.1 to 8.8 px** on a 66px track. A 60-coin credit moving the bar 2px
is not the "visible notch" `loop.md` D10 asks for. Phase B hit this exact wall
(1 of 40 balloons is 7.7px on a 308px track) and solved it with a pulse on the
label rather than a longer bar. Same answer, same numbers, same reason: **the
motion is what is visible; the bar is what is true.** The 0.6s coalescing and
the 19-unit floor exist because a taxi run lands ~6 credits a minute and six
pulses a minute in the corner of the eye is the point at which a useful signal
becomes a tic.

**Minimum visible fill:** `f = meter > 0 and math.max(0.09, meter / Config.Meter.Ticket) or 0`.
0.09 of 66px = 6px = twice the 3px corner radius, so the first credit of a cycle
is always visible as a shape and not as a rounded smear.

### 4. The moment a ticket completes

This is the whole reward, and it must not take the screen.

| t | What |
|---|---|
| 0.00 | `CapsuleFill` tweens to `fromScale(1,1)` and to `C.gold` -- 0.18s Quad |
| 0.18 | held full |
| 0.30 | `CapsuleFill.Size` **set directly** to the new fraction (never tweened down -- a tween down reads as losing progress), colour back to `C.mint` |
| 0.30 | `CapsuleCount.Text` = the new count, colour -> `C.gold`; `pulse(CapsuleScale, 1.22, 0.10, 0.18)` |
| 0.30 | `Audio.play("BigChime", 1.25, 0.75)` -- the weight class of a FIND claim (`CityEvents.lua:1040`) |
| 0.45 | one notification (§9) |

Total ~1.0 second, entirely inside a 120x48 rectangle in the top-right, plus one
320x66 card in the bottom-right. **No banner, no modal, no full-screen line, no
`City.popCoins`** -- a ticket is not coins and must not be drawn as coins.

If `City.hudOff` is true at that instant: skip all of it. The state is written
directly, so when the HUD comes back the pill is simply correct -- there is no
stale animation, because the pill renders from `ctx.data`, not from animation
state. The notification still goes through `notify()`, so the receipt is waiting
in the phone's CITY NEWS (phase B's rule, `collect-events/ux.md` §4).

### 5. Holding a ticket: how you know, how many, and where it is spent

Three channels, in the order a player meets them:

1. **How many:** the number on the pill. It is the ticket count and nothing else
   -- `0`, `1`, `2`, `3`, and **`4`** (the Daily 3 can push `c.tickets` to 4 past
   the banked cap; `loop.md` D5's invariant. The label must not clamp).
2. **Where:** the **first** ticket's notification says it in words, and it is
   the only teaching this feature does:
   `("capsule", "CAPSULE TICKET", "use it at Capsule Corner, in the mall", C.lav)`.
   It lands the moment the ticket does, which is the only moment the sentence is
   interesting.
3. **How to get there:** **tap the pill.** With `tickets >= 1` it lays the
   existing green ribbon -- `City.Way.to(Places.MallShops[2].pos, "Capsule Corner")`
   -- and confirms with `City.Jobs.notify("pin", "PATH SET", "Capsule Corner, in the mall", C.mintDark)`
   (direct, so a path confirmation does not pollute CITY NEWS). No new pointer,
   no new marker, no map pin: the green-dot path is what the whole city already
   uses for "go here", including the TOWN screen's own THE MALL row.

   With `tickets == 0` the same tap is still useful rather than dead:
   `City.Jobs.notify("capsule", "CAPSULE METER", "1240 of 1870 \u{00B7} full = a free capsule", C.lav)`.
   That is where the exact number lives, and it is the only place it appears.

**At the machine** (`Places.lua:119`, `V(536,0,168)`, `near(..., 14)`,
`City.lua:2236-2241`). `setPrompt` has exactly one button, so:

| `tickets` | title | sub | button | icon |
|---|---|---|---|---|
| 0 | `CAPSULE CORNER` | `the same shop as back home` | `BROWSE` | `bag` |
| 1 | `CAPSULE CORNER` | `1 capsule ticket ready \u{00B7} one free capsule` | `USE TICKET` | `capsule` |
| 2-4 | `CAPSULE CORNER` | `3 capsule tickets ready \u{00B7} one tap each` | `USE TICKET` | `capsule` |

The button label stays `USE TICKET` at every count: `H.pBtn` is 160 wide at
FredokaOne 20, and `USE TICKET (3)` is ~140px of glyphs in it. The count belongs
in the sub, which is 200px of room at 13pt. BROWSE is not lost -- it is the SHOP
button in the left column (`City.lua:568`), and it returns the moment the last
ticket is spent, because `promptTick` re-renders every frame. That is the whole
one-button constraint discharged with one branch.

Redemption reply -> `UI.playCapsule(res)` then `task.delay(1.6, function() ctx.setData(res.data) end)`,
copying `ctx.openCapsule` (`SminskiRunner.client.lua:766-776`). The count on the
pill therefore drops as the capsule starts shaking, which is when the ticket is
actually gone. **Zero new reward UI.**

### 6. The Daily 3 -- the phone section

**I claim `LayoutOrder` 50**, the slot `phone-ui/ux.md` §6 reserved for phase D.
I do not touch 20 or 40 (phase C) or 60 (phase G).

**And I ask for one integer from the phone's owner: `PhoneSecNews` from 30 to 70.**
Worked, because it decides whether the feature is above the fold:

| feed contents (desktop, 438px viewport, 12px between sections, T8/B10 padding) | hunt occupies | visible? |
|---|---|---|
| NOW IN TOWN (0 events, 108) + CITY NEWS **at 30** (112) + HUNT at 50 (272) | y 240-512 | **74px below the fold** |
| NOW IN TOWN (108) + HUNT at 50 (272) + CITY NEWS **at 70** (112) | y 128-400 | **fully visible, 38px spare** |

CITY NEWS is history; the hunt is a standing objective that a returning player
opens the phone specifically to read. The phone spec's own principle
("live-and-urgent first, standings and history after") puts news last; 30 was
chosen when news was the only other section. This is one `LayoutOrder` on a
section that is already being built, and it is the difference between a
day-long feature you see and one you have to scroll for. **If the owner says
no, phase D still ships at 50** -- the feed scrolls and the scrollbar says so.

```
PhoneSecHunt   LayoutOrder 50   Size (1,0,0,0)  AutomaticSize = Y
 +- UIListLayout  Padding 8, SortOrder = LayoutOrder
 +- HuntHeader    260x20  "TODAY'S HUNT"   FredokaOne 15  C.inkSoft  left   order 1
 +- HuntCount      54x20  "1 / 3"          FredokaOne 15  right, anchor (1,0), same band
 +- HuntRow1..3   314x52  order 2,3,4
 +- HuntReset     314x16  "new ones in 6h 12m"                        order 5
 +- HuntSocial    314x16  "others have found 2 today ..."             order 6 (hides itself)
 +- HuntStreak    314x16  "3-day streak ..."                          order 7
```

Child width 314 (the feed's `UIPadding L10 R20` inside 344, `phone-ui/ux.md` §6).
`HuntCount` shares `HuntHeader`'s 20px band as a second label in the same
section, right-anchored -- **not** a second list row, so it costs 0 height.
Section height: **248 with `HuntSocial` hidden, 272 with it shown** (desktop);
**260 / 284** compact.

**A row** (`C.paper2`, `UICorner 14` -- the event rows' own treatment):

| Name | desktop | compact |
|---|---|---|
| row frame | **314 x 52** | **314 x 56** |
| `HuntBadge` `Frame` + `UICorner 11` | 30x30 @ (8, 11) | 32x32 @ (8, 12) |
| `HuntBadgeIcon` `UI.icon capsule` | 24x24 @ (3, 3) in the badge | 26x26 @ (3, 3) |
| `HuntClue` `UI.text`, wrapped, 2 lines, `TextYAlignment Center`, `TextTruncate AtEnd` | **174 x 34** @ (46, 9), GothamMedium **12** | **166 x 36** @ (48, 10), GothamMedium **13** |
| `HuntGo` `UI.button` `C.mint`, no icon | **76 x 36** @ `(1,-10,0.5,0)` anchor (1,0.5) = x 228-304, y 8-44 | **84 x 44** @ same = x 220-304, y 6-50 |
| `HuntTap` `TextButton`, `Text=""`, **`ZIndex = 0`** | `fromScale(1,1)` | same |

`HuntTap` at ZIndex 0 sits under `HuntGo`'s holder so GO keeps its own clicks,
and under the labels, which do not consume input. Same construction as the event
rows' `r.tap` (`phone-ui/ux.md` §7).

Worked clearances:
- clue ends x 220 desktop / 214 compact; GO starts x 228 / 220 -> **8px / 6px**.
- **Longest tier-3 clue** (`loop.md` D7: compass + landmark + street + thing),
  `south-west of the School, on Sycamore Ave, by the CORNER STORE` = 62 chars at
  GothamMedium 12 ~= 390px over 174 = **2.24 lines -> the tail ellipsizes.**
  Accepted for tier 3 (it is the "you already know where it is, GO is enabled"
  tier). **Tier 2 must never truncate** and does not: the longest tier-2 string,
  `on Sycamore Ave, by the CORNER STORE` = 36 chars ~= 227px over 174 = 1.31
  lines. That matters because `loop.md`'s REQUESTS calls tier 2 "the shareable
  string" -- it is what a player types into chat, and a chat message with an
  ellipsis in it is useless.
- Compact uses `clueShort` (§11, <= 44 chars) so a 44-char string is 299px over
  166 = 1.80 lines. No truncation on the small screen at all.

### 7. Every state

**The pill**

| State | Count | Fill | Notes |
|---|---|---|---|
| `ctx.data.City.meter` is not a number yet (first second in the city, or an old server) | -- | -- | `CapsulePill.Visible = false`. **Never print a 0 you cannot vouch for.** Latches to `true` on the first tick where it is a number, and `Visible` is **never written again** -- see the `hudVisible` record/restore hazard in WHAT EXISTS. |
| fresh account: meter 0, tickets 0 | `0`, `C.inkSoft` | `fromScale(0,1)` | the quiet resting state; zero motion |
| meter 1..1495, tickets 0 | `0`, `C.inkSoft` | `C.mint`, `max(0.09, m/1870)` | |
| meter >= 1496 (80%) | `0`, `C.inkSoft` | **`C.gold`** | the only "nearly" signal. No text, no notification, no pulse of its own. |
| tickets 1-2 | `1`/`2`, **`C.gold`** | as above | |
| tickets 3 (banked cap) | `3`, **`C.coral`** | `C.coral` at 0.999 | one notification, once (§9) |
| tickets 4 (3 banked + the hunt's) | `4`, `C.coral` | `C.coral` at 0.999 | **do not clamp the label** |
| `meterDayTickets >= Config.Meter.DayCap` | as the count is | `C.inkSoft` at 0.999 | no notification. Tap says `all earned today \u{00B7} back tomorrow`. |
| `City.hudOff` | swept with the HUD | | no tween, no pulse; state written directly |
| leaving the city (`E.leave()`) | -- | -- | `Visible = false`, latch cleared, so a return trip re-latches from fresh data |

**The hunt section**

| State | What it shows |
|---|---|
| the `state` reply has no `hunt` block (old server, or a server with the hunt disabled) | `PhoneSecHunt.Visible = false`. The feed reflows; nothing empty is left behind. |
| not synced yet / 3 failed syncs | section hidden. NOW IN TOWN already says `checking what's on...` / `can't reach the city right now.` (`phone-ui/ux.md` §9) -- one loading state per screen, not three. |
| 0 / 3, nobody has found anything | `0 / 3`; three paper2 badges; three tier-1 clues; no GO |
| a spot others have found, you have not | that row's badge **`C.sky`**, icon transparency 0.25 (from 0.55) | 
| a spot you have found | badge **`C.mint`**, icon opaque, clue `found \u{00B7} <clueShort>` in `C.inkSoft`, **no GO**, tap = dull `Audio.play("Click", 0.6, 0.5)` and nothing else |
| a tier-3 spot | GO shown and enabled |
| a tier-1/2 spot, tapped | the row holds `not close enough yet -- follow the clue` in `C.coral` for **1.2s** then reverts. Same `holdText/holdColor/holdUntil` idiom as the event rows and the tray. **The phone stays open** -- a refusal must not close the thing you are reading. |
| 3 / 3 | `3 / 3` in `C.mintDark`; three mint badges; three `found \u{00B7} ...` clues; no GO anywhere |
| "you already did this" | is exactly the 3/3 row above. There is no second claim, and no error copy is needed for one. |
| under 30 minutes to the reset | `HuntReset` -> `C.coral` |
| `hunt.ends` in the past (a clock skew, or the boundary arriving before the broadcast) | `HuntReset` reads `new ones any moment now` in `C.coral`. Never a negative clock. |

### 8. The Daily 3 -- the flow, from learning it exists to the third find

1. **Learning it exists.** No tutorial, no popup. Two places, both passive:
   - the phone's `TODAY'S HUNT 0 / 3` section, which is above CITY NEWS and
     therefore the second thing on the phone after what is live;
   - the first time anyone on the server finds one, the CITY NEWS line and (if
     it changed your tier) one `CLUE GOT WARMER` notification.
   A player who never opens the phone will still meet a hunt Sminski by walking
   into one, and the prompt card explains it in seven words.
2. **Searching.** Tier-1 clue = a district. No beacon (`mark()` is never
   called). At tier 3, GO lays the ribbon to `lot.door`, never to `pos`
   (`loop.md` D7), so the last 11 studs are still yours to find. Inside
   `Hunt.Reveal` (90) the model appears -- later and closer than a sighting's
   130, which is what makes it read as hidden rather than parked.
3. **The prompt.** `E.prompt` gains a hunt branch (it already outranks every
   shop and business door, `City.lua:2170`):

   | Case | title | sub | button | icon |
   |---|---|---|---|---|
   | your 1st or 2nd | `HIDING SMINSKI` | `one of today's three \u{00B7} say hello?` | `SAY HI` | `capsule` |
   | your 3rd | `HIDING SMINSKI` | `the last of today's three \u{00B7} say hello?` | `SAY HI` | `capsule` |

   `SAY HI` matches phase A's own words for a sighting claim ("you said hi!",
   `CityEvents.lua:1029`), which is correct: it is the same verb for the same
   gesture, and the two are separated by the title, the icon, the 0.5 scale and
   the plain skin (`loop.md` D9) -- not by inventing a third verb.
4. **Find 1 and 2.** `earned(res, ...)` -> the coin pop and the coin pill, free.
   `Audio.play("BigChime", 1.25, 0.8)` (FIND's finale). The row's badge flips to
   mint. **One** notification, carrying both facts so the clue-tightening is
   felt rather than inferred:

   | | |
   |---|---|
   | 1st | `("capsule", "FOUND 1 OF 3", "the other clues just got warmer", C.mint)` |
   | 1st, and first on this server today | `("capsule", "FOUND 1 OF 3", "first here today \u{00B7} the other clues got warmer", C.mint)` |
   | 2nd | `("capsule", "FOUND 2 OF 3", "one to go \u{00B7} that clue is as good as it gets", C.mint)` |

   The model stays 3 seconds and is removed, exactly as a claimed FIND is
   (`CityEvents.lua:1462`), and `E.prompt` stops returning it immediately.
5. **The third find.** The one moment in phase D that is allowed to be loud, and
   it is loud for 4.2 seconds in a 620x48 strip that never covers the city
   centre:

   | t | What |
   |---|---|
   | 0.00 | `earned()` pays; `City.popCoins(150 x multipliers)` -- the existing path |
   | 0.00 | the *meter* also moves (Hunt is on the whitelist, `loop.md` N1): fill tween + pulse, §3 |
   | 0.10 | `bigHolder`: **`ALL THREE FOUND!`** in **`C.gold`**, pop 0.6->1 over 0.30s Back |
   | 0.10 | the 3-note ta-da: `BigChime` 1.15/0.7, +0.30s `BigChime` 1.50/0.9, +0.55s `Chime` 1.80/0.45 |
   | 0.60 | the **ticket pip**: `CapsuleCount` increments with `pulse(CapsuleScale, 1.22, 0.10, 0.18)` and the pill flashes `C.lav` for 0.50s. **The fill does not run to full and wipe** -- this ticket did not come from the meter, and animating the meter would be a lie. Two sources, two animations, one pill. |
   | 0.80 | one notification (§9) |
   | 3.80 | fade `bigText.TextTransparency` **and** the `UIStroke.Transparency` 0->1 over 0.50s (`CityEvents.lua:626-629` -- fading one leaves the outline hanging) |
   | 4.30 | `bigHolder.Visible = false` |

   On a 7-day-streak day the big line is **`SEVEN DAYS RUNNING!`** instead (one
   line, never two), the pip happens twice 0.25s apart, and the notification
   merges (§9). `City.hudOff` -> no big line, no coin pop; the notification still
   files the receipt in CITY NEWS.
6. **Getting out.** Nothing in phase D is modal and nothing traps: walk away
   from a prompt, tap the phone's home bar / shade / GO, or open MENU
   (`City.hudOff` hides the pill, the strip, the tray, the notifications and the
   prompt, and closes the phone). The hunt Sminski models are **world** objects
   and `City.hudOff` must *not* remove them -- hiding the world because a menu
   opened would be wrong.

### 9. Every notification, final -- and the budget

`via notify()` = also written to CITY NEWS (a receipt). `direct` =
`City.Jobs.notify` only (a confirmation, not news).

| # | When | Call | Route |
|---|---|---|---|
| 1 | a meter ticket lands | `("capsule", "CAPSULE TICKET", "use it at Capsule Corner, in the mall", C.lav)` | notify() |
| 2 | the grant that reaches 3 banked (**replaces #1** that time) | `("capsule", "3 CAPSULE TICKETS", "the meter stops here -- spend one at Capsule Corner", C.coral)` | notify() |
| 3 | your 1st / 2nd hunt find | §8 step 4, three variants | notify() |
| 4 | your 3rd hunt find | `("capsule", "ALL THREE FOUND", "a capsule ticket \u{00B7} use it at Capsule Corner", C.gold)` | notify() |
| 5 | your 3rd find on a 7-day-streak day (**replaces #4**) | `("crown", "ALL THREE FOUND", "7-day streak \u{00B7} two tickets today", C.gold)` | notify() |
| 6 | someone else's find **that changed your tier** | `("capsule", "CLUE GOT WARMER", "Ari found the Downtown one", C.sky)` | notify() |
| 7 | the UTC day rolls over, you were 3/3 | `("capsule", "NEW HUNT TODAY", "three new hiding places \u{00B7} 0 of 3", C.lav)` | notify() |
| 8 | the UTC day rolls over, you were 1/3 or 2/3 | `("capsule", "NEW HUNT TODAY", "yesterday's three are gone \u{00B7} 0 of 3 again", C.lav)` | notify() |
| 9 | 5 minutes to the reset, spots still unfound, once per day | `("hourglass", "HUNT RESETS SOON", "new hiding places in 5 minutes", C.coral)` | notify() |
| 10 | pill tap, `tickets >= 1` | `("pin", "PATH SET", "Capsule Corner, in the mall", C.mintDark)` | direct |
| 11 | pill tap, `tickets == 0` | `("capsule", "CAPSULE METER", "1240 of 1870 \u{00B7} full = a free capsule", C.lav)` | direct |
| 11b | pill tap at the day cap | `("capsule", "CAPSULE METER", "all earned today \u{00B7} back tomorrow", C.lav)` | direct |
| 12 | GO on a hunt row | `("pin", "PATH SET", "follow the green dots", C.mintDark)` | direct |

Every `sub` above is <= 39 characters, which is what fits the notification's
254px sub slot at GothamMedium 13 (`CityJobs.lua:66-68`) with
`TextTruncate.AtEnd` as the backstop. That constraint is why #6 became a
two-word title plus a name rather than one long sentence.

**Budget.** Phase D's own worst realistic minute is **3**: a ticket + your own
find + somebody else's find. That is exactly the stack (`CityJobs.lua:51`). It
shares the stack with phases A and B, so in a genuinely busy minute a card gets
evicted -- and the one that must never be lost, the ticket, is the one that
`notify()` also files in CITY NEWS. #6 is naturally capped at **6 per day**
(`min(hereFound, 2)` means only the first two finds of each spot change
anything) and only fires when your own tier actually moved.

### 10. Both screen sizes -- the overlap arithmetic, worked

Canvas = `viewport / UIScale`, `UIScale = clamp(min(vx/1280, vy/760), floor, 1.25)`,
floor 0.45 desktop / 0.6 touch (`City.lua:516`). Everything phase D adds to the
HUD is **one 120x48 rectangle in the top-right**, right-anchored, so the only
question is what shares that band.

**Desktop, 1280 x 760, UIScale 1.** `CapsulePill` = x **976-1096**, y **26-74**
(its `UI.card` shadow -- `(1,-8,1,0)` at (4,7), `UI.lua:143` -- reaches x 980-1092,
y 33-81).

| Element | Occupies | Result |
|---|---|---|
| coin pill | x 798-968, y 26-74 | **clear by 8px** -- the tightest gap in the spec, and the reason the pill is 120 and not 140 |
| right nav MENU | x 1106-1256, y 22-78 | **clear by 10px** |
| right nav HOME / MAP / HELP | x 1106-1256, y 86-270 | clear (x) |
| district pill | x 480-800, y 18-82 | clear by 176 |
| boost banner | x 470-810, y 92-146 | clear (x **and** y) |
| event strip | x 470-810, y 152-202 | clear -- **phase B untouched** |
| **progress tray (phase B, y 202-248)** | x 470-810 | clear. Phase D asks for **nothing** in the top-centre column. |
| `bigHolder` (shared) | x 330-950, y 256-304 | clear by 26px in x, 175 in y |
| `H.raceText` | x 340-940, y 96-146 | clear |
| notifications `noteRoot` | x 916-1256, y 320-560 | pill's shadow ends y 81 -> **clear by 239** |
| driving buttons | x 926-1256, y 586-736 | clear |
| CITY JOBS card | x 24-324, y 284-574 | clear |
| the new phone shell | x 24-400, y 144-736 | clear |
| shift strip | x 24-354, y 644-736 | clear |
| prompt card | x 405-875, y 602-706 | clear |

**Compact.** The pill is right-anchored, so it is `x = W-304 .. W-184` on every
canvas width. The three compact canvases named in `collect-events/ux.md` §7 and
`phone-ui/ux.md` §8:

| canvas | pill | coin pill right edge | MENU left edge | verdict |
|---|---|---|---|---|
| 1333 x 530 | x 1029-1149, y 24-76 | 1021 | 1159 | 8 / 10 ✓ |
| 1280 x 592 | x 976-1096 | 968 | 1106 | 8 / 10 ✓ |
| 1112 x 625 | x 808-928 | 800 | 938 | 8 / 10 ✓ |

The compact elements that could reach the pill's band, worked:

- **compact district pill** (240x44 at y 12-56, centred): x 546-786 at W1333,
  x 436-676 at W1112, x 520-760 at W1280. Pill starts at W-304 = 1029 / 808 /
  976. **Clear on all three.**
- **compact boost banner** (340x54, y 92-146, centred): x 386-726 at W1112.
  Pill ends y 76. Clear in both axes.
- **compact driving buttons** (`drive` 330x150 at `(1,-24,1,-196)`): at W1112 x
  758-1088, which *does* share x with the pill's 808-928 -- but y is H-346..H-196
  = 184-334 at H530. Pill ends y 76 (shadow 83). **Clear by 101.**
- **compact `noteRoot`** (340x240 at `(1,-24,1,-200)`): at H530 the frame is y
  90-330, and the pill's shadow ends at y 83 -- 7px. But notifications fill from
  the frame's *bottom* (`Position (1,0,1,-(i-1)*74)`, anchor (1,1),
  `CityJobs.lua:46`), so the topmost of three cards starts at y 330-148-66 =
  **y 116 -> 33px of real clearance.** Worked, not assumed.
- **compact phone shell** (376x480 at x 24-400): clear of x >= 808.
- **thumbstick:** bottom-left. Phase D puts nothing below y 76 on the HUD and
  nothing on the left at all.

**One pre-existing overlap I found and am not fixing.** At canvasW 1112 (an
SE-class phone where the 0.6 scale floor binds rather than the width ratio), the
compact district pill spans x 436-676 and the coin pill spans x 630-800 -- a
**46 x 30 px overlap** in the shipped HUD, independent of phase D. The pill sits
further right and is unaffected. Reported under REQUESTS because it belongs to
`City.lua`'s owner, and because the phone spec's "the canvas is never narrower
than 1280" is only true when the width ratio binds.

**The phone feed, both sizes** (§6): desktop the hunt section is 248-272 tall and
lands y 128-400 of a 438px viewport with 0 events live -- fully visible. With one
live event it lands y 210-482 and the last ~44px (the streak line) is below the
fold; the 4px scrollbar is the indicator, which is correct for a phone. Compact
(260-284 tall in a 324px viewport) scrolls as soon as anything else is in the
feed. Accepted: `phone-ui/ux.md` §10 already ships a feed that scrolls at 2-3
events, and the row that matters most (the unfound one with GO) is never the
last row for long.

### 11. What the client must receive from the server

Field names are exact; this becomes contract lines. **No new remote, no new
payload for the meter.** Anything absent must degrade to "pill hidden" or
"section hidden" -- never to a printed zero.

**A. The meter -- nothing new.** `publicData(s)` clones `s.data`
(`SminskiServer.server.lua:331`), so every reply that already carries `data`
carries `data.City`. The pill reads, on the existing 0.25s gate:

```
ctx.data.City.meter            -- integer 0 .. Config.Meter.Ticket - 1
ctx.data.City.tickets          -- integer 0 .. 4   (4 is legal: loop.md D5)
ctx.data.City.meterDayTickets  -- integer; only used to pick the day-cap tap text
```

`Config.Meter.Ticket` is read straight from shared `Config`; the fraction is
never sent.

**B. One push, because one payout can be invisible to the client.** A ticket may
be granted on a deferred or server-initiated payout whose reply the client never
sees. So:

```
CityEvent("ticket", { tickets = 2, meter = 140, from = "meter" | "hunt" | "streak" })
```

Fired to the granted player at the moment of the grant. `from` picks the
animation (§4 vs §8's pip). The client must treat this as authoritative over
`ctx.data` until the next `data` arrives.

**C. The hunt block, on the existing `Events:InvokeServer("state")` reply:**

```
hunt = {
  day    = "2026-09-21",
  ends   = 1758499200,          -- UNIX seconds, UTC midnight. The client formats it.
  found  = { true, false, false },   -- DENSE 3-element boolean array. See below.
  streak = 3,                   -- consecutive UTC days completed 3/3
  full   = false,               -- 3/3 today
  spots  = {                    -- exactly 3, index-stable for the whole day
    { tier      = 2,            -- 1..3, computed server-side per player
      clue      = "on Birch Ave, by the FLORIST",
      clueShort = "on Birch Ave, by the FLORIST",   -- optional, <= 44 chars, compact only
      here      = 1,            -- how many players on THIS server found it today
      go        = nil },        -- { x = 412, z = -88 } (lot.door) ONLY when tier == 3
    ...
  },
}
```

> **`found` must be a dense 3-element array, never the sparse
> `{ [1] = true, [3] = true }` of `loop.md` N3.** A sparse Lua table
> round-trips through DataStore JSON as a **dictionary with string keys**, so
> after a rejoin the client would read `found["1"]` and show `0 / 3` to a player
> who had found two. Normalise on the way out, in one place, or every consumer
> pays for it forever.

**D. Per-player clue push, whenever anything in C changes for that player:**

```
CityEvent("huntClues", { ends, found, streak, full, spots })   -- the same shape as C.hunt
```

Fires on your own find and on the **first two** finds of each spot by anyone
else -- at most 9 sends per player per UTC day. This is why the client never
recomputes a tier itself: the tier number is derivable, the *sentence* is not,
and **sending tier-3 text before it is earned hands a modded client the answer.**

**E. Social broadcast, text only, no coordinates:**

```
CityEvent("huntFound", { i = 1, who = "Ari", where = "the Downtown one", first = true })
```

`where` is a short place phrase (<= 22 chars) so that
`"Ari found " .. where` fits the notification's 39-character sub.

**F. Reveal / hide, on their own kinds:**

```
CityEvent("huntReveal", { i = 2, spot = { x, z, face } })
CityEvent("huntHide",   { i = 2 })            -- optional; the client also drops it on claim/reset
```

**These must not reuse `"reveal"`.** `onReveal` (`CityEvents.lua:888-897`)
fabricates a whole `sighting` event for an unknown uid, so a hunt reveal on that
kind would invent a phantom event in `E.list`, the phone and the strip.

**G. The claim:**

```
Events:InvokeServer("huntClaim", i)
  -> { ok, reason,
       coins, xp, first,          -- first finder of this spot on this server today
       found  = { true, ... },    -- dense, mine, after the claim
       mine   = 1,                -- how many I have found today, 1..3
       ticket = true | nil,       -- a capsule ticket was granted by this claim
       tickets = 1,               -- my banked count after it
       streak  = 4,               -- after it
       streakTicket = true | nil, -- the 7-day streak's extra ticket landed
       spots  = { ... },          -- refreshed clue set (same shape as C)
       data, city }               -- so earned(res, what) works untouched
```

`reason` strings, lower case, shown in the row's 1.2s coral hold:
`too far away` · `already found today` · `it's a new day -- look again`.

**H. Reset broadcast:**

```
CityEvent("huntReset", { ends, spots, found = { false, false, false }, streak })
```

**I. Redemption** -- `City:InvokeServer("capsuleTicket")` returns `rollCapsule`'s
own table plus `tickets` and `meter` (`loop.md` D5), so `UI.playCapsule(res)`
plays unchanged.

**J. What must respect `City.hudOff`:**

| Thing | How |
|---|---|
| `CapsulePill` | a direct `Frame` child of `H.root`, `Visible` latched once -> swept by `City.hudVisible`. **Nothing new to wire.** |
| the pill's tweens and pulses | explicit `if City.hudOff then write the end state directly` |
| `bigHolder` (3/3) | the existing `City.hudOff` early return in `showBig` must survive the extract-function in REQUESTS 2 |
| `City.popCoins` on a hunt claim | already guarded in phase B's pattern; keep it |
| the notification stack | `noteRoot` is a `Frame` child of `H.root` -> swept |
| the phone section | inside the phone, which the phone spec closes on `City.hudOff` every frame |
| the hunt Sminski **models** | **must NOT respect it.** They are world objects; a menu must not delete the city. |

---

## NUMBERS

| Tunable | Value | Reasoning |
|---|---|---|
| pill width | **120** | the free slot is 138 (`canvasW-312` .. `canvasW-174`); 120 leaves 8px to the coin pill and 10px to MENU. 140 would overlap the coin pill by 12px -- worked. |
| pill height | 48 / **52** compact | 48 matches the coin pill exactly, which is what makes them read as a pair. Compact gains 4 for the bigger type; 52 from y24 ends at 76, 16px clear of the boost banner at 92. |
| pill x anchor | `(1, -184)` | 184 = 174 (nav column) + 10 gap. Right-anchored so it is identical on every canvas width. |
| track | 66x6 / 64x7, corner 3 | the widest bar the 120px pill can hold with an icon and a number; 6px is the shift strip's bar language (8px at 330 wide) scaled down |
| minimum visible fill | `max(0.09, m/1870)` | 0.09 x 66 = 6px = 2x the corner radius, so the first credit of a cycle is a shape and not a smear. Phase B's 0.035 on a 308px track is the same rule at a different width. |
| fill tween | 0.25s Quad | phase B's number, for the same reason: fast enough to feel caused, slow enough to see when it was not you |
| credit pulse | 1.06, 0.10 up / 0.16 down Back | smaller than phase B's 1.18 because this fires up to 6x a minute, not once per event |
| pulse coalescing | **1 per 0.60s**, and none below **19 units** | 19 = 1% of the bar. Six pulses a minute in peripheral vision stops being a signal. |
| notch pulse | 1.10 at 0.25 / 0.50 / 0.75 | three per cycle; the same "the whole widget, so it reads as the bar" trick as the tray's milestones |
| ticket moment | 0.18 fill up / 0.12 hold / direct reset / 1.22 pip | ~1.0s. The reset is **not** tweened: a bar running backwards reads as loss. |
| 80% colour step | `C.gold` | gold = "nearly there" in phase B's tray too; consistency beats novelty |
| 3-banked colour | `C.coral` | coral is the HUD's only urgency colour, and 3 banked is the only actionable cap |
| ticket sound | `BigChime` 1.25 / 0.75 | FIND's claim finale (`CityEvents.lua:1040`). A 400-coin gift is that weight class. Every ~10 min, so not more than that. |
| hunt row height | 52 / **56** compact | the smallest that gives a 2-line 12pt clue (34) and a 36-high GO 8px of air inside a 314-wide row |
| hunt clue width | 174 / 166 | 314 - badge block (46/48) - GO (76/84) - inset (10) - gap (8/6) |
| hunt clue lines | 2 | tier 2 (the shareable string, <= 36 chars) is 1.31 lines; a 3rd line would cost 17px per row to save an ellipsis on tier 3 only |
| `clueShort` limit | **44 chars** | 44 x 6.8px at GothamMedium 13 = 299px over 166 = 1.80 lines, so compact never truncates at all |
| GO | 76x36 / 84x44 | 36 design px is a mouse target; compact needs 44 (26 real px at the 0.6 floor). Text-only: an unlabelled icon button is a new affordance and this kit labels everything. |
| section list padding | 8 | the phone spec's within-section padding; 12 is between sections |
| section height | 248-272 / 260-284 | lands y 128-400 in a 438 viewport with 0 events -- above the fold, which is the whole reason for the `LayoutOrder` request |
| big line | `ALL THREE FOUND!` at FredokaOne 34/26 in `bigHolder` | zero new instances; 16 chars is 320px in a 620px box, 19 chars (the streak line) is 380px |
| big line audience | **you only** | unlike phase B's city goal, this is a personal achievement; a bystander gets nothing, not even a notification |
| big line timing | pop 0.30 Back, hold 3.40, fade 0.50 | 4.2s, phase B's timing, same object |
| reset warning | **5 minutes**, once per UTC day | long enough to sprint to a tier-3 spot (76-115 studs/s by car, `loop.md` N6), short enough not to nag |
| reset urgency colour | `C.coral` under **30 min** | `loop.md`'s EDGE CASES asks for exactly this threshold |
| streak target | **7 days** | the human's decision; the counter and its payoff are both on `HuntStreak` |
| notification sub limit | **39 chars** | 254px at GothamMedium 13 in a 320x66 card |

---

## EDGE CASES

| Case | What the UI does |
|---|---|
| **Empty server** | The hunt exists (the spots are a pure function of the date). `here` is 0 on all three, so `HuntSocial` hides itself and every badge stays paper2. The pill is per-player and indifferent. Nothing in phase D has a `minPlayers`, so nothing says "waiting for players". |
| **One player** | Tiers advance on your own finds only: 0 found -> tier 1, 1 -> tier 2, 2 -> tier 3. So the last spot is always tier 3 with GO enabled -- solo is slower, never blocked, and never shows a dead GO. |
| **A scripted player** | Nothing in the UI changes. The pill's ceiling state is deliberately invisible (`loop.md` D5), so a script learns nothing from the HUD. `go` is absent below tier 3, so a client reading the remotes gets a street name, not a coordinate. |
| **An AFK player** | The pill is motionless. That is the design, not a bug: allowance accrues, units do not. |
| **Mid-hunt join** | The `state` reply's `found`/`spots` are per-player, so the first refresh is the truth. Joining a server where two players already found spot 2 shows tier 3 and an enabled GO on arrival -- **the badge is `C.sky` before you have done anything**, which is the clearest possible statement that other players made this easier. |
| **Mid-hunt leave** | `c.hunt.found` is saved, so the section resumes on any server. |
| **Day rollover while you are 2/3** | `huntReset` -> `HuntCount` `0 / 3`, three paper2 badges, three tier-1 clues, `HuntReset` recomputed, `HuntStreak` recomputed, and notification #8 which says plainly that yesterday's three are gone. **No big line and no fanfare** -- phase B's rule that a loss is not celebrated in 34pt. |
| **Day rollover while the phone is open** | The 0.25s refresh rewrites the section in place; `UIListLayout` reflows. No hole, no stale row. |
| **Day rollover while you are standing next to an unfound one** | The model is removed by the server's redraw; `E.prompt` stops returning it, so the prompt card clears on the next frame. No sound, no message beyond #8 -- a thing you never found vanishing is not an event. |
| **A claim landing exactly at the boundary** | The server pays against the key it computed; the client just renders the reply. If it is refused, the row holds `it's a new day -- look again` for 1.2s. |
| **Server restart mid-day** | Same three spots; `here` resets to 0, so badges drop from sky back to paper2 and tiers fall back to your own progress. **The UI must not treat a tier going down as an error** -- it re-renders quietly, no notification, no flash. Stated because a "your clue got colder" message would be the obvious wrong instinct. |
| **`tickets` reaches 4** | The label reads `4`. Do not clamp, do not `math.min(3, n)`. |
| **`DayCap` reached** | The fill parks at 0.999 in `C.inkSoft` and stops. No notification. The tap explains it. The hunt's ticket still lands and still animates. |
| **Redeeming with the mall streamed out** | The server's existing "you're not in the city" guard refuses it; the refusal goes to the prompt's own channel. QA must teleport and wait ~3s before measuring anything near the mall (`HANDOFF.md` §2). |
| **Two `USE TICKET` taps racing on one ticket** | Exactly one `ok`. The loser's reply has `reason = "no capsule tickets yet"`; the prompt is already re-rendering every frame, so it has become `BROWSE` by then and the refusal needs no copy of its own. |
| **A capsule reveal while the city HUD is up** | `UI.gui` is `DisplayOrder 5` and City's is 4 (`UI.lua:293`, `City.lua:490`), and `capOverlay` is in UI's `root`, not the dead `hud` frame. So the reveal draws over the HUD correctly. This is the one thing in phase D I could not reason about from first principles and had to verify; it is also QA item 8. |
| **3/3 while a collect event's `WE DID IT!` is on screen** | Same `bigHolder`. `bigGen` makes it last-writer-wins with no stacking and no orphaned fade. The hunt line wins if it fires second, which is right: it is the one you caused. Accepted. |
| **A 20-character display name in #6** | `clampName` (`CityEvents.lua:51`) gives 10 chars + ellipsis, plus `TextTruncate.AtEnd` on the notification sub. |
| **`hunt.spots` has fewer than 3 entries** | Hide the missing rows, keep the header honest (`0 / 2` is wrong, so the count reads `0 / 3` only when there are 3 spots; otherwise hide the whole section). Never render an empty row. |
| **A hunt spot on a lot whose prompt outranks `E.prompt`** | The real risk, and it is a server-side exclusion, not a UI problem -- see REQUESTS 4. `City.Apts`, `CityHome`, `City.Roads` and `City.Hang` all run **before** `City.Events.prompt` at `City.lua:2156-2170`, so a spot on a hangout or a station lot would be **unclaimable**. Businesses, mall shops, the claw, the farm and the depot all run *after* it and are safe. |
| **A dev-forced date (QA item 12)** | The section reads whatever the server sends; there is no client-side date logic at all, so nothing to desync. |

---

## NEEDS FROM OTHER LANES / REQUESTS FOR OTHER OWNERS

1. **Owner of `docs/specs/phone-ui/ux.md` and the phone's builder.** One
   integer: `PhoneSecNews.LayoutOrder` **30 -> 70**, so `TODAY'S HUNT` at 50
   sits above CITY NEWS. §6 shows the 74px-below-the-fold arithmetic. I claim
   **50** either way and do not touch 20, 40 or 60.
2. **`client-engineer`, one small refactor.** `showBig(ev, txt, col)`
   (`CityEvents.lua:606`) does two jobs: the 250-stud audience test and the
   `bigHolder` animation. Phase D needs the second without the first. Please
   **extract** `showBigLine(txt, col)` (the `bigGen` guard, the `City.hudOff`
   early return, pop/hold/fade, and the paired `TextTransparency` + `UIStroke`
   fade) and leave the audience test where it is, at the phase-B call site.
   Behaviour for phase B must be byte-identical -- it is at its QA gate.
3. **`client-engineer`, the rest of the build.** `CityEvents.lua`: the pill in
   `E.init(root)` as a direct `Frame` child of root (like `bigHolder`); the
   compact metrics from the existing `ViewportSize` connection at `:1373-1374`;
   the hunt's own list (**never** in `E.list`, never in `headline()`, never in
   the strip); the hunt branch in `E.prompt`; the three new `CityEvent` kinds in
   the dispatcher at `:1521-1531`; the hunt section in the rebuilt phone.
   **Do not use `UI.toast` / `UI.popText` / `UI.banner`** -- they do not render
   in the city (`collect-events/ux.md` §NEEDS 1, still unowned).
4. **`server-engineer`, four contract lines beyond `loop.md`:**
   - `hunt.found` is a **dense 3-element boolean array**, never sparse (§11 C,
     and the DataStore JSON trap it avoids);
   - the hunt's candidate pool must **exclude lots that carry a higher-priority
     prompt** -- anything `City.Roads` (station lifts, platforms), `City.Hang`
     (hangouts), `City.Apts` (lobbies) or `CityHome` claims. `E.prompt` runs
     after all four (`City.lua:2156-2170`), so a spot on one of those lots is
     unclaimable. Worked, and it is ~10 lots out of 381.
   - `spots[i].go` present **only** at tier 3, and equal to `lot.door`;
   - `spots[i].clueShort`, <= 44 characters, so the compact phone never
     truncates a clue.
5. **Owner of `City.lua`** (not me): the Capsule Corner prompt branch in §5 --
   one `if` before the `MallShops` loop at `:2236`. And one observation, not
   mine to fix: at canvasW 1112 the compact district pill and the coin pill
   already overlap by 46 x 30 px (§10).
6. **`audio`.** Four moments named, all from the existing pooled set:
   `BigChime` 1.25/0.75 (ticket), `BigChime` 1.25/0.8 (a hunt find, = FIND's
   claim), the three-note ta-da for 3/3 (`goalFanfare`'s exact pitches),
   `Click` 0.6/0.5 (the dull refusal on a found row). Nothing new requested.
7. **Art: none.** `capsule`, `crown`, `pin`, `hourglass` all exist. The hunt
   Sminski is `buildSminski` at 0.5 in the `none` skin (`loop.md` D9). **No
   Blender job, no review gate, no new icon.**
8. **`narrative-designer`.** Nothing. Every string here is interface text. The
   clue *sentences* are the server's, built from `areaOf`/`streetOf`/`compass`
   (`loop.md` D7) -- if anyone wants to warm their tone up, that is a
   conversation between narrative and server, and the UI renders whatever
   arrives.

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **A meter readout anywhere on the phone** | It would be the second place the same number lives, which is the duplicate the human has already ruled out once (the coin balance). The pill carries it; the pill's tap carries the exact figure. |
| **A "you're nearly there" notification at 80%** | It would fire every ~10 minutes forever. The gold fill says it for free and says it continuously. |
| **Surfacing the per-minute ceiling** | `loop.md` D5 forbids it and is right: it can only fire at somebody already earning above the reference rate. |
| **A radial / ring meter around the capsule icon** | Needs a rotated `UIGradient` or a new image set. The kit has a bar; the bar is two Frames and a corner. A new component needs a reason and "rounder" is not one. |
| **A once-per-account "here's what the meter is" tutorial** | There is no lifetime capsule counter in `data` to gate it on -- `bump()` (`SminskiServer.server.lua:121-130`) only writes challenge progress -- so it would need a new save field to avoid nagging. The first ticket's notification teaches the same thing at a better moment. |
| **Ticket count in the phone's status bar or footer** | The footer is the collection hook (`RARE SMINSKIS SPOTTED`) and the status bar is the clock and the weather. A third number there costs the phone its calm and duplicates the pill. |
| **A `GO` button on the pill, or a second prompt button at the machine** | `setPrompt` has one button (`City.lua:1750`) and a second one is a widget change in another lane's file. The tap-to-path plus SHOP covers both jobs. |
| **Per-spot distance readouts ("340 studs")** | The tier system *is* the distance readout, and a number would make tiers 1 and 2 pointless. |
| **A leaderboard of who found what** | `here` as a badge colour answers the only question a player actually asks ("is this one easier now?"). A name list is phase C's champion board. |
| **A hunt row in `NOW IN TOWN` or on the countdown strip** | It is a day-long objective, not a 3-minute event. `loop.md` D9 makes non-membership of `E.list` a structural rule and I am keeping it a visual rule too. |
| **A beacon or map pin on a hunt spot** | Finding it is the feature. GO's green ribbon stops at the door; the last 11 studs are yours. |
| **An animated "three new hiding places" card at the rollover** | A notification is the right size for something that happens while you are doing something else. |
| **A compact-specific pill position** | There isn't one to have: the slot is right-anchored and 138 wide on every canvas. |
| **Showing `meterDayTickets` as "8 / 12 today"** | A cap nobody reaches, rendered as a chore. It stays in the tap text only. |

---

## OPEN QUESTIONS FOR THE HUMAN

1. **A third pill in the top-right row.** The HUD's money row becomes coins,
   then tickets, then MENU. I think two currencies side by side is exactly
   right and the 138px slot is there for it -- but it is the busiest corner of
   the game and it is your HUD.
2. **`0` on the pill when you hold no tickets.** Honest and it teaches the unit,
   at the cost of a permanent zero on screen. The alternative is a blank slot
   with only the bar until your first ticket, which is prettier and slightly
   less clear.
3. **CITY NEWS moving from `LayoutOrder` 30 to 70.** My case is in §6; the cost
   is that a neighbour's spec changes by one integer.
4. **`SEVEN DAYS RUNNING!` as the streak-day big line**, replacing
   `ALL THREE FOUND!` rather than appearing alongside it. One line, two tickets,
   one notification -- or should the seventh day be bigger than that?
5. **The day cap being mentioned at all** (`all earned today \u{00B7} back tomorrow`,
   on a deliberate tap only). It is unreachable in a normal session; saying it
   at all admits a ceiling exists.
6. **`HIDING SMINSKI` / `SAY HI`** as the prompt's words, sharing `SAY HI` with
   phase A's rare sighting. Deliberate -- same gesture, same verb -- but if the
   two must never sound alike, the alternative is `FOUND ONE!` / `PICK IT UP`.

---

## QA SHOULD CHECK

Play-mode screenshots come back **solid magenta** (`HANDOFF.md` §49-50), so
every check is numeric. Every instance in this spec has a `Name`.

```
G  = Players.LocalPlayer.PlayerGui.SminskiCityUI      -- City.gui, DisplayOrder 4
R  = G:GetChildren()[1]                              -- H.root (the UIScale'd frame)
P  = R.CapsulePill                                   -- the meter/ticket pill
F  = R.PhoneShade.PhoneBody                          -- the phone (phone-ui spec)
HS = F:FindFirstChild("PhoneSecHunt", true)
```

**The pill: geometry and the two 8/10px gaps**

1. Desktop 1280x760, `UIScale == 1`: `P.AbsolutePosition` ~= `(976, 26)` +/- 2
   and `P.AbsoluteSize` ~= `(120, 48)`. (`IgnoreGuiInset` makes
   `AbsolutePosition.Y` inset-relative -- `HANDOFF.md`.)
2. `P.AbsolutePosition.X - (coinPill.AbsolutePosition.X + coinPill.AbsoluteSize.X)`
   **== 8** +/- 1, and `menuBtn.AbsolutePosition.X - (P.AbsolutePosition.X + P.AbsoluteSize.X)`
   **== 10** +/- 1. Re-run at canvas widths 1112, 1280 and 1333: both must hold
   at all three, because both neighbours are right-anchored.
3. `GetGuiObjectsAtPosition(centre of the coin pill)` returns the coin pill and
   **no** instance whose name begins `Capsule`. Same at the centre of MENU.
4. `GetGuiObjectsAtPosition(centre of P)` at canvasW 1112 returns `CapsuleTap`
   and **not** `H.boost`, `EventTray` or any `drive` button.

**The pill: states, read as integers**

5. Fresh session, before the first reply: `P.Visible == false`. After the first
   reply: `true`, and it is **never written again** -- set
   `data.City.meter = nil` via a dev hook and confirm `P.Visible` stays `true`
   (the latch) rather than flickering.
6. `City.hudVisible(false)` -> `P.Visible == false` within 0.1s **without
   phase D writing it** (it must be in `hudHidden`). `City.hudVisible(true)` ->
   `true`. Do this twice in a row: the `hudHidden` record must not be emptied
   (`City.lua:1324-1330`).
7. Force `meter` to 0 / 500 / 1495 / 1496 / 1869 and assert
   `CapsuleFill.AbsoluteSize.X / CapsuleTrack.AbsoluteSize.X` == 0 / 0.267 /
   0.799 / 0.800 / 0.999 (+/- 0.01), and `CapsuleFill.BackgroundColor3` is
   `C.mint` (150,205,140) below 0.80 and `C.gold` (245,196,80) at or above it.
8. Force `meter = 1` -> the fill is **>= 6 real px wide** (the 0.09 floor), not
   0.5px.
9. Force `tickets` = 0 / 1 / 3 / **4**: `CapsuleCount.Text` == `"0"` / `"1"` /
   `"3"` / **`"4"`** and `TextColor3` is `C.inkSoft` / `C.gold` / `C.coral` /
   `C.coral`. **`"4"` is the check that matters** -- a clamp to 3 silently eats
   the Daily 3's reward.
10. Earn 6 payouts inside 60s and count `CapsuleScale` tween starts: **<= 100**
    over the minute is meaningless; instead assert **no two pulses start within
    0.60s** of each other, and that a credit of 18 units starts none.
11. `City.hudVisible(false)`, then grant a ticket: `CapsuleCount.Text` is the
    new value immediately (written directly, not tweened), `CapsuleScale.Scale
    == 1` exactly, and `E.news[1].title == "CAPSULE TICKET"` (the receipt
    survived in CITY NEWS).

**Redemption**

12. Stand within 14 studs of `V(536,0,168)` with `tickets == 0`:
    `H.pBtn` text is `BROWSE`. With `tickets == 1`: `USE TICKET`, and
    `H.pSub.Text == "1 capsule ticket ready \u{00B7} one free capsule"`.
    With 3: the sub says `3 capsule tickets ready \u{00B7} one tap each`,
    button still `USE TICKET` and `H.pBtn.face.TextFits == true`.
13. Redeem: within 0.3s `GetGuiObjectsAtPosition(screen centre)` includes an
    instance descended from **`UI.gui`** (DisplayOrder 5) and the topmost hit is
    **not** a City HUD instance -- i.e. the capsule reveal is in front. At
    t = 1.8s `CapsuleCount.Text` has decremented by exactly 1.
14. Spend the last ticket: the prompt reverts to `BROWSE` within 0.2s without
    leaving the mall.

**The hunt section**

15. `hunt` absent from the `state` reply -> `HS.Visible == false`, and
    `PhoneFeed.AbsoluteCanvasSize.Y` shrinks by >= 248 (it reflowed, it did not
    leave a hole).
16. With `PhoneSecNews.LayoutOrder == 70` and 0 live events, phone open:
    `HS.AbsolutePosition.Y - PhoneFeed.AbsolutePosition.Y` ~= 120 and
    `HS.AbsoluteSize.Y <= 272`, and
    `HS.AbsolutePosition.Y + HS.AbsoluteSize.Y <= PhoneFeed.AbsolutePosition.Y + PhoneFeed.AbsoluteSize.Y`
    -- **the whole section is above the fold.** This is the check that proves
    the `LayoutOrder` request was worth making.
17. The three `HuntRow*.AbsolutePosition.Y` are strictly increasing with an 8px
    design gap, and `HuntRow1.AbsoluteSize` ~= `(314, 52)` desktop /
    `(314, 56)` compact.
18. In every row: `HuntClue.AbsolutePosition.X + HuntClue.AbsoluteSize.X`
    **<** `HuntGo.AbsolutePosition.X`, with a gap of 8 (desktop) / 6 (compact).
19. Force the longest tier-2 string (`on Sycamore Ave, by the CORNER STORE`):
    `HuntClue.TextFits == true` on **both** sizes. This is the shareable-clue
    guarantee. Tier 3 is allowed to report `false`.
20. Badge colours, with two clients: A finds spot 2 -> within 1s on client B,
    `HuntRow2.HuntBadge.BackgroundColor3` is `C.sky` (140,190,240) and
    `HuntBadgeIcon.ImageTransparency` ~= 0.25, **without B having found
    anything**. After B finds it: `C.mint` (150,205,140), transparency 0.
21. `HuntGo.holder.Visible` is `false` at tier 1 and 2 and `true` at tier 3, and
    `false` on a found row. Tap a tier-1 row: `HuntClue.Text ==
    "not close enough yet -- follow the clue"` and `TextColor3 == C.coral` for
    1.2s, **and `PhoneShade.Visible` stays `true`** (a refusal does not close
    the phone).
22. `HuntCount.Text` reads `"0 / 3"` -> `"1 / 3"` -> `"2 / 3"` -> `"3 / 3"`, and
    `TextColor3 == C.mintDark` (98,150,90) only at 3/3.
23. `HuntSocial.Visible == false` on a one-player server and `true` once any
    `spots[i].here >= 1` while `full == false`.
24. `HuntReset.TextColor3` flips to `C.coral` when `hunt.ends - os.time()` drops
    below 1800, and the text never contains a `-`.

**The third find, and the shared big line**

25. Claim the third: `bigHolder.Visible == true` within 0.2s,
    `bigText.Text == "ALL THREE FOUND!"`, `bigText.TextColor3 == C.gold`,
    `bigScale.Scale == 1` (not 0.6) at t = 0.5s, and `bigHolder.Visible ==
    false` at t = 4.6s with `bigText.TextTransparency == 1` **and** the
    `UIStroke.Transparency == 1`.
26. `City.hudOff` true at the third claim -> `bigHolder.Visible` stays `false`
    and `E.news[1].title == "ALL THREE FOUND"`.
27. Finish a collect event and claim the third hunt spot within 1s of each
    other, in both orders: exactly **one** `bigHolder` line is on screen at any
    instant, and `bigHolder.Visible == false` no later than 4.6s after the
    second of the two.
28. Force a 7-day streak: `bigText.Text == "SEVEN DAYS RUNNING!"`,
    `bigText.TextFits == true` at FredokaOne 34 in the 620px box **and** at 26
    in the 520px compact box, `CapsuleCount` increments by **2**, and exactly
    **one** notification fired.

**Prompt priority -- the one real collision risk**

29. For **6 or more** real hunt spots across several forced dates: teleport to
    the spot, wait 3s for streaming, and assert `H.pTitle.Text ==
    "HIDING SMINSKI"`. If it ever reads a shop, lift, hangout or lobby name,
    the lot exclusion in REQUESTS 4 is missing and the spot is **unclaimable**.
30. At the same spots: `H.pBtn.holder.Visible == true` and
    `City.Events.prompt(me)` returns non-nil at 11 studs and nil at 13
    (`Hunt.Claim = 12`).

**Instance budget and the day rollover**

31. Count instances once after `E.init`: `#P:GetDescendants() + 1 == 14` and
    `#HS:GetDescendants() + 1 == 58`. Then play a full hunt, a full meter cycle,
    a redemption and a rollover and re-count: **identical**. Nothing in phase D
    may allocate per credit, per find, per day or per tick.
32. Force the UTC day forward with 2/3 found: `HuntCount.Text == "0 / 3"` within
    2s, all three `HuntBadge.BackgroundColor3 == C.paper2`, all three
    `HuntGo.holder.Visible == false`, `HuntReset.Text` starts with
    `new ones in 23h`, exactly **one** notification fired
    (`NEW HUNT TODAY` / `yesterday's three are gone...`), `bigHolder.Visible ==
    false`, and the world's hunt models were **removed and re-added** (count
    them in `K.actors`).
33. Console clean through: entering the city, a full meter cycle, a redemption,
    a full hunt, a day rollover, `City.hudVisible(false)`/`(true)` with the
    phone open, and leaving the city.
