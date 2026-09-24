# Smiski voice lines

The spoken half of `AUDIO_PROMPTS.md`. Everything here is **invented babble,
never English** — a recognisable word on a loop is what makes a player mute
the game.

## The vocabulary

Keep it **small and closed**. A dozen sounds the player hears a thousand times
become a language they feel they understand; forty random noises stay noise.
Toad, Pikmin and Animal Crossing all work this way.

| Sound | Means | Shape |
|---|---|---|
| `mmi` | hello / hey | soft, rising |
| `sumi` | yes / okay / mm-hm | falling, settled |
| `na-ah` | no / oh no | two beats, falling |
| `oko?` | what? / really? | rising, curious |
| `hiyu` | look! / over there | bright, rising |
| `tobi` | go / come on | quick, clipped |
| `nnh` | effort / lifting | closed mouth, strained |
| `wah` | surprise | short, open |
| `ooh` | wonder | long, breathy |
| `hehm` | shy laugh | closed, through the nose |
| `mu…` | tired / bored | long, descending |
| `pih` | small nope / tiny protest | tiny, clipped |
| `dah!` | ta-da / done | bright, one beat |
| `numa` | mine / want / please | soft, pleading |

Two rules that matter more than the list:

- **One or two syllables.** Three is a sentence, and a sentence sounds like
  language nobody speaks. Stay under it.
- **Nobody ever shouts.** Even `wah` and `dah!` are half-volume. The whole
  character is shy.

---

## Ambient chatter (goes in the Veo prompts)

Background pairs. Low, overlapping, never the focus.

```
A: mmi?            B: sumi.
A: oko?            B: na-ah.
A: sumi sumi.      B: mm.
A: hiyu…           B: ooh.
A: mu…             B: hehm.
A: tobi tobi.      B: sumi!
```

Delivery: **half volume, mouth barely open, overlapping, trailing off.** Two
characters who have said this to each other every day for years. If a line
sounds like it's being performed, it's wrong.

---

## Gameplay lines

Recorded as one-shots, triggered in code. Cut **3–4 takes of each** and pick
randomly at runtime — one fixed bark is worse than none.

### Greeting / social

| Trigger | Line | Direction |
|---|---|---|
| Player walks up to an NPC | `mmi!` | bright, rising, quick |
| Player waves | `mmi— hehm.` | greeting then a shy laugh |
| NPC passes another NPC | `mmi.` | flat, barely voiced |
| Player leaves mid-conversation | `na-ah…` | small, disappointed, trailing |
| Emote: happy | `hehm hehm!` | two soft giggles |

### Reward / success

| Trigger | Line | Direction |
|---|---|---|
| Coin pickup | `pih!` | tiny, clipped, almost nothing |
| Collectible / rare find | `hiyu!` | bright, rising, genuinely excited |
| Job complete | `dah!` | one bright beat, then quiet |
| Capsule opened — common | `ooh…` | long, breathy |
| Capsule opened — rare | `wah! …ooh.` | surprise, then wonder settling |
| Level / streak up | `sumi sumi!` | doubled, pleased with itself |

### Effort / movement

Keep these **under half a second**. They fire constantly.

| Trigger | Line | Direction |
|---|---|---|
| Jump | `nnh` | closed-mouth grunt, tiny |
| Big jump / climb up | `nn-hah` | effort then release of breath |
| Landing from height | `whf` | air pushed out, not a word |
| Carrying something heavy | `nnh… nnh…` | rhythmic, slow, put-upon |
| Pushing | `nnnh` | sustained, low |
| Climbing, per reach | `hup` | breathy, barely voiced |

### Failure / trouble

| Trigger | Line | Direction |
|---|---|---|
| Fall / ragdoll | `waaah—` | cut off by the landing, not a scream |
| Get up after ragdoll | `mu…` | long, descending, dazed |
| Fail a job | `na-ah…` | falling, deflated |
| Can't afford something | `pih.` | one tiny protest, then silence |
| Bump into another Smiski | `wah! …hehm.` | startled, then both giggle |
| Stuck / blocked | `oko?` | rising, genuinely puzzled |

### Idle / ambient personality

Fires when the player stands still. **Rare** — no more than once every 20–40s,
randomised, or it becomes a tic.

| State | Line | Direction |
|---|---|---|
| Idle a while | `mu…` | bored, descending |
| Idle longer | `hehm.` | amused at nothing |
| Looking at something big | `ooh…` | long, craning up |
| Sleepy / night | `mu… mm.` | slowing, eyes closing |
| Sleeping | soft breath, no word | just air |
| Noticing the player | `oko?` | rising, curious |

### Shopkeepers / job NPCs

| Trigger | Line | Direction |
|---|---|---|
| Enter a shop | `mmi! hiyu.` | greeting, then "look at this" |
| Offering a job | `tobi?` | rising, inviting |
| Accept a job | `sumi!` | firm, settled |
| Decline a job | `na-ah.` | polite, soft |
| Hand over goods | `dah.` | quiet, businesslike |
| Customer waiting too long | `numa… numa.` | pleading, getting smaller |

---

## Recording notes

Whether these come out of Veo, a text-to-speech pass or a person at a mic:

- **Pitch up, don't speed up.** Pitching a normal voice up 3–5 semitones keeps
  the breath. Speeding it up gives you a chipmunk, which is a different and
  much worse character.
- **Record quiet and close.** A soft voice near the mic reads as *small*. A
  loud voice turned down just reads as far away.
- **Keep the breath in.** The inhale before `ooh` and the air on `hehm` is
  where the whole character lives. Don't gate it out.
- **No consonant attack.** `dah!` starts soft. Anything with a hard front edge
  sounds like a different game.
- **Vary the takes properly.** Three takes of the same read is one bark with
  noise on it. Make one shyer, one bolder, one sleepier.
- **Pitch-shift per character.** One set of recordings, ±2 semitones of random
  `PlaybackSpeed` per NPC, and every Smiski in the city sounds like itself.

## In Roblox

- One `Sound` per line under a `Voice` `SoundGroup`, its own volume slider.
- Pick randomly from a take pool. `PlaybackSpeed` jittered `0.94–1.06` per
  play kills the repetition for free.
- **Debounce everything.** No voice line within ~0.4s of the last one from the
  same character. Two barks on top of each other is instantly cheap.
- Voice is positional — it goes on the character's `HumanoidRootPart`, with a
  tight `RollOffMaxDistance`. A greeting audible across the street is wrong.
- Effort grunts on jump/land fire *constantly*. Play them at maybe 1 in 3, at
  low volume, or they will be the first thing anyone complains about.
