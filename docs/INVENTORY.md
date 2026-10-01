# Inventory assets — the second door

The city has two ways a 3D asset gets in:

1. **Props** — Blender-built in `art/blender/`, exported, listed in
   `Props.lua`, gated by `review = "approved"`. See `pipeline.md`.
2. **Inventory** — models the owner picked from their own Roblox inventory,
   curated into `ReplicatedStorage.SminskiAssets.Inventory` and placed by
   `K.place()`. The owner choosing them *is* the review; this document is
   the record of what was reviewed and what was rejected, and why.

Every caller keeps its part-built fallback, so a place file without the
Inventory folder still builds the whole city.

## Re-running the curation

Insert the raw models into `ReplicatedStorage.SminskiAssets.Inventory` as
`Inv_<Name>` (the MCP `insert_asset` does this), then from the command bar,
in Edit mode, with the file server running in `game/`:

```lua
local H = game:GetService("HttpService"); H.HttpEnabled = true
loadstring(H:GetAsync("http://127.0.0.1:8765/_inventory_setup.lua"))()
```

`game/_inventory_setup.lua` strips **every** script, light, sound and
emitter (the Sakura tree shipped with a fake "model corruption, paste this
code" backdoor; McDonald's with 27 lights), anchors and de-collides the
parts, puts the pivot at the feet, records native size as `H`/`W`
attributes and provenance as `AssetId`/`Creator`, then **deletes the raw
inserts** — ReplicatedStorage replicates to every client, and the raw set was
94,383 parts.

**Save the place afterwards.** The templates live in the `.rbxl`, not in
the repo.

## What was used (57 templates, 1,970 parts)

| Source | Templates | Where they stand |
|---|---|---|
| Nature Package // 2023 (12996952219) | `Tree_Beech_S/M/L`, `Tree_Broadleaf`, `Tree_Maple`, `Tree_Dogwood`, `Tree_Pine`, `Tree_Redwood_S/M`, `Flower`, `Clover`, `Grass`, `Herb` | every `K.tree` / `K.treeKind` / `K.pine` / `K.flowers` call — streets, park, orchard, forest, beds |
| Sakura tree (138990875351757) | `Tree_Sakura` | the `blossom` kind |
| Low Poly Farm Pack (8510928279) | barns, silos, water tower, greenhouses, tractor, trailer, hay, coop, beehive, trough, well, produce stand, 10 crates, 8 foods, barrel, wood stack | `B.barn`, `B.fields`, `B.farmmarket`, `B.pasture`, `B.cows`, `B.camp` |
| Colima City Park (12396863735) | `Plaza` (213 parts after curation) | Button Park, at 0.85 |
| McDonald's Restaurant (4572305378) | `McDonalds` (1,636 parts) | the market block, at 0.9 |

### How trees work now

`K.invTree` picks a template by kind from a pool, chooses the variant from
the position (so a tree is the same tree every visit), tints the untextured
leaf/trunk meshes to that kind's palette, scales to the height the part-built
tree had **capped by width** (a full-size maple is 62 studs across; a street
pit is 5), and adds a slim invisible trunk collider. Cost: 2–3 mesh parts vs
5 blobs + a cylinder.

### What was measured

- Trees: feet at +0.00 from the pavement, 12 wide / 10 tall at street scale.
- Plaza: 263 studs does not fit a 260 block, so 0.85. Its two clear discs are
  r=39 at the south corners; the pond (shrunk to 60 across) takes one and
  the gazebo the other; `Build.parkGazebo` tells the bandstand hangout where
  the gazebo went. 0 plaza parts inside either disc. Its 46 lamp posts (690
  parts, 46 lights) were dropped; `K.lamp` stands at a third of their spots.
- McDonald's: first placed at (+68,+72) it had **33 street-wall parts inside
  it** — the wall units on that block are 32 deep, so the inner face is at
  86. Now 0.9 scale at (+42,+52), parking row moved from z=+20 to +4;
  0 foreign solids inside. Walk-in prompt "McDONALD'S · ORDER" works.
- Farm: barn, silo, water tower, tractor, coop, hay, both greenhouses, the
  produce stand — all at +0.00, 0 overlaps. The greenhouses were first
  placed on top of two farm plots (caught in code, before the sync): the only
  free strip on the fields block is z 86..116.

## What was rejected, and why

| Asset | Parts | Why |
|---|---|---|
| National Supermarket | 23,429 (196 scripts) | more parts than the rest of the city; 695 studs wide against a 260 block |
| Six Mart | 37,009 (120 scripts) | same |
| Super Target | 16,028 (184 scripts) | same |
| Mega Mall | 11,544 loose parts named a/b/c… | no separable interior; the procedural mall already has 16 fitted units |
| Boss_The mall | 2,107 | an FPS map (GameMode, TeamSpecific folders), not a mall interior |
| McDonald's Gmod Map | 579 | a 2,221-stud map, not a building |
| tree forest / City Tree / Small city tree | 40 / 55 / 19 parts *per tree* | the Nature Pack trees are 2–3 parts and look better |

The grocery store therefore stays procedural (`B.market`'s SUPER MARKET).
If a grocery model under ~1,500 parts and ~150 studs wide turns up, it
drops into the same slot the supermarket box occupies.

## Brand note

McDonald's is a real trademark. Roblox moderation does remove branded
assets from time to time; the narrative rule for this project is "no real
brands", and this one is the owner's explicit exception. If it is ever
taken down the fallback is automatic (the block builds without it).

## Grocery stores (built 2026-09-22, tested in Play)

**The loop:** walk into a grocery (the SUPER MARKET on the market block, or
any corner GROCERY on a shopping street), **E** on a shelf to TAKE a thing
into your basket, **E** at THE TILL to PAY with coins, and what you bought is
in your fridge at home — **E** on the fridge eats one for +15 XP. Walk out
with an unpaid basket and you left it at the door. Store doors also take E:
ENTER outside, LEAVE inside (McDonald's and the supermarket).

| Piece | Where |
|---|---|
| Catalogue (16 items, 8–45 coins), `BasketMax` 12, `PantryMax` 30, `SnackXP` 15 | `Config.Groceries` |
| `checkout` / `eat` actions, `data.City.pantry` | server city block |
| basket, till line, fridge, walk-out drop, basket pill | `game/CityGrocery.lua` |
| `fitGrocery` (shelves as venue spots, the till, a keeper), SUPER MARKET as a room | `CityBuild.lua` |
| `grocery` shop type is now walk-in | `Places.lua` (lot order unchanged) |
| shelf / till / warp verbs; a spot you stand on beats a nearer room centre | `CityVenues.lua` |

Fittings from the inventory: `ShelfTall` / `ShelfShort` (PBR shelves kit,
5 parts), `Cashier` (7/11 counter, 70), `Register`, `ShelfFood`,
`FoodPack_A/B`. Produce shelves carry the farm pack's own meshes
(`Food_1..8`) as the items.

**Rejected:** the *Grocery Store* building (880723024) — its interior is one
solid block, so it cannot be entered; the *NPC Dialogue System*
(80608769509945) — a script kit, and nothing from the marketplace runs code
here; the keeper's lines go through the game's own prompt card.

**Measured:** server refuses a checkout from across town ("pay at the
till"), an empty basket, 13 items, bad ids; `apple = 999` is capped to 12 and
priced from Config (paid 144). `eat` took an apple out of a fridge of 12 and
paid +15 XP. The supermarket's outer shelves lost their prompt until spots
took priority over the nearest room centre (the kerb units were closer).
The plaza was flattened to 0.24-stud slabs flush with the pavement (it had
been a 1.6-stud mesa you waded through); McDonald's is sunk 0.15 so its
floor is +0.03, and its entrance glass at the apex of the storefront V is
walk-through (it had been sealed). The straight walk-in is only ~3 studs
wide at the apex; the E doors are the intended way in.

Studio-only hook: `SminskiDev:Invoke("city", "press")` presses whatever the
prompt card is showing and returns the basket.

## Tycoon kits (2026-09-22)

Two tycoon kits from the inventory went through the same curation
(`_inventory_setup.lua` §TYCOON): **blackbot008's Tycoon Kit** (233368931,
82 parts / 12 scripts — berezaa's classic) and the **pizza hut tycoon kit**
(34943877, 1,507 parts / 331 scripts). They were inserted into ServerStorage,
not the Inventory folder, and are deleted after curation. Kept: `TycoonPad`
(the 4-stud button disc) and seven appliance clusters as `Tyc_Oven`,
`Tyc_Stove`, `Tyc_Fridge`, `Tyc_Sink`, `Tyc_Soda`, `Tyc_Fryer`, `Tyc_Cashier`
(263 parts total). Restaurant Row (docs/TYCOON.md) stands a bought piece as
its template when one exists and draws a kit-style fallback otherwise; the
templates are 2010 plastic and are placeholders for the owner's own decor
under the same names. Rejected: every script (a whole tycoon economy in
331 files), the Humanoid name tags, the R6 "customer" dummies.

Also moved, not curated: three **R6 animation packs** the owner dropped into
Workspace (`Movement System`, a `Folder` with a walk cycle, `TemplateR6` with
seven idles — 45,600 instances, replicating to every client) now sit in
ServerStorage as `Inv_Anim_*`. The Sminski is a procedurally posed part rig
(`Models.poseSminski`), not a Motor6D rig, so these cannot be played on it
as-is; see docs/HANDOFF.md.

---

# The third door: downloaded CC0 kits (2026-10-01)

A third source, alongside Blender-built props and curated Roblox-inventory
models: **downloaded third-party kits**, extracted to `~/Downloads/newassets/`.
`docs/KITS.md` is the generated record — re-run `tools/kit_manifest.py` after
adding one.

These are **not** "Claude-built" in the sense `pipeline.md` means, and they
have not been through the `assets.md` review. The same discipline as the
inventory door applies: the owner choosing them is the first gate, this file
is the record, and every placement keeps its part-built fallback.

## Licence: checked, not assumed

All six KayKit packs (Kay Lousberg) and both Quaternius MegaKits are **CC0** —
public domain, commercial use fine, no attribution required. `[Standard]` in a
Quaternius filename means "the free subset of the models", not a paid tier.

**`Voxel House Interior - Free Sample` ships no licence file.** It is flagged
`UNKNOWN` in `docs/KITS.md` and must not ship until that is resolved.

## Technically clear

All **424 meshes** are under the Roblox MeshPart limit of 10,000 triangles —
counted from the OBJ faces, not estimated. The biggest is
`table_round_A_decorated` at 4,422. Total across every kit is ~186,000
triangles, which is small.

## What each kit is actually for

| Kit | Objects | Use |
|---|---|---|
| KayKit Furniture Bits | 53 | `Config.Furniture` — the flat-furnishing shop |
| KayKit Halloween Bits | 70 | `Config.Seasons` — October dressing + seasonal shop |
| KayKit Restaurant Bits | 150 | café / kitchen / restaurant interiors |
| KayKit City Builder Bits | 61 | street furniture, shopfronts |
| KayKit RPG Tools Bits | 59 | tools — farm, construction, workshop dressing |
| KayKit Skeletons | 13 | unassigned; only if a monster loop is ever built |
| Voxel House Interior | 18 | house interiors — **licence unresolved** |
| Downtown City MegaKit | 459 | parked. A new district, later, by instruction. |

## Three that are not what they look like

- **`Garden cozy kit` contains no model files.** 94 PNGs and a PSD — 2D sprite
  art. Not a farming kit. Possibly useful as UI or texture source.
- **`Midi files` are MIDI, which Roblox cannot play.** They need rendering to
  OGG first, and the tracklist (*Demon King Castle*, *Battle Theme IV*,
  *Pyramid*) is an RPG pack — wrong register for this game entirely.
- **`modern-apartment` (92 MB FBX) and `red_house.glb` (100 MB)** are
  whole-building scenes, far past what a MeshPart takes. They need splitting
  per room and per object in Blender before anything can enter the city. That
  is modelling work, not a format conversion.

`COLORALPHA 50 Menu Interface SFX` is 50 WAVs and is directly usable for UI
sound — the one audio pack here that needs no work.

## Still to do

Nothing above is in the game yet. The meshes have to be **uploaded to Roblox**
to get asset ids, and that needs Studio or Open Cloud; then
`_inventory_setup.lua` curates them into `ReplicatedStorage.SminskiAssets.
Inventory` as `Inv_<Name>`, stripping scripts, lights, sounds and emitters
first. `Config.Furniture` and `Config.Seasons` already name every mesh they
need, and `tests/run.luau` checks all 65 of those names against
`docs/KITS.md`, so a typo cannot reach a player.
