local T = workspace.Terrain
local C = Vector3.new(12000, 0, 0)
local function V(x, y, z) return C + Vector3.new(x, y, z) end
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

T:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(246, 228, 180))
return "bay ok"
