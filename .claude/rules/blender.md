# Blender Production Rules

## Blender is the Source of Truth

Blender files are the source assets.

Do not treat Roblox Studio as the place where the original model is created.

The normal pipeline is:

Blender
→ cleanup
→ optimization
→ export
→ Roblox Studio
→ collision / interaction setup
→ testing

Keep editable Blender source files.

Never overwrite source files with exported or optimized versions.

---

# Scene Setup

All Blender scenes must use the project's standard Smiski City scene setup.

Use consistent:

- world orientation
- object scale
- origin conventions
- naming
- collection structure
- material naming
- export settings

Do not create arbitrary scene configurations for individual assets.

---

# Units

The project uses Roblox-compatible scale.

Do not arbitrarily scale an asset during export to make it fit.

Maintain consistent dimensions in Blender.

Before exporting, verify the asset against a Roblox reference object.

For FBX exports, use the project's approved Roblox-compatible FBX scaling settings.

Do not introduce per-asset scale hacks.

---

# Object Transforms

Before export:

- Apply scale when appropriate.
- Verify rotation.
- Verify object origin.
- Verify forward direction.
- Verify world position.
- Remove unintended transforms.

Do not leave arbitrary non-uniform scale on production assets.

---

# Origins

Object origins must have a deliberate purpose.

For environmental assets:

- place the origin at the logical placement point
- normally use the bottom-center of the object
- use the ground contact point when appropriate

For doors:

- origin should support the intended hinge/pivot.

For rotating objects:

- origin must be at the intended rotation axis.

For interactive objects:

- origin should make Roblox placement intuitive.

---

# Geometry

Use clean, intentional topology.

Prefer:

- quads
- clean edge flow
- controlled bevels
- simple geometry
- weighted normals where appropriate

Avoid:

- unnecessary subdivision
- dense hidden geometry
- internal faces that cannot be seen
- duplicate vertices
- accidental ngons in deformation-critical areas
- destructive boolean artifacts

Do not increase polygon count simply to make an asset appear more detailed.

---

# Bevels

Bevels are important to the Smiski City visual style.

Use bevels to create soft toy-like edges.

Bevel sizes should be visually consistent across related assets.

Do not make every edge heavily rounded.

Important silhouette edges receive more attention than hidden edges.

---

# Modifiers

Keep modifiers intentional.

Before export:

- verify modifier order
- verify applied/non-applied modifiers
- verify resulting geometry
- remove unnecessary modifiers

Do not apply destructive modifiers until the source asset has been saved.

---

# Collections

Use predictable collections.

Example:

Asset_Name
├── GEO
├── COLLISION
├── RIG
├── IK
├── SOCKETS
├── LIGHTING
└── EXPORT

Not every asset needs every collection.

Do not mix source references with production geometry.

---

# Naming

Use descriptive names.

Examples:

SM_CityBench_A
SM_CityBench_B
SM_CafeChair_A
SM_DowntownBuilding_01
SM_Taxi_A
SM_Tree_Small_01

Avoid:

Cube.001
Plane.043
Object_Final_Final2
Thing
NewMesh

Prefixes:

SM_ = Smiski City asset
CHR_ = character
ENV_ = environment
PROP_ = prop
VEH_ = vehicle
COL_ = collision
IK_ = interaction target
