-- Models: Sminski variants (with accessories + poses) and the giant kid.
-- Everything is built from simple anchored parts and posed by setting CFrames.

local Models = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SminskiShared")
local Rigs = require(Shared:WaitForChild("Rigs"))
local RigMeshes = require(Shared:WaitForChild("RigMeshes"))

---------------------------------------------------------------------------
-- SMOOTH MESHES (Blender, see art/blender/rig_meshes.py). Templates live in
-- ReplicatedStorage.SminskiAssets.Rig; if they're missing everything falls
-- back to the primitive-built versions below.
---------------------------------------------------------------------------
local rigFolder
local function rigTemplate(name)
	if rigFolder == nil then
		local assets = ReplicatedStorage:FindFirstChild("SminskiAssets")
		rigFolder = assets and assets:FindFirstChild("Rig") or false
	end
	return rigFolder and rigFolder:FindFirstChild(name) or nil
end
function Models.hasMeshes(...)
	for _, n in { ... } do
		if not rigTemplate(n) then return false end
	end
	return true
end

local IMPORT_TURN = CFrame.Angles(0, math.pi, 0)

-- clone a rig mesh: returns the part and its offset CFrame from the joint
local function rigMesh(parent, name, scale, color, material, texture)
	local def = RigMeshes[name]
	local p = rigTemplate(name):Clone()
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Size = def.size * scale
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TextureID = texture or ""
	p.Name = name
	p.Parent = parent
	-- Studio's 3D importer turns imported meshes to face -Z; the rig faces +Z
	return p, CFrame.new(def.offset * scale) * IMPORT_TURN
end
Models.rigMesh = rigMesh

-- face decal: a hair-bigger copy of the head mesh carrying the face texture.
-- A tiny part transparency makes Roblox honour the texture's alpha, so only
-- the eyes/brows/mouth show and the head underneath keeps its own material.
local function faceOverlay(parent, headName, scale, texture)
	local p, off = rigMesh(parent, headName, scale * 1.012, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, texture)
	p.Name = "Face"
	p.Transparency = 0.02
	p.CastShadow = false
	return p, off
end
Models.faceOverlay = faceOverlay
-- star coin mesh size for a given diameter
function Models.coinSize(dia)
	return RigMeshes.StarCoin.size * (dia / RigMeshes.StarCoin.size.X)
end

-- move a list of { p, joint, off } entries in one engine call
local function applyJoints(model, entries, joints)
	local parts, cfs = table.create(#entries), table.create(#entries)
	for i, e in entries do
		parts[i] = e.p
		cfs[i] = joints[e.joint] * e.off
	end
	if model:IsDescendantOf(workspace) then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for i, p in parts do p.CFrame = cfs[i] end
	end
end

local SM = Enum.Material.SmoothPlastic
local SPH = Enum.MeshType.Sphere

function Models.part(parent, size, cf, color, material, opts)
	local p = Instance.new((opts and opts.class) or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SM
	if opts then
		if opts.shape then p.Shape = opts.shape end
		if opts.mesh then
			local m = Instance.new("SpecialMesh")
			m.MeshType = opts.mesh
			m.Parent = p
		end
		if opts.transparency then p.Transparency = opts.transparency end
		if opts.noShadow then p.CastShadow = false end
		if opts.walk then p.CanQuery = true end
		if opts.obs then
			p.CanQuery = true
			p:SetAttribute("Obs", true)
		end
		if opts.reflect then p.Reflectance = opts.reflect end
	end
	p.Parent = parent
	return p
end
local part = Models.part

---------------------------------------------------------------------------
-- SMINSKI
-- Proportions from the real figures: big perfectly round head (~40% of the
-- height), soft column body with rounded shoulders/hips, long thin arms that
-- hang to the hips, short stubby legs, tiny dot eyes + a small mouth.
---------------------------------------------------------------------------
local VCYL = CFrame.Angles(0, 0, math.pi / 2) -- turns a Cylinder part upright
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local FACE_COLOR = Color3.fromRGB(78, 140, 72)

-- outfit builders: add(joint, size, offsetCF, color, opts)
-- joint "head" offsets are from the head centre (head radius 0.8),
-- joint "body" offsets are from the torso centre (y = 1.5 above the feet).
local ACC = {}

ACC.nightcap = function(add)
	local blue = Color3.fromRGB(110, 140, 220)
	add("head", Vector3.new(0.26, 1.58, 1.58), CFrame.new(0, 0.52, 0) * VCYL, Color3.fromRGB(245, 245, 250), { shape = CYL })
	add("head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0.12, 0.9, -0.05) * CFrame.Angles(0, 0, -0.45), blue, { mesh = SPH })
	add("head", Vector3.new(0.65, 0.85, 0.65), CFrame.new(0.55, 1.25, -0.05) * CFrame.Angles(0, 0, -1.1), blue, { mesh = SPH })
	add("head", Vector3.new(0.36, 0.36, 0.36), CFrame.new(0.92, 1.28, -0.05), Color3.fromRGB(255, 255, 255), { shape = BALL })
end

ACC.headband = function(add)
	add("head", Vector3.new(0.22, 1.66, 1.66), CFrame.new(0, 0.2, 0) * VCYL, Color3.fromRGB(255, 130, 170), { shape = CYL })
end

ACC.tie = function(add)
	local navy = Color3.fromRGB(60, 80, 150)
	add("body", Vector3.new(0.26, 0.2, 0.16), CFrame.new(0, 0.55, 0.6), navy)
	add("body", Vector3.new(0.22, 0.75, 0.1), CFrame.new(0, 0.08, 0.62) * CFrame.Angles(0.08, 0, 0), navy)
end

ACC.towel = function(add)
	local c = Color3.fromRGB(160, 215, 245)
	add("head", Vector3.new(1.8, 0.8, 1.72), CFrame.new(0, 0.48, -0.05), c, { mesh = SPH })
	add("head", Vector3.new(1.3, 0.95, 0.25), CFrame.new(0, -0.05, -0.7) * CFrame.Angles(-0.2, 0, 0), c, { mesh = SPH })
end

ACC.chefhat = function(add)
	add("head", Vector3.new(0.7, 1.12, 1.12), CFrame.new(0, 0.85, 0) * VCYL, Color3.fromRGB(252, 252, 252), { shape = CYL })
	add("head", Vector3.new(1.45, 0.85, 1.45), CFrame.new(0, 1.35, 0), Color3.fromRGB(255, 255, 255), { mesh = SPH })
end

ACC.sprout = function(add)
	local g = Color3.fromRGB(90, 180, 80)
	add("head", Vector3.new(0.1, 0.5, 0.1), CFrame.new(0, 0.98, 0), g)
	add("head", Vector3.new(0.55, 0.14, 0.32), CFrame.new(-0.24, 1.22, 0) * CFrame.Angles(0, 0, 0.5), g, { mesh = SPH })
	add("head", Vector3.new(0.55, 0.14, 0.32), CFrame.new(0.24, 1.22, 0) * CFrame.Angles(0, 0, -0.5), g, { mesh = SPH })
end

ACC.bow = function(add)
	local pink = Color3.fromRGB(255, 120, 160)
	local base = CFrame.new(0.42, 0.62, 0.15) * CFrame.Angles(0, 0, -0.5)
	add("head", Vector3.new(0.5, 0.36, 0.2), base * CFrame.new(-0.24, 0, 0) * CFrame.Angles(0, 0, 0.3), pink, { mesh = SPH })
	add("head", Vector3.new(0.5, 0.36, 0.2), base * CFrame.new(0.24, 0, 0) * CFrame.Angles(0, 0, -0.3), pink, { mesh = SPH })
	add("head", Vector3.new(0.18, 0.18, 0.18), base, Color3.fromRGB(235, 90, 130), { shape = BALL })
end

ACC.scarf = function(add)
	local red = Color3.fromRGB(225, 85, 80)
	add("body", Vector3.new(0.3, 1.4, 1.4), CFrame.new(0, 0.7, 0) * VCYL, red, { shape = CYL })
	add("body", Vector3.new(0.3, 0.7, 0.12), CFrame.new(0.32, 0.3, 0.64) * CFrame.Angles(0.1, 0, 0.1), red)
	add("body", Vector3.new(0.32, 0.08, 0.13), CFrame.new(0.32, 0.1, 0.65) * CFrame.Angles(0.1, 0, 0.1), Color3.fromRGB(255, 240, 230))
end

ACC.party = function(add)
	local cols = { Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 120, 150) }
	local tilt = CFrame.new(0.15, 0, 0) * CFrame.Angles(0, 0, -0.2)
	add("head", Vector3.new(0.3, 0.85, 0.85), tilt * CFrame.new(0, 0.78, 0) * VCYL, cols[1], { shape = CYL })
	add("head", Vector3.new(0.3, 0.58, 0.58), tilt * CFrame.new(0, 1.05, 0) * VCYL, cols[2], { shape = CYL })
	add("head", Vector3.new(0.3, 0.32, 0.32), tilt * CFrame.new(0, 1.3, 0) * VCYL, cols[3], { shape = CYL })
	add("head", Vector3.new(0.26, 0.26, 0.26), tilt * CFrame.new(0, 1.5, 0), Color3.fromRGB(255, 255, 255), { shape = BALL })
end

ACC.catears = function(add)
	for _, sx in { -1, 1 } do
		local cf = CFrame.new(sx * 0.42, 0.68, 0.05) * CFrame.Angles(0, 0, -sx * 0.35)
		add("head", Vector3.new(0.4, 0.55, 0.16), cf, Color3.fromRGB(90, 80, 80), { mesh = SPH })
		add("head", Vector3.new(0.22, 0.34, 0.1), cf * CFrame.new(0, -0.03, 0.05), Color3.fromRGB(255, 170, 190), { mesh = SPH })
	end
end

ACC.flowers = function(add)
	local cols = { Color3.fromRGB(255, 150, 190), Color3.fromRGB(255, 230, 110), Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 150, 255) }
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("head", Vector3.new(0.3, 0.3, 0.3), CFrame.new(math.cos(a) * 0.68, 0.5, math.sin(a) * 0.68), cols[i % 4 + 1], { shape = BALL })
	end
	add("head", Vector3.new(0.16, 1.5, 1.5), CFrame.new(0, 0.46, 0) * VCYL, Color3.fromRGB(110, 180, 90), { shape = CYL })
end

ACC.santa = function(add)
	add("head", Vector3.new(0.3, 1.62, 1.62), CFrame.new(0, 0.55, 0) * VCYL, Color3.fromRGB(255, 255, 255), { shape = CYL })
	add("head", Vector3.new(1.3, 1.2, 1.3), CFrame.new(0.1, 0.95, 0) * CFrame.Angles(0, 0, -0.5), Color3.fromRGB(220, 60, 60), { mesh = SPH })
	add("head", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0.68, 1.3, 0), Color3.fromRGB(255, 255, 255), { shape = BALL })
end

ACC.backpack = function(add)
	local c = Color3.fromRGB(255, 170, 90)
	add("body", Vector3.new(1.0, 1.05, 0.5), CFrame.new(0, 0.15, -0.72), c, { mesh = SPH })
	add("body", Vector3.new(0.7, 0.4, 0.2), CFrame.new(0, -0.05, -0.98), Color3.fromRGB(255, 205, 140), { mesh = SPH })
	for _, sx in { -1, 1 } do
		add("body", Vector3.new(0.12, 0.9, 0.08), CFrame.new(sx * 0.32, 0.25, 0.6), Color3.fromRGB(200, 120, 60))
	end
end

ACC.helmet = function(add)
	add("head", Vector3.new(2.05, 2.05, 2.05), CFrame.new(0, 0, 0), Color3.fromRGB(200, 230, 255), { shape = BALL, transparency = 0.72, glass = true })
	add("head", Vector3.new(0.07, 0.55, 0.07), CFrame.new(0.4, 1.2, 0), Color3.fromRGB(180, 180, 190))
	add("head", Vector3.new(0.24, 0.24, 0.24), CFrame.new(0.4, 1.5, 0), Color3.fromRGB(255, 90, 90), { shape = BALL, neon = true })
end

ACC.daisy = function(add)
	local base = CFrame.new(-0.46, 0.55, 0.28) * CFrame.Angles(0.2, 0.4, 0.5)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("head", Vector3.new(0.26, 0.12, 0.14), base * CFrame.new(math.cos(a) * 0.2, math.sin(a) * 0.2, 0) * CFrame.Angles(0, 0, a), Color3.fromRGB(255, 255, 255), { mesh = SPH })
	end
	add("head", Vector3.new(0.18, 0.18, 0.12), base * CFrame.new(0, 0, 0.03), Color3.fromRGB(255, 208, 80), { mesh = SPH })
end

ACC.cape = function(add)
	local navy = Color3.fromRGB(58, 62, 128)
	add("body", Vector3.new(1.3, 1.5, 0.12), CFrame.new(0, -0.05, -0.62) * CFrame.Angles(0.18, 0, 0), navy, { mesh = SPH })
	add("body", Vector3.new(0.9, 0.18, 0.9), CFrame.new(0, 0.7, -0.1), navy, { mesh = SPH })
	for i, p in { { -0.28, 0.25 }, { 0.2, -0.15 }, { -0.05, -0.45 }, { 0.32, 0.35 } } do
		add("body", Vector3.new(0.12, 0.12, 0.05), CFrame.new(p[1], p[2], -0.7) * CFrame.Angles(0.18, 0, i), Color3.fromRGB(255, 226, 120), { neon = true })
	end
end

ACC.crown = function(add)
	local gold = Color3.fromRGB(255, 215, 80)
	add("head", Vector3.new(0.34, 1.02, 1.02), CFrame.new(0, 0.82, 0) * VCYL, gold, { shape = CYL, metal = true })
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("head", Vector3.new(0.15, 0.15, 0.15), CFrame.new(math.cos(a) * 0.45, 1.02, math.sin(a) * 0.45), Color3.fromRGB(255, 120, 150), { shape = BALL, neon = true })
	end
end

ACC.beanie = function(add)
	local c = Color3.fromRGB(120, 196, 170)
	add("head", Vector3.new(1.66, 0.95, 1.66), CFrame.new(0, 0.5, 0), c, { mesh = SPH })
	add("head", Vector3.new(0.28, 1.68, 1.68), CFrame.new(0, 0.18, 0) * VCYL, c:Lerp(Color3.new(1, 1, 1), 0.3), { shape = CYL })
	add("head", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 1.02, 0), Color3.fromRGB(255, 250, 240), { shape = BALL })
end

ACC.shades = function(add)
	local ink = Color3.fromRGB(34, 30, 44)
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(0.42, 0.26, 0.08), CFrame.new(sx * 0.27, 0.02, 0.78), ink)
	end
	add("head", Vector3.new(0.18, 0.06, 0.06), CFrame.new(0, 0.08, 0.8), ink)
end

ACC.halo = function(add)
	-- a ring of little glowing beads, tipped toward the front so it reads
	local tilt = CFrame.new(0, 1.22, 0) * CFrame.Angles(0.3, 0, 0)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		add("head", Vector3.new(0.17, 0.17, 0.17), tilt * CFrame.new(math.cos(a) * 0.5, 0, math.sin(a) * 0.5), Color3.fromRGB(255, 232, 140), { shape = BALL, neon = true })
	end
end

ACC.bunny = function(add)
	for _, sx in { -1, 1 } do
		local cf = CFrame.new(sx * 0.3, 1.0, 0) * CFrame.Angles(0, 0, -sx * 0.2)
		add("head", Vector3.new(0.34, 0.95, 0.2), cf, Color3.fromRGB(255, 252, 250), { mesh = SPH })
		add("head", Vector3.new(0.18, 0.66, 0.1), cf * CFrame.new(0, -0.02, 0.06), Color3.fromRGB(255, 184, 204), { mesh = SPH })
	end
end

ACC.frog = function(add)
	local g = Color3.fromRGB(128, 200, 110)
	add("head", Vector3.new(1.74, 0.9, 1.74), CFrame.new(0, 0.48, 0), g, { mesh = SPH })
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(0.52, 0.52, 0.52), CFrame.new(sx * 0.42, 0.98, 0.3), g, { shape = BALL })
		add("head", Vector3.new(0.26, 0.26, 0.12), CFrame.new(sx * 0.42, 1.02, 0.55), Color3.fromRGB(255, 255, 255), { mesh = SPH })
		add("head", Vector3.new(0.12, 0.12, 0.08), CFrame.new(sx * 0.42, 1.02, 0.61), Color3.fromRGB(30, 30, 36), { mesh = SPH })
	end
end

ACC.wings = function(add)
	for _, sx in { -1, 1 } do
		add("body", Vector3.new(0.9, 1.1, 0.12), CFrame.new(sx * 0.55, 0.5, -0.62) * CFrame.Angles(0.2, sx * 0.5, sx * 0.35), Color3.fromRGB(235, 245, 255), { mesh = SPH, transparency = 0.25 })
		add("body", Vector3.new(0.6, 0.7, 0.1), CFrame.new(sx * 0.5, 0.0, -0.6) * CFrame.Angles(0.2, sx * 0.5, sx * 0.9), Color3.fromRGB(220, 235, 255), { mesh = SPH, transparency = 0.3 })
	end
end

-- more cute outfits (Toy Shop)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local WHITE = rgb(255, 252, 248)

ACC.strawberry = function(add)
	local red = rgb(246, 96, 110)
	add("head", Vector3.new(1.72, 1.05, 1.72), CFrame.new(0, 0.5, 0), red, { mesh = SPH })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		add("head", Vector3.new(0.1, 0.14, 0.1), CFrame.new(math.cos(a) * 0.62, 0.62 + (i % 2) * 0.16, math.sin(a) * 0.62), rgb(255, 232, 140), { mesh = SPH })
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		add("head", Vector3.new(0.5, 0.1, 0.24), CFrame.new(math.cos(a) * 0.24, 1.02, math.sin(a) * 0.24) * CFrame.Angles(0, -a, 0.35), rgb(120, 196, 110), { mesh = SPH })
	end
	add("head", Vector3.new(0.1, 0.3, 0.1), CFrame.new(0, 1.14, 0), rgb(96, 160, 90))
end

ACC.bearears = function(add)
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(0.52, 0.52, 0.3), CFrame.new(sx * 0.56, 0.72, 0), rgb(176, 124, 90), { mesh = SPH })
		add("head", Vector3.new(0.3, 0.3, 0.1), CFrame.new(sx * 0.56, 0.72, 0.14), rgb(255, 196, 196), { mesh = SPH })
	end
end

ACC.cloud = function(add)
	for i, p in { Vector3.new(0, 1.62, 0), Vector3.new(-0.42, 1.52, 0.05), Vector3.new(0.44, 1.5, -0.05), Vector3.new(0.12, 1.84, -0.1), Vector3.new(-0.2, 1.46, 0.3) } do
		local s = ({ 0.8, 0.62, 0.6, 0.5, 0.5 })[i]
		add("head", Vector3.new(s, s, s), CFrame.new(p), WHITE, { shape = BALL })
	end
	for _, x in { -0.3, 0, 0.3 } do
		add("head", Vector3.new(0.08, 0.16, 0.08), CFrame.new(x, 1.12, 0.1), rgb(150, 206, 250), { mesh = SPH })
	end
end

ACC.cherries = function(add)
	local stem = rgb(96, 160, 90)
	for i, p in { Vector3.new(0.52, 0.52, 0.5), Vector3.new(0.7, 0.4, 0.28) } do
		add("head", Vector3.new(0.3, 0.3, 0.3), CFrame.new(p), rgb(236, 70, 90), { shape = BALL })
		add("head", Vector3.new(0.05, 0.36, 0.05), CFrame.new(p + Vector3.new(-0.06 * i, 0.26, 0)) * CFrame.Angles(0, 0, 0.4 * (i == 1 and 1 or -1)), stem)
	end
	add("head", Vector3.new(0.24, 0.08, 0.14), CFrame.new(0.6, 0.86, 0.36), stem, { mesh = SPH })
end

ACC.mushroom = function(add)
	local red = rgb(236, 90, 90)
	add("head", Vector3.new(2, 0.95, 2), CFrame.new(0, 0.66, 0), red, { mesh = SPH })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		add("head", Vector3.new(0.3, 0.12, 0.3), CFrame.new(math.cos(a) * 0.62, 0.88, math.sin(a) * 0.62) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), WHITE, { mesh = SPH })
	end
	add("head", Vector3.new(0.36, 0.12, 0.36), CFrame.new(0, 1.12, 0), WHITE, { mesh = SPH })
end

ACC.heartspecs = function(add)
	local pink = rgb(255, 120, 170)
	for _, sx in { -1, 1 } do
		local c = CFrame.new(sx * 0.3, 0.04, 0.8)
		add("head", Vector3.new(0.2, 0.2, 0.06), c * CFrame.new(-0.07, 0.05, 0), pink, { mesh = SPH })
		add("head", Vector3.new(0.2, 0.2, 0.06), c * CFrame.new(0.07, 0.05, 0), pink, { mesh = SPH })
		add("head", Vector3.new(0.2, 0.2, 0.06), c * CFrame.new(0, -0.04, 0) * CFrame.Angles(0, 0, math.pi / 4), pink)
	end
	add("head", Vector3.new(0.16, 0.05, 0.05), CFrame.new(0, 0.1, 0.82), pink)
end

ACC.duckfloat = function(add)
	local y = rgb(255, 222, 90)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		add("body", Vector3.new(0.5, 0.42, 0.5), CFrame.new(math.cos(a) * 0.95, -0.45, math.sin(a) * 0.95), y, { mesh = SPH })
	end
	add("body", Vector3.new(0.56, 0.56, 0.56), CFrame.new(0, -0.05, 1.05), y, { shape = BALL })
	add("body", Vector3.new(0.3, 0.12, 0.2), CFrame.new(0, -0.1, 1.36), rgb(255, 150, 70), { mesh = SPH })
	for _, sx in { -1, 1 } do add("body", Vector3.new(0.08, 0.08, 0.04), CFrame.new(sx * 0.13, 0.05, 1.32), rgb(30, 30, 36), { shape = BALL }) end
end

ACC.unicorn = function(add)
	local tip = CFrame.new(0, 0.95, 0.42) * CFrame.Angles(0.35, 0, 0)
	for k, c in { rgb(255, 196, 220), rgb(255, 230, 150), rgb(170, 220, 255), rgb(210, 180, 255) } do
		local d = 0.36 - k * 0.07
		add("head", Vector3.new(0.2, d, d), tip * CFrame.new(0, (k - 1) * 0.18, 0) * VCYL, c, { shape = CYL })
	end
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(0.2, 0.36, 0.14), CFrame.new(sx * 0.45, 0.78, 0) * CFrame.Angles(0, 0, -sx * 0.3), WHITE, { mesh = SPH })
	end
	for k, c in { rgb(255, 150, 190), rgb(255, 214, 110), rgb(150, 206, 250) } do
		add("head", Vector3.new(0.24, 0.3, 0.24), CFrame.new(-0.2 + k * 0.12, 0.62 - k * 0.1, -0.62), c, { mesh = SPH })
	end
end

ACC.starclips = function(add)
	for _, p in { Vector3.new(0.5, 0.62, 0.42), Vector3.new(-0.56, 0.5, 0.38) } do
		local c = CFrame.new(p)
		add("head", Vector3.new(0.16, 0.16, 0.08), c, rgb(255, 226, 110), { mesh = SPH, neon = true })
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			add("head", Vector3.new(0.08, 0.2, 0.06), c * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.12, 0), rgb(255, 226, 110), { neon = true })
		end
	end
end

ACC.bee = function(add)
	local ink = rgb(40, 34, 44)
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(0.05, 0.5, 0.05), CFrame.new(sx * 0.22, 0.98, 0.2) * CFrame.Angles(0.2, 0, -sx * 0.3), ink)
		add("head", Vector3.new(0.18, 0.18, 0.18), CFrame.new(sx * 0.33, 1.22, 0.26), rgb(255, 214, 90), { shape = BALL })
		add("body", Vector3.new(0.6, 0.72, 0.08), CFrame.new(sx * 0.4, 0.45, -0.62) * CFrame.Angles(0.2, sx * 0.4, sx * 0.5), rgb(230, 244, 255), { mesh = SPH, transparency = 0.3 })
	end
end

ACC.lollipop = function(add)
	local c = CFrame.new(0.62, 0.62, -0.1) * CFrame.Angles(0, math.pi / 2, 0.25)
	add("head", Vector3.new(0.06, 0.5, 0.06), c * CFrame.new(0, -0.2, 0), WHITE)
	add("head", Vector3.new(0.08, 0.5, 0.5), c * CFrame.new(0, 0.2, 0), rgb(255, 150, 200), { shape = CYL })
	add("head", Vector3.new(0.09, 0.32, 0.32), c * CFrame.new(0, 0.2, 0), WHITE, { shape = CYL })
	add("head", Vector3.new(0.1, 0.16, 0.16), c * CFrame.new(0, 0.2, 0), rgb(150, 206, 250), { shape = CYL })
end

ACC.sunhat = function(add)
	local straw = rgb(236, 206, 140)
	add("head", Vector3.new(0.12, 2.6, 2.6), CFrame.new(0, 0.5, 0) * VCYL, straw, { shape = CYL })
	add("head", Vector3.new(1.3, 0.62, 1.3), CFrame.new(0, 0.82, 0), straw, { mesh = SPH })
	add("head", Vector3.new(0.2, 1.36, 1.36), CFrame.new(0, 0.66, 0) * VCYL, rgb(255, 150, 190), { shape = CYL })
	add("head", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.55, 0.72, 0.4), rgb(255, 250, 240), { shape = BALL })
	add("head", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.58, 0.74, 0.54), rgb(255, 214, 90), { shape = BALL })
end

---------------------------------------------------------------------------
-- SKINS: whole-body looks, from Config.Skins.
--
-- Same add(joint, size, offsetCF, colour, opts) as the accessories above, but
-- a skin dresses the torso, the arms and the legs as well as the head, and it
-- is drawn AFTER the body so it sits on top of it.
--
-- TWO RULES WORTH KNOWING BEFORE ADDING ONE:
--
-- 1. LEAVE THE FACE ALONE. With the imported meshes the face is a texture
--    decal on the front of SmHead, so anything that wraps the head has to be
--    pushed back in -Z (a hood) or kept below the eyeline (a mask), or it
--    covers the face and the Sminski goes blank.
-- 2. THE SUIT COLOUR IS THE BODY COLOUR. buildSminski has already recoloured
--    the body to skinDef.body by the time these run (unless the skin is
--    keepBody, which leaves your capsule colour showing through), so `col` is
--    passed in and trim should contrast with it rather than restate it.
---------------------------------------------------------------------------
local V = Vector3.new
local SKIN = {}

SKIN.hoodie = function(add, col)
	local cloth, dark = rgb(126, 178, 238), rgb(92, 138, 196)
	add("head", V(1.78, 1.78, 1.7), CFrame.new(0, 0.12, -0.34), cloth, { shape = BALL })
	add("head", V(1.52, 0.66, 1.3), CFrame.new(0, -0.52, -0.12), cloth, { mesh = SPH })
	add("body", V(1.44, 1.52, 1.28), CFrame.new(0, 0.04, 0), cloth, { mesh = SPH })
	add("body", V(0.92, 0.46, 0.34), CFrame.new(0, -0.3, 0.56), dark, { mesh = SPH })
	for _, sx in { -1, 1 } do
		add("body", V(0.09, 0.4, 0.09), CFrame.new(sx * 0.18, 0.4, 0.58), rgb(248, 248, 244))
		add("body", V(0.14, 0.14, 0.14), CFrame.new(sx * 0.18, 0.18, 0.58), rgb(248, 248, 244), { shape = BALL })
	end
	for _, j in { "armL", "armR" } do
		add(j, V(0.54, 1.04, 0.56), CFrame.new(0, -0.46, 0), cloth, { mesh = SPH })
		add(j, V(0.5, 0.22, 0.52), CFrame.new(0, -0.92, 0), dark, { mesh = SPH })
	end
end

SKIN.tracksuit = function(add, col)
	local cloth, stripe = rgb(58, 66, 92), rgb(250, 250, 250)
	add("body", V(1.42, 1.5, 1.26), CFrame.new(0, 0.04, 0), cloth, { mesh = SPH })
	add("body", V(0.14, 1.3, 0.1), CFrame.new(0, 0.08, 0.6), stripe)
	add("body", V(1.1, 0.24, 1.0), CFrame.new(0, 0.6, 0), stripe, { mesh = SPH })
	for _, j in { "armL", "armR" } do
		add(j, V(0.54, 1.06, 0.56), CFrame.new(0, -0.46, 0), cloth, { mesh = SPH })
		for _, dy in { -0.2, -0.5 } do
			add(j, V(0.56, 0.08, 0.58), CFrame.new(0, dy, 0), stripe, { mesh = SPH })
		end
	end
	for _, j in { "legL", "legR" } do
		add(j, V(0.64, 0.7, 0.68), CFrame.new(0, -0.28, 0.02), cloth, { mesh = SPH })
		add(j, V(0.66, 0.08, 0.7), CFrame.new(0, -0.34, 0.02), stripe, { mesh = SPH })
		add(j, V(0.62, 0.3, 0.74), CFrame.new(0, -0.74, 0.06), stripe, { mesh = SPH })
	end
end

SKIN.chef = function(add, col)
	local white, kerchief = rgb(252, 252, 250), rgb(226, 78, 84)
	add("head", V(0.72, 1.16, 1.16), CFrame.new(0, 0.86, 0) * VCYL, white, { shape = CYL })
	add("head", V(1.5, 0.9, 1.5), CFrame.new(0, 1.36, 0), white, { mesh = SPH })
	add("head", V(0.96, 0.62, 0.96), CFrame.new(-0.3, 1.62, -0.18), white, { mesh = SPH })
	add("head", V(0.86, 0.56, 0.86), CFrame.new(0.32, 1.6, 0.16), white, { mesh = SPH })
	add("body", V(1.32, 0.42, 1.2), CFrame.new(0, 0.58, 0), kerchief, { mesh = SPH })
	add("body", V(1.0, 1.24, 0.24), CFrame.new(0, -0.02, 0.56), white, { mesh = SPH })
	for _, sx in { -1, 1 } do
		for _, dy in { 0.28, -0.02, -0.32 } do
			add("body", V(0.13, 0.13, 0.13), CFrame.new(sx * 0.28, dy, 0.64), rgb(230, 230, 226), { shape = BALL })
		end
	end
end

SKIN.bee = function(add, col)
	local stripe, wing = rgb(48, 44, 52), rgb(232, 244, 255)
	for _, dy in { 0.38, 0.0, -0.38 } do
		add("body", V(1.36, 0.22, 1.2), CFrame.new(0, dy, 0), stripe, { mesh = SPH })
	end
	for _, sx in { -1, 1 } do
		add("head", V(0.07, 0.5, 0.07), CFrame.new(sx * 0.3, 0.86, -0.06) * CFrame.Angles(0, 0, -sx * 0.32), stripe)
		add("head", V(0.2, 0.2, 0.2), CFrame.new(sx * 0.44, 1.14, -0.1), stripe, { shape = BALL })
		local w = add("body", V(1.05, 0.14, 0.7), CFrame.new(sx * 0.62, 0.42, -0.6) * CFrame.Angles(-0.35, -sx * 0.5, 0), wing, { mesh = SPH })
		w.Transparency = 0.42
	end
	add("body", V(0.24, 0.24, 0.42), CFrame.new(0, -0.6, -0.62) * CFrame.Angles(0.5, 0, 0), stripe, { mesh = SPH })
end

SKIN.ninja = function(add, col)
	local cloth, sash = rgb(34, 38, 56), rgb(214, 66, 72)
	add("head", V(1.8, 1.8, 1.74), CFrame.new(0, 0.1, -0.3), cloth, { shape = BALL })
	add("head", V(1.62, 0.5, 1.5), CFrame.new(0, -0.34, 0.06), cloth, { mesh = SPH })
	add("head", V(1.5, 0.6, 1.3), CFrame.new(0, -0.5, -0.12), cloth, { mesh = SPH })
	add("head", V(0.24, 0.7, 0.2), CFrame.new(0.5, -0.18, -0.74) * CFrame.Angles(0.3, 0, 0.3), sash, { mesh = SPH })
	add("body", V(1.38, 0.34, 1.22), CFrame.new(0, -0.26, 0), sash, { mesh = SPH })
	add("body", V(0.3, 0.72, 0.16), CFrame.new(0.5, -0.56, 0.42) * CFrame.Angles(0, 0, 0.2), sash, { mesh = SPH })
	for _, j in { "armL", "armR" } do
		add(j, V(0.5, 0.3, 0.52), CFrame.new(0, -0.82, 0), sash, { mesh = SPH })
	end
	add("body", V(0.14, 1.5, 0.14), CFrame.new(-0.2, 0.1, -0.68) * CFrame.Angles(0, 0, -0.5), rgb(120, 126, 140))
	add("body", V(0.2, 0.3, 0.2), CFrame.new(0.28, -0.5, -0.68) * CFrame.Angles(0, 0, -0.5), rgb(58, 52, 48))
end

SKIN.ghost = function(add, col)
	local sheet = rgb(246, 248, 252)
	local function ghostly(p) p.Transparency = 0.3 return p end
	ghostly(add("head", V(1.92, 1.9, 1.86), CFrame.new(0, 0.14, -0.1), sheet, { shape = BALL }))
	ghostly(add("body", V(1.7, 1.8, 1.54), CFrame.new(0, 0.1, 0), sheet, { mesh = SPH }))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		ghostly(add("body", V(0.46, 0.66, 0.46), CFrame.new(math.cos(a) * 0.66, -0.76, math.sin(a) * 0.58), sheet, { mesh = SPH }))
	end
end

SKIN.diver = function(add, col)
	local glassC, tank, fin = rgb(226, 246, 252), rgb(250, 176, 60), rgb(40, 96, 110)
	local g = add("head", V(1.3, 0.88, 0.5), CFrame.new(0, 0.06, 0.62), glassC, { mesh = SPH })
	g.Transparency = 0.45
	add("head", V(1.46, 0.28, 1.4), CFrame.new(0, 0.06, 0), fin, { mesh = SPH })
	add("head", V(0.16, 0.9, 0.16), CFrame.new(0.66, 0.5, 0.2) * CFrame.Angles(0, 0, -0.16), tank)
	add("head", V(0.2, 0.2, 0.3), CFrame.new(0.58, 0.02, 0.36), tank, { mesh = SPH })
	add("body", V(0.5, 1.2, 0.5), CFrame.new(-0.26, 0.1, -0.68), tank, { mesh = SPH })
	add("body", V(0.5, 1.2, 0.5), CFrame.new(0.26, 0.1, -0.68), tank, { mesh = SPH })
	add("body", V(1.0, 0.24, 0.3), CFrame.new(0, 0.66, -0.62), rgb(70, 74, 88), { mesh = SPH })
	for _, j in { "legL", "legR" } do
		add(j, V(0.72, 0.2, 1.5), CFrame.new(0, -0.8, 0.5), fin, { mesh = SPH })
	end
end

SKIN.pirate = function(add, col)
	local hat, trim, sash = rgb(42, 40, 52), rgb(238, 226, 190), rgb(214, 160, 56)
	add("head", V(1.5, 0.62, 1.2), CFrame.new(0, 0.82, -0.06), hat, { mesh = SPH })
	add("head", V(1.9, 0.22, 1.5), CFrame.new(0, 0.6, -0.06), hat, { mesh = SPH })
	add("head", V(1.5, 0.3, 0.56), CFrame.new(0, 0.9, 0.56) * CFrame.Angles(0.72, 0, 0), hat, { mesh = SPH })
	for _, sx in { -1, 1 } do
		add("head", V(0.52, 0.28, 1.3), CFrame.new(sx * 0.82, 0.84, -0.2) * CFrame.Angles(0, 0, -sx * 0.72), hat, { mesh = SPH })
	end
	add("head", V(0.3, 0.3, 0.16), CFrame.new(0, 1.0, 0.56), rgb(238, 226, 190), { shape = BALL })
	add("head", V(0.44, 0.42, 0.14), CFrame.new(-0.25, -0.02, 0.74), hat, { mesh = SPH })
	add("head", V(1.5, 0.1, 1.42), CFrame.new(0, 0.2, 0), hat, { mesh = SPH })
	add("body", V(1.42, 1.46, 1.26), CFrame.new(0, 0.02, 0), rgb(96, 44, 48), { mesh = SPH })
	add("body", V(0.3, 1.3, 0.2), CFrame.new(0, 0.02, 0.6), trim, { mesh = SPH })
	add("body", V(1.4, 0.3, 1.22), CFrame.new(0, -0.34, 0) * CFrame.Angles(0, 0, 0.14), sash, { mesh = SPH })
	add("body", V(0.3, 0.3, 0.16), CFrame.new(0.1, -0.34, 0.6), rgb(238, 210, 120))
	for _, j in { "armL", "armR" } do
		add(j, V(0.52, 0.26, 0.54), CFrame.new(0, -0.8, 0), trim, { mesh = SPH })
	end
end

SKIN.dino = function(add, col)
	local spike, belly = rgb(250, 214, 96), rgb(244, 232, 186)
	add("head", V(1.8, 1.8, 1.7), CFrame.new(0, 0.12, -0.3), col, { shape = BALL })
	-- crest: three fins standing on the hood's own surface (r = 0.95 about
	-- its centre), tipping further back as they go
	for i, a in { 0.1, 0.62, 1.12 } do
		add("head", V(0.18, 0.52 - (i - 1) * 0.06, 0.34), CFrame.new(math.sin(a) * 0.1, 0.12 + math.cos(a) * 1.02, -0.3 - math.sin(a) * 1.02) * CFrame.Angles(a, 0, 0), spike, { mesh = SPH })
	end
	for _, sx in { -1, 1 } do -- little horns, so it reads from the front too
		add("head", V(0.2, 0.42, 0.2), CFrame.new(sx * 0.42, 0.72, 0.3) * CFrame.Angles(-0.3, 0, sx * 0.3), spike, { mesh = SPH })
	end
	for _, j in { "legL", "legR" } do -- claws
		for _, sx in { -1, 0, 1 } do
			add(j, V(0.16, 0.16, 0.3), CFrame.new(sx * 0.19, -0.78, 0.34), spike, { mesh = SPH })
		end
	end
	add("body", V(1.0, 1.1, 0.3), CFrame.new(0, -0.04, 0.52), belly, { mesh = SPH })
	for i = 1, 3 do
		add("body", V(0.16, 0.36, 0.34), CFrame.new(0, 0.44 - i * 0.36, -0.58), spike, { mesh = SPH })
	end
	for i = 1, 4 do
		add("body", V(0.52 - i * 0.07, 0.46 - i * 0.07, 0.5), CFrame.new(0, -0.7 - i * 0.12, -0.8 - i * 0.42) * CFrame.Angles(0.38, 0, 0), col, { mesh = SPH })
	end
end

SKIN.robot = function(add, col)
	local panel, light = rgb(66, 72, 92), rgb(120, 240, 200)
	add("head", V(1.56, 0.4, 0.3), CFrame.new(0, 0.1, 0.7), panel, { mesh = SPH })
	add("head", V(0.9, 0.16, 0.2), CFrame.new(0, 0.1, 0.78), light, { neon = true, mesh = SPH })
	add("head", V(0.08, 0.6, 0.08), CFrame.new(0, 1.04, -0.1), panel)
	add("head", V(0.24, 0.24, 0.24), CFrame.new(0, 1.36, -0.1), light, { shape = BALL, neon = true })
	add("body", V(0.8, 0.7, 0.26), CFrame.new(0, 0.06, 0.56), panel, { mesh = SPH })
	for i, c in { rgb(255, 120, 110), rgb(250, 210, 90), light } do
		add("body", V(0.16, 0.16, 0.16), CFrame.new(-0.2 + (i - 1) * 0.2, 0.2, 0.66), c, { shape = BALL, neon = true })
	end
	add("body", V(0.56, 0.1, 0.1), CFrame.new(0, -0.1, 0.68), rgb(200, 206, 216))
	for _, j in { "armL", "armR" } do
		add(j, V(0.56, 0.18, 0.58), CFrame.new(0, -0.42, 0), panel, { mesh = SPH })
		add(j, V(0.5, 0.18, 0.52), CFrame.new(0, -0.74, 0), panel, { mesh = SPH })
	end
end

SKIN.wizard = function(add, col)
	local robe, star = rgb(74, 58, 140), rgb(250, 216, 96)
	add("head", V(0.22, 2.5, 2.5), CFrame.new(0, 0.54, -0.04) * VCYL, robe, { shape = CYL })
	add("head", V(0.18, 2.1, 2.1), CFrame.new(0, 0.66, -0.04) * VCYL, robe, { shape = CYL })
	for i = 1, 6 do
		local k = (i - 1) / 6
		add("head", V(0.3, 1.5 - k * 1.3, 1.5 - k * 1.3), CFrame.new(k * 0.16, 0.86 + (i - 1) * 0.28, -0.04 - k * 0.1) * VCYL, robe, { shape = CYL })
	end
	add("head", V(0.3, 0.3, 0.3), CFrame.new(0.2, 2.5, -0.2), star, { shape = BALL, neon = true })
	add("body", V(1.44, 1.5, 1.3), CFrame.new(0, 0.02, 0), robe, { mesh = SPH })
	add("body", V(1.5, 1.7, 0.4), CFrame.new(0, -0.1, -0.62), robe, { mesh = SPH })
	for i, off in { Vector3.new(-0.4, 0.3, 0), Vector3.new(0.36, -0.06, 0), Vector3.new(-0.16, -0.5, 0) } do
		add("body", V(0.2, 0.2, 0.12), CFrame.new(off.X, off.Y, -0.8), star, { shape = BALL, neon = true })
	end
end

SKIN.knight = function(add, col)
	local steel, plume = rgb(210, 216, 230), rgb(214, 66, 72)
	add("head", V(1.82, 1.8, 1.74), CFrame.new(0, 0.12, -0.16), steel, { shape = BALL, metal = true })
	add("head", V(1.5, 0.44, 0.24), CFrame.new(0, 0.02, 0.76), steel, { mesh = SPH, metal = true })
	add("head", V(1.48, 0.12, 0.28), CFrame.new(0, -0.02, 0.82), rgb(40, 42, 54), { mesh = SPH })
	add("head", V(0.3, 0.26, 1.6), CFrame.new(0, 0.96, -0.16), plume, { mesh = SPH })
	add("head", V(0.26, 0.5, 0.26), CFrame.new(0, 1.16, 0.3), plume, { mesh = SPH })
	add("body", V(1.44, 1.5, 1.3), CFrame.new(0, 0.04, 0), steel, { mesh = SPH, metal = true })
	add("body", V(0.6, 0.64, 0.2), CFrame.new(0, 0.18, 0.62), rgb(178, 186, 204), { mesh = SPH, metal = true })
	add("body", V(1.4, 0.26, 1.24), CFrame.new(0, -0.4, 0), rgb(92, 66, 52), { mesh = SPH })
	add("body", V(0.32, 0.3, 0.16), CFrame.new(0, -0.4, 0.62), rgb(238, 210, 120), { metal = true })
	for _, j in { "armL", "armR" } do
		add(j, V(0.76, 0.5, 0.74), CFrame.new(0, -0.08, 0), steel, { mesh = SPH, metal = true })
		add(j, V(0.54, 0.3, 0.56), CFrame.new(0, -0.8, 0), steel, { mesh = SPH, metal = true })
	end
end

SKIN.astronaut = function(add, col)
	local suit, trim, pack = rgb(250, 250, 252), rgb(250, 148, 52), rgb(196, 202, 214)
	local dome = add("head", V(2.0, 2.0, 2.0), CFrame.new(0, 0.06, 0.04), rgb(232, 246, 255), { shape = BALL, glass = true })
	dome.Transparency = 0.55
	dome.Reflectance = 0.14
	add("head", V(1.72, 0.3, 1.66), CFrame.new(0, -0.7, 0), suit, { mesh = SPH })
	add("head", V(1.5, 0.5, 0.36), CFrame.new(0, 0.42, 0.72), trim, { mesh = SPH })
	add("body", V(1.46, 1.52, 1.3), CFrame.new(0, 0.04, 0), suit, { mesh = SPH })
	add("body", V(0.96, 1.2, 0.64), CFrame.new(0, 0.1, -0.78), pack, { mesh = SPH })
	add("body", V(0.28, 0.9, 0.28), CFrame.new(0.44, 0.2, -0.96), trim, { mesh = SPH })
	add("body", V(0.6, 0.44, 0.22), CFrame.new(0, 0.1, 0.6), rgb(78, 84, 104), { mesh = SPH })
	add("body", V(0.16, 0.16, 0.16), CFrame.new(-0.14, 0.14, 0.7), rgb(120, 240, 200), { shape = BALL, neon = true })
	add("body", V(0.16, 0.16, 0.16), CFrame.new(0.14, 0.14, 0.7), rgb(255, 130, 120), { shape = BALL, neon = true })
	add("body", V(1.4, 0.2, 1.24), CFrame.new(0, -0.44, 0), trim, { mesh = SPH })
	for _, j in { "armL", "armR" } do
		add(j, V(0.56, 0.16, 0.58), CFrame.new(0, -0.3, 0), trim, { mesh = SPH })
		add(j, V(0.54, 0.3, 0.56), CFrame.new(0, -0.82, 0), trim, { mesh = SPH })
	end
	for _, j in { "legL", "legR" } do
		add(j, V(0.68, 0.34, 0.8), CFrame.new(0, -0.72, 0.08), pack, { mesh = SPH })
	end
end

SKIN.golden = function(add, col)
	local gold = rgb(255, 222, 128)
	add("head", V(1.5, 0.22, 1.44), CFrame.new(0, 0.6, 0), gold, { mesh = SPH, metal = true })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		add("head", V(0.18, 0.4, 0.18), CFrame.new(math.cos(a) * 0.6, 0.78, math.sin(a) * 0.6), gold, { mesh = SPH, metal = true })
	end
	add("body", V(1.4, 0.24, 1.24), CFrame.new(0, 0.44, 0), gold, { mesh = SPH, metal = true })
	add("body", V(0.36, 0.36, 0.2), CFrame.new(0, 0.3, 0.58), gold, { shape = BALL, metal = true })
end

-- charDef from Config.Characters, outfitId from Config.Outfits,
-- skinDef from Config.Skins (the whole-body look; nil or the "none" skin
-- leaves the plain Sminski body).
-- glow=false for decorations / UI previews.
function Models.buildSminski(parent, scale, charDef, glow, outfitId, skinDef)
	local s = scale or 1
	charDef = charDef or {}
	if skinDef and skinDef.id == "none" then skinDef = nil end
	-- THE SKIN WINS ON COLOUR unless it says keepBody, because a costume that
	-- is whatever colour your capsule happens to be is not a costume -- a pink
	-- knight is not a knight. keepBody skins (the hoodie, the tracksuit) are
	-- the ones designed to show your collection off instead.
	local col = charDef.body or Color3.fromRGB(218, 238, 186)
	local metal, neon, ghost = charDef.metal, charDef.neon, charDef.ghost
	if skinDef then
		if skinDef.body and not skinDef.keepBody then
			col = skinDef.body
			metal, neon, ghost = skinDef.metal, skinDef.neon, skinDef.ghost
		else
			metal = metal or skinDef.metal
		end
	end
	-- live characters get a glossy "jelly" finish; decorations stay matte
	local jelly = glow ~= false and not neon and not metal
	local mat = neon and Enum.Material.Neon or metal and Enum.Material.Metal or jelly and Enum.Material.Glass or SM
	local transp = ghost and 0.35 or jelly and 0.04 or 0
	local m = Instance.new("Model")
	m.Name = "Sminski_" .. (charDef.id or "Glow")
	local rig = { model = m, scale = s, def = charDef, parts = {} }

	local function add(joint, size, off, color, o)
		o = o or {}
		local mat2 = o.neon and Enum.Material.Neon or o.glass and Enum.Material.Glass or o.metal and Enum.Material.Metal or o.mat or SM
		local p = part(m, size * s, CFrame.new(), color, mat2, { shape = o.shape, mesh = o.mesh, transparency = o.transparency })
		if o.metal then p.Reflectance = 0.3 end
		table.insert(rig.parts, { p = p, joint = joint, off = CFrame.new(off.Position * s) * off.Rotation })
		return p
	end
	local function skin(joint, size, off, o)
		o = o or {}
		o.mat = mat
		o.transparency = transp
		local p = add(joint, size, off, col, o)
		if metal then p.Reflectance = 0.25 end
		return p
	end

	local smooth = Models.hasMeshes("SmHead", "SmTorso", "SmArm", "SmLeg")
	local function meshSkin(joint, name, face)
		local p, off = rigMesh(m, name, s, col, mat)
		p.Transparency = transp
		if metal then p.Reflectance = 0.25 end
		table.insert(rig.parts, { p = p, joint = joint, off = off })
		if face then
			local fp, foff = faceOverlay(m, name, s, RigMeshes.faces.sminski)
			table.insert(rig.parts, { p = fp, joint = joint, off = foff })
		end
		return p
	end
	if smooth then
		rig.body = meshSkin("body", "SmTorso")
		rig.head = meshSkin("head", "SmHead", true)
		rig.armL = meshSkin("armL", "SmArm")
		rig.armR = meshSkin("armR", "SmArm")
		rig.legL = meshSkin("legL", "SmLeg")
		rig.legR = meshSkin("legR", "SmLeg")
	end
	-- torso: rounded shoulders + soft column + rounded hips
	if not smooth then
	rig.body = skin("body", Vector3.new(1.3, 0.8, 1.12), CFrame.new(0, 0.62, 0), { mesh = SPH })
	skin("body", Vector3.new(1.05, 1.2, 1.2), CFrame.new(0, 0.02, 0) * VCYL, { shape = CYL })
	skin("body", Vector3.new(1.34, 0.85, 1.14), CFrame.new(0, -0.5, 0), { mesh = SPH })
	-- head + face
	rig.head = skin("head", Vector3.new(1.6, 1.6, 1.6), CFrame.new(), { shape = BALL })
	add("head", Vector3.new(0.1, 0.1, 0.1), CFrame.new(-0.25, -0.04, 0.76), FACE_COLOR, { shape = BALL })
	add("head", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0.25, -0.04, 0.76), FACE_COLOR, { shape = BALL })
	add("head", Vector3.new(0.14, 0.035, 0.05), CFrame.new(0.02, -0.3, 0.735) * CFrame.Angles(0, 0, 0.12), FACE_COLOR)
	-- limbs
	-- arms: smooth shoulder, soft sausage arm, round mitten hand
	for _, j in { "armL", "armR" } do
		skin(j, Vector3.new(0.46, 0.46, 0.46), CFrame.new(0, -0.05, 0), { shape = BALL })
		rig[j] = skin(j, Vector3.new(0.4, 1.12, 0.42), CFrame.new(0, -0.5, 0), { mesh = SPH })
		skin(j, Vector3.new(0.46, 0.46, 0.46), CFrame.new(0, -1.02, 0.03), { shape = BALL })
	end
	rig.legL = skin("legL", Vector3.new(0.58, 0.88, 0.62), CFrame.new(0, -0.38, 0.02), { mesh = SPH })
	rig.legR = skin("legR", Vector3.new(0.58, 0.88, 0.62), CFrame.new(0, -0.38, 0.02), { mesh = SPH })
	end

	-- the skin goes on before the hat, so a Party Hat still sits on top of a
	-- ninja hood rather than inside it
	if skinDef and SKIN[skinDef.id] then
		SKIN[skinDef.id](add, col)
	end
	if outfitId and ACC[outfitId] then
		ACC[outfitId](add)
	end

	-- leaf glider (hidden until a glide)
	if glow ~= false then
		rig.glider = {}
		local leaf = Color3.fromRGB(120, 205, 105)
		local function g(size, off, color, o)
			local p = add("head", size, off, color, o)
			p.Transparency = 1
			p.CastShadow = true
			table.insert(rig.glider, p)
		end
		g(Vector3.new(5.2, 0.45, 3.4), CFrame.new(0, 2.4, -0.2), leaf, { mesh = SPH })
		g(Vector3.new(0.12, 0.2, 3.4), CFrame.new(0, 2.62, -0.2), Color3.fromRGB(90, 160, 80))
		g(Vector3.new(0.25, 0.6, 0.25), CFrame.new(0, 2.5, -2.0), Color3.fromRGB(110, 80, 50))
		for _, sx in { -1, 1 } do
			g(Vector3.new(0.05, 1.9, 0.05), CFrame.new(sx * 1.25, 1.25, 0) * CFrame.Angles(0, 0, -sx * 0.37), Color3.fromRGB(240, 240, 230))
		end
	end

	if glow ~= false then
		local light = Instance.new("PointLight")
		light.Color = charDef.glow or Color3.fromRGB(190, 255, 150)
		light.Brightness = charDef.neon and 1.6 or 1.0
		light.Range = 13 * s
		light.Shadows = false
		light.Parent = rig.body
		rig.light = light
	end
	m.PrimaryPart = rig.body
	m.Parent = parent
	return rig
end

function Models.setGlider(rig, on)
	if not rig or not rig.glider then return end
	for _, p in rig.glider do
		p.Transparency = on and 0 or 1
	end
end

function Models.addTrail(rig, color)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.4, -0.3)
	a0.Parent = rig.body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, -0.3)
	a1.Parent = rig.body
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	t.Lifetime = 0.22
	t.LightEmission = 0.6
	t.FaceCamera = true
	t.Parent = rig.body
	rig.trail = t
	return t
end

-- rootCF sits at the feet; local +Z is forward.
-- opts: roll, lookBack (0..1), squash (0..1), stride
function Models.poseSminski(rig, rootCF, pose, t, opts)
	local s = rig.scale
	local roll = opts and opts.roll or 0
	local lookBack = opts and opts.lookBack or 0
	local squash = opts and opts.squash or 0
	local aL, aR, lL, lR = 0, 0, 0, 0
	local rL, rR = -0.1, 0.1
	local headTilt, headYaw = 0, 0
	local bodyCF = rootCF

	if pose == "run" then
		local sp = opts and opts.stride or 15
		local w = math.sin(t * sp)
		lL, lR = -w * 0.9, w * 0.9
		aL, aR = w * 1.0, -w * 1.0
		bodyCF = rootCF * CFrame.new(0, math.abs(math.cos(t * sp)) * 0.25 * s, 0) * CFrame.Angles(0.12, 0, roll)
	elseif pose == "jump" then
		aL, aR = -2.7, -2.7
		rL, rR = -0.4, 0.4
		lL, lR = -1.0, -0.6
		bodyCF = rootCF * CFrame.Angles(0.05, 0, roll)
	elseif pose == "fall" then
		aL, aR = -1.6, -1.6
		rL, rR = -1.1, 1.1
		lL, lR = -0.3, 0.2
		bodyCF = rootCF * CFrame.Angles(0.1, 0, roll)
	elseif pose == "slide" then
		bodyCF = rootCF * CFrame.new(0, 0.3 * s, -0.4 * s) * CFrame.Angles(-1.2, 0, roll)
		lL, lR = -0.35, -0.2
		aL, aR = 0.9, 0.9
		rL, rR = -0.5, 0.5
		headTilt = 0.5
	elseif pose == "surprised" then
		aL, aR = -2.9, -2.9
		rL, rR = -0.9, 0.9
		lL, lR = -0.5, 0.5
		headTilt = -0.35
		bodyCF = rootCF * CFrame.new(0, 0.35 * s, 0) * CFrame.Angles(-0.15, 0, roll)
	elseif pose == "hide" then
		-- hands up over the face
		aL, aR = -2.35, -2.35
		rL, rR = 0.45, -0.45
		headTilt = 0.2 + math.sin(t * 2) * 0.03
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 2) * 0.03 * s, 0) * CFrame.Angles(0.08, 0, 0)
	elseif pose == "peek" then
		aL, aR = -2.35, -0.15 + math.sin(t * 1.5) * 0.08
		rL, rR = 0.45, 0.12
		headTilt = 0.12
		headYaw = math.sin(t * 0.8) * 0.25
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 2) * 0.03 * s, 0)
	elseif pose == "yawn" then
		local k = (math.sin(t * 0.9) + 1) / 2
		aL, aR = -2.9 * k, -2.9 * k
		rL, rR = -0.2 - 0.3 * k, 0.2 + 0.3 * k
		headTilt = -0.35 * k
		bodyCF = rootCF * CFrame.new(0, 0.06 * k * s, 0)
	elseif pose == "yoga" then
		aL, aR = -3.0, -3.0
		rL, rR = 0.12, -0.12
		lL, lR = -0.2, -0.9
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 1.2) * 0.03 * s, 0) * CFrame.Angles(0, 0, math.sin(t * 1.2) * 0.03)
	elseif pose == "glide" then
		-- hanging from the leaf glider, legs dangling and swaying
		aL, aR = -2.85, -2.85
		rL, rR = -0.25, 0.25
		lL = 0.35 + math.sin(t * 6) * 0.15
		lR = 0.2 - math.sin(t * 6) * 0.15
		headTilt = -0.1
		bodyCF = rootCF * CFrame.Angles(0.18, 0, roll + math.sin(t * 2) * 0.06)
	elseif pose == "flail" then
		aL = -2.6 + math.sin(t * 22) * 0.6
		aR = -2.6 - math.sin(t * 22) * 0.6
		rL, rR = -0.6, 0.6
		lL, lR = math.sin(t * 18) * 0.8, -math.sin(t * 18) * 0.8
	elseif pose == "cheer" then
		aL = -2.9 + math.sin(t * 6) * 0.25
		aR = -2.9 - math.sin(t * 6) * 0.25
		rL, rR = -0.45, 0.45
		bodyCF = rootCF * CFrame.new(0, math.abs(math.sin(t * 6)) * 0.3 * s, 0)
	elseif pose == "sit" then
		bodyCF = rootCF * CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(-0.12, 0, 0)
		lL, lR = -1.5, -1.5
		aL, aR = -0.55, -0.55
		rL, rR = 0.3, -0.3
		headTilt = 0.12
	elseif pose == "hug" then
		bodyCF = rootCF * CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(0.18, 0, 0)
		lL, lR = -2.0, -2.0
		aL, aR = -1.25, -1.25
		rL, rR = 0.65, -0.65
		headTilt = 0.3
	else -- idle / breathing
		aL, aR = math.sin(t * 2) * 0.04, -math.sin(t * 2) * 0.04
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 2) * 0.03 * s, 0)
	end

	-- look over the shoulder: the body turns most of the way, the head a bit more
	if lookBack > 0 then
		bodyCF = bodyCF * CFrame.Angles(0, lookBack * 1.25, 0)
		headYaw += lookBack * 0.7
	end
	headYaw = math.clamp(headYaw, -1.2, 1.2)

	local sq = squash * 0.35
	local joints = {
		body = bodyCF * CFrame.new(0, (1.5 - sq) * s, 0),
		head = bodyCF * CFrame.new(0, (2.3 - sq) * s, 0) * CFrame.Angles(headTilt, headYaw, 0) * CFrame.new(0, 0.72 * s, 0),
		armL = bodyCF * CFrame.new(-0.62 * s, (2.08 - sq) * s, 0.04 * s) * CFrame.Angles(aL - 0.1, 0, rL),
		armR = bodyCF * CFrame.new(0.62 * s, (2.08 - sq) * s, 0.04 * s) * CFrame.Angles(aR - 0.1, 0, rR),
		legL = bodyCF * CFrame.new(-0.3 * s, 0.82 * s, 0) * CFrame.Angles(lL, 0, 0),
		legR = bodyCF * CFrame.new(0.3 * s, 0.82 * s, 0) * CFrame.Angles(lR, 0, 0),
	}
	for _, e in rig.parts do
		e.p.CFrame = joints[e.joint] * e.off
	end
end

---------------------------------------------------------------------------
-- GIANT KID
---------------------------------------------------------------------------
local KID_SKIN = Color3.fromRGB(255, 212, 180)
local KID_HOODIE = Color3.fromRGB(52, 60, 112)
local KID_HOODIE_DARK = Color3.fromRGB(40, 46, 88)
local KID_PANTS = Color3.fromRGB(150, 152, 170)
local KID_HAIR = Color3.fromRGB(110, 70, 45)
local KID_CAP = Color3.fromRGB(34, 38, 70)

-- chibi kid in a hoodie + cap. Limbs are capsules (cylinder + ball ends) so
-- joints read cleanly; legs have knees that bend while running.
-- opts: scale, hoodie, pants, skin, hair, cap (false = no cap), shoe
function Models.buildKid(parent, opts)
	opts = opts or {}
	local sc = opts.scale or 1
	local KID_HOODIE = opts.hoodie or KID_HOODIE
	local KID_HOODIE_DARK = opts.hoodie and opts.hoodie:Lerp(Color3.new(0, 0, 0), 0.22) or KID_HOODIE_DARK
	local KID_PANTS = opts.pants or KID_PANTS
	local KID_SKIN = opts.skin or KID_SKIN
	local KID_HAIR = opts.hair or KID_HAIR
	local KID_CAP = opts.capColor or KID_CAP
	local SHOE_STRIPE = opts.shoe or Color3.fromRGB(235, 85, 85)
	local m = Instance.new("Model")
	m.Name = opts.name or "GiantKid"
	local kid = { model = m, entries = {}, scale = sc }
	local VC = CFrame.Angles(0, 0, math.pi / 2) -- upright cylinder
	local HC = CFrame.new() -- cylinder along X (default)
	local function add(joint, size, off, color, kind, mat)
		local opts
		if kind == "ball" then
			opts = { shape = Enum.PartType.Ball }
		elseif kind == "cyl" then
			opts = { shape = Enum.PartType.Cylinder }
		elseif kind == "sph" then
			opts = { mesh = SPH }
		end
		local p = part(m, size * sc, CFrame.new(), color, mat or SM, opts)
		table.insert(kid.entries, { p = p, joint = joint, off = CFrame.new(off.Position * sc) * off.Rotation })
		return p
	end
	-- vertical capsule from y0 down to y1 (y1 < y0) on a joint
	local function capsule(joint, dia, y0, y1, color, z)
		z = z or 0
		local len = y0 - y1
		add(joint, Vector3.new(len, dia, dia), CFrame.new(0, (y0 + y1) / 2, z) * VC, color, "cyl")
		add(joint, Vector3.new(dia, dia, dia), CFrame.new(0, y0, z), color, "ball")
		add(joint, Vector3.new(dia, dia, dia), CFrame.new(0, y1, z), color, "ball")
	end

	local smooth = Models.hasMeshes("KidHead", "KidHoodie", "KidThigh", "KidShin", "KidShoeUpper", "KidSleeve", "KidHandL", "KidHandR", "KidCap", "KidHair")
	if smooth then
		local function mesh(joint, name, color, mat, tex)
			local p, off = rigMesh(m, name, sc, color, mat, tex)
			table.insert(kid.entries, { p = p, joint = joint, off = off })
			return p
		end
		local PANTS_DARK = KID_PANTS:Lerp(Color3.new(0, 0, 0), 0.12)
		for _, side in { "L", "R" } do
			mesh("thigh" .. side, "KidThigh", KID_PANTS)
			local shin = "shin" .. side
			mesh(shin, "KidShin", KID_PANTS)
			mesh(shin, "KidCuff", PANTS_DARK)
			mesh(shin, "KidShoeUpper", Color3.fromRGB(252, 252, 255))
			kid["sole" .. side] = mesh(shin, "KidSole", Color3.fromRGB(236, 236, 242))
			mesh(shin, "KidStripe", SHOE_STRIPE)
			mesh(shin, "KidLaces", Color3.fromRGB(230, 230, 235))
			local arm = "arm" .. side
			mesh(arm, "KidSleeve", KID_HOODIE)
			mesh(arm, "KidSleeveCuff", KID_HOODIE_DARK)
			kid["hand" .. side] = mesh(arm, "KidHand" .. side, KID_SKIN)
		end
		mesh("torso", "KidHoodie", KID_HOODIE)
		mesh("torso", "KidHips", KID_PANTS)
		mesh("torso", "KidTrim", KID_HOODIE_DARK)
		mesh("torso", "KidStrings", Color3.fromRGB(240, 240, 245))
		kid.head = mesh("head", "KidHead", KID_SKIN)
		do
			local fp, foff = faceOverlay(m, "KidHead", sc, (opts.face and RigMeshes.faces[opts.face]) or RigMeshes.faces.kid)
			table.insert(kid.entries, { p = fp, joint = "head", off = foff })
		end
		if opts.cap ~= false then
			mesh("head", "KidCap", KID_CAP)
			mesh("head", "KidCapButton", KID_CAP:Lerp(Color3.new(1, 1, 1), 0.2))
			mesh("head", "KidHair", KID_HAIR)
		else
			mesh("head", "KidHairFull", KID_HAIR)
			if opts.bun then mesh("head", "KidBun", KID_HAIR) end
		end
	end

	-- LEGS: thigh on the hip joint, shin + sneaker on the knee joint
	for _, side in { "L", "R" } do
		if smooth then break end
		capsule("thigh" .. side, 5.2, 0, -5.6, KID_PANTS)
		local shin = "shin" .. side
		capsule(shin, 4.9, 0, -4.6, KID_PANTS)
		add(shin, Vector3.new(1.2, 5.3, 5.3), CFrame.new(0, -5, 0) * VC, KID_PANTS:Lerp(Color3.new(0, 0, 0), 0.12), "cyl") -- cuff
		-- sneaker: sole, upper, rounded toe, stripe, laces
		add(shin, Vector3.new(5.8, 1.3, 8.6), CFrame.new(0, -7.7, 1.3), Color3.fromRGB(245, 245, 248))
		add(shin, Vector3.new(5.8, 1.3, 5.8), CFrame.new(0, -7.7, 4.9) * VC, Color3.fromRGB(245, 245, 248), "cyl")
		add(shin, Vector3.new(5.4, 3, 6.4), CFrame.new(0, -6, 0.6), Color3.fromRGB(252, 252, 255))
		add(shin, Vector3.new(5.4, 3.4, 5.4), CFrame.new(0, -6.2, 3.6), Color3.fromRGB(252, 252, 255), "sph")
		local stripe = add(shin, Vector3.new(5.5, 0.8, 8.7), CFrame.new(0, -7.1, 1.3), SHOE_STRIPE)
		kid["sole" .. side] = stripe
		add(shin, Vector3.new(2.2, 0.4, 2.8), CFrame.new(0, -4.5, 2.4) * CFrame.Angles(-0.35, 0, 0), Color3.fromRGB(230, 230, 235))
	end

	-- TORSO: rounded hoodie (block + cylinders along X for soft shoulders/hips)
	if not smooth then
	add("torso", Vector3.new(11.6, 8.4, 7.2), CFrame.new(0, 18.6, 0), KID_HOODIE)
	add("torso", Vector3.new(11.6, 7.2, 7.2), CFrame.new(0, 22.8, 0) * HC, KID_HOODIE, "cyl")
	add("torso", Vector3.new(11.8, 7.4, 7.4), CFrame.new(0, 14.4, 0) * HC, KID_PANTS, "cyl")
	add("torso", Vector3.new(12, 1.2, 7.6), CFrame.new(0, 15.2, 0), KID_HOODIE_DARK) -- hem
	add("torso", Vector3.new(7, 3, 0.8), CFrame.new(0, 17.4, 3.55), KID_HOODIE_DARK) -- pocket
	add("torso", Vector3.new(9, 4.2, 4.2), CFrame.new(0, 25.3, -2.6), KID_HOODIE_DARK, "sph") -- hood
	add("torso", Vector3.new(0.35, 3.2, 0.35), CFrame.new(-1.2, 23.4, 3.7), Color3.fromRGB(240, 240, 245))
	add("torso", Vector3.new(0.35, 3.2, 0.35), CFrame.new(1.2, 23.4, 3.7), Color3.fromRGB(240, 240, 245))
	add("torso", Vector3.new(0.7, 0.7, 0.7), CFrame.new(-1.2, 21.7, 3.75), Color3.fromRGB(240, 240, 245), "ball")
	add("torso", Vector3.new(0.7, 0.7, 0.7), CFrame.new(1.2, 21.7, 3.75), Color3.fromRGB(240, 240, 245), "ball")

	-- HEAD (joint at the neck): big round chibi head, cap worn backwards
	add("head", Vector3.new(4.4, 3, 4.4), CFrame.new(0, 0.6, 0) * VC, KID_SKIN, "cyl")
	kid.head = add("head", Vector3.new(11.5, 11.5, 11.5), CFrame.new(0, 6.8, 0), KID_SKIN, "ball")
	add("head", Vector3.new(1.8, 3.2, 2.4), CFrame.new(-5.8, 6.6, 0), KID_SKIN, "sph") -- ears
	add("head", Vector3.new(1.8, 3.2, 2.4), CFrame.new(5.8, 6.6, 0), KID_SKIN, "sph")
	if opts.cap ~= false then
		add("head", Vector3.new(12.3, 6.6, 12.3), CFrame.new(0, 10.4, -0.2), KID_CAP, "sph") -- cap dome
		add("head", Vector3.new(12.4, 1.4, 12.4), CFrame.new(0, 8.6, -0.2) * VC, KID_CAP, "cyl") -- cap band
		add("head", Vector3.new(9.5, 0.9, 6.5), CFrame.new(0, 8.4, -8) * CFrame.Angles(-0.12, 0, 0), KID_CAP, "sph") -- brim (backwards)
		add("head", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, 13.6, -0.2), KID_CAP:Lerp(Color3.new(1, 1, 1), 0.2), "ball") -- button
	else
		add("head", Vector3.new(12.2, 7.4, 12.4), CFrame.new(0, 9.8, -0.6), KID_HAIR, "sph") -- hair
		if opts.bun then
			add("head", Vector3.new(4.6, 4.6, 4.6), CFrame.new(0, 13.6, -2.4), KID_HAIR, "ball")
		end
	end
	-- hair poking out under the cap
	for i, x in { -3.6, -1.2, 1.4, 3.8 } do
		add("head", Vector3.new(3, 2.4, 2), CFrame.new(x, 8.3, 4.6) * CFrame.Angles(0.5, 0, (i - 2.5) * 0.25), KID_HAIR, "sph")
	end
	add("head", Vector3.new(3, 3, 2.4), CFrame.new(-5.2, 8, 1.4), KID_HAIR, "sph")
	add("head", Vector3.new(3, 3, 2.4), CFrame.new(5.2, 8, 1.4), KID_HAIR, "sph")
	-- face: big eyes with highlights, eyebrows, open "HEY!" mouth, blush
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(1.8, 2.5, 1), CFrame.new(sx * 2.3, 7.2, 5.05), Color3.fromRGB(35, 30, 45), "sph")
		add("head", Vector3.new(0.7, 0.7, 0.4), CFrame.new(sx * 2.3 + 0.35, 7.9, 5.5), Color3.fromRGB(255, 255, 255), "sph")
		add("head", Vector3.new(0.35, 0.35, 0.3), CFrame.new(sx * 2.3 - 0.35, 6.6, 5.5), Color3.fromRGB(255, 255, 255), "sph")
		add("head", Vector3.new(2, 0.5, 0.4), CFrame.new(sx * 2.3, 9.3, 4.85) * CFrame.Angles(0, 0, sx * -0.25), KID_HAIR)
		add("head", Vector3.new(2, 1.1, 0.4), CFrame.new(sx * 3.9, 5.3, 4.3), Color3.fromRGB(255, 160, 160), "sph")
	end
	add("head", Vector3.new(3, 2.2, 1), CFrame.new(0, 4.3, 5.05), Color3.fromRGB(140, 45, 60), "sph")
	add("head", Vector3.new(1.8, 0.8, 0.6), CFrame.new(0, 3.7, 5.3), Color3.fromRGB(245, 120, 130), "sph")
	add("head", Vector3.new(1.9, 0.5, 0.4), CFrame.new(0, 5.05, 5.35), Color3.fromRGB(255, 255, 255), "sph")

	-- ARMS (joint at the shoulder): capsule sleeves, cuffs, round hands
	for _, side in { "L", "R" } do
		local j = "arm" .. side
		capsule(j, 4.4, 0, -7.6, KID_HOODIE)
		add(j, Vector3.new(1.2, 4.7, 4.7), CFrame.new(0, -8.6, 0) * VC, KID_HOODIE_DARK, "cyl")
		kid["hand" .. side] = add(j, Vector3.new(4.4, 4.4, 4.4), CFrame.new(0, -10.8, 0.2), KID_SKIN, "ball")
		add(j, Vector3.new(1.6, 1.6, 1.6), CFrame.new(side == "L" and 1.8 or -1.8, -9.9, 1.2), KID_SKIN, "ball") -- thumb
	end
	end

	-- "HEY!" speech bubble
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 80)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 9 * sc, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.LightInfluence = 0
	local bubble = Instance.new("TextLabel")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 252, 244)
	bubble.Font = Enum.Font.FredokaOne
	bubble.TextScaled = true
	bubble.Text = "HEY!"
	bubble.TextColor3 = Color3.fromRGB(235, 85, 85)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.4, 0)
	c.Parent = bubble
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = Color3.fromRGB(60, 64, 52)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = bubble
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = bubble
	bubble.Parent = bb
	bb.Adornee = kid.head
	bb.Parent = kid.head
	kid.bubble = bb
	kid.bubbleText = bubble

	m.Parent = parent
	return kid
end

-- run: 0..1 running intensity, reach: 0..1 grabbing intensity
-- opts: phase (gait phase; default runs off the clock), throw (0..1)
function Models.poseKid(kid, rootCF, t, run, reach, opts)
	local ph = opts and opts.phase or t * 7.5
	local joints = Rigs.kidJoints(rootCF, ph, run, reach, t, kid.scale, opts and opts.throw)
	applyJoints(kid.model, kid.entries, joints)
	return ph
end

-- sitting at a desk, typing (the roommate in the lobby bedroom). seatCF sits
-- on the seat under the hips, facing the desk; opts.look turns the head.
function Models.poseKidSeated(kid, seatCF, t, opts)
	local s = kid.scale
	local look = opts and opts.look or 0
	local tap = math.sin(t * 13) * 0.05
	local sway = math.sin(t * 0.7) * 0.03
	local torso = seatCF * CFrame.new(0, -14 * s, 0) * CFrame.Angles(0.08 + sway, 0, 0)
	local thighL = torso * CFrame.new(-3 * s, 14 * s, 0) * CFrame.Angles(-math.pi / 2 + 0.12, 0, 0.06)
	local thighR = torso * CFrame.new(3 * s, 14 * s, 0) * CFrame.Angles(-math.pi / 2 + 0.12, 0, -0.06)
	local joints = {
		torso = torso,
		thighL = thighL,
		thighR = thighR,
		shinL = thighL * CFrame.new(0, -5.6 * s, 0) * CFrame.Angles(math.pi / 2 - 0.2, 0, 0),
		shinR = thighR * CFrame.new(0, -5.6 * s, 0) * CFrame.Angles(math.pi / 2 - 0.2, 0, 0),
		head = torso * CFrame.new(0, 25.6 * s, 0) * CFrame.Angles(-0.12 + math.sin(t * 2.3) * 0.03, look, look * 0.15),
		armL = torso * CFrame.new(-7.2 * s, 22.8 * s, 0) * CFrame.Angles(-1.18 + tap, 0, 0.2),
		armR = torso * CFrame.new(7.2 * s, 22.8 * s, 0) * CFrame.Angles(-1.18 - tap, 0, -0.2),
	}
	applyJoints(kid.model, kid.entries, joints)
end

-- over-ear headphones on a kid rig (glowing cups)
function Models.addHeadphones(kid, band, glow)
	local s = kid.scale
	local hc = RigMeshes.KidHead and 7.8 or 6.8
	local r = RigMeshes.KidHead and 7.0 or 6.0
	local function add(size, off, color, mat, shape)
		local p = part(kid.model, size * s, CFrame.new(), color, mat or SM, { shape = shape })
		table.insert(kid.entries, { p = p, joint = "head", off = CFrame.new(off.Position * s) * off.Rotation })
	end
	for _, sx in { -1, 1 } do
		add(Vector3.new(1.6, 4.2, 4.2), CFrame.new(sx * r, hc, 0) * CFrame.Angles(0, 0, 0), band, SM, Enum.PartType.Cylinder)
		add(Vector3.new(0.4, 3.2, 3.2), CFrame.new(sx * (r + 0.9), hc, 0), glow, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	-- the band follows the top of the head in a few short segments
	for i = -2, 2 do
		local ang = i * 0.32
		add(Vector3.new(r * 0.55, 0.9, 1.4), CFrame.new(math.sin(ang) * (r + 0.4), hc + math.cos(ang) * (r - 0.2), 0) * CFrame.Angles(0, 0, -ang), band)
	end
end

---------------------------------------------------------------------------
-- GIANT DOG (Dog Park map)
---------------------------------------------------------------------------
local FUR = Color3.fromRGB(232, 172, 92)
local FUR_LIGHT = Color3.fromRGB(248, 214, 150)
local FUR_DARK = Color3.fromRGB(196, 132, 64)

-- opts: scale, fur, light, dark, collar
function Models.buildDog(parent, o)
	o = o or {}
	local sc = o.scale or 1
	local FUR = o.fur or FUR
	local FUR_LIGHT = o.light or FUR_LIGHT
	local FUR_DARK = o.dark or FUR_DARK
	local m = Instance.new("Model")
	m.Name = o.name or "GiantDog"
	local dog = { model = m, entries = {}, scale = sc }
	local VC = CFrame.Angles(0, 0, math.pi / 2)
	local function add(joint, size, off, color, kind)
		local opts = kind == "ball" and { shape = Enum.PartType.Ball } or kind == "cyl" and { shape = Enum.PartType.Cylinder } or { mesh = SPH }
		local p = part(m, size * sc, CFrame.new(), color, SM, opts)
		table.insert(dog.entries, { p = p, joint = joint, off = CFrame.new(off.Position * sc) * off.Rotation })
		return p
	end
	if Models.hasMeshes("DogBody", "DogHead", "DogLeg", "DogPaw", "DogJaw", "DogEar", "DogTail") then
		local function mesh(joint, name, color, mat, tex)
			local p, off = rigMesh(m, name, sc, color, mat, tex)
			table.insert(dog.entries, { p = p, joint = joint, off = off })
			return p
		end
		mesh("body", "DogBody", FUR)
		mesh("body", "DogChest", FUR_LIGHT)
		mesh("body", "DogCollar", o.collar or Color3.fromRGB(220, 70, 80))
		local tag = mesh("body", "DogTag", Color3.fromRGB(255, 215, 80), Enum.Material.Metal)
		tag.Reflectance = 0.2
		dog.head = mesh("head", "DogHead", FUR)
		do
			local fp, foff = faceOverlay(m, "DogHead", sc, RigMeshes.faces.dog)
			table.insert(dog.entries, { p = fp, joint = "head", off = foff })
		end
		mesh("head", "DogSnout", FUR_LIGHT)
		mesh("head", "DogNose", Color3.fromRGB(40, 30, 30))
		dog.mouth = mesh("jaw", "DogJaw", FUR_LIGHT)
		mesh("jaw", "DogTongue", Color3.fromRGB(245, 120, 140))
		mesh("earL", "DogEar", FUR_DARK)
		mesh("earR", "DogEar", FUR_DARK)
		for _, leg in { "FL", "FR", "BL", "BR" } do
			mesh(leg, "DogLeg", FUR)
			mesh(leg, "DogPaw", FUR_LIGHT)
		end
		mesh("tail", "DogTail", FUR_LIGHT)
		m.Parent = parent
		return dog
	end
	-- body (joint at the body centre, facing +Z)
	add("body", Vector3.new(15, 13, 28), CFrame.new(0, 0, 0), FUR)
	add("body", Vector3.new(11, 10, 12), CFrame.new(0, -1.5, 9), FUR_LIGHT) -- chest
	add("body", Vector3.new(12, 6, 20), CFrame.new(0, 5, -1), FUR_DARK) -- back
	add("body", Vector3.new(11, 1.6, 11), CFrame.new(0, 5, 11.5) * CFrame.Angles(0.5, 0, 0) * VC, o.collar or Color3.fromRGB(220, 70, 80), "cyl") -- collar
	add("body", Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 1.2, 15), Color3.fromRGB(255, 215, 80), "ball") -- tag
	-- head (joint at the neck)
	add("head", Vector3.new(13, 12, 12), CFrame.new(0, 3, 3), FUR)
	add("head", Vector3.new(8, 6, 9), CFrame.new(0, 0, 9.5), FUR_LIGHT) -- snout
	add("head", Vector3.new(3.4, 2.6, 2.4), CFrame.new(0, 2.2, 13.8), Color3.fromRGB(40, 30, 30)) -- nose
	add("head", Vector3.new(1, 1, 0.6), CFrame.new(0.6, 2.9, 14.9), Color3.fromRGB(255, 255, 255))
	for _, sx in { -1, 1 } do
		add("head", Vector3.new(2.2, 2.8, 1.2), CFrame.new(sx * 3.2, 5.6, 8.6), Color3.fromRGB(35, 28, 30)) -- eyes
		add("head", Vector3.new(0.8, 0.8, 0.5), CFrame.new(sx * 3.2 + 0.5, 6.4, 9.2), Color3.fromRGB(255, 255, 255))
		add("ear" .. (sx < 0 and "L" or "R"), Vector3.new(3, 9, 6), CFrame.new(0, -3.8, 0), FUR_DARK) -- floppy ears
	end
	dog.mouth = add("jaw", Vector3.new(6.5, 2.4, 7), CFrame.new(0, 0, 3.6), FUR_LIGHT)
	add("jaw", Vector3.new(3.4, 1, 5), CFrame.new(0, -0.6, 4.6) * CFrame.Angles(-0.3, 0, 0), Color3.fromRGB(245, 120, 140)) -- tongue
	-- legs (joint at the shoulder/hip): capsules + paws
	for _, leg in { "FL", "FR", "BL", "BR" } do
		add(leg, Vector3.new(9, 4.6, 4.6), CFrame.new(0, -4.5, 0) * VC, FUR, "cyl")
		add(leg, Vector3.new(4.6, 4.6, 4.6), CFrame.new(0, 0, 0), FUR, "ball")
		add(leg, Vector3.new(5.6, 3, 6.6), CFrame.new(0, -9.4, 1), FUR_LIGHT) -- paw
	end
	-- tail
	add("tail", Vector3.new(3.4, 3.4, 11), CFrame.new(0, 0, -5), FUR_LIGHT)
	dog.head = dog.entries[6].p
	m.Parent = parent
	return dog
end

-- run: 0..1 gallop intensity, reach: 0..1 lunging for you
-- opts: phase (gait phase; default runs off the clock), pounce (0..1 through a leap)
function Models.poseDog(dog, rootCF, t, run, reach, opts)
	local ph = opts and opts.phase or t * 8
	local joints = Rigs.dogJoints(rootCF, ph, run, reach, t, dog.scale, opts and opts.pounce)
	applyJoints(dog.model, dog.entries, joints)
	return ph
end

return Models
