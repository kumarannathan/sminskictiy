-- CityDress (client): everything that fills the space BETWEEN the buildings.
--   D.block(cx, cz, kind)   street furniture along every urban kerb, plus the
--                           corner features of the residential blocks
--   D.courtyard(cx, cz)     the water garden in the middle of a housing block:
--                           a creek, a pond, a footbridge, garden beds
--   D.signals()             traffic lights at every crossroads (City.lua runs
--                           the cycle and makes the traffic obey it)
-- The rule this module exists to enforce (.claude/rules/environment.md):
-- from the street there is never bare ground. Every stretch of kerb carries
-- something, and every leftover corner is a pond, a plaza, a playground or a
-- garden. Placement is deterministic per block -- nothing is random, so the
-- town is the same for everyone and every prop looks put there on purpose.
--   deps: K (CityKit), Build (CityBuild), Places

return function(deps)
	local K, Build, Places = deps.K, deps.Build, deps.Places
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local P, W, cyl, ball, blob, solid, walkable = K.P, K.W, K.cyl, K.ball, K.blob, K.solid, K.walkable
	local Cc = K.C
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL
	local PAD = K.PAD_Y
	local CITY = Places.CITY
	local ROADS = Places.CityRoads
	local RW = Places.ROAD_W
	local D = {}

	local FARM = { pasture = true, orchard = true, fields = true, barn = true, windmills = true, farmmarket = true, camp = true, pumpkins = true, lake = true, sunflowers = true, cows = true, forest = true }
	local HOMES = { houses = true, apartments = true }
	-- outward normal + facing, matching Places.cityLots
	local SIDES = {
		{ n = V(0, 0, 1), face = 0 }, { n = V(0, 0, -1), face = math.pi },
		{ n = V(1, 0, 0), face = math.pi / 2 }, { n = V(-1, 0, 0), face = -math.pi / 2 },
	}
	-- a small stable number per block, so neighbours differ but nothing is random
	local function hash(cx, cz, k)
		return (math.abs(cx) // 50 * 7 + math.abs(cz) // 50 * 13 + (cx > 0 and 3 or 0) + (cz > 0 and 5 or 0) + (k or 0) * 31) % 97
	end
	-- a frame on a block's edge: `along` the street, `depth` out from the centre
	local function edge(cx, cz, side, along, depth, inward)
		local t = V(side.n.Z, 0, -side.n.X)
		local pos = V(cx, 0, cz) + side.n * depth + t * along
		return K.frameOf(pos, inward and side.face + math.pi or side.face), pos
	end

	local function water(size, cf)
		local p = P(size, cf, rgb(98, 160, 186), SMOOTH, { noShadow = true, reflect = 0.12 })
		p.Transparency = 0.12
		return p
	end
	local function reeds(cf)
		for k = 0, 4 do
			local a = k * 1.3
			cyl(0.25, 3 + k % 2, cf * CFrame.new(math.cos(a) * 0.9, 1.6, math.sin(a) * 0.9), rgb(104, 148, 84))
			if k % 2 == 0 then cyl(0.5, 0.9, cf * CFrame.new(math.cos(a) * 0.9, 3.4, math.sin(a) * 0.9), rgb(126, 92, 66)) end
		end
	end
	-- an arched wooden footbridge along local Z, centred on cf
	local function footbridge(cf, len, wide)
		local n = math.max(5, math.floor(len / 2.4))
		for k = 0, n do
			local u = k / n
			local z = -len / 2 + u * len
			local y = 0.5 + math.sin(u * math.pi) * 2
			local pl = P(V(wide, 0.45, len / n + 0.3), cf * CFrame.new(0, y, z) * CFrame.Angles(-math.cos(u * math.pi) * 0.34, 0, 0), k % 2 == 0 and rgb(206, 164, 116) or rgb(186, 144, 100), WOODM)
			walkable(pl)
		end
		for _, sx in { -1, 1 } do
			for k = 0, 3 do
				local u = k / 3
				local y = 0.5 + math.sin(u * math.pi) * 2
				cyl(0.5, 2.6, cf * CFrame.new(sx * (wide / 2 - 0.3), y + 1.3, -len / 2 + u * len), rgb(150, 110, 80), WOODM)
			end
			P(V(0.4, 0.4, len * 0.74), cf * CFrame.new(sx * (wide / 2 - 0.3), 4.3, 0), rgb(150, 110, 80), WOODM)
		end
	end
	local function bed(cf, w, d)
		solid(P(V(w, 1.4, d), cf * CFrame.new(0, 0.7, 0), rgb(176, 136, 100), WOODM))
		P(V(w - 1, 0.3, d - 1), cf * CFrame.new(0, 1.5, 0), Cc.soil)
		local n = math.max(2, math.floor(w / 2.4))
		for i = 0, n - 1 do
			local x = -w / 2 + 1.4 + i * (w - 2.8) / math.max(1, n - 1)
			blob(V(1.8, 1.6, 1.8), cf * CFrame.new(x, 2.2, ((i % 2) - 0.5) * (d * 0.36)), i % 3 == 0 and rgb(232, 120, 100) or Cc.leaf3)
		end
	end

	---------------------------------------------------------------------------
	-- THE KERB: six stations along every side of every urban block
	---------------------------------------------------------------------------
	local NEWS = { rgb(226, 120, 96), rgb(96, 140, 196), rgb(240, 196, 90) }
	local function kerb(cx, cz, kind)
		local h = hash(cx, cz)
		for si, side in SIDES do
			local k = h + si * 5
			-- corner bin
			K.trashcan((edge(cx, cz, side, -106, 124)))
			-- hydrant or mailbox
			if k % 2 == 0 then K.hydrant((edge(cx, cz, side, -64, 127))) else K.mailbox((edge(cx, cz, side, -64, 124))) end
			-- newspaper boxes, or a bike rack
			if k % 3 == 0 then
				K.bikerack((edge(cx, cz, side, -21, 125)))
			else
				for j = 0, 1 do K.newsbox((edge(cx, cz, side, -24 + j * 2.6, 125)), NEWS[(k + j) % #NEWS + 1]) end
			end
			-- a bench with its back to the traffic, facing the shopfronts
			K.bench((edge(cx, cz, side, 21, 124.5, true)))
			-- parking meters at the kerb
			for j = 0, 1 do K.meter((edge(cx, cz, side, 58 + j * 12, 128.4))) end
			-- one bus shelter per block; planters everywhere else
			if si == h % 4 + 1 then
				local f, pos = edge(cx, cz, side, 104, 123.5, true)
				K.busStop(f, "BUS")
				table.insert(Build.busStops, pos)
			else
				K.planter((edge(cx, cz, side, 106, 124.5)), 4)
			end
		end
	end

	---------------------------------------------------------------------------
	-- RESIDENTIAL CORNERS: the 34x34 left over where two rows of houses meet
	---------------------------------------------------------------------------
	local CORNER = {}
	function CORNER.pond(c, cx, cz, x, z, k)
		cyl(30, 0.5, c * CFrame.new(0, 0.2, 0), Cc.stone)
		local wtr = cyl(27, 0.55, c * CFrame.new(0, 0.24, 0), rgb(98, 160, 186), SMOOTH)
		wtr.Transparency, wtr.Reflectance, wtr.CastShadow = 0.12, 0.12, false
		footbridge(c * CFrame.Angles(0, (k % 2) * math.pi / 2 + 0.3, 0), 31, 5)
		reeds(c * CFrame.new(-9, 0.3, 6))
		reeds(c * CFrame.new(8, 0.3, -8))
		for j = 0, 2 do blob(V(3, 0.3, 3), c * CFrame.new(-5 + j * 4, 0.6, 7 - j * 5), rgb(120, 176, 104)) end
		K.treeKind("birch", x - 13, z + 13, 0.8)
		K.treeKind("blossom", x + 13, z - 12, 0.75)
	end
	function CORNER.plaza(c, cx, cz, x, z, k)
		cyl(32, 0.3, c * CFrame.new(0, 0.12, 0), rgb(216, 206, 190), MATTE, { noShadow = true })
		cyl(18, 0.34, c * CFrame.new(0, 0.14, 0), rgb(198, 184, 166), MATTE, { noShadow = true })
		solid(cyl(8, 1.6, c * CFrame.new(0, 0.8, 0), Cc.stone))
		K.treeKind(K.TREE_KINDS[k % #K.TREE_KINDS + 1], x, z, 1, PAD + 1.2)
		for j = 0, 2 do
			local a = j / 3 * math.pi * 2 + 0.5
			K.bench(CFrame.lookAt(c.Position + V(math.cos(a), 0, math.sin(a)) * 11, c.Position))
		end
		K.bikerack(c * CFrame.new(-12, 0, -12) * CFrame.Angles(0, math.pi / 4, 0))
		K.trashcan(c * CFrame.new(12, 0, -11))
	end
	function CORNER.playground(c, cx, cz, x, z, k)
		P(V(32, 0.24, 32), c * CFrame.new(0, 0.1, 0), rgb(232, 206, 150), Enum.Material.Sand, { noShadow = true })
		-- swings
		local sw = c * CFrame.new(-7, 0, -6)
		for _, sx in { -5, 5 } do solid(cyl(0.6, 9, sw * CFrame.new(sx, 4.5, 0), rgb(226, 120, 96), METAL)) end
		P(V(10.6, 0.6, 0.6), sw * CFrame.new(0, 9, 0), rgb(226, 120, 96), METAL)
		for _, sx in { -2.2, 2.2 } do
			for _, o in { -0.8, 0.8 } do cyl(0.12, 6, sw * CFrame.new(sx + o, 6, 0), Cc.ink, METAL) end
			P(V(2.2, 0.3, 1.1), sw * CFrame.new(sx, 2.9, 0), rgb(96, 140, 196))
		end
		-- a slide
		local sl = c * CFrame.new(8, 0, 5)
		solid(P(V(5, 6, 5), sl * CFrame.new(0, 3, 4), rgb(240, 196, 90)))
		walkable(P(V(4, 0.4, 13), sl * CFrame.new(0, 3.2, -4.4) * CFrame.Angles(-0.46, 0, 0), rgb(96, 170, 150), SMOOTH))
		for j = 0, 3 do walkable(P(V(4, 0.5, 1.2), sl * CFrame.new(0, 0.8 + j * 1.4, 8 + (3 - j) * 1.1), rgb(226, 120, 96))) end
		-- a low fence so it reads as a place
		for _, s in { -1, 1 } do
			P(V(33, 1.6, 0.5), c * CFrame.new(0, 0.9, s * 16.5), Cc.cream)
			P(V(0.5, 1.6, 33), c * CFrame.new(s * 16.5, 0.9, 0), Cc.cream)
		end
		K.treeKind("round", x - 12, z + 12, 0.8)
	end
	function CORNER.garden(c, cx, cz, x, z, k)
		P(V(32, 0.2, 32), c * CFrame.new(0, 0.1, 0), rgb(214, 202, 182), MATTE, { noShadow = true })
		for _, o in { V(-8, 0, -8), V(8, 0, -8), V(-8, 0, 8), V(8, 0, 8) } do bed(c * CFrame.new(o), 12, 6) end
		-- a trellis arch over the middle path
		for _, sx in { -3, 3 } do cyl(0.5, 9, c * CFrame.new(sx, 4.5, 0), rgb(176, 136, 100), WOODM) end
		P(V(7, 0.6, 2.4), c * CFrame.new(0, 9, 0), rgb(176, 136, 100), WOODM)
		blob(V(8, 2.4, 3.4), c * CFrame.new(0, 9.6, 0), Cc.leaf)
		K.treeKind("autumn", x + 13, z + 13, 0.7)
		K.hydrant(c * CFrame.new(-14, 0, 14))
	end
	local CORNERS = { "pond", "plaza", "playground", "garden" }

	local function homeCorners(cx, cz)
		local h = hash(cx, cz, 2)
		local i = 0
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				i += 1
				-- the north-east corner belongs to the block's cafe (a venue lot)
				if not (sx == 1 and sz == 1) then
					local x, z = cx + sx * 96, cz + sz * 96
					local c = W(x, PAD, z)
					CORNER[CORNERS[(h + i) % #CORNERS + 1]](c, cx, cz, x, z, h + i)
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- THE COURTYARD: a creek through the middle of every housing block
	---------------------------------------------------------------------------
	function D.courtyard(cx, cz)
		local h = hash(cx, cz, 4)
		local c = W(cx, PAD, cz)
		P(V(112, 0.16, 112), c * CFrame.new(0, 0.06, 0), rgb(212, 200, 180), MATTE, { noShadow = true })
		-- the creek meanders west to east; every block bends differently
		local pts = { V(-52, 0, -8 + h % 7), V(-26, 0, 5 - h % 5), V(0, 0, -3 + h % 4), V(26, 0, 6 - h % 6), V(52, 0, -5 + h % 5) }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid, len = (a + b) / 2, (b - a).Magnitude
			local f = CFrame.lookAt(c.Position + mid, c.Position + b)
			P(V(11, 0.5, len + 3), f * CFrame.new(0, 0.2, 0), Cc.stone)
			water(V(7.4, 0.56, len + 3.4), f * CFrame.new(0, 0.22, 0))
		end
		-- it widens into a pond at the west end
		local pc = c * CFrame.new(pts[1])
		cyl(26, 0.5, pc * CFrame.new(0, 0.2, 0), Cc.stone)
		local pw = cyl(23, 0.56, pc * CFrame.new(0, 0.22, 0), rgb(98, 160, 186), SMOOTH)
		pw.Transparency, pw.Reflectance, pw.CastShadow = 0.12, 0.12, false
		reeds(pc * CFrame.new(-6, 0.3, 5))
		reeds(pc * CFrame.new(4, 0.3, -7))
		-- an arched bridge mid-creek, stepping stones further down
		footbridge(c * CFrame.new(pts[3]), 17, 5.5)
		for j = -1, 1 do walkable(cyl(2.6, 0.7, c * CFrame.new(pts[4]) * CFrame.new(0, 0.3, j * 3), rgb(176, 176, 170))) end
		-- garden beds where Places.cityGardens() says they are
		for _, o in { V(-34, 0, -34), V(34, 0, -34), V(-34, 0, 34), V(34, 0, 34) } do bed(c * CFrame.new(o), 13, 7) end
		-- shade, seats, light
		K.treeKind("birch", cx - 16, cz - 30, 1)
		K.treeKind("blossom", cx + 18, cz + 30, 1.05)
		K.treeKind("autumn", cx - 42, cz + 20, 0.9)
		K.treeKind("tall", cx + 44, cz - 22, 0.9)
		K.bench(c * CFrame.new(-10, 0, 16) * CFrame.Angles(0, math.pi, 0))
		K.bench(c * CFrame.new(12, 0, -17))
		K.lamp(cx - 2, cz + 22)
		K.lamp(cx + 4, cz - 24)
	end

	---------------------------------------------------------------------------
	-- ONE CALL PER BLOCK (CityBuild runs it after the block has built)
	---------------------------------------------------------------------------
	-- GARDEN FENCES: a low picket line along the front of every row of
	-- houses, broken for each garden path and driveway. It turns four loose
	-- houses into one street frontage, and the corners stay open as little
	-- public squares.
	local FENCE_RUNS = { { -64, -53 }, { -43, -9.5 }, { -1.5, 18 }, { 30, 43 }, { 53, 76 } }
	local function frontage(cx, cz)
		for si, side in SIDES do
			local t = V(side.n.Z, 0, -side.n.X)
			for ri, run in FENCE_RUNS do
				-- the cafe owns the north side's last run
				if not (si == 1 and ri == #FENCE_RUNS) then
					local a = V(cx, 0, cz) + side.n * 113 + t * run[1]
					local b = V(cx, 0, cz) + side.n * 113 + t * run[2]
					K.fence(a, b, Cc.cream)
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- FINGERPOSTS: what is down each of these four roads?
	-- The city is legible from the air and baffling at street level, because
	-- every junction looks like every other junction. A blade per direction
	-- naming the nearest real landmark (and how far) turns "which way was the
	-- mall?" into a thing you can answer without opening the map.
	--
	-- The text is drawn with LightInfluence 0 on purpose -- K.textOn defaults
	-- to 0.8, which means the letters dim with the scene, and a direction sign
	-- you cannot read at 2am is not a direction sign.
	---------------------------------------------------------------------------
	local DIRS = { { V(0, 0, 1), "N" }, { V(0, 0, -1), "S" }, { V(1, 0, 0), "E" }, { V(-1, 0, 0), "W" } }
	local BLADE = { rgb(96, 140, 176), rgb(120, 156, 120), rgb(176, 140, 110), rgb(140, 124, 168) }
	local function fingerpost(cx, cz)
		-- stand it on the kerb corner, clear of the crossing and the lamp
		local px, pz = cx - 118, cz - 118
		local base = W(px, PAD, pz)
		solid(cyl(1.3, 22, base * CFrame.new(0, 11, 0), Cc.lampPost, METAL))
		cyl(2.2, 0.8, base * CFrame.new(0, 0.4, 0), Cc.lampPost, METAL)
		ball(2, base * CFrame.new(0, 22.4, 0), Cc.gold, METAL)
		local here = V(px, 0, pz)
		local n = 0
		for di, d in DIRS do
			local dir = d[1]
			-- the nearest landmark that actually lies down this road
			local best, bd
			for _, m in Places.CityLandmarks do
				local rel = m.pos - here
				local along = rel:Dot(dir)
				local side = math.abs(rel.X * dir.Z - rel.Z * dir.X)
				if along > 90 and side < along * 0.9 then
					local dist = rel.Magnitude
					if not bd or dist < bd then best, bd = m, dist end
				end
			end
			if best then
				n += 1
				local y = 19 - (n - 1) * 4.6
				local f = CFrame.lookAt(CITY + V(px, PAD + y, pz), CITY + V(px + dir.X, PAD + y, pz + dir.Z))
				-- CFrame.lookAt puts the look direction on -Z, so the blade runs
				-- along -Z and its READABLE faces are +-X. (Built along X first,
				-- which put the lettering on the 0.5-stud edge and the arrow
				-- flat on the pavement.)
				local w = 15
				local blade = P(V(0.6, 3.6, w), f * CFrame.new(0, 0, -(w / 2 + 1.3)), BLADE[di], MATTE)
				P(V(0.6, 3.4, 3.4), f * CFrame.new(0, 0, -(w + 1.3)) * CFrame.Angles(math.pi / 4, 0, 0), BLADE[di], MATTE)
				local txt = string.upper(string.gsub(best.name, "^the ", "")) .. "  " .. math.floor(bd / 10) * 10
				K.textOn(blade, Enum.NormalId.Right, txt, Cc.cream, Vector2.new(620, 100), 0)
				K.textOn(blade, Enum.NormalId.Left, txt, Cc.cream, Vector2.new(620, 100), 0)
			end
		end
	end

	function D.block(cx, cz, kind)
		if FARM[kind] then return end
		kerb(cx, cz, kind)
		fingerpost(cx, cz)
		if HOMES[kind] then homeCorners(cx, cz) end
		if kind == "houses" then frontage(cx, cz) end
	end

	---------------------------------------------------------------------------
	-- TRAFFIC LIGHTS: two masts per crossroads (diagonal corners), each with a
	-- head for both roads. City.lua owns the cycle; this only builds them and
	-- hands back the bulbs.
	---------------------------------------------------------------------------
	local OFF = rgb(46, 50, 50)
	D.LIGHT = { red = rgb(255, 80, 70), yellow = rgb(255, 204, 80), green = rgb(90, 230, 130), off = OFF }
	local function head(cf)
		P(V(1.8, 5, 1.6), cf, Cc.ink, METAL)
		local set = {}
		for i, name in { "red", "yellow", "green" } do
			local b = ball(1.2, cf * CFrame.new(0, 1.6 - (i - 1) * 1.6, -0.7), OFF, SMOOTH)
			b.CastShadow = false
			set[name] = b
		end
		return set
	end
	function D.signals()
		local out = {}
		for _, rx in ROADS do
			for _, rz in ROADS do
				local sig = { x = rx, z = rz, ns = {}, ew = {} }
				for _, s in { -1, 1 } do
					local px, pz = rx + s * (RW / 2 + 3), rz + s * (RW / 2 + 3)
					local base = W(px, PAD, pz)
					solid(cyl(0.7, 17, base * CFrame.new(0, 8.5, 0), Cc.lampPost, METAL))
					-- this mast's arm reaches over the road running north-south...
					P(V(12, 0.5, 0.5), base * CFrame.new(-s * 6, 16.4, 0), Cc.lampPost, METAL)
					table.insert(sig.ns, head(base * CFrame.new(-s * 11, 14.6, 0) * CFrame.Angles(0, s > 0 and math.pi or 0, 0)))
					-- ...and a second arm over the road running east-west
					P(V(0.5, 0.5, 12), base * CFrame.new(0, 16.4, -s * 6), Cc.lampPost, METAL)
					table.insert(sig.ew, head(base * CFrame.new(0, 14.6, -s * 11) * CFrame.Angles(0, s > 0 and math.pi / 2 or -math.pi / 2, 0)))
				end
				table.insert(out, sig)
			end
		end
		return out
	end

	Build.busStops = Build.busStops or {}
	return D
end
