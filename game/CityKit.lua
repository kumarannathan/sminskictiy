-- CityKit (client): the building kit for Sminski City.
--   * folders: one detail folder per block (hidden when you're far away),
--     plus shared Solid (cars bump into it) and Ground (cars ride on it)
--   * builders run inside coroutines and yield when their frame budget is
--     spent, so a 2000-stud city streams in without a hitch
--   * matte paint, board-built details, Neon only for small lights and signs
--   deps: Models, UI, Places

return function(deps)
	local Models, UI, Places = deps.Models, deps.UI, deps.Places
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SminskiShared")
	local Props = require(Shared:WaitForChild("Props"))
	local PropMeshes = require(Shared:WaitForChild("PropMeshes"))
	local part = Models.part
	local CITY = Places.CITY
	local K = {}
	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	K.V, K.rgb = V, rgb
	function K.shade(c, k) return c:Lerp(Color3.new(0, 0, 0), k) end
	function K.tint(c, k) return c:Lerp(Color3.new(1, 1, 1), k) end
	local shade, tint = K.shade, K.tint
	local MATTE = Enum.Material.Plaster
	local WOODM = Enum.Material.Wood
	local NEON = Enum.Material.Neon
	local SMOOTH = Enum.Material.SmoothPlastic
	local METAL = Enum.Material.Metal
	K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL = MATTE, WOODM, NEON, SMOOTH, METAL
	K.GLASS = Enum.Material.Glass
	K.C = {
		-- ground materials read as asphalt / concrete / real grass, not as
		-- white plastic. Keep the pastels for BUILDINGS, not for the street.
		cream = rgb(252, 246, 226), pave = rgb(198, 198, 192), paveJoint = rgb(176, 176, 170), curb = rgb(214, 214, 208),
		road = rgb(78, 80, 86), line = rgb(236, 228, 190), grass = rgb(122, 162, 92), grass2 = rgb(134, 172, 100),
		trunk = rgb(150, 110, 78), leaf = rgb(122, 196, 98), leaf2 = rgb(152, 214, 112), leaf3 = rgb(100, 174, 90),
		pine = rgb(70, 136, 86), pine2 = rgb(86, 152, 96), ink = rgb(52, 60, 50), pane = rgb(206, 232, 236),
		lampPost = rgb(56, 98, 70), soil = rgb(126, 90, 66), soil2 = rgb(104, 72, 52), stone = rgb(232, 230, 220),
		water = rgb(120, 196, 226), gold = rgb(246, 206, 96), signGreen = rgb(98, 164, 96), red = rgb(230, 96, 90),
		glassBlue = rgb(196, 230, 214), sage = rgb(98, 164, 96), mint = rgb(186, 228, 164), butter = rgb(250, 228, 150),
		warm = rgb(255, 232, 170),
	}
	local Cc = K.C
	K.FLOWER_COLS = { rgb(255, 150, 190), rgb(255, 230, 120), rgb(255, 255, 255), rgb(190, 160, 250), rgb(255, 176, 130) }
	K.PAD_Y = 0.45

	---------------------------------------------------------------------------
	-- FOLDERS + STREAMING
	---------------------------------------------------------------------------
	K.root = Instance.new("Folder")
	K.root.Name = "SminskiCity"
	K.solidF = Instance.new("Folder")
	K.solidF.Name = "Solid"
	K.solidF.Parent = K.root
	K.walkF = Instance.new("Folder")
	K.walkF.Name = "Ground"
	K.walkF.Parent = K.root
	K.actors = Instance.new("Folder")
	K.actors.Name = "SminskiCityActors"
	K.cur = K.root
	K.deadline = nil -- os.clock() at which the running builder must yield

	local function budget()
		if K.deadline and os.clock() > K.deadline and coroutine.isyieldable() then
			coroutine.yield()
		end
	end
	K.budget = budget

	function K.W(x, y, z) return CFrame.new(CITY + V(x, y, z)) end
	local W = K.W
	function K.P(size, cf, color, mat, opts)
		budget()
		return part(K.cur, size, cf, color, mat or MATTE, opts)
	end
	local P = K.P
	-- PER-BLOCK COLLISION BINS -- and why they are not simply the block folder.
	--
	-- THE BUG: K.solid / K.walkable used to parent every collidable part
	-- straight into K.solidF / K.walkF, which hang off K.root and NOT off the
	-- block folder that City.lua's cull() unparents (City.lua:103-113). So
	-- every wall, floor, counter and shelf the city has ever built stayed
	-- resident in Workspace at every distance -- ~2,450 permanent colliders
	-- before any of the interior work, and it grows with every room we furnish.
	--
	-- We cannot just parent them into the block folder, because City.lua's car
	-- and pedestrian raycasts use an *Include* filter rooted at K.solidF /
	-- K.walkF (City.lua:2676-2677): anything outside those two folders stops
	-- existing as far as traffic is concerned. So each block gets its own pair
	-- of sub-folders INSIDE K.solidF / K.walkF, and we mirror the block
	-- folder's own parenting onto them. The existing cull then culls colliders
	-- too, without a line changing in City.lua -- which matters, since that
	-- file is not ours to edit.
	local blockBins = {}   -- [blockFolder] = { solid = Folder, walk = Folder }
	local curBlock = nil   -- the block K.cur currently belongs to, or nil
	local function bins()
		local c = K.cur
		-- K.cur is the block folder while a block streams in, but builders also
		-- point it at loose Models with no parent yet (the ferris wheel, a
		-- windmill's blades), so we remember the last block folder we saw
		-- rather than walking up from whatever K.cur happens to be. Base
		-- geometry (roads, the valley floor) builds with K.cur == K.root and is
		-- never culled, so it keeps going into the shared folders.
		if c == K.root then
			curBlock = nil
		elseif typeof(c) == "Instance" and c.Parent == K.root then
			curBlock = c
		end
		local f = curBlock
		if not f then return nil end
		local b = blockBins[f]
		if not b then
			b = { solid = Instance.new("Folder"), walk = Instance.new("Folder") }
			b.solid.Name, b.walk.Name = f.Name, f.Name
			b.solid.Parent, b.walk.Parent = K.solidF, K.walkF
			blockBins[f] = b
			-- test child == f: AncestryChanged also fires on every block folder
			-- when K.root itself enters or leaves Workspace, and reacting to
			-- that would resurrect the colliders of culled blocks on re-entry.
			f.AncestryChanged:Connect(function(child, parent)
				if child ~= f then return end
				b.solid.Parent = parent and K.solidF or nil
				b.walk.Parent = parent and K.walkF or nil
			end)
		end
		return b
	end
	K.bins = bins
	function K.solid(p)
		p.CanCollide = true
		p.CanQuery = true
		local b = bins()
		p.Parent = b and b.solid or K.solidF
		return p
	end
	function K.walkable(p)
		p.CanCollide = true
		p.CanQuery = true
		local b = bins()
		p.Parent = b and b.walk or K.walkF
		return p
	end
	local solid = K.solid

	-- K.prop: put an authored mesh into the world, if there is one to put.
	-- Returns the part, or nil when the asset is unreviewed or not imported --
	-- the caller then builds its part-built version as usual. This is the one
	-- door 3D assets come through (see .claude/rules/pipeline.md).
	local propFolder
	local function propTemplate(name)
		if propFolder == nil then
			local assets = game:GetService("ReplicatedStorage"):FindFirstChild("SminskiAssets")
			propFolder = assets and assets:FindFirstChild("Props") or false
		end
		return propFolder and propFolder:FindFirstChild(name) or nil
	end
	function K.prop(name, cf, opts)
		local e = Props.approved(name)
		if not e or not e.parts then return nil end
		if not propTemplate(e.parts[1].mesh) then return nil end
		budget()
		opts = opts or {}
		local s = opts.scale or 1
		local mode = opts.collide or e.collide or "none"
		local first, glow
		for _, def in e.parts do
			local tpl = propTemplate(def.mesh)
			local m = PropMeshes[def.mesh]
			if tpl and m then
				local p = tpl:Clone()
				p.Name = name
				p.Anchored = true
				p.Size = m.size * s
				-- imported kit meshes already face the kit's way (-Z); no turn
				p.CFrame = cf * CFrame.new(m.offset * s)
				p.Color = (opts.colors and opts.colors[def.mesh]) or opts.color or def.color
				p.Material = def.material or MATTE
				if def.glow then p.CastShadow = false glow = p end
				-- only the first part carries collision; the rest are skin, so
				-- a tree costs one collider instead of three (performance.md)
				if first == nil and mode ~= "none" then
					p.CanCollide, p.CanQuery = true, true
					-- same per-block bin as K.solid / K.walkable, so an imported
					-- prop culls with its block instead of living forever
					local b = bins()
					if mode == "walkable" then
						p.Parent = b and b.walk or K.walkF
					else
						p.Parent = b and b.solid or K.solidF
					end
				else
					p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
					p.Parent = K.cur
				end
				first = first or p
			end
		end
		if not first then return nil end
		-- the caller may want the emissive part specifically (street lamps hang
		-- their night PointLight on it)
		K.lastGlow = glow
		-- interaction points, in the asset's own space
		for pointName, def in pairs(e.points or {}) do
			local a = Instance.new("Attachment")
			a.Name = pointName
			a.CFrame = def.look and CFrame.lookAt(def.pos * s, def.pos * s + def.look) or CFrame.new(def.pos * s)
			a.Parent = first
		end
		return first
	end
	local prop = K.prop

	---------------------------------------------------------------------------
	-- K.inv / K.place: THE SECOND DOOR assets come through. Models the owner
	-- picked from their own Roblox inventory, curated by
	-- game/_inventory_setup.lua into ReplicatedStorage.SminskiAssets.Inventory:
	-- scripts, lights, sounds and emitters stripped, pivot at the feet, native
	-- size kept as H / W attributes. The owner choosing them is the review
	-- gate (.claude/rules/assets.md); this code only decides scale, tint and
	-- collision. Every caller keeps its part-built fallback, so a place file
	-- without the Inventory folder still builds the whole city.
	---------------------------------------------------------------------------
	local invFolder
	function K.inv(name)
		if invFolder == nil then
			local assets = game:GetService("ReplicatedStorage"):FindFirstChild("SminskiAssets")
			invFolder = assets and assets:FindFirstChild("Inventory") or false
		end
		return invFolder and invFolder:FindFirstChild(name) or nil
	end
	-- Stand a template with its feet at cf.
	--   opts.height / opts.width  scale it to that size (whichever given;
	--                             both -> the smaller scale wins)
	--   opts.scale                a raw multiplier instead
	--   opts.tint = { NameFragment = Color }  recolours untextured mesh parts
	--   opts.collide = "solid"    restores collision on parts bigger than a
	--                             hand, and parents into the block's solid bin
	function K.place(name, cf, opts)
		local tpl = K.inv(name)
		if not tpl then return nil end
		budget()
		opts = opts or {}
		local s = opts.scale or 1
		local H, Wd = tpl:GetAttribute("H") or 1, tpl:GetAttribute("W") or 1
		if opts.height then s = opts.height / math.max(0.1, H) end
		if opts.width then s = math.min(opts.height and s or math.huge, opts.width / math.max(0.1, Wd)) end
		local m = tpl:Clone()
		if math.abs(s - 1) > 0.001 then m:ScaleTo(s) end
		m:PivotTo(cf)
		-- MEASURED, NOT TRUSTED: the curated pivot is meant to be at the feet,
		-- but a model that arrived with a PrimaryPart kept that part's pivot
		-- instead (a beech stood 10.8 studs into the ground). Find the lowest
		-- vertex and lift the whole model so it sits exactly on cf.
		local lowest = math.huge
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local h = d.Size / 2
				local pcf = d.CFrame
				for _, a in { -1, 1 } do for _, b in { -1, 1 } do for _, c in { -1, 1 } do
					lowest = math.min(lowest, (pcf * V(a * h.X, b * h.Y, c * h.Z)).Y)
				end end end
			end
		end
		-- opts.sink lowers it into the ground by that much: a plaza whose
		-- slabs are 0.24 thick sinks 0.22 so their tops are flush
		local want = cf.Position.Y - (opts.sink or 0)
		if lowest < math.huge and math.abs(lowest - want) > 0.02 then
			m:PivotTo(m:GetPivot() * CFrame.new(0, want - lowest, 0))
		end
		if opts.tint then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and (not d:IsA("MeshPart") or d.TextureID == "") then
					for key, col in opts.tint do
						if string.find(d.Name, key, 1, true) then d.Color = col break end
					end
				end
			end
		end
		if opts.collide == "solid" then
			for _, d in m:GetDescendants() do
				-- Pass parts (an entrance's glass) stay walk-through
				if d:IsA("BasePart") and d.Size.Magnitude > 3 and not d:GetAttribute("Pass") then d.CanCollide, d.CanQuery = true, true end
			end
			local b = bins()
			m.Parent = b and b.solid or K.solidF
		else
			m.Parent = K.cur
		end
		return m, s
	end
	function K.cyl(dia, len, cf, color, mat, opts) -- axis = the frame's Y
		opts = opts or {}
		opts.shape = Enum.PartType.Cylinder
		return P(V(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, opts)
	end
	local cyl = K.cyl
	function K.ball(d, cf, color, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Ball
		return P(V(d, d, d), cf, color, mat, opts)
	end
	local ball = K.ball
	function K.blob(size, cf, color, mat, opts)
		opts = opts or {}
		opts.mesh = Enum.MeshType.Sphere
		return P(size, cf, color, mat, opts)
	end
	local blob = K.blob
	function K.wedge(size, cf, color, mat)
		return P(size, cf, color, mat, { class = "WedgePart" })
	end
	function K.textOn(p, face, str, color, canvas, lit, font)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.CanvasSize = canvas or Vector2.new(400, 80)
		sg.LightInfluence = lit or 0.8
		sg.MaxDistance = 700
		UI.text(sg, str, { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = font or Enum.Font.FredokaOne, TextColor3 = color, stroke = 0 })
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.05, 0), UDim.new(0.05, 0)
		pad.Parent = sg:FindFirstChildWhichIsA("TextLabel")
		sg.Parent = p
		return sg
	end
	local textOn = K.textOn
	-- a building frame on the pad: origin on the ground, local -Z = the street
	function K.frameOf(pos, face, y)
		local p = CITY + V(pos.X, y or K.PAD_Y, pos.Z)
		return CFrame.lookAt(p, p + V(math.sin(face), 0, math.cos(face)))
	end
	-- a signboard with lettering on its street face
	function K.sign(cf, w, h, bg, fg, str, lit)
		local b = P(V(w, h, 0.6), cf, bg)
		textOn(b, Enum.NormalId.Front, str, fg, Vector2.new(math.max(200, math.floor(w / h * 90)), 90), lit or 0.4)
		return b
	end

	---------------------------------------------------------------------------
	-- ARCHITECTURE
	---------------------------------------------------------------------------
	-- framed window on a wall (cf on the wall face, local -Z = outwards)
	function K.window(cf, w, h, curtains, box, lit)
		P(V(w + 2.6, h + 2.6, 0.4), cf * CFrame.new(0, 0, 0.12), K.trim or Cc.sage)
		P(V(w + 1.4, h + 1.4, 0.5), cf, Cc.cream)
		-- a "lit" window is WARM GLASS, not a light source. Neon panes this size
		-- are what made the town look like it was glowing; the warmth carries
		-- fine as a colour (.claude/rules/design.md, "emissive is for signage")
		local pane = P(V(w, h, 0.3), cf * CFrame.new(0, 0, -0.28), lit and rgb(240, 214, 160) or Cc.pane, SMOOTH)
		pane.Reflectance = lit and 0.04 or 0.08
		if lit then pane.CastShadow = false end
		P(V(0.4, h, 0.3), cf * CFrame.new(0, 0, -0.42), Cc.cream)
		P(V(w, 0.4, 0.3), cf * CFrame.new(0, 0, -0.42), Cc.cream)
		P(V(w + 2.2, 0.6, 1.2), cf * CFrame.new(0, -h / 2 - 0.9, -0.5), Cc.cream)
		if curtains then
			for _, sx in { -1, 1 } do
				P(V(w * 0.26, h - 0.4, 0.2), cf * CFrame.new(sx * (w / 2 - w * 0.13), 0, -0.1), curtains, Enum.Material.Fabric)
			end
		end
		if box then
			P(V(w + 1, 1.2, 1.4), cf * CFrame.new(0, -h / 2 - 1.8, -0.9), box, WOODM)
			for k = 0, 3 do
				ball(1, cf * CFrame.new(-w / 2 + 0.6 + k * (w - 1.2) / 3, -h / 2 - 0.9, -0.9), K.FLOWER_COLS[k % 5 + 1])
			end
		end
	end
	-- a band of glass with mullions (for towers + shopfronts)
	function K.glassBand(cf, w, h, color, mull)
		local g = P(V(w, h, 0.4), cf, color or Cc.glassBlue, SMOOTH)
		g.Reflectance = 0.18
		local n = math.max(1, math.floor(w / (mull or 6)))
		for k = 0, n do
			P(V(0.5, h, 0.6), cf * CFrame.new(-w / 2 + k * w / n, 0, -0.1), Cc.cream)
		end
		return g
	end
	-- SMISKI GREEN: the one colour in town that means "you can use this". It is
	-- on every threshold mat and every glow dot, and nowhere else, so a player
	-- learns it in about four seconds (.claude/rules/design.md).
	K.OPEN = rgb(126, 200, 116)

	-- A THRESHOLD: the green mat outside a door you can walk through. Doors
	-- that are OPEN also get their leaves swung back against the wall, because
	-- a shut door reads as locked no matter what colour the mat is.
	function K.threshold(cf, w, d)
		local m = P(V(w or 9, 0.16, d or 5), cf * CFrame.new(0, 0.08, 0), K.OPEN, Enum.Material.Fabric, { noShadow = true })
		P(V((w or 9) - 1.6, 0.2, (d or 5) - 1.2), cf * CFrame.new(0, 0.1, 0), tint(K.OPEN, 0.3), Enum.Material.Fabric, { noShadow = true })
		return m
	end

	function K.door(f, x, zFace, color, wide)
		local df = f * CFrame.new(x, 0, zFace)
		local dw = wide and 9 or 5
		P(V(dw + 1.4, 10, 0.6), df * CFrame.new(0, 5.4, -0.1), Cc.cream)
		if wide then
			for _, sx in { -1, 1 } do
				local g = P(V(dw / 2 - 0.3, 8.6, 0.3), df * CFrame.new(sx * dw / 4, 4.8, -0.45), Cc.pane, SMOOTH)
				g.Reflectance = 0.1
				P(V(0.3, 8.6, 0.35), df * CFrame.new(sx * 0.1, 4.8, -0.5), color)
			end
		else
			P(V(dw, 8.6, 0.4), df * CFrame.new(0, 4.8, -0.45), color)
			P(V(dw - 1.4, 2, 0.3), df * CFrame.new(0, 7.2, -0.65), Cc.pane, SMOOTH)
			ball(0.6, df * CFrame.new(dw / 2 - 0.9, 4.4, -0.8), Cc.gold, METAL)
		end
		P(V(dw + 3, 0.55, 2.4), df * CFrame.new(0, 0.3, -1.3), Cc.stone)
		ball(1, df * CFrame.new(dw / 2 + 1.6, 8.4, -0.6), rgb(255, 236, 190), NEON).CastShadow = false
	end

	-- AN OPEN DOOR: the leaves stand folded back against the wall, there is a
	-- genuine hole between them, and a green mat runs out onto the pavement.
	--
	-- WHAT WAS WRONG WITH THE OLD ONE. It closed the opening with a slab of
	-- rgb(58, 52, 48), described here as "a dark recess, so it reads as a way
	-- in, not a painted-on door". It does the exact opposite: from ten studs
	-- away a near-black rectangle in a doorway IS a shut door, which is the
	-- one thing an open door must never look like. Depth is sold by a hall set
	-- BACK from the opening with a little light in it -- never by painting the
	-- hole dark.
	--
	--   opts.recess  studs of hall to build behind the opening (default 4).
	--                Pass `false` when a REAL room stands behind the door (a
	--                venue, the job centre) or the hall's back wall would be
	--                built inside it. Every other caller must CUT the opening
	--                out of its own wall first (see B.apartments, B.aptTower
	--                in CityBuild) -- drop this on a solid facade and the hall
	--                is buried inside the geometry, showing nothing.
	--   opts.mat     false = the caller lays the green threshold itself,
	--                because its door sits up a stoop or on a raised floor.
	function K.openDoor(f, x, zFace, color, wide, opts)
		opts = opts or {}
		local df = f * CFrame.new(x, 0, zFace)
		local dw = wide and 9 or 6
		P(V(dw + 1.6, 10.4, 0.6), df * CFrame.new(0, 5.4, -0.1), Cc.cream)      -- surround
		local rec = opts.recess
		if rec == nil or rec == true then rec = 4 end
		-- under a stud of hall there is nothing to see, and the sizes below go
		-- negative, so treat a silly depth as "no hall"
		if rec and rec > 1.2 then
			-- the hall: a warm back wall set well back from the opening, lit by
			-- a strip over the doorway. Dim, never black -- from the pavement
			-- you should be able to tell there is a floor in there.
			P(V(dw, 9.4, 0.5), df * CFrame.new(0, 4.9, rec - 0.4), rgb(124, 106, 92), MATTE, { noShadow = true })
			P(V(dw - 1.2, 0.4, rec - 0.6), df * CFrame.new(0, 9.2, rec / 2 - 0.2), rgb(255, 232, 186), NEON, { noShadow = true })
		end
		P(V(dw + 0.6, 0.7, 0.8), df * CFrame.new(0, 9.9, -0.2), color)          -- lintel
		-- the leaves, folded back either side
		for _, sx in { -1, 1 } do
			local leaf = P(V(dw / 2 - 0.4, 8.8, 0.35), df * CFrame.new(sx * (dw / 2 + 1.1), 4.8, -1.5) * CFrame.Angles(0, sx * 1.25, 0), color)
			P(V(dw / 2 - 1.8, 2.2, 0.2), df * CFrame.new(sx * (dw / 2 + 1.1), 7.1, -1.5) * CFrame.Angles(0, sx * 1.25, 0) * CFrame.new(0, 0, -0.2), Cc.pane, SMOOTH)
		end
		if opts.mat ~= false then K.threshold(df * CFrame.new(0, 0, -3), dw + 4, 6) end
		local glow = ball(1, df * CFrame.new(dw / 2 + 1.9, 8.6, -0.6), rgb(255, 236, 190), NEON)
		glow.CastShadow = false
		return df
	end
	-- gable roof, ridge front-to-back, shingle courses + a round attic window
	function K.gable(f, w, d, y, rise, color)
		local a = w / 2 + 1.8
		local L = math.sqrt(a * a + rise * rise) + 0.4
		local th = math.atan2(rise, a)
		for _, sx in { -1, 1 } do
			local slab = f * CFrame.new(sx * a / 2, y + rise / 2 + 0.3, 0) * CFrame.Angles(0, 0, -sx * th)
			solid(P(V(L, 1.1, d + 3.4), slab, color))
			for k = 0, 3 do
				P(V(L / 4 - 0.2, 0.4, d + 3.6), slab * CFrame.new(-sx * (L / 2 - L / 8 - k * L / 4), 0.65, 0), k % 2 == 0 and shade(color, 0.08) or tint(color, 0.06))
			end
		end
		cyl(1.4, d + 4, f * CFrame.new(0, y + rise + 0.8, 0) * CFrame.Angles(math.pi / 2, 0, 0), shade(color, 0.18))
		for _, z in { -d / 2, d / 2 } do
			for _, sx in { -1, 1 } do
				P(V(0.8, rise, w / 2), f * CFrame.new(sx * w / 4, y + rise / 2, z) * CFrame.Angles(0, -sx * math.pi / 2, 0), Cc.cream, MATTE, { class = "WedgePart" })
			end
		end
		local vcf = f * CFrame.new(0, y + rise * 0.4, -d / 2 - 0.45) * CFrame.Angles(math.pi / 2, 0, 0)
		cyl(3.6, 0.4, vcf, shade(Cc.cream, 0.08))
		cyl(2.6, 0.45, vcf * CFrame.new(0, -0.05, 0), Cc.pane, SMOOTH)
	end
	function K.flatRoof(f, w, d, y, color)
		solid(P(V(w + 1.6, 1, d + 1.6), f * CFrame.new(0, y + 0.5, 0), color))
		for _, sx in { -1, 1 } do P(V(1, 1.8, d + 1.6), f * CFrame.new(sx * (w / 2 + 0.3), y + 1.9, 0), color) end
		for _, sz in { -1, 1 } do P(V(w + 1.6, 1.8, 1), f * CFrame.new(0, y + 1.9, sz * (d / 2 + 0.3)), color) end
		P(V(w + 2.4, 0.7, d + 2.4), f * CFrame.new(0, y - 0.2, 0), Cc.cream)
	end
	-- a chunky rounded cornice: two stepped bands with a trim stripe
	function K.cornice(f, w, d, y, col, stripe)
		P(V(w + 3.4, 1.8, d + 3.4), f * CFrame.new(0, y + 0.9, 0), col or Cc.cream)
		P(V(w + 2.2, 1.1, d + 2.2), f * CFrame.new(0, y - 0.5, 0), col or Cc.cream)
		P(V(w + 2.3, 0.5, d + 2.3), f * CFrame.new(0, y - 1.3, 0), stripe or Cc.sage)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				cyl(1.8, 1.8, f * CFrame.new(sx * (w / 2 + 1.7), y + 0.9, sz * (d / 2 + 1.7)), col or Cc.cream)
			end
		end
	end
	-- a cream planter with a rounded boxy bush
	function K.planter(cf, w)
		w = w or 4
		P(V(w, 2.4, w), cf * CFrame.new(0, 1.2, 0), Cc.cream)
		P(V(w + 0.4, 0.4, w + 0.4), cf * CFrame.new(0, 2.4, 0), K.shade(Cc.cream, 0.06))
		blob(V(w + 0.6, w * 0.8, w + 0.6), cf * CFrame.new(0, 3.2 + w * 0.2, 0), Cc.leaf)
	end
	function K.sideWindows(f, w, d, rows, y0, gap, curtains, n)
		n = n or 2
		for _, sx in { -1, 1 } do
			for r = 0, rows - 1 do
				for k = 1, n do
					local z = -d / 2 + k * d / (n + 1)
					K.window(f * CFrame.new(sx * w / 2, y0 + r * gap, z) * CFrame.Angles(0, -sx * math.pi / 2, 0), 3.6, 4, curtains)
				end
			end
		end
	end
	-- striped shop awning along a street face
	function K.awning(f, x, w, y, zFace, a, b)
		local n = math.max(4, math.floor(w / 2.2))
		for k = 0, n - 1 do
			local px = x - w / 2 + (k + 0.5) * w / n
			P(V(w / n + 0.05, 0.3, 5), f * CFrame.new(px, y, zFace - 2.2) * CFrame.Angles(0.42, 0, 0), k % 2 == 0 and a or b)
			ball(0.9, f * CFrame.new(px, y - 1.1, zFace - 4.5), k % 2 == 0 and a or b)
		end
	end

	---------------------------------------------------------------------------
	-- SKYSCRAPERS (the New York part of Sminski City): tiled window textures
	-- keep them cheap, setbacks + crowns give each one a silhouette
	---------------------------------------------------------------------------
	K.TEX = {
		mint = { id = "rbxassetid://118017550140724", col = rgb(170, 214, 190) },
		cream = { id = "rbxassetid://88018234538602", col = rgb(246, 238, 214) },
		butter = { id = "rbxassetid://91946634706110", col = rgb(244, 214, 140) },
		sage = { id = "rbxassetid://104188516381945", col = rgb(150, 196, 150) },
		blue = { id = "rbxassetid://105620402758605", col = rgb(130, 186, 238), glass = true },
		teal = { id = "rbxassetid://133933482581783", col = rgb(130, 214, 214), glass = true },
		lav = { id = "rbxassetid://135977809657447", col = rgb(192, 176, 244), glass = true },
		pink = { id = "rbxassetid://94917435199995", col = rgb(252, 184, 210), glass = true },
	}
	K.NEONS = { rgb(255, 110, 190), rgb(170, 120, 255), rgb(90, 200, 255), rgb(255, 200, 80), rgb(120, 240, 180), rgb(255, 140, 100) }
	-- a glowing sign; vertical = letters stacked down the side of a tower
	function K.neonSign(cf, str, col, vertical, size)
		size = size or 5
		local n = #str
		local w, h = vertical and size + 2 or n * size * 0.72 + 3, vertical and n * size * 1.05 + 3 or size + 2.4
		P(V(w + 1.2, h + 1.2, 1), cf * CFrame.new(0, 0, 0.5), rgb(40, 36, 70))
		local b = P(V(w, h, 0.5), cf, col, NEON)
		b.CastShadow = false
		local txt = str
		if vertical then txt = table.concat(string.split(str, ""), "\n") end
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 1.5
		sg.MaxDistance = 1200
		sg.CanvasSize = Vector2.new(math.floor(w * 11), math.floor(h * 11))
		local t = UI.text(sg, txt, { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1), stroke = 0 })
		t.LineHeight = 0.9
		sg.Parent = b
		return b
	end
	K.BILLBOARDS = { "rbxassetid://79560366126984", "rbxassetid://75799108909037", "rbxassetid://98690904491561", "rbxassetid://98275894509046" }
	function K.texture(p, tex, u, v)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			local t = Instance.new("Texture")
			t.Texture = tex
			t.Face = face
			t.StudsPerTileU = u or 32
			t.StudsPerTileV = v or 48
			t.OffsetStudsV = (v or 48) - (p.Size.Y % (v or 48))
			t.Parent = p
		end
	end
	function K.waterTower(cf, s)
		s = s or 1
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do P(V(0.6, 6, 0.6) * s, cf * CFrame.new(sx * 2.4 * s, 3 * s, sz * 2.4 * s), rgb(120, 96, 80), WOODM) end
		end
		P(V(6, 0.5, 6) * s, cf * CFrame.new(0, 6 * s, 0), rgb(120, 96, 80), WOODM)
		cyl(7 * s, 7 * s, cf * CFrame.new(0, 9.6 * s, 0), rgb(196, 150, 110), WOODM)
		for k = 0, 2 do cyl(7.2 * s, 0.3 * s, cf * CFrame.new(0, (7.4 + k * 2.2) * s, 0), rgb(90, 90, 96), METAL) end
		cyl(7.6 * s, 0.6 * s, cf * CFrame.new(0, 13.3 * s, 0), Cc.sage)
		cyl(5 * s, 1.2 * s, cf * CFrame.new(0, 14.2 * s, 0), Cc.sage)
		cyl(2.6 * s, 1.2 * s, cf * CFrame.new(0, 15.2 * s, 0), Cc.sage)
	end
	-- a zig-zag fire escape down a wall (cf on the wall, local -Z = outwards)
	function K.fireEscape(cf, floors, fh)
		local iron = rgb(70, 96, 78)
		for f = 1, floors do
			local y = f * fh
			P(V(10, 0.3, 3), cf * CFrame.new(0, y, -1.6), iron, METAL)
			P(V(10, 2.4, 0.2), cf * CFrame.new(0, y + 1.2, -3.1), iron, METAL, { transparency = 0.2 })
			P(V(0.4, fh * 1.05, 2.2), cf * CFrame.new((f % 2 == 0) and 3 or -3, y - fh / 2, -1.6) * CFrame.Angles(0, 0, (f % 2 == 0) and 0.9 or -0.9), iron, METAL)
		end
	end
	-- a glowing billboard with one of the game's key-art images
	function K.billboard(cf, w, h, img)
		K._bbN = (K._bbN or 0) + 1
		local fr = P(V(w + 2.4, h + 2.4, 1.4), cf * CFrame.new(0, 0, 0.8), K.NEONS[K._bbN % #K.NEONS + 1], NEON)
		fr.CastShadow = false
		P(V(w + 2.6, h + 2.6, 0.6), cf * CFrame.new(0, 0, 1.7), rgb(70, 76, 110)) -- a plain back, so it isn't a glowing slab from behind
		local sc = P(V(w, h, 0.4), cf, Color3.new(1, 1, 1), SMOOTH)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 1.3
		sg.CanvasSize = Vector2.new(1024, math.floor(1024 * h / w))
		sg.MaxDistance = 1200
		local im = Instance.new("ImageLabel")
		im.Size = UDim2.fromScale(1, 1)
		im.BackgroundTransparency = 1
		im.Image = img
		im.ScaleType = Enum.ScaleType.Crop
		im.Parent = sg
		sg.Parent = sc
		for k = 0, math.floor(w / 3) do
			local b = ball(0.8, cf * CFrame.new(-w / 2 + k * w / math.floor(w / 3), h / 2 + 0.6, -0.4), rgb(255, 236, 170), NEON)
			b.CastShadow = false
		end
		return sc
	end
	-- a tower: podium with shopfronts, up to three textured tiers, a crown
	--   o: { x, z, w, d, h, tex, crown = "spire"|"deco"|"water"|"garden"|"antenna", name, face }
	function K.skyscraper(o)
		local T = K.TEX[o.tex or "cream"]
		local TR = T.glass and rgb(246, 250, 255) or Cc.cream -- ledges
		local AC = o.accent or (T.glass and T.col:Lerp(Color3.new(0, 0, 0), 0.25) or Cc.sage)
		local f = CFrame.new(CITY + V(o.x, K.PAD_Y, o.z)) * CFrame.Angles(0, o.face or 0, 0)
		local w, d, h = o.w, o.d, o.h
		local PH = 24 -- the podium (two shop floors)
		solid(P(V(w + 4, PH, d + 4), f * CFrame.new(0, PH / 2, 0), Cc.cream))
		for _, side in { { 0, d / 2 + 2, w + 4 }, { math.pi, d / 2 + 2, w + 4 }, { math.pi / 2, w / 2 + 2, d + 4 }, { -math.pi / 2, w / 2 + 2, d + 4 } } do
			local sf = f * CFrame.Angles(0, side[1], 0) * CFrame.new(0, 0, -side[2] - 0.2)
			-- tower podium shopfronts: warm glass, not a strip light round the block
			local g = P(V(side[3] - 6, 9, 0.4), sf * CFrame.new(0, 6.5, 0), rgb(232, 214, 176), SMOOTH)
			g.Reflectance = 0.1
			g.CastShadow = false
			P(V(side[3] - 4, 1.2, 1), sf * CFrame.new(0, 11.6, -0.3), AC)
			P(V(side[3] - 2, 2.4, 1.2), sf * CFrame.new(0, PH - 1, -0.3), AC)
			P(V(side[3], 1.6, 0.8), sf * CFrame.new(0, 0.8, -0.2), AC)
		end
		-- tiers
		local tiers = o.tiers or { { 1, 0.62 }, { 0.78, 0.86 }, { 0.56, 1 } }
		local y0 = PH
		local top = { w = w, d = d }
		for i, tr in tiers do
			local tw, td = w * tr[1], d * tr[1]
			local y1 = math.floor(h * tr[2])
			local ht = y1 - y0
			if ht > 4 then
				local body = solid(P(V(tw, ht, td), f * CFrame.new(0, y0 + ht / 2, 0), T.col))
				K.texture(body, T.id, 32, 48)
				if T.glass then body.Material = SMOOTH body.Reflectance = 0.12 end
				-- a chunky ledge at each setback, sage corner piers
				P(V(tw + 2.4, 1.6, td + 2.4), f * CFrame.new(0, y1 + 0.8, 0), TR)
				P(V(tw + 1.2, 0.6, td + 1.2), f * CFrame.new(0, y1 - 0.4, 0), AC)
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do P(V(1.6, ht, 1.6), f * CFrame.new(sx * tw / 2, y0 + ht / 2, sz * td / 2), i == 1 and TR or AC) end
				end
				-- roof gardens on the setbacks
				if i < #tiers then
					local nw = w * tiers[i + 1][1]
					for _, sx in { -1, 1 } do
						K.blob(V(4, 3, (td - 4)), f * CFrame.new(sx * (tw / 2 + nw / 2) / 2, y1 + 2.8, 0), Cc.leaf)
					end
				end
				y0, top = y1, { w = tw, d = td }
			end
		end
		local rf = f * CFrame.new(0, y0 + 1.6, 0)
		local crown = o.crown
		if crown == "spire" or crown == "deco" then
			for k = 0, 3 do
				local s = 1 - k * 0.22
				P(V(top.w * 0.5 * s, 7, top.d * 0.5 * s), rf * CFrame.new(0, 3.5 + k * 7, 0), k % 2 == 0 and Cc.cream or AC)
			end
			if crown == "deco" then
				for k = 0, 4 do
					local s = 1 - k * 0.18
					cyl(top.w * 0.22 * s, 5, rf * CFrame.new(0, 31 + k * 5, 0), k % 2 == 0 and Cc.gold or Cc.cream, METAL)
				end
			end
			cyl(1.4, 60, rf * CFrame.new(0, 58, 0), rgb(226, 226, 232), METAL)
			local b = ball(2.6, rf * CFrame.new(0, 89, 0), Cc.red, NEON)
			K.blinkers = K.blinkers or {}
			table.insert(K.blinkers, b)
		elseif crown == "water" then
			K.waterTower(rf * CFrame.new(top.w * 0.2, 0, top.d * 0.15), 1.4)
			P(V(8, 5, 6), rf * CFrame.new(-top.w * 0.25, 2.5, -top.d * 0.2), rgb(214, 214, 206))
		elseif crown == "garden" then
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				K.blob(V(7, 6, 7), rf * CFrame.new(math.cos(a) * top.w * 0.28, 3, math.sin(a) * top.d * 0.28), k % 2 == 0 and Cc.leaf or Cc.leaf2)
			end
			P(V(top.w * 0.4, 0.6, top.d * 0.4), rf * CFrame.new(0, 0.3, 0), Cc.grass)
		elseif crown == "antenna" then
			for _, sx in { -1, 1 } do cyl(0.9, 40, rf * CFrame.new(sx * top.w * 0.2, 20, 0), rgb(226, 226, 232), METAL) end
			P(V(top.w * 0.6, 6, top.d * 0.6), rf * CFrame.new(0, 3, 0), Cc.cream)
		end
		-- lobby door + a name over it on the street face (local -Z)
		local df = f * CFrame.new(0, 0, -d / 2 - 2.2)
		P(V(12, 10, 0.6), df * CFrame.new(0, 5, -0.2), AC)
		P(V(10, 9, 0.4), df * CFrame.new(0, 4.5, -0.5), rgb(210, 236, 240), SMOOTH).Reflectance = 0.1
		P(V(16, 0.8, 6), df * CFrame.new(0, 12.4, -3), AC)
		if o.name then K.sign(df * CFrame.new(0, 16.6, -0.9), math.min(w - 6, #o.name * 2 + 6), 3.4, AC, Cc.cream, o.name) end
		for _, sx in { -1, 1 } do K.planter(df * CFrame.new(sx * 10, -K.PAD_Y + K.PAD_Y, -4), 3) end
		if o.neon then
			local col = K.NEONS[(#o.neon + math.floor(o.h)) % #K.NEONS + 1]
			K.neonSign(f * CFrame.new(w / 2 * 0.62, math.min(h * 0.45, 90), -d / 2 - 1.2), o.neon, col, true, 8)
			K.neonSign(f * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, math.min(h * 0.45, 90) + 10, -w / 2 - 1.2), o.neon, col, true, 8)
		end
		return { f = f, w = w, d = d, h = h }
	end
	-- a subway entrance: green railings, globe lamps, a sign, stairs going down
	function K.subway(cf)
		P(V(8, 0.3, 12), cf * CFrame.new(0, 0.15, 0), rgb(60, 60, 70))
		for k = 0, 4 do P(V(7, 0.6, 2), cf * CFrame.new(0, -0.2 - k * 0.8, -4 + k * 2), rgb(200, 200, 196)) end
		for _, sx in { -1, 1 } do
			P(V(0.4, 3.6, 12), cf * CFrame.new(sx * 4.2, 1.8, 0), rgb(70, 110, 84), METAL)
			P(V(0.5, 0.5, 12.4), cf * CFrame.new(sx * 4.2, 3.7, 0), rgb(70, 110, 84), METAL)
			cyl(0.5, 7, cf * CFrame.new(sx * 4.2, 3.5, -6), rgb(70, 110, 84), METAL)
			local g = ball(1.6, cf * CFrame.new(sx * 4.2, 7.6, -6), rgb(160, 230, 160), NEON)
			g.CastShadow = false
		end
		K.sign(cf * CFrame.new(0, 6, 6.2) * CFrame.Angles(0, math.pi, 0), 8, 1.6, rgb(70, 110, 84), Cc.cream, "SUBWAY")
	end
	function K.cart(cf, name, col)
		P(V(5, 3, 3), cf * CFrame.new(0, 2.4, 0), Cc.cream)
		P(V(5.2, 0.4, 3.2), cf * CFrame.new(0, 4, 0), rgb(200, 200, 206), METAL)
		for _, sx in { -1.8, 1.8 } do P(V(0.3, 1.8, 1.8), cf * CFrame.new(sx, 0.9, 1.6), Cc.ink, SMOOTH, { shape = Enum.PartType.Cylinder }) end
		P(V(0.25, 5, 0.25), cf * CFrame.new(0, 6.5, 0), rgb(200, 200, 206), METAL)
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			P(V(2, 0.2, 3.6), cf * CFrame.new(math.cos(a) * 1.6, 8.8, math.sin(a) * 1.6) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, 0.3), k % 2 == 0 and (col or Cc.butter) or Cc.cream)
		end
		if name then K.sign(cf * CFrame.new(0, 2.8, -1.55), 4.4, 1.2, col or Cc.sage, Cc.cream, name) end
	end

	---------------------------------------------------------------------------
	-- NATURE + STREET FURNITURE
	---------------------------------------------------------------------------
	-- INVENTORY TREES. Same call sites and the same part-built fallbacks: a
	-- tree is picked from the owner's Nature Pack by kind, tinted to that
	-- kind's palette (the deciduous meshes are untextured), scaled to the
	-- height the part-built tree had -- capped by width, because a maple that
	-- is 62 studs across at full size does not belong in a 5-stud street pit
	-- -- and given a slim invisible trunk collider so it still blocks you.
	-- The variant comes from the position, so a tree is the same tree on
	-- every visit. Cost: 2-3 mesh parts against 5 blobs and a cylinder.
	local INV_TREES = {
		round   = { "Tree_Beech_S", "Tree_Beech_M", "Tree_Broadleaf", "Tree_Beech_L" },
		blossom = { "Tree_Sakura", "Tree_Dogwood", "Tree_Sakura" },
		tall    = { "Tree_Redwood_S", "Tree_Beech_L", "Tree_Redwood_M" },
		birch   = { "Tree_Beech_S", "Tree_Broadleaf", "Tree_Beech_M" },
		autumn  = { "Tree_Maple", "Tree_Dogwood", "Tree_Beech_M" },
		pine    = { "Tree_Pine", "Tree_Redwood_S", "Tree_Pine" },
	}
	local function invTree(kind, base, s, look, height, maxWidth)
		local pool = INV_TREES[kind]
		if not pool then return nil end
		local p = base.Position
		local h = math.floor(math.abs(p.X) * 7 + math.abs(p.Z) * 13 + 0.5)
		local name = pool[h % #pool + 1]
		if not K.inv(name) then return nil end
		local tint = look and { Leaves = look[1], OuterLeaves = look[1], Leaf = look[1], MeshPart = look[1], Trunk = look[3] } or nil
		local m = K.place(name, base * CFrame.Angles(0, (h % 8) * 0.785, 0),
			{ height = height * s, width = maxWidth * s, tint = tint })
		if not m then return nil end
		solid(cyl(1.6 * s, 6 * s, base * CFrame.new(0, 3 * s, 0), Cc.trunk, WOODM, { transparency = 1 }))
		return m
	end
	K.invTree = invTree
	function K.tree(x, z, s, y)
		s = s or 1
		local base = W(x, y or K.PAD_Y, z)
		if invTree("round", base, s, nil, 18, 16) then return end
		if prop("tree", base, { scale = s }) then return end
		solid(cyl(1.8 * s, 8 * s, base * CFrame.new(0, 4 * s, 0), Cc.trunk, WOODM))
		local cols = { Cc.leaf, Cc.leaf2, Cc.leaf3 }
		local r = (math.floor(math.abs(x) * 7 + math.abs(z) * 13) % 3) + 1
		blob(V(12, 10, 12) * s, base * CFrame.new(0, 11.5 * s, 0), cols[r])
		blob(V(8, 7, 8) * s, base * CFrame.new(3.6 * s, 9.6 * s, 1.6 * s), cols[r % 3 + 1])
		blob(V(8, 7, 8) * s, base * CFrame.new(-3.2 * s, 10 * s, -2 * s), cols[r % 3 + 1])
		blob(V(7, 6.5, 7) * s, base * CFrame.new(-1 * s, 15.4 * s, 0.6 * s), cols[(r + 1) % 3 + 1])
	end
	-- a stacked pine for the valley slopes
	function K.pine(cf, s)
		if invTree("pine", cf, s or 1, nil, 27, 18) then return end
		if prop("pine", cf, { scale = s }) then return end
		cyl(2.2 * s, 8 * s, cf * CFrame.new(0, 4 * s, 0), Cc.trunk, WOODM)
		for k = 0, 3 do
			local d = (14 - k * 3.2) * s
			local c = k % 2 == 0 and Cc.pine or Cc.pine2
			P(V(d, 4.5 * s, d), cf * CFrame.new(0, (8 + k * 4.2) * s, 0), c, MATTE, { mesh = Enum.MeshType.Sphere })
		end
		P(V(2.4 * s, 4 * s, 2.4 * s), cf * CFrame.new(0, 25.5 * s, 0), Cc.pine2, MATTE, { mesh = Enum.MeshType.Sphere })
	end
	function K.bush(cf, s, col)
		if prop("bush", cf, { scale = s }) then return end
		blob(V(4.4, 3, 4.4) * (s or 1), cf * CFrame.new(0, 1.3 * (s or 1), 0), col or Cc.leaf3)
	end
	function K.hedge(cf, len)
		P(V(len, 3.2, 3), cf * CFrame.new(0, 1.6, 0), Cc.leaf3)
		for k = 0, math.floor(len / 5) do
			blob(V(4, 2, 3.4), cf * CFrame.new(-len / 2 + k * 5, 3.1, 0), Cc.leaf)
		end
	end
	function K.bench(cf)
		if prop("bench", cf) then return end
		for _, dz in { -0.5, 0.5 } do P(V(6, 0.35, 0.8), cf * CFrame.new(0, 1.9, dz), rgb(200, 146, 96), WOODM) end
		P(V(6, 1.4, 0.3), cf * CFrame.new(0, 3, 1.05), rgb(200, 146, 96), WOODM)
		for _, sx in { -2.6, 2.6 } do P(V(0.4, 2, 2), cf * CFrame.new(sx, 1, 0.1), Cc.lampPost, METAL) end
	end
	function K.flowers(cf, w, d)
		P(V(w, 0.6, d), cf * CFrame.new(0, 0.3, 0), Cc.soil)
		if K.inv("Flower") then
			-- the Nature Pack's flower plant, five palette colours in turn; a
			-- clover patch under every other one so the bed reads as planted
			local m = math.max(2, math.floor(w / 4))
			for i = 0, m - 1 do
				local at = cf * CFrame.new(-w / 2 + 2 + i * (w - 4) / math.max(1, m - 1), 0.6, ((i % 2) - 0.5) * d * 0.35)
				K.place("Flower", at * CFrame.Angles(0, i * 1.3, 0), { height = 2.2, tint = { Flower = K.FLOWER_COLS[i % 5 + 1] } })
				if i % 2 == 0 then K.place("Clover", at * CFrame.new(1, -0.3, 0), { width = 3.5, tint = { Clover = Cc.leaf3 } }) end
			end
			return
		end
		local n = math.max(2, math.floor(w / 2))
		for i = 0, n - 1 do
			ball(1.1, cf * CFrame.new(-w / 2 + 1 + i * (w - 2) / math.max(1, n - 1), 1, ((i % 2) - 0.5) * d * 0.4), K.FLOWER_COLS[i % 5 + 1])
		end
	end
	function K.lamp(x, z)
		local base = W(x, K.PAD_Y, z)
		-- REGISTER EITHER WAY. The mesh path returns early, so a registry line
		-- further down never ran and the town had no street lighting at night.
		local m = prop("lamp", base)
		if m then
			K.lampGlobes = K.lampGlobes or {}
			table.insert(K.lampGlobes, K.lastGlow or m)
			return
		end
		cyl(2, 1.2, base * CFrame.new(0, 0.6, 0), Cc.lampPost, METAL)
		solid(cyl(0.8, 13, base * CFrame.new(0, 6.5, 0), Cc.lampPost, METAL))
		cyl(1.4, 0.6, base * CFrame.new(0, 12.6, 0), Cc.lampPost, METAL)
		local g = ball(2.2, base * CFrame.new(0, 14, 0), rgb(255, 214, 140), NEON)
		g.CastShadow = false
		-- registered so CityWeather can hang its pool of eight PointLights on
		-- whichever globes are nearest you after dark (same idea as K.blinkers)
		K.lampGlobes = K.lampGlobes or {}
		table.insert(K.lampGlobes, g)
		for _, a in { 0, math.pi / 2 } do P(V(2.5, 0.3, 0.3), base * CFrame.new(0, 13, 0) * CFrame.Angles(0, a, 0), Cc.lampPost, METAL) end
		P(V(2.8, 0.5, 2.8), base * CFrame.new(0, 15.4, 0) * CFrame.Angles(0, math.pi / 4, 0), Cc.lampPost, METAL)
		ball(0.7, base * CFrame.new(0, 15.9, 0), Cc.lampPost, METAL)
		-- a hanging flower basket
		P(V(2.6, 0.3, 0.3), base * CFrame.new(1.3, 10.6, 0), Cc.lampPost, METAL)
		K.blob(V(2, 1.6, 2), base * CFrame.new(2.4, 9.6, 0), Cc.leaf)
		ball(0.8, base * CFrame.new(2.2, 10.2, 0.5), K.FLOWER_COLS[(math.floor(x + z) % 5) + 1])
		ball(0.7, base * CFrame.new(2.7, 9.9, -0.5), K.FLOWER_COLS[(math.floor(x - z) % 5) + 1])
	end
	---------------------------------------------------------------------------
	-- STREET FURNITURE. Each tries the authored mesh first (K.prop) and falls
	-- back to a part-built version, so the street is dressed whether or not
	-- the Blender kit has been imported. cf = ground contact, -Z = the street.
	---------------------------------------------------------------------------
	function K.hydrant(cf)
		if prop("hydrant", cf) then return end
		solid(cyl(1.4, 2.4, cf * CFrame.new(0, 1.2, 0), rgb(214, 96, 88), METAL))
		ball(1.5, cf * CFrame.new(0, 2.5, 0), rgb(214, 96, 88), METAL)
		cyl(0.6, 2, cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(196, 84, 78), METAL)
	end
	function K.trashcan(cf)
		if prop("trashcan", cf) then return end
		solid(cyl(2.4, 3, cf * CFrame.new(0, 1.5, 0), rgb(104, 124, 112), METAL))
		cyl(2.7, 0.5, cf * CFrame.new(0, 3.2, 0), rgb(84, 102, 92), METAL)
	end
	function K.mailbox(cf)
		if prop("mailbox", cf) then return end
		cyl(0.7, 2, cf * CFrame.new(0, 1, 0), rgb(70, 100, 150), METAL)
		solid(P(V(2, 2.6, 1.6), cf * CFrame.new(0, 3.2, 0), rgb(96, 140, 196), METAL))
		blob(V(2, 1.2, 1.6), cf * CFrame.new(0, 4.5, 0), rgb(96, 140, 196), METAL)
	end
	function K.bikerack(cf)
		if prop("bikerack", cf) then return end
		P(V(7, 0.4, 0.4), cf * CFrame.new(0, 2.6, 0), Cc.lampPost, METAL)
		for _, sx in { -3.2, -1, 1, 3.2 } do cyl(0.4, 2.8, cf * CFrame.new(sx, 1.4, 0), Cc.lampPost, METAL) end
	end
	function K.newsbox(cf, col)
		cyl(0.5, 1.6, cf * CFrame.new(0, 0.8, 0), Cc.ink, METAL)
		solid(P(V(2, 2.6, 1.8), cf * CFrame.new(0, 2.6, 0), col or rgb(226, 120, 96), METAL))
		P(V(1.5, 1.2, 0.2), cf * CFrame.new(0, 3, -0.95), rgb(236, 240, 236), SMOOTH)
	end
	function K.meter(cf)
		cyl(0.4, 4, cf * CFrame.new(0, 2, 0), rgb(120, 126, 130), METAL)
		blob(V(1.2, 1.6, 0.9), cf * CFrame.new(0, 4.5, 0), rgb(84, 92, 100), METAL)
	end
	-- a bus shelter: glass back, bench, a route sign (buses stop here)
	function K.busStop(cf, label)
		for _, sx in { -5.4, 5.4 } do solid(cyl(0.5, 9, cf * CFrame.new(sx, 4.5, 1.6), Cc.lampPost, METAL)) end
		local g = P(V(10.8, 6, 0.3), cf * CFrame.new(0, 5, 1.6), Cc.pane, K.GLASS, { transparency = 0.5 })
		g.CastShadow = false
		P(V(12.4, 0.5, 5), cf * CFrame.new(0, 9.2, 0), Cc.lampPost, METAL)
		P(V(8, 0.5, 1.6), cf * CFrame.new(0, 2, 0.9), rgb(200, 146, 96), WOODM)
		local sgn = P(V(3.4, 3.4, 0.4), cf * CFrame.new(7.4, 8, 0), rgb(84, 140, 206))
		cyl(0.4, 8, cf * CFrame.new(7.4, 4, 0), Cc.lampPost, METAL)
		K.textOn(sgn, Enum.NormalId.Front, label or "BUS", Cc.cream, Vector2.new(160, 160), 0.5)
		K.textOn(sgn, Enum.NormalId.Back, label or "BUS", Cc.cream, Vector2.new(160, 160), 0.5)
	end

	-- TREE VARIETIES. One street of identical trees reads as a model kit; a
	-- mix reads as a place. With the mesh imported these are recolours of the
	-- one tree mesh; without it they are distinct part-built shapes.
	K.TREE_KINDS = { "round", "blossom", "tall", "birch", "autumn" }
	local TREE_LOOK = {
		blossom = { rgb(244, 178, 200), rgb(232, 150, 182), Cc.trunk },
		autumn  = { rgb(232, 168, 92), rgb(214, 128, 76), Cc.trunk },
		birch   = { rgb(168, 206, 124), rgb(140, 186, 108), rgb(232, 228, 216) },
		tall    = { rgb(96, 156, 96), rgb(80, 136, 86), Cc.trunk },
	}
	function K.treeKind(kind, x, z, s, y)
		s = s or 1
		local look = TREE_LOOK[kind]
		if not look then return K.tree(x, z, s, y) end
		local base = W(x, y or K.PAD_Y, z)
		if invTree(kind, base, s, look, kind == "tall" and 27 or 18, kind == "tall" and 13 or 16) then return end
		if prop("tree", base, { scale = kind == "tall" and s * 1.15 or s, colors = { tree_leaf = look[1], tree_leaf2 = look[2], tree_timber = look[3] } }) then return end
		if kind == "tall" then
			solid(cyl(1.6 * s, 7 * s, base * CFrame.new(0, 3.5 * s, 0), look[3], WOODM))
			blob(V(7, 20, 7) * s, base * CFrame.new(0, 15 * s, 0), look[1])
			blob(V(5, 12, 5) * s, base * CFrame.new(0.6 * s, 21 * s, 0.4 * s), look[2])
		else
			solid(cyl((kind == "birch" and 1.2 or 1.8) * s, 9 * s, base * CFrame.new(0, 4.5 * s, 0), look[3], WOODM))
			blob(V(11, 9, 11) * s, base * CFrame.new(0, 12 * s, 0), look[1])
			blob(V(7.5, 6.5, 7.5) * s, base * CFrame.new(3.2 * s, 10.4 * s, 1.4 * s), look[2])
			blob(V(7, 6, 7) * s, base * CFrame.new(-3 * s, 10.8 * s, -1.8 * s), look[2])
			blob(V(6, 5.5, 6) * s, base * CFrame.new(-0.6 * s, 15.6 * s, 0.4 * s), look[1])
		end
	end

	function K.fence(a, b, col)
		local mid, len = (a + b) / 2, (b - a).Magnitude
		local cf = CFrame.lookAt(CITY + V(mid.X, K.PAD_Y + 1.8, mid.Z), CITY + V(b.X, K.PAD_Y + 1.8, b.Z))
		col = col or Cc.cream
		P(V(0.4, 0.5, len), cf, col)
		P(V(0.4, 0.5, len), cf * CFrame.new(0, 1.4, 0), col)
		local n = math.max(1, math.floor(len / 8))
		for k = 0, n do P(V(0.7, 4, 0.7), cf * CFrame.new(0, 0.2, -len / 2 + k * len / n), col) end
	end
	function K.stall(cf, name, a)
		P(V(10, 3.6, 5), cf * CFrame.new(0, 1.8, 0), rgb(214, 170, 120), WOODM)
		for _, sx in { -4.6, 4.6 } do P(V(0.5, 8, 0.5), cf * CFrame.new(sx, 4, 2), rgb(170, 124, 84), WOODM) end
		for k = 0, 5 do
			P(V(1.8, 0.3, 6), cf * CFrame.new(-4.5 + k * 1.8, 8.2, 0) * CFrame.Angles(0.3, 0, 0), k % 2 == 0 and a or Cc.cream)
		end
		if name then K.sign(cf * CFrame.new(0, 9.8, -1.8), 8, 1.8, Cc.cream, a, name) end
	end

	---------------------------------------------------------------------------
	-- CARS: one kit for your car, parked cars, other players and traffic.
	-- Built around the origin; local -Z = forward. seat = where a driver's
	-- feet go (x, y, z) for the "sit" pose.
	---------------------------------------------------------------------------
	K.CAR_COLORS = {
		rgb(255, 170, 170), rgb(150, 206, 250), rgb(255, 222, 130), rgb(170, 226, 160),
		rgb(206, 180, 250), rgb(255, 196, 150), rgb(250, 250, 244), rgb(140, 220, 210),
	}
	K.SEAT = {
		convertible = V(0, 2.2, 0.9), van = V(0, 2.8, -0.6), taxi = V(0, 2.3, 0.4), icecream = V(0, 2.8, -1.4),
		sports = V(0, 1.6, 1.2), monster = V(0, 5.2, 0.9), bus = V(0, 3, -7),
	}
	function K.buildCar(kind, color, parent)
		kind = K.SEAT[kind] and kind or "convertible"
		local m = Instance.new("Model")
		m.Name = "SminskiCar"
		m:SetAttribute("Kind", kind)
		local function A(size, cf, col, mat, opts) return part(m, size, cf, col, mat or SMOOTH, opts) end
		local cyX = { shape = Enum.PartType.Cylinder }
		local lift = kind == "monster" and 3 or 0
		local wheelD = kind == "monster" and 6 or kind == "sports" and 2 or 2.3
		local len = kind == "van" and 12 or kind == "icecream" and 13 or kind == "sports" and 11 or 10
		local half = len / 2
		if kind == "taxi" then color = rgb(255, 214, 90) end
		-- body: a rounded slab
		local bodyH = kind == "sports" and 1.5 or 1.9
		local by = (kind == "sports" and 1.5 or 1.9) + lift
		A(V(5.6, bodyH, len - 3.4), CFrame.new(0, by, 0), color)
		A(V(5.6, bodyH, bodyH), CFrame.new(0, by, -half + 1.7), color, SMOOTH, cyX)
		A(V(5.6, bodyH, bodyH), CFrame.new(0, by, half - 1.7), color, SMOOTH, cyX)
		if kind == "van" or kind == "icecream" then
			-- a tall cabin with round windows
			local top = kind == "icecream" and rgb(255, 250, 244) or tint(color, 0.15)
			A(V(5.6, 5, len - 4.2), CFrame.new(0, by + 3.4, 0.6), top)
			A(V(5.4, 0.8, len - 4), CFrame.new(0, by + 6.2, 0.6), shade(color, 0.08))
			local ws = A(V(4.8, 2.6, 0.2), CFrame.new(0, by + 3.9, -half + 2.2) * CFrame.Angles(-0.2, 0, 0), Cc.pane, K.GLASS, { transparency = 0.45 })
			ws.CastShadow = false
			for _, sx in { -1, 1 } do
				for k = 0, 1 do
					A(V(0.3, 2.2, 2.2), CFrame.new(sx * 2.85, by + 4, -0.5 + k * 3.2), Cc.pane, SMOOTH, cyX)
				end
			end
			if kind == "icecream" then
				-- the giant cone on the roof + a serving hatch
				for k = 0, 3 do A(V(2.6 - k * 0.5, 1, 2.6 - k * 0.5), CFrame.new(0, by + 9.6 - k * 0.9, 3), rgb(226, 172, 110), SMOOTH, { shape = Enum.PartType.Cylinder }) end
				A(V(3.4, 3.4, 3.4), CFrame.new(0, by + 11.6, 3), rgb(255, 196, 220), MATTE, { shape = Enum.PartType.Ball })
				A(V(0.9, 0.9, 0.9), CFrame.new(0, by + 13.4, 3), Cc.red, MATTE, { shape = Enum.PartType.Ball })
				A(V(0.3, 2.4, 4.6), CFrame.new(2.9, by + 3.8, 2), rgb(255, 180, 200))
			end
		else
			A(V(5.2, 0.7, 3), CFrame.new(0, by + 1.2, -half + 2.4) * CFrame.Angles(0.08, 0, 0), tint(color, 0.08))
			A(V(5.2, 0.7, 2.2), CFrame.new(0, by + 1.2, half - 2), tint(color, 0.08))
			if kind == "taxi" then
				-- a hard top with a checker band and a roof light
				A(V(5, 2.6, 4.6), CFrame.new(0, by + 3.1, 1), color)
				A(V(5.1, 0.6, 4.7), CFrame.new(0, by + 2.1, 1), Cc.ink)
				A(V(2.6, 0.9, 1.2), CFrame.new(0, by + 4.8, 1), rgb(255, 250, 230), NEON)
				for _, sx in { -1, 1 } do A(V(0.3, 1.6, 3.4), CFrame.new(sx * 2.5, by + 3.3, 1), Cc.pane, SMOOTH) end
			end
			if kind == "sports" then
				A(V(5.8, 0.4, 1.6), CFrame.new(0, by + 2.4, half - 0.8), shade(color, 0.3))
				for _, sx in { -2, 2 } do A(V(0.4, 1.2, 0.6), CFrame.new(sx, by + 1.7, half - 0.8), shade(color, 0.3)) end
				A(V(5.8, 0.25, len - 1), CFrame.new(0, by - 0.8, 0), Cc.ink)
			end
			local ws = A(V(4.8, 1.8, 0.2), CFrame.new(0, by + 2.5, -half + 3.5) * CFrame.Angles(-0.35, 0, 0), Cc.pane, K.GLASS, { transparency = 0.5 })
			ws.CastShadow = false
		end
		-- the seat + steering wheel at the driver's spot
		local seat = K.SEAT[kind]
		A(V(4.2, 0.6, 2.4), CFrame.new(0, seat.Y + 0.85, seat.Z), Cc.cream)
		A(V(4.2, 2.2, 0.7), CFrame.new(0, seat.Y + 1.9, seat.Z + 1.5) * CFrame.Angles(0.15, 0, 0), Cc.cream)
		A(V(0.25, 1.3, 1.3), CFrame.new(0, seat.Y + 2.1, seat.Z - 1.6) * CFrame.Angles(0.5, 0, 0), Cc.ink, SMOOTH, cyX)
		-- wheels with cream hubcaps (monster trucks get chunky treads)
		for _, sx in { -1, 1 } do
			for _, sz in { -half + 1.9, half - 1.9 } do
				local wx = sx * (kind == "monster" and 3.6 or 2.6)
				A(V(kind == "monster" and 2.4 or 1, wheelD, wheelD), CFrame.new(wx, wheelD / 2, sz), Cc.ink, SMOOTH, cyX)
				A(V(kind == "monster" and 2.5 or 1.1, wheelD * 0.45, wheelD * 0.45), CFrame.new(wx, wheelD / 2, sz), Cc.cream, SMOOTH, cyX)
			end
		end
		if kind == "monster" then
			for _, sx in { -1, 1 } do A(V(0.8, 0.8, len - 2), CFrame.new(sx * 1.8, 2.6, 0), Cc.ink, METAL) end
		end
		for _, sx in { -1.8, 1.8 } do
			A(V(1.2, 1.2, 1.2), CFrame.new(sx, by + 0.4, -half + 0.6), rgb(255, 248, 220), NEON, { shape = Enum.PartType.Ball })
			A(V(1, 0.7, 0.4), CFrame.new(sx, by + 0.4, half - 0.3), rgb(255, 110, 110), NEON)
		end
		A(V(5.8, 0.6, 0.6), CFrame.new(0, by - 0.9, -half + 0.2), Cc.cream)
		A(V(5.8, 0.6, 0.6), CFrame.new(0, by - 0.9, half - 0.2), Cc.cream)
		for _, p in m:GetChildren() do p.CastShadow = p.Size.Magnitude > 4 end
		m.WorldPivot = CFrame.new()
		m.Parent = parent
		return m, seat
	end

	-- a MOVING city bus: the same shape as K.bus below, but built into its own
	-- model (front = -Z, pivot on the ground) so traffic can drive it
	function K.buildBus(color, label, parent)
		local m = Instance.new("Model")
		m.Name = "Bus"
		local function A(size, cf, col, mat, opts) return part(m, size, cf, col, mat or MATTE, opts) end
		local body = color or rgb(96, 150, 206)
		A(V(7.4, 7.4, 24), CFrame.new(0, 4.8, 0), body)
		A(V(7.6, 1, 24.2), CFrame.new(0, 3, 0), Cc.ink)
		A(V(7.5, 1.2, 24.1), CFrame.new(0, 7.2, 0), Cc.cream)
		for k = 0, 5 do
			for _, sx in { -1, 1 } do
				A(V(0.3, 2.6, 3), CFrame.new(sx * 3.75, 5.6, -8.5 + k * 3.5), Cc.pane, SMOOTH, { reflect = 0.1 })
			end
		end
		A(V(6.4, 3.2, 0.3), CFrame.new(0, 5.8, -12.1), Cc.pane, SMOOTH, { reflect = 0.1 })
		for _, sz in { -8, 8 } do
			for _, sx in { -1, 1 } do A(V(1.2, 3.2, 3.2), CFrame.new(sx * 3.4, 1.6, sz), Cc.ink, SMOOTH, { shape = Enum.PartType.Cylinder }) end
		end
		for _, sx in { -2.6, 2.6 } do
			A(V(1.2, 1.2, 1.2), CFrame.new(sx, 3.4, -12.1), rgb(255, 244, 210), NEON, { shape = Enum.PartType.Ball })
			A(V(1, 0.7, 0.4), CFrame.new(sx, 3.4, 12.1), rgb(255, 110, 110), NEON)
		end
		local sgn = A(V(5.4, 1.1, 0.2), CFrame.new(0, 8, -12.1), Cc.ink)
		K.textOn(sgn, Enum.NormalId.Front, label or "BUS", body, Vector2.new(300, 60))
		for _, p in m:GetChildren() do p.CastShadow = p.Size.Magnitude > 6 end
		m.WorldPivot = CFrame.new()
		m.Parent = parent
		return m
	end

	-- a round-nosed bus (school bus / city bus)
	function K.bus(cf, color, label)
		local y = color or rgb(255, 214, 90)
		solid(P(V(7.4, 7.4, 24), cf * CFrame.new(0, 4.8, 0), y))
		P(V(7.6, 1, 24.2), cf * CFrame.new(0, 3, 0), Cc.ink)
		for k = 0, 5 do
			for _, sx in { -1, 1 } do
				local g = P(V(0.3, 2.8, 3), cf * CFrame.new(sx * 3.75, 6.3, -8.5 + k * 3.5), Cc.pane, SMOOTH)
				g.Reflectance = 0.1
			end
		end
		P(V(6.4, 3.2, 0.3), cf * CFrame.new(0, 6.3, -12.1), Cc.pane, SMOOTH)
		for _, sz in { -8, 8 } do
			for _, sx in { -1, 1 } do P(V(1.2, 3.2, 3.2), cf * CFrame.new(sx * 3.4, 1.6, sz), Cc.ink, SMOOTH, { shape = Enum.PartType.Cylinder }) end
		end
		for _, sx in { -2.6, 2.6 } do ball(1.2, cf * CFrame.new(sx, 3.6, -12.1), rgb(255, 244, 210), NEON) end
		if label then
			local sgn = P(V(5.4, 1.1, 0.2), cf * CFrame.new(0, 8.4, -12.1), Cc.ink)
			textOn(sgn, Enum.NormalId.Front, label, y, Vector2.new(300, 60))
		end
	end

	---------------------------------------------------------------------------
	-- K.furn -- THE INTERIOR KIT
	--
	-- Until now there was not one chair, table, counter, shelf, bed or till in
	-- this file, so a new shop interior was ~46 lines of inline primitives --
	-- which is exactly why every restaurant in town is the same restaurant.
	-- The furniture that did exist lived in CityApts as a private `FURN` table;
	-- it has been MOVED here (not copied -- CityApts now calls these) so a
	-- street room, a flat, a lobby and a landmark all furnish from one kit.
	--
	-- Every piece takes a drawing CONTEXT as its first argument, rather than
	-- drawing into K.cur directly, because the two callers want different
	-- things from a "solid":
	--   * a street room is part of a block and wants K.solid, so the part goes
	--     into the block's collision bin and culls with it;
	--   * a flat is one Model that is built on approach and destroyed on exit
	--     (CityApts.buildFlat / clearRoom), so its solids must stay inside that
	--     Model and only need CanCollide set.
	-- The context is explicit and not a module-global because builders yield on
	-- K.budget() and City.lua may resume a DIFFERENT block's coroutine at the
	-- next frame -- a "currently bound" context would silently leak across it.
	--
	--   ctx.P(size, cf, color, material, opts) -> BasePart
	--   ctx.solid(part) -> part            (make it collide, park it correctly)
	--   ctx.spot(cf, title, sub, btn, icon, act)   -- register an interaction
	--
	-- `spot` is CityApts' shape, which is the one that already works; a caller
	-- that wants the 6-element prompt array converts in its own ctx.spot.
	---------------------------------------------------------------------------
	local FABRIC = Enum.Material.Fabric
	K.FABRIC = FABRIC
	local function noSpot() end
	-- the default context: draws into K.cur, collides through K.solid, and
	-- collects interactions into `spots` if you give it a list
	function K.furnCtx(spots)
		return {
			P = K.P,
			solid = K.solid,
			spot = spots and function(cf, title, sub, btn, icon, act)
				table.insert(spots, { pos = cf.Position, title = title, sub = sub, btn = btn, icon = icon, act = act })
			end or noSpot,
		}
	end
	-- shape helpers on top of a context (the kit's own cyl/ball/blob draw into
	-- K.cur, which is wrong for a room that owns its own Model)
	local function fcyl(c, dia, len, cf, col, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Cylinder
		return c.P(V(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), col, mat, opts)
	end
	local function fball(c, d, cf, col, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Ball
		return c.P(V(d, d, d), cf, col, mat, opts)
	end
	local function fblob(c, size, cf, col, mat, opts)
		opts = opts or {}
		opts.mesh = Enum.MeshType.Sphere
		return c.P(size, cf, col, mat, opts)
	end
	K.fcyl, K.fball, K.fblob = fcyl, fball, fblob

	local F = {}
	K.furn = F

	-------------------------------------------------------------------- HOME --
	-- (moved verbatim from CityApts' FURN; the geometry is unchanged so no
	-- flat's layout moves. Only the drawing calls are parameterised.)
	function F.bed(c, cf, col)
		c.solid(c.P(V(9, 2, 13), cf * CFrame.new(0, 1, 0), rgb(176, 136, 100), WOODM))
		c.P(V(8.6, 1.4, 12.4), cf * CFrame.new(0, 2.6, 0), rgb(250, 248, 242), FABRIC)
		c.P(V(8.8, 1.5, 8), cf * CFrame.new(0, 2.8, 2.2), col, FABRIC)
		for _, sx in { -2.1, 2.1 } do fblob(c, V(3.4, 1.4, 2.4), cf * CFrame.new(sx, 3.6, -4.6), rgb(255, 255, 255), FABRIC) end
		c.P(V(9.4, 5, 0.8), cf * CFrame.new(0, 3.4, -6.6), rgb(150, 110, 80), WOODM)
		c.spot(cf * CFrame.new(5.6, 0, 0), "YOUR BED", "a little lie down", "NAP", "heart", { sit = cf * CFrame.new(0, 3.4, 1), lines = { "zzz... best nap in town", "five more minutes", "you feel rested" } })
	end
	function F.sofa(c, cf, col)
		c.solid(c.P(V(12, 2, 4.6), cf * CFrame.new(0, 1.2, 0), col, FABRIC))
		c.P(V(12, 3.6, 1.2), cf * CFrame.new(0, 3.2, 1.8), col, FABRIC)
		for _, sx in { -5.6, 5.6 } do c.P(V(1.2, 3, 4.6), cf * CFrame.new(sx, 2.4, 0), shade(col, 0.08), FABRIC) end
		for _, sx in { -3, 3 } do fblob(c, V(2.4, 2, 1.6), cf * CFrame.new(sx, 3, 1), tint(col, 0.4), FABRIC) end
		c.spot(cf * CFrame.new(0, 0, -3.4), "THE SOFA", "put your feet up", "SIT", "heart", { sit = cf * CFrame.new(0, 2.3, -0.2) })
	end
	function F.rug(c, cf, w, d, col)
		c.P(V(w, 0.12, d), cf * CFrame.new(0, 0.07, 0), col, FABRIC, { noShadow = true })
		c.P(V(w - 2, 0.14, d - 2), cf * CFrame.new(0, 0.08, 0), tint(col, 0.3), FABRIC, { noShadow = true })
	end
	function F.coffee(c, cf)
		c.P(V(6, 0.5, 3.4), cf * CFrame.new(0, 1.6, 0), rgb(196, 156, 116), WOODM)
		for _, sx in { -2.4, 2.4 } do c.P(V(0.5, 1.4, 2.6), cf * CFrame.new(sx, 0.7, 0), Cc.ink, METAL) end
		fblob(c, V(1.2, 1, 1.2), cf * CFrame.new(1.4, 2.3, 0), rgb(240, 150, 170))
	end
	function F.tv(c, cf)
		c.solid(c.P(V(12, 2, 2.6), cf * CFrame.new(0, 1, 0), rgb(236, 232, 222)))
		c.P(V(10, 5.6, 0.4), cf * CFrame.new(0, 5.4, 0.6), Cc.ink, SMOOTH)
		c.P(V(9.4, 5, 0.1), cf * CFrame.new(0, 5.4, 0.36), rgb(120, 190, 230), NEON, { noShadow = true })
	end
	function F.dining(c, cf, col)
		fcyl(c, 1, 3, cf * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
		c.solid(fcyl(c, 7, 0.5, cf * CFrame.new(0, 3.2, 0), rgb(236, 226, 206), WOODM))
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local s = cf * CFrame.new(math.cos(a) * 5, 0, math.sin(a) * 5)
			fcyl(c, 0.5, 1.8, s * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
			fcyl(c, 2.2, 0.5, s * CFrame.new(0, 2, 0), col, SMOOTH)
		end
		c.spot(cf * CFrame.new(5, 0, 5), "THE TABLE", "pull up a stool", "SIT", "heart", { sit = CFrame.lookAt((cf * CFrame.new(3.5, 2.2, 3.5)).Position, (cf * CFrame.new(0, 2.2, 0)).Position) })
	end
	function F.kitchen(c, cf, len, col)
		c.solid(c.P(V(len, 3.6, 2.8), cf * CFrame.new(0, 1.8, 0), col))
		c.P(V(len + 0.4, 0.4, 3.2), cf * CFrame.new(0, 3.8, 0), rgb(236, 232, 222), SMOOTH)
		c.P(V(len, 3, 1.6), cf * CFrame.new(0, 9, -0.6), col)
		c.P(V(3, 0.2, 2), cf * CFrame.new(-len / 4, 4.05, 0), Cc.ink, SMOOTH)
		c.P(V(3, 0.3, 2), cf * CFrame.new(len / 4, 3.95, 0), rgb(200, 206, 210), METAL)
		c.solid(c.P(V(4, 9, 3.2), cf * CFrame.new(len / 2 + 2.4, 4.5, 0), rgb(236, 238, 240), METAL))
		c.P(V(0.3, 3, 0.4), cf * CFrame.new(len / 2 + 0.9, 5.4, 1.7), rgb(150, 156, 160), METAL)
		c.spot(cf * CFrame.new(len / 2 + 2.4, 0, 4), "THE FRIDGE", "anything good in there?", "SNACK", "bag", { emote = "cheer", lines = { "leftover noodles. score.", "one (1) suspicious yoghurt", "you made a tiny sandwich", "just checking. again." } })
	end
	function F.wardrobe(c, cf)
		c.solid(c.P(V(8, 11, 3), cf * CFrame.new(0, 5.5, 0), rgb(176, 136, 100), WOODM))
		c.P(V(0.2, 10, 0.2), cf * CFrame.new(0, 5.5, 1.6), Cc.ink)
		for _, sx in { -0.8, 0.8 } do fblob(c, V(0.5, 0.5, 0.5), cf * CFrame.new(sx, 5.4, 1.7), Cc.gold, METAL) end
		c.spot(cf * CFrame.new(0, 0, 4.4), "WARDROBE", "everything you own", "DRESS UP", "shirt", { ui = "outfits" })
	end
	function F.plant(c, cf, s)
		s = s or 1
		fcyl(c, 2.2 * s, 2.2 * s, cf * CFrame.new(0, 1.1 * s, 0), rgb(226, 150, 118))
		fblob(c, V(4, 5, 4) * s, cf * CFrame.new(0, 4.4 * s, 0), Cc.leaf)
		fblob(c, V(3, 3.4, 3) * s, cf * CFrame.new(0.8 * s, 6 * s, 0.4 * s), Cc.leaf3)
	end
	function F.lamp(c, cf)
		fcyl(c, 0.3, 8, cf * CFrame.new(0, 4, 0), Cc.ink, METAL)
		fcyl(c, 1.8, 0.4, cf * CFrame.new(0, 0.2, 0), Cc.ink, METAL)
		fblob(c, V(3, 2.4, 3), cf * CFrame.new(0, 8.4, 0), rgb(255, 236, 200), NEON, { noShadow = true })
	end
	function F.shelf(c, cf)
		c.solid(c.P(V(10, 10, 2), cf * CFrame.new(0, 5, 0), rgb(176, 136, 100), WOODM))
		for row = 0, 2 do
			for k = 0, 3 do c.P(V(1.8, 2.2, 1.4), cf * CFrame.new(-3.4 + k * 2.2, 2 + row * 3, 0.5), K.FLOWER_COLS[(row + k) % 5 + 1]) end
		end
	end
	function F.desk(c, cf)
		c.P(V(9, 0.5, 4), cf * CFrame.new(0, 3.4, 0), rgb(236, 226, 206), WOODM)
		for _, sx in { -4, 4 } do c.P(V(0.5, 3.2, 3.6), cf * CFrame.new(sx, 1.6, 0), Cc.ink, METAL) end
		c.P(V(4.6, 2.8, 0.3), cf * CFrame.new(0, 5.4, -1), Cc.ink, SMOOTH)
		c.P(V(4.2, 2.4, 0.1), cf * CFrame.new(0, 5.4, -0.82), rgb(150, 210, 240), NEON, { noShadow = true })
		fcyl(c, 2.4, 0.5, cf * CFrame.new(0, 2.2, 3.4), rgb(96, 140, 196), SMOOTH)
		fcyl(c, 0.5, 2, cf * CFrame.new(0, 1, 3.4), Cc.ink, METAL)
	end
	function F.tub(c, cf)
		c.solid(c.P(V(7, 3, 12), cf * CFrame.new(0, 1.5, 0), rgb(250, 250, 250), SMOOTH))
		c.P(V(5.6, 0.4, 10.6), cf * CFrame.new(0, 2.9, 0), rgb(150, 210, 236), SMOOTH, { transparency = 0.2 })
		for k = 0, 3 do fblob(c, V(1.6, 1.4, 1.6), cf * CFrame.new(-1.5 + k, 3.3, -3 + k * 1.4), rgb(255, 255, 255)) end
		c.spot(cf * CFrame.new(5.4, 0, 0), "THE TUB", "bubbles", "SOAK", "heart", { sit = cf * CFrame.new(0, 2.6, 1), lines = { "aaaaah.", "prune fingers achieved", "the bubbles approve" } })
	end
	function F.piano(c, cf)
		c.solid(c.P(V(11, 4.6, 6), cf * CFrame.new(0, 2.3, 0), Cc.ink, SMOOTH))
		c.P(V(10, 0.4, 1.8), cf * CFrame.new(0, 3.3, -3.4), rgb(250, 250, 244), SMOOTH)
		c.P(V(11, 0.4, 7), cf * CFrame.new(0, 7, 1) * CFrame.Angles(0.5, 0, 0), Cc.ink, SMOOTH)
		c.spot(cf * CFrame.new(0, 0, -6), "THE PIANO", "you have a piano now", "PLAY", "star", { tune = true })
	end
	function F.wallX(c, cf, len, h, wall) c.solid(c.P(V(len, h, 0.8), cf * CFrame.new(0, h / 2, 0), wall)) end
	function F.wallZ(c, cf, len, h, wall) c.solid(c.P(V(0.8, h, len), cf * CFrame.new(0, h / 2, 0), wall)) end

	-------------------------------------------------------------------- SHOP --
	-- The pieces a shop, cafe or counter-service room is made of. Every one
	-- takes its main dimension so the same builder fits a 30-stud room and a
	-- 56-stud one, and colour is always a parameter -- variation comes from
	-- material, colour, layout and signage, never from a second builder
	-- (.claude/rules/environment.md).

	-- a service counter. Returns the CFrame of the customer side, so the
	-- caller can put a queue, a till or a staff member against it.
	function F.counter(c, cf, len, col, opts)
		opts = opts or {}
		local h = opts.h or 3.6
		c.solid(c.P(V(len, h, 2.6), cf * CFrame.new(0, h / 2, 0), col, WOODM))
		c.P(V(len + 0.6, 0.4, 3.2), cf * CFrame.new(0, h + 0.2, 0), opts.top or Cc.cream, SMOOTH)
		-- a kick rail at Sminski ankle height: a counter with no base reads as
		-- a floating slab from down there
		c.P(V(len - 1, 0.5, 2.8), cf * CFrame.new(0, 0.3, 0), shade(col, 0.18), WOODM)
		return cf * CFrame.new(0, 0, -3.4)
	end
	-- a glazed display case: cakes, pastries, phones, whatever the shop sells
	function F.display(c, cf, len, col, stock)
		c.solid(c.P(V(len, 2.6, 3), cf * CFrame.new(0, 1.3, 0), col, WOODM))
		local g = c.P(V(len - 0.4, 2.6, 2.8), cf * CFrame.new(0, 4, 0), Cc.pane, K.GLASS, { transparency = 0.55, noShadow = true })
		c.P(V(len, 0.4, 3.2), cf * CFrame.new(0, 5.5, 0), shade(col, 0.1), WOODM)
		for _, sx in { -1, 1 } do c.P(V(0.3, 2.6, 0.3), cf * CFrame.new(sx * (len / 2 - 0.2), 4, 0), shade(col, 0.2), METAL) end
		stock = stock or K.FLOWER_COLS
		local n = math.max(2, math.floor(len / 2.6))
		for k = 0, n - 1 do
			local x = -len / 2 + 1.4 + k * (len - 2.8) / math.max(1, n - 1)
			fblob(c, V(1.6, 1, 1.6), cf * CFrame.new(x, 3.2, 0), stock[k % #stock + 1])
		end
		return g
	end
	-- one stool. `sub` lets a caller say what sitting here is for.
	function F.stool(c, cf, col, title, sub)
		fcyl(c, 0.5, 2.2, cf * CFrame.new(0, 1.1, 0), Cc.ink, METAL)
		fcyl(c, 1.4, 0.2, cf * CFrame.new(0, 0.1, 0), Cc.ink, METAL)
		c.solid(fcyl(c, 2.4, 0.6, cf * CFrame.new(0, 2.4, 0), col, SMOOTH))
		c.spot(cf * CFrame.new(0, 0, -2.4), title or "A STOOL", sub or "take the weight off", "SIT", "heart", { sit = cf * CFrame.new(0, 2.7, 0) })
		return cf * CFrame.new(0, 2.7, 0)
	end
	-- a fixed bench seat along a wall, the way a small cafe actually seats
	-- people. Faces its own -Z; put the table in front of it.
	function F.banquette(c, cf, len, col)
		c.solid(c.P(V(len, 2.2, 4), cf * CFrame.new(0, 1.1, 0), shade(col, 0.1), WOODM))
		c.P(V(len - 0.4, 0.6, 3.6), cf * CFrame.new(0, 2.4, 0), col, FABRIC)
		c.P(V(len, 4.4, 0.9), cf * CFrame.new(0, 4.4, 1.8), col, FABRIC)
		local n = math.max(1, math.floor(len / 7))
		for k = 0, n - 1 do
			local x = -len / 2 + len / (n * 2) + k * len / n
			fblob(c, V(2.2, 1.8, 1.2), cf * CFrame.new(x, 3.6, 1.1), tint(col, 0.4), FABRIC)
			c.spot(cf * CFrame.new(x, 0, -3), "THE BOOTH", "the good seat, by the window", "SIT", "heart", { sit = cf * CFrame.new(x, 2.9, -0.2) })
		end
	end
	-- a till. Sits ON a counter: pass the counter's top CFrame.
	function F.till(c, cf, acc)
		c.P(V(2.2, 1.4, 1.8), cf * CFrame.new(0, 0.7, 0), Cc.cream, SMOOTH)
		c.P(V(1.8, 1.2, 0.3), cf * CFrame.new(0, 1.7, -0.6) * CFrame.Angles(-0.35, 0, 0), Cc.ink, SMOOTH)
		c.P(V(1.5, 0.9, 0.1), cf * CFrame.new(0, 1.75, -0.78) * CFrame.Angles(-0.35, 0, 0), tint(acc or Cc.mint, 0.4), NEON, { noShadow = true })
		c.P(V(1.6, 0.2, 1.2), cf * CFrame.new(0, 1.5, 0.4), shade(acc or Cc.sage, 0.2), SMOOTH)
	end
	-- the board behind the counter. `lines` is an array of item names.
	function F.menuboard(c, cf, w, lines, acc)
		local back = c.P(V(w, 3.6, 0.4), cf, Cc.ink)
		c.P(V(w + 0.6, 0.4, 0.7), cf * CFrame.new(0, 2, 0), shade(acc or Cc.sage, 0.15), WOODM)
		c.P(V(w + 0.6, 0.4, 0.7), cf * CFrame.new(0, -2, 0), shade(acc or Cc.sage, 0.15), WOODM)
		textOn(back, Enum.NormalId.Front, table.concat(lines or {}, "  \u{00B7}  "), Cc.cream, Vector2.new(math.floor(w * 18), 120), 0)
		return back
	end
	-- an upright glass-door fridge case: the one piece that makes a grocery,
	-- a deli or a corner shop read as itself from the doorway
	function F.fridge(c, cf, len, stock)
		c.solid(c.P(V(len, 11, 3.4), cf * CFrame.new(0, 5.5, 0), rgb(226, 230, 232), METAL))
		local g = c.P(V(len - 1, 8.6, 0.3), cf * CFrame.new(0, 5.6, -1.85), Cc.pane, K.GLASS, { transparency = 0.5, noShadow = true })
		c.P(V(len, 1.2, 3.6), cf * CFrame.new(0, 10.8, 0), rgb(200, 206, 210), METAL)
		local strip = c.P(V(len - 1.4, 0.3, 0.5), cf * CFrame.new(0, 10, -1.6), rgb(226, 246, 255), NEON, { noShadow = true })
		stock = stock or { rgb(240, 170, 190), Cc.butter, rgb(150, 210, 236), Cc.mint }
		for row = 0, 2 do
			c.P(V(len - 1.2, 0.2, 2.6), cf * CFrame.new(0, 2 + row * 2.8, -0.2), rgb(200, 206, 210), METAL)
			for k = 0, math.max(1, math.floor(len / 3)) - 1 do
				c.P(V(1.6, 2, 1.2), cf * CFrame.new(-len / 2 + 1.4 + k * 3, 3.1 + row * 2.8, -0.5), stock[(row + k) % #stock + 1])
			end
		end
		return g, strip
	end
	-- a stocked shelving unit. `seed` shifts the stock colours so two units in
	-- the same room do not read as a copy-paste.
	function F.shelving(c, cf, len, stock, seed)
		seed = seed or 0
		c.solid(c.P(V(len, 9.4, 1.4), cf * CFrame.new(0, 4.7, 0), rgb(176, 136, 100), WOODM))
		stock = stock or K.FLOWER_COLS
		for row = 0, 2 do
			c.P(V(len, 0.3, 2), cf * CFrame.new(0, 2.4 + row * 2.6, -0.5), rgb(196, 156, 116), WOODM)
			for k = 0, 2 do
				c.P(V(len / 3 - 0.8, 1.7, 1.2), cf * CFrame.new(-len / 3 + k * len / 3, 3.4 + row * 2.6, -0.7), stock[(row + k + seed) % #stock + 1])
			end
		end
	end
	-- a wall mirror. Doubles the apparent size of a small room, which is the
	-- whole reason a barber or a fitting room has one.
	function F.mirror(c, cf, w, h)
		c.P(V(w + 0.8, (h or 7) + 0.8, 0.3), cf, Cc.cream, WOODM)
		c.P(V(w, h or 7, 0.25), cf * CFrame.new(0, 0, -0.2), rgb(214, 232, 240), SMOOTH, { reflect = 0.4, noShadow = true })
	end
	-- a clothes rail, hung with the shop's own colours
	function F.rack(c, cf, cols)
		for _, sx in { -3, 3 } do fcyl(c, 0.3, 5.6, cf * CFrame.new(sx, 2.8, 0), Cc.ink, METAL) end
		c.P(V(6.4, 0.3, 0.3), cf * CFrame.new(0, 5.5, 0), Cc.ink, METAL)
		cols = cols or K.FLOWER_COLS
		for k = 0, 4 do
			c.P(V(0.9, 3.2, 2.2), cf * CFrame.new(-2.4 + k * 1.2, 3.7, 0), cols[k % #cols + 1], FABRIC)
		end
	end
	-- an A-frame pavement sign. Chalk text on both faces, so it reads walking
	-- either way down the street.
	function F.signboard(c, cf, text, col)
		for _, s in { -1, 1 } do
			local leaf = c.P(V(5, 6.4, 0.4), cf * CFrame.new(0, 3.4, s * 0.9) * CFrame.Angles(s * 0.18, 0, 0), col or Cc.ink, WOODM)
			textOn(leaf, s > 0 and Enum.NormalId.Back or Enum.NormalId.Front, text or "OPEN", Cc.cream, Vector2.new(260, 330), 0)
		end
		c.P(V(5.2, 0.4, 2.6), cf * CFrame.new(0, 0.2, 0), shade(col or Cc.ink, 0.2), WOODM)
	end
	-- a pendant lamp on a flex. `y` is the ceiling height: it hangs from there
	-- down, so one call works in a 14-stud room and a 26-stud loft.
	function F.pendant(c, cf, y, col)
		local drop = math.max(1.5, (y or 14) - 9)
		fcyl(c, 0.2, drop, cf * CFrame.new(0, (y or 14) - drop / 2, 0), Cc.ink, METAL)
		c.P(V(3.4, 1.8, 3.4), cf * CFrame.new(0, (y or 14) - drop - 0.9, 0), col or Cc.cream, SMOOTH, { mesh = Enum.MeshType.Sphere })
		local bulb = fball(c, 1.2, cf * CFrame.new(0, (y or 14) - drop - 1.6, 0), rgb(255, 236, 200), NEON, { noShadow = true })
		-- no PointLight here on purpose: a room gets ONE light (performance.md),
		-- and the caller owns it
		return bulb
	end
	-- a wall clock. Small, cheap, and the single best "somebody works here"
	-- detail there is.
	function F.clock(c, cf, acc)
		fcyl(c, 4.2, 0.4, cf * CFrame.Angles(math.pi / 2, 0, 0), shade(acc or Cc.ink, 0.1), WOODM)
		local face = fcyl(c, 3.6, 0.2, cf * CFrame.new(0, 0, -0.25) * CFrame.Angles(math.pi / 2, 0, 0), Cc.cream, SMOOTH)
		c.P(V(0.18, 1.4, 0.1), cf * CFrame.new(0, 0.6, -0.4), Cc.ink, SMOOTH, { noShadow = true })
		c.P(V(1, 0.18, 0.1), cf * CFrame.new(0.4, 0, -0.4) * CFrame.Angles(0, 0, 0.4), Cc.ink, SMOOTH, { noShadow = true })
		return face
	end

	------------------------------------------------------- TRADE SILHOUETTES --
	-- Everything above this line dresses a generic room. These six change its
	-- SILHOUETTE, which is the only thing that makes a laundry read as a
	-- laundry from the doorway: recolouring a shelving unit green does not
	-- make it a greengrocer, and that is precisely why 55 rooms all read as
	-- the same room (docs/WORLD_REVAMP.md §4.2). One piece per trade, sized
	-- from its main dimension like the rest of the kit.

	-- a bank of front-loading machines. `n` is how many; they tile at 5 studs,
	-- so the caller passes a count, not a length, and never has to do the sum.
	function F.machines(c, cf, n, col)
		n = math.max(1, n or 3)
		col = col or rgb(226, 230, 232)
		for k = 0, n - 1 do
			local x = -(n - 1) * 2.5 + k * 5
			c.solid(c.P(V(4.6, 7, 4.2), cf * CFrame.new(x, 3.5, 0), col, METAL))
			c.P(V(4.8, 0.4, 4.4), cf * CFrame.new(x, 7.2, 0), shade(col, 0.12), METAL)
			-- the porthole, dark so it reads as a hole rather than a sticker
			fcyl(c, 2.8, 0.5, cf * CFrame.new(x, 3.6, -2.2) * CFrame.Angles(math.pi / 2, 0, 0), shade(col, 0.25), METAL)
			fcyl(c, 2.1, 0.3, cf * CFrame.new(x, 3.6, -2.45) * CFrame.Angles(math.pi / 2, 0, 0), rgb(120, 150, 170), K.GLASS, { transparency = 0.35, noShadow = true })
			c.P(V(3.4, 0.7, 0.3), cf * CFrame.new(x, 6.2, -2.2), Cc.cream, SMOOTH)
			for _, sx in { -1, 1 } do
				c.P(V(0.5, 0.5, 0.3), cf * CFrame.new(x + sx * 1.2, 6.2, -2.4), sx > 0 and Cc.mint or Cc.red, NEON, { noShadow = true })
			end
		end
	end
	-- a pegboard hung with tools. Hardware, bike shop, anywhere with a bench.
	function F.pegboard(c, cf, w, acc)
		w = w or 12
		c.P(V(w, 8, 0.4), cf * CFrame.new(0, 4, 0), rgb(214, 186, 150), WOODM)
		c.P(V(w + 0.6, 0.5, 0.8), cf * CFrame.new(0, 8.3, 0), shade(acc or Cc.sage, 0.15), WOODM)
		local n = math.max(3, math.floor(w / 2.4))
		for k = 0, n - 1 do
			local x = -w / 2 + w / (n * 2) + k * w / n
			local kind = k % 3
			if kind == 0 then -- a hammer
				c.P(V(0.3, 3.4, 0.3), cf * CFrame.new(x, 4.6, -0.5), rgb(196, 150, 104), WOODM, { noShadow = true })
				c.P(V(1.6, 0.9, 0.7), cf * CFrame.new(x, 6.3, -0.5), rgb(150, 156, 170), METAL, { noShadow = true })
			elseif kind == 1 then -- a saw
				c.P(V(0.9, 3.6, 0.25), cf * CFrame.new(x, 5.6, -0.4), rgb(200, 206, 212), METAL, { noShadow = true })
				c.P(V(1.2, 1.2, 0.5), cf * CFrame.new(x, 3.4, -0.4), acc or Cc.sage, SMOOTH, { noShadow = true })
			else -- a coil of something
				fcyl(c, 2.4, 0.5, cf * CFrame.new(x, 5.4, -0.55) * CFrame.Angles(math.pi / 2, 0, 0), Cc.ink, SMOOTH, { noShadow = true })
				fcyl(c, 1.2, 0.6, cf * CFrame.new(x, 5.4, -0.6) * CFrame.Angles(math.pi / 2, 0, 0), acc or Cc.sage, SMOOTH, { noShadow = true })
			end
		end
	end
	-- open market bins on a slope: fruit, veg, bread, whatever is in `cols`.
	-- The slope is the point -- a flat tray reads as a table from Sminski eye
	-- level, which is below the rim.
	function F.bins(c, cf, len, cols)
		cols = cols or K.FLOWER_COLS
		c.solid(c.P(V(len, 2.6, 5.4), cf * CFrame.new(0, 1.3, 0), rgb(176, 136, 100), WOODM))
		local n = math.max(2, math.floor(len / 6))
		for k = 0, n - 1 do
			local x = -len / 2 + len / (n * 2) + k * len / n
			local bw = len / n - 0.8
			c.P(V(bw, 0.5, 5.6), cf * CFrame.new(x, 3.2, 0) * CFrame.Angles(0.35, 0, 0), shade(cols[k % #cols + 1], 0.25), WOODM)
			c.P(V(bw, 1.6, 0.4), cf * CFrame.new(x, 3.2, -2.7), rgb(196, 156, 116), WOODM)
			for q = 0, 5 do
				fball(c, 1.3, cf * CFrame.new(x - bw / 2 + 1 + (q % 3) * (bw - 2) / 2, 3.9 + math.floor(q / 3) * 0.5, -1.4 + math.floor(q / 3) * 1.4), cols[(k + q) % #cols + 1])
			end
		end
	end
	-- a browsing bin you flick through: records, prints, seed packets, comics.
	-- Upright cards in a low box, so the room has something at knee height.
	function F.bin(c, cf, len, cols)
		cols = cols or K.FLOWER_COLS
		c.solid(c.P(V(len, 3.4, 5), cf * CFrame.new(0, 1.7, 0), rgb(196, 156, 116), WOODM))
		c.P(V(len + 0.5, 0.4, 5.4), cf * CFrame.new(0, 3.6, 0), shade(Cc.ink, 0.05), WOODM)
		local n = math.max(6, math.floor(len * 1.4))
		for k = 0, n - 1 do
			c.P(V(0.35, 3.2, 3.2), cf * CFrame.new(-len / 2 + 1 + k * (len - 2) / (n - 1), 5.2, 0) * CFrame.Angles(-0.12, 0, 0), cols[k % #cols + 1], SMOOTH, { noShadow = true })
		end
	end
	-- an easel with a half-finished canvas on it. Art shop, photo studio.
	function F.easel(c, cf, col)
		for _, sx in { -1.6, 1.6 } do c.P(V(0.4, 8, 0.4), cf * CFrame.new(sx, 4, 0.6) * CFrame.Angles(0.14, 0, 0), rgb(196, 150, 104), WOODM) end
		c.P(V(0.4, 8, 0.4), cf * CFrame.new(0, 4, -1.4) * CFrame.Angles(-0.3, 0, 0), rgb(196, 150, 104), WOODM)
		c.P(V(4.4, 0.4, 0.6), cf * CFrame.new(0, 3.4, 0.4), rgb(176, 136, 100), WOODM)
		c.P(V(6, 6.4, 0.3), cf * CFrame.new(0, 6.6, 0.3) * CFrame.Angles(0.14, 0, 0), Cc.cream, SMOOTH)
		c.P(V(4, 3, 0.15), cf * CFrame.new(0, 7.2, 0.14) * CFrame.Angles(0.14, 0, 0), col or Cc.sage, SMOOTH, { noShadow = true })
		c.P(V(2.2, 1.6, 0.15), cf * CFrame.new(-0.8, 5.6, 0.12) * CFrame.Angles(0.14, 0, 0), tint(col or Cc.sage, 0.4), SMOOTH, { noShadow = true })
	end
	-- a stack of crates. The cheapest "this place has a back room" there is,
	-- and it breaks up a bare corner without costing an interaction.
	function F.crates(c, cf, col, n)
		n = math.max(1, n or 3)
		col = col or rgb(214, 170, 120)
		for k = 0, n - 1 do
			local s = 3.4 - (k % 2) * 0.4
			c.solid(c.P(V(s, 2.6, s), cf * CFrame.new((k % 2) * 0.6 - 0.3, 1.3 + k * 2.6, (k % 3) * 0.4 - 0.4), col, WOODM))
			c.P(V(s + 0.15, 0.4, s + 0.15), cf * CFrame.new((k % 2) * 0.6 - 0.3, 2.5 + k * 2.6, (k % 3) * 0.4 - 0.4), shade(col, 0.15), WOODM)
		end
	end

	return K
end
