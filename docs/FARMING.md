# The Farmer job — plan

The first role built end to end. Everything here is a plan; nothing is built.

Farming is the pilot for a bigger shape change (roles, starter apartments,
role-based spawns) described in `docs/ONBOARDING.md` §3. Build the farmer
first, prove the pattern, then clone it for the other roles.

---

## 1. What exists today

The farm is **already the right architecture and the wrong depth.**

| | Today | Where |
|---|---|---|
| Plots | 12 fixed positions | `Places.cityFarmPlots()` |
| State | `cs.plots[i] = plantedAt` — one timestamp | server, `s.city.plots` |
| Growth | `k = (now - t0) / ripe`, 4 stages | `City.lua:2392` |
| Ripe time | **45 seconds** | `Config.City.RipeSeconds` |
| Payout | flat `Harvest = 10` | `Config.City.Harvest` |
| Visuals | client-built parts, 4 stages | `setCrop()`, `City.lua:2306` |
| Job | `farmhand`, `tasks = "fields"`, base 45 | `Config.Jobs` |

So: plant, wait 45 seconds, harvest, get 10 coins. It is a click-to-earn
field, not a farm.

**But the bones are exactly right.** Crop state is a timestamp, growth is a
pure function of server time, and nothing ticks. That is the pattern the whole
game needs — see §2 — and the work below is depth on top of it, not a rewrite.

---

## 2. The 60-player rules (every job follows these)

The city already learned this once: `docs/LOOPS.md` found that almost all city
state is per-player, and the DataStore work last session found that ordinary
city actions were writing the same key dozens of times a minute. Farming
multiplies both problems by twelve plots. The rules:

1. **State is a timestamp, never a ticking object.** A crop is
   `{ crop, plantedAt, watered, fertilised }`. Nothing updates it between
   plant and harvest. 60 players × 12 plots = **zero** server work per frame.
   The existing `(now - t0) / ripe` line is the model; keep it.
2. **Geometry is client-built and per-player.** The city already builds on the
   client and streams block by block. 60 players' crops cost **zero replicated
   parts**. A farm must never spawn server-side crop models.
3. **Never write to the DataStore per action.** Plant, water, fertilise and
   harvest are all frequent. All of them route through the coalesced `save()`
   — never `writeNow()`. A twelve-plot watering pass is one write, not twelve.
4. **Batch the remotes.** One call per interaction, not one per crop. Watering
   a row is a single action with a list of plot ids.
5. **Growth continues offline**, because it is arithmetic on a stored
   timestamp. This is free, and it is also the design requirement in §4.
6. **Ripe crops never spoil.** Also free — the stage function just clamps.
   A player is never punished for being busy or offline.

Anything that cannot be expressed this way needs a reason in writing before it
ships.

### 2.1 The one real decision: shared field or personal parcel

Today the 12 plot positions are **shared geometry with private state**. Player
A sees their carrots exactly where player B sees their corn, and neither can
see the other's. It works, it scales perfectly, and it is ghostly — the same
fault `LOOPS.md` named downtown: *two players in the same field are playing
two private games.*

**Recommendation: personal parcels, allocated on join.**

A farm belt of numbered parcels, one leased to each player in the server, each
with its own plots, barn, storage and fence. Allocate on demand — a 3-player
server builds 3 parcels, a 60-player server builds 60. Neighbours are visible
and real; your crops are yours.

This costs geometry, but it is **modular geometry**, which is what the kit is
for (`CityKit`, `CityBuild` already compose blocks and stream them by
distance). It buys the thing the design actually promises: *I own and operate
a little farm.* You cannot own a plot that flickers into somebody else's corn.

The cheap alternative is to keep shared plots and accept the ghostliness. It
is a legitimate v0 if parcels turn out to be slow — but then the farm is a
minigame with a field texture, not a place.

---

## 3. The loop

```text
PREPARE → PLANT → WATER → (FERTILISE) → WAIT → HARVEST → STORE → HAUL → SELL → EARN
```

Every arrow is a physical action somewhere on the map. No step is a menu.

### Plot states

`empty → prepared → planted → growing → ready`

Ready is terminal: it waits forever.

### The interactions

| Action | Feel | Rule |
|---|---|---|
| **Prepare** | till the bed, clear it | once per harvest cycle |
| **Plant** | choose a crop, drop seed | costs seed money |
| **Water** | an active interaction, per row not per crop | **not** babysitting — see below |
| **Fertilise** | optional, costs coins | the first real economy decision |
| **Harvest** | crop leaves the soil, appears carried | satisfying, physical |

**Watering is the one that goes wrong.** The spec rule is "active but not
constant babysitting". Concretely: **watering once per growth cycle is what a
crop needs**, and an unwatered crop grows at roughly half speed rather than
dying. So watering is a meaningful act with a real payoff, skipping it is a
choice rather than a failure, and nobody is ever forced back to a plot on a
timer. Sprinklers later remove the chore entirely, which is what an upgrade
should do.

### Crops

| Crop | Grow | Fertilised | Yield | Sells |
|---|---|---|---|---|
| Carrot | 5:00 | 3:30 | 5–8 | 8 |
| Tomato | 8:00 | 5:30 | 4–7 | 14 |
| Corn | 12:00 | 8:00 | 3–6 | 22 |

Later: potato, wheat, strawberry, pumpkin, apple, blueberry, rare crops.

> **This is 7–16× slower than today's 45 seconds.** That is correct for a
> farming game and wrong for a first session — see §6. It also means the farm
> stops being a quick-cash job, so the economy numbers in §5 have to be
> re-checked against the other jobs rather than copied from the spec.

### Storage and hauling

Harvested crops are **carried**, and you can only carry a little. Storage on
the parcel — barrels and crates, 50 starter capacity, upgradeable — lets you
bank several harvests before a trip to town. Hauling is then a real trip:
on foot at first, then hand cart, trailer, pickup, farm truck.

This is what makes the farm part of the city rather than a screen you stand
in. It is also why the storage upgrade is worth buying.

### Selling

Buyers are real doors that already exist in `Build.destinations`:

| Buyer | Wants |
|---|---|
| Grocery store (`CityGrocery`) | carrots, tomatoes, corn, potatoes |
| Restaurants (`CityKitchen`, `CityTycoon`) | tomatoes, corn, wheat |
| Farmers market | most crops, best prices |

You walk into the loading area and deliver a crate. Paid on delivery.

**This is the connective tissue.** The pizzeria buys the tomatoes. A player
who owns a restaurant through `CityTycoon` buys from farmers. That is the
difference between a job and a minigame, and it is the argument for building
farming before more jobs.

### Orders

Optional, never forced, and slightly better than selling loose produce:

> Grocery store needs 20 carrots — **250 coins**
> Pizzeria needs 15 tomatoes — **220 coins**
> Farmers market needs 30 mixed veg — **400 coins**

Orders answer "what should I plant?", which is the question a farm with three
crops and free choice otherwise leaves hanging. They slot into the existing
job/shift system (`Config.Jobs.farmhand` already has `tasks = "fields"`) and
onto the phone task list from `ONBOARDING.md` §5.2 — not a new system.

---

## 4. Progression

| Level | Farm | Unlocks |
|---|---|---|
| 1 | starter parcel | basic crops, manual watering, small storage |
| 2 | growing | more plots, fertiliser, larger storage, orders |
| 3 | established | sprinklers, better seeds, high-value crops, vehicle hauling |
| 4 | operation | large fields, advanced equipment, contracts, rare crops |

Upgrade categories: **storage** (barrels → shed), **equipment** (can →
sprinkler → tractor), **production** (plots, seeds, yield), **transport**
(cart → trailer → truck).

The arc is manual-few-crops → efficient-small-farm. Every upgrade removes a
chore the player has actually felt.

---

## 5. Economy — one table, not two

The spec's numbers are dollars; this game has **coins**, and it already has an
economy: jobs pay `base` 40–70, `Harvest = 10`, apartments cost 1500–4000×,
cars 1200–20000, businesses 1500–60000.

Before any of the §3 numbers ship, they need checking against that table.
The specific risk: a 5-minute carrot yielding 5–8 at 8 coins is ~50 coins per
plot per 5 minutes, and **twelve plots makes that 600 coins per 5 minutes** —
roughly ten times the taxi's `base = 70` per fare. Farming would become the
only sane way to earn.

Fix it at the *plot count and haul capacity*, not at the crop price: carrying
capacity and storage are the throttle, and they are also the upgrade path. A
starter farmer with 4 plots and a 10-crop carry limit is earning sensibly; the
same player at level 3 with a truck is earning well because they invested.

Sinks: seeds, fertiliser, farm upgrades, storage, vehicles, clothes, home.

---

## 6. First session on the farm

Ten steps, each one instruction, each with a beacon — the structure from
`ONBOARDING.md` §2. No popup explains the loop; the loop explains itself.

1. Go to your farm — GPS path (`CityWayfind`)
2. Prepare your first plot — highlight it
3. Plant carrots — free starter seeds
4. Water them — free watering can
5. Check the timer — *crops grow while you do other things*
6. Harvest
7. Store them in the barrel
8. Take them into town — GPS to the grocery store
9. Sell
10. Get paid — **this is how jobs make money in Sminski City**

**The 5-minute carrot is a problem for exactly one player: a brand new one.**
Three ways to fix it, in order of preference:

- the tutorial parcel starts with **one plot already nearly ripe**, so step 6
  arrives immediately and the full timer is learned on the second planting;
- step 5 hands out the first order, so the wait has a task in it;
- the walk to the barn and into town covers most of the remainder anyway.

Do not shorten the carrot for everyone to fix the first two minutes.

---

## 7. Look

Reference: the supplied farm image — dirt beds in neat rows with green tops
showing, a red barn, a white farmhouse, post-and-rail fences, chunky rounded
trees, a dirt path between beds.

That is already on-style (`design.md`): rounded, chunky, pastel, soft matte,
strong silhouettes. Notes specific to the farm:

- **Growth must read at a glance from standing height.** Four stages is the
  minimum; the difference between stage 3 and ready has to be obvious across
  the field, because that is what the player scans for.
- **Beds, not a texture.** Raised dirt rows with visible soil give the farm
  its silhouette from the road.
- Barn, farmhouse, fences, water source, storage barrels, tool rack and a
  small equipment area are the props that make it a place rather than a grid.
- Per `assets.md` these are **supporting assets** built from the kit, except
  the barn, which is a hero building and gets a review round.

---

## 8. Build order

1. **Parcel allocation** — claim a numbered parcel on join, build it from the
   kit, stream it with the rest of the city. Prove 60 parcels before anything
   else; this is the step that can fail.
2. **Crop data model** — `Config.Crops`, plot record `{ crop, plantedAt,
   watered, fertilised }`, stage as a pure function. Extends what exists.
3. **The five interactions** — prepare, plant, water, fertilise, harvest, as
   physical prompts on the parcel.
4. **Carry + storage** — carried produce, barrels, capacity, the upgrade.
5. **Hauling and selling** — grocery loading bay first, one buyer, end to end.
6. **Orders**, on the phone task list.
7. **Upgrades** — storage, watering can → sprinkler, plots, transport.
8. **The ten-step first session.**
9. **Art pass** — beds, barn, fences, growth stages, harvest feedback.
10. **Economy tuning against §5**, in a populated server, not an empty one.

Steps 1–5 are the vertical slice: plant a carrot, sell it in town, get paid.
Ship that and the rest is content.

## 9. Open questions

1. **Parcels or shared plots** (§2.1). Everything else assumes parcels.
2. **Does the farm belt have room for 60 parcels**, or does the north belt
   need extending? Measure before committing.
3. **Existing players have plots in `s.city.plots` keyed by the old fixed
   index.** Parcels change that key's meaning — needs a migration, or the old
   key retires and everyone starts fresh on their parcel.
4. **Is `farmhand` still a "job" you clock into**, or does owning a parcel
   replace the shift? Owning is better, but the ELO/rank system hangs off
   shifts, so this affects `CityJobs`.
