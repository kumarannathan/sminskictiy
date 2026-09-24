# UI inventory — handoff for a redesign

Everything that draws on screen today, where it lives, and what is load-bearing.
Written for someone coming to this cold with a brief to redesign it.

Survey date: 2026-09-22. Verify a named function still exists before relying
on it.

---

## 1. Read this first: there are two UIs in the repo

The repo started life as **SminskiRunner** — an endless runner with a bedroom
hub — and the city grew inside it. Both UIs are still in the build.

| | Lives in | Status |
|---|---|---|
| **City UI** | `City.lua` + the `City*.lua` modules | **This is the game.** Redesign this. |
| Runner / Hub UI | `UI.lua` home page + modals, `Hub.lua`, `Park.lua` | Legacy mode, still reachable, not the scope |

The catch: **`UI.lua` is both.** It holds the legacy runner screens *and* the
shared component library the city is built out of — `UI.button`, `UI.card`,
`UI.text`, `UI.icon`, the colour table `C`, the scaling helpers. The city
requires `UI` and draws itself with those pieces.

So a redesign has two separable halves:

- **the component library** (`UI.lua` lines 13–285) — changing this restyles
  the entire game at once, city and legacy both
- **the city's own screens and layout** — `City.lua` and friends

Scope is the **downtown vertical slice** (`docs/ROADMAP.md`). The runner
screens can be left alone.

---

## 2. The design system as it stands

### Palette — `UI.lua:16`, exported as `UI.C`

| Token | RGB | Used for |
|---|---|---|
| `paper` | 252, 248, 238 | card and panel backgrounds |
| `paper2` | 242, 236, 220 | secondary / neutral buttons (MENU, HELP, BACK) |
| `ink` | 58, 62, 50 | all body text, every stroke |
| `inkSoft` | 128, 128, 112 | subtitles, secondary rows, scrollbars |
| `mint` | 150, 205, 140 | the primary action colour — GO, HOME, confirm |
| `mintDark` | 98, 150, 90 | mint's pressed base |
| `coral` | 255, 125, 110 | close, destructive, TOWN, alerts, toasts |
| `gold` | 245, 196, 80 | money, SHOP, HONK |
| `sky` | 140, 190, 240 | MAP, PHONE, social / together |
| `lav` | 190, 165, 240 | WORK, GET OUT |
| `white` | — | button label text |

Everything in the game is one of these eleven. There is no semantic layer
(no `danger` / `success` / `surface-2`) — colour is assigned per button by
hand at the call site.

### Type — `UI.lua:29`

- **Display:** `FredokaOne` — all button labels, titles, numbers, place names
- **Body:** `GothamMedium` — paragraphs, descriptions
- **Bold:** `GothamBold` — subtitles, small caps rows, metadata

Sizes in use run 12 / 13 / 14 / 16 / 18 / 20 / 24 / 28 / 30 / 34 / 40 / 42.
No scale is defined anywhere; each number is typed at the call site.

### Rendered art — `Art.lua`, sources in `art/blender/uikit.py`

The UI is **not flat colour**. Every surface is a Blender-rendered glossy
candy skin, uploaded as a Roblox image id and applied as a **tintable
9-slice + an untinted gloss overlay** (`UI.skin`, `UI.lua:99`). The frame's
`BackgroundColor3` drives the tint, so one render serves all eleven colours.

Four surfaces: `pill` (512×160, corner 80) · `key` (512×160, corner 36) ·
`card` (512×512, corner 64) · `disc` (256×256, corner 128).

**23 icons**, also Blender-rendered: bag, bolt, capsule, chart, clock, coin,
crown, dog, friends, gear, heart, hourglass, house, lock, magnet, paw, pin,
play, shield, shirt, star, trophy, x2. Plus `Art.logo`, `Art.hero`, and 11
glossy character portraits.

> Re-rendering these is a Blender job (`art/blender/uikit.py`), then re-upload
> and update the ids in `Art.lua`. A redesign that changes surface shape,
> corner radius or gloss **has to go back through Blender** — it is not a CSS
> change. Budget for that.

### Components — all in `UI.lua`

| Component | Line | Notes |
|---|---|---|
| `button` | 152 | The signature element. A glossy face sitting on a darker base, `depth` 5px default; press physically pushes the face down onto the base, scales to 0.96, and plays a click. Options: `color`, `size`, `pos`, `anchor`, `icon`, `textSize`, `textColor`, `pill`, `depth`, `radius`, `releasePitch`. Returns `{holder, face, art, setEnabled, setColor, setText, press}`. |
| `card` | 141 | Holder + soft drop shadow (offset 4,7, 72% transparent) + a 9-sliced `card` face. |
| `pill` | 242 | Rounded capsule with an icon hanging off the left edge. The coin and capsule readouts. |
| `modal` | 777 | Legacy screens only: title, X, conditional ◀ BACK, body frame. Registered in `screens[name]`. |
| `modalCard` | `City.lua:783` | **The city's own modal.** Dim layer (50% black, tap-outside-to-close) + card + `UI.fit` scale. City screens use this, *not* `UI.modal`. |
| `scroller` | 859 | `ScrollingFrame` + `UIGridLayout`, 6px bar, auto canvas. |
| `sminskiViewport` | 264 | Live 3D character in a `ViewportFrame`, posed. |
| `icon` / `text` / `frame` / `corner` / `stroke` / `pad` / `tween` / `fmt` | 41–262 | primitives |

### Motion

One easing vocabulary, applied consistently: `Quad Out` for hovers and fades,
**`Back` for anything arriving or releasing** — modals scale in 0.85→fit over
0.28s with Back, buttons spring back on release. Press-down is a fast 0.06s.
Every button press plays `Audio.play("Click", …)` at a pitch that varies by
action; a disabled press plays a dull low click.

---

## 3. Layout and scaling — the part that will bite

There is no auto-layout. **Almost every element is absolutely positioned in
offset pixels** against a virtual canvas, then the whole canvas is scaled.

- Design canvas is **1280 × 760**.
- `UIScale` on the root: `clamp(min(vw/1280, vh/760), 0.6 on touch / 0.45 on
  desktop, 1.25)`. See `City.lua:527` and `UI.lua:310`.
- `UI.fit(w, h, margin)` — the most a `w × h` card can scale and still fit.
  Phones are held at 0.6 so buttons stay finger-sized.
- `UI.fitPage(f, designW, designH)` — same for a full-bleed page.
- `UI.compact()` — *not* "is touch". It means a phone held sideways or a very
  short window. When true: the jobs card folds to its header and moves
  top-left clear of the thumbstick, the place pill drops its second line, the
  prompt shrinks, keyboard hints go, and the driving buttons lift clear of
  Roblox's jump button.

Consequence for a redesigner: **element positions are interlocked by hand-
computed arithmetic**, and the comments say so. The capsule pill's comment at
`City.lua` is 20 lines of why it is 120px wide at `(1, -184)` — 140 would land
inside the coin pill. Moving one thing in the HUD moves the maths for its
neighbours. A redesign that changes the HUD grid should expect to redo that
arithmetic rather than nudge values.

### ScreenGui layering (`DisplayOrder`)

```
1000  SminskiTitle        loading + menu, ReplicatedFirst
  30  CityHome fade
  20  Tour
  12  Garden
   6  Park
   5  UI.lua (runner)
   4  City / Hub
```

Inside the city HUD, the dim layer is `ZIndex 20` and the modal card `21`;
`ZIndexBehavior` is `Sibling`.

---

## 4. Screen inventory

### 4.1 Title / loading — `SminskiTitle.client.lua` (1082 lines)

Runs from `ReplicatedFirst`, before anything else replicates. Three phases in
one script: **LOADING** (five plates of key art, logo across the top, a
progress bar, PLAY arriving 15s in) → **MENU** (built on demand, over a live
camera flying slowly over the real downtown) → **GONE**.

The bar is simulated on a fixed 15 seconds, deliberately — it used to be wired
to real streaming, which gave the slowest phone the longest bar and told it so
in percentages. Menu options: START/RESUME, HOUSE, WORK, SHOP, SETTINGS.

### 4.2 City HUD — `City.lua:494–780`

Persistent, `ScreenGui` named `SminskiCityUI`.

**Navigation column, right, 150×56 each, 64px pitch from y=22:**
MENU (paper2/gear) · HOME (mint/house) · MAP (sky/pin) · HELP (paper2/star)

**Action column, left, 160×56, same pitch:**
WORK (lav/chart) · SHOP (gold/bag) · TOWN (coral/friends) · PHONE (sky/bolt)

The split is intentional: **anything that moves you is on the right, anything
that opens a screen about the city is on the left**, so a thumb never hunts.

**Readouts:**
- Coin pill — 170 wide, right-anchored at `(1, -312)`
- Capsule pill — 120×48 at `(1, -184)`, the daily-capsule meter
- Place pill (`H.where`) — district name in FredokaOne 24 + street in
  GothamBold 14 underneath
- Jobs card (`H.jobs`) — 5 rows, folds to its header; row 5 opens the
  business card. Starts folded on phones, open on desktop.

**Contextual bars:**
- Prompt bar (`H.prompt`) — icon 84×84, title, subtitle, a mint **GO** button
  160×62. The thing that appears when you walk up to anything.
- Drive bar (`H.drive`) — GET OUT (lav) · HONK (gold) · MY CAR (mint) + a
  speed readout
- Boost banner, race text, bottom hint line
- Curtain — full-screen "ARRIVING IN SMINSKI CITY…" over the stream-in

`City.hudVisible(false)` hides the HUD additively (it records what it hid, so
nested hides don't strand it) — a real bug that was fixed once already.

### 4.3 City modals — all via `City.modalCard(w, h, title)`

| Screen | Size | File |
|---|---|---|
| SMINSKI MOTORS (car dealer) | 760×540 | `City.lua:816` |
| SMINSKI ARCADE (way into other modes) | 720×520 | `City.lua:892` |
| TRAVEL (destination list, one tap) | 720×620 | `City.lua:939` |
| SHOP (tabs: coins / boosts / passes) | 800×640 | `City.lua:1009` |
| TOWN (3-tab directory of people on the server) | 760×620 | `City.lua:1184` |
| WORK (chooser: your shops, or a shift) | 560×492 | `City.lua:1339` |
| MENU | 520×420 | `City.lua:1441` |
| CITY MAP | 820×600 | `City.lua:1473` |
| MY BUSINESSES (the business card) | 720×(rows) | `City.lua:2197` |
| JOB CENTER | 820×660 | `CityJobs.lua:157` |
| MY RESTAURANT / STOCKROOM / MENU | 640×600 / 620×620 / 600×560 | `CityTycoon.lua` |
| Welcome tour — 6 cards | — | `CityGuide.lua:33` |

### 4.4 The phone — `CityEvents.lua:2088+`

A toy handset that slides up out of the bottom-left over a 72% dim. 376 wide,
height from `PHONE_M.desk` / `PHONE_M.compact`. Shows what's happening in the
city right now with a GO for each.

**Built once: ~97 instances, and nothing is allocated at open, at refresh or
per event.** The row count is fixed at 3 forever; refresh only writes `Text`
and `Visible`. A city with 40 balloons and 6 news items allocates no GUI at
all. Keep that property — it is a `performance.md` requirement, not an
accident.

### 4.5 Other in-world / contextual UI

- **Notification stack** — `CityJobs.lua:55`, 320×66 cards, bottom right. One
  system for every job. `docs/LOOPS.md` treats this as the phone's inbox.
- **Shift strip** — `CityJobs.lua:98`, 330×92 bottom-left while clocked in
- **Event countdown strip** — `CityEvents.lua:2251`, 340×50, top centre
- **Event big line** — 620×48 at y=256, FredokaOne 34, mint, 3px stroke
- **Grocery basket** — `CityGrocery.lua:53`, 300×44, top centre
- **First-visit house card** — `CityHome.lua:668`, 400×176, top right
- **The green dot** — one small Smiski-green light hovering over whatever you
  can interact with (`City.lua:1976`)
- **Wayfind ribbon** — `CityWayfind.lua`, drawn *on the road* in the gutter
  lane rather than floating, so it reads at Smiski eye level
- **House nameplates + carports** — `CityHome.lua:46`, BillboardGuis
- Kitchen, tycoon, venue and hangout prompts — `CityKitchen`, `CityTycoon`,
  `CityVenues`, `CityHangouts`

### 4.6 Legacy runner UI — `UI.lua` (probably out of scope)

Home page, run HUD (chaos tiers, speed lines, danger vignette, coin bump,
banners, countdown), revive prompt, results with count-up, multiplayer
(menu, lobby, queue bar, squad HUD, down overlay, results), and nine
registered modals: `shop` (TOY SHOP, 900×590), `collection`, `daily` (7-day
calendar), `liveruns`, `challenges`, `stats`, `settings`, `multi`, `maps`.

Note **`settings` and `daily` are still reached from the city** via
`SminskiRunner.client.lua:2437/2503` — so those two are live even though the
rest of this section is not.

---

## 5. Cross-platform and input

- `UI.inputKind()` / `UI.onInputKind(fn)` — tracks touch / keyboard / gamepad
- `UI.autoSelect()` — gamepad focus, re-run on every screen change
- Backspace and gamepad B both call `UI.back()`
- `IgnoreGuiInset = true` everywhere, so `AbsolutePosition.Y` is
  inset-relative — a button at y = −38 is **on screen** (the inset was 58px).
  This has confused measurement before.
- Roblox's own jump button and thumbstick occupy the bottom corners on touch;
  compact layout exists to stay clear of them.

---

## 6. Constraints worth stating up front

1. **The art is rendered, not drawn in engine.** New surface shapes, radii or
   gloss mean a Blender pass in `art/blender/uikit.py`, a re-upload and new
   ids in `Art.lua`. Recolouring is free; reshaping is not.
2. **Icons are a fixed set of 23.** Anything new is a render job.
3. **The phone must not allocate at runtime.** Fixed row count, write text
   only.
4. **Positions are hand-computed and interlocked.** Expect to redo the HUD
   arithmetic, not tweak it.
5. **Buttons are already at minimum thumb size** on phones (that is why the
   compact layout takes space from information panels instead). Don't shrink
   them to make room.
6. **Play-mode screenshots come back solid magenta in this project.** UI is
   verified numerically — `AbsolutePosition`, ancestor `Visible` chain,
   `GetGuiObjectsAtPosition`. A redesign cannot be signed off from a
   screenshot in Studio; it has to be measured or seen on a real client.
7. The visual rules that govern all of this are `.claude/rules/design.md`
   (shape language, palette, scale philosophy) — that document wins any
   conflict with anything here.

---

## 7. What a redesign brief should actually ask for

In rough order of leverage:

1. **A token layer.** Semantic names over the eleven colours, a type scale, a
   spacing scale, a radius scale. Today every size and colour is typed at the
   call site, which is why the HUD arithmetic is hand-maintained.
2. **The city HUD grid.** Eight buttons, four readouts, two contextual bars,
   on a 1280×760 canvas that scales to a phone. This is what a player looks
   at for the entire session.
3. **The modal shell.** One `modalCard` serves twelve screens; restyling it
   restyles all of them.
4. **The phone**, as the home for the short-loops work in `docs/LOOPS.md`.
5. **A pass on the rendered surfaces** — the four 9-slices and the 23 icons —
   only if the direction actually needs new shapes.

Related docs: `docs/AD_PROMPTS.md` (marketing art direction, same style
block), `docs/LOOPS.md` (what the phone is becoming), `docs/HANDOFF.md`
(project state), `.claude/rules/design.md` (the visual law).
