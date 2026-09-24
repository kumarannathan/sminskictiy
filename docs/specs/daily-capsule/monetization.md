# Capsule ticket meter (phase D) — monetization & Roblox policy review

Written 2026-09-21 by `monetization-designer`, second on this feature, after
`docs/specs/daily-capsule/loop.md`. This is a **review lane**: I propose no new
passes and no new products, and I recommend none. I read the code, I checked the
loop designer's arithmetic, and I looked up current Roblox policy rather than
recalling it.

> ## ⚠ CORRECTED 2026-09-21 — READ THE ADDENDUM FIRST
>
> **This review's central premise was wrong.** I asserted that capsule
> characters are cosmetic. They are not: `Config.Passives` (`Config.lua:409-425`)
> gives all 15 a live Endless Run effect, and Golden's is `coin = 2` — every
> coin worth double, into the shared wallet. I verified it in code after the
> coordinator flagged it; I had taken it from a spec and approved it twice
> without checking.
>
> **Line 4 of the verdict below ("Not pay-to-win") is withdrawn.** The
> corrected verdict, a second violation the first pass missed (the all-time
> distance leaderboard is purchasable), and the re-run economics are in
> **ADDENDUM A** at the end of this file. Where the body of this review says
> "cosmetic", read the addendum instead. Everything in Q1, Q2 and the policy
> findings **still holds**; one factual error in N3 is corrected in A6.

**Verdict in five lines** *(line 4 superseded — see Addendum A)*.

1. **Commercially safe.** Free tickets do not measurably devalue COIN JAR,
   because capsules were *never* Robux-gated: 187 base coins/min ÷ 400 =
   **one capsule every 2.14 minutes, free, today**. The meter is 4.7× *slower*
   than the free route that already exists. Ship COIN JAR at R$99 unchanged.
2. **The loop designer's minted-coin reasoning is correct** (I re-derived 7.44
   and 104.1 exactly) but **7.4 is only true for a player's first ~10 rolls**.
   Mid-life expected refund is 70–92 coins. The conclusion holds; the
   reassuring number should not be quoted.
3. **One pre-existing policy defect, not caused by phase D, exposed by it.**
   `Config.CapsulesArePaid = false` (`Config.lua:59`) is **factually wrong**:
   three coin bundles are live with real product ids, so capsules *are*
   indirectly purchasable with Robux and *are* Paid Random Items under Roblox's
   own definition. Tier-level odds are disclosed; **per-outcome odds are not,
   and the claw machine has no disclosure at all.**
4. **Not pay-to-win, but the loop spec overstates pass-neutrality.** The
   multiplier passes and all three boosts are genuinely meter-neutral. **QUICK
   FEET + DREAM GARAGE shorten time-to-ticket by up to 2.1× on sub-ceiling
   activities** (sweeping 16–21 min → 10 min). They can never beat 10 minutes,
   and the fastest meter in the game costs 0 Robux. **QA item 6 as written will
   fail and must name the activity.**
5. **N5's restricted-player fallback is backwards.** A free earned roll is
   explicitly outside the policy; blocking it denies the exact remedy Roblox
   lists *first*, and paying 240 coins instead makes a restricted player's
   ticket stream **2.3× more inflationary** than everyone else's. Drop it.

---

## WHAT EXISTS ALREADY

Everything below I read; nothing is inferred from the loop spec. I re-checked
every citation in `loop.md`'s capsule table and **all of them are accurate**.

### The capsule machine and its four doors

| Fact | Where | What it means for this review |
|---|---|---|
| `Config.CapsuleCost = 400`, coins only | `Config.lua:54` | The sticker price. Not the economic cost, and not the policy-relevant fact. |
| `Config.CapsulesArePaid = false`, with the comment "coins can't be bought with Robux" | `Config.lua:55-59`, echoed at `SminskiServer.server.lua:512-515` | **This comment is false as of the last store session.** See P1. |
| `rollCapsule` has **four** callers | `OpenCapsule` `:537` (400 coins) · `ClaimDaily` `:596` (free, day 5) · the claw `:1757` (40 coins, 8%) · phase D's `"capsuleTicket"` (free, specced) | Only `OpenCapsule` consults the policy flag. That is the right set to gate *under my recommendation* — see P3. |
| `rollCapsule` refunds duplicates straight into `s.data.Coins` at `:562`, bypassing `pay()` | `:558-565` | No pass multiplies a refund. Verified. |
| `bump(s.data, "capsules", 1)` at `:567` | feeds `wcaps` (`Config.lua:503`) | All four doors feed the weekly challenge, including the claw's, today. |
| `paidRandomRestricted()` + `s.capsulesRestricted` | `:518-525`, cached at `:1296-1300`, published at `:334` | Correctly written (fails *closed* on a pcall error, `:522`), and **currently dead code** because the flag is false. |
| ~~15 characters, purely cosmetic, no gameplay field~~ **WRONG — see Addendum A** | `Config.Characters`, `Config.lua:80-96` **and `Config.Passives`, `Config.lua:409-425`** | **I checked the wrong table.** `Config.Characters` has no gameplay field, but `Config.Passives` is a *second* table keyed by the same ids, and it gives all 15 a live run effect. `Tour.lua:42` was telling the truth. A capsule is expression **and power**. |
| Default grant is `OwnedCharacters = { Glow = true }` | `SminskiRunner.client.lua:77`, server default at `:49`/`:140` | This is what makes the new-player duplicate probability exactly `0.62 × 1/5`. |

### Odds disclosure already exists — and is incomplete

**`UI.lua:1170-1191` is a "WHAT'S INSIDE" card** next to the OPEN button: one
row per rarity, the member character names, and the percentage, computed as
`math.floor(r.weight / total * 100 + 0.5)` → **62 / 27 / 9 / 2, summing to
100**. Plus "duplicates give coins back" at `:1191`.

Somebody already thought about this and got most of the way. Credit where it is
due. Two gaps remain (P2): it discloses **rarity tiers, not outcomes** — five
Commons share one 62% — and **the claw machine (`:1750-1777`) discloses
nothing**.

### The money side

- **Coins are sold for Robux, today.** `Config.Products` `:556-563`:
  POCKET CHANGE `3713946196` R$49/3,000 · BRIEFCASE `3713946250` R$249/22,000 ·
  VAULT `3713946313` R$499/50,000. `STORE.md` §3 records all three verified in
  Play in both shops. COIN JAR `productId = 0` is hidden (`:590`).
- **Bought coins never touch `pay()`.** `ProcessReceipt` writes
  `s.data.Coins += prod.coins` directly at `:960-961`. So **Robux cannot fill
  the meter by buying coins.** This is the single most load-bearing fact in the
  whole review and it is already true by construction.
- **`pay()` is the only meter hook** (`:1521`), and the multipliers land at
  `:1523` (CITY PRO) and `:1525` (`passCoinMult × boostMult`). Capturing `coins`
  before `:1523` is genuinely pass-neutral for every *multiplier*.
- **`bump(d, "coins", coins)` at `:1531` uses the POST-multiplier amount**, so
  the `wcoins` weekly and `coins` daily challenges are already pass-accelerated.
  Pre-existing, out of scope, noted so nobody thinks phase D introduced it.
- **`JobPay` has no pass multiplier** (`Config.lua:891-899`); its `mult` is
  Elo-derived, capped at ×1.25 at 1,200 Elo. Earned, not bought. Clean.
- **Pace floors use `CAR_MAX = 130`** (`:1458`), a constant, not the player's
  car — `:1637`, `:1665`, `:1790`. The *theoretical* ceiling is therefore
  car-independent; the *achievable* rate is not. That distinction is the whole
  of Q3.

### The store, checked against this feature

**Verified: zero of the 12 store items references capsules, tickets, or
randomness** in its name, badge, `perks`, or `desc` (`Config.Passes:515-540`,
`Config.Products:554-581`, `STORE.md` §1–§2). COIN JAR's shipped copy sells
"a car, a skin and change" — not capsules. That is now a compliance asset, not
just good taste (P4).

---

## THE DESIGN — the five verdicts

### Q1. Does giving away tickets devalue anything players pay for?

**No, and the reason is not the one the loop spec gives.**

The loop spec's argument is "sink displacement, not inflation". That is correct
as far as it goes, but it answers the wrong question. The commercial question is
*whether Robux was ever the gate on capsules*, and it was not:

```
187 base coins/min (LOOPS.md §6 reference rate)
  ÷ 400 coins per capsule
  = one capsule every 2.14 minutes, free, for any player, today
```

A player who spends 100% of income on capsules already gets **28 rolls an
hour**. Phase D's meter delivers **6 an hour at best** (`Ticket = 1870` at the
`PerMin = 187` ceiling) and **3.5–4 an hour** at the loop spec's own
more-honest 110–190 base-coins/min band. **The meter is 4.7× to 7.5× slower
than the free route that already shipped.**

So the collection was never money-gated; it was *attention*-gated — a choice
between a capsule and a car. Phase D adds a parallel currency that buys only
capsules, at a worse rate than the existing free route, and changes nothing
about the choice.

**COIN JAR, priced against capsules:**

| | |
|---|---|
| COIN JAR | R$99 → 7,500 coins |
| = capsule rolls | 18.75 |
| = free grinding time it replaces | 7,500 ÷ 187 = **40.1 minutes** |
| Phase D's give-away per hour of city play | ~4.75 tickets = 1,900 coins sticker = **0.25 COIN JAR** |

R$99 bought 40 minutes of capsule-equivalent grinding *before* phase D existed.
That was already a weak capsule proposition, which is exactly why STORE.md's
own copy sells COIN JAR as a car and a skin.

**Displacement estimate, stated as an estimate.** If capsules are a generous
15% of a coin-buyer's spend (the big sinks are 9,000–60,000: Arcade 60,000,
Cinema 35,000, Monster Truck 20,000, a Bankside penthouse 4,000 × 6 = 24,000 —
`Config.City:658-691`), and phase D supplies 4.75 of the 28 rolls/hour the coin
route already affords (17%), then phase D displaces
`0.15 × 0.17 ≈ **2.5% of coin demand**`. That is below the noise floor of a game
with **zero telemetry** (`loop.md` §"What does not exist"), so nobody will ever
be able to attribute it either way.

**Recommendation: ship COIN JAR at R$99 / 7,500 coins, copy unchanged.** The
`+25%` badge and the rising coins-per-Robux ladder are the reason the tier
exists and phase D does not touch either.

**The one product phase D makes slightly *more* valuable:** RIPEN NOW (R$25).
`skipFarm` ripens city farm plots (`:991-992`), and `CityHarvests` is on the
whitelist. 12 plots × `Harvest = 10` = **120 meter units** per purchase =
6.4% of a ticket. `1870 / 120 = 15.6` purchases = **R$390 per ticket** versus
10 free minutes, and you must still walk the whole 60×70 grid at radius 28. Not
an exploit; the only Robux→meter path in the game and it is 39× worse than
playing. Recorded so it is a decision, not a discovery.

**The one product phase D slightly devalues, which nobody asked about.** All
three boosts and the 2x COINS / VIP passes double or scale *coins* and not the
meter. A boost used to double 100% of what a player earns; it now doubles
`187 / (187 + 40) = **82%**` of what they *perceive* they earn — an **18%
relative devaluation** of `boost2x`, `boost2xs`, `boost2xs30`, 2x COINS (R$399)
and VIP (R$299), in perception only.

**Do nothing about it, and here is the citable reason to never fix it:** making
a boost multiply the meter would make tickets "indirectly purchased with Robux"
and would be a **rate-up on a random item** — a category Roblox's policy names
explicitly ("Luck boosts", "Pity systems", "Rate-up scrolls"). The loop
designer's pass-neutral meter is not merely tasteful; **it is the thing that
keeps phase D outside the Paid Random Items policy entirely.** That is the
finding I would most want the human to keep.

### Q2. Roblox policy on paid random items

I looked this up rather than recalling it. Sources are listed at the end.
The definition, verbatim from the Creator Hub policy page and the
"Clarifying Requirements for Paid Random Items" announcement (the announcement
states "The updates are live today"):

> items "purchased directly with Robux, or **indirectly via in-game currencies
> purchased with Robux**, that yield a random outcome"

and the exemption:

> "If your game offers randomized virtual rewards in exchange for completing an
> action that does not involve the payment of Robux or other in-game currency,
> you aren't required to disclose the odds."

> "If players cannot purchase (directly or indirectly) the random outcome … it
> is not a Paid Random Item and is not subject to this policy."

#### P1 — CRITICAL, PRE-EXISTING: `Config.CapsulesArePaid = false` is factually wrong

`Config.lua:55-58` says "They only cost EARNED coins, so they are not 'paid
random items'. If you ever sell coins for Robux, set this to true". **Coins are
sold for Robux.** Three developer products are live and verified
(`Config.lua:556`, `:560`, `:562`; `STORE.md` §3). The condition in the comment
is already met and the flag was never flipped.

Therefore, **today, with or without phase D**: the capsule machine is a Paid
Random Item, and so is the claw machine (40 coins, `Config.City.Claw`,
`:1750-1777`), because coins are an "in-game currency purchased with Robux".

**Phase D does not cause this and phase D's ticket path is the one part of the
system that is exempt.** But phase D is the right moment to fix it, because the
flag has to be correct before a fourth door onto `rollCapsule` is built.

#### P2 — Odds disclosure: mostly done, two gaps

| Risk | Rule it touches | Status | Mitigation |
|---|---|---|---|
| Rarity tiers disclosed, **individual outcomes are not** — five Commons share one 62% | "every possible outcome and its actual probability … as a percentage … adding up to 100%" | `UI.lua:1178-1190` | 15 rows at 2 d.p. See N2. Sums to **100.00** exactly. |
| The **claw machine discloses nothing** | same | `:1750-1777`, no UI | A 6-row panel on the claw prompt. See N3. Sums to **100**. |
| The claw's 8% branch is a **nested** random roll into `rollCapsule` | "all possible outcomes" | `:1757` | The claw row must read "a toy capsule (see capsule odds)" and link, not claim a flat outcome. |
| The claw's outfit slice **silently becomes coins** when the pool is empty (`:1765`, `if #pool > 0`) | probabilities "must sum to 100%" | `:1759-1770` | The displayed table must be state-aware: once a player owns all 17 eligible outfits, the 8% outfit row becomes coins and the 34% row reads 42%. An engineer will miss this. |
| `math.floor(x*100 + 0.5)` rounding | sum to exactly 100% | `UI.lua:1189` | Fine at tier level (62+27+9+2). At outcome level **one decimal is not enough** (Epic 2.25 → 2.3 → total 100.2). Use 2 d.p. |
| Phase D's redeem prompt shows no odds | *not required* — the ticket is earned, exemption above | — | Not required. Recommended anyway as one sub-line, because it is free and it is the same table. |

#### P3 — If `CapsulesArePaid` were ever turned on: does phase D create a new hole?

**Short answer: no — one specced-but-easy-to-forget gate, and the existing
"holes" are not holes under the correct treatment.**

The long answer matters, because flipping the flag *today* would produce a
**worse** state than either extreme. `OpenCapsule` (`:532`) blocks restricted
players from the 400-coin capsule; **the claw at `:1752-1758` does not**, so a
restricted player would lose the 400-coin door and keep the 40-coin door that
also hands out capsules. A partial block is worse than no block. That defect
exists today, independent of phase D.

Roblox lists six permitted treatments for a user with
`ArePaidRandomItemsRestricted = true`, and **the first one is**:

> "Offering an unpaid, earnable path to acquiring the random item"

**Phase D is literally that.** So the correct configuration is not "gate
everything", it is **gate the doors that consume purchasable currency, and
leave the currency-free doors open**:

| Door | Currency | Restricted player | Why |
|---|---|---|---|
| `OpenCapsule` `:537` | 400 coins (purchasable) | **blocked** | Treatment 5. Already coded at `:532`. |
| claw `:1757` | 40 coins (purchasable) | **blocked** | Same rule. **Not coded — this is the gap.** |
| `ClaimDaily` day 5 `:596` | none | **open** | Earned. Exempt by the quoted sentence. |
| phase D `"capsuleTicket"` | none (a ticket earned by playing) | **open** | Earned. Exempt. Treatment 1. |

Under that rule, phase D adds **zero** new policy obligations, and
`ClaimDaily`'s ungated free capsule — which looks like a bug today — is
correct. The only code that must change is the claw's gate and the flag itself.

**Honest uncertainty, stated rather than asserted.** I could not find an
explicit Roblox statement resolving the *mixed-source* case: one random
generator funded by both purchasable currency and a free earned ticket. The
"not subject to this policy" sentence is conditioned on players *not* being
able to purchase the outcome, and here they can — so the **machine** is in
scope and odds disclosure is owed regardless of phase D. What is not directly
answered is whether the *free door* must also be shut for restricted users.
Treatment 1's existence strongly implies the free door is the remedy, not the
problem. This is the one item I would put to Roblox DevRel before flipping the
flag, and it is Open Question 2.

#### P4 — The bright line I want to own

Because `Config.Meter.Rates` credits gameplay actions and nothing else, no
Robux purchase converts into tickets. The line that must never be crossed:

> **No store item's name, badge, description or perk list may reference
> capsules, tickets, the meter, luck, odds or rarity — and no store item may
> multiply, accelerate, refill or bank the meter.**

All 12 current items comply (verified above). I will add this rule to
`docs/STORE.md` on request rather than editing it unilaterally (see REQUESTS).

### Q3. Pay-to-win risk

**Verdict: not pay-to-win. But the loop spec's claim is false as written, and
one QA test will fail because of it.**

`loop.md` D5 says: *"An account holding every pass fills the meter at exactly
the rate a brand-new account does."* That is true of every **multiplier** —
verified at `:1523` and `:1525`: CITY PRO 1.5, VIP 1.25, 2x COINS 2, the login
streak up to 1.5, and all three boost products are meter-neutral.

It is **false of the two passes that are not multipliers**, because the meter
counts base coins *per minute* and both passes buy throughput:

- **QUICK FEET** R$149 — `walkMult = 1.6`, `carMult = 1.15`
  (`Config.lua:539`, applied at `:753-754`, `City.lua:1468-1471`).
- **DREAM GARAGE** R$349 — `allCars = true`, i.e. the Sports Car (115 studs/s),
  the Taxi (fares ×1.5 **applied to base at `:1658`, so it does fill the meter
  1.5× faster**) and the Ice Cream Truck (`Sweep + 2` and a 28-stud radius vs
  18, `:1676`, `:1679` — also base).

The `PerMin = 187` ceiling neutralises this **only on activities already above
187 base coins/min**. Numbers in N4. The summary:

| Activity | free, min/ticket | with QUICK FEET + DREAM GARAGE | advantage bought |
|---|---|---|---|
| Deliveries, free convertible | **10.0** (ceiling) | 10.0 | **none** |
| Taxi fares, free convertible | **10.0** (ceiling) | 10.0 | **none** |
| City farm | 11.7 | 10.0 | 1.17× |
| Pizzeria at par | 13.4–17.0 | 9.9–12.6 | ≤1.35× (its own `paced` scaler at `:2097` caps this) |
| Sweeping litter | 15.6–20.8 | 10.0 | **1.6–2.1×** |
| Kart races | ~14.6 (unmeasured) | 10.0 | ~1.5× + a payout-tier jump, see below |

**Plainly: R$498 of passes shortens time-to-ticket by up to 2.1× for a player
whose chosen activity is sweeping litter, and by nothing at all for a player
doing deliveries or taxi fares.**

**Why that is still not pay-to-win, and why I am comfortable:**

1. **A pass can never beat 10 minutes.** The ceiling is absolute. The most
   Robux can buy is *reaching* the ceiling.
2. **The fastest meter in the game costs 0 Robux.** Deliveries and taxi fares
   both saturate the ceiling on the **free convertible** (72 studs/s) — see N4.
   Every player has that car on day one (`Config.City.Cars`, `convertible`,
   `price = 0`). So the free path is not merely adequate; it is optimal.
3. ~~**The reward is cosmetic** (`Config.Characters` has no gameplay field), so
   nothing competitive is on the other end.~~ **WITHDRAWN — this was the load-
   bearing error. See Addendum A.** The reward carries a gameplay passive, and
   one of them is a permanent coin multiplier. Reasons 1, 2 and 4 stand; this
   one does not, and it is the one the verdict rested on.
4. **Robux cannot buy meter directly** — bought coins bypass `pay()` at
   `:960-961`.

**Two things I must flag rather than wave through:**

**(a) `Races` is the one whitelisted tag attached to a competitive number.**
`Config.City.Race = { gold = 30, par = 42, goldPay = 200, parPay = 80 }`
(`Config.lua:703`). The payout tier is gated on **absolute elapsed time**,
which is directly purchasable via DREAM GARAGE (sports car 115 vs convertible
72 — a 1.6× lap-time ratio against a fixed 30-second gold threshold), and gold
is **announced server-wide** at `:1798`. If the free convertible cannot beat 30
seconds, a paying player earns `200` where a free player earns `80` — a 2.5×
payout ratio on top of the time ratio, now feeding the meter.

This is **pre-existing** (the sports car is also 9,000 coins, and the race
payout was already pass-multiplied) and phase D merely routes it into the
whitelist. I am **not** recommending removing `Races = 1`: the delta is
~1.5×, the same order as sweeping, and removing it would punish a free player
who likes karting. I am recommending the threshold be **measured** (QA below)
and handed to whoever owns city economy balance, because `Race.gold = 30` being
unreachable in the free car is a balance problem in its own right.

**(b) QA item 6 in `loop.md` will fail, and the failure will be correct.**
As written it says *"Same activity, same duration … `meter` must differ by
< 2%"*. On sweeping that will differ by up to 110%. A failing test that
describes correct behaviour either wastes a QA round or gets "fixed". It must
name the activity. Corrected wording is in QA SHOULD CHECK.

**If the human wants strict neutrality**, the cheapest lever is **lowering
`Ticket`** (which helps everyone equally), **not** touching the whitelist, and
**never** adding a meter multiplier — see P4.

### Q4. Sanity-checking the three decisions already made

All three are safe. My combined figure lands within 0.1 points of the loop
designer's, and my `wcaps` figure is **lower** than theirs.

**The give-away rate, all five sources** (the two already shipped included —
the loop spec counts three and the accounting should count five):

| Source | Capsules/day, committed 1 h/day player | Where |
|---|---|---|
| Meter | ~4.75 (at 10–17 min/ticket) | phase D |
| Daily 3 hunt, 3/3 | 1.00 | phase D |
| 7-day Daily-3 streak | 0.143 | phase D, human decision |
| `Config.Daily` day 5 login capsule | 0.143 | **already ships**, `Config.lua:638`, `:595-597` |
| Claw, 8% at 40 coins | player-elective, coin-funded | **already ships**, `:1755` |
| **Total free** | **≈ 6.04/day** = 2,416 coins sticker | |

Against 60 min × 187 = 11,220 base coins/day → **21.5% of income in capsule
sticker value**. The loop designer said 21.4%. **I agree.**

At `DayCap = 12` (+1 hunt +0.14 streak +0.14 login = 13.3): reaching the cap
needs 120 ceiling-rate minutes, so that day's income is ≥ 22,440 → **23.7%**.
The ratio barely moves, which *confirms* the loop designer's framing that
`DayCap` is a circuit breaker and not a balance lever. Keep it or drop it; it is
not load-bearing.

**Minted coins, worst case day, complete collection:**
`13.3 × 104.1 = **1,385 coins/day** = 7.4 minutes of job income = 6.2% of that
day's earnings`. (The loop spec says 1,250 because it counts 12, not 13.3.)
Safe. Agreed.

**Where I disagree with the loop designer — the 7.4 number.** I re-derived both
endpoints and both are exactly right:

- New player, owns only Glow (`SminskiRunner.client.lua:77`):
  `P(dup) = 0.62 × 1/5 = 0.124`, refund 60 → **E = 7.44** ✓
- Complete collection:
  `0.62×60 + 0.27×120 + 0.09×250 + 0.02×600 = 37.2 + 32.4 + 22.5 + 12 =` **104.1** ✓

But **7.4 is true only for roughly a player's first ten rolls.** The intermediate
states are what an account actually spends its life in:

| Collection state | E[refund] per roll |
|---|---|
| Glow only (rolls 1–10) | 7.4 |
| all 5 Commons | 37.2 |
| all Commons + all Rares | **69.6** |
| everything but Golden | **92.1** |
| complete | 104.1 |

Because Golden is 2% (≈35 rolls to see once) and the four Epics are 2.25% each,
an account sits in the **69.6–92.1** band for the large majority of its rolls.
So the honest minting band is **0.4% of the job rate in the first hour, rising
to ~4–5% within the first several hours, 5.6% asymptotically** — not
"0.4%–5.6%" read as a range a player moves slowly across. The conclusion is
unchanged (under 6% of the job rate is not worth a mechanism) but **the 7.4
figure should not be used to reassure anyone.**

**`wcaps` — my number is lower than the loop designer's, and the
recommendation is the same: leave it.**

`Config.lua:503`: `goals = { 3, 5 }, reward = 600` (600/800). But
`ChallengeCounts.weekly = 2` out of a pool of 5 (`Config.lua:499-505`), so
`wcaps` is only drawn in roughly **2 weeks in 5**.

| | |
|---|---|
| Loop designer's figure | ≤ 800 coins/week |
| Expected, accounting for 40% draw rate | `0.4 × ~700 = **280 coins/week** = 40 coins/day = **0.36%** of daily income` |

And the sharper point: **`wcaps` was never a coin farm — it was a net sink.**
Opening 3 capsules costs 1,200 coins and returns `3 × E[refund] + 600`:
−288 coins for a complete-collection player, −578 for a new one. Free tickets
flip that occurrence from **−288…−578 to +600…+800**, a swing of
**+888 to +1,378 coins per occurrence**, ×0.4 = **+355 to +551 coins/week
expected = 51–79 coins/day = 0.5–0.7% of daily income**.

A small sink became a small faucet. **Recommendation: leave it**, as the loop
designer says, and it is now a decision with a number on it rather than an
oversight.

**`Ticket = 1870` ships as specced: agreed, with one caveat that is the loop
designer's own.** Their §M distrusts `PerMin = 187` first, and they are right
to: if the typical player earns ~120 base coins/min the typical ticket takes
15.6 minutes and the feature under-delivers. From a monetization angle that
error is in the **safe** direction — slower tickets mean less sink displacement
— so there is no commercial reason to pre-emptively lower `Ticket`. Measure
first (QA item 25), then tune.

**The 7-day streak ticket: agreed, and it is the cheapest of the three.** One
ticket per 7 days is 0.143/day, 2.4% of the give-away. It is also *the* source I
would most defend, because it rewards returning rather than grinding.

### Q5. What phase D makes newly possible commercially

**Nothing. No new pass, no new product, no price change.** I recommend one
thing, and it is not a product: **ship COIN JAR as already specced** — it is
the last item in `STORE.md` §4, it is unaffected by this feature, and the
R$49→R$249 gap is a real hole in the ladder.

What I considered and am explicitly recommending **against**, so nobody
re-proposes it in three weeks:

| Rejected | Why |
|---|---|
| **A ticket bundle product** (buy N capsule tickets for Robux) | This is the trap. It converts the one free, exempt, gameplay-earned path into a **Paid Random Item** — directly purchased with Robux, odds disclosure owed, restricted players blocked from it — and it destroys the 10-minute honesty that is the meter's entire design. **Never build this.** |
| **A pass or product that fills the meter faster** | The loop designer flagged it; I am confirming it with the rule, not the instinct. Roblox names "Luck boosts", "Pity systems", "Rate-up scrolls" and "Enhanced resource drops" as Paid Random Items requiring numerical odds disclosure with **dynamic updates**. A Robux meter accelerator is a rate-up on a random item and it would drag the free path into the policy with it. |
| **Selling extra banked-ticket slots** (`MaxTickets`) | Sells away the mall trip, which is the feature's only social property, and reads as a squeeze. |
| **Robux to redeem a ticket without the mall trip** | Genuinely "selling convenience", and genuinely tempting. But it deletes the co-location the loop spec built the feature around, and `loop.md` §M measurement 3 already says whether the mall trip survives is a *measurement* decision, not a product one. Revisit after data, if ever. |
| **Selling individual characters for coins at expected value** (Roblox treatment option 3) | It is a legitimate compliance alternative, but Golden's expected value is `400 / 0.02 = 20,000 coins`, which is absurd on its face, and it would undercut the capsule entirely. Odds disclosure is far cheaper. |
| **Trading or gifting tickets** | Agreed with the loop spec, plus: peer trading of paid items has its **own** policy attribute (`IsPaidItemTradingAllowed`) that nothing in this repo checks. Do not open this door. |

### The free path

**Strictly better than before, by construction.** A non-spender gains ~4.75
capsules/hour plus 1/day from the hunt plus 1/week from the streak, and loses
**nothing**: no coin price changed, no existing reward was reduced, no sink was
added, and the 2.14-minute coin route to a capsule is untouched. A non-spender
also completes the 15-character collection for free in 10–21 hours via the
meter, or 2.1–2.9 hours of dedicated grinding via coins — both free, both
unchanged or improved.

The only way phase D could make the free path worse is if someone "paid for" it
by raising `CapsuleCost` or trimming a payout. **Nobody should.** If that
appears in a later revision, this review objects.

---

## NUMBERS

### N1. Every tunable I am ruling on (I add none)

| Tunable | Value | My verdict |
|---|---|---|
| `Config.CapsuleCost` | 400 | **unchanged.** Raising it to "pay for" free tickets would make the free path worse and is forbidden by my own checklist. |
| `Config.CapsulesArePaid` | `false` | **must become `true`.** Factually wrong today (P1). Do it together with the claw gate, not alone. |
| `Config.Products` `coins2` COIN JAR | R$99 / 7,500 / `+25%` badge | **unchanged. Ship it.** |
| All other product prices and coin amounts | as shipped | **unchanged.** |
| All 11 pass prices | as shipped | **unchanged.** |
| `Config.Meter.Ticket` | 1870 | **unchanged**, tune from QA item 25. Error is in the safe direction. |
| `Config.Meter.PerMin` | 187 | **unchanged.** Do not raise it — it is the ceiling that caps the purchasable advantage at "reach the ceiling". |
| `Config.Meter.Rates` | the loop spec's 8 tags | **unchanged**, including `Races` (see Q3a). Never add a multiplier of any kind. |
| `Config.Meter.MaxTickets` / `DayCap` | 3 / 12 | **unchanged.** Not load-bearing on the 21.5% ratio either way. |
| `wcaps` counting free tickets | yes | **unchanged.** +0.5–0.7% of daily income. |
| N5 restricted fallback | 240 coins | **DROP IT.** See N6. |

### N2. Per-outcome capsule odds — the exact table to display

`rollCapsule` picks a rarity by weight (`Config.Rarities`, `Config.lua:65-70`)
then **uniformly** within that rarity's pool (`:553-557`). So per-character
odds are `rarity.weight / #pool`, and they must be shown at **two decimal
places** or they will not sum to 100 (one decimal turns Epic 2.25 → 2.3 and the
total to 100.2).

| Rarity | weight | pool | members | each | subtotal |
|---|---|---|---|---|---|
| Common | 62 | 5 | Glow, Blush, Sky, Lemon, Cocoa | **12.40%** | 62.00 |
| Rare | 27 | 5 | Lavender, Mint, Peach, Sakura, Aqua | **5.40%** | 27.00 |
| Epic | 9 | 4 | Ghost, Night, Galaxy, Ember | **2.25%** | 9.00 |
| Secret | 2 | 1 | Golden | **2.00%** | 2.00 |
| | | **15** | | | **100.00** |

Also disclose, because they are part of "all possible outcomes":

- **Duplicates are possible** — the roll never excludes owned characters
  (`:558`). The existing copy "duplicates give coins back" (`UI.lua:1191`) is
  good; give it the numbers.
- **Duplicate refunds: Common 60 · Rare 120 · Epic 250 · Secret 600**
  (`Config.lua:66-69`).

Presentation: keep the existing four-row tier card as the headline (it is
readable and cosy) and put the 15 rows behind a **labelled** control. Roblox's
guidance is explicit that a bare `(i)` symbol is insufficient — the label must
read **`DETAILS`** or **`INFO`**. Suggested copy, in the project's tone:
`ODDS  ·  15 to collect  ·  DETAILS`.

### N3. Claw machine odds — the exact table

Derived from `:1753-1775`. `r = math.random()`.

| Outcome | range | odds | note |
|---|---|---|---|
| A toy capsule | `r < 0.08` | **8%** | nested roll — must link to N2, not claim a flat outcome |
| An outfit you don't own | `0.08 ≤ r < 0.16` | **8%** | from `price > 0`, `≤ 1000`, not `exclusive` (17 items) |
| 10–30 coins | `0.16 ≤ r < 0.50` | **34%** | |
| 50 coins | `0.50 ≤ r < 0.80` | **30%** | |
| 120 coins | `0.80 ≤ r < 0.95` | **15%** | |
| 250 coins | `0.95 ≤ r` | **5%** | |
| | | **100%** | |

**State-dependent, and easy to get wrong:** the outfit branch only fires if the
pool is non-empty (`:1765`). A player who owns all 17 eligible outfits falls
through to the coin branch with `r < 0.5`, so their real table is **42% for
10–30 coins and 0% outfit**. The displayed table must reflect the viewing
player's state, or the disclosed probabilities do not sum to 100% for them.

Expected cost of a capsule via the claw: `40 / 0.08 = 500 coins` — worse than
400 direct, which is correct and needs no change.

### N4. The pass-acceleration arithmetic behind Q3

`Delivery = { base = 30, perStud = 1/8 }`, `Taxi = { base = 25, perStud = 1/6 }`,
`Sweep = 4`, `Harvest = 10` (`Config.lua:705-707`); `RipeSeconds = 45`
(`:708`); `CAR_MAX = 130` (`:1458`); convertible 72 studs/s, sports 115,
taxi 76, ice cream 64 (`Config.City.Cars`).

**Deliveries.** `pay = 30 + dist/8`; the `:1637` floor is `dist/130`, which
never binds below 130 studs/s. Round trip ≈ `2·dist / carSpeed` (you must return
to the depot, `:1627`). At `dist = 500`, `pay = 92.5`:

| car | round trip | base coins/min | min/ticket |
|---|---|---|---|
| convertible 72 (**free**) | 13.9 s | **399** | 10.0 (ceiling) |
| sports 115 + QUICK FEET 1.15 → 132 | 7.6 s | 730 | 10.0 (ceiling) |

**The free car already saturates the ceiling at 2.1× over.** Robux buys nothing.

**Taxi.** Fares are picked > 350 studs from the stand (`:1653`);
`pay = 25 + dist/6`, ×1.5 in a taxi (`:1658`, **pre-`pay()`, so it does credit
the meter**). At `dist = 700`, base fare 141.7:

| car | round trip | base coins/min | min/ticket |
|---|---|---|---|
| convertible 72 (**free**) | 19.4 s | **438** | 10.0 (ceiling) |
| taxi 76, fare ×1.5 = 212.5 | 18.4 s | 693 | 10.0 (ceiling) |

Ceiling again. DREAM GARAGE's taxi bonus buys nothing *for the meter*.

**Sweeping.** `Sweep = 4`, `+2` in the truck, radius 18 → 28 (`:1676`, `:1679`).
Free rate is unmeasured; the loop spec estimates 90–120 base/min.
Ice cream truck ≈ `(6/4) × ~1.7 throughput from the wider radius ≈ 2.5×` →
225–300 base/min → ceiling. **15.6–20.8 min/ticket → 10.0. Up to 2.1×.**
This is the largest verified purchasable advantage and it is unmeasured on both
ends — QA item 25 must cover sweeping with and without the truck.

**City farm.** 12 plots, 60×70 grid (`Places.lua:498-506`), radius 28, 45 s
ripen. Throughput is pure walk speed. 160 base/min free → QUICK FEET ×1.6 =
256 → ceiling. **11.7 → 10.0 min/ticket, 1.17×.**

**Pizzeria.** `gap < par×0.5` refused (`:2094`) and
`paced = clamp(0.35 + gap/par × 0.65, 0, 1)` (`:2097`). At the fastest legal
pace (`gap = par/2`) you get `paced = 0.675` in half the time = **1.35× rate,
maximum, and that is available to a free player too.** 110–140 → ≤189 base/min,
still under the ceiling. **≤1.35×.**

**Races.** Fixed payouts against absolute-time thresholds
(`gold = 30 s → 200`, `par = 42 s → 80`). A 1.6× car-speed ratio against a
fixed 30-second gate is a **payout-tier** difference, not a rate difference.
`raceLen` is computed at runtime (`:1460-1463`) so I will not assert the lap
time — **measure it** (QA below). If the convertible cannot clear 30 s, this is
the widest gap in the table.

### N5. Ceiling saturation, restated as the defence

```
best free meter rate  = 187 units/min  (deliveries or taxi, free convertible)
best paid meter rate  = 187 units/min  (the ceiling is absolute)
maximum purchasable   = 0% on the optimal activity
                        up to 108% on the slowest whitelisted activity
minimum time/ticket   = 10.0 minutes, for everybody, at any spend level
```

### N6. Why the 240-coin restricted fallback should be dropped

`loop.md` N5 proposes: when `CapsulesArePaid` is true and the player is
restricted, `"capsuleTicket"` pays 240 coins instead of rolling. Three reasons
to drop it, in increasing order of strength:

1. **It is not required.** A ticket costs no Robux and no in-game currency, so
   the roll is covered by the exemption quoted in Q2.
2. **It is inflationary, and worse than the thing it replaces.**
   `240 × 13.3 tickets/day = **3,192 coins/day**` versus the complete-collection
   minting worst case of `13.3 × 104.1 = **1,385**`. The fallback makes a
   restricted player's free-ticket stream **2.3× more inflationary than
   everyone else's**, and it pays a guaranteed 240 where the honest expected
   value ranges from 7.4 to 104.1.
3. **It is the worst experience for the cohort the policy exists to protect.**
   A young player in a restricted region plays ten minutes, earns a ticket, and
   receives coins while everyone around them receives a Sminski. `design.md`'s
   whole register is cosy; this is the opposite. And it denies them treatment
   option 1 — *"offering an unpaid, earnable path to acquiring the random
   item"* — which is the remedy Roblox lists **first** and which phase D
   already is.

**Recommendation: no fallback. A restricted player redeems tickets normally.**
Gate the two coin-funded doors instead (P3 table).

---

## EDGE CASES

Monetization- and policy-shaped; the loop spec covers the mechanical ones.

**A restricted player.** Under my recommendation: `OpenCapsule` and the claw
refuse; `ClaimDaily` day 5 and `capsuleTicket` work normally. They can complete
the whole 15-character collection for free via the meter and the hunt. That is
the most generous compliant configuration available and it needs no new UI
beyond an honest refusal on the two coin buttons. **Today**, with the flag
false, they can do everything — which is the non-compliant state, not a
feature.

**`paidRandomRestricted` lookup fails.** `:522` treats the player as
restricted — fails closed. Correct, and worth preserving: a `pcall` failure
must never open a paid random item. Under my recommendation the cost of a false
positive drops from "no capsules at all" to "no *bought* capsules", which makes
failing closed cheap.

**A COIN JAR buyer who also earns tickets.** No interaction. Bought coins land
at `:960-961` and never touch `pay()`, so a R$99 purchase adds 0 meter units.
A player can hold 7,500 coins and a full meter simultaneously; they are
unrelated stocks.

**A complete collection.** Every roll is a duplicate: 104.1 expected coins. At
`DayCap` that is 1,385 coins/day = 7.4 minutes of job income. Safe. But note
the *product* consequence: for this player a ticket is a 104-coin coupon and
the capsule sink is gone. **Nothing in the store should try to re-monetise
them** — there is no honest product there, and a "collection reset" or a second
capsule series is a content decision, not a monetization one.

**A boost is live when a ticket is granted.** The boost multiplies coins at
`:1525` and the meter is credited from the pre-multiplier base. A player who
paid R$349 for `boost2xs30` sees double coins and an unchanged meter. This is
correct and must stay correct (P4). It is the one place a player could
plausibly file a "my boost didn't work" complaint, so the boost's copy should
keep saying **coins** — which it already does (`STORE.md` §1, all three boosts
say "double coins"). No change.

**A player who buys RIPEN NOW to farm the meter.** 120 units per R$25 =
R$390/ticket, and they must walk the 12-plot grid (no standing position reaches
two plots at radius 28). Self-limiting by 39×. No action.

**A `ProcessReceipt` retry / a failed save around a ticket grant.** Tickets are
not purchased, so the `Receipts` ledger (`:943-945`) does not apply to them.
The relevant hazard is the loop spec's own: decrement the ticket **before**
`rollCapsule`, because it calls `task.spawn(save, player)` at `:566`
(`loop.md` D5). Nothing in my lane changes that.

**A Robux refund or chargeback.** Roblox does not call back into the
experience, so a refunded coin bundle leaves the coins spent — possibly on
capsules. Pre-existing for all four coin products and unaffected by phase D.
Recorded only so it is not discovered later and blamed on tickets.

**Empty server / one player.** No monetization surface changes. The meter and
the hunt are per-player, and neither has a `minPlayers`. Nothing in the store
is server-gated except the two server-wide boosts, whose value genuinely does
fall on an empty server — pre-existing, and arguably the reason to keep the
mall trip.

**A scripted player.** Cannot beat 10 minutes per ticket (the ceiling), gains
nothing a real player does not have, and produces at most 13.3 capsules/day of
cosmetics with no resale path (no trading, no real-money trading, no
marketplace). **The commercial exposure from botting phase D is zero**, which
is a better answer than any detection system.

**Mid-event join / leave.** No entitlement is event-scoped. Passes are read at
join (`refreshPasses`, `:1302`), banked tickets are saved, and boosts are
time-based. Nothing to reconcile.

**A player who owns every pass.** Fills the meter at the ceiling on the
activities a free player also fills at the ceiling, and up to 2.1× faster on
sweeping. Gets 4.5–5.6× the coins. The two numbers diverge, deliberately.

---

## CUT / DEFER

| Cut | Why |
|---|---|
| **Any new pass or product for phase D** | Nothing is missing. The store's gap is COIN JAR, which predates this feature and is unaffected by it. Inventing a ticket product is the one genuinely dangerous move available here. |
| **A price or content change to any of the 12 store items** | The displacement is ~2.5% of coin demand, unmeasurable with zero telemetry. Changing a live price on an estimate is worse than leaving it. |
| **Re-pricing the capsule (`CapsuleCost`)** | Would make the free path worse, which my own checklist forbids. |
| **Removing `Races` from the meter whitelist** | Tempting (Q3a) but disproportionate: ~1.5×, the same order as sweeping, and it would punish free karting players. Handed to the economy owner as a threshold question instead. |
| **A restricted-player coin fallback** | Dropped outright, with three reasons in N6. |
| **Odds disclosure on phase D's redeem prompt as a *requirement*** | Not required (the ticket is earned). Recommended as a one-line courtesy, deferred to whoever builds the prompt. |
| **Asking Roblox DevRel about the mixed-source case before shipping phase D** | Phase D itself is exempt either way. The question only becomes blocking when `CapsulesArePaid` is flipped, which is a separate change. Defer it to that change. |
| **Any monetization aimed at a complete-collection player** | No honest product exists. Content, not money. |

---

## REQUESTS FOR OTHER OWNERS

**These are requests, not designs. I have changed no code and no other file.**

1. **For the human, then `server-engineer` — the P1 package. Do these three
   together or not at all.** Flipping the flag alone produces a worse state
   than today (a restricted player loses the 400-coin door and keeps the
   40-coin one).
   - `Config.CapsulesArePaid = true` (`Config.lua:59`), and correct the comment
     at `Config.lua:55-58` and `SminskiServer.server.lua:512-515` — both
     currently claim coins cannot be bought with Robux.
   - Gate the **claw** (`:1750-1758`) on the same check `OpenCapsule` already
     uses at `:532`. This is the actual hole and it predates phase D.
   - Leave `ClaimDaily` (`:596`) and phase D's `"capsuleTicket"` **ungated**
     (P3, N6). Add a comment at each saying *why*, or someone will "fix" them.
   - **Do not touch `rollCapsule`.** I agree with the loop spec's reasoning
     entirely: the gate belongs at the doors, where the currency is, not inside
     the shared roll. Four doors, two currencies, one rule — and the rule
     partitions cleanly by door.

2. **For `client-engineer` / whoever owns the shop UI — odds disclosure.**
   The exact tables are N2 (15 rows, 2 d.p., sums to 100.00) and N3 (6 rows,
   sums to 100, **state-dependent** — see the empty-outfit-pool case). Extend
   the existing card at `UI.lua:1170-1191` rather than replacing it; the tier
   view is good and cosy, the per-outcome view goes behind a control labelled
   **`DETAILS`** (a bare `(i)` is explicitly insufficient under Roblox
   guidance). The claw needs a panel it does not have at all.

3. **For `loop-designer` — two corrections to `loop.md`, both mine to justify
   and yours to apply.**
   - D5's *"An account holding every pass fills the meter at exactly the rate a
     brand-new account does"* is **false for QUICK FEET and DREAM GARAGE** on
     sub-ceiling activities. Numbers in N4. The claim is true for every
     multiplier, which is the more important half and is worth stating
     precisely.
   - **QA item 6 will fail as written** and the failure will be correct.
     Corrected wording below.
   - N5 (the 240-coin fallback) should be struck; reasons in N6.
   - Consider replacing the "7.4 coins" headline with the 69.6–92.1 mid-life
     band, so nobody quotes the most flattering number.

4. **For whoever owns city economy balance (unassigned) — `Race.gold = 30`.**
   Not phase D's bug, but phase D routes it into the meter. If the free
   convertible (72 studs/s) cannot clear 30 s over `raceLen × 3` studs, then
   `goldPay = 200` is effectively car-gated and DREAM GARAGE (R$349) buys a
   2.5× payout on a server-announced result (`:1798`). Measure, then decide.

5. **For the human — `docs/STORE.md` is mine to edit and I have deliberately
   not edited it.** I would add one short section, and nothing else in the file
   changes — no name, no price, no description, no id:

   > ### 5. Capsules, the claw, and Roblox policy
   >
   > Selling coins for Robux makes the capsule machine (400 coins) and the claw
   > (40 coins) **Paid Random Items** under Roblox policy, because they are
   > "purchased indirectly via in-game currencies purchased with Robux". Three
   > coin bundles are live, so this is true today. Two consequences:
   >
   > 1. **Odds must be disclosed per outcome, as percentages summing to 100%,
   >    before purchase.** The capsule tab discloses rarity tiers
   >    (`UI.lua:1170-1191`); it owes per-character odds. The claw discloses
   >    nothing. Tables: `docs/specs/daily-capsule/monetization.md` N2 and N3.
   > 2. **`Config.CapsulesArePaid` must be `true`**, and the restricted-player
   >    check must cover the claw as well as `OpenCapsule`. Free doors
   >    (day-5 login capsule, phase D capsule tickets) stay open — an unpaid
   >    earnable path is the first remedy Roblox's own guidance lists.
   >
   > **Store rule, from here on:** no store item's name, badge, description or
   > perk list may reference capsules, tickets, the meter, luck, odds or
   > rarity, and no store item may multiply, accelerate, refill or bank the
   > capsule ticket meter. All 12 current items comply. Breaking this rule
   > would make capsule tickets a Paid Random Item and pull the free path into
   > the policy with it.

6. **A telemetry owner.** Seconding the loop designer, from the money side:
   with zero analytics in `game/`, **no claim in this review can be verified
   after launch**, including the 2.5% displacement estimate and the 21.5%
   ratio. The two counters I need are *coins spent on capsules per player-hour*
   and *coin-product purchases per DAU*, before and after phase D.

---

## QA SHOULD CHECK

Entitlements, restricted players, and the meter's rate — each one provable in
Studio. Items 1–4 are the ones that would change a decision.

**Entitlements and the meter's rate**

1. **Bought coins credit zero meter.** Buy any coin product in Studio (or call
   the `ProcessReceipt` path with a coins product). `data.City.meter` must be
   **unchanged, exactly**. This is the single most important test in my lane:
   if it ever moves, capsule tickets become a Paid Random Item.
2. **No boost and no multiplier pass moves the meter.** Same activity, same
   duration, on (a) a clean account, (b) an account with VIP + 2x COINS +
   CITY PRO, (c) a clean account under an active `boost2xs`. Coins must differ
   by ~4.5× and up to ~5.6×; **`meter` must differ by < 2%** in all three.
3. **`loop.md` QA item 6, corrected — it must name the activity.**
   Run the pass-vs-clean comparison **four times**:
   - **Deliveries** (free convertible both sides): `meter` differs by **< 2%**.
     Both saturate the ceiling. *This is the version of item 6 that passes.*
   - **Taxi fares** (free convertible both sides): **< 2%**.
   - **Sweeping litter**, clean-on-foot vs QUICK FEET + ice cream truck:
     `meter` is expected to differ by **up to +108%**. **A large difference
     here is CORRECT — do not file it as a bug and do not let anyone "fix" it.**
     Report the actual number; it is the one in N4 I am least sure of.
   - **City farm**, clean vs QUICK FEET: expected **+0% to +17%** (the pass
     pushes it into the ceiling).
4. **RIPEN NOW's meter credit is bounded.** Plant all 12 city plots, buy
   RIPEN NOW, harvest all 12. `meter` must move by **exactly 120** units
   (12 × `Harvest = 10`), no more. Repeat twice to confirm it does not
   compound beyond 120 per purchase.
5. **Every whitelisted tag's units-per-base-coin is exactly 1.** Read `meter`
   before and after one payout of each of the 8 whitelisted tags and confirm
   `Δmeter == base coins` (below the ceiling). A tag credited at >1 would be a
   silent give-away multiplier.
6. **Measure base coins/min per activity, with and without passes** — the loop
   spec's item 25, extended. 10 minutes each of pizzeria / parcels / taxi /
   sweeping / farm / races, once clean and once with QUICK FEET + DREAM GARAGE.
   **Every number in N4 depends on this and none of them has ever been
   measured.** Report the 12 numbers.
7. **`Race.gold` reachability.** Run three laps in the free convertible and in
   the sports car. Report both times against `Race.gold = 30` and
   `Race.par = 42`. If the convertible cannot reach gold, say so explicitly —
   it changes a recommendation.

**Restricted players** (requires forcing `s.capsulesRestricted = true`; there is
no dev hook today — ask `server-engineer` for one alongside `EventsDev`)

8. **With `CapsulesArePaid = false` (today's shipped state):** a "restricted"
   player can open a 400-coin capsule, play the claw, and receive the day-5
   login capsule. Confirm all three work. **This documents the
   non-compliant baseline** so the fix is provably a fix.
9. **With `CapsulesArePaid = true` and the P1 package applied:**
   - 400-coin `OpenCapsule` → refused, `reason = "restricted"`, **no coins
     deducted** (check the balance to the coin).
   - Claw at 40 coins → refused, **no coins deducted**.
   - `ClaimDaily` day 5 → **capsule granted normally**.
   - `"capsuleTicket"` at Capsule Corner → **rolls normally, ticket consumed,
     no coin fallback paid**.
   - The player can reach a **complete 15-character collection** using only
     tickets and the day-5 gift.
10. **`paidRandomRestricted` fails closed.** Force the `pcall` at `:520` to
    error and confirm the player is treated as restricted (`:522`) and that the
    **free** doors still work.
11. **The policy cache clears on leave.** `policyCache[player] = nil` at
    `:526`. Rejoin and confirm one fresh lookup, not a stale verdict.

**Odds disclosure**

12. **The capsule table sums to exactly 100.00** with 15 rows at 2 d.p., and
    each row matches `rarity.weight / #pool` (N2). Change a weight in
    `Config.Rarities` in Studio and confirm the display follows — a hard-coded
    table that drifts from `Config` is a policy defect, not a cosmetic one.
13. **The claw table sums to exactly 100** (N3), and **changes correctly** for
    a player who owns all 17 eligible outfits: the 8% outfit row must
    disappear and the 10–30 coin row must read **42%**.
14. **Odds are reachable before purchase**, from the CAPSULES tab and the claw
    prompt, behind a control labelled `DETAILS` or `INFO` — not a bare symbol.
15. **The claw's capsule row links to the capsule odds** rather than presenting
    "a capsule" as a terminal outcome.

**Store regression**

16. **No store item mentions capsules, tickets, the meter, luck, odds or
    rarity** — all 11 passes and all 9 products, in-game text and dashboard
    text. Currently clean; this is the check that keeps it clean.
17. **COIN JAR still absent everywhere** until its id is filled in
    (`productId = 0` → hidden by `:590`), and the COINS tab still shows 3 rows.

---

## OPEN QUESTIONS FOR THE HUMAN

Money and risk-appetite calls only. Everything else above is a recommendation
with arithmetic behind it.

1. **Flip `Config.CapsulesArePaid` to `true` — yes or no, and when?**
   It is factually true today and it is the honest reading of Roblox's
   definition. The cost is real: restricted players lose the 400-coin capsule
   and the 40-coin claw, and someone has to build the claw gate and the
   per-outcome odds table. The benefit is that the game stops selling
   undisclosed random items to children. **My recommendation: yes, as the P1
   package, and preferably before phase D adds a fourth door — but it is your
   call on sequencing, and phase D is safe either way.**

2. **The mixed-source question — do you want to ask Roblox before flipping?**
   I could not find an explicit statement on whether a free earned path into a
   generator that is *also* coin-funded must be blocked for restricted users.
   Treatment option 1 ("offering an unpaid, earnable path") strongly implies
   the free door is the remedy rather than the problem, and that is what I have
   recommended. If you would rather be certain, this is a one-post DevForum
   question, and it only blocks the flag flip — not phase D.

3. **Ship COIN JAR at R$99 / 7,500 coins?** My analysis says phase D does not
   threaten it and the R$49→R$249 gap is a real hole (a 5× step with the
   `+25%` badge missing). Three steps in `STORE.md` §4. **Recommendation:
   ship it unchanged.**

4. **Do you accept that R$498 of passes can halve time-to-ticket on the slowest
   whitelisted activity?** I say yes: the ceiling caps it at 10 minutes, the
   fastest meter in the game costs 0 Robux, and the reward is cosmetic. If you
   want strict neutrality instead, the lever is lowering `Ticket` for everyone —
   **never** a meter multiplier, for the policy reason in P4.

5. **`wcaps` keeps counting free tickets?** My number is +51–79 coins/day
   (0.5–0.7% of daily income), lower than the loop designer's worst case
   because the challenge is only drawn 2 weeks in 5. **Recommendation: leave
   it.** Raised because it turns a small sink into a small faucet and should be
   a decision.

6. **What does the 7-day Daily-3 streak give beyond the ticket?**
   `loop.md`'s own open question 4, and it lands in my lane because it is a
   give-away decision. **My recommendation: an `exclusive` outfit or skin.** The
   field already exists (`Config.lua:128-129`: `daisy` "Day 3 login gift",
   `cape` "Day 7 login gift"), it costs zero coins, it is pure expression, it
   cannot be bought — which makes it the single best thing this game gives away
   — and it needs no new art if you reuse the `exclusive` pattern. Do **not**
   make it coins.

---

## SOURCES CHECKED FOR POLICY

I looked these up rather than relying on recall; quotes in Q2 are from them.

- [Paid random items policy guidelines — Roblox Creator Hub](https://create.roblox.com/docs/production/monetization/paid-random-items)
- [Clarifying Requirements for Paid Random Items — Roblox Developer Forum announcement](https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622)
- [PolicyService — Roblox Creator Hub](https://create.roblox.com/docs/reference/engine/classes/PolicyService)
- [Guidelines around users paying for random virtual items — Roblox Developer Forum](https://devforum.roblox.com/t/guidelines-around-users-paying-for-random-virtual-items/307189)

**What I could not confirm, stated plainly:** (a) no effective date is given on
the policy page itself, though the announcement says "The updates are live
today"; (b) I found no statement resolving the mixed-source case in P3; (c) I
found no under-13-specific paid-random-item rule beyond what
`ArePaidRandomItemsRestricted` already encodes (it is described as derived from
geolocation, age group and platform). Where I was unsure I have said so rather
than asserting, because getting this wrong is worse than flagging it.

---
---

# ADDENDUM A — capsule contents are not cosmetic

Written 2026-09-21, same day, after the coordinator flagged that all three specs
on this feature family (theirs, the loop designer's and mine) asserted capsule
characters are cosmetic. **They are wrong and so was I.** I verified every claim
below in code rather than taking it from a spec, which is what I should have done
the first time. I approved "cosmetic" twice — once by reading
`Config.Characters` and concluding there was no gameplay field, which is true of
that table and irrelevant, because the passives live in a **second table keyed by
the same ids** 300 lines further down.

## A0. What I verified, and where

| Fact | Where | Verified how |
|---|---|---|
| **All 15 capsule characters carry a gameplay passive** | `Config.Passives`, `Config.lua:409-425` (the `Config.Passive()` accessor is `:426-428`) | Read the table. 15 keys, one per `Config.Characters` id. |
| **Golden's is `coin = 2` — "Every coin is worth double."** | `Config.lua:424` | Read it. |
| It is **wired, not vestigial** | `SminskiRunner.client.lua:360` (the local), `:433` (`passive = Config.Passive(data.EquippedCharacter)` on every run reset), and **15 read sites**: `:393, :575, :576, :587, :691, :1305, :1323, :1544, :1937, :1992, :2000, :2050, :2057, :2065` | Grepped `Config\.Passive|passive\.` across `game/`. |
| The decisive line | `SminskiRunner.client.lua:2000`: `local value = math.floor((c.gold and Config.GoldCoinValue * (passive.gold or 1) or 1) * (passive.coin or 1) * (hasPower("Doubler") and 2 or 1))` | Read it. `passive.coin` multiplies every coin pickup's value. |
| **Run coins land in the same wallet the city spends** | `award()` at `SminskiServer.server.lua:411`; `d.Coins += coins` at **`:431`** | Read it. |
| The server clamp **permits** the doubling | `:419`: `local maxCoins = distance * 0.35 * 2 + 50 -- dense trails, 2x powerup` | Read it. The `* 2` headroom is commented as being for the Doubler powerup. |
| Pass multipliers stack **on top** of the passive | `:429`: `coins = math.floor(coins * passCoinMult(s))`, applied to the already-doubled client total | Read it. Golden × VIP × 2x COINS = **×5** on run coins. |
| **Dog Park is clean** | `Park.lua` — **zero** matches for `passive` / `Config.Passive` / `EquippedCharacter` | Grepped. `Config.lua:512-513`'s claim that nothing is pay-to-win against other players in Dog Park is **true**, for passes *and* passives. |
| **There are two all-time cross-server leaderboards** | `LB_DEFS`, `SminskiServer.server.lua:250-253`: `distance` ("best single run, metres") and `wins` (Dog Park). `lbSubmit` at `:263`. Submitted at **`:441`** (distance) and `:1271` (wins). `Tour.lua:50` calls it "HALL OF FAME … across every server". | Read all of it. |

The coordinator's account is accurate in every particular. I have nothing to
correct in it and one thing to add (A2).

## A1. Q1 — the corrected pay-to-win verdict

**Verdict: yes, this is pay-to-win. It is a pre-existing violation of the
project's rule, it exists independently of phase D, and phase D neither creates
nor materially worsens it — but phase D does change who ends up holding it.**

I agree with the coordinator that it is pre-existing. The live chain is:

```
Robux  ->  coin bundle (3 live products)  ->  400-coin capsule roll
       ->  2% Golden  ->  permanent x2 on every coin in every run
       ->  d.Coins, the same wallet the city spends
```

Every link was live before phase D was specced. The violation dates from
whenever the coin bundles went live, not from this feature.

**How much is being sold.** `Config.Passes:518-519`: 2x COINS is **R$399** with
`coinMult = 2`, applied at `passCoinMult` (`:406`) to the run total at `:429`.
Golden's `coin = 2` is applied at `:2000` to each coin's value. **Mechanically
the same factor.** The difference is scope, and I will not overstate it:

- **2x COINS (R$399)** doubles *all* income — runs (`:429`) **and** city
  (`pay()` `:1525`).
- **Golden** doubles *run coin pickups only*. It does not touch city income;
  no city code reads `Config.Passive` (grepped — zero matches in `City.lua`,
  `CityJobs.lua` or the server).

So **Golden is, precisely, the run half of a R$399 pass, granted permanently,
at 2% per 400-coin roll.** That is the honest framing and it is bad enough.

**The cost of buying it.** Expected rolls to Golden = `1/0.02 = 50` = **20,000
coins**. Median = `ln(0.5)/ln(0.98) = 34.3` rolls = **13,720 coins**. p10 =
**5.3 rolls ≈ 2,100 coins**.

| route | coins/R$ | expected | median | p10 (lucky 1 in 10) |
|---|---|---|---|---|
| VAULT R$499 / 50,000 | 100 | **R$200** | R$137 | **R$21** |
| COIN JAR R$99 / 7,500 | 75.8 | R$264 | R$181 | R$28 |

**The capsule machine undercuts the game's most expensive pass by half**, and
one player in ten gets there for about R$21. The variance is the part that
matters for an audience this young: the advertised price of a permanent
economic advantage is a gamble.

### A2. The second violation, which the first pass missed and nobody has named

**The Hall of Fame all-time `distance` leaderboard is purchasable.**

My own lane's rule is explicit: *"Nothing competitive (races, leaderboards,
first-to-find bonuses) may be buyable."* `LB_DEFS.distance`
(`:251`, store `SmiskiRun_LB_Distance_v1`) is an `OrderedDataStore` all-time
cross-server leaderboard on **best single run in metres**, submitted at `:441`.
Survival time *is* distance. And **at least 7 of the 15 passives directly
extend survival**:

| character | rarity | passive | effect on how far you get |
|---|---|---|---|
| **Ghost** | Epic | `startShield = true` | a free Shield powerup fires 2.6 s into **every run** (`:576-579`) |
| **Blush** | Common | `stumble = 0.75` | a side bump costs 28.5 chase instead of 38 (`:1305`) — ~33% more hits before you are caught |
| **Night** | Epic | `regen = 1.2` | chase recovers 2.88/s instead of 2.4 (`:2065`) |
| **Sky** | Common | `gravity = 0.8` | slower fall after a jump (`:1937`) |
| **Mint** | Rare | `power = 1.15` | every powerup lasts 15% longer (`:1323`) |
| **Ember** | Epic | `boost = 1.25` | Zoom Boost 25% longer (`:1323`) |
| **Sakura** | Rare | `heartRegen = 2` | hearts regrow twice as fast on hearts maps (`:2057`) |
| Lavender | Rare | `comboCool = 0.5` | combos decay half as fast (`:2050`) — score, not distance |
| Aqua | Rare | `nearMiss = 2` | near misses count double (`:1544`) — combo, not distance |
| Glow | Common | `magnet = 1.6` | wider pickup radius (`:1992`) — coins, not distance |

**This is a competitive number and it is buyable.** It is a separate violation
from the coin multiplier, it is also pre-existing, and — the part that matters
for A5 — **an earn path does not fix it.** Giving Ghost a 3.5-hour Elo path
does not stop a paying player buying a leaderboard advantage in five minutes.

**Two precisions, so this is not overstated:**

1. **Galaxy's `score = 1.15` does not reach a leaderboard.** `:587` and `:691`
   apply it to the submitted `score`, but `lbSubmit` is only ever called with
   `"distance"` (`:441`) and `"wins"` (`:1271`). Galaxy inflates `d.BestScore`
   only. Contained.
2. **The `wins` board is not purchasable.** `Park.lua` reads no passive, and no
   pass affects Dog Park. On the coordinator's separate note about Dog Park ELO
   being client-farmable: it does not bear on my analysis, because with no
   passive and no pass in play the `wins` board is a **cheating** surface rather
   than a **monetization** one. Leave it with you; the one monetization-relevant
   fact is the negative one, and I verified it.

### A3. A latent bug that bounds the exploit — worth a QA line

`:419` is `maxCoins = distance * 0.35 * 2 + 50`, and the comment says the `* 2`
is for the **Doubler powerup**. Golden's `× 2` at `:2000` is applied to the
*same* reported total. So the headroom sized for a temporary powerup is
consumed by a permanent passive, and **a Golden player who also picks up a
Doubler (×4 on a coin) is silently clamped** — losing coins they legitimately
earned, with no message.

Which way this cuts depends on coin density per stud, which I cannot read off
`World.lua` with confidence and **have not measured**. Two possibilities, both
worth knowing:

- If density is high, the clamp already eats part of Golden's benefit, so the
  real advantage is **less than +100%** — good for the economy, bad as a silent
  penalty on a legitimate player.
- If density is low, Golden's +100% passes through in full and the clamp only
  bites on Golden + Doubler.

**I will not assert which.** It is QA item A-4 below, and it is the measurement
that turns the rest of this addendum's economics from structure into numbers.

## A4. Q2 — does this change the paid-random-items posture?

**Every policy finding in the body still holds. Nothing is withdrawn. Three
things become more urgent and one argument is destroyed.**

**Unchanged.** Roblox's Paid Random Items policy, as I read it on the Creator
Hub page and the announcement, defines a paid random item by **how it is
obtained** — "purchased directly with Robux, or indirectly via in-game
currencies purchased with Robux, that yield a random outcome" — and **not by
what is inside it**. I found no text distinguishing cosmetic outcomes from
gameplay-affecting ones. So:

- **P1 stands.** Coins are sold; capsules and the claw are Paid Random Items;
  `Config.CapsulesArePaid = false` is still factually wrong.
- **P2 stands**, and gains a gap (A6).
- **P3's remedy stands and gets stronger.** Gate the two coin-funded doors,
  leave the currency-free doors open. It now matters more, because the free
  doors are the only non-paying route to a gameplay advantage.
- **N6 stands.** The 240-coin restricted fallback should still be dropped — and
  more firmly: it would deny a restricted player the only free path to a
  gameplay passive and hand them coins instead.

**What becomes more urgent:**

1. **The odds card is disclosing the wrong thing.** `UI.lua:1178-1190` shows
   rarity, member names and a percentage. **The outcome a player actually
   receives is a passive**, and the passive text is only rendered on the
   collection card (`UI.lua:1302`, `:1323`) — i.e. *after* you own it. Under
   "all possible outcomes and the actual numerical odds", the disclosure should
   name what each outcome *does*. **This is free**: `Config.Passives[id].desc`
   already holds the string ("Every coin is worth double."). Add it to each of
   the 15 rows in N2.
2. **The P1 package moves from "should do" to "do before phase D ships."** Phase
   D adds a fourth door onto a machine that dispenses a permanent coin
   multiplier. Shipping a new free door to that is defensible; shipping it while
   the flag still claims the machine is unpaid is not.
3. **`Config.lua:512-513` is now a false comment in a second way.** It says
   "None of them affect Dog Park Survival, so nothing here is pay-to-win against
   other players." True of Dog Park, but it sits above the pass list and reads as
   a general claim, and the `distance` board *is* affected.

**The argument that is destroyed.** `LOOPS.md` §6's exemption — *"Rare-Sminski
collectibles are cosmetic … so they can be generous without touching the coin
economy"* — is **void**. My Q4 leaned on it. The loop designer's D8 leaned on it.
It was the entire justification for phase D's give-away rate. **It has to be
re-argued on its own terms**, and A5 does that.

**One thing I will not assert.** Some jurisdictions treat loot boxes conferring
a *gameplay* advantage differently from purely cosmetic ones. I did not verify
that, it is outside what I checked, and I am not going to guess at it. If the
human wants that assessed it needs someone with actual regulatory advice, not a
designer with a search engine. Flagging it as unknown is the honest answer.

## A5. Q3 and Q4 — the re-run economics, and the number

### Q3: is "commercially safe" still right?

**Yes for phase D. No for the capsule machine, and I never made that claim.**

The 2.14-minutes-per-capsule arithmetic stands and is unchanged. But its
*significance* inverts. It used to be the reassurance ("capsules were never
Robux-gated, so free tickets displace nothing"). It is now also the indictment:
**the game's strongest economic upgrade costs 107 expected minutes of work, or
~R$200 of coins, or R$21 if you are lucky.**

- **COIN JAR displacement: conclusion unchanged.** COIN JAR is not a capsule
  product (its own copy sells a car and a skin), the displacement estimate of
  ~2.5% of coin demand stands, and phase D still supplies capsule capacity at
  4.7× worse than the free coin route. **Ship COIN JAR at R$99, unchanged.**
- **A new commercial finding that is worse than anything phase D does:** the
  capsule machine **cannibalises 2x COINS (R$399)**, and always has. A player
  who wants doubled run coins can pay R$200 expected for the run half instead of
  R$399 for the whole thing — and 10% of them pay R$21. That is an argument for
  changing the passive, not for changing phase D.

### Q4: does phase D make it better or worse?

**Better on net, but by less than it looks, and worse in one respect that the
coordinator's read does not capture.**

**Better:** phase D adds a second currency-free path to a gameplay advantage.
That is the direction the project rule wants.

**But the marginal improvement is small, because a free path already existed and
was faster.** Same structure as my Q1 finding:

| route to Golden | cost | time |
|---|---|---|
| free, coins (already shipped) | 20,000 coins expected | **107 min** of paced work |
| free, phase D tickets | 50 tickets expected | **8.3 h** of meter |
| Robux, VAULT | R$200 expected | minutes |

Phase D's free path to Golden is **4.7× slower** than the free path that already
existed. So as a *remedy*, phase D adds very little.

**Worse, in one specific and quantified respect: phase D converts an opt-in
purchase into a passive drip, so far more accounts end up holding Golden.**
Before phase D, a free player got Golden only by *deciding* to spend 20,000
coins on capsules instead of a car. After phase D, tickets arrive whether or not
they were wanted:

`P(no Golden in n rolls) = 0.98^n`, median 34.3 rolls.

| ticket rate | P(Golden) per day | median days to Golden |
|---|---|---|
| 6/day (committed 1 h/day player) | 11.4% | **≈ 5.7 days** |
| 13.3/day (at `DayCap`) | 23.4% | **≈ 2.6 days** |

**Phase D hands the game's strongest economic passive to its most engaged
players inside a week, free, without them choosing it.** Whether that is good
(it is the free path working) or bad (it further devalues 2x COINS and doubles a
cohort's run-coin faucet) is a business decision. It must be *a decision*.

### The number the coordinator asked for

**What a free ticket is actually worth, once passives are counted.**

The minting analysis the loop designer and I agreed on measured **the refund and
ignored the prize**. Corrected:

```
E[ticket] = E[refund]  +  E[passive gained]

E[refund]        = 7.4 (new)  ->  69.6-92.1 (mid-life)  ->  104.1 (complete)
                   bounded above by 104.1, forever

E[passive]       ~ 0.02 x R_future        (for a player who does not own Golden)
   where R_future = the player's REMAINING LIFETIME RUN COIN INCOME,
   because Golden doubles it
```

The refund term is **bounded at 104.1**. The passive term is **unbounded in the
player's lifetime**. Worked example, with the input flagged as unmeasured:

| if a player's remaining run income is | E[passive] per ticket | vs. the 69.6–92.1 refund |
|---|---|---|
| 10,000 coins | 200 | 2–3× the refund |
| 50,000 coins | **1,000** | **11–14× the refund** |
| 200,000 coins | 4,000 | 43–57× the refund |

**So: the loop designer and I agreed a ticket mints 69.6–92.1 coins. Corrected,
a ticket is worth 69.6–92.1 coins plus a 2% lottery on a permanent +100%
run-income multiplier — and for any account that plays enough for the doubling
to matter, the second term dominates by an order of magnitude.**

`R_future` is **not measured and cannot be** — there is no telemetry in `game/`
and I have no run-coins-per-hour figure. The illustrative rows above are
illustrative. **The structure is the finding, not the coefficient**: one term is
capped, the other scales with how long the player stays, and the give-away was
justified on the capped one.

Three smaller economic passives, for completeness, all real and all minor:
**Peach** `gold = 1.5` → +10.2% expected coin value (gold coins are 2.5% at
`GoldCoinValue = 10`, so `0.975 + 0.025×15 = 1.35` vs `1.225`); **Lemon**
`luck = 1` → gold chance `0.025 → 0.037` (`World.lua:1259`) = +8.8% coin value,
**plus a free level of the `Luck` upgrade that costs 400 coins** (`Config.lua:213`);
**Cocoa** `startCoins = 25` → 25 free coins per run (`:575`).

**Does this change the 21.5% give-away ratio?** No — that was computed in
sticker coins and is unchanged. What changes is its *meaning*: 21.5% of income
in "cosmetic sticker value" was an acceptable number for costumes. For a 2%
lottery on a permanent multiplier, the sticker framing is no longer the right
measure at all, and I do not have a better one without telemetry.

## A6. Q5 — does the earn path fix it? Blunt answer

I read `docs/specs/earned-skins/loop.md`. It is a good spec and its coverage
rule (D1) is the right remedy **for the policy problem**. It does not fix the
pay-to-win problem, and I want to be blunt about why, because its own open
question 1 invites exactly this answer.

**No. It softens it. It cannot fix it, because it does not touch what is
broken.**

The earn path's premise is *"no cosmetic may be obtainable only from a random
machine"*, and it gives Golden a ~10-hour, ≥21-calendar-day capstone. That
genuinely delivers Roblox treatment option 1 and it genuinely delivers
provenance. But the pay-to-win problem is not **"Golden is only obtainable
randomly."** It is:

> **A permanent +100% coin multiplier is purchasable at all.**

A parallel earn path leaves the purchase completely intact:

| | paying player | free player, via the earn path |
|---|---|---|
| cost | ~R$200 expected, R$21 at p10 | ~10 hours of city work |
| **wall-clock floor** | **minutes** | **≥21 calendar days** (the `ChalDays` gate, which the spec correctly says no amount of play removes) |

**The earn path raises the free player's ceiling. It does not lower the paying
player's advantage, and it does not close the speed gap — it widens it**, because
the calendar gate is a hard floor on the free route and there is none on the
paid route. The loop designer's framing — *"strictly less pay-to-win than the
status quo"* — is **true and insufficient**. Less is not none. The project rule
is "Never sell winning", not "sell winning, but also give it away eventually".

**And it does nothing at all for A2.** Ghost, Blush, Night, Sky, Mint, Ember and
Sakura remain purchasable advantages on an all-time cross-server leaderboard
whether or not they are also earnable in 3.5 hours. **An earn path cannot
un-buy a competitive advantage.**

### So what would fix it

The coordinator asked me not to design the fix unless the answer to (5) is that
no earn path can fix it. It is, so here are the directions with their
invasiveness. **`Config.Passives` is `server-engineer`'s file, nothing is
decided, and I am naming options, not designing one.**

1. **Make the `distance` leaderboard passive-neutral** — fixes A2 only, smallest
   change, highest ratio of value to risk. Either skip `lbSubmit("distance", …)`
   (`:441`) for runs where a survival passive was active, or submit a
   passive-neutral figure. Does not touch the economy at all.
2. **Neutralise `Secret.coin = 2` specifically** — fixes the economic half, and
   it is **one field on one line** (`Config.lua:424`). Either drop `coin = 2`
   (Golden keeps its look — it is already visually the trophy, `metal = true`,
   `Config.lua:95`), or swap it for an effect that reaches neither the wallet nor
   a leaderboard (`score`, as Galaxy already does — verified contained in A2).
   **This is where I would start**, and it is the cheapest meaningful fix
   available anywhere in this review.
3. **Remove the purchase rather than the power** — make capsules ticket-only, no
   coin price. Most invasive: deletes a 400-coin sink, changes `OpenCapsule`, the
   shop card and the claw, and it makes the odds-disclosure obligation vanish
   (nothing purchasable, nothing to disclose). Clean in principle, expensive, and
   it throws away a working sink. **Not recommended.**
4. **Accept it and rewrite the rule.** The honest fourth option: the human
   decides Sminski City does sell a coin multiplier and a leaderboard edge.
   Then `Config.lua:512-513`'s comment, the project brief's no-pay-to-win rule
   and `STORE.md` all need to say so. I would rather be told this than have
   three specs keep asserting "cosmetic".

Options 1 and 2 together are small, independent, and between them close both
violations without touching phase D, the earn paths, `rollCapsule`, or any
shipped price.

### One correction I owe: my N3 outfit count was wrong

The loop designer caught it and is right. The claw's filter is
`price > 0 and price <= 1000 and not exclusive` (`:1763`). I read
`Config.Outfits` only as far as line 130 and counted **17**. The table runs to
`:143` and the correct count is **26** (bow, headband, sprout, nightcap, tie,
scarf, party, towel, chefhat, catears, flowers, santa, backpack, shades, beanie,
bunny, frog, cherries, starclips, heartspecs, bearears, lollipop, strawberry,
sunhat, duckfloat, bee).

**Consequence for the disclosure table in N3**, which is worse than a count
fix: the claw picks **uniformly from the eligible outfits you do not own**
(`:1761-1766`), so the per-outfit odds are `8% ÷ (eligible unowned)`, ranging
from **0.31%** (26 unowned) to **8.00%** (1 unowned). The outfit branch is
therefore **fully state-dependent per player**, not just in the empty-pool edge
case I flagged. A static table cannot be correct for it. Either disclose the
branch as "8% — an outfit you don't own yet, drawn evenly from the N you are
missing", with N live, or enumerate all 26 with live per-item percentages. The
first is honest, cheaper and more readable; N3's four-decimal arithmetic should
be replaced with it.

## A7. Does phase D need to wait?

**My honest answer: phase D can be built and ship. The passive decision cannot
wait for it, and I am escalating rather than resolving it.**

- **Phase D does not create either violation** and does not measurably worsen
  them per roll.
- **But phase D's own specs justify the give-away on a premise that is false**,
  and phase D delivers Golden to committed daily players in ~6 days without
  their choosing it (A5). So the give-away *rate* and the passive are one
  decision, exactly as the give-away rate and the COIN JAR price were.

**Recommendation, in order:**

1. **Strike "capsule characters are cosmetic" from all three specs** before
   anything ships. I have done it in mine (the banner and two inline
   corrections); `daily-capsule/loop.md`'s D-table row and `LOOPS.md` §6's
   exemption both still assert it.
2. **Decide on options 1 and 2 in A6** — the human's call, and both are small.
3. **Then tune phase D's give-away rate**, because `Ticket` and `DayCap` mean
   something different if a ticket carries a 2% lottery on a multiplier than if
   it carries a costume.
4. Phase D can be **built** in parallel with all of this. Nothing in its
   implementation changes based on the outcome.

**This is a human decision and it is above my lane.** The coordinator invited
that finding and it is the right one.

## A8. QA SHOULD CHECK — additions

Numbered A-n to sit alongside the 17 in the body.

**A-1. Golden actually doubles run coins, end to end.** Equip Golden, run a
fixed seeded route collecting a known number of coins; repeat with Glow.
Reported `stats.coins` must be **2.0× within rounding**, and the wallet delta
after `award()` must follow. **This is the test that proves or disproves the
whole addendum** — if it does not double, I am wrong again and I want to know.

**A-2. Golden stacks multiplicatively with the passes.** Golden + VIP + 2x
COINS on the same seeded route: wallet delta must be **≈5.0×** the
Glow-no-passes baseline (`2 × 1.25 × 2`, `:2000` then `:429`). If it is 2.5× or
4×, the stacking is not what `:429` implies and the A1 numbers need redoing.

**A-3. Golden does NOT affect city income.** Equip Golden, do 10 parcels, 10
fares, 10 sweeps, 10 harvests. Base coins and `data.City.meter` must be
**identical** to the same run with Glow. I grepped and found no city read of
`Config.Passive`; this confirms it empirically and bounds the violation to the
runner.

**A-4. The run coin clamp under Golden + Doubler.** On a dense-coin route,
equip Golden, pick up a Doubler, and collect coins to the end. Compare reported
`stats.coins` against `distance * 0.7 + 50` (`:419`) and **report whether the
clamp bit and by how much**. This is A3's open question and it decides whether
Golden's real advantage is +100% or less.

**A-5. The survival passives measurably extend distance.** Ten runs each with
Glow, Ghost (`startShield`), Blush (`stumble 0.75`) and Night (`regen 1.2`) on
the same map. **Report median distance per character.** If Ghost's median is
materially higher, the `distance` leaderboard is purchasable and A2 is proven
with a number rather than a mechanism.

**A-6. Dog Park is passive-free, empirically.** Play ranked rounds with Golden
and with Glow equipped. No coin, survival or score difference. Confirms the
grep and confirms `Config.lua:512-513` for passives.

**A-7. The odds card names each outcome's effect.** Every one of the 15 rows
carries its `Config.Passives[id].desc` string, and Golden's row reads "Every
coin is worth double." A disclosure that lists names and hides effects is the
gap A4 identified.

**A-8. The claw's outfit branch discloses live, not static.** With 26 eligible
unowned, the branch reads 8% split across 26; with 1 unowned it reads 8% for
that one; with 0 it reads as coins. Replaces the static N3 table.

## A9. OPEN QUESTIONS FOR THE HUMAN — additions

Money and rule calls only. These are all above my lane and I am not going to
pre-empt them.

**A-i. Is a purchasable permanent +100% run-coin multiplier acceptable in this
game?** Today it costs ~R$200 expected (R$21 at p10) via coin bundles, versus
R$399 for the 2x COINS pass that does strictly more. If the answer is no, A6
option 2 is **one field**. If the answer is yes, the project's no-pay-to-win
rule and `Config.lua:512-513` need rewriting to say so, and I would want that in
`STORE.md` too. **I cannot make this call and should not.**

**A-ii. Is a purchasable advantage on the all-time `distance` leaderboard
acceptable?** This is the cleaner violation of the two — it is a leaderboard,
the rule names leaderboards explicitly, and A6 option 1 fixes it without
touching the economy. **My recommendation: fix it.** It is the one thing in this
addendum I would push on.

**A-iii. Given A5, do you still want phase D's give-away at ~6 tickets/hour?**
At that rate a committed daily player holds Golden in ~6 days. If the passive
stays as-is, that is phase D distributing a permanent multiplier as a drip. If
option 2 lands first, the question disappears and 6/hour is fine. **The two
decisions are coupled and this is the coupling.**

**A-iv. Do you want the earn path shipped as a pay-to-win remedy, or only as a
policy remedy?** It is a good policy remedy (treatment option 1) and I support
it on those grounds. It is **not** a pay-to-win remedy (A6) and it should not be
signed off as one, or the real problem gets marked closed. The loop designer's
open question 1 asks you to accept it as the former; my answer is accept it as
the former only, and fix the passive separately.

**A-v. Should I have caught this, and does anything else in these specs rest on
an unchecked premise?** Rhetorical, but I mean it as a process point: I read
`Config.Characters`, saw no gameplay field, and wrote "purely cosmetic" —
without grepping for a second table. The check that would have caught it took
one `grep` for `Config.Passive`. I would suggest that any claim of the form "X
has no gameplay effect" requires a grep for X's id across `game/`, recorded in
the spec, before it can be asserted. Three specs and two approvals missed this
one.
