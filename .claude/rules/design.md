# Smiski City Design Rules

## Purpose

Smiski City is a cozy, playful, highly interactive Roblox city built around
a tiny Smiski character living inside a large world.

The visual goal is:

> A premium toy-like 3D world that feels warm, tactile, cute, dense,
> playful, and slightly magical.

The world should feel like a physical miniature city rather than a
generic Roblox map.

---

# Visual Identity

## Shape Language

Prefer:

- rounded edges
- soft corners
- chunky silhouettes
- simple readable forms
- slightly exaggerated proportions
- soft bevels
- friendly shapes
- large readable details

Avoid:

- aggressive sharp geometry
- overly realistic architecture
- excessive tiny details
- gritty realism
- photorealism
- overly complex silhouettes

Objects should still look good when viewed from a distance.

---

# Scale Philosophy

The Smiski is intentionally very small compared to the environment.

The city should feel oversized from the player's perspective.

A bench should feel like something the Smiski can climb onto.

A curb should feel like a meaningful height difference.

A staircase should feel physically traversable.

The world should communicate:

> Tiny character. Big city.

Do not scale objects simply to make development easier.

---

# Materials

Materials should generally be:

- soft
- matte
- slightly rough
- colorful
- clean
- simplified

Avoid excessive:

- metallic surfaces
- glossy plastic
- photorealistic reflections
- noisy textures
- grunge
- dirt
- scratches

Use physically believable materials while keeping the stylized toy-like
appearance.

---

# Color

Primary palette:

- soft greens
- cream
- warm white
- pastel blue
- soft yellow
- pink
- muted orange
- warm brown
- charcoal accents

Saturated colors should be used as accents rather than covering the entire
environment.

---

# Lighting

Lighting is **natural first**. The world is stylized; the light that falls on
it is not. A beautiful sunny day in a stylized city -- never a glowing
fantasy city.

Daytime:

- natural sunlight with a real direction
- honest, soft-edged shadows with actual depth
- moderate saturation and readable colour
- a blue sky and believable exposure
- atmospheric haze for depth, so distance reads

Do not:

- push ambient so high that shadows flatten out
- put a cream or white filter over the frame with ColorCorrection
- let bloom catch ordinary surfaces (keep its threshold high)
- make windows glowing rectangles in daylight
- make grass fluorescent or streets near-white
- make every surface emissive

Emissive materials are for signage, neon and genuine light sources after
dark. They are not a substitute for lighting.

Evening:

- warm windows
- street lights
- colorful signage

Night:

- deep blue environment
- warm interior lighting
- colorful neon accents
- glowing signs

Avoid making the entire city emissive.

---

# Detail Hierarchy

Every asset should have:

1. Strong silhouette
2. Large recognizable forms
3. Medium-scale details
4. Small environmental details

Do not add geometry simply because more polygons are possible.

Detail should communicate function, scale, or personality.

---

# Interaction First

Whenever possible, design assets around interaction.

A bench should have:

- SeatPoint
- optional HandPoints
- optional FootPoints

A ladder should have:

- HandPoints
- FootPoints

A railing should have:

- HandPoint

A door should have:

- InteractionPoint

An object should be designed with the Smiski's physical body in mind.

---

# Consistency

New assets should look like they belong to the same world.

Do not introduce:

- different rendering styles
- dramatically different proportions
- realistic assets next to toy-like assets
- inconsistent bevel sizes
- inconsistent material roughness

When uncertain, inspect existing approved assets before creating a new visual language.
