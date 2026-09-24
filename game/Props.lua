-- Props (ReplicatedStorage.SminskiShared.Props)
-- The catalog of authored 3D assets: what exists, who made it, whether a
-- designer has passed it, how it is coloured and where the Smiski can touch it.
--
-- The meshes live under ReplicatedStorage.SminskiAssets.Props (same idea as
-- the rig meshes in Models.lua). Their sizes and offsets come from
-- PropMeshes.lua, which art/blender/export_buildings.py generates -- Blender
-- is the source of truth for geometry (.claude/rules/blender.md).
--
-- A MeshPart carries exactly ONE colour, so every piece is exported split by
-- material role: a tree arrives as tree_timber + tree_leaf + tree_leaf2, and
-- this file says what colour each role is painted. That is why props are a
-- list of parts rather than a single mesh.
--
-- An entry is used by the world ONLY when it is `approved`. Anything else
-- falls back to the part-built version in CityKit, so an unreviewed mesh can
-- never reach the production map (.claude/rules/assets.md).

local Props = {}

Props.HUMAN, Props.AI = "human", "ai"
Props.APPROVED, Props.PENDING = "approved", "pending"

local V = Vector3.new
local rgb = Color3.fromRGB

-- collide: "none" decoration (cheapest) · "solid" you bump into it
--          "walkable" you can stand on it
-- points:  interaction attachments in the asset's own space, named to match
--          across a family (SeatPoint, HandPoint_L/R, FootPoint, ...)

---------------------------------------------------------------------------
-- ROLE COLOURS: the key-art palette, matched to CityKit's K.C so meshes and
-- part-built props sit side by side without a seam.
---------------------------------------------------------------------------
local C = {
	timber = rgb(168, 126, 92),   -- trunks, slats, soil
	metal  = rgb(108, 116, 124),  -- posts, legs, frames
	stone  = rgb(198, 198, 192),  -- plinths, planters, kerbs
	leaf   = rgb(126, 178, 104),  -- canopy, light side
	leaf2  = rgb(98, 148, 86),    -- canopy, shaded side
	pine   = rgb(104, 156, 100),
	pine2  = rgb(84, 132, 84),
	glass  = rgb(255, 228, 168),  -- lamp globes: warm, and the ONE emissive
	shrub  = rgb(118, 168, 100),
	bloom  = rgb(244, 154, 182),
	paint  = rgb(214, 196, 178),
}
Props.C = C

local MATTE = Enum.Material.Plaster
local WOOD  = Enum.Material.Wood
local METAL = Enum.Material.Metal
local NEON  = Enum.Material.Neon
local SLATE = Enum.Material.Slate

---------------------------------------------------------------------------
-- CATALOG. Names match the builders in CityKit, so a mesh replaces a
-- part-built prop the moment it is approved -- and only then.
---------------------------------------------------------------------------
Props.catalog = {
	-- STREET FURNITURE -- the environment kit (assets.md)
	bench = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = {
			{ mesh = "bench_timber", color = C.timber, material = WOOD },
			{ mesh = "bench_metal", color = C.metal, material = METAL },
		},
		points = {
			SeatPoint = { pos = V(0, 1.9, 0), look = V(0, 0, -1) },
			HandPoint_L = { pos = V(-2.6, 3.0, 0.9) },
			HandPoint_R = { pos = V(2.6, 3.0, 0.9) },
			FootPoint = { pos = V(0, 1.9, -0.9) },
		},
	},
	lamp = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = {
			-- the town's lamp posts are its dark green, same as the part-built ones
			{ mesh = "lamp_metal", color = rgb(56, 98, 70), material = METAL },
			-- the only emissive thing in the kit, and only because it is a lamp
			{ mesh = "lamp_glass", color = C.glass, material = NEON, glow = true },
		},
	},
	hydrant = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = { { mesh = "hydrant_wall", color = rgb(214, 96, 88), material = METAL } },
	},
	trashcan = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = { { mesh = "trashcan_wall", color = rgb(104, 124, 112), material = METAL } },
	},
	mailbox = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = { { mesh = "mailbox_wall", color = rgb(96, 140, 196), material = METAL } },
	},
	planter = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = {
			{ mesh = "planter_stone", color = C.stone, material = SLATE },
			{ mesh = "planter_leaf", color = C.shrub, material = MATTE },
		},
	},
	bikerack = {
		by = Props.HUMAN, review = Props.APPROVED, collide = "solid",
		parts = { { mesh = "bikerack_wall", color = C.metal, material = METAL } },
		points = { HandPoint = { pos = V(0, 2.8, 0) } },
	},

	-- NATURE -- AI-assisted volume, human cleanup (pipeline.md)
	tree = {
		by = Props.AI, review = Props.APPROVED, collide = "solid",
		parts = {
			{ mesh = "tree_timber", color = C.timber, material = WOOD },
			{ mesh = "tree_leaf", color = C.leaf, material = MATTE },
			{ mesh = "tree_leaf2", color = C.leaf2, material = MATTE },
		},
	},
	pine = {
		by = Props.AI, review = Props.APPROVED, collide = "solid",
		parts = {
			{ mesh = "pine_timber", color = C.timber, material = WOOD },
			{ mesh = "pine_leaf", color = C.pine, material = MATTE },
			{ mesh = "pine_leaf2", color = C.pine2, material = MATTE },
		},
	},
	bush = {
		by = Props.AI, review = Props.APPROVED, collide = "none",
		parts = {
			{ mesh = "bush_leaf", color = C.leaf, material = MATTE },
			{ mesh = "bush_leaf2", color = C.leaf2, material = MATTE },
		},
	},
	flowers = {
		by = Props.AI, review = Props.APPROVED, collide = "none",
		parts = {
			{ mesh = "flowers_timber", color = rgb(126, 96, 74), material = WOOD },
			{ mesh = "flowers_accent", color = C.bloom, material = MATTE },
		},
	},
}

---------------------------------------------------------------------------
-- QUERIES
---------------------------------------------------------------------------

-- the entry, only if a designer has passed it
function Props.approved(name)
	local e = Props.catalog[name]
	if e and e.review == Props.APPROVED then return e end
	return nil
end

-- everything still waiting on review, so a build can report it
function Props.pending()
	local out = {}
	for name, e in pairs(Props.catalog) do
		if e.review ~= Props.APPROVED then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

return Props
