# The PHONE -- UX / UI

> "also hte phone needs to look better like an actual phone ui sliding up form
> botom left"

Scope: the **container and the presentation** of the city phone. The data, the
row branches and the collect behaviour phase B just added are carried forward
untouched. No new art, no new icons, no change to `City.lua`.

---

## WHAT EXISTS ALREADY

| Where | What it means for this design |
|---|---|
| `CityEvents.lua:1284` `local dim, pcard = modalCard(560, 560, "PHONE")` | The whole problem in one line. It is the same centred card as SMINSKI MOTORS, TRAVEL, SHOP, TOWN and MENU, with the word PHONE written on it in 32pt. Nothing about it is a phone. **This line goes.** |
| `City.lua:704-733` `modalCard` | The convention I must keep even while I stop using the function: a **TextButton, `ZIndex = 20`, direct child of `H.root`**, tap-to-close, holder at `ZIndex 21` inside it, and a `fitScale` UIScale recomputed when it becomes visible. `City.anyModalOpen()` (`City.lua:1299`) literally scans `H.root` for a visible `TextButton` with `ZIndex == 20` -- so the shade must stay exactly that shape or the title screen stops knowing a screen is open. |
| `City.lua:1314` `City.hudVisible` | Sweeps **direct `Frame` children** of `H.root`. The phone's shade is a `TextButton`, so it is *not* swept -- today `City.hudVisible(false)` leaves the phone on screen. Fixed here with one explicit line in `E.step`, not by changing City.lua. |
| `City.lua:571` `act("PHONE", 214, C.sky, "bolt", ...)` | 160x56 at x 24-184, y 214-270. Colour **`C.sky`**, icon `bolt` (placeholder, HANDOFF §6). The phone must look like it belongs to this button; that is why the shell is `C.sky` and shares its x = 24 margin. |
| `CityEvents.lua:1289-1315` the 3 rows | 512x96 at y 92/196/300; `icon` 56, `title`, `clock`, `clue` (2 lines), `count` (1 line), `go` 120x56. Fixed positions written once at init. |
| `CityEvents.lua:1349-1389` `E.refreshPhone` | Sorts live events by `endT`, writes into the 3 fixed rows, hides the rest, and is re-run **every 0.25s while the shade is visible** (`E.step:1456`). Live numbers are already free. |
| `CityEvents.lua:725-760` `phoneClue` / `phoneCount` | Phase B's collect branch. `r.count` goes `C.inkSoft` -> **`C.ink`** for collect rows. `collect-events/ux.md` §6. **Carried forward verbatim.** |
| `CityEvents.lua:1338-1347` `E.go` | Sets `phone.shade.Visible = false` and then calls `UI.toast`. **`UI.toast` is `UI.popText` into `UI.hud` (`UI.lua:832`), and `UI.hud.Visible` is false in the city** -- so the "follow the glowing path!" confirmation after GO has never rendered. Fixed here. |
| `CityJobs.lua:49` `J.notify` | 320x66 cards, three at most, bottom-right above the driving buttons, `noteRoot` at x canvasW-364..-24. Never overlaps the phone's column. |
| `UI.lua:141` `UI.card` | holder + drop shadow + 9-sliced glossy `card` skin tinted by `BackgroundColor3`. ~27px effective corner radius at `sliceScale 0.42`. This is the phone shell, for free, with the shadow that makes it read as an object in front of the world. |
| `UI.lua:315` `UI.fit(w,h,margin)` | `min(1, (canvasW-m)/w, (canvasH-m)/h)`. Drives the two shell heights below. |
| `UI.lua:34` `UI.tween(o, t, props, style)` | The only tween helper. **`EasingDirection` is hard-coded to `Out`** -- there is no `In`, so every timing below is an Out curve. |
| `UI.lua:348` `UI.compact()` | `viewport.Y < 520 or (touch and viewport.Y < 700)`. Already read in `applyTraySize` (`CityEvents.lua:536`) and cached on `E.compact`. |
| `CityWeather.lua:201` `W.current()` | `{ hour, state, clock = "7:20 pm" }`. Reachable as `City.Weather.current()`. **The in-game time and the weather are currently displayed nowhere in the city HUD** -- grep for `clockText` returns the dev hook only. So putting them in the phone's status bar is new information, not a duplicate. |
| `Weather.lua:81-93` `STATES` | Names already written: `Clear` `Fair` `Overcast` `Rain` `Heavy Rain` `Sea Fog`, each with an `icon` from the existing set (`star` `clock` `heart` `bolt`). Free status-bar glyph, no new art. |
| `City.lua:623` `\u{25B8}` on CITY JOBS row 5 | Precedent for "a list row is itself tappable" in this codebase. |
| `LOOPS.md:74-84` | Three feeds go through the phone: `EVENT`, `JOB OFFER`, `CITY NEWS`. Phases C/D/G add a champion board, a daily hunt and NPC errands. The information architecture below is built so each is a new **section**, not a rebuild. |

**What I am reusing, unchanged:** the 3 row instances and every field on them,
`phoneClue`, `phoneCount`, the `endT` sort, `E.news` (6 deep), `spottedCount`,
`UI.card`, `UI.button`, `UI.icon`, `UI.text`, `UI.tween`, `UI.fit`,
`UI.compact`, the `C` palette, and the `ZIndex 20 / 21` modal convention.
**What I am adding:** one shell, one screen, one scrolling feed, two section
frames, a status bar, a home bar. No new component type, no new icon.

---

## THE DESIGN

### 1. What the object is

A **toy handset**: a chunky `C.sky` plastic shell with a speaker slot, a
camera dot, a cream screen with a status bar, and a chin with a home bar.
Concentric rounding -- shell ~27px (the `card` art), screen 20px -- which is
the single thing that makes a bezel read as a bezel. No glass, no notch, no
metal, no battery icon. It is the same object family as the game's cards; it
is just shaped like a phone and it arrives from the corner instead of the
middle.

There is **no "PHONE" title**. The shell is the title. Deleting that 32pt word
is the largest single readability gain in the screen.

### 2. The flow

1. Player taps **PHONE** (left column, y 214), or the **event strip**
   (`CityEvents.lua:1198`), or the **progress tray** (`:1232`). All three
   already call `E.openPhone()`; the signature does not change.
2. `E.openPhone()`:
   - if already open -> `E.refreshPhone()` and return (no re-tween).
   - `applyPhoneSize()` (first open, and on every viewport change).
   - `E.refreshPhone()` -- fill it *before* it is seen.
   - `shade.Visible = true`, `shade.BackgroundTransparency = 1`, body parked at
     `hidden`, `body.Rotation = -3`.
   - tween up (§3).
3. It sits open. The existing 0.25s tick keeps refreshing it: clocks count
   down, the collect counters move, the news list grows, the status-bar clock
   ticks.
4. Out, four ways:
   - **the home bar** at the bottom of the shell (220x50 target, captioned) --
     the phone's own control;
   - **tapping the world** (the shade) -- lighter than a normal modal but still
     tap-to-close, as every City modal is;
   - **GO** on a row, or tapping the row itself -- lays the path and puts the
     phone away, because you are meant to be looking at the city;
   - `City.hudOff` -> closed instantly, no tween (menu, transitions), and
     `E.leave()` closes it instantly too.

### 3. The slide-up

It comes out of the **bottom-left corner in the PHONE button's own column**.
Three cues do that work without touching `City.lua`:

- same left margin: **x = 24**, the exact margin of the left HUD column;
- same colour: shell `C.sky`, the PHONE button's colour;
- it **swallows the button**: at rest the shell occupies x 24-400, y 144-736 on
  a 760 canvas, and the PHONE button (x 24-184, y 214-270) is entirely inside
  that rectangle. The phone grows up out of the region that contains the
  button and covers it. On a 760 canvas the shell's top edge lands at **y 144**,
  which is inside the 142-150 gap between SHOP and TOWN -- so no button is cut
  in half.

| | value | why |
|---|---|---|
| `hidden` position | `UDim2.new(0, 24, 1, shellH + 12)`, AnchorPoint (0,1) | fully below the canvas edge; +12 clears the card's 7px drop shadow |
| `shown` position | `UDim2.new(0, 24, 1, -24)` | the game's standard 24px screen margin, shared with the shift strip and the drive buttons |
| travel | 628 desktop / 516 compact | |
| open slide | **0.26s, `Enum.EasingStyle.Quint`** | fast out of the gate, long soft landing; Quint reads as weight without overshoot. Back/Elastic would overshoot *upwards*, off the top of a short canvas |
| open tilt | `Rotation` **-3 -> 0, 0.30s, `Back`** | the toy bounce, taken on a property that cannot leave the screen. This is the only "physical" flourish and it is one property |
| open shade | `BackgroundTransparency` **1 -> 0.72, 0.20s, Quad** | see below |
| open sound | `Audio.play("Whoosh", 1.25, 0.5)` | mirrors `UI.open` (`UI.lua:809`) |
| close slide | **0.18s, `Quart`** | |
| close shade | **0.72 -> 1, 0.16s** | |
| close sound | `Audio.play("Whoosh", 0.85, 0.45)` | mirrors `UI.open(nil)` |
| `shade.Visible = false` | at **0.20s** after close starts, guarded by `phone.gen` | the shade must outlive the slide or the phone vanishes instead of leaving |
| instant close | set `hidden`, `Rotation = 0`, `shade.Visible = false`, cancel tweens | `City.hudOff`, `E.leave()` |

**The shade gets lighter: `BackgroundTransparency = 0.72`, not `modalCard`'s
0.5.** A phone you are holding up does not black out the street. At 0.72 the
city, the coin pill, the event strip and the three notifications in the
bottom-right all stay legible behind the wash, which is the point -- the phone
is a thing in your hand, not a room you walked into. It stays a full-screen
`TextButton` so it still blocks stray world clicks, still closes on tap, and
still answers `City.anyModalOpen()`.

`phone.gen` (an integer bumped on every open and close) guards the delayed
hide, exactly as `bigGen` guards the finish line (`CityEvents.lua:605`). A
reopen during a close must not be killed by the outgoing timer.

### 4. Geometry -- the shell

Two sizes, and the heights are chosen so that **`UI.fit` returns 1.0 on every
supported screen**. That is deliberate: a tall panel that gets fit-scaled to
0.8 on a phone and then multiplied by the 0.6 `UIScale` renders 12px body text
at 5.8 real pixels. Rather than scale a desktop phone down, compact gets a
**shorter phone with bigger text**.

| | desktop | compact |
|---|---|---|
| shell | **376 x 592** | **376 x 480** |
| `UI.fit(w, h, 44)` | 1.0 (desktop canvas height is always >= 760, see §8) | 1.0 (smallest compact canvas 530: (530-44)/480 = 1.01) |
| top chrome | y 0-34 | y 0-34 |
| screen | **344 x 500** @ (16, 34) | **344 x 388** @ (16, 34) |
| bottom chrome (chin) | y 534-592 | y 422-480 |

Why 376 wide: the prompt card is 470 wide, centred, bottom -- its left edge on
a 1280 canvas is x 405. 376 + 24 = **400, clearing it by 5px**. (376 is also
1 : 1.57 with the desktop height -- chunkier than a real phone, which is
correct for this world.)

**Shell face, local coordinates** (parent: the `UI.card` face, tinted `C.sky`):

| Name | Class | Size | Position | Colour / detail |
|---|---|---|---|---|
| `PhoneSpeaker` | Frame + UICorner 4 | 78 x 8 | (149, 13) | `C.sky:Lerp(C.ink, 0.45)` = rgb(103,132,154), ZIndex 3 |
| `PhoneCam` | Frame + UICorner 5 | 10 x 10 | (125, 12) | same colour, ZIndex 3 |
| `PhoneScreen` | Frame + UICorner **20** + UIStroke 2 | see table above | (16, 34) | `C.paper`; stroke `C.ink` at `Transparency 0.72`; **`ClipsDescendants = true`**; ZIndex 3 |
| `PhoneHomeBar` | Frame + UICorner 5 | 132 x 9 | (122, shellH - 40) | rgb(103,132,154), ZIndex 4 |
| `PhoneHomeHint` | TextLabel | 376 x 14 | (0, shellH - 26) | `tap the bar to close`, GothamBold **11**, `C.white` at `TextTransparency 0.35`, centred, ZIndex 4 |
| `PhoneHomeTap` | TextButton | **220 x 50** | (78, shellH - 58) | transparent, `Text = ""`, ZIndex 5, closes the phone |

Anything parented directly to a skinned card face needs `ZIndex >= 3`, because
`UI.skin` parents its two 9-slice images at the face's own ZIndex (same reason
`H.district` is ZIndex 3 in `City.lua:589`).

The chin is deeper than the forehead (58 vs 34) on purpose: it is where a toy
handset's chunk lives, and it gives the home bar a real 50px target.

### 5. Geometry -- the screen

Inside `PhoneScreen`, local coordinates:

| | desktop | compact |
|---|---|---|
| status band | y 0-32 | y 0-34 |
| divider 1 (344 x 2, `C.paper2`) | y 32 | y 34 |
| **feed** (ScrollingFrame, 344 wide) | **438**, y 34-472 | **324**, y 36-360 |
| divider 2 (344 x 2, `C.paper2`) | y 472 | y 360 |
| footer band | y 474-500 | y 364-388 |

**Status band** -- this is what says "phone" more than any bezel:

| Name | Content | Desktop | Compact |
|---|---|---|---|
| `PhoneClock` | `City.Weather.current().clock` -> `7:20 pm` | 140x22 @ (14,5), FredokaOne **15**, `C.inkSoft`, left | @ (14,6), **16** |
| `PhoneWxIcon` | `Weather.STATES[].icon` (`star`/`clock`/`heart`/`bolt`) | 20x20, anchor (1,0), (1,-118,0,6) | 22x22, (1,-122,0,6) |
| `PhoneWx` | `Weather.STATES[].name` -> `Clear` | 100x18, anchor (1,0), (1,-14,0,7), GothamBold **12**, `C.inkSoft`, right | 104x20, **13** |

If `City.Weather` or `current()` is unavailable, **hide both labels** -- never
print a placeholder time. Both are written in the existing 0.25s refresh; two
text writes per quarter second.

**Footer band** (pinned, never scrolls -- the collection hook must not scroll
away): `PhoneSpotted`, the existing `phone.spotted` label, text unchanged
`RARE SMINSKIS SPOTTED  3 / 15`, FredokaOne **14** desktop / **15** compact,
`C.gold`, at (14, 478) / (14, 366), 316 wide.

**No coin balance anywhere on the phone.** The HUD's coin pill is visible
through the 0.72 shade; a second one would be the duplicate the human has
already ruled out once.

### 6. The feed, and the answer to "apps or tabs?"

**Not tabs. One scrolling feed of sections.** Reasons, in order:

1. Tabs cost a 52px chrome row out of a 438px screen and hide two thirds of the
   phone behind a tap. With at most one headline event live at a time (the
   director never runs two, `LOOPS.md:56`) plus news, everything fits on one
   screen today -- tabs would be chrome protecting nothing.
2. A section list is the cheaper hook for phases C/D/G: a new feed is **one
   Frame appended with a `LayoutOrder`**, and `UIListLayout` reflows. No
   existing section is touched, which is exactly what the seventeen-features-
   into-five-archetypes lesson says to aim for.
3. Sections that are empty set `Visible = false` and vanish from the flow for
   free. That is also how the 0 / 1 / 2 / 3-event states re-lay themselves --
   the current fixed y 92/196/300 cannot do that, and it is why the empty state
   today sits at y 150 in the middle of a 560px card.

```
PhoneFeed (ScrollingFrame, 344 x 438, AutomaticCanvasSize = Y,
           CanvasSize = UDim2.new(), ScrollingDirection = Y,
           ScrollBarThickness = 4, ScrollBarImageColor3 = C.inkSoft,
           ScrollBarImageTransparency = 0.4, BackgroundTransparency = 1)
 +- UIListLayout   Padding 12, SortOrder = LayoutOrder
 +- UIPadding      L 10  R 20  T 8  B 10        -> child width 314
 +- PhoneSecNow    LayoutOrder 10   Size (1,0,0,0)  AutomaticSize = Y
 |   +- UIListLayout Padding 8
 |   +- PhoneNowHeader   314x20   "NOW IN TOWN"   FredokaOne 15  C.inkSoft  order 1
 |   +- PhoneBlurb       314x16   (existing phone.blurb)          order 2
 |   +- PhoneRow1..3     314xRH   (the existing 3 rows)           order 3,4,5
 |   +- PhoneEmpty       314x56   (existing phone.empty)          order 6
 +- PhoneSecNews   LayoutOrder 30   Size (1,0,0,0)  AutomaticSize = Y
     +- UIListLayout Padding 6
     +- PhoneNewsHeader  314x20   "CITY NEWS"     FredokaOne 15  C.inkSoft
     +- PhoneNews        314x84 desktop / 314x66 compact  (existing phone.news)
```

**Reserved `LayoutOrder`s, so later phases do not renumber anything:**

| Order | Section | Phase |
|---|---|---|
| 10 | `NOW IN TOWN` | B -- built now |
| 20 | `JOB OFFERS` | C (RUSH offers) |
| 30 | `CITY NEWS` | B -- built now |
| 40 | `TOP THIS HOUR` | C (champion board) |
| 50 | `TODAY'S HUNT` | D (daily 3) |
| 60 | `ERRANDS` | G (NPC errands) |

Live-and-urgent first, standings and history after, because the phone is
opened *during* an event nearly every time. Build **only 10 and 30 now**; the
contract is the `section(title, order)` helper and the rule that an empty
section hides itself. When a fourth section actually lands, the growth move is
a 28px **jump strip** of section chips under the status bar that sets
`PhoneFeed.CanvasPosition` -- not tabs. Deferred (§CUT).

### 7. The event rows -- re-laid-out, not rebuilt

Same instances, same fields, same code writing them. The 512-wide horizontal
row becomes a **stack**: header line (icon / title / clock), clue, count, then
GO on its own line bottom-right. That is what buys the clue back its 236px --
side by side, a 314px row would leave the text 174px and truncate a 60-
character clue.

| Field | desktop | compact |
|---|---|---|
| row frame (`C.paper2`, UICorner 14) | **314 x 138** | **314 x 156** |
| `r.icon` | 46x46 @ (10, 12) | 48x48 @ (10, 14) |
| `r.title` FredokaOne, left, `TextTruncate.AtEnd` | (64, 10), `(1,-146,0,22)` = 168w, **17** | (66, 10), `(1,-152,0,24)` = 162w, **18** |
| `r.clock` FredokaOne, right, anchor (1,0) | 72x22 @ `(1,-12,0,10)`, **17** | 76x24 @ `(1,-12,0,10)`, **18** |
| `r.clue` GothamMedium, wrapped, top-aligned, 2 lines | (64, 36), `(1,-78,0,34)` = 236w, **12** | (66, 38), `(1,-80,0,36)` = 234w, **13** |
| `r.count` GothamMedium, left, `TextTruncate.AtEnd` | (64, 70), `(1,-78,0,16)` = 236w, **12** | (66, 76), `(1,-80,0,18)` = 234w, **13** |
| `r.go` `UI.button`, icon `pin`, anchor (1,1) | **100 x 40** @ `(1,-12,1,-10)` = x 202-302, y 88-128, textSize 18 | **120 x 48** @ `(1,-12,1,-10)` = x 182-302, y 98-146, textSize 18 |
| `r.tap` (NEW) TextButton, `Text=""`, **`ZIndex = 0`** | `(1,1)` scale | same |

Worked clearances (the two that bite):
- `r.count` ends at y 86 (desktop) / y 94 (compact); `r.go` starts at y 88 / 98.
  **2px and 4px of air** -- the whole reason the rows grew from 96 to 138/156.
- `r.title` ends at x 232 / 228; `r.clock` starts at x 230 / 226 with a 2px gap
  (both truncate, so a long title eats its own tail, not the clock).
- longest clue in the game today, phase B's competitive line, 60 chars at
  GothamMedium 12 ~= 378px over 236 = 1.6 lines -> fits the 2-line box.
- longest `count`, `"5 bags left · Alexand… 6 · YOU 2"` after `clampName`,
  ~34 chars ~= 214px over 236 -> fits desktop. At compact 13 it is ~252px over
  234 and **would truncate**, so compact gets the short wording (§9), exactly
  the way `cityString`/`mineString` already spend words instead of pixels
  (`CityEvents.lua:395`).

`r.tap` at `ZIndex = 0` sits *under* the GO holder (ZIndex 1) so GO keeps its
own clicks, and under the labels -- which do not consume input, being inactive
`TextLabel`s. Tapping anywhere on the row does what GO does. When
`r.go.holder.Visible == false` (a FIND you already claimed, or an event with no
address yet) `r.tap` plays the kit's dull refusal, `Audio.play("Click", 0.6,
0.5)`, and does nothing else. That is the phone-list affordance the CITY JOBS
card already established, for 3 instances.

**Behaviour that must not change:** which branch fills `clue`/`count`
(`ev.def.kind == "collect"`), `r.count.TextColor3 = C.ink` for collect rows and
`C.inkSoft` for FIND, `r.clock` coral / inkSoft for live vs `in 0:45`,
`r.go.holder.Visible = not ev.mine and (ev.spot or ev.hint)`, the `endT` sort,
and the cap of 3.

### 8. Overlap arithmetic, worked

Canvas is `viewport / UIScale`, `UIScale = clamp(min(vx/1280, vy/760), floor,
1.25)` with floor 0.45 desktop / 0.6 touch. Two consequences worth stating
because they decide the numbers above:

- **Desktop canvas height is never below 760.** If the height ratio binds,
  canvasH = vy / (vy/760) = 760 exactly; if the width ratio or the floor binds,
  canvasH > 760. So the 592 shell never needs scaling.
- **Compact canvases are short and can be narrower than 1280.** Worked cases:
  an iPhone-class landscape 844x390 -> scale 0.659 -> canvas **1280 x 592**; an
  SE-class 667x375 -> scale floored at 0.6 -> canvas **1112 x 625**; the
  smallest case quoted in `collect-events/ux.md` §7, **1333 x 530**.

Phone at rest, desktop 1280 x 760: **x 24-400, y 144-736.**

| Element | Occupies | Result |
|---|---|---|
| left column WORK | y 22-78 | clear (phone top 144) |
| left column SHOP | y 86-142 | clear by 2px -- the shell's top edge lands in the 142-150 gap on purpose |
| left column TOWN, PHONE | y 150-270, x 24-184 | **covered** (intended: the phone comes out of PHONE) |
| CITY JOBS card (desktop x 24-324, y 284-574) | | **fully covered** -- better than a partial overlap; nothing is cut |
| shift strip (x 24-354, y 644-736) | | **fully covered**, and it shares the phone's exact 24/24 corner |
| district pill (x 480-800, y 18-82) | | clear |
| boost banner / event strip / progress tray (x 470-810, y 92-248) | | clear |
| coin pill (x 798-968, y 26-74) | | clear |
| notifications `noteRoot` (x 916-1256, y 320-560) | | clear -- and still readable through the 0.72 shade |
| driving buttons (x 926-1256, y 586-736) | | clear |
| **prompt card (x 405-875, y 602-706)** | | **clear by 5px** on a 1280 canvas. This is what sets the 376 width |

Narrower compact canvases: at canvasW 1112 the prompt (0.84 scale -> 395 wide,
centred) spans x 359-753, and the phone's x 24-400 **overlaps its left 41px**.
Worked, not assumed, and accepted: the phone is ZIndex 21 with a drop shadow so
it reads as being *in front*, and the prompt card is inert while any modal is
open. If the human dislikes the sliver, the fix belongs in City.lua as a
suppressor (see REQUESTS).

**The thumbstick.** The phone slides up into exactly where a mobile player's
left thumb lives; at rest on a 592-tall compact canvas it occupies x 24-400,
y 88-568, which contains the whole of Roblox's default touch thumbstick region
(roughly a 230-design-px square in the bottom-left). Worked through honestly:

1. **This is not a regression.** Every City modal, including today's phone, is
   a full-screen `TextButton` shade with `Active`/input capture, and
   `City.gui.DisplayOrder = 4` draws above `TouchGui` (DisplayOrder 0). The
   thumbstick is already dead and already covered whenever a modal is open.
2. **So the answer is to make the phone quick to put down, not to move it.**
   Compact gets the bigger home-bar target (220x50 at a 480-tall shell is
   132x30 real px at 0.6 scale), the shade stays tappable, and **GO closes the
   phone** -- so the one action that makes you want to walk hands the
   thumbstick straight back.
3. The alternatives were rejected: bottom-right belongs to the notification
   stack and the driving buttons; raising the phone clear of the thumbstick
   band pushes its top off a 530-tall canvas; and re-homing Roblox's
   thumbstick is another lane's file and a worse trade than a modal you dismiss
   in one tap.

Compact shell top edge lands wherever `canvasH - 24 - 480` falls (y 26 at 530,
y 88 at 592, y 121 at 625), so it can bisect a left-column button. Cosmetic
only -- everything it bisects is behind the shade and inert -- and it cannot be
pinned because the canvas height varies.

### 9. Every string, final

**Chrome**
| Where | String |
|---|---|
| status clock | `7:20 pm` (from `Weather.clockText`, already lower-case) |
| status weather | `Clear` / `Fair` / `Overcast` / `Rain` / `Heavy Rain` / `Sea Fog` (existing `STATES[].name`) |
| home bar caption | `tap the bar to close` |
| section header 1 | `NOW IN TOWN` |
| section header 2 | `CITY NEWS` |
| footer | `RARE SMINSKIS SPOTTED  3 / 15` (unchanged) |

Three new strings in total: `NOW IN TOWN`, `tap the bar to close`, and the
`3 of N` blurb variant below. Nothing here is story or character text.

**Blurb** (`phone.blurb`)
| State | String |
|---|---|
| 0 live | `""` (the empty state speaks instead) |
| 1 live | `1 thing happening in the city` |
| 2-3 live | `2 things happening in the city` |
| more than 3 live | `3 of 5 things happening in the city` |

The last row is new and small: today a fourth event is dropped silently.

**Empty / loading / error** (`phone.empty`, one label, three branches)
| State | String |
|---|---|
| `not E.synced` and nothing to show | `checking what's on...` |
| synced, nothing on | `Nothing on right now.` `\n` `Keep an eye out -- something always turns up.` (**unchanged**) |
| `E.syncFails >= 3` | `can't reach the city right now.` `\n` `it'll catch up in a moment.` |

**Rows** -- every string is phase B's, unchanged, plus one compact variant and
one new refusal:

| Line | Desktop | Compact |
|---|---|---|
| `clock` | `in 0:45` / `1:24` | same |
| FIND `clue` | `latestClue(ev)` / `ev.area` / `done -- nice one!` | same |
| FIND `count` | `Alex got there first · 3 so far` / `nobody is there yet -- be first` / `nobody has found it yet` | same |
| COLLECT `clue` | `40 balloons around Maple Row · walk over them to grab them` / `24 cash bags dropped on Maple Row · first one there keeps it` / `done -- the city did it!` | same |
| COLLECT `count` coop | `CITY 17 of 40  ·  YOU 1 of 3` | **`CITY 17/40 · YOU 1/3`** |
| COLLECT `count` coop, done | `CITY 40 of 40 · DONE · YOU 7` | **`40/40 · DONE · YOU 7`** |
| COLLECT `count` comp | `5 bags left · Alex 6 · YOU 2` | **`5 left · Alex 6 · YOU 2`** |
| COLLECT `count` comp, nobody | `24 bags out there · nobody has one yet` | **`24 out there · none taken yet`** |
| `go` | `GO` + `pin` icon | same |

**GO's feedback, which currently does not render at all.** `UI.toast` is
invisible in the city, so the two confirmations in `E.go` move to the
notification corner -- and go through **`City.Jobs.notify` directly, not the
module's local `notify()`**, so a path confirmation does not pollute CITY NEWS:

| Case | Call |
|---|---|
| a real spot | `City.Jobs.notify("pin", "PATH SET", def.title .. " · follow the green dots", C.mintDark)` |
| a hint only | `City.Jobs.notify("pin", "SEARCH THE AREA", "it was seen around " .. area, C.sky)` |
| no address yet | **the phone stays open** and the row's own `count` line holds `no address yet -- follow the clues` in `C.coral` for 1.2s |

The third is the important one: a refusal must not close the thing you are
looking at. It uses the same hold idiom as the tray (`holdCity`,
`CityEvents.lua:511`): `r.holdText` / `r.holdColor` / `r.holdUntil` on the row
table, honoured at the top of `refreshPhone`'s per-row write, and it needs no
new instance.

### 10. Every state

| State | What the phone shows |
|---|---|
| closed | `shade.Visible = false`, body parked at `hidden`, rotation 0 |
| opening | 0.26s slide + tilt; content already filled before the first frame is drawn |
| open, not synced | header, `checking what's on...`, CITY NEWS (`quiet so far`) |
| open, 0 events | header, the empty copy, CITY NEWS. Feed canvas ~218 in a 438 viewport -> **no scroll** |
| open, 1 event | ~296 desktop / ~312 compact -> **no scroll** |
| open, 2 events | ~448 desktop -> scrolls ~10px |
| open, 3 events | ~588 desktop / ~640 compact -> scrolls; the 4px bar is the only indicator, which is correct for a phone |
| open, >3 events | first 3 by `endT`; the blurb says `3 of 5 things happening in the city` |
| a row you already did (FIND, `ev.mine`) | `clue` = `done -- nice one!`, no GO, row tap gives the dull click |
| a collect event that reached its goal | `clue` = `done -- the city did it!`, `count` = `CITY 40 of 40 · DONE · YOU 7` in `C.ink` |
| an event with no address | GO hidden; row tap -> the 1.2s coral hold in `count` |
| news empty | `quiet so far` (unchanged) |
| sync failing | `can't reach the city right now.` -- and it keeps retrying on the existing tick, so it heals itself |
| `City.hudOff` | closed instantly, **checked every frame** at the top of `E.step`, not inside the 0.25s gate (a quarter second of phone over the title menu is visible) |
| leaving the city | `E.leave()` closes it instantly |
| viewport change while open | `applyPhoneSize()` re-reads `UI.compact()`, re-applies the metric table, recomputes `fitScale` and both positions |

### 11. Instance budget

| Block | Instances |
|---|---|
| shade | 1 |
| shell (`UI.card` holder + shadow + face + 2 skin images) + `fitScale` | 6 |
| speaker, camera (+ corners) | 4 |
| screen (+ corner, stroke) | 3 |
| status bar (clock, wx text, wx icon, divider) | 4 |
| feed (ScrollingFrame + layout + padding) | 3 |
| `PhoneSecNow` (+ layout, header, blurb, empty) | 5 |
| **3 rows** (frame, corner, icon, title, clock, clue, count, tap = 8; `UI.button` ~= 12) | **60** |
| `PhoneSecNews` (+ layout, header, news) | 4 |
| footer (divider, spotted) | 2 |
| home bar (pill, corner, hint, tap) | 4 |
| **total** | **~96, built once in `E.init`** |

Today's phone is ~72 (modalCard's 10 + 3 rows + 6 labels), so this is **+24
instances, one time**. Nothing is created at open, at refresh, or per event:
the row count is fixed at 3 forever and `E.refreshPhone` only writes text and
`Visible`. A city with 40 balloons and 6 news items allocates zero GUI here.

---

## NUMBERS

| Tunable | Value | Reasoning |
|---|---|---|
| shell w | 376 | 376 + 24 = 400, clears the prompt card's x 405 on a 1280 canvas by 5px |
| shell h desktop | 592 | top edge lands at y 144 on a 760 canvas -- inside the 142-150 gap between SHOP and TOWN, so no button is bisected; and `UI.fit` = 1 |
| shell h compact | 480 | 530 (smallest canvas) - 24 bottom - 26 top = 480; keeps `UI.fit` = 1 so nothing is scaled into illegibility |
| `UI.fit` margin | 44 | the smallest margin that still returns 1.0 at 530; a bigger margin would start shrinking the phone for no reason |
| left margin | 24 | the left HUD column's margin -- the "it came out of that button" cue |
| bottom margin | 24 | the game's standard, shared with the shift strip and drive buttons |
| screen inset | 16 / 34 / 58 | a 16px side bezel, a 34px forehead, a 58px chin; asymmetric because a toy handset has a chunk at the bottom, and it gives the home bar a 50px target |
| shell corner / screen corner | ~27 (card art) / 20 | concentric rounding is what makes a bezel read as a bezel |
| shade transparency | 0.72 | `modalCard` uses 0.5; a phone in your hand does not black out the street, and the notification corner must stay readable |
| slide open | 0.26s Quint | fast start, long landing; no overshoot to run off a 530-tall canvas |
| tilt open | -3deg -> 0, 0.30s Back | the one toy flourish, on the one property that cannot leave the screen |
| slide close | 0.18s Quart | shorter than the open -- putting something away should not cost you time |
| shade hide delay | 0.20s | > the 0.18 slide, so the phone leaves rather than vanishes |
| row h | 138 / 156 | the smallest height that gives `count` and GO 2px / 4px of air on a 314-wide row |
| GO | 100x40 / 120x48 | 40 design px is a mouse target; compact needs 48 (= 29 real px at 0.6, above the game's own 56x0.6 = 34 floor once you account for the 120 width) |
| clue lines | 2 | 60 chars at 12px over 236 = 1.6 lines; 3 lines would cost 17px per row for nothing |
| feed padding | 12 between sections, 8 within, L10 R20 | R20 leaves the 4px scrollbar a gutter instead of sitting on a row |
| scrollbar | 4px, `C.inkSoft`, transparency 0.4 | visible enough to say "there is more", quiet enough not to be furniture |
| news lines | 4 desktop / 3 compact | 3 lines keeps a 1-event compact feed under 324 and off the scrollbar |
| status text | 15/16 clock, 12/13 weather | a status bar is meant to be quiet; these are the smallest sizes already shipped (the notification sub-line is 13) |
| ZIndex | shade 20, body 21, face children 3, home bar 4-5, `r.tap` 0 | 20/21 is `modalCard`'s contract (`City.anyModalOpen` depends on it); 3 clears `UI.skin`'s images; `r.tap` at 0 sits under GO |

---

## EDGE CASES

- **Empty server / nothing live.** The commonest state. Section 1 shows the
  header + the empty copy, CITY NEWS shows `quiet so far`, the footer still
  shows the collection count -- so the phone always has something true on it
  and never opens blank.
- **Not synced yet / a failed `Events state` call.** `checking what's on...`,
  and after 3 failures `can't reach the city right now.` The existing tick
  retries, so it heals without the player doing anything. The bug this avoids
  is the current one: a failed sync is indistinguishable from a quiet city.
- **One player.** Nothing changes; the collect `count` line says
  `24 bags out there · nobody has one yet` until you take one.
- **A scripted / dev-started event** (`EventsDev:InvokeServer`). Arrives
  mid-life with `trayFresh`; the phone reads the same fields and shows it
  immediately -- no first-frame animation to catch up on, because the phone has
  none.
- **Mid-event join.** The row's clock, clue and counts are all computed from
  server fields at refresh time, so a joiner sees the truth on the first tick.
- **Event ends while the phone is open.** `onEnd` removes it from `E.list`; the
  next 0.25s refresh hides that row and `UIListLayout` closes the gap. If it
  was the only one, the empty state appears in place. No hole, no stale row.
- **A 4th event starts while the phone is open.** The blurb switches to
  `3 of 4 things happening in the city`; the rows re-sort by `endT`, so the row
  under your finger can change identity between frames. Accepted -- it is the
  existing sort, GO is idempotent, and the worst case is a path to the wrong
  event, which is one tap to redo.
- **Reopening during the close tween.** `phone.gen` invalidates the pending
  hide; the slide is cancelled and restarted from wherever it is.
- **`City.hudVisible(false)` with the phone open** (MENU, or the title opening
  a screen over the menu). The per-frame `City.hudOff` check closes it
  instantly. Without this the phone sits over the title menu, because
  `hudVisible` only sweeps `Frame` children and the shade is a `TextButton`.
- **Leaving the city with the phone open.** `E.leave()` closes it instantly, so
  a return trip does not start with a phone on screen.
- **`City.Weather` missing or mid-transition.** Both status labels hide. The
  status bar is allowed to be empty; it is not allowed to lie about the time.
- **A 20-character display name in `count`.** Already handled by `clampName`
  (10 chars + ellipsis, `CityEvents.lua:51`), and `TextTruncate.AtEnd` is now
  set on `count` as a second line of defence.
- **Rotated GUI and input.** The open tilt settles to 0 in 0.30s, and Roblox
  hit-tests rotated GuiObjects correctly, so a tap landing during the tilt
  still hits the right row.

---

## NEEDS FROM OTHER LANES / REQUESTS FOR OTHER OWNERS

Nothing here blocks the build.

1. **`client-engineer` (this file's builder).** Everything above lives in
   `CityEvents.lua`. `City.lua` is not touched.
2. **`audio`.** I have specified `Whoosh` at 1.25/0.5 opening and 0.85/0.45
   closing, mirroring `UI.open`. If the phone deserves its own two-note
   slide-and-click, that is your call; the hooks are `E.openPhone` /
   `E.closePhone`.
3. **Owner of `City.lua`** (not me, and not required for this):
   - an optional `City.suppressPrompt(bool)` so *any* modal can hide the prompt
     card while it is up -- it would remove the 41px sliver in §8 and help the
     dealer, TRAVEL and SHOP equally;
   - when a real phone icon exists, swap `act("PHONE", 214, C.sky, "bolt", ...)`
     at `City.lua:571` to it.
4. **Blender / art pipeline.** A `phone` icon (a chunky handset silhouette,
   matching the existing 24) would finish the HUD button -- already owed per
   `HANDOFF.md` §6 item 5. **This design does not need it**: the phone's
   identity comes from its shell, not from an icon, and the status bar reuses
   the weather states' existing `star`/`clock`/`heart`/`bolt`.
5. **`narrative-designer`.** Nothing. The three strings I added are interface
   chrome; the CITY NEWS bodies keep coming from `notify()`'s callers.

---

## WHAT CHANGES IN `CityEvents.lua`, AND WHAT DOES NOT

Phase B is at its QA gate, so here is the blast radius.

**Changes**

| # | Where | Change |
|---|---|---|
| 1 | `E.init`, lines **1284-1326** | The whole phone block is replaced. `modalCard(560, 560, "PHONE")` is no longer called. The 3 rows are built with the new metrics and parented to `PhoneSecNow` instead of `pcard`; `r.tap` is added. |
| 2 | new `applyPhoneSize()` | One metric table (`DESK` / `COMPACT`, ~16 fields), applied to the shell, screen, feed, footer, status bar and the 3 rows; then `fitScale.Scale = UI.fit(w, h, 44)` and both slide positions recomputed. Same shape as the existing `applyTraySize`. |
| 3 | `applyTraySize`'s `ViewportSize` connection, **1331-1332** | also calls `applyPhoneSize()`. |
| 4 | `E.openPhone`, **1390-1393** | guard against double-open, `applyPhoneSize()` on first open, then the slide + shade + tilt tweens and the sound. |
| 5 | new `E.closePhone(instant)` | the reverse, with `phone.gen`. |
| 6 | `E.go`, **1338-1347** | `phone.shade.Visible = false` -> `E.closePhone()`; the two `UI.toast` calls -> `City.Jobs.notify`; the "no address yet" toast -> a 1.2s row hold that leaves the phone open. |
| 7 | `E.refreshPhone`, **1349-1389** | the per-row writes are **unchanged**; added: the row hold check, section `Visible`, the `3 of N` blurb branch, the loading / error empty text, the status-bar clock and weather, and `math.min(E.compact and 3 or 4, #E.news)` for the news lines. |
| 8 | `phoneCount`, **743-760** | gains `E.compact and <short> or <long>`, exactly as `cityString`/`mineString` already do. |
| 9 | `E.step`, **1399** | one line at the top, before the 0.25s gate: `if City.hudOff and phone.open then E.closePhone(true) end`. |
| 10 | `E.leave`, **1461** | `E.closePhone(true)`. |
| 11 | `E.sync`, **975-983** | `E.syncFails` incremented on failure, cleared on success. (Optional; only the error string depends on it.) |

**Does not change**

`phoneClue` · the `ev.def.kind == "collect"` branch selection · `r.count`'s
`C.ink` for collect rows · the row field set and every string in it ·
`ev.mine` hiding GO · the 3-row cap and the `endT` sort · `spottedCount` ·
`E.news` (6 deep) and its `•` line format · the countdown strip · the progress
tray · `renderTray` / `renderClock` / the holds / the finish moment · drawing,
pooling, claiming, `stepCollect`, `E.prompt` · every remote and every server
field · **`City.lua` (zero edits)** · `UI.lua` (zero edits) · `Art.lua` (zero
edits).

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **Tabs / an app grid home screen** | 52px of chrome guarding one screen's worth of content, and an extra tap between the player and the event they opened the phone for. Revisit when there are 4+ live sections -- and then as a 28px jump strip that scrolls the feed, not as tabs. |
| **The `JOB OFFERS`, `TOP THIS HOUR`, `TODAY'S HUNT`, `ERRANDS` sections** | Phases C/D/G own them. Their `LayoutOrder`s are reserved so they land without touching anything built now. Building empty frames for them today is 8 instances doing nothing. |
| **A hanging phone charm** (cord + `disc`-skinned bead on the bezel) | Very on-brand, 3 instances, zero information. Polish pass. |
| **Battery / signal fiction** | A fake 100% is a lie you have to maintain. The slot is spent on the in-game clock and the weather, which are both real and both new to the UI. |
| **Unread dots per section** | Needs a "seen" timestamp per feed and a save field. Wait until there is a feed the player can actually miss. |
| **Drag-to-dismiss** | Real gesture handling for a case the home bar and the shade already cover twice. |
| **A scroll-fade gradient at the feed edges** | Two `UIGradient`s to solve what a 4px scrollbar already says. |
| **`E.syncFails` error copy** | If the engineer would rather not touch `E.sync`, ship with just the `checking what's on...` branch; the error string is the nicety, the loading state is the fix. |
| **Animating the PHONE button itself** (a press, a badge dot) | It lives in `City.lua`, another lane's file. The phone covering the button does the job. |

---

## OPEN QUESTIONS FOR THE HUMAN

1. **Shell colour: `C.sky` (the PHONE button's own colour) or `C.lav`?** I have
   specced sky, because matching the button is what makes the phone feel like
   it came out of it. Lav would be a more distinct object but breaks that link.
2. **Should the status bar carry the in-game clock and the weather?** It is the
   first time the time of day appears anywhere in the UI. I think a phone is
   the right home for it and it is free (`City.Weather.current()`), but it is
   new information in the game and therefore your call.
3. **Should GO close the phone (today's behaviour, kept) or keep it open with
   the row switching to `PATH SET`?** Closing gets you back to the city and
   hands a mobile player their thumbstick back; staying open lets you set a
   path and then read the other rows.
4. **Does `tap the bar to close` stay forever, or only for a player's first few
   opens?** It is the least phone-like thing on the phone, and the most useful
   for a player who has never seen a home bar.

---

## QA SHOULD CHECK

Play-mode screenshots come back **solid magenta** on this project
(`HANDOFF.md` §2), so every check below is numeric. Every instance in this spec
has a `Name`, so QA can reach them by path. Root:

```
G = Players.LocalPlayer.PlayerGui.SminskiCityUI          -- City.gui
R = G:GetChildren()[1]                                   -- H.root (the UIScale'd frame)
S = R.PhoneShade            -- TextButton, ZIndex 20
B = S.PhoneBody             -- the UI.card holder, ZIndex 21
```

Open it with `SminskiRemotes` / the dev hooks: start an event with
`SminskiRemotes.EventsDev:InvokeServer("cashdrop", true)`, and force the sky for
the status-bar check with the runner hook `city("sky", 19.4)` ->
`PhoneClock.Text == "7:24 pm"`.

**Geometry (desktop, 1280x760 canvas, `UIScale` = 1)**

1. `B:FindFirstChildOfClass("UIScale").Scale == 1.0` **exactly**, on every size
   tested. If it is ever < 1 the heights in §4 are wrong and text is being
   scaled down twice.
2. Closed: `B.AbsolutePosition.Y >= camera.ViewportSize.Y` (it is off-screen,
   not merely invisible), and `S.Visible == false`.
3. 0.4s after `City.Events.openPhone()`:
   `B.AbsolutePosition` ~= `(24, 144)` +/- 2 (design px x `UIScale`; remember
   `IgnoreGuiInset` makes `AbsolutePosition.Y` inset-relative), `B.AbsoluteSize`
   ~= `(376, 592)` x scale, `B.Rotation == 0`.
4. `S.BackgroundTransparency == 0.72` +/- 0.01 after 0.3s (the tween end-state,
   not the start value).
5. `B.AbsolutePosition.X + B.AbsoluteSize.X` **<** `H.prompt.AbsolutePosition.X`
   on a 1280-wide canvas -- the 5px prompt-card clearance.
6. `GetGuiObjectsAtPosition(promptLeftEdgeX + 2, promptCentreY)` must **not**
   return any instance whose name begins `Phone`.
7. `GetGuiObjectsAtPosition(x, y)` at the centre of the SHOP button must return
   the SHOP button and **no** `Phone*` instance (the top edge lands in the
   142-150 gap).

**The feed and the rows**

8. With 1 live event: `PhoneRow1.Visible == true`, `PhoneRow2/3.Visible ==
   false`, and `PhoneFeed.AbsoluteCanvasSize.Y <= PhoneFeed.AbsoluteSize.Y`
   (no scrollbar for the common case).
9. With 3 live events: the three rows' `AbsolutePosition.Y` are **strictly
   increasing** with an 8px design gap (this is the `UIListLayout` working;
   the old build used fixed y 92/196/300), and
   `PhoneFeed.AbsoluteCanvasSize.Y > PhoneFeed.AbsoluteSize.Y`.
10. In a row: `RowCount.AbsolutePosition.Y + RowCount.AbsoluteSize.Y <
    RowGo.AbsolutePosition.Y` -- the 2px (desktop) / 4px (compact) clearance
    that set the row height.
11. `RowClue.TextFits == true` and `RowCount.TextFits == true` for the longest
    phase-B strings (a competitive cash drop with a 10-char leader name).
12. `RowCount.TextColor3` is `C.ink` (58,62,50) on a **collect** row and
    `C.inkSoft` (128,128,112) on a **FIND** row -- phase B's behaviour, carried
    forward.
13. `RowGo.Visible == false` on a FIND event you have claimed (`ev.mine`).

**Visibility chain and the modal contract**

14. Full ancestor chain while open: `S.Visible` and `B.Visible` and
    `R.Visible` and `G.Enabled` all true.
15. `City.anyModalOpen() == true` while open, `false` after close -- it scans
    `H.root` for a visible `TextButton` with `ZIndex == 20`, so this proves the
    shade kept the contract.
16. `City.hudVisible(false)` -> within 0.1s `S.Visible == false`. This is the
    bug the current build has (`hudVisible` only sweeps `Frame` children).
17. Close, then reopen within 0.1s -> `S.Visible` is still true 0.5s later
    (the `phone.gen` guard; a stale delayed hide must not kill the reopen).
18. `City.Events.leave()` with the phone open -> `S.Visible == false`.

**Compact**

19. Force a compact viewport (`viewport.Y < 520`, or touch emulation with
    `Y < 700`) and re-check 1, 3, 8, 10, 11: `B.AbsoluteSize` ~= `(376, 480)`
    x scale, `UIScale` still 1.0, row height 156, `RowCount.TextFits == true`
    with the **short** wording.
20. `PhoneNews.Text` has 3 lines on compact, 4 on desktop.
21. `PhoneHomeTap.AbsoluteSize` >= `(132, 30)` **real** pixels at the 0.6 scale
    floor.

**Tween end-states (the things a screenshot would have caught)**

22. `B.Position` after open == `UDim2.new(0, 24, 1, -24)` exactly, and after
    close == `UDim2.new(0, 24, 1, shellH + 12)` exactly -- not merely "near".
23. `B.Rotation` is 0 (not -3) 0.4s after open, and 0 after close.
24. Open -> close -> open five times in a row and re-check 3, 4 and 22: no
    drift, no stacked tweens on `Position`.
