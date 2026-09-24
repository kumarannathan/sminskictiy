# BRIEF — Short loops PHASE B: the COLLECT archetype

Slug: `collect-events` · Lead-written, 2026-09-21 · Phase A is the pattern.

---

## 1. What the human asked for, in their words

> Short loops PHASE B -- the COLLECT archetype: Cash Drop, Balloon Festival,
> and a shared City Cleanup.
>
> This continues existing work, so do NOT redesign it. Read
> `~/Desktop/SminskiCity/docs/LOOPS.md` (the plan, and section 9 for how phase
> A was built) and `docs/HANDOFF.md` section 5 (the measured street geometry
> and the phase B decisions already made). Phase A's code is the pattern to
> extend: `Config.Events`, the director at the end of the city block in
> `SminskiServer.server.lua`, and `game/CityEvents.lua`.
>
> Already decided:
> - COLLECT is a new `kind` in `Config.Events`, handled by the same director,
>   remote, phone and countdown strip as FIND. No second system.
> - No new art. Balloons = the fun park recipe in `CityBuild.lua` (~line 2009).
>   Coins = the runner's `StarCoin` mesh (`World.lua` ~1222). Litter = the
>   recipe inline in `City.lua` `applyState` (~line 434) -- factor it into a
>   shared helper, do not copy it.
> - Items scatter on the +2 strip from each lot's door line, along [-13, 13],
>   on street-filtered lots within ~170 studs of a centre lot, min 8 studs
>   apart. That strip measured 0/105 blocked with open sky above.
> - Cash Drop is competitive: 24 bags x 60 coins, each taken once, split
>   across the server. Balloons and Cleanup are cooperative: a shared goal
>   scaled by player count, small pay per item, a completion bonus for
>   everyone who contributed at least 3. Cleanup pieces also call
>   `creditWorld(player, s, "cleaner", ...)` so they count for anyone clocked
>   in as a cleaner.
> - Economy: a paced job earns ~187 coins/min. Keep events near that.
>
> Lanes needed: ux-designer (the shared progress counter on the strip and
> phone, and the finish moment), audio-designer (collect / goal-reached
> sounds, kept light), then server-engineer + client-engineer in parallel,
> then qa-tester. Skip game-loop-designer, monetization, narrative,
> world-builder and blender-artist unless something forces it.
>
> QA must sample at least six real item positions for overlaps, and try the
> exploit paths: collecting the same item twice, from too far away, after the
> event ends, and two claims racing for one cash bag.

## 2. What I understand it to mean

Phase A shipped FIND: one hidden thing, one claim, one winner. COLLECT is the
second archetype — **N things scattered in a zone, with a counter that every
player on the server shares**. It is the first time the city has a number that
belongs to the server rather than to you.

Three events, all data rows in `Config.Events.List` with `kind = "collect"`:

| Event | Mode | Shape |
|---|---|---|
| **CASH DROP** | competitive | 24 bags × 60 coins. Each bag goes to exactly one player, first there. Nothing is shared but the scramble. |
| **BALLOON FESTIVAL** | cooperative | A shared goal scaled by player count. Small pay per balloon, completion bonus to everyone who got ≥ 3. |
| **CITY CLEANUP** | cooperative | Same, plus each piece calls `creditWorld(player, s, "cleaner", ...)` so it counts toward a cleaner shift, Elo and streak. |

Everything else is reuse. The same director starts it, the same `Events`
RemoteFunction claims it, the same `CityEvent` RemoteEvent broadcasts it, the
same countdown strip and PHONE list it. `publicEv` grows a progress field;
`claim` grows an item argument. **No second system, no new remote.**

### The hard constraints that shape it

- **The server cannot see geometry.** The world is built on the client
  (`HANDOFF.md` §2), so the server cannot raycast or overlap-test. Every
  scatter position must be clear *by construction*. The +2 strip is the one
  that measured 0/105 blocked with open sky — use it and nothing else.
- **The spot is not a secret here.** Unlike FIND, a COLLECT zone is public by
  design: everyone should converge. Items can ship in the public record.
  `RevealRadius` is not the mechanism; the zone is.
- **One claim per item, server-authoritative, raced.** Two players tapping
  the same cash bag in the same frame must produce one payment. Claims are
  distance-checked against `cityPos(player)` and paid through `pay()` so
  passes and boosts multiply them, exactly as in phase A.
- **Economy.** A paced job is ~187 coins/min. Cash Drop's whole 1,440 coins
  is split across the server, not per player. Cooperative pay stays near one
  minute of job income per minute spent, travel included.

## 3. Explicitly out of scope

- **No new art, no new meshes, no Blender.** All three use recipes that
  already exist and are already approved. If a lane thinks it needs new art,
  it must say so in its spec rather than assume it — that is a human gate.
- **No new geography.** No new lots, landmarks or hide-spot lists.
- **No redesign of phase A.** FIND keeps working exactly as it does. The
  countdown strip and phone gain a progress line; they are not rebuilt.
- **No monetization, no narrative lane, no new job type.**
- Phases C–G (RUSH, dailies, RACE, ROUND, errands) are not this feature.

## 4. Lanes

| Lane | Agent | Writes |
|---|---|---|
| Design | `ux-designer` | `docs/specs/collect-events/ux.md` |
| Design | `audio-designer` | `docs/specs/collect-events/audio.md` |
| Build | `server-engineer` | `Config.lua`, `SminskiServer.server.lua` |
| Build | `client-engineer` | `CityEvents.lua`, `City.lua`, `_sr_sync.lua` |
| Gate | `qa-tester` | `docs/qa/collect-events.md` |

Skipped, per the human: `game-loop-designer` (LOOPS.md §2 and §6 already are
the loop spec and the economy guardrail), `monetization-designer`,
`narrative-designer`, `world-builder`, `blender-artist`.

`audio-engineer` is **not** expected: the 12 pooled sounds in `Audio.lua`
(`Tick Click Whoosh Pop Chime BigChime Wobble Jump Land Bump Stomp Bark`) are
all client-callable from `CityEvents.lua`, which `client-engineer` owns. If
the audio spec needs a sound that is not in that pool, that forces the lane
and the human is told.

## 5. Where the code is

| Thing | File | Line |
|---|---|---|
| `Config.Events`, `Config.Event()`, `Config.SightingTier()` | `game/Config.lua` | 960–1023 |
| The director, `Events` remote, `pickSpot`, `claim`, reveal loop, schedules | `game/SminskiServer.server.lua` | 2108–2452 |
| `streetLots` filter (381 of 385 lots) | `game/SminskiServer.server.lua` | ~2182 |
| `creditWorld(player, s, jobId, quality, got)` | `game/SminskiServer.server.lua` | 2068 |
| Client: draw, claim, prompt, strip, phone | `game/CityEvents.lua` | all 520 |
| Balloon recipe (2.4 ball, reflectance 0.15, thin string, `K.CAR_COLORS`) | `game/CityBuild.lua` | ~2009 |
| `StarCoin` mesh via `Models.rigMesh` | `game/World.lua` | ~1222 |
| Litter recipe, inline — **to be factored into a shared helper** | `game/City.lua` | ~434 |
| Dev hook `EventsDev:InvokeServer(id, atMe)` | `game/SminskiServer.server.lua` | 2436 |

## 6. Acceptance, in one line

Three COLLECT events run from the same director as FIND; a shared counter
moves for every player on the server at once; six sampled item positions are
clear of geometry; and the four exploit paths (double-claim, far-claim,
after-end claim, two claims racing one bag) all fail closed.
