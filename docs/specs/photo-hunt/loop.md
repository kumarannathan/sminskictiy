# Photo Hunt (cheap version) — loop design

Short loops **phase G, part 2**. Scope is `docs/LOOPS.md` §5's deferred line:
"the cheap version (stand at a viewpoint with the landmark inside the view
cone)". No camera mode, no subject detection, no photo artefact, no album.

**Verdict up front: build it.** The trust problem the brief calls "the crux"
dissolves once the design stops asking the client to assert anything —
position, body facing and *other players' positions* are all replicated
server-side state, and occlusion is decided analytically at server start from
the same `Places` data the client builds the city from. The kill condition is
named in §D9 and it is a measurement, not an opinion.

And one thing this design buys that nothing else in G does: the reward
function literally contains *how many players are standing next to you*.
`LOOPS.md` §1 says the CCU gap is co-presence, not activity count. This is the
first mechanic that pays for co-presence directly.

---

## WHAT EXISTS ALREADY

Everything below was read, not assumed.

### The director and the find claim

| Fact | Where | What it means here |
|---|---|---|
| A find event's claim is: uid lookup → `claimed[UserId]` once → `cityPos` distance ≤ `EV.ClaimRadius` → `pay()` → `FireAllClients("found")`. | `SminskiServer.server.lua:3092-3138` | A photo claim is **this function plus a dot product**. ~18 new lines, no new remote, no new action. |
| `ICE CREAM TRUCK` is already a find with `open = true`: public position, claimed once per player, `firstN = 3` share a bonus. | `Config.lua:1060-1061` | The photo op is that row's shape. `open` is *exactly* "everyone knows where it is", which is what a photo op needs. |
| `publicEv` ships `spot = { pos.X, pos.Z, face }` for `def.open` events — **positional**, and phase A's client unpacks it positionally. | `:2695`, `:2721-2728` | The viewpoint reaches the client with **no new payload shape**. Do not "improve" it to key-shaped: that is the silent failure phase D shipped (`npc-errands/CONTRACT.md` §2). |
| `draw(ev)` looks up `DRAW[ev.id]`, then `mark(ev, at)` adds the 160-stud beacon column **iff `def.open`**. | `CityEvents.lua:367-375`, `:357-366` | Beacon for free. One new `DRAW.photo`. |
| `E.prompt` iterates `E.list` for any non-collect find within `EV.ClaimRadius - 2`, and returns `{ title, sub, verb, icon, fn, worldPos }`. | `CityEvents.lua:2008-2033` | The photo prompt is a radius substitution inside the loop that already exists, not a new branch above it. |
| `E.prompt` runs at `City.lua:2239` — **after** `City.Apts`, `Home`, `City.Roads` (lifts/trains) and `City.Hang`, **before** Jobs, Kitchen, Venues and every world prompt. | `City.lua:2221-2316` | Only Roads/Hang/Apts/Home can shadow a photo prompt. §D4 shows Roads is the only one that reaches a block corner, and it is excluded. |
| The director filters by `minPlayers` and `cityCount()`, and never starts anything unless `anyoneInCity()`. | `:3188-3244` | Empty-server behaviour is already correct and free. |
| The headline loop remembers `floor(keep/2)` recent ids; five headline rows exist today. | `:3226-3244` | A sixth row **makes every existing headline rarer**. That cost is priced in §N6. |
| `pickSpot` already reaches forward into a later block (`huntLotTaken`) to avoid putting two claimable things in one place. | `:2649-2668`, `:2540-2545` | The same forward-slot pattern is how a photo viewpoint keeps later finds off it (§X4). |
| Phase D derives the station-lift positions from `Roads` rather than copying coordinates, and keeps them in a `blockers` table **local to the hunt's `do` block**. | `:3354-3395` | The photo derivation needs those same eight points. Lifting `blockers` one scope up is the one refactor this spec asks for (§R1). |
| `huntNear(x, z, r2)` already exists as a forward slot: "is this within sqrt(r2) of one of today's three?" | `:2541`, `:3786-3793` | Hunt-spot separation costs one call. |

### The city geometry, and why the server can reason about it

- `Places.BLOCK = 260`, `Places.WALK_W = 14`, `Places.CityRoads` every 300 on
  both axes, `Places.BlockCentres` = ±150/±450/±750 (`Places.lua:60-63,107`).
- Every lot's door is **118** out from its block centre; kerb at door+12 = 130
  out; the sidewalk ring is therefore **116 → 130** out, 14 wide
  (`HANDOFF.md` §5, `:2572-2592`).
- So **the pavement corner centre is `BLOCK/2 - WALK_W/2 = 123` out on both
  axes** — derived from two published constants, not measured, and identical on
  all 36 blocks.
- The corner *turret* building is a 17-stud square centred at 107.5 out
  (`Places.lua:344`, `CityBuild.lua:1353-1356`), so it occupies 99 → 116. The
  corner pavement centre at 123 is **7 studs clear of the turret face and 7
  studs inside the kerb** — out of the traffic that "knocks you flying"
  (`ROADMAP.md`).
- **Fingerposts already stand on the block corner** at (cx−118, cz−118) and
  each blade already names "the nearest real landmark down this road" and its
  distance — `CityDress.lua:270-308`. The clue grammar for this feature is
  already built, approved, lit at `LightInfluence = 0` and readable at 22:36.
- `Places.CityLandmarks` (`Places.lua:139-150`) is 18 named points, **append
  only because a fare in flight saves its index**.
- `Places.cityDistrictAt(p)` (`:83-88`) buckets a position into one of five
  districts.

### The two things that constrain everything

1. **The server cannot raycast** — the world is built on the client
   (`HANDOFF.md` §2). Anything the server places must be clear *by
   construction*.
2. **There is no telemetry in this repo at all.** Every number below that is a
   guess is labelled as one in §N9.

---

## THE DESIGN

### D1. The loop in one line

> **The phone says "PHOTO OP — face City Hall from Main St & Central Blvd"
> → you walk to the green mat on that corner and turn to face City Hall →
> 150 base coins, +30 for every other player in the shot → the next one is a
> different view of a different landmark, and the ones with a crowd pay
> nearly double.**

Archetype: **FIND**, `open = true`. Two new fields on the row (`aim`,
`stand`). Not a sixth archetype — §D2.

#### One full cycle, second by second

```
-00:45  director picks (subject, viewpoint), announces to the whole server
        toast   PHOTO OP -- face City Hall
        strip   PHOTO OP   0:45   (counting down to the window opening)
        phone   NOW IN TOWN gains a row: "Main St & Central Blvd --
                face City Hall", with a GO button
-00:42  player taps GO -> CityWayfind lays the green ribbon to the corner
-00:15  arrives. The 160-stud beacon column was visible a block away; the
        12x12 green mat is on the corner pavement, angled at City Hall
 00:00  window opens; strip flips to 2:30 remaining
 00:04  player steps onto the mat -> green dot + prompt card
        PHOTO OP / "turn to face City Hall" / [SAY CHEESE]
 00:06  turns; the card's sub line flips to "City Hall, dead ahead"
 00:07  presses. Server: on the mat (9.1 <= 10), aimed (dot 0.94 >= 0.819,
        lateral 41 <= 130), not driving; three other players inside 14
        studs aimed within the last 2.5s -> base 150 + 3x30 = 240
 00:08  toast   PHOTO OP  ·  4 IN FRAME  ·  +240
        strip   4 SHOTS TAKEN
        meter   +240 units (8-13% of a capsule ticket)
 00:10  CITY NEWS: "Alex and 3 others got City Hall from Main St!"
 00:12  four players are standing shoulder to shoulder with nothing to do.
        This is the best place in the game for the director to fire the
        next thing -- see D8 (the chain), the one optional extra.
 02:30  window closes; mat and beacon removed; nothing is saved.
```

### D2. Which archetype

**FIND.** The verb is "one thing, go to it, anyone may claim once". Compare
the `icecream` row it is modelled on:

| | ICE CREAM TRUCK | PHOTO OP |
|---|---|---|
| position | `open`, public | `open`, public |
| claims | once per player, `claimed[UserId]` | identical |
| claim test | distance ≤ 16 | distance ≤ 10 **and a facing cone** |
| payout | `coins + first` | `coins + crowd × others` |
| state | none saved | none saved |

Two predicates and one payout modifier. It is data in `Config.Events.List`
plus ~18 lines inside the existing find claim. **A sixth archetype would be
indefensible here** — it would need its own `start`, `finish`, `publicEv`,
strip rank and phone row, which is exactly the five-special-cases cost phase
D's own header (`:3266-3275`) declined to pay for something much bigger.

### D3. What a viewpoint is — **derived, no new list, nobody else's file**

> **A viewpoint is a (block corner, subject landmark) *pair* whose sightline
> is analytically clear and whose range is 90–620 studs.** It is a pair, not a
> place: the same corner is a different viewpoint for a different subject,
> with a different aim.

Derived at server start, in five steps. No hand-placed list, so
**`Places.lua` is not touched and `world-builder` is not blocked** (§R5).

**Step 1 — corners.** For every block in `Places.CityBlocks` whose kind is not
in the farm belt (the same twelve kinds `CityDress.D.block` early-returns on,
so a fingerpost provably stands there): four corners at

```
vp = ( cx + sx*C , cz + sz*C )     sx, sz in {-1, +1}
C  = Places.BLOCK/2 - Places.WALK_W/2 = 123
```

24 non-farm blocks × 4 = **96 candidate corners**.

**Step 2 — subjects.** Every entry of `Places.CityLandmarks` whose position
satisfies `|x| <= 1000 and |z| <= 300` — i.e. the three central districts
(downtown, shopping, fun park) — minus `Config.Photo.Skip`. Today that is
**nine**: the Mall, City Hall, the Ferris Wheel, the Kart Track, the Arcade,
the Car Dealer, the Supermarket, the Job Center, Slice of Life. The seven it
excludes (School, Button Park, Pool, Barn, Lake, Campground, Windmills,
Apartments, City Gate) are outside the band, which is how this design stays
inside the **downtown vertical slice** without a scope rule: the filter *is*
the scope. Derived by band, not listed by name, so a landmark appended later
joins in automatically and a bad one is one string in `Skip`.

**Step 3 — range.** `d = |subject - vp|` must be in **[90, 620]**. 90 is
borrowed from the fingerpost's own `along > 90` rule (`CityDress.lua:287`) and
means "not a wall in your face". 620 is two blocks plus two roads, and sits
inside the range `Weather.FOG_MAX` is already capped to keep readable (the fog
cap is set so a **700**-stud sign stays legible — `ROADMAP.md`, weather
section). Cheap prefilter; run it first.

**Step 4 — the sightline, analytically.** The server cannot raycast, but it
does not need to: the city's building mass is a pure function of data the
server has. A block's buildings occupy the AABB `[cx ± 118] × [cz ± 118]`
(118 = the facade line; the towers behind the street wall stop at 100 out, so
the AABB is the **maximal** footprint and can only over-report). Shrink by
`Eps = 1` so a sightline running exactly along a facade plane counts as clear.

```
clearLine(a, b):
  own = the block centre whose Chebyshev distance to b is smallest, accepted
        only if that distance <= 118 + 16 (16 = the street wall's depth, so a
        landmark point standing just outside its own facade still resolves to
        its own block). A landmark with no own block excludes nothing.
  for every block centre except `own`:
      if segment a->b intersects [c ± 117]^2  -> return false
  return true
```

A standard 2-axis slab test; 36 blocks; ~10 ops each. Run **after** the range
prefilter, so the real cost is a few hundred pairs × 36, once, at start.

Excluding the subject's own block is the point that makes this work at all —
without it every sightline to the Mall is blocked by the Mall.

*Worked example, to prove the test admits the shots you want.* Corner (27, 27)
(block 150,150 SW) → the Arcade (−520, −40): 549 studs, and the segment's `z`
stays inside [−40, 27] the whole way, so it never enters the `z >= 33` AABBs of
blocks (−150,150)/(−450,150) nor the `z <= -33` AABBs of (150,−150)/(−450,−150).
Clear — and it is a genuine down-the-boulevard shot along the Central Blvd
canyon (facade to facade 268→332, i.e. 64 wide, centred on the road). The best
shots in the city are **diagonals across a junction**, which is why there is
no axial prefilter: a corner has the widest open cone in the city, which is
also why real photographers stand on corners.

**Step 5 — exclusions.** A candidate pair is dropped if:

| | Rule | Why, and where it comes from |
|---|---|---|
| **E1** | farm-belt blocks excluded | no street wall, no fingerpost, outside the slice |
| **E2** | viewpoint ≥ **24** studs from any station-lift bottom | `HANDOFF.md` §5. **This bites here, hard**: the Elevated runs down x/z = ±600, a lift bottom lands at 600 ± 25.5 = **574.5 / 625.5**, and the corner pavement centres either side of that avenue are at 450+123 = **573** and 750−123 = **627**. That is 1.5 studs. A viewpoint there is unclaimable — `City.Roads.prompt` runs *before* `E.prompt` and wins. Derived from `Roads` (§R1), never copied as numbers. |
| **E3** | viewpoint ≥ **24** studs from any of today's hunt spots — `huntNear(x, z, 576)` | The corner lot's own door is 17.6 studs away and a hunt spot sits at `door + t*±11 + n*2.5`, which lands **6.5 studs** from the corner pavement centre. `huntPrompt` runs first inside `E.prompt` (`CityEvents.lua:2012`), so the photo prompt would be shadowed. 24 = photo stand 10 + hunt claim 12 + 2. Evaluated **at event start**, not at server start — the hunt reseeds daily. |
| **E4** | viewpoint ≥ **26** studs from any live event's spot | Phase B's ≥12 rule, widened: photo stand 10 + find claim 14 + 2. 12 is enough for a *collect* item (no prompt, auto-pickup) but not for a find, and `E.list` iteration order is a hash order — two overlapping prompts would resolve nondeterministically. Evaluated at event start over `live`. |
| **E5** | not in `Config.Photo.Ban` | The measured deny-list. Keyed `"cx,cz,sx,sz|Subject Name"` — stable strings, never indices. §D5. |

Clear by construction against everything except thin street furniture, which
§D5 measures.

### D4. The view-cone test, exactly — and where it is enforced

**Enforced on the server, at claim time, from replicated character state. The
client asserts nothing.**

```
1  driving(player)                 -> refuse "get out of the car first"
2  pos  = cityPos(player)          -- existing, flattened, city-relative
   |pos - ev.pos| <= Photo.Stand (10)
                                   -> else refuse "stand on the green mat"
3  look = cityLook(player)         -- NEW, 4 lines: hrp.CFrame.LookVector,
                                   -- flattened to (X,0,Z) and unitised
   |look| before unitising >= 0.05 -> else refuse "hold still"  (ragdoll)
4  d    = ev.aimAt - pos  (flattened);  u = d.Unit
   dot     = look:Dot(u)              >= Photo.Cos      (0.819 = cos 35 deg)
   lateral = |d| * sqrt(1 - dot^2)    <= Photo.Lateral  (130)
                                   -> else refuse "turn to face <subject>"
5  crowd = # other players in the city with
             |their pos - ev.pos| <= Photo.Frame (14)
         and now - ev.aimT[their UserId] <= Photo.Grace (2.5)
6  pay(player, s, 150 + 30*crowd (cap 120), 25, "EventsDone")
```

**What counts as the landmark's extent: nothing. The cone is the extent.** At
the near limit (90 studs) a 35° half-angle is ±51.6 studs of lateral slack,
which is wider than any building in the city; at range the `lateral <= 130`
rule (half a block) takes over and binds from ~227 studs out. One angle rule
plus one lateral rule covers the whole 90–620 band with two lines, and nothing
has to know how big the Ferris Wheel is.

**Why 35° and not 15°.** The server sees the *body's* facing, not the camera's.
In shift-lock and first person they are the same; in free third person the
body faces the last movement direction. 35° means "walk at it and stop" always
works, which is the interaction we want, while still rejecting 81% of random
facings. It is a guess (§N9) and `Photo.Cos` is the dial.

**`aimT`, and why the 1 Hz loop earns its place.** `open` events currently skip
the reveal loop entirely (`:3170`). Add a small photo branch: once a second,
for each player within `Frame` of a live photo viewpoint, if they are aimed,
set `ev.aimT[UserId] = now()`. That does two jobs:
- it absorbs replication lag (the server's copy of a rotation is 50–100 ms
  stale, and a player who turns and presses in the same frame should not be
  called unaimed) — the claim passes on an instantaneous check **or** a
  `aimT` within `Grace`;
- it turns the crowd count from a knife-edge instant into a **2.5-second
  window**, so four people pressing over three seconds all count each other.
  This is the difference between a group photo and a lottery.

### D5. Trust — the honest analysis

Three claims are made at claim time. They are not equally verifiable, and the
important thing is **which way the money sits**.

| Claim | Who says it | Forgeable by a modded client? |
|---|---|---|
| "I am on the mat" | the server, from replicated `HumanoidRootPart.Position` | Yes — same as every claim in the game since phase A |
| "I am facing the subject" | the server, from replicated `HumanoidRootPart.CFrame` | Yes — **and by exactly the same mod**. It adds no new surface. |
| "the subject was actually visible" | **nobody at runtime.** Decided at server start by `clearLine`, and measured once by QA | Not forgeable — the client is never asked |
| "N other players were in the shot" | the server, from **other** players' positions | **No.** The claimant's client cannot fabricate them. |

Two conclusions, and they are the reason this is buildable:

1. **The unverifiable part was moved out of runtime.** Occlusion is not
   checked; it is *constructed*, the same discipline that put phase B's items
   on the +2 strip and phase D's Sminski at +2.5. A view-cone check the server
   cannot verify is not what this design contains.
2. **The most valuable part of the payout is the least forgeable part.** Base
   150 is forgeable; the crowd bonus, up to +120 — 44% of the maximum — is
   not, because it is other people.

**And the exploit is not worth writing.** A bot that teleports to the mat,
faces the subject and presses earns 150 base, once per event, at one photo
event every ~23 minutes (§N6): **≈390 coins/hour, against 11,220 coins/hour
for honest paced work.** 3.5%. Passes multiply both equally, so the ratio
holds on every account. There is nothing here to farm — which is the whole
reason the cheap version is safe and the full version (a camera, a subject,
a saved artefact) is not.

**The cheapest honest mitigation, and it is already in the design:** do not
ask the client anything, and keep the cadence low enough that the ceiling is
irrelevant. No heuristics, no signature, no server raycast. If a stronger
guarantee is ever wanted, the right one is not a raycast — it is to make the
crowd bonus the *majority* of the payout, because that part cannot be forged
at all.

**Measured, not derived: the street furniture.** `clearLine` models buildings.
It does not model trees, the fingerpost mast, traffic-light masts or the
Elevated's median columns. Those are thin and a photo with a lamp post in it
is still a photo — but a corner *tree* can genuinely block a grazing shot. The
answer is QA item 2: a **client-side** raycast sweep over every derived pair
(the world exists on the client, so a QA harness can raycast even though the
claim path must not), and every failure becomes one string in
`Config.Photo.Ban`. The derivation is the rule; the deny-list is the measured
correction. `Ban` lives in `Config.lua`, not `Places.lua`, so it costs
`server-engineer` and not `world-builder`.

### D6. How the player knows what to photograph, and where from

Entirely existing machinery. Nothing new is invented.

- **The announce toast** (existing `J.notify` stack): `PHOTO OP` /
  "face City Hall". Title 8 chars, sub 14 — both inside the ≤40 budget
  `npc-errands/CONTRACT.md` §3 records.
- **The clue**, in the existing `ev.clues` slot that phase A's `def.open`
  branch already fills: `"Main St & Central Blvd -- face City Hall"` (40
  chars). The corner's name is built from `Places.CityStreetsNS[cx + sx*150]`
  and `CityStreetsEW[cz + sz*150]`, both already exported at `Places.lua:73`.
  A street *corner* is the most natural address in the city and it is free.
- **The phone**: an ordinary row on `NOW IN TOWN`, `LayoutOrder` **10**, with
  its existing clock, clue and **GO** button. **No new phone section** — the
  reserved slots 20 / 40 / 60 stay free for whoever needs them next. This is
  the cheapest possible integration and it is deliberate.
- **GO** already calls `CityWayfind.W.to(pos, name)` — the green road ribbon,
  routed on the grid, eaten as you pass it.
- **The beacon**: `mark(ev, at)` draws it because `def.open` is true. Visible
  over the rooftops, which is how you find a corner without the map.
- **The fingerpost is already standing there** naming the landmark and its
  distance (`CityDress.lua:303`). On a SW corner the mast is 7.07 studs from
  the mat — inside the stand radius. The sign that tells you where to look is
  physically in the shot.
- **The mat**: a 12×12 `K.OPEN` green pad, `K.threshold`-style geometry
  (`CityKit.lua:244-248`), angled so its normal points at the subject. `K.OPEN`
  already means "you can use this" and is learned in four seconds
  (`CityKit.lua:236-239`). **The mat is the aim indicator**: it points.
- **The aim feedback** is the prompt card's own sub line, flipped by a local
  check the client can do for free (it has the viewpoint, the subject and its
  own character):
  - not aimed → `"turn to face City Hall"` (29 chars)
  - aimed → `"City Hall, dead ahead"` (21 chars)
  The server is still the authority; the client is only being polite.
- **Social proof while it is live**: `ev.found` already broadcasts on every
  claim, so the strip reads `4 SHOTS TAKEN`. A player on the way knows people
  are there. Zero new payload.

### D7. Daily, rotating, or always-available

**A rotating, director-scheduled headline event. Deliberately NOT daily, and
deliberately NOT always-available.**

- **Not daily.** Phase D owns the daily-reset habit with the Daily 3 Hunt.
  Two daily systems competing for one habit is the risk the brief names; the
  resolution is that this feature has **no day, no reset and no save field at
  all** (§D10). There is nothing for it to compete with.
- **Not always-available.** An always-open list of "views to collect" is a
  private checklist — the exact failure mode `LOOPS.md` §1 identifies as the
  CCU gap, and it would *also* compete with the Daily 3 for the
  collect-a-set habit. Rejected on both counts.
- **Rotating headline** is the only shape that makes it shared: one subject,
  one corner, announced to the whole server at once, so everybody converges.
  A photo op is worth building *because* everyone is sent to the same 20-stud
  square at the same minute.

**The rendezvous pick** is the highest-leverage line in the whole design.
Having chosen a subject at random, the director does not pick a viewpoint at
random: it picks, among that subject's surviving pairs, the one **minimising
the maximum travel distance over the players currently in the city**. On a
1-player server that degenerates to "nearest to them". A few hundred distance
sums, once per event. The director is now actively assembling a crowd rather
than hoping for one.

### D8. Session shape

- **3 minutes.** Probably no photo op at all (one every ~23 min). If one is
  live, it is the best possible three-minute event: no skill, no failure
  state, one walk, one press, a payout and a crowd. A 3-minute session is
  served by phases A and B; this is honest, not a defect to paper over.
- **15 minutes.** ~60% chance of one photo op. It is the one event in the
  window that reliably puts you next to other players, and the walk to the
  corner passes doors, litter and a hunt spot on the way.
- **60 minutes.** ~2–3 photo ops, different subjects, different corners. The
  real 60-minute reward is **learning the city's sightlines** — "you can see
  the wheel from Mochi St" is a genuine, pleasant, unwritten mastery, and it
  is the thing the full camera version would later be built on top of.

**The chain (optional, one line, add it after measuring).** The cycle ends
with several players standing together with nothing to do — the single best
moment in the game to fire the next thing. `pickSpot` could take an optional
`nearPos`, and for `Config.Photo.ChainR = 200` seconds after a photo window
closes the next **ambient** sighting prefers a lot within 200 studs of the
viewpoint. I would ship without it and add it **only if** measurement item 2
(§M) comes back healthy — if crowds are not forming, chaining onto them is
pointless.

### D9. Social, at 1 / 5 / 20 players — and on an empty server

- **Empty server.** The director never starts anything (`anyoneInCity()`,
  `:3188`). Nothing to be broken.
- **1 player.** `minPlayers = 1`. The pair chosen is nearest to them. Payout
  **150 base** for a ~60-second round trip = 150/min, i.e. *below* the 187
  job rate, which is exactly what `LOOPS.md` §6 asks of an event. A solo
  photo op is a small, pleasant, slightly-underpaid walk — and there is **no
  crowd requirement**, so this is not a social mode that starts with nobody in
  it.
- **5 players.** The rendezvous pick puts the corner near all of them. The
  crowd bonus makes waiting ten seconds for the others *rational* (+30 each,
  and there is no first-arrival bonus to lose — §N3), which produces five
  Sminski shoulder to shoulder on one corner all facing the same way. That is
  also the most screenshot-able moment the game has, which matters to the ad
  lane (`docs/AD_PROMPTS.md`).
- **20 players.** The mat is 12×12 and `Stand` is 10, which holds 8–10
  comfortably; `Frame` is 14 so latecomers on the edge still count *for
  others*. The crowd bonus caps at 4 others, so there is no incentive to pack
  20 in, and no scramble: every player can claim, so nobody is beaten to it.
- **The thing that would make me stop**: if the crowd figure in §M2 comes back
  at or below 0.25 on 5+ player servers, this feature is a private checklist
  with extra steps and should be cut, not tuned.

### D10. Saved data — **none. Zero fields.**

Nothing about a photo op is persisted. Not the subject, not the corner, not a
count, not an album. Consequences, stated plainly because phase D's bug is the
cautionary tale:

- **The sparse-array class of bug cannot occur here**, because there is no
  array, no `found`, no day key and no `saved()` back-fill. `data.City` gains
  nothing; a pre-phase-G save needs no migration and cannot throw.
- Re-claim protection is `ev.claimed[player.UserId]`, in memory on the
  server, keyed by UserId — so **leaving and rejoining mid-event cannot
  re-claim** (verified reading `:3101`). This is stronger than a save-backed
  flag, not weaker.
- A server restart mid-event loses the event, which is correct: it had 150
  seconds to live.
- `Places.CityLandmarks` may be **appended to freely** without touching this
  feature, because nothing here stores an index into it — the exact opposite
  of the constraint that governs fares, houses and lots.
- **The one thing I would have to add a field for is the one thing I am
  cutting**: a postcard album (§CUT 2). Say no to the album and the whole save
  layer stays out of phase G part 2.

### D11. Reuse versus new — ruthlessly

**Reused unchanged:** the director and its schedule, `minPlayers`/`weight`/
`warn`/`lasts`, `start()`'s event table, `publicEv`'s positional `spot`,
`finish()`, the `found` broadcast, the countdown strip and its `rank()`, the
notification stack, the phone's NOW IN TOWN section and its GO button,
`CityWayfind.W.to`, `mark()`'s beacon, `E.prompt`'s find loop, `pay()` (so
passes, boosts and the login streak all apply), the `EventsDone` meter tag,
`feed()` for CITY NEWS, `driving()`, `cityPos()`, `huntNear()`, `K.threshold`
/ `K.OPEN`, `Places.CityStreetsNS/EW`, `Places.CityLandmarks`,
`Places.cityDistrictAt`, `CityDress`'s fingerposts (as world furniture the
player already reads).

**New, and all of it small:**

| Where | What | Size |
|---|---|---|
| `Config.lua` | `Config.Photo` (§N1) + one `Config.Events.List` row (§N2) | ~30 lines of data |
| server, events block | the viewpoint derivation: corner enumeration, `clearLine`, pair table, E1–E5 | ~60 lines, runs once at start |
| server, `start()` | a `def.aim` branch: choose subject, rendezvous-pick the pair, synthesise the pseudo-lot, set `ev.aimAt` / `ev.subject` / its own clue | ~20 lines |
| server, find claim | steps 1–6 of §D4 | ~18 lines |
| server, 1 Hz loop | the `aimT` pass | ~12 lines |
| server | `cityLook(player)`; `publicEv` gains `subject`; one dev hook | ~10 lines |
| `CityEvents.lua` | `DRAW.photo` (the mat), `r = def.stand or EV.ClaimRadius - 2` in the prompt loop, the aim-flipped sub line, `crowd` in the reward toast, `ev.subject` in `upsert` | ~30 lines |

**Not new:** no remote, no `CityEvent` kind, no phone section, no save field,
no module, no `_sr_sync.lua` change, no `ownership.json` change, **no art**,
no geography, no archetype.

---

## NUMBERS

### N1. `Config.Photo`

```lua
Config.Photo = {
    -- GEOMETRY (derived, not measured -- see loop.md D3)
    Corner   = 123,   -- studs out from a block centre, both axes, to the
                      -- pavement corner centre. = BLOCK/2 - WALK_W/2
                      -- = 130 - 7. Facade 118, turret face 116, kerb 130:
                      -- 5 clear of the wall, 7 inside the kerb, so traffic
                      -- cannot reach you here.
    Half     = 118,   -- a block's building half-width (the facade line)
    Eps      = 1,     -- AABB shrink, so a sightline along a facade is clear
    OwnPad   = 16,    -- street-wall depth: how far outside its own AABB a
                      -- landmark point may sit and still own that block

    -- RANGE
    Near     = 90,    -- same number the fingerpost uses for "down this road"
    Far      = 620,   -- 2 blocks + 2 roads, and inside the range Weather's
                      -- fog cap keeps legible (it is set for 700-stud signs)

    -- THE AIM
    Stand    = 10,    -- claim radius at the mat (mat is 12x12)
    Frame    = 14,    -- crowd-counting radius: wider, so somebody on the
                      -- edge of the group still counts FOR the others
    Cos      = 0.819, -- cos(35 deg) half-angle. GUESS -- see N9
    Lateral  = 130,   -- max perpendicular miss, studs. Half a block. Binds
                      -- past ~227 studs; inside that the cone is tighter.
    Grace    = 2.5,   -- seconds an `aimT` stays warm: absorbs 50-100ms of
                      -- replication lag AND widens the group window to 2.5s
    MinLook  = 0.05,  -- flattened LookVector magnitude below which the
                      -- character is ragdolled/upended -> "hold still"

    -- MONEY (all BASE coins; pay() multiplies by passes, boosts and streak)
    Coins    = 150,
    Xp       = 25,
    Crowd    = 30,    -- per OTHER player in frame
    CrowdMax = 120,   -- cap = 4 others. Max base payout 270.

    -- SEPARATION (inherited, never re-derived)
    ExcludeR = 24,    -- from a station-lift bottom. Config.Hunt.ExcludeR.
    ClearHunt= 24,    -- from one of today's three: Stand 10 + Hunt.Claim 12 + 2
    ClearEv  = 26,    -- from a live event spot: Stand 10 + ClaimRadius 14 + 2

    Skip     = {},    -- landmark NAMES that are bad subjects. Empty on ship.
    Ban      = {},    -- measured deny-list, "cx,cz,sx,sz|Subject Name".
                      -- Filled from QA item 2. Strings, never indices.
    ChainR   = 0,     -- 0 = off. See loop.md D8; turn on only after M2.
}
```

### N2. The `Config.Events.List` row

Appended after phase B's three. Nothing above it changes.

```lua
{ id = "photo", kind = "find", open = true, title = "PHOTO OP", icon = "star",
  verb = "SAY CHEESE",
  warn = 45, lasts = 150, weight = 20, minPlayers = 1,
  coins = 150, xp = 25,
  aim = true, stand = 10 },
```

- `warn = 45` — the truck uses 50; 45 is one crossing plus two blocks on foot.
- `lasts = 150` — 2:30. Shorter than the truck's 170 because there is nothing
  to *do* at the destination, and a window that outlives the crowd wastes the
  strip.
- `icon = "star"` — exists. A camera icon is art (§CUT 10).
- **No `first` / `firstN`, on purpose.** A first-arrival bonus would fight the
  crowd bonus: waiting one more person is +30, losing the first-3 slot is −60,
  so a race bonus actively discourages the behaviour the feature exists to
  buy. There is no race here. Dropping it also removes a field.

### N3. The payout, with the arithmetic

Reference: a paced job earns **187 base coins/min** (`LOOPS.md` §6).

A typical participant spends: read the toast (2s) + travel (30–50s) + aim and
press (5s) ≈ **50–60 seconds**, and the window is announced 45s ahead so the
travel is mostly free time.

| In frame | Base coins | Per minute (60s trip) | vs 187/min |
|---|---|---|---|
| alone | 150 | 150 | 0.80× |
| +1 | 180 | 180 | 0.96× |
| +2 | 210 | 210 | 1.12× |
| +3 | 240 | 240 | 1.28× |
| +4 or more | **270** | 270 | 1.44× |

So a solo shot is *under* a job, which is correct, and the only way to beat a
job is to stand next to four other people — the behaviour being purchased.

**Quoted numbers are BASE.** `pay()` applies CITY PRO, VIP, 2× COINS, the
login streak and any boost, and `HANDOFF.md` §5 records the observed
all-passes factor as **4.5×** (460 base → 2,070). So a 270-coin photo op is
**1,215 coins** on an account holding every pass, and QA must express
expectations as the formula `base × citypro × coinMult × boost ×
StreakMult(streak)`, never as a number
(`npc-errands/CONTRACT.md` §6.7).

### N4. Why the cadence is the real economy guardrail

This is the load-bearing calculation, and it is what sets `weight`.

One headline cycle ≈ `warn (avg 45) + lasts (avg 165) + Gap (avg 180)` ≈
**390s ≈ 6.5 min**. Six headline rows after this one lands. At `weight = 10`
against five other tens, photo is 1 in 6 headlines = one every **~39
minutes** — too rare to matter to anybody. At `weight = 20` it is 2 in 7 =
one every **~23 minutes**.

Cost of that choice, stated: every other headline becomes **~30% rarer**
(from 1-in-5 to 1-in-3.5 share for photo). That is a real price and it is
`OPEN QUESTION 1`.

Income added to every player, at 23-minute cadence and ~210 average base:

```
210 / 23 min  =  9.1 base coins/min  =  4.9% of the 187/min job rate
```

Under 5%, which is where an event's contribution belongs. **And this is why
the photo op cannot be an ambient event**: the ambient clock is 70–130s, so a
photo op in that slot would fire every ~3.5 minutes and add
`210 / 3.5 = 60 coins/min` — a **32% raise for everybody**, which is the same
mistake `LOOPS.md` §6 caught with free capsules. The cadence, not the payout,
is the guardrail. Headline row, weight 20.

### N5. The capsule meter, and the corrected non-cosmetic rule

- The photo op grants **no capsule ticket**. `LOOPS.md` §6 (corrected) is
  explicit that capsule characters are **not** cosmetic — all 15 carry a live
  passive, `Secret` is `coin = 2` — so "just give a collectible" is not
  economy-neutral, and this feature does not lean on the exemption that was
  voided. Phase D owns ticket granting.
- It *does* credit the meter, because it pays through `pay()` with
  `stat = "EventsDone"`, which is already on the whitelist
  (`Config.lua:1169`). 150–270 units of the 1,870 per ticket = **8–14% of a
  ticket per shot**. At one event per 23 minutes that is **≈0.13 extra
  tickets per hour**. Recorded so nobody has to rediscover it; no action.
- The 187 units/min ceiling means a photo op cannot spike the meter even if
  it paid more.

### N6. The scripted player, and the AFK player

- **AFK**: a photo op pays only on a press, from a position, facing a
  direction. Standing still earns nothing. There is no time-based component
  anywhere in the feature.
- **Scripted**: §D5 — a perfect bot earns 3.5% of an honest working rate,
  because the cadence caps it. Nothing to protect.
- One asymmetry worth noting: a bot *parked* on a corner does not know which
  corner will be picked, and the rendezvous pick depends on where the
  **other** players are, so camping a specific corner is strictly worse than
  reading the announcement.

### N7. The candidate-pair budget

96 corners × 9 subjects = 864 pairs before filtering. The range band drops
most; `clearLine` drops most of the rest. I expect **60–200 surviving pairs**,
clustered along the Central Blvd / Mochi St / Cloud St bands (because all nine
subjects live in `|z| <= 300`) — which is the downtown slice, arrived at by
derivation rather than by decree.

**This number is unknown until the dev hook prints it, and it is the kill
signal**: see §D12.

### N8. Startup cost

~24 blocks enumerated, ~864 range tests, a few hundred slab tests × 36 blocks
≈ 10–20k slab iterations. Comparable to the `centreLots` O(n²) pass over 381
lots that already runs at start (`:2602-2647`) and much smaller than the ~380
hashes plus a sort the hunt does per day. Once, at server start. Not per event.

### N9. Which numbers are guesses, and what would settle them

**There is no telemetry in this repo at all** (verified). So:

| Number | Basis | What settles it |
|---|---|---|
| `Cos = 0.819` (35°) | **guess** | A dev hook that prints the live dot product: have QA walk to ten pairs with a thumbstick and with shift-lock and record the distribution of the angle error at the moment they press. If the 90th percentile is under 20°, tighten to 25°. |
| `Far = 620` | derived from the fog cap, **not** a legibility measurement | Stand at the far end of the longest surviving pair at noon, at 02:00, and in the foggiest weather state (`city("sky", "storm")`) and say whether the subject reads at Sminski eye level. |
| `Near = 90` | borrowed from `CityDress.lua:287` | Same session: is 90 studs too close to read as a photo *of* something? |
| `Coins = 150` | derived: 187/min × ~48s, deliberately just under | Nothing to settle; it is a policy choice. |
| `Crowd = 30`, `CrowdMax = 120` | **guess** about what is worth waiting ten seconds for | §M2 — if the mean crowd is ~0 on a 5-player server, the bonus is too small to change behaviour (or the rendezvous pick is wrong). |
| `warn 45` / `lasts 150` | inherited from the `icecream` row (50/170), **never measured** | §M1's funnel: if players are still arriving when the window closes, `lasts` is too short. |
| `weight = 20` | derived from §N4's cadence arithmetic | The arithmetic is sound; the *taste* of "every other headline 30% rarer" is OPEN QUESTION 1. |
| `Grace = 2.5` | **guess**, sized at 2 sampling ticks + margin | §M3: if "turn to face" refusals exceed 1.0 per successful claim, suspect `Grace` before `Cos`. |
| the §M targets (55%, 0.6) | **guesses with no baseline** — `LOOPS.md` §7's three baseline numbers were never logged | They become real after the first week of the counters in §R3. |

---

## EDGE CASES

| Case | Behaviour |
|---|---|
| **Empty server** | The director never starts anything. No code path to consider. |
| **One player** | `minPlayers = 1`; the pair is chosen nearest to them; 150 base; no crowd requirement anywhere. |
| **A player who joins mid-window** | The `state` reply already lists live events, and `spot` is public for `open` events, so the mat, the beacon, the strip clock and the phone row all appear with **no new code**. They can claim for the remaining window. |
| **Leaves and rejoins mid-window** | `ev.claimed[UserId]` lives on the server; re-claim is refused silently, exactly as phase A (`:3101`). |
| **Leaves after being counted in someone's crowd** | Harmless: `crowd` was evaluated and paid at that instant. No later reconciliation. |
| **A scripted player** | §D5/§N6. 3.5% of a working rate; no mitigation shipped, by decision. |
| **In a car** | Refused: `"get out of the car first"`. A car's facing is the car's, the car is in the road, and standing to take a photo is the fantasy. Uses the existing `driving(player)`. |
| **Knocked flying by traffic / ragdolled** | The flattened LookVector collapses → `"hold still"`. Also largely prevented: the mat is 7 studs inside the kerb, where cars do not reach. |
| **Sitting on a bench or a hangout blanket** | Body facing is the seat's facing. If it happens to be aimed, the claim passes. No special case; a photo from a bench is fine. |
| **Inside a shop, a flat or a lobby when the announcement lands** | Underground interiors are at y = −420; `cityPos` returns a flattened city-relative position regardless, but `Activity ~= "city"` inside a lobby gates it. They walk out; the window is 150s. |
| **A station lift lands on the chosen corner** | Cannot happen: E2 removes those pairs at startup, and QA item 3 prints the minimum distance the way phase D printed 26.31. |
| **One of today's hunt Sminski is on the corner lot** | Cannot happen: E3, evaluated at event start via `huntNear`. |
| **Another live event within 26 studs** | Cannot happen for the photo op (E4 at start). For the reverse — a *later* find placed onto a live photo viewpoint — `pickSpot` needs the same forward-slot rejection phase D gave it (§R2). |
| **The subject is a building the player has never seen** | Fine. The mat points at it, the clue names it, the fingerpost gives the bearing and the distance. |
| **Night / rain / fog** | No test depends on visibility. The fog cap already keeps 700-stud signage legible, and `Far = 620` sits inside it. Fog-aware pair selection is cut (§CUT 5). |
| **Nobody claims at all** | The window closes, `finish()` removes the mat and the beacon, nothing is saved, and the director moves on. There is no failure state, no partial credit and nothing to clean up. |
| **`Roads` cannot be required** | Phase D's precedent: warn and run unfiltered (`:3375-3379`). Do the same — but `warn("[photo] Roads unavailable; viewpoints unfiltered")` **and** log the pair count, so the unfiltered case is visible rather than silent. |
| **Fewer than 1 surviving pair for the chosen subject** | Pick another subject. If **no** subject has a pair, the row must not be schedulable: `warn` once at startup and drop `photo` from the headline pool for the life of the server. A headline that starts and has nowhere to go is worse than one that never fires. |

---

## NEEDS FROM OTHER LANES

**R1 — `server-engineer`: lift the station-lift `blockers` table out of the
hunt's `do` block.** It is currently local to the phase-D block
(`SminskiServer.server.lua:3354-3380`) and derived from `Roads`. Phase G part 1
already asks for exactly this (`npc-errands/CONTRACT.md` G3: "one shared
exclusion helper is the fix. Do not write a third copy of the rule"). This
spec is the **fourth** consumer. Please make it one helper in the events
block's scope — `evBlocked(x, z, r)` — used by the hunt pool, errand spots and
the photo derivation. I am not designing its signature for you; I am naming
that all four need it.

**R2 — `server-engineer`: `pickSpot` must reject a lot whose hidden spot is
within `Config.Photo.ClearEv` of a live photo viewpoint.** Same forward-slot
shape phase D used for `huntLotTaken` (`:2656-2662`), same bounded retry. This
is the *reverse* direction of E4: E4 keeps the photo op away from live events,
this keeps later events off the photo op. Without it a sighting can land 6.5
studs from the mat and one of the two prompts becomes unreachable.

**R3 — `server-engineer`: three counters, printed, because there is no
telemetry.** At each photo window's close, one `print`/`warn` line:
`players in city at announce · distinct players who entered Stand · claims ·
mean crowd at claim · refusals by reason`. Five integers and a float on one
line. Without them §M is unanswerable and this spec's numbers stay guesses
forever. This is the same gap `LOOPS.md` §7 flagged and nobody has closed.

**R4 — `client-engineer`:**
- `E.prompt`'s find loop: use `def.stand or (EV.ClaimRadius - 2)` as the
  radius, so the row's `stand = 10` binds. One expression.
- `DRAW.photo(ev, at, face)`: the 12×12 `K.OPEN` mat, from `K.threshold`'s
  recipe, oriented on `face`. No new art, no per-item light
  (`performance.md`), pooled like phase B's items.
- The aim-flipped sub line (§D6) — a local check, never an authority.
- `upsert` should carry the new public `subject` string onto `ev`.
- **No phone section.** Reserved `LayoutOrder` 20 / 40 / 60 stay free.

**R5 — `world-builder`: nothing, and that is deliberate.** No new list in
`Places.lua`, no new geography, no change to `CityLandmarks`. The one
conditional ask: if QA item 2 finds a *corner tree* blocking an otherwise good
sightline, the default fix is a `Config.Photo.Ban` string (`server-engineer`);
only escalate to moving a tree if the same tree kills several good pairs.

**R6 — copy: four strings, and they are short.** `PHOTO OP` (title, ≤ 14),
`SAY CHEESE` (verb, ≤ 12), the four refusals verbatim —
`stand on the green mat` · `turn to face <subject>` ·
`get out of the car first` · `hold still` — and the news line
`"<name> and N others got <subject> from <street>!"`.

**R7 — QA: the raycast sweep harness.** A Studio-only client script that walks
every derived pair, teleports, waits ~3s for streaming (`HANDOFF.md` §2), and
raycasts from Sminski eye height at the viewpoint to `y = 8` at the subject.
This is the only place a raycast is legitimate in this feature; it must never
appear on a claim path.

---

## QA SHOULD CHECK

Play-mode screenshots come back solid magenta (`HANDOFF.md` §2), so every UI
item below is verified **numerically** — prompt title/sub text read from the
instance, `AbsolutePosition`, the ancestor `Visible` chain and
`GetGuiObjectsAtPosition`.

1. **Dev hook `EventsDev:InvokeServer("photoPairs")`** prints every derived
   pair: corner, subject, range, computed `face`, and the totals. PASS:
   **≥ 40 pairs**; every corner exactly `Photo.Corner` from its block centre
   on both axes; every range in [90, 620]; zero pairs on a farm block.
   **< 40 pairs is the kill signal — see §D12.**
2. **Sightline sweep** (R7) over 100% of pairs. PASS: ≥ 90% reach the subject
   unobstructed, and every obstruction is either (a) street furniture under 3
   studs wide — mast, column, lamp, trunk — which is acceptable, or (b) a
   building, which is a `clearLine` **bug** and must be fixed rather than
   banned. Every (a) that blocks more than half the subject goes in
   `Config.Photo.Ban` with its measured reason.
3. **Exclusions, with numbers, the way phase D printed 26.31.** Print the
   minimum distance from any shipped viewpoint to (i) a station-lift bottom —
   PASS ≥ 24, (ii) each of today's three hunt spots across **at least two
   seeded days** (`huntSeed`) — PASS ≥ 24, (iii) every live event spot at
   start — PASS ≥ 26.
4. **Prompt ownership.** Standing on the mat, the prompt's title reads
   `PHOTO OP` and nothing else wins it. Explicitly confirm `City.Roads.prompt`
   returns nil at every shipped viewpoint (it runs first and would win).
5. **Claim matrix.** Refused at 12 studs / paid at 9. Facing 180° away →
   refused. Dead on → paid. 40° off → refused; 30° off → paid (this is the
   `Cos` boundary and it must be exercised from both sides). Driving → refused
   with the car string. Second claim → silently refused. Ragdolled (walk into
   traffic) → `hold still`.
6. **Crowd and grace.** Two test clients on one mat: both replies carry
   `crowd = 1`. One turns away and claims 2s later → still `crowd = 1`
   (grace). At 4s → `crowd = 0`. This is the feature; test it directly.
7. **The lateral rule is actually wired.** At a ≥ 500-stud pair, aim 15° off
   (dot 0.966 passes `Cos`, lateral ≈ 130+) → **refused**. If this passes,
   `Lateral` is not connected.
8. **Payment is a formula.** Expect `(150 + 30 × crowd) × citypro × coinMult ×
   boost × StreakMult`, never a hardcoded number
   (`npc-errands/CONTRACT.md` §6.7). Verify base ∈ [150, 270] on a bare
   account, and that the cap holds at 5+ in frame.
9. **Mid-window join** draws the mat, the beacon, the strip clock and the
   phone row from the `state` reply alone, with no extra push.
10. **No save field.** Dump `data.City` before and after ten photo claims:
    **identical key set**. A rejoin mid-window cannot re-claim.
11. **Meter.** A photo claim credits the meter by exactly its base coins
    (`EventsDone`), and does **not** grant a ticket.
12. **Cadence and economy.** Force 10 photo events (`EventsDev`) and print
    total base coins paid; PASS: mean base per claim ∈ [150, 270]. Separately
    confirm from the headline log that photo takes ~2 of every 7 headlines.
13. **Nobody claims**: the window closes, the mat and the beacon are gone
    (count instances under `K.actors`), no warning in the console.
14. **Phases A, B and D unregressed**: finds and collects still announce,
    claim, pay and expire; the Daily 3 still reveals and claims; the strip and
    tray behave; the phone's reserved `LayoutOrder` 20 / 40 / 60 are still
    empty.

### What would make me stop and rethink (§M)

- **M1 — funnel.** announced → entered `Stand` → claimed, per event.
  Target ≥ **55%** of players who were in the city at announce time claim.
  **Rethink if < 30%**, and look at *where* they fall out: arrived-but-never-
  claimed points at the aim step (change `Cos`), never-arrived points at
  `warn`/the rendezvous pick.
- **M2 — co-presence, the reason this exists.** Mean `crowd` at claim, and
  the share of claims with `crowd >= 1`, on servers with 5+ players in the
  city. Target ≥ **0.6** of claims have somebody else in frame.
  **If it is ≤ 0.25, cut the feature** — it is a private checklist and the
  crowd bonus is not buying anything.
- **M3 — refusals.** `turn to face` refusals per successful claim. Target
  ≤ **1.0**. Above that, the cone or the aim feedback is wrong; the number to
  change is `Photo.Cos` or `Photo.Grace`, **never the payout**.

### D12. The kill condition, stated in advance

If QA item 1 returns **fewer than 40 pairs**, the derivation is wrong, and the
only remedy is a hand-placed viewpoint list in `Places.lua` — another owner's
append-only file, plus a Studio measurement pass per entry. At that point this
is no longer the *cheap* Photo Hunt, and the correct call is to put it back in
`LOOPS.md` §5 "Deferred, and why" with the pair count written down, rather
than to pay for a new list. I would rather record that than discover it
halfway through the build.

---

## CUT / DEFER

1. **The full version** — camera mode, subject detection, "photograph someone
   working", a saved photo artefact. Unchanged from `LOOPS.md` §5. Everything
   above is deliberately built so the full version can land later *on top of*
   it: the pair table becomes the shot list, the cone becomes the viewfinder.
2. **A postcard album** (`spotted`-style, "6 of 9 views"). Cut, for two
   reasons: it is the only thing in the feature that would need a save field,
   which reintroduces the entire class of bug phase D shipped; and it is a
   private checklist competing with the Daily 3 for the collect-a-set habit.
   Note for later: a *cosmetic* album would be covered by `LOOPS.md` §6's
   surviving exemption, so it is cheap to add once §M2 proves the loop works.
3. **Photographing players or NPCs.** Needs subject detection. Deferred by
   the brief.
4. **Rooftop and Elevated-platform viewpoints.** There is no rooftop access
   system in the city (verified — `rooftop` appears in `CityBuild.lua` only as
   clutter), and a station platform is a `City.Roads` prompt zone, which is
   the one place a claim is provably unreachable. New geography; out of scope.
5. **Fog-aware or hour-aware pair selection.** The director can filter by
   weather, but `Far` already sits inside the guaranteed-legible band, so this
   is complexity for a case that cannot occur.
6. **A "hold still for 3 seconds" dwell, a shutter animation, a flash.** The
   grace window already gives the group behaviour a dwell buys, without a
   second interaction state. A flash is a dynamic light per shot, which
   `performance.md` would not thank us for.
7. **A dedicated phone section.** It is an ordinary event; NOW IN TOWN
   (`LayoutOrder` 10) already lists it with a clock, a clue and a GO.
   20 / 40 / 60 stay reserved.
8. **Any new remote, any new `CityEvent` kind.** Everything rides `rf("Events")`
   `action = "claim"` and the existing `start` / `found` / `end` kinds.
9. **Subjects outside the three central districts** (nine excluded). Keeps
   every trip inside the dense core and inside the vertical slice.
10. **A camera icon and a viewfinder overlay.** Both are art — a Blender lane
    and a human approval gate — for a 24×24 glyph and a frame. `star` ships
    today. If the human wants the icon, it is the *only* art this feature
    would ever ask for, and it is optional forever.
11. **The chain onto the crowd** (`ChainR`). Shipped as `0` = off. Add only
    after §M2 comes back healthy; chaining onto a crowd that is not forming is
    pointless.

---

## OPEN QUESTIONS FOR THE HUMAN

1. **`weight = 20` makes every other headline about 30% rarer.** §N4 shows
   the cadence, not the payout, is the economy guardrail: at weight 10 a photo
   op fires once every ~39 minutes and most sessions never see one; at 20 it
   is ~23 minutes and adds 4.9% to income. I shipped 20. Is taking that share
   from Cash Drop / Balloons / Cleanup / Lost Pup / Ice Cream the trade you
   want? *(Money and taste.)*
2. **Crowd bonus size: +30 each capped at +120 (max base 270, 1.44× the job
   rate at full crowd), or +40 capped at +160 (max 310, 1.66×)?** The higher
   number breaks `LOOPS.md` §6's one-minute-of-job-income rule harder, but it
   is the only lever that pays for co-presence, which §1 says is the actual
   CCU gap. I chose the conservative one. *(Money.)*
3. **`minPlayers = 1` or `2`?** At 1, a lone player gets a pleasant,
   deliberately-underpaid 150-coin walk and the feature teaches itself on a
   quiet server. At 2, the crowd is the whole point and a solo shot never
   happens. I chose 1 because a social mode that starts with nobody in it is
   a bug — but "a postcard with nobody in it" is a taste call about what the
   moment is *for*. *(Taste.)*
4. **Wording.** `PHOTO OP` / `SAY CHEESE`, or `POSTCARD` / `SNAP`, or
   `PHOTO HUNT` to match the plan's own name? The title must stay ≤ 14
   characters for the phone row at `titleTS 17`. *(Taste.)*
5. **Do you want "collect all the views" to become a habit later?** §CUT 2
   defers the cosmetic album. It is cheap to add and it is the natural bridge
   to the full camera version — but it is a second collection habit next to
   the Daily 3, and you have already been careful about not running two.
   *(Business.)*
