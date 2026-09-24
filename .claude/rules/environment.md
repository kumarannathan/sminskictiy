# Environment Design Rules

## Modular Construction

The city should be built primarily from modular systems.

Create reusable:

- road pieces
- sidewalks
- curbs
- buildings
- windows
- doors
- storefronts
- awnings
- signs
- street furniture
- vegetation

Do not individually model every building unless it is a hero location.

---

# Building Design

Buildings should be constructed from reusable components.

Example:

Building
├── Ground Floor
├── Upper Floors
├── Windows
├── Storefront
├── Roof
├── Signage
└── Decorations

Create variations through:

- material
- color
- window layout
- storefront
- signage
- height
- roof
- props

---

# Downtown

Downtown should feel dense but readable.

Include:

- major intersection
- storefronts
- café
- apartments
- office towers
- park
- subway entrance
- parking
- sidewalks
- alleys
- rooftop access
- interactive street objects

Every area should provide opportunities for:

- walking
- jumping
- climbing
- sitting
- reaching
- collecting
- jobs
- social interaction

---

# Player Scale

Always evaluate the environment from Smiski eye level.

A building may look correct from an aerial camera but completely wrong
from the player's perspective.

Test:

- ground level
- sidewalk
- stairs
- rooftop
- interior
- sitting position

---

# Density and Sightlines

The city must feel enormous because you cannot see all of it -- not because
the map is big. Do not solve emptiness by enlarging the map. Make it denser.

The test: standing anywhere, there should be something worth looking at
within roughly 20-50 studs, and the far edge of town should not be visible.

Rules:

- Buildings meet the pavement. A road should be followed by a sidewalk and
  then a building face -- never by a field of grass.
- Blocks present a continuous street wall. Towers rise *behind* a storefront
  podium; they do not stand alone in an open lot.
- Break every long sightline deliberately, with mid-rise buildings, corners,
  trees, signage, parked vehicles, bridges or elevation.
- Mixed heights. Mostly 3-8 floors, occasionally 10-15, rarely a landmark
  tower. Not every building is a skyscraper.
- Atmospheric haze is a design tool: it fades distance and hides the map edge.

Ask of every view: "what is around the next corner?" -- not "can I see the
whole city from here?"

---

# Every Street Earns Its Place

No decorative streets. Every block carries something to do -- a shop, a job,
a collectible, an NPC, a destination.

Buildings carry metadata rather than being scenery:

```text
name · btype · district · shop · job · interior · npc · collectible
```

Register destinations in a lookup (`Build.destinations`) rather than
hard-coding positions, so activities added later attach to the world
automatically instead of needing new geometry.

---

# Districts

Districts should be recognizable and transition into one another naturally:
downtown, residential, shopping, waterfront, industrial, entertainment,
financial, campus, park.

Each needs a landmark that players navigate by without opening the map --
a clock tower, a plaza, a station, a bridge, a wheel.
