# Sminski City — session handoff

Context export from a long working session, written 2026-09-21. Paste this
into a new chat (or point a new session at this file) to pick up where it
left off. Everything here was true at the time of writing; verify a named
file or function still exists before relying on it.

---

## 1. The project

**Sminski City** is a Roblox social / life-sim: a tiny soft character living
in a big pastel toy city. Repo: `~/Desktop/SminskiCity`. Rules live in
`CLAUDE.md` and `.claude/rules/*.md` — read the relevant one before touching
an area.

The ones that bite most often:

- **Assets are Claude-built, human-approved.** Built from re-runnable Blender
  code in `art/blender/`; nothing reaches the map without review. Prefer
  reusing an approved asset over making a new one.
- **Never make assumptions about import or layout behaviour. Measure.**
- Modular kits, never one-off implementations. Append-only lists
  (`Places.cityLots()`, `Places.CityLandmarks`) because saves store indices.
- Scope is the **downtown vertical slice**; check `docs/ROADMAP.md` first.

### Hard constraint from the user

> **Never push SminskiCity to "yogegr" or anything related to it.** It is a
> separate project. (Also saved in Claude's memory for this project.)

Nothing has been committed or pushed in this session. Do not commit or push
unless asked.

---

## 2. How work gets into Studio

1. `python3 -m http.server 8765` running in `game/`.
2. In Studio (Edit mode) run `_G.SR_sync()`. In a **fresh Studio session**
   `_G.SR_sync` does not exist yet — load it by fetching
   `http://127.0.0.1:8765/_sr_sync.lua` with `HttpService:GetAsync` and
   running it through `loadstring`.
3. A new client module must be added to the module list in `game/_sr_sync.lua`.
4. Sync only works in Edit mode: stop Play, sync, start Play.

### Testing gotchas (each one cost time)

- **Play-mode screenshots come back solid magenta.** Verify UI numerically
  (`AbsolutePosition`, ancestor `Visible` chain, `GetGuiObjectsAtPosition`).
- The test console runs in **its own Luau VM**: `_G` is empty and
  `require(City)` returns a constructor, not the live table. Reach the game
  through RemoteFunctions and the Studio-only hooks below.
- `GetBoundingBox()` is in the PrimaryPart's frame. For "is it on the
  ground", compute world-space min Y from part corners.
- With `IgnoreGuiInset = true`, `AbsolutePosition.Y` is inset-relative
  (the inset was 58px here). A button at y = -38 is on screen.
- A tool call that waits more than ~60s times out. Split long waits.
- The city streams in around the player: teleport next to a spot and wait
  ~3s before measuring geometry there.
- The world is built **on the client**. The server cannot raycast or check
  overlaps, so anything the server places must be clear *by construction*.

### Studio-only hooks

| Hook | Where | Does |
|---|---|---|
| `ReplicatedFirst.SR_TestPick:Invoke(what)` | title | presses a menu option (`play`, `home`, `work`, `shop`, `settings`) through the real routing |
| `ReplicatedFirst.SR_ShowMenu:Fire()` | title | reopens the menu mid-game |
| `SminskiRemotes.EventsDev:InvokeServer(id, atMe)` | server | starts a city event now; `atMe` drops it 40 studs away |
| `PlayerScripts.SminskiDev` (BindableFunction) | runner | `city job`, `city town`, `city store`, `city biz`, `skin`, `look` |

---

## 3. Luau / Roblox facts learned the hard way

- `RunService:BindToRenderStep` returns **nil**, not a connection. Track it
  with a boolean and unbind by name.
- `UIStroke.Transparency` is separate from `TextTransparency` — fade both.
- A `local function` is invisible to code written above it. Six bugs in this
  session had that shape; mutable flags in `SminskiTitle` now sit at the top.
- `BillboardGui.AlwaysOnTop` draws above ScreenGuis.
- `VideoFrame` only plays uploaded, moderated video assets. Image uploads
  cap at 1024px on the long edge.
- No local Lua toolchain on this Mac; syntax is only checked when Studio
  compiles the synced script.

---

## 4. What was built this session

| Area | State | Key files |
|---|---|---|
| Store: 3 passes + 9 products, icons rendered | 11 of 12 live; **COIN JAR (R$99) not created** | `docs/STORE.md`, `art/blender/store_icons.py`, `Config.lua` |
| Tabbed SHOP, business card with shifts (+50% if you wait), town directory | done | `City.lua`, server |
| 15 whole-body skins | done | `Config.Skins`, `Models.lua` |
| Job system phases 1–7: Job Center, browser, ELO, streaks, shifts, uniforms, pizzeria kitchen | done; phases 8–13 not started | `CityJobs.lua`, `CityKitchen.lua`, server |
| Intro: 10 loader stills + skip, camera dive, title menu | done | `SminskiTitle.client.lua` |
| Menu routing (START/RESUME, HOUSE, WORK, SHOP, SETTINGS) | done, verified both pre-game and mid-game | title + `SminskiRunner.client.lua` |
| HUD: right = MENU/HOME/MAP/HELP, left = WORK/SHOP/TOWN/PHONE | done | `City.lua` |
| Ad / loader / TikTok prompts | sections 1–9 written | `docs/AD_PROMPTS.md` |
| **Short loops plan** | written | `docs/LOOPS.md` |
| **Short loops phase A** | built, synced, tested | see §5 |

Bugs fixed late in the session worth remembering:

- `City.hudVisible(false)` cleared its own record when called twice, so the
  HUD never came back after MENU → SHOP → RESUME. Hiding is now additive.
- The title's test hook called `pick()` unconditionally, so it could not test
  routing. It now branches like a real click.
- The title failsafe tested `titleScreen.Visible` (false in normal play too)
  and warned 53s into every session. It now tests `menuShown`.

---

## 5. Short loops (the CCU work) — current state

Plan and full results: **`docs/LOOPS.md`**. The core finding: almost all city
state is **per-player** (`s.city` on the session), so nothing in the city was
shared between players. Events are the first server-wide thing.

Design: five archetypes (FIND, COLLECT, RUSH, RACE, ROUND), events defined as
data in `Config.Events`, one server director, one client module, one phone.

### Phase A — DONE and tested

- `Config.Events`, `Config.Event()`, `Config.SightingTier()`
- Director + `Events` RemoteFunction + `CityEvent` RemoteEvent: end of the
  city block in `SminskiServer.server.lua`
- `game/CityEvents.lua`: drawing, prompt, claim, countdown strip, PHONE modal
- Events: **Sminski Sighting** (ambient; NPC in a skin; saved collection in
  `data.City.spotted`), **Lost Pup** (3 timed clues), **Ice Cream Truck**
  (public spot, first 3 share a bonus). Lost Cat and Food Truck were swapped
  for these because the pup and truck models already exist and are approved.
- Hidden spots are secret: the exact position is only sent to players within
  130 studs. Claims are distance-checked and paid through `pay()`, so passes
  and boosts multiply them like a job.

### Street geometry, measured (reuse these numbers)

Distances are out from a lot's **door line** (door is 118 from the block
centre; north is **+Z**, matching the in-game map):

| Offset | What is there |
|---|---|
| −1.5 | the facade plane (shop window) — never place anything here |
| **+2** | clear pavement: 0/105 samples blocked, open sky overhead |
| +4 / +6 | occasional metal street furniture (3–5 of 105 blocked) |
| +8 | a row of wooden posts at every door |
| +10 | lamp posts (6/105) |
| +12 | kerb; road surface (y = 0) beyond; pavement top is y = 0.45 |
| **+15.3** | kerb gutter, 6.9 wide, clear: where the truck parks |
| +18.9 | near edge of the traffic lane |

Only the 381 of 385 lots with this standard section are used (the school,
barn, city hall and market are excluded by a filter in the director).

### Station lifts land on the door strip — measured, and it bites any phase

The Elevated runs down the middle of `x`/`z` = **±600**, which are *roads*, so
each station's glass lift comes down on the pavement **in front of the lots
either side**, with an `UP` prompt at r = 7. Measured for HOMETOWN: the lift
bottom at `(139, -574.5)` is **4.0 studs** from that apartment lot's own
`door + t*±11 + n*2.5` spot. Eight lifts, so roughly ten lots.

Anything placed on a lot whose door is within **24 studs** of a lift bottom is
**unclaimable**: the player stands on it, `City.Roads`' prompt wins, and there
is no way to interact. Phase D excludes those lots (`Config.Hunt.ExcludeR`),
deriving the lift positions from the shared `Roads` module rather than copying
coordinates. **Phase E will hit this too.**

Note what it is *not*: the other three prompt modules are all clear by
construction — `City.Apts` nearest approach 24.1 studs, `City.Home` 25.0,
`City.Hang` 36. Excluding by *lot kind* (houses, apartments) would remove ~100
lots for no reason and break "by a house on Sunny St".

### Phase B — STARTED, nothing coded yet

COLLECT archetype: **Cash Drop**, **Balloon Festival**, shared **City
Cleanup**. Decided so far:

- **No new art needed.** Balloons: the fun park's recipe (2.4-stud ball,
  reflectance 0.15, thin string, `K.CAR_COLORS`) in `CityBuild.lua` ~2009.
  Coins: the runner's `StarCoin` mesh (`World.lua` ~1222). Litter: the recipe
  inline in `City.lua` `applyState` (~434) — factor it into a shared helper
  rather than copying it.
- **Scatter on the +2 strip**, `a ∈ [-13, 13]` along each lot's frontage,
  lots chosen within ~170 studs of a centre lot so players converge.
- Cash Drop is competitive (each bag taken once; 24 × 60 coins split across
  the server). Balloons and Cleanup are cooperative: a shared goal scaled by
  player count, small pay per item, completion bonus for contributors.
  Cleanup pieces should also call `creditWorld(player, s, "cleaner", ...)`
  so they count for anyone clocked in as a cleaner.
- Economy guardrail: a paced job earns ~187 coins/min; events should pay
  about that for the time they take.

### Phases C–G — plan only

C Rush shifts + job offers + 10-minute champion · D Daily 3 Hunt + capsule
ticket meter (one per ~10 *active* minutes, not 5) · E races · F Hide & Seek,
Red Light Green Light · G NPC errands, photo hunt, power outage.

---

---

## 5b. World revamp — decisions that OVERRIDE the rule files (2026-09-21)

The human made two calls that contradict `.claude/rules/`. They are deliberate,
they were made with the conflict spelled out, and they win. **Recorded here
because an agent reading only the rule files will otherwise refuse or stall.**

### 1. Third-party / toolbox assets may be used freely. No review gate.

Overrides `pipeline.md` ("Never From a Generator", "Claude-built,
human-approved") and `assets.md`'s per-mesh review checklist, **for world and
interior dressing**. The human has added buildings, bedroom and interior sets,
small props, character models, airports, roads and a `Social Interactions
[Dev Module]` to their Roblox inventory and wants them used.

Still true, and not overridden:
- **The Sminski itself, its rig and its animation stay Claude-built.**
  `pipeline.md`'s hero-asset list exists for things with exact dimensions,
  complex collision and many moving parts. Nothing in this decision touches
  the character.
- Anything that stutters or reads as a different art style is still a problem
  worth fixing — the gate is gone, the judgement is not.
- Re-colouring / re-materialling imported sets toward the pastel palette is
  expected where it is cheap, so the city still reads as one place.

### 2. Whole city, tiered — not the downtown slice only.

Overrides `ROADMAP.md`'s "4-6 block downtown vertical slice" boundary **for
enterability**:

- **95% of buildings enterable, city-wide.** Only ~5% may be facade-only.
- **Downtown gets bespoke, detailed, individually-designed interiors.**
- **Outer districts get good modular interiors** from an expanded `CityKit`,
  varied enough not to read as repeats.

The thing the human is actually reacting to is **repetition** ("don't have too
many repeating places"), so modular must not mean identical: vary by layout,
material, colour, props and signage, per `environment.md`.

Streaming and collision cost are now a real constraint rather than a
theoretical one — `performance.md` still applies, and `CityBuild`'s coroutine
budget and distance hiding are what make this possible at all.

### Inventory assets (2026-09-22)

The owner's Roblox-inventory models are curated into
`ReplicatedStorage.SminskiAssets.Inventory` by `game/_inventory_setup.lua`
and placed by `K.place()` / `K.invTree()` — trees, flowers, the farm pack,
a plaza in Button Park and a McDonald's in the market block. What was used,
what was rejected (all three grocery stores, both malls: 11k–37k parts) and
every measurement: **`docs/INVENTORY.md`**. The templates live in the place
file, so the place must be saved after curation. **Grocery stores** (basket →
till → fridge loop, E doors) are in the same doc.

---

## 6. Still owed to the user

1. **10 experience-page image prompts + 5 ad-campaign prompts** — asked for
   twice, not delivered.
2. **COIN JAR** product (R$99, 7,500 coins); `art/store/coins2.png` is ready.
   Steps in `docs/STORE.md` §4.
3. Phase B onward of the short loops.
4. Job phases 8–13 (bakery/café/burger, taxi navigation minigame, police,
   cleaner routes, construction).
5. Optional: a real phone icon (PHONE uses `bolt` for now) and a Lost Cat
   model — both go through Blender + review.
6. Driving was never re-tested with an actual car after the title-camera fix
   (the title provably releases the camera; there is no dev hook to enter a
   car).

---

## 7. How the user likes to work

- Short, informal messages; expects Claude to make routine calls and keep
  going rather than ask.
- Wants things **verified in Play**, and bugs found by measurement rather
  than guessed at.
- UI taste: bracketed white text for the title menu (`[START GAME]`), no pill
  buttons there; no duplicate coin display in the shop.
- Monetisation is server-authoritative (`ProcessReceipt` + a PurchaseId
  ledger); an id of `0` hides an item everywhere.

## 7. The loading screen is a performance now (SminskiTitle.client.lua)

The title screen was rebuilt around bounce rate, at the human's instruction.
Three things changed, and the third one reverses a decision the file used to
argue for in its own header.

**Five plates, held still.** `PLATES` (five ids, `game/art/intro/loader/*.jpg`)
replaces the ten-plate `STILLS` set, which survives only as `LEGACY_PLATES` in
case an id is moderated. Three seconds each, so one full pass ends exactly as
PLAY appears. There is **no Ken Burns push** any more -- the human asked for
"no animation on it", and the drift read as the image failing to sit still on
a phone. The only movement is the 0.6s crossfade, and the incoming plate takes
ZIndex 3 each cycle: with fixed ZIndexes, every other transition fades the new
image in *behind* the old one, which is invisible for 0.6s and then a hard cut.

**The logo is at the top**, over a new `ScrimTop`. There is a `ScrimBottom`
too. Neither is decoration: the picture under the type changes every three
seconds, so nothing on this card can rely on what is behind it. The tip line
went white with a stroke for the same reason -- it used to be ink on a cream
card and is now sitting on a photograph.

**THE BAR IS FAKE, DELIBERATELY.** It was wired to `City.loadProgress()` and
the header used to say "THE BAR NEVER LIES". Honest turned out to be the
problem: an honest bar's length is set by the player's hardware, so the slowest
phone -- the player most likely to leave -- got the longest bar and was told so
in percentages the whole way down. It now runs a fixed 14.2s curve with two
deliberate stalls (34%, 78%) so it does not read as the timer it is.

**What did NOT change is the safety.** The city still streams behind the card,
and the city's own curtain (`City.lua`, "ARRIVING IN SMINSKI CITY...") is still
underneath: it waits for the blocks near you and lifts by itself after 15s.
Pressing PLAY early hands you to that, not to a hole. The bar stopped
*reporting* the wait; it did not remove it.

### Consequences a later change must not undo

- **`SR_Progress` is still created and is now read by nothing here.** Do not
  delete it. `SminskiRunner.client.lua:2443` gates its entire title handshake
  on `if bar and playEvent` -- removing the value silently disables the HUD
  hold, the peek routing and PLAY itself.
- **PLAY appears on a bare `task.delay(PLAY_AT, revealPlay)`**, gated on
  nothing, with a second failsafe at `PLAY_AT + 8`. That is the point of it.
  Do not re-add a readiness condition.
- **The menu is built lazily.** `showMenu()` is gone; `buildMenu()` is
  forward-declared at the top and called from `reopenMenu()` only. A first join
  never opens the menu at all -- PLAY enters the city directly, which is one
  press instead of two -- so on most sessions those five buttons are never
  constructed.
- **`pick()` now tears down the load card as well as the menu.** It only ever
  faded `titleScreen` before, which would leave the card over the game with a
  live PLAY button on it.
- **Hold plates by `os.clock()`, not by counting waits.** The `t += 0.05` per
  `task.wait(0.05)` pattern loses a few ms an iteration; measured, that made a
  3.00s plate run 3.41s and pushed the fifth plate past PLAY, so nobody ever
  saw the shot the set is ordered to end on.
- Everything on the card is **named** (`LoadCard`, `PlateA/B`, `ScrimTop/Bottom`,
  `LoaderLogo`, `BarCard`, `Track`, `Fill`, `Status`, `Percent`, `Tip`,
  `PlayButton`, and `TitleMenu`). It was all "Frame" and "ImageLabel", which
  left `GetChildren()[n]` as the only way to address any of it.

### Test hooks

`SR_TestPlayNow` (BindableFunction, Studio only) reveals PLAY immediately and
returns its visibility -- without it the only way to test the button is to sit
through a 15-second wall clock on every run. `SR_TestPick("play")` still
exercises the routing.

### Measured 2026-09-21 (lead, not QA)

Bar full at **+0.257s**, PLAY visible at **+1.032s** in the same sample --
**gap 0.775s**, against the designed 14.2 -> 15.0. Plate deltas after the clock
fix: **3.030, 3.070, 2.980** (design 3.0; before the fix, 3.41, 3.45, 3.64,
3.39). A real mouse click at the button's centre left `LoadCard.Visible=false`
with **0 descendants still visible**, camera `Custom` with the humanoid as
subject, `SR_Choice="play"`, `SminskiCityUI` enabled. `SR_ShowMenu:Fire()`
afterwards took `TitleMenu` from **7 to 27 descendants**, 5 buttons, `[RESUME]`
not `[START GAME]`, all at TextTransparency 0.00, camera parked at radius
**420** / height **324** -- the menu pose.

## Restaurant Row (2026-09-22)

The restaurant tycoon is in: docs/TYCOON.md is the record. Twelve lots on
the old forest block (750,750), fourteen pieces on build pads, a recipe book
over the groceries, passive/serve/friends income, stars, chains, three new
Robux products and a pass (all id 0 until created). New module
`game/CityTycoon.lua`; server block "RESTAURANT ROW"; `B.restaurantrow`
replaces `B.forest`; `Kit.play` on CityKitchen lends the step panel.

**Save the place.** The kit templates (`TycoonPad`, `Tyc_*`) live in the
`.rbxl`, and the two raw kits were deleted from ServerStorage by the
curation run.

**The animation packs are R6.** `Inv_Anim_MovementSystem`, `Inv_Anim_Folder`
and `Inv_Anim_TemplateR6` (moved out of Workspace into ServerStorage: 45k
instances were replicating) are KeyframeSequences over Head / Torso / Left
Arm / Right Arm / Left Leg / Right Leg / HumanoidRootPart. The Sminski has
no Motor6D rig and no Animator — `Models.poseSminski` sets each part's
CFrame per frame from a pose name — so `Animator:LoadAnimation` has nothing
to drive. The path that fits the rules (character.md: R15-based, procedural
+ IK; pipeline.md: re-runnable code) is to **bake** the keyframes: sample
each sequence's limb rotations into a Lua table and give `poseSminski` a
`"keyed"` pose that plays them. Idles and the Emote are the useful ones; the
walk/run cycles would replace a procedural gait already tuned to the
Sminski's proportions. Not done; a separate job.

### The bodiless-arcade bug (2026-09-22)

**Symptom:** load in, land in the old arcade instead of the city, no Sminski
drawn. **Cause:** the client's `City` require had a bare
`WaitForChild("CityTycoon")` inside it and the runner's `require(City)` was
bare too. The place the owner was playing had had an **Undo** after a sync:
the undo re-created the deleted tycoon kits *and* removed the synced
`CityTycoon` module, so City.lua yielded for ever ("Infinite yield possible
on ...CityTycoon") and nothing below the runner's require ever ran -- no rig,
no PLAY route. **Fix:** City.lua loads every module through `mod(name)`, a
10-second `WaitForChild` that errors with the module's name; the runner
wraps the City require in a pcall, warns once, toasts, and leaves `City =
nil` -- the arcade still works with a body in it and PLAY says the city
did not load. Tested with the module hidden: warning in the log, 11 rigs
drawn, `Activity=hub`, dev hook alive; restored: city enters in 1s.

**Do not Ctrl+Z after a sync or a curation run.** Both are undoable Studio
operations; an undo puts the script tree a step behind the repo. If it
happens, `_G.SR_sync()` and the curation script put it right.
