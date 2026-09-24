# Roblox Studio Rules

## Role of Studio

Roblox Studio is the integration environment, not the modeling environment.

Studio owns:

- placement
- collision
- interaction setup
- physics
- lighting
- streaming
- gameplay scripting
- final runtime testing

Studio does not own the original geometry. If a mesh is wrong, fix it in
Blender and re-export. Do not patch geometry with Studio-side scale hacks.

---

# Import

Before importing, verify in Blender:

- scale against a Roblox reference object
- origin placement
- forward direction
- applied transforms
- material and mesh naming

After importing, verify in Studio:

- physical size matches the intended Blender dimensions
- orientation is correct
- normals read correctly under project lighting
- texture resolution is appropriate
- the asset reads correctly from Smiski eye level

Do not make assumptions about import behavior. Test the actual pipeline.

---

# Collision

Collision is authored deliberately, not left to defaults.

- Use simplified collision geometry, not render geometry, wherever possible.
- Collision should match what the player can physically feel, not every
  visual detail.
- Small decorative details should usually have collision disabled.
- Climbable, sittable, and walkable surfaces must have collision that matches
  the interaction the asset promises.

A surface that looks climbable must be climbable.

---

# Interaction Points

Interaction attachments come from the Blender SOCKETS / IK collections and
must survive export.

Standard points:

- SeatPoint
- HandPoint / HandPoint_L / HandPoint_R
- FootPoint / FootPoint_L / FootPoint_R
- InteractionPoint

Rules:

- Names must match across assets of the same family.
- Points must be positioned for the Smiski's actual body scale.
- Do not add an interaction point an asset cannot actually support.

---

# Modularity

Prefer reusable, instanced modules over one-off duplicated geometry.

- Build streets, buildings, and props from the approved modular kits.
- Create variation through material, color, layout, and props rather than
  through new unique meshes.
- Do not replace a modular system with a one-off implementation.

---

# Naming and Hierarchy

Keep Studio hierarchy readable and predictable.

Carry Blender naming into Studio. Do not leave:

- MeshPart
- Model
- Part
- Union

Group assets by area and function so the place file stays navigable.

---

# Lighting and Materials

Lighting is tuned at the place level, not per asset.

- Do not add per-asset lighting hacks to compensate for a bad material.
- Keep emissive surfaces limited to windows, signage, and intentional
  accents. Avoid making the entire city emissive.
- Material roughness should stay consistent with approved assets.
