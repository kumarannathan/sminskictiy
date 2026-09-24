# Smiski City

## Project

Smiski City is a Roblox social exploration/life-sim experience centered
around a tiny physical Smiski character living in a large interactive city.

## Art Pipeline

The primary 3D pipeline is:

Blender → Roblox Studio

Blender is the source of truth for production geometry, rigging,
skinning, materials, and animation source files.

Roblox Studio is the integration, gameplay, interaction, physics,
lighting, and final runtime environment.

## Design Priority

1. Character readability
2. Physical interaction
3. Consistent visual style
4. Strong silhouettes
5. Performance
6. Detail

Never sacrifice the character's physical interaction system for visual detail.

## Rules

Read the relevant `.claude/rules/*.md` file before making changes
to that area of the project.

Before producing any asset, read `pipeline.md`. Assets are **Claude-built,
human-approved**: built from re-runnable Blender code in `art/blender/`, and
nothing skips the human review gate.

For 3D assets:
- read `pipeline.md`
- read `blender.md`
- read `assets.md`
- read `roblox.md`

For the Smiski:
- read `character.md`
- read `animation.md`
- read `blender.md`
- read `roblox.md`

For environments:
- read `design.md`
- read `environment.md`
- read `blender.md`
- read `assets.md`
- read `roblox.md`

For performance-sensitive systems:
- read `performance.md`

Current scope is the **downtown vertical slice**, not the whole city.
See `docs/ROADMAP.md` before adding content outside it.

Do not create a new visual style without first checking existing
approved references.

Do not replace modular systems with one-off implementations.

Do not make assumptions about Blender or Roblox import behavior.
Test the actual pipeline.
