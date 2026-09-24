# COLLECT events (phase B) -- UX / UI

Slug `collect-events` · lane: `ux-designer` · written 2026-09-21
Reads: `BRIEF.md`, `docs/LOOPS.md` §2 §9, `docs/HANDOFF.md` §2 §5,
`game/CityEvents.lua` (all), `game/UI.lua`, `game/City.lua` HUD block,
`game/CityJobs.lua` notifications, `.claude/rules/design.md`.

**One sentence:** the shared counter is a 46px **progress tray** that grows out
of the bottom of the existing countdown strip, carrying exactly two labels --
`CITY 17 of 40` on the left and `YOU 1 of 3` on the right -- and the finish is
one stroked white-display line under it plus one notification. FIND keeps every
pixel it has today.

---

## WHAT EXISTS ALREADY

| Thing | Where | What it means for this design |
|---|---|---|
| Countdown strip: `UI.card` 340x50 at `UDim2.new(0.5,0,0,152)`, anchor (0.5,0), children `sIcon` 40x40 @(6,5), `sTitle` FredokaOne 16 @(52,6), `sSub` 12 @(52,27), `sClock` FredokaOne 20 right @(1,-12,0.5,0), plus a full-size tap button at ZIndex 6 | `CityEvents.lua:322-345` | I extend this card **downwards with a child frame**. No existing property changes, so FIND is byte-identical. The tap button only covers the 50px row, so the tray needs its own. |
| Strip visibility: `strip.Visible = ev ~= nil and not City.hudOff` | `CityEvents.lua:486` | The tray inherits `hudOff` compliance for free by being a child. Nothing new to wire. |
| `headline()` skips `ev.mine` | `CityEvents.lua:307-313` | **Collect must never set `ev.mine`**, or your first balloon deletes the strip. Collect progress lives in `ev.myCount` / `ev.got` / `ev.goal`. |
| Phone: `modalCard(560,560,"PHONE")`, 3 rows at y 92/196/300, each 512x96 with `icon 56`, `title`, `clock`, `clue` (2 lines, 13px), `count` (1 line, 12px @y74), `GO` 120x56; `empty`; CITY NEWS @408/430; RARE SMINSKIS footer | `CityEvents.lua:350-392, 409-442` | The `count` line is already a spare one-line slot in exactly the right place. Collect needs **no new instance in the phone**. |
| Progress bar precedent: track `Frame` C.paper2 + fill `Frame` C.mint, both `UICorner` | shift strip `CityJobs.lua:113-125`, ELO bar `CityJobs.lua:165-177` | A bar is not a new component; it is this composition, twice already. I reuse it verbatim. |
| `J.notify(icon,title,sub,color)`: bottom-right, **max 3**, 320x66, 4.5s, above the driving buttons | `CityJobs.lua:42-84` | My whole-event notification budget is 3. Per-item pickups get none. |
| `notify()` in CityEvents also pushes into `E.news` (capped 6) before calling `City.Jobs.notify` | `CityEvents.lua:36-40` | The finish receipt survives in the phone's CITY NEWS even if the HUD was hidden at the moment it fired. |
| HUD grammar, top centre: district pill y18 h64 (320 wide), boost banner y92 h54 (340), event strip y152 h50 (340) | `City.lua:566-575`, `City.lua:678-682`, `CityEvents.lua:323` | y **202-248** is the next free slot in that stack and it is 340 wide. That is where the tray goes. |
| Left column WORK/SHOP/TOWN/PHONE 160x56 at y 22/86/150/214; CITY JOBS card at `(0,24,0.5,-96)` desktop / `(0,24,0,278)` compact | `City.lua:552-556`, `City.lua:660` | Both columns and the jobs card are at the screen edges; the whole top-centre column is mine. No collision -- worked below. |
| `City.hudVisible` sweeps **direct `Frame` children of `H.root` that are Visible** | `City.lua:1299-1323` | A bare `TextLabel` child of `H.root` is *not* swept (`H.raceText`, `H.hint` are existing holes). My finish line therefore lives in a wrapper `Frame`. |
| `UI.card` shadow is `(1,-8,1,0)` at (4,7) | `UI.lua:143` | The strip's shadow ends at y209, so a *sibling* card below it would sit in its shadow. A child tray has no such problem. |
| **`UI.popText` / `UI.toast` are parented to `hud`** (`UI.lua:538`), and `UI.setMode` does `hud.Visible = mode == "run"` (`UI.lua:2259`), while `ctx.enterCity` calls `UI.setMode("none")` (`SminskiRunner.client.lua:1245`) | -- | **Every `UI.toast` in the city is invisible.** That includes phase A's three (`CityEvents.lua:236, 401, 406`) and the `UI.toast(what)` inside `earned()` (`City.lua:1760`). `UI.banner` is in the same dead frame (`UI.lua:515`). **This design uses neither.** See NEEDS FROM OTHER LANES. |
| `City.popCoins(n)` -- a BillboardGui over your own head, "+N COINS", 1.7s, `AlwaysOnTop` | `City.lua:2447-2477` | This is the city's working "you got paid" visual. It is the one place the bonus number appears. One per event only -- 40 of these would stack on top of each other. |
| Icons that exist: bag bolt capsule chart clock coin crown dog friends gear heart hourglass house lock magnet paw pin play shield shirt star trophy x2 | `Art.lua:18-42` | No new icon requested. Assignments in NEEDS FROM OTHER LANES. |
| `EV.ClaimRadius = 16`, prompt loop `E.prompt` | `Config.lua:991`, `CityEvents.lua:285-298` | Collect must be excluded from `E.prompt` -- see §5. |

---

## THE DESIGN

### 1. The flow

1. Director announces (existing path). One notification: `CASH DROP!` /
   `in 45s · around Maple Row`. Strip appears with the countdown, as today.
2. At `startT` the items appear and **the tray appears under the strip**. The
   beacon appears (collect sets `def.open = true`, so `mark()` at
   `CityEvents.lua:135` fires unchanged) and PHONE → GO paths you there
   (`ev.spot` = zone centre, so `E.go` needs no change).
3. You walk over items. **No prompt card, no button: pickup is automatic
   within 6 studs.** Every pickup moves the tray. Whose pickup it was is
   readable from *which slot pulses and in what colour*.
4. Finish: the goal is reached (coop) or the last bag goes (competitive) ->
   the tray completes in place, one big line appears for ~4.2s, one
   notification lands with the receipt, the strip's clock reads `DONE`/`GONE`.
   The event is removed by the server ~5s later and the strip and tray go with
   it via the existing `onEnd`/`E.step` teardown.
5. **Getting out** is: walk away (nothing is modal at any point), or MENU /
   any modal -> `City.hudOff` hides strip + tray + notifications. The phone
   closes on its X, its dim, or GO. Nothing in this feature can trap a player,
   and nothing in it ever covers the city.

### 2. The progress tray (the centrepiece)

**Built as a child of the strip's existing `card`.** The strip row is
untouched; the tray extends past the card's 50px bottom edge (the holder does
not clip). `strip.Visible` already gates `City.hudOff`, so the tray does too.

```
 x=470                                       x=810      (1280 canvas, scale 1)
 ┌──────────────────────────────────────────────────┐  y=152  ← existing row,
 │ [icon] CITY CLEANUP                       1:24   │          UNCHANGED
 │        around Maple Row                          │  h=50
 ├──────────────────────────────────────────────────┤  y=202  ← NEW tray
 │  CITY 17 of 40                    YOU 1 of 3     │
 │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  h=46
 └──────────────────────────────────────────────────┘  y=248
```

| Instance | Kit | Size / Position (in the strip `card`'s space) | Style |
|---|---|---|---|
| `tray` | `Frame` + `UICorner 14` | `fromOffset(340,46)` at `fromOffset(0,50)` | `C.paper`, `BorderSizePixel 0`, **`ZIndex = 4`** (must beat the card's skin images and labels, which are at 1 and 3), `Visible = false` |
| `trayTap` | `TextButton` | `fromScale(1,1)`, `Text = ""`, `BackgroundTransparency 1` | `Audio.play("Click",1.1,0.6)` then `E.openPhone()` -- same affordance as the row above it |
| `trayCity` | `UI.text` | `fromOffset(170,22)` at `fromOffset(16,4)` | FredokaOne **18**, `C.ink`, `TextXAlignment Left`, `TextTruncate AtEnd` |
| `trayMine` | `UI.text` | `fromOffset(138,22)` at `UDim2.new(1,-16,0,4)`, anchor (1,0) | FredokaOne **16**, `C.inkSoft`, `TextXAlignment Right`, `TextTruncate AtEnd` |
| `trayTrack` | `Frame` + `UICorner 5` | `fromOffset(308,10)` at `fromOffset(16,30)` | `C.paper2` |
| `trayFill` | `Frame` + `UICorner 5` | `fromScale(0,1)` inside track | `C.mint` (coop) / `C.gold` (competitive) |

Five new instances, fixed. **Nothing in this feature scales with item count.**

**Why two named slots.** The two numbers must never be confused, so they are
separated on four axes at once: **position** (left vs right), **size** (18 vs
16), **colour** (ink vs inkSoft/gold/mint) and -- the one that actually does
the work -- **a word each**. The server's number is literally labelled `CITY`,
which is the game's own word for the shared thing (SMINSKI CITY, CITY JOBS,
CITY NEWS, CITY CLEANUP). Yours is labelled `YOU`. Parallel construction, no
ambiguity, no legend needed, and it teaches the idea that the city now has
numbers of its own.

**Which direction the bar goes says which kind of event it is.**

- **Cooperative** (Balloon Festival, City Cleanup): the fill **grows** left to
  right, `got / goal`, `C.mint`, stepping to `C.gold` at ≥ 0.85 ("nearly
  there"). Every growth is a 0.25s `UI.tween` on `Size` -- never a snap,
  because a jump you did not cause should read as motion made by someone else.
- **Competitive** (Cash Drop): there is no goal, so the bar shows the money
  that is **left** and **drains** right to left, `left / count`, `C.gold`,
  turning `C.coral` at ≤ 0.25. Full-at-start / empty-at-end is the opposite
  motion to cooperative, so the two modes are distinguishable in peripheral
  vision without reading a word.

**Cash Drop's strip, specifically** (the brief asks): left slot = bags left,
because that is the only number that creates urgency; the leader is **not** on
the tray -- there is no room for a name, and a stranger's name ticking up
every four seconds is discouraging noise. The leader appears in exactly two
places: the phone row (always) and the finish notification (once). The tray
tells you only when *you* are the leader, which is the part worth knowing
mid-scramble.

#### Every tray string, final

`trayCity` (left):

| State | Text | Colour |
|---|---|---|
| coop, live | `CITY 17 of 40` | `C.ink` |
| coop, crossing 50% (1.2s, then reverts) | `HALFWAY!` | `C.mintDark` |
| coop, goal reached | `CITY 40 of 40` | `C.ink` |
| coop, time out short of goal | `CITY 31 of 40` | `C.inkSoft` |
| comp, > 25% left | `19 BAGS LEFT` | `C.ink` |
| comp, ≤ 25% left | `5 BAGS LEFT` | `C.coral` |
| comp, exactly 1 left | `1 BAG LEFT` | `C.coral` |
| comp, none left | `ALL GONE` | `C.coral` |
| a refused claim (1.0s, then reverts) | `too far away` / `already gone` / `it's over` | `C.coral` |

`trayMine` (right):

| State | Text | Colour |
|---|---|---|
| coop, mine 0, city < 80% | `YOU 0 of 3` | `C.inkSoft` |
| coop, mine 0, city ≥ 80% | `GRAB 3, QUICK!` | `C.coral` |
| coop, mine 1-2 | `YOU 2 of 3` | `C.gold` |
| coop, the moment mine hits 3 (1.6s) | `BONUS LOCKED` | `C.mintDark` |
| coop, mine ≥ 3 | `YOU 7 · BONUS` | `C.mintDark` |
| coop finish, mine ≥ 3 | `YOU 7 · PAID` | `C.mintDark` |
| coop finish, mine 1-2 | `YOU 2 · NO BONUS` | `C.inkSoft` |
| coop finish, mine 0 | `NEXT TIME!` | `C.inkSoft` |
| comp, mine 0 | `YOU 0 BAGS` | `C.inkSoft` |
| comp, mine ≥ 1, not top | `YOU 2 BAGS` | `C.gold` |
| comp, mine ≥ 1 and strictly top | `YOU 4 · LEADING` | `C.gold` |
| comp finish, strictly top | `YOU 4 · TOP` | `C.gold` |
| comp finish, mine ≥ 1 not top | `YOU 2 BAGS` | `C.gold` |
| comp finish, mine 0 | `NONE THIS TIME` | `C.inkSoft` |

Once you are past the bonus threshold your slot **drops its denominator**, so
at the moment you are most likely to stare at the tray the two numbers do not
even share a shape. Both slots carry `TextTruncate.AtEnd` so an unforeseen
string degrades instead of overflowing the card.

### 3. Per-item feedback (no notification, ever)

A pickup is worth about 6 coins. It gets three cheap channels and nothing
else:

1. **The item vanishes** (client-engineer's draw; pooled parts, no per-item
   GUI, no per-item light -- `performance.md`).
2. **The tray moves, and pulses in the colour of whoever did it.** This is the
   feature, not decoration:
   - *my* pickup -> `trayMine` `UIScale` 1 → 1.18 (0.10s) → 1 (0.16s, Back).
   - *someone else's* pickup (`got` changed, `myCount` did not) -> `trayCity`
     pulses the same way **and flashes `C.sky` for 0.30s** before returning to
     its colour. `C.sky` is used nowhere else in the tray, so "that was not
     me" is a colour you learn in one event. On a one-player server you will
     never see it; the first time another player's balloon moves your bar is
     the emotional beat of the entire phase, and it should have its own colour.
3. **One pooled sound** (audio lane owns which).

No `J.notify`, no `City.popCoins`, no floating text per item. 40 balloons
means 40 sounds and 40 two-frame pulses, and zero new GUI objects.

**Milestones** (still no notification, except one):
- city 25% / 50% / 75%: whole-`tray` `UIScale` pulse 1 → 1.05 → 1 (0.12 +
  0.18s). At **50% only**, `trayCity` reads `HALFWAY!` in `C.mintDark` for
  1.2s and then returns to the number.
- competitive, crossing down to ≤ 5 left: `trayCity` + fill turn `C.coral`
  (state change, not an animation) and the tray pulses once.
- **your 3rd item** is the one real state change a player owns, so it gets the
  one milestone notification: `notify("star", "BONUS LOCKED IN", "3 collected
  · you get the finish bonus", C.mint)` plus the `BONUS LOCKED` flash.

Total notification budget for one player over one whole cooperative event:
**3** (announce, bonus locked, finish). The stack holds 3.

### 4. The finish moment

Everything here is in `H.root`, because `UI.banner` and `UI.toast` do not
render in the city (see WHAT EXISTS ALREADY).

New instances, created once in `E.init(root)`:

| Instance | Kit | Size / Position (1280x760 canvas) | Style |
|---|---|---|---|
| `bigHolder` | `Frame` | `fromOffset(620,48)` at `UDim2.new(0.5,0,0,256)`, anchor (0.5,0) | `BackgroundTransparency 1`, `Visible false`. **A Frame, not a bare label**, so `City.hudVisible` sweeps it like everything else. |
| `bigText` | `UI.text` | `fromScale(1,1)` | FredokaOne **34**, `stroke = 3` (the kit's UIStroke in `C.ink`), centred. Colour: `C.mint` cooperative, `C.gold` competitive. Same treatment as `H.raceText` / `H.hint`, which is the city's established "big news over the world" voice. |
| `bigScale` | `UIScale` on `bigHolder` | -- | pop in 0.6 → 1 over 0.30s, `EasingStyle.Back` |

y 256-304 sits **under** the tray (ends 248) and above the character's head in
normal camera framing. It never covers the city centre-screen and it never
takes input.

**Sequence, cooperative goal reached** (server `done`, `why = "goal"`):

| t | What |
|---|---|
| 0.00 | `trayFill` tweens to full (0.18s); `trayCity` → `CITY 40 of 40`; strip `sClock` → `DONE` in `C.mintDark` (4 glyphs, fits the 64px slot) |
| 0.10 | `bigText` = `WE DID IT!` in `C.mint`, pops in |
| 0.25 | `trayMine` → its finish string (table above) |
| 0.60 | contributors with mine ≥ 3 only: `City.popCoins(bonus)` -- the one and only place the bonus number is drawn |
| 0.80 | one `J.notify` (below) -- counts, never coins, so the number is not shown twice |
| 3.70 | `bigText` fades: `TextTransparency` 0→1 **and** the UIStroke's `Transparency` 0→1 over 0.5s (HANDOFF §3) |
| 4.20 | `bigHolder.Visible = false` |
| ~5.0 | server ends the event; existing teardown removes strip, tray and models |

**Who sees the big line.** Only if `myCount > 0` **or** you are within 250
studs of the zone centre. A full-width celebration for something happening
across town is noise; a notification is the right size for that. If
`City.hudOff` is true at t=0, skip the big line and the `popCoins` entirely --
the notification still runs through `notify()`, which writes to `E.news`, so
the receipt is waiting in the phone's CITY NEWS. Nothing is ever lost, and
nothing ever appears over a modal.

**What it says to each player** (all three cases the brief asks for):

| You | Big line | Notification |
|---|---|---|
| contributed 7 (≥ 3) | `WE DID IT!` | `("coin", "CITY GOAL REACHED", "you got 7 of 40 · bonus paid", C.gold)` |
| contributed 1 (below the threshold) | `WE DID IT!` | `("friends", "CITY GOAL REACHED", "you got 1 · grab 3 next time", C.sky)` |
| contributed 0, but standing there | `WE DID IT!` | `("friends", "CITY GOAL REACHED", "the city got there · join in next time", C.sky)` |
| contributed 0, across town | -- | same as above |

The bystander still gets the big line **on purpose**: it is the city's moment,
not yours, and hiding it would turn a shared event back into a private one --
which is the exact problem phase B exists to fix. What differs is the receipt.

**Cooperative, time out short of the goal** (`why = "time"`): no big line --
we did not do it and saying so in 34pt would be mean-spirited. `trayCity` dims
to `C.inkSoft`, the bar stays where it got to, and one notification:
`("hourglass", "BALLOON FESTIVAL OVER", "the city got 31 of 40 · no bonus this
time", C.inkSoft)`. Per-item pay was already paid; only the bonus is lost, and
the wording says so plainly.

**Cash Drop's ending** (`why = "empty"` -- the last bag going *is* the end):

| t | What |
|---|---|
| 0.00 | `trayFill` tweens to 0 (0.18s); `trayCity` → `ALL GONE` in `C.coral`; `sClock` → `GONE` in `C.gold` |
| 0.10 | `bigText` in `C.gold`: `YOU TOOK THE MOST!` if you are strictly top, otherwise `ALL BAGS GONE!` |
| 0.25 | `trayMine` → its finish string |
| 0.80 | notification (below). No `popCoins`: every bag was already paid as it was grabbed. |
| 3.70-4.20 | fade, as above |

| You | Notification |
|---|---|
| strictly top | `("coin", "CASH DROP OVER", "you took the most · 6 bags", C.gold)` |
| ≥ 1 bag, not top | `("coin", "CASH DROP OVER", "you took 2 bags · Alex took 6", C.gold)` |
| 0 bags | `("hourglass", "CASH DROP OVER", "Alex took the most · 6 bags", C.inkSoft)` |
| nobody took any | `("hourglass", "CASH DROP OVER", "nobody found the bags this time", C.inkSoft)` |

If Cash Drop times out with bags still out: no big line,
`("hourglass", "CASH DROP OVER", "3 bags never got found", C.inkSoft)`.

Leader names are clamped to 10 characters + `…` before they go in any string.

### 5. No prompt card for collect items

`E.prompt` (`CityEvents.lua:285-298`) gains one condition:
`ev.def.kind ~= "collect"`. Collect items never produce a prompt.

**Why:** the bottom-centre prompt card is 470x104 and it is for *decisions*
("this pup looks lost. take it home?"). Walking past 40 balloons would flicker
that card continuously, and on a phone it would demand 40 taps with the other
thumb on the stick. Picking up a balloon is not a decision. **Pickup is
automatic within 6 studs**, client-initiated, server-validated exactly like a
FIND claim -- so the anti-cheat story is unchanged and the race for a cash bag
becomes pure movement instead of who tapped first. The card stays free for the
things that actually ask a question.

Refusals (`too far away`, `already gone`, `it's over`) show for 1.0s in
`trayCity` in `C.coral`, because that is where the player is already looking
and because `UI.toast` does not render here. A lost race is a one-second
flicker, not a notification.

### 6. The phone

Zero new instances. Two existing lines gain a collect branch; everything else
in `E.refreshPhone` is untouched.

| Line | FIND (today, untouched) | COLLECT |
|---|---|---|
| `r.title` | `def.title` | unchanged code |
| `r.clock` | `in 0:45` / `1:24` | unchanged code |
| `r.clue` (2 lines, 13px, 282 wide) | `latestClue(ev) or ev.area` | coop: `40 balloons around Maple Row · walk over them to grab them`  ·  comp: `24 cash bags dropped on Maple Row · first one there keeps it`  ·  goal reached: `done -- the city did it!` |
| `r.count` (1 line, 12px) + `TextColor3` | `"Alex got there first · 3 so far"`, `C.inkSoft` | coop: `CITY 17 of 40  ·  YOU 1 of 3` in **`C.ink`**  ·  coop done: `CITY 40 of 40 · DONE · YOU 7`  ·  comp: `5 bags left · Alex 6 · YOU 2`  ·  comp, nobody yet: `24 bags out there · nobody has one yet` |
| `r.go` | hidden when `ev.mine` | always shown for collect (`ev.mine` is never set, `ev.spot` = zone centre) |

`r.count` goes from `C.inkSoft` to `C.ink` **for collect rows only**: on the
strip the bar carries the progress and the numbers can be quiet; in a list
with no bar the numbers are the whole point. 26-38 characters at GothamMedium
12 is ~180-260px in a 282px slot.

**No contributors list, and no bar, on the phone.** A list of names needs a
scroll that the 3-fixed-row phone does not have (CITY NEWS is pinned at y408),
and it would answer a question nobody asks mid-event. The one name worth
showing is the leader, and it fits in `r.count` as one word plus a number.
"Your share" is already there: `YOU 1 of 3` is your share *and* the rule for
earning the bonus in six words. The phone is the list and the history; the
strip is the live instrument.

### 7. Both screen sizes

Canvas geometry is stable in x: `root.Size = viewport / scale` with scale
clamped to ≥ 0.6, so the canvas is **never narrower than 1280** -- only the
height varies (~530 on the smallest phone, up to ~970 on a tall desktop
window). Everything I add is top-anchored, so nothing moves.

Worked overlap check on the **smallest supported canvas (1333 x 530)**:

| Element | Occupies (design px) | Clear of |
|---|---|---|
| district pill (compact 240x44) | y 12-56, centred | -- |
| boost banner | y 92-146, centred x 497-837 | pill |
| **event strip row** | y 152-202, x 497-837 | boost |
| **tray (NEW)** | y 202-248, x 497-837 | strip shadow ends y209 *inside* the tray's x-range, but the tray is a child drawn above it -- no visible seam |
| **big line (NEW)** | y 256-304, x 357-977 | 68px above the prompt |
| prompt card | top y ≈ 372 (389 with the 0.84 compact scale) | big line |
| left column + CITY JOBS (compact y278-330, x 24-214) | x ≤ 214 | tray starts x 497 |
| coin pill | y 26-74, x 851-1021 | tray starts y 202 |
| notifications `noteRoot` | x 969-1309, y 90-330 | tray ends x 837 |
| driving buttons (compact) | y 184-334, right | centre column |

Closest call is the big line's 68px of clearance above the prompt card on a
530-tall canvas. If both are up at once the screen is busy but nothing
overlaps, and the big line is gone in 4.2s.

**Compact variant of the tray** (read `UI.compact()` in `E.init` and re-read
on `camera:GetPropertyChangedSignal("ViewportSize")` -- do **not** add a hook
to `H.layout`, City.lua is another lane's file):

| | desktop | compact |
|---|---|---|
| `tray` height | 46 | **48** |
| `trayTrack` | 308x10 @ (16,30) | 308x**12** @ (16,**30**) |
| `trayCity` TextSize | 18 | **20** |
| `trayMine` TextSize | 16 | **18** |
| wording | `CITY 17 of 40` / `YOU 1 of 3` | **`17/40`** / **`YOU 1/3`** |
| `bigText` | 34, 620 wide | **26**, **520** wide |

At 0.6 scale, 20 design px is ~12 real px, which is the smallest thing on that
screen I am willing to make load-bearing -- so the compact tray buys legibility
by spending words, not by spending pixels. `CITY`/`YOU` survive as the labels
because they are what stop the two numbers being confused; `of` does not.

The bottom-left belongs to the thumbstick on a phone; I put nothing there.

### 8. What the client must receive from the server to draw this

Field names are exact. **No new remote.** Anything absent must degrade to
"tray hidden, strip behaves exactly like FIND".

**A. `Config.Events` def fields** (static, both sides read them):

| Field | Type | Used for |
|---|---|---|
| `kind` | `"collect"` | selects every branch in this spec |
| `shared` | `true` coop / `false` competitive | bar direction, wording, finish |
| `count` | int (24) | competitive denominator |
| `bonusAt` | int (3) or nil | the `of 3` in `YOU 1 of 3`; nil = no bonus wording anywhere |
| `noun` | `"bags"` / `"balloons"` / `"litter"` | phone `r.clue`, competitive tray (`N BAGS LEFT`) |
| `open` | `true` | makes the existing beacon + GO path work unchanged |
| `icon`, `title` | string | strip and phone, unchanged code |

**B. the public event record** (`CityEvent "start"`, and each entry of the
`Events state` reply) gains:

```
got   = 17            -- integer, items the server counts as collected
goal  = 40            -- integer, cooperative only (player-count-scaled); nil when not shared
left  = 5             -- integer, competitive only (count - got); client will not derive it
top   = { name = "Alex", n = 6 }   -- competitive only; nil until someone has one
spot  = { x, z, 0 }   -- the ZONE CENTRE, in the existing spot shape, so mark() and E.go work untouched
area  = "around Maple Row"         -- existing field, reused for the strip sub and the phone
```

**C. progress pushes:** `CityEvent("progress", { uid, got, left, goal, top })`
-- broadcast, **coalesced server-side to at most 4 per second per event** and
sent only when `got` changes. The client tweens; it never needs a tick rate
higher than that.

**D. claim reply:** `Events:InvokeServer("claim", uid, itemId)` →
`{ ok, coins, xp, mine, got, left, goal, top, reason }`. `mine` is **my new
total** and is the only authority for `YOU n`. `reason` is one of the three
short strings in §5, lower case. FIND's claim reply shape is untouched.

**E. finish:** `CityEvent("done", { uid, why, got, goal, top })` broadcast,
where `why` is `"goal"` / `"empty"` / `"time"`; **plus** a per-player
`FireClient(p, "reward", { uid, mine, bonus })` to each player with
`mine > 0`, where `bonus` is the coins actually paid (0 if none). A player who
collected nothing needs nothing: their client already knows `myCount == 0`.

**F. mid-event join:** the `Events state` reply is per-player, so each collect
entry must carry `mine` (0 for a new arrival) alongside the shared numbers.

**G. a new tunable:** `Config.Events.PickupRadius = 6` (client auto-claims
inside it; the server should validate at ~9 to absorb latency and streaming).

**H. what must respect `City.hudOff`:** the tray (free, it is inside
`strip`), `bigHolder` (a Frame in `H.root`, plus an explicit
`if City.hudOff then skip` at t=0), and `City.popCoins` (skip). The
notifications already live in a Frame under `H.root`.

---

## NUMBERS

| Tunable | Value | Why |
|---|---|---|
| tray size | 340 x 46 (48 compact) | 340 matches the strip and the boost banner exactly; 46 is the smallest height that fits an 18px line plus a 10px bar with 4/6/6 breathing room |
| tray y offset in card | 50 | flush with the bottom of the 50px row: one object, not two |
| tray ZIndex | 4 | above the card's skin images (1) and its labels (1-3), below the row's tap button (6) |
| tray corner radius | 14 | the kit's card radius (`UI.lua:44`) |
| bar | 308 x 10, inset 16, corner 5 | the shift strip's bar is `(1,-32) x 8` inset 16 corner 4; same language, 2px taller because this one is the headline |
| minimum visible fill | `p = got > 0 and math.max(0.035, got/goal) or 0` | 1 of 40 is 7.7px, which a 5px corner radius eats. 0.035 = 10.8px, so one item always shows |
| fill tween | 0.25s Quad Out | fast enough to feel caused, slow enough to see it move when you were not the cause |
| coop fill colour steps | `C.mint` < 0.85, `C.gold` ≥ 0.85 | mint = the city's own colour; gold at the end is "nearly there" |
| comp fill colour steps | `C.gold` > 0.25 left, `C.coral` ≤ 0.25 left | gold = money; coral is the HUD's only urgency colour |
| my-pickup pulse | UIScale 1 → 1.18 (0.10s) → 1 (0.16s Back) | matches the button press feel in `UI.button` (0.06/0.22 Back) |
| other-player pulse | same, plus `C.sky` for 0.30s | long enough to catch peripherally, short enough not to look like a state |
| tray milestone pulse | 1 → 1.05 → 1 (0.12 / 0.18s) | the whole tray, so it reads as the bar and not the text |
| `HALFWAY!` hold | 1.2s | one glance |
| `BONUS LOCKED` hold | 1.6s | it is a rule being taught, so slightly longer |
| refusal hold | 1.0s | a lost race should not linger |
| big line | y 256, 620x48, FredokaOne 34, stroke 3 | 34pt with a 3px ink stroke is `H.raceText`'s weight class; y256 clears the tray (248) and the smallest canvas's prompt (372) |
| big line timing | pop 0.30 Back, hold 3.40, fade 0.50 | 4.2s total: long enough to read twice, shorter than the ~5s the server leaves before teardown |
| big line audience | `myCount > 0` or within **250 studs** of the zone centre | the zone is scattered over lots within ~170 studs of a centre lot (HANDOFF §5), so 250 is "in or at the edge of the event" |
| `mine ≥ 80%` panic string | city fill ≥ 0.80 and `myCount == 0` | late joiners: `GRAB 3, QUICK!` is only honest while there is still time to get 3 |
| notification budget | ≤ 3 per event per player | the stack holds 3 (`CityJobs.lua:51`) |
| progress push rate | ≤ 4/s per event, only on change | the tray refreshes on the existing 0.25s UI tick anyway |
| leader name clamp | 10 chars + `…` | 20-char display names overflow `r.count` |
| pickup radius | 6 studs (server validates at ~9) | `EV.ClaimRadius` is 16 and would auto-grab from across the pavement; 6 is "I walked over it" |

---

## EDGE CASES

| Case | What the UI does |
|---|---|
| **No progress fields in the payload** (server bug, old client, new event kind) | `goal`/`left` nil → `tray.Visible = false`; the strip behaves exactly like FIND. Never `CITY nil of nil`. |
| **Before `startT`** | Tray hidden. The row already says `starting soon · tap for details` with the countdown; a `CITY 0 of 40` bar before the items exist is a lie. |
| **Empty server / one player** | Goal is player-count-scaled, so `CITY 0 of 12`. The `CITY` label is still correct and still teaches the idea. The `C.sky` "someone else" pulse simply never fires. |
| **Second player's first pickup** | `got` changes, `myCount` does not → the sky pulse. This is the phase's headline moment; it must not be swallowed by coalescing (the server sends on change). |
| **Mid-event join** | `Events state` returns `got/goal/mine=0`; the tray appears with the bar already part-full and `YOU 0 of 3`, or `GRAB 3, QUICK!` if the city is past 80%. No animation on the first draw -- set the fill directly, then tween from there, or the bar sweeps for two seconds on arrival. |
| **Mid-event leave/join changes `goal`** | Tween the fill to the new fraction over 0.40s and pulse `trayCity` in `C.sky`. Never let it jump, and never show it going backwards silently. |
| **One item left** | Nothing special coop; competitive says `1 BAG LEFT` (singular, `C.coral`). |
| **Goal reached with items still on the ground** | Coop only. Items stop counting; a pickup attempt gets `it's over` in `trayCity`. The server may leave them to despawn with the event. |
| **"You already did this"** | Does not exist for collect -- there is no once-per-player claim. The nearest thing is a race lost to another player: `already gone`, 1.0s, in the tray. |
| **Two claims racing one bag** | The loser gets `already gone`; their tray does not move, and the bar shows the winner's pickup arriving via `progress`. No notification, no result card. |
| **`City.hudOff` at the finish** (a modal open) | No big line, no `popCoins`; the notification still writes to `E.news`, so the phone's CITY NEWS carries the receipt. |
| **Phone open while progress moves** | `E.refreshPhone` already reruns on the 0.25s tick when the phone is visible (`CityEvents.lua:496`) -- the row's numbers move live, for free. |
| **A scripted / NPC name in `top`** | Clamped to 10 chars like any other name. The tray never shows a name, so only `r.count` and one notification are affected. |
| **Two collect events at once** | Cannot happen (one headline at a time), but `headline()` picks the soonest-ending and the tray follows it. The other still lists on the phone with its own numbers. |
| **Collect event while a kart race is running** | `H.raceText` sits at y96 and already collides with the boost banner -- pre-existing, not mine. My additions start at y202. |
| **Leaving the city mid-event** | Existing `E.leave` teardown; the tray and big line go with `H.root`. |

---

## NEEDS FROM OTHER LANES

1. **`UI.toast` and `UI.popText` do not render in the city** --
   `popLayer` is a child of `hud` (`UI.lua:538`), `hud.Visible = mode ==
   "run"` (`UI.lua:2259`), and the city runs in `"none"`
   (`SminskiRunner.client.lua:1245`). That silently kills phase A's three
   toasts (`CityEvents.lua:236, 401, 406`) and the confirmation inside
   `earned()` (`City.lua:1760`). **This spec depends on neither**, but someone
   owns the fix: either reparent `popLayer` (and `banner`) to `root` in
   `UI.lua`, or stop calling `UI.toast` from city code. Lead's call which lane.
2. **`Config.Events` fields** (server lane): `kind`, `shared`, `count`,
   `bonusAt`, `noun`, `open = true`, and `Config.Events.PickupRadius = 6`.
3. **Icons from the existing set** (server lane sets `def.icon`): CASH DROP =
   `coin`, CITY CLEANUP = `bag` (a bin bag is the closest existing silhouette),
   BALLOON FESTIVAL = `heart` (round, festive, warm; `capsule` reads as gacha
   everywhere else in the game and would muddy it). **No new art requested.**
   A real balloon icon would be a Blender job -- see OPEN QUESTIONS.
4. **Server payload shapes** exactly as §8 B-G, including the per-player
   `mine` in the `state` reply and the `FireClient(p, "reward", ...)` at the
   finish.
5. **Server should end a cooperative event ~5s after the goal** and Cash Drop
   ~5s after the last bag, so the finish moment gets to play before teardown.
6. **Client-engineer**: the drawing must not add a GUI or a light per item
   (`performance.md`), `ev.mine` must stay unset for collect events (it would
   delete the strip via `headline()`), and `E.prompt` gains the
   `kind ~= "collect"` guard.
7. **Audio lane**: I have named four moments -- per-item pickup, city
   milestone, your bonus locking, and the finish -- and asked for nothing
   outside the 12 pooled sounds.

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **A contributors leaderboard on the phone** | Needs a scroll the 3-fixed-row phone does not have, and mid-event nobody asks "who else is helping" -- they ask "how far along are we". The one name that matters (the leader) fits in the row's existing count line. Revisit with phase C's 10-minute champion board, which is the right home for standings. |
| **A progress bar inside the phone row** | The row has 6px of spare vertical space; a bar there would be decoration next to the numbers that already say it. The bar belongs on the live instrument. |
| **A results modal at the finish** | It would cover the city at the exact moment the city is worth looking at, and modals are for decisions. The tray + one line + one notification say the same thing without taking the screen. |
| **Per-item floating "+6"** | `City.popCoins` is a 230x64 billboard that would stack 40 deep. The tray tick plus a sound is enough for a 6-coin event. |
| **A prompt card per item** | See §5: flicker on desktop, 40 taps on a phone. Auto-pickup is better *and* cheaper. |
| **Showing the leader's name on the tray** | No room at 340 wide, and a stranger's name ticking up every four seconds discourages more than it motivates. |
| **A zone-boundary ring / minimap overlay** | The existing beacon (`mark()`, visible over rooftops) plus the GO path already answer "where". A new world-space UI layer is a phase-C-sized ask. |
| **A balloon icon, a bin-bag icon** | Blender + human approval. Phase B ships with `heart` / `bag` / `coin`; swapping an icon later is a one-line change in `Config.Events`. |
| **Compact-specific tray position** | The top-centre column is free on both sizes. Moving it would cost a `H.layout` hook in someone else's file for no gain. |

---

## OPEN QUESTIONS FOR THE HUMAN

1. **`CITY` as the label for the shared number.** It is the whole idea in four
   letters, and `CITY CLEANUP` / `CITY NEWS` / `CITY JOBS` already exist -- or
   is a fourth `CITY` one too many? The alternatives are `ALL` or `SERVER`
   (accurate, unlovely).
2. **`WE DID IT!` as the cooperative finish line.** Warmest option, and
   deliberately collective. Say the word if you would rather it named the event
   (`CITY GOAL REACHED!`) or the city (`THE CITY DID IT!`).
3. **Balloons using the `heart` icon** (shared with the ice cream truck). Fine
   for now, or do you want a balloon icon queued as a Blender job?
4. **Bystanders see the big line.** A player who collected nothing but was in
   the zone still gets `WE DID IT!`. Deliberate -- it is the city's moment --
   but it is a taste call about how much a non-participant should be told to
   celebrate.
5. **Automatic pickup instead of a prompt.** It removes the tap and makes the
   cash-drop race pure movement. It is also the first thing in the city that
   pays you without you pressing anything.
