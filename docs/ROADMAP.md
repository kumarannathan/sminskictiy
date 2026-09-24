# Smiski City — Rework Roadmap

## The Goal

> Claude-built, human-approved assets + procedural assembly in Roblox.

Build one **4–6 block downtown vertical slice** and make it ridiculously
good, before building the rest of the city.

---

# Where the code actually is today

The repo is `SminskiRunner` — an endless runner, a bedroom-diorama hub, a dog
park survival mode, and a large `City` mode. It is a real, working game. It is
not yet the game above.

## What already matches the goal

- **Procedural assembly exists and is good.** `game/CityKit.lua` is already a
  modular kit — `K.window`, `K.door`, `K.awning`, `K.gable`, `K.flatRoof`,
  `K.cornice`, `K.bench`, `K.lamp`, `K.tree`, `K.skyscraper`, `K.subway`,
  `K.buildCar`. `game/CityBuild.lua` composes blocks from it. This is exactly
  the "assemble, don't model" architecture the goal calls for.
- **Streaming is already solved.** Blocks build in coroutines with a frame
  budget and hide at distance. A dense slice will not stall the client.
- **The mesh-with-fallback convention already exists.** `Models.lua` clones
  Blender rig meshes from `ReplicatedStorage.SminskiAssets.Rig` when present
  and falls back to primitives when absent (`Models.hasMeshes`). This is the
  pattern the whole asset pipeline should follow.
- **An asset-id registry already exists.** `Art.lua` maps names to uploaded
  image ids. The 3D equivalent is the missing piece.

## The actual gaps

1. **Every 3D object in the city is built from anchored Roblox parts.** There
   is no path for a Blender or AI mesh to enter the city — only the character
   rig has one. Hero assets have nowhere to land.
2. **No interaction-point system.** `design.md` and `roblox.md` require
   `SeatPoint`, `HandPoint`, `FootPoint`, `InteractionPoint` on assets.
   Nothing in the kit emits them. The Smiski cannot climb, sit, lean or grab
   against world geometry.
3. **Scale is runner scale, not Smiski scale.** The city reads as a normal
   Roblox town. "Tiny character, big city" is not yet expressed — a curb is
   not a meaningful height, a bench is not climbable.
4. **The city is wide, not deep.** ~2000 studs of blocks, harbour, nature and
   farm. The goal wants 4–6 blocks at much higher density and interactivity.
5. **No prop catalog.** AI-produced props have no registry, no naming
   convention and no place to be reviewed before use.

---

# Build order

The first fifteen things, in order. Everything is **Claude-built,
human-approved** (`pipeline.md`); "Review" is how closely a human looks.

| # | Asset | Review |
|---|---|---|
| 1 | Smiski character + rig | piece by piece |
| 2 | Smiski animation / IK system | piece by piece |
| 3 | Road + sidewalk kit | piece by piece |
| 4 | Downtown building kit | piece by piece |
| 5 | Café | piece by piece |
| 6 | Apartment | piece by piece |
| 7 | Mall | piece by piece |
| 8 | Taxi | piece by piece |
| 9 | Park kit | piece by piece |
| 10 | Trees / plants | family contact sheet |
| 11 | Furniture | family contact sheet |
| 12 | Store props | family contact sheet |
| 13 | Signs / posters | family contact sheet |
| 14 | Food / toys / items | family contact sheet |
| 15 | City clutter | family contact sheet |

Items 1–9 unblock everything. Items 10–15 are volume and can run in parallel
once the style bible is locked.

---

# Mode architecture

The city is the world. The runner, the dog park and the bedroom table are
games **inside** it, reached from the Sminski Arcade on Main St.

```text
            SMINSKI CITY  (the game)
                  │
          THE ARCADE, Main St
                  │
   ┌──────────┬───┴────┬─────────────┐
   │          │        │             │
Endless    Dog Park   Dog Park   The Bedroom
 Run x3    Survival    Run        Table
                                (shops, outfits,
                                 collection)
```

Finishing any of them returns you to the street outside the arcade, not to
the bedroom. The bedroom table is now one cabinet among several rather than
the lobby everything hangs off.

Still open: the shops, boutique, cubbies, garden and library currently live
on the bedroom table. They are city businesses by rights and should move to
storefronts in the slice — the table can stay as a nostalgia room.

---

# The vertical slice

Six blocks, one loop:

```text
Apartment → street → café → park → store → subway → rooftop → home
```

The slice is done when a Smiski can, inside those blocks:

- walk, climb, sit, lean, grab, jump
- ragdoll and get up
- ride the subway
- enter buildings
- do a job
- buy something
- discover something
- return home

That list is the acceptance test. If all of it works in six blocks, the game
is proven and the rest of the city is production work rather than design risk.

Do not widen the map until the slice passes.

---

# Engineering steps to get there

In dependency order.

1. **`game/Props.lua` — the asset catalog.** Name → mesh asset id + scale,
   origin, collision mode and interaction points. Mirrors `Art.lua`. Entries
   record who made the asset and whether it passed review.
2. **`K.prop(name, cf, opts)` in CityKit.** Resolves a name through the
   catalog: clones the reviewed mesh if it is present, otherwise calls the
   existing part-built builder. Nothing in `CityBuild.lua` has to change, and
   the city keeps working with zero meshes imported.
3. **Interaction points.** Emit `SeatPoint` / `HandPoint` / `FootPoint` /
   `InteractionPoint` attachments from the kit builders, then teach the
   character controller to consume them.
4. **Scale pass.** Re-derive the kit's dimensions from the Smiski's body, not
   from Roblox defaults. This is a breaking change to the city and should
   happen before the slice is dressed.
5. **Slice layout.** Replace the current sprawl with the six-block loop.
6. **Dress it.** Props, signage, clutter — the AI-assisted volume.

Steps 1–2 are additive and safe to land immediately. Step 4 is the disruptive
one and should be scheduled deliberately.

---

# World density programme

Phased, per the brief. Test after each phase.

| Phase | Work | State |
|---|---|---|
| 1 | Natural lighting + grounded ground materials | **done, untested** |
| 2 | Redesign one district (downtown) for density | **done, untested** |
| 3 | Increase building density citywide | next |
| 4 | Street-level props and storefronts | |
| 5 | NPC population | |
| 6 | Traffic | |
| 7 | Interactive destinations | |
| 8 | District structure | |
| 9 | Extend the language citywide | |
| 10 | More activities and jobs | |

## What phase 1 changed

`LOOKS.city` was the cause of the washed-out glow, not the geometry:
ambient was (150,140,136) with Brightness 3.2, which flattens every shadow;
bloom threshold sat at 1.05, so ordinary surfaces bloomed; and the grade
applied +0.24 saturation under a cream tint -- the "white filter". It now
runs natural sun, ambient (74,76,86), bloom threshold 2.0, near-neutral
grade, no sun rays, and Haze 1.45 for aerial depth. Ground colours moved
from near-white pavement and blue-grey road to concrete and asphalt, and
grass from (150,206,112) to a natural green.

Note: `Lighting.Technology` cannot be set from a script. Confirm the place
is on **Future** in Studio, or the new shadow work will not show.

## What phase 2 changed

The towers on the downtown blocks sit at +-62 and stop at 100 studs out; the
sidewalk begins at 116. That 16-stud ring was bare, which is what made
downtown read as towers standing in a field.

It is now a continuous street wall: 15 storefront mid-rises per block, 3-6
floors, 16 deep, flush to the kerb, shoulder to shoulder, with one gap on
the east side left as an alley. Ground floors are real shopfronts (glass,
awning, signboard); above are windowed floors, cornices, fire escapes, water
towers and rooftop units. The towers now read as rising *behind* a podium,
which is the real downtown block pattern.

Each unit registers itself in `Build.destinations` with name, type,
district, door position and what it sells -- the metadata layer the brief
asked for, so later phases attach activities to the world instead of
hard-coding coordinates.

Left alone deliberately: the `cityhall` and `postbank` blocks already carry
civic buildings, so the street wall was applied only to `towersW` and
`towersE`. Extending it is phase 3.

---

# Phase 3 and the Blender kit

## The kit (art/blender)

`buildings.py` is the modular kit; `export_buildings.py` writes
`art/meshes/SminskiCity.fbx` + `buildings.json`; `preview_buildings.py`
renders `art/preview/city_kit.png` as a style check. It runs -- 15 pieces,
~9k triangles total.

Four building modules stack into any building (Ground -> Floor xN -> Roof,
plus a Corner), and eleven street-furniture pieces whose names match
`game/Props.lua` exactly, so `K.prop()` picks each one up the moment its
catalog entry is flipped from `pending` to `approved`. Until then the
part-built fallback runs, so importing a half-finished kit cannot break the
city.

Import path: FBX -> `ReplicatedStorage.SminskiAssets.Props`, names unchanged.

Catalog sizes are generated from the exported meshes, not hand-written --
Blender is the source of truth (`blender.md`).

## Street wall, citywide

`WALL` in `Places.cityLots()` is a per-kind profile table: floor range,
district, alley side. Eleven block kinds carry a wall at six units a side
(up from four), and it is applied *additively* -- a houses block keeps its
houses and gains a street wall in front of them.

Deliberately excluded, and why:

- **Farm blocks** (pasture, orchard, fields, barn, windmills, cows,
  pumpkins, sunflowers, lake, camp, forest) -- the rural belt. They get
  courtyard gardens instead, via `Places.cityGardens()`.
- **shopstreet, mall, dealer, postbank, fair, race, farmmarket** -- their own
  buildings already reach past 100 studs, so a wall at 100-116 would
  intersect them. These need a per-block pass with Studio open to measure
  properly. This is the main outstanding item.

## Facade first

The wall is 16 studs deep. Block interiors are hollow, and that is the
design: from the street you see a solid wall of buildings, and the space
behind it costs nothing because nobody can see it. The hollow is reached
through each block's alley and is where the courtyard gardens live.

## Not done yet

These are structural and were not safe to attempt blind:

- **Curved and irregular roads.** `Places.CityRoads` is a fixed list of
  seven straight lines on both axes, and the whole city -- blocks, lots,
  districts, traffic, the map UI -- is derived from it. Curving the network
  means replacing that list with a spline/graph and re-deriving block
  placement from it. It is the single biggest remaining change and it wants
  its own pass.
- **Water, bridges, waterfront.** Needs the road graph first, since a river
  has to cut the network somewhere and bridges have to carry roads over it.
- **Organic parks.** Same root cause: parks are currently block-shaped
  because blocks are the only spatial primitive.
- **NPC population and traffic** (phases 5-6).

---

# Density pass 2 (tested in Studio)

Unlike the earlier phases this one was built against a live Studio session:
blocks were constructed in edit mode and photographed, then a Play test was
run and the console read. Zero errors; 7 ms of work per frame.

## Bugs this pass fixed (all mine, from the first street-wall attempt)

- **Every houses block failed to build.** `B.houses` builds every lot in its
  block as a house; the mid-rise lots had no `roof` colour -> nil `Lerp`.
- **All 64 homes were walled in** -- a mid-rise stood on every doorstep,
  blocking doors, driveways and travel pads.
- **Lot indices shifted.** The server saves house ownership as an index into
  `Places.cityLots()`. New lots are now appended strictly after the original
  80, and a check in the preview harness asserts it.

Rule going forward: **never insert into `cityLots()`, only append**, and any
builder that iterates `lotsIn()` must filter by `kind`.

## What was added

- `CityDress.lua` -- kerb furniture on every urban block (bins, hydrants,
  mailboxes, news boxes, bike racks, benches, meters, a bus shelter per
  block), residential corner features (pond + footbridge, plaza, playground,
  garden), a creek courtyard in every housing block, garden fences, and
  traffic-light masts at all 49 junctions.
- `CityVenues.lua` -- walk-in cafes/bakeries/noodle bars/delis: order at the
  counter, sit on a stool, eat. No economy hooked up on purpose;
  `Venues.order()` is the single place to charge if that changes.
- Street wall: landmark blocks get a wide gateway mid-side instead of being
  hidden; corner turrets close each block; exposed end walls are glazed.
- Housing: a third (unowned) house per side, so rows read as terraces.
- Shopping street: +4 shops, +4 narrow mid-rises between the existing ones.
- Traffic: 22 cars + 4 buses, signals on a server-clock cycle that traffic
  obeys, buses dwell once a block, and cars brake late for pedestrians --
  stand still and they stop short, step out and you get knocked flying.
- No lawn on urban blocks; grass is for the farm belt and the park.
- Five street-tree varieties, one per block.

## The preview harness

Build blocks in the edit datamodel with a stub `UI`, photograph with
`screen_capture`, destroy afterwards. It needs fresh module clones because
`require` caches. This is the only way to *see* the city without playing, and
it caught every bug above. Worth turning into a checked-in tool.

## Still open

- Road graph (curves, freeways, river, real bridges) -- unchanged, still the
  biggest structural item.
- Seven block kinds still have no street wall (mall, dealer, postbank, fair,
  race, farmmarket, shopstreet's long sides are infilled instead).
- Non-food shopfronts are facades. Browse-only interiors are the next step
  for "more doors that open".
- Pedestrians do not yet wait at crossings or use the bus shelters.

---

# Density pass 3: coloured meshes, the last walls, shops that open

Built and checked in Studio (edit-mode preview + a Play test, clean console).

## Kit meshes

The 33 role-split sub-meshes are imported under
`ReplicatedStorage.SminskiAssets.Props` and live: benches, lamps, hydrants,
bins, mailboxes, bike racks, trees, pines. No default-grey meshes remain.

Orientation lesson, verified side by side against the part-built bench: the
city kit faces **-Z**, the character rig faces **+Z**, so the kit's exporter
maps Blender `(x, y, z)` to `(-x, z, y)` and `K.prop` applies **no** import
turn. `export_meshes.py` (the rig) uses the mirror of this -- do not copy it.
The FBX imports at 100x (centimetres); harmless, because `K.prop` sets `Size`
from `PropMeshes.lua`.

## Walls on the last five blocks

fair, race, dealer, mall, postbank. Their own buildings reach the kerb zone,
so each got a **measured** slot mask: the block was built in edit mode and
every frontage slot tested against the bounding boxes of what was there.
`WALL[kind].mask` / `.corners` in `Places.lua`. If one of those builders
changes, re-measure rather than edit the mask by eye. Only `farmmarket`
(rural) and the farm belt remain unwalled, by design.

## Every street-wall unit is a room

All mid-rise units are walk-in now. Food places keep the counter/stools
fit-out; everything else gets shelves, a till with a shopkeeper, and one
"spot" from the `SHOPFIT` table in `CityBuild.lua`:

| shop | what you do | how |
|---|---|---|
| clothing, tailor | TRY ON | opens the real outfits UI |
| toy store | OPEN | opens the real capsules UI |
| electronics | UPGRADE | opens the real upgrades UI |
| books | READ | sit in the nook |
| pet shop | PET | hug emote, bark |
| gym | WORK OUT | yoga emote |
| music | PLAY | a run of notes on the shop piano |
| florist | SMELL | cheer emote |
| barber | SIT | the chair |
| everything else | BROWSE | a line of flavour text |

A new kind of shop is a row in that table plus (optionally) a furniture
function in `SPOT` -- no new interaction code. Room lights switch off beyond
150 studs.

Not yet rooms: the 17x17 corner turrets (too small), the one-storey shops on
the shopping street, and the mall's existing units.

---

# Mobile UI, collapsible jobs, welcome tour  (synced + tested in Play)

Synced and driven in a Play test through the Studio dev hooks (below): the
tour runs all six cards and rings the right HUD elements, the jobs card folds
190x52 <-> 300x290, and the console is clean. The PHONE layout itself still
needs eyes in Studio's device emulator -- that cannot be switched on remotely.

## Why phones were swamped

The UI is designed on a 1280x760 canvas. On touch devices the scale is
clamped to a floor of 0.6 so buttons stay finger-sized -- but an 844x390
phone only *fits* at 0.51, so its canvas is ~650 units tall, and a small
phone's ~530. Every card designed for 760 ran off the top and bottom, and
fixed-size panels took a fifth of the screen each.

The buttons are already at the limit of a thumb target (84x34 px), so they
were **not** shrunk. The space comes from panels instead:

- `UI.fit(w, h)` -- the largest scale at which a card still fits. All nine
  `modal()` screens, revive, results and MP results open at their fit, as do
  every city modal (dealer, map, arcade, travel, menu). Never scales up.
- `UI.compact()` -- touch, or a viewport under 520 px tall.
- City HUD compact layout (`H.layout`): jobs card folded and moved top-left
  clear of the thumbstick, place pill down to one line, prompt at 0.84,
  keyboard hints hidden, driving buttons lifted clear of the jump button,
  home-tutorial card at 0.78.

## Collapsible CITY JOBS

Tap the header. Folds 300x290 -> 190x52. Starts folded on phones, open on
desktop. `H.setJobsOpen(bool)`.

## Welcome tour (`CityGuide.lua`)

Six cards on first arrival -- jobs, doors that open, traffic, getting around,
the arcade -- each ringing the HUD element it is about. Skippable, replayable
from the new HELP button. Server remembers via `c.tour` / action `tourDone`.
The existing find-your-house tutorial now waits for it (`cs.tour ~= false`),
so a new player never gets two cards at once; with an older server that
sends no `tour` field, nothing changes.

## Hub, home menu, dog park, garden, table tour  (also unsynced)

- `UI.fitPage(frame, designW, designH)` -- for pages anchored to all four
  edges, where a card-style fit does not apply. The **home menu** uses it
  (1200x720): on a small phone its top stack and bottom stack were colliding.
- Hub: prompt at 0.84, the survival waiting panel at 0.7, walking hint hidden
  (the hub state machine re-showed it every frame; that now respects compact).
- Dog park results, garden card and the table-tour card open at their fit.
- The **runner HUD was left alone**: it is score text and small pills, and
  was never the problem.

`UI.compact()` means a phone held sideways or a very short window -- NOT
"has a touch screen". A tablet has room for the full layout and gets it.

Modelled across devices (scale / canvas / fits), because Studio was offline:
modals only overflowed on SE-class phones (fit ~0.85); on mid-size phones
they already fitted, so what swamped those screens was the always-on panels.

---

# Test hooks (Studio only)

`SminskiDev` (a BindableFunction in PlayerScripts) gained a `city` command so
the city can be tested without a mouse -- simulated clicks stop arriving
whenever Studio is not the focused window:

`city("tour" | "tourNext" | "tourSkip" | "jobs", bool | "prompt" | "order", n | "eat" | "venue" | "knock")`

Verified with it: order -> food waits on the counter -> SIT -> food follows to
the table -> three bites -> gone; a traffic hit launches a standing player at
~62 studs/s for ~46 studs and they get back up; a hit while seated unseats
(that was a bug -- the seat re-pinned you every frame -- now fixed).

# Next: roads, homes, wayfinding, hangouts, weather, airport, trains

Survey done before starting:

- The **server barely knows about the grid**: one use, scattering litter.
  Jobs, houses and lots are all position/index based. So the grid can stay as
  the city core and the network can grow *outward* from it without touching
  saved data -- far safer than rewriting the core into a graph.
- Terrain is flat to +-1000, foothills ring from ~1260, mountain ranges east
  and west, harbour chunk to the north. New districts need the terrain script
  re-cut where they go.

Plan, in dependency order:

1. **Spline road kit** -- roads along curves, with kerbs, lane lines, optional
   elevation on pillars. Everything below is built from it.
2. **Ring freeway + river + bridges** round the grid, ramps at the four gates.
3. **Traffic on splines** (the current cars only understand the grid).
4. **Wayfinding** -- a soft glowing ribbon on the road surface to your target.
5. **High-rise living** -- ownable apartments (append-only lots, as ever).
6. **Train** on a viaduct loop with stations, then the **airport** beyond it.
7. **Hangouts** (plaza, rooftop, beach) and **weather on a 30-minute day**.

---

# The road network (step 1-3 of the expansion)

`game/Roads.lua` (shared data + sampling) and `game/CityRoads.lua` (builder,
trains, planes, prompts). The street grid is untouched; saved data is safe.

**Correction to the earlier survey:** the "flat land" to the north is the
SEA (`_city_bay.lua`). The town is boxed in by hills S/E/W and water N, which
is what shaped all of this.

- **Paths are polylines with filleted corners, not splines.** A 5,447-stud
  freeway is 11 straight parts + corner chords; corners are true arcs; nothing
  overshoots. `Roads.pieces / at / nearest`. Pieces tables carry `.length` and
  `.closed`, so iterate them with `ipairs` (generalized `for` trips on those).
- **Bay Freeway** -- elevated horseshoe in the 58-stud strip between the outer
  pavement and the fence, W-N-E, open to the south (arcade + gate). Ground
  slip roads at the SW and SE join the edge streets.
- **Bay Bridge** -- leaves the freeway's north side between the lighthouse and
  the first berth (the barrier has a measured gap there), red suspension
  towers, lands on the airport island.
- **Airport island** -- runway, glass-walled walk-in terminal (landside faces
  town, airside the runway), control tower, parked planes, and one plane
  flying a closed circuit (roll, climb, racetrack over the bay, land).
- **The Elevated** -- a rail loop over the x/z = +-600 avenues on a single
  row of median columns (never inside a junction). Four MID-BLOCK stations
  with glass lifts to the pavement; two trains that brake into stations and
  dwell. BOARD / GET OFF; BOARD outranks the lift's DOWN button.
- **Traffic**: 10 cars on the freeway + 4 on the bridge follow their paths.
- **The player's car** now looks for ground from its own height (it could not
  climb a ramp before) and may leave the town square; with nothing to drive
  on (open water, deck edge) it stops instead of falling.

Verified in Play: clean console; lift up to a platform; trains run and dwell;
BOARD puts you on the train; GET OFF returns you to the platform.
**Not yet verified:** a full station-to-station ride (the session was stopped
mid-test), driving a car up the ramp and over the bridge, the plane in motion.

Still to do from the same request: wayfinding ribbon on the road, ownable
high-rise apartments, hangout spots, weather on a 30-minute day, and a rail
spur to the airport.

---

# Apartments, open entrances, the glow pass

## Places to live (`CityApts.lua`)

Five buildings, five floor plans. Walk to a front door, press E:
street -> **shared lobby** (concierge, leasing desk, post, sofas) -> tour any
plan -> buy -> the lift takes you straight to YOUR flat.

Sites were **measured**, not guessed: each block was built in edit mode and
scanned on a 44-stud grid for a genuinely empty footprint. Only three blocks
had room for a tower (postbank, dealer, fair); the other two addresses reuse
buildings that already stand -- the brownstone `apartment` lots and the
`rowhouse` terraces.

| building | where | from |
|---|---|---|
| Bankside Tower | downtown, behind the post office | 4,000 |
| Motor Row Lofts | east, by the dealer | 3,000 |
| Funfair Heights | over the fun park | 2,600 |
| Mochi Brownstones | the quiet side | 2,000 |
| Willow Row | a garden street | 1,500 |

Plans: studio / one-bed / loft (double height, sleeping deck up a ramp) /
family (two beds, tub) / penthouse (terrace, piano). Price = building base x
plan multiplier, so 1,500 to 24,000.

**Infinite residents.** A flat is not a room inside the tower -- it is built
for you, on your machine, when you step out of the lift, and destroyed when
you leave. Lobbies are one shared room per building (you meet neighbours
there); flats stand on a per-player pitch.

**`workspace.FallenPartsDestroyHeight` is -500.** Interiors sit at **-420**.
The first build put them at -700 and players were swept back to the street
within two frames. The houses' interiors are at -400 for the same reason.

Prices are checked on the SERVER from `Config.AptPrice` -- the client only
names what it wants (`buyApt`, "building:plan").

## Open entrances + the green dot

- `K.OPEN` is Smiski green, and it means one thing: **you can use this.**
- `K.threshold()` lays a green mat; `K.openDoor()` builds a doorway with its
  leaves folded back and a dark hall behind, so it reads as a way in.
- Every walk-in room, every apartment lobby and **your own house** now has an
  open door and a mat. A neighbour's house stays shut, as asked.
- **The green dot**: one small glowing sphere hovering over whatever you are
  close enough to press E on. Every prompt source now passes its world
  position as a 6th value, and `City.stepDot` fades/bobs the dot.

## Glow pass

Big `Neon` panes were what made the town look lit from within. Lit windows,
tower podium fronts and shop windows are now **warm glass** (SmoothPlastic +
reflectance), not emitters. The mall's ten range-70 room lights overlapped
five deep and bleached whatever stood under them -- Capsule Corner worst of
all; they are now range 52 at 0.55, and the unit wall tints went from 0.55 to
0.3 so a yellow unit no longer reads as white.

## Verified in Play

Clean console. Door -> lobby (holds at y=-417) -> tour studio/loft/penthouse
(75/106/142 parts) -> buy (Willow Row studio, 1,500) -> `{"willow":"studio"}`
on the server -> lift -> your flat. The green dot is invisible on an empty
street and solid at a door.

**Not mine, but worth knowing:** four imported models are sitting loose in
Workspace -- `SminskiRoom`, `SminskiProps`, `SminskiRig` (up at y~1800-1960)
and `SminskiArt`. They are visible from the ground as lumps in the sky. I
have not touched them.

## Still outstanding from the recent asks

hangout spots · weather on a 30-minute day · road signs and the wayfinding
ribbon · whole-body outfit skins · a gated Premium neighbourhood · rail spur
to the airport.

---

# Weather, signage + wayfinding, hangouts

Scoped by a recon workflow (7 agents: 3 recon, 3 adversarial, 1 completeness
critic) before any code. Its findings changed the plan in two ways worth
recording, because both were right:

- **Build order reversed.** The roadmap had weather last. Everything else was
  being authored against one constant -- `clock = 14.6` -- so signs and the
  ribbon would have been tuned at noon and then broken by the day cycle.
  Weather went first.
- **Rain would have fallen indoors.** The city's walk-in rooms are roofed
  boxes in the open world; only houses and flats are teleported underground.
  So "inside" cannot be a flag -- it has to be a raycast.

## 1. Weather + a 30-minute day (`Weather.lua`, `CityWeather.lua`)

Pure functions of `workspace:GetServerTimeNow()`. No stored state, no
replication: every client computes the same sky from the same clock.

- Seven keyframes interpolated continuously (the hand-tuned 14h daylight look
  is one of them). `Weather.lookAt(t)` returns a look in the same shape as
  `LOOKS`, so it feeds the existing machinery.
- Six states, weighted; `Weather.FOG_MAX` caps haze **below the point where a
  700-stud sign or a grazing-angle ribbon stops being readable**.
- **CityWeather owns Lighting in the city** and applies its first frame
  synchronously in `City.enter`, because `applyLook("city")` forces noon and
  runs again on every return from a run or the park.
- **Rain**: one camera-following emitter, gated on a raycast straight up.
  Verified: rate 714 outdoors in a storm, 0 standing in a cafe.
- **Street lamps**: `K.lamp` built a glowing ball and no light. ~750
  PointLights is forbidden by `performance.md`, so lamps register their globe
  and a **pool of eight** lights is re-homed to the nearest eight, twice a
  second. Verified 0/8 at 2pm, 8/8 at night.
- Dev: `city("sky")` / `("sky", 23)` / `("sky", "storm")` / `("sky", false)`.

Two bugs found by running it: Luau has no `~`/`&`/`|`, so a bitwise hash
failed to load; and the sine hash that replaced it gave **40% "fair" against
a 26% weight**. It is minstd now, verified 34/26/18/14/4/4 exactly. Also
`K.lamp` returns early when the Blender mesh is approved, so the registry
line added below it never ran -- registration now happens on both paths.

## 2. Signage + wayfinding (`CityDress` fingerposts, `CityWayfind.lua`)

- **Fingerposts** on every block: a blade per direction naming the nearest
  landmark **down that road** and its distance ("CITY HALL 290"). Text is
  drawn at `LightInfluence = 0` -- `K.textOn` defaults to 0.8, which dims
  letters with the scene, and a sign you cannot read at 2am is not a sign.
  Verified legible at 22:36.
- **The ribbon**: a soft green line along the gutter lane, routed on the road
  grid, eaten as you pass it. It **dims as the day darkens** (a ribbon tuned
  at noon is a runway at midnight) and, where the grid does not reach (the
  airport is across the bay), it stops at the last real road and says so
  rather than drawing a confident line over open water.
- GUIDE sits beside GO on every travel-pad destination: walk there or jump.

## 3. Hangouts (`CityHangouts.lua`)

**In the shared world, not instanced** -- that is the whole distinction from
flats, and the reason they work: other players are real characters in the
city, so you genuinely meet them.

Each is built onto something that already existed and had no interaction:
the **concert lawn** (stage, band and crowd were there; now a lawn of picnic
blankets, a blinking dance floor and a drinks stand), the **boardwalk** (piers
and boats were there; now benches facing the sea, a fire with logs round it,
fishing spots) and the **bandstand** (gazebo was there; now a ring of benches
and a chess table).

**The thing that makes them social**: poses were only replicated for
`Driving`, so another player sitting looked like they were standing. There is
now a `CityPose` attribute published through the server the same way, set
from one place after every sitting system has run (reading it earlier
publishes a pose from a frame `othersTick` has already cleared).

Verified: sit publishes `sit`, standing releases it, dancing publishes
`cheer` and expires. Getting up by walking uses the project's existing
`MoveDirection` check and **cannot be driven by a script** -- a scripted
`Humanoid:Move` is overwritten by Roblox's control module every frame -- so
that one path is untested; `city("stand")` exists for tests.

Prerequisite landed first, as advised: `City.travel` now clears every seat.
Travelling while sat on a bench would have snapped you straight back, because
a seat re-pins your CFrame every frame.

## Still outstanding

Sound effects (cars, weather, people, doors, driving) · whole-body outfit
skins · a gated Premium neighbourhood · rail spur to the airport.

---

# Sound (`CitySound.lua`)

`Audio.lua` is the game's 2D sound and stays as it is. The city needed
POSITIONAL sound, which it had none of.

**Every sound is built from ten engine built-ins**, probed in-engine first
(24 of 25 candidates loaded; `pop_mid_up.wav` did not). They ship with the
engine, so nothing can vanish from the marketplace. They are raw material,
not finished sounds -- shaping is `PlaybackSpeed` + an `EqualizerSoundEffect`:

| want | built from |
|---|---|
| distant town roar | `action_falling` at 0.42x, highs cut 22dB |
| rain on pavement | the same rush at 1.35x, lows cut 14dB |
| the sea | `action_swim` at 0.55x |
| car / bus engine | `bass.mp3` looped at 0.2-0.48x by speed |
| thunder | `bass.mp3` at 0.16x, loud |
| crowd chatter | `uuhhh.mp3` at a random pitch per voice |
| birds | `electronicpingshort` at 2.4x, daylight + fair weather only |
| doors, tills | `switch.wav`, `electronicpingshort` |

**Cost is bounded exactly like the street lights**: 12 positional emitters and
6 one-shot emitters, re-homed every 0.28s to whatever is nearest -- not a
Sound per car and per shop.

**Ambience follows where you are and what is overhead.** Beds crossfade
town/sea/country by position, and the same roof raycast the rain uses muffles
everything to 0.25x indoors. Measured: town bed 0.20 on the street -> 0.04 in
a cafe; rain 0.57 on the street -> 0.20 under a cafe roof (you hear it on the
roof, which is the detail that sells it).

One bug caught by testing: horns backed off 9-25s even when no car was near,
so an empty street stayed silent for minutes. It retries in 2s unless it
actually sounded one.

---

# Monetization

There was already a mature pass system (8 passes with real ids,
`ProcessReceipt`, `refreshPasses`) and exactly ONE developer product. This
extends it rather than replacing it.

## EVERY NEW ID IS 0 AND MUST BE FILLED IN

Developer products and game passes are created on the Roblox creator
dashboard, not from code. So all 9 products and the 3 new passes ship with
id `0`, and **anything with id 0 is hidden from the shop and cannot be
bought** -- the file is safe to ship unfilled. Paste the real ids into
`Config.Products` / `Config.Passes` and they appear.

## Products (`Config.Products`)

- **Cash**: 4 tiers, and value per Robux climbs with the tier -- 61 / 76 / 88
  / 100 coins per Robux, so the big one is genuinely the deal.
- **Skips**: COLLECT NOW fills every business to its cap; RIPEN NOW ripens
  every garden plot. Both act on waits the game already had.
- **Boosts**: personal 2x/15min, and server-wide 2x for 15 or 30 minutes.
  The server-wide one names the buyer to everyone.

## Passes (appended, so no existing pass id moves)

STARTER PACK (49 R$: coins + the van + a plot, paid out once via a
`StarterClaimed` flag), AUTO-COLLECT, QUICK FEET (1.6x walk, 1.15x cars).

## Money safety

`ProcessReceipt` **records every PurchaseId in the save before reporting
success**. Roblox calls it again whenever the previous call did not confirm,
and without that ledger a single purchase pays out twice. Grants are applied
server-side only; the client never names a price, only a product id.

Boosts multiply inside `pay()`, after the pass multipliers, so personal and
server-wide boosts stack with VIP and 2x Coins.

Verified in Play: server starts clean, the Boost remote exists, the banner
appears and counts down (14:43 -> 14:40), and with no ids filled in the shop
correctly offers nothing.

---

# Pass: the shop, the business card, and skins

## The shop finally has a door

The coin shop existed and **nothing in the game ever called `City.openStore`**
-- it was unreachable code. It is now a three-tab SHOP (COINS / BOOSTS /
PASSES) behind a gold bag button on the city HUD, and the Toy Shop in the
lobby gained a matching COINS tab. Anything whose id is still 0 stays hidden
and the tab says why, so the whole catalogue ships safe and switches on one
id at a time. `docs/STORE.md` is the list to create, with prices, copy, and
512x512 art in `art/store/`.

Verified in Play: all three tabs switch; PASSES lists the 8 live passes and
correctly hides the 3 with id 0; COINS and BOOSTS show their empty state.

## Businesses: a shift, not a cap

The 240-minute cap used to be a silent punishment for sleeping. The first
`ShiftMinutes` (20) are now a **shift**: collect mid-shift and you get exactly
what is in the till; let the shift finish and the payout carries
`ShiftBonus` (+50%). The cap still holds at 240 (480 with TYCOON), so offline
earning is unchanged -- what changed is that waiting is now a choice with an
upside rather than a ceiling.

**MY BUSINESSES** is a card, opened from the HUD or by tapping the jobs row:
every shop in town, its shift bar filling live, what it owes you, a COLLECT
per shop and a COLLECT EVERYTHING. Shops you do not own show their price and
a SHOW ME that lays the wayfinding ribbon to the door.

`collectBiz` **no longer needs you to stand at the shop** -- that is the whole
point of the card. `buyBiz` still does.

Verified in Play: the payout curve is exact (19.9 min -> 119 + 0; 20.0 min ->
120 + 60; 240 min -> 1440 + 720; capped past that), collecting works from
12,000 studs away, a second collect is refused, and a shop you do not own is
refused.

This also wired **AUTO-COLLECT**, which had been granting a flag that nothing
read. A server loop cashes out finished shifts once a minute -- and only
*finished* ones, so the pass's real pitch is "you never miss the bonus", not
"you can stop tapping".

## Skins: the third look layer

A Sminski is now three independent things that compose:

    CHARACTER  body colour and finish   <- toy capsules
    SKIN       the shape you wear       <- Config.Skins, 15 of them
    OUTFIT     a hat or a clip on top   <- the Toy Shop

15 skins from Just Me to Solid Gold. A skin sets its own colour (a pink knight
is not a knight) unless it is `keepBody` -- the hoodie and the tracksuit are
dyed by whichever capsule character you have on, so they show your collection
off. `EquippedSkin` replicates as a `Skin` attribute, so every other player
sees it; your own avatar is drawn from `ctx.data` so it changes the instant
the server confirms.

Two traps worth remembering:

1. **Leave the face alone.** With the imported meshes the face is a decal on
   the front of SmHead, so a hood has to be pushed back in -Z or it blanks the
   Sminski.
2. **Check the hood actually clears.** The dino's spikes sat at radius 0.75
   inside a hood of radius 0.9 and were swallowed whole -- the skin shipped as
   a plain green Sminski until they were moved onto the hood's surface.

Verified in Play: all 15 build; buy/equip/level-gate/double-buy all behave;
the live rig goes 14 -> 24 -> 30 -> 14 parts as skins are worn and removed.

## Layout bugs caught by measuring rather than looking

Play-mode screen capture returns solid magenta, so the cards were audited
numerically instead -- every child's box against its card and against its
siblings. That found three real collisions a screenshot would have shown and
a code review would not: the COLLECT EVERYTHING button sitting on top of the
last business row, and long text sliding under the close X on both the
business card and the shop (modalCard's X owns y 14..66 on the right, so
anything full-width has to start below it).

## The store went live

11 of 12 ids are in. Every one was checked against `GetProductInfo` rather
than trusted: all resolve, and every live price matches what Config claims.
COIN JAR (R$99) is the only one not created -- without it the cash ladder
jumps 49 -> 249 and the "+25%" badge that sells the value curve never appears.

Two things the ids turned up that a code read would not have:

- **QUICK FEET was half broken.** The server published `CarMult` and nothing
  anywhere read it, so "your cars are 15% quicker too" did nothing. `carSpeed()`
  applies it now.
- **AUTO-COLLECT works.** Verified by temporarily dropping `ShiftMinutes` to
  0.2 so the once-a-minute tick landed inside a test: it paid 894 coins for one
  finished shift, fired `AutoCollected` to the client, and moved the balance by
  exactly that. `ShiftMinutes` is back at 20.

STARTER PACK grants once and cannot pay twice (`StarterClaimed`), verified
with the van, the plots and the coins all arriving.

The Toy Shop's own balance pill was removed: it sat in the same top-right
strip as the tab row, and the sixth tab (COINS) ran underneath it. The home
screen already shows the balance.

## The town directory

A **TOWN** button on the city HUD, three tabs:

- **NEIGHBOURS** -- everyone on this server and where they live, whether that
  is a numbered door on a street or a flat in a named building.
- **SHOPS** -- all six businesses and who here owns each one.
- **RICHEST** -- everyone ranked by coins, with level, shops and address.

**Every row goes somewhere.** A directory you can only read is a list; the
VISIT button lays the wayfinding ribbon to the actual front door. Knowing
where the richest player lives is only interesting if you can go and look.

This is one server, deliberately: it is about the people you are actually
sharing a town with. Nothing on it is a new disclosure either -- a house is a
numbered door on a public street anyone can already knock on, and an owned
shop already has its owner standing in it. The screen indexes the world; it
does not leak it.

One bug it surfaced: `Places.CityApts` holds only the three **tower** sites,
so `aptDoor()` returned nil for the brownstones and the townhouses and VISIT
never appeared for anyone living in one. Those two resolve through the lots
they actually stand on now.

## The green pill behind the price

The value badge ("+47%", "BEST VALUE") was pinned 180px in from the right of
its row, which put its bottom-right corner underneath the price button -- it
read as a green pill poking out from behind the price. Rows are 14px taller
and the badge has a lane of its own directly above the button, in both shops.

Caught the same way as the last batch: by measuring. The earlier audit only
walked each card's **direct children**, so a collision *inside* a list row was
invisible to it. The audit now descends into rows, which is what found this
one and a second (the coin column in RICHEST running under long names).


---

# The job system (phases 1-7)

## The shape of it

Four new pieces, and one decision that shaped all of them.

**The city already had jobs in it.** Parcels from the depot, fares from the
taxi stand, litter on every street, fields up north -- scattered across the
map with no front door, no reputation and no sense of a career. So the Job
Center does not replace them. It indexes them, and the config says which is
which:

    world = <loop>   the job IS the open city. Clocking in makes the work
                     COUNT -- shift totals, reputation, streaks -- and the
                     loop itself is untouched.
    room  = <id>     the job happens at stations in a building. The pizzeria
                     is the first; Config.Restaurants holds its menu and its
                     pipeline, and one framework runs all of them.

That is why taxi / delivery / cleaner / farm hand are playable careers on day
one rather than "coming soon", and why adding the bakery is a config entry
instead of a second copy of the kitchen.

## What was built

- **Config.Jobs** -- 16 careers across four categories. The ten that are not
  built yet are LISTED, marked "not open yet" and cannot be started. A career
  you can see and cannot start is a goal; one that is hidden until it exists
  is a surprise nobody asked for.
- **The Job Center** -- a civic building on the downtown block at (150,-212),
  facing out through a gateway in the street wall so its door reads from the
  road. A board, a clerk, chairs. Both new sites were read off `B.postbank`'s
  actual geometry, not guessed, and both lots are appended last so no saved
  house index moves.
- **Slice of Life** -- the pizzeria at (212,-150), six stations laid out as a
  U so an order walks you down the left wall, along the back and out to the
  pass. A kitchen you could work standing still would be a menu with a floor
  under it.
- **The kitchen framework** -- five kinds of step (stop / fill / pick / bake /
  taps) plus serve, all one tap or one hold, because it has to work on a
  phone with a thumb.
- **Reputation** -- one number across every job, six tiers, five career titles
  per job. A perfect task is +7 and a botched one is -6, so no single bad
  order matters and a reset costs 1,000 coins.
- **Notifications, uniforms, streaks, the shift strip.**

## Balance: measured against what the city already paid

A parcel run is 67-105 coins; a fare is 75-125. A pizza order is 52-131 and
takes about the same time, so a job is a denser, more interesting way to earn
what the city already paid -- not a new faucet. Coins per minute: a typical
order is 137/min, a perfect one on the top item 187/min, against 133/min for
taxi fares and 180/min for a fully-owned arcade. Jobs beat passive income if
you are good at them and roughly match it if you are not, which is the right
way round.

## Three bugs the testing caught that a code read would not have

1. **The client could name its own price.** An item that was not on the menu
   fell through to the job's default base instead of being refused. Now the
   price comes from the server's own Config lookup and an unrecognised item is
   rejected outright.

2. **Rushing paid.** The first rate limit let a script claim an order every 14
   seconds at ~70% credibility, earning at roughly twice the intended rate
   while playing none of the game. Payout now scales with the time an order
   actually took, which flattens the curve: 185/min at the floor, 187/min at
   par, 131/min if you dawdle. Rushing gains nothing, and an honest fast cook
   is still slightly ahead.

3. **One piece of litter was worth as much reputation as a whole pizza.**
   Measured: clocking in as a cleaner and jogging down a littered street was
   36 tasks and +252 reputation in twenty seconds -- NEW to EXPERIENCED inside
   a minute. Tasks now carry a `weight` (litter 0.12, harvest 0.25, fares and
   parcels 1) and fractional work banks up until it makes a whole task. Every
   loop now earns 8-13 reputation a minute, so a career from NEW to EXPERT is
   about a hundred minutes of work whichever job you do it in.

## Verified in Play

Both buildings stream in clean (95 and 158 parts, no swallowed builder
errors). A full pizzeria order plays end to end -- dough 95%, sauce 93%,
toppings 100%, oven 92%, cut 94%, order score 96%, reputation +7, paid. The
next ticket auto-queues. Clocking out returns a shift summary and drops the
uniform; a `soon` job and an under-reputation job are both refused; the
reputation reset costs its 1,000 and works. Against a hostile client: no time
passed -> refused, 15s -> refused, 23s -> allowed but the claimed 100% capped
to 70%, an item not on the menu -> refused, score 9999 -> clamped and priced
at the real item's rate.

## Deliberately not built yet

Phases 8-13. The bakery, cafe and burger bar are config entries away. The
taxi is currently the existing fare loop with a shift and reputation on top,
not yet the navigation minigame in the brief. Police, the cleaner route,
construction sites with server-wide progress, and the rest are listed in the
browser as not open.

One gate is untested: every reputation-gated job is also marked `soon`, so
the `elo <` branch has never actually fired in a test. It is two lines and it
runs after the `soon` check, but it has not been exercised.



---

# The intro and title screen

## How it runs

`ReplicatedFirst/SminskiTitle` goes up before `StarterPlayerScripts` exists,
which is the whole point -- it covers the window a new player currently spends
watching a half-built city assemble around them.

```
  join
   |
   +-- SminskiTitle (ReplicatedFirst)   the four clips play, bar fills
   |
   +-- SminskiRunner (StarterPlayerScripts)
         enters the city immediately  <- the world builds BEHIND the intro
         writes real progress into ReplicatedFirst.SR_Progress
         holds its own UI back until ReplicatedFirst.SR_Play fires
```

Three objects are the whole handshake, created by the title script because it
runs first:

| object | what it carries |
|---|---|
| `SR_Progress` | NumberValue 0..1, written by `City.loadProgress()` |
| `SR_Play` | BindableEvent, fired when a menu item is pressed |
| `SR_Choice` | StringValue: play / home / jobs / shop / settings |

## The rules it follows

**The bar never lies.** It is wired to `City.loadProgress()`, which counts the
blocks actually built within 350 studs of you -- the same readiness test the
in-city curtain uses. A bar that hits 100% while the world is still building
makes the wait feel longer than no bar at all.

**The intro is cut short the moment the city is ready.** Forty seconds of video
covers about twenty seconds of loading. Holding somebody at a title sequence
after their game has finished loading is the exact mistake this screen exists
to avoid, so a fast join sees the descent and half a street and a slow one sees
more of the city. The wait never gets longer.

**It always lifts.** A 45-second failsafe shows the menu even if the ready
signal never arrives, and a second one fires 8 seconds after that. A loading
screen that traps someone forever is worse than no loading screen.

**Every menu item is a real destination.** PLAY, MY HOME (walks you home), GET
A JOB (opens the Job Center), SHOP, SETTINGS. There is no QUIT, because Roblox
has no quit -- leaving is the platform's button, and a dead menu item is worse
than a missing one.

## The flow

```
  10 plates, 2s each        skip appears once the city is BUILT
        |                   (before that there is nothing to skip to)
        v
  MENU, camera floating over the map, drifting
        |
        +-- START GAME / GO TO MY HOUSE --> camera dives to the player,
        |                                   then hands over. The zoom IS
        |                                   entering the game.
        |
        +-- WORK / SHOP / SETTINGS -------> the screen opens OVER the menu,
                                            world still drifting behind it.
                                            You asked for the shop, not for
                                            the city.
  MENU button in the HUD climbs back out -- the dive played in reverse.
```

## The bug that broke walking, driving and every cutscene

`camConn = RunService:BindToRenderStep(...)`

**BindToRenderStep returns nil.** It is not a connection. So `camConn` was
nil forever, `stopCamera()`'s `if camConn` never fired, the binding never
unbound, and the title screen kept writing `camera.CFrame` every frame for the
rest of the session -- at `Camera + 10`, i.e. *after* the game's own camera
code. That is one line, and it presented as three unrelated complaints: the
view panning on its own after entering, being unable to look around, and cars
being undriveable.

`stopCamera()` now unbinds by name unconditionally, because a flag can always
get out of step with reality and a stale binding that owns the camera is the
worst failure this screen can have.

The same shape of mistake has now appeared FOUR times in this feature --
`ready`, `hideWorldLabels`, `bizWaiting` and `showMenu`'s idempotence -- all
"used above where it was declared" or "assumed to run once". In one Lua chunk
a `local function` is invisible to everything written before it, and any
function a UI can reach twice needs a guard.

## Six bugs the menu flow shook out

**Two tracks at once.** `Audio.ambient(true)` spawns a coroutine that waits
for the sound to LOAD. Boot calls `ambient(true)`, then `ambient(false)` a
frame later on the way into the city -- and the first coroutine was still
parked on `Loaded`. When the file finally arrived it Played and faded the
lobby loop back up, over the city's ambience and the menu music. The call that
started it had returned long ago, so nothing pointed at it. Fixed with a
generation token: a stale coroutine checks whether it is still the current one
before it does anything.

**Text shadows lingering through transitions.** A `UIStroke`'s `Transparency`
is a separate property from its label's `TextTransparency`. Every fade tweened
the text and left the outline at full opacity, so the shadow stayed behind
after the word had gone. One `fadeText()` helper now moves both, used at all
seven fade sites.

**The logo twice.** The loading card carries its own copy of the logo, and
hiding the card was left to a delayed closure plus a fade. Kill the duplicate
outright the moment the menu exists; the fade is a nicety, not showing two
logos is not.

**A blank tutorial card after transitions.** `City.hudVisible(on)` set every
HUD Frame to `Visible = on`, so turning the HUD back on also revealed
everything that was legitimately hidden -- including the welcome tour's card.
It remembers what it hid now, and restores only that.

**The tour running against a hidden screen.** The city is entered while the
title is still up -- that is the point, the world builds behind the intro --
so `Guide.onState` fired long before anyone was looking at the game. It is
held until START GAME is pressed and released afterwards.

**Settings opening into nothing.** The city puts the runner UI into
`setMode("none")`, so the settings modal came up over a screen with nothing on
it. The peek path sets the mode back for as long as the screen is open.

LEAVE is gone from the city HUD: MENU is how you step out now, and two buttons
for "stop playing" that did different things was one more than anyone wants to
think about.

## Assets to upload

Everything is optional and the screen degrades in three steps, all of which
look deliberate: four videos, then the same four beats as crossfading stills,
then a plain gradient sky. Roblox gates video upload behind account
verification, so assuming a video exists would have shipped a screen that is
broken for most people who paste it in.

| file | goes in | what for |
|---|---|---|
| `art/video/aerial1.mp4` .. `apt4.mp4` | `CLIPS` | the intro, in order, 10s each |
| `art/video/title_bg.png` | `TITLE_BG` | the menu background -- apt4's last frame |
| `art/video/still_*.png` | `STILLS` | the no-video fallback |
| `game/art/logo_city.png` | `LOGO` | SMINSKI CITY, rendered to match the house style |

`title_bg.png` is the final frame of `apt4.mp4`, so when it is uploaded the cut
from video to menu is invisible -- the menu settles onto the last shot of the
intro instead of replacing it.

## One bug worth remembering

The client script destroys any leftover `^Sminski*` ScreenGui at startup -- a
cleanup for the Studio preview harness. The title screen is named
`SminskiTitle`, so for the first few runs the client killed the very screen the
player was looking at, a second after it appeared. It is excluded by name now,
and the title screen re-parents itself if anything else ever sweeps PlayerGui.

## Verified in Play

Loading card up immediately, bar tracking real block streaming, menu appearing
when the city is ready (4.0s in Studio with everything cached), all five
options present with their sub-labels, the game's own UI held back until the
handshake fires, and GET A JOB landing in the Job Center browser with the
camera handed back to the player.

## Still outstanding

COIN JAR (R$99) needs creating · the gated Premium neighbourhood (VIP
district) · rail spur to the airport · curvy roads inside the core 7x7 grid ·
street walls for `shopstreet` long sides and `farmmarket` · job phases 8-13
(bakery/cafe/burger, the taxi navigation minigame, police, cleaner routes,
construction sites).
