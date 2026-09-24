# Ambient audio prompts (Veo)

Five background audio beds for the city. Veo makes an **8-second video with
native audio** — the video is a throwaway, the audio track is the deliverable.

**Four rules for all of them:**

1. **Every prompt carries the style block**, same as `AD_PROMPTS.md`.
   `pipeline.md` requires it on every generation prompt.
2. **Lock the camera.** A static, locked-off shot. Any camera move makes Veo
   score the shot like a trailer, and a music swell is unloopable.
3. **Say "no music" every time.** Veo adds a soundtrack unless told not to.
   It also burns in subtitles when there is speech — kill both in the negative
   prompt.
4. **Never real English.** The Smiski voice is a soft invented babble. Real
   dialogue is recognisable, and a recognisable line on a 12-second loop is
   the fastest way to make a player mute the game.

## The style block

```
SMISKI CITY STYLE

Geometry:    rounded, chunky, simplified, minimal sharp edges
Proportions: oversized objects, tiny characters, slightly exaggerated
             architecture
Materials:   soft matte, subtle roughness, limited reflective surfaces
Colors:      pastel, warm, playful, occasional saturated accents
Lighting:    soft sunlight, warm interiors, colorful nighttime lighting
Detail:      high silhouette readability, medium geometric detail, lots of
             small environmental storytelling
```

## The Smiski voice block

Paste this into every prompt that has characters talking in it.

```
SMISKI VOICE

Small, soft, breathy, high-pitched — a child's voice at half volume, never
shrill and never squeaky-cartoon. Rounded vowels, soft consonants, words that
trail off. Gentle rising-falling melody like a question that answers itself.

They do not speak English. They speak a soft invented babble — "mmi", "sumi",
"na-ah", "oko", "hiyu", "tobi" — closer to sleepy murmuring than to speech.
Lines are one or two syllables. Nobody shouts. Occasional small breathy
giggle. Think Animal Crossing villager, quieter and shyer.
```

## Negative prompt (paste into Veo's negative field every time)

```
music, soundtrack, score, background music, singing, melody, instruments,
subtitles, captions, on-screen text, watermark, English speech, intelligible
words, narrator, voiceover, announcer, camera movement, zoom, pan, whoosh,
sound effects sting, audience laughter, applause
```

---

## 1. Downtown street — the main bed

Runs under the whole downtown slice. The busiest of the five.

> Locked-off static wide shot of a pastel toy-city street corner at late
> afternoon. Cream, sage and butter-yellow shopfronts meet the pavement, awnings
> out, a glass tower behind. Roughly fifteen tiny rounded green characters walk
> the sidewalk in both directions, two stopped talking to each other near a
> bench, one waiting at a crossing. A small round taxi rolls past in the
> background. Soft sunlight, honest soft-edged shadows, gentle haze down the
> street.
>
> AUDIO: a gentle crowd bed of many tiny soft voices layered at low volume —
> nobody in the foreground, no single voice clear. Soft padding footsteps on
> pavement. A distant muffled toy-car hum and one short soft horn. Faint
> awning flap. Two characters near the bench murmur quietly: *"mmi? na-ah."* /
> *"sumi sumi."* A small breathy giggle far off. No music.
>
> [STYLE BLOCK] [VOICE BLOCK]

## 2. Café interior — warm and close

For the café and the pizzeria. Fewer voices, closer, warmer.

> Locked-off static medium shot inside a small pastel café. A coral counter, a
> chunky rounded espresso machine, three round tables with tiny rounded green
> characters sitting at them, one at the counter waiting. Warm interior light
> against cool daylight through the shopfront window. Steam curling off a cup.
>
> AUDIO: close, warm room tone. A few tiny soft voices in quiet conversation,
> nearer than a street crowd but still not intelligible. Small ceramic clinks,
> a cup set down on a saucer, a short hiss of a steam wand, a low machine hum.
> One character at the counter says softly *"oko… hiyu?"* and another answers
> *"mm-hm."* A gentle breathy laugh. A chair scrapes softly once. No music.
>
> [STYLE BLOCK] [VOICE BLOCK]

## 3. Mall / arcade — bright and busy

The densest, most playful bed. Bigger room, more reverb.

> Locked-off static wide shot inside a pastel shopping mall atrium: a fountain,
> a curved escalator, storefronts on two levels, a row of chunky rounded arcade
> cabinets glowing along one wall. Twenty tiny rounded green characters moving
> through the space, a few clustered at the cabinets. Bright soft lighting, a
> little colourful signage glow.
>
> AUDIO: a big open room with soft reverb. A wide layered bed of tiny voices
> bouncing off hard surfaces. Trickling fountain water underneath everything.
> Soft escalator hum. Sparse blippy toy-electronic arcade beeps — quiet,
> spaced out, never a tune. Distant muffled tannoy in the same soft babble.
> Two characters at a cabinet: *"tobi tobi!"* / *"na-ah…"* then a small
> giggle. No music.
>
> [STYLE BLOCK] [VOICE BLOCK]

## 4. Park — calm and open

The quietest bed. Use it as the contrast against downtown.

> Locked-off static wide shot of a pastel city park: rounded chunky trees, a
> mint-green bench, a curved path, low hedges, a small pond, pastel mid-rise
> buildings visible beyond the treeline. A handful of tiny rounded green
> characters — two on the bench, one on the grass, one walking a small round
> dog. Soft morning sunlight, long gentle shadows.
>
> AUDIO: open, airy outdoor tone with almost no reverb. Soft wind in leaves.
> Small rounded bird chirps, sparse and unhurried. Very distant muffled city
> hum far behind the trees. Occasional soft footsteps on a path. One tiny voice
> says *"mmi…"* quietly and another hums back. One small soft dog yip, far
> away. Long stretches of near-quiet. No music.
>
> [STYLE BLOCK] [VOICE BLOCK]

## 5. Subway station — enclosed and rumbly

The low-end bed. Gives the city vertical variety when a player goes under it.

> Locked-off static wide shot of a pastel underground subway platform: tiled
> cream walls, rounded chunky benches, a curved rounded toy subway train
> stopped at the platform with its doors open, soft strip lighting, a pastel
> transit poster on the wall. Tiny rounded green characters boarding and
> waiting.
>
> AUDIO: enclosed tiled space with long soft reverb and a low constant rumble.
> Layered tiny voices, echoing and washed out. A deep soft air rush as the
> train settles. A gentle two-tone door chime — soft and toy-like, not shrill.
> Distant muffled tannoy in soft babble. Footsteps echoing on tile. One
> character near the doors: *"hiyu! hiyu."* No music.
>
> [STYLE BLOCK] [VOICE BLOCK]

---

## Getting a loop out of an 8-second clip

Generate **3 or 4 takes of each** and keep the one with no music bleed and no
single voice sticking out. Then:

```bash
# 1. pull the audio out of the Veo mp4
ffmpeg -i veo_street.mp4 -vn -ac 2 -ar 44100 street_raw.wav

# 2. make it seamless: 1.5s crossfade of the tail back over the head
ffmpeg -i street_raw.wav -filter_complex \
  "[0:a]atrim=0:1.5,afade=t=in:d=1.5[head]; \
   [0:a]atrim=6.5,asetpts=PTS-STARTPTS,afade=t=out:d=1.5[tail]; \
   [0:a]atrim=1.5:6.5,asetpts=PTS-STARTPTS[mid]; \
   [tail][head]amix=inputs=2[seam];[mid][seam]concat=n=2:v=0:a=1[out]" \
  -map "[out]" street_loop.wav

# 3. Roblox wants ogg or mp3, mono is fine for ambience and half the memory
ffmpeg -i street_loop.wav -ac 1 -b:a 128k street_loop.ogg
```

8 seconds is short for an ambient bed and the ear catches the repeat. Fix it
by layering, not by generating longer: run **two different takes of the same
location at once** with different `TimePosition` offsets and different
`PlaybackSpeed` (0.97 and 1.03). The beat never lines up and the loop stops
being audible.

## In Roblox

- `SoundGroup` per bed, parented under one `Ambience` group, so one volume
  slider controls all of it.
- Ambience is **not** parented to a part unless it is positional. Street/park
  beds go in `SoundService`, crossfaded by district. The arcade cabinets and
  the café espresso machine are positional — those go on the part with
  `RollOffMaxDistance` set tight.
- Crossfade districts over ~1.5s with a `TweenService` tween on `Volume`.
  A hard cut between beds is more noticeable than either bed.
- Keep it quiet. Ambience sits under everything — start at `Volume = 0.15`
  and only come up if it is inaudible at Smiski eye level.
- Test at night too. The street bed at 3am with a full daytime crowd on it
  reads as a bug.
