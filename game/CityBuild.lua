-- CityBuild (client): every block of Sminski City.
--   Build.base()   roads, crossings, sidewalks, the edge of town, the gate
--   Build.blocks() one entry per block: { cx, cz, kind, run } (run() builds it;
--                  City.lua runs these in coroutines, nearest block first)
--   Build.nature() pines on the valley slopes (the mountains are Terrain)
-- Blocks register moving things (ferris wheel, carousel, windmills, dancers)
-- in Build.anims so they only animate while you're near.
--   deps: K (CityKit), Models, Config, Places

return function(deps)
	local K, Models, Config, Places = deps.K, deps.Models, deps.Config, deps.Places
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local P, W, cyl, ball, blob, solid, walkable = K.P, K.W, K.cyl, K.ball, K.blob, K.solid, K.walkable
	local Cc = K.C
	local part = Models.part
	-- a warm ceiling light that really lights a room
	local function roomLight(cf, range, bright)
		local b = K.ball(2.4, cf, rgb(255, 240, 210), NEON)
		b.CastShadow = false
		local l = Instance.new("PointLight")
		l.Range = range or 50
		l.Brightness = bright or 1.2
		l.Color = rgb(255, 236, 206)
		l.Shadows = false
		l.Parent = b
		return b
	end
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL
	local CITY = Places.CITY
	local ROADS = Places.CityRoads
	local RW = Places.ROAD_W
	local PAD = K.PAD_Y
	local HALF_B = Places.BLOCK / 2 -- 130
	local INNER = HALF_B - Places.WALK_W -- 116: inside the sidewalk ring

	local Build = { anims = {}, parked = {}, dancers = {}, spots = {}, workers = {} }
	local B = {} -- block builders by kind

	-- townsfolk with little jobs: a sweeper with a broom, a bench reader
	local function worker(kind, cf, charIndex)
		local def = Config.Characters[(charIndex or 1) % #Config.Characters + 1]
		local rig = Models.buildSminski(K.cur, 1, def, false, kind == "sweep" and "beanie" or nil)
		local prop = Instance.new("Model")
		prop.Parent = K.cur
		if kind == "sweep" then
			part(prop, V(0.3, 6.4, 0.3), CFrame.new(0, -2.6, 0), rgb(196, 150, 104), WOODM)
			part(prop, V(2.6, 1.1, 0.9), CFrame.new(0, -6, 0), rgb(250, 222, 130), WOODM)
			part(prop, V(2.8, 0.3, 1), CFrame.new(0, -5.4, 0), Cc.sage)
		else
			part(prop, V(2.4, 1.8, 0.1), CFrame.new(-0.6, 0, 0) * CFrame.Angles(0, 0.35, 0), rgb(248, 246, 236), SMOOTH)
			part(prop, V(2.4, 1.8, 0.1), CFrame.new(0.6, 0, 0) * CFrame.Angles(0, -0.35, 0), rgb(248, 246, 236), SMOOTH)
			part(prop, V(1.6, 0.2, 0.12), CFrame.new(-0.6, 0.4, -0.08) * CFrame.Angles(0, 0.35, 0), Cc.ink)
		end
		prop.WorldPivot = CFrame.new()
		table.insert(Build.workers, { kind = kind, rig = rig, prop = prop, cf = cf, t0 = math.random() * 5 })
	end
	Build.worker = worker

	local function isRoad(v)
		for _, r in ROADS do if math.abs(v - r) < RW / 2 + 1 then return true end end
		return false
	end
	Build.isRoad = isRoad
	local function park(cf, kind, color)
		table.insert(Build.parked, { cf = cf, kind = kind or "convertible", color = color or K.CAR_COLORS[#Build.parked % 8 + 1] })
	end
	-- an enterable room: floor, three walls, a front wall with a doorway, roof
	local function room(f, w, d, h, wall, floorCol, doorW, roofCol)
		walkable(P(V(w, 0.5, d), f * CFrame.new(0, 0.25, 0), floorCol or rgb(236, 226, 206), SMOOTH))
		solid(P(V(w, h, 1.2), f * CFrame.new(0, h / 2, d / 2), wall))
		for _, sx in { -1, 1 } do solid(P(V(1.2, h, d), f * CFrame.new(sx * w / 2, h / 2, 0), wall)) end
		local seg = (w - doorW) / 2
		for _, sx in { -1, 1 } do
			solid(P(V(seg, h, 1.2), f * CFrame.new(sx * (doorW / 2 + seg / 2), h / 2, -d / 2), wall))
		end
		P(V(doorW, h - 12, 1.2), f * CFrame.new(0, 12 + (h - 12) / 2, -d / 2), wall)
		solid(P(V(w + 2, 1.2, d + 2), f * CFrame.new(0, h + 0.6, 0), roofCol or shade(wall, 0.12)))
		P(V(w + 0.2, 0.4, d + 0.2), f * CFrame.new(0, h - 0.4, 0), Cc.cream) -- ceiling trim
	end
	Build.room = room

	---------------------------------------------------------------------------
	-- BASE: roads, crossings, dashes, outer sidewalks, edge of town
	---------------------------------------------------------------------------
	function Build.base()
		K.cur = K.root
		local E = ROADS[#ROADS] + RW / 2 -- 920
		-- the whole valley floor inside town (terrain grass shows beyond it)
		walkable(P(V(2016, 1, 2016), W(0, -0.52, 0), Cc.grass, MATTE, { noShadow = true }))
		for _, r in ROADS do
			walkable(P(V(RW, 0.2, E * 2), W(r, -0.1, 0), Cc.road, SMOOTH, { noShadow = true }))
			walkable(P(V(E * 2, 0.2, RW), W(0, -0.1, r), Cc.road, SMOOTH, { noShadow = true }))
			-- two dashed lane lines each way
			for k = -E + 10, E - 10, 16 do
				if not isRoad(k) and not isRoad(k + 8) then
					for _, off in { -1, 1 } do
						if off == 1 then
							P(V(0.6, 0.06, 8), W(r, 0.02, k + 4), Cc.line, SMOOTH, { noShadow = true })
							P(V(8, 0.06, 0.6), W(k + 4, 0.02, r), Cc.line, SMOOTH, { noShadow = true })
						end
					end
				end
			end
		end
		-- zebra crossings on every approach
		for _, rx in ROADS do
			for _, rz in ROADS do
				for _, dir in { V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1) } do
					local c = V(rx, 0, rz) + dir * (RW / 2 + 5)
					if math.abs(c.X) < E and math.abs(c.Z) < E then
						for k = -3, 3 do
							local off = dir.X ~= 0 and V(0, 0, k * 5.2) or V(k * 5.2, 0, 0)
							local size = dir.X ~= 0 and V(7, 0.06, 2.6) or V(2.6, 0.06, 7)
							P(size, W(c.X + off.X, 0.02, c.Z + off.Z), Cc.line, SMOOTH, { noShadow = true })
						end
					end
				end
			end
		end
		-- outer sidewalks all round town + a rail fence at the edge
		local o0, o1 = E, E + 14
		for _, s in { -1, 1 } do
			walkable(P(V(o1 * 2, PAD, 14), W(0, PAD / 2, s * (o0 + o1) / 2), Cc.pave, MATTE, { noShadow = true }))
			walkable(P(V(14, PAD, o1 * 2), W(s * (o0 + o1) / 2, PAD / 2, 0), Cc.pave, MATTE, { noShadow = true }))
		end
		local F = 992
		for _, s in { -1, 1 } do
			for k = -F, F - 40, 40 do
				if math.abs(k + 20) >= 60 then K.fence(V(k, 0, s * F), V(k + 40, 0, s * F)) end
				K.fence(V(s * F, 0, k), V(s * F, 0, k + 40))
			end
		end
		if Build.signalsFn then Build.signals = Build.signalsFn() end
		-- the freeway, the bridge, The Elevated, the airport (CityRoads)
		if Build.roadsFn then Build.roadsFn() end
		Build.entrance()
		-- the fountain roundabout in the middle of Times Sminski Square
		local rc = W(0, 0, 0)
		solid(cyl(12, 1.6, rc * CFrame.new(0, 0.8, 0), Cc.cream))
		cyl(10.4, 1.7, rc * CFrame.new(0, 0.9, 0), Cc.water, SMOOTH)
		cyl(2.4, 5, rc * CFrame.new(0, 2.5, 0), Cc.cream)
		cyl(5.6, 0.8, rc * CFrame.new(0, 5, 0), Cc.cream)
		ball(2.4, rc * CFrame.new(0, 6.6, 0), rgb(255, 170, 200))
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			ball(1.1, rc * CFrame.new(math.cos(a) * 5.6, 1.9, math.sin(a) * 5.6), K.FLOWER_COLS[k % 5 + 1])
		end
	end

	-- the harbour on the bay north of town: a boardwalk, piers, boats, cranes
	function Build.harbour()
		local z0 = 1010
		walkable(P(V(900, 1, 40), W(0, 0, z0 + 20), rgb(214, 178, 130), WOODM))
		for k = -5, 5 do
			P(V(900, 0.06, 0.4), W(0, 0.54, z0 + 20 + k * 3.6), rgb(190, 152, 108), WOODM, { noShadow = true })
		end
		for _, x in { -300, -100, 100, 300 } do
			walkable(P(V(14, 1, 120), W(x, 0, z0 + 100), rgb(214, 178, 130), WOODM))
			for k = 0, 5 do
				for _, sx in { -7, 7 } do cyl(1.6, 8, W(x + sx, -2, z0 + 50 + k * 22), rgb(150, 110, 80), WOODM) end
			end
			K.lamp(x, z0 + 156)
		end
		-- sailing boats + a ferry
		Build.boats = {}
		for k, x in { -200, 0, 200, -380, 380 } do
			local cf = W(x, -1.4, z0 + 90 + (k % 2) * 40) * CFrame.Angles(0, k * 0.7, 0)
			local m = Instance.new("Model")
			m.Parent = K.cur
			local col = K.CAR_COLORS[k + 1]
			part(m, V(8, 3, 20), cf * CFrame.new(0, 1.5, 0), Cc.cream, SMOOTH)
			part(m, V(8.2, 0.8, 20.2), cf * CFrame.new(0, 2.8, 0), col, SMOOTH)
			part(m, V(0.5, 22, 0.5), cf * CFrame.new(0, 13, -1), rgb(150, 110, 80), WOODM)
			part(m, V(0.3, 16, 10), cf * CFrame.new(0, 12, 4.4), Color3.new(1, 1, 1), MATTE, { class = "WedgePart" })
			part(m, V(0.3, 12, 6), cf * CFrame.new(0, 10, -4.4) * CFrame.Angles(0, math.pi, 0), col, MATTE, { class = "WedgePart" })
			m.WorldPivot = cf
			table.insert(Build.boats, { m = m, cf = cf, t0 = k })
		end
		table.insert(Build.anims, { cx = 0, cz = 1100, far = true, fn = function(_, t)
			for _, b in Build.boats do
				b.m:PivotTo(b.cf * CFrame.new(0, math.sin(t * 0.9 + b.t0) * 0.5, 0) * CFrame.Angles(math.sin(t * 0.7 + b.t0) * 0.04, 0, math.sin(t * 0.5 + b.t0) * 0.05))
			end
		end })
		-- two cargo cranes out east
		for _, x in { 520, 620 } do
			local c = W(x, 0, z0 + 30)
			for _, sx in { -10, 10 } do solid(P(V(3, 70, 3), c * CFrame.new(sx, 35, 0), rgb(240, 130, 90), METAL)) end
			P(V(26, 4, 5), c * CFrame.new(0, 68, 0), rgb(240, 130, 90), METAL)
			P(V(5, 4, 110), c * CFrame.new(0, 74, 30), rgb(240, 130, 90), METAL)
			P(V(0.6, 40, 0.6), c * CFrame.new(0, 52, 70), Cc.ink, METAL)
		end
		for k = 0, 8 do
			P(V(16, 7, 7), W(470 + (k % 3) * 18, 4 + math.floor(k / 3) * 7, z0 + 22), K.CAR_COLORS[k % 8 + 1], METAL)
		end
		-- a lighthouse on the west point
		local lh = W(-560, 0, z0 + 60)
		solid(cyl(16, 6, lh * CFrame.new(0, 3, 0), Cc.stone))
		for k = 0, 4 do cyl(12 - k * 1.2, 12, lh * CFrame.new(0, 12 + k * 12, 0), k % 2 == 0 and Cc.cream or Cc.red) end
		cyl(9, 5, lh * CFrame.new(0, 68, 0), rgb(255, 240, 190), NEON)
		cyl(11, 2, lh * CFrame.new(0, 72, 0), Cc.red)
		K.sign(W(0, 12, z0 + 2) * CFrame.Angles(0, math.pi, 0), 40, 5, rgb(90, 160, 220), Cc.cream, "SMINSKI HARBOUR")
		for _, sx in { -18, 18 } do solid(cyl(1.4, 12, W(sx, 6, z0 + 2), Cc.cream)) end
	end

	-- the way in: welcome arch, car park, bus stop, tunnel back to the bedroom
	function Build.entrance()
		local sp = Places.CitySpawn
		P(V(90, 0.2, 50), W(0, 0.1, sp.Z - 6), Cc.pave, MATTE, { noShadow = true })
		for k = 0, 5 do P(V(10, 0.22, 3), W(0, 0.12, sp.Z + 18 - k * 7), Cc.stone, MATTE, { noShadow = true }) end
		-- the big welcome arch over Main St
		local ac = W(0, 0, -928)
		for _, sx in { -1, 1 } do
			solid(P(V(4, 30, 4), ac * CFrame.new(sx * 26, 15, 0), Cc.stone))
			P(V(5.4, 2, 5.4), ac * CFrame.new(sx * 26, 1, 0), shade(Cc.stone, 0.1))
			ball(5, ac * CFrame.new(sx * 26, 31.5, 0), Cc.gold, METAL)
			K.flowers(ac * CFrame.new(sx * 32, 0, 0), 6, 4)
		end
		local sgn = P(V(52, 7, 1.2), ac * CFrame.new(0, 26, 0), rgb(96, 132, 88))
		P(V(54.4, 9.2, 0.6), ac * CFrame.new(0, 26, -0.7), rgb(150, 110, 80), WOODM)
		K.textOn(sgn, Enum.NormalId.Back, "WELCOME TO SMINSKI CITY", Cc.cream, Vector2.new(900, 120), 0.5)
		K.textOn(sgn, Enum.NormalId.Front, "SMINSKI CITY", Cc.cream, Vector2.new(700, 120), 0.5)
		-- THE SMINSKI ARCADE: the big glowing landmark at the end of Main St.
		-- Walk in and you're at the games (runs, dog park, shops).
		local ex = Places.CityExit
		local f = K.frameOf(V(ex.X, 0, ex.Z - 46), 0) -- local -Z faces the town
		local AW, AD, AH = 150, 84, 62
		local shellCol = rgb(86, 62, 150)
		solid(P(V(AW, AH, AD), f * CFrame.new(0, AH / 2, 0), shellCol))
		P(V(AW + 6, 10, AD + 6), f * CFrame.new(0, 5, 0), rgb(64, 46, 116))
		K.cornice(f, AW, AD, AH, rgb(252, 246, 226), rgb(120, 90, 210))
		-- a stepped deco crown with a giant glowing joystick on top
		for k = 0, 2 do
			P(V(AW - 30 - k * 30, 8, AD - 20 - k * 20), f * CFrame.new(0, AH + 4 + k * 8, 0), k % 2 == 0 and rgb(120, 90, 210) or rgb(252, 246, 226))
		end
		local jb = f * CFrame.new(0, AH + 28, 0)
		cyl(26, 5, jb, rgb(60, 44, 110))
		cyl(4, 22, jb * CFrame.new(0, 12, 0), rgb(240, 240, 250), METAL)
		local knob = ball(12, jb * CFrame.new(0, 24, 0), rgb(255, 90, 120), NEON)
		knob.CastShadow = false
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2
			local btn = cyl(7, 2.4, jb * CFrame.new(math.cos(a) * 9, 3, math.sin(a) * 9), K.NEONS[k + 1], NEON)
			btn.CastShadow = false
		end
		-- the front: a huge neon sign, a marquee of chasing bulbs, glass doors
		local fr = f * CFrame.new(0, 0, -AD / 2 - 0.4)
		P(V(AW - 10, 16, 3), fr * CFrame.new(0, 44, -1), rgb(40, 30, 76))
		local sgn = P(V(AW - 22, 12, 0.8), fr * CFrame.new(0, 44, -2.6), rgb(255, 90, 150), NEON)
		sgn.CastShadow = false
		K.textOn(sgn, Enum.NormalId.Front, "SMINSKI ARCADE", Color3.new(1, 1, 1), Vector2.new(1100, 190), 0)
		local sub = P(V(AW - 50, 5, 0.6), fr * CFrame.new(0, 34, -2.4), rgb(90, 230, 255), NEON)
		sub.CastShadow = false
		K.textOn(sub, Enum.NormalId.Front, "RUNS  ·  DOG PARK  ·  SHOPS", rgb(20, 20, 40), Vector2.new(900, 90), 0)
		Build.arcadeBulbs = {}
		for k = 0, 27 do
			local a = k / 28 * math.pi * 2
			local b = ball(2.6, fr * CFrame.new(math.cos(a) * (AW / 2 - 6), 44 + math.sin(a) * 9, -3), rgb(255, 236, 170), NEON)
			b.CastShadow = false
			table.insert(Build.arcadeBulbs, b)
		end
		table.insert(Build.anims, { cx = ex.X, cz = ex.Z, far = true, fn = function(_, t)
			for i, b in Build.arcadeBulbs do
				local on = (i + math.floor(t * 6)) % 3 == 0
				b.Color = on and rgb(255, 240, 180) or rgb(180, 120, 190)
			end
		end })
		-- entrance: a wide canopy, glass doors and a glowing purple foyer
		P(V(70, 3, 26), fr * CFrame.new(0, 26, -13), rgb(120, 90, 210))
		for _, sx in { -1, 1 } do solid(cyl(4, 26, fr * CFrame.new(sx * 30, 13, -24), rgb(252, 246, 226))) end
		local foy = P(V(48, 24, 1), fr * CFrame.new(0, 12, 0.2), rgb(140, 100, 240), NEON)
		foy.CastShadow = false
		for _, sx in { -1, 1 } do
			local g = P(V(22, 22, 0.6), fr * CFrame.new(sx * 12.5, 11, -0.8), rgb(210, 240, 255), SMOOTH)
			g.Transparency = 0.45
			P(V(1.4, 22, 1), fr * CFrame.new(sx * 24, 11, -1), rgb(252, 246, 226))
		end
		P(V(50, 1.6, 1.2), fr * CFrame.new(0, 22.4, -1), rgb(252, 246, 226))
		-- arcade cabinets flanking the doors, a ticket booth, velvet ropes
		for k = -2, 2 do
			if math.abs(k) > 0 then
				local cab = fr * CFrame.new(k * 26, 0, -6)
				P(V(8, 14, 6), cab * CFrame.new(0, 7, 0), K.NEONS[(k + 3) % #K.NEONS + 1])
				local scr = P(V(6, 5, 0.4), cab * CFrame.new(0, 10, -3.2), rgb(150, 240, 255), NEON)
				scr.CastShadow = false
				P(V(7, 1, 3), cab * CFrame.new(0, 6.6, -3.4), Cc.ink)
			end
		end
		for _, sx in { -1, 1 } do
			for k = 0, 2 do
				cyl(2.2, 6, fr * CFrame.new(sx * (14 + k * 9), 3, -20), Cc.gold, METAL)
				ball(2.6, fr * CFrame.new(sx * (14 + k * 9), 6.6, -20), Cc.gold, METAL)
			end
		end
		-- a red carpet up Main St to the doors, with rope lights + palm planters
		P(V(34, 0.16, 90), W(ex.X, 0.12, ex.Z + 40), rgb(226, 80, 96), Enum.Material.Fabric, { noShadow = true })
		P(V(38, 0.1, 94), W(ex.X, 0.08, ex.Z + 40), rgb(250, 214, 110), MATTE, { noShadow = true })
		for k = 0, 4 do
			K.lamp(ex.X - 22, ex.Z + 6 + k * 20)
			K.lamp(ex.X + 22, ex.Z + 6 + k * 20)
			for _, sx in { -1, 1 } do K.planter(W(ex.X + sx * 28, PAD, ex.Z + 14 + k * 20), 4) end
		end
		-- the walk-in doormat (the trigger lives in City.lua)
		P(V(48, 0.2, 10), W(ex.X, 0.14, ex.Z + 2), rgb(120, 90, 210), NEON, { noShadow = true })
		-- bus stop + a car park of convertibles
		local st = W(-40, PAD, sp.Z + 6) * CFrame.Angles(0, math.pi / 2, 0)
		P(V(12, 0.5, 5), st * CFrame.new(0, 9, 0), rgb(120, 170, 220))
		for _, sx in { -5.6, 5.6 } do P(V(0.4, 9, 0.4), st * CFrame.new(sx, 4.5, 2), Cc.lampPost) end
		P(V(12, 7, 0.2), st * CFrame.new(0, 5, 2.2), Cc.pane, K.GLASS, { transparency = 0.5 })
		K.bench(st * CFrame.new(0, 0, 0.8))
		for k = 0, 5 do
			local x = 30 + k * 9
			P(V(0.4, 0.05, 12), W(x - 4.5, 0.22, sp.Z), Cc.line, SMOOTH, { noShadow = true })
			park(W(x, 0.2, sp.Z) * CFrame.Angles(0, math.pi, 0), "convertible", K.CAR_COLORS[k + 1])
		end
		for _, x in { -70, 100 } do K.tree(x, sp.Z + 10, 1.1, 0) end
	end

	---------------------------------------------------------------------------
	-- EVERY BLOCK: sidewalk pad, curbs, lamps, a street sign, corner trees
	---------------------------------------------------------------------------
	local FARM = { pasture = true, orchard = true, fields = true, barn = true, windmills = true, farmmarket = true, camp = true, pumpkins = true, lake = true, sunflowers = true, cows = true, forest = true, restaurantrow = true }
	local function blockBase(cx, cz, kind)
		local w = Places.BLOCK
		walkable(P(V(w, PAD, w), W(cx, PAD / 2, cz), Cc.pave, MATTE, { noShadow = true }))
		-- grass belongs to the farm belt and the park. Everywhere else the block
		-- is paved: in a real downtown there is no spare lawn, every metre is
		-- used (.claude/rules/environment.md)
		local green = FARM[kind] or kind == "park"
		local lawn = FARM[kind] and rgb(176, 208, 120) or (green and Cc.grass2) or rgb(204, 196, 182)
		P(V(w - 28, PAD + 0.04, w - 28), W(cx, PAD / 2 + 0.02, cz), lawn, green and MATTE or Enum.Material.Pavement, { noShadow = true })
		for _, s in { -1, 1 } do
			P(V(w + 0.6, 0.6, 0.6), W(cx, 0.3, cz + s * w / 2), Cc.curb, MATTE, { noShadow = true })
			P(V(0.6, 0.6, w + 0.6), W(cx + s * w / 2, 0.3, cz), Cc.curb, MATTE, { noShadow = true })
		end
		-- sidewalk joints
		for k = -2, 2 do
			for _, s in { -1, 1 } do
				P(V(0.3, 0.02, 13), W(cx + k * 52, PAD + 0.01, cz + s * (HALF_B - 7)), Cc.paveJoint, MATTE, { noShadow = true })
				P(V(13, 0.02, 0.3), W(cx + s * (HALF_B - 7), PAD + 0.01, cz + k * 52), Cc.paveJoint, MATTE, { noShadow = true })
			end
		end
		-- lamps along the kerb
		for _, k in { -85, 0, 85 } do
			K.lamp(cx + k, cz + HALF_B - 3)
			K.lamp(cx + k, cz - HALF_B + 3)
			K.lamp(cx + HALF_B - 3, cz + k)
			K.lamp(cx - HALF_B + 3, cz + k)
		end
		-- street trees in cream-edged pits between the lamps
		for _, k in { -42, 42 } do
			for _, spot in { V(cx + k, 0, cz + HALF_B - 4), V(cx + k, 0, cz - HALF_B + 4), V(cx + HALF_B - 4, 0, cz + k), V(cx - HALF_B + 4, 0, cz + k) } do
				P(V(5, 0.3, 5), W(spot.X, PAD + 0.05, spot.Z), Cc.soil, MATTE, { noShadow = true })
				P(V(5.6, 0.4, 5.6), W(spot.X, PAD + 0.02, spot.Z), Cc.cream, MATTE, { noShadow = true })
				K.treeKind(K.TREE_KINDS[(math.abs(cx) // 150 + math.abs(cz) // 150 * 2 + (cx > 0 and 1 or 0)) % #K.TREE_KINDS + 1], spot.X, spot.Z, 0.72)
			end
		end
		-- street sign on the south-west corner
		local sx, sz = cx - HALF_B + 4, cz - HALF_B + 4
		local base = W(sx, PAD, sz)
		solid(cyl(0.5, 13, base * CFrame.new(0, 6.5, 0), Cc.lampPost, METAL))
		local ns, ew = Places.CityStreetsNS[cx - 150], Places.CityStreetsEW[cz - 150]
		if ns then
			local s = P(V(0.3, 1.6, 9), base * CFrame.new(0, 12, 0), Cc.signGreen)
			K.textOn(s, Enum.NormalId.Right, ns, Cc.cream, Vector2.new(400, 80), 0.5)
			K.textOn(s, Enum.NormalId.Left, ns, Cc.cream, Vector2.new(400, 80), 0.5)
		end
		if ew then
			local s = P(V(9, 1.6, 0.3), base * CFrame.new(0, 13.8, 0), Cc.signGreen)
			K.textOn(s, Enum.NormalId.Front, ew, Cc.cream, Vector2.new(400, 80), 0.5)
			K.textOn(s, Enum.NormalId.Back, ew, Cc.cream, Vector2.new(400, 80), 0.5)
		end
	end

	---------------------------------------------------------------------------
	-- HOMES
	---------------------------------------------------------------------------
	local lots = Places.cityLots()
	local function lotsIn(cx, cz)
		local out = {}
		for _, l in lots do
			if not l.landmark and math.abs(l.pos.X - cx) < HALF_B and math.abs(l.pos.Z - cz) < HALF_B then table.insert(out, l) end
		end
		return out
	end

	function B.house(l, i)
		local f = K.frameOf(l.pos, l.face)
		local w, d, fh = 36, 26, 11
		local col, roof = l.color, l.roof
		local modern = l.style == 1
		solid(P(V(w + 1.2, 1.4, d + 1.2), f * CFrame.new(0, 0.7, 0), shade(col, 0.3)))
		solid(P(V(w, fh * 2, d), f * CFrame.new(0, 1.4 + fh, 0), col))
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do P(V(1.2, fh * 2, 1.2), f * CFrame.new(sx * w / 2, 1.4 + fh, sz * d / 2), Cc.cream) end
		end
		P(V(w + 0.6, 0.8, d + 0.6), f * CFrame.new(0, 1.4 + fh, 0), Cc.cream)
		K.door(f, 0, -d / 2, shade(roof, 0.1))
		P(V(10, 0.6, 4.4), f * CFrame.new(0, 11.2, -d / 2 - 2) * CFrame.Angles(-0.2, 0, 0), roof)
		for _, sx in { -4.4, 4.4 } do P(V(0.7, 11, 0.7), f * CFrame.new(sx, 5.6, -d / 2 - 3.8), Cc.cream) end
		local curtain = tint(roof, 0.45)
		for _, sx in { -1, 1 } do
			K.window(f * CFrame.new(sx * 10.5, 6.4, -d / 2), 6, 5.2, curtain, rgb(200, 140, 100))
			K.window(f * CFrame.new(sx * 10.5, 1.4 + fh + 5.4, -d / 2), 5, 5, curtain)
		end
		K.window(f * CFrame.new(0, 1.4 + fh + 5.4, -d / 2), 4, 5, curtain)
		K.sideWindows(f, w, d, 2, 6.4, fh, curtain)
		for _, sx in { -1, 1 } do K.window(f * CFrame.new(sx * 9, 6.4, d / 2) * CFrame.Angles(0, math.pi, 0), 5, 5, curtain) end
		if modern then
			-- flat roof with a planted roof terrace + glass balustrade
			solid(P(V(w, 1, d), f * CFrame.new(0, 1.9 + fh * 2, 0), shade(col, 0.1)))
			K.cornice(f, w, d, 1.4 + fh * 2, Cc.cream, roof)
			K.flowers(f * CFrame.new(-8, 1.4 + fh * 2 + 1, 6), 12, 3)
			P(V(8, 0.3, 8), f * CFrame.new(8, 1.4 + fh * 2 + 1.2, 4), rgb(200, 146, 96), WOODM)
			local g = P(V(w, 3, 0.3), f * CFrame.new(0, 1.4 + fh * 2 + 3, -d / 2 + 0.5), Cc.pane, K.GLASS, { transparency = 0.5 })
			g.CastShadow = false
		else
			K.gable(f, w, d, 1.4 + fh * 2, 11, roof)
			solid(P(V(3, 10, 3), f * CFrame.new(w / 4 + 2, 1.4 + fh * 2 + 6, d / 4), rgb(214, 140, 120)))
			P(V(3.6, 0.7, 3.6), f * CFrame.new(w / 4 + 2, 1.4 + fh * 2 + 11.2, d / 4), rgb(190, 120, 104))
		end
		-- the front yard: path, picket fence with a gap, mailbox, a tree, flowers
		local yard = -d / 2
		for k = 1, 5 do P(V(4, 0.2, 2.4), f * CFrame.new(0, 0.1, yard - 1.6 - k * 3.6), Cc.stone) end
		local fz = yard - 20.5
		for _, sx in { -1, 1 } do
			local x0, x1 = sx * 3.2, sx * 22
			local len, mid = math.abs(x1 - x0), (x0 + x1) / 2
			P(V(len, 0.5, 0.35), f * CFrame.new(mid, 1.8, fz), Cc.cream)
			P(V(len, 0.5, 0.35), f * CFrame.new(mid, 3.2, fz), Cc.cream)
			for k = 0, math.floor(len / 2) do P(V(1, 4.2, 0.3), f * CFrame.new(x0 + sx * k * 2, 2.1, fz), Cc.cream) end
		end
		local mb = f * CFrame.new(5.4, 0, fz - 0.8)
		P(V(0.5, 3.8, 0.5), mb * CFrame.new(0, 1.9, 0), rgb(150, 110, 80), WOODM)
		local box = P(V(1.8, 1.6, 2.6), mb * CFrame.new(0, 4.4, 0), roof)
		P(V(0.2, 1.1, 0.3), mb * CFrame.new(1, 4.8, 0.7), Cc.red)
		local num = string.match(l.address, "^%d+") or ""
		K.textOn(box, Enum.NormalId.Right, num, Cc.cream, Vector2.new(120, 80))
		K.textOn(box, Enum.NormalId.Left, num, Cc.cream, Vector2.new(120, 80))
		local tp = (f * CFrame.new(-12, 0, yard - 10)).Position - CITY
		K.tree(tp.X, tp.Z, 0.85)
		K.flowers(f * CFrame.new(10, 0, yard - 3), 12, 2.4)
		for _, sx in { -1, 1 } do K.bush(f * CFrame.new(sx * (w / 2 + 2), 0, yard + 3), 1.2) end
		-- a driveway, and every third house has a car you can borrow
		if not l.row then
			P(V(8, 0.1, 20), f * CFrame.new(w / 2 + 6, 0.05, yard - 8), rgb(214, 204, 188))
			if i % 3 == 0 then park(f * CFrame.new(w / 2 + 6, -PAD + 0.2, yard - 6), "convertible") end
		end
		-- the back garden
		K.hedge(f * CFrame.new(0, 0, d / 2 + 16), w + 8)
		if i % 2 == 0 then
			local pool = f * CFrame.new(-6, 0, d / 2 + 8)
			P(V(12, 0.5, 7), pool * CFrame.new(0, 0.25, 0), Cc.stone)
			P(V(10.6, 0.55, 5.6), pool * CFrame.new(0, 0.3, 0), Cc.water, SMOOTH)
		else
			local sw = f * CFrame.new(6, 0, d / 2 + 8)
			for _, sx in { -3, 3 } do P(V(0.5, 7, 0.5), sw * CFrame.new(sx, 3.5, 0), rgb(200, 146, 96), WOODM) end
			P(V(7, 0.5, 0.5), sw * CFrame.new(0, 7, 0), rgb(200, 146, 96), WOODM)
			P(V(2, 0.3, 1), sw * CFrame.new(0, 2.6, 0), Cc.red)
		end
	end

	function B.houses(cx, cz)
		for i, l in lotsIn(cx, cz) do
			if l.kind == "house" or l.kind == "rowhouse" then B.house(l, i) end
		end
		-- the middle of the block: a creek garden (CityDress), or the old
		-- shared green if the dressing module is not loaded
		if Build.courtyard then
			Build.courtyard(cx, cz)
		else
			K.tree(cx - 20, cz - 12, 1.2)
			K.tree(cx + 18, cz + 16, 1.1)
			K.bench(W(cx, PAD, cz) * CFrame.Angles(0, 0.4, 0))
		end
	end

	function B.apartments(cx, cz)
		local apts = {}
		for _, l in lotsIn(cx, cz) do
			if l.kind == "apartment" then table.insert(apts, l) end
		end
		for i, l in apts do
			-- New York style brownstone mid-rise: textured brick, a stoop,
			-- fire escapes, balconies, a water tower on the roof
			local f = K.frameOf(l.pos, l.face)
			local w, d, fh, floors = 50, 34, 12, 11
			local acc = Cc.sage
			local tex = ({ "butter", "cream", "mint", "butter" })[i % 4 + 1]
			local T = K.TEX[tex]
			local H = fh * floors
			-- THE GROUND FLOOR, CARVED ROUND THE DOORWAY. It used to be one
			-- cream slab across the whole footprint, which is why the entrance
			-- could only ever be a door painted onto it. This is a building you
			-- actually go into -- it is the Mochi Brownstones' front door
			-- (CityApts prompts at the lot's own step) -- so the opening is cut
			-- out of the wall and there is a hall behind it. The three pieces
			-- are solid as well: the old slab had no collision at all, so the
			-- ground floor could be walked straight through.
			local gap, nd = 6, 4                 -- half-width, depth of the opening
			local bw = (w + 0.6) / 2 - gap
			for _, sx in { -1, 1 } do
				solid(P(V(bw, 14, d + 0.6), f * CFrame.new(sx * (gap + bw / 2), 7, 0), Cc.cream))
			end
			solid(P(V(gap * 2, 14, d + 0.6 - nd), f * CFrame.new(0, 7, nd / 2), Cc.cream))
			solid(P(V(gap * 2, 3, nd), f * CFrame.new(0, 12.5, -(d + 0.6) / 2 + nd / 2), Cc.cream))
			local body = solid(P(V(w, H - 14, d), f * CFrame.new(0, 14 + (H - 14) / 2, 0), T.col))
			K.texture(body, T.id, 32, 48)
			for _, sx in { -1, 1 } do P(V(1.8, H, 1.8), f * CFrame.new(sx * w / 2, H / 2, -d / 2), Cc.cream) end
			-- the lobby door stands open, with its own hall in the niche above
			K.openDoor(f, 0, -d / 2 - 0.3, acc, true, { recess = nd, mat = false })
			-- THE STOOP. Four steps used to climb to y 3.2 -- ABOVE the door's
			-- own sill, so the doorway was hidden behind its own stairs, and the
			-- door cannot be raised to meet them because the entrance canopy at
			-- y 11 caps the surround at 10.6. So it is a low landing at the
			-- door's level instead, one kerb high (0.45, the same step a kerb
			-- is), walkable, and carried through the niche so you do not step
			-- up onto it and back down into the lobby.
			walkable(P(V(gap * 2, 0.45, nd + 0.2), f * CFrame.new(0, 0.225, -(d + 0.6) / 2 + nd / 2), Cc.stone))
			walkable(P(V(14, 0.45, 5), f * CFrame.new(0, 0.225, -d / 2 - 2.6), Cc.stone))
			walkable(P(V(16, 0.22, 2), f * CFrame.new(0, 0.11, -d / 2 - 6), Cc.stone))
			-- the green mat goes on the landing, not on the pavement below it
			K.threshold(f * CFrame.new(0, 0.47, -d / 2 - 3), 12, 4)
			P(V(14, 0.7, 6), f * CFrame.new(0, 11, -d / 2 - 3), acc)
			K.sign(f * CFrame.new(0, 12.4, -d / 2 - 6), 12, 2, Cc.cream, acc, "SMINSKI FLATS")
			for _, sx in { -1, 1 } do K.window(f * CFrame.new(sx * 15, 6, -d / 2 - 0.3), 8, 6, nil, rgb(200, 150, 110), true) end
			for k = 2, floors - 1, 2 do
				for _, sx in { -1, 1 } do
					local bc = f * CFrame.new(sx * 12, k * fh + 0.3, -d / 2 - 2)
					P(V(10, 0.6, 4), bc, Cc.cream)
					P(V(10, 0.35, 0.35), bc * CFrame.new(0, 3, -1.9), acc)
					for q = 0, 4 do P(V(0.3, 2.8, 0.3), bc * CFrame.new(-4.8 + q * 2.4, 1.5, -1.9), acc) end
					blob(V(1.8, 2, 1.8), bc * CFrame.new(sx * 3.6, 1.3, 0.6), Cc.leaf)
				end
			end
			K.fireEscape(f * CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), floors - 1, fh)
			solid(P(V(w, 1, d), f * CFrame.new(0, H + 0.5, 0), T.col))
			K.cornice(f, w, d, H, Cc.cream, acc)
			K.waterTower(f * CFrame.new(-12, H + 1, 6), 1.2)
			K.flowers(f * CFrame.new(10, H + 1, 6), 12, 3)
		end
		-- courtyard playground
		local c = W(cx, PAD, cz)
		P(V(50, 0.2, 50), c * CFrame.new(0, 0.1, 0), rgb(230, 200, 150))
		for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do P(V(0.6, 8, 0.6), c * CFrame.new(-10 + sx * 2, 4, sz * 2), rgb(120, 170, 220)) end end
		P(V(5, 0.6, 5), c * CFrame.new(-10, 8, 0), rgb(255, 216, 110))
		P(V(4, 0.4, 12), c * CFrame.new(-10, 4.4, -8.4) * CFrame.Angles(-0.62, 0, 0), Cc.red)
		ball(10, c * CFrame.new(10, 0, 0), rgb(150, 206, 250), MATTE, { transparency = 0.2 })
		K.tree(cx - 20, cz + 20, 1)
		K.tree(cx + 20, cz - 20, 1)
	end

	function B.school(cx, cz)
		local f = K.frameOf(V(cx, 0, cz + 20), math.pi)
		local w, d, fh = 150, 44, 12
		local col = rgb(250, 232, 164)
		local H = fh * 2 + 1
		solid(P(V(w, H, d), f * CFrame.new(0, H / 2, 0), col))
		P(V(w + 0.6, 1.4, d + 0.6), f * CFrame.new(0, 0.7, 0), Cc.sage)
		P(V(w + 0.6, 0.8, d + 0.6), f * CFrame.new(0, 1 + fh, 0), Cc.cream)
		for _, sx in { -1, 1 } do
			for k = 0, 6 do
				for fl = 0, 1 do K.window(f * CFrame.new(sx * (18 + k * 8.5), 6.5 + fl * fh, -d / 2), 5, 5.6) end
			end
		end
		solid(P(V(w, 1, d), f * CFrame.new(0, H + 0.5, 0), shade(col, 0.1)))
		K.cornice(f, w, d, H, Cc.cream, Cc.sage)
		local bay = f * CFrame.new(0, 0, -d / 2 - 3)
		solid(P(V(24, H + 8, 6), bay * CFrame.new(0, (H + 8) / 2, 0), col))
		K.door(f, 0, -d / 2 - 6.1, rgb(120, 170, 220), true)
		K.sign(bay * CFrame.new(0, 14, -3.2), 18, 3, rgb(120, 170, 220), Cc.cream, "SMINSKI SCHOOL")
		local tw = f * CFrame.new(0, H + 8, -d / 2 + 2)
		solid(P(V(12, 10, 12), tw * CFrame.new(0, 5, 0), col))
		for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do P(V(1, 8, 1), tw * CFrame.new(sx * 4.8, 14, sz * 4.8), Cc.cream) end end
		ball(4, tw * CFrame.new(0, 13.6, 0), Cc.gold, METAL)
		P(V(16, 1, 15), tw * CFrame.new(0, 18.4, 0), Cc.sage)
		for _, sx in { -1, 1 } do P(V(1, 5, 15), tw * CFrame.new(sx * 3.9, 21.4, 0) * CFrame.Angles(0, -sx * math.pi / 2, 0), Cc.sage, MATTE, { class = "WedgePart" }) end
		cyl(7, 0.4, tw * CFrame.new(0, 5.4, -6.2) * CFrame.Angles(math.pi / 2, 0, 0), Cc.cream)
		P(V(0.35, 2.2, 0.2), tw * CFrame.new(0, 6.2, -6.5), Cc.ink)
		P(V(1.8, 0.35, 0.2), tw * CFrame.new(0.7, 5.4, -6.5), Cc.ink)
		-- the playing field behind (with goals) + the school bus
		local fld = W(cx, PAD, cz + 80)
		P(V(120, 0.1, 60), fld * CFrame.new(0, 0.06, 0), rgb(130, 196, 110), MATTE, { noShadow = true })
		for _, x in { -40, 0, 40 } do P(V(0.5, 0.12, 60), fld * CFrame.new(x, 0.08, 0), Cc.cream, MATTE, { noShadow = true }) end
		for _, sx in { -1, 1 } do
			local g = fld * CFrame.new(sx * 56, 0, 0)
			for _, sz in { -6, 6 } do P(V(0.6, 7, 0.6), g * CFrame.new(0, 3.5, sz), Cc.cream) end
			P(V(0.6, 0.6, 12.6), g * CFrame.new(0, 7, 0), Cc.cream)
		end
		K.bus(W(cx + 90, PAD, cz - 60), nil, "SCHOOL BUS")
		K.tree(cx - 100, cz - 90, 1.1)
		K.tree(cx + 100, cz + 100, 1.1)
	end

	function B.park(cx, cz)
		local c = W(cx, PAD, cz)
		-- THE PLAZA from the owner's inventory (Colima City Park), when it is
		-- in: a diagonal paved star, a lawn, twenty palms and seven trees, at
		-- 0.85 so its 263 studs fit a 260 block. It was MEASURED: the largest
		-- clear discs in it are r=39 at its two south corners, so the pond
		-- (shrunk to 60 across) takes the south-west one and the gazebo the
		-- south-east; everything else in the park keys off those two points
		-- (CityHangouts reads Build.parkGazebo). Its 46 lamp posts were
		-- dropped at curation -- K.lamp stands at a third of their spots and
		-- joins the night light pool instead of carrying 46 lights.
		local plaza = K.place("Plaza", c, { scale = 0.85, sink = 0.22 })
		local pondAt, gazeboAt, pondR = V(40, 0, -40), V(-50, 0, 50), 42
		if plaza then
			pondAt, gazeboAt, pondR = V(-85, 0, -85), V(85, 0, -85), 31
			local spots = plaza:GetAttribute("LampSpots")
			if type(spots) == "string" then
				local k = 0
				for x, z in string.gmatch(spots, "(-?%d+),(-?%d+)") do
					k += 1
					if k % 4 == 1 then K.lamp(cx + tonumber(x) * 0.85, cz + tonumber(z) * 0.85) end
				end
			end
		else
			P(V(200, 0.08, 8), c * CFrame.new(0, 0.06, 0), Cc.pave)
			P(V(8, 0.08, 200), c * CFrame.new(0, 0.06, 0), Cc.pave)
		end
		Build.parkGazebo = V(cx + gazeboAt.X, 0, cz + gazeboAt.Z)
		local pc = c * CFrame.new(pondAt.X, 0, pondAt.Z)
		cyl(pondR * 2 + 4, 0.3, pc * CFrame.new(0, 0.12, 0), Cc.stone)
		cyl(pondR * 2, 0.35, pc * CFrame.new(0, 0.16, 0), Cc.water, SMOOTH)
		-- an island with a willow and a wooden bridge
		cyl(22, 1.2, pc * CFrame.new(8, 0.4, 8), Cc.grass2)
		K.tree((pc.Position - CITY).X + 8, (pc.Position - CITY).Z + 8, 1.2, PAD + 1)
		for k = 0, 9 do
			local z = -(pondR - 10) + k * 3
			P(V(6, 0.4, 2.8), pc * CFrame.new(8, 1 + math.sin(k / 9 * math.pi) * 1.6, z), k % 2 == 0 and rgb(214, 170, 120) or rgb(190, 146, 100), WOODM)
		end
		local ducks = {}
		for k = 1, 6 do
			local dk = { a = k * 1.1, r = (pondR - 20) + (k % 3) * 6, sp = 0.12 + k * 0.03, c = pc }
			dk.p = { ball(1.8, pc, rgb(255, 230, 110)), ball(1.2, pc, rgb(255, 230, 110)), P(V(0.5, 0.3, 0.8), pc, rgb(255, 160, 80)) }
			table.insert(ducks, dk)
		end
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(dt, t)
			for _, dk in ducks do
				dk.a += dk.sp * dt
				local p = dk.c * CFrame.new(math.cos(dk.a) * dk.r, 0.6, math.sin(dk.a) * dk.r) * CFrame.Angles(0, -dk.a, 0)
				dk.p[1].CFrame = p * CFrame.new(0, 0.5 + math.sin(t * 2 + dk.r) * 0.1, 0)
				dk.p[2].CFrame = p * CFrame.new(0, 1.5, -0.7)
				dk.p[3].CFrame = p * CFrame.new(0, 1.4, -1.5)
			end
		end })
		-- gazebo
		local gz = c * CFrame.new(gazeboAt.X, 0, gazeboAt.Z)
		solid(cyl(22, 1.2, gz * CFrame.new(0, 0.6, 0), Cc.cream))
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			if k ~= 4 then solid(cyl(1, 11, gz * CFrame.new(math.cos(a) * 9.5, 6.7, math.sin(a) * 9.5), Cc.cream)) end
		end
		for k = 0, 4 do cyl(25 - k * 5, 1.4, gz * CFrame.new(0, 12.6 + k * 1.2, 0), k % 2 == 0 and Cc.sage or Cc.cream) end
		ball(2, gz * CFrame.new(0, 19.2, 0), Cc.gold, METAL)
		K.sign(c * CFrame.new(plaza and 0 or -60, 4, plaza and -112 or -104), 20, 3.6, Cc.signGreen, Cc.cream, "BUTTON PARK")
		if not plaza then
			for _, p in { V(-90, 0, -80), V(-86, 0, 86), V(92, 0, 84), V(90, 0, 30), V(-30, 0, -90), V(20, 0, 94), V(-96, 0, 10), V(60, 0, 60) } do
				K.tree(cx + p.X, cz + p.Z, 1.1)
			end
			K.flowers(c * CFrame.new(-30, 0, -20), 20, 4)
			K.flowers(c * CFrame.new(-30, 0, 20), 20, 4)
		end
		local br = pondR + 6
		for _, a in { 0.3, 1.8, 3.4, 4.9 } do
			K.bench(pc * CFrame.new(math.cos(a) * br, 0, math.sin(a) * br) * CFrame.Angles(0, -a - math.pi / 2, 0))
		end
	end

	function B.pool(cx, cz)
		local c = W(cx, PAD, cz - 30)
		P(V(110, 0.6, 60), c * CFrame.new(0, 0.3, 0), rgb(244, 238, 226))
		P(V(96, 0.7, 44), c * CFrame.new(0, 0.36, 0), Cc.water, SMOOTH)
		for k = 1, 5 do P(V(96, 0.72, 0.4), c * CFrame.new(0, 0.38, -22 + k * 7.3), Cc.cream) end
		-- slide + lifeguard chair + loungers + umbrellas
		local sl = c * CFrame.new(54, 0, 18)
		P(V(5, 12, 5), sl * CFrame.new(0, 6, 0), rgb(120, 170, 220))
		P(V(4, 0.6, 20), sl * CFrame.new(-8, 6, -4) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0.5, 0, 0), rgb(255, 150, 190))
		local lg = c * CFrame.new(-54, 0, 0)
		for _, sx in { -1.4, 1.4 } do P(V(0.5, 9, 0.5), lg * CFrame.new(sx, 4.5, 0), Cc.cream) end
		P(V(3.6, 0.5, 3), lg * CFrame.new(0, 9, 0), Cc.red)
		for k = 0, 5 do
			local lc = c * CFrame.new(-40 + k * 16, 0, 36)
			P(V(3, 1, 7), lc * CFrame.new(0, 1, 0) * CFrame.Angles(-0.1, 0, 0), K.FLOWER_COLS[k % 5 + 1])
			if k % 2 == 0 then
				P(V(0.3, 8, 0.3), lc * CFrame.new(4, 4, 0), Cc.cream)
				cyl(9, 0.5, lc * CFrame.new(4, 8, 0), k % 4 == 0 and rgb(255, 150, 150) or rgb(150, 206, 250))
			end
		end
		K.sign(W(cx, PAD + 6, cz - 66), 18, 3, rgb(120, 170, 220), Cc.cream, "SPLASH POOL")
		-- tennis court
		local tc = W(cx, PAD, cz + 60)
		P(V(80, 0.1, 40), tc * CFrame.new(0, 0.06, 0), rgb(120, 170, 140), MATTE, { noShadow = true })
		P(V(0.4, 0.12, 40), tc * CFrame.new(0, 0.08, 0), Cc.cream, MATTE, { noShadow = true })
		P(V(0.4, 3, 40), tc * CFrame.new(0, 1.5, 0), Cc.cream, MATTE, { transparency = 0.4 })
		for _, x in { -80, 80 } do K.tree(cx + x, cz + 60, 1.1) end
	end

	---------------------------------------------------------------------------
	-- DOWNTOWN
	---------------------------------------------------------------------------
	function B.cityhall(cx, cz)
		local f = K.frameOf(V(cx, 0, cz - 30), 0)
		local w, d, h = 150, 70, 30
		local col = rgb(250, 244, 230)
		solid(P(V(w + 6, 3, d + 6), f * CFrame.new(0, 1.5, 0), Cc.stone))
		solid(P(V(w, h, d), f * CFrame.new(0, h / 2 + 3, 0), col))
		for k = 0, 3 do walkable(P(V(60 - k * 3, 0.8, 4), f * CFrame.new(0, 0.4 + k * 0.8, -d / 2 - 20 + k * 3.4), Cc.stone)) end
		P(V(64, 1.6, 14), f * CFrame.new(0, 2.4, -d / 2 - 7), Cc.stone)
		for k = 0, 7 do
			local c = f * CFrame.new(-28 + k * 8, 0, -d / 2 - 12)
			cyl(3.4, 22, c * CFrame.new(0, 14, 0), Cc.cream)
			P(V(4.6, 1.4, 4.6), c * CFrame.new(0, 3.7, 0), Cc.stone)
			P(V(4.6, 1.4, 4.6), c * CFrame.new(0, 25.6, 0), Cc.stone)
		end
		P(V(64, 3, 16), f * CFrame.new(0, 27.8, -d / 2 - 6.5), Cc.cream)
		local fr = P(V(40, 2.6, 0.4), f * CFrame.new(0, 27.8, -d / 2 - 14.7), Cc.cream)
		K.textOn(fr, Enum.NormalId.Front, "CITY HALL", rgb(120, 104, 90), Vector2.new(700, 70), 0.6)
		for _, sx in { -1, 1 } do
			P(V(1, 9, 32), f * CFrame.new(sx * 16, 33.8, -d / 2 - 14.5) * CFrame.Angles(0, -sx * math.pi / 2, 0), Cc.cream, MATTE, { class = "WedgePart" })
		end
		K.door(f, 0, -d / 2, rgb(150, 110, 80), true)
		for _, sx in { -1, 1 } do
			for _, x in { 40, 52, 64 } do
				K.window(f * CFrame.new(sx * x, 11, -d / 2), 5, 8)
				K.window(f * CFrame.new(sx * x, 24, -d / 2), 5, 6)
			end
		end
		K.flatRoof(f, w, d, h + 3, rgb(236, 228, 214))
		-- the dome, drum colonnade, clock + gold finial
		local dc = f * CFrame.new(0, h + 4, 4)
		cyl(26, 9, dc * CFrame.new(0, 4.5, 0), Cc.cream)
		for k = 0, 15 do
			local a = k / 16 * math.pi * 2
			cyl(1.4, 9, dc * CFrame.new(math.cos(a) * 13, 4.5, math.sin(a) * 13), rgb(236, 228, 214))
		end
		ball(25, dc * CFrame.new(0, 10, 0), rgb(150, 206, 190))
		cyl(3, 4, dc * CFrame.new(0, 23, 0), Cc.cream)
		ball(2.6, dc * CFrame.new(0, 26, 0), Cc.gold, METAL)
		cyl(9, 0.6, dc * CFrame.new(0, 5, -13.3) * CFrame.Angles(math.pi / 2, 0, 0), Cc.cream)
		cyl(10, 0.5, dc * CFrame.new(0, 5, -13.1) * CFrame.Angles(math.pi / 2, 0, 0), Cc.gold)
		Build.clock = { cf = dc * CFrame.new(0, 5, -13.75), hands = { P(V(0.5, 2.8, 0.25), dc, Cc.ink), P(V(0.4, 3.8, 0.25), dc, Cc.ink) } }
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function()
			local lt = os.date("*t")
			local hA = ((lt.hour % 12) + lt.min / 60) / 12 * math.pi * 2
			local mA = lt.min / 60 * math.pi * 2
			Build.clock.hands[1].CFrame = Build.clock.cf * CFrame.Angles(0, 0, -hA) * CFrame.new(0, 1.2, 0)
			Build.clock.hands[2].CFrame = Build.clock.cf * CFrame.Angles(0, 0, -mA) * CFrame.new(0, 1.7, -0.05)
		end })
		-- grand plaza with a fountain towards Central Blvd
		local pz = W(cx, PAD, cz + 60)
		P(V(110, 0.12, 80), pz * CFrame.new(0, 0.06, 0), Cc.pave, MATTE, { noShadow = true })
		solid(cyl(34, 2.4, pz * CFrame.new(0, 1.2, 0), Cc.stone))
		cyl(31, 2.5, pz * CFrame.new(0, 1.3, 0), Cc.water, SMOOTH)
		cyl(4, 8, pz * CFrame.new(0, 4, 0), Cc.stone)
		cyl(14, 1.2, pz * CFrame.new(0, 8, 0), Cc.stone)
		cyl(12.4, 1.25, pz * CFrame.new(0, 8.1, 0), Cc.water, SMOOTH)
		local rig = Models.buildSminski(K.cur, 1.6, Config.Character("Glow"), false, "crown")
		Models.poseSminski(rig, pz * CFrame.new(0, 8.8, 0), "cheer", 0)
		local drops = {}
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			local dp = ball(1, pz, tint(Cc.water, 0.4), SMOOTH)
			dp.Transparency = 0.2
			table.insert(drops, { p = dp, a = a })
		end
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t)
			for _, dp in drops do
				local k = (t * 0.7 + dp.a) % 1
				dp.p.CFrame = pz * CFrame.new(math.cos(dp.a) * (2 + k * 7), 10 + math.sin(k * math.pi) * 4 - k * 4, math.sin(dp.a) * (2 + k * 7))
			end
		end })
		for _, sx in { -1, 1 } do
			local fp = W(cx + sx * 48, PAD, cz + 90)
			cyl(0.6, 30, fp * CFrame.new(0, 15, 0), rgb(220, 220, 228), METAL)
			ball(1.2, fp * CFrame.new(0, 30.5, 0), Cc.gold, METAL)
			P(V(0.2, 4.6, 7.4), fp * CFrame.new(0, 27, -3.9), sx < 0 and rgb(150, 206, 190) or rgb(255, 180, 200))
			for _, dz in { -30, 30 } do K.tree(cx + sx * 50, cz + 60 + dz, 1.1) end
			for _, dz in { -18, 18 } do K.bench(pz * CFrame.new(sx * 30, 0, dz) * CFrame.Angles(0, sx * math.pi / 2, 0)) end
			K.flowers(pz * CFrame.new(sx * 30, 0, 0), 6, 14)
		end
		worker("read", pz * CFrame.new(30, 0, 18) * CFrame.Angles(0, math.pi / 2, 0), 6)
		K.skyscraper({ x = cx - 90, z = cz - 92, w = 60, d = 44, h = 210, tex = "pink", crown = "water", face = 0, neon = "MALL" })
		K.skyscraper({ x = cx + 90, z = cz - 92, w = 60, d = 44, h = 250, tex = "blue", crown = "spire", face = 0 })
		-- Times Square south corner: a billboard on legs
		local bcf = CFrame.lookAt(CITY + V(cx + 100, PAD + 30, cz + 100), CITY + V(0, PAD + 30, 0))
		for _, sx in { -18, 18 } do P(V(1.6, 30, 1.6), bcf * CFrame.new(sx, -15, 1.4), Cc.lampPost, METAL) end
		K.billboard(bcf * CFrame.new(0, 6, 0), 44, 25, K.BILLBOARDS[3])
	end

	function B.postbank(cx, cz)
		-- post office (the parcel depot): cream + mint, a hanging signboard,
		-- a butter-yellow mailbox, as in the key art
		local f = K.frameOf(V(cx - 40, 0, cz + 86), 0)
		local w, d, h = 90, 50, 30
		local sage, mint = Cc.sage, Cc.mint
		solid(P(V(w, h, d), f * CFrame.new(0, h / 2, 0), Cc.cream))
		P(V(w + 0.6, 12, d + 0.6), f * CFrame.new(0, h - 6, 0), mint) -- the green top floor
		P(V(w + 0.9, 2, d + 0.9), f * CFrame.new(0, 1, 0), sage)
		for _, sx in { -1, 1 } do P(V(2.6, h, 2.6), f * CFrame.new(sx * (w / 2 - 0.4), h / 2, -d / 2 - 0.3), Cc.cream) end
		K.door(f, 0, -d / 2 - 0.2, sage, true)
		for _, sx in { -1, 1 } do
			for _, x in { 16, 32 } do
				K.window(f * CFrame.new(sx * x, 7.4, -d / 2 - 0.2), 8, 7.4, nil, nil, true)
				K.window(f * CFrame.new(sx * x, h - 6, -d / 2 - 0.2), 6, 5.4)
			end
		end
		K.window(f * CFrame.new(0, h - 6, -d / 2 - 0.2), 6, 5.4)
		K.cornice(f, w, d, h, Cc.cream, sage)
		-- the hanging signboard on a bracket
		local sb = f * CFrame.new(0, 15.4, -d / 2 - 1)
		P(V(34, 7.6, 1), sb, sage)
		local sboard = P(V(32, 6.2, 0.6), sb * CFrame.new(0, 0, -0.5), Cc.cream)
		K.textOn(sboard, Enum.NormalId.Front, "SMINSKI POST OFFICE", sage, Vector2.new(820, 150), 0.4)
		local hang = f * CFrame.new(-w / 2 - 1, 11, -d / 2 - 5) * CFrame.Angles(0, math.pi / 2, 0)
		P(V(0.6, 0.6, 9), f * CFrame.new(-w / 2 + 3, 16, -d / 2 - 4.6), Cc.lampPost, METAL)
		local hs = P(V(8, 6, 0.6), hang * CFrame.new(0, 0, 0), Cc.cream)
		K.textOn(hs, Enum.NormalId.Front, "POST", sage, Vector2.new(240, 180), 0.5)
		K.textOn(hs, Enum.NormalId.Back, "POST", sage, Vector2.new(240, 180), 0.5)
		-- butter-yellow mailboxes with rounded tops
		for _, sx in { -w / 2 - 3, -w / 2 + 3.5 } do
			local pb = f * CFrame.new(sx, 0, -d / 2 - 6)
			P(V(3.4, 4.6, 3), pb * CFrame.new(0, 2.8, 0), Cc.butter)
			cyl(3.4, 3, pb * CFrame.new(0, 5.1, 0) * CFrame.Angles(math.pi / 2, 0, 0), Cc.butter)
			P(V(2, 0.35, 0.3), pb * CFrame.new(0, 4.4, -1.55), Cc.ink)
			P(V(1.2, 0.5, 1.2), pb * CFrame.new(0, 0.25, 0), Cc.lampPost)
		end
		for _, sx in { -1, 1 } do K.planter(f * CFrame.new(sx * 10, 0, -d / 2 - 4), 3.4) end
		worker("sweep", f * CFrame.new(24, 0, -d / 2 - 12) * CFrame.Angles(0, math.pi + 0.4, 0), 2)
		-- the counter pad out front (where parcels are picked up)
		local dp = W(Places.CityDepot.X, PAD, Places.CityDepot.Z)
		cyl(12, 0.2, dp * CFrame.new(0, 0.1, 0), rgb(255, 214, 110), NEON, { transparency = 0.5 })
		for k = 0, 2 do
			local bx = P(V(3, 2.4, 3), dp * CFrame.new(-8, 1.2 + k * 2.4, 4) * CFrame.Angles(0, k * 0.5, 0), rgb(214, 170, 120))
			P(V(3.05, 0.4, 3.05), bx.CFrame, rgb(250, 240, 214))
		end
		-- the bank
		local bf = K.frameOf(V(cx + 60, 0, cz + 84), 0)
		local bw, bd, bh = 70, 50, 26
		solid(P(V(bw, bh, bd), bf * CFrame.new(0, bh / 2 + 2, 0), rgb(250, 238, 184)))
		solid(P(V(bw + 4, 2, bd + 4), bf * CFrame.new(0, 1, 0), Cc.stone))
		for k = 0, 5 do cyl(2.6, 20, bf * CFrame.new(-20 + k * 8, 12, -bd / 2 - 3), Cc.cream) end
		P(V(50, 3, 7), bf * CFrame.new(0, 23.5, -bd / 2 - 3), Cc.cream)
		K.sign(bf * CFrame.new(0, 23.5, -bd / 2 - 6.6), 30, 2.6, Cc.sage, Cc.cream, "SMINSKI BANK")
		K.door(bf, 0, -bd / 2, rgb(150, 110, 80), true)
		K.flatRoof(bf, bw, bd, bh + 2, rgb(236, 228, 214))
		-- taxi stand on Main St with a row of cabs
		local ts = W(Places.CityTaxiStand.X + 6, PAD, Places.CityTaxiStand.Z)
		P(V(5, 0.5, 14), ts * CFrame.new(0, 9, 0), rgb(255, 214, 90))
		for _, sz in { -6, 6 } do P(V(0.4, 9, 0.4), ts * CFrame.new(2, 4.5, sz), Cc.ink) end
		K.sign(ts * CFrame.new(0, 11.2, 0) * CFrame.Angles(0, -math.pi / 2, 0), 12, 2, Cc.ink, rgb(255, 214, 90), "TAXI")
		K.bench(ts * CFrame.new(2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
		for k = 0, 2 do park(W(cx - 105, 0.2 + PAD, cz + 20 + k * 14) * CFrame.Angles(0, math.pi / 2, 0), "taxi") end
		K.skyscraper({ x = cx - 70, z = cz - 70, w = 70, d = 70, h = 320, tex = "lav", crown = "deco", name = "POST TOWER", face = 0, neon = "POST" })
		K.skyscraper({ x = cx + 75, z = cz - 75, w = 60, d = 60, h = 200, tex = "teal", crown = "garden", face = 0 })
		local bcf = CFrame.lookAt(CITY + V(cx - 100, PAD + 30, cz + 100), CITY + V(0, PAD + 30, 0))
		for _, sx in { -18, 18 } do P(V(1.6, 30, 1.6), bcf * CFrame.new(sx, -15, 1.4), Cc.lampPost, METAL) end
		K.billboard(bcf * CFrame.new(0, 6, 0), 44, 25, K.BILLBOARDS[4])
	end

	-- a glass tower with mullions, floor bands, a lobby and a crown
	function B.tower(pos, w, d, h, glass, name, spire)
		local f = K.frameOf(pos, 0)
		solid(P(V(w, h, d), f * CFrame.new(0, h / 2, 0), glass, SMOOTH)).Reflectance = 0.15
		local n = math.floor(w / 8)
		for _, side in { { 0, -d / 2, w }, { math.pi, d / 2, w }, { math.pi / 2, 0, d }, { -math.pi / 2, 0, d } } do
			local face = f * CFrame.Angles(0, side[1], 0) * CFrame.new(0, 0, -(side[1] == 0 and d / 2 or side[1] == math.pi and d / 2 or w / 2) - 0.2)
			local fw = side[3]
			local m = math.floor(fw / 8)
			for k = 0, m do P(V(0.8, h - 12, 0.6), face * CFrame.new(-fw / 2 + k * fw / m, (h - 12) / 2 + 12, 0), Cc.cream) end
		end
		for y = 24, h - 6, 12 do P(V(w + 1, 0.8, d + 1), f * CFrame.new(0, y, 0), Cc.cream) end
		-- lobby
		P(V(w + 1.2, 12, d + 1.2), f * CFrame.new(0, 6, 0), rgb(236, 230, 220))
		K.glassBand(f * CFrame.new(0, 6, -d / 2 - 0.7), w - 12, 9, rgb(200, 230, 246), 5)
		K.door(f, 0, -d / 2 - 0.9, rgb(120, 110, 100), true)
		P(V(w * 0.6, 0.8, 8), f * CFrame.new(0, 12.4, -d / 2 - 4), Cc.ink)
		if name then K.sign(f * CFrame.new(0, 14.6, -d / 2 - 1), math.min(w - 6, #name * 2.2 + 6), 3, Cc.ink, Cc.cream, name) end
		-- crown
		P(V(w - 6, 6, d - 6), f * CFrame.new(0, h + 3, 0), Cc.cream)
		P(V(w - 14, 4, d - 14), f * CFrame.new(0, h + 8, 0), shade(glass, 0.1), SMOOTH)
		if spire then
			cyl(1.2, 40, f * CFrame.new(0, h + 30, 0), rgb(220, 220, 228), METAL)
			local b = ball(2.4, f * CFrame.new(0, h + 51, 0), Cc.red, NEON)
			table.insert(Build.anims, { cx = pos.X, cz = pos.Z, far = true, fn = function(_, t) b.Transparency = (t % 2 < 1) and 0 or 0.8 end })
		end
	end

	-- MIDTOWN: blocks packed with pastel skyscrapers, New York style
	local function sx0(v) return v > 0 and 1 or -1 end
	---------------------------------------------------------------------------
	-- WALK-IN VENUES: cafes, bakeries, noodle bars, delis. A real room at
	-- street level -- no teleport, you just walk in off the pavement -- with a
	-- counter to order at, stools to sit on and a couple of regulars already
	-- eating. Deliberately lightweight: no job, no stock, no economy. The
	-- point is that the city's doors open. CityVenues.lua runs the
	-- interactions; this only builds the room and registers what is in it.
	---------------------------------------------------------------------------
	Build.venues = {}
	---------------------------------------------------------------------------
	-- THE DRAWING CONTEXT FOR A STREET ROOM.
	--
	-- K.furn's pieces register their interactions in CityApts' shape, because
	-- that is where the furniture came from: `act.sit` is the CFrame to sit
	-- at. CityVenues.use reads the seat off `sp.seat` instead and treats
	-- `act.sit` as a boolean. Rather than teach either module about the other,
	-- the translation happens once, here, on the way in.
	--
	-- Note also that a venue spot's `pos` is CITY-RELATIVE (CityVenues
	-- compares it against the player's city-space position), which K.furnCtx
	-- does not know -- it stores world space. A street room must use this
	-- context, not K.furnCtx, or every prompt it registers sits 1500 studs
	-- from where the furniture is and never fires.
	--
	-- Pass `spots = nil` for a piece whose interaction you do NOT want, e.g. a
	-- banquette in a food room: CityVenues.order indexes v.tables by the
	-- seat's `table` field, and a spot-seat has no table to index.
	---------------------------------------------------------------------------
	local function venueCtx(spots)
		return {
			P = P,
			solid = solid,
			spot = spots and function(cf, title, sub, btn, icon, act)
				act = act or {}
				local seat = (typeof(act.sit) == "CFrame") and act.sit or nil
				if seat then
					act = table.clone(act)
					act.sit = true
				end
				table.insert(spots, {
					pos = cf.Position - CITY, title = title, sub = sub,
					btn = btn, icon = icon, act = act, seat = seat,
				})
			end or function() end,
		}
	end
	---------------------------------------------------------------------------
	-- MENUS ARE KEYED BY THE SHOP'S NAME, NOT ITS TYPE.
	--
	-- There were four menus for ten food types, so RAMEN, NOODLES, SUSHI,
	-- PIZZA and DINER -- five different signs over five different streets --
	-- all served ramen, gyoza, onigiri and tea (docs/WORLD_REVAMP.md §4.1).
	-- The name was always in the lot table; it was just never asked.
	-- Places' SHOPS and CAFES tables between them put seventeen distinct food
	-- names on the street, so there are seventeen menus here. `btype` remains
	-- the fallback, which is what keeps this safe when a name is added to
	-- Places without a menu being added here.
	---------------------------------------------------------------------------
	local MENUS = {
		cafe = { "LATTE", "MATCHA", "CROISSANT", "COOKIE" },
		bakery = { "MELON PAN", "DONUT", "CREAM PUFF", "TOAST" },
		restaurant = { "RAMEN", "GYOZA", "ONIGIRI", "TEA" },
		deli = { "SANDWICH", "PICKLES", "SOUP", "SODA" },
	}
	local NAMED_MENUS = {
		["CAFE"] = { "LATTE", "FLAT WHITE", "MATCHA", "CROISSANT" },
		["CORNER CAFE"] = { "LATTE", "HOT CHOCOLATE", "TOASTIE", "COOKIE" },
		["TEA HOUSE"] = { "GREEN TEA", "TEA", "MOCHI", "CASTELLA" },
		["MILK BAR"] = { "MILKSHAKE", "MALTED MILK", "EGG CREAM", "COOKIE" },
		["BOBA"] = { "BROWN SUGAR BOBA", "TARO MILK TEA", "MATCHA LATTE", "LYCHEE JELLY" },
		["ICE CREAM"] = { "VANILLA CONE", "STRAWBERRY SCOOP", "MINT CHIP", "SUNDAE" },
		["BAKERY"] = { "MELON PAN", "DONUT", "CREAM PUFF", "TOAST" },
		["DONUT SHOP"] = { "GLAZED RING", "JAM DONUT", "CHOCOLATE RING", "FILTER COFFEE" },
		["DELI"] = { "SANDWICH", "PICKLES", "SOUP", "SODA" },
		["SANDWICH BAR"] = { "CLUB SANDWICH", "SOUP", "CRISPS", "SODA" },
		["RAMEN"] = { "RAMEN", "GYOZA", "EDAMAME", "TEA" },
		["NOODLES"] = { "DAN DAN NOODLES", "SPRING ROLL", "WONTON", "TEA" },
		["NOODLE BAR"] = { "UDON", "TEMPURA", "MISO SOUP", "TEA" },
		["SUSHI"] = { "SALMON NIGIRI", "CUCUMBER ROLL", "ONIGIRI", "MISO SOUP" },
		["PIZZA"] = { "MARGHERITA SLICE", "GARLIC BREAD", "DOUGH BALLS", "SODA" },
		["DINER"] = { "PANCAKE STACK", "CHEESEBURGER", "FRIES", "MILKSHAKE" },
		["CURRY HOUSE"] = { "KATSU CURRY", "NAAN", "MANGO LASSI", "PICKLES" },
	}
	-- which btypes are food at all. This used to be `MENUS[l.btype]`, which
	-- quietly meant "food = there is a menu for it" and would have started
	-- misrouting the moment a named menu existed for a non-food shop.
	local FOODTYPE = { cafe = true, bakery = true, restaurant = true, deli = true }
	local function menuFor(l)
		return NAMED_MENUS[string.upper(l.name or "")] or MENUS[l.btype] or MENUS.cafe
	end
	-- ...and HOW THE ROOM IS LAID OUT, likewise by name. Four arrangements,
	-- because a ramen bar is a row of stools at a counter and a diner is
	-- booths, and no amount of recolouring the same four round tables gets you
	-- from one to the other.
	local FOOD_LAYOUT = {
		["RAMEN"] = "bar", ["NOODLES"] = "bar", ["NOODLE BAR"] = "bar",
		["SUSHI"] = "bar", ["BOBA"] = "bar", ["MILK BAR"] = "bar",
		["DINER"] = "booths", ["DELI"] = "booths", ["SANDWICH BAR"] = "booths",
		["CURRY HOUSE"] = "booths", ["PIZZA"] = "booths",
		["BAKERY"] = "cases", ["DONUT SHOP"] = "cases", ["ICE CREAM"] = "cases",
		["CAFE"] = "tables", ["CORNER CAFE"] = "tables", ["TEA HOUSE"] = "tables",
	}
	local FOOD_LAYOUT_BY_TYPE = { restaurant = "bar", deli = "booths", bakery = "cases", cafe = "tables" }

	-- one round cafe table with two stools. Shared by the `tables` and
	-- `booths` layouts, and the single reason those two are not a copy-paste.
	local function roundTable(tcf, acc, seats, tables, sides)
		cyl(0.6, 3, tcf * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
		solid(cyl(4.4, 0.4, tcf * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH))
		table.insert(tables, tcf * CFrame.new(0, 3.4, 0))
		local ti = #tables
		for _, sz in (sides or { -3, 3 }) do
			local scf = tcf * CFrame.new(0, 0, sz) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0)
			cyl(0.5, 1.8, scf * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
			cyl(2.2, 0.5, scf * CFrame.new(0, 2, 0), acc, SMOOTH)
			table.insert(seats, { cf = scf * CFrame.new(0, 2.2, 0), table = ti })
		end
		return ti
	end

	-- FOOD FIT-OUT: a counter to order at, a menu board, and seating that
	-- belongs to this particular kind of food place.
	local function fitFood(f, w, d, l, i, acc)
		local menu = menuFor(l)
		local layout = FOOD_LAYOUT[string.upper(l.name or "")] or FOOD_LAYOUT_BY_TYPE[l.btype] or "tables"
		-- the counter along the back-right, with a till and a menu board
		local cw = math.min(16, w * 0.42)
		local cf = f * CFrame.new(w / 2 - cw / 2 - 2, 0, d / 2 - 4.2)
		solid(P(V(cw, 3.6, 2.6), cf * CFrame.new(0, 1.8, 0), shade(acc, 0.1), WOODM))
		P(V(cw + 0.6, 0.4, 3.2), cf * CFrame.new(0, 3.8, 0), Cc.cream)
		P(V(1.6, 1.2, 1.4), cf * CFrame.new(cw / 2 - 2, 4.6, 0), Cc.ink, SMOOTH)
		for k = 0, 2 do ball(1.1, cf * CFrame.new(-cw / 2 + 1.6 + k * 1.6, 4.5, 0.2), ({ rgb(236, 190, 130), rgb(250, 214, 170), rgb(214, 150, 110) })[k + 1]) end
		local board = P(V(cw, 3.4, 0.3), f * CFrame.new(w / 2 - cw / 2 - 2, 10, d / 2 - 1.2), Cc.ink)
		K.textOn(board, Enum.NormalId.Front, table.concat(menu, "  ·  "), Cc.cream, Vector2.new(620, 120), 0)
		-- someone behind the counter
		local def = Config.Characters[(i * 3) % #Config.Characters + 1]
		local staff = Models.buildSminski(K.cur, 1, def, false, "chefhat")
		Models.poseSminski(staff, cf * CFrame.new(0, 0, 2.6) * CFrame.Angles(0, math.pi, 0), "idle", i)

		local seats, tables = {}, {}
		local spots = {}
		local ctx = venueCtx(spots)
		-- the left half of the room is the seating; the right half in front of
		-- the counter is kept clear so the queue and the ORDER prompt work.
		local lx = -w / 2 + 2                 -- inside face of the left wall
		local backZ, frontZ = d / 2 - 2, -d / 2 + 2

		if layout == "bar" then
			-- A COUNTER YOU EAT AT. Slurp-shop seating: one long bar down the
			-- left wall, stools facing it, no tables at all. Food is served on
			-- the bar top directly in front of each stool, so `tables` holds
			-- one entry per seat rather than one per group.
			local bl = math.max(10, d - 14)
			local bcf = f * CFrame.new(lx + 3, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
			solid(P(V(bl, 3.9, 3.4), bcf * CFrame.new(0, 1.95, 0), shade(acc, 0.12), WOODM))
			P(V(bl + 0.6, 0.4, 4), bcf * CFrame.new(0, 4.1, 0), Cc.cream, SMOOTH)
			P(V(bl - 1, 0.5, 3.6), bcf * CFrame.new(0, 0.3, 0), shade(acc, 0.24), WOODM)
			local n = math.max(2, math.floor(bl / 5))
			for k = 0, n - 1 do
				local a = -bl / 2 + bl / (n * 2) + k * bl / n
				local scf = bcf * CFrame.new(a, 0, -4.2) * CFrame.Angles(0, math.pi, 0)
				cyl(0.5, 2.2, scf * CFrame.new(0, 1.1, 0), Cc.ink, METAL)
				solid(cyl(2.4, 0.6, scf * CFrame.new(0, 2.4, 0), acc, SMOOTH))
				table.insert(tables, bcf * CFrame.new(a, 4.4, -1.2))
				-- the regular at the end stool: an occupied seat is not offered
				if k == 0 then
					local reg = Models.buildSminski(K.cur, 1, Config.Characters[(i * 5 + 2) % #Config.Characters + 1], false, nil)
					Models.poseSminski(reg, scf * CFrame.new(0, 1.35, 0), "sit", i * 2)
					ball(1, bcf * CFrame.new(a, 4.9, -1.2), rgb(250, 214, 170))
				else
					table.insert(seats, { cf = scf * CFrame.new(0, 2.6, 0), table = #tables })
				end
			end
			-- noren-style strips hung IN the doorway. The doorway is 8 wide
			-- (venueRoom's doorW) and its header runs to y 10.1, so these hang
			-- from just under it, inside the opening, not across the facade.
			for k = 0, 5 do
				P(V(1.3, 3, 0.2), f * CFrame.new(-3.5 + k * 1.4, 8.4, -d / 2 + 1.6), k % 2 == 0 and acc or tint(acc, 0.35), K.FABRIC, { noShadow = true })
			end
			K.furn.pendant(ctx, f * CFrame.new(lx + 3, 0, -d / 4), 14, rgb(240, 150, 120))
		elseif layout == "booths" then
			-- BOOTHS down the left wall: the fixed bench is the wall side, a
			-- stool the aisle side, so you can always get in.
			local bl = math.max(14, d - 10)
			-- no spots from the bench itself: the per-table seats below carry the
			-- `table` index CityVenues.order needs, and a bench spot would not
			K.furn.banquette(venueCtx(nil), f * CFrame.new(lx + 2.4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), bl, tint(acc, 0.15))
			local n = math.max(1, math.floor(bl / 7))
			for k = 0, n - 1 do
				local a = -bl / 2 + bl / (n * 2) + k * bl / n
				local tcf = f * CFrame.new(lx + 8.5, 0, a)
				solid(P(V(5, 0.4, 4.4), tcf * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH))
				cyl(0.6, 3, tcf * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
				table.insert(tables, tcf * CFrame.new(0, 3.4, 0))
				local ti = #tables
				-- the wall bench seat (K.furn.banquette already drew the bench;
				-- this is the seat position that belongs to THIS table)
				table.insert(seats, { cf = f * CFrame.new(lx + 4.6, 2.9, a), table = ti })
				local scf = tcf * CFrame.new(3.4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
				cyl(0.5, 1.8, scf * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
				solid(cyl(2.2, 0.5, scf * CFrame.new(0, 2, 0), acc, SMOOTH))
				table.insert(seats, { cf = scf * CFrame.new(0, 2.2, 0), table = ti })
				-- condiments, so a bare table top is not the last thing you see
				P(V(0.7, 1.2, 0.7), tcf * CFrame.new(1.4, 4, 1.4), Cc.red, SMOOTH, { noShadow = true })
				P(V(0.7, 1.2, 0.7), tcf * CFrame.new(1.4, 4, 0.4), Cc.butter, SMOOTH, { noShadow = true })
			end
			K.furn.clock(ctx, f * CFrame.new(lx + 0.4, 10, backZ - 6) * CFrame.Angles(0, -math.pi / 2, 0), acc)
		elseif layout == "cases" then
			-- A COUNTER SHOP. You do not sit for long in a bakery, so the room
			-- is mostly display: a run of glazed cases you walk past, and two
			-- small tables by the window for whoever does stay.
			local runL = math.max(8, d - 16)
			K.furn.display(ctx, f * CFrame.new(lx + 3, 0, 1) * CFrame.Angles(0, -math.pi / 2, 0), runL,
				shade(acc, 0.12), { tint(acc, 0.3), Cc.butter, rgb(240, 170, 190), Cc.cream })
			K.furn.shelving(ctx, f * CFrame.new(lx + 1.2, 0, backZ - 5) * CFrame.Angles(0, -math.pi / 2, 0), 8,
				{ rgb(226, 188, 140), rgb(244, 216, 170), rgb(214, 150, 110) }, i)
			for k = 0, 1 do
				roundTable(f * CFrame.new(lx + 9 + k * 8, 0, frontZ + 5), acc, seats, tables, { -3, 3 })
			end
			-- a tray of today's bake on the counter, and the A-board inside the
			-- window where a real bakery puts it
			for k = 0, 3 do ball(1.2, cf * CFrame.new(-cw / 2 + 2 + k * 2.4, 4.6, -0.6), ({ rgb(236, 190, 130), rgb(250, 214, 170), rgb(244, 160, 190), rgb(214, 150, 110) })[k + 1]) end
			K.furn.signboard(ctx, f * CFrame.new(w / 2 - 6, 0.5, frontZ + 3), "FRESH\nTODAY", shade(acc, 0.2))
		else
			-- TABLES: the original arrangement, kept because a cafe really is
			-- loose round tables. It is now one of four, not the only one.
			local n = math.max(2, math.floor((w * 0.5) / 8))
			for k = 0, n - 1 do
				local tx = -w / 2 + 6 + k * 8
				local tz = (k % 2 == 0) and -1.5 or (d / 2 - 5.5)
				if d < 20 then tz = -0.5 end
				local ti = roundTable(f * CFrame.new(tx, 0, tz), acc, seats, tables, { -3, 3 })
				if k == 0 then
					-- the regular: take back the seat we just registered
					local taken = table.remove(seats)
					local reg = Models.buildSminski(K.cur, 1, Config.Characters[(i * 5 + 2) % #Config.Characters + 1], false, nil)
					Models.poseSminski(reg, taken.cf * CFrame.new(0, -1.05, 0), "sit", i * 2)
					ball(1, tables[ti] * CFrame.new(0, 0.5, -1), rgb(250, 214, 170))
				end
			end
			K.furn.plant(ctx, f * CFrame.new(lx + 3, 0.5, frontZ + 3), 1)
		end

		return {
			name = l.name, btype = l.btype, menu = menu, layout = layout,
			pos = (f.Position - CITY), door = l.door, radius = math.max(26, d / 2 + 8),
			counter = (cf * CFrame.new(0, 0, -3.4)).Position - CITY,
			counterTop = cf * CFrame.new(-2.4, 4.1, -0.2),
			seats = seats, tables = tables, accent = acc, spots = spots,
		}
	end

	-- SHOP FIT-OUT: shelves of stock, a till with someone behind it, a display
	-- table, and ONE thing to do that suits the shop. Where the game already
	-- has the real thing (outfits, capsules, upgrades) the shop opens it, so
	-- a clothes shop in town is an actual clothes shop; everywhere else it is
	-- a small moment -- read, pet the dog, lift a weight, play a few notes.
	local LINES = {
		-- `browse` is now a LAST RESORT, not the thing 55 rooms say. Every
		-- btype Places can hand out has its own lines below.
		browse = { "ooh, shiny.", "just looking, thanks!", "everything is so tiny and perfect", "one of everything, please" },
		grocery = { "the tomatoes are suspiciously perfect", "two for one on melons", "you squeeze an avocado. it is not ready.", "a bag of everything, please" },
		pharmacy = { "plasters, in every size but yours", "the pharmacist waves", "cough sweets: acquired", "you feel 3% healthier already" },
		bikes = { "she spins the wheel. it ticks beautifully.", "brand new brake pads", "you ring the bell. twice.", "that one's a lovely frame" },
		art = { "so many blues", "you test a pen on the pad. perfect.", "one sketchbook, one regret about the price", "the good paper, obviously" },
		photo = { "say cheese!", "the flash goes off. you blink.", "four tiny photos, one long strip", "that one's going on the fridge" },
		hardware = { "a drawer of screws, sorted by nothing", "you definitely need this. probably.", "the man knows exactly which one", "one washer, 4 coins, 20 minutes" },
		laundry = { "warm socks. the best feeling.", "round and round it goes", "somebody's left a sock behind", "smells like clean laundry in here" },
		tech = { "everything blinks at once", "you press a button. something beeps.", "the demo one is always the fun one", "shiny, and it has a screen" },
		toys = { "so many little faces", "you wind one up and it walks", "the box says AGES 3+. close enough.", "one of each, obviously" },
		clothes = { "the mirror is very flattering", "that one's a bit much. get it.", "soft. very soft.", "everything is your size here" },
		music = { "somebody flips through the crate behind you", "you find a record you've never heard of", "that bassline again", "the good stuff is in the back" },
		books = { "\"The Very Small Adventure\" -- a classic", "\"How To Sit In A Corner\", 3rd edition", "\"Moss: A Love Story\"", "you read a whole chapter. nice." },
		pets = { "who's a good boy? YOU are.", "the puppy licked your hand!", "tail wags all round", "you made a friend" },
		flowers = { "mmm, fresh peonies", "smells like spring", "achoo! ...worth it", "you feel 10% calmer" },
		gym = { "one more rep!", "feel the burn (it is a very small burn)", "gains: acquired", "personal best!" },
		barber = { "just a little off the top", "looking sharp!", "fresh trim, fresh start" },
	}
	local SHOPFIT = {
		books = { spot = "nook", title = "READING NOOK", sub = "pick a book, take a seat", btn = "READ", icon = "star", act = { sit = true, lines = LINES.books } },
		pets = { spot = "pen", title = "PUPPY PEN", sub = "they would like some attention", btn = "PET", icon = "paw", act = { emote = "hug", sound = "Bark", lines = LINES.pets } },
		clothes = { spot = "rack", title = "FITTING ROOM", sub = "your whole wardrobe is here", btn = "TRY ON", icon = "shirt", act = { ui = "outfits" } },
		tailor = { spot = "rack", title = "FITTING ROOM", sub = "your whole wardrobe is here", btn = "TRY ON", icon = "shirt", act = { ui = "outfits" } },
		toys = { spot = "capsule", title = "CAPSULE MACHINE", sub = "what will you get?", btn = "OPEN", icon = "capsule", act = { ui = "capsules" } },
		tech = { spot = "demo", title = "DEMO TABLE", sub = "power-ups and upgrades", btn = "UPGRADE", icon = "bolt", act = { ui = "upgrades" } },
		flowers = { spot = "buckets", title = "FRESH FLOWERS", sub = "stop and smell them", btn = "SMELL", icon = "heart", act = { emote = "cheer", lines = LINES.flowers } },
		music = { spot = "piano", title = "THE SHOP PIANO", sub = "go on, nobody minds", btn = "PLAY", icon = "star", act = { tune = true } },
		gym = { spot = "weights", title = "FREE WEIGHTS", sub = "a quick set", btn = "WORK OUT", icon = "bolt", act = { emote = "yoga", secs = 4, lines = LINES.gym } },
		barber = { spot = "chair", title = "BARBER'S CHAIR", sub = "hop up", btn = "SIT", icon = "heart", act = { sit = true, lines = LINES.barber } },
		-- THE SEVEN THAT FELL THROUGH. grocery, pharmacy, bikes, art, photo,
		-- hardware and laundry had no row here, so every one of them got
		-- DEFAULT_FIT: the same display table, the same BROWSE button, the
		-- same "ooh, shiny." -- across ~55 rooms (docs/WORLD_REVAMP.md §4.2).
		grocery = { spot = "produce", title = "THE FRUIT STAND", sub = "everything is in season here", btn = "PICK ONE", icon = "bag", act = { emote = "cheer", lines = LINES.grocery } },
		pharmacy = { spot = "dispensary", title = "THE COUNTER", sub = "the pharmacist knows your name", btn = "ASK", icon = "heart", act = { lines = LINES.pharmacy } },
		bikes = { spot = "workstand", title = "THE REPAIR STAND", sub = "give the wheel a spin", btn = "SPIN", icon = "bolt", act = { sound = "Pop", lines = LINES.bikes } },
		art = { spot = "easel", title = "THE EASEL", sub = "the paint is still wet", btn = "PAINT", icon = "star", act = { emote = "yoga", secs = 3, lines = LINES.art } },
		photo = { spot = "booth", title = "PHOTO BOOTH", sub = "four shots, one strip", btn = "POSE", icon = "star", act = { sit = true, emote = "cheer", secs = 3, lines = LINES.photo } },
		hardware = { spot = "workbench", title = "THE WORKBENCH", sub = "somebody is halfway through something", btn = "HAVE A GO", icon = "bolt", act = { sound = "Pop", lines = LINES.hardware } },
		laundry = { spot = "washer", title = "MACHINE NO. 4", sub = "the warm one, everybody knows", btn = "WATCH IT SPIN", icon = "heart", act = { sit = true, lines = LINES.laundry } },
	}
	local DEFAULT_FIT = { spot = "table", title = "ON DISPLAY", sub = "have a look around", btn = "BROWSE", icon = "bag", act = { lines = LINES.browse } }
	-- the furniture for each kind of spot; returns a seat CFrame if you sit there
	local SPOT = {}
	function SPOT.nook(c, acc)
		solid(P(V(4.4, 2, 4.2), c * CFrame.new(0, 1, 0), acc, Enum.Material.Fabric))
		P(V(4.4, 3.4, 1), c * CFrame.new(0, 3.6, 1.6), acc, Enum.Material.Fabric)
		for _, sx in { -1, 1 } do P(V(0.9, 1.4, 4.2), c * CFrame.new(sx * 2.2, 2.6, 0), shade(acc, 0.1), Enum.Material.Fabric) end
		cyl(0.3, 6, c * CFrame.new(3.6, 3, 1.4), Cc.ink, METAL)
		blob(V(2.4, 1.6, 2.4), c * CFrame.new(3.6, 6.4, 1.4), rgb(255, 232, 190))
		return c * CFrame.new(0, 2.1, 0)
	end
	function SPOT.pen(c, acc)
		for _, s in { -1, 1 } do
			P(V(8, 1.8, 0.3), c * CFrame.new(0, 0.9, s * 2.4), Cc.cream)
			P(V(0.3, 1.8, 4.8), c * CFrame.new(s * 4, 0.9, 0), Cc.cream)
		end
		for k, x in { -2, 1.6 } do
			local col = k == 1 and rgb(226, 190, 140) or rgb(250, 246, 236)
			blob(V(2.2, 1.6, 2.8), c * CFrame.new(x, 1, 0.2 * k), col)
			ball(1.4, c * CFrame.new(x, 1.9, -1 + 0.2 * k), col)
			for _, sx in { -0.5, 0.5 } do blob(V(0.5, 0.9, 0.3), c * CFrame.new(x + sx, 2.5, -1 + 0.2 * k), shade(col, 0.2)) end
		end
	end
	function SPOT.rack(c, acc)
		for _, sx in { -3, 3 } do cyl(0.3, 5.6, c * CFrame.new(sx, 2.8, 0), Cc.ink, METAL) end
		P(V(6.4, 0.3, 0.3), c * CFrame.new(0, 5.5, 0), Cc.ink, METAL)
		for k = 0, 4 do
			P(V(0.9, 3.2, 2.2), c * CFrame.new(-2.4 + k * 1.2, 3.7, 0), ({ acc, Cc.cream, rgb(240, 170, 190), rgb(140, 190, 240), Cc.butter })[k + 1], Enum.Material.Fabric)
		end
		solid(P(V(3.6, 7.4, 0.4), c * CFrame.new(5.6, 3.7, 1), rgb(214, 232, 240), SMOOTH, { reflect = 0.35 }))
	end
	function SPOT.capsule(c, acc)
		solid(P(V(3.6, 3.4, 3.2), c * CFrame.new(0, 1.7, 0), rgb(236, 110, 110)))
		local dome = ball(3.8, c * CFrame.new(0, 5, 0), rgb(220, 240, 250), K.GLASS, { transparency = 0.55 })
		dome.CastShadow = false
		for k = 0, 5 do ball(1, c * CFrame.new(math.cos(k) * 0.9, 4.4 + (k % 3) * 0.5, math.sin(k) * 0.9), K.FLOWER_COLS[k % 5 + 1]) end
		cyl(1, 0.5, c * CFrame.new(0, 2, -1.7) * CFrame.Angles(math.pi / 2, 0, 0), Cc.gold, METAL)
	end
	function SPOT.demo(c, acc)
		solid(P(V(8, 3, 3.4), c * CFrame.new(0, 1.5, 0), Cc.cream))
		for k = -1, 1 do
			P(V(2, 1.5, 0.2), c * CFrame.new(k * 2.6, 4, 0) * CFrame.Angles(-0.25, 0, 0), Cc.ink, SMOOTH)
			local scr = P(V(1.7, 1.2, 0.1), c * CFrame.new(k * 2.6, 4, -0.14) * CFrame.Angles(-0.25, 0, 0), rgb(120, 220, 250), NEON)
			scr.CastShadow = false
		end
	end
	function SPOT.buckets(c, acc)
		for k = 0, 3 do
			local b = c * CFrame.new(-3.6 + k * 2.4, 0, (k % 2) * 1.2)
			cyl(1.8, 2.2, b * CFrame.new(0, 1.1, 0), rgb(150, 160, 164), METAL)
			for j = 0, 2 do ball(1.1, b * CFrame.new(math.cos(j * 2.1) * 0.6, 2.9 + j * 0.25, math.sin(j * 2.1) * 0.6), K.FLOWER_COLS[(k + j) % 5 + 1]) end
		end
	end
	function SPOT.piano(c, acc)
		solid(P(V(8, 4.4, 2.6), c * CFrame.new(0, 2.2, 0.6), rgb(60, 48, 44), WOODM))
		P(V(7.4, 0.4, 1.6), c * CFrame.new(0, 3, -1.3), rgb(250, 250, 244), SMOOTH)
		for k = 0, 9 do P(V(0.3, 0.2, 0.9), c * CFrame.new(-3.2 + k * 0.7, 3.25, -1), Cc.ink, SMOOTH) end
		cyl(2.2, 0.5, c * CFrame.new(0, 1.8, -3.4), acc, SMOOTH)
		cyl(0.5, 1.6, c * CFrame.new(0, 0.8, -3.4), Cc.ink, METAL)
	end
	function SPOT.weights(c, acc)
		P(V(3, 0.6, 7), c * CFrame.new(0, 1.6, 0), Cc.ink, Enum.Material.Fabric)
		for _, sz in { -2.6, 2.6 } do P(V(3, 1.6, 0.5), c * CFrame.new(0, 0.8, sz), rgb(120, 126, 130), METAL) end
		cyl(0.3, 8, c * CFrame.new(0, 4, 2.8) * CFrame.Angles(0, 0, math.pi / 2), rgb(180, 184, 188), METAL)
		for _, sx in { -3.4, 3.4 } do cyl(2.6, 0.7, c * CFrame.new(sx, 4, 2.8) * CFrame.Angles(0, 0, math.pi / 2), acc, SMOOTH) end
		for _, sx in { -2, 2 } do cyl(0.4, 4, c * CFrame.new(sx, 2, 2.8), rgb(120, 126, 130), METAL) end
	end
	function SPOT.chair(c, acc)
		cyl(1.2, 1.6, c * CFrame.new(0, 0.8, 0), rgb(180, 184, 188), METAL)
		solid(P(V(3.6, 1, 3.6), c * CFrame.new(0, 2, 0), acc, Enum.Material.Fabric))
		P(V(3.6, 4, 0.8), c * CFrame.new(0, 4.4, 1.5), acc, Enum.Material.Fabric)
		P(V(5, 5.4, 0.3), c * CFrame.new(0, 6, -5.4), rgb(214, 232, 240), SMOOTH, { reflect = 0.35 })
		return c * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, 0)
	end
	function SPOT.table(c, acc)
		solid(P(V(7, 2.6, 4), c * CFrame.new(0, 1.3, 0), Cc.cream))
		P(V(7.6, 0.4, 4.6), c * CFrame.new(0, 2.8, 0), shade(acc, 0.05), WOODM)
		for k = -1, 1 do blob(V(1.6, 1.5, 1.6), c * CFrame.new(k * 2.2, 3.7, 0), ({ acc, Cc.butter, rgb(240, 170, 190) })[k + 2]) end
	end
	-- the seven new ones. They lean on K.furn rather than re-inlining boxes,
	-- which is the whole reason the kit exists; venueCtx(nil) because the
	-- interaction here belongs to SHOPFIT's row, not to the furniture.
	function SPOT.produce(c, acc)
		K.furn.bins(venueCtx(nil), c * CFrame.new(1, -0.5, 0), 11,
			{ rgb(236, 110, 96), rgb(250, 200, 90), rgb(140, 196, 110), rgb(240, 150, 190) })
		-- a hanging scale: the one prop that says "weighed and sold by hand"
		P(V(0.25, 3.4, 0.25), c * CFrame.new(-4.6, 7, 0), Cc.lampPost, METAL)
		cyl(2.6, 0.5, c * CFrame.new(-4.6, 5.2, 0), Cc.cream, METAL)
		cyl(2.2, 1, c * CFrame.new(-4.6, 4.3, 0), shade(acc, 0.1), METAL)
	end
	function SPOT.dispensary(c, acc)
		local top = K.furn.counter(venueCtx(nil), c * CFrame.new(0, -0.5, 1.4), 9, Cc.cream, { top = tint(acc, 0.2), h = 4.2 })
		K.furn.till(venueCtx(nil), c * CFrame.new(3, 4.2, 1.4))
		-- little labelled drawers behind: a pharmacy is a wall of drawers
		for row = 0, 3 do
			for k = 0, 5 do
				P(V(1.5, 1.3, 0.5), c * CFrame.new(-4.4 + k * 1.7, 5.4 + row * 1.6, 3.6), row % 2 == 0 and Cc.cream or rgb(238, 232, 220), WOODM, { noShadow = true })
				P(V(0.5, 0.15, 0.2), c * CFrame.new(-4.4 + k * 1.7, 5.4 + row * 1.6, 3.3), shade(acc, 0.2), METAL, { noShadow = true })
			end
		end
		P(V(11, 0.6, 1.2), c * CFrame.new(-0.4, 11.4, 3.6), shade(acc, 0.15), WOODM)
		return top
	end
	function SPOT.workstand(c, acc)
		-- a bike upside-down in a repair stand, mid-job
		P(V(0.5, 7, 0.5), c * CFrame.new(0, 3.5, 1.6), Cc.lampPost, METAL)
		P(V(3.4, 0.4, 0.4), c * CFrame.new(0, 6.6, 0.6), Cc.lampPost, METAL)
		P(V(0.35, 0.35, 5.4), c * CFrame.new(0, 5.6, -1.2), acc, METAL)
		P(V(0.35, 2.6, 0.35), c * CFrame.new(0, 4.4, -3.4), acc, METAL)
		for _, sz in { -3.4, 1.2 } do
			cyl(5, 0.35, c * CFrame.new(0, 5.4, sz) * CFrame.Angles(0, 0, math.pi / 2), Cc.ink, SMOOTH)
			cyl(1.2, 0.5, c * CFrame.new(0, 5.4, sz) * CFrame.Angles(0, 0, math.pi / 2), rgb(200, 206, 212), METAL)
		end
		K.furn.crates(venueCtx(nil), c * CFrame.new(-5, -0.5, 1), rgb(196, 156, 116), 2)
	end
	function SPOT.easel(c, acc)
		K.furn.easel(venueCtx(nil), c * CFrame.new(0, -0.5, 0), acc)
		-- a jar of brushes and a spill of tubes on the floor beside it
		cyl(1.6, 2, c * CFrame.new(3, 0.5, 0.4), Cc.cream, SMOOTH)
		for k = 0, 4 do P(V(0.18, 3, 0.18), c * CFrame.new(2.4 + k * 0.3, 2.6, 0.4) * CFrame.Angles(0.1 * k, 0, 0.08 * k), K.FLOWER_COLS[k % 5 + 1], SMOOTH, { noShadow = true }) end
	end
	function SPOT.booth(c, acc)
		-- a curtained photo booth: three sides, a stool, a screen, a slot
		solid(P(V(8, 11, 0.6), c * CFrame.new(0, 5, 3.2), shade(acc, 0.15)))
		for _, sx in { -1, 1 } do solid(P(V(0.6, 11, 6.4), c * CFrame.new(sx * 3.7, 5, 0), shade(acc, 0.15))) end
		P(V(8.8, 1.2, 7), c * CFrame.new(0, 11.2, 0), acc)
		P(V(7, 8, 0.4), c * CFrame.new(0, 5, -2.8), tint(acc, 0.45), K.FABRIC)
		local scr = P(V(3.4, 2.6, 0.3), c * CFrame.new(0, 7.4, 2.8), rgb(140, 230, 255), NEON)
		scr.CastShadow = false
		P(V(1.6, 0.25, 0.3), c * CFrame.new(3.2, 3.4, -2.9), Cc.ink, SMOOTH)
		solid(cyl(2.4, 0.6, c * CFrame.new(0, 2.4, 0), Cc.cream, SMOOTH))
		cyl(0.5, 2.2, c * CFrame.new(0, 1.1, 0), Cc.ink, METAL)
		return c * CFrame.new(0, 2.7, 0)
	end
	function SPOT.workbench(c, acc)
		solid(P(V(11, 3.6, 4.4), c * CFrame.new(0, 1.8, 0.8), rgb(176, 136, 100), WOODM))
		P(V(11.4, 0.5, 4.8), c * CFrame.new(0, 3.8, 0.8), rgb(150, 116, 86), WOODM)
		-- a vice, and a job half done
		P(V(1.6, 1.4, 2.4), c * CFrame.new(-4, 4.7, 0.8), rgb(120, 150, 130), METAL)
		P(V(0.3, 0.3, 2.4), c * CFrame.new(-4, 4.7, -0.8), rgb(180, 184, 188), METAL)
		P(V(4.4, 0.6, 1.2), c * CFrame.new(1, 4.3, 0.4) * CFrame.Angles(0, 0.2, 0), rgb(214, 170, 120), WOODM)
		K.furn.pegboard(venueCtx(nil), c * CFrame.new(0, -0.5, 3.4), 11, acc)
	end
	function SPOT.washer(c, acc)
		K.furn.machines(venueCtx(nil), c * CFrame.new(0.5, -0.5, 1.6), 3, rgb(232, 236, 238))
		-- the plastic chairs you wait in. BEHIND the machines, not in front of
		-- them: the anchor is 5.6 off the front wall, so a chair at -5.2 would
		-- be inside the shop window. No rotation, because a CFrame's
		-- LookVector is its -Z and the machines are that way.
		for _, sx in { -3.4, 0, 3.4 } do
			solid(P(V(2.8, 0.5, 2.8), c * CFrame.new(sx, 2, 5.2), tint(acc, 0.35), SMOOTH))
			P(V(2.8, 3.2, 0.5), c * CFrame.new(sx, 3.4, 6.4), tint(acc, 0.35), SMOOTH)
			for _, q in { -1, 1 } do P(V(0.3, 2, 0.3), c * CFrame.new(sx + q, 1, 5.2), Cc.lampPost, METAL, { noShadow = true }) end
		end
		return c * CFrame.new(0, 2.5, 5.2)
	end

	---------------------------------------------------------------------------
	-- ROOM DRESSING BY TRADE. The SHOPFIT row above gives a room its one
	-- thing to DO; this gives it its silhouette. Two or three kit pieces
	-- against the side walls and, in a deep room, one island -- which is the
	-- difference between "a shop" and "a laundry".
	--
	-- The anchors dodge what the fit-out already owns, and they were chosen
	-- against the fit-out's own numbers, not by eye:
	--   back wall, x -w/2+2 .. 0        the stocked shelving
	--   x w/2-9.5 .. w/2-2.5, z d/2-4   the till
	--   x -w/2+8, z -d/2+5.6            the SHOPFIT spot
	--   centre, z d/6                   venueRoom's rug and pendant
	-- so what is left is the right wall forward of the till, the left wall
	-- behind the spot, and a strip just inside the window.
	---------------------------------------------------------------------------
	local DRESS = {}
	do
		local function rightWall(f, w, d, z) return f * CFrame.new(w / 2 - 3.2, 0, z) * CFrame.Angles(0, math.pi / 2, 0) end
		local function leftWall(f, w, d, z) return f * CFrame.new(-w / 2 + 3.2, 0, z) * CFrame.Angles(0, -math.pi / 2, 0) end
		-- an island only exists if the room is deep enough to walk round one
		local function island(f, w, d) return d >= 28 and f * CFrame.new(0, 0.5, -d / 2 + 12) or nil end
		local WARM = { rgb(236, 110, 96), rgb(250, 200, 90), rgb(140, 196, 110), rgb(240, 150, 190), rgb(150, 190, 236) }

		DRESS.books = function(c, f, w, d, acc, i)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 11), math.min(16, d - 16), { rgb(150, 110, 90), rgb(196, 156, 116), tint(acc, 0.3), Cc.cream }, i)
			if island(f, w, d) then K.furn.bin(c, island(f, w, d), 10, { rgb(226, 188, 140), tint(acc, 0.35), Cc.butter, rgb(200, 160, 200) }) end
		end
		DRESS.pets = function(c, f, w, d, acc, i)
			-- glass tanks, lit, stacked: the thing every pet shop actually is
			K.furn.display(c, rightWall(f, w, d, -d / 2 + 11), math.min(14, d - 16), tint(acc, 0.2), { rgb(240, 170, 100), rgb(150, 210, 236), rgb(250, 230, 150) })
			K.furn.crates(c, leftWall(f, w, d, 1), rgb(214, 170, 120), 3)
		end
		DRESS.clothes = function(c, f, w, d, acc, i)
			K.furn.mirror(c, rightWall(f, w, d, -d / 2 + 10) * CFrame.new(0, 7, 0), 7, 10)
			if island(f, w, d) then K.furn.rack(c, island(f, w, d), { acc, Cc.cream, rgb(240, 170, 190), rgb(140, 190, 240), Cc.butter }) end
		end
		DRESS.tailor = DRESS.clothes
		DRESS.tech = function(c, f, w, d, acc, i)
			K.furn.display(c, rightWall(f, w, d, -d / 2 + 11), math.min(14, d - 16), Cc.ink, { rgb(120, 220, 250), rgb(180, 190, 200), rgb(140, 160, 240) })
			K.furn.crates(c, leftWall(f, w, d, 2), rgb(196, 186, 176), 3)
		end
		DRESS.toys = function(c, f, w, d, acc, i)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 11), math.min(16, d - 16), K.FLOWER_COLS, i)
			if island(f, w, d) then K.furn.bin(c, island(f, w, d), 10, K.FLOWER_COLS) end
		end
		DRESS.flowers = function(c, f, w, d, acc, i)
			if island(f, w, d) then K.furn.bins(c, island(f, w, d) * CFrame.new(0, -0.5, 0), 12, K.FLOWER_COLS) end
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 10), 10, { rgb(150, 190, 140), Cc.cream, rgb(196, 156, 116) }, i)
		end
		DRESS.music = function(c, f, w, d, acc, i)
			K.furn.pegboard(c, rightWall(f, w, d, -d / 2 + 10), 12, acc)
			if island(f, w, d) then K.furn.bin(c, island(f, w, d), 11, { Cc.ink, tint(acc, 0.3), rgb(226, 100, 90), Cc.butter, rgb(140, 190, 240) }) end
		end
		DRESS.gym = function(c, f, w, d, acc, i)
			K.furn.mirror(c, rightWall(f, w, d, -d / 2 + 12) * CFrame.new(0, 7, 0), 14, 11)
			K.furn.crates(c, leftWall(f, w, d, 2), tint(acc, 0.2), 2)
		end
		DRESS.barber = function(c, f, w, d, acc, i)
			K.furn.mirror(c, rightWall(f, w, d, -d / 2 + 10) * CFrame.new(0, 7, 0), 6, 8)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 19), 8, { Cc.cream, tint(acc, 0.3), rgb(226, 188, 140) }, i)
		end
		DRESS.grocery = function(c, f, w, d, acc, i)
			K.furn.fridge(c, rightWall(f, w, d, -d / 2 + 12), math.min(16, d - 16))
			if island(f, w, d) then K.furn.bins(c, island(f, w, d) * CFrame.new(0, -0.5, 0), 12, WARM) end
		end
		DRESS.pharmacy = function(c, f, w, d, acc, i)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 11), math.min(16, d - 16), { Cc.cream, tint(acc, 0.35), rgb(150, 210, 236), Cc.butter }, i)
			if island(f, w, d) then K.furn.display(c, island(f, w, d) * CFrame.new(0, -0.5, 0), 9, Cc.cream, { rgb(150, 210, 236), Cc.cream, tint(acc, 0.3) }) end
		end
		DRESS.bikes = function(c, f, w, d, acc, i)
			K.furn.pegboard(c, rightWall(f, w, d, -d / 2 + 10), 12, acc)
			K.furn.crates(c, leftWall(f, w, d, 2), rgb(196, 156, 116), 3)
		end
		DRESS.art = function(c, f, w, d, acc, i)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 11), math.min(14, d - 16), K.FLOWER_COLS, i + 2)
			if island(f, w, d) then K.furn.bin(c, island(f, w, d), 11, { Cc.cream, tint(acc, 0.4), Cc.butter, rgb(150, 210, 236) }) end
		end
		DRESS.photo = function(c, f, w, d, acc, i)
			K.furn.display(c, rightWall(f, w, d, -d / 2 + 11), math.min(12, d - 16), Cc.ink, { Cc.cream, rgb(226, 188, 140), tint(acc, 0.3) })
			K.furn.easel(c, leftWall(f, w, d, 2), tint(acc, 0.3))
		end
		DRESS.hardware = function(c, f, w, d, acc, i)
			K.furn.pegboard(c, rightWall(f, w, d, -d / 2 + 10), 12, acc)
			if island(f, w, d) then K.furn.bins(c, island(f, w, d) * CFrame.new(0, -0.5, 0), 12, { rgb(180, 184, 188), rgb(196, 156, 116), Cc.lampPost, rgb(150, 156, 170) }) end
		end
		DRESS.laundry = function(c, f, w, d, acc, i)
			K.furn.machines(c, rightWall(f, w, d, -d / 2 + 12), 4, rgb(232, 236, 238))
			K.furn.crates(c, leftWall(f, w, d, 2), tint(acc, 0.25), 2)
		end
		-- the fallback is still a shop, but it is a shop with a back-of-house
		DRESS.default = function(c, f, w, d, acc, i)
			K.furn.shelving(c, rightWall(f, w, d, -d / 2 + 11), math.min(14, d - 16), { acc, tint(acc, 0.4), Cc.butter, Cc.cream }, i)
			K.furn.crates(c, leftWall(f, w, d, 2), rgb(214, 170, 120), 2)
		end
	end

	local function fitShop(f, w, d, l, i, acc)
		local fit = SHOPFIT[l.btype] or DEFAULT_FIT
		-- shelving along the back wall, stocked in the shop's colours
		local sw = w * 0.5
		local sf = f * CFrame.new(-w / 2 + sw / 2 + 2, 0, d / 2 - 1.8)
		solid(P(V(sw, 9.4, 1.4), sf * CFrame.new(0, 4.7, 0), rgb(176, 136, 100), WOODM))
		local stock = { acc, tint(acc, 0.4), Cc.butter, shade(acc, 0.2), Cc.cream }
		for row = 0, 2 do
			P(V(sw, 0.3, 2), sf * CFrame.new(0, 2.4 + row * 2.6, -0.5), rgb(196, 156, 116), WOODM)
			for k = 0, 2 do
				P(V(sw / 3 - 0.8, 1.7, 1.2), sf * CFrame.new(-sw / 3 + k * sw / 3, 3.4 + row * 2.6, -0.7), stock[(row + k + i) % #stock + 1])
			end
		end
		-- the till, with the shopkeeper behind it
		local tf = f * CFrame.new(w / 2 - 6, 0, d / 2 - 4)
		solid(P(V(7, 3.4, 2.4), tf * CFrame.new(0, 1.7, 0), shade(acc, 0.1), WOODM))
		P(V(7.6, 0.4, 3), tf * CFrame.new(0, 3.6, 0), Cc.cream)
		P(V(1.6, 1.2, 1.4), tf * CFrame.new(1.8, 4.4, 0), Cc.ink, SMOOTH)
		local keeper = Models.buildSminski(K.cur, 1, Config.Characters[(i * 3 + 1) % #Config.Characters + 1], false, nil)
		Models.poseSminski(keeper, tf * CFrame.new(0, 0, 2.4) * CFrame.Angles(0, math.pi, 0), "idle", i)
		-- the one thing to do here, against the left wall near the window
		local c = f * CFrame.new(-w / 2 + 8, 0.5, -d / 2 + 5.6)
		local seat = SPOT[fit.spot](c, acc)
		local spot = {
			pos = c.Position - CITY,
			title = fit.title, sub = fit.sub, btn = fit.btn, icon = fit.icon, act = fit.act, seat = seat,
		}
		local spots = { spot }
		-- ...and the trade's own furniture, which is what stops the next
		-- three shops down the street from being this one in another colour
		local dress = DRESS[l.btype] or DRESS.default
		dress(venueCtx(spots), f, w, d, acc, i)
		-- a name board over the till, because a shop's own name inside it is
		-- the cheapest way for two rooms of the same trade to read apart
		if l.name then
			-- width and offset clamped so the board clears the right-hand wall
			-- in the narrow (w = 30) shopstreet rooms as well as the w = 38 ones
			local nb = P(V(math.min(w * 0.36, 11), 2.6, 0.3), f * CFrame.new(w / 2 - 7, 10.4, d / 2 - 1.2), shade(acc, 0.2))
			K.textOn(nb, Enum.NormalId.Front, l.name, Cc.cream, Vector2.new(420, 80), 0)
		end
		return {
			name = l.name, btype = l.btype, pos = (f.Position - CITY), door = l.door,
			-- how far from the room's CENTRE still counts as being in this
			-- room. It used to be a flat 26 in CityVenues, which was fine for a
			-- 16-deep room and is not for a 56-deep one: standing at the back
			-- wall you would be 28 away and in no venue at all.
			radius = math.max(26, d / 2 + 8),
			seats = {}, tables = {}, accent = acc, spots = spots,
		}
	end

	---------------------------------------------------------------------------
	-- A WORKING KITCHEN. Same shell as every other venue -- CityVenues can
	-- still order at the counter -- but the room behind the counter is laid
	-- out as a job: six stations in the order you work them, arranged as a U
	-- so an order walks you down the left wall, along the back and out to the
	-- pass. Moving through the room IS the loop; a kitchen you could work
	-- standing still would be a menu with a floor under it.
	--
	-- This builds the ROOM. CityKitchen.lua runs what happens in it, and
	-- reads the station list off the venue it registers here.
	---------------------------------------------------------------------------
	---------------------------------------------------------------------------
	-- THE STATION VOCABULARY.
	--
	-- One builder per step KIND, not per restaurant. A step's `build` names
	-- one of these outright; otherwise its `kind` (the minigame CityKitchen
	-- runs there) picks the bench, and anything unrecognised falls back to a
	-- plain prep bench -- so a Config row naming a station this file has never
	-- heard of still produces a room you can work in, instead of a nil call
	-- inside a coroutine that streamStep would turn into a missing building.
	--
	--   mk(bw, opts) -> CFrame   draws the bench and registers the station
	--                            (bw = false for something that draws its own
	--                            body, like the oven). opts.stand is where the
	--                            cook must stand; opts.glow is a part
	--                            CityKitchen may brighten.
	---------------------------------------------------------------------------
	local BENCH = {}
	-- PREP: the default. A clean bench, a board and a bowl.
	BENCH.prep = function(mk, cf, acc, st, R)
		local c = mk(10)
		cyl(4, 0.4, c * CFrame.new(-1, 3.9, 0), rgb(226, 188, 140), WOODM)
		blob(V(3, 1.8, 3), c * CFrame.new(2.6, 4.4, 0), Cc.cream)
	end
	-- STOP: something you roll, stretch or portion, and three of them waiting.
	BENCH.stop = function(mk, cf, acc, st, R)
		local c = mk(10)
		cyl(0.9, 6, c * CFrame.new(0, 4.4, 0.6) * CFrame.Angles(0, 0, math.pi / 2), rgb(214, 170, 120), WOODM)
		for _, sx in { -3, 0, 3 } do ball(1.5, c * CFrame.new(sx, 4.5, -1.2), rgb(244, 232, 210)) end
	end
	-- FILL: something you pour. `st.color` lets a config row say what colour
	-- the pot is -- tomato, caramel, batter, coffee.
	BENCH.fill = function(mk, cf, acc, st, R)
		local c = mk(10)
		cyl(3.2, 3.4, c * CFrame.new(-1.5, 5.3, 0), st.color or rgb(200, 66, 60), SMOOTH)
		cyl(3.5, 0.4, c * CFrame.new(-1.5, 7.1, 0), Cc.cream, SMOOTH)
		cyl(0.3, 5, c * CFrame.new(2.4, 6, 0) * CFrame.Angles(0.3, 0, 0), Cc.lampPost, METAL)
	end
	-- PICK: one tub per ingredient, in the INGREDIENT'S OWN COLOUR, read
	-- straight off the config row. This is the piece that makes a burger
	-- bar's rail lettuce and pickles and a pizzeria's olives and peppers
	-- without a line here changing. `st.from` names the list; default
	-- `toppings`, which is what the pizzeria calls it.
	BENCH.pick = function(mk, cf, acc, st, R)
		local list = (R and R[st.from or "toppings"]) or {}
		local c = mk(math.clamp(#list * 2, 10, 16))
		for ti, t in list do
			local tx = -(#list - 1) + (ti - 1) * 2
			cyl(1.7, 2, c * CFrame.new(tx, 4.6, ti % 2 == 0 and 1.1 or -1.1), Cc.cream, SMOOTH)
			cyl(1.5, 0.5, c * CFrame.new(tx, 5.7, ti % 2 == 0 and 1.1 or -1.1), t.color or acc, SMOOTH)
		end
	end
	-- TAPS: the finishing bench -- cut, box, plate, wrap.
	BENCH.taps = function(mk, cf, acc, st, R)
		local c = mk(10)
		cyl(4, 0.4, c * CFrame.new(-1, 3.9, 0), rgb(226, 188, 140), WOODM)
		cyl(1.2, 0.3, c * CFrame.new(2.6, 4.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Cc.stone, METAL)
		P(V(0.5, 0.5, 2.4), c * CFrame.new(2.6, 4.4, 1.6), Cc.ink)
		for k = 0, 2 do P(V(4, 0.5, 4), c * CFrame.new(-4, 4.2 + k * 0.6, 1.2), rgb(236, 214, 178), WOODM) end
	end
	-- BAKE: the hot station. Not a bench -- a brick arch with a mouth you can
	-- see into, and the one thing in the room that gets its own light.
	BENCH.bake = function(mk, cf, acc, st, R)
		local brick = st.color or rgb(176, 108, 88)
		solid(P(V(13, 11, 8), cf * CFrame.new(0, 5.5, 0), brick, Enum.Material.Brick))
		P(V(14, 1.6, 9), cf * CFrame.new(0, 11.4, 0), shade(brick, 0.15))
		local mouth = P(V(7, 4.6, 1), cf * CFrame.new(0, 4.4, -4.2), rgb(255, 150, 70), NEON)
		mouth.CastShadow = false
		local ol = Instance.new("PointLight")
		ol.Range, ol.Brightness, ol.Color, ol.Shadows = 22, 1.3, rgb(255, 150, 70), false
		ol.Parent = mouth
		cyl(1.6, 9, cf * CFrame.new(4.4, 15, 0), shade(brick, 0.15), Enum.Material.Brick)
		mk(false, { stand = CFrame.new(0, 0, -5), glow = mouth, plate = CFrame.new(0, 11.6, -3.6), plateW = 12 })
	end
	-- GRILL: the other hot station -- a flat top with a hood over it, for the
	-- restaurants that fry rather than bake.
	BENCH.grill = function(mk, cf, acc, st, R)
		solid(P(V(13, 3.6, 5), cf * CFrame.new(0, 1.8, 0), rgb(150, 156, 170), METAL))
		local top = P(V(12.4, 0.5, 4.6), cf * CFrame.new(0, 3.9, 0), rgb(72, 70, 76), METAL)
		for _, sx in { -3.5, 0, 3.5 } do
			cyl(2.6, 0.4, cf * CFrame.new(sx, 4.3, 0), rgb(200, 140, 96), SMOOTH)
		end
		local heat = P(V(12, 0.3, 4.4), cf * CFrame.new(0, 4.05, 0), rgb(255, 150, 70), NEON, { noShadow = true })
		heat.Transparency = 0.55
		P(V(14, 1.4, 6), cf * CFrame.new(0, 10.4, 0.6), rgb(196, 202, 210), METAL)
		for _, sx in { -6.4, 6.4 } do P(V(0.5, 6, 0.5), cf * CFrame.new(sx, 7.2, 2.8), rgb(196, 202, 210), METAL) end
		mk(false, { stand = CFrame.new(0, 0, -4.4), glow = heat, plate = CFrame.new(0, 9.5, -2.6), plateW = 11 })
		return top
	end

	-- WHERE THE STATIONS STAND. A U, and still for the original reason: an
	-- order should walk you down one wall, along the back and out to the pass.
	-- Moving through the room IS the loop; a kitchen you could work standing
	-- still would be a menu with a floor under it.
	--
	-- The split is the HOT station: everything before the bake is prep and
	-- goes down the left wall, everything from the bake on is the hot line
	-- along the back. That is how a kitchen is arranged, and it happens to
	-- reproduce the pizzeria's hand-placed layout exactly, which is the point
	-- -- nothing about Slice of Life moves.
	--
	-- LEFT_T are fractions along the left wall (0 = by the window,
	-- 1 = at the back); BACK_X are x positions along the back wall. The last
	-- back station abuts the pass counter on purpose: it reads as one
	-- continuous worktop, which is what the pizzeria already did.
	-- the wording on a bench's name plate. A config row's `bench` wins; these
	-- are the pizzeria's original labels, kept verbatim so that nothing about
	-- Slice of Life changes now its stations come out of the table.
	local BENCH_LABEL = { dough = "DOUGH", sauce = "SAUCE", top = "TOPPINGS", oven = "OVEN", cut = "CUT & BOX", counter = "SERVE" }
	local LEFT_T = { [1] = { 0.5 }, [2] = { 0, 1 }, [3] = { 0, 0.41, 1 }, [4] = { 0, 0.34, 0.67, 1 } }
	local BACK_X = { [1] = { -5 }, [2] = { -5, 8 }, [3] = { -14, -5, 8 }, [4] = { -18, -9, 1, 10 } }

	---------------------------------------------------------------------------
	-- A GROCERY STORE. Shelves you take things from, a till you pay at, a
	-- keeper behind it. The shelves are the owner's inventory kit (PBR
	-- supermarket shelving, ~5 mesh parts each) when it is in, and K.furn's
	-- part-built shelving when it is not; either way every shelf is a venue
	-- SPOT carrying one grocery from Config.Groceries, and the till is a spot
	-- that checks out (CityGrocery / CityVenues.use). Produce stands on its
	-- shelf as the farm pack's own mesh -- an apple shelf has apples on it.
	-- Scales from a 30 x 30 corner shop to the 150 x 70 SUPER MARKET.
	---------------------------------------------------------------------------
	local function fitGrocery(f, w, d, l, i, acc)
		local spots = {}
		local ctx = venueCtx(spots)
		local items = Config.Groceries
		local k = i or 0
		local haveKit = K.inv("ShelfTall") ~= nil
		local shelfH = 8
		-- one shelf: the kit piece (or a K.furn run), facing `cf`'s -Z, plus its spot
		local function shelf(cf, item)
			if haveKit then
				K.place("ShelfTall", cf * CFrame.Angles(0, math.pi, 0), { height = shelfH, collide = "solid" })
			else
				K.furn.shelving(ctx, cf * CFrame.new(0, 0, 0.6), 6, { item.col, tint(item.col, 0.4), Cc.cream, Cc.butter }, k)
			end
			if item.mesh then
				for q = -1, 1 do
					K.place(item.mesh, cf * CFrame.new(q * 1.6, shelfH * 0.55, -1.2) * CFrame.Angles(0, q * 0.7, 0), { width = 1.4 })
				end
			end
			table.insert(spots, { pos = (cf * CFrame.new(0, 0, -3.6)).Position - CITY,
				title = string.upper(item.name), sub = "", btn = "TAKE", icon = "bag", act = { grocery = item.id } })
		end
		-- SHELVES ALONG BOTH SIDE WALLS, from the back forward, leaving the
		-- front six studs for the till and the doorway
		local pitch = 6
		local n = math.max(1, math.floor((d - 12) / pitch))
		for side = -1, 1, 2 do
			for j = 0, n - 1 do
				local item = items[(k + j * 2 + (side > 0 and 1 or 0)) % #items + 1]
				local z = d / 2 - 4 - j * pitch
				shelf(f * CFrame.new(side * (w / 2 - 3.4), 0.5, z) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0), item)
				k += 0
			end
		end
		-- WIDE ROOMS GET AISLES: pairs of shelves back to back down the middle
		if w >= 60 then
			local aisles = math.floor((w - 40) / 30)
			for a = 1, aisles do
				local x = -w / 2 + 20 + (a - 0.5) * ((w - 40) / aisles)
				for j = 0, n - 2 do
					local z = d / 2 - 10 - j * pitch
					for side = -1, 1, 2 do
						local item = items[(k + 7 + a * 3 + j * 2 + (side > 0 and 1 or 0)) % #items + 1]
						shelf(f * CFrame.new(x + side * 2.6, 0.5, z) * CFrame.Angles(0, side > 0 and math.pi / 2 or -math.pi / 2, 0), item)
					end
				end
			end
		end
		-- THE TILL, front-right, facing the door, keeper behind it
		local tf = f * CFrame.new(w / 2 - 9, 0.5, -d / 2 + 7)
		if K.inv("Cashier") then
			K.place("Cashier", tf * CFrame.Angles(0, math.pi / 2, 0), { width = 9, collide = "solid" })
		else
			solid(P(V(8, 3.4, 2.6), tf * CFrame.new(0, 1.7, 0), shade(acc, 0.1), WOODM))
			P(V(8.6, 0.4, 3.2), tf * CFrame.new(0, 3.6, 0), Cc.cream)
			P(V(1.6, 1.2, 1.4), tf * CFrame.new(2, 4.4, 0), Cc.ink, SMOOTH)
		end
		local keeper = Models.buildSminski(K.cur, 1, Config.Characters[(k * 3 + 2) % #Config.Characters + 1], false, "chefhat")
		Models.poseSminski(keeper, tf * CFrame.new(0, -0.5, 2.6) * CFrame.Angles(0, math.pi, 0), "idle", k)
		table.insert(spots, { pos = (tf * CFrame.new(0, 0, -3.2)).Position - CITY,
			title = "THE TILL", sub = "", btn = "PAY", icon = "coin", act = { checkout = true } })
		-- a stack of baskets by the door, so the room says what it is for
		for q = 0, 2 do
			P(V(2.6, 0.9, 2), f * CFrame.new(-w / 2 + 4, 0.5 + q * 0.9, -d / 2 + 4) * CFrame.Angles(0, q * 0.2, 0), q % 2 == 0 and acc or tint(acc, 0.4))
		end
		return {
			name = l.name or "GROCERY", btype = "grocery", pos = (f.Position - CITY), door = l.door,
			radius = math.max(26, math.max(w, d) / 2 + 8),
			seats = {}, tables = {}, accent = acc, spots = spots,
		}
	end
	Build.fitGrocery = fitGrocery

	local function fitKitchen(f, w, d, l, i, acc)
		local rid = l.restaurant
		local R = rid and Config.Restaurant(rid)
		local stations = {}
		-- draw a station and register it. Returns the anchor so the BENCH
		-- builder can dress the top of it.
		local function station(bw, cf, id, label, opts)
			opts = opts or {}
			if bw then
				solid(P(V(bw, 3.4, 4.2), cf * CFrame.new(0, 1.7, 0), Cc.cream, WOODM))
				P(V(bw + 0.5, 0.4, 4.6), cf * CFrame.new(0, 3.6, 0), shade(Cc.stone, 0.05), SMOOTH)
			end
			local pcf = opts.plate or CFrame.new(0, 3.9, -2)
			local plate = P(V((opts.plateW or (bw or 10)) - 1, 0.1, 0.9), cf * pcf, acc, SMOOTH)
			K.textOn(plate, Enum.NormalId.Top, label, Cc.cream, Vector2.new(360, 60), 0)
			table.insert(stations, {
				id = id, cf = cf, name = label, glow = opts.glow,
				pos = (cf * (opts.stand or CFrame.new())).Position - CITY,
			})
			return cf
		end
		-- the steps that have a bench of their own. `serve` is the pass, and
		-- the pass is built below with the counter, because CityVenues needs
		-- that counter whether this room is a workplace or not.
		local line, hotAt = {}, nil
		for _, st in (R and R.steps or {}) do
			if st.kind ~= "serve" and st.station ~= "counter" then
				table.insert(line, st)
				if not hotAt and (st.kind == "bake" or st.kind == "grill") then hotAt = #line end
			end
		end
		local split = hotAt and (hotAt - 1) or math.ceil(#line / 2)
		local nL, nB = math.min(split, #line), #line - math.min(split, #line)
		local leftT = LEFT_T[nL] or LEFT_T[4]
		local backX = BACK_X[nB] or BACK_X[4]
		for si, st in line do
			local cf
			if si <= nL then
				local t = leftT[math.min(si, #leftT)] or 0.5
				cf = f * CFrame.new(-w / 2 + 7, 0, (-d / 2 + 9) + t * (d - 17))
			else
				local bi = si - nL
				cf = f * CFrame.new(backX[math.min(bi, #backX)] or 0, 0, d / 2 - 5.5)
			end
			local label = string.upper(st.bench or BENCH_LABEL[st.station] or st.station or "PREP")
			local mk = function(bw, opts) return station(bw, cf, st.station, label, opts) end
			local spec = BENCH[st.build] or BENCH[st.kind] or BENCH.prep
			spec(mk, cf, acc, st, R)
		end
		-- THE PASS: the counter customers wait at
		local cw = math.min(16, w * 0.4)
		local cf = f * CFrame.new(w / 2 - cw / 2 - 2, 0, d / 2 - 4.2)
		solid(P(V(cw, 3.6, 2.6), cf * CFrame.new(0, 1.8, 0), shade(acc, 0.1), WOODM))
		P(V(cw + 0.6, 0.4, 3.2), cf * CFrame.new(0, 3.8, 0), Cc.cream)
		P(V(1.6, 1.2, 1.4), cf * CFrame.new(cw / 2 - 2, 4.6, 0), Cc.ink, SMOOTH)
		local board = P(V(cw, 3.4, 0.3), f * CFrame.new(w / 2 - cw / 2 - 2, 10, d / 2 - 1.2), Cc.ink)
		local names = {}
		for _, m in (R and R.menu or {}) do table.insert(names, string.upper(m.name)) end
		K.textOn(board, Enum.NormalId.Front, table.concat(names, "  \u{00B7}  "), Cc.cream, Vector2.new(700, 120), 0)
		table.insert(stations, { id = "counter", cf = cf, pos = (cf * CFrame.new(0, 0, -3.4)).Position - CITY, name = "SERVE" })
		-- a couple of tables, so it is still a place people eat
		local seats, tables = {}, {}
		for k = 0, 1 do
			local tcf = f * CFrame.new(-w / 2 + 16 + k * 9, 0, -d / 2 + 7)
			cyl(0.6, 3, tcf * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
			solid(cyl(4.4, 0.4, tcf * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH))
			table.insert(tables, tcf * CFrame.new(0, 3.4, 0))
			for _, sz in { -3, 3 } do
				local scf = tcf * CFrame.new(0, 0, sz) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0)
				cyl(0.5, 1.8, scf * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
				cyl(2.2, 0.5, scf * CFrame.new(0, 2, 0), acc, SMOOTH)
				table.insert(seats, { cf = scf * CFrame.new(0, 2.2, 0), table = #tables })
			end
		end
		return {
			name = l.name, btype = l.btype, work = rid, stations = stations,
			menu = names, pos = (f.Position - CITY), door = l.door,
			radius = math.max(26, d / 2 + 8),
			counter = (cf * CFrame.new(0, 0, -3.4)).Position - CITY,
			counterTop = cf * CFrame.new(-2.4, 4.1, -0.2),
			queue = (cf * CFrame.new(0, 0, -7)).Position - CITY,
			seats = seats, tables = tables, accent = acc, spots = {},
		}
	end

	local function venueRoom(f, w, d, l, i)
		local h = 14
		local wall, acc = l.color, l.accent or Cc.sage
		local inner = tint(wall, 0.35)
		-- floor, ceiling, back and side walls
		walkable(P(V(w - 1, 0.5, d - 1), f * CFrame.new(0, 0.25, 0), rgb(222, 204, 176), WOODM))
		solid(P(V(w, h, 1), f * CFrame.new(0, h / 2, d / 2 - 0.5), inner))
		for _, sx in { -1, 1 } do solid(P(V(1, h, d), f * CFrame.new(sx * (w / 2 - 0.5), h / 2, 0), inner)) end
		P(V(w, 0.6, d), f * CFrame.new(0, h - 0.3, 0), Cc.cream)
		-- the shopfront: glass either side of an open doorway, a header above
		local doorW = 8
		local seg = (w - doorW) / 2 - 1
		for _, sx in { -1, 1 } do
			local gx = sx * (doorW / 2 + seg / 2)
			solid(P(V(seg, 2.4, 1), f * CFrame.new(gx, 1.2, -d / 2 + 0.5), shade(wall, 0.08)))
			local g = solid(P(V(seg, 8.2, 0.4), f * CFrame.new(gx, 6.5, -d / 2 + 0.5), Cc.pane, K.GLASS, { transparency = 0.6 }))
			g.CastShadow = false
			P(V(0.6, h, 1.2), f * CFrame.new(sx * doorW / 2, h / 2, -d / 2 + 0.5), acc)
		end
		P(V(w, h - 10.6, 1), f * CFrame.new(0, 10.6 + (h - 10.6) / 2, -d / 2 + 0.5), wall)
		-- the stone plinth, CUT ROUND THE DOORWAY. It used to run right across
		-- the opening at 1.4 high, which is 0.9 above the floor inside: with
		-- the doorway filled by a dark slab that never showed, but an open door
		-- with a stone bar across it hides the bottom of the room and reads as
		-- something to climb over. Cut out, the way in is one 0.5 step up off
		-- the pavement -- about a kerb, which is the step this city uses.
		local plw = (w + 0.8 - doorW) / 2
		for _, sx in { -1, 1 } do
			P(V(plw, 1.4, d + 0.8), f * CFrame.new(sx * (doorW / 2 + plw / 2), 0.7, 0), Cc.stone)
		end
		P(V(doorW, 1.4, d + 0.8 - 2.4), f * CFrame.new(0, 0.7, 1.2), Cc.stone)
		-- the green mat: this door is OPEN and you may walk in (CityKit.OPEN).
		-- y 0.06, not 1.4: the stone plinth above is only d + 0.8 deep, so at
		-- 1.4 the front five studs of the mat hung in mid-air over the
		-- pavement. Width and depth are UNCHANGED on purpose -- the mat already
		-- reaches the +2 strip the server scatters event items on
		-- (docs/HANDOFF.md §5) and it must not grow.
		K.threshold(f * CFrame.new(0, 0.06, -d / 2 - 2.4), doorW + 5, 7)
		-- NOTHING ACROSS THE DOORWAY. There was a near-black slab here, filling
		-- the opening as a "dark recess". The opening is a genuine hole -- the
		-- wall above only begins at y 10.6 and the glass is to either side --
		-- so the slab was pure fill, and a near-black rectangle in a doorway
		-- reads as a shut door however open the rest of the shopfront looks.
		-- The room behind is floored, walled, furnished and lit, so with the
		-- slab gone you simply see into it, which is the whole point of it.
		-- one warm light: roofed rooms are dark under honest daylight
		local lamp = ball(1.6, f * CFrame.new(0, h - 2, 0), rgb(255, 236, 200), NEON)
		lamp.CastShadow = false
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Color, pl.Shadows = math.max(w, d) * 0.9, 1.1, rgb(255, 232, 196), false
		pl.Parent = lamp
		-- fit it out: food places and shops share the shell, not the furniture
		-- WHICH FIT-OUT. A room is a working kitchen only if its LOT names a
		-- restaurant that exists in Config -- deliberately not if its btype
		-- matches one, because the moment a `cafe` row lands in
		-- Config.Restaurants that would turn all ~30 cafes in town into
		-- workplaces with six stations each.
		local isKitchen = l.restaurant ~= nil and Config.Restaurant(l.restaurant) ~= nil
		local v = (isKitchen and fitKitchen or l.btype == "grocery" and fitGrocery or FOODTYPE[l.btype] and fitFood or fitShop)(f, w, d, l, i, acc)
		v.light = pl
		-- DEEP ROOMS. The street wall grew from 16 studs deep to 32
		-- (Places' WALL[kind].d), so the room behind a shopfront went from a
		-- 14-stud slot to 30 studs -- but the three fit-outs were written for
		-- the slot and leave the new depth bare. Dress the middle from the kit
		-- kit so every room gains with the depth instead of just getting
		-- emptier. Deliberately only the CENTRE and the front wall: the back
		-- wall and the front-left corner are where the fit-outs put their
		-- shelving and their one thing to do, and a piece dropped on top of
		-- those would be the sort of bug nobody sees from the street.
		-- The per-type fit-outs are now in DRESS / FOOD_LAYOUT above; this is
		-- only what EVERY deep room gets regardless of trade.
		if d >= 28 then
			local ctx = venueCtx(v.spots)
			K.furn.rug(ctx, f * CFrame.new(0, 0.5, d / 6), w * 0.5, d * 0.32, tint(acc, 0.45))
			K.furn.pendant(ctx, f * CFrame.new(0, 0, d / 6), h, tint(l.color, 0.25))
			-- over the doorway, facing back into the room, where a customer
			-- queueing at the counter is looking anyway
			-- y 11.4: the clock is 4.2 across, so it clears the doorway header
			-- below (top 10.1) and the ceiling slab above (underside 13.7)
			K.furn.clock(ctx, f * CFrame.new(0, 11.4, -d / 2 + 1.3) * CFrame.Angles(0, math.pi, 0), acc)
		end
		table.insert(Build.venues, v)
		return h
	end

	-- a corner cafe in a housing block: its own little one-storey building
	function B.venue(l, i)
		local f = K.frameOf(l.pos, l.face)
		local w, d = 30, 24
		local h = venueRoom(f, w, d, l, i)
		local acc = l.accent or Cc.sage
		solid(P(V(w + 2, 1.4, d + 2), f * CFrame.new(0, h + 0.7, 0), shade(l.color, 0.1)))
		K.cornice(f, w, d, h + 1.4, tint(l.color, 0.2), acc)
		K.awning(f, 0, w - 2, 11.4, -d / 2, acc, Cc.cream)
		-- ONE name, used by the sign and by the destination record below. They
		-- used to fall back differently -- the sign to "CAFE", the record to
		-- nil -- so an unnamed venue was a building with a sign on it that the
		-- map's search could not find, and nothing said why.
		local name = l.name or "CAFE"
		local sgn = P(V(w - 6, 3.6, 0.6), f * CFrame.new(0, h + 3.4, -d / 2 + 0.4), shade(acc, 0.15))
		K.textOn(sgn, Enum.NormalId.Front, name, Cc.cream, Vector2.new(480, 80), 0.5)
		-- two tables out on the pavement
		for _, sx in { -9, 9 } do
			local t = f * CFrame.new(sx, 0, -d / 2 - 6)
			cyl(0.6, 3, t * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
			cyl(4.2, 0.4, t * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH)
			blob(V(7, 1.4, 7), t * CFrame.new(0, 8.4, 0), acc)
			cyl(0.3, 5, t * CFrame.new(0, 5.8, 0), Cc.ink, METAL)
		end
		table.insert(Build.destinations, { name = name, btype = l.btype, district = l.district, pos = l.door, shop = l.shop, interior = true })
	end

	-- AN APARTMENT TOWER: a residential high-rise, which is a different animal
	-- from the glass office skyscrapers -- masonry, a balcony on every floor,
	-- a proper canopied front door with the building's name over it, and a
	-- roof garden. The door is the way in to CityApts' lobby.
	---------------------------------------------------------------------------
	-- THE JOB CENTER. A civic building on the downtown block, facing out
	-- through the gateway in the street wall so its door reads from the road.
	--
	-- The BOARD inside is the point. You can open the same browser from the
	-- HUD once you have been here, but the first time has to be a walk: a job
	-- centre that was only ever a button would make the building scenery, and
	-- the rule in environment.md is that every street earns its place.
	---------------------------------------------------------------------------
	function B.jobcentre(l, i)
		local f = K.frameOf(l.pos, l.face)
		local w, d, h = 62, 38, 26
		local wall, acc = l.color or rgb(238, 244, 252), l.accent or rgb(96, 150, 230)
		-- THE SHELL IS A SHELL NOW, NOT A BLOCK. Everything below -- the floor,
		-- the board, the clerk, the chairs, the room light -- was built inside
		-- ONE SOLID 62 x 26 x 38 box, so the room existed and nobody could ever
		-- stand in it; and J.prompt only offers the board within 14 studs of
		-- it (CityJobs.lua), which is inside. Walls, a ceiling, and a genuine
		-- opening in the front wall for the door to stand in. Inner faces are
		-- set to meet what is already here: the floor edge is at +-29.5 x and
		-- +-17.5 z, the board's back is at z 17.0, the room light tops out at
		-- y 22.2.
		local gap = 6                                   -- half the doorway
		local pw = w / 2 - gap
		solid(P(V(w, h, 1.5), f * CFrame.new(0, h / 2, d / 2 - 0.75), wall))            -- back wall
		for _, sx in { -1, 1 } do
			solid(P(V(1.5, h, d), f * CFrame.new(sx * (w / 2 - 0.75), h / 2, 0), wall)) -- side walls
			solid(P(V(pw, h, 1.5), f * CFrame.new(sx * (gap + pw / 2), h / 2, -d / 2 + 0.75), wall))
		end
		solid(P(V(gap * 2, h - 10.5, 1.5), f * CFrame.new(0, 10.5 + (h - 10.5) / 2, -d / 2 + 0.75), wall)) -- over the door
		P(V(w, 1.5, d), f * CFrame.new(0, h - 2.75, 0), Cc.cream)                       -- ceiling
		solid(P(V(w + 5, 2, d + 5), f * CFrame.new(0, 1, 0), Cc.stone))
		P(V(w + 1.5, 3, d + 1.5), f * CFrame.new(0, h - 1.5, 0), acc)
		K.flatRoof(f, w, d, h + 1.5, shade(wall, 0.08))
		for k = 0, 5 do
			cyl(2.2, h - 6, f * CFrame.new(-22 + k * 8.8, (h - 6) / 2 + 2, -d / 2 - 3.4), Cc.cream)
		end
		P(V(w - 4, 3, 8), f * CFrame.new(0, h - 3, -d / 2 - 3), Cc.cream)
		-- the sign over the door
		K.sign(f * CFrame.new(0, h - 3, -d / 2 - 7.4), 34, 3.4, acc, Cc.cream, "JOB CENTER")
		-- steps up to an open door, with the green mat that means "come in"
		for k = 0, 2 do
			walkable(P(V(20 - k * 2, 0.8, 3 - k * 0.6), f * CFrame.new(0, 0.4 + k * 0.8, -d / 2 - 6 + k * 1.4), Cc.stone))
		end
		-- the door itself stands open: recess = false because the room IS the
		-- hall (a back wall built 4 studs in would seal the doorway again), and
		-- mat = false because this door is up a flight of steps, so the mat is
		-- laid by hand below
		K.openDoor(f, 0, -d / 2 - 0.2, acc, true, { recess = false, mat = false })
		-- and the mat goes at the FOOT of the steps, on the pavement. It used
		-- to lie at y 2.6 and 6 studs deep, which is the height of the TOP step
		-- across the whole flight -- so it hung in the air over the two below
		-- it. At the bottom it reads the way it should anyway: the way in
		-- starts here, and the stairs are what you do next.
		K.threshold(f * CFrame.new(0, 0.06, -d / 2 - 9.6), 20, 5)
		for _, sx in { -1, 1 } do
			K.window(f * CFrame.new(sx * 20, 12, -d / 2 - 0.2), 10, 9, nil, nil, true)
			K.planter(f * CFrame.new(sx * 26, 0, -d / 2 - 7), 3.4)
		end
		-- INSIDE: a floor, a lit room, and the board on the back wall
		walkable(P(V(w - 3, 0.5, d - 3), f * CFrame.new(0, 2.25, 0), rgb(226, 220, 208), SMOOTH))
		roomLight(f * CFrame.new(0, h - 5, 0), 70, 1.2)
		local bf = f * CFrame.new(0, 0, d / 2 - 2.6)
		solid(P(V(40, 14, 1.2), bf * CFrame.new(0, 9.5, 0), shade(acc, 0.2)))
		local face = P(V(36, 11, 0.5), bf * CFrame.new(0, 9.5, -1), Cc.cream)
		K.textOn(face, Enum.NormalId.Front, "OPEN POSITIONS\n\nTAXI  \u{00B7}  DELIVERIES  \u{00B7}  CLEANING\nFARM HAND  \u{00B7}  PIZZERIA COOK\n\nwalk up to apply", acc, Vector2.new(700, 220), 0)
		-- little paper notices pinned around the board
		for k = 0, 5 do
			local px = -15 + (k % 3) * 15
			local pz = (k < 3) and 1 or -1
			P(V(5, 6.4, 0.2), bf * CFrame.new(px + pz * 0.5, 3.6, -1.1) * CFrame.Angles(0, 0, (k % 2 == 0) and 0.06 or -0.05),
				({ rgb(255, 244, 214), rgb(226, 240, 255), rgb(255, 226, 226) })[k % 3 + 1])
		end
		table.insert(Build.spots, { pos = (bf * CFrame.new(0, 0, -5)).Position - CITY, kind = "jobboard" })
		-- a clerk at a desk on the left, and a couple of chairs to wait in
		local df = f * CFrame.new(-w / 2 + 12, 0, 4)
		solid(P(V(11, 3.4, 5), df * CFrame.new(0, 1.7 + 2.5, 0), shade(acc, 0.1), WOODM))
		P(V(11.6, 0.4, 5.6), df * CFrame.new(0, 3.6 + 2.5, 0), Cc.cream)
		P(V(1.6, 1.2, 1.4), df * CFrame.new(3, 4.4 + 2.5, 0), Cc.ink, SMOOTH)
		local clerk = Models.buildSminski(K.cur, 1, Config.Characters[(i * 3 + 4) % #Config.Characters + 1], false, "tie")
		Models.poseSminski(clerk, df * CFrame.new(0, 2.5, 3.2) * CFrame.Angles(0, math.pi, 0), "idle", i)
		for k = 0, 2 do
			local scf = f * CFrame.new(w / 2 - 10, 2.5, -6 + k * 5) * CFrame.Angles(0, -math.pi / 2, 0)
			cyl(0.5, 1.8, scf * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
			cyl(2.2, 0.5, scf * CFrame.new(0, 2, 0), acc, SMOOTH)
			P(V(0.6, 3, 4), scf * CFrame.new(-1.6, 3.4, 0), acc, Enum.Material.Fabric)
			if k == 1 then
				local wait = Models.buildSminski(K.cur, 1, Config.Characters[(i * 7 + 2) % #Config.Characters + 1], false, nil)
				Models.poseSminski(wait, scf * CFrame.new(0, 1.15, 0), "sit", i * 3)
			end
		end
		-- register it as somewhere the city knows about, so wayfinding and the
		-- taxi can take you here like anywhere else
		Build.destinations = Build.destinations or {}
		table.insert(Build.destinations, { name = "the Job Center", pos = l.door, kind = "jobcentre", district = l.district, interior = true })
		return h
	end

	-- a workplace: the venue shell, fitted out as a kitchen with stations
	function B.workplace(l, i)
		local f = K.frameOf(l.pos, l.face)
		local w, d = 46, 34
		local h = venueRoom(f, w, d, l, i)
		local acc = l.accent or Cc.sage
		solid(P(V(w + 2, 1.4, d + 2), f * CFrame.new(0, h + 0.7, 0), shade(l.color, 0.1)))
		K.cornice(f, w, d, h + 1.4, tint(l.color, 0.2), acc)
		K.awning(f, 0, w - 2, 11.4, -d / 2, acc, Cc.cream)
		local sgn = P(V(w - 8, 4, 0.6), f * CFrame.new(0, h + 3.6, -d / 2 + 0.4), shade(acc, 0.15))
		K.textOn(sgn, Enum.NormalId.Front, l.name or "KITCHEN", Cc.cream, Vector2.new(560, 90), 0.5)
		-- two pavement tables, so it reads as a restaurant from the street
		for _, sx in { -13, 13 } do
			local t = f * CFrame.new(sx, 0, -d / 2 - 6)
			cyl(0.6, 3, t * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
			solid(cyl(4.2, 0.4, t * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH))
			for _, sz in { -3.4, 3.4 } do
				cyl(0.5, 1.8, t * CFrame.new(0, 0.9, sz), Cc.ink, METAL)
				cyl(2, 0.5, t * CFrame.new(0, 2, sz), acc, SMOOTH)
			end
		end
		Build.destinations = Build.destinations or {}
		table.insert(Build.destinations, { name = l.name, pos = l.door, kind = "workplace", work = l.restaurant })
		return h
	end

	function B.aptTower(id, a)
		local f = K.frameOf(a.pos, a.face)
		local w, d, fh = a.w, a.d, 12
		local h = 20 + a.floors * fh
		local T = K.TEX[a.tex] or K.TEX.cream
		local acc = a.accent
		-- A TWO-STOREY BASE, CARVED ROUND THE LOBBY DOORWAY, then the shaft.
		-- It was one solid block, so K.openDoor's hall was built INSIDE it,
		-- where nothing shows -- which left a flat dark panel sitting on the
		-- podium face, i.e. a painted-on shut door on the one building in town
		-- whose whole point is that you go in (CityApts' lobby). The niche is
		-- 4.2 deep from the podium face; the door plane sits 0.4 inside that,
		-- so the hall has 3.8 studs to stand in.
		local pw, pd = w + 6, d + 6
		local gap, nd = 6, 4.2                -- half-width, depth of the opening
		local pier = pw / 2 - gap
		for _, sx in { -1, 1 } do
			solid(P(V(pier, 20, pd), f * CFrame.new(sx * (gap + pier / 2), 10, 0), Cc.cream))
		end
		solid(P(V(gap * 2, 20, pd - nd), f * CFrame.new(0, 10, nd / 2), Cc.cream))
		solid(P(V(gap * 2, 9, nd), f * CFrame.new(0, 15.5, -pd / 2 + nd / 2), Cc.cream))
		P(V(w + 7, 1.6, d + 7), f * CFrame.new(0, 0.8, 0), Cc.stone)
		P(V(w + 7, 1.4, d + 7), f * CFrame.new(0, 20.2, 0), acc)
		local shaft = solid(P(V(w, h - 20, d), f * CFrame.new(0, 20 + (h - 20) / 2, 0), T.col))
		K.texture(shaft, T.id, 32, 48)
		-- every floor: a window band on all four sides, a balcony on the front
		for k = 0, a.floors - 1 do
			local y = 20 + k * fh + fh / 2
			for _, side in { { 0, d / 2, w }, { math.pi, d / 2, w }, { math.pi / 2, w / 2, d }, { -math.pi / 2, w / 2, d } } do
				local sf = f * CFrame.Angles(0, side[1], 0) * CFrame.new(0, y, -side[2] - 0.15)
				P(V(side[3] - 8, 6.4, 0.4), sf, Cc.pane, SMOOTH, { reflect = 0.12 })
			end
			if k % 2 == 0 then
				local bf = f * CFrame.new(0, 20 + k * fh, -d / 2 - 2.6)
				P(V(w - 14, 0.7, 5), bf * CFrame.new(0, 0.35, 0), Cc.cream)
				P(V(w - 14, 3, 0.4), bf * CFrame.new(0, 2, -2.4), acc, SMOOTH, { transparency = 0.35 })
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do P(V(3, h - 20, 3), f * CFrame.new(sx * (w / 2 - 0.5), 20 + (h - 20) / 2, sz * (d / 2 - 0.5)), Cc.cream) end
		end
		-- the front door: glass, a deep canopy on two posts, the name in lights
		local df = f * CFrame.new(0, 0, -d / 2 - 3.2)
		-- glass either side, a doorway you can see into in the middle
		for _, sx in { -1, 1 } do
			local g = P(V(7, 13, 0.5), df * CFrame.new(sx * 7.5, 7, 0), rgb(214, 236, 244), SMOOTH, { transparency = 0.3, reflect = 0.15 })
			g.CastShadow = false
		end
		-- 3.8 = nd - 0.4, the niche behind the door plane (see the podium above)
		K.openDoor(df * CFrame.new(0, 0, 0.6), 0, 0, acc, true, { recess = nd - 0.4 })
		P(V(24, 1.2, 1), df * CFrame.new(0, 14, -0.2), acc)
		for _, sx in { -4.8, 4.8 } do P(V(0.6, 13, 0.8), df * CFrame.new(sx, 7, -0.2), Cc.cream) end
		P(V(30, 1.4, 14), df * CFrame.new(0, 16, -6.5), acc)
		P(V(31, 0.5, 15), df * CFrame.new(0, 16.9, -6.5), Cc.cream)
		for _, sx in { -13, 13 } do solid(cyl(1.2, 16, df * CFrame.new(sx, 8, -12), Cc.cream)) end
		local sgn = P(V(30, 3, 0.4), df * CFrame.new(0, 16, -13.7), Cc.ink)
		K.textOn(sgn, Enum.NormalId.Front, Config.AptBuilding(id).name, rgb(255, 232, 180), Vector2.new(620, 66), 0)
		P(V(14, 0.16, 16), df * CFrame.new(0, 0.1, -8), rgb(196, 80, 90), Enum.Material.Fabric, { noShadow = true })
		for _, sx in { -10, 10 } do K.planter(df * CFrame.new(sx, 0, -5), 4) end
		-- crown: a parapet, a roof garden, a water tower
		P(V(w + 2, 3, d + 2), f * CFrame.new(0, h + 1.5, 0), Cc.cream)
		P(V(w - 6, 0.6, d - 6), f * CFrame.new(0, h + 0.4, 0), Cc.grass2, MATTE, { noShadow = true })
		for k = 0, 3 do blob(V(7, 5, 7), f * CFrame.new(-w / 2 + 10 + k * (w - 20) / 3, h + 3.4, d / 4), k % 2 == 0 and Cc.leaf or Cc.leaf3) end
		K.waterTower(f * CFrame.new(w / 4, h + 3, -d / 4), 0.9)
		table.insert(Build.destinations, { name = Config.AptBuilding(id).name, btype = "home", district = "residential", pos = Places.aptDoor(id), interior = true })
	end

	-- A CORNER BUILDING: 17 studs square, a floor taller than its neighbours,
	-- glazed on both street faces, with a little domed cupola. It closes the
	-- corner of a street wall the way a real block is closed.
	function B.corner(l, i)
		local f = K.frameOf(l.pos, l.face)
		local w, fh = 17, 12
		local floors = l.floors or 5
		local h = 14 + (floors - 1) * fh
		local col, acc = l.color, l.accent or Cc.sage
		solid(P(V(w, h, w), f * CFrame.new(0, h / 2, 0), col))
		P(V(w + 0.5, 14, w + 0.5), f * CFrame.new(0, 7, 0), shade(col, 0.07))
		P(V(w + 0.8, 1.4, w + 0.8), f * CFrame.new(0, 0.7, 0), Cc.stone)
		-- two street faces: the lot's own (-Z) and the side street (lateral X)
		local faces = { f * CFrame.new(0, 0, -w / 2 - 0.2), f * CFrame.new(l.lateral * (w / 2 + 0.2), 0, 0) * CFrame.Angles(0, -l.lateral * math.pi / 2, 0) }
		for _, sf in faces do
			local g = P(V(11, 9, 0.4), sf * CFrame.new(0, 6.6, 0), Cc.pane, SMOOTH, { reflect = 0.1 })
			g.CastShadow = false
			P(V(12, 0.8, 1.2), sf * CFrame.new(0, 1.8, -0.3), Cc.stone)
			P(V(13, 2.6, 0.5), sf * CFrame.new(0, 12.6, -0.3), shade(acc, 0.12))
			for k = 1, floors - 1 do
				local y = 14 + (k - 1) * fh + fh / 2
				P(V(9, 8.2, 0.4), sf * CFrame.new(0, y, 0), Cc.cream)
				P(V(7.6, 6.8, 0.5), sf * CFrame.new(0, y, -0.1), Cc.pane, SMOOTH, { reflect = 0.08 })
				P(V(9.8, 0.7, 1.2), sf * CFrame.new(0, y - 4.5, -0.4), Cc.cream)
			end
		end
		-- one name for the sign AND the destination record, as in B.venue: the
		-- record used to hold nil where the sign said SHOP, which hides the
		-- corner from a search by name
		local name = l.name or "SHOP"
		local sgn = P(V(13, 2.2, 0.3), faces[1] * CFrame.new(0, 12.6, -0.6), shade(acc, 0.12))
		K.textOn(sgn, Enum.NormalId.Front, name, Cc.cream, Vector2.new(320, 60), 0.5)
		K.cornice(f, w, w, h, tint(col, 0.2), acc)
		-- the cupola
		cyl(9, 5, f * CFrame.new(0, h + 3.5, 0), tint(col, 0.25))
		blob(V(10, 7, 10), f * CFrame.new(0, h + 6.4, 0), acc)
		cyl(0.5, 5, f * CFrame.new(0, h + 11.5, 0), Cc.gold, METAL)
		table.insert(Build.destinations, { name = name, btype = l.btype, district = l.district, pos = l.door, shop = l.shop, interior = false })
	end

	-- A DOWNTOWN MID-RISE: the street wall. 16 studs deep, 3-6 floors, its
	-- face flush to the sidewalk so there is no gap between pavement and
	-- building. Ground floor is a real storefront (glass, awning, sign); the
	-- floors above are apartments and offices. Built shoulder to shoulder
	-- these form a solid block you cannot see through, which is the whole
	-- point -- see docs/ROADMAP.md on sightlines.
	function B.midrise(l, i)
		local f = K.frameOf(l.pos, l.face)
		-- DEPTH comes from the lot now (Places.WALL[kind].d), not from a
		-- constant. The lot was placed at 116 - d/2 so the street face lands on
		-- 116 whatever d is: the door line, the awning, the sign and every
		-- pavement offset the server does arithmetic on are unmoved, and only
		-- the back wall travels into the hollow middle of the block.
		-- 16 is the old value and the fallback, for the shopstreet mid-rises
		-- and anything else that does not ask.
		local w, d = l.w or 38, l.d or 16
		local fh = 12                        -- floor height
		local floors = l.floors or 4
		local h = 14 + (floors - 1) * fh     -- taller ground floor
		local col, acc = l.color, l.accent or Cc.sage
		local sf = f * CFrame.new(0, 0, -d / 2 - 0.2)  -- the street face
		if l.interior then
			-- a food place: the ground floor is a room you can walk into,
			-- and only the floors above it are solid
			venueRoom(f, w, d, l, i)
			solid(P(V(w, h - 14, d), f * CFrame.new(0, 14 + (h - 14) / 2, 0), col))
		else
			solid(P(V(w, h, d), f * CFrame.new(0, h / 2, 0), col))
			-- ground floor in a deeper tone, on a stone plinth
			P(V(w + 0.5, 14, d + 0.5), f * CFrame.new(0, 7, 0), K.shade(col, 0.06))
			P(V(w + 0.8, 1.4, d + 0.8), f * CFrame.new(0, 0.7, 0), Cc.stone)
			-- shopfront glass either side of a recessed door
			local gx, gw = w * 0.29, w * 0.34
			for _, sx in { -1, 1 } do
				K.glassBand(sf * CFrame.new(sx * gx, 7, 0), gw, 9, Cc.pane, 3)
				P(V(gw + 0.6, 0.8, 1.6), sf * CFrame.new(sx * gx, 2.2, -0.6), Cc.stone)
			end
			P(V(8, 11, 0.6), sf * CFrame.new(0, 5.6, 0), acc)
			P(V(6.2, 9.4, 0.4), sf * CFrame.new(0, 5.1, -0.4), K.tint(acc, 0.35))
			P(V(10, 0.5, 2.2), sf * CFrame.new(0, 0.25, -1.1), Cc.stone)
		end
		-- awning + the shop's signboard above it
		K.awning(f, 0, w - 2, 13.4, -d / 2, acc, Cc.cream)
		-- same one-name rule as B.venue / B.corner: what the sign says is what
		-- the destination record carries, so the map can find it
		local name = l.name or "SHOP"
		local sgn = P(V(w - 4, 4.4, 0.6), sf * CFrame.new(0, 17.4, -0.5), K.shade(acc, 0.15))
		K.textOn(sgn, Enum.NormalId.Front, name, Cc.cream, Vector2.new(520, 90), 0.5)
		-- the floors above: real windows, no glowing rectangles by day
		for k = 1, floors - 1 do
			local y = 14 + (k - 1) * fh + fh / 2
			for _, sx in (w < 34 and { -7.5, 7.5 } or { -12, 0, 12 }) do
				K.window(sf * CFrame.new(sx, y, -0.1), 7.4, 7, k % 3 == 0 and Cc.cream or nil)
			end
			-- an end wall nobody built against: glaze it, so an alley or a
			-- gateway is lined with windows instead of blank plaster
			for _, sx in { l.openL and 1 or 0, l.openR and -1 or 0 } do
				if sx ~= 0 then
					local ef = f * CFrame.new(sx * (w / 2 + 0.15), y, 0)
					P(V(0.5, 8, 7.6), ef, Cc.cream)
					P(V(0.6, 6.8, 6.4), ef * CFrame.new(sx * 0.1, 0, 0), Cc.pane, SMOOTH, { reflect = 0.08 })
				end
			end
		end
		-- a cornice so the roofline has a shadow, and rooftop clutter
		K.cornice(f, w, d, h, K.tint(col, 0.2), acc)
		-- fire escapes start ABOVE the shopfront and off to one side: the ground
		-- floor is a real doorway now, and a ladder across it blocks the way in
		if i % 3 == 0 and floors > 2 then K.fireEscape(sf * CFrame.new(-w / 4, 14, -1.2), floors - 2, fh) end
		if i % 5 == 0 then K.waterTower(f * CFrame.new(0, h + 3, 0), 0.6) end
		for k = -1, 1, 2 do
			P(V(5, 3, 4), f * CFrame.new(k * 9, h + 1.6, 2), rgb(176, 178, 176), METAL)
		end
		-- register the destination so activities can be hung off it later
		table.insert(Build.destinations, {
			name = name, btype = l.btype, district = l.district,
			pos = l.door, shop = l.shop, interior = l.interior,
		})
	end

	local function midtown(cx, cz, towers)
		local built = {}
		for _, t in towers do
			t.x, t.z = cx + t.x, cz + t.z
			-- face the street nearest to the tower (its lobby door + sign)
			local dx, dz = t.x - cx, t.z - cz
			-- the lobby is on the tower's local -Z side
			if math.abs(dz) >= math.abs(dx) then t.face = dz > 0 and math.pi or 0 else t.face = dx > 0 and -math.pi / 2 or math.pi / 2 end
			table.insert(built, K.skyscraper(t))
		end
		-- a pocket plaza in the middle of the block
		local c = W(cx, PAD, cz)
		P(V(34, 0.12, 34), c * CFrame.new(0, 0.06, 0), Cc.pave, MATTE, { noShadow = true })
		K.tree(cx - 8, cz - 8, 0.8)
		K.tree(cx + 8, cz + 8, 0.8)
		K.bench(c * CFrame.Angles(0, 0.8, 0))
		return built
	end
	-- Times Square: giant billboards facing the big crossroads at (0, 0)
	local function timesSquare(cx, cz)
		local ix, iz = -sx0(cx), -sx0(cz) -- towards the crossroads
		local corner = V(cx + ix * 100, 0, cz + iz * 100)
		local imgs = K.BILLBOARDS
		-- one billboard facing each road, stacked high on the corner tower
		for k = 0, 1 do
			local y = 40 + k * 44
			local bx = CFrame.lookAt(CITY + V(cx + ix * 103, PAD + y, cz + iz * 62), CITY + V(cx + ix * 200, PAD + y, cz + iz * 62))
			K.billboard(bx, 48, 27, imgs[(math.abs(cx + cz) / 150 + k) % #imgs + 1])
			local bz = CFrame.lookAt(CITY + V(cx + ix * 62, PAD + y, cz + iz * 103), CITY + V(cx + ix * 62, PAD + y, cz + iz * 200))
			K.billboard(bz, 48, 27, imgs[(math.abs(cx - cz) / 150 + k + 1) % #imgs + 1])
		end
		-- a neon ticker wrapping the podium corner
		local tk = P(V(0.4, 2.2, 60), CFrame.new(CITY + V(cx + ix * 103, PAD + 27, cz + iz * 62)), rgb(255, 214, 120), NEON)
		tk.CastShadow = false
		K.textOn(tk, ix > 0 and Enum.NormalId.Right or Enum.NormalId.Left, "SMINSKI CITY  ·  NOW OPEN  ·  SMINSKI CITY", rgb(80, 120, 80), Vector2.new(1400, 60), 0)
		-- a hot dog cart + a subway entrance on the corner
		K.cart(W(corner.X + ix * 10, PAD, corner.Z - iz * 20) * CFrame.Angles(0, ix > 0 and -math.pi / 2 or math.pi / 2, 0), "HOT DOGS", Cc.red)
		K.subway(W(corner.X + ix * 8, PAD, corner.Z + iz * 18) * CFrame.Angles(0, iz > 0 and math.pi or 0, 0))
		table.insert(Build.subways, V(corner.X + ix * 8, 0, corner.Z + iz * 18))
	end
	Build.subways = {}
	-- every place in town worth walking to, filled in as blocks build.
	-- Jobs, shops, quests and NPC spawns read this instead of hard-coding
	-- positions, so new content scales with the city (see docs/ROADMAP.md).
	Build.destinations = {}
	function B.towersW(cx, cz)
		midtown(cx, cz, {
			{ x = 62, z = -62, w = 76, d = 76, h = 300, tex = "blue", crown = "spire", name = "SKYLINE", neon = "SMINSKI" },
			{ x = -62, z = -62, w = 70, d = 70, h = 170, tex = "pink", crown = "water", neon = "HOTEL" },
			{ x = -62, z = 62, w = 72, d = 76, h = 220, tex = "lav", crown = "garden", name = "HOTEL SMINSKI", neon = "ARCADE" },
			{ x = 62, z = 62, w = 76, d = 72, h = 360, tex = "teal", crown = "antenna", name = "CLOUD TOWER", neon = "CLOUD" },
		})
		timesSquare(cx, cz)
	end
	function B.towersE(cx, cz)
		midtown(cx, cz, {
			{ x = -60, z = -60, w = 80, d = 80, h = 430, tex = "blue", crown = "deco", name = "SMINSKI STATE BUILDING" },
			{ x = 62, z = -62, w = 70, d = 70, h = 230, tex = "lav", crown = "garden", neon = "CINEMA" },
			{ x = 62, z = 62, w = 72, d = 76, h = 180, tex = "cream", crown = "water", name = "MOCHI APARTMENTS", neon = "MOCHI" },
			{ x = -62, z = 62, w = 76, d = 72, h = 280, tex = "teal", crown = "spire", name = "SMINSKI BANK TOWER", neon = "BANK" },
		})
		timesSquare(cx, cz)
	end
	---------------------------------------------------------------------------
	-- SHOPPING
	---------------------------------------------------------------------------
	local ROOF_TOYS = {}
	function ROOF_TOYS.CAFE(cf)
		cyl(9, 9, cf * CFrame.new(0, 4.5, 0), Cc.cream)
		cyl(9.6, 0.8, cf * CFrame.new(0, 9, 0), rgb(236, 226, 210))
		cyl(7.8, 0.6, cf * CFrame.new(0, 9.2, 0), rgb(150, 100, 70))
		P(V(1.2, 4.6, 4.6), cf * CFrame.new(5.1, 5, 0), Cc.cream)
	end
	function ROOF_TOYS.BAKERY(cf)
		local d = cf * CFrame.new(0, 5, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			ball(3.8, d * CFrame.new(math.cos(a) * 3.8, 0, math.sin(a) * 3.8), rgb(222, 164, 110))
			ball(3.2, d * CFrame.new(math.cos(a) * 3.8, -1, math.sin(a) * 3.8), rgb(255, 170, 200))
		end
	end
	ROOF_TOYS["ICE CREAM"] = function(cf)
		local cone = cf * CFrame.new(0, 4.6, 0)
		for k = 0, 4 do cyl(5.2 - k, 1.8, cone * CFrame.new(0, -k * 1.6 + 3, 0), rgb(226, 172, 110)) end
		ball(6.4, cone * CFrame.new(0, 6.4, 0), rgb(255, 196, 220))
		ball(5.4, cone * CFrame.new(0, 10.8, 0), rgb(250, 244, 226))
		ball(1.4, cone * CFrame.new(0, 13.8, 0), Cc.red)
	end
	function ROOF_TOYS.FLOWERS(cf)
		P(V(0.9, 7, 0.9), cf * CFrame.new(0, 3.5, 0), Cc.leaf3)
		local head = cf * CFrame.new(0, 9, 0) * CFrame.Angles(math.pi / 2 - 0.3, 0, 0)
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			blob(V(3.8, 2, 3.8), head * CFrame.new(math.cos(a) * 2.9, 0, math.sin(a) * 2.9), rgb(255, 160, 196))
		end
		ball(3.2, head, Cc.gold)
	end
	function ROOF_TOYS.BOOKS(cf)
		for k, c in { rgb(120, 160, 220), rgb(236, 130, 120), rgb(140, 196, 130) } do
			P(V(10 - k, 2.4, 7), cf * CFrame.new(0, 1.2 + (k - 1) * 2.4, 0) * CFrame.Angles(0, k * 0.2, 0), c)
		end
	end
	function ROOF_TOYS.DINER(cf)
		cyl(10, 1.6, cf * CFrame.new(0, 2, 0), rgb(226, 170, 100))
		cyl(10.4, 1, cf * CFrame.new(0, 3.2, 0), rgb(150, 90, 60))
		cyl(10.6, 0.4, cf * CFrame.new(0, 3.9, 0), rgb(255, 214, 90))
		blob(V(10, 3, 10), cf * CFrame.new(0, 4.8, 0), rgb(236, 180, 110))
	end
	function ROOF_TOYS.MUSIC(cf)
		local n = cf * CFrame.new(0, 2, 0)
		blob(V(4, 3, 3), n * CFrame.new(-2, 1.4, 0), Cc.ink)
		P(V(0.8, 10, 0.8), n * CFrame.new(-0.4, 6, 0), Cc.ink)
		P(V(4, 1.2, 0.8), n * CFrame.new(1.4, 10.4, 0) * CFrame.Angles(0, 0, -0.4), Cc.ink)
	end
	ROOF_TOYS["PET SHOP"] = function(cf)
		blob(V(8, 7, 6), cf * CFrame.new(0, 4, 0), rgb(236, 214, 180))
		for _, sx in { -2.6, 2.6 } do blob(V(2.2, 4, 1.4), cf * CFrame.new(sx, 8, 0) * CFrame.Angles(0, 0, sx * 0.12), rgb(200, 160, 120)) end
		for _, sx in { -1.4, 1.4 } do ball(0.9, cf * CFrame.new(sx, 5, -3), Cc.ink) end
	end

	-- a Sminski shopfront (styled after the cafe in the key art): cream or
	-- butter walls, a chunky cornice, a big sage signboard, a striped awning,
	-- warm-lit windows, a yellow door, planters and a "help wanted" card
	function B.shop(l)
		local f = K.frameOf(l.pos, l.face)
		local w, d, h = 44, 36, 26
		local col, acc = l.color, l.accent or Cc.sage
		local door = rgb(250, 214, 110)
		solid(P(V(w, h, d), f * CFrame.new(0, h / 2, 0), col))
		-- ground floor: a slightly deeper tone + a sage plinth
		P(V(w + 0.6, 14, d + 0.6), f * CFrame.new(0, 7, 0), K.shade(col, 0.04))
		P(V(w + 0.9, 1.6, d + 0.9), f * CFrame.new(0, 0.8, 0), acc)
		for _, sx in { -1, 1 } do
			P(V(2.2, 14, 2.2), f * CFrame.new(sx * (w / 2 - 0.2), 7, -d / 2 - 0.2), acc)
			P(V(2.8, 1, 2.8), f * CFrame.new(sx * (w / 2 - 0.2), 14.4, -d / 2 - 0.2), Cc.cream)
		end
		-- the door (butter yellow, round-topped window)
		local df = f * CFrame.new(0, 0, -d / 2 - 0.3)
		P(V(9, 11, 0.6), df * CFrame.new(0, 5.8, 0), acc)
		P(V(7, 9.6, 0.4), df * CFrame.new(0, 5.1, -0.4), door)
		P(V(4.4, 3.4, 0.3), df * CFrame.new(0, 7, -0.62), rgb(236, 222, 190), SMOOTH, { reflect = 0.08 })
		ball(0.7, df * CFrame.new(2.4, 4.8, -0.8), Cc.gold, METAL)
		P(V(10, 0.5, 2.4), df * CFrame.new(0, 0.25, -1.2), Cc.stone)
		-- big warm shop windows with sage frames + a display shelf
		for _, sx in { -1, 1 } do
			local wf = f * CFrame.new(sx * 13.5, 6.4, -d / 2 - 0.2)
			P(V(14.6, 9.6, 0.5), wf, acc)
			P(V(13, 8, 0.4), wf * CFrame.new(0, 0, -0.1), Cc.cream)
			-- shop windows are glass with a warm room behind them, not glowing panels
			local g = P(V(12, 7, 0.3), wf * CFrame.new(0, 0, -0.3), rgb(236, 220, 184), SMOOTH, { reflect = 0.08 })
			g.Transparency = 0.1
			g.CastShadow = false
			P(V(0.5, 7, 0.4), wf * CFrame.new(0, 0, -0.45), Cc.cream)
			P(V(14.6, 0.8, 1.8), wf * CFrame.new(0, -5.2, -0.6), Cc.cream)
			for k = 0, 3 do ball(1.3, wf * CFrame.new(-4.5 + k * 3, -2.6, -0.8), ({ Cc.leaf2, Cc.butter, rgb(255, 180, 200), Cc.cream })[k + 1]) end
		end
		-- HELP WANTED card in one window
		if (#l.name + math.floor(l.pos.X)) % 2 == 0 then
			local hw = P(V(4.6, 3.4, 0.2), f * CFrame.new(13.5, 7.6, -d / 2 - 0.8), rgb(250, 250, 246))
			K.textOn(hw, Enum.NormalId.Front, "HELP WANTED", rgb(210, 70, 70), Vector2.new(160, 120), 0.6)
		end
		-- the striped awning (sage + cream) with a scalloped trim
		K.awning(f, 0, w - 1, 14.2, -d / 2, acc, Cc.cream)
		-- the big signboard across the top floor
		local sgn = f * CFrame.new(0, 19.2, -d / 2 - 0.6)
		P(V(w - 4, 6.4, 0.8), sgn, Cc.cream)
		local board = P(V(w - 6, 5.2, 0.6), sgn * CFrame.new(0, 0, -0.4), acc)
		K.textOn(board, Enum.NormalId.Front, "SMINSKI " .. l.name, Cc.cream, Vector2.new(720, 110), 0.35)
		K.cornice(f, w, d, h, Cc.cream, acc)
		K.sideWindows(f, w, d, 1, 19, 0, nil, 2)
		local toy = ROOF_TOYS[l.name]
		if toy then toy(f * CFrame.new(0, h + 2, 4)) end
		-- planters by the door, a bench, a little cafe table
		for _, sx in { -1, 1 } do K.planter(f * CFrame.new(sx * 7, 0, -d / 2 - 3.5), 3) end
		local tcf = f * CFrame.new(-13, 0, -d / 2 - 7)
		cyl(3.6, 0.35, tcf * CFrame.new(0, 3, 0), Cc.cream)
		P(V(0.5, 3, 0.5), tcf * CFrame.new(0, 1.5, 0), Cc.lampPost)
		for _, cz in { -2.8, 2.8 } do cyl(1.8, 1.8, tcf * CFrame.new(cz, 0.9, 0), acc) end
		K.bench(f * CFrame.new(13, 0, -d / 2 - 7) * CFrame.Angles(0, math.pi, 0))
	end
	function B.shopstreet(cx, cz)
		for i, l in lotsIn(cx, cz) do
			if l.kind == "shop" then B.shop(l) end
			if i % 3 == 1 then
				worker("sweep", K.frameOf(l.pos, l.face) * CFrame.new(18, 0, -30) * CFrame.Angles(0, math.pi + 0.5, 0), i)
			end
		end
		worker("read", W(cx, PAD, cz) * CFrame.new(0, 0, 14) * CFrame.Angles(0, math.pi, 0), 4)
		local c = W(cx, PAD, cz)
		P(V(60, 0.12, 60), c * CFrame.new(0, 0.06, 0), Cc.pave, MATTE, { noShadow = true })
		solid(cyl(16, 2, c * CFrame.new(0, 1, 0), Cc.stone))
		cyl(14, 2.1, c * CFrame.new(0, 1.1, 0), Cc.water, SMOOTH)
		ball(4, c * CFrame.new(0, 3, 0), rgb(255, 196, 220))
		for _, a in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			K.bench(CFrame.lookAt(c.Position + V(math.sin(a), 0, math.cos(a)) * 14, c.Position + V(math.sin(a), 0, math.cos(a)) * 30))
		end
		for _, p in { V(-26, 0, -26), V(26, 0, 26), V(-26, 0, 26), V(26, 0, -26) } do K.tree(cx + p.X, cz + p.Z, 0.9) end
	end

	-- THE MALL: two floors, glass atrium, escalator ramps, 16 shop units
	--
	-- EVERY UNIT NOW HAS A PROMPT AND ITS OWN STOCK. Seven had neither: the
	-- ground floor's seven interactive units are wired through
	-- Places.CityBiz / Places.MallShops, and the other nine were scenery whose
	-- entire contents were the same 48 balls on the same four shelves, with
	-- FOOD COURT listed twice (docs/WORLD_REVAMP.md §4.4).
	--
	-- Element 7 is the fit-out. Units with a `kind` (the ground floor) are
	-- prompted by City.lua from Places; units with a `fit` and no `kind` are
	-- registered here as venues, with the spot deliberately at the BACK of the
	-- unit -- a mall unit is 67 studs deep and the ground-floor prompt zones
	-- are at its mouth, so a spot at the back cannot shadow the floor below.
	local MALL_UNITS = {
		-- x, side (1 = north), floor, name, accent, kind, fit
		{ 364, 1, 0, "BUBBLE TEA", rgb(180, 150, 230), "boba", "food" }, { 400, 1, 0, "SWEET SHOP", rgb(255, 150, 190), "sweets", "sweets" },
		{ 500, 1, 0, "BOUTIQUE", rgb(140, 190, 240), "boutique", "clothes" }, { 536, 1, 0, "CAPSULE CORNER", rgb(255, 196, 110), "capsules", "capsules" },
		{ 364, -1, 0, "TOY STORE", rgb(120, 200, 150), "toys", "toys" }, { 400, -1, 0, "POWER-UPS", rgb(255, 170, 120), "powerups", "tech" },
		{ 500, -1, 0, "PIZZA PLACE", rgb(236, 120, 100), "pizza", "food" }, { 536, -1, 0, "CHARACTER SHOP", rgb(150, 190, 160), "skins", "skins" },
		{ 364, 1, 1, "BOOKS", rgb(130, 110, 90), nil, "books" }, { 400, 1, 1, "RECORDS", rgb(120, 130, 210), nil, "music" },
		{ 500, 1, 1, "SHOES", rgb(230, 150, 120), nil, "shoes" }, { 536, 1, 1, "PHOTO BOOTH", rgb(255, 180, 200), nil, "photo" },
		{ 364, -1, 1, "FOOD COURT", rgb(255, 206, 110), nil, "court" }, { 400, -1, 1, "NOODLE BAR", rgb(236, 140, 90), nil, "noodles" },
		{ 500, -1, 1, "CANDLES", rgb(236, 190, 150), nil, "candles" }, { 536, -1, 1, "MALL CAFE", rgb(150, 96, 70), nil, "cafe" },
	}
	-- what is in a mall unit, and what you can do in it. Built entirely from
	-- K.furn -- the point of the kit is that sixteen distinct shops cost
	-- sixteen short rows, not sixteen builders.
	local MALL_FIT = {}
	do
		local function L(c, f, uw, dep, z) return f * CFrame.new(-uw / 2 + 3.2, 0, z) * CFrame.Angles(0, -math.pi / 2, 0) end
		local function R2(c, f, uw, dep, z) return f * CFrame.new(uw / 2 - 3.2, 0, z) * CFrame.Angles(0, math.pi / 2, 0) end
		MALL_FIT.books = function(c, f, uw, dep, acc, x)
			K.furn.shelving(c, L(c, f, uw, dep, 4), 20, { rgb(150, 110, 90), rgb(196, 156, 116), tint(acc, 0.3), Cc.cream }, x)
			K.furn.shelving(c, R2(c, f, uw, dep, 4), 20, { Cc.butter, rgb(200, 160, 200), tint(acc, 0.4) }, x + 1)
			K.furn.bin(c, f * CFrame.new(0, 0.6, -2), 12, { rgb(226, 188, 140), Cc.butter, tint(acc, 0.35) })
			-- emote, not sit: CityVenues only seats you if the spot carries a
			-- seat CFrame, and this one is a place to stand and read
			return f * CFrame.new(0, 0.6, 8), "THE STACKS", "somebody has alphabetised all of this", "READ", "star", { emote = "sit", secs = 4, lines = { "\"Small Buildings of the Old City\"", "you read a whole chapter. nice.", "the spine creaks. lovely." } }
		end
		MALL_FIT.music = function(c, f, uw, dep, acc, x)
			K.furn.pegboard(c, R2(c, f, uw, dep, 2), 16, acc)
			K.furn.bin(c, f * CFrame.new(-6, 0.6, 0), 14, { Cc.ink, tint(acc, 0.3), rgb(226, 100, 90), Cc.butter })
			K.furn.bin(c, f * CFrame.new(6, 0.6, 0), 14, { rgb(140, 190, 240), Cc.cream, tint(acc, 0.45) })
			return f * CFrame.new(0, 0.6, 9), "THE LISTENING POST", "headphones on, one track", "LISTEN", "star", { tune = true, lines = { "that bassline again", "you find something you've never heard of" } }
		end
		MALL_FIT.shoes = function(c, f, uw, dep, acc, x)
			K.furn.shelving(c, L(c, f, uw, dep, 4), 20, { rgb(230, 150, 120), Cc.cream, rgb(120, 130, 150), Cc.butter }, x)
			K.furn.mirror(c, R2(c, f, uw, dep, 0) * CFrame.new(0, 5, 0), 8, 9)
			K.furn.banquette(c, f * CFrame.new(0, 0, 10), 14, tint(acc, 0.3))
			return f * CFrame.new(0, 0.6, 3), "TRY THEM ON", "sit down, laces off", "TRY ON", "shirt", { ui = "outfits" }
		end
		MALL_FIT.photo = function(c, f, uw, dep, acc, x)
			K.furn.display(c, L(c, f, uw, dep, 6), 16, Cc.ink, { Cc.cream, rgb(226, 188, 140), tint(acc, 0.3) })
			K.furn.easel(c, R2(c, f, uw, dep, 2), tint(acc, 0.3))
			return f * CFrame.new(0, 0.6, 6), "PHOTO BOOTH", "four shots, one strip", "POSE", "star", { emote = "cheer", secs = 3, lines = { "say cheese!", "the flash goes off. you blink.", "that one's going on the fridge" } }
		end
		MALL_FIT.candles = function(c, f, uw, dep, acc, x)
			K.furn.shelving(c, L(c, f, uw, dep, 4), 20, { Cc.cream, tint(acc, 0.3), rgb(240, 170, 190), Cc.butter }, x)
			K.furn.display(c, R2(c, f, uw, dep, 4), 16, tint(acc, 0.2), { Cc.cream, Cc.butter, rgb(240, 200, 170) })
			K.furn.pendant(c, f * CFrame.new(0, 0, 0), 22, Cc.butter)
			return f * CFrame.new(0, 0.6, 8), "THE TESTER SHELF", "have a sniff", "SMELL", "heart", { emote = "cheer", lines = { "warm vanilla. lovely.", "achoo! ...worth it", "you feel 10% calmer" } }
		end
		MALL_FIT.court = function(c, f, uw, dep, acc, x)
			-- the food court proper: benches and trays, no counter
			for k = 0, 2 do
				local t = f * CFrame.new(-10 + k * 10, 0, -4 + (k % 2) * 10)
				cyl(5, 0.4, t * CFrame.new(0, 3.4, 0), Cc.cream)
				P(V(0.6, 3.4, 0.6), t * CFrame.new(0, 1.7, 0), Cc.ink)
				for _, sx in { -3.4, 3.4 } do K.furn.stool(venueCtx(nil), t * CFrame.new(sx, 0, 0), acc) end
			end
			K.furn.signboard(c, f * CFrame.new(-12, 0.6, -dep / 2 + 6), "FOOD\nCOURT", shade(acc, 0.2))
			return f * CFrame.new(10, 0.6, 12), "THE TRAY RETURN", "somebody has to", "TIDY UP", "coin", { emote = "yoga", secs = 3, lines = { "trays stacked. immaculate.", "that's better", "somebody left a whole burger" } }
		end
		MALL_FIT.noodles = function(c, f, uw, dep, acc, x)
			K.furn.counter(c, f * CFrame.new(0, 0, 8), 22, shade(acc, 0.1))
			K.furn.till(c, f * CFrame.new(8, 3.8, 8))
			K.furn.menuboard(c, f * CFrame.new(0, 12, dep / 2 - 2), 22, { "RAMEN", "UDON", "GYOZA", "ICED TEA" }, acc)
			for k = 0, 3 do K.furn.stool(venueCtx(nil), f * CFrame.new(-9 + k * 6, 0, 3), acc, "AT THE BAR", "eat standing up like everyone else") end
			return f * CFrame.new(0, 0.6, 0), "THE NOODLE BAR", "ramen, udon, gyoza", "ORDER", "bag", { emote = "cheer", lines = { "one ramen, coming up", "the broth takes twelve hours, apparently", "extra gyoza. obviously." } }
		end
		MALL_FIT.cafe = function(c, f, uw, dep, acc, x)
			K.furn.counter(c, f * CFrame.new(0, 0, 10), 20, shade(acc, 0.1))
			K.furn.till(c, f * CFrame.new(7, 3.8, 10))
			K.furn.display(c, f * CFrame.new(-10, 0, 4), 12, shade(acc, 0.15), { rgb(236, 190, 130), Cc.butter, rgb(240, 170, 190) })
			K.furn.menuboard(c, f * CFrame.new(0, 12, dep / 2 - 2), 20, { "LATTE", "MATCHA", "CROISSANT", "COOKIE" }, acc)
			K.furn.banquette(c, R2(c, f, uw, dep, 2), 16, tint(acc, 0.35))
			K.furn.pendant(c, f * CFrame.new(0, 0, 2), 22, Cc.cream)
			return f * CFrame.new(0, 0.6, 5), "THE MALL CAFE", "the one with the good pastries", "ORDER", "bag", { emote = "cheer", lines = { "flat white, two sugars", "the pastry case is dangerous", "you get a window seat" } }
		end
	end
	Build.MALL_UNITS = MALL_UNITS
	function B.mall(cx, cz)
		local x0, x1, z0, z1 = 344, 556, 60, 240
		local FY, H = 26, 50 -- upper floor height, roof height
		local wall = rgb(252, 246, 226)
		local trim = Cc.sage
		local function at(x, y, z) return W(x, PAD + y, z) end
		-- floors
		walkable(P(V(x1 - x0, 0.5, z1 - z0), at((x0 + x1) / 2, 0.25, (z0 + z1) / 2), rgb(244, 236, 226), SMOOTH))
		for i = 0, 10 do P(V(1, 0.02, z1 - z0), at(x0 + i * (x1 - x0) / 10, 0.51, (z0 + z1) / 2), rgb(232, 220, 206), SMOOTH, { noShadow = true }) end
		-- the upper floor with a void over the atrium (x 425..475, z 95..185)
		local function slab(ax, bx, az, bz)
			walkable(P(V(bx - ax, 1, bz - az), at((ax + bx) / 2, FY - 0.5, (az + bz) / 2), rgb(244, 236, 226), SMOOTH))
			P(V(bx - ax, 0.6, bz - az), at((ax + bx) / 2, FY - 1.3, (az + bz) / 2), Cc.cream)
		end
		slab(x0, 425, z0, z1)
		slab(475, x1, z0, z1)
		slab(425, 475, z0, 95)
		slab(425, 475, 185, z1)
		-- glass balustrade round the void
		for _, e in { { 425, 425, 95, 185 }, { 475, 475, 95, 185 } } do
			local g = P(V(0.3, 3.4, e[4] - e[3]), at(e[1], FY + 1.7, (e[3] + e[4]) / 2), Cc.pane, K.GLASS, { transparency = 0.55 })
			g.CastShadow = false
			solid(g)
			P(V(0.6, 0.4, e[4] - e[3]), at(e[1], FY + 3.5, (e[3] + e[4]) / 2), trim)
		end
		-- outer walls with entrances (west, south, east)
		local function wallX(z, from, to, gapC, gapW)
			local segs = gapC and { { from, gapC - gapW / 2 }, { gapC + gapW / 2, to } } or { { from, to } }
			for _, s in segs do solid(P(V(s[2] - s[1], H, 2), at((s[1] + s[2]) / 2, H / 2, z), wall)) end
			if gapC then P(V(gapW, H - 16, 2), at(gapC, 16 + (H - 16) / 2, z), wall) end
		end
		local function wallZ(x, from, to, gapC, gapW)
			local segs = gapC and { { from, gapC - gapW / 2 }, { gapC + gapW / 2, to } } or { { from, to } }
			for _, s in segs do solid(P(V(2, H, s[2] - s[1]), at(x, H / 2, (s[1] + s[2]) / 2), wall)) end
			if gapC then P(V(2, H - 16, gapW), at(x, 16 + (H - 16) / 2, gapC), wall) end
		end
		wallX(z0, x0, x1, 450, 30)
		wallX(z1, x0, x1, nil)
		wallZ(x0, z0, z1, 150, 30)
		wallZ(x1, z0, z1, 150, 30)
		-- facade: stripes, big sign, entrance canopies
		for _, e in { { V(x0 - 1.4, 0, 150), -math.pi / 2 }, { V(450, 0, z0 - 1.4), math.pi }, { V(x1 + 1.4, 0, 150), math.pi / 2 } } do
			local f = K.frameOf(e[1], e[2], PAD)
			P(V(40, 2, 12), f * CFrame.new(0, 17, -5), trim)
			for _, sx in { -1, 1 } do cyl(1.6, 17, f * CFrame.new(sx * 18, 8.5, -10), Cc.cream) end
			K.sign(f * CFrame.new(0, 24, -0.8), 34, 6, Cc.sage, Cc.cream, "SMINSKI MALL")
			K.glassBand(f * CFrame.new(0, 8, 0.4), 30, 16, rgb(206, 232, 246), 7.5)
			for _, sx in { -1, 1 } do K.flowers(f * CFrame.new(sx * 26, 0, -5), 10, 4) end
		end
		-- facades: lit display windows below, framed windows above, a chunky
		-- cornice and a sage band, so the mall reads like the rest of the street
		local function facade(frame, len, gapAt)
			for k = 0, math.floor(len / 24) - 1 do
				local x = -len / 2 + 12 + k * 24
				if not gapAt or math.abs(x - gapAt) > 26 then
					K.window(frame * CFrame.new(x, 8, 0), 14, 9, nil, nil, true)
					K.window(frame * CFrame.new(x, 34, 0), 9, 8)
					K.awning(frame, x, 16, 14.6, 0, trim, Cc.cream)
				end
			end
			P(V(len + 1, 2, 1), frame * CFrame.new(0, 24, -0.6), trim)
		end
		facade(CFrame.lookAt(CITY + V(450, PAD, z0 - 1), CITY + V(450, PAD, z0 - 10)), x1 - x0, 0)
		facade(CFrame.lookAt(CITY + V(450, PAD, z1 + 1), CITY + V(450, PAD, z1 + 10)), x1 - x0, nil)
		facade(CFrame.lookAt(CITY + V(x0 - 1, PAD, 150), CITY + V(x0 - 10, PAD, 150)), z1 - z0, 0)
		facade(CFrame.lookAt(CITY + V(x1 + 1, PAD, 150), CITY + V(x1 + 10, PAD, 150)), z1 - z0, 0)
		K.cornice(CFrame.new(CITY + V(450, PAD, 150)), x1 - x0, z1 - z0, H, Cc.cream, trim)
		-- roof + the skylight over the atrium
		solid(P(V(x1 - x0 + 2, 1.2, z1 - z0 + 2), at((x0 + x1) / 2, H + 0.6, (z0 + z1) / 2), rgb(236, 226, 216)))
		local sky = P(V(50, 0.6, 90), at(450, H + 1.4, 140), rgb(220, 240, 255), K.GLASS, { transparency = 0.6 })
		sky.CastShadow = false
		for k = 0, 5 do P(V(0.6, 0.8, 90), at(425 + k * 10, H + 1.8, 140), Cc.cream) end
		-- the ceiling of the ground floor is the upper slab; ceiling of upstairs:
		P(V(x1 - x0, 0.4, z1 - z0), at((x0 + x1) / 2, H - 0.3, (z0 + z1) / 2), rgb(252, 248, 242), SMOOTH, { noShadow = true }).Transparency = 0
		-- escalator ramps inside the void
		local rise, run = FY, 90
		local ang = math.atan2(rise, run)
		local len = math.sqrt(rise * rise + run * run)
		for _, r in { { 436, 1 }, { 464, -1 } } do
			local zc = 140
			local cf = at(r[1], rise / 2, zc) * CFrame.Angles(r[2] * -ang, 0, 0)
			walkable(P(V(10, 0.8, len), cf, rgb(210, 214, 222), METAL))
			for k = 0, math.floor(len / 2.4) do P(V(9.6, 0.2, 0.3), cf * CFrame.new(0, 0.5, -len / 2 + k * 2.4), rgb(150, 156, 170), METAL, { noShadow = true }) end
			for _, sx in { -1, 1 } do
				P(V(0.6, 3.4, len), cf * CFrame.new(sx * 5.2, 1.9, 0), Cc.pane, K.GLASS, { transparency = 0.5 }).CastShadow = false
				P(V(0.8, 0.6, len), cf * CFrame.new(sx * 5.2, 3.8, 0), Cc.ink)
			end
		end
		-- the fountain in the west corridor + palms + benches
		local fc = at(385, 0, 150)
		solid(cyl(20, 2, fc * CFrame.new(0, 1, 0), Cc.stone))
		cyl(18, 2.1, fc * CFrame.new(0, 1.1, 0), Cc.water, SMOOTH)
		cyl(3, 7, fc * CFrame.new(0, 3.5, 0), Cc.stone)
		ball(4, fc * CFrame.new(0, 8, 0), rgb(255, 196, 220))
		for _, sx in { -1, 1 } do
			local pc = at(515, 0, 150 + sx * 12)
			cyl(3, 3, pc * CFrame.new(0, 1.5, 0), rgb(214, 130, 96))
			cyl(1, 12, pc * CFrame.new(0, 7, 0), Cc.trunk, WOODM)
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				P(V(1.4, 0.3, 7), pc * CFrame.new(math.cos(a) * 3, 13, math.sin(a) * 3) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(0.35, 0, 0), Cc.leaf)
			end
			K.bench(at(385, 0, 150 + sx * 16) * CFrame.Angles(0, sx < 0 and 0 or math.pi, 0))
		end
		-- shop units
		for _, u in MALL_UNITS do
			local x, side, fl = u[1], u[2], u[3]
			local y = fl * FY
			local zf = side == 1 and 172 or 128 -- the unit's glass front
			local zb = side == 1 and z1 - 1 or z0 + 1
			local uw = 35
			local f = CFrame.lookAt(CITY + V(x, PAD + y, (zf + zb) / 2), CITY + V(x, PAD + y, zf - side * 100)) -- local -Z faces the corridor
			local depth = math.abs(zb - zf)
			-- side walls, back wall tint, shopfront with a doorway
			for _, sx in { -1, 1 } do solid(P(V(1, FY - 2, depth), f * CFrame.new(sx * uw / 2, (FY - 2) / 2, 0), wall)) end
			-- deeper tints: at 0.55 / 0.7 a yellow unit's walls were nearly white
			P(V(uw - 1, FY - 3, 0.4), f * CFrame.new(0, (FY - 3) / 2 + 0.5, depth / 2 - 1.4), tint(u[5], 0.3))
			P(V(uw, 0.1, depth), f * CFrame.new(0, 0.56, 0), tint(u[5], 0.5), SMOOTH, { noShadow = true })
			local front = f * CFrame.new(0, 0, -depth / 2)
			for _, sx in { -1, 1 } do
				local g = P(V(11, 10, 0.3), front * CFrame.new(sx * 11.5, 5.5, 0), Cc.pane, SMOOTH)
				g.Reflectance = 0.12
				g.Transparency = 0.45
				P(V(0.8, 12, 0.6), front * CFrame.new(sx * 17.2, 6, 0), u[5])
			end
			P(V(uw, FY - 14, 0.8), front * CFrame.new(0, 12 + (FY - 14) / 2, 0), u[5])
			K.sign(front * CFrame.new(0, 14.6, -0.6), math.min(uw - 4, #u[4] * 1.6 + 4), 3, Cc.cream, shade(u[5], 0.25), u[4])
			-- inside. A unit with its own MALL_FIT gets that; the seven that
			-- City.lua already prompts through Places keep the generic shelf
			-- run, but stocked in THEIR OWN colours -- it was the same 48
			-- balls in all sixteen, which is what made the upper floor read as
			-- one shop repeated eight times.
			local inside = f * CFrame.new(0, 0, 4)
			local fit = MALL_FIT[u[7]]
			if fit then
				local spots = {}
				local ctx = venueCtx(spots)
				local scf, title, sub, btn, icon, act = fit(ctx, f, uw, depth, u[5], x)
				if scf then
					table.insert(spots, { pos = scf.Position - CITY, title = title, sub = sub, btn = btn, icon = icon, act = act })
				end
				table.insert(Build.venues, {
					name = u[4], btype = "mall", pos = f.Position - CITY,
					-- deliberately tight: the unit is 67 deep and the mall's
					-- other fifteen units are 36 apart, so a generous radius
					-- would have a player in the corridor "inside" three shops
					radius = 26, seats = {}, tables = {}, accent = u[5], spots = spots,
				})
				Build.destinations = Build.destinations or {}
				table.insert(Build.destinations, { name = u[4], btype = "mall", district = "shopping", pos = (f * CFrame.new(0, 0, -depth / 2 - 6)).Position - CITY, interior = true })
			else
				local stock = { u[5], tint(u[5], 0.45), Cc.cream, shade(u[5], 0.2), Cc.butter }
				P(V(16, 4, 3.6), inside * CFrame.new(0, 2, 6), rgb(200, 150, 110), WOODM)
				P(V(16.6, 0.5, 4.2), inside * CFrame.new(0, 4.2, 6), Cc.cream)
				for _, sx in { -1, 1 } do
					local sh = inside * CFrame.new(sx * 14, 0, 0) * CFrame.Angles(0, -sx * math.pi / 2, 0)
					P(V(20, 12, 0.6), sh * CFrame.new(0, 6, 1.6), rgb(170, 124, 84), WOODM)
					for s = 0, 3 do
						P(V(20, 0.5, 3), sh * CFrame.new(0, 1.4 + s * 3.2, 0), rgb(200, 150, 110), WOODM)
						for q = 0, 5 do ball(1.3, sh * CFrame.new(-8 + q * 3.2, 2.3 + s * 3.2, 0), stock[(q + s) % #stock + 1]) end
					end
				end
			end
			local lampP = ball(1.6, f * CFrame.new(0, FY - 6, 0), rgb(255, 236, 196), NEON)
			lampP.CastShadow = false
			P(V(0.2, 4, 0.2), f * CFrame.new(0, FY - 3.6, 0), Cc.ink)
		end
		for _, x in { 360, 395, 450, 505, 540 } do
			-- gentler, tighter: at range 70 these overlapped five deep and bleached
			-- whatever stood under them (Capsule Corner, at x = 536, worst of all)
			roomLight(at(x, FY - 3, 150), 52, 0.55)
			roomLight(at(x, H - 3, 150), 52, 0.55)
		end
		-- mall directory + parking lot out front with cars
		for k = 0, 5 do
			P(V(0.4, 0.05, 14), W(344 - 30 + 0.1, PAD + 0.02, 70 + k * 12), Cc.line, SMOOTH, { noShadow = true })
		end
		park(W(330, PAD + 0.2, 200) * CFrame.Angles(0, math.pi / 2, 0), "van")
		park(W(330, PAD + 0.2, 215) * CFrame.Angles(0, math.pi / 2, 0), "convertible")
		for _, p in { V(340, 0, 40), V(560, 0, 40), V(570, 0, 260), V(335, 0, 262) } do K.tree(p.X, p.Z, 1) end
	end

	function B.dealer(cx, cz)
		local d0 = Places.CityDealer
		local f = K.frameOf(V(d0.X, 0, d0.Z + 34), math.pi)
		local w, d, h = 110, 60, 22
		-- a glass showroom: slim frame, glass walls, a solid back
		walkable(P(V(w, 0.5, d), f * CFrame.new(0, 0.25, 0), rgb(246, 246, 250), SMOOTH))
		solid(P(V(w, h, 1.4), f * CFrame.new(0, h / 2, d / 2), rgb(236, 236, 244)))
		for _, sx in { -1, 1 } do
			local g = P(V(0.6, h, d), f * CFrame.new(sx * w / 2, h / 2, 0), Cc.pane, SMOOTH)
			g.Transparency = 0.5
			solid(g)
		end
		for _, sx in { -1, 1 } do
			local g = P(V(w / 2 - 8, h, 0.6), f * CFrame.new(sx * (w / 4 + 4), h / 2, -d / 2), Cc.pane, SMOOTH)
			g.Transparency = 0.5
			solid(g)
		end
		for k = 0, 10 do P(V(0.8, h, 0.8), f * CFrame.new(-w / 2 + k * w / 10, h / 2, -d / 2 - 0.3), Cc.cream) end
		solid(P(V(w + 4, 1.4, d + 4), f * CFrame.new(0, h + 0.7, 0), rgb(236, 236, 244)))
		K.sign(f * CFrame.new(0, h + 4, -d / 2 - 1), 44, 5, rgb(80, 120, 210), Cc.cream, "SMINSKI MOTORS")
		-- turntables with one of every car
		local kinds = { "van", "taxi", "icecream", "sports", "monster" }
		Build.turntables = {}
		for i, kind in kinds do
			local tcf = f * CFrame.new(-44 + (i - 1) * 22, 0, 6)
			cyl(18, 0.6, tcf * CFrame.new(0, 0.8, 0), rgb(226, 226, 236), METAL)
			local car = K.buildCar(kind, K.CAR_COLORS[i + 1], K.cur)
			car:PivotTo(tcf * CFrame.new(0, 1.1, 0))
			table.insert(Build.turntables, { m = car, cf = tcf * CFrame.new(0, 1.1, 0), sp = 0.3 + i * 0.05 })
		end
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t)
			for _, tt in Build.turntables do tt.m:PivotTo(tt.cf * CFrame.Angles(0, t * tt.sp, 0)) end
		end })
		-- flags + a lot of cars outside
		for k = 0, 7 do
			local fp = W(620 + 34 + k * 22, PAD, 40)
			cyl(0.4, 14, fp * CFrame.new(0, 7, 0), rgb(220, 220, 228), METAL)
			P(V(0.2, 5, 3), fp * CFrame.new(0, 12, 1.6), K.CAR_COLORS[k + 1])
		end
		for k = 0, 5 do
			local cf = W(650 + k * 16, PAD + 0.2, 220) * CFrame.Angles(0, math.pi, 0)
			P(V(0.4, 0.05, 14), W(642 + k * 16, PAD + 0.02, 220), Cc.line, SMOOTH, { noShadow = true })
			park(cf, "convertible", K.CAR_COLORS[(k + 3) % 8 + 1])
		end
	end

	function B.market(cx, cz)
		local f = K.frameOf(V(cx + 10, 0, cz - 50), 0)
		local w, d, h = 150, 70, 24
		local acc = rgb(120, 190, 120)
		-- A STORE YOU CAN WALK INTO. It was a solid box with a sign on it; now
		-- it is a room (floor, walls, a 14-wide doorway at the front) fitted
		-- out as a grocery -- aisles of shelves, a till, a keeper -- and
		-- registered as a venue so CityVenues drives the shelves and the till.
		room(f, w, d, h, rgb(248, 246, 236), rgb(236, 232, 220), 14, rgb(226, 230, 220))
		do
			-- the frame looks along +Z, so the doorway (local -d/2) is on the
			-- +Z side, toward the parking row: world z = cz - 50 + 35
			local v = fitGrocery(f, w, d, { name = "SUPER MARKET", btype = "grocery", door = V(cx + 10, 0, cz - 50 + d / 2 + 2) }, 4, acc)
			-- the doorway is open, and it also has E: ENTER from the pavement,
			-- LEAVE from just inside (both a few studs off the threshold so the
			-- two prompts never overlap)
			local dOut, dIn = V(cx + 10, 0, cz - 50 + d / 2 + 5), V(cx + 10, 0, cz - 50 + d / 2 - 6)
			table.insert(v.spots, { pos = dOut, title = "SUPER MARKET", sub = "grab a basket on the way in", btn = "ENTER", icon = "house", act = { warp = dIn, face = math.pi } })
			table.insert(v.spots, { pos = dIn, title = "THE DOOR", sub = "back out to the street", btn = "LEAVE", icon = "house", act = { warp = dOut, face = 0 } })
			table.insert(Build.venues, v)
			-- a warm light: a roofed room is dark under honest daylight
			for _, x in { -45, 0, 45 } do
				local lamp = ball(2, f * CFrame.new(x, h - 2.5, 0), rgb(255, 236, 200), NEON)
				lamp.CastShadow = false
				if x == 0 then
					local pl = Instance.new("PointLight")
					pl.Range, pl.Brightness, pl.Color, pl.Shadows = 70, 1.1, rgb(255, 232, 196), false
					pl.Parent = lamp
				end
			end
			K.threshold(f * CFrame.new(0, 0.06, -d / 2 - 2.4), 19, 7)
			Build.destinations = Build.destinations or {}
			table.insert(Build.destinations, { name = "the Supermarket", btype = "grocery", district = "shopping", pos = v.door, interior = true })
		end
		P(V(w + 0.6, 3, d + 0.6), f * CFrame.new(0, h - 1.5, 0), acc)
		K.cornice(f, w, d, h, Cc.cream, acc)
		-- the glass band either side of the doorway, not across it
		local seg = (w - 30) / 2 - 9
		for _, sx in { -1, 1 } do
			K.glassBand(f * CFrame.new(sx * (9 + seg / 2), 6.5, -d / 2 - 0.3), seg, 11, rgb(206, 232, 246), 6)
		end
		K.door(f, -30, -d / 2 - 0.6, acc, true)
		K.door(f, 30, -d / 2 - 0.6, acc, true)
		K.sign(f * CFrame.new(0, 17, -d / 2 - 0.8), 50, 5, acc, Cc.cream, "SUPER MARKET")
		K.flatRoof(f, w, d, h, rgb(226, 230, 220))
		for k = 0, 4 do
			local tr = f * CFrame.new(-60 + k * 5, 0, -d / 2 - 6)
			P(V(3.4, 2.6, 5), tr * CFrame.new(0, 1.8, 0), rgb(200, 206, 216), METAL)
		end
		-- parking with cars
		-- the parking row sits at z=+4 (it was +20) to leave the north-east
		-- quarter deep enough for the restaurant below
		for k = 0, 7 do
			P(V(0.4, 0.05, 14), W(cx - 70 + k * 18, PAD + 0.02, cz + 4), Cc.line, SMOOTH, { noShadow = true })
			if k % 3 ~= 1 then park(W(cx - 61 + k * 18, PAD + 0.2, cz + 4) * CFrame.Angles(0, math.pi, 0), k % 4 == 0 and "van" or "convertible") end
		end
		-- a little gas station
		local g = W(cx - 70, PAD, cz + 80)
		P(V(40, 1.4, 24), g * CFrame.new(0, 14, 0), rgb(255, 214, 90))
		for _, sx in { -16, 16 } do for _, sz in { -8, 8 } do cyl(1, 14, g * CFrame.new(sx, 7, sz), Cc.cream) end end
		for _, sx in { -8, 8 } do
			P(V(3, 6, 2), g * CFrame.new(sx, 3, 0), Cc.red)
			P(V(2, 1.4, 0.2), g * CFrame.new(sx, 4.6, -1.05), Cc.cream, NEON)
		end
		K.sign(g * CFrame.new(0, 15.8, -12.2), 16, 2.4, Cc.red, Cc.cream, "SMINSKI GAS")
		-- McDONALD'S, from the owner's inventory, in the block's north-east
		-- quarter. MEASURED, twice: the first placement at (+68, +72) put 33
		-- street-wall parts inside the restaurant, because the wall units on
		-- this block are 32 deep (their inner face is at 86, not 114). The
		-- free quarter is x 0..84 by z 12..84 once the parking row moves to
		-- z=+4, so the restaurant runs at 0.9 (63 x 62) centred at (+42, +52):
		-- x 10..74, z 21..83. Its front (the wordmark) faces -Z, toward the
		-- cars. The corner tree that stood there is skipped.
		-- sink 0.15: its floor slab is 0.2 thick, so the floor top lands flush
		-- with the pavement instead of a lip you trip on at the door
		local mcd = K.place("McDonalds", W(cx + 42, PAD, cz + 52), { scale = 0.9, collide = "solid", sink = 0.15 })
		if mcd then
			local at = V(cx + 42, 0, cz + 38)
			-- the doors: E outside to step in, E inside to step out (the
			-- entrance glass is walk-through too; this is for players who
			-- expect a door to be a button)
			-- the door frame is the apex of the glass V, 0.9 * (+7.6, -34.4)
			-- from the centre -> (+49, +21); the spots sit just outside and
			-- just inside it
			local doorOut, doorIn = V(cx + 49, 0, cz + 15), V(cx + 49, 0, cz + 28)
			Build.venues = Build.venues or {}
			table.insert(Build.venues, {
				name = "McDONALD'S", btype = "restaurant", pos = V(cx + 42, 0, cz + 48), radius = 32,
				seats = {}, tables = {}, accent = rgb(255, 196, 40),
				spots = {
					{ pos = doorOut, title = "McDONALD'S", sub = "the doors are open", btn = "ENTER", icon = "house", act = { warp = doorIn, face = 0 } },
					{ pos = doorIn, title = "THE DOOR", sub = "back out to the car park", btn = "LEAVE", icon = "house", act = { warp = doorOut, face = math.pi } },
					{ pos = at, title = "McDONALD'S", sub = "fries, nuggets, a very small Happy Meal", btn = "ORDER", icon = "bag",
						act = { emote = "cheer", secs = 3, lines = { "would you like fries with that? you would.", "the ice cream machine is working today!", "one Happy Meal. the toy is a tiny Sminski.", "extra sauce, no questions" } } },
				},
			})
			Build.destinations = Build.destinations or {}
			table.insert(Build.destinations, { name = "McDonald's", btype = "restaurant", district = "shopping", pos = V(cx + 42, 0, cz + 18), interior = true })
			K.tree(cx - 100, cz - 100, 1.2)
		else
			for _, p in { V(100, 0, 100), V(-100, 0, -100) } do K.tree(cx + p.X, cz + p.Z, 1.2) end
		end
	end

	---------------------------------------------------------------------------
	-- FUN PARK
	---------------------------------------------------------------------------
	function B.fair(cx, cz)
		-- the ferris wheel (turns while you're near; riders sit in a gondola)
		local hub = Places.FerrisHub
		local R = 70
		local base = W(hub.X, 0, hub.Z)
		for _, sx in { -1, 1 } do
			for _, dz in { -6, 6 } do
				local a = W(hub.X + sx * 34, PAD, hub.Z + dz)
				local b = W(hub.X, hub.Y, hub.Z + dz)
				local mid = a.Position:Lerp(b.Position, 0.5)
				solid(P(V(2, 2, (b.Position - a.Position).Magnitude), CFrame.lookAt(mid, b.Position), rgb(236, 236, 244), METAL))
			end
		end
		cyl(4, 16, base * CFrame.new(0, hub.Y, 0) * CFrame.Angles(math.pi / 2, 0, 0), Cc.ink, METAL)
		local wheel = Instance.new("Model")
		wheel.Name = "FerrisWheel"
		wheel.Parent = K.cur
		local keep = K.cur
		K.cur = wheel
		local centre = CFrame.new(CITY + hub)
		for _, dz in { -5, 5 } do
			for k = 0, 31 do
				local a0, a1 = k / 32 * math.pi * 2, (k + 1) / 32 * math.pi * 2
				local p0 = centre * CFrame.new(math.cos(a0) * R, math.sin(a0) * R, dz)
				local p1 = centre * CFrame.new(math.cos(a1) * R, math.sin(a1) * R, dz)
				local mid = p0.Position:Lerp(p1.Position, 0.5)
				P(V(1.4, 1.4, (p1.Position - p0.Position).Magnitude + 0.4), CFrame.lookAt(mid, p1.Position), k % 2 == 0 and rgb(255, 170, 200) or rgb(150, 206, 250), METAL)
				if k % 2 == 0 then
					local s0 = centre * CFrame.new(0, 0, dz)
					local sm = s0.Position:Lerp(p0.Position, 0.5)
					P(V(0.7, 0.7, R), CFrame.lookAt(sm, p0.Position), rgb(240, 240, 248), METAL)
					ball(1.6, p0, rgb(255, 244, 200), NEON).CastShadow = false
				end
			end
		end
		wheel.WorldPivot = centre
		K.cur = keep
		local gondolas = {}
		for k = 0, 15 do
			local g = Instance.new("Model")
			g.Parent = K.cur
			local col = K.CAR_COLORS[k % 8 + 1]
			part(g, V(8, 5, 6), CFrame.new(0, -4, 0), col, SMOOTH)
			part(g, V(8.4, 0.8, 6.4), CFrame.new(0, -1.2, 0), K.C.cream, SMOOTH)
			part(g, V(0.5, 3, 0.5), CFrame.new(0, 0, 0), K.C.ink, METAL)
			part(g, V(8, 0.6, 6), CFrame.new(0, -6.3, 0), shade(col, 0.2), SMOOTH)
			g.WorldPivot = CFrame.new()
			table.insert(gondolas, { m = g, a = k / 16 * math.pi * 2 })
		end
		Build.ferris = { wheel = wheel, gondolas = gondolas, centre = centre, R = R, angle = 0 }
		table.insert(Build.anims, { cx = cx, cz = cz, far = true, fn = function(dt)
			local fw = Build.ferris
			fw.angle += dt * 0.06
			fw.wheel:PivotTo(fw.centre * CFrame.Angles(0, 0, fw.angle))
			for _, g in fw.gondolas do
				local a = g.a + fw.angle
				g.m:PivotTo(fw.centre * CFrame.new(math.cos(a) * fw.R, math.sin(a) * fw.R, 0))
			end
		end })
		-- boarding platform + ticket booth
		local bp = W(Places.CityRides.ferris.X, PAD, Places.CityRides.ferris.Z)
		walkable(P(V(20, 1, 12), bp * CFrame.new(0, 0.5, 0), rgb(236, 226, 206), WOODM))
		K.stall(bp * CFrame.new(16, 0, -6), "RIDE 25", rgb(255, 150, 190))
		-- carousel (turns and the ponies bob)
		local cc = W(Places.CityRides.carousel.X, PAD, Places.CityRides.carousel.Z)
		solid(cyl(40, 1.4, cc * CFrame.new(0, 0.7, 0), rgb(250, 240, 226)))
		cyl(4, 16, cc * CFrame.new(0, 8, 0), rgb(255, 214, 90))
		for k = 0, 3 do cyl(44 - k * 10, 2, cc * CFrame.new(0, 16 + k * 2, 0), k % 2 == 0 and rgb(255, 170, 200) or Cc.cream) end
		ball(3, cc * CFrame.new(0, 25, 0), Cc.gold, METAL)
		local ponies = {}
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			local pole = cyl(0.5, 14, cc, rgb(255, 214, 90), METAL)
			local body = blob(V(2.4, 3, 5.4), cc, K.CAR_COLORS[k % 8 + 1])
			local head = blob(V(2, 3, 2.4), cc, K.CAR_COLORS[k % 8 + 1])
			table.insert(ponies, { a = a, pole = pole, body = body, head = head })
		end
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t)
			for i, pn in ponies do
				local a = pn.a + t * 0.4
				local p = cc * CFrame.new(math.cos(a) * 15, 0, math.sin(a) * 15) * CFrame.Angles(0, -a, 0)
				local bob = math.sin(t * 2 + i) * 1.2
				pn.pole.CFrame = p * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.pi / 2)
				pn.body.CFrame = p * CFrame.new(0, 6 + bob, 0)
				pn.head.CFrame = p * CFrame.new(0, 8 + bob, -2.6) * CFrame.Angles(0.4, 0, 0)
			end
		end })
		K.stall(cc * CFrame.new(28, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), "RIDE 10", rgb(150, 206, 250))
		-- snack stalls, balloons and string lights
		for k, nm in { "POPCORN", "CANDY FLOSS", "LEMONADE" } do
			K.stall(W(cx - 60 + k * 40, PAD, cz - 100), nm, K.CAR_COLORS[k + 3])
		end
		for k = 0, 11 do
			local bl = ball(2.4, W(cx - 100 + k * 18, PAD + 12 + (k % 3), cz - 112), K.CAR_COLORS[k % 8 + 1], SMOOTH)
			bl.Reflectance = 0.15
			P(V(0.1, 10, 0.1), W(cx - 100 + k * 18, PAD + 6, cz - 112), Cc.ink)
		end
		K.sign(W(cx, PAD + 30, cz - 118), 40, 6, rgb(255, 150, 190), Cc.cream, "SMINSKI FUN PARK")
		for _, sx in { -22, 22 } do solid(cyl(2, 32, W(cx + sx, PAD + 16, cz - 118), rgb(255, 214, 90))) end
	end

	function B.race(cx, cz)
		local pts = Places.racePoints()
		-- asphalt ribbon along the track (walkable so cars ride it)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt(CITY + V(mid.X, PAD + 0.1, mid.Z), CITY + V(b.X, PAD + 0.1, b.Z))
			walkable(P(V(26, 0.3, len + 8), cf, rgb(96, 96, 110), SMOOTH, { noShadow = true }))
			for _, sx in { -1, 1 } do
				for k = 0, math.floor(len / 4) do
					P(V(1.6, 0.5, 2), cf * CFrame.new(sx * 13.5, 0.2, -len / 2 + k * 4 + 2), k % 2 == 0 and Cc.red or Cc.cream, SMOOTH, { noShadow = true })
				end
			end
		end
		-- start / finish gantry with a checkered banner
		local s = Places.RaceStart
		local sf = W(s.X, PAD, s.Z)
		for k = 0, 11 do
			for r = 0, 1 do
				P(V(2.2, 0.08, 2.2), sf * CFrame.new(0, 0.3, -12 + k * 2.2) * CFrame.new(-1.1 + r * 2.2, 0, 0), (k + r) % 2 == 0 and Cc.ink or Cc.cream, SMOOTH, { noShadow = true })
			end
		end
		for _, sz in { -15, 15 } do solid(cyl(1.4, 18, sf * CFrame.new(0, 9, sz), Cc.cream)) end
		local ban = P(V(1, 4, 32), sf * CFrame.new(0, 17, 0), Cc.ink)
		K.textOn(ban, Enum.NormalId.Left, "KART TRACK", Cc.cream, Vector2.new(500, 70))
		K.textOn(ban, Enum.NormalId.Right, "FINISH", Cc.cream, Vector2.new(500, 70))
		-- grandstand with a cheering crowd, tyre stacks, a pit sign
		local gs = W(cx, PAD, cz - 102)
		for k = 0, 3 do solid(P(V(90, 2, 5), gs * CFrame.new(0, 1 + k * 2, k * 5), k % 2 == 0 and rgb(120, 170, 220) or rgb(150, 190, 236))) end
		for k = 0, 9 do
			local def = Config.Characters[k % #Config.Characters + 1]
			local rig = Models.buildSminski(K.cur, 1, def, false, nil)
			table.insert(Build.dancers, { rig = rig, cf = gs * CFrame.new(-36 + k * 8, 2 + (k % 4) * 2, (k % 4) * 5) * CFrame.Angles(0, math.pi, 0), t0 = k, cx = cx, cz = cz })
		end
		for _, p in { V(-870, 0, 100), V(-630, 0, 100), V(-870, 0, 200), V(-630, 0, 200) } do
			for k = 0, 2 do cyl(4, 1.6, W(p.X, PAD + 0.8 + k * 1.6, p.Z), Cc.ink) end
		end
		K.sign(W(cx, PAD + 6, cz + 112), 30, 4, Cc.red, Cc.cream, "3 LAPS · BEAT 30s FOR GOLD")
	end

	function B.arcade(cx, cz)
		-- the arcade (you can walk in; claw machines + cabinets)
		local af = K.frameOf(V(-520, 0, -90), 0)
		local aw, ad, ah = 110, 70, 26
		local purple = Cc.mint
		room(af, aw, ad, ah, purple, rgb(84, 128, 96), 16, Cc.sage)
		K.cornice(af, aw, ad, ah, Cc.cream, Cc.sage)
		K.sign(af * CFrame.new(0, ah + 5, -ad / 2 - 1), 40, 8, Cc.sage, Cc.butter, "CLAW CORNER")
		for k = 0, 13 do
			local b = ball(1.4, af * CFrame.new(-26 + k * 4, ah + 9.6, -ad / 2 - 1.2), rgb(255, 236, 170), NEON)
			b.CastShadow = false
		end
		-- carpet with confetti dots
		for k = 0, 40 do
			P(V(1.2, 0.05, 1.2), af * CFrame.new(-50 + (k * 37) % 100, 0.53, -30 + (k * 23) % 60), K.FLOWER_COLS[k % 5 + 1], NEON, { noShadow = true })
		end
		for _, x in { -30, 0, 30 } do roomLight(af * CFrame.new(x, ah - 3, 0), 55, 1.3) end
		-- claw machines
		for k = 0, 3 do
			local cm = af * CFrame.new(-30 + k * 12, 0, 10)
			local col = K.CAR_COLORS[k + 1]
			P(V(8, 5, 8), cm * CFrame.new(0, 2.5, 0), col)
			local g = P(V(7.6, 8, 7.6), cm * CFrame.new(0, 9, 0), Cc.pane, K.GLASS)
			g.Transparency = 0.6
			P(V(8, 1.4, 8), cm * CFrame.new(0, 13.7, 0), col)
			for q = 0, 5 do ball(1.6, cm * CFrame.new(-2 + (q % 3) * 2, 5.6 + math.floor(q / 3) * 1.2, -1 + math.floor(q / 3) * 2), K.CAR_COLORS[(q + k) % 8 + 1]) end
			P(V(0.3, 3, 0.3), cm * CFrame.new(0, 11.4, 0), rgb(200, 200, 210), METAL)
			K.sign(cm * CFrame.new(0, 15.6, -3.8), 7, 1.6, Cc.ink, rgb(255, 214, 110), "CLAW 40")
		end
		-- arcade cabinets along the walls
		for k = 0, 7 do
			local sx = k < 4 and -1 or 1
			local z = -24 + (k % 4) * 14
			local cab = af * CFrame.new(sx * 48, 0, z) * CFrame.Angles(0, sx * math.pi / 2, 0)
			P(V(6, 10, 5), cab * CFrame.new(0, 5, 0), K.CAR_COLORS[k % 8 + 1])
			local scr = P(V(4.6, 3.6, 0.3), cab * CFrame.new(0, 7, -2.6), rgb(140, 230, 255), NEON)
			scr.CastShadow = false
			P(V(5, 0.6, 2), cab * CFrame.new(0, 4.6, -3), Cc.ink)
		end
		-- the cinema next door, with a bulb-lit marquee
		local cf = K.frameOf(V(-395, 0, -170), math.pi / 2)
		local cw, cd, ch = 70, 110, 34
		local red = rgb(210, 90, 100)
		local cwall = rgb(248, 226, 146)
		room(cf, cw, cd, ch, cwall, rgb(150, 96, 84), 16, Cc.sage)
		K.cornice(cf, cw, cd, ch, Cc.cream, Cc.sage)
		local mq = cf * CFrame.new(0, 20, -cd / 2 - 4)
		P(V(40, 8, 6), mq, rgb(250, 240, 226))
		local ms = P(V(36, 5, 0.4), mq * CFrame.new(0, 0, -3.1), Cc.ink)
		K.textOn(ms, Enum.NormalId.Front, "NOW SHOWING: SMINSKI RUN", rgb(255, 214, 110), Vector2.new(700, 90), 0.2)
		for k = 0, 19 do
			local b = ball(1, mq * CFrame.new(-19 + k * 2, 4.4, -3), rgb(255, 236, 170), NEON)
			b.CastShadow = false
		end
		K.sign(cf * CFrame.new(0, ch + 6, -cd / 2 - 1), 34, 8, Cc.sage, Cc.cream, "SMINSKI CINEMA")
		for _, sx in { -1, 1 } do
			local pst = cf * CFrame.new(sx * 24, 9, -cd / 2 - 0.8)
			P(V(8, 12, 0.4), pst, K.CAR_COLORS[sx < 0 and 2 or 5])
			P(V(9, 13, 0.3), pst * CFrame.new(0, 0, 0.2), rgb(255, 214, 90))
		end
		for _, z in { -30, 0, 30 } do roomLight(cf * CFrame.new(0, ch - 3, z), 55, 0.9) end
		---------------------------------------------------------------------
		-- INSIDE THE CINEMA. What was here: forty 3-stud cubes you could not
		-- sit on, stepped 0.6 studs apart so there was no rake to see over; a
		-- popcorn stand with no prompt; and K.textOn(screen, ..., "") -- an
		-- empty string on a blank white panel, under a marquee promising NOW
		-- SHOWING (docs/WORLD_REVAMP.md §4.3).
		--
		-- It is registered as a venue so CityVenues runs the seats and the
		-- popcorn, the same machinery as every other room in town. The radius
		-- is 52, not cd/2+8 = 63, on purpose: Places.CityBiz.cinema is the
		-- BUY/COLLECT spot 57 studs out at the door, and City.lua checks
		-- Venues before businesses.
		---------------------------------------------------------------------
		local cSeats, cSpots = {}, {}
		local cctx = venueCtx(cSpots)
		-- the popcorn stand, in the foyer end, now with something to do at it
		local pf = cf * CFrame.new(-20, 0, -20)
		K.furn.counter(cctx, pf, 14, rgb(255, 214, 90), { top = Cc.cream })
		K.furn.till(cctx, pf * CFrame.new(5, 3.8, 0))
		for q = 0, 5 do
			cyl(2.6, 4, pf * CFrame.new(-5 + q * 1.8, 5.8, 0), q % 2 == 0 and Cc.red or Cc.cream, SMOOTH)
			for j = 0, 2 do ball(1.1, pf * CFrame.new(-5 + q * 1.8, 7.8 + j * 0.4, (j - 1) * 0.6), Cc.butter) end
		end
		K.furn.menuboard(cctx, cf * CFrame.new(-20, 12, -cd / 2 + 3), 16, { "POPCORN", "SODA", "PICK & MIX" }, Cc.red)
		table.insert(cSpots, {
			pos = (pf * CFrame.new(0, 0, -4)).Position - CITY,
			title = "THE POPCORN STAND", sub = "large, obviously", btn = "BUY POPCORN", icon = "bag",
			act = { emote = "cheer", lines = { "extra butter. no regrets.", "you get the big one", "the bag is bigger than you are" } },
		})
		local kid = Models.buildSminski(K.cur, 1, Config.Characters[3] or Config.Characters[1], false, "beanie")
		Models.poseSminski(kid, pf * CFrame.new(0, 0, 3) * CFrame.Angles(0, math.pi, 0), "idle", 3)
		-- the auditorium: five raked rows of real seats, facing the screen
		for r = 0, 4 do
			local z, y = 14 + r * 6, r * 1.6
			-- the step the row stands on. A rake is what makes a room read as
			-- an auditorium, and it is what lets row 5 see over row 1.
			walkable(P(V(40, 1.2 + y, 6), cf * CFrame.new(0, (1.2 + y) / 2, z), rgb(120, 70, 74), MATTE))
			for k = 0, 7 do
				local s = cf * CFrame.new(-14 + k * 4, 1.2 + y, z)
				solid(P(V(3.2, 1.4, 3), s * CFrame.new(0, 0.7, 0), red, K.FABRIC))
				P(V(3.2, 3.6, 0.8), s * CFrame.new(0, 2.3, 1.4), red, K.FABRIC)
				for _, q in { -1.7, 1.7 } do P(V(0.5, 1.2, 2.6), s * CFrame.new(q, 1.6, -0.1), shade(red, 0.2), K.FABRIC, { noShadow = true }) end
				-- three seats are taken: an empty cinema is a sad cinema
				if (r == 2 and (k == 2 or k == 3)) or (r == 0 and k == 5) then
					local rig = Models.buildSminski(K.cur, 1, Config.Characters[(r * 3 + k) % #Config.Characters + 1], false, nil)
					-- 0.3, not 1.4: a seated rig's origin sits ~1.1 below the
					-- cushion, the same offset the stools elsewhere use
					Models.poseSminski(rig, s * CFrame.new(0, 0.3, 0), "sit", r + k)
				else
					table.insert(cSeats, { cf = s * CFrame.new(0, 1.4, 0) })
				end
			end
		end
		-- the screen, and something on it. The marquee outside says SMINSKI
		-- RUN, so that is what is playing.
		local screen = P(V(50, 22, 0.5), cf * CFrame.new(0, 16, cd / 2 - 1.2), rgb(30, 34, 44), SMOOTH)
		screen.CastShadow = false
		P(V(54, 26, 0.6), cf * CFrame.new(0, 16, cd / 2 - 0.8), Cc.ink)
		for _, sx in { -26.6, 26.6 } do P(V(2, 26, 2.4), cf * CFrame.new(sx, 16, cd / 2 - 2.4), rgb(120, 70, 74), K.FABRIC) end
		-- three bands of light that drift across it: from a seat this reads as
		-- a film without needing a VideoFrame (which only plays uploaded,
		-- moderated assets -- see docs/HANDOFF.md §3)
		local bands = {}
		for b = 0, 2 do
			local p = P(V(48, 6, 0.3), cf * CFrame.new(0, 10 + b * 6, cd / 2 - 1.5), ({ rgb(120, 180, 236), rgb(250, 226, 170), rgb(226, 150, 190) })[b + 1], NEON, { noShadow = true })
			p.Transparency = 0.35
			table.insert(bands, { p = p, y = 10 + b * 6, k = 0.7 + b * 0.35 })
		end
		K.textOn(screen, Enum.NormalId.Front, "SMINSKI RUN", Cc.cream, Vector2.new(700, 300), 0)
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t)
			for bi, b in bands do
				b.p.CFrame = cf * CFrame.new(math.sin(t * b.k + bi) * 14, b.y + math.sin(t * 0.6 + bi) * 2, cd / 2 - 1.5)
				b.p.Transparency = 0.3 + math.sin(t * b.k * 1.7 + bi) * 0.18
			end
		end })
		table.insert(Build.venues, {
			name = "SMINSKI CINEMA", btype = "cinema", pos = cf.Position - CITY,
			radius = 52, seats = cSeats, tables = {}, accent = red, spots = cSpots,
		})
		Build.destinations = Build.destinations or {}
		table.insert(Build.destinations, { name = "the cinema", btype = "cinema", district = "entertainment", pos = Places.CityBiz.cinema, interior = true })
	end

	function B.concert(cx, cz)
		local sf = K.frameOf(V(cx, 0, cz - 70), 0)
		solid(P(V(90, 6, 40), sf * CFrame.new(0, 3, 0), rgb(84, 132, 96)))
		P(V(90, 40, 2), sf * CFrame.new(0, 26, 20), rgb(70, 112, 84))
		P(V(96, 3, 44), sf * CFrame.new(0, 46, 0), rgb(70, 112, 84))
		for _, sx in { -1, 1 } do
			solid(P(V(3, 44, 3), sf * CFrame.new(sx * 46, 22, -20), rgb(70, 112, 84)))
			P(V(10, 16, 8), sf * CFrame.new(sx * 38, 14, -12), Cc.ink)
			for k = 0, 1 do cyl(6, 0.4, sf * CFrame.new(sx * 38, 10 + k * 7, -16.2) * CFrame.Angles(math.pi / 2, 0, 0), rgb(90, 90, 100)) end
		end
		Build.stageLights = {}
		for k = 0, 7 do
			local l = ball(3, sf * CFrame.new(-35 + k * 10, 43, -18), K.CAR_COLORS[k + 1], NEON)
			l.CastShadow = false
			table.insert(Build.stageLights, l)
		end
		local bd = P(V(70, 24, 0.5), sf * CFrame.new(0, 24, 18.6), rgb(186, 228, 164), NEON)
		bd.CastShadow = false
		K.textOn(bd, Enum.NormalId.Front, "SMINSKI FEST", Cc.cream, Vector2.new(600, 200), 0)
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t)
			for i, l in Build.stageLights do l.Color = K.CAR_COLORS[(math.floor(t * 3) + i) % 8 + 1] end
		end })
		-- a band on stage + a crowd
		for k = 0, 2 do
			local rig = Models.buildSminski(K.cur, 1.4, Config.Characters[k + 2] or Config.Characters[1], false, k == 1 and "shades" or nil)
			table.insert(Build.dancers, { rig = rig, cf = sf * CFrame.new(-14 + k * 14, 6, 0) * CFrame.Angles(0, math.pi, 0), t0 = k * 2, cx = cx, cz = cz })
		end
		for k = 0, 17 do
			local def = Config.Characters[(k * 3) % #Config.Characters + 1]
			local rig = Models.buildSminski(K.cur, k % 5 == 0 and 0.6 or 1, def, false, nil)
			table.insert(Build.dancers, { rig = rig, cf = W(cx - 40 + (k % 6) * 16, PAD, cz - 20 + math.floor(k / 6) * 14) * CFrame.Angles(0, math.pi, 0), t0 = k, cx = cx, cz = cz })
		end
		for k, nm in { "TACOS", "BURGERS", "SMOOTHIES" } do
			K.stall(W(cx + 90, PAD, cz - 60 + k * 30) * CFrame.Angles(0, -math.pi / 2, 0), nm, K.CAR_COLORS[k + 4])
		end
		for _, p in { V(-100, 0, 90), V(100, 0, 90), V(-100, 0, 40) } do K.tree(cx + p.X, cz + p.Z, 1.2) end
	end

	---------------------------------------------------------------------------
	-- FARMS
	---------------------------------------------------------------------------
	local function fieldRows(cx, cz, w, d, col, plant)
		P(V(w, 0.3, d), W(cx, PAD + 0.1, cz), Cc.soil, MATTE, { noShadow = true })
		for r = 0, math.floor(d / 6) - 1 do
			local z = cz - d / 2 + 3 + r * 6
			P(V(w - 2, 0.5, 2), W(cx, PAD + 0.3, z), Cc.soil2, MATTE, { noShadow = true })
			if plant then
				for k = 0, math.floor(w / 6) - 1 do plant(W(cx - w / 2 + 3 + k * 6, PAD + 0.4, z), k + r) end
			end
		end
	end
	function B.fields(cx, cz)
		Build.plotModels = {}
		for i, p in Places.cityFarmPlots() do
			local cf = W(p.X, PAD, p.Z)
			P(V(42, 0.6, 32), cf * CFrame.new(0, 0.3, 0), rgb(170, 124, 84), WOODM)
			P(V(40, 0.65, 30), cf * CFrame.new(0, 0.33, 0), Cc.soil)
			for r = -2, 2 do P(V(38, 0.4, 2), cf * CFrame.new(0, 0.7, r * 5.6), Cc.soil2) end
			local m = Instance.new("Model")
			m.Name = "Crop" .. i
			m.Parent = K.cur
			local num = P(V(2.6, 2.2, 0.3), cf * CFrame.new(-18, 2.4, -16.4), Cc.cream)
			K.textOn(num, Enum.NormalId.Front, tostring(i), Cc.soil2, Vector2.new(80, 70))
			P(V(0.4, 2, 0.4), cf * CFrame.new(-18, 1, -16.4), Cc.cream)
			Build.plotModels[i] = { m = m, cf = cf, stage = -2 }
		end
		-- two greenhouses and a hay stack along the east edge, when the farm
		-- pack is in (the plots themselves stay part-built: they animate)
		-- the plots fill x +-111 and z +-86 (42 x 32 at +-90 / +-70), so the
		-- one free strip is z 86..116 along the north edge -- everything new
		-- stands there, nothing on a plot
		if K.inv("Greenhouse_A") then
			K.place("Greenhouse_A", W(cx - 60, PAD, cz + 101), { width = 29, collide = "solid" })
			K.place("Greenhouse_A", W(cx + 60, PAD, cz + 101), { width = 29, collide = "solid" })
			for k = 0, 3 do K.place("HaySquare", W(cx - 104 + (k % 2) * 6, PAD + math.floor(k / 2) * 2.1, cz + 101 + (k % 2) * 0.4), { width = 5.5 }) end
			K.place("Wheelbarrow", W(cx + 4, PAD, cz + 104) * CFrame.Angles(0, 2.2, 0), { width = 3 })
		end
		local sc = W(cx + 110, PAD, cz)
		P(V(0.6, 10, 0.6), sc * CFrame.new(0, 5, 0), rgb(150, 110, 80), WOODM)
		P(V(8, 0.6, 0.6), sc * CFrame.new(0, 7.4, 0), rgb(150, 110, 80), WOODM)
		P(V(4, 4.4, 1.8), sc * CFrame.new(0, 6.8, 0), rgb(120, 160, 220))
		ball(3.4, sc * CFrame.new(0, 10.6, 0), rgb(246, 226, 170))
		cyl(5.4, 0.4, sc * CFrame.new(0, 12, 0), rgb(226, 190, 110))
		cyl(2.6, 1.6, sc * CFrame.new(0, 12.8, 0), rgb(226, 190, 110))
		K.sign(W(cx, PAD + 6, cz - 118), 30, 4, rgb(150, 110, 80), Cc.cream, "CITY FIELDS · PLANT + HARVEST")
	end
	function B.barn(cx, cz)
		local bf = K.frameOf(V(cx, 0, cz + 20), math.pi)
		local red = rgb(222, 104, 96)
		-- THE FARM PACK, when the owner's inventory has it: barn, silo, water
		-- tower and machines from one low-poly family, so the whole belt is
		-- one style instead of five part-built guesses. Same footprint as the
		-- part-built version so nothing else on the block has to move.
		if K.inv("Barn_A") then
			K.place("Barn_A", bf, { width = 54, collide = "solid" })
			K.place("Silo_A", W(cx + 50, PAD, cz + 30), { height = 46, collide = "solid" })
			K.place("WaterTower", W(cx + 80, PAD, cz - 30) * CFrame.Angles(0, 0.4, 0), { height = 38, collide = "solid" })
			-- farmhouse (part-built: the pack's house is 103 studs wide)
			local ff = K.frameOf(V(cx - 60, 0, cz - 50), 0)
			solid(P(V(36, 20, 26), ff * CFrame.new(0, 10, 0), rgb(255, 244, 220)))
			K.gable(ff, 36, 26, 20, 10, rgb(170, 110, 90))
			K.door(ff, 0, -13, rgb(170, 110, 90))
			for _, sx in { -1, 1 } do K.window(ff * CFrame.new(sx * 10, 6, -13), 5, 5, rgb(255, 214, 214), rgb(200, 140, 100)) end
			P(V(36, 0.8, 8), ff * CFrame.new(0, 10, -17), rgb(200, 150, 110), WOODM)
			K.place("Tractor", W(cx + 20, PAD, cz - 60) * CFrame.Angles(0, 0.6, 0), { width = 12, collide = "solid" })
			K.place("Trailer", W(cx + 36, PAD, cz - 66) * CFrame.Angles(0, 0.6, 0), { width = 12, collide = "solid" })
			for k = 0, 5 do
				K.place(k % 2 == 0 and "HayRound" or "HaySquare", W(cx - 90 + (k % 3) * 7, PAD, cz + 80 + math.floor(k / 3) * 7) * CFrame.Angles(0, k * 0.7, 0), { width = 5.5 })
			end
			K.place("ChickenCoop", W(cx - 40, PAD, cz + 70) * CFrame.Angles(0, -0.3, 0), { width = 10, collide = "solid" })
			K.place("Well", W(cx - 20, PAD, cz - 20), { height = 5, collide = "solid" })
			K.place("Wheelbarrow", W(cx + 4, PAD, cz - 40) * CFrame.Angles(0, 1.2, 0), { width = 3 })
			K.place("WoodStack", W(cx - 76, PAD, cz - 30), { width = 6 })
			park(W(cx - 30, PAD + 0.2, cz - 90) * CFrame.Angles(0, -0.4, 0), "van", rgb(170, 226, 160))
			return
		end
		solid(P(V(50, 26, 40), bf * CFrame.new(0, 13, 0), red))
		for _, sx in { -1, 1 } do P(V(1.4, 26, 1.4), bf * CFrame.new(sx * 25, 13, -20), Cc.cream) end
		P(V(18, 20, 0.6), bf * CFrame.new(0, 10, -20.2), shade(red, 0.15))
		P(V(19, 0.8, 0.8), bf * CFrame.new(0, 10, -20.6) * CFrame.Angles(0, 0, 0.84), Cc.cream)
		P(V(19, 0.8, 0.8), bf * CFrame.new(0, 10, -20.6) * CFrame.Angles(0, 0, -0.84), Cc.cream)
		K.gable(bf, 50, 40, 26, 16, rgb(120, 96, 90))
		local sf = W(cx + 50, PAD, cz + 30)
		solid(cyl(18, 50, sf * CFrame.new(0, 25, 0), rgb(214, 220, 228), METAL))
		ball(18, sf * CFrame.new(0, 50, 0), rgb(150, 190, 220), METAL)
		-- farmhouse
		local ff = K.frameOf(V(cx - 60, 0, cz - 50), 0)
		solid(P(V(36, 20, 26), ff * CFrame.new(0, 10, 0), rgb(255, 244, 220)))
		K.gable(ff, 36, 26, 20, 10, rgb(170, 110, 90))
		K.door(ff, 0, -13, rgb(170, 110, 90))
		for _, sx in { -1, 1 } do K.window(ff * CFrame.new(sx * 10, 6, -13), 5, 5, rgb(255, 214, 214), rgb(200, 140, 100)) end
		P(V(36, 0.8, 8), ff * CFrame.new(0, 10, -17), rgb(200, 150, 110), WOODM)
		-- a tractor
		local tr = W(cx + 20, PAD, cz - 60) * CFrame.Angles(0, 0.6, 0)
		P(V(6, 4, 9), tr * CFrame.new(0, 4, 0), rgb(120, 190, 110))
		P(V(5, 5, 4), tr * CFrame.new(0, 8, 2), rgb(120, 190, 110))
		for _, sx in { -1, 1 } do
			P(V(1.6, 7, 7), tr * CFrame.new(sx * 3.8, 3.5, 2.4), Cc.ink, SMOOTH, { shape = Enum.PartType.Cylinder })
			P(V(1.2, 4, 4), tr * CFrame.new(sx * 3.4, 2, -3), Cc.ink, SMOOTH, { shape = Enum.PartType.Cylinder })
		end
		for k = 0, 5 do cyl(5, 5, W(cx - 90 + (k % 3) * 6, PAD + 2.5, cz + 80 + math.floor(k / 3) * 6) * CFrame.Angles(0, 0, math.pi / 2), rgb(236, 206, 120)) end
		park(W(cx - 30, PAD + 0.2, cz - 90) * CFrame.Angles(0, -0.4, 0), "van", rgb(170, 226, 160))
	end
	function B.orchard(cx, cz)
		for i = -2, 2 do
			for j = -2, 2 do
				local x, z = cx + i * 40, cz + j * 40
				K.tree(x, z, 0.9)
				for q = 0, 4 do ball(1.4, W(x + math.cos(q * 1.3) * 3.6, PAD + 9 + (q % 2) * 2, z + math.sin(q * 1.3) * 3.6), q % 2 == 0 and Cc.red or rgb(255, 196, 110)) end
			end
		end
		K.sign(W(cx, PAD + 5, cz - 118), 24, 3.4, rgb(150, 110, 80), Cc.cream, "APPLE ORCHARD")
	end
	function B.windmills(cx, cz)
		fieldRows(cx, cz + 40, 200, 120, nil, function(cf, k)
			if k % 2 == 0 then P(V(1.6, 4, 1.6), cf * CFrame.new(0, 2, 0), rgb(236, 206, 120), MATTE, { mesh = Enum.MeshType.Sphere }) end
		end)
		for i, x in { -70, 0, 70 } do
			local base = W(cx + x, PAD, cz - 70)
			solid(cyl(10, 36, base * CFrame.new(0, 18, 0), Cc.cream))
			cyl(12, 4, base * CFrame.new(0, 38, 0), rgb(200, 110, 100))
			local hubCF = base * CFrame.new(0, 34, -6.5)
			local blades = Instance.new("Model")
			blades.Parent = K.cur
			local keep = K.cur
			K.cur = blades
			for k = 0, 3 do
				P(V(2.2, 22, 0.4), hubCF * CFrame.Angles(0, 0, k * math.pi / 2) * CFrame.new(0, 11, 0), rgb(250, 244, 232), WOODM)
			end
			ball(2.6, hubCF, Cc.ink)
			K.cur = keep
			blades.WorldPivot = hubCF
			table.insert(Build.anims, { cx = cx, cz = cz, far = true, fn = function(_, t) blades:PivotTo(hubCF * CFrame.Angles(0, 0, t * 0.8 + i)) end })
		end
	end
	function B.farmmarket(cx, cz)
		for k, nm in { "FRESH EGGS", "HONEY", "PIES", "VEGGIES", "FLOWERS", "JAM" } do
			local i = k - 1
			K.stall(W(cx - 60 + (i % 3) * 60, PAD, cz - 30 + math.floor(i / 3) * 60), nm, K.CAR_COLORS[k])
		end
		for k = 0, 5 do cyl(3, 3, W(cx - 50 + k * 20, PAD + 1.5, cz), rgb(200, 146, 96), WOODM) end
		-- the farm pack's produce: a crate of something on every stall counter,
		-- and a proper produce stand in the middle
		if K.inv("Crate_1") then
			for k = 0, 5 do
				local i = k
				local st = W(cx - 60 + (i % 3) * 60, PAD, cz - 30 + math.floor(i / 3) * 60)
				for j = 0, 2 do
					K.place("Crate_" .. ((k * 3 + j) % 10 + 1), st * CFrame.new(-3 + j * 3, 3.6, -1) * CFrame.Angles(0, (k + j) * 0.5, 0), { width = 2.8 })
				end
				K.place("Food_" .. (k % 8 + 1), st * CFrame.new(0, 5.5, 0), { width = 2 })
			end
			K.place("ProduceStand", W(cx, PAD, cz + 40) * CFrame.Angles(0, math.pi, 0), { width = 12, collide = "solid" })
			K.place("Barrel", W(cx + 10, PAD, cz + 44), { height = 3 })
		end
		K.sign(W(cx, PAD + 6, cz - 118), 26, 3.6, rgb(150, 110, 80), Cc.cream, "FARMERS MARKET")
		for _, p in { V(-100, 0, -100), V(100, 0, 100) } do K.tree(cx + p.X, cz + p.Z, 1.2) end
	end
	local function critter(cf, body, head, s)
		blob(V(4, 3.4, 6) * s, cf * CFrame.new(0, 3.4 * s, 0), body)
		blob(V(2.4, 2.4, 2.8) * s, cf * CFrame.new(0, 4.6 * s, -3.4 * s), head)
		for _, sx in { -1, 1 } do for _, sz in { -1.8, 1.8 } do P(V(0.8, 2, 0.8) * s, cf * CFrame.new(sx * 1.2 * s, 1 * s, sz * s), Cc.ink) end end
	end
	function B.pasture(cx, cz)
		for _, e in { { V(-110, 0, -110), V(110, 0, -110) }, { V(110, 0, -110), V(110, 0, 110) }, { V(110, 0, 110), V(-110, 0, 110) }, { V(-110, 0, 110), V(-110, 0, -110) } } do
			K.fence(V(cx, 0, cz) + e[1], V(cx, 0, cz) + e[2], rgb(196, 150, 104))
		end
		for k = 0, 11 do
			critter(W(cx - 80 + (k * 47) % 160, PAD, cz - 70 + (k * 31) % 140) * CFrame.Angles(0, k * 0.9, 0), rgb(250, 248, 242), rgb(80, 70, 70), 1)
		end
		local sh = K.frameOf(V(cx + 60, 0, cz + 70), math.pi)
		solid(P(V(24, 12, 16), sh * CFrame.new(0, 6, 0), rgb(200, 150, 110), WOODM))
		K.gable(sh, 24, 16, 12, 6, rgb(170, 110, 90))
		if K.inv("Trough") then
			K.place("Trough", W(cx - 40, PAD, cz + 60) * CFrame.Angles(0, 0.3, 0), { width = 10, collide = "solid" })
			for k = 0, 2 do K.place("Beehive", W(cx - 90 + k * 6, PAD, cz - 90), { height = 4 }) end
			K.place("HayPile", W(cx + 30, PAD, cz - 80), { width = 6 })
		end
	end
	function B.cows(cx, cz)
		for _, e in { { V(-110, 0, -110), V(110, 0, -110) }, { V(110, 0, -110), V(110, 0, 110) }, { V(110, 0, 110), V(-110, 0, 110) }, { V(-110, 0, 110), V(-110, 0, -110) } } do
			K.fence(V(cx, 0, cz) + e[1], V(cx, 0, cz) + e[2], Cc.cream)
		end
		for k = 0, 7 do
			local cf = W(cx - 70 + (k * 53) % 140, PAD, cz - 60 + (k * 37) % 120) * CFrame.Angles(0, k * 1.3, 0)
			critter(cf, Cc.cream, rgb(250, 220, 220), 1.5)
			blob(V(2, 2, 2.4), cf * CFrame.new(1, 5.6, 1), Cc.ink)
		end
		if not K.place("Trough", W(cx, PAD, cz), { width = 12, collide = "solid" }) then
			P(V(12, 2, 3), W(cx, PAD + 1, cz), rgb(170, 124, 84), WOODM)
			P(V(11, 2.1, 2.2), W(cx, PAD + 1.1, cz), Cc.water, SMOOTH)
		end
	end
	function B.pumpkins(cx, cz)
		fieldRows(cx, cz, 200, 200, nil, function(cf, k)
			if k % 2 == 0 then
				P(V(3.4, 2.6, 3.4), cf * CFrame.new(0, 1.3, 0), rgb(255, 150, 70), MATTE, { mesh = Enum.MeshType.Sphere })
			else
				blob(V(2.4, 1, 2.4), cf * CFrame.new(0, 0.6, 0), Cc.leaf)
			end
		end)
		K.sign(W(cx, PAD + 5, cz - 118), 24, 3.4, rgb(255, 150, 70), Cc.cream, "PUMPKIN PATCH")
	end
	function B.sunflowers(cx, cz)
		for i = -8, 8 do
			for j = -8, 8, 2 do
				local cf = W(cx + i * 12, PAD, cz + j * 12)
				P(V(0.5, 9, 0.5), cf * CFrame.new(0, 4.5, 0), Cc.leaf3)
				local head = cf * CFrame.new(0, 9.6, -0.5) * CFrame.Angles(math.pi / 2 - 0.2, 0, 0)
				cyl(4, 0.5, head, rgb(255, 214, 80))
				cyl(2, 0.7, head, rgb(130, 90, 60))
			end
		end
	end
	function B.lake(cx, cz)
		local c = W(cx, PAD, cz)
		cyl(230, 0.4, c * CFrame.new(0, 0.12, 0), rgb(214, 204, 170))
		cyl(220, 0.45, c * CFrame.new(0, 0.18, 0), Cc.water, SMOOTH).Reflectance = 0.1
		-- a jetty with rowing boats
		for k = 0, 9 do P(V(8, 0.6, 3.6), c * CFrame.new(0, 1, -110 + k * 3.8), rgb(200, 146, 96), WOODM) end
		for k, sx in { -8, 8 } do
			local bt = c * CFrame.new(sx, 0.6, -84) * CFrame.Angles(0, k, 0)
			P(V(4, 1.6, 10), bt * CFrame.new(0, 0.6, 0), K.CAR_COLORS[k + 1])
			P(V(3.2, 0.3, 8.8), bt * CFrame.new(0, 1.3, 0), Cc.cream)
		end
		local swans = {}
		for k = 1, 5 do
			local sw = { a = k * 1.2, r = 40 + k * 10, sp = 0.05 + k * 0.01 }
			sw.p = { blob(V(3, 2.6, 5), c, Cc.cream), P(V(0.8, 4, 0.8), c, Cc.cream), ball(1.4, c, Cc.cream) }
			table.insert(swans, sw)
		end
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(dt)
			for _, sw in swans do
				sw.a += sw.sp * dt
				local p = c * CFrame.new(math.cos(sw.a) * sw.r, 0.8, math.sin(sw.a) * sw.r) * CFrame.Angles(0, -sw.a, 0)
				sw.p[1].CFrame = p * CFrame.new(0, 1, 0)
				sw.p[2].CFrame = p * CFrame.new(0, 3.4, -2) * CFrame.Angles(-0.3, 0, 0)
				sw.p[3].CFrame = p * CFrame.new(0, 5.4, -2.8)
			end
		end })
		K.sign(W(cx, PAD + 5, cz - 122), 24, 3.4, Cc.signGreen, Cc.cream, "MIRROR LAKE")
	end
	function B.camp(cx, cz)
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			local tc = W(cx + math.cos(a) * 40, PAD, cz + math.sin(a) * 40) * CFrame.Angles(0, -a + math.pi / 2, 0)
			for _, sx in { -1, 1 } do
				P(V(0.4, 9, 12), tc * CFrame.new(sx * 3, 3.6, 0) * CFrame.Angles(0, 0, sx * 0.62), K.CAR_COLORS[k + 1])
			end
		end
		local fire = W(cx, PAD, cz)
		K.place("WoodStack", fire * CFrame.new(14, 0, 6) * CFrame.Angles(0, 0.8, 0), { width = 6 })
		K.place("Barrel", fire * CFrame.new(-13, 0, 9), { height = 3.2 })
		for k = 0, 5 do cyl(1, 6, fire * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.pi / 2, k, 0), Cc.trunk, WOODM) end
		local flame = blob(V(3, 5, 3), fire * CFrame.new(0, 3, 0), rgb(255, 170, 80), NEON)
		flame.CastShadow = false
		table.insert(Build.anims, { cx = cx, cz = cz, fn = function(_, t) flame.Size = V(3, 4.4 + math.sin(t * 9) * 0.8, 3) end })
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + 0.4
			cyl(2.4, 8, fire * CFrame.new(math.cos(a) * 12, 1.2, math.sin(a) * 12) * CFrame.Angles(0, -a, math.pi / 2), Cc.trunk, WOODM)
		end
		for k = 0, 17 do
			local a = k / 18 * math.pi * 2
			K.pine(W(cx + math.cos(a) * (80 + (k % 3) * 12), PAD, cz + math.sin(a) * (80 + (k % 3) * 12)), 1.2)
		end
	end
	-- RESTAURANT ROW (docs/TYCOON.md). This block was `forest`: thirty pines
	-- and a cabin. It is twelve tycoon plots now, three a side, each with a
	-- paved apron, a kerb, a claim gate and a FOR LEASE post -- and nothing
	-- else, because the restaurant that stands on a plot is drawn by
	-- CityTycoon from the lot's replicated state (it is a player's, and it
	-- changes). The cabin keeps the middle of the block as the Row's green:
	-- a ring of pines, benches and the arch sign the wayfinder points at.
	function B.restaurantrow(cx, cz)
		local T = Config.Tycoon
		local rng = Random.new(cx * 7 + cz)
		-- the middle: the cabin from the old forest, now the Row's office
		local cf = K.frameOf(V(cx, 0, cz), 0)
		solid(P(V(24, 12, 18), cf * CFrame.new(0, 6, 0), rgb(170, 120, 84), WOODM))
		for k = 0, 5 do P(V(24.4, 0.6, 18.4), cf * CFrame.new(0, 1 + k * 2, 0), rgb(140, 96, 66), WOODM) end
		K.gable(cf, 24, 18, 12, 7, rgb(96, 130, 90))
		K.door(cf, 0, -9, rgb(120, 80, 60))
		K.sign(cf * CFrame.new(0, 10.4, -9.4), 20, 3, Cc.cream, Cc.ink, "RESTAURANT ROW", 0.3)
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			K.pine(W(cx + math.cos(a) * (44 + (k % 2) * 10), PAD, cz + math.sin(a) * (44 + (k % 2) * 10)), rng:NextNumber(1, 1.4))
		end
		for _, q in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			K.bench(W(cx + math.sin(q) * 22, PAD, cz + math.cos(q) * 22) * CFrame.Angles(0, q + math.pi, 0))
		end
		-- the plots
		local lots = Places.tycoonLots()
		for _, lot in lots do
			if lot.block ~= (cx .. "," .. cz) then continue end
			local f = K.frameOf(lot.pos, lot.face)
			local w, d = T.LotW, T.LotD
			-- the apron, a half stud above the block's lawn, with a kerb round it
			walkable(P(V(w, 0.5, d), f * CFrame.new(0, 0.25, 0), rgb(214, 210, 200), MATTE, { noShadow = true }))
			for _, sx in { -1, 1 } do P(V(0.6, 0.7, d + 0.6), f * CFrame.new(sx * w / 2, 0.35, 0), Cc.curb, MATTE, { noShadow = true }) end
			P(V(w + 0.6, 0.7, 0.6), f * CFrame.new(0, 0.35, d / 2), Cc.curb, MATTE, { noShadow = true })
			-- the paving joints, so it reads as a plot and not a slab
			for k = -2, 2 do P(V(0.25, 0.02, d - 2), f * CFrame.new(k * 9, 0.51, 0), Cc.paveJoint, MATTE, { noShadow = true }) end
			-- a low fence along the back and the two sides' rear halves
			local A, Bk = Places.tycoonPoint(lot, -w / 2, d / 2), Places.tycoonPoint(lot, w / 2, d / 2)
			K.fence(A, Bk, Cc.cream)
			K.fence(Places.tycoonPoint(lot, -w / 2, 0), A, Cc.cream)
			K.fence(Bk, Places.tycoonPoint(lot, w / 2, 0), Cc.cream)
			-- THE GATE: two posts and a header, kerbside by the pad strip. The
			-- tycoon kit's gate is a slab that says "touch to claim"; this one
			-- says it on the prompt card, which is how this city talks.
			local g = T.Spots.gate
			local gcf = f * CFrame.new(g[1], 0, g[2])
			for _, sx in { -3.2, 3.2 } do solid(P(V(1, 7, 1), gcf * CFrame.new(sx, 4, 0), Cc.ink, SMOOTH)) end
			P(V(8, 1.6, 1.2), gcf * CFrame.new(0, 7.6, 0), Cc.ink, SMOOTH)
			K.threshold(gcf * CFrame.new(0, 0.5, 0), 6, 4)
			-- FOR LEASE, on the sign post. CityTycoon puts the owner's name
			-- over it when the lot is taken.
			local sp = T.Spots.sign
			local scf = f * CFrame.new(sp[1], 0, sp[2])
			solid(cyl(0.4, 9, scf * CFrame.new(0, 4.5, 0), Cc.lampPost, METAL))
			local board = P(V(7, 3.4, 0.5), scf * CFrame.new(0, 9.6, 0), Cc.cream)
			K.textOn(board, Enum.NormalId.Front, "LOT " .. lot.i .. "\nFOR LEASE", Cc.ink, Vector2.new(300, 150), 0.4)
			K.textOn(board, Enum.NormalId.Back, "LOT " .. lot.i .. "\nFOR LEASE", Cc.ink, Vector2.new(300, 150), 0.4)
			-- nothing else on the plot: the terrace, the door and the pad
			-- strip all want the front, and the owner dresses their own
		end
		Build.destinations = Build.destinations or {}
		table.insert(Build.destinations, { name = "Restaurant Row", pos = V(cx, 0, cz - HALF_B - 6), kind = "tycoon", district = "farm" })
	end

	---------------------------------------------------------------------------
	-- REGISTRY
	---------------------------------------------------------------------------
	function Build.blocks()
		local out = {}
		for key, kind in Places.CityBlocks do
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			table.insert(out, {
				cx = cx, cz = cz, kind = kind,
				run = function()
					blockBase(cx, cz, kind)
					local fn = B[kind]
					if fn then fn(cx, cz) end
					-- the street wall goes up last, in front of whatever the
					-- block built, so every urban kerb has a building on it
					for i, l in lotsIn(cx, cz) do
						if l.kind == "midrise" then B.midrise(l, i)
						elseif l.kind == "corner" then B.corner(l, i)
						elseif l.kind == "venue" then B.venue(l, i)
						elseif l.kind == "jobcentre" then B.jobcentre(l, i)
						elseif l.kind == "workplace" then B.workplace(l, i) end
					end
					-- an apartment tower, if one stands in this block
					for id, a in Places.CityApts do
						if math.abs(a.pos.X - cx) < HALF_B and math.abs(a.pos.Z - cz) < HALF_B then B.aptTower(id, a) end
					end
					-- kerb furniture, corner ponds and plazas (CityDress)
					if Build.dress then Build.dress(cx, cz, kind) end
					-- somewhere to be with other people (CityHangouts). Wrapped:
					-- streamStep swallows a builder error into a warn and marks
					-- the block done, so an accident in here would silently eat
					-- the rest of the block rather than showing up as a crash.
					if Build.hangout and (kind == "concert" or kind == "park") then
						local okH, eH = pcall(Build.hangout, kind)
						if not okH then warn("[SminskiCity] hangout " .. kind .. " failed: " .. tostring(eH)) end
					end
				end,
			})
		end
		return out
	end

	-- pines scattered over the valley slopes (the mountains are Terrain);
	-- one chunk per slope so they stream in like blocks
	function Build.nature()
		local chunks = { { cx = 0, cz = 1100, kind = "harbour", far = true, run = function()
			Build.harbour()
			-- the boardwalk: benches, a fire and fishing, on the deck the
			-- harbour already built (CityHangouts)
			if Build.hangout then Build.hangout("harbour") end
		end } }
		for _, ch in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
			table.insert(chunks, {
				cx = ch[1] * 1250, cz = ch[2] * 1250, kind = "nature", far = true,
				run = function()
					local rng = Random.new(ch[1] * 31 + ch[2] * 17 + 99)
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Include
					params.FilterDescendantsInstances = { workspace.Terrain }
					for _ = 1, 170 do
						local x, z
						if ch[1] ~= 0 then
							x = ch[1] * rng:NextNumber(1020, 1500)
							z = rng:NextNumber(-1300, 1300)
						else
							x = rng:NextNumber(-1300, 1300)
							z = ch[2] * rng:NextNumber(1020, 1400)
						end
						local hit = workspace:Raycast(CITY + V(x, 1400, z), V(0, -1600, 0), params)
						if hit and hit.Position.Y - CITY.Y < 420 and hit.Material ~= Enum.Material.Rock and hit.Material ~= Enum.Material.Snow and hit.Material ~= Enum.Material.Water and hit.Material ~= Enum.Material.Sand then
							K.pine(CFrame.new(hit.Position - V(0, 1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(1.3, 2.4))
						end
					end
				end,
			})
		end
		return chunks
	end

	return Build
end
