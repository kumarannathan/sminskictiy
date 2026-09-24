# Performance Rules

## Philosophy

Smiski City is dense and highly interactive. Density is the point, so
performance must be planned rather than fixed at the end.

Performance is priority 5 in the project's design priority list: above
detail, below character readability, physical interaction, visual
consistency, and silhouette.

Never sacrifice the character's physical interaction system for visual
detail — and never sacrifice it for a performance shortcut either.

---

# Polygon Budget

Polygon count should follow the asset category:

- Hero assets: the highest budget, justified by screen presence.
- Supporting assets: moderate, reused heavily.
- Background assets: highly optimized simplified geometry.

Rules:

- Do not increase polygon count simply to make an asset appear more detailed.
- Detail must communicate function, scale, or personality.
- Silhouette gets the geometry. Hidden edges do not.
- Remove hidden, internal, and duplicate geometry before export.

---

# Instancing and Reuse

Reuse is the primary performance strategy.

- Build from modular kits and instance them.
- Prefer a small number of strong base assets with controlled variants over
  many unrelated unique meshes.
- Vary through material, color, and layout rather than new geometry.

---

# Textures

- Texture resolution should match the asset's on-screen size, not its
  importance to the artist.
- Share materials and atlases across an asset family where possible.
- Avoid noisy, high-frequency textures — they cost memory and fight the
  stylized look.

---

# Collision Cost

Collision is a performance system, not only a gameplay system.

- Use simplified collision geometry.
- Disable collision on small decorative details.
- Do not use render geometry as collision geometry on dense props.

---

# Streaming and Level of Detail

- Assets must read correctly at distance — strong silhouettes are both an
  art rule and a LOD strategy.
- Background and skyline elements should be simplified aggressively.
- Group assets by area so streaming can unload coherent regions.

---

# Lighting Cost

- Keep dynamic lights intentional and limited.
- Prefer warm windows, street lights, and signage as accents over many
  small lights scattered through the map.
- Avoid making the entire city emissive.

---

# Measuring

Do not guess.

- Test in-game, at Smiski eye level, in the dense areas — not in an empty
  baseline place.
- Test day, evening, and night lighting.
- When a change is made for performance, verify it actually helped before
  keeping it.
