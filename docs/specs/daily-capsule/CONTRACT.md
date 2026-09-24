# CONTRACT — daily-capsule (short loops phase D)

Lead-written, 2026-09-21. Merges `loop.md`, `ux.md` and `monetization.md`
(including Addendum A). **This file wins any conflict with any of them.**

Read first: your own lane's spec, then this.

---

## 0. Lead decisions

**D1. The hunt candidate pool excludes lots whose prompt the hunt cannot win.**
`ux.md` §8 assumes `E.prompt` wins because it outranks every shop and business
door — true, but incomplete. It does **not** outrank `City.Apts`, `City.Home`,
`City.Roads` or `City.Hang` (`City.lua:2156-2170`). A hunt Sminski on a
hangout, apartment or station lot would be **permanently unclaimable**: the
player stands on it, the other module's prompt shows, and there is no way to
say hello.

> Exclude those lots from the hunt's candidate pool, by the same
> by-construction discipline phase B used for scatter. Roughly 10 lots. Do
> **not** solve it by changing prompt priority — that would reorder
> interactions players already rely on.

**D2. `found` is a dense 3-element boolean array. Everywhere. No exceptions.**
Both specs now say so; it is repeated here because it is a data-loss bug, not
a style note. A sparse `{ [1] = true, [3] = true }` round-trips through
DataStore JSON as a **string-keyed dictionary**, so after a rejoin `found[1]`
reads nil, the player sees `0 / 3` — **and can re-claim the whole day's
reward.** Normalise once, on the way out of the save layer, and coerce on load.
Nothing in phase D may be a sparse array.

**D3. The ticket is not a costume, and the contract says so.** Every earlier
draft leaned on `LOOPS.md` §6's cosmetic exemption. That exemption is void for
capsule characters: all 15 carry a live passive (`Config.Passives`), `Secret`
is `coin = 2`, wired at `SminskiRunner.client.lua:433` and applied at `:2000`,
into the shared wallet. Corrected value of one ticket:

| Remaining lifetime run income | Ticket worth |
|---|---|
| 10,000 coins | ~270–292 |
| **50,000** | **~1,000** (11–14× the 69.6–92.1 previously published) |
| 200,000 | ~4,070 |

`Ticket = 1870` **still ships** — the human's decision, to be tuned after
measurement. But the builders should know the rate governs how fast players
acquire **gameplay advantage**, not cosmetics (~5.7 days to Golden at ~6
tickets/day). City inflation and time-to-Golden are two different trade-offs
and must not be resolved with one number later.

Mitigating, and verified: `award()`'s clamp caps run coins at 0.7/stud
(`SminskiServer.server.lua:419-420`), so Golden + Doubler is already truncated.

**D4. New `CityEvent` kinds must not reuse `"reveal"`.** Phase A/B already use
`start · end · progress · taken · done · found · reveal · reward`. `onReveal`
(`CityEvents.lua:888-897`) **fabricates a whole `sighting` event** for an
unknown uid, so a hunt reveal on that kind would invent a phantom event in
`E.list`, the phone and the strip. Phase D adds, all distinct:
`ticket · huntClues · huntFound · huntReveal · huntHide · huntReset`.

### Decided, flagged for the human at review (not blocking)

| Source | Question | Decision |
|---|---|---|
| human | 7-day streak reward | **A capsule ticket.** Noted: this is a second free-ticket source on the thing the meter rate-limits; bounded at one per 7 days. |
| human | free tickets count toward `wcaps` | **Yes.** ~280 coins/week expected (drawn 2 weeks in 5), not the 800 first estimated. |
| human | `Ticket` value | **1870 ships**, tune after measuring. |
| lead | Endless Run fills the meter | **No — city only.** `award()` bypasses `pay()`, so this is free. |
| lead | `DayCap = 12` | **Keep.** Cheap insurance against a scripted 2-hour session. |
| lead | restricted-player coin fallback | **REJECTED** (reversing my earlier approval). The ticket path is *exempt* from the paid-random-items policy and free play is Roblox's own first-listed remedy; 240 minted coins denies the remedy and is 2.3× the mid-life stream. |
| lead | third pill in the top-right | **Accept.** The 138px band between the coin pill and the nav column is measured to exist on every canvas. |
| lead | show `0` tickets when holding none | **Show `0`.** Honest, and teaches the unit. |
| lead | `CITY NEWS` `LayoutOrder` 30 → 70 | **Done already** — built into the phone, so phase D does not touch a neighbour's file. |
| lead | day 7 line bigger than one line | **One line.** `SEVEN DAYS RUNNING!` replaces `ALL THREE FOUND!`, never both. |
| lead | mention the daily cap | **Only on a deliberate tap.** |
| lead | `SAY HI` shared with phase A | **Keep.** Same gesture; separated by title, icon, scale and skin. |

---

## 1. Config — exact

`Config.Meter` per `loop.md` §676-690, with these bindings fixed:

```lua
Config.Meter = {
    Ticket   = 1870,   -- units per ticket = 10 x PerMin
    PerMin   = 187,    -- ceiling: max units credited per rolling minute
    Burst    = 187,
    DayCap   = 12,     -- tickets GRANTED per UTC day, both sources
    MaxTickets = 4,    -- banked cap; 4 is legal
}
Config.Hunt = {
    Reveal = 90,       -- studs; deliberately tighter than a sighting's 130
    Count  = 3,
    Rewards = { 60, 90, 150 },   -- base coins for finds 1, 2, 3
    StreakDays = 7,
}
```

The whitelist of `stat` tags that credit the meter is `loop.md` N1 verbatim.
`BizCollects` (both sites), `HomeNaps` and the claw's untagged `pay()` credit
**zero**. `award()` is excluded for free because it never calls `pay()`.

**Pass-neutrality, corrected.** The **ceiling** is pass-proof; the **floor** is
not. Taxi and parcels saturate 187/min on the free convertible, so passes
change nothing there; **sweeping moves up to 2.1×** with QUICK FEET + DREAM
GARAGE. Nobody beats 10 minutes. QA item 6 must name the activity.

## 2. Remotes — no new remote

Everything rides existing objects: `rf("Events")` (`:2754`), `rf("City")`
(`:1643`), and the `CityEvent` RemoteEvent.

- **Meter: no new payload.** `publicData(s)` clones `s.data`, so
  `data.City.meter` / `.tickets` / `.meterDayTickets` already reach the client.
- `CityEvent("ticket", { tickets, meter, from = "meter"|"hunt"|"streak" })` —
  fired to the granted player, because a ticket can be granted on a deferred or
  server-initiated payout whose reply the client never sees. Authoritative over
  `ctx.data` until the next `data` arrives.
- `Events:InvokeServer("state")` reply gains `hunt = { … }` exactly as
  `ux.md` §11C, `found` dense.
- `Events:InvokeServer("huntClaim", i)` → `ux.md` §11G verbatim. `reason` is
  **exactly one of**: `too far away` · `already found today` ·
  `it's a new day -- look again`.
- `CityEvent("huntClues" | "huntFound" | "huntReveal" | "huntHide" | "huntReset")`
  per `ux.md` §11D-H. **Text only in `huntFound` — no coordinates.**
- Redemption: `City:InvokeServer("capsuleTicket")` returns `rollCapsule`'s own
  table plus `tickets` and `meter`, so `UI.playCapsule(res)` plays unchanged.

**The client never computes a clue tier.** The tier is derivable; the
*sentence* is not, and sending tier-3 text early hands a modded client the
answer.

## 3. Saved data

Added under `data.City`: `meter`, `tickets`, `meterDay`, `meterDayTickets`,
`huntDay`, `found` (**dense 3-array**), `streak`, `streakDay`. All back-filled
by `reconcile()`; a pre-phase-D save must build defaults without throwing.

`rollCapsule` is **not modified.** The paid path, `ClaimDaily` and the claw all
share it, and the worst case is a 104-coin duplicate refund. Both `loop.md` and
`monetization.md` reached this independently.

## 4. Work split

| File | Owner | Changes |
|---|---|---|
| `game/Config.lua` | `server-engineer` | §1: `Config.Meter`, `Config.Hunt`, the whitelist. |
| `game/SminskiServer.server.lua` | `server-engineer` | The meter hook in `pay()`, the `Hunt` block beside the director (sharing `streetLots`, the clue helpers and the 1 Hz reveal loop), D1's lot exclusion, D2's normalisation, §2's payloads, redemption, §5's dev hooks. |
| `game/CityEvents.lua` | `client-engineer` | The hunt section on the phone (`LayoutOrder` **50**), the prompt branch, the third-find moment, the `ticket` push handling, the five `hunt*` kinds. |
| `game/City.lua` | `client-engineer` | The capsule pill in the top-right band, and only that. |

No new files, so **no `ownership.json` change**. No new module, so
`_sr_sync.lua` is untouched.

**Assets: none.** `capsule` and `star` icons already exist.

## 5. Test hooks — mandatory, QA cannot wait a day or grind ten minutes

Inside the existing `if RunService:IsStudio()` guard:

1. `EventsDev:InvokeServer("meterAdd", n)` — add `n` units, returning the new
   `meter`/`tickets`. Must go through the **real** grant path, ceiling and caps
   included, not by writing the field.
2. `EventsDev:InvokeServer("huntSeed", dayKey)` — reseed today's three from an
   arbitrary day key, returning all three positions and tiers. This is how the
   six-position geometry check happens.
3. `EventsDev:InvokeServer("huntReset")` — force the day roll-over, so the
   reset broadcast and the mid-hunt roll-over are testable in seconds.
4. `EventsDev:InvokeServer("streakSet", n)` — set the streak, so day 7 is
   reachable without seven days.

A feature QA cannot trigger cannot be verified.

## 6. Acceptance

1. The meter credits from the whitelist only; `BizCollects`, `HomeNaps` and the
   claw credit **zero**.
2. The 187/min ceiling holds on **taxi and parcels** (1,870 ± 2% per 10 min on
   both a bare and a fully-passed account) and **sweeping moves up to 2.1×** —
   that is the PASS condition, not a failure.
3. AFK credits nothing: no position-static activity ticks the meter.
4. `DayCap = 12` and `MaxTickets = 4` both bind; the hunt's ticket is granted
   **even at both caps** (a once-a-day reward that silently vanishes is worse).
5. Three hunt positions are on the `+2.5` strip in front of a door, ≥ 12 studs
   from any live event, and **never on an excluded lot** (D1). Sample all three
   across at least two seeded days.
6. The same three positions for two different players on the same day; stable
   across a server restart.
7. `found` survives a rejoin at **1/3 and 2/3** — the player sees the real
   count, and **cannot re-claim**. The raw saved value is a JSON array.
8. Tier text is never sent before it is earned; a tier-3 `go` appears only at
   tier 3 and points at `lot.door`, not `pos`.
9. Day roll-over mid-hunt behaves per spec; `huntReset` lands.
10. The 7-day streak grants a second ticket, and the big line reads
    `SEVEN DAYS RUNNING!` — one line, never two.
11. A ticket redeems at Capsule Corner through `rollCapsule` unchanged, and
    `UI.playCapsule` plays.
12. Phases A and B are unregressed: FIND and COLLECT still announce, claim, pay
    and expire; the strip, tray and the new phone all behave as tested.
