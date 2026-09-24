-- CityHome (client): your own house in Sminski City.
--   * the server gives every player a house (player attribute CityHouse);
--     every assigned house gets a nameplate + a carport on its driveway
--   * walk up to the front door to go inside: a furnished home with things to
--     do (nap, snack, TV, sofa, wardrobe, piano, lamp, computer, bubble bath)
--   * drive onto your driveway to park at home; your car waits there next time
--   * first visit: a tutorial with a glowing path from the gate to your house
-- The interior lives 400 studs under the house (under the valley floor, out
-- of sight), so going in/out is a quick fade + hop.
--   deps: K, Build, Models, UI, Audio, ctx, Places, player, remote, earned,
--         City, S, H (City HUD table), gui

return function(deps)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local K, Build, Models, UI, Audio, ctx, Places = deps.K, deps.Build, deps.Models, deps.UI, deps.Audio, deps.ctx, deps.Places
	local player, City, S = deps.player, deps.City, deps.S
	local V, rgb = K.V, K.rgb
	local Cc = K.C
	local C = UI.C
	local part = Models.part
	local CITY = Places.CITY
	local camera = workspace.CurrentCamera
	local lots = Places.cityLots()
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL

	local Home = { inside = nil, sitting = nil, tut = nil }
	local decor = {} -- [lotIndex] = { m, owner }
	local interiors = {} -- [lotIndex] = { m, f, items }
	local HOUSE_W, HOUSE_D = 36, 26
	local IW, ID, IH = 64, 46, 20

	local function dirOf(lot) return V(math.sin(lot.face), 0, math.cos(lot.face)) end
	local function lotFrame(lot, y) return K.frameOf(lot.pos, lot.face, y) end
	-- where you stand to use the front door, and the driveway parking spot
	local function frontDoor(lot) return lot.pos + dirOf(lot) * (HOUSE_D / 2 + 3) end
	local function drivewayCF(lot) return lotFrame(lot) * CFrame.new(HOUSE_W / 2 + 6, -K.PAD_Y + 0.2, -HOUSE_D / 2 - 7) end
	local function myHouse() return player:GetAttribute("CityHouse") end
	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end
	local function flat(v) return V(v.X, 0, v.Z) end

	---------------------------------------------------------------------------
	-- NAMEPLATES + CARPORTS on every assigned house
	---------------------------------------------------------------------------
	local function buildDecor(i, owner)
		local lot = lots[i]
		local m = Instance.new("Model")
		m.Name = "HomeDecor"
		local f = lotFrame(lot)
		local mine = owner == player
		-- a carport over the driveway
		local cp = f * CFrame.new(HOUSE_W / 2 + 6, 0, -HOUSE_D / 2 - 7)
		for _, sx in { -4.6, 4.6 } do
			for _, sz in { -7, 7 } do part(m, V(0.7, 9, 0.7), cp * CFrame.new(sx, 4.5, sz), Cc.cream, MATTE) end
		end
		part(m, V(11, 0.7, 16), cp * CFrame.new(0, 9.2, 0), Cc.sage, MATTE)
		part(m, V(11.6, 0.4, 16.6), cp * CFrame.new(0, 9.7, 0), Cc.cream, MATTE)
		local pSign = part(m, V(2.4, 2.4, 0.2), cp * CFrame.new(-4.6, 7, -7.4), Cc.sage, MATTE)
		K.textOn(pSign, Enum.NormalId.Front, "P", Cc.cream, Vector2.new(80, 80))
		-- a welcome mat
		part(m, V(6, 0.12, 3), f * CFrame.new(0, 0.08, -HOUSE_D / 2 - 3), rgb(210, 160, 110), Enum.Material.Fabric)
		-- the nameplate above the roof
		local anchor = part(m, V(1, 1, 1), f * CFrame.new(0, 40, 0), Color3.new(), MATTE, { transparency = 1 })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(240, 58)
		bb.MaxDistance = mine and 1400 or 240
		bb.LightInfluence = 0
		bb.AlwaysOnTop = mine
		bb.Adornee = anchor
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1)
		pill.BackgroundColor3 = mine and rgb(250, 228, 150) or C.white
		pill.Parent = bb
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(1, 0) cr.Parent = pill
		local st = Instance.new("UIStroke") st.Thickness = 3 st.Color = Cc.sage st.Parent = pill
		UI.icon(pill, "house", { Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(6, 4), ZIndex = 2 })
		UI.text(pill, mine and "YOUR HOUSE" or (owner.DisplayName .. "'s House"), { Size = UDim2.new(1, -66, 1, 0), Position = UDim2.fromOffset(60, 0), Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = rgb(70, 130, 70), ZIndex = 2 })
		bb.Parent = anchor
		m.Parent = K.actors
		-- THE TRAVEL PAD: a ring set into the path by the front door. Step on
		-- it and you can jump to any of the city's main places, so a player
		-- who lives out in the houses is never a long walk from downtown.
		local pf = f * CFrame.new(-(HOUSE_W / 2 + 5), 0, -HOUSE_D / 2 - 4)
		part(m, V(11, 0.3, 11), pf * CFrame.new(0, 0.15, 0), Cc.cream, MATTE, { shape = Enum.PartType.Cylinder })
		local ring = part(m, V(9.4, 0.36, 9.4), pf * CFrame.new(0, 0.26, 0), K.C.mint or Cc.sage, Enum.Material.Neon, { shape = Enum.PartType.Cylinder })
		ring.CastShadow = false
		ring.Transparency = 0.25
		part(m, V(6.2, 0.4, 6.2), pf * CFrame.new(0, 0.3, 0), Cc.cream, MATTE, { shape = Enum.PartType.Cylinder })
		-- YOUR door stands open with a green mat; a neighbour's stays shut. You
		-- can tell your own house from across the street.
		if mine then
			local fd = lotFrame(lot) * CFrame.new(0, 0, -HOUSE_D / 2 - 0.4)
			part(m, V(9, 0.16, 5), fd * CFrame.new(0, K.PAD_Y + 0.08, -2.6), K.OPEN, Enum.Material.Fabric, { noShadow = true })
			part(m, V(7.4, 0.2, 3.8), fd * CFrame.new(0, K.PAD_Y + 0.1, -2.6), K.tint(K.OPEN, 0.3), Enum.Material.Fabric, { noShadow = true })
			-- IN FRONT OF THE SHUT LEAF, AND WARM RATHER THAN INK. CityBuild builds
			-- its own closed door on every house and we cannot remove it from here,
			-- so this panel sat BEHIND it and never showed: your own house advertised
			-- itself as open with folded leaves either side of a shut door. The leaf's
			-- front face is at local z -0.25, so -0.45 covers it. Ink is also wrong --
			-- a near-black panel in a doorway reads as a shut door, which is the whole
			-- reason the dark fills came out of K.openDoor.
			local hall = part(m, V(5.4, 8.6, 0.4), fd * CFrame.new(0, 4.5, -0.45), rgb(124, 106, 92), MATTE)
			hall.CastShadow = false
			for _, sx in { -1, 1 } do
				part(m, V(2.4, 8.4, 0.35), fd * CFrame.new(sx * 3.6, 4.4, -1.2) * CFrame.Angles(0, sx * 1.2, 0), rgb(250, 214, 110), MATTE)
			end
		end
		decor[i] = { m = m, owner = owner, pad = pf.Position }
	end
	local scanT = 0
	local function scanOwners(dt)
		scanT -= dt
		if scanT > 0 then return end
		scanT = 1
		local seen = {}
		for _, p in Players:GetPlayers() do
			local i = p:GetAttribute("CityHouse")
			if i and lots[i] then
				seen[i] = true
				if not decor[i] or decor[i].owner ~= p then
					if decor[i] then decor[i].m:Destroy() end
					buildDecor(i, p)
				end
			end
		end
		for i, d in decor do
			if not seen[i] then
				d.m:Destroy()
				decor[i] = nil
			end
		end
	end

	---------------------------------------------------------------------------
	-- THE INTERIOR
	---------------------------------------------------------------------------
	local fadeGui = Instance.new("ScreenGui")
	fadeGui.Name = "SminskiHomeFade"
	fadeGui.IgnoreGuiInset = true
	fadeGui.DisplayOrder = 30
	fadeGui.ResetOnSpawn = false
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = rgb(40, 48, 44)
	fade.BackgroundTransparency = 1
	fade.Parent = fadeGui
	local function fadeTo(a, t)
		fadeGui.Parent = deps.gui.Parent
		TweenService:Create(fade, TweenInfo.new(t or 0.25), { BackgroundTransparency = a }):Play()
		task.wait(t or 0.25)
	end

	local function buildInterior(i)
		if interiors[i] then return interiors[i] end
		local lot = lots[i]
		local f = lotFrame(lot, -400)
		local m = Instance.new("Model")
		m.Name = "HomeInterior"
		local keep = K.cur
		K.cur = m
		local P, solidP = K.P, function(p) p.CanCollide = true p.CanQuery = true return p end
		local items = {}
		local wall, wains, floorC = rgb(252, 246, 226), Cc.mint, rgb(214, 170, 120)
		-- shell: floor, walls with a sage wainscot, ceiling
		solidP(P(V(IW, 1, ID), f * CFrame.new(0, -0.5, 0), floorC, Enum.Material.WoodPlanks))
		solidP(P(V(IW + 2, 1, ID + 2), f * CFrame.new(0, IH + 0.5, 0), rgb(250, 248, 240)))
		-- side walls are plain; the front + back walls have real window holes
		local function trimRow(size, x, z)
			P(V(size.X, 6, size.Z), f * CFrame.new(x, 3, z), wains)
			P(V(size.X, 0.5, size.Z), f * CFrame.new(x, 6.2, z), Cc.cream)
		end
		for _, sx in { -1, 1 } do
			solidP(P(V(1, IH, ID), f * CFrame.new(sx * (IW / 2 + 0.5), IH / 2, 0), wall))
			trimRow(V(0.2, 0, ID - 0.2), sx * (IW / 2 - 0.1), 0)
		end
		local WY0, WY1, WW = 6.6, 14, 8 -- window opening
		local function holedWall(z, xs)
			solidP(P(V(IW, WY0, 1), f * CFrame.new(0, WY0 / 2, z), wall))
			solidP(P(V(IW, IH - WY1, 1), f * CFrame.new(0, (IH + WY1) / 2, z), wall))
			local edges = { -IW / 2 }
			for _, x in xs do table.insert(edges, x - WW / 2) table.insert(edges, x + WW / 2) end
			table.insert(edges, IW / 2)
			for k = 1, #edges, 2 do
				local a, b = edges[k], edges[k + 1]
				solidP(P(V(b - a, WY1 - WY0, 1), f * CFrame.new((a + b) / 2, (WY0 + WY1) / 2, z), wall))
			end
			local inz = z - (z > 0 and 0.6 or -0.6)
			trimRow(V(IW - 0.2, 0, 0.2), 0, inz)
		end
		holedWall(ID / 2 + 0.5, { -18, 14 })
		holedWall(-ID / 2 - 0.5, { -18, 18 })
		-- the view: a painted city skyline a few studs beyond the glass, so it
		-- shifts a little as you walk past (sky, mountains, towers, trees)
		local function skyline(z, flip)
			local panel = P(V(IW + 30, 20, 0.4), f * CFrame.new(0, 15.5, z), rgb(150, 206, 250), SMOOTH)
			local sg = Instance.new("SurfaceGui")
			sg.Face = flip and Enum.NormalId.Back or Enum.NormalId.Front
			sg.LightInfluence = 0
			sg.CanvasSize = Vector2.new(3760, 800)
			local sky = Instance.new("Frame")
			sky.Size = UDim2.fromScale(1, 1)
			sky.BorderSizePixel = 0
			sky.BackgroundColor3 = Color3.new(1, 1, 1)
			local gr = Instance.new("UIGradient")
			gr.Rotation = 90
			gr.Color = ColorSequence.new(rgb(96, 170, 246), rgb(214, 238, 255))
			gr.Parent = sky
			sky.ClipsDescendants = true
			sky.Parent = sg
			local function blobF(x, y, w, h, col, z2)
				local fr = Instance.new("Frame")
				fr.AnchorPoint = Vector2.new(0.5, 0.5)
				fr.Position = UDim2.fromOffset(x, y)
				fr.Size = UDim2.fromOffset(w, h)
				fr.BackgroundColor3 = col
				fr.BorderSizePixel = 0
				fr.ZIndex = z2 or 1
				local c2 = Instance.new("UICorner") c2.CornerRadius = UDim.new(1, 0) c2.Parent = fr
				fr.Parent = sky
				return fr
			end
			local function box(x, y0, w, h, col, z2)
				local fr = Instance.new("Frame")
				fr.AnchorPoint = Vector2.new(0.5, 1)
				fr.Position = UDim2.fromOffset(x, y0)
				fr.Size = UDim2.fromOffset(w, h)
				fr.BackgroundColor3 = col
				fr.BorderSizePixel = 0
				fr.ZIndex = z2 or 3
				fr.Parent = sky
				return fr
			end
			local rng = Random.new(lot.pos.X * 3 + lot.pos.Z + (flip and 7 or 0))
			blobF(2900, 300, 120, 120, rgb(255, 246, 200)) -- the sun
			for k = 0, 11 do
				local cx, cy = rng:NextInteger(60, 3700), rng:NextInteger(200, 440)
				for q = 0, 2 do blobF(cx + q * 50, cy + (q % 2) * 14, 110 - q * 10, 50, Color3.new(1, 1, 1)) end
			end
			-- snowy mountains, then green hills
			for k = 0, 10 do
				local x = k * 380 + rng:NextInteger(-60, 60)
				local r = rng:NextInteger(520, 760)
				blobF(x, 700, r, r, rgb(150, 150, 170), 2)
				blobF(x, 700 - r * 0.36, r * 0.42, r * 0.3, rgb(250, 252, 255), 2)
			end
			for k = 0, 14 do blobF(k * 270 + rng:NextInteger(-40, 40), 800, 520, 380, k % 2 == 0 and rgb(120, 190, 110) or rgb(104, 176, 100), 2) end
			-- the skyline
			local cols = { rgb(130, 186, 238), rgb(130, 214, 214), rgb(192, 176, 244), rgb(252, 184, 210), rgb(246, 238, 214) }
			local x = 40
			while x < 3740 do
				local w = rng:NextInteger(70, 130)
				local h = rng:NextInteger(120, 330)
				local col = cols[rng:NextInteger(1, #cols)]
				local b = box(x + w / 2, 760, w, h, col)
				box(x + w / 2, 760 - h, w * 0.6, h * 0.16, col)
				if h > 280 then box(x + w / 2, 760 - h * 1.16, 6, 70, rgb(240, 240, 246)) end
				for wy = 0, math.floor(h / 40) - 1 do
					for wx = 0, math.floor(w / 26) - 1 do
						local win2 = Instance.new("Frame")
						win2.Size = UDim2.fromOffset(12, 18)
						win2.Position = UDim2.fromOffset(8 + wx * 26, 12 + wy * 40)
						win2.BorderSizePixel = 0
						win2.BackgroundColor3 = rng:NextNumber() < 0.25 and rgb(255, 232, 160) or Color3.new(1, 1, 1)
						win2.BackgroundTransparency = 0.35
						win2.ZIndex = 4
						win2.Parent = b
					end
				end
				x += w + rng:NextInteger(6, 40)
			end
			-- trees + a hedge along the bottom
			box(1880, 800, 3760, 50, rgb(110, 184, 100), 5)
			for k = 0, 32 do blobF(k * 118 + rng:NextInteger(0, 40), 740, 110, 100, k % 2 == 0 and rgb(122, 196, 98) or rgb(100, 174, 90), 5) end
			sg.Parent = panel
		end
		skyline(ID / 2 + 9, false)
		skyline(-ID / 2 - 9, true)
		-- daylight spilling in from outside
		for _, z in { ID / 2 + 5, -ID / 2 - 5 } do
			local lp = P(V(1, 1, 1), f * CFrame.new(0, 12, z), Color3.new(1, 1, 1), MATTE, { transparency = 1 })
			local l = Instance.new("PointLight")
			l.Range = 40
			l.Brightness = 1
			l.Color = rgb(220, 236, 255)
			l.Shadows = false
			l.Parent = lp
		end
		-- window frames, glass, curtains (cf on the wall's inner face)
		local function win(cf)
			for _, sx in { -1, 1 } do P(V(0.6, 8.6, 1.6), cf * CFrame.new(sx * 4.1, 0.3, 0.5), Cc.cream) end
			for _, sy in { -1, 1 } do P(V(8.8, 0.6, 1.6), cf * CFrame.new(0, 0.3 + sy * 4, 0.5), Cc.cream) end
			P(V(0.4, 7.6, 0.4), cf * CFrame.new(0, 0.3, 0.6), Cc.cream)
			P(V(7.6, 0.4, 0.4), cf * CFrame.new(0, 0.3, 0.6), Cc.cream)
			-- (not the Glass material: it hides SurfaceGuis behind it)
			local g = P(V(7.6, 7.6, 0.2), cf * CFrame.new(0, 0.3, 0.7), rgb(220, 240, 255), SMOOTH)
			g.Transparency = 0.88
			g.Reflectance = 0.06
			P(V(9.6, 0.6, 2.2), cf * CFrame.new(0, -4, -0.3), Cc.cream) -- sill
			for _, sx in { -1, 1 } do P(V(2.2, 9.4, 0.3), cf * CFrame.new(sx * 5.2, 0, -0.4), rgb(250, 214, 150), Enum.Material.Fabric) end
		end
		for _, x in { -18, 18 } do win(f * CFrame.new(x, 10, -ID / 2) * CFrame.Angles(0, math.pi, 0)) end
		for _, x in { -18, 14 } do win(f * CFrame.new(x, 10, ID / 2)) end
		local door = f * CFrame.new(0, 0, -ID / 2 + 0.3)
		P(V(7, 11, 0.5), door * CFrame.new(0, 5.5, 0), Cc.sage)
		P(V(5.6, 10, 0.4), door * CFrame.new(0, 5, 0.2), rgb(250, 214, 110))
		K.ball(0.7, door * CFrame.new(2, 5, 0.6), Cc.gold, METAL)
		-- ceiling lights (real light: we're under the valley floor)
		for _, p in { V(-16, 0, -8), V(16, 0, -8), V(-16, 0, 12), V(16, 0, 12) } do
			local b = K.ball(2.2, f * CFrame.new(p.X, IH - 1.6, p.Z), rgb(255, 238, 200), NEON)
			local l = Instance.new("PointLight")
			l.Range = 34
			l.Brightness = 0.8
			l.Color = rgb(255, 236, 206)
			l.Shadows = true
			l.Parent = b
		end
		-- LIVING ROOM: rug, sofa, coffee table, the TV
		K.cyl(18, 0.2, f * CFrame.new(-18, 0.1, -6), rgb(186, 228, 164), Enum.Material.Fabric)
		local sofaCF = f * CFrame.new(-14, 0, -6) * CFrame.Angles(0, math.pi / 2, 0)
		P(V(12, 2.4, 5), sofaCF * CFrame.new(0, 1.8, 0), Cc.sage, Enum.Material.Fabric)
		P(V(12, 4, 1.6), sofaCF * CFrame.new(0, 3.4, 2.4), Cc.sage, Enum.Material.Fabric)
		for _, sx in { -1, 1 } do P(V(1.6, 3.2, 5), sofaCF * CFrame.new(sx * 6.6, 2.2, 0), Cc.sage, Enum.Material.Fabric) end
		for _, sx in { -3, 3 } do P(V(5, 0.8, 4), sofaCF * CFrame.new(sx, 3.3, -0.2), rgb(210, 236, 196), Enum.Material.Fabric) end
		P(V(6, 1.8, 4), f * CFrame.new(-21, 0.9, -6), rgb(200, 150, 110), WOODM)
		K.ball(1.2, f * CFrame.new(-21, 2.4, -5), rgb(255, 150, 190))
		local tvCF = f * CFrame.new(-31.2, 8, -6) * CFrame.Angles(0, -math.pi / 2, 0) -- local -Z faces the room
		P(V(14, 8.4, 0.8), tvCF, Cc.ink)
		local screen = P(V(13, 7.4, 0.3), tvCF * CFrame.new(0, 0, -0.5), rgb(30, 34, 40), SMOOTH)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.CanvasSize = Vector2.new(640, 360)
		local tvImg = Instance.new("ImageLabel")
		tvImg.Size = UDim2.fromScale(1, 1)
		tvImg.BackgroundTransparency = 1
		tvImg.ScaleType = Enum.ScaleType.Crop
		tvImg.Visible = false
		tvImg.Parent = sg
		sg.Parent = screen
		P(V(12, 3, 3), f * CFrame.new(-30, 1.5, -6), rgb(200, 150, 110), WOODM)
		-- KITCHEN: counter, stove, fridge (with a door that opens), table
		for z = -20, -4, 4 do P(V(5, 4.4, 4), f * CFrame.new(29, 2.2, z), Cc.cream) end
		P(V(5.6, 0.6, 20.6), f * CFrame.new(29, 4.7, -12), rgb(236, 236, 230), METAL)
		P(V(4, 0.2, 4), f * CFrame.new(29, 5.05, -8), Cc.ink)
		for _, dz in { -1, 1 } do K.cyl(1.4, 0.15, f * CFrame.new(29, 5.2, -8 + dz), rgb(90, 90, 96), METAL) end
		P(V(6, 11, 6), f * CFrame.new(28.5, 5.5, 2), rgb(236, 246, 240))
		local fridgeDoor = P(V(0.6, 10.4, 5.6), f * CFrame.new(25.3, 5.5, 2), rgb(206, 236, 214))
		P(V(0.4, 3, 0.4), f * CFrame.new(24.8, 6, 4), Cc.sage, METAL)
		P(V(6, 1.4, 0.2), f * CFrame.new(28.5, 13, -1), Cc.sage) -- a little shelf of jars above
		for q = 0, 2 do K.ball(1, f * CFrame.new(26.8 + q * 1.4, 14.2, -1.2), K.FLOWER_COLS[q + 1]) end
		K.cyl(8, 0.5, f * CFrame.new(16, 4, -10), rgb(250, 246, 236))
		P(V(0.8, 4, 0.8), f * CFrame.new(16, 2, -10), rgb(200, 150, 110), WOODM)
		for _, dz in { -6, 6 } do P(V(3, 3, 3), f * CFrame.new(16, 1.5, -10 + dz), Cc.butter) end
		K.ball(1.2, f * CFrame.new(16, 5, -10), rgb(236, 90, 90))
		-- BEDROOM: bed, nightstand + lamp, wardrobe
		local bed = f * CFrame.new(20, 0, 15)
		P(V(10, 2, 13), bed * CFrame.new(0, 1.4, 0), rgb(200, 150, 110), WOODM)
		P(V(9.6, 1.2, 12.6), bed * CFrame.new(0, 3, 0), rgb(252, 250, 244), Enum.Material.Fabric)
		P(V(9.8, 1.3, 8), bed * CFrame.new(0, 3.2, -2.2), rgb(250, 214, 150), Enum.Material.Fabric)
		P(V(7, 1.4, 3), bed * CFrame.new(0, 4, 4.4), rgb(252, 250, 244), Enum.Material.Fabric)
		P(V(10.4, 5, 0.8), bed * CFrame.new(0, 3.5, 6.6), rgb(200, 150, 110), WOODM)
		P(V(3.6, 3.6, 3.6), f * CFrame.new(28, 1.8, 19), rgb(200, 150, 110), WOODM)
		local lampShade = P(V(2.4, 2, 2.4), f * CFrame.new(28, 5.4, 19), rgb(255, 236, 190), NEON)
		local lampLight = Instance.new("PointLight")
		lampLight.Range = 16
		lampLight.Brightness = 1.4
		lampLight.Color = rgb(255, 214, 150)
		lampLight.Parent = lampShade
		P(V(0.3, 1.6, 0.3), f * CFrame.new(28, 4, 19), Cc.ink)
		local ward = f * CFrame.new(30.5, 0, 9) * CFrame.Angles(0, math.pi / 2, 0)
		P(V(10, 13, 3.4), ward * CFrame.new(0, 6.5, 0), Cc.mint)
		P(V(0.3, 12, 0.2), ward * CFrame.new(0, 6.5, -1.8), Cc.sage)
		for _, sx in { -1, 1 } do K.ball(0.7, ward * CFrame.new(sx * 0.9, 7, -1.9), Cc.gold, METAL) end
		-- BACK LEFT: piano, computer desk, bubble bath
		local pn = f * CFrame.new(-24, 0, 20)
		P(V(12, 7, 4), pn * CFrame.new(0, 3.5, 0), rgb(60, 70, 64))
		P(V(12, 0.6, 3), pn * CFrame.new(0, 4.4, -2.8), rgb(60, 70, 64))
		P(V(11, 0.4, 2), pn * CFrame.new(0, 4.8, -2.8), rgb(252, 250, 244))
		for k = 0, 7 do P(V(0.5, 0.3, 1.2), pn * CFrame.new(-4.6 + k * 1.4, 5.05, -2.4), Cc.ink) end
		P(V(5, 2.4, 3), pn * CFrame.new(0, 1.2, -6), rgb(60, 70, 64))
		local desk = f * CFrame.new(-6, 0, 20)
		P(V(10, 0.8, 5), desk * CFrame.new(0, 4.6, 0), rgb(200, 150, 110), WOODM)
		for _, sx in { -4.4, 4.4 } do P(V(0.8, 4.4, 4.4), desk * CFrame.new(sx, 2.2, 0), rgb(200, 150, 110), WOODM) end
		P(V(6, 4, 0.5), desk * CFrame.new(0, 7.6, 1.4), Cc.ink)
		local mon = P(V(5.4, 3.4, 0.2), desk * CFrame.new(0, 7.6, 1.1), rgb(186, 228, 164), NEON)
		K.textOn(mon, Enum.NormalId.Front, "CITY MAP", Cc.ink, Vector2.new(200, 120), 0)
		P(V(3.4, 3.4, 3.4), desk * CFrame.new(0, 1.7, -4), Cc.butter)
		local bath = f * CFrame.new(-27, 0, 8)
		P(V(8, 3.4, 12), bath * CFrame.new(0, 1.7, 0), rgb(250, 250, 250))
		P(V(7, 0.5, 11), bath * CFrame.new(0, 3.2, 0), rgb(170, 216, 236), SMOOTH)
		P(V(0.4, 3, 0.4), bath * CFrame.new(-3, 4.4, -5), rgb(200, 200, 206), METAL)
		-- a little stone arch in the wall: the shortcut back to the bedroom
		local ga = f * CFrame.new(-IW / 2 + 0.4, 0, -15) * CFrame.Angles(0, -math.pi / 2, 0)
		for k = 0, 8 do
			local a = k / 8 * math.pi
			P(V(2, 2.4, 1), ga * CFrame.new(math.cos(a) * 4.6, 6 + math.sin(a) * 4.6, 0) * CFrame.Angles(0, 0, a), k % 2 == 0 and Cc.stone or K.shade(Cc.stone, 0.12))
		end
		for _, sx in { -1, 1 } do P(V(2, 6, 1), ga * CFrame.new(sx * 4.6, 3, 0), Cc.stone) end
		local glow = P(V(7.4, 6, 0.3), ga * CFrame.new(0, 3, 0.2), rgb(120, 90, 200), NEON)
		K.cyl(7.4, 0.3, ga * CFrame.new(0, 6, 0.2) * CFrame.Angles(math.pi / 2, 0, 0), rgb(120, 90, 200), NEON)
		for k = 0, 4 do K.ball(0.4, ga * CFrame.new(-2.4 + k * 1.2, 3 + (k * 37 % 5), -0.1), rgb(255, 250, 220), NEON) end
		local gl = Instance.new("PointLight")
		gl.Color = rgb(170, 140, 255)
		gl.Range = 12
		gl.Parent = glow
		local gs = P(V(8, 1.4, 0.3), ga * CFrame.new(0, 12.4, -0.2), rgb(120, 96, 180))
		K.textOn(gs, Enum.NormalId.Front, "TO THE ARCADE", Cc.cream, Vector2.new(400, 70), 0.3)
		-- plants + framed pictures of Sminski Run
		for _, p in { V(-29, 0, -21), V(29, 0, 19), V(8, 0, -19), V(-12, 0, 19) } do K.planter(f * CFrame.new(p.X, 0, p.Z), 3) end
		for k, x in { -8, 3 } do
			local pic = P(V(7, 5, 0.3), f * CFrame.new(x, 11, ID / 2 - 0.2), Cc.sage)
			local psg = Instance.new("SurfaceGui")
			psg.Face = Enum.NormalId.Front
			psg.LightInfluence = 0.6
			local im = Instance.new("ImageLabel")
			im.Size = UDim2.new(1, -24, 1, -24)
			im.Position = UDim2.fromOffset(12, 12)
			im.Image = K.BILLBOARDS[k]
			im.ScaleType = Enum.ScaleType.Crop
			im.Parent = psg
			psg.Parent = pic
		end
		K.cur = keep
		m.Parent = K.actors
		local it = { m = m, f = f, lot = lot, tvImg = tvImg, screen = screen, fridgeDoor = fridgeDoor, fridgeCF = fridgeDoor.CFrame, lampLight = lampLight, lampShade = lampShade, sofa = sofaCF, bath = bath }
		-- the things you can use (local positions inside the house)
		it.items = {
			{ id = "lobby", at = V(-IW / 2 + 5, 0, -15), title = "ARCADE PORTAL", sub = "straight to the games: runs, dog park, shops", btn = "PLAY", icon = "play" },
			{ id = "door", at = V(0, 0, -ID / 2 + 4), title = "FRONT DOOR", sub = "back out to the street", btn = "GO OUT", icon = "house" },
			{ id = "sofa", at = V(-14, 0, -6), title = "COMFY SOFA", sub = "sit down and watch some TV", btn = "SIT", icon = "heart" },
			{ id = "tv", at = V(-24, 0, -6), title = "TV", sub = "Sminski Run on every channel", btn = "TV", icon = "play" },
			{ id = "fridge", at = V(23, 0, 2), title = "FRIDGE", btn = "SNACK", icon = "star", sub = function()
				local G = City.Grocery
				local n = G and G.pantryCount() or 0
				if n == 0 then return "empty -- buy groceries at the market" end
				return n .. " thing" .. (n == 1 and "" or "s") .. " inside: " .. table.concat(G.pantryNames(3), ", ")
			end },
			{ id = "bed", at = V(20, 0, 7), title = "COZY BED", sub = "a nap once a day = +50 coins", btn = "SLEEP", icon = "clock" },
			{ id = "wardrobe", at = V(26, 0, 9), title = "WARDROBE", sub = "try on your outfits", btn = "DRESS", icon = "shirt" },
			{ id = "lamp", at = V(26, 0, 17), title = "LAMP", sub = "click", btn = "LIGHT", icon = "bolt" },
			{ id = "piano", at = V(-24, 0, 14), title = "PIANO", sub = "play a little tune", btn = "PLAY", icon = "star" },
			{ id = "computer", at = V(-6, 0, 14), title = "COMPUTER", sub = "the city map + fast travel", btn = "OPEN", icon = "pin" },
			{ id = "bath", at = V(-21, 0, 8), title = "BATHTUB", sub = "a bubble bath", btn = "SPLASH", icon = "heart" },
		}
		interiors[i] = it
		return it
	end

	function Home.debugBuild(i) Home.indoorLook(true) return buildInterior(i).f end

	-- things the house items do
	local ACT = {}
	local function progress()
		if Home.tut and Home.tut.step == 3 then
			Home.tut.used = (Home.tut.used or 0) + 1
			if Home.tut.used >= 2 then Home.setStep(4) end
		end
	end
	function ACT.lobby()
		if ctx.exitCity then ctx.exitCity() end
	end
	function ACT.door(it)
		task.spawn(Home.goOut)
	end
	function ACT.sofa(it)
		Home.sitting = it.sofa * CFrame.new(0, 1.6, 0.6)
		if not it.tvOn then ACT.tv(it) end
	end
	function ACT.tv(it)
		it.tvOn = not it.tvOn
		it.tvImg.Visible = it.tvOn
		it.screen.Color = it.tvOn and Color3.new(1, 1, 1) or rgb(30, 34, 40)
		it.tvK = 0
		if it.tvOn then
			task.spawn(function()
				while it.tvOn and it.m.Parent do
					it.tvK += 1
					it.tvImg.Image = K.BILLBOARDS[it.tvK % #K.BILLBOARDS + 1]
					task.wait(4)
				end
			end)
		end
		Audio.play("Click", 1.2, 0.7)
	end
	function ACT.fridge(it)
		TweenService:Create(it.fridgeDoor, TweenInfo.new(0.35), { CFrame = it.fridgeCF * CFrame.new(-2.6, 0, -2.6) * CFrame.Angles(0, math.pi / 2, 0) }):Play()
		Audio.play("Pop", 1.3, 0.7)
		task.delay(1.6, function() TweenService:Create(it.fridgeDoor, TweenInfo.new(0.35), { CFrame = it.fridgeCF }):Play() end)
		-- THE FRIDGE HOLDS WHAT YOU BOUGHT. Groceries from the store come out
		-- here one at a time for a little XP; an empty fridge says where the
		-- market is instead of inventing a snack out of nothing.
		if City.Grocery then City.Grocery.eat() return end
		local snacks = { "a strawberry milk", "a slice of melon", "a rice ball", "a pudding cup", "a jam sandwich", "some cold noodles" }
		UI.toast("yum! " .. snacks[math.random(1, #snacks)], C.mintDark)
	end
	function ACT.bed(it)
		task.spawn(function()
			fadeTo(0, 0.6)
			local res = deps.remote("homeBonus")
			task.wait(0.8)
			fadeTo(1, 0.6)
			if res and res.ok and res.rested then
				deps.earned(res, "well rested!")
			else
				UI.toast("a cozy nap (come back tomorrow for the rest bonus)", C.mintDark)
			end
		end)
	end
	function ACT.wardrobe() UI.openShopTab("outfits") end
	function ACT.lamp(it)
		it.lampLight.Enabled = not it.lampLight.Enabled
		it.lampShade.Material = it.lampLight.Enabled and NEON or MATTE
		Audio.play("Click", 1.5, 0.6)
	end
	function ACT.piano()
		local tune = { 1, 1.12, 1.26, 1, 1.26, 1.5, 1.33, 1.26, 1.12, 1 }
		task.spawn(function()
			for _, pitch in tune do
				Audio.play("Chime", pitch, 0.6)
				task.wait(0.22)
			end
		end)
	end
	function ACT.computer() City.toggleMap() end
	function ACT.bath(it)
		for _ = 1, 16 do
			local b = part(it.m, V(1.4, 1.4, 1.4), it.bath * CFrame.new(math.random(-30, 30) / 10, 3.8, math.random(-50, 50) / 10), Color3.new(1, 1, 1), SMOOTH, { shape = Enum.PartType.Ball, transparency = 0.3 })
			TweenService:Create(b, TweenInfo.new(3, Enum.EasingStyle.Sine), { CFrame = b.CFrame * CFrame.new(0, 5 + math.random() * 4, 0), Transparency = 1 }):Play()
			task.delay(3.1, function() b:Destroy() end)
		end
		Audio.play("Pop", 1.6, 0.6)
		UI.toast("splish splash!", C.mintDark)
	end

	-- indoors the sunny city grade is far too hot: calm it while you're inside
	local Lighting = game:GetService("Lighting")
	local savedLook
	local function indoorLook(on)
		local bloom = Lighting:FindFirstChild("Bloom")
		if on and not savedLook then
			savedLook = { exp = Lighting.ExposureCompensation, bloom = bloom and bloom.Intensity }
			Lighting.ExposureCompensation = -0.75
			if bloom then bloom.Intensity = 0.15 end
		elseif not on and savedLook then
			Lighting.ExposureCompensation = savedLook.exp
			if bloom and savedLook.bloom then bloom.Intensity = savedLook.bloom end
			savedLook = nil
		end
	end
	Home.indoorLook = indoorLook

	function Home.goIn(i)
		local hrp, hum = myChar()
		if not hrp or Home.inside then return end
		local it = buildInterior(i)
		fadeTo(0, 0.25)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = it.f * CFrame.new(0, 3.4, -ID / 2 + 6) * CFrame.Angles(0, math.pi, 0)
		Home.inside = i
		if City.Sound then City.Sound.door(frontDoor(lots[i])) end
		player.CameraMaxZoomDistance = 22
		indoorLook(true)
		Audio.play("Pop", 1, 0.7)
		fadeTo(1, 0.35)
		if Home.tut and Home.tut.step <= 2 and i == myHouse() then Home.setStep(3) end
	end
	function Home.goOut()
		local i = Home.inside
		local hrp = myChar()
		if not i or not hrp then return end
		fadeTo(0, 0.25)
		Home.sitting = nil
		local lot = lots[i]
		local p = CITY + frontDoor(lot) + dirOf(lot) * 3 + V(0, K.PAD_Y + 3.2, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.lookAt(p, p + dirOf(lot))
		Home.inside = nil
		player.CameraMaxZoomDistance = 80
		indoorLook(false)
		fadeTo(1, 0.35)
	end

	---------------------------------------------------------------------------
	-- WAYFINDER: a glowing breadcrumb path along the sidewalks to a house
	---------------------------------------------------------------------------
	local ROADS = Places.CityRoads
	local LANES = {}
	for _, r in ROADS do table.insert(LANES, r - 27) table.insert(LANES, r + 27) end
	local function nearest(list, v)
		local best, bd = list[1], math.huge
		for _, l in list do if math.abs(l - v) < bd then best, bd = l, math.abs(l - v) end end
		return best
	end
	local path = { pts = {}, parts = nil, idx = 1 }
	function Home.clearPath()
		if path.parts then path.parts:Destroy() end
		path.parts = nil
		path.pts = {}
	end
	function Home.guide(i)
		i = i or myHouse()
		local lot = i and lots[i]
		local hrp = myChar()
		if not lot or not hrp then return end
		Home.clearPath()
		local a = flat(hrp.Position - CITY)
		local door = lot.door
		local dir = dirOf(lot)
		local corners = { a }
		if math.abs(dir.Z) > 0.5 then
			local zs = door.Z + dir.Z * 5
			local xa = nearest(LANES, a.X)
			table.insert(corners, V(xa, 0, a.Z))
			table.insert(corners, V(xa, 0, zs))
			table.insert(corners, V(door.X, 0, zs))
		else
			local xs = door.X + dir.X * 5
			local za = nearest(LANES, a.Z)
			table.insert(corners, V(a.X, 0, za))
			table.insert(corners, V(xs, 0, za))
			table.insert(corners, V(xs, 0, door.Z))
		end
		table.insert(corners, frontDoor(lot))
		-- breadcrumbs every 14 studs
		local m = Instance.new("Model")
		m.Name = "Wayfinder"
		local pts = {}
		for c = 1, #corners - 1 do
			local p0, p1 = corners[c], corners[c + 1]
			local len = (p1 - p0).Magnitude
			local n = math.max(1, math.floor(len / 14))
			for k = (c == 1 and 1 or 0), n - 1 do
				local p = p0:Lerp(p1, k / n)
				local cf = CFrame.lookAt(CITY + p + V(0, 1, 0), CITY + p1 + V(0, 1, 0))
				local ring = part(m, V(0.3, 5, 5), cf * CFrame.Angles(0, 0, math.pi / 2), rgb(186, 240, 160), NEON, { shape = Enum.PartType.Cylinder, transparency = 0.35 })
				for _, sx in { -1, 1 } do
					part(m, V(0.6, 0.4, 2.6), cf * CFrame.new(sx * 0.8, 0.4, -0.4) * CFrame.Angles(0, sx * 0.7, 0), rgb(255, 250, 220), NEON)
				end
				table.insert(pts, { p = p, ring = ring })
			end
		end
		m.Parent = K.actors
		path.parts, path.pts, path.idx, path.lot = m, pts, 1, i
		Audio.play("Chime", 1.2, 0.6)
	end
	-- the next breadcrumb ahead (for the arrow over your head)
	-- where your own front door is, for the travel pad and anything else
	-- that needs to send you home
	function Home.doorPos()
		local i = myHouse()
		return i and frontDoor(lots[i]) or nil
	end

	function Home.target()
		local nextP = path.pts[path.idx]
		if nextP then return nextP.p end
		return nil
	end

	---------------------------------------------------------------------------
	-- FIRST VISIT TUTORIAL
	---------------------------------------------------------------------------
	local tutCard, tutTitle, tutBody, tutBtn
	do
		local holder, card = UI.card(deps.H.root, UDim2.fromOffset(400, 176), UDim2.new(1, -24, 0, 156), Vector2.new(1, 0), C.paper)
		holder.Visible = false
		holder.ZIndex = 10
		tutCard = holder
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(56, 56)
		badge.Position = UDim2.fromOffset(14, 14)
		badge.BackgroundColor3 = C.mint
		badge.Parent = card
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 20) cr.Parent = badge
		UI.icon(badge, "house", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(5, 5) })
		tutTitle = UI.text(card, "", { Size = UDim2.new(1, -96, 0, 30), Position = UDim2.fromOffset(82, 26), Font = Enum.Font.FredokaOne, TextSize = 24, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
		tutBody = UI.text(card, "", { Size = UDim2.new(1, -32, 0, 84), Position = UDim2.fromOffset(16, 80), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		tutBtn = UI.button(card, "LET'S GO!", { size = UDim2.fromOffset(130, 40), pos = UDim2.new(1, -12, 1, -8), anchor = Vector2.new(1, 1), color = C.mint, textSize = 18, onClick = function() Home.finishTutorial() end })
		tutBtn.holder.Visible = false
	end
	local STEPS = {
		{ "WELCOME TO SMINSKI CITY!", "This is your new home town. Follow the glowing path to YOUR house. Tip: press C (or MY CAR) to call your car!" },
		{ "THIS IS YOUR HOUSE!", "Your name is on it for everyone to see. Walk up to the front door and go inside." },
		{ "HOME SWEET HOME", "Make yourself at home: nap in the bed, raid the fridge, play the piano, dress up at the wardrobe." },
		{ "YOU'RE ALL SET!", "Head out and earn coins: parcels at the Post Office, taxi fares downtown, the farm up north. Open the MAP any time." },
	}
	function Home.setStep(n)
		if not Home.tut then return end
		Home.tut.step = n
		tutCard.Visible = true
		tutTitle.Text = STEPS[n][1]
		tutBody.Text = STEPS[n][2]
		tutBtn.holder.Visible = n == 4
		local sc = tutCard:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", tutCard)
		-- smaller on a phone, where this card would otherwise cover a quarter of the view
		local full = deps.H.compact and 0.78 or 1
		sc.Scale = 0.9 * full
		UI.tween(sc, 0.3, { Scale = full }, Enum.EasingStyle.Back)
		Audio.play("Chime", 1 + n * 0.08, 0.6)
	end
	function Home.startTutorial()
		if Home.tut or not myHouse() then return end
		Home.tut = { step = 1 }
		Home.setStep(1)
		Home.guide()
	end
	function Home.finishTutorial()
		tutCard.Visible = false
		Home.tut = nil
		Home.clearPath()
		task.spawn(deps.remote, "tutorialDone")
		UI.toast("have fun in Sminski City!", C.mintDark)
	end

	---------------------------------------------------------------------------
	-- STATE / PROMPTS / UPDATE
	---------------------------------------------------------------------------
	local homeCarSpawned = false
	function Home.onState(cs)
		if not cs then return end
		Home.cs = cs
		-- your car waits on your driveway
		local i = myHouse()
		if not homeCarSpawned and i and cs.homeCar then
			homeCarSpawned = true
			local kind, col = string.match(cs.homeCar, "^(%w+):(%d+)$")
			if kind and K.SEAT[kind] then
				local cf = drivewayCF(lots[i])
				local m = K.buildCar(kind, K.CAR_COLORS[tonumber(col)] or K.CAR_COLORS[1], K.actors)
				m:PivotTo(cf)
				table.insert(Build.parked, { m = m, cf = cf, kind = kind, color = K.CAR_COLORS[tonumber(col)] or K.CAR_COLORS[1] })
				S.parkedDone = #Build.parked
			end
		end
		-- the find-your-house tutorial waits for the welcome tour (CityGuide) to
		-- finish, so a new player never has two cards talking at once
		if cs.tutorial == false and cs.tour ~= false and not Home.tut and not Home.tutDone then
			Home.tutDone = true
			task.delay(1.2, Home.startTutorial)
		end
	end

	-- returns a prompt { title, sub, btn, icon, action } / "none" / nil
	function Home.prompt(me)
		local hrp = myChar()
		if Home.inside then
			local it = interiors[Home.inside]
			if not it or not hrp then return "none" end
			local lp = it.f:PointToObjectSpace(hrp.Position)
			local best, bd
			for _, item in it.items do
				local d = (V(lp.X, 0, lp.Z) - item.at).Magnitude
				if d < 7 and (not bd or d < bd) then best, bd = item, d end
			end
			if not best then return "none" end
			return { best.title, type(best.sub) == "function" and best.sub() or best.sub, best.btn, best.icon, function()
				if ACT[best.id] then ACT[best.id](it) end
				if best.id ~= "door" then progress() end
			end, (it.f * CFrame.new(best.at.X, 2, best.at.Z)).Position }
		end
		-- driving onto your own driveway
		local i = myHouse()
		if S.car and i then
			local spot = drivewayCF(lots[i])
			if (flat(S.car.pos) - flat(spot.Position)).Magnitude < 14 then
				return { "YOUR DRIVEWAY", "park here and your car waits for you next time", "PARK", "house", function()
					local car = S.car
					local kind, colIdx = car.kind, car.color
					City.exitCar()
					local last = Build.parked[#Build.parked]
					if last and last.m then
						last.m:PivotTo(spot)
						last.cf = spot
					end
					task.spawn(deps.remote, "parkHome", kind .. ":" .. colIdx)
					UI.toast("parked at home!", C.mintDark)
				end }
			end
			return nil
		end
		-- standing on your own travel pad
		for li, d in decor do
			if d.pad and d.owner == player and (flat(me) - flat(d.pad)).Magnitude < 6 then
				return { "TRAVEL PAD", "jump to anywhere in the city", "TRAVEL", "pin", function()
					if City.openTravel then City.openTravel() end
				end, CITY + d.pad }
			end
		end
		-- front doors (yours, or a friend's)
		for li, d in decor do
			if (flat(me) - frontDoor(lots[li])).Magnitude < 8 then
				local mine = d.owner == player
				return { mine and "YOUR HOUSE" or (string.upper(d.owner.DisplayName) .. "'S HOUSE"), mine and "home sweet home" or "come on in, it's open!", mine and "GO IN" or "VISIT", "house", function()
					task.spawn(Home.goIn, li)
				end, CITY + frontDoor(lots[li]) }
			end
		end
		return nil
	end

	function Home.update(dt, t, me)
		scanOwners(dt)
		local hrp, hum = myChar()
		-- sitting on the sofa (stand up by walking)
		if Home.sitting and hrp then
			if hum and hum.MoveDirection.Magnitude > 0.2 then
				Home.sitting = nil
			else
				hrp.CFrame = Home.sitting * CFrame.new(0, 2.9, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
				S.poses[player] = "sit"
			end
		end
		-- breadcrumbs: pulse, and eat the ones you've reached
		if path.parts and hrp then
			local pos = flat(me)
			for k = path.idx, math.min(#path.pts, path.idx + 3) do
				if (pos - path.pts[k].p).Magnitude < 12 then
					for j = path.idx, k do
						if path.pts[j].ring then path.pts[j].ring.Transparency = 1 end
					end
					path.idx = k + 1
				end
			end
			for k = path.idx, math.min(#path.pts, path.idx + 12) do
				local r = path.pts[k].ring
				r.Transparency = 0.25 + 0.3 * (0.5 + 0.5 * math.sin(t * 5 - k * 0.6))
			end
			if path.lot and (pos - frontDoor(lots[path.lot])).Magnitude < 10 then
				Home.clearPath()
			end
		end
		if Home.tut and Home.tut.step == 1 and myHouse() and (flat(me) - frontDoor(lots[myHouse()])).Magnitude < 40 then
			Home.setStep(2)
		end
	end

	function Home.enter()
		homeCarSpawned = false
		Home.tutDone = false
	end
	function Home.leave()
		indoorLook(false)
		if Home.inside then
			Home.inside = nil
			Home.sitting = nil
			player.CameraMaxZoomDistance = 80
		end
		Home.clearPath()
		if Home.tut then
			Home.tut = nil
			tutCard.Visible = false
		end
		-- drop the parked home car so it isn't duplicated next visit
		for i = #Build.parked, 1, -1 do
			local p = Build.parked[i]
			if p.m and p.m.Parent == K.actors and not p.fromBlock then
				-- player cars only (block cars live in block folders)
				p.m:Destroy()
				table.remove(Build.parked, i)
			end
		end
		S.parkedDone = #Build.parked
	end

	return Home
end
