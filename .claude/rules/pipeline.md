# Production Pipeline Rules

## The Split

> Claude-built, human-approved.

Claude builds the assets -- procedurally, in Blender, from code that lives in
`art/blender/` -- and a human approves them. Nobody on this project models by
hand as a matter of course. What a human owns is **the decision**: does this
look right, does it feel like Smiski, does it ship.

That split is deliberate about what each side is good at:

- **Claude is good at** rounded, chunky, bevelled, hard-surface geometry; kits
  of modular pieces; consistent variants; exporting, measuring and verifying;
  procedural animation and IK; doing forty trash cans without complaint.
- **A human is better at** taste and likeness ("does it feel like Smiski?"),
  hand-keyed animation charm, sculpted organic form, hand-painted texture.
  Bring one in for those when the procedural result is not good enough --
  that is a judgement call made at review, not a rule up front.

The review gate does not move. Nothing reaches the production map until a
human has looked at it (see `assets.md`); `game/Props.lua` enforces this in
code with `review = "approved"`.

---

# The Pipeline

```text
                 IDEA
                  │
                  ▼
            AI CONCEPT ART
                  │
                  ▼
           HUMAN APPROVES
                  │
          ┌───────┴────────┐
          │                │
       HERO ASSET       PROP ASSET
          │                │
          ▼                ▼
       BLENDER         AI / BLENDER
          │                │
          └───────┬────────┘
                  ▼
            CLEAN / OPTIMIZE
                  │
                  ▼
             ROBLOX STUDIO
                  │
                  ▼
          INTERACTION SETUP
                  │
                  ▼
             FINAL WORLD
```

Every branch passes through **CLEAN / OPTIMIZE**. There is no path from an AI
generator directly into the production map. See `assets.md` for the review
checklist.

---

# Hero Assets

These establish the game, so they get the most care and the most review
rounds. Claude builds them in Blender; a human approves each one, and is
expected to send them back.

- Smiski character: body, rig, hands, feet, face, deformation,
  clothing/accessory system, ragdoll setup, IK attachment points
- The animation + IK system
- Hero building kits (~10-15), as modular pieces -- not finished buildings
- Recognizable interiors players spend time in: cafe, mall, arcade, subway
- Base vehicles (~5-8), then colour and decoration variants
- The road / sidewalk / street-furniture kit
- Materials and lighting
- Major landmarks

---

# Volume Assets

High volume, low individual stakes, heavy variation. Same builder, lighter
review: approve a family from a contact sheet rather than piece by piece.

- Tiny props: books, food, cups, plates, bottles, cans, toys, boxes,
  packages, lamps, clocks, kitchen / bathroom / bedroom / office objects
- Furniture families and their variants
- Plants, trees, bushes, flowers, rocks, grass, garden dressing
- Signs, posters, billboards, menu boards, transit posters, advertisements
- Store products and merchandise
- City clutter: cones, barriers, dumpsters, crates, pallets, trash bags,
  utility boxes, vending machines, shopping bags, shelves, displays
- Concept art and texture exploration

Signage and posters are the single highest-leverage use of AI here: they make
the city feel dense without any 3D modelling.

---

# Never From a Generator

"Claude-built" means built from code that is in the repo and can be re-run,
measured and fixed. It does NOT mean pasted in from a text-to-3D generator.
Generated meshes arrive with unknown topology, scale and UVs, cannot be
regenerated consistently, and are never used for:

- The Smiski
- Hero buildings
- Major vehicles
- Core interactive objects
- Anything requiring exact dimensions
- Anything requiring complex collision
- Anything with many moving parts
- Anything players see constantly
- Anything requiring consistent variants

---

# Never Prompt For a City

Do not ask a generator for "an entire Roblox city", or for a finished
building, street or interior. That returns a pile of inconsistent assets that
costs more to reconcile than it saved.

Prompt for **one asset, in the project's style, against the asset bible**.

Every generation prompt must carry the style block:

```text
SMISKI CITY STYLE

Geometry:   rounded, chunky, simplified, minimal sharp edges
Proportions: oversized objects, tiny characters, slightly exaggerated
             architecture
Materials:  soft matte, subtle roughness, limited reflective surfaces
Colors:     pastel, warm, playful, occasional saturated accents
Lighting:   soft sunlight, warm interiors, colorful nighttime lighting
Detail:     high silhouette readability, medium geometric detail, lots of
            small environmental storytelling
```

`design.md` is the long form of this block and wins any conflict.

---

# Assemble, Don't Model

The city is assembled from kits at runtime, not modelled building by building.

A building is a composition:

```text
House A + Roof 03 + Door 05 + Windows 02 + Fence 04 + Garden 07
```

Six base houses and a handful of parts give dozens of houses. Fifteen hero
building kits give a hundred buildings.

Variation comes from material, colour, layout, signage and props — not from
new unique meshes. Do not replace a kit with a one-off implementation.
