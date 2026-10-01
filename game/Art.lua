-- Art (ReplicatedStorage.SminskiShared.Art)
-- Uploaded image ids for the UI art.
--
-- Icons and nine-slices are PIXEL art from `art/pixel/pixel_ui.py` (Pillow,
-- authored one pixel per pixel). They are NOT rendered in Blender: rendering
-- geometry and downscaling it produces the soft mush that
-- ResampleMode = Pixelated exists to prevent.
--
-- Re-run the script, re-upload, then update these ids.

local Art = {}

Art.logo = "rbxassetid://86239266364583"
Art.hero = "rbxassetid://103450079715685"

-- tintable surfaces: base (tint with ImageColor3) + untinted gloss overlay
-- PIXEL NINE-SLICES. Native sizes are deliberately TINY -- 24 and 32 px --
-- because Roblox scales them with nearest-neighbour and a 1px line in the
-- source lands as a crisp 4px line on screen at SliceScale 4 (UI.T.border).
-- The old art was 512x160 and downscaled, which is what made every edge
-- disagree about its own thickness.
--
-- NO `gloss`. The old set shipped a second untinted overlay to fake a
-- specular sheen, which is a 3D idea; the art now carries its own 1px
-- highlight along the top inside edge. UI.skin treats gloss as optional, so
-- an entry that still has one keeps working.
--
-- `pill` and `disc` share an id on purpose: both are a 24px square at full
-- corner radius, so they are byte-identical and Roblox deduplicated them. A
-- pill is just that circle nine-sliced and stretched wide.
Art.ui = {
	pill = { base = "rbxassetid://88020931290462", size = Vector2.new(24, 24), corner = 12 },
	key = { base = "rbxassetid://133814936064778", size = Vector2.new(24, 24), corner = 6 },
	card = { base = "rbxassetid://104857404775729", size = Vector2.new(32, 32), corner = 8 },
	disc = { base = "rbxassetid://88020931290462", size = Vector2.new(24, 24), corner = 12 },
}

Art.icons = {
	bag = "rbxassetid://75166212245448",
	bolt = "rbxassetid://89786936433804",
	capsule = "rbxassetid://86248755938322",
	chart = "rbxassetid://117443758026393",
	clock = "rbxassetid://78008761472059",
	coin = "rbxassetid://92004397180565",
	crown = "rbxassetid://118075418122290",
	dog = "rbxassetid://70608985979986",
	friends = "rbxassetid://79778417049972",
	gear = "rbxassetid://98610968076801",
	heart = "rbxassetid://98903381055834",
	hourglass = "rbxassetid://85704161526872",
	house = "rbxassetid://110048869292539",
	lock = "rbxassetid://98364052009349",
	magnet = "rbxassetid://124521666191803",
	paw = "rbxassetid://88699596402893",
	pin = "rbxassetid://87141795618138",
	play = "rbxassetid://88695453713587",
	shield = "rbxassetid://123541362398182",
	shirt = "rbxassetid://86580374971699",
	star = "rbxassetid://117058200627116",
	trophy = "rbxassetid://94411923660026",
	x2 = "rbxassetid://128721496686306",
}

-- which icon each powerup uses
Art.powerup = { Magnet = "magnet", Doubler = "x2", Shield = "shield", SlowTime = "hourglass", Boost = "bolt" }

-- glossy portraits of every Sminski (no outfit)
Art.chars = {
	Glow = "rbxassetid://91758739475236",
	Blush = "rbxassetid://103892276563669",
	Sky = "rbxassetid://127581141845691",
	Lemon = "rbxassetid://132416684527478",
	Lavender = "rbxassetid://129278615441101",
	Mint = "rbxassetid://139404449258053",
	Peach = "rbxassetid://116432688852154",
	Ghost = "rbxassetid://85677411871220",
	Night = "rbxassetid://140380333229638",
	Galaxy = "rbxassetid://115878721898023",
	Secret = "rbxassetid://86346361485442",
}

return Art
