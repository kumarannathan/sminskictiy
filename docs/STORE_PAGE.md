# Store page copy

For the Roblox experience page. Two versions: the **short** one is what people
actually read, the **long** one fills the description box.

⚠ **Lines marked `[gated]` describe work that is not shipped yet** — see
`docs/RELEASE.md`. Do not publish those until they are true. A store page that
promises a feature the game does not have is the fastest way to earn a wall of
one-star ratings you cannot delete.

---

## Short (the hook — first two lines are all most people see)

> You're a tiny Sminski in a very big city. Get a job, make some money, and
> turn a bare flat into somewhere you actually want to come home to.

---

## Long

```
You're a tiny Sminski in a very big city.

Start with nothing but a bare room and a job you picked on your way in.
Drive a taxi. Run deliveries on a bike. Work the farm out past the edge of
town. Cook in a kitchen, sweep the streets, or buy a shop and let it earn
while you're off doing something else.

Then spend it on something that's yours.

🏠 YOUR OWN PLACE
Buy a flat, pick where in the city it is, and furnish it properly — sofas,
rugs, bookcases, lamps, a bed worth sleeping in. Over fifty pieces of
furniture and no right answer. Bring a friend round and see what they think.

🚕 TWELVE WAYS TO EARN
Taxi, deliveries, farming, cooking, street cleaning, kart racing, and the
businesses you can own outright. Every job has its own rhythm — find the one
you actually like and get good at it.

🌱 THE FARM
Plant, water, fertilise, harvest, and haul it into town to sell. Crops grow
in real time and keep growing while you're offline, so there's always
something ready when you come back.

🎁 SMINSKI CAPSULES
Play, and a capsule charges itself. Open it for a character you haven't got
yet — fifteen to collect, each one with its own look and its own perk. Three
hidden Sminski turn up somewhere new in the city every single day, and
they're the same three for everybody, so finding one is worth telling people
about.

🎃 OCTOBER IS SPOOKY MONTH
The city goes dark for Halloween: jack-o'-lanterns on the pavement, dead
trees, lanterns in the fog, and a dozen seasonal pieces for your flat that
go away again on the first of November. No luck involved — if you play this
month, you can get all of them.

☀️ A CITY THAT KEEPS MOVING
Thirty-minute days, real weather, shops that open and close, streets that
sound different at night. Learn it well enough and you won't need the map.

📖 COLLECTIONS                                                      [gated]
Every cosmetic is part of a set, and every set has one piece that almost
nobody has. Fill the album.

🎡 THE PRIZE WHEEL                                                  [gated]
A real wheel, in downtown, one spin a day.

🤝 TRADING                                                          [gated]
Swap cosmetics with other players.

Built by one person and a lot of Blender. Updates often.
```

---

## Notes for whoever publishes this

**"Twelve ways to earn" is a count that has to be checked.** Seven jobs are
still `soon = true` in `Config.Jobs` (bus, police, construction, fire, grocery,
mechanic, photo). Count what is *playable* on the day you publish and use that
number — the job browser is the first place a player will check you on it.

**Do not write "loot boxes", "crates", "odds" or "chance" into the page as
selling points.** Capsules charge from play. That is both the better pitch and
the thing that keeps the game out of the Paid Random Items rules
(`docs/RELEASE.md` §0).

**The Halloween line is the one with a deadline.** It is only true in October,
and a store page still advertising Spooky Month in November reads as abandoned.
Pull it on the 1st.

**The furniture count is 53 + 12 seasonal** today (`Config.Furniture`,
`Config.Seasons`). "Over fifty" is safe; if the catalogue grows, update it
rather than leaving an undersell in place.

## Thumbnail / icon

The copy above sells a flat you furnish and a city you learn. The images
should show those two things, not a menu. One interior shot with furniture in
it, one street at night with the signage lit, one farm at harvest. Avoid the
screenshot every Roblox life-sim uses — a character standing in an empty road
facing camera.
