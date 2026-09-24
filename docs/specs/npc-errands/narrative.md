# NPC errands -- narrative

Phase G, `docs/LOOPS.md` §5 and §3: *"`npcSay` exists; an errand is a FIND
with a single-player scope and a saved story index per NPC."* This spec is
that line, written out. Photo Hunt, Power Outage and neighbour knocks are
out of scope -- not mine, not here.

---

## WHAT EXISTS ALREADY

| Fact | Where | What it means for this design |
|---|---|---|
| `npcSay(n)` builds a 250x66px billboard pill (54px tall, `TextWrapped`, `TextSize 15`, 4.5s then destroyed), anchored to `n.rig.body`, fired on a per-NPC 10s cooldown after 2s of lingering nearby. | `game/City.lua:2565-2598`, caller `:172-189` | This is the **display budget**, not the trigger. Every spoken line in this spec is written to read comfortably in that pill -- one short sentence, ~40 characters, same register as the existing `CHAT` table (`:2559-2564`, whose longest line is 36 characters: *"Have you met your neighbours yet?"*). It fires on **wandering, anonymous pedestrians** (`S.people`), not on a fixed shopkeeper -- see the next row. |
| Every non-food shop unit (`kind="midrise"`/`"shop"`, `btype` anything except cafe/bakery/restaurant/deli) already builds a standing Sminski **keeper** behind its till, in the shop's own body colour, facing the door. | `game/CityBuild.lua:1020-1026` (`fitShop`) | This is the errand-giver, already in the world, already dressed, already standing at a real address. **Zero new art.** The keeper currently does nothing but stand there. |
| The Job Center already builds a named-in-spirit **clerk** at a desk, in a tie, next to a job board and waiting chairs. | `game/CityBuild.lua:1247-1253` | The single strongest anchor for a cast member -- fixed, civic, always the same look (see below), and it already sits at `Places.CityLandmarks`' "the Job Center." |
| The keeper's/clerk's look is `Config.Characters[(i*3+k) % #Config.Characters + 1]` where `i` is the lot's stable index into `Places.cityLots()`. | `CityBuild.lua:1025`, `:1252` | Deterministic. **The same shopkeeper, in the same colour, stands at the same address on every server, every session.** A returning player really can recognise "the florist." I am relying on this. |
| Food venues (cafe/bakery/restaurant/deli, incl. the pizzeria) get counters and stations but **no standing keeper NPC.** | `game/CityBuild.lua:1166` (`fitFood`/`fitKitchen` vs `fitShop`), confirmed no `buildSminski` call in either | The bakery/pizzeria cannot host a talking errand-giver **without new build work**. Flagged below; my cast avoids food venues for this reason. |
| `lot.npc = d % 2 == 0` is set on every other midrise lot and **read nowhere in the codebase.** | `game/Places.lua:319`, confirmed via repo-wide grep | An unused hook. I suggest the errand system claims it: "this lot's keeper talks" reuses a flag that already exists instead of adding a new one. |
| The FIND archetype's fairness machinery already exists and is tested: `compass(from, to)` (north = +Z, matches the map), `streetOf(lot)`, `nearestLandmark(pos)`, `areaOf(lot, pos)`, producing exactly the clue shapes `"{compass} of {landmark}"` and `"on {street}, near {landmark}"`. | `game/SminskiServer.server.lua:2213-2236` | I do not invent a new clue grammar. My one "send the player elsewhere" beat per NPC reuses these two exact templates, verified against real `Places.CityLandmarks` entries ("City Hall", "the Job Center"). |
| FIND events already scatter a hidden spot on the `+2` clear pavement strip in front of a real lot's door, secret until `RevealRadius`, claimed within `ClaimRadius`, paid through `pay()`. | `Config.Events` (`Config.lua:1003-1046`), `SminskiServer.server.lua` ~2238-2270 | The mechanical FIND (hidden spot, reveal radius, claim radius, server-authoritative pay) already exists for Lost Pup/Ice Cream Truck. An errand's "find" step should be the same mechanism scoped to one player, not a new one. |
| Reward scale for comparison: a parcel run pays 67-105 coins, a taxi fare 75-125, a pizza order 52-131, Lost Pup 260 (a multi-minute, citywide, multiplayer chase). Paced job income is ~187 coins/min. | `docs/ROADMAP.md` job-system section; `Config.Events.List` (`Config.lua:1012-1015`) | My rewards (below) are pitched well under Lost Pup's, because an errand find is much shorter and usually right next to the NPC -- see NUMBERS. |
| `Places.CityBlocks` gives downtown exactly four blocks: `cityhall`, `postbank`, `towersW`, `towersE` (all centred at (±150,±150)), plus two attached landmarks, the Job Center (150,0,-268) and the pizzeria "Slice of Life" (268,0,-150), both inside the same footprint. | `Places.lua:76-77, 91-93, 139-149` | This *is* the "4-6 block downtown slice" the brief asks for. Every errand-giver and every find in this spec stays inside it. |
| `SHOPS` (27 kinds) is cycled deterministically across each wall's lot slots by `(d + seed) % #SHOPS`, seed 0 (towersW) / 9 (towersE) / 4 (cityhall) / 16 (postbank). Working the arithmetic through, `books`, `pets`/`PET SHOP`, `flowers`/`FLORIST`, `clothes`/`tailor` all fall inside downtown's 24-96 lot slots for at least one of the four blocks. | `Places.lua:184-236, 285-353` (`WALL`, `SHOPS`, the lot-assignment loop) | Gives me real, existing shop kinds to hang a florist/bookseller/tailor/pet-shop keeper on **without inventing geography**. Not measured in Studio -- see REQUESTS. |

---

## THE DESIGN

### The errand structure, in narrative terms

An errand is a small serial with a **saved story index per NPC** (that is
the entire save shape -- see NUMBERS). The index points at the current
*beat*. Visiting the NPC:

- **index has an open task, not yet done** -> the NPC's personal "not yet"
  line (a short pool, below).
- **index has an open task, the item was just found** -> the beat's `say`
  (thank-you for the old item + ask for the new one, or thank-you + closing
  if this was the last beat) fires once, the index advances, a new task
  opens (unless this was the closing beat).
- **index is past the last beat** -> the arc is done. The NPC has no more
  tasks and instead cycles through a personal **epilogue pool** (5
  variants per NPC, so a player who keeps visiting after finishing never
  hears the exact same line twice in a row) forever. No further reward. It
  does not loop back to beat 1 -- a finished story that quietly restarts
  itself stops feeling like a story.

Every arc's **beat 1 stands alone**: it reads as a complete, satisfying
little request even if a player never comes back (per the design rule that
a story must make sense from beat 1 alone).

Arcs are 4 beats (3 finds + a close) except the bookseller, who gets 5 (4
finds + a close) -- one NPC allowed to run a beat longer, because her arc is
the odd, quiet one and it earns the extra turn. No calendar/day gating
(see OPEN QUESTIONS -- the brief's own example uses one, I did not).

### The cast

Five NPCs, all standing inside the four downtown blocks, all reusing a
keeper or clerk that the city already builds.

| NPC | Who | Where (real) | Voice, one line |
|---|---|---|---|
| **Nell** | the Job Center clerk | the Job Center desk (`CityLandmarks`: "the Job Center") | Brisk, dry, quietly proud of her board. |
| **Marlow** | the florist | a `flowers`/FLORIST shop keeper, downtown | Warm, chatty, can't stop smelling things. |
| **Wren** | the bookseller | a `books` shop keeper, downtown | Quiet. Slightly magical. Says less than she knows. |
| **Oskar** | the tailor | a `clothes`/`tailor` shop keeper, downtown | Fussy, precise, secretly delighted by help. |
| **Fern** | the pet shop keeper | a `pets`/PET SHOP keeper, downtown | Soft-hearted, easily worried, loves the shy ones. |

Wren is the "one or two odder, quieter voices" `design.md`/`character.md`
ask for -- everyone else is warm daylight; she is the sliver of "slightly
magical, slightly mysterious" the Sminski itself is built from.

### The dialogue

Format below matches the data shape: each beat's first `say` line is the
**thank-you for the previous find** (skipped on beat 1, which is a pure
ask), the second is the **new ask**. The closing beat has no task. `wait`
lines fire on repeat visits while a task is still open. `epilogue` lines
fire forever once the arc is done.

Character counts are given for anything at the display limit; the rule
throughout is **≤ 40 characters per spoken line** (the existing `CHAT`
table's longest line is 36).

#### Nell -- the Job Center clerk

Shared "not yet" pool (also used by Marlow, Oskar and Fern -- see NUMBERS
for why this one is shared rather than five separate pools):

1. "Not yet? Keep looking." (22)
2. "No luck? It's got to be close." (31)
3. "Still missing. Try again?" (26)
4. "Hmm, not there? Try nearby." (27)
5. "Nothing yet. Don't give up!" (27)

Beats:

1. **Ask:** "The job board is a mess again." / "My stapler walked off.
   Again." -- **find**, hint *"on the steps outside"* (fixed, doorstep,
   no clue system needed). Reward 45.
2. **Thanks + ask:** "You found it! You're a natural." / "Now the OPEN pin
   has blown off too." -- **find**, hint *"just outside, chasing the
   wind"*. Reward 55.
3. **Thanks + ask (the away beat):** "The pin's back up. Marvelous." /
   "Now my whistle's rolled off somewhere." -- **find**, hint *"somewhere
   downtown -- listen for it"*, clue template `"{compass} of City Hall"`.
   Reward 120.
4. **Close:** "My whistle! Music to my ears." / "Best assistant this
   board's ever had."

Epilogue pool (5): "Board's tidy today. Rare." / "New listings went up
this morning." / "We're all square. Thank you again." / "The whistle
hasn't moved once." / "Quiet day at the board."

#### Marlow -- the florist

1. **Ask:** "My watering can's gone walking." / "Have you seen it round
   the shop?" -- **find**, hint *"behind the flower buckets"*. Reward 45.
2. **Thanks + ask:** "Found it! You've got a green thumb." / "Next: my
   best seed packet blew off." -- **find**, hint *"just past the front
   step"*. Reward 55.
3. **Thanks + ask (away):** "Seeds recovered. Bless the wind." / "Now my
   lucky trowel's missing too." -- **find**, hint *"somewhere out there,
   downtown"*, clue template `"on {street}, near {landmark}"`. Reward 120.
4. **Close:** "My trowel! You saved market day." / "This bouquet's half
   yours, really."

Epilogue pool (5): "The peonies are extra fresh today." / "Market day
went beautifully, thanks to you." / "Smell anything nice on your way in?"
/ "Still keeping better track of my tools." / "Come by anytime -- the
door's always open."

#### Wren -- the bookseller

Own "not yet" pool (quieter register, does not share Nell's):

1. "Not yet. It will find you." (27)
2. "Patience. Pages wander slowly." (30)
3. "Still hiding? So is the page." (29)
4. "Not found. It's in no hurry." (28)
5. "Quiet. Keep your eyes open." (27)

The odd, quiet arc: a very old book on her shelf keeps shedding its own
pages, one at a time, and each one the player finds seems to already know
something about them. Nothing frightening happens; it resolves as warm.

1. **Ask:** "This book keeps losing its pages." / "Odd. It never used to
   do that." -- **find**, hint *"tucked under the reading nook bench"*.
   Reward 45.
2. **Thanks + ask:** "Ah. That page was blank before." / "Find the next
   one -- it just left." -- **find**, hint *"just past the shop window"*.
   Reward 55.
3. **Thanks + ask (away):** "This one has your name in it." / "One more.
   It went further this time." -- **find**, hint *"it wandered off,
   somewhere near the Job Center"*, clue template `"{compass} of the Job
   Center"`. Reward 120.
4. **Thanks + ask:** "Curious. The pages are finding you." / "One page
   left. It won't go far now." -- **find**, hint *"right by the door,
   waiting"*. Reward 80.
5. **Close:** "The last page. It's just your name." / "The book was
   always going to find you."

Epilogue pool (5): "The book is closed now. Good." / "Some books know
when to stop." / "Thank you for finding all of it." / "I reread your
page, sometimes." / "Quiet in here today. I like that."

#### Oskar -- the tailor

1. **Ask:** "My tape measure has vanished." / "Cannot fit a stitch
   without it." -- **find**, hint *"on the fitting room floor"*. Reward
   45.
2. **Thanks + ask:** "Precisely where I left it. Naturally." / "Now I am
   missing a spool of thread." -- **find**, hint *"rolled behind the
   rack"*. Reward 55.
3. **Thanks + ask (away):** "The right shade too. How lucky." / "One pin
   box, somewhere out there." -- **find**, hint *"somewhere downtown"*,
   clue template `"on {street}, near {landmark}"`. Reward 120.
4. **Close:** "Every pin accounted for. Superb." / "The commission is
   finally finished."

Epilogue pool (5): "The commission turned out rather well." / "Best-
dressed Sminski in town, probably." / "Still not one pin out of place." /
"A little tailoring never hurt anyone." / "Do come back if you need
mending."

#### Fern -- the pet shop keeper

Reuses the Lost Pup pattern in miniature -- three different escapes, same
dog rig (`Places`/City event convention, scale 0.18), no new art at all.

1. **Ask:** "Biscuit got out again. Oh no." / "He does this before
   closing time." -- **find**, hint *"behind the puppy pen"*. Reward 45.
2. **Thanks + ask:** "There he is! Sneaky little guy." / "Now Waffle's
   missing. Different pup, same trick." -- **find**, hint *"just past the
   shop door"*. Reward 55.
3. **Thanks + ask (away):** "Waffle! Bad dog. Sweet dog." / "Peanut's
   gone further this time, I think." -- **find**, hint *"somewhere
   downtown"*, clue template `"{compass} of City Hall"`. Reward 120.
4. **Close:** "Peanut's home! And staying, I hope." / "Maybe he finally
   likes it here."

Epilogue pool (5): "All pups present and accounted for." / "Peanut
hasn't tried the door once." / "Thank you for bringing him home." / "The
pen's calmer these days." / "You're good with the shy ones."

### Flavour that reuses what exists (and what would be new)

**Reuses an existing system, no new work beyond wiring:**
- Every keeper/clerk NPC -- already built, already dressed, already
  standing at a real address (`fitShop`, `B.jobcentre`).
- The FIND mechanism itself -- hidden spot, reveal radius, claim radius,
  `pay()` -- already exists for Lost Pup/Ice Cream Truck; scope it to one
  player.
- The clue grammar for the one "away" beat per arc -- `compass()`,
  `streetOf()`, `nearestLandmark()` -- already exists and is already
  fairness-tested.
- Fern's three "escaped pups" -- the exact dog rig already used for Lost
  Pup, same scale, just re-triggered per beat.
- The speech-bubble pill itself -- `npcSay`'s existing billboard, just
  fired by an interaction instead of proximity-linger, and reading from
  story data instead of the random `CHAT` table.
- The phone/notify format -- `notify(icon, TITLE, sub)`, exactly as used
  by `CityEvents.lua` for JOB OFFER/CITY NEWS.
- The beacon/green-dot wayfinding -- `CityWayfind.lua`, already routes a
  player to a position; needs no new capability, just a new source.

**New, and who it costs (see REQUESTS FOR OTHER OWNERS):**
- A "talk" interaction on the keeper/clerk distinct from the shop's
  existing BROWSE/READ/PET/etc. prompt (client-engineer).
- The per-NPC story index in save data, and the server-side claim/pay
  logic for an errand find (server-engineer).
- A deterministic per-player "away" find-spot, seeded from
  `(userId, npc, beatIndex)` rather than stored, so it survives a
  disconnect with zero new save fields (server-engineer) -- see EDGE
  CASES.
- A generic small "found it" marker visual for the plain objects (a
  stapler, a pin, a spool of thread, a book page) -- I'd expect this to
  reuse whatever pickup marker Phase B's Cash Drop/Balloon Festival
  already drew (a pooled, lightweight part, no per-item light, per
  `performance.md`), not a new mesh. Confirm with whoever owns
  `CityEvents.lua`.

### Tone range

Four warm, everyday voices (Nell, Marlow, Oskar, Fern) and one quiet,
odd one (Wren). Nobody is cynical, nobody is scared, nothing is bleak --
Wren's arc is the "slightly magical" end of the dial the world bible asks
for, and it resolves gently (the book was never anything but kind).

### The words around the errand

**Phone notification** (fires once, first time a beat's task opens; same
shape as an existing JOB OFFER row):

```
notify(icon, "<NAME> NEEDS A HAND", "<place> \u{00B7} <short need>", color)
```

Examples (sub ≤ 40 characters, verified):
- `"at the Job Center \u{00B7} lost her stapler"` (36)
- `"the florist \u{00B7} her watering can walked off"` (39... trim to
  `"the florist's watering can walked off"` (38) if the separator form
  runs long)
- `"the pet shop \u{00B7} Biscuit got loose again"` (37)

**Beacon labels** (≤ 14 characters, shown on the GO/wayfinding pill):
while searching, the item's name in caps -- `"THE STAPLER"`, `"THE OPEN
PIN"`, `"THE WHISTLE"`, `"THE TROWEL"`, `"BISCUIT"`, `"WAFFLE"`,
`"PEANUT"`; once found, the NPC's own address -- `"NELL'S DESK"`,
`"MARLOW'S SHOP"`, `"WREN'S SHOP"`, `"OSKAR'S SHOP"`, `"FERN'S SHOP"` --
to guide the trip back.

**Completion toast** (fires the instant the hidden item is claimed,
lower-case, matches `UI.toast` house style), 5 variants templated on
`{name}` so five NPCs across a whole arc do not read as one copy-pasted
line:

1. "found it! head back to {name}"
2. "got it! {name} will be thrilled"
3. "there it is -- {name} is waiting"
4. "found! don't keep {name} waiting"
5. "nice find -- {name} will love this"

**New object/character names introduced** (all flavour text, no new
assets): Nell's stapler, the OPEN pin, her whistle. Marlow's watering
can, a seed packet, her lucky trowel. Wren's book (unnamed -- it is
never given a title, which is the point) and its pages. Oskar's tape
measure, a spool of thread, a pin box. Fern's three shop pups: Biscuit,
Waffle, Peanut.

---

## NUMBERS

| Value | Number | Reasoning |
|---|---|---|
| Spoken-line budget | ≤ 40 characters | The `npcSay` pill is 250x54px, `TextSize 15`; the existing `CHAT` table's longest line is 36 characters, so 40 keeps a small margin without changing the bubble. |
| Beats per arc | 4 (Nell, Marlow, Oskar, Fern), 5 (Wren) | 3-6 per the design rule; Wren gets the extra turn because she is the one arc built to be savoured rather than solved quickly. |
| Reward, doorstep find | 45 / 55 coins | A doorstep find is ~10-20s round trip (the item is a few studs from the NPC). At ~187 coins/min baseline that is 30-60 coins for the time spent; 45/55 sits inside that with a small "it's a story, not a job" discount, and is well under a parcel run's 67-105 for real cross-block travel. |
| Reward, the "away" find | 120 coins | This beat sends the player to a genuinely different downtown address (a compass/street clue, not the NPC's own doorstep), closer to a real fare/parcel in time-and-travel. Priced in that band (75-125), not above it. |
| Reward, Wren's 4th beat | 80 coins | A second doorstep find after the away beat; priced between the doorstep and away rates since it is doorstep-easy but the arc has run longer and earns a slightly bigger thank-you. |
| Arc total | 220 coins (4-beat arcs), 300 coins (Wren) | Spread across a whole arc (likely several separate visits, not one sitting), this is a rounding error against the ~187/min a paced job pays -- errands stay flavour, never income. Matches `docs/LOOPS.md` §6's guardrail explicitly. |
| "Not yet" pool size | 5 (shared) / 5 (Wren's own) | "Variants over repetition": a stuck player may re-trigger this many times in one sitting. |
| Epilogue pool size | 5 per NPC | Seen indefinitely, every return visit, for the rest of the game -- needs real variety per the same rule, and per-NPC because this is the personality payoff, not filler. |
| "Found it" toast | 5 variants, templated on `{name}` | Seen once per beat per NPC; across a full playthrough of all 5 NPCs a player could see the *shape* of this toast up to ~21 times, so it needs real variety even though no single NPC triggers it more than 4-5 times. |
| Beacon label | ≤ 14 characters | Matches the existing GO-pill convention (`"CITY HALL"`, `"THE MALL"` style short caps labels already used for wayfinding destinations). |
| Notify sub | ≤ 40 characters | Matches the task's own stated budget for a notification subtitle. |

---

## EDGE CASES

- **Empty server / one player.** No issue -- an errand is single-player by
  design, no `minPlayers` gate needed, unlike the shared FIND/COLLECT
  events.
- **A scripted player.** The find claim must go through the exact
  server-authoritative pattern Phase A already uses: the exact position is
  never sent to a client outside `RevealRadius`, the claim is checked
  against real character distance and paid once per `(userId, npc,
  beatIndex)`, exactly like the existing per-event claim ids. No new
  trust model, reuse the old one.
- **Mid-arc disconnect / relog.** The only saved state is the story
  index (per LOOPS.md's own description -- nothing more). So the "away"
  find's exact position must be **derived, not stored**: seed a
  deterministic offset from `(userId, npcId, beatIndex)` the same way the
  Daily 3 Hunt seeds from the date, rather than persisting a chosen spot.
  A player who logs off mid-search and comes back gets the exact same
  target, with no new save field.
- **A player who never notices the NPC.** The phone (`PHONE > TOWN`)
  should list any NPC with an open beat, per the existing "the phone is
  where you find the one you missed" philosophy (`docs/LOOPS.md` §2) --
  otherwise five silent shopkeepers may as well not have stories.
- **A player who finishes every arc.** All five epilogue pools fire
  forever; no arc restarts, no arc ever runs dry into a blank/default
  line (the generic `LINES.browse`/`CHAT` pools are the fallback only for
  NPCs who were never given a story, not for one whose story is over).
- **Two players talking to the same NPC.** The keeper is one shared world
  object; its story state is **per player**, same as litter/fares/parcels
  today (`docs/LOOPS.md` §1's own finding about `s.city`). Two players see
  the same standing NPC but each gets their own beat/index -- this needs
  the bubble to read from *the viewer's* save, not a single shared state
  on the NPC instance.
- **A shop kind that doesn't spawn in downtown after all.** See REQUESTS
  -- I have not measured this in Studio; if `flowers`/`books`/`tailor`/
  `pets` do not land in one of the four downtown blocks on the current
  build, retarget that NPC to whichever downtown shop kind is actually
  present (the dialogue is written generically enough -- "the shop," "the
  counter" -- that only the flavour noun in the ask lines would need to
  change, not the structure).

---

## CUT / DEFER

- **Day-gating ("come back tomorrow").** The example in the brief uses
  it; I did not, because the errand's own pacing (walk to a real place,
  find a thing, walk back) already spaces beats out, and a returning-
  player daily hook already exists as its own feature (Daily 3 Hunt,
  phase D). Stacking a second daily-gate system on top would compete
  with it for the same "come back tomorrow" moment. **Confirmed by the
  human: no day-gating for launch** -- a player who wants to finish an
  arc in one sitting should be able to; revisit only if data later shows
  arcs need pacing (a one-line change if so).
- **A sixth or later NPC.** Five is enough to make downtown feel
  peopled without turning "say hi to everyone" into a chore; more can be
  added later as new keys, since keys are append-only-stable by design.
- **Food-venue errand-givers** (a baker, the pizzeria cook). Would need a
  new standing NPC built into `fitFood`/`fitKitchen`, which today have no
  keeper at all -- real build cost for another lane, not a data change.
  Cut for this phase; flagged as a natural phase-G-part-2 if the human
  wants "the baker" specifically.
- **A cosmetic reward on arc completion** (a hat, a keepsake). Considered
  and cut: every existing cosmetic in `Config.Outfits` is either bought
  with coins or gated behind a login-day exclusive, and handing one out
  free from an errand either undercuts the shop or needs a brand new
  item -- both are calls for another lane/the human, not mine to assume.
  Arc completion stays coins-only plus the epilogue's warmth.
- **Wren's book having an actual title or a payoff object.** Deliberately
  left as just "the book" -- naming it or turning the last page into a
  literal collectible risks tipping "slightly magical" into "a whole new
  system," which is more than a phase-G flavour pass should cost.

---

## REQUESTS FOR OTHER OWNERS

1. **A "talk" interaction on the five keeper/clerk NPCs**, alongside
   (not replacing) their existing shop prompt (`SHOPFIT` in
   `CityBuild.lua`) -- client-engineer.
2. **Per-NPC story index in save data** (`data.City.errands = { nell = i,
   marlow = i, wren = i, oskar = i, fern = i }`, integers, nothing else)
   -- server-engineer.
3. **Server-authoritative find/claim for an errand**, reusing the exact
   `RevealRadius`/`ClaimRadius`/`pay()` pattern from `Config.Events` and
   the director in `SminskiServer.server.lua`, scoped to one player and
   keyed by `(userId, npc, beatIndex)` -- server-engineer.
4. **Deterministic seeding for the "away" beat's hidden spot** from
   `(userId, npcId, beatIndex)`, not a stored position -- server-engineer
   (see EDGE CASES).
5. **Confirm in Studio** (or from a `cityLots()` dump) that a
   `flowers`/`books`/`clothes`-or-`tailor`/`pets` shop actually lands
   inside one of the four downtown blocks on the current build. My
   arithmetic against `Places.lua`'s `WALL`/`SHOPS` tables says yes, but
   this was never run in the engine, unlike the measured facts already in
   `docs/ROADMAP.md`'s density passes.
6. **A generic small "found it" pickup marker** (pooled part, no
   per-item light) for the plain objects -- stapler, pin, thread, book
   page, trowel -- reusing whatever Phase B already drew for Cash Drop/
   Balloon Festival rather than a new mesh -- whoever owns
   `CityEvents.lua`.
7. **The phone (`PHONE > TOWN`)** should carry a row per NPC with an open
   beat, GO button included, per the existing feed conventions --
   client-engineer.
8. **Two-stage beacon**: point at the item while searching, then at the
   NPC once it's found, both through the existing `CityWayfind.lua` --
   client-engineer.

---

## QA SHOULD CHECK

- Beat 1 of every arc reads sensibly to someone who has never seen the
  NPC before (the "make sense from beat 1 alone" rule) -- have a fresh
  tester talk to just one NPC cold and confirm they understand what to
  do without reading this doc.
- Story index persists correctly across a relog **mid-search** (item not
  yet found) and the away-beat's hidden spot lands in the same place both
  times.
- Two players talking to the same keeper get their own independent
  beat/index, not a shared one.
- An errand's find is claimed once and only once -- hostile-client style
  double-claim test, same as Phase A's existing claim tests.
- The five keepers are visually distinct from each other and stable
  across a server restart (same body colour at the same address every
  time) -- confirms the "recognisable regular" read actually works in
  Play, not just on paper.
- Every spoken line actually fits the 250x54px pill without clipping or
  wrapping onto a third line, at the game's default `TextSize 15` --
  screenshots/`AbsolutePosition` checks the way `docs/HANDOFF.md` §2
  recommends, since Play-mode screenshots return solid magenta.
- Nobody can grind a single NPC for repeat rewards -- confirm the
  epilogue state truly pays nothing and truly never re-opens a beat.

---

## DECISIONS FROM THE HUMAN

All five of the original open questions are resolved; nothing below is
still open.

1. **Day-gating -- no, not for launch.** Phase D's Daily 3 Hunt is already
   the returning-player hook; stacking a second daily gate onto errands
   would compete with it and slow how fast a player meets the cast. All
   five arcs stay completable back-to-back in one sitting. Revisit only
   if it later needs pacing.
2. **Names -- Fern replaces Sunny.** `Sunny` collided with real geography
   (`Sunny St`, `Sunny Homes` -- `Places.lua:72, 80`), which would have
   produced confusing self-referential clue text (a Fern-named errand
   pointing at "Sunny St" was the failure mode). Renamed throughout this
   doc and `game/StoryErrands.lua`; checked (and clear) against every
   street, district and landmark name, and against the existing
   `Config.Characters` register (`Glow · Blush · Sky · Lemon · Lavender ·
   Mint · Peach · Ghost`, etc.) for the same reason. Nell, Marlow, Wren
   and Oskar were already clear and are unchanged.
3. **Wren stays lightly magical.** One odd voice in five is the right
   ratio and is what keeps the cast from reading as uniformly nice, per
   `design.md`/`character.md`.
4. **Reward total stands at 220-300 coins per arc.** Comfortably under
   job income per `docs/LOOPS.md` §6, and reads as a discovery bonus
   rather than a wage.
5. **Five NPCs is right for launch.** One per district would push past
   the downtown vertical slice `docs/ROADMAP.md` scopes this work to.
   Growing the roster later is additive (more keys), not a redesign.
