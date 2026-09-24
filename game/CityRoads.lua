-- CityRoads (client): builds everything in Roads.lua -- the Bay Freeway, the
-- Bay Bridge, The Elevated and its stations, the airport island -- and runs
-- the trains and the planes.
--   R.build()            called once with the road base (always visible)
--   R.update(dt, t, me)  trains + planes + riding
--   R.prompt(me)         BOARD / GET OFF at a platform
-- The street grid is untouched: this network is laid round it and over it.
--   deps: K, Build, Places, Roads, Models, UI, Audio, S, player

return function(deps)
	local K, Build, Places, Roads, Models = deps.K, deps.Build, deps.Places, deps.Roads, deps.Models
	local UI, Audio, S, player = deps.UI, deps.Audio, deps.S, deps.player
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local P, cyl, ball, blob, solid, walkable = K.P, K.cyl, K.ball, K.blob, K.solid, K.walkable
	local part = Models.part
	local Cc = K.C
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL
	local CITY = Places.CITY
	local ROADS = Places.CityRoads
	local R = { trains = {}, planes = {}, lifts = {}, cars = {} }

	local CONCRETE = rgb(188, 188, 182)
	local ASPHALT = Cc.road
	local STEEL = rgb(86, 110, 96)

	-- a box laid from a to b (city-relative), `w` wide, top surface on the line
	local function span(a, b, w, thick, col, mat, extra, lateral, lift)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + (extra or 0.6)
		local cf = CFrame.lookAt(CITY + mid, CITY + b) * CFrame.new(lateral or 0, (lift or 0) - thick / 2, 0)
		return P(V(w, thick, len), cf, col, mat or MATTE), cf
	end
	local function nearRoadLine(v)
		for _, r in ROADS do if math.abs(v - r) < 27 then return true end end
		return false
	end

	---------------------------------------------------------------------------
	-- ROAD DECKS (freeway + bridge)
	---------------------------------------------------------------------------
	-- openings in the side barriers, where one road joins another
	local GAPS = { { pos = V(-470, 0, 983), r = 22 } }
	local function barrierRuns(pc, lateral)
		-- split a piece's barrier round any gap that falls on it
		local dir = (pc.b - pc.a).Unit
		local right = V(-dir.Z, 0, dir.X)
		local runs = { { 0, pc.len } }
		for _, g in GAPS do
			local rel = g.pos - pc.a
			local along = V(rel.X, 0, rel.Z):Dot(V(dir.X, 0, dir.Z).Unit)
			local side = V(rel.X, 0, rel.Z):Dot(right)
			if along > 0 and along < pc.len and math.abs(side - lateral) < 8 then
				local out = {}
				for _, run in runs do
					if along - g.r > run[1] then table.insert(out, { run[1], math.min(run[2], along - g.r) }) end
					if along + g.r < run[2] then table.insert(out, { math.max(run[1], along + g.r), run[2] }) end
				end
				runs = out
			end
		end
		return runs, dir
	end
	local function deck(name)
		local path = Roads.paths[name]
		local w = path.width
		local pcs = Roads.pieces(name)
		local sincePillar = 40
		for _, pc in ipairs(pcs) do
			local elevated = math.max(pc.a.Y, pc.b.Y) > 1.5
			local extra = pc.arc and 3 or 0.8
			-- the running surface (cars ride on it, you can walk on it)
			local d = span(pc.a, pc.b, w, elevated and 1.4 or 0.3, ASPHALT, SMOOTH, extra)
			walkable(d)
			if elevated then
				span(pc.a, pc.b, w + 2, 1.2, CONCRETE, MATTE, extra, 0, -1.4)
				-- kerb barriers both sides, broken where another road joins
				for _, lat in { -(w / 2 - 0.6), w / 2 - 0.6 } do
					local runs, dir = barrierRuns(pc, lat)
					for _, run in runs do
						if run[2] - run[1] > 1 then
							local a, b = pc.a + dir * run[1], pc.a + dir * run[2]
							solid((span(a, b, 1.2, 3.2, CONCRETE, MATTE, pc.arc and 1.4 or 0.4, lat, 3.2)))
						end
					end
				end
			end
			if name == "freeway" then
				-- a median, and lane dashes on the straights
				if elevated then solid((span(pc.a, pc.b, 1.4, 2.2, CONCRETE, MATTE, extra, 0, 2.2))) end
				if not pc.arc and pc.len > 60 then
					local dir = (pc.b - pc.a).Unit
					for s = 12, pc.len - 12, 30 do
						for _, lat in { -10, 10 } do
							local q = pc.a + dir * s
							span(q, q + dir * 9, 0.6, 0.08, Cc.line, SMOOTH, 0, lat, 0.06)
						end
					end
				end
			else
				span(pc.a, pc.b, 0.6, 0.08, Cc.line, SMOOTH, extra, 0, 0.06)
			end
			-- columns down to the ground (or the sea bed) under anything raised
			sincePillar += pc.len
			local y = (pc.a.Y + pc.b.Y) / 2
			if y > 9 and sincePillar > 78 then
				sincePillar = 0
				local mid = (pc.a + pc.b) / 2
				local overWater = mid.Z > 1015
				local foot = overWater and -24 or 0
				local h = y - 2.6 - foot
				local cf = CFrame.lookAt(CITY + V(mid.X, 0, mid.Z), CITY + V(pc.b.X, 0, pc.b.Z))
				P(V(w * 0.72, 2.4, 5), cf * CFrame.new(0, y - 3.8, 0), CONCRETE)
				for _, lat in { -w * 0.26, w * 0.26 } do
					solid(P(V(3.6, h, 3.6), cf * CFrame.new(lat, foot + h / 2, 0), CONCRETE))
				end
			end
		end
	end

	-- the bridge's two towers and their cables
	local function bridgeTowers()
		for _, z in { 1300, 1420 } do
			local base = CFrame.new(CITY + V(-470, 0, z))
			for _, sx in { -19, 19 } do
				solid(P(V(5, 150, 7), base * CFrame.new(sx, 51, 0), rgb(214, 96, 88), METAL))
			end
			P(V(43, 6, 6), base * CFrame.new(0, 122, 0), rgb(214, 96, 88), METAL)
			P(V(43, 4, 6), base * CFrame.new(0, 86, 0), rgb(214, 96, 88), METAL)
			for _, sx in { -19, 19 } do
				for k = 1, 5 do
					for _, dz in { -1, 1 } do
						local top = CITY + V(-470 + sx, 124, z)
						local foot = CITY + V(-470 + sx, 53, z + dz * k * 34)
						local c = P(V(0.5, 0.5, (top - foot).Magnitude), CFrame.lookAt((top + foot) / 2, foot), rgb(236, 232, 224), METAL)
						c.CastShadow = false
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- THE ELEVATED: deck, rails, a single row of columns down the median
	---------------------------------------------------------------------------
	local function viaduct()
		local pcs = Roads.pieces("rail")
		local since = 40
		for _, pc in ipairs(pcs) do
			local extra = pc.arc and 1.6 or 0.6
			walkable((span(pc.a, pc.b, 12, 1.4, STEEL, METAL, extra)))
			for _, lat in { -2.6, 2.6 } do span(pc.a, pc.b, 0.7, 0.5, rgb(190, 194, 196), METAL, extra, lat, 0.5) end
			for _, lat in { -5.7, 5.7 } do span(pc.a, pc.b, 0.5, 1.6, shade(STEEL, 0.15), METAL, extra, lat, 1.6) end
			-- columns stand mid-block only: never in a junction
			local dir = (pc.b - pc.a).Unit
			local s = 0
			while s < pc.len do
				since += 12
				local q = pc.a + dir * s
				local along = math.abs(dir.X) > 0.5 and q.X or q.Z
				if since > 58 and not pc.arc and not nearRoadLine(along) then
					since = 0
					local cf = CFrame.lookAt(CITY + V(q.X, 0, q.Z), CITY + V(q.X + dir.X, 0, q.Z + dir.Z))
					solid(P(V(3, pc.a.Y - 2, 3), cf * CFrame.new(0, (pc.a.Y - 2) / 2, 0), STEEL, METAL))
					P(V(11, 1.6, 3.4), cf * CFrame.new(0, pc.a.Y - 2.4, 0), STEEL, METAL)
					for _, lat in { -3.4, 3.4 } do
						P(V(0.8, 7, 0.8), cf * CFrame.new(lat, pc.a.Y - 5, 0) * CFrame.Angles(0, 0, lat > 0 and 0.62 or -0.62), STEEL, METAL)
					end
				end
				s += 12
			end
		end
	end

	-- a station: two platforms, canopies, and a ramp down to each pavement
	local function station(st)
		local s0 = Roads.nearest("rail", st.pos)
		local pos, dir = Roads.at("rail", s0)
		st.s = s0
		local cf = CFrame.lookAt(CITY + pos, CITY + pos + dir)
		st.cf = cf
		for _, side in { -1, 1 } do
			local plat = walkable(P(V(9, 1.2, 84), cf * CFrame.new(side * 10.6, -0.6, 0), rgb(222, 214, 198), MATTE))
			P(V(1, 0.3, 84), cf * CFrame.new(side * 6.6, 0.06, 0), rgb(250, 214, 110), SMOOTH)
			-- canopy
			for _, dz in { -30, 0, 30 } do cyl(0.6, 10, cf * CFrame.new(side * 13.4, 5, dz), STEEL, METAL) end
			P(V(10, 0.6, 76), cf * CFrame.new(side * 10.8, 10.2, 0) * CFrame.Angles(0, 0, side * 0.08), rgb(96, 150, 130), METAL)
			solid(P(V(0.5, 3.4, 84), cf * CFrame.new(side * 15, 1.7, 0), shade(STEEL, 0.1), METAL))
			-- name board + a bench
			local board = P(V(0.4, 3, 18), cf * CFrame.new(side * 14.6, 6.4, 0), rgb(60, 110, 160))
			K.textOn(board, side > 0 and Enum.NormalId.Left or Enum.NormalId.Right, st.name, Cc.cream, Vector2.new(520, 90), 0.4)
			K.bench(cf * CFrame.new(side * 13, 0, 18) * CFrame.Angles(0, side * math.pi / 2, 0))
			-- a footbridge out over the traffic lane to a glass LIFT at the kerb.
			-- (A walk-down ramp would need forty studs of pavement and would run
			-- straight across the shop doorways; a lift takes seven.)
			walkable(P(V(11, 1, 7), cf * CFrame.new(side * 20, -0.5, -11), rgb(222, 214, 198)))
			local lift = cf * CFrame.new(side * 25.5, -pos.Y, -11)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do cyl(0.6, pos.Y + 9, lift * CFrame.new(sx * 3.2, (pos.Y + 9) / 2, sz * 3.2), STEEL, METAL) end
			end
			local shaft = P(V(6.2, pos.Y + 8, 6.2), lift * CFrame.new(0, (pos.Y + 8) / 2, 0), Cc.pane, K.GLASS, { transparency = 0.7 })
			shaft.CastShadow = false
			P(V(7.4, 0.8, 7.4), lift * CFrame.new(0, pos.Y + 9.2, 0), rgb(96, 150, 130), METAL)
			local lamp = P(V(5, 0.4, 5), lift * CFrame.new(0, 0.4, 0), rgb(250, 214, 110), NEON)
			lamp.CastShadow = false
			table.insert(R.lifts, {
				station = st,
				bottom = lift.Position - CITY,
				-- the DOWN button is out on the footbridge; you ARRIVE on the
				-- platform itself, so a waiting passenger is offered the train
				top = (cf * CFrame.new(side * 21, 0, -11)).Position - CITY,
				arrive = (cf * CFrame.new(side * 10.6, 0, -4)).Position - CITY,
			})
		end
	end

	---------------------------------------------------------------------------
	-- TRAINS
	---------------------------------------------------------------------------
	local CAR_LEN, GAP = 26, 2
	local function buildTrain(col)
		local cars = {}
		for i = 1, 3 do
			local m = Instance.new("Model")
			m.Name = "ElevatedCar"
			local function A(size, cf, c, mat, opts) return part(m, size, cf, c, mat or MATTE, opts) end
			A(V(9.4, 8.4, CAR_LEN), CFrame.new(0, 5.4, 0), rgb(236, 232, 222))
			A(V(9.6, 2.2, CAR_LEN + 0.2), CFrame.new(0, 2.6, 0), col)
			A(V(9.0, 1, CAR_LEN - 1), CFrame.new(0, 10, 0), shade(col, 0.15))
			for _, sx in { -1, 1 } do
				A(V(0.3, 3, CAR_LEN - 6), CFrame.new(sx * 4.75, 6.4, 0), Cc.pane, SMOOTH, { reflect = 0.12 })
				for _, dz in { -7, 7 } do A(V(0.35, 6.4, 3.2), CFrame.new(sx * 4.78, 4.6, dz), shade(col, 0.05)) end
			end
			A(V(7, 3, 0.3), CFrame.new(0, 6.4, -CAR_LEN / 2 - 0.1), Cc.pane, SMOOTH, { reflect = 0.12 })
			for _, dz in { -8, 8 } do A(V(7, 1.4, 5), CFrame.new(0, 0.9, dz), Cc.ink, METAL) end
			if i == 1 then
				for _, sx in { -2.6, 2.6 } do A(V(1, 1, 0.4), CFrame.new(sx, 3, -CAR_LEN / 2 - 0.2), rgb(255, 244, 200), NEON) end
			end
			for _, p in m:GetChildren() do p.CastShadow = p.Size.Magnitude > 8 end
			m.WorldPivot = CFrame.new()
			m.Parent = K.actors
			cars[i] = m
		end
		return cars
	end
	local function stepTrain(tr, dt)
		local len = Roads.pieces("rail").length
		-- the next station ahead
		local ahead, which = math.huge, nil
		for _, st in Roads.stations do
			local d = (st.s - tr.s) % len
			if d < ahead then ahead, which = d, st end
		end
		if tr.dwell > 0 then
			tr.dwell -= dt
			tr.v = 0
			if tr.dwell <= 0 then tr.left = tr.at tr.at = nil end
		else
			local target = 46
			if which ~= tr.left and ahead < 90 then target = math.max(3, ahead * 0.55) end
			tr.v += (target - tr.v) * math.min(1, dt * 1.4)
			if which ~= tr.left and ahead < 1.2 then
				tr.dwell, tr.at, tr.v = 6, which, 0
			end
			if tr.left and (tr.left.s - tr.s) % len > 120 and (tr.left.s - tr.s) % len < len - 120 then tr.left = nil end
		end
		tr.s = (tr.s + tr.v * dt) % len
		for i, m in tr.cars do
			local s = tr.s - (i - 1) * (CAR_LEN + GAP)
			local front, back = Roads.at("rail", s + CAR_LEN * 0.36), Roads.at("rail", s - CAR_LEN * 0.36)
			local cf = CFrame.lookAt(CITY + (front + back) / 2 + V(0, 0.9, 0), CITY + front + V(0, 0.9, 0))
			m:PivotTo(cf)
			tr.cfs[i] = cf
		end
	end

	---------------------------------------------------------------------------
	-- THE AIRPORT ISLAND
	---------------------------------------------------------------------------
	local function plane(col, parent)
		local m = Instance.new("Model")
		m.Name = "Plane"
		local function A(size, cf, c, mat, opts) return part(m, size, cf, c, mat or SMOOTH, opts) end
		local white = rgb(248, 246, 240)
		A(V(64, 9, 9), CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), white, SMOOTH, { shape = Enum.PartType.Cylinder })
		A(V(9, 9, 9), CFrame.new(0, 0, -32), white, SMOOTH, { shape = Enum.PartType.Ball })
		A(V(7, 7, 12), CFrame.new(0, 0.6, 35), white, SMOOTH, { mesh = Enum.MeshType.Sphere })
		A(V(58, 1, 12), CFrame.new(0, -1.6, 2), white)
		A(V(22, 0.8, 7), CFrame.new(0, 1, 33), white)
		A(V(1, 13, 9), CFrame.new(0, 7, 34) * CFrame.Angles(-0.35, 0, 0), col)
		A(V(8.6, 1.6, 50), CFrame.new(0, -0.4, 0), col)
		for _, sx in { -15, 15 } do A(V(8, 4, 4), CFrame.new(sx, -3.4, -1) * CFrame.Angles(0, math.pi / 2, 0), rgb(120, 126, 132), METAL, { shape = Enum.PartType.Cylinder }) end
		for k = -5, 5 do for _, sx in { -1, 1 } do A(V(0.3, 1.6, 2.2), CFrame.new(sx * 4.55, 1.2, k * 4.4), rgb(90, 120, 150), SMOOTH) end end
		for _, p in m:GetChildren() do p.CastShadow = p.Size.Magnitude > 20 end
		m.WorldPivot = CFrame.new()
		m.Parent = parent
		return m
	end
	local function airport()
		local A = Roads.airport
		local c = CFrame.new(CITY + A.center)
		-- the island: a sand skirt under a paved top
		P(V(A.size.X + 60, 10, A.size.Z + 60), c * CFrame.new(0, -8, 0), rgb(240, 224, 178), Enum.Material.Sand)
		walkable(P(V(A.size.X, 6, A.size.Z), c * CFrame.new(0, -3, 0), rgb(196, 198, 192), MATTE))
		-- runway + centre line + threshold bars
		local ra, rb = A.runway.a, A.runway.b
		span(ra, rb, A.runway.width, 0.3, rgb(64, 66, 72), SMOOTH, 0)
		local dir = (rb - ra).Unit
		for s = 40, (rb - ra).Magnitude - 40, 60 do
			local q = ra + dir * s
			span(q, q + dir * 26, 1.6, 0.08, Cc.line, SMOOTH, 0, 0, 0.1)
		end
		for _, e in { ra + dir * 14, rb - dir * 14 } do
			for k = -3, 3 do span(e, e + dir * 18, 3, 0.08, Cc.line, SMOOTH, 0, k * 7, 0.1) end
		end
		-- the road in from the bridge, a set-down lane, and a car park
		walkable((span(V(-470, 3.06, 1745), V(330, 3.06, 1745), 30, 0.2, ASPHALT, SMOOTH, 0)))
		span(V(-440, 3.08, 1745), V(320, 3.08, 1745), 0.6, 0.06, Cc.line, SMOOTH, 0, 0, 0.06)
		P(V(200, 0.2, 60), c * CFrame.new(430, 0.1, -170), rgb(90, 92, 98), SMOOTH, { noShadow = true })
		for k = 0, 9 do P(V(0.5, 0.06, 22), c * CFrame.new(345 + k * 19, 0.22, -170), Cc.line, SMOOTH, { noShadow = true }) end
		-- the apron and a taxiway back to the terminal
		P(V(620, 0.2, 130), c * CFrame.new(-70, 0.1, -20), rgb(90, 92, 98), SMOOTH, { noShadow = true })
		-- TERMINAL: a long glass hall you can walk into
		local t = CFrame.new(CITY + A.terminal)
		local TW, TD, TH = 300, 56, 34
		walkable(P(V(TW, 0.6, TD), t * CFrame.new(0, 0.3, 0), rgb(232, 226, 214), SMOOTH))
		-- airside wall is glass: you watch the planes from the departure lounge
		local air = solid(P(V(TW, TH, 1.4), t * CFrame.new(0, TH / 2, TD / 2), Cc.pane, K.GLASS, { transparency = 0.5 }))
		air.CastShadow = false
		for _, sx in { -1, 1 } do solid(P(V(1.4, TH, TD), t * CFrame.new(sx * TW / 2, TH / 2, 0), rgb(236, 232, 222))) end
		for k = -3, 3 do
			if k ~= 0 then
				local g = solid(P(V(38, TH - 8, 0.6), t * CFrame.new(k * 40, (TH - 8) / 2, -TD / 2), Cc.pane, K.GLASS, { transparency = 0.55 }))
				g.CastShadow = false
			end
		end
		for k = -4, 4 do P(V(2, TH, 2), t * CFrame.new(k * 40 - 20, TH / 2, -TD / 2), rgb(96, 150, 130), METAL) end
		P(V(TW + 12, 2.4, TD + 16), t * CFrame.new(0, TH + 1.2, -2), rgb(96, 150, 130), METAL)
		blob(V(TW + 12, 16, TD + 16), t * CFrame.new(0, TH + 2.4, -2), rgb(226, 232, 236))
		local sgn = P(V(120, 9, 1), t * CFrame.new(0, TH + 14, -TD / 2 - 4), rgb(60, 110, 160))
		K.textOn(sgn, Enum.NormalId.Front, "SMINSKI INTERNATIONAL", Cc.cream, Vector2.new(1100, 90), 0.4)
		-- rows of seats, a departures board, a check-in desk
		for row = -1, 1, 2 do
			for k = -2, 2 do
				solid(P(V(22, 1.6, 4), t * CFrame.new(k * 44, 1.4, row * 9), rgb(96, 140, 196), Enum.Material.Fabric))
				P(V(22, 3, 0.8), t * CFrame.new(k * 44, 3.2, row * 9 + row * 1.8), rgb(96, 140, 196), Enum.Material.Fabric)
			end
		end
		local board = P(V(70, 12, 0.8), t * CFrame.new(0, 18, TD / 2 - 1.2), Cc.ink)
		K.textOn(board, Enum.NormalId.Front, "DEPARTURES   ·   BAY TOUR  ON TIME   ·   MOUNTAIN LOOP  BOARDING", rgb(255, 214, 120), Vector2.new(1400, 110), 0)
		solid(P(V(60, 4, 5), t * CFrame.new(-100, 2, TD / 2 - 8), rgb(176, 136, 100), WOODM))
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = 60, 0.9, false
		pl.Parent = board
		-- CONTROL TOWER
		local tw = c * CFrame.new(300, 0, -150)
		solid(cyl(16, 96, tw * CFrame.new(0, 48, 0), rgb(236, 232, 222)))
		cyl(34, 12, tw * CFrame.new(0, 102, 0), Cc.pane, K.GLASS, { transparency = 0.4 })
		cyl(38, 3, tw * CFrame.new(0, 109, 0), rgb(96, 150, 130), METAL)
		cyl(1, 22, tw * CFrame.new(0, 121, 0), Cc.red, METAL)
		-- planes parked nose-in at the terminal
		for k, x in { -170, -60, 150 } do
			local m = plane(K.CAR_COLORS[k * 2], K.cur)
			m:PivotTo(t * CFrame.new(x, 8.4, 84))
		end
		-- and one that actually flies: out along the runway, round the bay, back
		local flyer = plane(rgb(96, 170, 150), K.actors)
		table.insert(R.planes, { m = flyer, t = 0 })
	end
	-- one plane flies the circuit for ever: hold, roll, climb, round the bay,
	-- descend, land, roll out, taxi back along the runway to the start
	local function stepPlane(pl, dt)
		local A = Roads.airport.runway
		local len = Roads.pieces("flight").length
		if not pl.s then
			pl.sa = Roads.nearest("flight", V(A.a.X, 0, A.a.Z))
			pl.sb = Roads.nearest("flight", V(A.b.X, 0, A.b.Z))
			pl.s, pl.v, pl.hold = pl.sa + 40, 0, 6
		end
		local past = (pl.s - pl.sa) % len         -- how far beyond the runway's start
		local runway = pl.sb - pl.sa
		local target
		if pl.hold > 0 then
			pl.hold -= dt
			target = 0
		elseif past < runway + 500 then target = 150  -- roll + climb out
		elseif past > len - 1100 then target = 86       -- final approach
		else target = 170 end
		if past > len - 1100 or past < 40 then
			-- landing: bleed the speed off along the runway, stop, hold, go again
			if past < 40 and pl.v < 30 then pl.hold, pl.v = 7, 0 end
		end
		pl.v += (target - pl.v) * math.min(1, dt * (target == 0 and 3 or 0.55))
		pl.s = (pl.s + pl.v * dt) % len
		local pos, dir = Roads.at("flight", pl.s)
		-- height: on the ground along the runway, up after rotation, down on final
		local y, pitch = 0, 0
		if past > runway * 0.7 and past < len - 1100 then
			local k = math.clamp((past - runway * 0.7) / 900, 0, 1)
			y = 170 * (k * k * (3 - 2 * k))
			pitch = (1 - k) * 0.24 * math.clamp((past - runway * 0.7) / 120, 0, 1)
		elseif past >= len - 1100 then
			local k = math.clamp((len - past) / 1100, 0, 1)
			y = 170 * (k * k * (3 - 2 * k))
			pitch = -0.07 * k
		end
		local at = CITY + V(pos.X, A.a.Y + 8.4 + y, pos.Z)
		pl.m:PivotTo(CFrame.lookAt(at, at + dir + V(0, pitch, 0)))
	end

	---------------------------------------------------------------------------
	-- TRAFFIC on the freeway and the bridge: cars that simply follow a path in
	-- their lane and come round again. No junction logic -- there are none.
	---------------------------------------------------------------------------
	local function buildPathCars()
		local kinds = { "convertible", "van", "sports", "taxi", "convertible", "icecream" }
		local function add(path, dirSign, lane, frac, i)
			local kind = kinds[i % #kinds + 1]
			local m, seat = K.buildCar(kind, K.CAR_COLORS[(i * 3) % 8 + 1], K.actors)
			local len = Roads.pieces(path).length
			local c = { m = m, seat = seat, path = path, dir = dirSign, lane = lane, s = frac * len, v = 52 + (i % 4) * 6 }
			c.driver = Models.buildSminski(K.actors, 1, deps.Config.Characters[i % math.min(#deps.Config.Characters, 10) + 1], false, nil)
			table.insert(R.cars, c)
		end
		for i = 1, 10 do add("freeway", i % 2 == 0 and 1 or -1, 5 + (i % 3 == 0 and 9 or 0), i / 10, i) end
		for i = 1, 4 do add("bridge", i % 2 == 0 and 1 or -1, 7, i / 4, i + 10) end
	end
	local function stepPathCar(c, dt, t)
		local len = Roads.pieces(c.path).length
		c.s += c.v * dt * c.dir
		-- off the end: come back in at the other
		if c.s > len - 30 then c.s = 40 elseif c.s < 30 then c.s = len - 40 end
		local pos, dir = Roads.at(c.path, c.s)
		local fwd = dir * c.dir
		local right = V(-fwd.Z, 0, fwd.X).Unit
		local at = CITY + pos + right * c.lane + V(0, 0.1, 0)
		local cf = CFrame.lookAt(at, at + fwd)
		c.m:PivotTo(cf)
		Models.poseSminski(c.driver, cf * CFrame.new(c.seat), "sit", t)
	end

	---------------------------------------------------------------------------
	-- BUILD / UPDATE / PROMPTS
	---------------------------------------------------------------------------
	function R.build()
		K.cur = K.root
		deck("freeway")
		deck("bridge")
		bridgeTowers()
		viaduct()
		for _, st in Roads.stations do station(st) end
		airport()
		buildPathCars()
		local len = Roads.pieces("rail").length
		for i, col in { rgb(96, 150, 206), rgb(236, 130, 96) } do
			local tr = { cars = buildTrain(col), cfs = {}, s = (i - 1) * len / 2, v = 0, dwell = 0 }
			table.insert(R.trains, tr)
		end
	end

	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end

	function R.update(dt, t, me)
		for _, tr in R.trains do stepTrain(tr, dt) end
		for _, pl in R.planes do stepPlane(pl, dt) end
		-- path traffic only needs to move when you could see it
		for _, c in R.cars do
			local pos = Roads.at(c.path, c.s)
			if (V(pos.X, 0, pos.Z) - V(me.X, 0, me.Z)).Magnitude < 900 then stepPathCar(c, dt, t) else c.s += c.v * dt * c.dir
				local len = Roads.pieces(c.path).length
				if c.s > len - 30 then c.s = 40 elseif c.s < 30 then c.s = len - 40 end
			end
		end
		local ride = R.riding
		if ride then
			local hrp = myChar()
			local cf = ride.train.cfs[ride.car]
			if hrp and cf then
				hrp.CFrame = cf * CFrame.new(ride.seat) * CFrame.new(0, 2.9, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
				S.poses[player] = "sit"
			end
		end
	end

	-- BOARD at a platform while a train is standing there; GET OFF at a stop
	function R.prompt(me)
		local ride = R.riding
		if ride then
			local at = ride.train.at
			if at then
				return { at.name, "this is your stop?", "GET OFF", "pin", function()
					local hrp = myChar()
					R.riding = nil
					if hrp then hrp.CFrame = at.cf * CFrame.new(10.6, 4, 6) end
					Audio.play("Pop", 1, 0.6)
				end, CITY + at.pos }
			end
			return { "THE ELEVATED", "next stop coming up...", nil, "pin", nil }
		end
		local flat = V(me.X, 0, me.Z)
		if me.Y > 28 then
			-- on a platform with a train standing at it: the train comes first
			for _, tr in R.trains do
				local st = tr.at
				if st and (flat - V(st.pos.X, 0, st.pos.Z)).Magnitude < 46 then
					return { "THE ELEVATED", st.name .. " · round the whole town", "BOARD", "pin", function()
						R.riding = { train = tr, car = 2, seat = V(2.6, 1.6, 0) }
						Audio.play("Chime", 1.1, 0.7)
						UI.toast("all aboard! get off at any station", UI.C.mintDark)
					end, CITY + st.pos }
				end
			end
		end
		-- the station lifts: up from the pavement, down from the footbridge
		for _, lf in R.lifts do
			if me.Y < 12 and (flat - V(lf.bottom.X, 0, lf.bottom.Z)).Magnitude < 7 then
				return { lf.station.name, "The Elevated · trains round the whole town", "UP", "pin", function()
					local hrp = myChar()
					if hrp then hrp.CFrame = CFrame.new(CITY + lf.arrive + V(0, 4, 0)) end
					Audio.play("Whoosh", 1.2, 0.6)
					if deps.City and deps.City.Sound then deps.City.Sound.door(lf.bottom) end
				end, CITY + lf.bottom }
			elseif me.Y > 28 and (flat - V(lf.top.X, 0, lf.top.Z)).Magnitude < 5 then
				return { lf.station.name, "back down to the street", "DOWN", "pin", function()
					local hrp = myChar()
					if hrp then hrp.CFrame = CFrame.new(CITY + lf.bottom + V(3.5, 4, 0)) end
					Audio.play("Whoosh", 0.9, 0.6)
				end, CITY + lf.top }
			end
		end
		return nil
	end

	function R.leave() R.riding = nil end
	return R
end
