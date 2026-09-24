-- World: endless procedural house. Builds track segments ahead of the player,
-- deletes them behind, and keeps runtime records for obstacles, coins,
-- powerups and moving hazards.

return function(Models, Config)
	local World = {}

	local part = Models.part
	local SM = Enum.Material.SmoothPlastic
	local SPH = Enum.MeshType.Sphere
	local CYL = Enum.PartType.Cylinder
	local BALL = Enum.PartType.Ball

	local LANE_W = Config.LaneWidth
	local LANES = { -2 * LANE_W, -LANE_W, 0, LANE_W, 2 * LANE_W }
	local SEG_LEN = Config.SegmentLength
	local SEGS_AHEAD = 9
	local SEGS_BEHIND = 2

	local TOY_COLORS = {
		Color3.fromRGB(255, 105, 97), Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 225, 90),
		Color3.fromRGB(110, 200, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(170, 120, 230),
		Color3.fromRGB(255, 140, 190),
	}
	local GREEN_PALETTE = {
		Color3.fromRGB(150, 215, 120), Color3.fromRGB(190, 235, 150), Color3.fromRGB(120, 190, 110),
		Color3.fromRGB(230, 240, 160), Color3.fromRGB(170, 225, 190), Color3.fromRGB(255, 225, 120),
	}
	local PALETTE = TOY_COLORS
	local mapId = "house"
	local COIN_COLOR = Color3.fromRGB(255, 200, 60)
	local GOLD_COLOR = Color3.fromRGB(255, 150, 35)
	local MOON = Color3.fromRGB(150, 170, 255)
	local LAMP = Color3.fromRGB(255, 205, 140)

	-- fake volumetric light: a soft additive beam between two points
	local function lightShaft(parent, from, to, color, w0, w1, strength)
		local a = part(parent, Vector3.new(0.2, 0.2, 0.2), CFrame.new(from), color, SM, { transparency = 1, noShadow = true })
		local b = part(parent, Vector3.new(0.2, 0.2, 0.2), CFrame.new(to), color, SM, { transparency = 1, noShadow = true })
		local a0 = Instance.new("Attachment")
		a0.Parent = a
		local a1 = Instance.new("Attachment")
		a1.Parent = b
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - strength), NumberSequenceKeypoint.new(0.7, 1 - strength * 0.5), NumberSequenceKeypoint.new(1, 1) })
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = w0
		beam.Width1 = w1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = a
		return beam
	end
	World.lightShaft = lightShaft

	-- seeded so every player in a multiplayer match builds the same world
	local RNG = Random.new()
	-- luck-dependent rolls (gold coins, powerups) use their own stream so a
	-- player's upgrades can never change the shared layout
	local LRNG = Random.new()
	local forceWide = false
	local function pick(t) return t[RNG:NextInteger(1, #t)] end
	local function lerp(a, b, k) return a + (b - a) * k end

	World.LANES = LANES

	---------------------------------------------------------------------------
	-- REALISM: sculpted props (ReplicatedStorage.SminskiAssets) and material
	-- variants (MaterialService). Everything falls back to primitives if missing.
	---------------------------------------------------------------------------
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local MaterialService = game:GetService("MaterialService")
	local assetFolder

	local function asset(name)
		assetFolder = assetFolder or ReplicatedStorage:FindFirstChild("SminskiAssets")
		return assetFolder and assetFolder:FindFirstChild(name)
	end
	World.asset = asset

	-- realistic surface: Roblox's built-in PBR material, plus a custom
	-- MaterialVariant on top if one with this name exists in MaterialService
	local function variant(p, name, base)
		p.Material = base
		p.Reflectance = 0
		if MaterialService:FindFirstChild(name) then
			p.MaterialVariant = name
		end
		return p
	end
	local function hasVariant(_name)
		return true -- built-in PBR materials are always available
	end

	-- drop a sculpted asset so it fills a box (non-colliding, visual only)
	local function placeAsset(parent, name, cf, size)
		local src = asset(name)
		if not src then return nil end
		local c = src:Clone()
		local function prep(bp)
			bp.Anchored = true
			bp.CanCollide = false
			bp.CanQuery = false
			bp.CanTouch = false
		end
		if c:IsA("BasePart") then
			prep(c)
			-- assets can carry a base yaw (e.g. generated long along X instead of Z)
			local yaw = src:GetAttribute("YawDeg") or 0
			if yaw % 180 == 90 then
				size = Vector3.new(size.Z, size.Y, size.X)
			end
			if src:GetAttribute("TileZ") and size.Z > src.Size.Z * (size.X / src.Size.X) * 1.4 then
				-- long boxes get a row of copies (e.g. train cars) instead of one stretched mesh
				local pieceLen = src.Size.Z * (size.X / src.Size.X)
				local n = math.max(1, math.floor(size.Z / pieceLen + 0.5))
				local len = size.Z / n
				local holder = Instance.new("Model")
				holder.Name = name
				for i = 1, n do
					local piece = i == 1 and c or c:Clone()
					piece.Size = Vector3.new(size.X, size.Y, len * 0.97)
					piece.CFrame = cf * CFrame.new(0, 0, -size.Z / 2 + len * (i - 0.5))
					piece.Parent = holder
				end
				holder.Parent = parent
				return holder
			end
			c.Size = size
			c.CFrame = cf * CFrame.Angles(0, math.rad(yaw), 0)
		else
			for _, d in c:GetDescendants() do
				if d:IsA("BasePart") then prep(d) end
			end
			local bcf, ext = c:GetBoundingBox()
			if src:GetAttribute("TileZ") then
				-- long boxes get a row of cars fitted to the width/height
				local k = math.min(size.X / ext.X, size.Y / ext.Y)
				local n = math.max(1, math.floor(size.Z / (ext.Z * k) + 0.5))
				c:ScaleTo(c:GetScale() * k)
				local holder = Instance.new("Model")
				holder.Name = name
				for i = 1, n do
					local piece = i == 1 and c or c:Clone()
					local pb = piece:GetBoundingBox()
					piece.WorldPivot = CFrame.new(pb.Position)
					piece:PivotTo(cf * CFrame.new(0, 0, -size.Z / 2 + (size.Z / n) * (i - 0.5)))
					piece.Parent = holder
				end
				holder.Parent = parent
				return holder
			end
			local k = math.min(size.X / ext.X, size.Y / ext.Y, size.Z / ext.Z)
			c:ScaleTo(c:GetScale() * k)
			bcf = c:GetBoundingBox()
			-- pivot at the box centre with no rotation: the pieces carry the
			-- importer's 180° turn, which must not leak into the placement
			c.WorldPivot = CFrame.new(bcf.Position)
			-- props placed before the pivot fix were tuned facing the other way
			if src:GetAttribute("Flip") then cf = cf * CFrame.Angles(0, math.pi, 0) end
			c:PivotTo(cf)
		end
		c.Parent = parent
		return c
	end
	World.placeAsset = placeAsset

	-- obstacles are built into their own model; if a sculpted version exists,
	-- the primitive shapes turn invisible (they still do the collision) and the
	-- asset is fitted over them. Parts named "Keep"/"Ramp" stay visible.
	local pendingDress = {}
	local function newOb(model, kind, zone)
		local ob = Instance.new("Model")
		ob.Name = kind
		ob.Parent = model
		table.insert(pendingDress, { ob = ob, kind = kind, zone = zone })
		return ob
	end

	local function assetFor(kind, zone)
		local park = zone:sub(1, 4) == "Park"
		if kind == "block" then
			if park then return "DogBowl" end
			if zone == "Kitchen" or zone == "Bathroom" then return nil end
			return "ToyBlock"
		elseif kind == "bar" then
			if park or zone == "Kitchen" or zone == "Bathroom" or zone == "Backyard" then return nil end
			return "Pencil"
		elseif kind == "wall" then
			if park then return "ParkBin" end
			if zone == "Kitchen" or zone == "Bathroom" or zone == "Backyard" then return nil end
			return "BookStack"
		elseif kind == "train" then
			return "ToyTrain"
		end
		return nil
	end

	local function dressObstacle(ob, name)
		if not name or not asset(name) then return end
		local list = {}
		local minV = Vector3.new(math.huge, math.huge, math.huge)
		local maxV = -minV
		for _, d in ob:GetChildren() do
			if d:IsA("BasePart") and d.Name ~= "Keep" and d.Name ~= "Ramp" then
				table.insert(list, d)
				local h = d.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = d.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
							minV = minV:Min(w)
							maxV = maxV:Max(w)
						end
					end
				end
			end
		end
		if #list == 0 then return end
		if not placeAsset(ob, name, CFrame.new((minV + maxV) / 2), maxV - minV) then return end
		for _, d in list do
			d.Transparency = 1
			for _, g in d:GetChildren() do
				if g:IsA("SurfaceGui") or g:IsA("SpecialMesh") then g:Destroy() end
			end
		end
	end
	World.CENTER_LANE = 3
	local NARROW_MIN, NARROW_MAX = 2, 4

	---------------------------------------------------------------------------
	-- STATE
	---------------------------------------------------------------------------
	local root -- folder in workspace
	local coinPool = {}
	local coinPoolFolder

	World.segments = {}
	World.groups = {} -- obstacle groups (near-miss / dodge detection)
	World.movers = {}
	World.fallers = {}
	World.coins = {}
	World.pickups = {}

	local nextZ = 0
	local segCount = 0
	local zoneIdx = 1
	local zoneLeft = 6
	local safeLane = 3
	local zoneWide = false
	local ZONE_ORDER = { "Hallway", "Kitchen", "LivingRoom", "Backyard", "Bathroom", "Bedroom" }
	World.ZONE_TITLES = {
		GreenLounge = "the lounge", GreenLibrary = "the library", GreenBedroom = "the bunk room", GreenStairs = "the stairwell",
		ParkPath = "the park path", ParkPlayground = "the playground", ParkPond = "the duck pond",
		Hallway = "the hallway", Kitchen = "the kitchen", LivingRoom = "the living room",
		Backyard = "the backyard", Bathroom = "the bathroom", Bedroom = "the bedroom",
	}

	function World.init(parentFolder)
		root = parentFolder
		coinPoolFolder = Instance.new("Folder")
		coinPoolFolder.Name = "CoinPool"
	end

	---------------------------------------------------------------------------
	-- SMALL DECOR HELPERS
	---------------------------------------------------------------------------
	local function letterFace(p, text, color, face)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face or Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 1
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.Parent = sg
		sg.Parent = p
	end

	local function decorSminski(parent, cf, scale, pose)
		local defs = Config.Characters
		local def = RNG:NextNumber() < 0.7 and defs[1] or defs[RNG:NextInteger(2, #defs)]
		local outfit = RNG:NextNumber() < 0.35 and Config.Outfits[RNG:NextInteger(2, #Config.Outfits)].id or nil
		local rig = Models.buildSminski(parent, scale, def, false, outfit)
		Models.poseSminski(rig, cf, pose, RNG:NextNumber(0, 10))
		return rig
	end

	local function flower(parent, pos, h)
		local petal = pick({ Color3.fromRGB(255, 130, 170), Color3.fromRGB(255, 220, 90), Color3.fromRGB(180, 140, 255), Color3.fromRGB(255, 255, 255) })
		part(parent, Vector3.new(h, 1.2, 1.2), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(80, 160, 70), SM, { shape = CYL })
		local top = pos + Vector3.new(0, h, 0)
		part(parent, Vector3.new(3, 3, 3), CFrame.new(top), Color3.fromRGB(255, 200, 60), SM, { shape = BALL })
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			part(parent, Vector3.new(3.4, 3.4, 1.4), CFrame.new(top) * CFrame.Angles(0, 0, a) * CFrame.new(0, 3, -0.2), petal, SM, { mesh = SPH })
		end
		part(parent, Vector3.new(5, 1, 2.2), CFrame.new(pos + Vector3.new(1.8, h * 0.45, 0)) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(90, 175, 80), SM, { mesh = SPH })
	end

	local function toyCar(parent, pos, yaw, color)
		local c = color or pick(PALETTE)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		local parts = {}
		table.insert(parts, { part(parent, Vector3.new(6, 2.4, 11), cf * CFrame.new(0, 2.2, 0), c), CFrame.new(0, 2.2, 0) })
		table.insert(parts, { part(parent, Vector3.new(5.2, 2.2, 5.5), cf * CFrame.new(0, 4.4, -0.5), c), CFrame.new(0, 4.4, -0.5) })
		table.insert(parts, { part(parent, Vector3.new(5.3, 1.6, 5.6), cf * CFrame.new(0, 4.5, -0.5), Color3.fromRGB(160, 220, 255), Enum.Material.Glass, { transparency = 0.3 }), CFrame.new(0, 4.5, -0.5) })
		for _, o in { Vector3.new(-3, 1.2, 3.4), Vector3.new(3, 1.2, 3.4), Vector3.new(-3, 1.2, -3.4), Vector3.new(3, 1.2, -3.4) } do
			local off = CFrame.new(o) * CFrame.Angles(0, 0, math.pi / 2)
			table.insert(parts, { part(parent, Vector3.new(1.2, 2.4, 2.4), cf * off, Color3.fromRGB(40, 40, 45), SM, { shape = CYL }), off })
		end
		return parts
	end

	local function crayon(parent, pos, yaw)
		local c = pick(PALETTE)
		local cf = CFrame.new(pos + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, yaw, 0)
		part(parent, Vector3.new(12, 1.8, 1.8), cf, c, SM, { shape = CYL })
		part(parent, Vector3.new(6, 1.9, 1.9), cf, Color3.fromRGB(250, 250, 240), SM, { shape = CYL })
		part(parent, Vector3.new(2.4, 1.4, 1.4), cf * CFrame.new(7, 0, 0), c, SM, { shape = CYL })
	end

	local function ball(parent, pos, r)
		local p = part(parent, Vector3.new(r, r, r), CFrame.new(pos + Vector3.new(0, r / 2, 0)) * CFrame.Angles(RNG:NextNumber(0, 6), RNG:NextNumber(0, 6), 0), pick(PALETTE), SM, { shape = BALL })
		part(parent, Vector3.new(r * 1.01, r * 0.2, r * 1.01), p.CFrame, Color3.fromRGB(255, 255, 255), SM, { shape = CYL })
	end

	local function toyBlockDecor(parent, pos, size)
		local p = part(parent, Vector3.new(size, size, size), CFrame.new(pos + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, RNG:NextNumber(-0.5, 0.5), 0), pick(PALETTE))
		letterFace(p, string.char(RNG:NextInteger(65, 90)))
	end

	local function sock(parent, pos, yaw)
		local c = pick(PALETTE):Lerp(Color3.new(1, 1, 1), 0.3)
		local cf = CFrame.new(pos + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, yaw, 0)
		part(parent, Vector3.new(4, 1.8, 11), cf, c, Enum.Material.Fabric, { mesh = SPH })
		part(parent, Vector3.new(4, 1.8, 5), cf * CFrame.new(2.2, 0, 4.5) * CFrame.Angles(0, 0.9, 0), c, Enum.Material.Fabric, { mesh = SPH })
		part(parent, Vector3.new(4.1, 1.9, 2), cf * CFrame.new(0, 0, -4.8), Color3.fromRGB(255, 255, 255), Enum.Material.Fabric, { mesh = SPH })
	end

	local function rubberDuck(parent, pos, yaw, s)
		s = s or 1
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		if placeAsset(parent, "RubberDuck", cf * CFrame.new(0, 3.5 * s, 0), Vector3.new(6, 7, 7.5) * s) then return end
		local y = Color3.fromRGB(255, 215, 60)
		part(parent, Vector3.new(6, 4.5, 7.5) * s, cf * CFrame.new(0, 2.4 * s, 0), y, SM, { mesh = SPH })
		part(parent, Vector3.new(4, 4, 4) * s, cf * CFrame.new(0, 5.5 * s, 1.8 * s), y, SM, { shape = BALL })
		part(parent, Vector3.new(2.2, 0.8, 1.8) * s, cf * CFrame.new(0, 5.2 * s, 4 * s), Color3.fromRGB(255, 140, 40), SM, { mesh = SPH })
		part(parent, Vector3.new(0.5, 0.6, 0.4) * s, cf * CFrame.new(-1.1 * s, 6.1 * s, 3.5 * s), Color3.fromRGB(30, 30, 30), SM, { mesh = SPH })
		part(parent, Vector3.new(0.5, 0.6, 0.4) * s, cf * CFrame.new(1.1 * s, 6.1 * s, 3.5 * s), Color3.fromRGB(30, 30, 30), SM, { mesh = SPH })
	end

	local function scatterToy(parent, side, z)
		local x = side * RNG:NextNumber(21, 28)
		local pos = Vector3.new(x, 0, z)
		local r = RNG:NextInteger(1, 7)
		if r == 1 then
			toyCar(parent, pos, RNG:NextNumber(-0.6, 0.6))
		elseif r == 2 then
			crayon(parent, pos, RNG:NextNumber(0, math.pi))
		elseif r == 3 then
			ball(parent, pos, RNG:NextNumber(4, 7))
		elseif r == 4 then
			toyBlockDecor(parent, pos, RNG:NextNumber(3.5, 5))
		elseif r == 5 then
			sock(parent, pos, RNG:NextNumber(0, math.pi))
		else
			decorSminski(parent, CFrame.new(pos) * CFrame.Angles(0, side > 0 and -2.2 or 2.2, 0), RNG:NextNumber(1, 1.6), pick({ "sit", "hug", "cheer", "hide", "peek" }))
		end
	end

	local function sideWall(parent, z0, color, withWainscot)
		for _, side in { -1, 1 } do
			variant(part(parent, Vector3.new(2, 150, SEG_LEN), CFrame.new(side * 37, 75, z0 + SEG_LEN / 2), color, SM, { noShadow = true }), "SminskiWallPaint", Enum.Material.Plaster)
			part(parent, Vector3.new(1.6, 6, SEG_LEN), CFrame.new(side * 35.6, 3, z0 + SEG_LEN / 2), Color3.fromRGB(250, 248, 240))
			if withWainscot then
				part(parent, Vector3.new(0.8, 30, SEG_LEN), CFrame.new(side * 35.8, 15, z0 + SEG_LEN / 2), Color3.fromRGB(245, 242, 232))
				part(parent, Vector3.new(1.8, 1.4, SEG_LEN), CFrame.new(side * 35.5, 30.5, z0 + SEG_LEN / 2), Color3.fromRGB(255, 255, 250))
			end
		end
	end

	local function wallWindow(parent, side, z)
		local x = side * 35.8
		part(parent, Vector3.new(1.2, 44, 34), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
		part(parent, Vector3.new(1.4, 38, 28), CFrame.new(x, 68, z), Color3.fromRGB(95, 120, 215), Enum.Material.Neon, { noShadow = true })
		part(parent, Vector3.new(1.5, 5, 5), CFrame.new(x, 76, z + 7), Color3.fromRGB(255, 250, 215), Enum.Material.Neon, { shape = CYL, noShadow = true })
		lightShaft(parent, Vector3.new(x - side * 1, 68, z), Vector3.new(x - side * 30, 0.5, z + 12), MOON, 30, 36, 0.16)
		part(parent, Vector3.new(1.6, 38, 1.2), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
		part(parent, Vector3.new(1.6, 1.2, 28), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
		part(parent, Vector3.new(4, 1.5, 38), CFrame.new(x - side * 1.5, 46, z), Color3.fromRGB(255, 255, 255))
	end

	local function pictureFrame(parent, side, z)
		local x = side * 35.6
		local w, h = RNG:NextNumber(18, 30), RNG:NextNumber(20, 30)
		part(parent, Vector3.new(1.2, h, w), CFrame.new(x, 62, z), Color3.fromRGB(120, 80, 50))
		part(parent, Vector3.new(1.4, h - 3, w - 3), CFrame.new(x, 62, z), pick(PALETTE):Lerp(Color3.new(1, 1, 1), 0.35))
		part(parent, Vector3.new(1.6, 5, 5), CFrame.new(x, 66, z + w / 5), Color3.fromRGB(255, 220, 80), SM, { shape = CYL })
		part(parent, Vector3.new(1.5, h / 3, w - 3), CFrame.new(x, 62 - h / 3, z), Color3.fromRGB(120, 200, 110))
	end

	local function doorOnWall(parent, side, z)
		local x = side * 35.4
		part(parent, Vector3.new(1.5, 92, 44), CFrame.new(x, 46, z), Color3.fromRGB(255, 255, 255))
		part(parent, Vector3.new(1.8, 88, 38), CFrame.new(x, 44, z), Color3.fromRGB(215, 185, 150), Enum.Material.Wood)
		part(parent, Vector3.new(3.5, 3.5, 3.5), CFrame.new(x - side * 1.2, 42, z - 14), Color3.fromRGB(230, 200, 90), Enum.Material.Metal, { shape = BALL, reflect = 0.2 })
	end

	local function tileFloor(model, z0, a, b, size)
		size = size or 10
		if hasVariant("SminskiTiles") then
			variant(part(model, Vector3.new(70, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), a:Lerp(b, 0.25), Enum.Material.CeramicTiles, { walk = true }), "SminskiTiles", Enum.Material.CeramicTiles)
			return
		end
		local nx = math.floor(70 / size)
		local nz = math.floor(SEG_LEN / size)
		for ix = 0, nx - 1 do
			for iz = 0, nz - 1 do
				part(model, Vector3.new(size, 2, size), CFrame.new(-35 + size / 2 + ix * size, -1, z0 + size / 2 + iz * size), (ix + iz) % 2 == 0 and a or b, SM, { walk = true, reflect = 0.04 })
			end
		end
	end

	---------------------------------------------------------------------------
	-- ZONES
	---------------------------------------------------------------------------
	local ZONES = {}

	ZONES.Hallway = function(model, z0)
		if hasVariant("SminskiOakFloor") then
			variant(part(model, Vector3.new(70, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(150, 98, 62), Enum.Material.WoodPlanks, { walk = true }), "SminskiOakFloor", Enum.Material.WoodPlanks)
		end
		local woods = { Color3.fromRGB(176, 118, 72), Color3.fromRGB(163, 108, 66), Color3.fromRGB(186, 128, 80), Color3.fromRGB(154, 100, 60) }
		for i = 0, 13 do
			local x = -35 + 2.5 + i * 5
			local cut = RNG:NextNumber(18, SEG_LEN - 18)
			if hasVariant("SminskiOakFloor") then continue end
			part(model, Vector3.new(5, 2, cut - 0.3), CFrame.new(x, -1, z0 + cut / 2), pick(woods), Enum.Material.Wood, { walk = true })
			part(model, Vector3.new(5, 2, SEG_LEN - cut - 0.3), CFrame.new(x, -1, z0 + cut + (SEG_LEN - cut) / 2), pick(woods), Enum.Material.Wood, { walk = true })
		end
		part(model, Vector3.new(70, 1.8, SEG_LEN), CFrame.new(0, -1.1, z0 + SEG_LEN / 2), Color3.fromRGB(80, 50, 30), SM, { walk = true })
		sideWall(model, z0, Color3.fromRGB(246, 232, 205), true)
		for _, side in { -1, 1 } do
			local r = RNG:NextNumber()
			if r < 0.35 then
				pictureFrame(model, side, z0 + RNG:NextNumber(20, 60))
			elseif r < 0.6 then
				doorOnWall(model, side, z0 + 40)
			elseif r < 0.8 then
				wallWindow(model, side, z0 + 40)
			end
			if RNG:NextNumber() < 0.4 then
				local z = z0 + RNG:NextNumber(10, 70)
				part(model, Vector3.new(0.6, 7, 4.5), CFrame.new(side * 35.4, 14, z), Color3.fromRGB(252, 252, 248))
				part(model, Vector3.new(0.7, 1.4, 0.5), CFrame.new(side * 35.3, 15.5, z - 0.9), Color3.fromRGB(60, 60, 60))
				part(model, Vector3.new(0.7, 1.4, 0.5), CFrame.new(side * 35.3, 15.5, z + 0.9), Color3.fromRGB(60, 60, 60))
			end
			if RNG:NextNumber() < 0.7 then scatterToy(model, side, z0 + RNG:NextNumber(10, 70)) end
		end
	end

	ZONES.Kitchen = function(model, z0)
		tileFloor(model, z0, Color3.fromRGB(250, 250, 245), Color3.fromRGB(150, 200, 225))
		local cab = Color3.fromRGB(245, 240, 225)
		for _, side in { -1, 1 } do
			variant(part(model, Vector3.new(2, 150, SEG_LEN), CFrame.new(side * 45, 75, z0 + SEG_LEN / 2), Color3.fromRGB(255, 244, 215), SM, { noShadow = true }), "SminskiWallPaint", Enum.Material.Plaster)
			part(model, Vector3.new(0.6, 24, SEG_LEN), CFrame.new(side * 43.8, 48, z0 + SEG_LEN / 2), Color3.fromRGB(200, 230, 225))
			part(model, Vector3.new(16, 34, SEG_LEN), CFrame.new(side * 36, 17, z0 + SEG_LEN / 2), cab)
			part(model, Vector3.new(15, 3, SEG_LEN), CFrame.new(side * 36.5, 1.5, z0 + SEG_LEN / 2), Color3.fromRGB(90, 80, 70))
			part(model, Vector3.new(19, 2.6, SEG_LEN), CFrame.new(side * 35.5, 35.3, z0 + SEG_LEN / 2), Color3.fromRGB(130, 130, 140), Enum.Material.Granite)
			for i = 0, 3 do
				local z = z0 + 10 + i * 20
				part(model, Vector3.new(0.6, 26, 17), CFrame.new(side * 27.8, 18.5, z), Color3.fromRGB(235, 228, 210))
				part(model, Vector3.new(1.2, 1.2, 5), CFrame.new(side * 27.2, 27, z), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
			end
			part(model, Vector3.new(12, 30, SEG_LEN), CFrame.new(side * 38.5, 78, z0 + SEG_LEN / 2), cab)
			local r = RNG:NextNumber()
			local z = z0 + RNG:NextNumber(15, 65)
			if r < 0.3 then
				local box = part(model, Vector3.new(6, 22, 15), CFrame.new(side * 35, 47.6, z), pick(PALETTE))
				letterFace(box, "YUM", Color3.new(1, 1, 1), side > 0 and Enum.NormalId.Left or Enum.NormalId.Right)
			elseif r < 0.55 then
				part(model, Vector3.new(9, 8, 8), CFrame.new(side * 34, 41, z) * CFrame.Angles(0, 0, math.pi / 2), pick(PALETTE), SM, { shape = CYL })
			elseif r < 0.85 then
				decorSminski(model, CFrame.new(side * 32, 36.6, z) * CFrame.Angles(0, side > 0 and -1.9 or 1.9, 0), 1.8, pick({ "sit", "hug", "cheer" }))
			end
			for _ = 1, RNG:NextInteger(0, 3) do
				part(model, Vector3.new(0.8, 2.4, 2.4), CFrame.new(side * RNG:NextNumber(20, 26), 0.4, z0 + RNG:NextNumber(5, 75)) * CFrame.Angles(0, RNG:NextNumber(0, 3), math.pi / 2), Color3.fromRGB(230, 170, 80), SM, { shape = CYL })
			end
		end
	end

	ZONES.LivingRoom = function(model, z0)
		variant(part(model, Vector3.new(90, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(214, 198, 170), Enum.Material.Fabric, { walk = true }), "SminskiCarpet", Enum.Material.Carpet)
		part(model, Vector3.new(30, 0.12, SEG_LEN), CFrame.new(0, 0.04, z0 + SEG_LEN / 2), Color3.fromRGB(190, 80, 80), Enum.Material.Fabric, { noShadow = true })
		part(model, Vector3.new(25, 0.14, SEG_LEN), CFrame.new(0, 0.05, z0 + SEG_LEN / 2), Color3.fromRGB(240, 220, 180), Enum.Material.Fabric, { noShadow = true })
		for i = 0, 3 do
			part(model, Vector3.new(25, 0.16, 3), CFrame.new(0, 0.06, z0 + 10 + i * 20), Color3.fromRGB(80, 130, 180), Enum.Material.Fabric, { noShadow = true })
		end
		sideWall(model, z0, Color3.fromRGB(176, 200, 170), false)
		for _, side in { -1, 1 } do
			local r = RNG:NextNumber()
			if r < 0.45 then
				local c = pick({ Color3.fromRGB(90, 140, 190), Color3.fromRGB(230, 150, 90), Color3.fromRGB(150, 120, 200) })
				local x = side * 27
				local zc = z0 + SEG_LEN / 2
				if placeAsset(model, "Sofa", CFrame.new(side * 29, 11.2, zc) * CFrame.Angles(0, side > 0 and math.pi or 0, 0), Vector3.new(21.7, 22.4, 56)) then
					decorSminski(model, CFrame.new(side * 27, 9.5, zc + RNG:NextNumber(-18, 18)) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 2, pick({ "sit", "hug", "hide" }))
					continue
				end
				variant(part(model, Vector3.new(16, 12, 64), CFrame.new(x, 8, zc), c, Enum.Material.Fabric), "SminskiLinen", Enum.Material.Fabric)
				part(model, Vector3.new(5, 30, 64), CFrame.new(x + side * 6, 17, zc), c, Enum.Material.Fabric)
				for k = -1, 1 do
					part(model, Vector3.new(12, 4.5, 20), CFrame.new(x - side * 1.5, 16, zc + k * 20.6), c:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Fabric)
				end
				part(model, Vector3.new(16, 20, 5), CFrame.new(x, 12, zc - 34), c, Enum.Material.Fabric)
				part(model, Vector3.new(16, 20, 5), CFrame.new(x, 12, zc + 34), c, Enum.Material.Fabric)
				decorSminski(model, CFrame.new(x - side * 1.5, 18.3, zc + RNG:NextNumber(-20, 20)) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 2, pick({ "sit", "hug", "hide" }))
			elseif r < 0.7 then
				local x, z = side * 26, z0 + RNG:NextNumber(20, 60)
				local lampAsset = placeAsset(model, "FloorLamp", CFrame.new(x, 36, z), Vector3.new(18, 72, 18))
				if not lampAsset then
					part(model, Vector3.new(1.4, 12, 12), CFrame.new(x, 0.7, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 60, 60), SM, { shape = CYL })
					part(model, Vector3.new(70, 1.4, 1.4), CFrame.new(x, 35, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 60, 60), SM, { shape = CYL })
				end
				local shade = part(model, Vector3.new(14, 18, 18), CFrame.new(x, 70, z) * CFrame.Angles(0, 0, math.pi / 2), LAMP, Enum.Material.Neon, { shape = CYL })
				if lampAsset then
					-- keep the light, lose the primitive shade
					shade.Transparency = 1
					shade.Size = Vector3.new(2, 2, 2)
				end
				local l = Instance.new("PointLight")
				l.Color = LAMP
				l.Range = 60
				l.Brightness = 2.4
				l.Shadows = true
				l.Parent = shade
				lightShaft(model, Vector3.new(x, 63, z), Vector3.new(x, 0.5, z), LAMP, 16, 44, 0.2)
			else
				wallWindow(model, side, z0 + 40)
				-- giant TV remote on the floor
				if RNG:NextNumber() < 0.5 then
					local cf = CFrame.new(side * RNG:NextNumber(21, 27), 1, z0 + RNG:NextNumber(15, 65)) * CFrame.Angles(0, RNG:NextNumber(-0.4, 0.4), 0)
					part(model, Vector3.new(4.5, 2, 16), cf, Color3.fromRGB(45, 45, 50))
					part(model, Vector3.new(1.4, 0.4, 1.4), cf * CFrame.new(0, 1.1, 5.5), Color3.fromRGB(230, 70, 70), SM, { shape = CYL })
					for k = 0, 5 do
						part(model, Vector3.new(0.9, 0.3, 0.9), cf * CFrame.new(((k % 2) - 0.5) * 1.8, 1.1, 2 - k * 1.2), Color3.fromRGB(200, 200, 205))
					end
				end
			end
		end
	end

	ZONES.Backyard = function(model, z0)
		variant(part(model, Vector3.new(200, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(110, 180, 80), Enum.Material.Grass, { walk = true }), "SminskiLawn", Enum.Material.Grass)
		for i = 0, 3 do
			part(model, Vector3.new(38, 0.3, 17), CFrame.new(RNG:NextNumber(-0.8, 0.8), 0.05, z0 + 10 + i * 20) * CFrame.Angles(0, RNG:NextNumber(-0.05, 0.05), 0), Color3.fromRGB(185, 180, 170), Enum.Material.Slate, { noShadow = true })
		end
		for _, side in { -1, 1 } do
			for i = 0, 15 do
				part(model, Vector3.new(1, 32, 3.6), CFrame.new(side * 40, 16, z0 + 2.5 + i * 5), Color3.fromRGB(252, 252, 248))
				part(model, Vector3.new(1, 2.6, 2.6), CFrame.new(side * 40, 32.2, z0 + 2.5 + i * 5) * CFrame.Angles(math.rad(45), 0, 0), Color3.fromRGB(252, 252, 248))
			end
			part(model, Vector3.new(1.2, 2, SEG_LEN), CFrame.new(side * 39.2, 10, z0 + SEG_LEN / 2), Color3.fromRGB(240, 240, 235))
			part(model, Vector3.new(1.2, 2, SEG_LEN), CFrame.new(side * 39.2, 24, z0 + SEG_LEN / 2), Color3.fromRGB(240, 240, 235))
			for _ = 1, RNG:NextInteger(1, 2) do
				flower(model, Vector3.new(side * RNG:NextNumber(18, 34), 0, z0 + RNG:NextNumber(5, 75)), RNG:NextNumber(12, 26))
			end
			for _ = 1, 3 do
				local pos = Vector3.new(side * RNG:NextNumber(13, 36), 0, z0 + RNG:NextNumber(0, 80))
				for k = 1, 3 do
					part(model, Vector3.new(0.8, RNG:NextNumber(3, 6), 1.6), CFrame.new(pos) * CFrame.Angles(0, k * 2, (k - 2) * 0.35) * CFrame.new(0, 2, 0), Color3.fromRGB(90, 165, 70), SM, { mesh = SPH, noShadow = true })
				end
			end
			if RNG:NextNumber() < 0.6 and placeAsset(model, "ParkTree", CFrame.new(side * RNG:NextNumber(62, 90), 30, z0 + RNG:NextNumber(10, 70)) * CFrame.Angles(0, RNG:NextNumber(0, 6.28), 0), Vector3.new(56, 60, 56)) then
				-- sculpted tree placed
			elseif RNG:NextNumber() < 0.6 then
				local x, z = side * RNG:NextNumber(60, 90), z0 + RNG:NextNumber(10, 70)
				part(model, Vector3.new(60, 9, 9), CFrame.new(x, 30, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 85, 55), Enum.Material.Wood, { shape = CYL })
				for k = 1, 4 do
					part(model, Vector3.new(34, 30, 34) * RNG:NextNumber(0.8, 1.2), CFrame.new(x + RNG:NextNumber(-10, 10), 64 + RNG:NextNumber(-6, 10), z + RNG:NextNumber(-10, 10)), Color3.fromRGB(95, 170, 85):Lerp(Color3.fromRGB(140, 200, 100), k / 5), Enum.Material.Grass, { mesh = SPH })
				end
			end
			if RNG:NextNumber() < 0.45 then
				local z = z0 + RNG:NextNumber(10, 70)
				if RNG:NextNumber() < 0.5 then
					ball(model, Vector3.new(side * RNG:NextNumber(25, 31), 0, z), RNG:NextNumber(7, 10))
				else
					decorSminski(model, CFrame.new(side * RNG:NextNumber(21, 28), 0, z) * CFrame.Angles(0, side > 0 and -2.3 or 2.3, 0), RNG:NextNumber(1.2, 1.8), pick({ "cheer", "sit", "yoga" }))
				end
			end
		end
	end

	ZONES.Bathroom = function(model, z0)
		tileFloor(model, z0, Color3.fromRGB(245, 250, 250), Color3.fromRGB(200, 235, 225), 7)
		for _, side in { -1, 1 } do
			part(model, Vector3.new(2, 150, SEG_LEN), CFrame.new(side * 37, 75, z0 + SEG_LEN / 2), Color3.fromRGB(215, 235, 245), SM, { noShadow = true })
			-- tiled lower wall
			for i = 0, 7 do
				part(model, Vector3.new(0.6, 36, 9.6), CFrame.new(side * 35.8, 18, z0 + 5 + i * 10), i % 2 == 0 and Color3.fromRGB(170, 215, 225) or Color3.fromRGB(190, 228, 235), SM, { reflect = 0.05 })
			end
			local r = RNG:NextNumber()
			local zc = z0 + SEG_LEN / 2
			if r < 0.35 then
				-- bathtub
				local x = side * 26
				part(model, Vector3.new(18, 22, 70), CFrame.new(x, 11, zc), Color3.fromRGB(252, 252, 252), SM, { reflect = 0.08 })
				part(model, Vector3.new(14, 1, 64), CFrame.new(x, 21, zc), Color3.fromRGB(160, 215, 240), Enum.Material.Glass, { transparency = 0.2 })
				for k = 1, 6 do
					part(model, Vector3.new(3, 3, 3) * RNG:NextNumber(0.6, 1.4), CFrame.new(x + RNG:NextNumber(-5, 5), 22, zc + RNG:NextNumber(-28, 28)), Color3.fromRGB(255, 255, 255), SM, { shape = BALL, transparency = 0.1 })
				end
				rubberDuck(model, Vector3.new(x - side * 2, 21.5, zc + RNG:NextNumber(-15, 15)), RNG:NextNumber(0, 6), 0.8)
			elseif r < 0.6 then
				-- toilet
				local x, z = side * 27, z0 + RNG:NextNumber(20, 60)
				part(model, Vector3.new(14, 14, 16), CFrame.new(x + side * 4, 12, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(252, 252, 252), SM, { shape = CYL })
				part(model, Vector3.new(16, 3, 18), CFrame.new(x + side * 2, 19.5, z), Color3.fromRGB(245, 245, 245), SM, { mesh = SPH })
				part(model, Vector3.new(6, 26, 18), CFrame.new(x + side * 8, 28, z), Color3.fromRGB(252, 252, 252))
			else
				-- sink vanity with toothbrush cup and soap
				local x, z = side * 29, z0 + RNG:NextNumber(20, 60)
				part(model, Vector3.new(14, 30, 26), CFrame.new(x, 15, z), Color3.fromRGB(245, 235, 215))
				part(model, Vector3.new(15, 2, 28), CFrame.new(x, 31, z), Color3.fromRGB(240, 240, 245), Enum.Material.Marble)
				part(model, Vector3.new(7, 6, 6), CFrame.new(x, 35, z - 7) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(130, 200, 230), Enum.Material.Glass, { shape = CYL, transparency = 0.25 })
				part(model, Vector3.new(1, 14, 1), CFrame.new(x - 0.5, 40, z - 7) * CFrame.Angles(0, 0, 0.15), pick(PALETTE))
				part(model, Vector3.new(4, 2, 6), CFrame.new(x, 33, z + 7), Color3.fromRGB(255, 190, 210), SM, { mesh = SPH })
				decorSminski(model, CFrame.new(x - side * 3, 32, z + 1) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 1.6, pick({ "hide", "sit", "peek" }))
			end
			-- towel rack
			if RNG:NextNumber() < 0.5 then
				local z = z0 + RNG:NextNumber(15, 65)
				part(model, Vector3.new(1, 1, 24), CFrame.new(side * 35, 55, z), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
				part(model, Vector3.new(0.8, 26, 18), CFrame.new(side * 34.8, 43, z), pick(PALETTE):Lerp(Color3.new(1, 1, 1), 0.45), Enum.Material.Fabric)
			end
		end
		if RNG:NextNumber() < 0.5 then
			rubberDuck(model, Vector3.new(pick({ -1, 1 }) * RNG:NextNumber(22, 26), 0, z0 + RNG:NextNumber(10, 70)), RNG:NextNumber(0, 6), 1)
		end
	end

	ZONES.Bedroom = function(model, z0)
		variant(part(model, Vector3.new(90, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(196, 180, 220), Enum.Material.Fabric, { walk = true }), "SminskiCarpet", Enum.Material.Carpet)
		sideWall(model, z0, Color3.fromRGB(250, 222, 225), true)
		for _, side in { -1, 1 } do
			local r = RNG:NextNumber()
			local zc = z0 + SEG_LEN / 2
			if r < 0.4 then
				-- giant bed along the wall
				local x = side * 27
				local blanket = pick({ Color3.fromRGB(150, 190, 240), Color3.fromRGB(255, 190, 150), Color3.fromRGB(190, 230, 170) })
				part(model, Vector3.new(18, 10, 76), CFrame.new(x, 5, zc), Color3.fromRGB(190, 140, 100), Enum.Material.Wood)
				part(model, Vector3.new(17, 8, 74), CFrame.new(x, 14, zc), Color3.fromRGB(252, 250, 245), Enum.Material.Fabric)
				part(model, Vector3.new(18, 3, 50), CFrame.new(x - side * 0.3, 18.5, zc + 10), blanket, Enum.Material.Fabric)
				part(model, Vector3.new(1.5, 14, 50), CFrame.new(x - side * 9.2, 12, zc + 10), blanket, Enum.Material.Fabric)
				part(model, Vector3.new(13, 5, 14), CFrame.new(x, 20, zc - 28), Color3.fromRGB(255, 255, 255), Enum.Material.Fabric, { mesh = SPH })
				decorSminski(model, CFrame.new(x - side * 3, 20.5, zc + RNG:NextNumber(-8, 25)) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 2, pick({ "hug", "yawn", "sit" }))
			elseif r < 0.65 then
				-- desk + lamp
				local x, z = side * 28, z0 + RNG:NextNumber(20, 60)
				part(model, Vector3.new(16, 2, 30), CFrame.new(x, 30, z), Color3.fromRGB(230, 210, 180), Enum.Material.Wood)
				for _, o in { Vector3.new(-6, 15, -13), Vector3.new(6, 15, -13), Vector3.new(-6, 15, 13), Vector3.new(6, 15, 13) } do
					part(model, Vector3.new(1.6, 30, 1.6), CFrame.new(x + o.X, o.Y, z + o.Z), Color3.fromRGB(215, 195, 165), Enum.Material.Wood)
				end
				part(model, Vector3.new(6, 1, 9), CFrame.new(x, 31.5, z - 6), pick(PALETTE))
				part(model, Vector3.new(6, 1, 9), CFrame.new(x, 32.5, z - 6) * CFrame.Angles(0, 0.2, 0), pick(PALETTE))
				local lampShade = part(model, Vector3.new(5, 6, 6), CFrame.new(x, 40, z + 7) * CFrame.Angles(0, 0, math.pi / 2), LAMP, Enum.Material.Neon, { shape = CYL })
				part(model, Vector3.new(0.6, 8, 0.6), CFrame.new(x, 34, z + 7), Color3.fromRGB(80, 80, 80))
				local l = Instance.new("PointLight")
				l.Range = 45
				l.Brightness = 2.2
				l.Color = LAMP
				l.Shadows = true
				l.Parent = lampShade
				lightShaft(model, Vector3.new(x, 37.5, z + 7), Vector3.new(x - side * 4, 0.5, z + 7), LAMP, 5, 26, 0.18)
				decorSminski(model, CFrame.new(x - side * 2, 31, z + 2) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 1.3, "peek")
			else
				-- poster + toy chest
				part(model, Vector3.new(1, 30, 22), CFrame.new(side * 35.7, 60, z0 + RNG:NextNumber(20, 60)), pick(PALETTE):Lerp(Color3.new(1, 1, 1), 0.2))
				local cz = z0 + RNG:NextNumber(15, 65)
				local chest = part(model, Vector3.new(14, 12, 22), CFrame.new(side * 27, 6, cz), Color3.fromRGB(120, 170, 220))
				part(model, Vector3.new(14.6, 2, 22.6), CFrame.new(side * 27, 12.5, cz), Color3.fromRGB(255, 200, 80))
				letterFace(chest, "TOYS", Color3.new(1, 1, 1), side > 0 and Enum.NormalId.Left or Enum.NormalId.Right)
			end
			if RNG:NextNumber() < 0.6 then
				if RNG:NextNumber() < 0.5 then
					sock(model, Vector3.new(side * RNG:NextNumber(21, 25), 0, z0 + RNG:NextNumber(10, 70)), RNG:NextNumber(0, 6))
				else
					scatterToy(model, side, z0 + RNG:NextNumber(10, 70))
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- SMINSKI DOLLHOUSE zones: mint rooms, round windows, glowing lamps, Sminskis everywhere
	---------------------------------------------------------------------------
	local MINT_WALL = Color3.fromRGB(200, 236, 186)
	local MINT_TRIM = Color3.fromRGB(232, 250, 222)
	local WARM = Color3.fromRGB(255, 232, 140)

	local function dollSminski(model, cf, scale, pose)
		local defs = { Config.Characters[1], Config.Character("Lemon"), Config.Character("Sky"), Config.Character("Peach") }
		local rig = Models.buildSminski(model, scale, defs[RNG:NextInteger(1, #defs)], false, nil)
		Models.poseSminski(rig, cf, pose, RNG:NextNumber(0, 10))
	end

	local function greenShell(model, z0)
		-- pale plank floor
		local woods = { Color3.fromRGB(232, 214, 170), Color3.fromRGB(222, 202, 158), Color3.fromRGB(238, 222, 182) }
		for i = 0, 13 do
			part(model, Vector3.new(5, 2, SEG_LEN - 0.3), CFrame.new(-35 + 2.5 + i * 5, -1, z0 + SEG_LEN / 2), pick(woods), Enum.Material.Wood, { walk = true })
		end
		-- walls + ceiling (a dollhouse compartment)
		for _, side in { -1, 1 } do
			variant(part(model, Vector3.new(2, 70, SEG_LEN), CFrame.new(side * 37, 35, z0 + SEG_LEN / 2), MINT_WALL, SM, { noShadow = true }), "SminskiWallPaint", Enum.Material.Plaster)
			part(model, Vector3.new(1.6, 5, SEG_LEN), CFrame.new(side * 35.6, 2.5, z0 + SEG_LEN / 2), MINT_TRIM)
			-- round window with a glowing night sky
			local wz = z0 + RNG:NextNumber(25, 55)
			part(model, Vector3.new(1.2, 26, 26), CFrame.new(side * 36.2, 40, wz), MINT_TRIM, SM, { shape = CYL })
			part(model, Vector3.new(1.4, 22, 22), CFrame.new(side * 36, 40, wz), Color3.fromRGB(150, 185, 245), Enum.Material.Neon, { shape = CYL, noShadow = true })
			part(model, Vector3.new(1.6, 22, 1.2), CFrame.new(side * 35.9, 40, wz), MINT_TRIM)
			part(model, Vector3.new(1.6, 1.2, 22), CFrame.new(side * 35.9, 40, wz), MINT_TRIM)
			lightShaft(model, Vector3.new(side * 35, 40, wz), Vector3.new(side * 10, 0.5, wz + 8), Color3.fromRGB(190, 215, 255), 18, 26, 0.06)
		end
		part(model, Vector3.new(76, 2, SEG_LEN), CFrame.new(0, 66, z0 + SEG_LEN / 2), MINT_WALL, SM, { noShadow = true })
		-- rounded compartment frame at the start of each room
		for _, side in { -1, 1 } do
			part(model, Vector3.new(6, 70, 5), CFrame.new(side * 35, 35, z0), MINT_TRIM)
			part(model, Vector3.new(5, 12, 12), CFrame.new(side * 29, 59, z0) * CFrame.Angles(0, math.pi / 2, 0), MINT_TRIM, SM, { shape = CYL })
		end
		part(model, Vector3.new(70, 6, 5), CFrame.new(0, 64, z0), MINT_TRIM)
		-- hanging lamp with a warm glow cone
		local lz = z0 + SEG_LEN / 2
		part(model, Vector3.new(0.5, 12, 0.5), CFrame.new(0, 59, lz), Color3.fromRGB(120, 140, 110))
		local shade = part(model, Vector3.new(4, 12, 12), CFrame.new(0, 52, lz) * CFrame.Angles(0, 0, math.pi / 2), WARM, Enum.Material.Neon, { shape = CYL })
		local l = Instance.new("PointLight")
		l.Color = WARM
		l.Range = 55
		l.Brightness = 1.6
		l.Shadows = true
		l.Parent = shade
		lightShaft(model, Vector3.new(0, 50, lz), Vector3.new(0, 18, lz), WARM, 11, 30, 0.08)
	end

	ZONES.GreenLounge = function(model, z0)
		greenShell(model, z0)
		for _, side in { -1, 1 } do
			local x = side * 27
			local zc = z0 + RNG:NextNumber(25, 55)
			-- little sofa
			part(model, Vector3.new(14, 7, 26), CFrame.new(x, 3.5, zc), Color3.fromRGB(120, 185, 110), Enum.Material.Fabric)
			part(model, Vector3.new(4, 14, 26), CFrame.new(x + side * 6, 7, zc), Color3.fromRGB(110, 170, 100), Enum.Material.Fabric)
			dollSminski(model, CFrame.new(x - side * 1, 7, zc + RNG:NextNumber(-8, 8)) * CFrame.Angles(0, side > 0 and -1.6 or 1.6, 0), 1.6, pick({ "sit", "hug", "peek" }))
			-- floor lamp (glowing globe)
			local gz = z0 + RNG:NextNumber(8, 20)
			part(model, Vector3.new(0.8, 18, 0.8), CFrame.new(side * 26, 9, gz), Color3.fromRGB(90, 110, 90))
			local globe = part(model, Vector3.new(7, 7, 7), CFrame.new(side * 26, 20, gz), Color3.fromRGB(255, 245, 190), Enum.Material.Neon, { shape = BALL })
			local gl = Instance.new("PointLight")
			gl.Color = WARM
			gl.Range = 26
			gl.Brightness = 1.1
			gl.Parent = globe
		end
		-- round rug
		part(model, Vector3.new(0.12, 30, 30), CFrame.new(0, 0.06, z0 + 40) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(175, 220, 150), Enum.Material.Fabric, { shape = CYL, noShadow = true })
	end

	ZONES.GreenLibrary = function(model, z0)
		greenShell(model, z0)
		for _, side in { -1, 1 } do
			-- tall bookshelf with rows of books
			local x = side * 32
			local zc = z0 + RNG:NextNumber(20, 60)
			part(model, Vector3.new(8, 50, 26), CFrame.new(x, 25, zc), Color3.fromRGB(150, 200, 130))
			for row = 0, 4 do
				local y = 6 + row * 9.5
				part(model, Vector3.new(8.4, 1, 26), CFrame.new(x - side * 0.2, y - 3.5, zc), MINT_TRIM)
				local bz = zc - 11
				while bz < zc + 11 do
					local w = RNG:NextNumber(1.2, 2.2)
					local h = RNG:NextNumber(5, 7.5)
					part(model, Vector3.new(6, h, w), CFrame.new(x - side * 1.2, y - 3 + h / 2, bz + w / 2), pick(GREEN_PALETTE):Lerp(Color3.new(1, 1, 1), 0.15))
					bz += w + 0.15
				end
			end
			dollSminski(model, CFrame.new(x - side * 3, 44.1, zc + 6) * CFrame.Angles(0, side > 0 and -1.6 or 1.6, 0), 1.3, "sit")
		end
		-- desk with two Sminskis at little laptops
		local side = pick({ -1, 1 })
		local dz = z0 + RNG:NextNumber(20, 60)
		part(model, Vector3.new(10, 1.2, 16), CFrame.new(side * 24, 9, dz), Color3.fromRGB(215, 240, 200))
		for _, o in { -6, 6 } do
			part(model, Vector3.new(1, 9, 1), CFrame.new(side * 24 + 4, 4.5, dz + o), MINT_TRIM)
			part(model, Vector3.new(1, 9, 1), CFrame.new(side * 24 - 4, 4.5, dz + o), MINT_TRIM)
		end
		for _, o in { -4, 4 } do
			part(model, Vector3.new(0.3, 2.4, 3.4), CFrame.new(side * 26, 10.8, dz + o) * CFrame.Angles(0, 0, side * 0.2), Color3.fromRGB(70, 80, 70))
			dollSminski(model, CFrame.new(side * 20.5, 6, dz + o) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0), 1.2, "sit")
		end
	end

	ZONES.GreenBedroom = function(model, z0)
		greenShell(model, z0)
		for _, side in { -1, 1 } do
			-- bunk bed
			local x = side * 27
			local zc = z0 + RNG:NextNumber(25, 55)
			for _, y in { 4, 20 } do
				part(model, Vector3.new(14, 2, 28), CFrame.new(x, y, zc), Color3.fromRGB(215, 240, 200))
				part(model, Vector3.new(13, 1.6, 26), CFrame.new(x, y + 1.6, zc), Color3.fromRGB(250, 252, 245), Enum.Material.Fabric)
				part(model, Vector3.new(13.4, 1.2, 16), CFrame.new(x, y + 2.3, zc + 5), pick(GREEN_PALETTE), Enum.Material.Fabric)
			end
			for _, o in { Vector3.new(-6.5, 0, -13.5), Vector3.new(6.5, 0, -13.5), Vector3.new(-6.5, 0, 13.5), Vector3.new(6.5, 0, 13.5) } do
				part(model, Vector3.new(1.2, 26, 1.2), CFrame.new(x + o.X, 13, zc + o.Z), MINT_TRIM)
			end
			dollSminski(model, CFrame.new(x, 22.4, zc - 6) * CFrame.Angles(0, side > 0 and -1.6 or 1.6, 0), 1.4, pick({ "cheer", "yoga" }))
			dollSminski(model, CFrame.new(x, 6.4, zc - 8) * CFrame.Angles(0, side > 0 and -1.6 or 1.6, 0), 1.4, pick({ "hug", "sit", "yawn" }))
		end
	end

	ZONES.GreenStairs = function(model, z0)
		greenShell(model, z0)
		local side = pick({ -1, 1 })
		-- a white staircase climbing along one wall, a Sminski hiding underneath
		for i = 0, 11 do
			part(model, Vector3.new(12, 1.4, 5), CFrame.new(side * 29, 3 + i * 4.8, z0 + 10 + i * 5), MINT_TRIM)
			part(model, Vector3.new(12, 3.8 + i * 4.8, 1), CFrame.new(side * 29, (3.8 + i * 4.8) / 2, z0 + 12.2 + i * 5), Color3.fromRGB(220, 245, 210))
		end
		dollSminski(model, CFrame.new(side * 27, 0, z0 + 22) * CFrame.Angles(0, side > 0 and -1.6 or 1.6, 0), 1.6, "hug")
		dollSminski(model, CFrame.new(side * 29, 3 + 6 * 4.8 + 0.7, z0 + 40) * CFrame.Angles(0, math.pi, 0), 1.3, "peek")
		-- plant + tiny sminski on the other side
		local o = -side
		part(model, Vector3.new(6, 7, 6), CFrame.new(o * 27, 3.5, z0 + 40) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 245, 235), SM, { shape = CYL })
		for k = 1, 5 do
			part(model, Vector3.new(2, 7, 4), CFrame.new(o * 27, 9, z0 + 40) * CFrame.Angles(0, k * 1.25, 0.4) * CFrame.new(0, 2, 1.5), Color3.fromRGB(90, 170, 80), SM, { mesh = SPH })
		end
		dollSminski(model, CFrame.new(o * 22, 0, z0 + 55) * CFrame.Angles(0, o > 0 and -2 or 2, 0), 1.4, pick({ "cheer", "peek", "sit" }))
	end

	---------------------------------------------------------------------------
	-- DOG PARK zones: sunny grass, gravel path, trees, playground, pond
	---------------------------------------------------------------------------
	local function tree(model, x, z, s)
		s = s or 1
		if placeAsset(model, "ParkTree", CFrame.new(x, 30 * s, z) * CFrame.Angles(0, RNG:NextNumber(0, 6.28), 0), Vector3.new(56, 60, 56) * s) then return end
		part(model, Vector3.new(70 * s, 10 * s, 10 * s), CFrame.new(x, 35 * s, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(125, 90, 60), Enum.Material.Wood, { shape = CYL })
		for k = 1, 5 do
			part(model, Vector3.new(36, 30, 36) * s * RNG:NextNumber(0.8, 1.2), CFrame.new(x + RNG:NextNumber(-12, 12) * s, (72 + RNG:NextNumber(-8, 12)) * s, z + RNG:NextNumber(-12, 12) * s), Color3.fromRGB(95, 175, 80):Lerp(Color3.fromRGB(150, 210, 100), k / 6), Enum.Material.Grass, { mesh = SPH })
		end
	end

	local function parkGround(model, z0, pathColor)
		variant(part(model, Vector3.new(220, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(122, 196, 84), Enum.Material.Grass, { walk = true }), "SminskiLawn", Enum.Material.Grass)
		local path = part(model, Vector3.new(40, 0.3, SEG_LEN), CFrame.new(0, 0.05, z0 + SEG_LEN / 2), pathColor or Color3.fromRGB(222, 202, 160), Enum.Material.Sand, { noShadow = true })
		if not pathColor then variant(path, "SminskiGravel", Enum.Material.Pebble) end
		for _, side in { -1, 1 } do
			part(model, Vector3.new(2, 0.5, SEG_LEN), CFrame.new(side * 20.5, 0.2, z0 + SEG_LEN / 2), Color3.fromRGB(190, 185, 175), Enum.Material.Slate)
			-- iron fence far out
			for i = 0, 7 do
				part(model, Vector3.new(0.8, 22, 0.8), CFrame.new(side * 70, 11, z0 + 5 + i * 10), Color3.fromRGB(45, 50, 55), Enum.Material.Metal)
			end
			part(model, Vector3.new(0.8, 1, SEG_LEN), CFrame.new(side * 70, 20, z0 + SEG_LEN / 2), Color3.fromRGB(45, 50, 55), Enum.Material.Metal)
		end
	end

	local function parkBench(model, x, z, side)
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, side > 0 and -math.pi / 2 or math.pi / 2, 0)
		if placeAsset(model, "ParkBench", cf * CFrame.new(0, 5.3, 0), Vector3.new(22, 10.6, 8.4)) then return end
		part(model, Vector3.new(22, 1.4, 6), cf * CFrame.new(0, 7, 0), Color3.fromRGB(170, 115, 70), Enum.Material.Wood)
		part(model, Vector3.new(22, 5, 1.2), cf * CFrame.new(0, 11, -2.8), Color3.fromRGB(170, 115, 70), Enum.Material.Wood)
		for _, o in { -9, 9 } do
			part(model, Vector3.new(1.2, 7, 5), cf * CFrame.new(o, 3.5, 0), Color3.fromRGB(50, 55, 60), Enum.Material.Metal)
		end
	end

	ZONES.ParkPath = function(model, z0)
		parkGround(model, z0)
		for _, side in { -1, 1 } do
			if RNG:NextNumber() < 0.8 then tree(model, side * RNG:NextNumber(40, 60), z0 + RNG:NextNumber(10, 70), RNG:NextNumber(0.8, 1.2)) end
			if RNG:NextNumber() < 0.6 then parkBench(model, side * 27, z0 + RNG:NextNumber(15, 65), side) end
			-- lamp post
			local lz = z0 + RNG:NextNumber(5, 75)
			part(model, Vector3.new(1.2, 34, 1.2), CFrame.new(side * 24, 17, lz), Color3.fromRGB(45, 50, 55), Enum.Material.Metal)
			part(model, Vector3.new(3.6, 4, 3.6), CFrame.new(side * 24, 35, lz), Color3.fromRGB(255, 245, 200), Enum.Material.Neon)
			-- flower bed
			for _ = 1, 4 do
				part(model, Vector3.new(1.6, 1.6, 1.6), CFrame.new(side * RNG:NextNumber(24, 34), 0.8, z0 + RNG:NextNumber(0, 80)), pick({ Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 220, 90), Color3.fromRGB(180, 140, 255) }), SM, { shape = BALL })
			end
			if RNG:NextNumber() < 0.35 then
				ball(model, Vector3.new(side * RNG:NextNumber(25, 34), 0, z0 + RNG:NextNumber(10, 70)), 3.6)
			end
		end
	end

	ZONES.ParkPlayground = function(model, z0)
		parkGround(model, z0, Color3.fromRGB(230, 130, 110))
		local side = pick({ -1, 1 })
		-- slide
		local sx, sz = side * 36, z0 + 30
		part(model, Vector3.new(10, 26, 10), CFrame.new(sx, 13, sz), Color3.fromRGB(90, 160, 230))
		part(model, Vector3.new(8, 1.2, 34), CFrame.new(sx - side * 0, 13, sz + 20) * CFrame.Angles(-0.65, 0, 0), Color3.fromRGB(255, 200, 70))
		for i = 0, 6 do
			part(model, Vector3.new(8, 0.8, 0.8), CFrame.new(sx, 3 + i * 3.6, sz - 6), Color3.fromRGB(240, 90, 90))
		end
		-- sandbox on the other side
		local o = -side
		part(model, Vector3.new(26, 2, 30), CFrame.new(o * 38, 0.5, z0 + 45), Color3.fromRGB(235, 215, 160), Enum.Material.Sand)
		for _, e in { Vector3.new(0, 1.5, 15), Vector3.new(0, 1.5, -15) } do
			part(model, Vector3.new(28, 3, 1.4), CFrame.new(o * 38 + e.X, e.Y, z0 + 45 + e.Z), Color3.fromRGB(170, 115, 70), Enum.Material.Wood)
		end
		part(model, Vector3.new(4, 5, 4), CFrame.new(o * 34, 3, z0 + 42), Color3.fromRGB(240, 90, 90))
		decorSminski(model, CFrame.new(o * 40, 1.5, z0 + 48) * CFrame.Angles(0, o > 0 and -2 or 2, 0), 1.6, "cheer")
		-- swings
		local wz = z0 + RNG:NextNumber(55, 70)
		for _, d in { -8, 8 } do
			part(model, Vector3.new(1, 32, 1), CFrame.new(side * 32, 16, wz + d), Color3.fromRGB(80, 90, 100), Enum.Material.Metal)
		end
		part(model, Vector3.new(1, 1, 18), CFrame.new(side * 32, 32, wz), Color3.fromRGB(80, 90, 100), Enum.Material.Metal)
		part(model, Vector3.new(5, 0.8, 3), CFrame.new(side * 32, 8, wz), Color3.fromRGB(240, 90, 90))
		tree(model, side * -58, z0 + 20, 1)
	end

	ZONES.ParkPond = function(model, z0)
		parkGround(model, z0)
		local side = pick({ -1, 1 })
		-- the pond
		part(model, Vector3.new(60, 0.4, SEG_LEN), CFrame.new(side * 55, 0.25, z0 + SEG_LEN / 2), Color3.fromRGB(95, 165, 215), Enum.Material.Glass, { transparency = 0.15, noShadow = true, reflect = 0.2 })
		part(model, Vector3.new(3, 1.2, SEG_LEN), CFrame.new(side * 25.5, 0.4, z0 + SEG_LEN / 2), Color3.fromRGB(175, 170, 160), Enum.Material.Slate)
		for _ = 1, 3 do
			part(model, Vector3.new(0.2, 5, 5), CFrame.new(side * RNG:NextNumber(32, 70), 0.5, z0 + RNG:NextNumber(5, 75)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(90, 170, 90), SM, { shape = CYL })
		end
		for _ = 1, 2 do
			rubberDuck(model, Vector3.new(side * RNG:NextNumber(35, 70), 0.4, z0 + RNG:NextNumber(10, 70)), RNG:NextNumber(0, 6), 1.2)
		end
		for _ = 1, 6 do
			part(model, Vector3.new(0.6, RNG:NextNumber(5, 10), 0.6), CFrame.new(side * RNG:NextNumber(26, 30), 3, z0 + RNG:NextNumber(0, 80)), Color3.fromRGB(110, 150, 70))
		end
		tree(model, -side * RNG:NextNumber(40, 60), z0 + RNG:NextNumber(10, 70), 1.1)
		if RNG:NextNumber() < 0.6 then parkBench(model, -side * 27, z0 + RNG:NextNumber(15, 65), -side) end
	end

	local function doorway(model, z)
		if mapId == "dogpark" then
			-- park gate: two stone pillars and an arch sign
			for _, sx in { -1, 1 } do
				part(model, Vector3.new(6, 30, 6), CFrame.new(sx * 24, 15, z), Color3.fromRGB(190, 185, 175), Enum.Material.Slate)
				part(model, Vector3.new(7, 3, 7), CFrame.new(sx * 24, 31.5, z), Color3.fromRGB(170, 165, 155), Enum.Material.Slate)
			end
			part(model, Vector3.new(50, 5, 1.5), CFrame.new(0, 34, z), Color3.fromRGB(60, 120, 70))
			return
		end
		if mapId == "dollhouse" then return end -- rooms already have rounded frames
		local wallC = Color3.fromRGB(250, 240, 222)
		for _, side in { -1, 1 } do
			part(model, Vector3.new(34, 150, 3), CFrame.new(side * 40, 75, z), wallC)
			part(model, Vector3.new(4, 60, 4.5), CFrame.new(side * 22, 30, z), Color3.fromRGB(255, 255, 255))
		end
		part(model, Vector3.new(48, 90, 3), CFrame.new(0, 105, z), wallC)
		part(model, Vector3.new(48, 4, 4.5), CFrame.new(0, 60, z), Color3.fromRGB(255, 255, 255))
	end

	---------------------------------------------------------------------------
	-- OBSTACLES (themed per zone)
	---------------------------------------------------------------------------
	local function addGroup(kind, lane, z0, z1, top, bottom)
		local g = { kind = kind, lane = lane, x = LANES[lane], z0 = z0, z1 = z1, top = top, bottom = bottom or 0, minGap = math.huge, minClear = math.huge, inLane = false, resolved = false }
		table.insert(World.groups, g)
		return g
	end

	local OBS = {}

	-- low obstacle: jump it
	local isPark = function(zone) return zone:sub(1, 4) == "Park" end

	OBS.block = function(model, zone, lane, z)
		local x = LANES[lane]
		local d = 4.2
		if isPark(zone) then
			-- dog bowl full of kibble
			part(model, Vector3.new(3.4, 5.4, 5.4), CFrame.new(x, 1.7, z + 2.7) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(225, 70, 80), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(0.6, 4.4, 4.4), CFrame.new(x, 3.4, z + 2.7) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(160, 100, 55), SM, { shape = CYL })
			local lbl = part(model, Vector3.new(3, 1.6, 0.1), CFrame.new(x, 1.8, z - 0.02), Color3.fromRGB(255, 255, 255), SM, { noShadow = true })
			letterFace(lbl, "DOG", Color3.fromRGB(225, 70, 80))
			return 5.4, 3.4
		end
		if zone == "Kitchen" then
			local p = part(model, Vector3.new(4.2, 4.6, 4.6), CFrame.new(x, 2.1, z + 2.1) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(200, 200, 210), Enum.Material.Metal, { shape = CYL, obs = true, reflect = 0.15 })
			part(model, Vector3.new(2.6, 4.7, 4.7), p.CFrame, pick(PALETTE), SM, { shape = CYL })
			return d, 4.2
		elseif zone == "Bathroom" then
			local p = part(model, Vector3.new(5, 3.6, d), CFrame.new(x, 1.8, z + d / 2), Color3.fromRGB(255, 185, 205), SM, { obs = true })
			letterFace(p, "soap", Color3.fromRGB(255, 255, 255))
			for k = 1, 3 do
				part(model, Vector3.new(1, 1, 1) * RNG:NextNumber(0.6, 1.2), CFrame.new(x + RNG:NextNumber(-2, 2), 3.8, z + RNG:NextNumber(0.5, 3.5)), Color3.fromRGB(255, 255, 255), SM, { shape = BALL, noShadow = true })
			end
			return d, 3.6
		elseif zone == "Backyard" then
			part(model, Vector3.new(4, 5, 5), CFrame.new(x, 2, z + 2.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(200, 110, 70), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(0.6, 5.4, 5.4), CFrame.new(x, 3.9, z + 2.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(185, 100, 60), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(3, 1.6, 3), CFrame.new(x, 4.6, z + 2.5), Color3.fromRGB(100, 180, 80), SM, { mesh = SPH, noShadow = true })
			return 5, 4.2
		end
		local p = part(model, Vector3.new(4.8, 4.2, d), CFrame.new(x, 2.1, z + d / 2), pick(PALETTE), SM, { obs = true })
		letterFace(p, string.char(RNG:NextInteger(65, 90)))
		return d, 4.2
	end

	-- overhead obstacle resting on two supports: slide under it
	OBS.bar = function(model, zone, lane, z)
		local x = LANES[lane]
		local y = 3.4
		local supportColor = Color3.fromRGB(255, 150, 170)
		local cf = CFrame.new(x, y, z + 0.75)
		if isPark(zone) then
			-- low park bench seat: slide under it
			part(model, Vector3.new(6.8, 0.9, 3), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(170, 115, 70), Enum.Material.Wood, { obs = true })
			supportColor = Color3.fromRGB(50, 55, 60)
		elseif zone == "Bathroom" then
			part(model, Vector3.new(6.8, 1.2, 1.2), cf, pick(PALETTE), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(2.2, 1.6, 1.4), cf * CFrame.new(-2.6, 0.9, 0), Color3.fromRGB(255, 255, 255), SM, { noShadow = true })
			supportColor = Color3.fromRGB(190, 230, 250)
		elseif zone == "Kitchen" then
			part(model, Vector3.new(6.8, 1.2, 1.4), cf, Color3.fromRGB(200, 150, 100), Enum.Material.Wood, { shape = CYL, obs = true })
			part(model, Vector3.new(2.8, 1.6, 2.4), cf * CFrame.new(3.6, 0, 0), Color3.fromRGB(200, 150, 100), Enum.Material.Wood, { mesh = SPH })
			supportColor = Color3.fromRGB(250, 250, 250)
		elseif zone == "Backyard" then
			part(model, Vector3.new(7, 1.3, 1.3), cf * CFrame.Angles(0.05, 0, 0.04), Color3.fromRGB(130, 95, 60), Enum.Material.Wood, { shape = CYL, obs = true })
			supportColor = Color3.fromRGB(160, 160, 155)
		else
			local p = part(model, Vector3.new(6.6, 1.5, 1.5), cf, Color3.fromRGB(255, 200, 50), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(1.4, 1.52, 1.52), p.CFrame * CFrame.new(3.8, 0, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, { shape = CYL })
			part(model, Vector3.new(1.4, 1.5, 1.5), p.CFrame * CFrame.new(5.1, 0, 0), Color3.fromRGB(255, 150, 170), SM, { shape = CYL })
			part(model, Vector3.new(1.8, 1.1, 1.1), p.CFrame * CFrame.new(-4.1, 0, 0), Color3.fromRGB(245, 220, 170), SM, { shape = CYL })
			part(model, Vector3.new(0.8, 0.6, 0.6), p.CFrame * CFrame.new(-5.2, 0, 0), Color3.fromRGB(50, 50, 50), SM, { shape = CYL })
		end
		for _, s in { -1, 1 } do
			part(model, Vector3.new(1.1, y - 0.7, 2.2), CFrame.new(x + s * 3.3, (y - 0.7) / 2, z + 0.75), supportColor, SM, { obs = true }).Name = "Keep"
		end
		part(model, Vector3.new(6, 0.08, 1), CFrame.new(x, 0.1, z - 3), Color3.fromRGB(255, 200, 50), SM, { noShadow = true }).Name = "Keep"
		return 1.5, 4.1, 2.6
	end

	-- tall obstacle: switch lanes
	OBS.wall = function(model, zone, lane, z)
		local x = LANES[lane]
		if isPark(zone) then
			-- park bin
			part(model, Vector3.new(13, 6.2, 6.2), CFrame.new(x, 6.5, z + 3.1) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 120, 80), Enum.Material.Metal, { shape = CYL, obs = true })
			part(model, Vector3.new(1.4, 6.8, 6.8), CFrame.new(x, 13.5, z + 3.1) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(45, 95, 60), Enum.Material.Metal, { shape = CYL, obs = true })
			return 6.2
		end
		if zone == "Kitchen" then
			local c = pick(PALETTE)
			local box = part(model, Vector3.new(6.4, 16, 4), CFrame.new(x, 8, z + 2) * CFrame.Angles(0, RNG:NextNumber(-0.1, 0.1), 0), c, SM, { obs = true })
			letterFace(box, pick({ "YUM", "O's", "CRUNCH" }), Color3.new(1, 1, 1))
			return 4
		elseif zone == "Bathroom" then
			local c = pick(PALETTE):Lerp(Color3.new(1, 1, 1), 0.2)
			part(model, Vector3.new(13, 6, 5), CFrame.new(x, 6.5, z + 2.5) * CFrame.Angles(0, 0, math.pi / 2), c, SM, { shape = CYL, obs = true })
			part(model, Vector3.new(3, 3, 3), CFrame.new(x, 14.5, z + 2.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 255, 255), SM, { shape = CYL, obs = true })
			part(model, Vector3.new(6.1, 5, 5.1), CFrame.new(x, 1, z + 2.5), c, SM, { mesh = SPH, obs = true })
			local label = part(model, Vector3.new(4, 5, 0.2), CFrame.new(x, 7, z - 0.05), Color3.fromRGB(255, 255, 255), SM, { noShadow = true })
			letterFace(label, "SHAMPOO", Color3.fromRGB(120, 140, 200))
			return 5
		elseif zone == "Backyard" then
			-- garden gnome
			part(model, Vector3.new(6, 8, 5), CFrame.new(x, 4, z + 2.5), Color3.fromRGB(80, 120, 200), SM, { mesh = SPH, obs = true })
			part(model, Vector3.new(4.4, 4.4, 4.4), CFrame.new(x, 9.5, z + 2.5), Color3.fromRGB(255, 205, 170), SM, { shape = BALL, obs = true })
			part(model, Vector3.new(4.4, 4, 2), CFrame.new(x, 7.5, z + 0.6), Color3.fromRGB(250, 250, 250), SM, { mesh = SPH })
			part(model, Vector3.new(4.2, 7, 4.2), CFrame.new(x, 13.5, z + 2.7) * CFrame.Angles(0.15, 0, 0), Color3.fromRGB(230, 60, 60), SM, { mesh = SPH, obs = true })
			part(model, Vector3.new(1.2, 1.2, 1.2), CFrame.new(x, 9.8, z + 0.3), Color3.fromRGB(255, 160, 150), SM, { shape = BALL })
			return 5
		end
		local y = 0
		local d = 5
		local n = RNG:NextInteger(4, 6)
		for i = 1, n do
			local h = RNG:NextNumber(2, 2.8)
			local c = pick(PALETTE):Lerp(Color3.fromRGB(80, 60, 60), 0.25)
			local cf = CFrame.new(x + RNG:NextNumber(-0.4, 0.4), y + h / 2, z + d / 2) * CFrame.Angles(0, RNG:NextNumber(-0.12, 0.12), 0)
			part(model, Vector3.new(6.4, h, d), cf, c, SM, { obs = true })
			part(model, Vector3.new(6.2, h * 0.8, 0.1), cf * CFrame.new(0, 0, -d / 2 - 0.02), Color3.fromRGB(250, 245, 225), SM, { noShadow = true })
			if i == n and RNG:NextNumber() < 0.4 then
				decorSminski(model, cf * CFrame.new(0, h / 2, 0), 1, "sit")
			end
			y += h
		end
		return d
	end

	-- wooden toy train: switch lanes, or run up the ramp and ride the roof
	OBS.train = function(model, zone, lane, z, withRamp)
		local x = LANES[lane]
		local len = 26
		local c = pick(PALETTE)
		local startZ = z
		if withRamp then
			local ramp = part(model, Vector3.new(5.8, 5.8, 13), CFrame.new(x, 2.9, z + 6.5), Color3.fromRGB(215, 175, 120), Enum.Material.Wood, { class = "WedgePart", walk = true })
			ramp.Name = "Ramp"
			startZ = z + 13.5
		end
		local zc = startZ + len / 2
		part(model, Vector3.new(6.2, 5, len), CFrame.new(x, 2.7, zc), c, SM, { obs = true })
		part(model, Vector3.new(6.8, 0.6, len + 1), CFrame.new(x, 5.5, zc), c:Lerp(Color3.new(1, 1, 1), 0.3), SM, { obs = true })
		for i = 0, 3 do
			for _, s in { -1, 1 } do
				part(model, Vector3.new(0.3, 2, 3.5), CFrame.new(x + s * 3.12, 3.4, startZ + 4 + i * 6), Color3.fromRGB(170, 220, 255), Enum.Material.Neon, { noShadow = true })
				part(model, Vector3.new(0.7, 2.2, 2.2), CFrame.new(x + s * 3.2, 1.1, startZ + 3 + i * 6.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 50, 50), SM, { shape = CYL })
			end
		end
		part(model, Vector3.new(5.6, 4.2, 0.2), CFrame.new(x, 2.9, startZ - 0.05), Color3.fromRGB(255, 250, 235), SM, { noShadow = true })
		part(model, Vector3.new(0.3, 0.7, 0.7), CFrame.new(x - 1.2, 3.5, startZ - 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 30), SM, { shape = CYL })
		part(model, Vector3.new(0.3, 0.7, 0.7), CFrame.new(x + 1.2, 3.5, startZ - 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 30), SM, { shape = CYL })
		part(model, Vector3.new(1.8, 0.4, 0.2), CFrame.new(x, 2.3, startZ - 0.2), Color3.fromRGB(200, 70, 80), SM, { noShadow = true })
		return (startZ - z) + len, startZ
	end

	-- rolling ball / toy car that moves toward the player (tier 3+)
	local function spawnMover(model, lane, z)
		local x = LANES[lane]
		local mv = { lane = lane, x = x, z = z, active = false, parts = {}, t = 0 }
		local tennis = mapId == "dogpark"
		if tennis or RNG:NextNumber() < 0.5 then
			mv.kind = "ball"
			mv.speed = 24
			local r = 5.6
			local b = part(model, Vector3.new(r, r, r), CFrame.new(x, r / 2, z), tennis and Color3.fromRGB(210, 240, 70) or pick(PALETTE), tennis and Enum.Material.Fabric or SM, { shape = BALL, obs = true })
			local stripe = part(model, Vector3.new(r * 1.01, r * 0.25, r * 1.01), b.CFrame, Color3.fromRGB(255, 255, 255), SM, { shape = CYL })
			mv.parts = { { b, CFrame.new(0, r / 2, 0) }, { stripe, CFrame.new(0, r / 2, 0) } }
			mv.len, mv.top, mv.r = r, r, r
		else
			mv.kind = "car"
			mv.speed = 30
			mv.parts = toyCar(model, Vector3.new(x, 0, z), math.pi, pick(PALETTE))
			for i, pr in mv.parts do
				if i <= 2 then
					pr[1].CanQuery = true
					pr[1]:SetAttribute("Obs", true)
				end
			end
			mv.len, mv.top = 11, 5.5
		end
		mv.group = addGroup("mover", lane, z - mv.len / 2, z + mv.len / 2, mv.top)
		table.insert(World.movers, mv)
		return mv
	end

	-- chaos event: a burst of rolling toys ahead of the player
	function World.avalanche(pz, n)
		for i = 1, n or 3 do
			local z = pz + 110 + i * 42
			local seg
			for _, sg in World.segments do
				if z >= sg.z0 and z < sg.z0 + SEG_LEN then seg = sg break end
			end
			if seg and seg.model then
				local lo, hi = World.laneRangeAt(z)
				spawnMover(seg.model, RNG:NextInteger(lo, hi), z)
			end
		end
	end

	-- book that drops into a lane as you approach (tier 3+)
	local function spawnFaller(model, lane, z)
		local x = LANES[lane]
		if mapId == "dogpark" then
			local fl = { lane = lane, x = x, z = z, y = 70, vy = 0, state = "wait", parts = {}, stomp = true, hold = 0 }
			local shoe = part(model, Vector3.new(7, 5, 12), CFrame.new(x, 70, z + 5), Color3.fromRGB(250, 250, 252), SM, { obs = true })
			local sole = part(model, Vector3.new(7.2, 1.4, 12.4), CFrame.new(x, 70, z + 5), Color3.fromRGB(235, 85, 85), SM, { obs = true })
			local leg = part(model, Vector3.new(5.6, 40, 5.6), CFrame.new(x, 90, z + 3), Color3.fromRGB(80, 110, 175), SM, { mesh = SPH })
			fl.parts = { { shoe, CFrame.new(0, 3.2, 5) }, { sole, CFrame.new(0, 0.7, 5) }, { leg, CFrame.new(0, 24, 3) } }
			local sneaker = placeAsset(model, "Sneaker", CFrame.new(x, 70, z + 5), Vector3.new(7.4, 6.4, 12.6))
			if sneaker then
				shoe.Transparency = 1
				sole.Transparency = 1
				if sneaker:IsA("BasePart") then
					table.insert(fl.parts, { sneaker, CFrame.new(0, 3.2, 5) })
				else
					-- multi-part Blender sneaker: keep each piece's place relative to the shoe
					local centre = CFrame.new(x, 70, z + 5)
					for _, p in sneaker:GetDescendants() do
						if p:IsA("BasePart") then
							table.insert(fl.parts, { p, CFrame.new(0, 3.2, 5) * centre:ToObjectSpace(p.CFrame) })
						end
					end
				end
			end
			fl.shadow = part(model, Vector3.new(0.1, 12, 12), CFrame.new(x, 0.06, z + 5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(20, 20, 30), SM, { shape = CYL, transparency = 1, noShadow = true })
			fl.group = addGroup("wall", lane, z, z + 12, 5)
			table.insert(World.fallers, fl)
			return fl
		end
		local fl = { lane = lane, x = x, z = z, y = 70, vy = 0, state = "wait", parts = {} }
		local c = pick(PALETTE):Lerp(Color3.fromRGB(80, 60, 60), 0.2)
		local b = part(model, Vector3.new(6.6, 3.2, 8), CFrame.new(x, 70, z + 4), c, SM, { obs = true })
		local pages = part(model, Vector3.new(6.3, 2.6, 0.2), CFrame.new(x, 70, z - 0.05), Color3.fromRGB(250, 245, 225), SM, { noShadow = true })
		fl.parts = { { b, CFrame.new(0, 1.6, 4) }, { pages, CFrame.new(0, 1.6, -0.05) } }
		local shadow = part(model, Vector3.new(0.1, 8, 8), CFrame.new(x, 0.06, z + 4) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(20, 20, 30), SM, { shape = CYL, transparency = 1, noShadow = true })
		fl.shadow = shadow
		fl.group = addGroup("wall", lane, z, z + 8, 3.2)
		table.insert(World.fallers, fl)
		return fl
	end

	---------------------------------------------------------------------------
	-- COINS + POWERUPS
	---------------------------------------------------------------------------
	local function getCoinPart()
		local p = table.remove(coinPool)
		if not p and Models.hasMeshes("StarCoin") then
			-- smooth Blender star coin (faces +Z, so it needs no quarter turn)
			p = Models.rigMesh(nil, "StarCoin", 1, COIN_COLOR, Enum.Material.SmoothPlastic)
			p.Reflectance = 0.22
			p.CastShadow = false
			p:SetAttribute("M", true)
		end
		if not p then
			p = part(nil, Vector3.new(0.45, 1.8, 1.8), CFrame.new(), COIN_COLOR, Enum.Material.Metal, { shape = CYL, noShadow = true })
			for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
				local sg = Instance.new("SurfaceGui")
				sg.Face = face
				sg.LightInfluence = 0.4
				sg.CanvasSize = Vector2.new(100, 100)
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Size = UDim2.fromScale(1, 1)
				l.Text = "★"
				l.TextScaled = true
				l.Font = Enum.Font.GothamBlack
				l.TextColor3 = Color3.fromRGB(215, 135, 25)
				l.Parent = sg
				sg.Parent = p
			end
		end
		return p
	end

	function World.releaseCoin(c)
		if c.part then
			c.part.Parent = coinPoolFolder
			table.insert(coinPool, c.part)
			c.part = nil
		end
	end

	local function makeCoin(seg, pos, trail, luckLevel)
		local gold = LRNG:NextNumber() < 0.025 + (luckLevel or 0) * 0.012
		local p = getCoinPart()
		p.Color = gold and GOLD_COLOR or COIN_COLOR
		if p:GetAttribute("M") then
			p.Size = Models.coinSize(gold and 2.5 or 1.8)
		else
			p.Size = gold and Vector3.new(0.6, 2.5, 2.5) or Vector3.new(0.45, 1.8, 1.8)
		end
		p.Transparency = 0
		p.CFrame = CFrame.new(pos)
		p.Parent = seg.model
		local c = { part = p, pos = pos, base = pos, alive = true, gold = gold, trail = trail, seg = seg }
		trail.total += 1
		table.insert(seg.coins, c)
		table.insert(World.coins, c)
		return c
	end

	local function makePickup(seg, pos, kind)
		local def = Config.Powerups[kind]
		local shell = part(seg.model, Vector3.new(3, 3, 3), CFrame.new(pos), Color3.fromRGB(255, 255, 255), Enum.Material.Glass, { shape = BALL, transparency = 0.55, noShadow = true })
		local core = part(seg.model, Vector3.new(2, 2, 2), CFrame.new(pos), def.color, Enum.Material.Neon, { shape = BALL, noShadow = true })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(60, 60)
		bb.AlwaysOnTop = false
		bb.LightInfluence = 0
		bb.MaxDistance = 160
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = def.icon
		l.TextColor3 = Color3.new(1, 1, 1)
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.fromRGB(60, 64, 52)
		st.Parent = l
		l.Parent = bb
		bb.Parent = core
		local pu = { kind = kind, pos = pos, shell = shell, core = core, alive = true, seg = seg }
		table.insert(seg.pickups, pu)
		table.insert(World.pickups, pu)
		return pu
	end

	-- height a coin should float at, given what's in the lane at z (nil = skip)
	local function coinHeight(occ, z)
		for _, o in occ do
			if o.kind == "block" and z > o.a - 7 and z < o.b + 7 then
				local mid = (o.a + o.b) / 2
				local k = math.clamp(1 - ((z - mid) / 8) ^ 2, 0, 1)
				return 1.6 + 5.2 * k
			elseif o.kind == "bar" and z > o.a - 1.5 and z < o.b + 1.5 then
				return 1.1
			elseif (o.kind == "wall" or o.kind == "mover" or o.kind == "faller") and z > o.a - 16 and z < o.b + 2 then
				return nil
			elseif o.kind == "ramp" and z >= o.a and z <= o.b then
				return 1.6 + (z - o.a) / (o.b - o.a) * 5.8
			elseif o.kind == "train" and z >= o.a - 0.5 and z <= o.b then
				return o.ramp and 7.4 or nil
			elseif o.kind == "train" and not o.ramp and z > o.a - 16 and z < o.a then
				return nil
			end
		end
		return 1.6
	end

	local function laneFree(occ, a, b)
		for _, o in occ do
			if o.b > a - 4 and o.a < b + 4 then return false end
		end
		return true
	end

	---------------------------------------------------------------------------
	-- PATH: the track curves, climbs and dips. Everything is built and
	-- simulated in straight "track space" (x = lateral, y = height, z = distance
	-- along the track) and then mapped onto the path with World.frame(s).
	---------------------------------------------------------------------------
	local pathSegs = {} -- { s0, len, startCF, k (yaw per stud), dh (height change), kind }
	local pathIdx = 1
	local nextStartCF = CFrame.new()
	World.glides = {} -- { s0, s1 } stretches where you glide over a gap
	local glideCountdown = 7
	local heightSoFar = 0

	local function segFrame(ps, u)
		local L = ps.len
		local x = math.clamp(u / L, 0, 1)
		local h = ps.dh * (x * x * (3 - 2 * x))
		local slope = ps.dh * 6 * x * (1 - x) / L
		local k = ps.k
		local th = k * u
		local px, pz
		if math.abs(k) < 1e-6 then
			px, pz = 0, u
		else
			px, pz = (1 - math.cos(th)) / k, math.sin(th) / k
		end
		return ps.startCF * CFrame.new(px, h, pz) * CFrame.Angles(0, th, 0) * CFrame.Angles(-math.atan(slope), 0, 0)
	end

	-- CFrame of the track centreline at distance s (facing along the track)
	function World.frame(s)
		local n = #pathSegs
		if n == 0 then return CFrame.new(0, 0, s) end
		local first = pathSegs[1]
		if s < first.s0 then
			return first.startCF * CFrame.new(0, 0, s - first.s0)
		end
		local i = math.clamp(pathIdx, 1, n)
		while i > 1 and s < pathSegs[i].s0 do i -= 1 end
		while i < n and s >= pathSegs[i].s0 + pathSegs[i].len do i += 1 end
		pathIdx = i
		local ps = pathSegs[i]
		local u = s - ps.s0
		if u > ps.len then
			return segFrame(ps, ps.len) * CFrame.new(0, 0, u - ps.len)
		end
		return segFrame(ps, u)
	end
	local frame = World.frame

	-- track-space position -> world CFrame
	function World.at(s, x, y)
		return frame(s) * CFrame.new(x or 0, y or 0, 0)
	end
	-- a straight-space CFrame (x, y, z = s) -> world
	function World.map(cf)
		return frame(cf.Z) * CFrame.new(cf.X, cf.Y, 0) * cf.Rotation
	end
	function World.toWorld(v)
		return (frame(v.Z) * CFrame.new(v.X, v.Y, 0)).Position
	end

	-- are we over a glide gap? returns { s0, s1 } or nil
	function World.glideAt(s)
		for _, g in World.glides do
			if s >= g.s0 and s < g.s1 then return g end
		end
		return nil
	end
	-- glide height above the track at s, starting from launch height y0
	function World.glideHeight(g, s, y0)
		local t = math.clamp((s - g.s0) / (g.s1 - g.s0), 0, 1)
		return (y0 or 4) * (1 - t) + 16 * math.sin(math.pi * t)
	end

	-- decide how this segment of track bends (deterministic from the seed)
	local function choosePath(z0)
		if z0 < 240 then
			return 0, 0, "flat"
		end
		glideCountdown -= 1
		if glideCountdown == 1 then
			return 0, 16, "launch"
		elseif glideCountdown <= 0 then
			glideCountdown = RNG:NextInteger(10, 15)
			return 0, -12, "gap"
		end
		local k, dh = 0, 0
		if RNG:NextNumber() < 0.55 then
			local turn = RNG:NextNumber(0.3, 0.85) * (RNG:NextNumber() < 0.5 and -1 or 1)
			k = turn / SEG_LEN
		end
		if RNG:NextNumber() < 0.45 then
			dh = RNG:NextNumber(6, 13) * (RNG:NextNumber() < 0.5 and -1 or 1)
			-- keep the track from wandering too high or low overall
			if heightSoFar + dh > 60 or heightSoFar + dh < -30 then dh = -dh end
		end
		return k, dh, "normal"
	end

	-- map a freshly built (straight) segment onto the path; long boxes on
	-- curves/hills get sliced so floors and walls follow the bend smoothly
	local function bendModel(model, ps)
		local curved = ps.k ~= 0 or ps.dh ~= 0
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
		for _, part_ in parts do
			local c = part_.CFrame
			if part_.CanQuery then part_:SetAttribute("S", c.Z) end
			local splittable = curved and part_.ClassName == "Part" and part_.Shape == Enum.PartType.Block
				and #part_:GetChildren() == 0 and math.abs(c.LookVector.Z) > 0.999 and part_.Size.Z > 12
			if splittable then
				local n = math.ceil(part_.Size.Z / 8)
				local len = part_.Size.Z / n
				local extra = math.abs(ps.k) * (math.abs(c.X) + part_.Size.X / 2) * len + 0.6
				for i = 1, n do
					local q = part_:Clone()
					q.Size = Vector3.new(part_.Size.X, part_.Size.Y, len + extra)
					local zc = c.Z - part_.Size.Z / 2 + len * (i - 0.5)
					q.CFrame = frame(zc) * CFrame.new(c.X, c.Y, 0) * c.Rotation
					if q.CanQuery then q:SetAttribute("S", zc) end
					q.Parent = part_.Parent
				end
				part_:Destroy()
			elseif curved and part_:IsA("MeshPart") and part_.Size.Z > 30 and part_.Size.X < 30 then
				-- long rigid props can't bend; drop them on curvy stretches
				part_:Destroy()
			else
				part_.CFrame = frame(c.Z) * CFrame.new(c.X, c.Y, 0) * c.Rotation
			end
		end
	end

	-- glide gap: remove the floor and low decor mid-segment, add a drop below
	local function carveGap(model, z0, zone)
		local a, b = z0 + 3, z0 + SEG_LEN - 12
		local floorColor = Color3.fromRGB(150, 100, 70)
		for _, d in model:GetChildren() do
			local cf, size
			if d:IsA("BasePart") then
				cf, size = d.CFrame, d.Size
			elseif d:IsA("Model") then
				cf, size = d:GetBoundingBox()
			end
			if cf then
				local isFloor = d:IsA("BasePart") and d.CanQuery and cf.Y < 0.5 and size.Y <= 2.5
				local lowDecor = cf.Y < 14 and math.abs(cf.X) < 34
				if isFloor then
					floorColor = d.Color
					-- keep only the landing strip at the end
					local z1, z2 = cf.Z - size.Z / 2, cf.Z + size.Z / 2
					if z2 > b then
						local keepFrom = math.max(z1, b)
						d.Size = Vector3.new(size.X, size.Y, z2 - keepFrom)
						d.CFrame = CFrame.new(cf.X, cf.Y, (keepFrom + z2) / 2)
					elseif z1 < a then
						local keepTo = math.min(z2, a)
						d.Size = Vector3.new(size.X, size.Y, keepTo - z1)
						d.CFrame = CFrame.new(cf.X, cf.Y, (z1 + keepTo) / 2)
					else
						d:Destroy()
					end
				elseif lowDecor and cf.Z > a and cf.Z < b then
					d:Destroy()
				end
			end
		end
		local park = zone:sub(1, 4) == "Park"
		-- the drop: a lower floor (or a pond in the park) far below the glide
		part(model, Vector3.new(76, 2, b - a + 10), CFrame.new(0, park and -8 or -42, (a + b) / 2), park and Color3.fromRGB(90, 160, 215) or floorColor:Lerp(Color3.new(0, 0, 0), 0.25), park and Enum.Material.Glass or Enum.Material.WoodPlanks, { transparency = park and 0.15 or 0 })
		if not park then
			for _ = 1, 4 do
				ball(model, Vector3.new(RNG:NextNumber(-25, 25), -41, RNG:NextNumber(a + 5, b - 5)), RNG:NextNumber(4, 8))
			end
			for _, zz in { a, b } do
				part(model, Vector3.new(70, 40, 1.2), CFrame.new(0, -21, zz), floorColor:Lerp(Color3.new(0, 0, 0), 0.4))
			end
		end
		-- lips of the platforms
		part(model, Vector3.new(70, 0.6, 1.2), CFrame.new(0, 0.1, a), Color3.fromRGB(255, 210, 90), Enum.Material.Neon, { noShadow = true })
		part(model, Vector3.new(70, 0.6, 1.2), CFrame.new(0, 0.1, b), Color3.fromRGB(255, 210, 90), Enum.Material.Neon, { noShadow = true })
		table.insert(World.glides, { s0 = z0 - 1, s1 = b + 1 })
	end

	-- launch ramp across every lane at the end of the segment before a gap
	local function launchRamp(model, z0)
		local zr = z0 + SEG_LEN - 12
		local ramp = part(model, Vector3.new(36, 4, 12), CFrame.new(0, 2, zr + 6), Color3.fromRGB(255, 120, 150), SM, { class = "WedgePart", walk = true })
		ramp.Name = "Ramp"
		for i = 0, 2 do
			part(model, Vector3.new(30, 0.3, 1.2), CFrame.new(0, 0.9 + i * 1.2, zr + 2 + i * 3.5) * CFrame.Angles(-math.atan(4 / 12), 0, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon, { noShadow = true })
		end
		for _, sx in { -1, 1 } do
			part(model, Vector3.new(1.2, 5, 14), CFrame.new(sx * 18.6, 2.5, zr + 6), Color3.fromRGB(255, 255, 255))
		end
		local sign = part(model, Vector3.new(16, 5, 0.4), CFrame.new(0, 14, zr - 10), Color3.fromRGB(255, 250, 235), SM, { noShadow = true })
		letterFace(sign, "GLIDE!", Color3.fromRGB(255, 120, 150))
	end

	---------------------------------------------------------------------------
	-- GENERATION
	---------------------------------------------------------------------------
	local function genObstacles(seg, model, z0, tier, luckLevel, zone, lo, hi, clearEnd, launch)
		local diff = math.clamp((tier - 1) / 3, 0, 1)
		safeLane = math.clamp(safeLane + RNG:NextInteger(-1, 1), lo, hi)
		local occ = { {}, {}, {}, {}, {} }
		-- before the path narrows, keep the end clear so the funnel is safe
		local zEnd = z0 + SEG_LEN - ((clearEnd or launch) and 30 or 8)

		-- three-lane barrier: safe lane gets a jump/slide, the rest are walls
		local rowZ
		if tier >= 2 and RNG:NextNumber() < 0.25 + 0.1 * tier then
			rowZ = z0 + RNG:NextNumber(30, 50)
			for l = lo, hi do
				if l == safeLane then
					if RNG:NextNumber() < 0.5 then
						local d, top = OBS.block(newOb(model, "block", zone), zone, l, rowZ)
						addGroup("block", l, rowZ, rowZ + d, top)
						table.insert(occ[l], { kind = "block", a = rowZ, b = rowZ + d })
					else
						local d, top, bottom = OBS.bar(newOb(model, "bar", zone), zone, l, rowZ)
						addGroup("bar", l, rowZ, rowZ + d, top, bottom)
						table.insert(occ[l], { kind = "bar", a = rowZ, b = rowZ + d })
					end
				else
					local d = OBS.wall(newOb(model, "wall", zone), zone, l, rowZ)
					addGroup("wall", l, rowZ, rowZ + d, 12)
					table.insert(occ[l], { kind = "wall", a = rowZ, b = rowZ + d })
				end
			end
		end

		for l = lo, hi do
			local z = z0 + 16 + RNG:NextNumber(0, 10)
			while z < zEnd do
				if rowZ and z > rowZ - 22 and z < rowZ + 20 then
					z = rowZ + 20 + RNG:NextNumber(0, 6)
					continue
				end
				local r = RNG:NextNumber()
				local kind
				if l == safeLane then
					kind = r < 0.35 and "block" or r < 0.65 and "bar" or "none"
					if tier == 1 and kind == "bar" and RNG:NextNumber() < 0.5 then kind = "none" end
				else
					if tier == 1 then
						kind = r < 0.3 and "block" or r < 0.65 and "wall" or "none"
					else
						kind = r < 0.2 and "block" or r < 0.34 and "bar" or r < 0.56 and "wall" or r < 0.8 and "train" or "none"
						if tier >= 3 and RNG:NextNumber() < 0.14 + 0.06 * (tier - 3) then
							kind = RNG:NextNumber() < 0.55 and "mover" or "faller"
						end
					end
				end
				if kind == "train" and z + 42 > z0 + SEG_LEN - 2 then kind = "wall" end
				local len = 0
				if kind == "block" then
					local top
					len, top = OBS.block(newOb(model, "block", zone), zone, l, z)
					addGroup("block", l, z, z + len, top)
					table.insert(occ[l], { kind = "block", a = z, b = z + len })
				elseif kind == "bar" then
					local top, bottom
					len, top, bottom = OBS.bar(newOb(model, "bar", zone), zone, l, z)
					addGroup("bar", l, z, z + len, top, bottom)
					table.insert(occ[l], { kind = "bar", a = z, b = z + len })
				elseif kind == "wall" then
					len = OBS.wall(newOb(model, "wall", zone), zone, l, z)
					addGroup("wall", l, z, z + len, 12)
					table.insert(occ[l], { kind = "wall", a = z, b = z + len })
				elseif kind == "train" then
					local withRamp = RNG:NextNumber() < 0.6
					local startZ
					len, startZ = OBS.train(newOb(model, "train", zone), zone, l, z, withRamp)
					if withRamp then
						table.insert(occ[l], { kind = "ramp", a = z, b = startZ })
					end
					addGroup("train", l, startZ, z + len, 5.8)
					table.insert(occ[l], { kind = "train", a = startZ, b = z + len, ramp = withRamp })
				elseif kind == "mover" then
					local mv = spawnMover(model, l, z + 6)
					len = mv.len + 4
					-- a mover sweeps back toward the player, so keep its lane free behind it
					table.insert(occ[l], { kind = "mover", a = z0, b = z + len })
				elseif kind == "faller" then
					spawnFaller(model, l, z)
					len = 8
					table.insert(occ[l], { kind = "faller", a = z, b = z + len })
				else
					len = 8
				end
				local gapMin = lerp(34, 16, diff)
				local gapMax = lerp(58, 28, diff)
				z += len + RNG:NextNumber(gapMin, gapMax)
			end
		end

		for _, d in pendingDress do
			dressObstacle(d.ob, assetFor(d.kind, d.zone))
		end
		table.clear(pendingDress)

		-- coin patterns
		local patterns = RNG:NextInteger(1, tier >= 2 and 2 or 1)
		for _ = 1, patterns do
			local trail = { total = 0, got = 0, done = false }
			local r = RNG:NextNumber()
			if r < 0.3 then
				-- lane-switch arc between two adjacent lanes
				local a = RNG:NextInteger(lo, hi)
				local b = a + (RNG:NextNumber() < 0.5 and -1 or 1)
				if b < lo or b > hi then b = a == lo and a + 1 or a - 1 end
				local zs = z0 + RNG:NextNumber(6, 30)
				local ze = zs + 30
				if laneFree(occ[a], zs, zs + 12) and laneFree(occ[b], zs + 12, ze) then
					for z = zs, ze, 4 do
						local k = math.clamp((z - zs) / (ze - zs), 0, 1)
						k = k * k * (3 - 2 * k)
						makeCoin(seg, Vector3.new(lerp(LANES[a], LANES[b], k), 1.6 + math.sin(k * math.pi) * 1.2, z), trail, luckLevel)
					end
					continue
				end
			end
			-- straight line / jump arcs (heights follow obstacles in that lane)
			local sl = RNG:NextNumber() < 0.7 and safeLane or RNG:NextInteger(lo, hi)
			local zs = z0 + RNG:NextNumber(4, 30)
			local ze = math.min(z0 + SEG_LEN - 2, zs + RNG:NextNumber(25, 55))
			for z = zs, ze, 4.5 do
				local h = coinHeight(occ[sl], z)
				if h then
					makeCoin(seg, Vector3.new(LANES[sl], h, z), trail, luckLevel)
				end
			end
		end

		-- powerup capsule in the safe lane
		if LRNG:NextNumber() < 0.15 + (luckLevel or 0) * 0.035 then
			for _ = 1, 6 do
				local z = z0 + LRNG:NextNumber(10, SEG_LEN - 10)
				if laneFree(occ[safeLane], z - 4, z + 4) then
					makePickup(seg, Vector3.new(LANES[safeLane], 2.6, z), Config.PowerupOrder[LRNG:NextInteger(1, #Config.PowerupOrder)])
					break
				end
			end
		end
	end

	local function genSegment(runTime, luckLevel)
		segCount += 1
		local z0 = nextZ
		local zone = ZONE_ORDER[zoneIdx]
		local lo, hi = NARROW_MIN, NARROW_MAX
		if zoneWide or forceWide then lo, hi = 1, #LANES end
		local seg = { z0 = z0, coins = {}, pickups = {}, zone = zone, lo = lo, hi = hi }
		local model = Instance.new("Model")
		model.Name = "Segment" .. segCount
		seg.model = model

		local k, dh, kind = choosePath(z0)
		local ps = { s0 = z0, len = SEG_LEN, startCF = nextStartCF, k = k, dh = dh, kind = kind }
		table.insert(pathSegs, ps)
		nextStartCF = segFrame(ps, SEG_LEN)
		heightSoFar += dh
		seg.path = ps

		ZONES[zone](model, z0)
		if segCount == 1 then
			doorway(model, z0)
		end
		zoneLeft -= 1
		local wasWide = zoneWide
		if zoneLeft <= 0 then
			local newIdx = zoneIdx
			while newIdx == zoneIdx do
				newIdx = RNG:NextInteger(1, #ZONE_ORDER)
			end
			zoneIdx = newIdx
			zoneLeft = RNG:NextInteger(4, 7)
			doorway(model, z0 + SEG_LEN)
			-- later in a run, some zones open up into 5 lanes
			local tier = Config.TierAtDistance(z0)
			zoneWide = tier >= 2 and RNG:NextNumber() < (tier >= 3 and 0.55 or 0.35)
		end
		if kind == "gap" then
			carveGap(model, z0, zone)
			-- a coin arc through the air in three lanes
			local g = World.glides[#World.glides]
			for _, l in { math.max(lo, 2), 3, math.min(hi, 4) } do
				local trail = { total = 0, got = 0, done = false }
				for z = g.s0 + 6, g.s1 - 6, 5 do
					makeCoin(seg, Vector3.new(LANES[l], World.glideHeight(g, z, 4) + 1.2, z), trail, luckLevel)
				end
			end
		elseif z0 >= 80 then
			genObstacles(seg, model, z0, Config.TierAtDistance(z0), luckLevel, zone, lo, hi, wasWide and not zoneWide and not forceWide, kind == "launch")
			if kind == "launch" then launchRamp(model, z0) end
		end
		bendModel(model, ps)
		model.Parent = root
		table.insert(World.segments, seg)
		nextZ += SEG_LEN
	end

	local function destroySegment(seg)
		for _, c in seg.coins do
			c.alive = false
			World.releaseCoin(c)
		end
		seg.model:Destroy()
	end

	function World.reset(seed)
		seed = seed or math.floor(os.clock() * 1000)
		RNG = Random.new(seed)
		LRNG = Random.new(seed + 7919)
		World.seed = seed
		for _, s in World.segments do
			destroySegment(s)
		end
		table.clear(World.segments)
		table.clear(World.groups)
		table.clear(World.movers)
		table.clear(World.fallers)
		table.clear(World.coins)
		table.clear(World.pickups)
		nextZ = -SEG_LEN * SEGS_BEHIND
		table.clear(pathSegs)
		table.clear(World.glides)
		pathIdx = 1
		nextStartCF = CFrame.new(0, 0, nextZ)
		glideCountdown = 7
		heightSoFar = 0
		segCount = 0
		zoneIdx = 1
		zoneLeft = 6
		safeLane = 3
		zoneWide = false
	end

	local function prune(list, minZ, getZ)
		local i = 1
		while i <= #list do
			if getZ(list[i]) < minZ then
				table.remove(list, i)
			else
				i += 1
			end
		end
	end

	-- generate ahead / delete behind. runTime drives the difficulty tier of new segments.
	function World.update(pz, runTime, luckLevel)
		while nextZ < pz + SEGS_AHEAD * SEG_LEN do
			genSegment(runTime or 0, luckLevel or 0)
		end
		local removed = false
		while #World.segments > 0 and World.segments[1].z0 + SEG_LEN < pz - SEGS_BEHIND * SEG_LEN do
			destroySegment(table.remove(World.segments, 1))
			removed = true
		end
		if removed then
			local minZ = pz - SEGS_BEHIND * SEG_LEN
			prune(World.groups, minZ, function(g) return g.z1 end)
			prune(World.movers, minZ, function(m) return m.z end)
			prune(World.fallers, minZ, function(f) return f.z end)
			prune(World.coins, minZ, function(c) return c.alive and c.pos.Z or -math.huge end)
			prune(World.pickups, minZ, function(p) return p.alive and p.pos.Z or -math.huge end)
			prune(World.glides, minZ, function(g) return g.s1 end)
			while #pathSegs > 1 and pathSegs[1].s0 + SEG_LEN < minZ - SEG_LEN do
				table.remove(pathSegs, 1)
				pathIdx = math.max(1, pathIdx - 1)
			end
		end
	end

	function World.setMap(id)
		local m = Config.Map(id)
		mapId = m.id
		ZONE_ORDER = m.zones
		PALETTE = m.id == "dollhouse" and GREEN_PALETTE or TOY_COLORS
	end

	-- multiplayer: all five lanes open everywhere
	function World.setForceWide(on)
		forceWide = on
	end

	-- which lanes are open at z (lo, hi)
	function World.laneRangeAt(z)
		for _, s in World.segments do
			if z >= s.z0 and z < s.z0 + SEG_LEN then return s.lo, s.hi end
		end
		return NARROW_MIN, NARROW_MAX
	end

	function World.zoneAt(z)
		for _, s in World.segments do
			if z >= s.z0 and z < s.z0 + SEG_LEN then return s.zone end
		end
		return nil
	end

	-- moving hazards; timeScale already applied to dt
	function World.updateHazards(dt, pz)
		for _, mv in World.movers do
			if not mv.active and mv.z - pz < 140 and mv.z > pz then
				mv.active = true
			end
			if mv.active and mv.z > pz - 40 then
				mv.z -= mv.speed * dt
				mv.t += dt
				local base = World.at(mv.z, mv.x, 0)
				for _, pr in mv.parts do
					local cf = base * pr[2]
					if mv.kind == "ball" then
						cf = cf * CFrame.Angles(-mv.t * mv.speed / (mv.r / 2), 0, 0)
					else
						cf = base * CFrame.Angles(0, math.pi, 0) * pr[2]
					end
					pr[1].CFrame = cf
				end
				mv.group.z0 = mv.z - mv.len / 2
				mv.group.z1 = mv.z + mv.len / 2
			end
		end
		for _, fl in World.fallers do
			if fl.stomp then
				if fl.state == "wait" and fl.z - pz < 75 then
					fl.state = "warn"
					fl.hold = 0.45
					fl.y = 26
				elseif fl.state == "warn" then
					fl.hold -= dt
					fl.shadow.Transparency = 0.9 - 0.4 * (1 - fl.hold / 0.45)
					if fl.hold <= 0 then fl.state = "fall" end
				elseif fl.state == "fall" then
					fl.y = math.max(0, fl.y - 140 * dt)
					if fl.y <= 0 then
						fl.state = "down"
						fl.hold = 0.9
						if World.onFallerLanded then World.onFallerLanded(fl) end
					end
				elseif fl.state == "down" then
					fl.hold -= dt
					if fl.hold <= 0 then fl.state = "lift" end
				elseif fl.state == "lift" then
					fl.y += 60 * dt
					fl.shadow.Transparency = math.min(1, fl.shadow.Transparency + dt * 2)
					if fl.y > 60 then fl.state = "gone" end
				end
				if fl.state ~= "wait" and fl.state ~= "gone" then
					for _, pr in fl.parts do
						pr[1].CFrame = World.at(fl.z, fl.x, fl.y) * pr[2]
					end
				end
				continue
			end
			if fl.state == "wait" and fl.z - pz < 58 then
				fl.state = "fall"
				fl.y = 34
				fl.shadow.Transparency = 0.75
			end
			if fl.state == "fall" then
				fl.vy -= 160 * dt
				fl.y = math.max(0, fl.y + fl.vy * dt)
				local s = math.clamp(1 - fl.y / 40, 0.3, 1)
				fl.shadow.Size = Vector3.new(0.1, 8 * s, 8 * s)
				fl.shadow.Transparency = 0.8 - 0.35 * s
				for _, pr in fl.parts do
					pr[1].CFrame = World.at(fl.z, fl.x, fl.y) * pr[2]
				end
				if fl.y <= 0 then
					fl.state = "landed"
					fl.shadow.Transparency = 1
					if World.onFallerLanded then World.onFallerLanded(fl) end
				end
			end
		end
	end

	-- revive: clear obstacles/hazards just ahead of the player
	function World.clearAhead(z0, z1)
		for _, s in World.segments do
			for _, p in s.model:GetDescendants() do
				local ps_ = p:IsA("BasePart") and p:GetAttribute("S")
				if ps_ and (p:GetAttribute("Obs") or p.Name == "Ramp") and ps_ > z0 and ps_ < z1 then
					p.Transparency = 1
					p.CanQuery = false
					p:SetAttribute("Obs", nil)
					for _, c in p:GetChildren() do
						if c:IsA("SurfaceGui") then c.Enabled = false end
					end
				end
			end
		end
		for _, mv in World.movers do
			if mv.z > z0 - 10 and mv.z < z1 + 150 then
				mv.z = z0 - 100
				for _, pr in mv.parts do pr[1].Transparency = 1; pr[1].CanQuery = false end
			end
		end
	end

	-- returns the world-space shift so the caller can move its camera too
	function World.recenter(d)
		local dv = Vector3.new(0, 0, d)
		local shift = frame(d).Position
		for _, inst in root:GetDescendants() do
			if inst:IsA("BasePart") then
				inst.CFrame -= shift
				local sv = inst:GetAttribute("S")
				if sv then inst:SetAttribute("S", sv - d) end
			end
		end
		for _, ps in pathSegs do
			ps.s0 -= d
			ps.startCF -= shift
		end
		nextStartCF -= shift
		for _, g in World.glides do g.s0 -= d; g.s1 -= d end
		for _, s in World.segments do s.z0 -= d end
		for _, g in World.groups do g.z0 -= d; g.z1 -= d end
		for _, m in World.movers do m.z -= d end
		for _, f in World.fallers do f.z -= d end
		for _, c in World.coins do c.pos -= dv; c.base -= dv end
		for _, p in World.pickups do p.pos -= dv end
		nextZ -= d
		return shift
	end

	return World
end
