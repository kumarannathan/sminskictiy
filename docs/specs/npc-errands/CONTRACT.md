# CONTRACT — npc-errands (short loops phase G, part 1)

Lead-written, 2026-09-21. Built from `narrative.md` and `game/StoryErrands.lua`.
**This file wins any conflict with the narrative spec.**

Scope, per the human: phase G ships **NPC errands** and a **cheap Photo Hunt**.
Power Outage and neighbour knocks are out. **Photo Hunt is not designed yet and
is not in this contract** — it gets its own, so this build is not blocked.

---

## 0. Lead decisions

**G1. An errand is FIND, scoped to one player. No new archetype.** `LOOPS.md`
§3 already says so. It reuses the director's clue helpers (`compass`,
`streetOf`, `nearestLandmark`, `areaOf`), the `streetLots` pool and the
measured `door + t*±11 + n*2.5` geometry. **No new remote, no new RemoteEvent.**

**G2. The away-spot is seeded, never stored.** `narrative.md` asks for a
deterministic per-player spot from `(userId, npc, beatIndex)`. Do exactly that:
it survives a disconnect with **zero new save fields** and needs no reveal
bookkeeping beyond what phase A already does. This is the same discipline as
phase D's hunt seeding, which stores no lot index — and for the same reason:
**saves store indices, and this project's lists are append-only because of it.**

**G3. Errand spots inherit phase D's two exclusions.** They are placed on the
same strip by the same helpers, so they must honour:
- the **station-lift exclusion** (`Config.Hunt.ExcludeR`, and see
  `docs/HANDOFF.md` §5) — the Elevated's lifts land on the door strip at
  x/z = ±600 with an r=7 `UP` prompt, which makes anything there
  **unclaimable**;
- **≥ 12 studs from any live event spot**, phase B's rule, so an errand item
  and a sighting cannot occupy the same place.

Two claimable things in one spot is the bug; one shared exclusion helper is the
fix. Do not write a third copy of the rule.

**G4. The talk prompt is a new branch in `E.prompt`, not a new system.**
`narrative.md` asks for a "talk" interaction distinct from the shop's existing
BROWSE/READ/PET. `E.prompt` runs at `City.lua:2170`, **before** the shop and
`MallShops` branches, so an errand-giver's prompt can take precedence while the
shop's own prompt returns when there is nothing to say.

> **Order inside `E.prompt` is load-bearing.** Phase D placed the Capsule
> Corner branch *after* the event loop so a rare sighting on the mall block
> could not be made unclaimable by holding a ticket. Apply the same reasoning:
> a live event claim outranks an errand conversation, which outranks a shop.

**G5. The found-item marker reuses phase B's pooled parts.** No new mesh, no
new art, no per-item light (`performance.md`). `CityEvents.lua` already pools
balloon, coin and litter parts; a stapler / pin / spool / book page is a pooled
primitive from the same pool, not a Blender job.

**G6. `StoryErrands.lua` keys are frozen on ship.** Saved progress refers to
them. Once shipped they are **appended to, never renamed or removed** — the
same rule as `Places.cityLots()` and `Places.CityLandmarks`.

### Decided (human, recorded in the narrative spec)

| Question | Decision |
|---|---|
| Day-gating between beats | **No**, not for launch. Phase D's Daily 3 is already the returning-player hook. |
| The `Sunny` name clash | Renamed **Fern** (clashed with `Sunny St` and `Sunny Homes`). |
| Wren's tone | **Stays lightly magical** — one odd voice in five. |
| Reward total 220–300 coins/arc | **Stands.** Under job income, reads as a discovery bonus. |
| Cast size | **Five** for launch, all inside the downtown slice. |

---

## 1. Config and data

**No `Config.Events.List` row.** An errand is not a director-scheduled event:
it has no `lasts`, no `warn`, no `uid`, and it is per-player. It is a block
beside the director sharing helpers, exactly as phase D's `Hunt` is.

`game/StoryErrands.lua` is the content and already exists — data only, no
logic, no requires, and **not** in `_sr_sync.lua`'s module list. **It must be
added to that list to reach Studio** (`client-engineer` owns `_sr_sync.lua`).

**Saved, under `data.City`:** one integer per NPC — the story index.

```lua
errands = { nell = 2, marlow = 0, wren = 1, oskar = 0, fern = 3 }
```

Keyed by `StoryErrands` id, **dense is not required here** (it is a string-keyed
map, not an array), but it **must** be back-filled by the same lazy-migration
point phase D used (`saved()`, not `reconcile()` — `reconcile()` has no access
to the city block). A pre-phase-G save must build it without throwing.

> **Learn phase D's save bug rather than repeating it.** A sparse *array*
> round-trips through DataStore JSON as a string-keyed dictionary. This map is
> already string-keyed so it is safe — but if any part of the errand state
> becomes an array, it must be dense.

## 2. Remotes — no new remote

- `Events:InvokeServer("errandTalk", npcId)` → advance/among-beat reply.
- `Events:InvokeServer("errandClaim", npcId)` → the find claim.
- Reply fields: `{ ok, reason, coins, xp, beat, say, task, spot, data, city }`.
- Reveal of an away-spot rides a **new kind**, `errandReveal`.

> **`spot` must be KEY-SHAPED: `{ x, z, face }`.** Phase A's `secret()` uses a
> **positional** array and is correct for its own consumer; phase D shipped a
> positional `huntReveal` by copying it, and the result was **no model, no
> error and no warning** — every hunt check failing for one invisible cause.
> Both shapes now legitimately coexist in `SminskiServer.server.lua` with
> comments marking the boundary at `:2645` and `:3667`. Read those before
> writing a payload.

**Do not reuse `reveal`.** `onReveal` (`CityEvents.lua`) fabricates a whole
`sighting` event for an unknown uid, so an errand reveal on that kind would
invent a phantom event in `E.list`, the phone **and** the strip. Existing kinds:
`start · end · progress · taken · done · found · reveal · reward · ticket ·
huntClues · huntFound · huntReveal · huntHide · huntReset`.

## 3. Strings and wording

**`narrative.md` and `StoryErrands.lua` are verbatim.** Every line of dialogue,
the epilogues, the notify titles and the beacon labels are written; do not
author replacements. Budgets already verified there: `say` lines ≤ 40 chars
each, notify subs ≤ 40, beacon labels ≤ 14.

Clue text on the one "away" beat per arc uses the **existing** helpers
(`compass` / `streetOf` / `nearestLandmark`). Do not invent a new clue grammar —
the city already has one and the player has learned it.

## 4. Work split

| File | Owner | Changes |
|---|---|---|
| `game/SminskiServer.server.lua` | `server-engineer` | The errand block beside the director: G2 seeding, G3 exclusions, talk/claim, payment through `pay()`, the `errandReveal` push, `saved()` back-fill, dev hooks (§5). |
| `game/Config.lua` | `server-engineer` | Only if a tunable is genuinely needed (reveal radius, claim radius). Prefer reusing `Config.Hunt`'s. |
| `game/CityEvents.lua` | `client-engineer` | The talk prompt branch, the errand find drawing from the **existing** pool, the `errandReveal` kind, the phone row if `narrative.md` asks for one. |
| `game/_sr_sync.lua` | `client-engineer` | **Add `StoryErrands`** — it cannot reach Studio otherwise. |
| `game/StoryErrands.lua` | `narrative-designer` | Content only; already written. Append-only once shipped. |

No new files beyond the existing `StoryErrands.lua`, so **no `ownership.json`
change**. **Assets: none** — five existing shopkeeper/clerk Sminskis, pooled
primitives for the items.

## 5. Test hooks

Inside the existing `if RunService:IsStudio()` guard, on `EventsDev`:

1. `errandSet(npcId, beat)` — jump an NPC's arc to any beat, so a five-beat
   arc is testable without playing five beats.
2. `errandSpot(npcId)` — return the seeded away-spot for the current beat, so
   its geometry can be measured the way `huntSeed` allowed.

## 6. Acceptance

1. Five NPCs each run their full arc; the epilogue plays forever after.
2. The away-spot is **stable across a disconnect** — same position on rejoin,
   with no new save field holding it.
3. Away-spots are on the `+2.5` strip, **never on a station-lift lot**, and
   **≥12 studs from any live event spot**.
4. `errandReveal`'s `spot` is key-shaped and a model actually draws. *Test this
   first* — the positional-array failure mode is silent.
5. The talk prompt beats the shop's prompt where an errand is live, and a live
   event claim still beats the talk prompt.
6. Story index survives a rejoin mid-arc; a pre-phase-G save builds it without
   throwing.
7. Payment runs through `pay()` so passes and boosts apply. Coin expectations
   are **formulas** — `base × citypro × coinMult × boost × StreakMult(login
   streak)` — never hardcoded numbers (this project's payouts drift ~10%/day
   until the streak caps).
8. Phases A, B, D and the phone are unregressed.
