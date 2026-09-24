# Repo setup and the source-of-truth rule

## What owns what

| Thing | Lives in | Notes |
|---|---|---|
| Every script we write | `game/*.lua` | **This repo is the source of truth.** |
| 3D assets | `art/blender/*.py` | Re-runnable code, per `.claude/rules/blender.md` |
| Geometry, terrain, the Workspace tree | **the place file only** | Not in the repo, not reproducible from it |
| Third-party scripts | `vendor/` | Reference copy; Rojo does not sync it |
| Uploaded asset ids | `game/Art.lua` | Names → `rbxassetid://` |

The place file is gitignored (`*.rbxl`) because it is a 26 MB binary that
merges badly. The working copy lives outside the repo.

## The rule that matters

**The repo is the source of truth for scripts. The place is the source of
truth for the world.** Neither can rebuild the other on its own.

This broke once already: work was done in Studio and the place ran two days
ahead of the repo, so `UI.lua`, `City.lua` and a whole new `CityMinimap.lua`
existed only inside the place. Anything written against the repo in that window
would have been written against dead code.

If you edit scripts in Studio rather than here, **recover them before doing
anything else** (see below).

## Toolchain

```bash
aftman install      # rojo 7.7.0
brew install lune   # 0.10.x -- reads .rbxl files
```

Lune is not in `aftman.toml` on purpose: aftman wants an interactive trust
prompt the first time it sees a tool, which a scripted shell cannot answer.

## Getting changes into the game

**With Studio open** — Rojo serve, which replaces the HTTP loop in
`game/_sr_sync.lua`:

```bash
rojo serve
```

Then Connect in the Rojo Studio plugin. Every save in `game/` lands in Studio
live. A new module must be added to `default.project.json` (and, while the old
path still exists, to the list in `game/_sr_sync.lua`).

**Without Studio** — build and verify:

```bash
rojo build -o /tmp/check.rbxl
```

This catches a broken project tree in a couple of seconds. **It is not a
publishable place**: it contains the scripts and nothing else — no geometry,
no terrain, no `vendor/` — so it is about 885 KB against the real 26 MB.
Publishing headlessly would need Open Cloud *and* a full place to publish.

There is also a balance checker that runs without any Roblox tooling:

```bash
python3 art/tools/luacheck_balance.py game/*.lua
```

## Recovering source from a place file

When Studio has got ahead of the repo:

```bash
lune run tools/dump_place.luau ~/Downloads/sminskicity.rbxl /tmp/place
cat /tmp/place/_manifest.txt          # every script, by full path and size
diff /tmp/place/<Full__Path>.lua game/<Module>.lua
```

`_manifest.txt` sorts by size, which makes a changed module obvious at a
glance. Reconcile by hand — do not copy the whole dump over `game/`, because
the repo legitimately holds things the place does not (docs, `art/`, and any
work done here since the last sync).

## Known loose ends

- **`SmiskiRunner.client.lua` in the repo root** is a 53 KB ancestor of
  `game/SminskiRunner.client.lua` (100 KB) from when the game was called
  Smiski Escape. It is not in the place and nothing reads it.
- **`game/_sr_sync.lua`** is the old HTTP sync. Rojo replaces it; it is kept
  until Rojo has been used in anger a few times.
- **Nothing was ever committed** before this baseline, so `git show :<file>`
  was returning blobs several days stale. Commit regularly now.
