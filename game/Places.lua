-- Places (ReplicatedStorage.SminskiShared.Places)
-- Layout of the walkable neighborhood hub and the Dog Park Survival arena.
-- Both are drawn on each client; the server reads the same layout for its
-- trigger zones and for the park AI (what to walk around), so nothing has to
-- be streamed and every machine agrees on where things are.

local Places = {}

local V = Vector3.new

-- far away from the runner (which lives around the origin)
Places.HUB = V(6000, 0, 0)
Places.ARENA = V(-6000, 0, 0)
Places.ARENA_HALF = 250

---------------------------------------------------------------------------
-- THE LOBBY: a brown side table in a cozy bedroom at night. The Sminskis
-- walk around a miniature diorama set on the tabletop (y = 0); each little
-- set is a way into a game mode. Positions are relative to Places.HUB.
---------------------------------------------------------------------------
Places.TABLE_X = 150 -- half width  (x)
Places.TABLE_Z = 88  -- half depth  (z)
Places.HUB_HALF = Places.TABLE_X
Places.FLOOR_Y = -64 -- the bedroom floor, far below the tabletop
Places.HubSpawn = V(-8, 0, -100) -- on the bridge: MINI GAMES one way, SMINSKI CITY the other
Places.HubReturnFromRun = V(-38, 0, 34) -- in front of the Endless Run huts
Places.HubReturnFromPark = V(100, 0, 28) -- just outside the dog-park tray

-- action: what walking in / pressing E does (handled on the client)
-- auto: the door is a walk-in trigger (re-arms once you step out)
-- pos: the diorama's centre, face: which way its open front looks (radians)
-- The GAME MODES stand in one row along the back of the table; everything
-- else (shop, cubbies, boutique, library) is scattered around the front.
Places.Entrances = {
	-- the game row (back edge, all facing the middle of the table)
	{ id = "arcade", game = true, title = "RECORD SHOP", sub = "Ranked", icon = "🏆", pos = V(-124, 0, 64), face = math.pi, color = Color3.fromRGB(190, 150, 250), door = V(-124, 0, 48), key = "RANKED" },
	-- Endless Run: one little hut per map (map = Config.Maps id; walk in to run it)
	{ id = "house", game = true, map = "house", title = "THE BIG HOUSE", sub = "Endless Run", icon = "🏠", pos = V(-78, 0, 66), face = math.pi, color = Color3.fromRGB(150, 130, 230), door = V(-78, 0, 50), auto = true, key = "RUN" },
	{ id = "dollhouse", game = true, map = "dollhouse", title = "SMINSKI DOLLHOUSE", sub = "Endless Run", icon = "🏡", pos = V(-38, 0, 66), face = math.pi, color = Color3.fromRGB(150, 215, 120), door = V(-38, 0, 50), auto = true, key = "RUN" },
	{ id = "dogrun", game = true, map = "dogpark", title = "DOG PARK RUN", sub = "Endless Run", icon = "🐶", pos = V(2, 0, 66), face = math.pi, color = Color3.fromRGB(120, 200, 110), door = V(2, 0, 50), auto = true, key = "RUN" },
	{ id = "friends", game = true, title = "SMINSKI CAFE", sub = "Play Together", icon = "👥", pos = V(48, 0, 66), face = math.pi, color = Color3.fromRGB(255, 170, 190), door = V(48, 0, 48), key = "PLAY" },
	{ id = "dogpark", game = true, title = "DOG PARK SURVIVAL", sub = "Last Sminski alive wins", icon = "🐕", pos = V(104, 0, 62), face = math.pi, color = Color3.fromRGB(120, 200, 110), door = V(104, 0, 36), key = "ENTER" },
	-- everything else, scattered around
	{ id = "store", title = "SMINSKI SHOP", sub = "Upgrades · power-ups", icon = "🛒", pos = V(40, 0, -60), face = 0, color = Color3.fromRGB(245, 196, 80), door = V(40, 0, -42), key = "SHOP" },
	{ id = "capsule", title = "DISPLAY CUBBIES", sub = "Capsules + collection", icon = "🎰", pos = V(102, 0, -66), face = 0, color = Color3.fromRGB(255, 125, 110), door = V(102, 0, -50), key = "OPEN" },
	{ id = "closet", title = "LITTLE BOUTIQUE", sub = "Outfits", icon = "👕", pos = V(132, 0, 18), face = -math.pi / 2, color = Color3.fromRGB(140, 190, 240), door = V(116, 0, 18), key = "DRESS UP" },
	{ id = "garden", title = "SMINSKI GARDEN", sub = "Grow plants · sell for coins", icon = "🌱", pos = V(78, 0, -22), face = 0, color = Color3.fromRGB(120, 200, 110), door = V(78, 0, -4), key = "GARDEN" },
	{ id = "board", title = "SMINSKI LIBRARY", sub = "Goals + stats", icon = "📋", pos = V(132, 0, -30), face = -math.pi / 2, color = Color3.fromRGB(150, 205, 140), door = V(116, 0, -30), key = "VIEW" },
}

---------------------------------------------------------------------------
-- SMINSKI CITY: a real little city in a green valley between two huge
-- mountains, through the arch in the bedroom wall. 2000 x 2000 studs on a
-- 7x7 road grid (blocks are 260 wide), five districts. Everything below is
-- relative to Places.CITY; the server uses it to check jobs, the client to
-- build the town, so both always agree.
---------------------------------------------------------------------------
Places.CITY = V(12000, 0, 0)
Places.CITY_HALF = 1000
Places.CityRoads = { -900, -600, -300, 0, 300, 600, 900 } -- road centre lines, both axes
Places.ROAD_W = 40
Places.BLOCK = 260 -- a block between two roads
Places.WALK_W = 14 -- sidewalk ring inside each block
Places.CitySpawn = V(0, 0, -955)
Places.CityExit = V(0, 0, -992) -- the tunnel back to the bedroom
-- the gate in the bedroom wall (hub-relative), and where you come back out
Places.HubGateX = -8
Places.HubGateZ = -112 -- the bedroom wall's inner face
Places.HubReturnFromCity = V(-8, 0, -70)

local STREETS_NS = { [-900] = "Pine Ave", [-600] = "Maple Ave", [-300] = "Cherry Ave", [0] = "Main St", [300] = "Birch Ave", [600] = "Willow Ave", [900] = "Cedar Ave" }
local STREETS_EW = { [-900] = "Sunny St", [-600] = "Button St", [-300] = "Mochi St", [0] = "Central Blvd", [300] = "Cloud St", [600] = "Clover Rd", [900] = "Meadow Rd" }
Places.CityStreetsNS, Places.CityStreetsEW = STREETS_NS, STREETS_EW

-- districts (for the map, the street sign in the HUD, and fast travel)
Places.CityDistricts = {
	{ id = "downtown", name = "Downtown", x0 = -300, x1 = 300, z0 = -300, z1 = 300, color = Color3.fromRGB(150, 180, 230), stop = V(27, 0, -250) },
	{ id = "shopping", name = "Shopping District", x0 = 300, x1 = 1000, z0 = -300, z1 = 300, color = Color3.fromRGB(250, 170, 200), stop = V(327, 0, 250) },
	{ id = "fun", name = "Fun Park", x0 = -1000, x1 = -300, z0 = -300, z1 = 300, color = Color3.fromRGB(255, 206, 110), stop = V(-327, 0, 250) },
	{ id = "homes", name = "Sunny Homes", x0 = -1000, x1 = 1000, z0 = -1000, z1 = -300, color = Color3.fromRGB(170, 220, 150), stop = V(27, 0, -560) },
	{ id = "farm", name = "Green Valley Farms", x0 = -1000, x1 = 1000, z0 = 300, z1 = 1000, color = Color3.fromRGB(206, 190, 130), stop = V(27, 0, 380) },
}
function Places.cityDistrictAt(p)
	for _, d in Places.CityDistricts do
		if p.X >= d.x0 and p.X <= d.x1 and p.Z >= d.z0 and p.Z <= d.z1 then return d end
	end
	return nil
end

-- what stands on each block (keyed "cx,cz" by block centre)
Places.CityBlocks = {
	-- downtown
	["-150,-150"] = "cityhall", ["150,-150"] = "postbank", ["-150,150"] = "towersW", ["150,150"] = "towersE",
	-- shopping
	["450,150"] = "mall", ["750,150"] = "dealer", ["450,-150"] = "shopstreet", ["750,-150"] = "market",
	-- fun park
	["-450,150"] = "fair", ["-750,150"] = "race", ["-450,-150"] = "arcade", ["-750,-150"] = "concert",
	-- homes
	["-750,-450"] = "houses", ["-450,-450"] = "park", ["-150,-450"] = "school", ["150,-450"] = "apartments",
	["450,-450"] = "houses", ["750,-450"] = "houses", ["-750,-750"] = "houses", ["-450,-750"] = "houses",
	["-150,-750"] = "pool", ["150,-750"] = "houses", ["450,-750"] = "houses", ["750,-750"] = "houses",
	-- farms
	["-750,450"] = "pasture", ["-450,450"] = "orchard", ["-150,450"] = "fields", ["150,450"] = "barn",
	["450,450"] = "windmills", ["750,450"] = "farmmarket", ["-750,750"] = "camp", ["-450,750"] = "pumpkins",
	-- "750,750" was `forest` (30 pines and a cabin). It is RESTAURANT ROW now:
	-- twelve tycoon plots round its kerb (docs/TYCOON.md). The list of Row
	-- blocks lives in Config.Tycoon.Blocks; this entry must agree with it.
	["-150,750"] = "lake", ["150,750"] = "sunflowers", ["450,750"] = "cows", ["750,750"] = "restaurantrow",
}
Places.BlockCentres = { -750, -450, -150, 150, 450, 750 }

-- job + attraction spots
Places.CityDepot = V(110, 0, -28) -- post office counter (pick up parcels)
Places.CityTaxiStand = V(27, 0, -150)
Places.CityDealer = V(720, 0, 76)
Places.CityBiz = { -- where you buy / collect each business (its front door)
	boba = V(364, 0, 168), sweets = V(400, 0, 168), toys = V(364, 0, 132), pizza = V(500, 0, 132),
	arcade = V(-520, 0, -48), cinema = V(-338, 0, -170),
}
Places.MallShops = { -- the mall's non-business shops (open the main game's shops)
	{ id = "boutique", name = "BOUTIQUE", pos = V(500, 0, 168), tab = "outfits" },
	{ id = "capsules", name = "CAPSULE CORNER", pos = V(536, 0, 168), tab = "capsules" },
	{ id = "powerups", name = "POWER-UPS", pos = V(400, 0, 132), tab = "upgrades" },
	-- APPENDED. The mall's fourth ground-floor unit on the south side used to
	-- be a PET SHOP with no prompt on it at all -- one of seven such units
	-- (docs/WORLD_REVAMP.md §4.4). The skins tab was the one shop in the game
	-- with no door anywhere in the city, so it gets this one. Appended last:
	-- CityEvents and the server both index this list ([2] is Capsule Corner).
	{ id = "skins", name = "CHARACTER SHOP", pos = V(536, 0, 132), tab = "skins" },
}
Places.CityRides = { ferris = V(-450, 0, 168), carousel = V(-530, 0, 80) }
Places.FerrisHub = V(-450, 78, 214) -- the wheel's axle
Places.CityClaw = V(-520, 0, -90)
-- the kart track: a rounded rectangle in the Fun Park, driven counter-clockwise
Places.RaceLaps = 3
Places.RaceStart = V(-750, 0, 100)
function Places.racePoints()
	local pts = {}
	local cxs = { -700, -800 }
	-- bottom straight (z = 100) west -> east, east bend, top straight east -> west, west bend
	for k = 0, 3 do table.insert(pts, V(-800 + k * 100 / 3, 0, 100)) end
	for k = 0, 6 do local a = -math.pi / 2 + k * math.pi / 6 table.insert(pts, V(cxs[1] + math.cos(a) * 50, 0, 150 + math.sin(a) * 50)) end
	for k = 1, 2 do table.insert(pts, V(-700 - k * 100 / 3, 0, 200)) end
	for k = 0, 6 do local a = math.pi / 2 + k * math.pi / 6 table.insert(pts, V(cxs[2] + math.cos(a) * 50, 0, 150 + math.sin(a) * 50)) end
	return pts
end
-- named places a taxi passenger might want to go
-- the big store: where B.market puts the SUPER MARKET's till. The server
-- checks a checkout against this and against every grocery lot's door.
-- MEASURED: the store's frame looks along +Z, so its front is the +Z side
-- and local +X is world -X; the till at local (+66, -28) is world (694, -172).
Places.CityMarketTill = V(694, 0, -172)

Places.CityLandmarks = {
	{ name = "the Mall", pos = V(327, 0, 150) }, { name = "City Hall", pos = V(-150, 0, -40) },
	{ name = "the Ferris Wheel", pos = V(-450, 0, 40) }, { name = "the Kart Track", pos = V(-620, 0, 40) },
	{ name = "the Arcade", pos = V(-520, 0, -40) }, { name = "the School", pos = V(-150, 0, -330) },
	{ name = "Button Park", pos = V(-450, 0, -330) }, { name = "the Pool", pos = V(-150, 0, -630) },
	{ name = "the Barn", pos = V(150, 0, 330) }, { name = "the Lake", pos = V(-150, 0, 630) },
	{ name = "the Car Dealer", pos = V(720, 0, 40) }, { name = "the Supermarket", pos = V(760, 0, -40) },
	{ name = "the Campground", pos = V(-750, 0, 630) }, { name = "the Windmills", pos = V(450, 0, 330) },
	{ name = "the Apartments", pos = V(150, 0, -330) }, { name = "the City Gate", pos = V(40, 0, -940) },
	-- APPEND ONLY: a fare in flight saves its destination as an index in here
	{ name = "the Job Center", pos = V(150, 0, -268) }, { name = "Slice of Life", pos = V(268, 0, -150) },
}

-- every building lot that can take a parcel: { kind, pos, face, door, address, ... }
local lotCache
function Places.cityLots()
	if lotCache then return lotCache end
	local rgb = Color3.fromRGB
	local lots, num = {}, 0
	local SIDES = { N = { V(0, 0, 1), 0 }, S = { V(0, 0, -1), math.pi }, E = { V(1, 0, 0), math.pi / 2 }, W = { V(-1, 0, 0), -math.pi / 2 } }
	local function street(cx, cz, side)
		if side == "N" then return STREETS_EW[cz + 150] elseif side == "S" then return STREETS_EW[cz - 150]
		elseif side == "E" then return STREETS_NS[cx + 150] else return STREETS_NS[cx - 150] end
	end
	local function add(kind, cx, cz, side, along, depth, extra)
		local s = SIDES[side]
		local n = s[1]
		local t = V(n.Z, 0, -n.X) -- along the street
		local pos = V(cx, 0, cz) + n * depth + t * along
		num += 1
		local lot = { kind = kind, pos = pos, face = s[2], door = V(cx, 0, cz) + n * 118 + t * along, address = (num * 2 + 1) .. " " .. (street(cx, cz, side) or "Main St") }
		for k, v in extra or {} do lot[k] = v end
		table.insert(lots, lot)
		return lot
	end
	-- candy pastels with bright roofs (as in the key art)
	local HOUSE_COLS = {
		{ Color3.fromRGB(255, 232, 200), Color3.fromRGB(236, 130, 96) }, { Color3.fromRGB(214, 236, 255), Color3.fromRGB(96, 150, 230) },
		{ Color3.fromRGB(255, 244, 200), Color3.fromRGB(240, 170, 80) }, { Color3.fromRGB(214, 244, 214), Color3.fromRGB(96, 180, 120) },
		{ Color3.fromRGB(240, 226, 255), Color3.fromRGB(160, 120, 226) }, { Color3.fromRGB(255, 222, 232), Color3.fromRGB(236, 110, 160) },
		{ Color3.fromRGB(214, 246, 240), Color3.fromRGB(70, 180, 170) }, { Color3.fromRGB(252, 246, 226), Color3.fromRGB(200, 100, 90) },
	}
	-- STREET-WALL PROFILES, one per block kind. Absent = no wall (the farm
	-- belt, and the blocks whose own buildings already reach the kerb).
	-- lo/hi = floor range, so each district has its own skyline.
	local WALL = {
		-- `d` = HOW DEEP the street-wall buildings are, and it is the one number
		-- that turns their ground floors from slots into rooms. It is safe to
		-- change because the lot's depth is derived from it as `116 - d/2`,
		-- while `door` is `centre + n*118` and does not involve depth at all
		-- (see add(), above). So growing `d`:
		--   * keeps the FACADE at exactly 116 from the block centre,
		--   * keeps the DOOR LINE at 118, and with it the -1.5 facade plane,
		--     the +2 clear-pavement strip the COLLECT events scatter on, the
		--     +8 posts, the +12 kerb and the +15.3 gutter the ice cream truck
		--     parks in (docs/HANDOFF.md §5),
		--   * keeps the lot index, and with it every saved house.
		-- Only the BACK of the building moves, inward into the block's hollow
		-- middle. So `d` is per block kind, sized to what is actually behind it:
		--   16 -- towersW / towersE: ZERO SLACK. The towers stand at ±62 with
		--         76-wide footprints, so they reach exactly 100 and the wall
		--         already occupies 100-116. These cannot get deeper without
		--         moving a tower, which is measured geometry.
		--   32 -- EVERYTHING ELSE, which is deliberately less than the 56 the
		--         plan proposed. 56 would put the inner face at 60 from the
		--         block centre, and the block centres are NOT hollow to ±34:
		--         read off the builders, B.school's playing field runs to
		--         z = centre+110 (CityBuild.lua:555) and B.park's pond reaches
		--         x = centre+82 (CityBuild.lua:572), so a 56-deep wall would
		--         stand in both. 32 puts the inner face on 100 -- the line
		--         towersW/E already prove is clear -- which is 8 studs of new
		--         ground and doubles the room behind the shopfront from a
		--         14-stud slot to a 30-stud room. Going deeper is a per-block
		--         decision and wants a Studio measurement, not an estimate.
		-- The five measured blocks (fair, race, dealer, mall, postbank) carry an
		-- explicit d = 32 even though it is the default, because they are the
		-- ones whose own buildings reach the kerb zone and so the ones whose
		-- depth must be re-checked first if the default ever moves.
		towersW   = { lo = 4, hi = 7, district = "downtown",      seed = 0,  alley = "E", d = 16 },
		towersE   = { lo = 4, hi = 7, district = "downtown",      seed = 9,  alley = "W", d = 16 },
		cityhall  = { lo = 3, hi = 5, district = "downtown",      seed = 4,  gate = true },
		arcade    = { lo = 3, hi = 5, district = "entertainment", seed = 6,  gate = true },
		concert   = { lo = 3, hi = 5, district = "entertainment", seed = 2,  gate = true },
		market    = { lo = 2, hi = 4, district = "shopping",      seed = 11, gate = true },
		school    = { lo = 2, hi = 3, district = "residential",   seed = 7,  gate = true },
		pool      = { lo = 2, hi = 3, district = "residential",   seed = 13, gate = true },
		park      = { lo = 3, hi = 5, district = "park",          seed = 15, gate = true },
		-- These five have buildings of their own that reach the kerb zone, so
		-- they only take a wall where the frontage is actually free. The masks
		-- were MEASURED (edit-mode build, bounding boxes against each slot),
		-- not guessed: one character per ALONG slot, "." = free, "X" = taken.
		-- corners = (-x-z, -x+z, +x-z, +x+z). Re-measure if a builder changes.
		fair      = { lo = 3, hi = 5, district = "entertainment", seed = 5,  gate = true, d = 32,
			mask = { N = "......", S = "XXXXXX", E = "......", W = "XX...." }, corners = "X..." },
		race      = { lo = 2, hi = 4, district = "entertainment", seed = 10, gate = true, d = 32,
			mask = { N = "..XX..", S = "......", E = "......", W = "......" }, corners = "...." },
		dealer    = { lo = 2, hi = 4, district = "shopping",      seed = 12, gate = true, d = 32,
			mask = { N = "......", S = ".XXXXX", E = "......", W = "......" }, corners = "...." },
		mall      = { lo = 2, hi = 4, district = "shopping",      seed = 14, gate = true, d = 32,
			mask = { N = "......", S = "......", E = "XXXXXX", W = "XXXXXX" }, corners = "XXXX" },
		postbank  = { lo = 3, hi = 5, district = "downtown",      seed = 16, gate = true, d = 32,
			mask = { N = "XXXXXX", S = "XX.XXX", E = "....XX", W = "XXXX.X" }, corners = "XXX." },
	}
	-- which shop types have a walk-in interior. `grocery` joined: a corner
	-- shop you push a basket round (CityGrocery). Lot ORDER is unchanged --
	-- only the kind of those lots -- so saved lot indices still line up.
	local FOOD = { cafe = true, bakery = true, restaurant = true, deli = true, grocery = true }
	-- six units a side instead of four: tighter frontage, more doors per
	-- street, which is what actually makes a block feel busy
	local ALONG = { -80, -48, -16, 16, 48, 80 }
	local SHOPS = {
		{ "CAFE", "cafe", rgb(150, 96, 70) }, { "BAKERY", "bakery", rgb(236, 170, 110) },
		{ "BOOKS", "books", rgb(130, 110, 90) }, { "PET SHOP", "pets", rgb(150, 190, 160) },
		{ "CLOTHING", "clothes", rgb(140, 190, 240) }, { "ELECTRONICS", "tech", rgb(110, 130, 210) },
		{ "TOY STORE", "toys", rgb(120, 200, 150) }, { "FLORIST", "flowers", rgb(240, 130, 170) },
		{ "RAMEN", "restaurant", rgb(226, 100, 90) }, { "BARBER", "barber", rgb(90, 150, 200) },
		{ "GYM", "gym", rgb(240, 150, 80) }, { "GROCERY", "grocery", rgb(120, 180, 120) },
		{ "PHARMACY", "pharmacy", rgb(100, 170, 190) }, { "BIKE SHOP", "bikes", rgb(200, 120, 90) },
		{ "ART STORE", "art", rgb(180, 140, 220) }, { "MUSIC", "music", rgb(120, 130, 210) },
		{ "DELI", "deli", rgb(220, 160, 100) }, { "LAUNDRY", "laundry", rgb(150, 170, 200) },
		{ "HARDWARE", "hardware", rgb(190, 140, 100) }, { "NOODLES", "restaurant", rgb(230, 140, 90) },
		{ "TAILOR", "tailor", rgb(170, 130, 190) }, { "PHOTO", "photo", rgb(120, 160, 180) },
		{ "ICE CREAM", "cafe", rgb(244, 170, 196) }, { "SUSHI", "restaurant", rgb(96, 150, 170) },
		{ "PIZZA", "restaurant", rgb(226, 120, 90) }, { "BOBA", "cafe", rgb(180, 150, 230) },
		{ "DINER", "restaurant", rgb(210, 90, 100) },
	}
	local WALLS = {
		Color3.fromRGB(214, 196, 178), Color3.fromRGB(196, 186, 176), Color3.fromRGB(226, 212, 194),
		Color3.fromRGB(186, 172, 164), Color3.fromRGB(206, 198, 186), Color3.fromRGB(176, 164, 158),
		Color3.fromRGB(222, 206, 186), Color3.fromRGB(202, 190, 170),
	}
	local keys = {}
	for k in Places.CityBlocks do table.insert(keys, k) end
	table.sort(keys)
	local h = 0
	for _, key in keys do
		local kind = Places.CityBlocks[key]
		local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
		cx, cz = tonumber(cx), tonumber(cz)
		if kind == "houses" then
			for _, side in { "N", "S", "E", "W" } do
				for _, along in { -48, 48 } do
					h += 1
					local c = HOUSE_COLS[h % #HOUSE_COLS + 1]
					add("house", cx, cz, side, along, 82, { color = c[1], roof = c[2], style = h % 3 })
				end
			end
		elseif kind == "shopstreet" then
			local names = { "CAFE", "BAKERY", "FLOWERS", "BOOKS", "ICE CREAM", "DINER", "MUSIC", "PET SHOP" }
			local walls = { Color3.fromRGB(255, 236, 200), Color3.fromRGB(252, 246, 226), Color3.fromRGB(255, 226, 236), Color3.fromRGB(226, 240, 255), Color3.fromRGB(236, 228, 255), Color3.fromRGB(220, 246, 226) }
			local accents = { Color3.fromRGB(236, 130, 96), Color3.fromRGB(240, 120, 170), Color3.fromRGB(110, 160, 236), Color3.fromRGB(160, 120, 226), Color3.fromRGB(80, 184, 150), Color3.fromRGB(240, 170, 70), Color3.fromRGB(230, 96, 100), Color3.fromRGB(70, 180, 200) }
			local i = 0
			for _, side in { "N", "S" } do
				for _, along in { -78, 0, 78 } do
					i += 1
					add("shop", cx, cz, side, along, 90, { name = names[i], color = walls[i % #walls + 1], accent = accents[i % #accents + 1] })
				end
			end
			for _, side in { "E", "W" } do
				i += 1
				add("shop", cx, cz, side, 0, 90, { name = names[i], color = walls[i % #walls + 1], accent = accents[i % #accents + 1] })
			end
		elseif kind == "apartments" then
			for _, side in { "N", "S", "E", "W" } do
				add("apartment", cx, cz, side, 0, 78, { color = HOUSE_COLS[#lots % #HOUSE_COLS + 1][1], accent = HOUSE_COLS[#lots % #HOUSE_COLS + 1][2] })
			end
		end
	end
	-- a few landmark doors take parcels too
	for _, x in {
		{ "school", V(-150, 0, -470), "School" }, { "barn", V(150, 0, 400), "Green Valley Farm" },
		{ "cityhall", V(-150, 0, -134), "City Hall" }, { "market", V(760, 0, -160), "Supermarket" },
	} do
		table.insert(lots, { kind = x[1], pos = x[2], face = 0, door = x[2], address = x[3], landmark = true })
	end
	-- THE STREET WALL. Appended strictly AFTER every original lot: the server
	-- saves house ownership as an index into this list (assignHouse), so new
	-- lots may only ever be added at the end, never in the middle.
	-- Depth is per block kind (WALL[kind].d, default 32) and grows INWARD from
	-- a facade fixed at 116: the middle of a block may be hollow, nobody can
	-- see it (.claude/rules/environment.md). It used to be 16 for every block,
	-- which made every ground floor a 14-stud slot.
	for _, key in keys do
		local kind = Places.CityBlocks[key]
		local w = WALL[kind]
		if w then
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			local d = 0
			for _, side in { "N", "S", "E", "W" } do
				for _, along in ALONG do
					d += 1
					-- landmark blocks keep a wide gateway in the middle of every
					-- side, so the landmark is framed by buildings, not hidden;
					-- tower blocks get one alley through the wall instead
					-- no unit here: a gateway, the alley, or the block's own building
					local function gap(a)
						local i = (a + 80) // 32 + 1
						return (w.gate and math.abs(a) == 16) or (side == w.alley and a == 16)
							or (w.mask ~= nil and string.sub(w.mask[side], i, i) == "X")
					end
					local open = gap(along)
					if not open then
						local sh = SHOPS[(d + w.seed) % #SHOPS + 1]
						-- `dep` is the building's own depth; the lot sits at
						-- 116 - dep/2 so the FACADE stays on 116 however deep
						-- the room behind it gets, and nothing downstream of
						-- the door line moves. (`d` here is the unit counter,
						-- not a depth -- it was named first.)
						local dep = w.d or 32
						add("midrise", cx, cz, side, along, 116 - dep / 2, {
							name = sh[1], btype = sh[2], accent = sh[3], d = dep,
							color = WALLS[(d + w.seed) % #WALLS + 1],
							floors = w.lo + (d * 2 + (cx > 0 and 1 or 0)) % (w.hi - w.lo + 1),
							district = w.district,
							-- food places are the ones you can walk into (CityVenues)
							-- every unit is a real room you can walk into; food
							-- places get a counter and tables, shops get shelves
							-- and something to do (CityVenues)
							interior = true,
							food = FOOD[sh[2]] == true,
							shop = sh[2],
							npc = d % 2 == 0,
							-- an end wall with no neighbour gets windows instead
							-- of blank plaster (lower `along` = the lot's +X side)
							openL = along > -80 and gap(along - 32),
							openR = along < 80 and gap(along + 32),
						})
					end
				end
			end
			-- CORNER BUILDINGS: a block's corner is its most visible spot, so
			-- it gets a taller turret with two street faces rather than an
			-- empty square of paving. Tower blocks keep the corner nearest
			-- the central crossroads clear: the subway entrance lives there.
			local ci = 0
			for _, side in { "N", "S" } do
				for _, along in { -107.5, 107.5 } do
					ci += 1
					local wx = (side == "N") and along or -along
					local wz = (side == "N") and 1 or -1
					local subway = w.alley and (wx > 0) == (cx < 0) and (wz > 0) == (cz < 0)
					-- measured blocks: is this corner already built on?
					local cidx = (wx > 0 and 2 or 0) + (wz > 0 and 1 or 0) + 1
					local built = w.corners and string.sub(w.corners, cidx, cidx) == "X"
					if not subway and not built then
						local sh = SHOPS[(ci * 5 + w.seed) % #SHOPS + 1]
						add("corner", cx, cz, side, along, 107.5, {
							name = sh[1], btype = sh[2], accent = sh[3],
							color = WALLS[(ci + w.seed) % #WALLS + 1],
							floors = w.hi + 1, lateral = along > 0 and -1 or 1,
							district = w.district, shop = sh[2],
						})
					end
				end
			end
		end
	end
	-- HOUSING INFILL: a third house in the middle of every side. Same house,
	-- but nobody is assigned one ("rowhouse", not "house"), so ownership and
	-- the saved lot indices are untouched. No driveway: the neighbours' are
	-- either side of it.
	local rh = 0
	for _, key in keys do
		if Places.CityBlocks[key] == "houses" then
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			for _, side in { "N", "S", "E", "W" } do
				rh += 1
				local c = HOUSE_COLS[(rh * 3) % #HOUSE_COLS + 1]
				add("rowhouse", cx, cz, side, -5.5, 82, { color = c[1], roof = c[2], style = rh % 3, row = true })
			end
		elseif Places.CityBlocks[key] == "shopstreet" then
			-- THE SHOPPING STREET had eight shops and a lot of paving. Close
			-- the gaps: two more shops on each short side, and a narrow
			-- mid-rise squeezed between each pair on the long sides.
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			local k = 0
			for _, side in { "E", "W" } do
				for _, along in { -47, 47 } do
					k += 1
					local sh = SHOPS[(k * 4 + 2) % #SHOPS + 1]
					add("shop", cx, cz, side, along, 90, { name = sh[1], color = WALLS[k % #WALLS + 1], accent = sh[3] })
				end
			end
			for _, side in { "N", "S" } do
				for _, along in { -39, 39 } do
					k += 1
					local sh = SHOPS[(k * 3 + 1) % #SHOPS + 1]
					add("midrise", cx, cz, side, along, 100, {
						name = sh[1], btype = sh[2], accent = sh[3], color = WALLS[k % #WALLS + 1],
						floors = 3 + k % 2, w = 30, district = "shopping",
						interior = true, food = FOOD[sh[2]] == true, shop = sh[2],
					})
				end
			end
		end
	end
	-- CORNER CAFES: a walk-in venue on the north-east corner of every housing
	-- block, so no neighbourhood is more than a block from somewhere to sit
	-- down and eat. Also appended last, for the same index-stability reason.
	local CAFES = {
		{ "CORNER CAFE", "cafe", rgb(150, 96, 70) }, { "BAKERY", "bakery", rgb(236, 170, 110) },
		{ "NOODLE BAR", "restaurant", rgb(226, 100, 90) }, { "DELI", "deli", rgb(220, 160, 100) },
		{ "TEA HOUSE", "cafe", rgb(120, 170, 130) }, { "DONUT SHOP", "bakery", rgb(240, 150, 180) },
		{ "CURRY HOUSE", "restaurant", rgb(230, 150, 70) }, { "SANDWICH BAR", "deli", rgb(110, 160, 190) },
		{ "MILK BAR", "cafe", rgb(170, 150, 220) },
	}
	local v = 0
	for _, key in keys do
		local kind = Places.CityBlocks[key]
		if kind == "houses" or kind == "apartments" then
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			v += 1
			local c = CAFES[v % #CAFES + 1]
			add("venue", cx, cz, "N", 96, 100, {
				name = c[1], btype = c[2], accent = c[3], color = WALLS[v % #WALLS + 1],
				district = "residential", interior = true, shop = c[2],
			})
		end
	end
	-- THE JOB CENTER, and the first workplace with stations in it. Appended
	-- last, like every lot added after launch: the server saves house
	-- ownership as an index into this list (assignHouse), so a lot may only
	-- ever go on the end, never in the middle.
	--
	-- BOTH SITES WERE READ OFF B.postbank, not guessed. That block holds the
	-- post office (x 65..155, z -89..-39), the bank (x 175..245, z -91..-41)
	-- and two towers (x 45..115 and x 195..255, both z -255..-185). That
	-- leaves an 80-stud gap between the towers on the south side, and a clear
	-- strip due east of centre. Both happen to sit behind a GATEWAY in the
	-- street wall (postbank is a `gate` block, so |along| <= 16 is open), which
	-- is the point: you can see each front door from the street instead of it
	-- being buried behind a facade.
	add("jobcentre", 150, -150, "S", 0, 62, {
		name = "JOB CENTER", district = "downtown",
		color = rgb(238, 244, 252), accent = rgb(96, 150, 230),
	})
	add("workplace", 150, -150, "E", 0, 62, {
		name = "SLICE OF LIFE", btype = "pizzeria", restaurant = "pizzeria",
		district = "downtown", interior = true, shop = "pizzeria",
		color = rgb(255, 238, 222), accent = rgb(226, 100, 90),
	})
	for _, l in lots do l.drop = true end
	lotCache = lots
	return lots
end

-- RESTAURANT ROW: the tycoon plots (docs/TYCOON.md). NOT part of cityLots():
-- nothing here takes a parcel, and no saved index points into this list --
-- a lot is claimed per server, the way a house is (assignHouse), and the
-- restaurant itself lives in the owner's save. Twelve plots a Row block,
-- three a side, each LotW x LotD with its kerb edge on the sidewalk ring.
-- Both the server (range checks) and the client (geometry) read positions
-- through tycoonPoint(), so a spot is one pair of numbers in Config.Tycoon.
local tyCache
function Places.tycoonLots()
	if tyCache then return tyCache end
	local Config = require(script.Parent:WaitForChild("Config"))
	local T = Config.Tycoon
	local INNER = Places.BLOCK / 2 - Places.WALK_W -- 116
	local SIDES = { N = { V(0, 0, 1), 0 }, E = { V(1, 0, 0), math.pi / 2 }, S = { V(0, 0, -1), math.pi }, W = { V(-1, 0, 0), -math.pi / 2 } }
	local lots = {}
	for _, key in T.Blocks do
		local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
		cx, cz = tonumber(cx), tonumber(cz)
		for _, side in { "N", "E", "S", "W" } do
			local n, face = SIDES[side][1], SIDES[side][2]
			local t = V(n.Z, 0, -n.X)
			for _, along in T.Along do
				table.insert(lots, {
					i = #lots + 1, pos = V(cx, 0, cz) + n * (INNER - T.LotD / 2) + t * along,
					face = face, block = key, side = side,
				})
			end
		end
	end
	tyCache = lots
	return lots
end
-- a plot-local (x, z) -> city-relative position. Matches K.frameOf(pos, face)
-- exactly: +x is that frame's RightVector, +z its -LookVector (into the block).
function Places.tycoonPoint(lot, x, z)
	local f = lot.face
	return lot.pos + V(-math.cos(f), 0, math.sin(f)) * x + V(-math.sin(f), 0, -math.cos(f)) * z
end
function Places.tycoonSpot(lot, name)
	local Config = require(script.Parent:WaitForChild("Config"))
	local s = Config.Tycoon.Spots[name]
	-- `pads` is a list of spots, not a spot; ask for those by index yourself
	if type(s) ~= "table" or type(s[1]) ~= "number" then return nil end
	return Places.tycoonPoint(lot, s[1], s[2])
end
Places.RestaurantRow = V(750, 0, 750) -- the Row's middle: wayfinding, the map

-- where the Job Center's door and its board are, for prompts and wayfinding
Places.CityJobCentre = V(150, 0, -268)
Places.CityJobBoard = V(150, 0, -206)
-- every workplace that has stations in it, by restaurant id
Places.CityWorkplaces = {
	pizzeria = { pos = V(212, 0, -150), face = math.pi / 2, door = V(268, 0, -150), name = "SLICE OF LIFE" },
}

-- APARTMENT TOWERS: where the three high-rises stand. Every site was
-- MEASURED empty (edit-mode build, 44-stud cells, counting flat things like
-- forecourts and lawns as well as buildings) -- they stand inside their
-- blocks, behind the street wall, the way a real tower rises behind a podium.
-- `face` is which way the lobby looks; each one looks at a gateway in its
-- block's wall so you can see the front door from the street.
-- (The brownstones and the townhouses reuse buildings that already exist:
-- the "apartment" lots and the "rowhouse" lots. See CityApts.lua.)
Places.CityApts = {
	bankside = { pos = V(150, 0, -134), w = 64, d = 54, floors = 22, face = math.pi, tex = "cream", accent = Color3.fromRGB(96, 140, 196) },
	motorrow = { pos = V(783, 0, 198), w = 52, d = 52, floors = 16, face = 0, tex = "butter", accent = Color3.fromRGB(226, 120, 96) },
	funfair = { pos = V(-500, 0, 166), w = 52, d = 52, floors = 18, face = -math.pi / 2, tex = "mint", accent = Color3.fromRGB(240, 150, 190) },
}
function Places.aptDoor(id)
	local a = Places.CityApts[id]
	if not a then return nil end
	return a.pos + V(math.sin(a.face), 0, math.cos(a.face)) * (a.d / 2 + 5)
end

-- COURTYARD GARDENS. The street wall leaves the middle of each urban block
-- hollow; that hollow is reached through the block's alley and is where the
-- city keeps its gardens. Same growing job as the farm belt, but scattered
-- through town so a player never has to cross the map to tend one.
function Places.cityGardens()
	local out = {}
	local HAS = { houses = true, apartments = true, school = true, pool = true, park = true, arcade = true }
	local keys = {}
	for k in Places.CityBlocks do table.insert(keys, k) end
	table.sort(keys)
	for _, key in keys do
		if HAS[Places.CityBlocks[key]] then
			local cx, cz = string.match(key, "(-?%d+),(-?%d+)")
			cx, cz = tonumber(cx), tonumber(cz)
			-- four beds around the courtyard, clear of the wall's inner face
			for _, o in { V(-34, 0, -34), V(34, 0, -34), V(-34, 0, 34), V(34, 0, 34) } do
				table.insert(out, V(cx + o.X, 0, cz + o.Z))
			end
		end
	end
	return out
end

-- the farm fields (job plots) in the "fields" block
function Places.cityFarmPlots()
	local out = {}
	for j = -1, 1 do
		for _, i in { -90, -30, 30, 90 } do
			table.insert(out, V(-150 + i, 0, 450 + j * 70))
		end
	end
	return out
end

function Places.entrance(id)
	for _, e in Places.Entrances do
		if e.id == id then return e end
	end
	return nil
end

-- Dog Park waiting pen: the fenced grass tray on the right (walk in = queue)
Places.Pen = { center = V(104, 0, 62), half = V(24, 30, 22) }

function Places.inPen(worldPos)
	local p = worldPos - Places.HUB - Places.Pen.center
	local h = Places.Pen.half
	return math.abs(p.X) <= h.X and math.abs(p.Z) <= h.Z and p.Y > -10 and p.Y < h.Y
end

---------------------------------------------------------------------------
-- DOG PARK ARENA (positions relative to Places.ARENA)
---------------------------------------------------------------------------
Places.Gates = { V(0, 0, 250), V(250, 0, 0), V(0, 0, -250), V(-250, 0, 0) }
Places.PATH_W = 26 -- the two cross paths
Places.RING_R = 205 -- jogging loop

-- player spawn ring
function Places.arenaSpawn(i, n)
	local a = (i - 1) / math.max(1, n) * math.pi * 2 + 0.3
	return V(math.cos(a) * 42, 0, math.sin(a) * 42)
end

-- deterministic prop layout. Each prop:
--   kind, pos (y = 0), yaw, size (Vector3), r (AI keeps this far away; 0 = walk over),
--   shelter (feet + thrown things can't reach you under it), bush (hides you from dogs)
local layoutCache
function Places.arenaLayout()
	if layoutCache then return layoutCache end
	local rng = Random.new(90210)
	local props = {}
	local H = Places.ARENA_HALF - 14

	local function onPath(p, pad)
		pad = pad or 0
		if math.abs(p.X) < Places.PATH_W / 2 + pad or math.abs(p.Z) < Places.PATH_W / 2 + pad then return true end
		local r = math.sqrt(p.X * p.X + p.Z * p.Z)
		if math.abs(r - Places.RING_R) < 11 + pad then return true end
		return false
	end
	local function clear(p, r)
		if math.abs(p.X) > H - r or math.abs(p.Z) > H - r then return false end
		if (p.X * p.X + p.Z * p.Z) < (55 + r) ^ 2 then return false end -- open middle for spawning
		for _, q in props do
			local d = V(p.X - q.pos.X, 0, p.Z - q.pos.Z).Magnitude
			if d < r + (q.clear or q.r or 4) + 4 then return false end
		end
		return true
	end
	local function add(kind, p, yaw, size, r, extra)
		local pr = { kind = kind, pos = V(p.X, 0, p.Z), yaw = yaw or 0, size = size, r = r or 0 }
		for k, v in extra or {} do pr[k] = v end
		pr.clear = pr.clear or math.max(pr.r, math.max(size.X, size.Z) / 2)
		table.insert(props, pr)
		return pr
	end
	local function scatter(kind, n, sizeFn, r, extra, onPathOk, tries)
		for _ = 1, n do
			for _ = 1, tries or 40 do
				local p = V(rng:NextNumber(-H, H), 0, rng:NextNumber(-H, H))
				local size = sizeFn()
				local fr = math.max(size.X, size.Z) / 2
				if (onPathOk or not onPath(p, fr)) and clear(p, fr) then
					add(kind, p, rng:NextNumber(0, math.pi * 2), size, r and r(size) or 0, extra)
					break
				end
			end
		end
	end

	-- benches facing the cross paths, picnic tables on the grass
	for _, spot in { V(-60, 0, 24), V(60, 0, -24), V(-130, 0, -24), V(130, 0, 24), V(24, 0, 80), V(-24, 0, -90), V(24, 0, -150), V(-24, 0, 150) } do
		local alongX = math.abs(spot.Z) < 40
		local yaw = alongX and (spot.Z > 0 and math.pi or 0) or (spot.X > 0 and -math.pi / 2 or math.pi / 2)
		add("bench", spot, yaw, V(36, 12, 10), 20, { shelter = true, clear = 19 })
	end
	-- agility course (north-east field)
	add("tunnel", V(110, 0, 120), math.pi / 4, V(14, 14, 44), 24, { shelter = true, clear = 24 })
	add("aframe", V(150, 0, 80), 0, V(18, 16, 40), 22, { clear = 22 })
	add("weave", V(80, 0, 165), math.pi / 2, V(4, 12, 50), 0, { clear = 26 })
	add("hurdle", V(160, 0, 150), 0.3, V(24, 9, 3), 0, { clear = 13 })
	add("hurdle", V(135, 0, 175), 0.6, V(24, 9, 3), 0, { clear = 13 })
	-- a pond (south-west) with a puddle rim
	add("pond", V(-140, 0, -130), 0, V(70, 1, 54), 38, { clear = 40 })

	scatter("tree", 13, function() local d = rng:NextNumber(9, 14) return V(d, rng:NextNumber(80, 110), d) end, function(s) return s.X / 2 + 5 end)
	scatter("picnic", 4, function() return V(40, 18, 30) end, function() return 24 end, { shelter = true })
	scatter("bush", 12, function() local d = rng:NextNumber(16, 26) return V(d, rng:NextNumber(10, 14), d * rng:NextNumber(0.8, 1.2)) end, function(s) return s.X / 2 + 3 end, { bush = true })
	scatter("rock", 9, function() local d = rng:NextNumber(6, 16) return V(d, d * rng:NextNumber(0.5, 0.8), d * rng:NextNumber(0.8, 1.3)) end, function(s) return s.X > 11 and s.X / 2 + 3 or 0 end)
	scatter("hydrant", 5, function() return V(6, 13, 6) end, function() return 6 end)
	scatter("trash", 5, function() return V(10, 17, 10) end, function() return 8 end, nil, false)
	scatter("sign", 4, function() return V(14, 26, 2) end, function() return 3 end)
	scatter("log", 6, function() return V(5, 5, rng:NextNumber(24, 36)) end)
	scatter("branch", 8, function() return V(2.2, 2.2, rng:NextNumber(18, 30)) end)
	scatter("puddle", 7, function() local d = rng:NextNumber(14, 26) return V(d, 0.3, d * rng:NextNumber(0.6, 1)) end, nil, { puddle = true }, true)
	scatter("bowl", 6, function() return V(10, 3.2, 10) end)
	scatter("ball", 10, function() return V(5, 5, 5) end, nil, nil, true)
	scatter("frisbee", 5, function() return V(10, 0.9, 10) end, nil, nil, true)
	scatter("bone", 5, function() return V(3, 3, 11) end, nil, nil, true)
	scatter("rope", 3, function() return V(3, 3, 14) end, nil, nil, true)

	-- sprinkler heads (they pop up during the "sprinklers" event)
	Places.Sprinklers = { V(-95, 0, 70), V(95, 0, -80), V(-60, 0, -175), V(175, 0, 30) }
	layoutCache = props
	return props
end

-- things the park AI steers around (props with r > 0)
function Places.arenaObstacles()
	local out = {}
	for _, p in Places.arenaLayout() do
		if p.r > 0 then table.insert(out, p) end
	end
	return out
end

-- is this (arena-relative) point under a shelter / in a bush?
function Places.coverAt(p)
	for _, q in Places.arenaLayout() do
		if q.shelter or q.bush then
			local l = CFrame.new(q.pos) * CFrame.Angles(0, q.yaw, 0)
			local o = l:PointToObjectSpace(V(p.X, 0, p.Z))
			local hx, hz = q.size.X / 2 - 1, q.size.Z / 2 - 1
			if q.bush then hx, hz = hx * 0.85, hz * 0.85 end
			if math.abs(o.X) < hx and math.abs(o.Z) < hz then
				return q.shelter and "shelter" or "bush"
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- DIFFICULTY ("Chaos Meter") for Dog Park Survival
---------------------------------------------------------------------------
Places.ParkTiers = {
	{ name = "QUIET PARK", from = 0, color = Color3.fromRGB(150, 205, 140) },
	{ name = "BUSY PARK", from = 30, color = Color3.fromRGB(245, 196, 80) },
	{ name = "CROWDED PARK", from = 60, color = Color3.fromRGB(255, 150, 90) },
	{ name = "CHAOS PARK", from = 120, color = Color3.fromRGB(255, 95, 95) },
}
function Places.parkTier(t)
	local tier = 1
	for i, d in Places.ParkTiers do
		if t >= d.from then tier = i end
	end
	return tier
end
-- 0..1 over the first 150s, then keeps creeping up (overtime)
function Places.chaos(t)
	if t <= 150 then
		local k = t / 150
		return k * k * (3 - 2 * k) * 0.35 + k * 0.65
	end
	return 1 + (t - 150) / 200
end

---------------------------------------------------------------------------
-- THROWN THINGS (same maths on server + client)
-- p = { kind = "ball"|"frisbee", from = Vector3 (y = hand height), to = Vector3 (y = 0), t0, T }
---------------------------------------------------------------------------
Places.BALL_R = 2.6
Places.ROLL_T = 1.3

-- position (arena-relative) and whether it can squash you right now
function Places.projAt(p, now)
	local k = (now - p.t0) / p.T
	local flat = V(p.to.X - p.from.X, 0, p.to.Z - p.from.Z)
	local dir = flat.Magnitude > 0.01 and flat.Unit or V(0, 0, 1)
	if p.kind == "frisbee" then
		if k < 0 then return nil end
		if k <= 1 then
			local pos = V(p.from.X, 0, p.from.Z):Lerp(V(p.to.X, 0, p.to.Z), k)
			-- glides flat, then drops and skids along the grass for the last third
			local h = k < 0.62 and p.from.Y + math.sin(k / 0.62 * math.pi) * 5 or math.max(1.2, p.from.Y * (1 - (k - 0.62) / 0.3))
			return pos + V(0, h, 0), h < 4.5, dir
		end
		local after = now - (p.t0 + p.T)
		if after < 0.6 then
			local slide = 22 * after * (1 - after / 1.2)
			return V(p.to.X, 1, p.to.Z) + dir * slide, after < 0.35, dir
		end
		return V(p.to.X, 0.6, p.to.Z) + dir * 6.6, false, dir, true
	end
	-- ball: parabolic lob, then a short roll
	if k < 0 then return nil end
	if k <= 1 then
		local pos = V(p.from.X, 0, p.from.Z):Lerp(V(p.to.X, 0, p.to.Z), k)
		local h = p.from.Y * (1 - k) + Places.BALL_R * k + math.sin(math.pi * k) * (p.arc or 26)
		return pos + V(0, h, 0), k > 0.93, dir
	end
	local after = now - (p.t0 + p.T)
	local roll = math.min(after, Places.ROLL_T)
	local v0 = p.roll or 34
	local d = v0 * roll - v0 / (2 * Places.ROLL_T) * roll * roll
	local bounce = after < 0.5 and math.abs(math.sin(after * 9)) * 3 * (1 - after / 0.5) or 0
	return V(p.to.X, Places.BALL_R + bounce, p.to.Z) + dir * d, after < Places.ROLL_T * 0.7, dir, after >= Places.ROLL_T
end

return Places
