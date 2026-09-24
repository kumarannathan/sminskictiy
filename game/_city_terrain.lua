-- Sminski City terrain (run once in Studio edit mode, then save the place).
-- A green valley floor, a ring of foothills round the town, and two huge
-- mountain ranges east + west with rocky shoulders and snowy peaks.
-- The town itself (x/z within +-1000 of CITY) is left flat and empty.
local T = workspace.Terrain
local C = Vector3.new(12000, 0, 0)
local G, R, S, L, Mud = Enum.Material.Grass, Enum.Material.Rock, Enum.Material.Snow, Enum.Material.LeafyGrass, Enum.Material.Ground
local rng = Random.new(20260919)
local function V(x, y, z) return C + Vector3.new(x, y, z) end

-- wipe anything from an earlier run (the place has no other terrain)
T:Clear()

-- valley floor (top at y = -2; the town's own ground sits just above it)
for i = -4, 4 do
	for j = -4, 4 do
		T:FillBlock(CFrame.new(V(i * 1000, -26, j * 1000)), Vector3.new(1000, 48, 1000), G)
	end
end
-- a slightly different green in wide soft patches outside town
for _ = 1, 40 do
	local a = rng:NextNumber(0, math.pi * 2)
	local d = rng:NextNumber(1150, 3800)
	T:FillBall(V(math.cos(a) * d, -40, math.sin(a) * d), rng:NextNumber(60, 140), L)
end

-- foothills: a ring of soft hills just outside the fence (never inside town)
local function hill(x, z, r, y, mat)
	-- keep the hill's footprint (at y = 0) outside the town square
	local foot = math.sqrt(math.max(0, r * r - y * y))
	if math.max(math.abs(x), math.abs(z)) - foot < 1012 then return end
	T:FillBall(V(x, y, z), r, mat or G)
end
for k = 0, 71 do
	local a = k / 72 * math.pi * 2
	for ring = 0, 2 do
		local d = 1260 + ring * 220 + rng:NextNumber(-40, 40)
		local r = rng:NextNumber(170, 260) + ring * 40
		-- square-ish ring that hugs the town's square edge
		local x, z = math.cos(a), math.sin(a)
		local m = math.max(math.abs(x), math.abs(z))
		hill(x / m * d, z / m * d, r, -r * rng:NextNumber(0.45, 0.7))
	end
end

-- the tunnel hill at the south gate (the tunnel mouth faces the town)
T:FillBall(V(0, -40, -1150), 160, G)
T:FillBall(V(-60, -20, -1180), 120, G)
T:FillBall(V(70, -30, -1170), 120, G)
T:FillBall(V(0, 4, -1022), 26, R)

-- a mountain: grassy base, rocky shoulders, snowy peak
local function mountain(x, z, r, y0)
	r = math.min(r, 800) -- a single FillBall tops out a little under r = 1000
	T:FillBall(V(x, y0, z), r, G)
	T:FillBall(V(x + rng:NextNumber(-0.1, 0.1) * r, y0 + r * 0.55, z + rng:NextNumber(-0.1, 0.1) * r), r * 0.62, R)
	local px, pz = x + rng:NextNumber(-0.08, 0.08) * r, z + rng:NextNumber(-0.08, 0.08) * r
	T:FillBall(V(px, y0 + r * 0.98, pz), r * 0.36, R)
	T:FillBall(V(px, y0 + r * 1.12, pz), r * 0.26, S)
	-- rocky outcrops on the flanks
	for _ = 1, 4 do
		local a = rng:NextNumber(0, math.pi * 2)
		T:FillBall(V(x + math.cos(a) * r * 0.7, y0 + r * 0.45, z + math.sin(a) * r * 0.7), r * rng:NextNumber(0.12, 0.2), R)
	end
end

-- two ranges: east + west of town, the tallest peaks level with the centre
for _, sx in { -1, 1 } do
	for z = -4200, 4200, 420 do
		local centre = 1 - math.min(1, math.abs(z) / 3200)
		local r = 620 + centre * 380 + rng:NextNumber(-60, 60)
		mountain(sx * (2150 + rng:NextNumber(-120, 160)), z + rng:NextNumber(-80, 80), r, -r * 0.42)
		-- a second, taller range behind for depth
		local r2 = 800 + centre * 300 + rng:NextNumber(-80, 80)
		mountain(sx * (3200 + rng:NextNumber(-150, 150)), z + 210 + rng:NextNumber(-80, 80), r2, -r2 * 0.3)
	end
end
-- the valley closes gently to the north and south with rolling ridges
for _, sz in { -1, 1 } do
	for x = -1800, 1800, 300 do
		local r = rng:NextNumber(300, 460)
		hill(x + rng:NextNumber(-60, 60), sz * (1750 + rng:NextNumber(-80, 80)), r, -r * 0.55)
		hill(x + 150, sz * (2400 + rng:NextNumber(-100, 100)), r * 1.3, -r * 0.6)
	end
end

-- a little mountain lake + river of water on the valley floor, north-east
T:FillBlock(CFrame.new(V(1500, -6, 1300)), Vector3.new(260, 12, 180), Enum.Material.Water)

T.WaterColor = Color3.fromRGB(110, 180, 220)
T.WaterTransparency = 0.6
T.WaterWaveSize = 0.08
T:SetMaterialColor(G, Color3.fromRGB(116, 170, 86))
T:SetMaterialColor(L, Color3.fromRGB(106, 158, 80))
T:SetMaterialColor(R, Color3.fromRGB(150, 142, 136))
T:SetMaterialColor(S, Color3.fromRGB(248, 250, 255))
-- THE BAY: the valley opens onto the sea to the north. Clear the ridges
-- there, lay a sandy beach + water between the two mountain ranges.
for i = -2, 2 do
	for j = 0, 5 do
		T:FillBlock(CFrame.new(V(i * 600, 400, 1320 + j * 600)), Vector3.new(600, 900, 600), Enum.Material.Air)
	end
end
for i = -2, 2 do
	for j = 0, 5 do
		T:FillBlock(CFrame.new(V(i * 600, -60, 1320 + j * 600)), Vector3.new(600, 60, 600), Enum.Material.Sand)
		T:FillBlock(CFrame.new(V(i * 600, -17, 1320 + j * 600)), Vector3.new(600, 26, 600), Enum.Material.Water)
	end
end
-- the shore right behind the boardwalk
for i = -2, 2 do
	T:FillBlock(CFrame.new(V(i * 440, -17, 1115)), Vector3.new(440, 26, 190), Enum.Material.Water)
	T:FillBlock(CFrame.new(V(i * 440, -40, 1115)), Vector3.new(440, 20, 190), Enum.Material.Sand)
end
for _, sx in { -1, 1 } do
	T:FillBlock(CFrame.new(V(sx * 1000, -10, 1030)), Vector3.new(200, 14, 50), Enum.Material.Sand)
end
-- rocky islands out in the bay
for _, p in { { -700, 2100, 120 }, { 500, 2600, 160 }, { 1100, 1900, 100 } } do
	T:FillBall(V(p[1], -40, p[2]), p[3], Enum.Material.Rock)
	T:FillBall(V(p[1], -40 + p[3] * 0.5, p[2]), p[3] * 0.6, Enum.Material.Grass)
end

-- carve the town square a little lower so the town's own ground never z-fights
for _, i in { -1, 1 } do
	for _, j in { -1, 1 } do
		T:FillBlock(CFrame.new(V(i * 506, 0, j * 506)), Vector3.new(1012, 16, 1012), Enum.Material.Air)
	end
end
return "terrain ok: " .. T:CountCells() .. " cells"
