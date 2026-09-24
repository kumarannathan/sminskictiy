# Earned cosmetics — game-loop design (the free-play half of the capsule package)

Written 2026-09-21 by `loop-designer`. Third spec on this feature family, after
`docs/specs/daily-capsule/loop.md` (the ticket meter) and
`docs/specs/daily-capsule/monetization.md` (the policy review). Read those two
first; this one assumes their arithmetic and does not repeat it.

**One-sentence summary.** Nothing in Sminski City may be obtainable *only* from
a random machine: every one of the 15 capsule characters and every one of the 26
claw-eligible outfits gets a named, deterministic, currency-free earn path built
from counters that already exist (`Jobs.Done[jobId]`, `Jobs.Elo`, claimed
challenges), the paths are tuned to be **slower than average luck but certain**,
and the whole thing is one `Config.Earn` table plus one ~40-line `checkEarn()`
called from six places that already run.

**Five things I found in the code that change the design.**

1. **Capsule characters are NOT purely cosmetic, and both prior specs say they
   are.** `Config.Passives` (`Config.lua:409-428`) gives every character a real
   Endless Run effect and it is fully wired (`SminskiRunner.client.lua:433`,
   `:575`, `:1305`, `:2000`, `:2050`, `:2065`). Golden's is `coin = 2` — every
   coin in a run worth double. `Tour.lua:42` is telling the truth; `loop.md`
   D-table row "15 characters, purely cosmetic" and `monetization.md`'s
   "no gameplay field" are both wrong. See D2 and OPEN QUESTION 1.
2. **`exclusive` is already enforced for skins**, not just outfits:
   `BuySkin` refuses an `exclusive` skin with `reason = "gift"`
   (`SminskiServer.server.lua:645`). So a grant-only skin needs no new code —
   which is exactly why I am **not** using the flag. See D7.
3. **The claw's outfit pool is 26 items, not 17.** `monetization.md` N3 says 17;
   I counted the live filter (`price > 0 and price <= 1000 and not exclusive`,
   `:1763`) against `Config.Outfits:106-143` and get **26**. Their
   state-dependent disclosure table is built on the wrong number.
4. **Dog Park ELO is client-farmable and must not gate a cosmetic.** Bots are
   simulated and reported by the host client (`Matchmaking.lua:302`, `:318`,
   `:371`), `rankedGame = m.ranked and #rows >= 2` counts bots (`:199`), and
   bot stats get only `sanitizeStats` — no elapsed-time plausibility cap like
   `award()` has. A solo ranked lobby is therefore a +16 Elo/match faucet for a
   modified client. **The "certain elo" the human asked for is job
   reputation** (`d.Jobs.Elo`), which is server-computed behind a pace floor.
5. **There is exactly one ELO in the city, not one per job.** The brief says
   "per-job ELO"; `jobs(s)` keeps a single `j.Elo` across every job
   (`:1984-1995`, and `Config.lua:836-838` says so out loud). What *is* per-job
   is `j.Done[jobId]` and `j.Best[jobId]`. That is the difference between "you
   are a reliable worker" and "you are a cleaner", and the design uses both.

---

## WHAT EXISTS ALREADY

Everything this feature needs is already in the save and already maintained.
The build is a table, a function and six call sites.

### The two random machines, and what they can give

| Fact | Where | What it means here |
|---|---|---|
| `rollCapsule` picks a rarity by weight, then **uniformly** inside that rarity's pool | `SminskiServer.server.lua:541-570` | Per-character odds are `weight / #pool`: Common **12.40%**, Rare **5.40%**, Epic **2.25%**, Secret **2.00%**. These are the numbers the earn paths have to be honest against. |
| Four doors onto `rollCapsule` | `OpenCapsule` `:537` (400 coins) · `ClaimDaily` day 5 `:596` (free) · claw `:1757` (8% of a 40-coin play) · phase D's specced ticket | The capsule's contents are the 15 `Config.Characters`. Nothing else. |
| The claw's **second** prize class is an outfit | `:1759-1769`, filter `price > 0 and price <= 1000 and not exclusive and not owned` | **26 outfits** qualify today (I enumerated them; N2). These are the other thing a random machine can hand out. |
| **Skins are in no random machine at all** | `Config.Skins:166-196`; no `rollCapsule` or claw reference | So no skin *needs* an earn path for the policy remedy. Five get one anyway, because the human asked for job identity. This separation is the whole of D1. |
| `BuySkin` already refuses `exclusive` skins | `:645` | The mechanism for "grant-only" exists. I recommend against using it (D7). |
| `Config.Characters` **do** carry gameplay effects via `Config.Passives` | `Config.lua:409-428`, applied `SminskiRunner.client.lua:433`+ | Golden = `coin = 2` in a run. This is the one place my "cosmetics only" constraint is not literally true, and I am not going to paper over it. |

### The counters the earn paths ride on — all of them already saved

| Counter | Where it is kept | Where it moves | Trustworthiness |
|---|---|---|---|
| `d.Jobs.Done[jobId]` | `jobs(s)`, `:1992` | room jobs `:2106`, world jobs `:2165` (only on a **whole** task after fractional `weight` banking, `:2153-2160`) | High. Requires being **clocked in** (`sh.job ~= jobId` returns early, `:2145`), and every underlying payout is position-checked and pace-floored. |
| `d.Jobs.Elo` | `:1988`, clamped 0–5000 | `:2112` room, `:2154` world (`× weight`), `-2` on abandon `:2047`, reset to 120 by `resetElo` `:2132` | High. `Config.JobEloDelta` breaks even at score 0.6 (`Config.lua:869-871`), and score is capped by the clock at `:2096`. A script that claims mediocre work **never rises**; a script that claims perfect work has to spend the same wall-clock a human does. |
| `d.Jobs.Tasks`, `.Streak`, `.Best[jobId]`, `.Earned` | `:1989-1993` | same sites | `Earned` is post-multiplier, so **never threshold on it** — a pass holder would reach any coin threshold 4.5× faster. |
| `d.City.spotted[skinId]` | created lazily in `saved(s)`, written `:2749-2751` | phase A sighting claims | Shipped and tested. Random input, so it may only carry a `bonus` rule (D6). |
| `Challenges.daily/.weekly[].claimed` | `refreshChallenges` `:103-119`, claimed at `:793` | `ClaimChallenge` `:786-798` | High. But **only 3 of 8 dailies and 2 of 5 weeklies are drawn per date** (`Config.ChallengeCounts:507`, `rollSet:89-102`), so a reward hung on *one specific challenge row* appears on ~37% of days. That is why the challenge path counts **claims**, not rows. |
| `d.Login.streak`, `d.Level`, `d.PeakElo`, `d.RankedWins` | `defaultData:33-78` | various | `PeakElo`/`RankedWins` are the farmable ones (finding 4). Unused here. |

### The grant machinery that already exists

| Piece | Where | Reused how |
|---|---|---|
| `ClaimDaily` grants an **outfit** and falls back to coins when owned | `:582-592` | The precedent for "the server hands you a cosmetic". I follow the grant half and deliberately **drop** the coin fallback (D9). |
| `reconcile(data)` back-fills any missing top-level key from `defaultData()` | `:132-136` | New save fields need **no migration**, exactly as phase D found. |
| `syncLook(player, s)` + `player:SetAttribute("Skin", …)` | `:309`, called from `BuySkin` `:652` | A granted skin becomes visible with one existing call. |
| `dress(player, s, jobId)` sets `JobUniform` from a hard-coded table | `:2013-2019`: `pizzeria=chefhat, taxi=shades, delivery=backpack, cleaner=beanie, farmhand=sunhat` | **The uniform table already exists and is already visible to everyone on the street.** Today you wear it only while clocked in. Rung 1 of every job ladder makes it yours to keep. Zero new art, zero new data. |
| `feed(text, kind)` server-wide announce | `:~290`, used at `:568`, `:653`, `:2121` | The social surface for a grant, free. |
| `DataChanged` RemoteEvent → client `setData(d)` | server `:689-691`, client `SminskiRunner.client.lua:1099-1105` | A generic "your data changed" push for the one grant site with no reply. **Caution:** its handler also runs `goHome()` when `state == "home"`. Safe here because every grant site is city- or shop-side, never the flat. |
| `publicData(s)` is returned by `Job`, `ClaimChallenge`, `Events` and every shop remote | `:324` | A grant made inside any of those needs **no push at all**. |
| CITY CLEANUP already credits the cleaner job | `:2685`, `def.credits = "cleaner"` (`Config.lua:1035`) | Attending a cleanup event advances the cleaner ladder if you are clocked in. A free cross-link between phase B and this feature — worth telling the player. |

**What does not exist:** telemetry, still. No `AnalyticsService`, no session logging
anywhere in `game/`. Every duration in this document is an estimate; §M names
the three I distrust most and the measurement that settles each.

---

## THE DESIGN

### D1. The coverage rule — the load-bearing decision

> **No cosmetic may be obtainable only from a random machine.**
>
> Every outcome of the capsule (15 characters) and of the claw's item branch
> (26 outfits) has at least one **deterministic, currency-free** path: a named
> threshold on a counter the player controls, granted automatically when the
> threshold is crossed, costing no coins and no Robux.
>
> **Skins are outside the rule**, because no random machine gives a skin. Five
> are made earnable anyway — that is the human's identity request, not the
> policy remedy, and the two must not be confused.
>
> **The rule is a release requirement, not a one-off audit.** A new character or
> a new ≤1,000-coin outfit is not shippable until its earn path exists. QA item
> 1 iterates both pools and fails the build if anything is uncovered.

**Why "deterministic and currency-free" and not "buyable with coins".**
`Config.CapsulesArePaid = false` was written on the reasoning that earned coins
make a thing unpaid. `monetization.md` P1 demolished that: three coin bundles
are live, so coins are "an in-game currency purchased with Robux" and spending
them is an *indirect purchase*. The remedy Roblox lists **first** is "offering an
unpaid, earnable path to acquiring the random item". A coin price is not that.
Seventy-five taxi fares is.

**Is full coverage of the characters honest, or is it 15 fig leaves?** It is
honest if and only if the earn times sit in a defensible band, and that is the
next section. It is a fig leaf if the rarest item takes 200 hours. Mine takes
about ten, and I will defend that number specifically in D5.

**What full coverage costs the capsule.** Almost nothing, and the arithmetic is
the reason to be comfortable. A capsule roll costs 400 coins = **2.14 minutes**
of paced work. Expected rolls to get one *specific* character are
`1 / (weight/#pool)`, so the capsule already delivers any named character in:

| | per-outcome odds | expected rolls | expected work | p90 work |
|---|---|---|---|---|
| a specific Common | 12.40% | 8.1 | **17 min** | 40 min |
| a specific Rare | 5.40% | 18.5 | **40 min** | 91 min |
| a specific Epic | 2.25% | 44.4 | **95 min** | 216 min |
| Golden | 2.00% | 50.0 | **107 min** | 244 min |

Every earn path below is **2–6× slower than the expected luck route**. Nobody
rational switches to the earn path for efficiency. What the earn path sells is
**certainty and provenance** — it cannot fail, and the thing you get says where
it came from. That is a different product from a capsule, and it is why both can
exist without one eating the other.

### D2. The loop in one line

> **Clock into a job → the job board shows the next rung and how far off it is →
> you work → the rung fires and the city is told → you are wearing the thing
> five seconds later, in public → the same panel already shows the next rung.**

For the challenge path: *claim a challenge → a counter you can see moves → every
fifth claim the shop rack hands you the cheapest thing you do not own → you come
back tomorrow because the counter is 3/5.*

### D3. One full cycle, second by second

A real first-hour slice. New account, no passes, starting at the Job Center.
`[D]` is `Jobs.Done.delivery`; `[E]` is `Jobs.Elo` (starts at 120).

```
0:00   job board: DELIVERY DRIVER. The row reads
       "0 done  ·  next: TINY BACKPACK at 20"                    [D 0]  [E 120]
0:12   clock in. The uniform goes on (this already happens today) — but now the
       card under it reads "KEEP IT: 20 parcels"
0:55   parcel 1                                                  [D 1]  [E 125]
       the ladder chip on the HUD ticks 1/20
...
13:40  parcel 20                                                 [D 20] [E 216]
13:40  TOAST: "EARNED — TINY BACKPACK. Yours to keep."
       feed: "Ari earned the Tiny Backpack as a Courier"
       the outfit does NOT auto-equip; the toast has a WEAR button (D10)
13:41  the board row now reads "20 done  ·  next: SKY at 75"
...
19:00  [E 250] TOAST: "RELIABLE — WORK TIE earned"
...
50:20  parcel 75                                                 [D 75] [E 495]
50:20  TOAST: "EARNED — SKY.  A new Sminski for your shelf."
       feed: "Ari earned Sky (Common) — 75 parcels delivered"
       -- the capsule animation does NOT play. A grant is not a roll and must
       -- never be dressed as one (D9).
57:00  [E 500] TOAST: "EXPERIENCED — COSY HOODIE earned"
       the hoodie is keepBody, so it is dyed by whichever capsule character you
       have equipped. The first earned skin shows off the capsule collection.
```

Two things to notice, because they are the design:

1. **The first grant lands at ~13 minutes.** Deliberately just above phase D's
   10-minute capsule-ticket floor, so a session never produces a cosmetic in the
   first ten minutes from *any* source. A 3-minute session gets the ladder shown
   to it and nothing handed to it.
2. **Every grant is worn in public and announced once.** That is the entire
   social surface this feature has, and I am not going to claim it is more than
   that. See D12.

### D4. Which archetype

**None of the five, and it is not an event.** FIND / COLLECT / RUSH / RACE /
ROUND (`LOOPS.md` §2) all describe *a thing the director starts and finishes*.
This has no start, no clock, no spot, no `minPlayers` and no `lasts`. It is not a
sixth archetype either — a sixth archetype would need a director, a lifecycle and
a client module, and this needs none.

**It is a projection of counters that already exist onto a table of thresholds.**
The correct shape is the one `Config.Meter` took in phase D: a `Config.Earn`
table of data rows and one function. Concretely:

- `Config.Earn` — an **append-only** list of rules (N1).
- `checkEarn(player, s, opts)` — ~40 lines, file-scope local next to
  `rollCapsule` so it can see `s.data`. Iterates rules not already in
  `d.Earned`, evaluates `need`, grants, records, saves, notifies.
- Six call sites, all of which already run and already return `publicData(s)`:

| Call site | Where | Why there |
|---|---|---|
| `ClaimChallenge`, after `ch.claimed = true` | `:793` | the challenge path |
| `Job` action `task`, after the Elo line | `:2112` | room jobs (pizzeria) |
| `creditWorld`, after `jj.Done[jobId] += 1` | `:2165` | world jobs — **inside the whole-task branch only**, never in the fractional early-return at `:2156-2159` |
| `Job` action `quit` | `:2050` | catches an Elo threshold crossed by the abandon penalty's neighbours; cheap |
| the sighting claim, after `c.spotted` is written | `:2752` | the one `bonus` rule |
| once per join, after `reconcile` | the join path | the retro back-fill (D11) |

No new remote. No new client module. No new Blender asset. Phase A shipped with
no new art; so does this.

### D5. The earn paths, with the actual numbers

Three paths, exactly the three the human named. Every threshold is stated in
**target minutes first**, then converted, so an engineer can retune the whole
table from one measured number per job.

> `threshold = targetMinutes × DonePerMin`

`DonePerMin` is **estimated, not measured** (QA item 3). The two I trust least are
cleaner and farmhand, because `creditWorld` divides by `Config.Jobs.weight`
(`:2148`, `:2153`): a cleaner Done is 8.3 litter pickups (`weight = 0.12`) and a
farmhand Done is 4 harvests (`weight = 0.25`), while a parcel or a fare is 1:1.

| job | `weight` | est. Done/min | basis |
|---|---|---|---|
| delivery | 1 | **1.5** | `loop.md` D1's timeline shows parcels at 45–50 s including the depot return |
| taxi | 1 | **1.5** | fares are picked >350 studs out (`:1653`); same order as parcels |
| pizzeria | (room) | **1.3** | `par = 40 s` and `gap < par/2` is refused (`:2094`) |
| cleaner | 0.12 | **3.0** | 90–120 base coins/min ÷ 4 per piece ÷ 8.3 pieces per Done. **Least certain number in this document.** |
| farmhand | 0.25 | **4.0** | ripen-capped: 12 plots ÷ 45 s = 16 harvests/min ÷ 4 per Done |

#### Path 1 — WORKING CERTAIN JOBS (`Jobs.Done[jobId]`)

Three rungs per job. Rung 1 is the identity reward the human described; rung 2 is
the job's colour; rung 3 is the career.

| job | R1 ≈12 min | R2 ≈50 min | R3 ≈120 min |
|---|---|---|---|
| **delivery** | 20 → `backpack` outfit *(Tiny Backpack, 1000c)* | 75 → **Sky** (Common) | 180 → **Peach** (Rare) |
| **taxi** | 20 → `shades` outfit *(Cool Shades, 400c)* | 75 → **Lemon** (Common) | 180 → **Aqua** (Rare) |
| **pizzeria** | 15 → `chefhat` outfit *(Chef Hat, 600c)* | 60 → **Blush** (Common) | 150 → **Sakura** (Rare) |
| **cleaner** | 35 → `beanie` outfit *(Mint Beanie, 550c)* | 150 → `sprout` outfit *(Sprout, 300c)* | 360 → **Mint** (Rare) |
| **farmhand** | 50 → `sunhat` outfit *(Sun Hat, 700c)* | 200 → **Cocoa** (Common) | 480 → **Lavender** (Rare) |

Plus two **speciality skins**, deeper than rung 3 and marked `bonus`:

| rule | need | grants | ≈ |
|---|---|---|---|
| Head Chef | `Done.pizzeria ≥ 300` **and** `Elo ≥ 1000` | `chef` skin *(Head Chef, 900c)* | 230 min |
| Beekeeper | `Done.farmhand ≥ 1200` | `bee` skin *(Bumble Suit, 1100c)* | 300 min |

Three deliberate properties:

- **Rung 1 is the five uniforms that already exist** in `UNIFORM` (`:2013`). You
  already wear one on shift; the rung makes it yours off shift. It is the
  cheapest, warmest reward in the whole system and it costs nothing to build.
- **`Done` only moves while clocked in** (`:2145`). A player sweeping litter
  without taking the job gets coins and no ladder. That is correct — the ladder
  is about *being* a cleaner — and it is a discoverability trap, so it is item 1
  in D13.
- **Cleaner's rung is partly fed by CITY CLEANUP events** (`:2685`): 48 items ×
  0.12 = 5.76 Done per event for a clocked-in cleaner. Two events ≈ 11.5 Done.
  Not an exploit (director-scheduled, distance-checked), and a good reason to go.

#### Path 2 — REPUTATION (`Jobs.Elo`, one number across all jobs)

From `Config.JobEloStart = 120`, at an honest +5/task and ~45 s/task:

| need | grants | tasks | ≈ | note |
|---|---|---|---|---|
| Elo **250** (RELIABLE) | `tie` outfit *(Work Tie, 350c)* | 26 | 19 min | the first "you're good at this" |
| Elo **500** (EXPERIENCED) | `hoodie` **skin** *(400c)* | 76 | 57 min | `keepBody` — dyed by your capsule character |
| Elo **1000** (EXPERT) | `tracksuit` **skin** *(600c)* | 176 | 2.2 h | `keepBody` too |
| Elo **1500** | **Ghost** (Epic) | 276 | 3.5 h | |
| Elo **2500** | **Ember** (Epic) | 476 | 6.0 h | the deepest grind rule |

`Config.JobRanks` stops at EXPERT = 1000 (`Config.lua:846-849`) but the clamp is
5000 (`:2112`), so 1500 and 2500 are reachable and currently mean nothing. They
mean something now.

**World jobs barely move reputation** — `creditWorld` scales the delta by
`weight` (`:2154`), so a litter pickup is worth +0.84 at best and a harvest
+1.75. Reputation is earned in the pizzeria, the taxi and the depot. Say so on
the board or players will grind the wrong thing.

**`resetElo` (`:2128-2135`, 1,000 coins) does not claw anything back.** Grants are
permanent; a reset only costs you future thresholds. Nobody can buy a cosmetic
by resetting, and nobody loses one by resetting. It needs no code — the ledger
is the latch.

#### Path 3 — CHALLENGES (two new integers)

The challenge tables already exist but **a specific row is only drawn on ~37% of
days** (3 of 8 dailies, `rollSet:89-102`). So the path counts claims, not rows:

| need | grants | ≈ |
|---|---|---|
| `ChalDone` ≥ 5, 10, 15, … (**repeats every 5**) | the **cheapest claw-eligible outfit you do not own** | one grant per ~1.5 days |
| `ChalDays` ≥ **7** | **Night** (Epic) | 7 days |
| `ChalDays` ≥ **21** | **Galaxy** (Epic) | 21 days |

- `ChalDone` = lifetime claimed challenges, daily and weekly.
- `ChalDays` = days on which **every** drawn daily was claimed (all 3).
- The repeating rule is the coverage engine for outfits: deterministic (cheapest
  unowned, ties broken by `Config.Outfits` order, which is append-only), and it
  **auto-covers any outfit added later** that falls in the claw's price band.
  After the 6 outfits named above, 20 remain; a committed player claims ~23
  challenges a week, so the rack empties in about **30 days**.
- Two Epics on a **calendar** axis that money and a long session cannot rush is
  deliberate. Path 1 and 2 reward staying; path 3 rewards returning. The remedy
  should not depend on one play style.

#### The capstone — Golden

| need | grants |
|---|---|
| every **non-`bonus`** rule in `Config.Earn` has fired | **Golden** (Secret, 2%) |

Binding constraints: the five job ladders (≈10 h combined), Elo 2500 (≈6 h, which
accrues *during* the ladders and is therefore not binding), and `ChalDays ≥ 21`.

> **Golden by playing: about 10 hours of city work, spread over at least 21
> calendar days. Golden by rolling: 107 minutes of work expected, 244 at the
> unlucky tail.**

**The defence of the top end, since this is where the design either works or is a
fig leaf.**

- **5.6× the expected luck route, 2.4× the p90 tail.** That is the right side of
  both lines: too fast and the 2% means nothing; too slow and it is decoration.
  A player who wants Golden *soon* still buys capsules. A player who wants it
  *certainly* works for it. Both are real choices at these numbers.
- **It is 100% completion, not a pity timer.** The rule counts **rules fired**,
  never **items owned**. A paid roll can never advance it. That matters for
  more than taste: a guarantee that advanced on ownership would be a **pity
  system**, which Roblox names explicitly as a Paid Random Item mechanic
  requiring disclosure (`monetization.md` Q5). Counting rules keeps the paid
  and free sides completely disjoint, and keeps the existing odds card correct.
- **No rule with a random input may count toward it** (invariant, D6). The
  deterministic remedy must not be gated on a die roll.
- **It cannot be reached in one weekend** — `ChalDays ≥ 21` is a floor no amount
  of play removes. Golden stays the rarest thing in the game.

### D6. The rarity mapping, stated as one rule

> **Earn time ≈ 2–3× the expected work-minutes of rolling for that specific
> outcome. Never below 1×. The capstone is allowed to be 5×.**

| rarity | per-outcome odds | roll = | target | what the table actually delivers |
|---|---|---|---|---|
| Common (4 earnable; Glow is default) | 12.40% | 17 min | 35–50 min | **40–50 min** (job rung 2) ✓ |
| Rare (5) | 5.40% | 40 min | 80–120 min | **115–120 min** (job rung 3) ✓ |
| Epic (4) | 2.25% | 95 min | 190–290 min | **3.5 h / 6 h** (Elo) · **7 d / 21 d** (calendar) ✓ |
| Secret (1) | 2.00% | 107 min | 215–320 min | **~10 h and ≥21 days** (capstone, deliberately 5×) |
| claw outfits (26) | 8% ÷ pool | — | ~1 per 1.5 days | shop price 250–1,000c already exists as a parallel route |

**Two invariants that keep this honest as the game grows.**

1. **No rule whose input is random may be required for the capstone.** Random
   inputs may only carry `bonus = true` rules. Today there is exactly one
   (`spotted`, D7), and it is a fig leaf for a reason: meeting all 14 sighting
   skins is a coupon-collector problem dominated by a 0.5% legendary tier — I
   estimate **70–100 hours**. It grants a skin nobody needs and gates nothing.
2. **`bonus = true` means "not part of 100%"**, and it is set for exactly two
   reasons: the rule grants something no random machine can give (the five
   skins), or the rule has a random input (the sighting rule).

### D7. The five earnable skins, and what that does to the shop

**Recommendation: three overlapping sets, not three distinct ones.** Concretely:

| set | rule |
|---|---|
| **shop skins** | all 15, prices and `level` gates unchanged |
| **capsule/claw contents** | 15 characters + 26 outfits — unchanged, and now fully covered |
| **earned skins** | a named subset of **5**, which stay in the shop at the same price |

The five: `hoodie` (400c), `tracksuit` (600c), `chef` (900c), `bee` (1100c),
`ghost` (1300c, `bonus`, via `spotted ≥ 8`).

**Why this costs the shop nothing measurable, with the number.** At 187 base
coins/min every earnable skin is trivially cheap to *buy* and expensive to
*earn*:

| skin | shop price | = minutes of work | earn path | ratio |
|---|---|---|---|---|
| hoodie | 400 | **2.1 min** | Elo 500 ≈ 57 min | 27× |
| tracksuit | 600 | **3.2 min** | Elo 1000 ≈ 2.2 h | 41× |
| chef | 900 | **4.8 min** | 300 pizzas + EXPERT ≈ 3.8 h | 48× |
| bee | 1100 | **5.9 min** | 1200 farm Done ≈ 5 h | 51× |
| ghost | 1300 | **7.0 min** | 8 distinct sightings, unbounded | — |

Nobody grinds four hours to save five minutes. **The earn path and the coin price
are not substitutes; they are different products.** The coin price sells the
look. The earn path sells the story — you cannot buy having been a Head Chef.

**The ten skins that stay shop-only** are the expensive ones with no job
attached: ninja 1200, diver 1400, pirate 1500, dino 1600, robot 1800,
wizard 2000, knight 2200, astronaut 2500, **golden 12,000**, and `none`. Solid
Gold is the shop's largest cosmetic sink (64 minutes of work) and it should stay
exactly where it is.

**Do NOT set `exclusive` on any earnable skin.** `BuySkin:645` would then refuse
it with `reason = "gift"`, which deletes a live coin sink and converts an
overlapping set into a distinct one for no benefit. The `exclusive` field stays
where it is (the two login-gift outfits, `Config.lua:128-129`).

**Do not add a new `exclusive` skin either**, tempting as it is: a new skin is a
Blender build and a human review gate (`pipeline.md`), and this feature's whole
case is that it ships with no new art.

### D8. The duplicate and ownership interaction

A player earns Sky at 75 parcels, then rolls Sky from a capsule. `rollCapsule`
refunds 60 coins (`:560-562`). That is a coin faucet. How big?

**It is not a new maximum; it is an earlier arrival at an existing one.** The
refund ceiling has always been the complete-collection expectation,
`0.62×60 + 0.27×120 + 0.09×250 + 0.02×600 = 104.1` coins per roll. The earn
paths do not raise it by a single coin. They move a player up the curve sooner:

| collection state | E[refund]/roll | when the earn paths get you there |
|---|---|---|
| mid-life, no earn paths (`monetization.md` Q4) | 69.6 – 92.1 | most of an account's life |
| everything earned (14 of 15 by hour ~10, Golden at the capstone) | **104.1** | from ~10 h in |

**Delta: +12 to +35 coins per roll, for an account with ten hours in it.** At
phase D's 6–7 capsules/hour that is **+72 to +245 coins/hour**, against 11,220
base coins/hour of income — **0.6% to 2.2%**. Both prior specs set the "not worth
a mechanism" bar at 5.6%; this is well under it.

**I agree `rollCapsule` must not be touched, and I have a third reason.** The
first two stand (four callers, two currencies, the risk of editing shared code —
`loop.md` N4, `monetization.md` REQUEST 1). Mine: for a player who has *earned*
their collection, the refund is the only thing a roll still gives them. Zeroing
or halving it would make the earn path feel like it had taken something away —
the exact emotional failure that `loop.md` names when it rejects the 240-coin
restricted fallback. A generous refund is what lets a completionist keep opening
capsules for fun. **Leave `:558-565` exactly as it is.**

Two further no-ops worth stating so nobody "fixes" them:

- **An earn grant never calls `rollCapsule`**, so it never fires
  `bump(d, "capsules", 1)` (`:567`) and never touches the `wcaps` weekly
  challenge. The faucet `monetization.md` quantified at +51–79 coins/day is
  unchanged by this feature.
- **An earn grant never calls `pay()`**, so no pass multiplies it and it never
  credits phase D's capsule meter. A cosmetic grant is not income.

### D9. What a grant is, exactly

```
1. condition met  ->  2. record ruleId in d.Earned  ->  3. grant the item
                                                        (if already owned:
                                                         record only, no coins)
                  ->  4. task.spawn(save, player)
                  ->  5. one toast, one feed line, no animation
```

Six rules the builder must not get wrong:

1. **Record before granting**, and save after both. `d.Earned[ruleId] = true` is
   the idempotence latch; a double-fire must be impossible even if two call
   sites run in the same frame.
2. **No coin fallback when the item is already owned.** `ClaimDaily` pays
   `fallbackCoins` (`:584`) and that precedent is wrong for this feature: coins
   attached to a cosmetic threshold would turn every ladder into an income
   source, break `LOOPS.md` §6's cosmetic exemption (which applies *because*
   cosmetics do not touch the coin economy), and reward a player for having
   already been lucky. The rule fires, is recorded, counts toward the capstone,
   and grants nothing. The toast says "you already have it — that's 12/19".
3. **Never play the capsule animation.** `UI.playCapsule` (`UI.lua:1211`) is the
   paid machine's language. A grant that looks like a roll invites "so it *is*
   random?" — the one impression this whole feature exists to prevent.
4. **Never auto-equip.** `BuySkin` auto-equips (`:650`) because the player asked
   for it. A grant arrives unasked; silently replacing someone's knight armour
   with a chef's hat mid-shift is rude. The toast carries a WEAR button.
5. **One feed line per grant batch, the rarest item only.** The retro back-fill
   (D11) can fire fifteen rules at once; fifteen feed lines is spam.
6. **Copy may never quote odds or imply a rate-up.** "ALSO EARNED BY: 75 taxi
   fares" is fine. "Improve your chances" is not, and neither is any store item
   mentioning an earn path (`monetization.md` P4's bright line, which this
   feature must not cross from the other side).

### D10. Saved data — the exact shape

Four new top-level keys plus one field inside the existing `Challenges` table.
All back-filled by `reconcile()` (`:132-136`), so **no migration and no
`defaultData` version bump beyond adding the keys**.

```lua
-- in defaultData(), alongside OwnedSkins/OwnedOutfits
Earned    = {},   -- ruleId (STRING) -> true. The ledger. Append-only KEYS.
ChalDone  = 0,    -- lifetime claimed challenges, daily + weekly
ChalDays  = 0,    -- days on which every drawn daily was claimed
EarnPoolN = 0,    -- how many repeating-outfit grants have already fired

-- inside the existing Challenges table (refreshChallenges, :106-119)
c.dayDone = "2026-09-21"  -- UTC dayKey already credited to ChalDays
```

Rules the builder must not get wrong:

1. **`d.Earned` is keyed by rule id, a string, never by list index.** This is the
   project's append-only discipline (`HANDOFF.md` §1: *"append-only lists because
   saves store indices"*) applied correctly rather than worked around. A rule id
   is **never renamed and never reused**, because the capstone counts them.
2. **Everything the ledger records is derived from durable counters**, so a save
   lost between grant and write **self-heals**: the condition is still true, and
   the next `checkEarn` re-grants. A rejoining player can never appear to have
   lost a cosmetic, and that is by construction, not by luck.
3. **`OwnedSkins` / `OwnedOutfits` / `OwnedCharacters` are the ownership record
   and they do not change.** An earned item is indistinguishable from a bought
   one in the save; `d.Earned` only records *why*. That keeps `EquipSkin`
   (`:657-664`), `syncLook` and every UI ownership check untouched.
4. **`ChalDays` is latched by `c.dayDone`**, not counted: on each claim, if every
   drawn daily is claimed and `c.dayDone ~= dayKey`, set `c.dayDone = dayKey` and
   `ChalDays += 1`. `refreshChallenges` already owns the UTC day boundary
   (`:104`) and three other systems agree with it; do not invent a fourth.
5. **The repeating outfit rule is idempotent via `EarnPoolN`**:
   `while EarnPoolN < floor(ChalDone / 5) and an eligible unowned outfit exists`
   → grant the cheapest, `EarnPoolN += 1`. When the rack is empty, `EarnPoolN`
   **does not advance** — so a later-added outfit is granted immediately to a
   player who is already owed one. That is the self-maintaining half of the
   coverage rule.
6. **Size.** 28 boolean keys, three integers and a date string, once per account.
   Negligible against the existing `Receipts`, `MapBest` and `Challenges` tables.

### D11. Session shape

| | with this in the game |
|---|---|
| **3 minutes** | Nothing is granted, and that is deliberate — the first rung is ~13 minutes, just above phase D's 10-minute ticket floor, so no source hands out a cosmetic in the first ten minutes. What 3 minutes *does* get: the job board row reads "0 done · next: TINY BACKPACK at 20" with the item previewed, and three parcels move it to 3/20. **The weakest part of this design, and I will say so: a player who never clocks in never sees any of it.** The mitigation is D13 item 1, not a shorter ladder. |
| **15 minutes** | One uniform, worn, announced, and a visible next rung. The single best 15-minute payoff in the game right now, because the reward is permanent and public rather than a number going up. |
| **60 minutes** | Uniform + the job's colour character + RELIABLE's Work Tie + probably EXPERIENCED's hoodie. Four grants, one of which is a skin. Two ladders visibly started. |
| **the long arc** | ~10 hours and ≥21 days to the Golden capstone; ~30 days for the outfit rack to empty. That is the retention arc, and it is a genuinely different arc from phase D's (which is measured in rolls). |
| **the retro back-fill** | Every existing account fires everything it already qualifies for on its next join. A veteran with 400 parcels logs in to **"WELCOME BACK — 7 things were waiting for you"**, one summary card, no feed spam. I recommend this strongly: it is the launch moment, it costs one call site, and the alternative (grandfathering nothing) punishes exactly the players who already did the work. |

### D12. Social: 1, 5, 20 players, and an empty server

**I am not going to oversell this.** `LOOPS.md`'s core finding is that private
per-player state is the CCU problem, and a threshold ladder is per-player state.
This is a **retention** feature. It must not be built *instead of* phases B–F.

What it does have, honestly:

- **Empty server / 1 player.** Everything works. No `minPlayers`, no timer, no
  director dependency, nothing waits on a second person. A social mode that
  starts with nobody in it is a bug; this is not a social mode.
- **5 players.** The uniform is the payload. `dress()` already publishes
  `JobUniform` as a character attribute (`:2017`), so a permanent uniform means
  strangers on the street are legible: *that one's a cleaner, that one cooks*.
  The `feed()` line does the rest of the work — "Ari earned Sky — 75 parcels
  delivered" is the line that makes someone else ask how, which is the only
  discoverability mechanism that costs nothing.
- **20 players.** The uniforms become a visible census of what the server is
  doing, and a busy server makes the cleanup-event cross-link (`:2685`) worth
  attending because it feeds a ladder as well as paying.

**The honest limit, stated as a measurement rather than a hope:** if
"time near another player" (LOOPS.md §7) does not move for players who have
fired ≥1 rule versus players who have not, then the uniform-as-identity argument
is wrong and the social claim should be dropped from this feature's description
rather than defended.

### D13. Discoverability — what must be communicated

An earn path nobody knows about is not a remedy, and this is the part most
likely to be under-built. The UX lane owns the surfaces; these five facts must
reach the player, in this priority order.

1. **"Clock in or it doesn't count."** The highest-value sentence in the feature.
   `Done` only moves while clocked in (`:2145`), so a player sweeping litter for
   twenty minutes off-shift earns nothing toward the ladder. This belongs on the
   litter prompt and on the job board, in those words.
2. **The next rung, on the job board row that already exists.** `CityJobs.lua:296`
   already renders `"41 done · best 92%"` into `r.done`. Extend that string:
   `"41 done · next: SKY at 75"`. One string, one existing label, no new UI.
3. **"ALSO EARNED BY" on every locked capsule character.** The collection card
   already draws a per-character panel with its passive
   (`UI.lua:1302`, `:1323`). A locked character gets one extra line with the
   rule's `how` text and live progress: `ALSO EARNED BY: 75 taxi fares (41/75)`.
   **This is the line that satisfies the policy remedy in the player's hands** —
   it is the sentence that says the capsule is not the only way — and it should
   sit next to the odds card that `monetization.md` N2 is extending, not
   somewhere else in the menu.
4. **"or earn it" on the five earnable skin cards.** `UI.lua:963-969` already
   branches on level/price for the button; the sub-line reads
   `or earn it: EXPERT reputation`.
5. **One panel where the whole thing is legible.** Cheapest home is a tab in the
   PHONE modal that phase A already built (`CityEvents.lua:1395-1462`), listing
   every rule, its `how` string, its progress and its item, with the capstone at
   the bottom as `19/19`. Not required for v1; required before anyone claims the
   remedy is discoverable.

**Copy rules:** never quote odds on an earn surface; never write "chance",
"luck" or "boost"; never let a store item mention an earn path (the mirror of
`monetization.md` P4).

### D14. Where it sits in the city

**Nowhere new.** No geography, no props, no art, no place. The job board, the
shop's SKINS and CAPSULES tabs, the PHONE modal, and the toast stack — all built,
all tested. This stays comfortably inside the downtown vertical slice because it
adds no world at all.

### M. Measure it

Three numbers decide whether this worked. None of them can be collected today;
there is no telemetry in `game/` (verified again for this spec).

1. **First-rung funnel.** Share of new players who fire ≥1 rule in their first
   session, and the median minutes to it.
   **Target: ≥60% within 20 minutes. Stop and rethink below 25%** — that means
   players are not clocking in, which is a job-board problem this feature cannot
   fix by shortening ladders.
2. **Wear rate.** Share of granted items equipped within 24 hours of the grant.
   **Target ≥50%.** If earned cosmetics are granted and never worn, the identity
   reward is not landing and the answer is better presentation, not longer
   ladders. This is the number I would most want and least expect to get.
3. **Shop displacement.** Coins spent on skins and outfits per player-hour,
   before and after. **I predict <3%. Stop and rethink above 20%.**

Secondary, correlational only (say so when reporting it): D1/D7 return rate for
players who fired ≥1 rule versus those who did not.

**The number I distrust most in this whole document** is `DonePerMin` for cleaner
and farmhand, because both are divided by `Config.Jobs.weight` and neither has
ever been measured. If cleaner is really 3 Done/min, 35 is a 12-minute rung; if
it is 1, it is a 35-minute rung and the entry job has the slowest first reward in
the game. QA item 3 settles it and five thresholds move.

---

## NUMBERS

### N1. `Config.Earn` — new table, appended after `Config.Meter` / `Config.Hunt`

```lua
-- EARNED COSMETICS. Every outcome of a random machine also has a deterministic,
-- currency-free path. THIS LIST IS APPEND-ONLY AND IDS ARE NEVER RENAMED OR
-- REUSED: saves record rule ids, and the capstone counts them.
--
-- need  = { stat, key, n }  or a LIST of those, ANDed.
-- gives = { kind = "character"|"skin"|"outfit"|"outfitPool", id = ... }
-- bonus = true  ->  not counted toward the capstone. Set for exactly two
--                   reasons: (a) it grants something no random machine can give,
--                   (b) its input is random. Nothing else.
Config.Earn = {
  -- PATH 1: WORKING CERTAIN JOBS ------------------------------------------
  { id="dlv1", need={stat="jobDone",key="delivery",n=20 },  gives={kind="outfit",   id="backpack"},  how="Deliver 20 parcels" },
  { id="dlv2", need={stat="jobDone",key="delivery",n=75 },  gives={kind="character",id="Sky"},       how="Deliver 75 parcels" },
  { id="dlv3", need={stat="jobDone",key="delivery",n=180},  gives={kind="character",id="Peach"},     how="Deliver 180 parcels" },
  { id="tax1", need={stat="jobDone",key="taxi",    n=20 },  gives={kind="outfit",   id="shades"},    how="Complete 20 fares" },
  { id="tax2", need={stat="jobDone",key="taxi",    n=75 },  gives={kind="character",id="Lemon"},     how="Complete 75 fares" },
  { id="tax3", need={stat="jobDone",key="taxi",    n=180},  gives={kind="character",id="Aqua"},      how="Complete 180 fares" },
  { id="piz1", need={stat="jobDone",key="pizzeria",n=15 },  gives={kind="outfit",   id="chefhat"},   how="Serve 15 orders" },
  { id="piz2", need={stat="jobDone",key="pizzeria",n=60 },  gives={kind="character",id="Blush"},     how="Serve 60 orders" },
  { id="piz3", need={stat="jobDone",key="pizzeria",n=150},  gives={kind="character",id="Sakura"},    how="Serve 150 orders" },
  { id="cln1", need={stat="jobDone",key="cleaner", n=35 },  gives={kind="outfit",   id="beanie"},    how="Clear 35 streets' worth of litter" },
  { id="cln2", need={stat="jobDone",key="cleaner", n=150},  gives={kind="outfit",   id="sprout"},    how="Clear 150" },
  { id="cln3", need={stat="jobDone",key="cleaner", n=360},  gives={kind="character",id="Mint"},      how="Clear 360" },
  { id="frm1", need={stat="jobDone",key="farmhand",n=50 },  gives={kind="outfit",   id="sunhat"},    how="Bring in 50 loads" },
  { id="frm2", need={stat="jobDone",key="farmhand",n=200},  gives={kind="character",id="Cocoa"},     how="Bring in 200 loads" },
  { id="frm3", need={stat="jobDone",key="farmhand",n=480},  gives={kind="character",id="Lavender"},  how="Bring in 480 loads" },
  -- speciality skins (bonus: no random machine gives a skin)
  { id="chef",  bonus=true, need={{stat="jobDone",key="pizzeria",n=300},{stat="jobElo",n=1000}},
                            gives={kind="skin", id="chef"},  how="300 orders as an EXPERT cook" },
  { id="bee",   bonus=true, need={stat="jobDone",key="farmhand",n=1200},
                            gives={kind="skin", id="bee"},   how="1,200 loads brought in" },
  -- PATH 2: REPUTATION -----------------------------------------------------
  { id="elo250",  need={stat="jobElo",n=250 },  gives={kind="outfit",   id="tie"},       how="Reach RELIABLE reputation" },
  { id="elo500",  bonus=true, need={stat="jobElo",n=500 },  gives={kind="skin", id="hoodie"},    how="Reach EXPERIENCED reputation" },
  { id="elo1000", bonus=true, need={stat="jobElo",n=1000},  gives={kind="skin", id="tracksuit"}, how="Reach EXPERT reputation" },
  { id="elo1500", need={stat="jobElo",n=1500},  gives={kind="character",id="Ghost"},     how="Reach 1,500 reputation" },
  { id="elo2500", need={stat="jobElo",n=2500},  gives={kind="character",id="Ember"},     how="Reach 2,500 reputation" },
  -- PATH 3: CHALLENGES -----------------------------------------------------
  { id="pool",  every=5, need={stat="chalDone"}, gives={kind="outfitPool"},
                how="Every 5 challenges: an outfit from the rack" },
  { id="days7",  need={stat="chalDays",n=7 },  gives={kind="character",id="Night"},      how="Clear every daily on 7 days" },
  { id="days21", need={stat="chalDays",n=21},  gives={kind="character",id="Galaxy"},     how="Clear every daily on 21 days" },
  -- BONUS: the sighting collection (random input -> bonus, never the capstone)
  { id="spot8", bonus=true, need={stat="spotted",n=8}, gives={kind="skin", id="ghost"},
                how="Meet 8 different rare Sminskis in the street" },
  -- THE CAPSTONE -----------------------------------------------------------
  { id="all",   need={stat="rulesLeft",n=0}, gives={kind="character",id="Secret"},
                how="Complete every other career and challenge goal" },
}
```

**`stat` resolvers — five, all reading data that already exists:**

| `stat` | reads | note |
|---|---|---|
| `jobDone` | `d.Jobs.Done[key] or 0` | `:1992`, `:2106`, `:2165` |
| `jobElo` | `d.Jobs.Elo` | `:1988`; survives `resetElo` via the ledger |
| `chalDone` | `d.ChalDone` | new integer |
| `chalDays` | `d.ChalDays` | new integer |
| `spotted` | count of keys in `d.City.spotted` | `:2749`; `bonus` rules only |
| `rulesLeft` | count of non-`bonus`, non-`every` rules other than this one absent from `d.Earned` | recomputed each check; appending a rule automatically extends the capstone, and a player who already holds Golden keeps it |

### N2. The 26 claw-eligible outfits, enumerated

The live filter is `price > 0 and price <= 1000 and not exclusive` (`:1763`).
Against `Config.Outfits:106-143` that is **26 items, not the 17 quoted in
`monetization.md` N3**:

> bow 250 · headband 250 · sprout 300 · nightcap 350 · tie 350 · shades 400 ·
> cherries 400 · starclips 420 · scarf 450 · party 450 · heartspecs 480 ·
> towel 500 · bearears 520 · beanie 550 · lollipop 560 · chefhat 600 ·
> strawberry 650 · catears 700 · sunhat 700 · bunny 750 · flowers 800 ·
> flowers/duckfloat 850 · santa 900 · bee 900 · frog 950 · backpack 1000

Covered by a named rule: **6** (backpack, shades, chefhat, beanie, sunhat,
sprout, tie — the five uniforms plus two). The remaining **20** are covered by
the repeating `pool` rule at one per 5 claimed challenges ≈ **30 days**.

Sticker value handed out: 20 × ~600 ≈ 12,000 coins over 30 days = **400 coins a
day = 2.1 minutes of work a day**. Inside `LOOPS.md` §6's cosmetic exemption, and
every one of them is separately buyable for coins today.

### N3. Time-to-earn, every rule

Using the `DonePerMin` estimates in D5 and +5 Elo per ~45 s task.

| rule | ≈ time | vs. rolling for it |
|---|---|---|
| dlv1 / tax1 | 13 min | — (outfit, 1000c / 400c in shop) |
| piz1 | 12 min | — |
| cln1 | 12 min | — |
| frm1 | 13 min | — |
| elo250 | 19 min | — |
| **dlv2 (Sky), tax2 (Lemon)** | **50 min** | 2.9× the 17-min expected roll |
| **piz2 (Blush)** | **46 min** | 2.7× |
| **frm2 (Cocoa)** | **50 min** | 2.9× |
| elo500 (hoodie skin) | 57 min | — |
| cln2 | 50 min | — |
| **piz3 (Sakura)** | **115 min** | 2.9× the 40-min expected roll |
| **dlv3 (Peach), tax3 (Aqua)** | **120 min** | 3.0× |
| **cln3 (Mint), frm3 (Lavender)** | **120 min** | 3.0× |
| elo1000 (tracksuit skin) | 2.2 h | — |
| **elo1500 (Ghost)** | **3.5 h** | 2.2× the 95-min expected roll |
| **elo2500 (Ember)** | **6.0 h** | 3.8× |
| **days7 (Night)** | **7 days** | a different axis; cannot be rushed |
| **days21 (Galaxy)** | **21 days** | same |
| chef skin | 3.8 h | — |
| bee skin | 5.0 h | — |
| spot8 (ghost skin) | unbounded, `bonus` | — |
| **all (Golden)** | **≈10 h over ≥21 days** | 5.6× the 107-min expected roll, 2.4× its p90 |

**The fastest possible player** cannot compress this much: `Done` is gated by
pace floors and by the farm's 45-second ripen clock, Elo is gated by
`gap < par*0.5` (`:2094`), and `ChalDays` is gated by the calendar. QUICK FEET
and DREAM GARAGE shorten sweeping and driving in the same ≤2.1× band
`monetization.md` N4 measured — so a R$498 account reaches the job rungs up to
about twice as fast on the *slowest* ladders and not at all faster on the
calendar ones. That is the same trade the human already accepted for the capsule
meter, and it buys a cosmetic, not power.

### N4. What this mints — the whole economy exposure

| source | coins/hour | % of the 11,220 base coins/hour |
|---|---|---|
| grants themselves | **0** | 0% — no grant calls `pay()` or adds coins, ever |
| extra duplicate refunds from earning faster (D8) | +72 to +245 | **0.6% – 2.2%**, and only for accounts ~10 h in |
| `wcaps` weekly challenge | **0 change** | grants never call `rollCapsule` |
| sink displacement (a skin earned is a skin not bought) | ≤1,100 coins once, per earnable skin | my prediction: <3% of cosmetic spend (M.3) |

This is the smallest economic footprint of any feature in the current plan.

---

## EDGE CASES

**Empty server.** Everything works. No rule has a `minPlayers`, no rule depends
on the director, no timer starts on first join.

**One player.** Identical. The only thing a second player adds is the feed line
being seen.

**A scripted player.** Three defences, in order of strength:

1. **The counters are already the hardened ones.** `Done` requires a clock-in
   plus the underlying payout's position check and pace floor; `Elo` breaks even
   at score 0.6 and score is capped by elapsed time (`:2096`). A script that
   claims *mediocre* work forever sits at Elo 120 and never passes `elo250`. A
   script that claims *perfect* work must wait `par * 0.85` per task — the same
   wall clock a human spends. **This feature adds no new trust surface at all.**
2. **The reward is a cosmetic with no resale path**: no trading, no marketplace,
   no real-money trading. Botting the ladders produces a hat.
3. **The one counter I will not use** is Dog Park ELO, because it *is* farmable
   (finding 4). Job reputation is not.

**An AFK player.** Zero. `Done` needs a completed, position-checked task;
`Elo` needs a scored task; `ChalDone` needs a claim. The two genuinely idle
income paths in the game (`BizCollects`, `HomeNaps`) touch none of them.

**A player who already owns the item when the rule fires.** The rule fires, is
recorded, counts toward the capstone, and grants nothing. **No coin fallback**
(D9.2). The toast says so.

**A player who resets reputation** (`resetElo`, 1,000 coins, `:2128`). Grants
already made are kept — the ledger is the latch, not the Elo number. Future Elo
rules must be re-earned. This cannot be abused: resetting only destroys
progress.

**A player mid-shift when a rule fires.** Nothing interrupts. No auto-equip
(D9.4), so a chef does not suddenly change clothes mid-order.

**Mid-event join / leave.** Nothing here is event-scoped. Progress is in the
save; a player can advance a ladder on one server and finish it on another.

**A save that fails between grant and write.** Self-healing: the ledger is
derived from durable counters, so the next `checkEarn` re-grants. The reverse —
a ledger entry saved without the item — is impossible if the grant order in
D9 is followed and both live in the same `s.data` write.

**A veteran's first join after launch.** Up to ~15 rules fire at once. One
summary card, **no feed lines**, one save (D11).

**A restricted player** (`ArePaidRandomItemsRestricted`). This feature *is* their
path. Nothing here checks `Config.CapsulesArePaid` or `s.capsulesRestricted`,
for the same reason phase D's ticket does not (`loop.md` N5): a threshold on
parcels delivered is not a paid random item under any reading. If
`CapsulesArePaid` is flipped to `true` and both coin doors close, a restricted
player can still reach **every character in the game, including Golden**, by
playing. That is the strongest single sentence available for the policy review
and it is only true because of the coverage rule in D1.

**A rule id typo or a renamed id.** Breaks the capstone count silently. Hence
D10.1 and QA item 2.

---

## REQUESTS FOR OTHER OWNERS

These are requests. I have written no code and edited no file but this one.

1. **For `monetization-designer` — three corrections, one of which is material.**
   - **`Config.Characters` are not purely cosmetic.** `Config.Passives`
     (`Config.lua:409-428`) is live and wired (`SminskiRunner.client.lua:433`,
     `:575-576`, `:1305`, `:1992-2000`, `:2050`, `:2057`, `:2065`). Golden grants
     `coin = 2` in Endless Run. Your Q1 row "15 characters, purely cosmetic, no
     gameplay field — `Tour.lua:42` lies" is backwards: `Tour.lua` is right.
     This sharpens the paid-random-item question (a paid random generator that
     can yield an earning multiplier), and it weakens `LOOPS.md` §6's
     cosmetic-generosity exemption as applied to capsules. **Your call, your
     lane** — I have designed as if the exemption holds, because the earn paths
     make the passives *more* freely available, not less.
   - **The claw outfit pool is 26, not 17** (N2). Your N3 state-dependent table
     ("once a player owns all 17 eligible outfits…") uses the wrong count, and
     the repeating `pool` rule above will empty that rack for committed players
     in ~30 days — which makes the empty-pool state a **common** case rather
     than an exotic one. The claw's disclosure has to handle it.
   - **This feature is Roblox's treatment option 1, made concrete for every
     outcome.** If you want a sentence for `STORE.md` §5, it is: *"every capsule
     character and every claw outfit is also earnable by playing, at a named
     threshold, for no currency."*

2. **For `server-engineer` — the build is a table, a function and six call
   sites** (D4). Two things to get right or it will be wrong in a way nobody
   notices for weeks: `checkEarn` in `creditWorld` must sit **inside** the
   whole-task branch after `:2165`, never in the fractional early-return at
   `:2156-2159`; and rule ids are append-only and never renamed (D10.1).
   **Do not touch `rollCapsule`** — D8 gives a third reason on top of the two
   already agreed.

3. **For `ux-designer` — D13 is the spec, in priority order.** The two surfaces
   that matter most are the *cheapest* ones: the job board's existing `r.done`
   string (`CityJobs.lua:296`) and an "ALSO EARNED BY" line on the locked
   character card (`UI.lua:1302`). The "ALSO EARNED BY" line should sit beside
   the odds card `monetization-designer` is extending, not elsewhere. Grants
   must never reuse `UI.playCapsule` and must never auto-equip (D9.3, D9.4).

4. **For whoever owns `Matchmaking.lua` — a real hole, not mine to fix.** Bot
   stats are relayed by the host client with only `sanitizeStats`
   (`:365-376`), bots count toward `rankedGame` (`:199`), and bot Elo is seeded
   to the lobby average (`:317`). A solo ranked lobby is therefore ~+16 Elo per
   match for a modified client, and `PeakElo` / `RankedWins` inherit that. **I
   have designed around it by using job reputation instead** — but it is a
   ranked-ladder integrity bug independently of this feature. The cheap fix that
   would unlock a Dog Park earn path later is a `RankedHumanWins` counter
   incremented only when the match had ≥2 non-bot finishers.

5. **A telemetry owner.** Third spec in a row asking. The three counters I need
   are in §M; without them, none of the durations in N3 can ever be checked and
   "does anyone wear the thing" is unanswerable.

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **Any Dog Park ELO / ranked-wins rule** | Farmable today (finding 4). Revisit after `RankedHumanWins` exists. |
| **A coin fallback when a granted item is already owned** | Turns every ladder into income, breaks §6's cosmetic exemption, rewards prior luck. `ClaimDaily`'s `fallbackCoins` precedent is the wrong one to copy here (D9.2). |
| **A CLAIM button** | Grants fire automatically. A claim UI is a second system, a second failure mode, and a reason for a player to have "lost" something. |
| **New `exclusive` skins, or marking earnable skins `exclusive`** | The first needs Blender and a review gate; the second deletes a live coin sink for nothing (D7). |
| **Earn paths for the 10 shop-only skins** | Not in any random machine, so not part of the remedy. Solid Gold at 12,000 coins is the shop's biggest cosmetic sink and stays there. |
| **Per-job reputation** | There is one Elo by design (`Config.lua:836-838`). Splitting it is a progression rewrite, not a threshold table. |
| **The `spotted` rule, if sightings measure below ~4/hour** | It is already `bonus` and gates nothing; if the sighting rate is low it is a rule nobody will ever fire, and a dead rule on a discoverability panel is worse than no rule. |
| **A shared/server-wide surface** (e.g. "3 Senior Couriers on this server") | Tempting, and it is the one thing that would make this social rather than private. But it needs a server aggregate and a new payload, and this feature's case is that it adds nothing. Revisit only if M.2 shows people actually wear the uniforms. |
| **Any rule keyed on `Jobs.Earned` or on coins** | Post-multiplier (`:2117`), so a pass holder crosses any coin threshold 4.5× faster. Never threshold on money. |

---

## QA SHOULD CHECK

Items 1–4 would change a decision. Every one is provable in Studio.

**Coverage — the policy half**

1. **Nothing is random-only.** Iterate `Config.Characters` (15) and every
   `Config.Outfits` entry matching the claw filter (`price > 0 and price <= 1000
   and not exclusive`, expected **26**). Each must be reachable by at least one
   `Config.Earn` rule — counting `outfitPool` as covering the whole eligible
   set. **This test must be run in CI or as a startup assert, not once by hand**;
   it is the release requirement in D1, and the failure mode is a new cosmetic
   shipping uncovered.
2. **Rule ids are unique, and `rulesLeft` is right.** Assert no duplicate id in
   `Config.Earn`; assert the capstone's `rulesLeft` counts exactly the
   non-`bonus`, non-`every` rules minus itself (expect **19** with the table in
   N1). Then append a dummy rule and confirm the capstone requirement rises to
   20 and an existing Golden holder keeps Golden.

**Does a path actually grant?**

3. **Measure `DonePerMin` for all five jobs** — 10 minutes of honest play each,
   clocked in, reporting `Jobs.Done[jobId]` before and after. **Every threshold
   in N1 is derived from these five numbers and none has ever been measured.**
   Report all five; cleaner and farmhand are the ones I expect to be wrong.
4. **Each of the 27 rules fires exactly once**, by setting the underlying counter
   one below and one at the threshold. Specifically confirm: `Done` set to 74 →
   no grant; 75 → `Sky` in `OwnedCharacters`, `Earned.dlv2 = true`, a toast, one
   feed line; call `checkEarn` five more times → **no second grant, no second
   feed line**.
5. **Grants come from the right side of `creditWorld`.** Clock in as a cleaner
   and pick up 8 pieces of litter (`weight = 0.12` → `frac` still < 1): `Done`
   must be unchanged and no rule may fire. The 9th completes a Done.
6. **Off-shift work earns nothing.** Sweep 40 pieces of litter **without**
   clocking in: coins increase, `Jobs.Done.cleaner` does not move, no grant.
   (This is correct behaviour and also the thing players will report as a bug —
   D13.1 exists because of it.)
7. **Elo rules survive a reset.** Reach Elo 500 (hoodie granted), then
   `resetElo`. `OwnedSkins.hoodie` must still be true and `Earned.elo500` must
   still be true. Re-reaching 500 must not grant twice or re-announce.
8. **Already-owned grants pay nothing.** Buy the Chef Hat for 600 coins, then
   cross `piz1`. Coins must be **unchanged to the coin**, `Earned.piz1 = true`,
   and the rule must count toward the capstone.
9. **The repeating pool rule is deterministic and terminates.** With
   `ChalDone = 25` and `EarnPoolN = 0`, run `checkEarn`: exactly 5 outfits
   granted, cheapest-first (bow 250, headband 250, sprout 300, nightcap 350,
   tie 350 — order within a price tie follows `Config.Outfits`), `EarnPoolN = 5`.
   Then own all 26 and set `ChalDone = 200`: **no grant, `EarnPoolN` does not
   advance**, no error, no infinite loop.
10. **The capstone.** Force every non-`bonus` rule into `d.Earned`; the next
    check grants **Golden** and nothing else. Confirm it does **not** fire when
    the player merely *owns* 14 characters from capsules with no rules fired —
    this is the anti-pity-system test and it is the one a reviewer will ask for.

**Prove it cannot be farmed**

11. **Bought coins grant nothing.** Buy any coin product; `Jobs.Done`,
    `Jobs.Elo`, `ChalDone`, `ChalDays` and `Earned` must all be **byte-identical**
    before and after. The mirror of `monetization.md`'s QA 1.
12. **No pass accelerates a threshold except through doing more work.** Same
    activity, same duration, clean account vs. VIP + 2x COINS + CITY PRO: coins
    differ by ~4.5×, `Jobs.Done` and `Jobs.Elo` must differ by **<2%**. Then
    repeat with QUICK FEET + DREAM GARAGE on **sweeping**, where a difference of
    up to +108% is **expected and correct** — name the activity, or this test
    fails for the right reason (the mistake `monetization.md` caught in
    `loop.md`'s QA 6).
13. **A mediocre script never passes RELIABLE.** Submit 200 pizzeria tasks at
    `score = 0.6` at the fastest legal pace (`gap = par*0.5 + 1`). `Jobs.Elo`
    must remain **120** (`JobEloDelta(0.6) = 0`) and `elo250` must not fire.
    Then repeat at `score = 1.0`: the clock cap at `:2096` must force
    `gap ≥ par*0.85 = 34 s` per task, so 26 tasks take ≥15 minutes of wall
    clock. Report the elapsed time — it is the anti-farm number.
14. **The rate limiter holds.** `checkEarn` runs on every `Job` task
    (`allow(s, "Job", 0.2)`, ~5/s). Hammer it for 60 s and confirm no extra
    DataStore writes beyond one per actual grant (the budget is ~60 + 10 per
    player per minute for the whole server, `:1516`).
15. **No grant calls `pay()` or `rollCapsule`.** Fire ten rules and confirm
    `data.City.meter` (phase D) is unchanged, `Coins` is unchanged, and the
    `capsules` challenge stat is unchanged.

**Presentation**

16. **No auto-equip.** Wear the Knight skin, then fire `elo500`. `EquippedSkin`
    must still be `knight`; the hoodie is owned and not worn.
17. **No capsule animation on a grant**, and the toast's WEAR button equips
    through the existing `EquipSkin` / `EquipOutfit` remotes.
18. **The retro back-fill is quiet.** An account with `Done.delivery = 400`,
    `Elo = 1200`, `ChalDone = 60` joining for the first time: all qualifying
    rules fire, **one** summary card, **zero** feed lines, **one** save.
19. **Progress strings are live.** Change a threshold in `Config.Earn` in Studio
    and confirm the job board row and the character card follow. A hard-coded
    "75" that drifts from `Config` is how a remedy becomes a lie.

---

## OPEN QUESTIONS FOR THE HUMAN

Taste and money only. Everything else above has arithmetic behind it.

1. **Capsule characters are not cosmetic, and you should know before you sign
   this off.** Every one carries a live Endless Run passive
   (`Config.Passives`, `Config.lua:409-428`, wired at
   `SminskiRunner.client.lua:433`+) — Golden's is *every coin worth double*. Two
   earlier specs told you the opposite. So these earn paths hand out a small
   run-economy advantage, not only a look. **My recommendation: ship it anyway,
   and treat that as the point.** Today the strongest passive in the game is
   reachable only through a random machine funded by purchasable coins; after
   this, it is reachable by working. That is strictly *less* pay-to-win than the
   status quo. The alternative — granting the look without the passive — does
   not exist in the code and would need a whole new ownership concept. **Your
   call: accept, or ask monetization to re-run its pay-to-win verdict first.**

2. **Golden at ~10 hours and ≥21 days — too slow, too fast, or right?** Rolling
   for it costs 107 minutes of work on average and 244 at the unlucky tail. Ten
   hours is 5.6× the average and 2.4× the tail: slower than luck, but certain,
   and it is the game's 100% badge. Push it to 20 hours and it becomes a trophy
   almost nobody sees; pull it to 4 and the 2% stops meaning anything. **I would
   defend 10.**

3. **Do you want the 21-day calendar gate at all?** Two Epics (Night, Galaxy)
   and the capstone cannot be rushed by playing longer or spending more — only
   by coming back on 21 separate days. That is the single best retention lever
   in this spec and also the one most likely to read as a chore. **My
   recommendation: keep exactly two calendar rules and no more**, so the path is
   a flavour rather than the system.

4. **The five earnable skins — is `chef` acceptable?** It is a 900-coin shop
   item, and the earn path (300 orders as an EXPERT cook, ~3.8 h) is 48× slower
   than buying it, so I do not think the shop loses anything real. But it is the
   first time a shop skin is given away, and that is a precedent you own. Also
   confirm: **`golden` (12,000 coins) stays shop-only**, which is my
   recommendation — it is the largest cosmetic sink in the game.

5. **The retro back-fill at launch.** Every existing account is handed
   everything it already qualifies for on its next join — a veteran could
   receive seven items at once. It is a great re-engagement moment and it is
   also the day you give away the most cosmetics you will ever give away in
   twenty-four hours. **My recommendation: do it**, with one quiet summary card.

6. **Auto-equip the very first uniform?** I have specified "never auto-equip",
   which is right for a skin. But the uniform is already on your body while you
   are clocked in, so the rung-1 grant changes nothing visible until you clock
   out. **Option: for rung 1 only, keep the uniform on after clock-out until the
   player changes it.** Warmer, slightly presumptuous. Your taste.

7. **What this feature is *for*.** It is a retention system, not a CCU system —
   its social surface is a worn uniform and one feed line, and that is all
   (D12). `LOOPS.md` §7 gates phases C–G on session length moving after A+B.
   **This should not be built instead of B–F.** If you want it built alongside
   them, say so; if you want it built first because the policy remedy is
   time-sensitive, say that instead, and I will note the trade rather than
   pretend there isn't one.
