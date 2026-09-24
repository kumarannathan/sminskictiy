# vendor/

Third-party code that lives in the place file and that **we did not write**.

This is a **reference copy, not the source of truth.** Rojo does not sync it
(`default.project.json` does not map it), and editing a file here changes
nothing in the game.

It is in the repo for two reasons: so a rebuild from scratch knows what has to
be re-added, and so a change to somebody else's asset is visible in a diff
instead of appearing from nowhere.

## movement-system/

A Roblox toolbox movement asset. In the place it sits in `Workspace` as a
model called `Movement System`, whose children are folders named
`Ungroup in <service>` — you drag them into that service and delete the model.
The filenames here keep that structure, `__` standing in for a `/`.

It provides sprint/stamina, crouch, roll, lean, jump-fall-land, footprints,
emotes and a custom shift-lock. That is real gameplay the Smiski depends on,
which is why losing it in a rebuild would not be obvious straight away.

**`.claude/rules/assets.md` applies to this the way it applies to any asset we
did not build**: it arrived with unknown structure and has not been through
review. It works, so it stays for now, but it is not exempt from the rule —
anything in here is a candidate to be replaced by our own implementation.

`Thumbnail [Delete me]` and `Read Me` are the asset's own packaging and should
not be in the published place at all.
