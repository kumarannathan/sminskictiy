# The first fifteen minutes — plan

**The problem:** players arrive and do not know what to do. This is the plan
for fixing that, at minute 1 and at minute 30. Nothing here is built yet.

Read with `docs/FARMING.md` (the first role, built end to end),
`docs/LOOPS.md` (what happens after the first session) and
`.claude/rules/design.md`.

---

## 1. What a new player gets today

Traced from the actual first-join path:

| Order | What | Where | Player does |
|---|---|---|---|
| 1 | Title + loading, 15s, PLAY | `SminskiTitle.client.lua` | waits |
| 2 | Title menu | `SminskiTitle` | picks START |
| 3 | City curtain, "ARRIVING IN SMINSKI CITY…" | `City.lua` | waits |
| 4 | **Welcome tour — 6 modal cards** | `CityGuide.lua` | taps NEXT ×6 |
| 5 | **House tutorial — 4 more cards** | `CityHome.lua:687` | walks home |

**A new player reads ten cards before the game asks them to do anything.** Six
are pure text over a dim layer with no action attached — jobs, doors, traffic,
the map and the arcade in one unbroken block. The first verb the game teaches
is *reading*; the second is *going home*. Neither is the loop.

Three specific faults:

- **Nobody earns a coin during onboarding.** Card 2 *describes* five income
  sources; the player performs zero.
- **It front-loads everything.** Traffic, the arcade, the travel pad and the
  car are all explained before the player has a use for any of them.
- **It ends with "you're all set"** and drops them on a street with no next
  action. That is the moment they leave — and nothing ever tells them what to
  do again.

That last one is the real bug. Onboarding is not a five-minute problem; the
game never answers "what do I do?" at *any* point.

---

## 2. The principle

> Don't teach players what every system is. Teach them what to do next.

The first fifteen minutes should be a **guided life progression**, not a
tutorial — the player plays the game normally while the game tells them the
next thing. Everything the cards currently say is better learned by doing it
once with a beacon pointing at it.

Corollaries:

- **One instruction at a time**, each attached to something they will do in
  the next ten seconds.
- **Never explain a system before its first use.** Traffic when they first
  cross a road. The car when the walk gets long. The arcade never — let them
  find it.
- **The minigame IS the job.** A job is not a button that pays out.
- **At every moment there is one obvious next thing on screen**, forever, not
  just during the intro.
- **It has to survive being skipped.** A skipper still gets a goal widget and
  a stocked phone.

## 3. The loop, stated plainly

```text
GET A JOB → PLAY THE MINIGAME → EARN COINS → BUY / UPGRADE → UNLOCK MORE CITY → REPEAT
```

The first fifteen minutes exist to make that sentence obvious without anyone
reading it.

---

## 4. Pick a role, then move in

Before the city loads, one screen: **where do you want to start?**

```text
  🌾 FARMER      🚕 DRIVER      🍕 COOK
```

The role picks **your starting neighbourhood and your first job. It is not a
career.** Every job in the city stays open to everybody — `Config.Jobs`
already runs one shared reputation across all of them — and the phone will
offer the others within the first session.

That framing matters. A permanent class choice is a terrible first decision
for someone who has seen nothing of the game yet, and players who feel
locked in leave. "Where do you want to start?" gets the same result with none
of the trap.

**Ship three roles, not six.** Each role needs a neighbourhood that is worth
spawning in and a job that is actually finished. Farmer, driver and cook map
onto the farm belt, Motor Row and the restaurant/market district — all of
which exist. Photographer, police, construction and firefighter are all
`soon = true` in `Config.Jobs` and have no gameplay yet; a role that spawns
you next to a job you cannot do is worse than no role at all. Add roles as
jobs finish.

Each role's neighbourhood puts its job **within sight of the front door.**
That is the whole point of choosing: the first walk is short and the first
landmark is the place you work.

### The arc

| Time | Phase | They learn |
|---|---|---|
| 0–2 | **Move in** | movement, interacting, the phone/computer, the GPS path |
| 2–5 | **First job** | your workplace, a real shift, a minigame, getting paid |
| 5–8 | **Spend it** | shops, clothes, home, what coins are *for* |
| 8–12 | **Explore** — "earn 500 coins", any job | the city is a choice, not a corridor |
| 12–15 | **First big purchase** | saving, vehicles, new tasks unlock |

By minute 15 they are playing independently and the goal widget has taken over
from the script.

### 0–2 · Move in

Spawn **inside a basic starter apartment** in the role's neighbourhood.

> **Welcome to Sminski City! You just moved in. Let's get you your first job.**

Small, cheap, and yours — the first room should look like somewhere you would
want to leave and come back to improve. A tiny flat you outgrow is a better
opening than a free house, because it makes the house mean something later.

**This inverts the current model.** Today every player is auto-assigned a free
house (`assignHouse`, server ~1279) and apartments cost 1500–4000× a plan
multiplier. The change: a free `starter` tier becomes the default home, and
the house moves behind a purchase — the big aspirational one.

> **Migration risk:** players who already have a house must keep it. The
> change applies to new saves; existing ones keep what they were given.

### The starter apartment

One room, and every object in it is a verb. A window is not required for v1.

| Object | Does |
|---|---|
| **Bed** | sleep / pass time, already built (`CityHome`) |
| **Closet** | change outfit — `UI.openShopTab("outfits")` |
| **Fridge / food** | eat, already built |
| **TV** | flavour, and a place to put news later |
| **Computer** | **find jobs, and receive notifications** |

The computer is the important one. It is the phone's desk twin and the
in-fiction answer to "where do I find work" — a job board you sit down at
rather than a menu you open. It should show the same CITY TASKS list as the
phone (§5.2), so there is one task system with two surfaces, not two systems.

Then a **GPS path on the ground to your first job** — `CityWayfind` already
draws exactly this, in the gutter lane so it reads at Smiski eye level.

On the way out, one free coin: litter on the pavement within a few steps
(`cleaner` is live, `hard = 1`, and its work is *everywhere*, so it needs no
travel). Walk over it, the prompt appears, press GO, get paid. Twenty seconds,
nothing explained. Now they know actions pay.

### 2–5 · First job

The role already chose it, so there is no job board to read — the GPS path
ends at your workplace and the shift starts. The career browser
(`CityJobs.lua:150`) is where they go to find the *second* job, later.

**Farmer is the one being built first** — the full loop is in
`docs/FARMING.md`. Cook is the cheapest to reach because the pizzeria is the
most *legible* job in the build — you can
see what you are doing at every step — and because `CityKitchen` is already
exactly the right shape: a stepped pipeline of one-tap/one-hold minigames with
the stations physically apart, so an order is a lap of the room.

**Walk them through one step at a time.** Do not explain the pipeline up
front; beacon the next station and show one line:

> 🍕 Make the customer's pizza → 🔥 Put it in the oven → 🏃 Deliver it → **+35 coins**

Then the shift ends with the real SHIFT OVER notification, which they have now
seen once in a context where it made sense.

### 5–8 · Spend it

> **YOU EARNED 135 COINS**

Immediately answer what money is for. Three big buttons, and **do not force a
purchase**:

**🏠 Upgrade Home** · **👕 Buy Clothes** · **🚗 Save for a Vehicle**

Clothes is the cheapest and most immediately visible, so it is the likely
first purchase and the best one — they see the change on their own character.
The capsule pill is already on the HUD with a meter; a free first capsule
(`rollCapsule` already has a free-gift path) fits here too, and introduces the
collection.

### 8–12 · Explore

One open goal — **earn 500 coins, any job**. This is the first moment the
player chooses, and it is deliberately job-agnostic: taxi, delivery, cleaner,
farm and pizzeria are all live and all count.

> You can work any job in Sminski City. Different jobs make money in
> different ways.

### 12–15 · First big purchase

> 🚗 **You can now afford your first vehicle!**

Sminski Motors already exists as a modal (`City.lua:816`). Buying something
large closes the loop: they earned, they chose, they saved, they bought. Then
**new city tasks unlock** and the script steps back.

---

## 5. The two systems that outlive onboarding

This is the part that actually fixes "players don't know what to do", because
it never ends.

### 5.1 The CITY GOAL widget — always answer "what do I do?"

A small persistent HUD element. At any moment it holds exactly one thing:

```text
CITY GOAL
💰 Earn 500 coins
How?  Work any job
[ TRACK ]
```

While working, it becomes the current job instead:

```text
CURRENT JOB
🍕 Complete 3 orders
2 / 3
```

On completion: **✓ TASK COMPLETE · +100 coins · +50 XP**, and then it
*immediately shows the next thing*. It is never empty. TRACK routes the player
there using `beacon()` and `CityWayfind` — both already built.

### 5.2 The phone becomes the task list

The phone (`CityEvents.lua`) is already the "what's happening" screen with a
GO per row. Give it a **CITY TASKS** tab:

```text
📱 TODAY
☑ Get your first job
☑ Complete your first shift
⬜ Earn 500 coins
⬜ Buy your first vehicle
⬜ Upgrade your apartment
⬜ Try another job
```

Every task carries the same four fields, which is what makes it teach rather
than nag:

**TASK** · **REWARD** · **HOW** · **[TRACK]**

The onboarding script is then just *the first six rows of this list*. There is
no separate tutorial system to maintain, and a returning player at minute 200
gets the same affordance as a new one at minute 2.

> **Constraint:** the phone is built once at init — ~97 instances, fixed row
> count, refresh writes only `Text` and `Visible`. A tasks tab must keep that
> property (`performance.md`). Fixed rows, no allocation on refresh.

---

## 6. What it reuses

| Need | Already there |
|---|---|
| GPS path on the ground | `CityWayfind.W.to(pos, name)` |
| point at a thing | `beacon()` — `City.lua:428` |
| "you got paid" | `J.notify()` — `CityJobs.lua:49` |
| stepped job minigame | `CityKitchen` + `Config.Restaurants[].steps` |
| the job board | career browser, `CityJobs.lua:150` |
| named destinations | `Build.destinations` |
| the house interior | `CityHome` |
| clothes | `UI.openShopTab("outfits")` |
| vehicles | Sminski Motors, `City.lua:816` |
| a free capsule | `rollCapsule`'s free-gift path |
| the card, ring and dots | `CityGuide.lua` |
| beats as data | `StoryErrands.lua` |
| remembering progress | `c.tour` / `c.tutorial`, server ~1900 / 2228 / 2258 |

Almost none of this is new geometry or new UI. It is a task system and a
sequencer over things that already work — which is why it is worth doing
before more content.

## 7. What changes in the current build

- **`CityGuide`'s six cards → gone as a block.** Content redistributed: jobs →
  phases 2–5, doors → a prompt they walk into, traffic → proximity trigger at
  the first crossing, map → the GPS path, arcade → cut from onboarding.
  **Keep the component** — card, dots, gold `mark()` ring, SKIP — driven one
  beat at a time without the full-screen dim.
- **`CityHome`'s 4-card tutorial → phase 0**, reframed as moving in — but
  into the starter flat, not the house.
- **Spawn** for a new player moves from `Places.CitySpawn` to inside their
  starter apartment in the chosen role's neighbourhood (`citySpawnCF`, server
  ~1278, already branches on `tutorial`).
- **Homes invert.** A free `starter` tier joins `Config.City.AptPlans` and
  becomes the default; `assignHouse` moves behind a purchase. Existing saves
  keep their house.
- **Role selection** is a new pre-city screen, and a new saved field. It
  writes one value and is never asked again.
- **HELP** currently replays the tour. It should instead focus the goal widget
  and re-beacon — more useful to a confused player at minute 20.

## 8. Build order

1. **Task model + goal widget.** One task shape (`TASK/REWARD/HOW/TRACK`), one
   HUD element, TRACK wired to `beacon()`/`CityWayfind`. Build this first — the
   onboarding is expressed in it, not beside it.
2. **Phone CITY TASKS tab**, fixed rows.
3. **Beat runner** over `StoryErrands` data: show a line, set a beacon, wait
   for a condition, pay, advance.
4. **Write the first six tasks as data.**
5. **Starter apartment** — the free tier, the five interactive objects, and
   the computer as the second surface for the task list.
6. **Role select + role spawns**, farmer first (`docs/FARMING.md`).
7. **The farmer vertical slice** — plant a carrot, sell it in town, get paid.
   This is the proof that a role is a real job; everything after it is a
   repeat of the same shape.
8. **First-shift step-through** — one instruction at a time, next station
   beaconed, first time only.
9. **The spend prompt** — three buttons after the first paycheck.
10. **Strip `CityGuide`** to a single-card renderer the runner drives.
11. **Proximity lines** — traffic at the first crossing, the car when a walk
    gets long.
12. **Skip and resume.** Skipping leaves a goal and a stocked phone. Leaving
    mid-tutorial resumes at the same beat.

Steps 1–2 are shared by every role and should exist before any role is built.
Steps 6–7 are the farmer slice; when it works, driver and cook are the same
work with different verbs.

## 9. How we will know it worked

Instrument **before** building, so the current onboarding gives a baseline:

- joined → **first coin earned** (target >90%, under 60s)
- → **first job completed** (target >70%)
- → **first purchase made**
- → **still playing at 5 / 15 minutes** — the number that actually matters
- **skip rate**, and whether skippers behave differently afterwards
- **goal widget**: how often TRACK is pressed, and whether the goal is ever
  empty (it should never be)

## 10. Open calls

1. **Guide NPC, or the phone alone?** `StoryErrands.lua` is already a beat
   format and a character who asks for help teaches better than a
   notification — but the phone alone is cheaper and the task list carries
   most of the weight either way.
2. **Does the arcade appear in onboarding at all?** Cutting it makes the first
   session unambiguously about the city. But the runner and Dog Park Survival
   are finished modes, and hiding them from new players is a real cost. If
   retention later says the runner is what keeps people, this flips.
3. **How many roles at launch?** Three is the recommendation (§4) because
   three jobs are finished. Shipping six means four roles spawn you beside a
   `soon = true` job with no gameplay behind it.
4. **Does the role choice ever change?** It should not need to — every job is
   open to everyone — but a player who picks farmer and hates it should not
   feel stuck in the farm belt. Probably: the role is only a spawn, and moving
   house is how you change neighbourhood.
5. **Farm parcels vs shared plots** — `docs/FARMING.md` §2.1. This is the one
   decision that changes how the whole city handles 60 players, because every
   other job will copy whatever the farm does.
