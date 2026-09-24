# Collect Events -- audio

WHAT EXISTS ALREADY
--------------------------------------------------------------------------
- `game/Audio.lua` is the whole palette I'm allowed to use. Pooled voices:
  `Tick`(5) `Click`(3) `Whoosh`(3) `Pop`(3) `Chime`(2) `BigChime`(1)
  `Wobble`(1) `Jump`(2) `Land`(2) `Bump`(2) `Stomp`(3) `Bark`(2, conditional).
  `Audio.play(name, pitch, volMul)` plays `pool[name].vol * volMul` at
  `pitch` (`Audio.lua:185-195`). No new asset, no new pool: everything below
  is pitch/volume/timing/repetition over this list, per the brief.
- **`Audio.coin(now, gold)` already exists and is exported** (`Audio.lua:198-206`):
  a rising pentatonic run (`SCALE = {1,1.122,1.26,1.498,1.682,2,2.245,2.52}`,
  played as `Tick` at `1.5 * SCALE[step]`), reset if the gap since the last
  call exceeds **0.7s**, plus a louder `Tick` and an extra `Chime`@1.4/0.6
  when `gold` is true. This is the exact "run/reset" shape the task asks me
  to reuse for the single pickup (§1 below) -- but see the note under §1 on
  why I'm *not* calling this function directly.
- `Audio.coin` is currently called from exactly one place:
  `game/SminskiRunner.client.lua:2004`, the endless-runner minigame. It is a
  different script, a different mode, and never runs at the same time as
  walking the city, so its module-level `coinStep`/`lastCoin` state is safe
  to leave alone -- but it also means its 0.7s reset gap was tuned for the
  runner's dense coin lane (sub-second spacing), not for items that the
  brief places **>= 8 studs apart** in the open street. Re-using the *shape*
  with a wider reset gap, tracked locally in `CityEvents.lua`, gets the same
  feeling without dragging in a mismatched tuning or touching `Audio.lua`
  (which nobody owns on this feature -- see `BRIEF.md` §4, no
  `audio-engineer`).
- `game/CityEvents.lua:260-283` (`claim`) is the **one existing claim path**,
  shared by every `mine` event today, and it unconditionally ends with
  `Audio.play("BigChime", 1.25, 0.8)`. If Cash Drop / Balloon / Cleanup route
  their per-item pickups through this same function unchanged (which the
  brief's "claim grows an item argument" suggests they will), every one of
  dozens of pickups gets the FIND finale sound. **That is the exact "torture
  the 30th time" failure the task warns about**, and it is a real risk
  because the code path is shared, not hypothetical. My design assumes this
  call is branched by `ev.def.kind` -- `"find"` keeps `BigChime`@1.25/0.8
  exactly as today (must not regress FIND), `"collect"` uses the pickup run
  in §1 instead. This is the one place my spec asks for a change to
  *behaviour* the client-engineer would otherwise ship unmodified, so I'm
  flagging it here plainly rather than assuming it.
- `CityEvents.lua:179-200` (`onStart`) already plays `Audio.play("BigChime",
  1.05, 0.6)` on every announce, `find` or otherwise, since it's generic.
  `CityEvents.lua:223-239` (`onReveal`) plays `Chime`@1.4/0.5 the first time
  a *hidden* thing's exact spot arrives -- this is FIND's "you're close"
  tell. COLLECT zones are public by construction (`BRIEF.md` §2: "the spot
  is not a secret here"), so `onReveal` should simply never fire for a
  `collect` event; there is nothing to reveal. I am not asking for a new
  proximity chime to replace it -- see the silence list.
- `CityEvents.lua:202-212` (`onEnd`) plays **no sound at all today**, win or
  lose ("nobody found it this time" is a silent toast). That is the existing
  precedent for restraint at end-of-event, and I keep it for the failure
  cases below.
- `CityEvents.lua:469-479` (the clue-unlock loop in `E.step`) is the existing
  pattern for "a shared clock crosses N thresholds, announce only the ones
  that are new, and don't announce ones you've already missed on a late
  join." I reuse this idiom verbatim for milestones (§2) instead of
  inventing a new bookkeeping shape.
- `Audio.lua:106-121` (`ambientGen`) is the existing pattern for cancelling a
  sound that was scheduled with `task.delay`/a coroutine if the world state
  changes before it fires (its own comment explains the bug it fixes). I
  reuse this idiom to guard the goal-reached sequence (§3) against firing
  after the player has left the city or the event has ended.
- `Audio.musicStart` / `Audio.ambient` / `Audio.duck` (`Audio.lua:63-122,
  215-218`) are called only from `SminskiRunner.client.lua` and once from
  `Park.lua`. **Nothing plays music through `Audio.lua` while walking the
  city** -- `City.lua`'s ~20 `Audio.play` calls never touch `musicStart` or
  `duck`. So there is no music bed in the city for `Audio.duck` to duck
  against; reaching for it here would be a no-op. Ambience in the city comes
  from `CitySound.lua`'s positional beds instead, which `Audio.duck` does
  not touch and which this feature does not need to change (see CUT/DEFER).
- `game/CitySound.lua` shapes ten built-ins into positional beds/one-shots
  with a small emitter pool, but `client-engineer` on this feature owns
  `CityEvents.lua`, `City.lua`, `_sr_sync.lua` -- not `CitySound.lua` -- and
  no `audio-engineer` is scoped in (`BRIEF.md` §4). So everything below is
  **2D**, through `Audio.lua`, called from files client-engineer already
  owns. I name the positional idea I had to drop under CUT/DEFER.

THE DESIGN
--------------------------------------------------------------------------

| Trigger (exact) | 2D/pos | Recipe | Pitch | Volume (volMul) | Priority | Cooldown / max |
|---|---|---|---|---|---|---|
| Local player picks up **one** item (coin bag's coins, one balloon, one litter piece) -- any of the three events | 2D | `Tick` run, local pentatonic step (§ pseudocode) | `1.5 * SCALE[step]`, step 1-8, wraps | 1.0 (1.4 if `gold`, i.e. Cash Drop's final bag) | low (base layer) | run resets after 2.5s of no pickup; uncapped count, naturally throttled by item spacing |
| Nearby item picked up by **another** player | -- | silent | -- | -- | -- | -- |
| Shared bar crosses 25% / 50% / 75% (Balloon Festival, City Cleanup only) | 2D | `Chime` | 1.00 / 1.15 / 1.30 (per threshold) | 0.5 | medium | fires once per threshold per event, max 3/event, for every connected client |
| Shared bar reaches 100% -- **the goal is met** | 2D, 3-part sequence | `BigChime`, `BigChime`, `Chime` | 1.15 / 1.50 / 1.80 | 0.7 / 0.9 / 0.45 | highest in COLLECT | fires once per event, for every connected client |
| Local player's personal completion bonus lands (contributed >= 3) | 2D | `BigChime` | 1.35 | 0.85 | high (personal) | once per player per event |
| Local player misses the bonus (contributed 1-2) | 2D | `Chime` | 1.15 | 0.5 | low-medium | once per player per event; **never fires at 0 contributed** |
| Cash Drop: the 24th (last) bag is claimed, by whoever claims it | 2D | `Tick` run with `gold=true` (loud `Tick` + trailing `Chime`) | see run row + `Chime`@1.4/0.6 | 1.4 (Tick), 0.6 (Chime) | medium-high, personal only | once per event, one player |
| Announce, 45s (Balloon/Cleanup, cooperative) | 2D | `BigChime` | 1.05 (unchanged) | 0.6 (unchanged) | as FIND today | once per event |
| Announce, 45s (Cash Drop, competitive) | 2D | `BigChime` | 1.15 | 0.65 | as FIND today, slightly brighter | once per event |
| Event ends: cooperative goal *not* reached (timer ran out) | -- | silent | -- | -- | -- | matches existing `onEnd`, no change |
| Event ends: Cash Drop timer runs out with bags unclaimed | -- | silent | -- | -- | -- | matches existing `onEnd`, no change |
| Losing a race for one Cash Drop bag (claim rejected, someone beat you) | -- | silent | -- | -- | -- | matches existing failed-claim path (`CityEvents.lua:266-268`), unchanged |

### The pickup run -- pseudocode (client-engineer, in `CityEvents.lua`)

```lua
-- local to this module, NOT Audio.lua -- keeps its own tuning separate from
-- the runner minigame's Audio.coin (Audio.lua:198), which is tuned for a
-- much denser coin lane.
local PICKUP_SCALE = { 1, 1.122, 1.26, 1.498, 1.682, 2, 2.245, 2.52 } -- copy of Audio.lua's SCALE
local PICKUP_RESET_GAP = 2.5 -- seconds; wider than Audio.lua's 0.7s because
                              -- items are placed >= 8 studs apart (BRIEF.md)
local pickupStep, lastPickup = 0, 0

local function playPickup(gold)
	local t = now()
	if t - lastPickup > PICKUP_RESET_GAP then pickupStep = 0 end
	lastPickup = t
	pickupStep = pickupStep % #PICKUP_SCALE + 1
	Audio.play("Tick", 1.5 * PICKUP_SCALE[pickupStep], gold and 1.4 or 1)
	if gold then Audio.play("Chime", 1.4, 0.6) end
end
```

Call `playPickup(false)` on every successful local pickup in all three
events. Call `playPickup(true)` **only** for the Cash Drop claim that makes
`progress.count == progress.total` (the last bag) -- see NUMBERS for how the
client can tell.

This replaces the current unconditional `Audio.play("BigChime", 1.25, 0.8)`
at the end of `claim()` **for `kind == "collect"` only**. FIND's claim
(sighting/pup/icecream) keeps that line exactly as it is.

### Milestones + goal -- pseudocode (mirrors the existing clue-unlock loop)

```lua
-- ev.progress = { count = N, total = M } arrives on the replicated event
-- (the field the ux-designer spec adds to publicEv). Runs once per ev per
-- E.step() tick, same place the clue-unlock loop already lives.
local MILESTONES = { 0.25, 0.50, 0.75 }

local function checkProgress(ev, fresh)
	if not ev.progress or (ev.progress.total or 0) <= 0 then return end
	local frac = ev.progress.count / ev.progress.total
	local crossed = 0
	for _, th in MILESTONES do if frac >= th then crossed += 1 end end
	if fresh then
		-- a mid-event joiner silently catches up, exactly like cluesShown
		-- does today -- no burst of missed-milestone chimes on arrival.
		ev.milestonesShown = crossed
	elseif crossed > (ev.milestonesShown or 0) then
		for i = (ev.milestonesShown or 0) + 1, crossed do
			Audio.play("Chime", 1.00 + 0.15 * (i - 1), 0.5)
		end
		ev.milestonesShown = crossed
	end
	if frac >= 1 and not ev.goalCelebrated and not fresh then
		ev.goalCelebrated = true
		local gen = ev.uid -- or a small per-event generation counter, see below
		Audio.play("BigChime", 1.15, 0.7)
		task.delay(0.30, function()
			if E.list[ev.uid] == ev then Audio.play("BigChime", 1.50, 0.9) end
		end)
		task.delay(0.55, function()
			if E.list[ev.uid] == ev then Audio.play("Chime", 1.80, 0.45) end
		end)
	end
end
```

The `E.list[ev.uid] == ev` checks before the two delayed plays are the
`ambientGen`-style guard (`Audio.lua:106-121`): if the event has ended or the
player has left the city between t=0 and t=0.55s, `undraw`/`E.leave` will
already have cleared or replaced the table entry, and the stray play is
skipped. **QA should check exactly this** (see QA section).

### Personal bonus / miss

Fire once, at the point the server tells the client the local player's own
final contribution for that event (whatever payload carries the bonus --
likely the same one the ux-designer's result card reads):

```lua
if myContributed >= 3 then
	Audio.play("BigChime", 1.35, 0.85)
elseif myContributed >= 1 then
	Audio.play("Chime", 1.15, 0.5)
end
-- myContributed == 0: nothing. You didn't play; there is nothing to reward.
```

If this resolves at the same instant as the goal-reached sequence (the
common case for a cooperative event you personally finished), offset it to
**t = +0.85s** after the sequence's first `BigChime` -- 0.3s clear of the
trailing `Chime`@1.80 -- so it reads as "and here's yours" after the shared
moment, not on top of it. If it resolves separately (event timed out without
the shared goal being met, but you personally hit 3), it plays immediately
with nothing to offset against.

### What ducks what

Nothing. `Audio.duck` only attenuates `musicGroup`, and nothing in the city
walk plays through `musicGroup` (see WHAT EXISTS ALREADY) -- reaching for it
here would silently do nothing. The goal-reached sequence gets its impact
from being the loudest, biggest thing in the table (two `BigChime`s), not
from ducking anything else.

### Time of day / weather

Deliberately **no variation**. These are reward-feedback cues, not
atmosphere -- a milestone chime should sound exactly the same at noon and at
3am in the rain, so it stays recognisable. Atmosphere (rain, evening hum,
dawn) is `CitySound.lua`'s job and untouched by this feature.

### Restraint -- what stays silent, and why

- **Another player's pickup**, at any distance. Hearing every Tick from a
  four-player Balloon Festival scramble is a wall of noise, not five sounds
  reading as five sounds -- it's fifty. Your own pickup already tells you
  you were paid; the shared bar (milestones + goal) is the *collective*
  feedback channel, and that's the only place other players' progress
  should be audible.
- **`onReveal`'s proximity `Chime`@1.4/0.5.** That's FIND's "you found the
  hidden thing" tell. COLLECT items are never hidden -- the zone is public
  by design (`BRIEF.md` §2) -- so this cue has no COLLECT use and must not
  be wired to it.
- **Losing a race for one Cash Drop bag.** The failed-claim path already
  plays nothing (`CityEvents.lua:266-268`) and stays that way -- a "you
  lost" sting would read as punishing exactly where FIND already chose not
  to punish ("someone else found it first" is a silent toast today too).
- **Event ends without the goal met**, both cooperative events and Cash
  Drop running out of bags. Matches existing `onEnd` behaviour exactly: a
  toast, no sound. Losing quietly beats losing loudly.
- **Zero contribution at event end.** No consolation sound at all -- see
  the pseudocode above. A sound for "you did nothing" is not a smaller
  reward, it's a nag.
- **The countdown strip's clock**, ticking down every second while a
  COLLECT event runs. No per-second sound today for FIND either; not adding
  one for COLLECT.
- **`creditWorld`'s cleaner-shift crediting** on City Cleanup pieces. One
  tap should be one sound. It already gets the pickup run; the fact that it
  also counts toward a job shift is not a second audio event.

NUMBERS
--------------------------------------------------------------------------
| Tunable | Value | Why |
|---|---|---|
| `PICKUP_RESET_GAP` | 2.5s | Items are >=8 studs apart (BRIEF.md); a walking/running Smiski needs more than `Audio.coin`'s 0.7s to reach the next one, so 0.7s would reset the run on almost every pickup and lose the climbing feel entirely. 2.5s covers a short run/hop between two adjacent items without covering the walk across a whole zone. |
| `PICKUP_SCALE` ceiling | step 8 -> pitch `1.5*2.52 = 3.78` | Copied unchanged from `Audio.lua`'s `SCALE` -- proven, and reusing the literal numbers means it still sounds like "the same coin sound" the player already knows from elsewhere in the game. |
| Run wrap | steps past 8 restart at 1 (pitch 1.5) | Existing behaviour of the modulo in `Audio.coin`; a genuinely long Balloon Festival chain (dense scatter, many players) will loop the scale rather than climb forever, which is intended -- an unbounded pitch would eventually leave the audible/pleasant range. |
| Milestone pitches | 1.00 / 1.15 / 1.30 | Small, even steps -- distinct from each other and from the pickup run's scale, but clearly smaller than the goal fanfare (1.15-1.80) and the personal bonus (1.35). |
| Milestone volume | 0.5 | Above a plain pickup (whose `Tick` pool base is 0.35, further scaled by `volMul`), below the personal bonus (0.85) -- middle of the reward ladder. |
| Goal sequence timing | 0s / +0.30s / +0.55s | `BigChime` has one voice (`Audio.lua:177`), so the second call at +0.30s necessarily cuts the first short -- that's not a bug to route around, it's the two-note "ta-da" the sequence wants. +0.55s for the trailing `Chime` (a different pool, 2 voices) leaves the second `BigChime` ~0.25s to ring before it layers in. |
| Goal sequence pitches/volumes | 1.15/0.7, 1.50/0.9, 1.80/0.45 | Rising pitch and rising then falling volume reads as build-then-release; the trailing `Chime` is quieter because it's a sparkle, not the payload. |
| Personal bonus | `BigChime` 1.35/0.85 | Sits between a plain FIND claim (1.25/0.8, unchanged) and the goal sequence's peak (1.50/0.9) -- bigger than an ordinary claim because it's a completion bonus, smaller than the shared moment because it's personal, not the whole server's. |
| Personal-bonus offset from goal sequence | +0.85s | 0.3s clear of the sequence's last note (+0.55s) so the two don't blur into one noise when the same player triggers both. |
| Miss consolation | `Chime` 1.15/0.5 | Same volume tier as a milestone -- "still a reward, just a small one" -- but a slightly flatter pitch (no rising-scale feel) so it doesn't read as an achievement. |
| Competitive announce | `BigChime` 1.15/0.65 vs cooperative's unchanged 1.05/0.6 | +0.10 pitch / +0.05 volume: just enough to feel a beat brighter/faster for "get there first," without becoming a different sound. Branch on `ev.def.shared == false` (the field name `LOOPS.md` §2's example data row uses for Cash Drop) -- if server-engineer lands on a different field name for competitive vs cooperative, the audio branch condition just needs to follow it. |
| Cash-Drop last-bag `gold` flag | fires when `progress.count == progress.total` after the claim resolves | Reuses `Audio.coin`'s existing `gold` behaviour (`Audio.lua:200-206`) verbatim -- no new numbers, no new code path, just a boolean the client already has once it's tracking `progress` for the milestone logic above. |

EDGE CASES
--------------------------------------------------------------------------
- **Empty server (1 active player).** A cooperative goal scaled by player
  count should be reachable solo; the milestone/goal audio is computed
  client-side from replicated `progress` and doesn't care how many players
  contributed, so no special case.
- **One player finishes the whole cooperative goal alone.** Goal sequence
  fires once at frac>=1, personal bonus fires at +0.85s as designed -- see
  the offset math above, this is the case it's tuned for.
- **A scripted/idle player who never picks anything up.** `myContributed ==
  0`: silent at event end, per the restraint list. Must not fire the miss
  chime for someone who didn't participate at all.
- **Mid-event join**, cooperative bar already past 50%. The `fresh` branch
  in `checkProgress` sets `ev.milestonesShown` to the already-crossed count
  without playing anything -- mirrors the existing `cluesShown` catch-up
  behaviour exactly (`CityEvents.lua:474-479`). Without this, every player
  who tabs into the city mid-event would hear 1-2 Chimes fire the instant
  their client first syncs the event, which reads as a bug, not a reward.
- **Mid-event leave**, between the goal being hit and the trailing `Chime`
  at +0.55s (or the personal bonus at +0.85s). The `E.list[ev.uid] == ev`
  guards on the two delayed plays make this silent rather than an error or
  a sound firing into an empty HUD -- this is the exact case
  `Audio.lua:97-105`'s comment warns about (a delayed play outliving the
  state it was scheduled for).
- **Two claims racing one Cash Drop bag.** Exactly one resolves `ok`; the
  loser's client already takes the silent failed-claim path
  (`CityEvents.lua:266-268`) -- no change needed, and no sound should be
  added there (see restraint list).
- **The event that would have been "last bag" is claimed by a player who
  then immediately leaves.** The `gold` `Tick`+`Chime` already fired
  synchronously inside `playPickup` before any delay, so there's nothing to
  guard -- unlike the goal sequence, this cue has no `task.delay` in it.

NEEDS FROM OTHER LANES
--------------------------------------------------------------------------
- **`ev.progress = { count, total }` on the replicated collect event**,
  for both cooperative events and Cash Drop. Milestones and the goal
  sequence need it for Balloon/Cleanup; the last-bag `gold` accent needs it
  for Cash Drop too (`progress.count == progress.total`). This is very
  likely the same field `ux-designer` needs for the strip/phone progress
  line -- naming it here so it isn't assumed to already exist.
- **The local player's own final contribution count (or a precomputed
  bonus/miss flag) in whatever payload resolves the event for that
  player**, so the client knows to play the bonus `BigChime` vs the miss
  `Chime` vs nothing. Likely already needed by ux-designer's result card;
  flagging so it isn't dropped as "audio-only, not needed."
- **Confirmation of the field name used to distinguish competitive vs
  cooperative** on an event definition (`LOOPS.md`'s example uses `shared =
  false` for Cash Drop) -- the announce-pitch branch needs to key off
  whatever server-engineer actually ships.
- **The `claim()`-ending `BigChime` in `CityEvents.lua:281` branched by
  `ev.def.kind`.** Not a new sound, but a real behaviour change to existing
  shared code that this design depends on -- flagging explicitly per WHAT
  EXISTS ALREADY, not assuming client-engineer will infer it.

CUT / DEFER
--------------------------------------------------------------------------
- **A positional ambience bed for standing inside a COLLECT zone** (e.g. a
  brighter, faster version of `CitySound.lua`'s town bed while a Balloon
  Festival is live nearby). Would need `CitySound.lua` changes, which is
  outside both this feature's lane list (no `audio-engineer`) and
  client-engineer's owned files. Worth a future pass once that lane is
  scoped in -- named here so it isn't lost.
- **A soft, distant cue for other players' pickups nearby.** Cut for
  restraint (see silence list) and because giving it any audible presence
  at all reopens the "torture the 30th time" problem for whoever is
  standing in the middle of the scramble hearing everyone else's Ticks too.
- **A negative sting for losing a Cash Drop race.** Cut; matches FIND's
  existing choice not to punish the runner-up.
- **A distinct sound layered onto City Cleanup pickups for the
  `creditWorld`/cleaner-shift side of the credit.** Cut; one tap, one sound.
- **Weather/time-of-day variation of any cue in this spec.** Cut; these are
  reward feedback, not atmosphere, and should stay recognisable regardless
  of the sky.

OPEN QUESTIONS FOR THE HUMAN
--------------------------------------------------------------------------
1. Is the competitive-vs-cooperative announce difference (1.15/0.65 vs the
   unchanged 1.05/0.6) worth the branch, or should every COLLECT announce
   stay identical to FIND's for maximum consistency? Pure taste call.
2. Is the miss-consolation `Chime` (contributed 1-2) worth shipping at all,
   or does surfacing "you almost got the bonus" undercut the "still a
   reward" framing more than it helps? The alternative is: sub-3
   contributors get their per-item Ticks during play and nothing extra at
   the end.
3. Cash Drop's last-bag `gold` accent rewards whoever happens to grab bag
   24 by pure chance of ordering, not by any merit. Keep it (a small,
   arbitrary "that was the last one" moment), or drop it so Cash Drop ends
   exactly as quietly as FIND does today?
