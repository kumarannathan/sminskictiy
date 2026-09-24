-- INVENTORY CURATION (Studio command bar, Edit mode). Re-runnable.
--
-- Turns the raw marketplace models the owner inserted into
-- ReplicatedStorage.SminskiAssets.Inventory (Inv_*) into clean, named
-- templates the city builds from -- then deletes the raw inserts, because
-- ReplicatedStorage is sent to every client and the raw set was ~90,000
-- parts (three supermarkets alone were 16k / 23k / 37k).
--
-- WHAT "CLEAN" MEANS HERE (.claude/rules/assets.md review list):
--   * no scripts of any kind -- the Sakura tree shipped with a fake
--     "model corruption, paste this code" backdoor; McDonald's with
--     day/night light scripts. Nothing from the marketplace runs code here.
--   * no Lights, Sounds or ParticleEmitters -- the city pools its own
--     lights (performance.md), and 27 PointLights in one restaurant is not
--     a thing this game does
--   * anchored, and NOT collidable by default: colliders are added by the
--     kit where a thing must be solid (a trunk, a building's walls)
--   * pivot at the bottom-centre of the bounding box, so PivotTo(ground)
--     stands it on the pavement; H / W attributes carry its native size so
--     the kit can scale it to the slot it goes in
--
-- Provenance is kept as attributes (AssetId, Creator) on every template.
-- The owner picked these assets and is the review gate for them; nothing
-- here touches the Blender-built Props path.

local RS = game:GetService("ReplicatedStorage")
local assets = RS:WaitForChild("SminskiAssets")
local inv = assets:WaitForChild("Inventory")
local report = {}
local function say(s) table.insert(report, s) end

local function bbox(m)
	local lo, hi
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, h = d.CFrame, d.Size / 2
			for _, a in { -1, 1 } do for _, b in { -1, 1 } do for _, c in { -1, 1 } do
				local p = cf * Vector3.new(a * h.X, b * h.Y, c * h.Z)
				lo = lo and Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z)) or p
				hi = hi and Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z)) or p
			end end end
		end
	end
	return lo, hi
end

-- strip everything that is not geometry, then normalise the parts
local function clean(m, keepDecals)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("Sound") or d:IsA("ParticleEmitter")
			or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
			or d:IsA("Camera") or d:IsA("Constraint") or d:IsA("BodyMover") or d:IsA("ClickDetector")
			or d:IsA("ProximityPrompt") or d:IsA("Seat") or (not keepDecals and (d:IsA("Decal") or d:IsA("Texture")))
			or d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ValueBase") then
			d:Destroy()
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Massless = true
		end
	end
end

-- a template: cloned out of a raw insert, cleaned, pivoted at its feet
local made = {}
local function template(src, name, opts)
	opts = opts or {}
	if not src then say("  MISSING source for " .. name) return nil end
	local m = src:Clone()
	m.Name = name
	if m:IsA("BasePart") then
		local holder = Instance.new("Model")
		holder.Name = name
		m.Parent = holder
		m = holder
	elseif m:IsA("Folder") then
		-- some packs arrive as a Folder; a Folder has no pivot, a Model does
		local holder = Instance.new("Model")
		holder.Name = name
		for _, c in ipairs(m:GetChildren()) do c.Parent = holder end
		m:Destroy()
		m = holder
	end
	clean(m, opts.keepDecals)
	if opts.prune then opts.prune(m) end
	local lo, hi = bbox(m)
	if not lo then say("  EMPTY " .. name) m:Destroy() return nil end
	local size = hi - lo
	-- NO PRIMARYPART. With one set, a Model's pivot is that part's pivot and
	-- assigning WorldPivot only adjusts its offset -- the first run left a
	-- beech's pivot 10.8 studs up its trunk. Clearing it makes WorldPivot the
	-- stored value, verified afterwards: pivot y == lowest vertex y.
	m.PrimaryPart = nil
	m.WorldPivot = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	if math.abs(m:GetPivot().Position.Y - lo.Y) > 0.05 then say("  PIVOT OFF: " .. name) end
	m:SetAttribute("H", size.Y)
	m:SetAttribute("W", math.max(size.X, size.Z))
	m:SetAttribute("SizeX", size.X)
	m:SetAttribute("SizeZ", size.Z)
	if opts.assetId then m:SetAttribute("AssetId", opts.assetId) end
	if opts.creator then m:SetAttribute("Creator", opts.creator) end
	local old = inv:FindFirstChild(name)
	if old then old:Destroy() end
	m.Parent = inv
	local n = 0
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
	made[name] = n
	say(string.format("  %-14s %3d parts  %.0fx%.0fx%.0f", name, n, size.X, size.Y, size.Z))
	return m
end

local function child(root, name, nth)
	local k = 0
	for _, c in ipairs(root:GetChildren()) do
		if c.Name == name then
			k += 1
			if k == (nth or 1) then return c end
		end
	end
	return nil
end
local function childLike(root, pattern, nth)
	local k = 0
	for _, c in ipairs(root:GetChildren()) do
		if string.find(c.Name, pattern, 1, true) then
			k += 1
			if k == (nth or 1) then return c end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- TREES  (Nature Package // 2023 by CeIestialAurum, 12996952219; Sakura by
-- IvyDr8ewGaming25sage, 138990875351757). The deciduous meshes carry no
-- texture, so the kit can tint them to the project palette.
---------------------------------------------------------------------------
say("TREES")
local nature = inv:FindFirstChild("Inv_NaturePack")
nature = nature and nature:FindFirstChild("Model")
if nature then
	local NP = { assetId = "12996952219", creator = "CeIestialAurum" }
	template(nature:FindFirstChild("BeechwoodTreeVar0"), "Tree_Beech_S", NP)
	template(nature:FindFirstChild("BeechwoodTreeVar1"), "Tree_Beech_M", NP)
	template(nature:FindFirstChild("BeechwoodTreeVar2"), "Tree_Beech_L", NP)
	template(nature:FindFirstChild("BroadLeafTreeVar0"), "Tree_Broadleaf", NP)
	template(nature:FindFirstChild("MapleLeafTreeVar0"), "Tree_Maple", NP)
	template(nature:FindFirstChild("DogWoodTreeVar0"), "Tree_Dogwood", NP)
	template(nature:FindFirstChild("PineTreeVar0"), "Tree_Pine", NP)
	template(nature:FindFirstChild("RedwoodTreeVar0"), "Tree_Redwood_S", NP)
	template(nature:FindFirstChild("RedwoodTreeVar1"), "Tree_Redwood_M", NP)
	template(nature:FindFirstChild("Flower_Plant_B"), "Flower", NP)
	template(nature:FindFirstChild("CloverPatch"), "Clover", NP)
	template(nature:FindFirstChild("GrassBunch_1"), "Grass", NP)
	template(nature:FindFirstChild("HerbBunch1"), "Herb", NP)
end
local sak = inv:FindFirstChild("Inv_SakuraTree")
if sak then template(sak, "Tree_Sakura", { assetId = "138990875351757", creator = "IvyDr8ewGaming25sage" }) end

---------------------------------------------------------------------------
-- FARM  (Low Poly Farm Pack (Remake), RedWood Roleplay GROUP, 8510928279)
---------------------------------------------------------------------------
say("FARM")
local farm = inv:FindFirstChild("Inv_FarmPack")
farm = farm and farm:FindFirstChild("Ungroup")
if farm then
	local FP = { assetId = "8510928279", creator = "RedWood Roleplay GROUP", keepDecals = true }
	local barns = child(farm, "Barns")
	template(barns and child(barns, "Model", 1), "Barn_A", FP)
	template(barns and child(barns, "Model", 2), "Barn_B", FP)
	local silos = child(farm, "Silos")
	template(silos and child(silos, "Model", 1), "Silo_A", FP)
	template(silos and child(silos, "Model", 2), "Silo_B", FP)
	template(childLike(farm, "Water Tower"), "WaterTower", FP)
	local gh = child(farm, "Green Houses")
	template(gh and child(gh, "Model", 1), "Greenhouse_A", FP)
	template(gh and child(gh, "Model", 2), "Greenhouse_B", FP)
	local veh = child(farm, "Vehicles")
	if veh then
		template(child(veh, "Tractor Old"), "Tractor", FP)
		template(child(veh, "Pickup Truck"), "Pickup", FP)
		template(childLike(veh, "Trailer Tank"), "Trailer", FP)
		template(childLike(veh, "Plough"), "Plough", FP)
	end
	local props = child(farm, "Props")
	if props then
		template(childLike(props, "Hay_Bale_Ro"), "HayRound", FP)
		template(childLike(props, "Hay_Bale_Sq"), "HaySquare", FP)
		template(childLike(props, "Hay_Pile"), "HayPile", FP)
		template(childLike(props, "Wheelbarrow"), "Wheelbarrow", FP)
		template(childLike(props, "Chicken_Coo"), "ChickenCoop", FP)
		template(childLike(props, "Beehive_02"), "Beehive", FP)
		template(childLike(props, "Trough"), "Trough", FP)
		template(childLike(props, "Wood_Stack"), "WoodStack", FP)
		template(childLike(props, "Barrel_02"), "Barrel", FP)
		-- the well is two loose meshes; group them
		local well = Instance.new("Model")
		for _, c in ipairs(props:GetChildren()) do
			if string.find(c.Name, "Well_01", 1, true) then c:Clone().Parent = well end
		end
		if #well:GetChildren() > 0 then template(well, "Well", FP) end
		well:Destroy()
	end
	local det = child(farm, "Details")
	if det then
		template(childLike(det, "ProduceStand"), "ProduceStand", FP)
		template(childLike(det, "Shelter"), "Shelter", FP)
	end
	local crates = child(farm, "Crates")
	if crates then
		local k = 0
		for _, c in ipairs(crates:GetChildren()) do
			k += 1
			template(c, "Crate_" .. k, FP)
		end
	end
	local foods = child(farm, "Foods")
	if foods then
		for i, nm in { "Pumpkin_01", "Watermelon_", "Corn_01", "Apple_01", "Cabbage_01_", "Tomato_01", "Carrot_01", "Lettuce_01_" } do
			template(childLike(foods, nm), "Food_" .. i, FP)
		end
	end
end

---------------------------------------------------------------------------
-- PLAZA  (Mexico Colima City Park, captainnoe42, 12396863735)
-- Its 46 lamp posts (690 parts, 46 lights) go: the kit's K.lamp draws lamps
-- that join the night light pool. Its parts are recoloured to the city's
-- pavement and lawn so the plaza sits in the palette instead of on it.
---------------------------------------------------------------------------
say("PLAZA")
local plaza = inv:FindFirstChild("Inv_Plaza")
plaza = plaza and plaza:FindFirstChild("Model")
if plaza then
	local PAVE, JOINT, GRASS = Color3.fromRGB(198, 198, 192), Color3.fromRGB(176, 176, 170), Color3.fromRGB(134, 172, 100)
	local lampSpots = {}
	template(plaza, "Plaza", { assetId = "12396863735", creator = "captainnoe42", keepDecals = false, prune = function(m)
		local lo, hi = bbox(m)
		local c = (lo + hi) / 2
		for _, d in ipairs(m:GetChildren()) do
			if d:IsA("Model") and d.Name == "Model" then
				local l, h = bbox(d)
				if l then
					local p = (l + h) / 2 - c
					table.insert(lampSpots, string.format("%.0f,%.0f", p.X, p.Z))
				end
				d:Destroy()
			elseif d:IsA("BasePart") then
				-- the two vertical slabs standing at the centre are unknown
				-- monument geometry; nothing in the city wants a 72-stud wall
				if d.Size.Y > 20 and d.Size.X < 2 then d:Destroy()
				else
					local grass = d.Material == Enum.Material.Grass
					if grass then d.Color = GRASS
					elseif d.Color.R < 0.5 then d.Color = JOINT
					else d.Color = PAVE end
					d.Material = Enum.Material.SmoothPlastic
					-- FLAT. As authored the paving stood 1.0 and the lawn 1.9
					-- above ground: a mesa you waded through, since it has no
					-- collision. Every slab becomes 0.24 thick on the ground
					-- (the lawn a hair higher so it draws over the paving), and
					-- K.place sinks the whole plaza so the tops are flush with
					-- the pavement -- a floor you walk ON, at the right height.
					if d.Size.Y <= 2 and math.max(d.Size.X, d.Size.Z) >= 5 then
						d.Size = Vector3.new(d.Size.X, 0.24, d.Size.Z)
						d.CFrame = CFrame.new(d.Position.X, lo.Y + 0.12 + (grass and 0.02 or 0), d.Position.Z) * (d.CFrame - d.CFrame.Position)
					end
				end
			end
		end
		-- the "Realistic Tree" bodies are untextured: tint to the leaf palette
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("MeshPart") and d.Name == "Body" then d.Color = Color3.fromRGB(122, 196, 98) end
		end
	end })
	local t = inv:FindFirstChild("Plaza")
	if t then t:SetAttribute("LampSpots", table.concat(lampSpots, ";")) end
end

---------------------------------------------------------------------------
-- McDONALD'S  (McDonald's Restaurant, BlueNebula10, 4572305378)
-- Decals stay (menu boards, the logo). Its authored wall collision is
-- restored by the kit when it is placed, not here.
---------------------------------------------------------------------------
say("MCDONALDS")
local mcd = inv:FindFirstChild("Inv_McDonalds")
mcd = mcd and mcd:FindFirstChild("McDonald's")
if mcd then
	local t = template(mcd, "McDonalds", { assetId = "4572305378", creator = "BlueNebula10", keepDecals = true, prune = function(m)
		-- THE WAY IN. MEASURED: the storefront is seventeen glass panels
		-- (WindowGlass, 1 x 7 x 3.4) on a diagonal V whose apex -- the door
		-- frame -- is at (+7.6, -34.4) from the centre; the panels are the
		-- doors, there is no gap. The kit would make them solid with the
		-- walls, which sealed the restaurant on the first placement. The four
		-- panels past z = -30 (the apex) are marked Pass, and K.place leaves
		-- Pass parts walk-through: a ten-stud opening where the doors are.
		local lo, hi = bbox(m)
		local c = (lo + hi) / 2
		local n = 0
		for _, d in ipairs(m:GetDescendants()) do
			-- the panels, and the thin frame posts between them (1 x 7 x 0.2):
			-- one post stands exactly on the apex and blocked the straight
			-- walk in even with the glass open
			local thin = d:IsA("BasePart") and math.min(d.Size.X, d.Size.Y, d.Size.Z) <= 1.2
			if d:IsA("BasePart") and (d.Transparency > 0.3 or thin) then
				local q = d.Position
				if q.Z < c.Z - 30 and q.Y - lo.Y < 9 then
					d:SetAttribute("Pass", true)
					n += 1
				end
			end
		end
		m:SetAttribute("PassParts", n)
	end })
	if t then
		-- which way is the front? the wordmark sits over the entrance
		local lo, hi = bbox(t)
		local c = (lo + hi) / 2
		local wm = t:FindFirstChild("Wordmark", true)
		if wm and wm:IsA("BasePart") then
			local p = wm.Position - c
			t:SetAttribute("Front", string.format("%.1f,%.1f", p.X, p.Z))
		end
		-- remember which parts were solid when authored, so the kit can put
		-- collision back on walls / counters without making food collidable
		local n = 0
		for _, d in ipairs(mcd:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide and d.Size.Magnitude > 3 then n += 1 end
		end
		t:SetAttribute("SolidParts", n)
	end
end

---------------------------------------------------------------------------
-- STORE FITTINGS  (Grocery store shelves kit (PBR) by Hifiveghostie5,
-- 11648470593; 7/11 Cashier by POS | Prinz's Outfit Shop, 11258932706;
-- cashier register by NOOBGAMERTH009, 5179753997; Store Shelf with Food by
-- Runealix73, 72888068757390). The Grocery Store building (880723024) is
-- NOT used: its interior is one solid 47 x 25 x 52 block, so it cannot be
-- walked into. The NPC Dialogue System (80608769509945) is a script kit;
-- nothing from the marketplace runs code here, and the game's own prompt
-- card already carries the keeper's lines.
---------------------------------------------------------------------------
say("STORE")
local kit = inv:FindFirstChild("Inv_ShelvesKit")
if kit then
	local KP = { assetId = "11648470593", creator = "Hifiveghostie5" }
	template(kit:FindFirstChild("Tall shelf", true), "ShelfTall", KP)
	template(kit:FindFirstChild("Shelf", true), "ShelfShort", KP)
end
local c7 = inv:FindFirstChild("Inv_Cashier711")
if c7 then template(c7, "Cashier", { assetId = "11258932706", creator = "POS | Prinz's Outfit Shop", keepDecals = true }) end
local reg = inv:FindFirstChild("Inv_Register")
if reg then template(reg, "Register", { assetId = "5179753997", creator = "NOOBGAMERTH009" }) end
local sf = inv:FindFirstChild("Inv_ShelfFood")
if sf then template(sf, "ShelfFood", { assetId = "72888068757390", creator = "Runealix73" }) end
for _, nm in { "Inv_FoodsDrinks", "Inv_LightMartFoods" } do
	local fp = inv:FindFirstChild(nm)
	if fp then template(fp, nm == "Inv_FoodsDrinks" and "FoodPack_A" or "FoodPack_B", { keepDecals = true }) end
end

---------------------------------------------------------------------------
-- RESTAURANT ROW (docs/TYCOON.md). Two tycoon kits from the owner's
-- inventory, inserted into ServerStorage as Inv_TycoonKit (blackbot008's
-- re-upload of berezaa's Tycoon Kit, 233368931: 82 parts, 12 scripts) and
-- Inv_PizzaTycoonKit (bulderman1's pizza hut tycoon kit, 34943877: 1,507
-- parts, 331 scripts). What they contribute is the VOCABULARY -- a pad with
-- a price, a gate you claim, a collector, things that appear when bought --
-- and CityTycoon implements that in the game's own kit. What is copied out
-- as geometry: the pad (a 4x0.2x4 cylinder) and, from the pizza kit, the
-- appliances a piece can stand as (Config.Tycoon.Pieces[].model): oven,
-- stove, fridge, sink, soda machine, fries maker, a cashier desk. Every
-- one of them is 2010 plastic and reads as a placeholder next to the
-- Blender props; they exist so a bought piece is SOMETHING on day one, and
-- the owner swaps them for their own decor by keeping the template names.
-- The Humanoid name tags, the ClickDetectors and all 343 scripts go.
---------------------------------------------------------------------------
say("TYCOON")
local SS = game:GetService("ServerStorage")
local tk = SS:FindFirstChild("Inv_TycoonKit") or inv:FindFirstChild("Inv_TycoonKit")
if tk then
	local TK = { assetId = "233368931", creator = "blackbot008" }
	local tycoon = tk:FindFirstChild("Tycoons", true)
	local blue = tycoon and tycoon:FindFirstChildOfClass("Model")
	local buttons = blue and blue:FindFirstChild("Buttons")
	local btn = buttons and buttons:FindFirstChildOfClass("Model")
	local head = btn and btn:FindFirstChild("Head")
	if head then
		template(head, "TycoonPad", { assetId = TK.assetId, creator = TK.creator, prune = function(m)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("Humanoid") then d:Destroy() end
			end
		end })
	end
end
local pk = SS:FindFirstChild("Inv_PizzaTycoonKit") or inv:FindFirstChild("Inv_PizzaTycoonKit")
if pk then
	local PK = { assetId = "34943877", creator = "bulderman1", keepDecals = true }
	local fac = pk:FindFirstChild("Factory", true)
	local function noTags(m)
		-- the kit labels things with Humanoid name tags on 2x1x1 heads;
		-- those and any R6 "customer" dummies are not furniture
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Humanoid") then
				local dummy = d.Parent
				if dummy and dummy:FindFirstChild("Torso") then dummy:Destroy() else d:Destroy() end
			end
		end
	end
	PK.prune = noTags
	if fac then
		for src, name in pairs({ ove = "Tyc_Oven", sto = "Tyc_Stove", ref = "Tyc_Fridge", sink = "Tyc_Sink", sm = "Tyc_Soda", fm = "Tyc_Fryer", c1 = "Tyc_Cashier" }) do
			local piece = fac:FindFirstChild(src)
			if piece then template(piece, name, PK) else say("  MISSING pizza kit piece " .. src) end
		end
	end
end
-- the kits themselves go: 4,900 instances of scripts and name tags in the
-- place file, and ServerStorage is not sent to clients but is saved
for _, nm in { "Inv_TycoonKit", "Inv_PizzaTycoonKit" } do
	local raw = SS:FindFirstChild(nm)
	if raw then raw:Destroy() say("  removed ServerStorage." .. nm) end
end

---------------------------------------------------------------------------
-- DELETE THE RAW INSERTS. Everything usable has been copied out.
---------------------------------------------------------------------------
local removed, removedParts = {}, 0
for _, c in ipairs(inv:GetChildren()) do
	if string.sub(c.Name, 1, 4) == "Inv_" then
		for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then removedParts += 1 end end
		table.insert(removed, c.Name)
		c:Destroy()
	end
end
say(string.format("REMOVED %d raw inserts (%d parts): %s", #removed, removedParts, table.concat(removed, ", ")))
local total = 0
for _, n in pairs(made) do total += n end
say(string.format("KEPT %d templates, %d parts total, in ReplicatedStorage.SminskiAssets.Inventory", (function() local k = 0 for _ in pairs(made) do k += 1 end return k end)(), total))
return table.concat(report, "\n")
