-- HubSets (client): the miniature dioramas on the lobby table.
-- House rules, so everything reads as hand-built rather than stamped out:
--   * built from boards (floor slab, walls, lintel, posts); painted panels sit
--     INSIDE the frame, never flush with another face (no flicker)
--   * matte paint (Plaster) and wood; Neon only for small bulbs and signs
--   * one soft lamp per set; signs glow on their own and cast nothing
--   * figures stand on the floor of the set, props are sized to the figures

return function(K)
	local part, solid, light, sign, deco = K.part, K.solid, K.light, K.sign, K.deco
	local World, Models, Config, UI, C = K.World, K.Models, K.Config, K.UI, K.C
	local HUB, BOOK_COLS, WARM = K.HUB, K.BOOK_COLS, K.WARM
	local entranceParts = K.entranceParts
	local function V(x, y, z) return Vector3.new(x, y, z) end

	local MATTE = Enum.Material.Plaster
	local WOODM = Enum.Material.Wood
	local NEON = Enum.Material.Neon
	local BIRCH = Color3.fromRGB(206, 168, 124)
	local WALNUT = Color3.fromRGB(112, 74, 50)
	local CREAM = Color3.fromRGB(250, 244, 232)
	local INK = Color3.fromRGB(52, 44, 60)
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local function shade(c, k) return c:Lerp(Color3.new(0, 0, 0), k) end
	local function tint(c, k) return c:Lerp(Color3.new(1, 1, 1), k) end

	local function P(size, cf, color, mat, opts)
		return part(K.folder(), size, cf, color, mat or MATTE, opts)
	end
	-- cylinder whose axis is the frame's Y
	local function cyl(dia, len, cf, color, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Cylinder
		return P(V(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, opts)
	end
	local function ball(d, cf, color, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Ball
		return P(V(d, d, d), cf, color, mat, opts)
	end
	local function blob(size, cf, color, mat, opts)
		opts = opts or {}
		opts.mesh = Enum.MeshType.Sphere
		return P(size, cf, color, mat, opts)
	end
	local function frameOf(e)
		local pos = HUB + e.pos
		return CFrame.lookAt(pos, pos + V(math.sin(e.face), 0, math.cos(e.face))) -- local -Z = the open front
	end
	local function textOn(p, face, str, color, canvas, opts)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.CanvasSize = canvas or Vector2.new(400, 80)
		sg.LightInfluence = opts and opts.lit or 0.85
		sg.Brightness = opts and opts.bright or 1
		UI.text(sg, str, { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = color, stroke = 0 })
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.06, 0), UDim.new(0.06, 0)
		pad.Parent = sg:FindFirstChildWhichIsA("TextLabel")
		sg.Parent = p
		return sg
	end

	---------------------------------------------------------------------------
	-- KIT
	---------------------------------------------------------------------------
	local FLOOR_Y = 1.6

	-- open-front box built from boards. o: wall, floor, floorMat, frame, title
	local function shell(e, w, d, h, o)
		local cf = frameOf(e)
		local fr = o.frame or BIRCH
		solid(P(V(w + 3.4, 1.2, d + 3.4), cf * CFrame.new(0, 0.6, 0), WALNUT, WOODM)) -- plinth
		P(V(w, 0.4, d), cf * CFrame.new(0, 1.4, 0), o.floor or rgb(196, 160, 120), o.floorMat or Enum.Material.WoodPlanks)
		-- back wall: board + inset painted panel + baseboard + picture rail
		solid(P(V(w + 2.4, h, 1.2), cf * CFrame.new(0, h / 2 + 1.2, d / 2 + 0.6), fr, WOODM))
		P(V(w, h - 0.4, 0.4), cf * CFrame.new(0, h / 2 + 1.4, d / 2 - 0.2), o.wall)
		P(V(w, 1.6, 0.5), cf * CFrame.new(0, FLOOR_Y + 0.8, d / 2 - 0.65), CREAM)
		P(V(w, 0.7, 0.5), cf * CFrame.new(0, h - 1.2, d / 2 - 0.65), CREAM)
		for _, sx in { -1, 1 } do
			solid(P(V(1.2, h, d + 1.2), cf * CFrame.new(sx * (w / 2 + 0.6), h / 2 + 1.2, 0), fr, WOODM))
			P(V(0.4, h - 0.4, d), cf * CFrame.new(sx * (w / 2 - 0.2), h / 2 + 1.4, 0), shade(o.wall, 0.07))
			P(V(0.5, 1.6, d), cf * CFrame.new(sx * (w / 2 - 0.65), FLOOR_Y + 0.8, 0), CREAM)
			-- front posts with a little base block
			P(V(1.6, h, 1.6), cf * CFrame.new(sx * (w / 2 + 0.6), h / 2 + 1.2, -d / 2 - 0.2), fr, WOODM)
			P(V(2.4, 1.4, 2.4), cf * CFrame.new(sx * (w / 2 + 0.6), 1.9, -d / 2 - 0.2), shade(fr, 0.12), WOODM)
		end
		solid(P(V(w + 3.4, 1.2, d + 3.4), cf * CFrame.new(0, h + 1.8, 0), fr, WOODM)) -- lid
		-- lintel with a painted name plaque
		P(V(w + 2.4, 3, 1.4), cf * CFrame.new(0, h - 0.3, -d / 2 - 0.3), fr, WOODM)
		if o.title then
			local plq = P(V(math.min(w - 6, #o.title * 1.5 + 4), 2.1, 0.3), cf * CFrame.new(0, h - 0.3, -d / 2 - 1.15), o.plaque or rgb(70, 58, 84))
			textOn(plq, Enum.NormalId.Front, o.title, CREAM, Vector2.new(520, 70))
		end
		-- one hanging lamp
		cyl(0.25, 3, cf * CFrame.new(0, h - 0.4, 0), INK)
		cyl(4.2, 1.6, cf * CFrame.new(0, h - 2.6, 0), o.lamp or CREAM)
		local bulb = ball(1.6, cf * CFrame.new(0, h - 3.5, 0), rgb(255, 232, 190), NEON, { noShadow = true })
		light(bulb, math.max(w, d) * 0.95, o.lampPower or 0.8, WARM)
		return cf
	end

	-- gable roof with overhang, fascia, ridge cap and clapboard gable ends
	local function gableRoof(cf, w, d, y, rise, color)
		local a = w / 2 + 3
		local L = math.sqrt(a * a + rise * rise) + 0.6
		local th = math.atan2(rise, a)
		for _, sx in { -1, 1 } do
			local slab = cf * CFrame.new(sx * a / 2, y + rise / 2 + 0.4, 0) * CFrame.Angles(0, 0, -sx * th)
			solid(P(V(L, 1.1, d + 6), slab, color))
			-- shingle courses
			for k = 0, 3 do
				P(V(L / 4 - 0.2, 0.5, d + 6.4), slab * CFrame.new(-sx * (L / 2 - L / 8 - k * L / 4) * 1, 0.7, 0), k % 2 == 0 and shade(color, 0.08) or tint(color, 0.06))
			end
			P(V(L, 1.4, 0.6), slab * CFrame.new(0, -0.3, -(d + 6) / 2 - 0.3), CREAM) -- fascia
			P(V(L, 1.4, 0.6), slab * CFrame.new(0, -0.3, (d + 6) / 2 + 0.3), CREAM)
		end
		cyl(1.4, d + 7, cf * CFrame.new(0, y + rise + 0.9, 0) * CFrame.Angles(math.pi / 2, 0, 0), shade(color, 0.15))
		-- gable ends: two wedges make a clean triangle, trimmed along the eaves
		for _, z in { -d / 2 - 0.2, d / 2 + 0.2 } do
			for _, sx in { -1, 1 } do
				P(V(0.8, rise, w / 2), cf * CFrame.new(sx * w / 4, y + rise / 2, z) * CFrame.Angles(0, -sx * math.pi / 2, 0), CREAM, MATTE, { class = "WedgePart" })
			end
			P(V(w, 0.6, 1), cf * CFrame.new(0, y + 0.3, z), shade(CREAM, 0.12))
		end
		-- a round attic vent in the front gable
		local vz = -d / 2 - 0.75
		cyl(3.4, 0.4, cf * CFrame.new(0, y + rise * 0.42, vz) * CFrame.Angles(math.pi / 2, 0, 0), shade(CREAM, 0.1))
		local vent = cyl(2.5, 0.45, cf * CFrame.new(0, y + rise * 0.42, vz - 0.05) * CFrame.Angles(math.pi / 2, 0, 0), rgb(255, 226, 170), NEON, { noShadow = true })
		vent.Transparency = 0.25
		P(V(2.5, 0.25, 0.5), cf * CFrame.new(0, y + rise * 0.42, vz - 0.3), CREAM)
		P(V(0.25, 2.5, 0.5), cf * CFrame.new(0, y + rise * 0.42, vz - 0.3), CREAM)
	end

	-- framed window with muntins, a sill and a softly glowing pane
	local function window(cf, w, h, glow, curtains)
		P(V(w + 1.6, h + 1.6, 0.5), cf, CREAM)
		local pane = P(V(w, h, 0.3), cf * CFrame.new(0, 0, -0.3), glow, NEON, { noShadow = true })
		pane.Transparency = 0.15
		P(V(0.5, h, 0.3), cf * CFrame.new(0, 0, -0.5), CREAM)
		P(V(w, 0.5, 0.3), cf * CFrame.new(0, 0, -0.5), CREAM)
		P(V(w + 3, 0.7, 1.6), cf * CFrame.new(0, -h / 2 - 1, -0.7), CREAM)
		if curtains then
			for _, sx in { -1, 1 } do
				P(V(w * 0.28, h + 1.2, 0.5), cf * CFrame.new(sx * (w / 2 + 0.2), -0.2, -0.8), curtains, Enum.Material.Fabric)
			end
			cyl(0.4, w + 4, cf * CFrame.new(0, h / 2 + 1.1, -0.8) * CFrame.Angles(0, 0, math.pi / 2), WALNUT, WOODM)
		end
		return pane
	end

	local function rug(cf, dia, color, inner)
		cyl(dia, 0.25, cf * CFrame.new(0, FLOOR_Y + 0.12, 0), color, Enum.Material.Fabric, { noShadow = true })
		cyl(dia * 0.72, 0.27, cf * CFrame.new(0, FLOOR_Y + 0.14, 0), inner or tint(color, 0.35), Enum.Material.Fabric, { noShadow = true })
	end

	-- a small potted plant; h = leaf height
	local function plant(cf, s)
		s = s or 1
		cyl(3.2 * s, 2.6 * s, cf * CFrame.new(0, 1.3 * s, 0), rgb(214, 130, 96))
		cyl(3.6 * s, 0.5 * s, cf * CFrame.new(0, 2.7 * s, 0), rgb(196, 112, 82))
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			blob(V(1.5 * s, 4.6 * s, 1.5 * s), cf * CFrame.new(math.cos(a) * 0.9 * s, 4.6 * s, math.sin(a) * 0.9 * s) * CFrame.Angles(math.sin(a) * 0.45, 0, -math.cos(a) * 0.45), k % 2 == 0 and rgb(104, 170, 96) or rgb(128, 190, 110))
		end
	end

	-- books standing on a shelf, spines to the front (x along the shelf)
	local function books(cf, length, height, depth, seed)
		local x, i = -length / 2, seed or 0
		while x < length / 2 - 0.7 do
			i += 1
			local bw = 0.7 + ((i * 37) % 5) * 0.2
			local bh = height * (0.72 + ((i * 53) % 4) * 0.08)
			local lean = (i % 11 == 0) and 0.18 or 0
			P(V(bw, bh, depth), cf * CFrame.new(x + bw / 2, bh / 2, 0) * CFrame.Angles(0, 0, lean), BOOK_COLS[i % #BOOK_COLS + 1])
			x += bw + 0.06 + (lean > 0 and 0.5 or 0)
		end
	end

	-- a bookcase built like the cubbies: back, sides, shelves, books set inside
	local function bookcase(cf, w, h, d, shelves, wood)
		wood = wood or rgb(150, 104, 70)
		P(V(w, h, 0.6), cf * CFrame.new(0, h / 2, d / 2 - 0.3), shade(wood, 0.25), WOODM)
		for _, sx in { -1, 1 } do P(V(0.9, h, d), cf * CFrame.new(sx * (w / 2 - 0.45), h / 2, 0), wood, WOODM) end
		local gap = (h - 0.9) / shelves
		for s = 0, shelves do
			P(V(w - 1.8, 0.9, d), cf * CFrame.new(0, 0.45 + s * gap, 0), wood, WOODM)
			if s < shelves then books(cf * CFrame.new(0, 0.9 + s * gap, -0.2), w - 2.6, gap - 1.6, d - 1.6, s * 7) end
		end
		P(V(w + 0.8, 0.9, d + 0.6), cf * CFrame.new(0, h + 0.45, -0.1), shade(wood, 0.1), WOODM)
	end

	local function door(e, cf, w, h, d)
		local p = P(V(w, h, 0.4), cf * CFrame.new(0, FLOOR_Y + h / 2, -d / 2 + 0.4), Color3.new(), MATTE, { transparency = 1 })
		entranceParts[e.id] = p
		return p
	end
	local function banner(e, cf, y, iconName)
		local anchor = P(V(1, 1, 1), cf * CFrame.new(0, y, 0), Color3.new(), MATTE, { transparency = 1 })
		sign(K.folder(), anchor, e.title, e.sub, e.color, iconName, 6)
	end

	---------------------------------------------------------------------------
	-- ENDLESS RUN HUTS
	---------------------------------------------------------------------------
	local HW, HD, HH = 34, 26, 24
	local function hutShell(e, o, roofCol)
		local cf = shell(e, HW, HD, HH, o)
		gableRoof(cf, HW + 2.4, HD, HH + 2.4, 10, roofCol)
		-- chimney with a cap, a doormat and a flower box under the side window
		P(V(3.6, 9, 3.6), cf * CFrame.new(HW / 2 - 7, HH + 9, 5), rgb(178, 96, 78), Enum.Material.Brick)
		P(V(4.6, 0.9, 4.6), cf * CFrame.new(HW / 2 - 7, HH + 13.9, 5), CREAM)
		P(V(11, 0.3, 4.6), cf * CFrame.new(0, FLOOR_Y + 0.15, -HD / 2 + 2.6), rgb(186, 140, 96), Enum.Material.Fabric, { noShadow = true })
		local g = P(V(12, 17, 0.5), cf * CFrame.new(0, FLOOR_Y + 8.5, -HD / 2 + 0.4), e.color, MATTE, { transparency = 1 })
		entranceParts[e.id] = g
		local mapDef = Config.Map(e.map)
		local owned = not K.ctx.data or not K.ctx.data.OwnedMaps or K.ctx.data.OwnedMaps[e.map]
		local sub = e.sub
		if mapDef and not owned then
			sub = "LOCKED  ·  " .. UI.fmt(mapDef.price or 0) .. " coins"
			P(V(5, 4, 1.4), cf * CFrame.new(0, 13, -HD / 2 - 1.4), rgb(240, 196, 84), Enum.Material.Metal)
			cyl(4, 1, cf * CFrame.new(0, 16.2, -HD / 2 - 1.4) * CFrame.Angles(math.pi / 2, 0, 0), rgb(200, 200, 210), Enum.Material.Metal)
		end
		local anchor = P(V(1, 1, 1), cf * CFrame.new(0, HH + 15, 0), Color3.new(), MATTE, { transparency = 1 })
		sign(K.folder(), anchor, e.title, sub, e.color, owned and "house" or "lock", 6)
		return cf
	end

	local function buildBigHouse(e)
		local cf = hutShell(e, { wall = rgb(92, 84, 150), floor = rgb(188, 148, 108), title = "THE BIG HOUSE", lampPower = 0.65 }, rgb(118, 96, 196))
		for _, x in { -10, 10 } do
			window(cf * CFrame.new(x, 13, HD / 2 - 0.7), 7, 8, rgb(255, 206, 124), rgb(150, 120, 200))
		end
		blob(V(3.6, 3.6, 0.5), cf * CFrame.new(0, 19.5, HD / 2 - 0.7), rgb(255, 240, 190), NEON, { noShadow = true })
		rug(cf * CFrame.new(0, 0, -2), 17, rgb(224, 150, 170))
		if not World.placeAsset(K.folder(), "Sofa", cf * CFrame.new(-8.5, FLOOR_Y + 2.4, 5) * CFrame.Angles(0, -math.pi / 2, 0), V(5.2, 4.8, 13)) then
			P(V(13, 3, 5), cf * CFrame.new(-8.5, FLOOR_Y + 1.5, 5), rgb(150, 125, 210), Enum.Material.Fabric)
		end
		-- TV on a low console, a floor lamp, a toy block left on the rug
		P(V(11, 2.6, 4), cf * CFrame.new(9, FLOOR_Y + 1.3, 8), WALNUT, WOODM)
		P(V(9.4, 5.6, 0.7), cf * CFrame.new(9, FLOOR_Y + 5.6, 8), INK)
		local scr = P(V(8.6, 4.8, 0.3), cf * CFrame.new(9, FLOOR_Y + 5.6, 7.55), rgb(130, 196, 255), NEON, { noShadow = true })
		scr.Transparency = 0.1
		cyl(0.4, 11, cf * CFrame.new(14.5, FLOOR_Y + 5.5, -6), INK)
		cyl(3.4, 2.6, cf * CFrame.new(14.5, FLOOR_Y + 11.4, -6), rgb(255, 226, 170))
		World.placeAsset(K.folder(), "ToyBlock", cf * CFrame.new(-3, FLOOR_Y + 1.5, -7) * CFrame.Angles(0, 0.5, 0), V(3, 3, 3))
		deco(K.folder(), cf * CFrame.new(-12, FLOOR_Y, -6) * CFrame.Angles(0, math.pi + 0.5, 0), "Glow", "hide")
		local kid = Models.buildKid(K.folder(), { scale = 0.34, hoodie = rgb(230, 110, 100), name = "Kid" })
		Models.poseKid(kid, cf * CFrame.new(4, FLOOR_Y, 2) * CFrame.Angles(0, math.pi + 0.45, 0), 0.3, 1, 0.6)
	end

	local function buildDollhouse(e)
		local cf = hutShell(e, { wall = rgb(198, 236, 198), floor = rgb(176, 222, 170), floorMat = MATTE, title = "SMINSKI DOLLHOUSE", lamp = rgb(214, 250, 205) }, rgb(112, 192, 108))
		-- a loft on posts with a railing, reached by a proper little staircase
		local loftY = 14
		P(V(HW - 8, 0.9, HD * 0.46), cf * CFrame.new(4, loftY, HD * 0.27), rgb(150, 205, 140), WOODM)
		for _, x in { -11.5, 19.5 } do cyl(0.8, loftY - FLOOR_Y, cf * CFrame.new(x, (loftY + FLOOR_Y) / 2, HD * 0.05), CREAM) end
		for i = 0, 8 do cyl(0.35, 3.4, cf * CFrame.new(-10.5 + i * 3.7, loftY + 2.1, HD * 0.05), CREAM) end
		P(V(HW - 8, 0.5, 0.6), cf * CFrame.new(4, loftY + 3.9, HD * 0.05), CREAM)
		for i = 0, 6 do
			P(V(5.4, 0.8, 2.2), cf * CFrame.new(-HW / 2 + 3.6, FLOOR_Y + 1 + i * 1.75, HD / 2 - 3 - i * 1.9), rgb(232, 246, 226), WOODM)
		end
		window(cf * CFrame.new(6, 8, HD / 2 - 0.7), 6, 6, rgb(200, 255, 190))
		-- floating hearts (the map's three lives)
		for _, hp in { V(-7, 9, -5), V(1, 11.5, -1), V(9, 8.5, -4) } do
			local hc = cf * CFrame.new(hp)
			P(V(2.4, 2.4, 1), hc * CFrame.Angles(0, 0, math.pi / 4), rgb(255, 128, 156), NEON, { noShadow = true })
			cyl(2.1, 1, hc * CFrame.new(-0.85, 0.85, 0) * CFrame.Angles(math.pi / 2, 0, 0), rgb(255, 128, 156), NEON, { noShadow = true })
			cyl(2.1, 1, hc * CFrame.new(0.85, 0.85, 0) * CFrame.Angles(math.pi / 2, 0, 0), rgb(255, 128, 156), NEON, { noShadow = true })
		end
		rug(cf * CFrame.new(2, 0, -4), 14, rgb(150, 205, 140))
		deco(K.folder(), cf * CFrame.new(-4, FLOOR_Y, -4) * CFrame.Angles(0, math.pi, 0), "Mint", "yoga")
		deco(K.folder(), cf * CFrame.new(8, FLOOR_Y, -2) * CFrame.Angles(0, math.pi - 0.5, 0), "Night", "cheer")
		deco(K.folder(), cf * CFrame.new(8, loftY + 0.45, 8) * CFrame.Angles(0, math.pi, 0), "Galaxy", "sit")
		World.placeAsset(K.folder(), "BookStack", cf * CFrame.new(12.5, FLOOR_Y + 3, -8) * CFrame.Angles(0, 0.3, 0), V(4, 6, 3.6))
		plant(cf * CFrame.new(-1, loftY + 0.45, 9), 0.7)
	end

	local function buildDogRun(e)
		local cf = hutShell(e, { wall = rgb(168, 214, 250), floor = rgb(120, 196, 108), floorMat = Enum.Material.Grass, title = "DOG PARK RUN", frame = CREAM, plaque = rgb(196, 84, 74) }, rgb(226, 104, 92))
		-- painted sky: sun + layered clouds on the back wall
		blob(V(5.6, 5.6, 0.5), cf * CFrame.new(-10, 18.5, HD / 2 - 0.7), rgb(255, 226, 120), NEON, { noShadow = true })
		for _, c in { { 5, 18, 7 }, { 9.5, 19.4, 5 }, { 1.5, 17.2, 4.4 } } do
			blob(V(c[3], c[3] * 0.5, 0.5), cf * CFrame.new(c[1], c[2], HD / 2 - 0.7), CREAM)
		end
		-- a stone path to the door
		for i = 0, 4 do
			blob(V(4.2 - (i % 2) * 0.8, 0.5, 3.2), cf * CFrame.new((i % 2 == 0) and -1 or 1.2, FLOOR_Y + 0.12, -HD / 2 + 3 + i * 3.4), rgb(214, 204, 186), MATTE, { noShadow = true })
		end
		-- picket fence with pointed tops along the back
		for i = 0, 9 do
			local px = -HW / 2 + 2.6 + i * 3.2
			P(V(1.1, 4.6, 0.6), cf * CFrame.new(px, FLOOR_Y + 2.3, HD / 2 - 3.4), CREAM)
			P(V(0.8, 0.8, 0.6), cf * CFrame.new(px, FLOOR_Y + 4.75, HD / 2 - 3.4) * CFrame.Angles(0, 0, math.pi / 4), CREAM)
		end
		for _, y in { 1.7, 3.5 } do P(V(HW - 4, 0.6, 0.4), cf * CFrame.new(0, FLOOR_Y + y, HD / 2 - 3), shade(CREAM, 0.06)) end
		if not World.placeAsset(K.folder(), "ParkTree", cf * CFrame.new(-11, FLOOR_Y + 8, 3), V(12, 16, 12)) then
			cyl(1.8, 8, cf * CFrame.new(-11, FLOOR_Y + 4, 3), rgb(135, 95, 70), WOODM)
			ball(9, cf * CFrame.new(-11, FLOOR_Y + 11, 3), rgb(110, 190, 95), Enum.Material.Grass)
		end
		World.placeAsset(K.folder(), "ParkBench", cf * CFrame.new(9.5, FLOOR_Y + 2.3, 6) * CFrame.Angles(0, math.pi, 0), V(10, 4.6, 3.8))
		World.placeAsset(K.folder(), "DogBowl", cf * CFrame.new(12.5, FLOOR_Y + 0.8, -5), V(3, 1.6, 3))
		ball(1.9, cf * CFrame.new(-4, FLOOR_Y + 0.95, -8), rgb(214, 236, 84), Enum.Material.Fabric)
		deco(K.folder(), cf * CFrame.new(-7, FLOOR_Y, -4) * CFrame.Angles(0, math.pi - 0.3, 0), "Lemon", "cheer")
		local dog = Models.buildDog(K.folder(), { scale = 0.14, fur = rgb(230, 185, 110), light = rgb(245, 215, 160), dark = rgb(170, 120, 70) })
		Models.poseDog(dog, cf * CFrame.new(4, FLOOR_Y, 0) * CFrame.Angles(0, math.pi + 0.3, 0), 0.4, 1, 0.5)
	end

	---------------------------------------------------------------------------
	-- RECORD SHOP (Ranked)
	---------------------------------------------------------------------------
	local function buildRecords(e)
		local w, d, h = 46, 24, 34
		local cf = shell(e, w, d, h, { wall = rgb(246, 238, 224), floor = rgb(60, 54, 70), floorMat = MATTE, title = "RECORD SHOP", frame = rgb(96, 70, 56) })
		-- checkerboard tiles
		for ix = 0, 7 do for iz = 0, 3 do
			if (ix + iz) % 2 == 0 then
				P(V(w / 8, 0.12, d / 4), cf * CFrame.new(-w / 2 + w / 16 + ix * w / 8, FLOOR_Y + 0.06, -d / 2 + d / 8 + iz * d / 4), CREAM, MATTE, { noShadow = true })
			end
		end end
		-- wall display: sleeves sitting on three picture ledges
		for row = 0, 1 do
			local y = 12 + row * 6.8
			P(V(w - 8, 0.5, 1.4), cf * CFrame.new(0, y, d / 2 - 1.1), WALNUT, WOODM)
			for col = 0, 5 do
				local rc = cf * CFrame.new(-w / 2 + 7 + col * 6.4, y + 2.95, d / 2 - 1.2) * CFrame.Angles(-0.12, 0, 0)
				local colr = BOOK_COLS[(row * 5 + col * 3) % #BOOK_COLS + 1]
				P(V(5.2, 5.2, 0.3), rc, colr)
				if (row + col) % 2 == 0 then
					-- a record peeking out of its sleeve
					cyl(4.8, 0.2, rc * CFrame.new(1.6, 0, 0.2) * CFrame.Angles(math.pi / 2, 0, 0), rgb(28, 24, 32))
					cyl(1.6, 0.24, rc * CFrame.new(1.6, 0, 0.2) * CFrame.Angles(math.pi / 2, 0, 0), tint(colr, 0.3))
				else
					blob(V(2.6, 2.6, 0.2), rc * CFrame.new(0, 0, -0.2), tint(colr, 0.45))
				end
			end
		end
		local ns = K.neonText(K.folder(), cf * CFrame.new(0, h - 5, d / 2 - 0.9), V(18, 4.4, 0.4), "RECORDS", rgb(255, 110, 140), Enum.NormalId.Front)
		-- browsing crates: open boxes of sleeves on a low bench
		P(V(30, 1, 7), cf * CFrame.new(-6, FLOOR_Y + 3, 3), WALNUT, WOODM)
		for _, x in { -19, 7 } do P(V(1, 3, 6), cf * CFrame.new(x, FLOOR_Y + 1.5, 3), WALNUT, WOODM) end
		for i = 0, 2 do
			local crate = cf * CFrame.new(-16 + i * 10, FLOOR_Y + 3.5, 3)
			P(V(8.4, 0.5, 6), crate * CFrame.new(0, 0.25, 0), BIRCH, WOODM)
			for _, sx in { -1, 1 } do P(V(0.5, 4, 6), crate * CFrame.new(sx * 3.95, 2.2, 0), BIRCH, WOODM) end
			for _, sz in { -1, 1 } do P(V(8.4, 4, 0.5), crate * CFrame.new(0, 2.2, sz * 2.75), BIRCH, WOODM) end
			for k = 0, 6 do
				P(V(7, 5, 0.22), crate * CFrame.new(0, 3, -2.1 + k * 0.7) * CFrame.Angles(-0.2, 0, 0), BOOK_COLS[(i * 7 + k) % #BOOK_COLS + 1])
			end
		end
		-- listening corner: turntable on a cabinet, two speakers, headphones Sminski
		local tt = cf * CFrame.new(16, 0, 4)
		P(V(10, 6, 7), tt * CFrame.new(0, FLOOR_Y + 3, 0), WALNUT, WOODM)
		P(V(8.4, 1, 6.2), tt * CFrame.new(0, FLOOR_Y + 6.5, 0), rgb(232, 226, 214))
		cyl(5.4, 0.3, tt * CFrame.new(-0.8, FLOOR_Y + 7.15, 0), rgb(28, 24, 32))
		cyl(1.7, 0.34, tt * CFrame.new(-0.8, FLOOR_Y + 7.17, 0), rgb(255, 110, 140))
		P(V(0.35, 0.35, 4), tt * CFrame.new(3, FLOOR_Y + 7.5, -0.3) * CFrame.Angles(0, 0.45, 0), rgb(200, 200, 210), Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			local sp = tt * CFrame.new(sx * 0, 0, 0) * CFrame.new(sx == -1 and -7.5 or 7.2, FLOOR_Y + 4, 2.5)
			if sx == -1 then sp = cf * CFrame.new(6.5, FLOOR_Y + 4, 8) else sp = cf * CFrame.new(20.5, FLOOR_Y + 10.5, 8) end
			P(V(4, 8, 3.4), sp, INK)
			cyl(2.6, 0.3, sp * CFrame.new(0, -1.4, -1.75) * CFrame.Angles(math.pi / 2, 0, 0), rgb(86, 80, 96))
			cyl(1.3, 0.3, sp * CFrame.new(0, 2.2, -1.75) * CFrame.Angles(math.pi / 2, 0, 0), rgb(86, 80, 96))
		end
		deco(K.folder(), cf * CFrame.new(8, FLOOR_Y, -4) * CFrame.Angles(0, math.pi + 0.4, 0), "Night", "cheer")
		plant(cf * CFrame.new(-w / 2 + 3.4, FLOOR_Y, -d / 2 + 3.4), 0.9)
		door(e, cf, 14, 14, d)
		banner(e, cf, h + 5, "trophy")
		return ns
	end

	---------------------------------------------------------------------------
	-- LIBRARY (Goals + stats)
	---------------------------------------------------------------------------
	local function buildLibrary(e)
		local w, d, h = 46, 26, 38
		local cf = shell(e, w, d, h, { wall = rgb(92, 128, 110), floor = rgb(176, 130, 92), title = "SMINSKI LIBRARY", frame = rgb(150, 108, 74), lampPower = 1 })
		for _, x in { -w / 2 + 8, w / 2 - 8 } do
			bookcase(cf * CFrame.new(x, FLOOR_Y, d / 2 - 3.2) * CFrame.Angles(0, math.pi, 0), 14, h - 8, 5, 5, rgb(186, 138, 96))
		end
		bookcase(cf * CFrame.new(0, FLOOR_Y, d / 2 - 3) * CFrame.Angles(0, math.pi, 0), 15, 14, 4.6, 2, rgb(186, 138, 96))
		local rl = P(V(1.4, 1.4, 1.4), cf * CFrame.new(-12, FLOOR_Y + 12, -2), Color3.new(), MATTE, { transparency = 1 })
		light(rl, 26, 0.6, WARM)
		-- a framed map over the low case, a globe on top of it
		P(V(11, 8, 0.4), cf * CFrame.new(0, 24, d / 2 - 0.7), WALNUT, WOODM)
		P(V(9.6, 6.6, 0.3), cf * CFrame.new(0, 24, d / 2 - 0.95), rgb(226, 210, 170))
		cyl(0.5, 2, cf * CFrame.new(-3.5, FLOOR_Y + 16, d / 2 - 3), rgb(180, 150, 90), Enum.Material.Metal)
		ball(4, cf * CFrame.new(-3.5, FLOOR_Y + 18.6, d / 2 - 3), rgb(110, 170, 210))
		-- rolling ladder on a rail
		cyl(0.4, 13, cf * CFrame.new(-w / 2 + 8, h - 10.5, d / 2 - 6.4) * CFrame.Angles(0, 0, math.pi / 2), rgb(180, 150, 90), Enum.Material.Metal)
		for _, x in { -2.4, 2.4 } do
			P(V(0.6, h - 11, 0.6), cf * CFrame.new(-w / 2 + 9 + x, (h - 11) / 2 + FLOOR_Y, d / 2 - 8.4) * CFrame.Angles(-0.16, 0, 0), BIRCH, WOODM)
		end
		for i = 0, 6 do
			P(V(4.8, 0.5, 0.7), cf * CFrame.new(-w / 2 + 9, FLOOR_Y + 2.5 + i * 3.4, d / 2 - 10.2 + i * 0.55), BIRCH, WOODM)
		end
		-- reading nook: wing chair, side table with a shaded lamp, a rug
		rug(cf * CFrame.new(6, 0, -3), 18, rgb(178, 96, 78), rgb(226, 200, 150))
		local ch = cf * CFrame.new(9, FLOOR_Y, -1) * CFrame.Angles(0, -0.3, 0)
		P(V(8, 3, 7), ch * CFrame.new(0, 2.2, 0), rgb(186, 64, 64), Enum.Material.Fabric)
		P(V(8, 8, 2), ch * CFrame.new(0, 6.5, 3), rgb(186, 64, 64), Enum.Material.Fabric)
		for _, sx in { -1, 1 } do
			P(V(1.8, 4.6, 7), ch * CFrame.new(sx * 4, 3.6, 0), rgb(170, 56, 58), Enum.Material.Fabric)
			P(V(2, 3, 2.4), ch * CFrame.new(sx * 3.4, 9.2, 2.6), rgb(170, 56, 58), Enum.Material.Fabric)
		end
		for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do cyl(0.7, 0.8, ch * CFrame.new(sx * 3.2, 0.4, sz * 2.6), WALNUT, WOODM) end end
		deco(K.folder(), ch * CFrame.new(0, 3.7, -0.4) * CFrame.Angles(0, math.pi, 0), "Peach", "sit")
		local tb = cf * CFrame.new(17, FLOOR_Y, -4)
		cyl(5, 0.6, tb * CFrame.new(0, 5.3, 0), WALNUT, WOODM)
		cyl(0.8, 5, tb * CFrame.new(0, 2.5, 0), WALNUT, WOODM)
		cyl(0.4, 4, tb * CFrame.new(0, 7.6, 0), rgb(180, 150, 90), Enum.Material.Metal)
		cyl(3.6, 2.6, tb * CFrame.new(0, 10.6, 0), rgb(255, 228, 176))
		P(V(3, 0.7, 2.2), tb * CFrame.new(-0.6, 5.95, 1) * CFrame.Angles(0, 0.4, 0), BOOK_COLS[2])
		deco(K.folder(), cf * CFrame.new(-8, FLOOR_Y, -6) * CFrame.Angles(0, math.pi - 0.5, 0), "Sky", "peek")
		door(e, cf, 14, 14, d)
		banner(e, cf, h + 5, "chart")
	end

	---------------------------------------------------------------------------
	-- TOY SHOP
	---------------------------------------------------------------------------
	local function buildShop(e)
		local w, d, h = 54, 30, 32
		local cf = shell(e, w, d, h, { wall = rgb(252, 238, 214), floor = rgb(226, 200, 164), title = nil, frame = rgb(188, 140, 98) })
		-- scalloped striped awning on two brackets
		for i = 0, 8 do
			local col = i % 2 == 0 and rgb(236, 112, 100) or CREAM
			local x = -w / 2 + w / 18 + i * w / 9
			P(V(w / 9, 0.6, 9), cf * CFrame.new(x, h - 3.4, -d / 2 - 4.2) * CFrame.Angles(0.34, 0, 0), col, Enum.Material.Fabric)
			cyl(w / 9 * 0.62, 0.5, cf * CFrame.new(x, h - 5.5, -d / 2 - 8.3) * CFrame.Angles(math.pi / 2 - 0.34, 0, 0), col, Enum.Material.Fabric)
		end
		for _, sx in { -1, 1 } do
			P(V(0.6, 0.6, 9), cf * CFrame.new(sx * (w / 2 - 1), h - 5.6, -d / 2 - 4.4) * CFrame.Angles(0.34, 0, 0), INK, Enum.Material.Metal)
		end
		-- painted sign board on the roof with two little gooseneck lamps
		local board = P(V(30, 9, 1), cf * CFrame.new(0, h + 7.6, -d / 2 + 2.4), rgb(70, 52, 86))
		P(V(32, 11, 0.6), cf * CFrame.new(0, h + 7.6, -d / 2 + 3), rgb(188, 140, 98), WOODM)
		for _, sx in { -1, 1 } do P(V(1.2, 4, 1.2), cf * CFrame.new(sx * 11, h + 3.2, -d / 2 + 3), rgb(188, 140, 98), WOODM) end
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0.3
		sg.CanvasSize = Vector2.new(300, 90)
		local row = Instance.new("Frame")
		row.Size = UDim2.fromScale(1, 1)
		row.BackgroundTransparency = 1
		row.Parent = sg
		UI.icon(row, "bag", { Size = UDim2.fromOffset(78, 78), Position = UDim2.fromOffset(10, 6) })
		UI.text(row, "TOY SHOP", { Size = UDim2.new(1, -104, 1, -16), Position = UDim2.fromOffset(96, 8), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(255, 214, 110), stroke = 0 })
		sg.Parent = board
		for _, sx in { -1, 1 } do
			cyl(0.3, 4, cf * CFrame.new(sx * 9, h + 13.6, -d / 2 + 1.2) * CFrame.Angles(0.9, 0, 0), INK, Enum.Material.Metal)
			local b = ball(1.2, cf * CFrame.new(sx * 9, h + 14.2, -d / 2 - 0.6), rgb(255, 232, 190), NEON, { noShadow = true })
			if sx == 1 then light(b, 18, 0.4, WARM) end
		end
		-- wall shelving built from boards, toys set inside
		local sw = w - 8
		P(V(sw, 24, 0.6), cf * CFrame.new(0, FLOOR_Y + 13, d / 2 - 0.9), rgb(232, 214, 184))
		for _, sx in { -1, 1 } do P(V(0.9, 24, 5), cf * CFrame.new(sx * (sw / 2 - 0.45), FLOOR_Y + 13, d / 2 - 3.4), BIRCH, WOODM) end
		for r = 0, 3 do
			local y = FLOOR_Y + 1.5 + r * 7.5
			P(V(sw - 1.8, 0.9, 5), cf * CFrame.new(0, y, d / 2 - 3.4), BIRCH, WOODM)
			if r < 3 then
				for k = 0, 6 do
					local c = cf * CFrame.new(-sw / 2 + 4.6 + k * (sw - 9.2) / 6, y + 0.45, d / 2 - 3.6)
					local item = (r * 7 + k) % 5
					if item == 0 then
						World.placeAsset(K.folder(), "ToyBlock", c * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0.3 * k, 0), V(3.2, 3.2, 3.2))
					elseif item == 1 then
						World.placeAsset(K.folder(), "RubberDuck", c * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, math.pi, 0), V(2.8, 3.2, 3.6))
					elseif item == 2 then
						ball(2.8, c * CFrame.new(0, 1.4, 0), BOOK_COLS[(r + k) % #BOOK_COLS + 1])
						cyl(2.9, 0.5, c * CFrame.new(0, 1.4, 0), CREAM)
					elseif item == 3 then
						-- a stacking-ring toy
						cyl(0.5, 4.2, c * CFrame.new(0, 2.1, 0), BIRCH, WOODM)
						for q = 0, 2 do cyl(3.2 - q * 0.7, 0.9, c * CFrame.new(0, 0.5 + q * 1, 0), BOOK_COLS[(k + q * 2) % #BOOK_COLS + 1]) end
					else
						P(V(2.6, 4, 1.6), c * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0.2, 0), BOOK_COLS[(r * 3 + k) % #BOOK_COLS + 1])
						P(V(2, 1.6, 0.2), c * CFrame.new(0, 2.6, -0.85) * CFrame.Angles(0, 0.2, 0), CREAM)
					end
				end
			end
		end
		-- counter: panelled front, overhanging top, register with keys, a coin jar
		local ct = cf * CFrame.new(-12, FLOOR_Y, 0)
		solid(P(V(20, 7, 6), ct * CFrame.new(0, 3.5, 0), rgb(240, 176, 116)))
		for k = 0, 2 do P(V(5.4, 5, 0.3), ct * CFrame.new(-6.4 + k * 6.4, 3.5, -3.1), rgb(250, 204, 150)) end
		P(V(21.4, 0.9, 7.2), ct * CFrame.new(0, 7.45, 0), WALNUT, WOODM)
		P(V(5, 3, 4.2), ct * CFrame.new(-5.6, 9.4, 0.4), rgb(92, 88, 108))
		P(V(4, 1.6, 0.3), ct * CFrame.new(-5.6, 10.6, -1.8) * CFrame.Angles(-0.35, 0, 0), rgb(150, 236, 170), NEON, { noShadow = true })
		for kx = 0, 2 do for kz = 0, 1 do P(V(0.8, 0.4, 0.8), ct * CFrame.new(-6.6 + kx * 1, 8.2 + kz * 0, -1.2 + kz * 1), CREAM) end end
		local jar = cyl(3.2, 4, ct * CFrame.new(4.4, 9.9, 0.4), rgb(226, 240, 250))
		jar.Transparency = 0.55
		cyl(3.4, 0.5, ct * CFrame.new(4.4, 12.1, 0.4), WALNUT, WOODM)
		for k = 0, 5 do
			local coin = Models.hasMeshes("StarCoin") and Models.rigMesh(K.folder(), "StarCoin", 1, rgb(255, 200, 60), Enum.Material.SmoothPlastic) or cyl(1.7, 0.35, CFrame.new(), rgb(255, 200, 60))
			if coin:IsA("MeshPart") then coin.Size = Models.coinSize(1.7) end
			coin.CFrame = ct * CFrame.new(4.4 + ((k % 3) - 1) * 0.5, 8.3 + k * 0.42, 0.4 + ((k % 2) - 0.5) * 0.4) * CFrame.Angles(math.pi / 2, 0, k * 1.3)
		end
		deco(K.folder(), ct * CFrame.new(0, 0, 5.5) * CFrame.Angles(0, math.pi, 0), "Lemon", "cheer")
		-- a striped mat at the door and a hanging OPEN sign
		for i = 0, 4 do
			P(V(3, 0.2, 6), cf * CFrame.new(-6 + i * 3, FLOOR_Y + 0.1, -d / 2 + 4), i % 2 == 0 and rgb(236, 112, 100) or CREAM, Enum.Material.Fabric, { noShadow = true })
		end
		local open = K.neonText(K.folder(), cf * CFrame.new(18, 15, -d / 2 + 1.2), V(8, 3, 0.4), "OPEN", rgb(150, 240, 176))
		for _, sx in { -1, 1 } do cyl(0.15, 6, cf * CFrame.new(18 + sx * 3.4, 19.5, -d / 2 + 1.2), INK) end
		plant(cf * CFrame.new(w / 2 - 3.6, FLOOR_Y, -d / 2 + 3.6), 1)
		door(e, cf, 16, 16, d)
		banner(e, cf, h + 15, "bag")
	end

	---------------------------------------------------------------------------
	-- BOUTIQUE (Outfits)
	---------------------------------------------------------------------------
	local function buildBoutique(e)
		local w, d, h = 40, 24, 30
		local cf = shell(e, w, d, h, { wall = rgb(250, 222, 232), floor = rgb(232, 210, 188), title = "LITTLE BOUTIQUE", frame = rgb(226, 190, 170), plaque = rgb(190, 96, 130) })
		-- wallpaper stripes
		for i = 0, 9 do
			P(V(1.2, h - 4, 0.12), cf * CFrame.new(-w / 2 + 2 + i * 4, h / 2 + 1.6, d / 2 - 0.48), rgb(244, 204, 220), MATTE, { noShadow = true })
		end
		-- clothes rail on two uprights, hangers with little outfits
		for _, x in { -13, 13 } do cyl(0.5, 15, cf * CFrame.new(x, FLOOR_Y + 7.5, d / 2 - 5), rgb(205, 170, 110), Enum.Material.Metal) end
		cyl(0.5, 27, cf * CFrame.new(0, FLOOR_Y + 15, d / 2 - 5) * CFrame.Angles(0, 0, math.pi / 2), rgb(205, 170, 110), Enum.Material.Metal)
		for i = 0, 6 do
			local hc = cf * CFrame.new(-10.5 + i * 3.5, FLOOR_Y + 14.2, d / 2 - 5)
			P(V(3, 0.3, 0.3), hc * CFrame.new(0, 0.2, 0), WALNUT, WOODM)
			local col = BOOK_COLS[(i * 3) % #BOOK_COLS + 1]
			P(V(3, 5.4, 1.4), hc * CFrame.new(0, -3, 0), col, Enum.Material.Fabric)
			P(V(3.4, 1.2, 1.5), hc * CFrame.new(0, -0.9, 0), tint(col, 0.25), Enum.Material.Fabric)
		end
		-- standing mirror in a wooden frame (soft, not a chrome slab)
		local mc = cf * CFrame.new(-14, FLOOR_Y, 2) * CFrame.Angles(0, 0.6, 0)
		P(V(8, 15, 0.8), mc * CFrame.new(0, 8.2, 0) * CFrame.Angles(-0.1, 0, 0), rgb(205, 170, 110), WOODM)
		local glass = P(V(6.6, 13.4, 0.3), mc * CFrame.new(0, 8.2, -0.5) * CFrame.Angles(-0.1, 0, 0), rgb(214, 232, 246))
		glass.Reflectance = 0.12
		for _, sx in { -1, 1 } do P(V(0.7, 1.4, 5), mc * CFrame.new(sx * 3.4, 0.7, 0.8), rgb(205, 170, 110), WOODM) end
		-- hat stand with three hats, a round display table with folded scarves
		local hs = cf * CFrame.new(14, FLOOR_Y, 3)
		cyl(3.6, 0.6, hs * CFrame.new(0, 0.3, 0), WALNUT, WOODM)
		cyl(0.6, 13, hs * CFrame.new(0, 6.8, 0), WALNUT, WOODM)
		for k, hat in { { 0, 13.6, rgb(255, 205, 80) }, { 1.9, 10.2, rgb(150, 205, 140) }, { -1.9, 8, rgb(185, 160, 240) } } do
			cyl(3.8, 0.35, hs * CFrame.new(hat[1], hat[2], 0), hat[3], Enum.Material.Fabric)
			blob(V(2.4, 1.9, 2.4), hs * CFrame.new(hat[1], hat[2] + 0.8, 0), hat[3], Enum.Material.Fabric)
		end
		local tbl = cf * CFrame.new(3, FLOOR_Y, -4)
		cyl(8, 0.7, tbl * CFrame.new(0, 4.4, 0), CREAM)
		cyl(1.2, 4, tbl * CFrame.new(0, 2, 0), CREAM)
		cyl(4, 0.5, tbl * CFrame.new(0, 0.25, 0), CREAM)
		for k = 0, 3 do
			P(V(3, 0.6, 2.2), tbl * CFrame.new(-1.6 + (k % 2) * 3.2, 5 + math.floor(k / 2) * 0.62, -0.6 + (k % 2) * 0.8) * CFrame.Angles(0, k * 0.2, 0), BOOK_COLS[(k * 2 + 1) % #BOOK_COLS + 1], Enum.Material.Fabric)
		end
		rug(cf * CFrame.new(-3, 0, -2), 16, rgb(240, 176, 200))
		local rig = Models.buildSminski(K.folder(), 1, Config.Character("Lavender"), true, "flowers")
		Models.poseSminski(rig, cf * CFrame.new(-7, FLOOR_Y, -1) * CFrame.Angles(0, math.pi - 0.6, 0), "cheer", 2)
		door(e, cf, 14, 14, d)
		banner(e, cf, h + 5, "shirt")
	end

	---------------------------------------------------------------------------
	-- CAFE (Play Together): an open-air corner under a pergola
	---------------------------------------------------------------------------
	local function buildCafe(e)
		local cf = frameOf(e)
		local w, d = 40, 30
		solid(P(V(w + 3, 1.2, d + 3), cf * CFrame.new(0, 0.6, 0), WALNUT, WOODM))
		-- terracotta tiles
		for ix = 0, 4 do for iz = 0, 3 do
			P(V(w / 5 - 0.3, 0.4, d / 4 - 0.3), cf * CFrame.new(-w / 2 + w / 10 + ix * w / 5, 1.4, -d / 2 + d / 8 + iz * d / 4), (ix + iz) % 2 == 0 and rgb(214, 150, 116) or rgb(226, 168, 132), MATTE, { noShadow = true })
		end end
		-- pergola: four posts, two beams, rafters with rounded tails
		local ph = 25
		for _, x in { -w / 2 + 1.5, w / 2 - 1.5 } do for _, z in { -d / 2 + 1.5, d / 2 - 1.5 } do
			solid(P(V(1.6, ph, 1.6), cf * CFrame.new(x, ph / 2 + 1.2, z), CREAM, WOODM))
			P(V(2.6, 1.4, 2.6), cf * CFrame.new(x, 1.9, z), shade(CREAM, 0.08), WOODM)
		end end
		for _, z in { -d / 2 + 1.5, d / 2 - 1.5 } do P(V(w + 3, 1.6, 1.2), cf * CFrame.new(0, ph + 1.4, z), CREAM, WOODM) end
		for i = 0, 6 do P(V(1, 1.2, d + 5), cf * CFrame.new(-w / 2 + 2 + i * (w - 4) / 6, ph + 2.6, 0), CREAM, WOODM) end
		-- string lights: many bulbs, only two real lights
		for i = 0, 12 do
			local k = i / 12
			local b = ball(0.9, cf * CFrame.new(-w / 2 + 2 + k * (w - 4), ph + 0.2 - math.sin(k * math.pi) * 3, -d / 2 + 1.6), rgb(255, 228, 170), NEON, { noShadow = true })
			if i == 3 or i == 9 then light(b, 22, 0.45, WARM) end
		end
		-- climbing plant on one post
		for k = 0, 8 do
			blob(V(2.2, 1.6, 2.2), cf * CFrame.new(w / 2 - 1.5 + math.sin(k * 1.3) * 0.9, 3 + k * 2.6, d / 2 - 1.5 + math.cos(k * 1.7) * 0.9), k % 2 == 0 and rgb(104, 170, 96) or rgb(128, 190, 110))
		end
		-- two bistro tables with stools and cups
		for k, spot in { V(-10, 0, -3), V(9, 0, 1) } do
			local tcf = cf * CFrame.new(spot) * CFrame.new(0, FLOOR_Y, 0)
			cyl(3.4, 0.5, tcf * CFrame.new(0, 0.25, 0), INK, Enum.Material.Metal)
			cyl(0.7, 5, tcf * CFrame.new(0, 2.7, 0), INK, Enum.Material.Metal)
			solid(cyl(8.6, 0.6, tcf * CFrame.new(0, 5.4, 0), CREAM))
			cyl(1.5, 1.3, tcf * CFrame.new(1.4, 6.35, 0.6), CREAM)
			cyl(1.1, 0.12, tcf * CFrame.new(1.4, 7, 0.6), rgb(120, 78, 50))
			cyl(2.2, 0.2, tcf * CFrame.new(-1.6, 5.8, -0.8), rgb(240, 176, 200))
			blob(V(1.6, 1, 1.6), tcf * CFrame.new(-1.6, 6.3, -0.8), rgb(252, 226, 190))
			for side = -1, 1, 2 do
				local st = tcf * CFrame.new(side * 6.4, 0, 0)
				cyl(3, 0.6, st * CFrame.new(0, 2.6, 0), rgb(236, 112, 100), Enum.Material.Fabric)
				cyl(0.5, 2.4, st * CFrame.new(0, 1.2, 0), INK, Enum.Material.Metal)
				deco(K.folder(), st * CFrame.new(0, 2.9, 0) * CFrame.Angles(0, side * math.pi / 2, 0), k == 1 and (side < 0 and "Blush" or "Lemon") or (side < 0 and "Mint" or "Lavender"), "sit")
			end
		end
		-- counter at the back: panelled, with a pastry stand, an espresso machine and a menu board
		local ct = cf * CFrame.new(0, FLOOR_Y, d / 2 - 5)
		solid(P(V(22, 7, 5), ct * CFrame.new(0, 3.5, 0), rgb(244, 186, 196)))
		for k = 0, 3 do P(V(4.4, 5, 0.3), ct * CFrame.new(-7.8 + k * 5.2, 3.5, -2.6), rgb(252, 214, 220)) end
		P(V(23.4, 0.8, 6), ct * CFrame.new(0, 7.4, 0), WALNUT, WOODM)
		cyl(4.6, 0.3, ct * CFrame.new(-6, 9.4, 0), CREAM)
		cyl(0.5, 1.6, ct * CFrame.new(-6, 8.6, 0), CREAM)
		cyl(3.2, 1.8, ct * CFrame.new(-6, 10.5, 0), rgb(255, 238, 226))
		ball(0.8, ct * CFrame.new(-6, 11.8, 0), rgb(226, 72, 84))
		P(V(5, 4.6, 4), ct * CFrame.new(5.5, 10.1, 0.2), rgb(196, 200, 210), Enum.Material.Metal)
		P(V(5.4, 0.8, 4.4), ct * CFrame.new(5.5, 12.8, 0.2), INK)
		cyl(0.5, 1.6, ct * CFrame.new(5.5, 8.9, -1.6), INK)
		local menu = P(V(12, 8, 0.5), cf * CFrame.new(0, 18, d / 2 - 1.4), rgb(54, 60, 58))
		P(V(13.2, 9.2, 0.4), cf * CFrame.new(0, 18, d / 2 - 1.1), WALNUT, WOODM)
		textOn(menu, Enum.NormalId.Front, "QUICK PLAY\nPRIVATE LOBBY\nRANKED", CREAM, Vector2.new(360, 240))
		for _, x in { -w / 2 + 4, w / 2 - 4 } do
			P(V(6, 2.6, 2.6), cf * CFrame.new(x, FLOOR_Y + 1.3, -d / 2 + 2.2), WALNUT, WOODM)
			for q = 0, 2 do blob(V(2.2, 2, 2.2), cf * CFrame.new(x - 1.8 + q * 1.8, FLOOR_Y + 3.2, -d / 2 + 2.2), q % 2 == 0 and rgb(240, 150, 176) or rgb(128, 190, 110)) end
		end
		entranceParts[e.id] = P(V(14, 12, 0.4), cf * CFrame.new(0, 7, -d / 2 + 3), Color3.new(), MATTE, { transparency = 1 })
		banner(e, cf, ph + 8, "friends")
	end

	---------------------------------------------------------------------------
	-- DOG PARK TRAY (Survival waiting pen)
	---------------------------------------------------------------------------
	local function buildDogTray(e)
		local c = e.pos
		local hx, hz = 24, 22
		local function at(x, y, z) return CFrame.new(HUB + V(x, y, z)) end
		-- a wooden tray with a raised rim, filled with turf
		solid(P(V(hx * 2 + 4, 1.2, hz * 2 + 4), at(c.X, 0.6, c.Z), WALNUT, WOODM))
		P(V(hx * 2, 0.7, hz * 2), at(c.X, 1.55, c.Z), rgb(118, 196, 104), Enum.Material.Grass)
		for _, s in { { 0, -hz - 1.4, hx * 2 + 4, 1.2 }, { 0, hz + 1.4, hx * 2 + 4, 1.2 }, { -hx - 1.4, 0, 1.2, hz * 2 + 1.6 }, { hx + 1.4, 0, 1.2, hz * 2 + 1.6 } } do
			P(V(s[3], 2.4, s[4]), at(c.X + s[1], 1.8, c.Z + s[2]), BIRCH, WOODM)
		end
		-- picket fence with pointed tops; a gap + arch at the front
		local x0, x1, z0, z1 = c.X - hx, c.X + hx, c.Z - hz, c.Z + hz
		local function run(from, to)
			local dlt = to - from
			local n = math.floor(dlt.Magnitude / 2.8)
			for i = 0, n do
				local p = from + dlt * (i / math.max(1, n))
				solid(P(V(1.1, 4.8, 0.7), CFrame.lookAt(HUB + p + V(0, 4.3, 0), HUB + p + V(0, 4.3, 0) + dlt.Unit:Cross(V(0, 1, 0))), CREAM))
				P(V(0.8, 0.8, 0.7), CFrame.lookAt(HUB + p + V(0, 6.8, 0), HUB + p + V(0, 6.8, 0) + dlt.Unit:Cross(V(0, 1, 0))) * CFrame.Angles(0, 0, math.pi / 4), CREAM)
			end
			for _, y in { 3.4, 5.4 } do
				local mid = from + dlt / 2
				P(V(0.5, 0.7, dlt.Magnitude), CFrame.lookAt(HUB + mid + V(0, y, 0), HUB + to + V(0, y, 0)), shade(CREAM, 0.06))
			end
		end
		run(V(x0, 0, z0), V(c.X - 7.5, 0, z0))
		run(V(c.X + 7.5, 0, z0), V(x1, 0, z0))
		run(V(x0, 0, z1), V(x1, 0, z1))
		run(V(x0, 0, z0), V(x0, 0, z1))
		run(V(x1, 0, z0), V(x1, 0, z1))
		for _, sx in { -7.5, 7.5 } do solid(P(V(1.6, 13, 1.6), at(c.X + sx, 8.4, z0), rgb(112, 186, 104), WOODM)) end
		P(V(18, 2.6, 1.4), at(c.X, 14.6, z0), rgb(240, 196, 84), WOODM)
		local archTxt = P(V(15, 1.9, 0.3), at(c.X, 14.6, z0 - 0.85), rgb(86, 120, 70))
		textOn(archTxt, Enum.NormalId.Front, "DOG PARK", CREAM, Vector2.new(420, 60))
		-- trees, a doghouse with a gable roof, a bone, a ball, a water bowl, the pup
		for _, p in { V(c.X - 16, 0, c.Z + 12), V(c.X + 17, 0, c.Z + 13) } do
			if not World.placeAsset(K.folder(), "ParkTree", at(p.X, 9.9, p.Z), V(12, 16, 12)) then
				cyl(1.6, 8, at(p.X, 5.9, p.Z), rgb(135, 95, 70), WOODM)
				ball(10, at(p.X, 13, p.Z), rgb(110, 190, 95), Enum.Material.Grass)
			end
		end
		local dh = at(c.X, 1.9, c.Z + 11)
		solid(P(V(10, 6.4, 8), dh * CFrame.new(0, 3.2, 0), rgb(226, 104, 92)))
		P(V(4.2, 4.6, 0.5), dh * CFrame.new(0, 2.3, -4.05), rgb(44, 34, 52))
		cyl(4.2, 0.5, dh * CFrame.new(0, 4.6, -4.05) * CFrame.Angles(math.pi / 2, 0, 0), rgb(44, 34, 52))
		gableRoof(dh, 10, 8, 6.4, 3.6, rgb(250, 244, 232))
		local tag = P(V(3.4, 1.2, 0.3), dh * CFrame.new(0, 6.1, -4.45), rgb(240, 196, 84))
		textOn(tag, Enum.NormalId.Front, "PUP", INK, Vector2.new(160, 56))
		World.placeAsset(K.folder(), "DogBowl", at(c.X + 8, 2.7, c.Z + 6), V(3.4, 1.8, 3.4))
		ball(2, at(c.X - 4, 2.9, c.Z - 8), rgb(214, 236, 84), Enum.Material.Fabric)
		local bone = at(c.X + 5, 2.3, c.Z - 6) * CFrame.Angles(0, 0.6, 0)
		P(V(3.4, 0.7, 0.8), bone, CREAM)
		for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do ball(0.9, bone * CFrame.new(sx * 1.7, 0, sz * 0.35), CREAM) end end
		local pup = Models.buildDog(K.folder(), { scale = 0.18, fur = rgb(245, 245, 240), light = rgb(255, 255, 255), dark = rgb(200, 170, 140) })
		K.setPup({ rig = pup, cf = at(c.X - 8, 1.9, c.Z - 2) * CFrame.Angles(0, 2.6, 0) })
		-- framed status board at the back
		for _, x in { -12, 12 } do solid(P(V(1.4, 15, 1.4), at(c.X + x, 9.4, z1 + 1), WALNUT, WOODM)) end
		P(V(28, 13, 0.8), at(c.X, 15.4, z1 + 1.2), WALNUT, WOODM)
		local board = solid(P(V(26, 11, 0.6), at(c.X, 15.4, z1 + 0.7), rgb(58, 64, 60)))
		local bg = Instance.new("SurfaceGui")
		bg.Face = Enum.NormalId.Front
		bg.CanvasSize = Vector2.new(520, 220)
		bg.LightInfluence = 0.3
		UI.text(bg, "DOG PARK SURVIVAL", { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 8), Font = Enum.Font.FredokaOne, TextSize = 42, TextColor3 = C.gold, stroke = 0 })
		UI.text(bg, "last Sminski alive wins", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 56), Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = CREAM })
		local line1 = UI.text(bg, "PLAYERS 0 / 16", { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 96), Font = Enum.Font.FredokaOne, TextSize = 38, TextColor3 = C.mint, stroke = 0 })
		local line2 = UI.text(bg, "walk in to join", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 150), Font = Enum.Font.FredokaOne, TextSize = 32, TextColor3 = CREAM, stroke = 0 })
		bg.Parent = board
		K.setPen({ line1 = line1, line2 = line2 })
		local gate = P(V(14, 9, 1), at(c.X, 5, z0), rgb(245, 196, 80), MATTE, { transparency = 1 })
		entranceParts[e.id] = gate
		sign(K.folder(), gate, e.title, e.sub, e.color, "paw", 14)
	end

	local BUILDERS = {
		house = buildBigHouse, dollhouse = buildDollhouse, dogrun = buildDogRun,
		arcade = buildRecords, board = buildLibrary, store = buildShop,
		closet = buildBoutique, friends = buildCafe, dogpark = buildDogTray,
	}
	return {
		build = function(e)
			local f = BUILDERS[e.id]
			if f then f(e) return true end
			return false
		end,
		kit = { P = P, cyl = cyl, ball = ball, blob = blob, plant = plant, MATTE = MATTE, textOn = textOn },
	}
end
