-- Roads (ReplicatedStorage.SminskiShared.Roads)
-- Everything that is NOT the street grid: the freeway, the bay bridge, the
-- elevated railway. The grid (Places.CityRoads) stays exactly as it was --
-- jobs, lots and saved houses all hang off it -- and this network grows
-- outward from it and over it.
--
-- A path is a POLYLINE WITH ROUNDED CORNERS, not a free spline: a list of
-- vertices { x, y, z, r } (city-relative; y = deck height; r = corner radius).
-- Roads are straights joined by arcs, and describing them that way means a
-- 1500-stud straight is ONE part instead of a hundred, corners are true
-- circular arcs, and nothing ever overshoots the way a spline does.
--
-- Shared so the client (which builds and drives it) and the server (which
-- may one day validate against it) always agree on where things are.

local Roads = {}
local V = Vector3.new

-- The town is boxed in: hills to the south, east and west, the bay to the
-- north. So the freeway is a HORSESHOE hugging the west, north and east
-- edges in the 58-stud strip between the outer sidewalk (934) and the fence
-- (992), open to the south where the Arcade and the town gate are.
local F = 963   -- freeway centreline
local FY = 30   -- deck height: clears lamps (16), signals (17), buses, trees

Roads.paths = {
	-- FREEWAY: slip road off the west edge street, up a ramp, round the
	-- horseshoe, down a ramp, slip road back onto the east edge street.
	freeway = {
		kind = "freeway", width = 40, name = "Bay Freeway",
		pts = {
			{ -908, 0.25, -830 }, { -908, 0.25, -760, 50 }, { -F, 0.25, -660, 50 },
			{ -F, 0.25, -620 }, { -F, FY, -380 },
			{ -F, FY, F, 110 }, { F, FY, F, 110 },
			{ F, FY, -380 }, { F, 0.25, -620 },
			{ F, 0.25, -660, 50 }, { 908, 0.25, -760, 50 }, { 908, 0.25, -830 },
		},
	},
	-- BAY BRIDGE: leaves the freeway's north side between the lighthouse and
	-- the first boat berth, climbs to a high centre span, lands on the island.
	bridge = {
		kind = "bridge", width = 32, name = "Bay Bridge",
		pts = {
			{ -470, FY, F + 18 }, { -470, FY, 1060 }, { -470, 52, 1300 }, { -470, 52, 1420 },
			{ -470, 3, 1700 }, { -470, 3, 1760 },
		},
	},
	-- THE ELEVATED: a loop over the avenues (x = +-600, z = +-600), one ring
	-- through every district. It runs down the MIDDLE of the street on a
	-- single row of columns, so the cars keep their lanes -- and it puts a
	-- roof of steel across the long straight sightlines.
	rail = {
		kind = "rail", width = 12, closed = true, name = "The Elevated",
		pts = {
			{ -600, 34, -600, 40 }, { -600, 34, 600, 40 }, { 600, 34, 600, 40 }, { 600, 34, -600, 40 },
		},
	},
}

-- Stations on The Elevated. MID-BLOCK, never on a junction: the lifts have
-- to land on a pavement, not in the middle of a cross street.
Roads.stations = {
	{ id = "homes", name = "HOMETOWN", pos = V(150, 34, -600) },
	{ id = "market", name = "MARKET EAST", pos = V(600, 34, 150) },
	{ id = "farm", name = "FARM GATE", pos = V(-150, 34, 600) },
	{ id = "fun", name = "FUN PARK", pos = V(-600, 34, -150) },
}

-- THE AIRPORT ISLAND, out in the bay where the bridge lands. Landside (the
-- road, the doors) faces south towards town; airside faces the runway.
Roads.airport = {
	center = V(110, 3, 1900), size = V(1300, 0, 440),
	runway = { a = V(-460, 3.3, 2000), b = V(680, 3.3, 2000), width = 64 },
	terminal = V(40, 3, 1790),
}
-- THE CIRCUIT a departing plane flies: down the runway, a wide left-hand
-- racetrack out over the open bay, and back in to land. One closed path, so
-- there is nowhere for it to jump.
Roads.paths.flight = {
	kind = "air", width = 0, closed = true, name = "circuit",
	pts = { { -1310, 0, 2000, 440 }, { 1530, 0, 2000, 440 }, { 1530, 0, 2900, 440 }, { -1310, 0, 2900, 440 } },
}

---------------------------------------------------------------------------
-- SAMPLING: a path becomes a list of straight PIECES { a, b } -- one piece
-- per straight, a run of short chords per corner.
---------------------------------------------------------------------------
local cache = {}
function Roads.pieces(name)
	if cache[name] then return cache[name] end
	local path = Roads.paths[name]
	local pts = {}
	for i, p in path.pts do pts[i] = { pos = V(p[1], p[2], p[3]), r = p[4] or 0 } end
	local n = #pts
	local out = {}
	local function flat(v) return V(v.X, 0, v.Z) end
	-- where each corner's arc starts and ends
	local corners = {}
	for i = 1, n do
		local p = pts[i]
		local prev = pts[i - 1] or (path.closed and pts[n])
		local nxt = pts[i + 1] or (path.closed and pts[1])
		if p.r > 0 and prev and nxt then
			local din, dout = flat(p.pos - prev.pos).Unit, flat(nxt.pos - p.pos).Unit
			local turn = math.acos(math.clamp(din:Dot(dout), -1, 1))
			if turn > 0.01 then
				local tl = p.r * math.tan(turn / 2)
				corners[i] = { a = p.pos - din * tl, b = p.pos + dout * tl, din = din, dout = dout, turn = turn }
			end
		end
	end
	local function startOf(i) return corners[i] and corners[i].b or pts[i].pos end
	local function endOf(i) return corners[i] and corners[i].a or pts[i].pos end
	local last = path.closed and n or n - 1
	for i = 1, last do
		local j = i % n + 1
		local a, b = startOf(i), endOf(j)
		if (b - a).Magnitude > 0.5 then table.insert(out, { a = a, b = b }) end
		local c = corners[j]
		if c and (path.closed or j < n) then
			-- the arc, as chords of about 9 studs
			local p = pts[j]
			local side = c.din:Cross(c.dout).Y > 0 and 1 or -1
			local nrm = V(-c.din.Z, 0, c.din.X) * -side -- towards the arc's centre
			local centre = flat(c.a) + nrm * p.r
			local steps = math.max(3, math.ceil(p.r * c.turn / 9))
			local a0 = math.atan2(c.a.Z - centre.Z, c.a.X - centre.X)
			local prevP = c.a
			for k = 1, steps do
				local ang = a0 + (c.turn * k / steps) * -side
				local q = V(centre.X + math.cos(ang) * p.r, c.a.Y + (c.b.Y - c.a.Y) * k / steps, centre.Z + math.sin(ang) * p.r)
				table.insert(out, { a = prevP, b = q, arc = true })
				prevP = q
			end
		end
	end
	-- cumulative distance, for anything that travels along the path
	local s = 0
	for _, pc in out do
		pc.s = s
		pc.len = (pc.b - pc.a).Magnitude
		s += pc.len
	end
	out.length = s
	out.closed = path.closed
	cache[name] = out
	return out
end

-- position + heading at distance s along a path (wraps on closed paths)
function Roads.at(name, s)
	local pcs = Roads.pieces(name)
	if pcs.closed then s = s % pcs.length else s = math.clamp(s, 0, pcs.length - 0.01) end
	local lo, hi = 1, #pcs
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if pcs[mid].s <= s then lo = mid else hi = mid - 1 end
	end
	local pc = pcs[lo]
	local k = (s - pc.s) / math.max(pc.len, 0.001)
	return pc.a:Lerp(pc.b, k), (pc.b - pc.a).Unit
end

-- distance along a path nearest to a point (stations, boarding)
function Roads.nearest(name, pos)
	local pcs = Roads.pieces(name)
	local best, bd = 0, math.huge
	for _, pc in ipairs(pcs) do
		local ab = pc.b - pc.a
		local k = math.clamp((pos - pc.a):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
		local d = (pc.a + ab * k - pos).Magnitude
		if d < bd then best, bd = pc.s + pc.len * k, d end
	end
	return best, bd
end

return Roads
