# Asset Production Rules

## Asset Categories

### Hero Assets

Built by Claude in Blender (`art/blender/`), approved by a human before they
ship. Expect several review rounds -- these define the game.

Examples:

- Smiski character
- major landmarks
- major buildings
- vehicles
- subway
- mall
- café
- major props

### Supporting Assets

May be AI-assisted.

Examples:

- furniture
- plants
- food
- decorations
- clutter
- store products

### Background Assets

Can use highly optimized simplified geometry.

Examples:

- distant buildings
- skyline elements
- distant vehicles
- background props

---

# AI Generated Assets

AI-generated 3D assets are starting points, not automatically production-ready assets.

Every AI-generated mesh must be reviewed for:

- topology
- scale
- proportions
- materials
- UVs
- normals
- duplicate geometry
- hidden geometry
- texture resolution
- polygon count
- Roblox compatibility

Do not directly import an unreviewed AI mesh into the production map.

---

# Style Matching

AI-generated assets must match existing approved Smiski City assets.

When generating an asset, reference:

- approved shape language
- approved materials
- approved color palette
- approved proportions

Do not ask AI to independently invent the visual style.

---

# Variations

Prefer generating a small number of strong base assets and creating controlled
variants.

Example:

Bench_A
Bench_B
Bench_C

rather than:

30 completely unrelated benches.

Variants should clearly belong to the same asset family.

---

# Category Reference

Use this to decide who makes a given asset. `pipeline.md` covers the
build/approve split and the review gate; this is the concrete inventory.

## Hero building kits (~10–15)

Downtown tower · apartment · mall · café · arcade · cinema · hotel · grocery ·
toy store · clothing store · bank · police/fire station · subway station ·
city hall · hospital

Each ships as modular pieces, never as a finished building:

```text
Building Kit
├── Ground floor
├── Middle floor
├── Roof
├── Window modules
├── Door modules
├── Sign modules
├── Awnings
├── Balconies
└── AC / vents
```

## Houses (6–10 bases + variant parts)

Bases first, reviewed individually. Roofs, windows, doors, siding, porches,
garages, fences and gardens are variant parts, reviewed as a family.

## Vehicles (5–8 bases)

Taxi · hatchback · sedan · delivery van · bus · subway · bike · scooter

Then colour and decoration variants only. Do not model fifty cars.

## Environment kit

Roads: straight · corner · T-junction · 4-way · roundabout · parking lot ·
alley · crosswalk · sidewalk · curbs · stairs · ramps

Street furniture: traffic lights · street lamps · benches · bus stops ·
mailboxes · trash cans · fire hydrants · planters · newspaper boxes ·
bike racks · road signs

Once this kit exists the city can be assembled quickly. It is the highest
-leverage work after the character.

## Interiors

Places players spend time in get properly built interiors with interaction
points — café (counter, tables, chairs, menu board, kitchen, coffee machines,
food displays), mall (entrance, escalators, stores, food court, fountain,
elevator, signage).
