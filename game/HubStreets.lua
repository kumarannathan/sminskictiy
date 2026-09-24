-- HubStreets (client): the "town square" of the lobby table, so the middle
-- reads as a tiny town instead of a pile of objects:
--   * cream paper-tile sidewalks linking every building to a round plaza
--   * proper little street lamps (few real lights, the rest just glow)
--   * a painted blue stream spilling from a tipped paper cup, crossed by
--     two popsicle-stick bridges
--   * a wayfinding signpost in the plaza pointing to every place
-- Everything is matte, board-built and sits flat on the table (y = 0).

return function(K)
	local part, solid, light = K.part, K.solid, K.light
	local UI, Places, HUB = K.UI, K.Places, K.HUB
	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local MATTE = Enum.Material.Plaster
	local WOODM = Enum.Material.Wood
	local NEON = Enum.Material.Neon
	local PAVE = rgb(244, 234, 214)
	local PAVE_JOINT = rgb(222, 208, 184)
	local CURB = rgb(200, 184, 160)
	local STICK = rgb(232, 204, 156)
	local STICK_DARK = rgb(206, 174, 124)
	local WATER = rgb(142, 200, 236)
	local WATER_LIGHT = rgb(190, 228, 248)
	local LAMP_POST = rgb(62, 84, 76)
	local CREAM = rgb(250, 244, 232)

	local Streets = {}
	local folder

	local function P(size, cf, color, mat, opts)
		opts = opts or {}
		if opts.noShadow == nil then opts.noShadow = true end
		return part(folder, size, cf, color, mat or MATTE, opts)
	end
	local function flat(x, z, y) return CFrame.new(HUB + V(x, y or 0, z)) end
	local function disc(dia, cf, color, h)
		return P(V(h or 0.3, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), color, MATTE, { shape = Enum.PartType.Cylinder })
	end

	---------------------------------------------------------------------------
	-- SIDEWALKS
	---------------------------------------------------------------------------
	local Y = 0.16
	local function walk(a, b, w)
		w = w or 9
		local d = V(b.X - a.X, 0, b.Z - a.Z)
		local len = d.Magnitude
		if len < 0.5 then return end
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(HUB + V(mid.X, Y, mid.Z), HUB + V(b.X, Y, b.Z))
		P(V(w, 0.3, len), cf, PAVE)
		-- tile joints across the walk every ~7 studs
		local n = math.floor(len / 7)
		for k = 1, n - 1 do
			P(V(w - 0.4, 0.32, 0.22), cf * CFrame.new(0, 0, -len / 2 + k * len / n), PAVE_JOINT)
		end
		-- low curbs along both edges
		for _, sx in { -1, 1 } do
			P(V(0.6, 0.55, len), cf * CFrame.new(sx * (w / 2 + 0.3), 0.12, 0), CURB)
		end
	end
	local function joint(p, w)
		disc((w or 9) + 1.2, flat(p.X, p.Z, Y), PAVE, 0.3)
	end
	local function route(points, w)
		for i = 1, #points - 1 do walk(points[i], points[i + 1], w) end
		for i = 2, #points - 1 do joint(points[i], w) end
	end

	---------------------------------------------------------------------------
	-- STREET LAMP: plinth, slim post, curled arm, a lantern with a warm globe
	---------------------------------------------------------------------------
	local lampCount = 0
	local function lamp(x, z, facing)
		lampCount += 1
		local base = CFrame.new(HUB + V(x, 0, z)) * CFrame.Angles(0, facing or 0, 0)
		disc(2.8, base * CFrame.new(0, 0.5, 0), LAMP_POST, 1)
		disc(2, base * CFrame.new(0, 1.25, 0), LAMP_POST, 0.5)
		P(V(13, 0.7, 0.7), base * CFrame.new(0, 7.5, 0) * CFrame.Angles(0, 0, math.pi / 2), LAMP_POST, Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
		P(V(0.5, 0.5, 3), base * CFrame.new(0, 14.2, -1.3), LAMP_POST, Enum.Material.Metal)
		P(V(0.5, 1.2, 0.5), base * CFrame.new(0, 13.6, -2.7), LAMP_POST, Enum.Material.Metal)
		-- lantern: cap, glowing globe, collar
		P(V(2.2, 0.5, 2.2), base * CFrame.new(0, 13.1, -2.7), LAMP_POST, Enum.Material.Metal)
		-- frosted shade (matte) around a small glowing bulb, so it doesn't bloom into a blob
		local globe = P(V(1.7, 1.9, 1.7), base * CFrame.new(0, 11.9, -2.7), rgb(255, 238, 206), MATTE, { mesh = Enum.MeshType.Sphere })
		globe.Transparency = 0.25
		P(V(0.6, 0.6, 0.6), base * CFrame.new(0, 11.9, -2.7), rgb(255, 214, 150), NEON, { shape = Enum.PartType.Ball })
		P(V(1.2, 0.35, 1.2), base * CFrame.new(0, 10.9, -2.7), LAMP_POST, Enum.Material.Metal)
		-- only every other lamp is a real light (keeps the scene cheap)
		if lampCount % 2 == 1 then light(globe, 24, 0.55, rgb(255, 214, 160)) end
		-- a little lamp-foot pool so it reads at night
		local pool = disc(7, base * CFrame.new(0, Y + 0.05, -2.7), rgb(255, 236, 200), 0.1)
		pool.Transparency = 0.8
	end

	---------------------------------------------------------------------------
	-- POPSICLE-STICK THINGS
	---------------------------------------------------------------------------
	-- one stick: a flat plank with rounded ends, long along local Z
	local function stick(cf, len, wid, color, solidOk)
		wid = wid or 1.6
		local body = P(V(wid, 0.35, len - wid), cf, color or STICK, WOODM, { noShadow = false })
		for _, sz in { -1, 1 } do
			P(V(0.35, wid, wid), cf * CFrame.new(0, 0, sz * (len - wid) / 2) * CFrame.Angles(0, 0, math.pi / 2), color or STICK, WOODM, { shape = Enum.PartType.Cylinder, noShadow = false })
		end
		if solidOk then solid(body) end
		return body
	end

	-- arched bridge over the stream. cf: centre on the ground, local -Z = walking direction
	local function bridge(cf, span, width)
		span = span or 18
		width = width or 8
		local n = 11
		local rise = 1.8
		for i = 0, n - 1 do
			local k = (i + 0.5) / n
			local z = -span / 2 + k * span
			local y = math.sin(k * math.pi) * rise + 0.25
			local tilt = math.cos(k * math.pi) * math.atan(rise * math.pi / span)
			-- sticks lie across the walkway (their length along local X)
			stick(cf * CFrame.new(0, y, z) * CFrame.Angles(tilt, math.pi / 2, 0), width + 1.2, span / n + 0.15, (i % 2 == 0) and STICK or STICK_DARK, true)
		end
		-- railings: stick posts + a long stick handrail each side
		for _, sx in { -1, 1 } do
			for _, pz in { -span / 2 + 1, 0, span / 2 - 1 } do
				local k = (pz + span / 2) / span
				local y = math.sin(k * math.pi) * rise
				stick(cf * CFrame.new(sx * (width / 2 + 0.5), y + 2.2, pz) * CFrame.Angles(math.pi / 2, 0, 0), 4.4, 1.1, STICK_DARK)
			end
			for seg = 0, 1 do
				local z0, z1 = -span / 2 + 1 + seg * (span / 2 - 1), (seg == 0) and 0 or span / 2 - 1
				local y0 = math.sin(((z0 + span / 2) / span) * math.pi) * rise + 4
				local y1 = math.sin(((z1 + span / 2) / span) * math.pi) * rise + 4
				local a = cf * CFrame.new(sx * (width / 2 + 0.5), y0, z0)
				local b = cf * CFrame.new(sx * (width / 2 + 0.5), y1, z1)
				local mid = a.Position:Lerp(b.Position, 0.5)
				stick(CFrame.lookAt(mid, b.Position) * CFrame.Angles(0, 0, math.pi / 2), (b.Position - a.Position).Magnitude + 1.2, 1.1, STICK)
			end
		end
	end

	-- a popsicle-stick bench (seat slats + back + legs), facing local -Z
	local function bench(cf)
		for k = 0, 2 do stick(cf * CFrame.new(0, 2.2, -0.8 + k * 1.2) * CFrame.Angles(0, math.pi / 2, 0), 8, 1.1, k % 2 == 0 and STICK or STICK_DARK) end
		for k = 0, 1 do stick(cf * CFrame.new(0, 3.8 + k * 1.3, 1.5) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.15), 8, 1.1, STICK) end
		for _, sx in { -3.2, 3.2 } do
			stick(cf * CFrame.new(sx, 1.1, -0.6) * CFrame.Angles(math.pi / 2, 0, 0), 2.4, 1, STICK_DARK)
			stick(cf * CFrame.new(sx, 2.3, 1.4) * CFrame.Angles(math.pi / 2 - 0.15, 0, 0), 5, 1, STICK_DARK)
		end
	end

	---------------------------------------------------------------------------
	-- THE STREAM: spilling from a tipped paper cup at the table edge
	---------------------------------------------------------------------------
	local STREAM = { V(-146, 0, -32), V(-122, 0, -26), V(-100, 0, -12), V(-92, 0, 8), V(-92, 0, 30), V(-98, 0, 42) }
	local function stream()
		local w = 8
		for i = 1, #STREAM - 1 do
			local a, b = STREAM[i], STREAM[i + 1]
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			local cf = CFrame.lookAt(HUB + V(mid.X, 0.1, mid.Z), HUB + V(b.X, 0.1, b.Z))
			P(V(w, 0.2, len), cf, WATER)
			P(V(w * 0.35, 0.22, len * 0.8), cf * CFrame.new(w * 0.12, 0, 0), WATER_LIGHT)
		end
		for i = 2, #STREAM do disc(w, flat(STREAM[i].X, STREAM[i].Z, 0.1), WATER, 0.2) end
		-- a round puddle at the end
		disc(13, flat(-98, 44, 0.1), WATER, 0.2)
		disc(7, flat(-96.5, 43, 0.1), WATER_LIGHT, 0.22)
		-- the tipped paper cup it came from
		local cup = CFrame.new(HUB + V(-146, 4.6, -36)) * CFrame.Angles(0, 0.3, math.pi / 2 - 0.1)
		P(V(12, 9, 9), cup, CREAM, MATTE, { shape = Enum.PartType.Cylinder, noShadow = false })
		P(V(1.2, 10, 10), cup * CFrame.new(-6, 0, 0), rgb(236, 120, 110), MATTE, { shape = Enum.PartType.Cylinder, noShadow = false })
	end

	---------------------------------------------------------------------------
	-- WAYFINDING SIGNPOST in the plaza: one arrow board per place
	---------------------------------------------------------------------------
	local function signpost(x, z)
		local base = CFrame.new(HUB + V(x, 0, z))
		disc(3, base * CFrame.new(0, 0.5, 0), rgb(120, 86, 60), 1)
		P(V(1.2, 22, 1.2), base * CFrame.new(0, 11, 0), rgb(150, 108, 74), WOODM, { noShadow = false })
		P(V(1.8, 1.2, 1.8), base * CFrame.new(0, 22.5, 0), rgb(120, 86, 60), WOODM)
		local dests = {
			{ "RUN", "dollhouse", rgb(150, 130, 230) },
			{ "CAFE", "friends", rgb(255, 170, 190) },
			{ "DOG PARK", "dogpark", rgb(120, 200, 110) },
			{ "SHOP", "store", rgb(245, 196, 80) },
			{ "GARDEN", "garden", rgb(110, 184, 96) },
			{ "RANKED", "arcade", rgb(190, 150, 250) },
			{ "LEADERBOARD", nil, rgb(245, 196, 80), V(-128, 0, -12) },
		}
		for i, dd in dests do
			local e = dd[2] and Places.entrance(dd[2])
			local target = dd[4] or (e and (e.door or e.pos)) or V(0, 0, 0)
			local dir = V(target.X - x, 0, target.Z - z)
			if dir.Magnitude < 1 then continue end
			local y = 20.5 - (i - 1) * 2.5
			-- the board sticks out from the post toward its destination (local +X)
			local frame = CFrame.fromMatrix(HUB + V(x, y, z), dir.Unit, V(0, 1, 0))
			local len = math.max(7, #dd[1] * 0.95 + 3)
			local board = P(V(len, 2, 0.5), frame * CFrame.new(len / 2 + 0.6, 0, 0), dd[3], MATTE, { noShadow = false })
			P(V(1.5, 1.5, 0.5), frame * CFrame.new(len + 0.6, 0, 0) * CFrame.Angles(0, 0, math.pi / 4), dd[3], MATTE)
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local sg = Instance.new("SurfaceGui")
				sg.Face = face
				sg.CanvasSize = Vector2.new(len * 40, 80)
				sg.LightInfluence = 0.4
				UI.text(sg, dd[1], { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM, stroke = 0 })
				local pad = Instance.new("UIPadding")
				pad.PaddingTop, pad.PaddingBottom = UDim.new(0.16, 0), UDim.new(0.16, 0)
				pad.Parent = sg:FindFirstChildWhichIsA("TextLabel")
				sg.Parent = board
			end
		end
	end

	---------------------------------------------------------------------------
	-- BUILD
	---------------------------------------------------------------------------
	function Streets.build(parent)
		folder = Instance.new("Folder")
		folder.Name = "Streets"
		folder.Parent = parent

		-- the plaza: a paved ring around the statue with a border and pavers
		disc(52, flat(0, -4, Y - 0.02), CURB, 0.28)
		disc(50, flat(0, -4, Y), PAVE, 0.3)
		for r = 1, 2 do
			local ring = disc(50 - r * 14, flat(0, -4, Y + 0.01), PAVE_JOINT, 0.3)
			disc(50 - r * 14 - 0.5, flat(0, -4, Y + 0.02), PAVE, 0.3)
			ring.Name = "PlazaRing"
		end
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			P(V(0.25, 0.32, 11), CFrame.new(HUB + V(math.cos(a) * 19.5, Y + 0.01, -4 + math.sin(a) * 19.5)) * CFrame.Angles(0, -a + math.pi / 2, 0), PAVE_JOINT)
		end

		-- the avenue along the games row, with short walks to each door
		route({ V(-140, 0, 33), V(-60, 0, 33), V(20, 0, 33), V(122, 0, 33) }, 10)
		for _, id in { "arcade", "house", "dollhouse", "dogrun", "friends" } do
			local e = Places.entrance(id)
			if e then walk(V(e.door.X, 0, 37.5), V(e.door.X, 0, e.door.Z + 1), 8) end
		end
		walk(V(104, 0, 37.5), V(104, 0, 39.5), 12)
		-- plaza spokes: north to the avenue, south to the shop, east + west
		walk(V(0, 0, 20), V(0, 0, 29), 9)
		route({ V(16, 0, -22), V(28, 0, -32), V(40, 0, -41) }, 9)
		route({ V(25, 0, -2), V(60, 0, -2), V(111, 0, -2) }, 9)
		route({ V(111, 0, -48), V(111, 0, -2), V(111, 0, 18), V(115, 0, 18) }, 8)
		walk(V(111, 0, -30), V(116, 0, -30), 8)
		walk(V(102, 0, -48), V(111, 0, -48), 8)
		route({ V(-25, 0, -4), V(-70, 0, -6), V(-112, 0, -8) }, 9)
		route({ V(-3, 0, -28), V(Places.HubGateX, 0, -50), V(Places.HubGateX, 0, -82) }, 10)

		-- popsicle-stick bridges where the walks cross the stream
		stream()
		bridge(CFrame.lookAt(HUB + V(-98, 0, -9.5), HUB + V(-112, 0, -10)), 18, 8)
		bridge(CFrame.lookAt(HUB + V(-92, 0, 33), HUB + V(-110, 0, 33)), 20, 9)

		-- street lamps along the walks (post on the verge, lantern over the walk)
		for _, x in { -128, -58, -18, 24, 66 } do lamp(x, 26, math.pi) end
		for _, x in { 45, 92 } do lamp(x, 5.5, 0) end
		lamp(-50, -14, math.pi)
		lamp(119, -40, math.pi / 2)
		-- plaza lamps, set between the spokes (not on them)
		for _, deg in { 45, 135, 225, -85 } do
			local a = math.rad(deg)
			lamp(math.cos(a) * 29, -4 + math.sin(a) * 29, math.pi / 2 - a)
		end

		-- two popsicle benches facing the statue
		for _, a in { math.pi * 0.62, math.pi * 1.38 } do
			local pos = HUB + V(math.cos(a) * 21, 0, -4 + math.sin(a) * 21)
			bench(CFrame.lookAt(pos, HUB + V(0, 0, -4)))
		end

		signpost(11, 12)
	end

	---------------------------------------------------------------------------
	-- THE CITY GATE: a stone archway cut into the bedroom wall, a grand
	-- popsicle-stick bridge across the gap, and a lantern-lit tunnel beyond
	---------------------------------------------------------------------------
	local STONE = rgb(226, 214, 196)
	local STONE_DARK = rgb(196, 182, 162)
	function Streets.buildGate(parent, info)
		local keep = folder
		folder = Instance.new("Folder")
		folder.Name = "CityGate"
		folder.Parent = parent
		local gx = Places.HubGateX
		local wz = info.wallZ -- the wall's room-side face
		local fz = wz + 0.7 -- just in front of the wall
		local function W(x, y, z) return CFrame.new(HUB + V(x, y, z)) end
		local cy, r0, r1 = 22, 13, 17.5 -- arch centre height, inner + outer radius

		-- the dark arched opening (the tunnel behind reads through it)
		-- the upper half of the arch is painted dark onto the wall so the
		-- opening reads as a round-topped doorway
		for k = 0, 9 do
			local y0 = k * r0 / 10
			local hw = math.sqrt(r0 * r0 - (y0 + r0 / 20) ^ 2)
			P(V(hw * 2, r0 / 10 + 0.05, 0.3), W(gx, cy + y0 + r0 / 20, wz + 0.2), rgb(40, 34, 58))
		end
		-- voussoir stones around the arch + a keystone
		local n = 11
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi
			local rm = (r0 + r1) / 2
			local c = W(gx + math.cos(a) * rm, cy + math.sin(a) * rm, fz) * CFrame.Angles(0, 0, a - math.pi / 2)
			P(V(r1 - r0 + 0.6, (r0 * math.pi / n) * 1.25 - 0.35, 1.6), c * CFrame.Angles(0, 0, math.pi / 2), i % 2 == 0 and STONE or STONE_DARK, MATTE, { noShadow = false })
		end
		local key = P(V(4, 5, 2.2), W(gx, cy + r1 - 0.6, fz + 0.3), rgb(246, 236, 214), MATTE, { noShadow = false })
		-- a little Sminski face on the keystone
		for _, sx in { -1, 1 } do P(V(0.5, 0.7, 0.2), key.CFrame * CFrame.new(sx * 0.7, 0.4, 1.15), rgb(70, 90, 60)) end
		P(V(0.9, 0.25, 0.2), key.CFrame * CFrame.new(0, -0.5, 1.15), rgb(70, 90, 60))
		-- stone pillars down both sides of the opening
		for _, sx in { -1, 1 } do
			for k = 0, 4 do
				P(V(r1 - r0 + (k % 2) * 0.6, 4.2, 1.6), W(gx + sx * (r0 + r1) / 2, 2.1 + k * 4.4, fz), k % 2 == 0 and STONE_DARK or STONE, MATTE, { noShadow = false })
			end
			P(V(r1 - r0 + 2, 1.4, 2.4), W(gx + sx * (r0 + r1) / 2, cy + 0.4, fz + 0.2), rgb(246, 236, 214), MATTE)
			-- climbing vines + a flower box on each pillar
			for k = 0, 8 do
				local b = P(V(2.2, 1.8, 1.2), W(gx + sx * (r1 + 0.4) + math.sin(k * 1.9) * 0.8, 4 + k * 3.4, fz + 0.6), k % 2 == 0 and rgb(104, 170, 96) or rgb(128, 190, 110), MATTE, { mesh = Enum.MeshType.Sphere })
				b.Name = "Vine"
			end
			local boxc = W(gx + sx * (r1 + 4.5), 12, fz + 2)
			P(V(6, 2.4, 3), boxc, rgb(176, 120, 84), WOODM)
			for q = 0, 3 do
				P(V(1.4, 1.4, 1.4), boxc * CFrame.new(-2.2 + q * 1.5, 1.9, 0), ({ rgb(255, 150, 190), rgb(255, 226, 110), rgb(190, 160, 250), rgb(255, 255, 255) })[q + 1], MATTE, { shape = Enum.PartType.Ball })
			end
		end
		-- the name board, hung from the wall on two chains
		local boardCF = W(gx, cy + r1 + 7, fz + 1)
		local board = P(V(30, 6.4, 0.8), boardCF, rgb(96, 132, 88), MATTE, { noShadow = false })
		P(V(31.4, 7.8, 0.5), boardCF * CFrame.new(0, 0, -0.5), rgb(120, 86, 60), WOODM)
		for _, sx in { -12, 12 } do P(V(0.4, 4, 0.4), boardCF * CFrame.new(sx, 5, 0), rgb(150, 150, 160), Enum.Material.Metal) end
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back -- faces into the room (+Z)
		sg.CanvasSize = Vector2.new(600, 128)
		sg.LightInfluence = 0.3
		UI.text(sg, "SMINSKI CITY", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM, stroke = 0 })
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
		pad.Parent = sg:FindFirstChildWhichIsA("TextLabel")
		sg.Parent = board
		-- the grand bridge from the table edge into the arch
		local z0, z1 = info.tableZ + 4, wz - 4
		bridge(CFrame.lookAt(HUB + V(gx, 0, (z0 + z1) / 2), HUB + V(gx, 0, z1)), z0 - z1, 22)
		-- THE RIVER under the bridge: a toy-train-set river in a long wooden
		-- tray on a shelf along the wall, with pebbles, reeds, lilies and boats
		local rz = (info.tableZ + wz) / 2
		local RL = 300
		P(V(RL, 1.4, 24), W(0, -9, rz), rgb(176, 130, 92), WOODM, { noShadow = false })
		for _, sz in { -1, 1 } do P(V(RL, 4, 1.4), W(0, -7, rz + sz * 11.4), rgb(150, 108, 76), WOODM) end
		local water = P(V(RL - 2, 0.6, 21), W(0, -6.4, rz), WATER, Enum.Material.SmoothPlastic)
		water.Reflectance = 0.15
		for k = 0, 24 do
			local x = -RL / 2 + 8 + k * 12
			P(V(5 + (k % 3), 0.62, 1 + (k % 2) * 0.6), W(x, -6.38, rz + math.sin(k * 1.7) * 6), WATER_LIGHT, Enum.Material.SmoothPlastic)
			if math.abs(x - gx) > 16 then
				local side = k % 2 == 0 and -1 or 1
				P(V(2.4, 1.6, 2), W(x + 3, -5.8, rz + side * 9.4), k % 3 == 0 and rgb(200, 196, 188) or rgb(170, 168, 164), MATTE, { mesh = Enum.MeshType.Sphere })
				for q = 0, 2 do P(V(0.3, 5 + q, 0.3), W(x + q * 0.7, -4 + q * 0.5, rz + side * 9.8) * CFrame.Angles(0, 0, (q - 1) * 0.12), rgb(110, 170, 96)) end
				if k % 4 == 1 then
					disc(3, W(x - 4, -6.05, rz - side * 4), rgb(120, 190, 110), 0.12)
					P(V(1, 0.8, 1), W(x - 4, -5.7, rz - side * 4), rgb(255, 170, 200), MATTE, { mesh = Enum.MeshType.Sphere })
				end
			end
		end
		-- paper boats bobbing downstream
		Streets.boats = {}
		for k = 0, 3 do
			local m = Instance.new("Model")
			part(m, V(2.2, 0.9, 4.4), CFrame.new(0, 0, 0), CREAM, MATTE)
			part(m, V(0.2, 2.4, 2.6), CFrame.new(0, 1.4, 0), CREAM, MATTE, { class = "WedgePart" })
			part(m, V(0.2, 2.4, 2.6), CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.pi, 0), ({ rgb(255, 170, 190), rgb(150, 206, 250), rgb(255, 222, 130), rgb(170, 226, 160) })[k + 1], MATTE, { class = "WedgePart" })
			m.WorldPivot = CFrame.new()
			m.Parent = folder
			table.insert(Streets.boats, { m = m, x = -120 + k * 70, lane = (k % 2 == 0) and -4 or 4, rz = rz, half = RL / 2 - 6 })
		end
		-- the MINI GAMES arch at the table end (facing the bridge)
		local mg = W(gx, 0, z0 + 1.5)
		for _, sx in { -1, 1 } do
			stick(mg * CFrame.new(sx * 13, 9, 0) * CFrame.Angles(math.pi / 2, 0, 0), 18, 2, STICK_DARK, true)
			P(V(3, 3, 3), mg * CFrame.new(sx * 13, 19, 0), ({ rgb(255, 150, 190), rgb(150, 206, 250) })[sx < 0 and 1 or 2], MATTE, { shape = Enum.PartType.Ball })
		end
		local mboard = P(V(27, 6.4, 0.8), mg * CFrame.new(0, 17, 0), rgb(250, 170, 90), MATTE, { noShadow = false })
		P(V(28.4, 7.8, 0.5), mg * CFrame.new(0, 17, 0.5), rgb(120, 86, 60), WOODM)
		local msg = Instance.new("SurfaceGui")
		msg.Face = Enum.NormalId.Front -- faces the bridge (-Z)
		msg.CanvasSize = Vector2.new(600, 140)
		msg.LightInfluence = 0.3
		UI.text(msg, "MINI GAMES", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM, stroke = 0 })
		local mpad = Instance.new("UIPadding")
		mpad.PaddingTop, mpad.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
		mpad.Parent = msg:FindFirstChildWhichIsA("TextLabel")
		msg.Parent = mboard
		local msub = P(V(20, 2.6, 0.5), mg * CFrame.new(0, 11.6, 0), CREAM, MATTE)
		local ssg = Instance.new("SurfaceGui")
		ssg.Face = Enum.NormalId.Front
		ssg.CanvasSize = Vector2.new(600, 80)
		UI.text(ssg, "runs  ·  dog park  ·  shops", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = rgb(120, 86, 60), stroke = 0 })
		ssg.Parent = msub
		-- painted arrows on the deck pointing each way
		for _, e in { { 1, rgb(250, 170, 90) }, { -1, rgb(96, 132, 88) } } do
			local zc = (z0 + z1) / 2 + e[1] * 7
			for _, sx in { -1, 1 } do
				P(V(0.8, 0.1, 4), W(gx + sx * 1.2, 2.2, zc) * CFrame.Angles(0, -sx * e[1] * 0.7, 0), e[2], NEON)
			end
		end
		-- bunting between two tall posts at the table end, lamps either side
		for _, sx in { -1, 1 } do
			stick(W(gx + sx * 11.5, 8, z1 + 2) * CFrame.Angles(math.pi / 2, 0, 0), 16, 1.3, STICK_DARK)
		end
		for k = 0, 8 do
			local t = k / 8
			local x = gx - 11.5 + t * 23
			local y = 15.5 - math.sin(t * math.pi) * 2.4
			local flag = P(V(1.6, 1.8, 0.2), W(x, y - 1, z1 + 2) * CFrame.Angles(0, 0, math.pi / 4), ({ rgb(255, 150, 190), rgb(255, 226, 110), rgb(150, 210, 255), rgb(180, 230, 160) })[k % 4 + 1], MATTE)
			flag.Name = "Bunting"
		end
		lamp(gx - 17, info.tableZ + 8, math.pi / 2)
		lamp(gx + 17, info.tableZ + 8, -math.pi / 2)
		-- the tunnel: planked floor, stone sides, lanterns, a warm glow at the end
		local tz0, tz1 = wz - 1, wz - 30
		P(V(22, 0.4, tz0 - tz1), W(gx, 0.2, (tz0 + tz1) / 2), rgb(176, 130, 92), WOODM)
		for _, sx in { -1, 1 } do
			P(V(2, 24, tz0 - tz1), W(gx + sx * 11, 12, (tz0 + tz1) / 2), STONE_DARK, MATTE)
			for k = 0, 2 do
				local lz = tz0 - 6 - k * 9
				local lantern = P(V(1.4, 1.8, 1.4), W(gx + sx * 9.6, 9, lz), rgb(255, 222, 160), NEON, { shape = Enum.PartType.Ball })
				if k == 1 then light(lantern, 16, 0.6, rgb(255, 200, 140)) end
			end
		end
		P(V(24, 2, tz0 - tz1), W(gx, 24, (tz0 + tz1) / 2), rgb(60, 52, 76), MATTE)
		local glow = P(V(20, 22, 0.4), W(gx, 11, tz1), rgb(255, 236, 196), NEON)
		glow.Transparency = 0.1
		light(glow, 40, 1.2, rgb(255, 222, 170), "SurfaceLight").Face = Enum.NormalId.Back
		folder = keep
	end

	function Streets.update(dt, t)
		if not Streets.boats then return end
		for i, b in Streets.boats do
			b.x += dt * (3 + i * 0.6)
			if b.x > b.half then b.x = -b.half end
			b.m:PivotTo(CFrame.new(HUB + V(b.x, -5.7 + math.sin(t * 2 + i) * 0.12, b.rz + b.lane)) * CFrame.Angles(0, math.pi / 2 + math.sin(t + i) * 0.1, math.sin(t * 1.6 + i) * 0.06))
		end
	end

	return Streets
end
