# World revamp — the plan

Lead-written 2026-09-21, from `world-builder`'s read-only audit. Decisions in
§0 are the human's and override the rule files where noted (see
`docs/HANDOFF.md` §5b).

---

## The reframe, and it matters

The human's ask was *"only 5% should be unenterable"*. **The city is already
67.3% enterable** — 259 of 385 lots always, plus up to 64 houses.

The real problem, measured:

| | |
|---|---|
| walk-in rooms | **222** |
| distinct interior shells | **3** |
| distinct fit-out functions | **3** (`fitFood`, `fitShop`, `fitKitchen` — the last used **once**) |
| distinct furniture arrangements | **2** |
| copies of each shop name | **~7.6** |
| rooms whose only content is the toast *"ooh, shiny."* | **~55** |
| interior furniture pieces in `CityKit` | **0** |

So `CAFE` appears ~8 times and every copy is the same 36 × 14 room. **This is a
repetition and density problem, not a door problem.** Effort goes to making
rooms distinct, not to opening more of them.

---

## 0. Decisions

| # | Decision | Source |
|---|---|---|
| D-A | **Third-party / toolbox assets may be used freely, no review gate.** The Sminski, its rig and its animations stay Claude-built. | human; overrides `pipeline.md`, `assets.md` |
| D-B | **Whole city, tiered.** Downtown bespoke; outer districts good modular from an expanded kit, varied enough not to read as repeats. | human; overrides `ROADMAP.md` scope |
| D-C | **"95%" means nothing prominent is fake.** Open the ~22 big civic buildings and skyscrapers players notice; spend the rest on making the 222 existing rooms distinct. The lot ratio is not the target. | human |
| D-D | **Corners: a mix of rooms and features.** Some widened to ~24 and made small interiors; others converted to things meant to be seen — clock towers, kiosks, rooftop stair access. | human |
| D-E | **The subway is an under-construction site, not a station.** The stairs lead down to a visible works area: a partly-built tunnel mouth and a bridge stub reaching up toward The Elevated, hoardings reading UNDER CONSTRUCTION, and NPC Sminskis working on it. The real connection is future work. | human |

**Split rule for D-D** (lead's, adjust at review): corners on **downtown and
shopping** blocks become small interiors — an espresso bar, a newsstand, a
record booth, a flower kiosk — because footfall justifies the work and a tiny
characterful room is *more* distinct than another 36 × 14 slot. Corners on
**residential, park and entertainment** blocks become features, which also
gives those districts the navigation landmarks `environment.md` asks for.

---

## 1. Fix these two first. Nothing else is affordable until they are.

### 1a. The cull bug — permanent colliders

`CityKit.lua:76-87`: `K.solid` / `K.walkable` reparent every collidable part to
`K.solidF` / `K.walkF`, which are children of `K.root` — **not** of the block
folder that `City.lua:103-113` unparents to cull. So **every interior wall,
floor, counter and shelf in the city is permanently resident in Workspace at
every distance.** ~11 permanent colliders per `venueRoom` × 222 ≈ **2,450
today**; at 366 furnished rooms with ~25 solids each, **~9,000**.

This is a bug, not a budget. The 900-stud cull radius also covers ~28 of 36
blocks from anywhere central, so residency is effectively unbounded.

**Fix:** adopt `CityApts`' pattern for street rooms — `buildFlat` / `clearRoom`
(`CityApts.lua:335-350`) build on approach and destroy on exit. That turns
~52,000 parts of interior into a few hundred resident at a time. Parenting
solids per-block is the smaller alternative.

### 1b. Depth — rooms are 14 studs and feel like slots

`door = blockCentre + n·118` and is **independent of `depth`**
(`Places.lua:169`). The facade must stay at 116. So `depth = 116 − d/2` lets
**`d` grow to 56** and the door line, the address, the lot index and every
piece of event arithmetic **do not move at all**.

Constraints, both measured:
- **`towersW` / `towersE` have zero slack** — towers at ±62 with 76-wide
  footprints reach exactly 100, and the wall occupies 100–116. Those 46 units
  cannot get deeper without moving a tower.
- Gate blocks are hollow to the courtyard gardens at ±34, so ~60 studs are free.
- The five measured masks (`fair`, `race`, `dealer`, `mall`, `postbank`) need
  **re-measuring in Studio** if footprints change.

---

## 2. Then: the interior kit

There is not one chair, table, counter, shelf, bed or till in `CityKit`'s 48
builders. `Props.lua` has 11 mesh entries, all street furniture. **A new
restaurant today is 46 lines of inline primitives — which is exactly why every
restaurant is the same one.**

**A furniture library already exists in the wrong file.** `CityApts.lua:118-214`
`FURN` has 16 pieces (`bed sofa rug coffee tv dining kitchen wardrobe plant
lamp shelf desk tub piano wallX wallZ`), each registering its own interaction
via `spot()` as it builds. That is the right architecture. Promote it to
`CityKit` as `K.furn.*` so anything can reach it, then add the ~15 a shop needs:
counter, display case, stool, banquette, till, menu board, fridge case,
shelving unit, mirror, rack, sign board, rug, pendant, wall clock, potted plant.

Under **D-A**, toolbox sets may fill this faster than Blender can. Re-colour and
re-material toward the pastel palette where cheap, so the city still reads as
one place.

---

## 3. Work order

| # | Work | Owner | Notes |
|---|---|---|---|
| 1 | Cull fix + depth growth | `world-builder` | §1. Must precede everything. QA re-measures the five masks and the two tower blocks. |
| 2 | Interior kit (`K.furn.*` + the 15 missing pieces) | `world-builder` | §2. Until this exists every room is inline boxes. |
| 3 | Restaurants as config, not functions | `world-builder` | `fitKitchen` + `Config.Restaurants` is a **complete scored job loop used once**. ROADMAP: "the bakery, café and burger bar are config entries away." Cheapest large win. |
| 4 | The 55 "ooh, shiny." shops get real fit-outs | `world-builder` | Grocery with food, hardware with tools, laundry with machines. |
| 5 | The five worst offenders | `world-builder` | §4. |
| 6 | Civic landmarks + skyscrapers opened (D-C) | `world-builder` | ~22 buildings. None are lots, so the ratio does not move — the *feel* does. |
| 7 | Corners split (D-D) | `world-builder` | Needs the widening from §1b. |
| 8 | **The city at work** — subway works site + Main St parade prep (D-E) | `world-builder` | **Both small, neither is a phase.** See §7. Street-furniture scale, so they can land any time after §2. |

---

## 4. The five worst offenders, with file:line

1. **Every restaurant and café — one layout, ~87 rooms.** `CityBuild.lua:854`
   `fitFood`, chosen at `:1166`. `MENUS` at `:847` has **4** menus for 10 food
   types; RAMEN/NOODLES/SUSHI/PIZZA/DINER all serve the same four items.
2. **The 55 "BROWSE" shops.** `CityBuild.lua:927` `DEFAULT_FIT`, room at
   `:1007`. Identical shelf wall, identical till, one toast: *"ooh, shiny."*
3. **The cinema — genuinely nothing.** `CityBuild.lua:2098-2129`. 40 seats as
   3-stud cubes you cannot sit on, a popcorn stand with no prompt, and
   `K.textOn(screen, ..., "")` — **an empty string on a blank white panel** —
   under a marquee promising NOW SHOWING.
4. **The mall — 7 of 16 units have no prompt at all.** `CityBuild.lua:1656`,
   built `:1773`. FOOD COURT listed twice. Every non-food unit's stock is the
   same 48 balls. It is ROADMAP hero asset #7.
5. **The 46 corner turrets** — the most prominent slot on every block, lit
   signs reading CAFE, and **no doorway geometry anywhere**.
   `CityBuild.lua:1353`, `interior = false` at `:1383`.

Honourable mentions: the two **subway entrances** (stairs into solid ground;
`Build.subways` is written at `CityBuild.lua:1494` and **read nowhere**); the
**airport terminal** (300 × 56 × 34, departures board, check-in desk, **zero
prompts**, `CityRoads.lua:322`); the five **civic landmarks**, all solid boxes
with a painted door — the parcel job's counter is on the **pavement** outside
the post office; and the **12 shopstreet shops**, the best-looking buildings in
the game (`CityBuild.lua:1579`), sealed.

---

## 7. The city at work — NPCs doing visible things

Two requests from the human that turn out to be the same idea, so they get one
section and one set of parts. **The city should look like it is being worked on
and looked after**, which is the cheapest density there is: no interiors, no
cull cost, existing rigs, and it makes a street worth walking down.

`design.md` asks for "lots of small environmental storytelling" and
`environment.md` wants every street to earn its place. This is how.

### 7a. The subway works site (D-E)

The two entrances currently descend into solid ground. Rather than build an
underground network, the stairs open onto a **construction site** — which keeps
the promise honest, adds a destination, and leaves the real station as future
work instead of a half-built one.

What it is:

- **A shallow excavated area** at the bottom of the existing stairs
  (`CityKit.lua:545` builds the stairs; `Build.subways` is written at
  `CityBuild.lua:1494` and read nowhere — wire it or drop it, per §9).
- **A tunnel mouth**, partly bored, going nowhere on purpose — shuttered, so the
  eye stops there rather than asking what is beyond.
- **A bridge stub** rising from the excavation toward The Elevated's deck, cut
  off mid-span. This is the bit that tells the story: you can see what it *will*
  connect to.
- **Hoardings / barriers** reading `UNDER CONSTRUCTION`, plus a dated notice
  board — good use of signage, which `pipeline.md` calls the highest-leverage
  dressing in the game.
- **NPC Sminskis working on it.** `Models.buildSminski` takes a `skinDef`
  and the city already places NPCs this way (phase A's sighting, the shop
  keepers, the grandstand crowd at `CityBuild.lua:2050`). Idle work poses, not
  new animation — `Config.Characters` already carries `idle` values.

Constraints:

- **No new art required.** Barriers, cones and hoardings are `CityKit`
  primitives; the workers are existing rigs. A hard hat would be new — under
  **D-A** a toolbox one is acceptable, or it ships without and reads fine.
- It is **street furniture scale**, not an interior, so §1a's cull bug does not
  gate it. It can land any time after the kit work in §2.
- It must respect the placement exclusions any street-placed thing now needs:
  the station-lift zone (`docs/HANDOFF.md` §5) and ≥ 12 studs from a live
  event spot. The two existing entrances sit on **subway corner lots**, which
  `Places.lua` already excludes from the corner count — check that the works
  area does not spill onto the `+2` strip events scatter on.

When the real station is eventually built, the works site becomes the
before-state of a visible change to the city, which is worth more than having
shipped a station quietly.

### 7b. Parade preparation on Main St

NPC Sminskis stringing banners and bunting along **Main St** — the north-south
avenue at `x = 0` (`Places.lua` `STREETS_NS[0]`), which runs straight through
both downtown blocks, so it is the most-walked street in the city.

What it is:

- **Bunting and banners** strung between lamp posts (`K.lamp` already stands at
  +10 from every door line, per `HANDOFF.md` §5) and across the street between
  facades. Flat coloured parts and `K.textOn` signage — no new art.
- **Workers mid-task**: one up a stepladder with a banner end, one holding the
  other end, one directing from the pavement, a couple carrying a rolled
  banner. Existing rigs, `Config.Characters` `idle` poses.
- **The kit around them**: barriers, cones, a small stack of crates, a cart with
  more bunting on it. All `CityKit` pieces that already exist (`K.stall`,
  `K.cart`, `K.fence`, `K.planter`).
- **A notice** giving the parade a date and a name, so it reads as a scheduled
  event rather than random decoration.

Why Main St specifically: it is the one street a player is guaranteed to cross,
and hanging things *across* it breaks the long sightline `environment.md` says to
break deliberately.

**It must not block the street.** Events scatter on the `+2` strip and the
gutter at `+15.3` is where the ice cream truck parks — keep ladders, crates and
workers clear of both, or a Cash Drop bag lands under a stepladder.

### 7c. Why these two are worth more than they cost

Both are **street furniture scale**: no interiors, so §1a's cull bug does not
gate them, and they can land any time after §2. Both reuse rigs and kit pieces
the city already has. And both do something no amount of interior work does —
they make the city feel *inhabited and in progress* rather than placed.

There is an obvious extension neither request asked for, recorded and **not
committed**: the parade itself could become a `Config.Events` row once the
COLLECT and FIND archetypes are settled — a moving event along a known route,
with the preparation as its warning phase. That would be phases C–F territory,
not this revamp.

---

## 8. What must not break

**Append-only, because saved data stores indices:**

- **`Places.cityLots()`** — `assignHouse` persists a lot index
  (`SminskiServer.server.lua:1259-1281`). **Changing `ALONG`, the `{N,S,E,W}`
  side order, or the `table.sort(keys)` over `Places.CityBlocks` silently
  renumbers every lot and moves every saved house.**
- **`Places.CityLandmarks`** — `cs.fare.dest` is an index into it.
- Do not change what `gap()` returns for an existing slot; it changes how many
  lots a block contributes and shifts everything downstream.
- Do not change `WALL[kind].mask` / `.corners` string lengths or positions —
  indexed `(a+80)//32+1` against `ALONG`, and **measured**, not eyeballed.
- Do not change `lot.face`, `lot.door` or the facade offset.
  `SminskiServer.server.lua:2593-2600` filters on
  `lot.door:Dot(n) − 118 − 150 ≡ 0 (mod 300)`, and the events, the daily hunt
  and the litter scatter all derive from it. **The server cannot detect a
  break, because the world is built on the client.**

**Safe by construction:** growing `d` with `depth = 116 − d/2`; appending lots
at the very end; adding fields to a lot table; adding rows to `SHOPFIT`,
`SPOT`, `MENUS`, `Config.Restaurants`.

---

## 9. Two loose ends the audit found

- **`Build.destinations` is written in 6 places and read in 0.** 269 entries
  built every session, consumed by nothing — while `environment.md` mandates it
  as *the* registry and `CityEvents`, `CityJobs`, `CityWayfind`, the taxi and
  the town directory all resolve through `Places` directly. Either wire the
  consumers through it or delete it; leaving it is the worst option.
- **Five parallel, incompatible spot tables** (`CityBuild`, `CityApts`,
  `CityHangouts`, `CityHome`, `Build.spots`), dispatched in a fixed chain at
  `City.lua:2221-2247`. The real shared convention is the prompt's 6-element
  array `{title, sub, btn, icon, fn, worldPos}`; four of five already match and
  **`CityHome`'s is the odd one out** (local `at`, `id`-keyed actions). New
  interiors must return the 6-element shape. Note `.claude/rules/roblox.md`'s
  `SeatPoint`/`InteractionPoint` convention is emitted only by `K.prop`, for
  2 of 11 catalog entries, and **consumed by nothing** — ROADMAP gap #2.
- **Pre-existing, worth knowing:** `B.venue` puts umbrella tables at exactly
  118 from the block centre on the 9 `venue` lots — **2 studs inside the "+2
  clear pavement" strip** events scatter on.
