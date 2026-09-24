# Chat context export — Sminski City

Paste this into a new chat to carry the working context over. Written
2026-09-21. It describes state, not history: what exists, what is verified,
what is open, and the traps that cost time.

---

## Hard rules

- **Never push this project to `yogegr` or anything related to it.** It is a
  separate project. (Also saved in Claude's memory for this repo.)
- `CLAUDE.md` + `.claude/rules/*.md` are binding: assets are Claude-built in
  `art/blender/` and human-approved; never from a text-to-3D generator; scope
  is the downtown vertical slice; test the real pipeline, do not assume.
- Commit or push only when asked. On `main` with everything staged and no
  commits yet.

## The project

Roblox social / life-sim: a tiny Sminski in a big pastel toy city.
Repo: `~/Desktop/SminskiCity`. All game code is Luau in `game/`, synced into
Studio; nothing is edited in Studio directly.

**Sync pipeline:** `python3 -m http.server 8765` running in `game/`, then
`_G.SR_sync()` from the Studio command bar (Edit mode only). Module list is in
`game/_sr_sync.lua`. Stop Play → sync → start Play.

## What is in the build (verified in Play unless marked)

- **City:** streets, 385 lots, landmarks (Mall, City Hall, Fun Park + Ferris
  wheel, Job Center, Slice of Life pizzeria, lake, city gate...), 30-minute
  shared day/weather clock, traffic, houses/apartments, businesses you own.
- **Jobs:** Job Center + browser, 16 careers (5 playable: taxi, delivery,
  cleaner, farmhand, pizzeria cook), Job ELO/ranks, streaks, shifts, paid ELO
  reset. Restaurant framework in `CityKitchen.lua` (5 step kinds + serve).
  Phases 8-13 (bakery/cafe/burger, taxi nav minigame, police, cleaner routes,
  construction) not built.
- **Store:** 11 of 12 products/passes live with real ids in `Config.lua`.
  **COIN JAR (R$99, 7,500 coins) is the one not created** — image ready at
  `art/store/coins2.png`; id 0 is hidden everywhere. See `docs/STORE.md`.
- **Skins:** 15 whole-body skins (`Config.Skins`, builders in `Models.lua`);
  15 capsule characters (`Config.Characters`).
- **Town directory, business card, tabbed SHOP, WORK button** — in `City.lua`.
- **Intro:** `game/SminskiTitle.client.lua` (ReplicatedFirst): 10 loader
  stills × 2s with skip → camera dive → title menu. Menu routing verified:
  START GAME / RESUME and GO TO MY HOUSE enter the game (house teleports to
  your door); WORK / SHOP / SETTINGS open over the menu without diving in.
- **HUD fix (this session):** `City.hudVisible(false)` used to clear its own
  record when called twice (HUD MENU button, then a menu screen), so the HUD
  never came back. Now only the restore clears it. Verified 3 rounds.
- **Short loops / events:** plan in `docs/LOOPS.md`. **Phase A
  (`game/CityEvents.lua`, director + PHONE + FIND) is being built by a
  different Claude session** — its state is whatever that session says, not
  verified here. A LOST PUP event and a PHONE button were visible in Play.

## Marketing material

- `docs/AD_PROMPTS.md` — style block; ad prompts 1-7; the 10 loader plates
  (8); TikTok/Veo prompts (9a scale reveal, 9b day in the city, 9c outfit
  switch, 9d the closer plate, 9e/9f two talking skits using the Veo skin
  references Gold / Lavender / Glow / Ghost / Ninja).
  - Characters have **two small eyes and a tiny smile** — prompts pin the
    face to the references and forbid lip-sync. (An earlier draft wrongly
    said "no mouth"; fixed.)
  - Veo cannot draw the logo or reliable text: composite
    `art/preview/logo_city.png` + "EARLY ACCESS NOW!" + the search line in
    the editor, all in the top half of a 9:16 frame.
- **`~/Desktop/google flow/`** — reference pack for Flow/Veo: logo,
  12 character renders, 23 UI icons, 12 store + 4 pass images, **16 in-game
  city shots (1920×1080, HUD hidden; 12 also as 9:16)**, 2 HUD shots, loader
  plates, key art, the 4 clips, a README on how to use them.
  **`03_skins/` is empty and the shop / work / town screens are not shot** —
  the screen locked, then the user stopped the capture run.
- **Still owed, asked for earlier and never delivered:** 10 experience-page
  image prompts + 5 ad-campaign prompts. Offered: a transparent 1080×1920
  end-card overlay PNG (logo + both text lines).

## Open items

1. **Delete `workspace._RefShots` from the EDIT datamodel.** A temporary
   folder (15 posed characters + 2 slabs at y = 5000) left by the reference
   shoot. It can only be removed when Studio is not in Play, and the other
   session has kept Studio in Play. Do not save/publish the place before it is
   gone. Command bar, Edit mode:
   `local f = workspace:FindFirstChild("_RefShots") if f then f:Destroy() end`
   Everything else the shoot added was client-side and has been removed.
2. WORK button on the left HUD column sits under Roblox's own top-left
   buttons and is mostly covered (seen in `hud_01_on_foot_with_ui.png`).
3. COIN JAR product; job phases 8-13; events phases B-G; gated Premium
   neighbourhood; rail spur to the airport.
4. Driving after the title handover was reasoned about, not re-tested with a
   real car (no dev hook for entering one).

## Traps that cost time — read before debugging

- `RunService:BindToRenderStep` **returns nil.** It is not a connection; keep
  your own flag and unbind by name.
- `UIStroke.Transparency` is separate from `TextTransparency` — fade both.
- Luau `local` declared *below* the function that reads it is nil inside that
  function. Six bugs of this shape; mutable flags now live at the top of
  `SminskiTitle.client.lua`.
- `streamStep` swallows a block builder's error into a `warn` and marks the
  block done — a missing building is usually a swallowed error.
- `Places.cityLots()` is **append-only**; lot indices are saved server-side.
- City gameplay state is **per player** (`s.city`), not shared.
- `IgnoreGuiInset = true` makes `AbsolutePosition` inset-relative (the inset
  was 58px here) — a negative Y is not necessarily off-screen.
- The MCP `execute_luau` VM is separate from the game's: `_G` is empty there
  and `require(City)` returns the factory, not the live table. Reach the game
  through `PlayerScripts.SminskiDev` (BindableFunction:
  `dev:Invoke("city", "sky" | "store" | "job" | "town" | "biz" | ...)`) and
  the `ReplicatedFirst` handshakes (`SR_ShowMenu` event, `SR_TestPick`
  BindableFunction — it now routes exactly like a click).
- **Screenshots:** MCP `screen_capture` works in Edit only and returns no
  file; in Play it is magenta. What works: `screencapture -x -o -l <windowId>`
  on the Studio window (id via a small Swift `CGWindowListCopyWindowInfo`
  script), crop the viewport, and sync shots to a Luau pose schedule on the
  shared wall clock. It fails while the Mac's screen is locked.
- `dev:Invoke("city", "sky", 14.5)` forces the hour, `"clear"` the weather,
  `false` clears both.
- **Two sessions on one Studio collide**: the other one restarts Play to
  test, which wipes client-side state mid-run; and teleporting the character
  or forcing the sky pollutes its tests. Coordinate before driving Studio.
