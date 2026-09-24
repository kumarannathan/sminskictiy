-- Park (client): Dog Park Survival.
--   * builds the huge park (everything oversized next to a 4-stud Sminski)
--   * draws dogs / humans / bots / thrown things from server snapshots,
--     extrapolated to "now" so what you see is where they really are
--   * foot shadows telegraph stomps, "!" telegraphs a dog about to pounce
--   * checks your own Sminski against every hazard (fair: uses what you see)
--   * HUD: SURVIVE timer, SURVIVORS n/N, Chaos Meter, event banners, danger
--   * caught -> comedic poof -> spectate; winner screen; back to the hub

return function(deps)
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config, Models, World, Audio, UI, ctx, Hub = deps.Config, deps.Models, deps.World, deps.Audio, deps.UI, deps.ctx, deps.Hub
	local Places = deps.Places
	local Rules = require(ReplicatedStorage:WaitForChild("SminskiShared"):WaitForChild("ParkRules"))
	local player = deps.player
	local camera = workspace.CurrentCamera
	local part = Models.part
	local SM = Enum.Material.SmoothPlastic
	local C = UI.C
	local A = Places.ARENA
	local KIND, DOG, HUM = Rules.KIND, Rules.DOG, Rules.HUM

	local Park = {}
	local shake = 0
	local folder, actors
	local built = false
	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function at(x, y, z) return CFrame.new(A + V(x, y, z)) end
	local function solid(p)
		p.CanCollide = true
		p.CanQuery = true
		return p
	end
	local function now() return workspace:GetServerTimeNow() end

	local remote = game:GetService("RunService"):IsRunning() and ReplicatedStorage:WaitForChild("SminskiPark", 10) or nil
	local Event = remote and remote:WaitForChild("Event")
	local Snap = remote and remote:WaitForChild("Snap")

	---------------------------------------------------------------------------
	-- THE PARK
	---------------------------------------------------------------------------
	local sprinklerHeads = {}

	local function buildProp(pr)
		local cf = at(pr.pos.X, 0, pr.pos.Z) * CFrame.Angles(0, pr.yaw, 0)
		local s = pr.size
		local k = pr.kind
		if k == "tree" then
			if not World.placeAsset(folder, "ParkTree", cf * CFrame.new(0, s.Y / 2, 0), V(s.X * 5.2, s.Y, s.X * 5.2)) then
				part(folder, V(s.Y * 0.55, s.X, s.X), cf * CFrame.new(0, s.Y * 0.27, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(135, 95, 70), SM, { shape = Enum.PartType.Cylinder })
				part(folder, V(s.X * 5, s.X * 4, s.X * 5), cf * CFrame.new(0, s.Y * 0.7, 0), Color3.fromRGB(120, 200, 100), SM, { shape = Enum.PartType.Ball })
			end
			solid(part(folder, V(s.Y * 0.5, s.X * 0.9, s.X * 0.9), cf * CFrame.new(0, s.Y * 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.new(), SM, { shape = Enum.PartType.Cylinder, transparency = 1 }))
		elseif k == "bench" then
			if not World.placeAsset(folder, "ParkBench", cf * CFrame.new(0, s.Y / 2, 0), s) then
				part(folder, V(s.X, 1, s.Z), cf * CFrame.new(0, s.Y * 0.62, 0), Color3.fromRGB(200, 140, 85), Enum.Material.Wood)
			end
			-- seat you can hide under (legs + seat collide, the gap under it is free)
			solid(part(folder, V(s.X, 1, s.Z * 0.7), cf * CFrame.new(0, s.Y * 0.47, 0), Color3.new(), SM, { transparency = 1 }))
			for _, x in { -s.X * 0.41, s.X * 0.41 } do
				solid(part(folder, V(1.2, s.Y * 0.45, s.Z * 0.9), cf * CFrame.new(x, s.Y * 0.22, 0), Color3.new(), SM, { transparency = 1 }))
			end
		elseif k == "picnic" then
			local wood = Color3.fromRGB(190, 130, 80)
			solid(part(folder, V(s.X, 1.4, s.Z * 0.5), cf * CFrame.new(0, s.Y, 0), wood, Enum.Material.Wood))
			for _, z in { -s.Z * 0.38, s.Z * 0.38 } do
				solid(part(folder, V(s.X, 1, s.Z * 0.16), cf * CFrame.new(0, s.Y * 0.55, z), wood, Enum.Material.Wood))
			end
			for _, x in { -s.X * 0.4, s.X * 0.4 } do
				solid(part(folder, V(1.4, s.Y, s.Z * 0.9), cf * CFrame.new(x, s.Y / 2, 0) * CFrame.Angles(0, 0, 0), wood:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Wood))
			end
			-- checked cloth on top
			part(folder, V(s.X * 0.7, 0.3, s.Z * 0.5), cf * CFrame.new(0, s.Y + 0.85, 0), Color3.fromRGB(235, 90, 90), Enum.Material.Fabric)
		elseif k == "bush" then
			local green = Color3.fromRGB(95, 175, 85)
			for i = 0, 4 do
				local a = i / 5 * math.pi * 2
				part(folder, V(s.X * 0.6, s.Y, s.Z * 0.6), cf * CFrame.new(math.cos(a) * s.X * 0.22, s.Y * 0.45, math.sin(a) * s.Z * 0.22), green:Lerp(Color3.fromRGB(130, 210, 110), i % 2 * 0.3), Enum.Material.Grass, { shape = Enum.PartType.Ball })
			end
			part(folder, V(s.X * 0.7, s.Y * 1.1, s.Z * 0.7), cf * CFrame.new(0, s.Y * 0.6, 0), green, Enum.Material.Grass, { shape = Enum.PartType.Ball })
		elseif k == "rock" then
			solid(part(folder, s, cf * CFrame.new(0, s.Y * 0.35, 0), Color3.fromRGB(165, 160, 170), Enum.Material.Slate, { mesh = Enum.MeshType.Sphere }))
		elseif k == "hydrant" then
			local red = Color3.fromRGB(230, 70, 70)
			solid(part(folder, V(s.Y * 0.8, s.X * 0.8, s.X * 0.8), cf * CFrame.new(0, s.Y * 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), red, SM, { shape = Enum.PartType.Cylinder }))
			part(folder, V(s.X * 0.9, s.X * 0.9, s.X * 0.9), cf * CFrame.new(0, s.Y * 0.82, 0), red, SM, { shape = Enum.PartType.Ball })
			part(folder, V(s.X * 1.4, s.X * 0.4, s.X * 0.4), cf * CFrame.new(0, s.Y * 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 200, 80), SM, { shape = Enum.PartType.Cylinder })
		elseif k == "trash" then
			if not World.placeAsset(folder, "ParkBin", cf * CFrame.new(0, s.Y / 2, 0), s) then
				part(folder, s, cf * CFrame.new(0, s.Y / 2, 0), Color3.fromRGB(90, 160, 110), SM)
			end
			solid(part(folder, V(s.Y, s.X, s.X), cf * CFrame.new(0, s.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.new(), SM, { shape = Enum.PartType.Cylinder, transparency = 1 }))
		elseif k == "sign" then
			solid(part(folder, V(1, s.Y, 1), cf * CFrame.new(0, s.Y / 2, 0), Color3.fromRGB(120, 90, 70), Enum.Material.Wood))
			local board = part(folder, V(s.X, s.X * 0.55, 0.6), cf * CFrame.new(0, s.Y - s.X * 0.3, 0), Color3.fromRGB(110, 170, 110), SM)
			local sg = Instance.new("SurfaceGui")
			sg.CanvasSize = Vector2.new(300, 160)
			UI.text(sg, "🐾 DOGS ONLY\nplease keep off the grass", { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = C.white })
			sg.Parent = board
		elseif k == "log" then
			solid(part(folder, V(s.Z, s.X, s.X), cf * CFrame.new(0, s.X / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(140, 95, 65), Enum.Material.Wood, { shape = Enum.PartType.Cylinder }))
		elseif k == "branch" then
			solid(part(folder, V(s.Z, s.X, s.X), cf * CFrame.new(0, s.X / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(120, 85, 60), Enum.Material.Wood, { shape = Enum.PartType.Cylinder }))
		elseif k == "puddle" then
			local p = part(folder, V(0.2, s.Z, s.X), cf * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 170, 220), Enum.Material.Glass, { shape = Enum.PartType.Cylinder })
			p.Transparency = 0.25
			p.Reflectance = 0.3
		elseif k == "bowl" then
			if not World.placeAsset(folder, "DogBowl", cf * CFrame.new(0, s.Y / 2, 0), s) then
				part(folder, V(s.Y, s.X, s.X), cf * CFrame.new(0, s.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(235, 90, 90), SM, { shape = Enum.PartType.Cylinder })
			end
			solid(part(folder, V(s.Y, s.X, s.X), cf * CFrame.new(0, s.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.new(), SM, { shape = Enum.PartType.Cylinder, transparency = 1 }))
		elseif k == "ball" then
			solid(part(folder, s, cf * CFrame.new(0, s.Y / 2, 0), Color3.fromRGB(215, 240, 70), Enum.Material.Fabric, { shape = Enum.PartType.Ball }))
		elseif k == "frisbee" then
			part(folder, V(s.Y, s.X, s.Z), cf * CFrame.new(0, s.Y / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 125, 110), SM, { shape = Enum.PartType.Cylinder })
		elseif k == "bone" then
			local w = Color3.fromRGB(250, 245, 230)
			solid(part(folder, V(s.Z * 0.7, s.X * 0.6, s.X * 0.6), cf * CFrame.new(0, s.X / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), w, SM, { shape = Enum.PartType.Cylinder }))
			for _, z in { -s.Z * 0.4, s.Z * 0.4 } do
				for _, x in { -0.5, 0.5 } do
					part(folder, V(s.X * 0.75, s.X * 0.75, s.X * 0.75), cf * CFrame.new(x * s.X * 0.6, s.X / 2, z), w, SM, { shape = Enum.PartType.Ball })
				end
			end
		elseif k == "rope" then
			local cols = { Color3.fromRGB(255, 125, 110), Color3.fromRGB(140, 190, 240), Color3.fromRGB(250, 245, 230) }
			for i = 0, 4 do
				part(folder, V(s.X, s.X, s.Z / 5), cf * CFrame.new(0, s.X / 2, -s.Z / 2 + s.Z / 10 + i * s.Z / 5), cols[i % 3 + 1], Enum.Material.Fabric)
			end
		elseif k == "tunnel" then
			local col = Color3.fromRGB(255, 150, 70)
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				solid(part(folder, V(3.8, 1.2, s.Z), cf * CFrame.new(math.cos(a) * s.X / 2, s.X / 2 + math.sin(a) * s.X / 2, 0) * CFrame.Angles(0, 0, a + math.pi / 2), (i % 2 == 0) and col or col:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Fabric))
			end
		elseif k == "aframe" then
			local blue = Color3.fromRGB(110, 170, 240)
			for _, sx in { -1, 1 } do
				solid(part(folder, V(s.X, 1.2, s.Z * 0.55), cf * CFrame.new(0, s.Y / 2, sx * s.Z * 0.22) * CFrame.Angles(sx * -0.62, 0, 0), blue, SM))
			end
		elseif k == "weave" then
			for i = 0, 7 do
				local z = -s.Z / 2 + i * s.Z / 7
				solid(part(folder, V(1, s.Y, 1), cf * CFrame.new(0, s.Y / 2, z), i % 2 == 0 and Color3.fromRGB(255, 125, 110) or Color3.fromRGB(250, 245, 240), SM, { shape = Enum.PartType.Block }))
			end
		elseif k == "hurdle" then
			for _, x in { -s.X / 2, s.X / 2 } do
				solid(part(folder, V(1, s.Y, 1), cf * CFrame.new(x, s.Y / 2, 0), Color3.fromRGB(250, 245, 240), SM))
			end
			solid(part(folder, V(s.X, 0.8, 0.8), cf * CFrame.new(0, s.Y * 0.8, 0), Color3.fromRGB(245, 196, 80), SM))
		elseif k == "pond" then
			local p = part(folder, V(0.4, s.X, s.Z), cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(110, 170, 225), Enum.Material.Glass, { shape = Enum.PartType.Cylinder })
			p.Transparency = 0.2
			p.Reflectance = 0.35
			part(folder, V(0.3, s.X + 6, s.Z + 6), cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(200, 185, 150), Enum.Material.Sand, { shape = Enum.PartType.Cylinder })
			World.placeAsset(folder, "RubberDuck", cf * CFrame.new(8, 2.2, 3), V(4, 4.4, 5.4))
		end
	end

	function Park.build()
		if built then return end
		built = true
		folder = Instance.new("Folder")
		folder.Name = "SminskiPark"
		actors = Instance.new("Folder")
		actors.Name = "SminskiParkActors"
		local H = Places.ARENA_HALF
		-- lawn + paths
		solid(part(folder, V(H * 2 + 400, 2, H * 2 + 400), at(0, -1, 0), Color3.fromRGB(110, 185, 90), Enum.Material.Grass))
		local path = Color3.fromRGB(215, 200, 170)
		part(folder, V(Places.PATH_W, 0.3, H * 2), at(0, 0.15, 0), path, Enum.Material.Pavement)
		part(folder, V(H * 2, 0.3, Places.PATH_W), at(0, 0.16, 0), path, Enum.Material.Pavement)
		local ring = 64
		for i = 0, ring - 1 do
			local a = i / ring * math.pi * 2
			local p = V(math.cos(a), 0, math.sin(a)) * Places.RING_R
			part(folder, V(22, 0.3, Places.RING_R * math.pi * 2 / ring + 1.2), at(p.X, 0.17, p.Z) * CFrame.Angles(0, -a, 0), path, Enum.Material.Pavement)
		end
		-- the fence (with four gates)
		local fence = Color3.fromRGB(70, 75, 95)
		for _, side in { { V(1, 0, 0), V(0, 0, 1) }, { V(-1, 0, 0), V(0, 0, 1) }, { V(0, 0, 1), V(1, 0, 0) }, { V(0, 0, -1), V(1, 0, 0) } } do
			local n, along = side[1], side[2]
			for t = -H, H, 12 do
				if math.abs(t) > 22 then
					local p = n * H + along * t
					solid(part(folder, V(1.2, 16, 1.2), at(p.X, 8, p.Z), fence, Enum.Material.Metal))
				end
			end
			for _, seg in { { -H, -22 }, { 22, H } } do
				local mid = n * H + along * ((seg[1] + seg[2]) / 2)
				local len = seg[2] - seg[1]
				for _, y in { 5, 13 } do
					solid(part(folder, (along.X ~= 0) and V(len, 0.8, 0.8) or V(0.8, 0.8, len), at(mid.X, y, mid.Z), fence, Enum.Material.Metal))
				end
			end
		end
		-- lots of trees + houses beyond the fence, so the park feels huge
		for i = 1, 40 do
			local a = i / 40 * math.pi * 2
			local r = H + 50 + (i % 3) * 30
			World.placeAsset(folder, "ParkTree", at(math.cos(a) * r, 40, math.sin(a) * r), V(80, 90, 80))
		end
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2 + 0.3
			local r = H + 190
			local hcol = ({ Color3.fromRGB(255, 220, 190), Color3.fromRGB(200, 220, 255), Color3.fromRGB(255, 200, 210) })[i % 3 + 1]
			local h = at(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
			part(folder, V(110, 90, 90), h * CFrame.new(0, 45, 0), hcol, SM)
			part(folder, V(116, 30, 96), h * CFrame.new(0, 105, 0), Color3.fromRGB(200, 100, 90), SM, { class = "WedgePart" })
		end
		for _, pr in Places.arenaLayout() do
			buildProp(pr)
		end
		for i, sp in Places.Sprinklers or {} do
			local head = part(folder, V(2, 2, 2), at(sp.X, -1.5, sp.Z), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
			local a0 = Instance.new("Attachment")
			a0.Position = V(0, 1, 0)
			a0.Parent = head
			local pe = Instance.new("ParticleEmitter")
			pe.Rate = 0
			pe.Speed = NumberRange.new(40, 55)
			pe.Lifetime = NumberRange.new(1, 1.4)
			pe.SpreadAngle = Vector2.new(4, 4)
			pe.Acceleration = V(0, -60, 0)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			pe.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
			pe.LightEmission = 0.3
			pe.Parent = a0
			sprinklerHeads[i] = { part = head, att = a0, pe = pe, pos = sp }
		end
		folder.Parent = workspace
		actors.Parent = workspace
	end

	---------------------------------------------------------------------------
	-- HUD
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiParkUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = false
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local function rescale()
		local v = camera.ViewportSize
		local s = math.clamp(math.min(v.X / 1280, v.Y / 760), game:GetService("UserInputService").TouchEnabled and 0.6 or 0.45, 1.25)
		sc.Scale = s
		root.Size = UDim2.fromOffset(v.X / s, v.Y / s)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	Park.gui = gui

	local timerHolder, timerCard = UI.card(root, UDim2.fromOffset(210, 84), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0), C.paper)
	UI.text(timerCard, "SURVIVE", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 8), Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = C.coral, ZIndex = 3 })
	local timerText = UI.text(timerCard, "00:00", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 30), Font = Enum.Font.FredokaOne, TextSize = 44, ZIndex = 3 })
	local survHolder, survCard = UI.card(root, UDim2.fromOffset(200, 84), UDim2.fromOffset(20, 76), nil, C.paper)
	UI.icon(survCard, "friends", { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(-12, -12), ZIndex = 3 })
	UI.text(survCard, "SURVIVORS", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 8), Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = C.mintDark, ZIndex = 3 })
	local heartBadge = UI.icon(root, "heart", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(226, 86), Visible = false })
	local survText = UI.text(survCard, "1 / 1", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 30), Font = Enum.Font.FredokaOne, TextSize = 40, ZIndex = 3 })
	-- chaos meter
	local chaosHolder, chaosCard = UI.card(root, UDim2.fromOffset(250, 70), UDim2.new(1, -20, 0, 16), Vector2.new(1, 0), C.paper)
	local chaosName = UI.text(chaosCard, "QUIET PARK", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 8), Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = C.mintDark, ZIndex = 3 })
	local chaosBg = Instance.new("Frame")
	chaosBg.Size = UDim2.new(1, -36, 0, 16)
	chaosBg.Position = UDim2.fromOffset(18, 42)
	chaosBg.BackgroundColor3 = C.paper2
	chaosBg.ZIndex = 3
	chaosBg.Parent = chaosCard
	UI.skin(chaosBg, "pill", 8 / 80)
	local chaosFill = Instance.new("Frame")
	chaosFill.Size = UDim2.fromScale(0.1, 1)
	chaosFill.BackgroundColor3 = C.mint
	chaosFill.ZIndex = 4
	chaosFill.Parent = chaosBg
	UI.skin(chaosFill, "pill", 8 / 80)
	-- banners + big state text
	local banner = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(800, 60), Position = UDim2.new(0.5, 0, 0, 118), Font = Enum.Font.FredokaOne, TextSize = 52, TextColor3 = C.gold, stroke = 4, TextTransparency = 1 })
	local warn = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(700, 40), Position = UDim2.new(0.5, 0, 1, -40), Font = Enum.Font.FredokaOne, TextSize = 32, TextColor3 = C.coral, stroke = 3 })
	local big = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(900, 140), Position = UDim2.fromScale(0.5, 0.36), Font = Enum.Font.FredokaOne, TextSize = 110, TextColor3 = C.coral, stroke = 6, Visible = false, Rotation = -5 })
	local bigSub = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(900, 50), Position = UDim2.new(0.5, 0, 0.36, 84), Font = Enum.Font.FredokaOne, TextSize = 36, TextColor3 = C.white, stroke = 3, Visible = false })
	-- spectator bar
	local specHolder, specCard = UI.card(root, UDim2.fromOffset(460, 70), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1), C.paper)
	specHolder.Visible = false
	local specName = UI.text(specCard, "SPECTATING", { Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(75, 0), Font = Enum.Font.FredokaOne, TextSize = 26, ZIndex = 3 })
	local specIdx = 1
	local function cycle(d) specIdx += d Audio.play("Click", 1.3, 0.5) end
	UI.button(specCard, "<", { size = UDim2.fromOffset(56, 52), pos = UDim2.new(0, 10, 0.5, 2), anchor = Vector2.new(0, 0.5), color = C.sky, textSize = 28, onClick = function() cycle(-1) end }).holder.ZIndex = 3
	UI.button(specCard, ">", { size = UDim2.fromOffset(56, 52), pos = UDim2.new(1, -10, 0.5, 2), anchor = Vector2.new(1, 0.5), color = C.sky, textSize = 28, onClick = function() cycle(1) end }).holder.ZIndex = 3
	-- danger vignette
	local vig = Instance.new("ImageLabel")
	vig.BackgroundTransparency = 1
	vig.Size = UDim2.fromScale(1, 1)
	vig.Image = "rbxasset://textures/ui/TopBar/WhiteOverlayAsset.png"
	vig.ImageTransparency = 1
	vig.Visible = false
	vig.Parent = root
	-- results
	local resHolder, resCard = UI.card(root, UDim2.fromOffset(600, 560), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5), C.paper)
	resHolder.Visible = false
	UI.text(resCard, "LAST ONE ALIVE", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 18), Font = Enum.Font.FredokaOne, TextSize = 40, TextColor3 = C.coral, ZIndex = 3 })
	local resPortrait = UI.icon(resCard, "trophy", { Size = UDim2.fromOffset(170, 170), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), ZIndex = 3 })
	UI.icon(resCard, "trophy", { Size = UDim2.fromOffset(72, 72), Position = UDim2.new(0.5, 50, 0, 150), ZIndex = 4 })
	local resWinner = UI.text(resCard, "", { Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 236), Font = Enum.Font.FredokaOne, TextSize = 44, ZIndex = 3 })
	local resTime = UI.text(resCard, "", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 286), Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = C.inkSoft, ZIndex = 3 })
	local resList = UI.text(resCard, "", { Size = UDim2.new(1, -60, 0, 140), Position = UDim2.fromOffset(30, 324), Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 })
	local resReward = UI.text(resCard, "", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -60), Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = C.gold:Lerp(C.ink, 0.2), ZIndex = 3 })

	local function showBanner(str, color, hold)
		banner.Text = str
		banner.TextColor3 = color or C.gold
		banner.TextTransparency = 0
		local st = banner:FindFirstChildOfClass("UIStroke")
		st.Transparency = 0
		local s = banner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", banner)
		s.Scale = 0.5
		UI.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(hold or 2, function()
			if banner.Text == str then
				UI.tween(banner, 0.5, { TextTransparency = 1 })
				UI.tween(st, 0.5, { Transparency = 1 })
			end
		end)
	end
	local function showBig(str, sub, color)
		big.Visible = str ~= nil
		bigSub.Visible = sub ~= nil
		if not str then return end
		big.Text = str
		big.TextColor3 = color or C.coral
		bigSub.Text = sub or ""
		local s = big:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", big)
		s.Scale = 2
		UI.tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	---------------------------------------------------------------------------
	-- ROUND STATE
	---------------------------------------------------------------------------
	local round -- { t0, roster, total, myId, alive, ents, projs, out, sprinklers, over }
	local fxPart, poof

	local function makeFx()
		fxPart = part(nil, V(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1), nil, { transparency = 1 })
		poof = Instance.new("ParticleEmitter")
		poof.Rate = 0
		poof.Lifetime = NumberRange.new(0.4, 0.8)
		poof.Speed = NumberRange.new(10, 22)
		poof.SpreadAngle = Vector2.new(180, 180)
		poof.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		poof.LightEmission = 0.8
		poof.Drag = 5
		poof.Parent = fxPart
	end

	local function burstAt(pos, color, n)
		if not fxPart then makeFx() end
		fxPart.Parent = actors
		fxPart.CFrame = CFrame.new(pos)
		poof.Color = ColorSequence.new(color or Color3.fromRGB(255, 255, 255))
		poof:Emit(n or 30)
	end

	local function clearRound()
		if not round then return end
		for _, e in round.ents do
			if e.model then e.model:Destroy() end
			for _, s in e.shadows or {} do s:Destroy() end
			if e.bang then e.bang:Destroy() end
		end
		for _, p in round.projs do
			if p.part then p.part:Destroy() end
			if p.marker then p.marker:Destroy() end
		end
		for _, h in round.heartPickups or {} do h.model:Destroy() end
		heartBadge.Visible = false
		round = nil
	end

	local function entityModel(info)
		if info.kind == KIND.dog then
			local d = Rules.DOGS[info.variant] or Rules.DOGS[2]
			return Models.buildDog(actors, { scale = d.s, fur = d.fur, light = d.light, dark = d.dark })
		elseif info.kind == KIND.human then
			local h = Rules.HUMANS[info.variant] or Rules.HUMANS[1]
			return Models.buildKid(actors, { scale = h.s, hoodie = h.hoodie, pants = h.pants, cap = h.cap ~= false, capColor = h.cap or nil, bun = h.bun })
		end
	end

	local function shadowDisc()
		local s = part(actors, V(0.1, 6, 6), CFrame.new(), Color3.fromRGB(20, 15, 35), SM, { shape = Enum.PartType.Cylinder, noShadow = true })
		s.Transparency = 1
		return s
	end

	local function addEntity(info)
		if not round or round.ents[info.id] then return end
		local e = { id = info.id, kind = info.kind, variant = info.variant, s = info.s or 1, role = info.role, x = 0, z = 0, h = 0, v = 0, ph = 0, st = 0, stT = 0, ready = false }
		if info.kind == KIND.bot then
			local r = round.rosterById[info.id]
			local def = Config.Character(r and r.char or "Glow")
			e.rig = Models.buildSminski(actors, 1, def, true, r and r.outfit ~= "None" and r.outfit or nil)
			if deps.nameplate then deps.nameplate(e.rig, { name = r and r.name or "bot", isBot = true }) end
			e.model = e.rig.model
		else
			e.rig = entityModel(info)
			e.model = e.rig.model
			if info.kind == KIND.human then
				e.shadows = { shadowDisc(), shadowDisc() }
			end
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(80, 80)
			bb.StudsOffsetWorldSpace = V(0, 10 * e.s, 0)
			bb.AlwaysOnTop = true
			bb.Enabled = false
			bb.LightInfluence = 0
			UI.text(bb, "!", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = C.coral, stroke = 4 })
			bb.Adornee = e.rig.head
			bb.Parent = e.model
			e.bang = bb
		end
		e.model.Parent = nil
		round.ents[info.id] = e
	end

	---------------------------------------------------------------------------
	-- NETWORK
	---------------------------------------------------------------------------
	local handlers = {}
	handlers.pen = function(st) Hub.setPen(st) end
	handlers.start = function(d)
		clearRound()
		Park.build()
		round = { t0 = d.t0, roster = d.roster, rosterById = {}, total = d.total, alive = d.total, ents = {}, projs = {}, out = {}, tier = 1 }
		for _, r in d.roster do
			round.rosterById[r.id] = r
			if r.userId == (player and player.UserId) then round.myId = r.id end
		end
		ctx.enterPark()
	end
	handlers.spawn = function(info)
		if round then
			if not round.rosterById[info.id] or info.kind ~= KIND.bot then addEntity(info) end
		end
	end
	handlers.despawn = function(id)
		if not round then return end
		local e = round.ents[id]
		if e then
			e.model:Destroy()
			for _, s in e.shadows or {} do s:Destroy() end
			round.ents[id] = nil
		end
	end
	handlers.proj = function(p)
		if not round then return end
		p.part = part(actors, p.kind == "frisbee" and V(0.9, 9, 9) or V(Places.BALL_R * 2, Places.BALL_R * 2, Places.BALL_R * 2), CFrame.new(), p.kind == "frisbee" and Color3.fromRGB(255, 125, 110) or Color3.fromRGB(215, 240, 70), p.kind == "frisbee" and SM or Enum.Material.Fabric, { shape = p.kind == "frisbee" and Enum.PartType.Cylinder or Enum.PartType.Ball })
		-- landing marker: a pulsing ring where it'll come down
		p.marker = part(actors, V(0.15, 8, 8), CFrame.new(A + p.to + V(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 90, 90), Enum.Material.Neon, { shape = Enum.PartType.Cylinder, noShadow = true })
		p.marker.Transparency = 0.5
		round.projs[p.id] = p
		Audio.play("Whoosh", 0.9, 0.5)
	end
	handlers.tier = function(tier)
		if not round then return end
		round.tier = tier
		local def = Places.ParkTiers[tier]
		showBanner(def.name .. "!", def.color, 2.4)
		Audio.play("BigChime", 0.8 + tier * 0.1, 0.7)
		deps.parkLook(tier)
	end
	handlers.event = function(ev)
		if not round then return end
		showBanner(ev.title, C.gold, 2.6)
		Audio.play("Chime", 1.3, 0.8)
		if ev.kind == "sprinklers" and ev.sprinklers then
			round.sprinklers = ev.sprinklers
		end
	end
	handlers.bark = function(id)
		if not round then return end
		local e = round.ents[id]
		local hrp = Hub.myHRP()
		if e and hrp then
			local d = (A + V(e.x, 0, e.z) - hrp.Position).Magnitude
			if d < 120 then Audio.play("Bark", 0.9 + math.random() * 0.25, math.clamp(1 - d / 120, 0.15, 1)) end
		end
	end
	handlers.elim = function(d)
		if not round then return end
		round.out[d.id] = d.how
		round.alive = d.left
		local e = round.ents[d.id]
		local where
		if e and e.model and e.model.Parent then
			where = A + V(e.x, 2, e.z)
			e.model.Parent = nil
			e.dead = true
		end
		for _, p in Players:GetPlayers() do
			local r = round.rosterById[d.id]
			if r and r.userId == p.UserId and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				where = p.Character.HumanoidRootPart.Position
			end
		end
		if where then burstAt(where, Color3.fromRGB(190, 255, 150), 36) end
		local how = ({ caught = "CAUGHT!", stomped = "STOMPED!", squished = "SQUISHED!", bonked = "BONKED!", fell = "OOPS!", left = "LEFT" })[d.how] or "CAUGHT!"
		if d.id == round.myId then
			round.meOut = true
			round.outAt = now()
			shake = 1.2
			Audio.play("Bump", 0.8, 1)
			Audio.play("Wobble", 1, 1)
			showBig(how, "YOU WERE CAUGHT!  " .. d.left .. " SMINSKIS REMAIN", C.coral)
			task.delay(2.4, function() if round and round.meOut then showBig(nil) end end)
		else
			local who = d.name or "someone"
			showBanner(who .. " " .. string.lower(how), C.coral, 1.6)
			Audio.play("Pop", 0.7, 0.6)
		end
	end
	-- heart pickups: a glowing pink heart bobbing over a soft ring
	local function heartModel(x, z)
		local m = Instance.new("Model")
		m.Name = "HeartPickup"
		local base = at(x, 0, z)
		local ring = part(m, V(0.2, 7, 7), base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 130, 160), Enum.Material.Neon, { shape = Enum.PartType.Cylinder, noShadow = true })
		ring.Transparency = 0.55
		local core = part(m, V(2.4, 2.4, 2.4), base * CFrame.new(0, 3.5, 0), Color3.fromRGB(255, 110, 140), Enum.Material.Neon, { shape = Enum.PartType.Ball, transparency = 1 })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 120, 160)
		l.Range = 14
		l.Brightness = 1.2
		l.Parent = core
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(90, 90)
		bb.LightInfluence = 0
		bb.AlwaysOnTop = false
		bb.MaxDistance = 300
		bb.Adornee = core
		UI.icon(bb, "heart", { Size = UDim2.fromScale(1, 1) })
		bb.Parent = core
		m.Parent = actors
		return { model = m, core = core, ring = ring, x = x, z = z }
	end
	handlers.heart = function(h)
		if not round then return end
		round.heartPickups = round.heartPickups or {}
		if h.x then
			round.heartPickups[h.id] = heartModel(h.x, h.z)
			Audio.play("Chime", 1.6, 0.5)
			return
		end
		local pk = round.heartPickups[h.id]
		if pk then
			if h.by then burstAt(pk.core.Position, Color3.fromRGB(255, 130, 170), 24) end
			pk.model:Destroy()
			round.heartPickups[h.id] = nil
		end
		if h.by and h.by == round.myId then
			round.myHearts = 1
			heartBadge.Visible = true
			UI.popText("+1 ♥  EXTRA LIFE!", Color3.fromRGB(255, 130, 170), 38, -40)
			Audio.play("BigChime", 1.3, 0.8)
		end
	end
	handlers.saved = function(d)
		if not round then return end
		if d.id == round.myId then
			round.myHearts = 0
			heartBadge.Visible = false
			round.safeUntil = now() + (d.safe or 2.5)
			round.reported = false
			shake = 0.8
			UI.flash(Color3.fromRGB(255, 130, 170), 0.5)
			showBig("SAVED!", "your heart popped · " .. string.format("%.1f", d.safe or 2.5) .. "s to get clear", Color3.fromRGB(255, 120, 160))
			task.delay(1.3, function() if round and not round.meOut then showBig(nil) end end)
			Audio.play("Pop", 0.9, 1)
			-- knock you clear of whatever got you
			local hrp = Hub.myHRP()
			local e = round.ents[d.by]
			if hrp and e then
				local away = hrp.Position - (A + V(e.x, 0, e.z))
				away = V(away.X, 0, away.Z)
				away = away.Magnitude > 0.1 and away.Unit or V(1, 0, 0)
				hrp.AssemblyLinearVelocity = away * 60 + V(0, 30, 0)
			end
		else
			local r = round.rosterById[d.id]
			showBanner((r and r.name or "someone") .. "'s heart popped!", Color3.fromRGB(255, 130, 170), 1.4)
		end
	end

	handlers.results = function(d)
		if not round then return end
		round.over = true
		showBig(nil)
		specHolder.Visible = false
		resHolder.Visible = true
		local w = d.winner
		resPortrait.Image = UI.Art.chars[w.char] or UI.Art.icons.trophy
		resWinner.Text = w.name .. (w.bot and " (bot)" or "")
		resTime.Text = string.format("SURVIVAL TIME  %d:%02d", math.floor(w.time / 60), math.floor(w.time % 60))
		local lines = {}
		for i, r in d.results do
			if i <= 6 then
				table.insert(lines, string.format("%d.  %s%s   %d:%02d", r.place, r.name, r.bot and " (bot)" or "", math.floor(r.time / 60), math.floor(r.time % 60)))
			end
		end
		resList.Text = table.concat(lines, "\n")
		resReward.Text = d.reward and ("+" .. d.reward.coinsEarned .. " coins   +" .. d.reward.xpEarned .. " xp") or ""
		if d.reward and d.reward.data then ctx.setData(d.reward.data) end
		local won = w.id == round.myId
		round.winnerId = w.id
		Audio.play(won and "BigChime" or "Chime", 1, 1)
		if won then
			showBanner("YOU'RE THE LAST SMINSKI!", C.gold, 4)
		end
		local s = resHolder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", resHolder)
		s.Scale = 0.7
		UI.tween(s, 0.35, { Scale = UI.fit(600, 560) }, Enum.EasingStyle.Back)
	end
	-- LEAVE: tap twice to walk out of the round and back to the table
	local leaveArmed = 0
	local leaveBtn
	leaveBtn = UI.button(root, "LEAVE", { size = UDim2.fromOffset(150, 50), pos = UDim2.new(0, 24, 1, -24), anchor = Vector2.new(0, 1), color = C.paper2, textColor = C.ink, textSize = 20, icon = "house", onClick = function()
		if os.clock() < leaveArmed then
			leaveArmed = 0
			if Event then Event:FireServer("leave") end
		else
			leaveArmed = os.clock() + 3
			leaveBtn.setText("SURE? TAP AGAIN")
			leaveBtn.setColor(C.coral)
			task.delay(3, function()
				if os.clock() >= leaveArmed then
					leaveBtn.setText("LEAVE")
					leaveBtn.setColor(C.paper2)
				end
			end)
		end
	end })
	handlers.left = function()
		clearRound()
		resHolder.Visible = false
		specHolder.Visible = false
		showBig(nil)
		leaveBtn.setText("LEAVE")
		leaveBtn.setColor(C.paper2)
		ctx.exitPark()
	end
	handlers.idle = function()
		if round then
			clearRound()
			resHolder.Visible = false
			specHolder.Visible = false
			showBig(nil)
			ctx.exitPark()
		end
	end

	if Event then
		Event.OnClientEvent:Connect(function(kind, data)
			local h = handlers[kind]
			if h then h(data) end
		end)
	end
	if Snap then
		Snap.OnClientEvent:Connect(function(b)
			if not round or typeof(b) ~= "buffer" then return end
			local t, list = Rules.unpack(b)
			for _, s in list do
				local e = round.ents[s.id]
				if not e and s.kind == KIND.bot then
					addEntity({ id = s.id, kind = KIND.bot, s = 1 })
					e = round.ents[s.id]
				end
				if e and not e.dead then
					e.snapT = t
					e.sx, e.sz, e.sh, e.sv, e.sph, e.sst, e.sstT = s.x, s.z, s.h, s.v, s.ph, s.st, s.stT
					if not e.ready then
						e.x, e.z, e.h, e.v, e.ph, e.st, e.stT = s.x, s.z, s.h, s.v, s.ph, s.st, s.stT
						e.ready = true
					end
				end
			end
		end)
	end

	---------------------------------------------------------------------------
	-- PER FRAME
	---------------------------------------------------------------------------
	local lastSole = {}

	local function angleLerp(a, b, k)
		local d = (b - a + math.pi) % (math.pi * 2) - math.pi
		return a + d * k
	end

	local function driveEntity(e, dt, t, tn)
		if not e.ready then return end
		-- extrapolate the last snapshot to "now", then ease the drawn state toward it
		local age = math.clamp(tn - e.snapT, 0, 0.35)
		local tx = e.sx + math.sin(e.sh) * e.sv * age
		local tz = e.sz + math.cos(e.sh) * e.sv * age
		local k = math.min(1, dt * 14)
		e.x += (tx - e.x) * k
		e.z += (tz - e.z) * k
		e.h = angleLerp(e.h, e.sh, k)
		e.v = e.sv
		e.st = e.sst
		e.stT = e.sstT + age
		local tph = e.sph + Rules.phaseRate({ kind = e.kind, v = e.sv, s = e.s, st = e.sst, role = e.role }) * age
		e.ph = e.ph + (tph - e.ph) * math.min(1, dt * 20)
		e.model.Parent = actors
		local root = Rules.rootCF(e)
		if e.kind == KIND.dog then
			local reach = (e.st == DOG.chase and 0.5) or (e.st == DOG.crouch and 1) or 0.15
			Models.poseDog(e.rig, root, t + e.id, Rules.dogRun(e), reach, { phase = e.ph, pounce = Rules.pounce(e) > 0 and Rules.pounce(e) or nil })
			e.bang.Enabled = e.st == DOG.crouch or e.st == DOG.chase and e.stT < 0.6
		elseif e.kind == KIND.human then
			local throw = e.st == HUM.windup and math.clamp(e.stT / Rules.WINDUP_T, 0, 1) or 0
			Models.poseKid(e.rig, root, t + e.id, Rules.humanRun(e), 0, { phase = e.ph, throw = throw })
			e.bang.Enabled = false
			-- foot shadows: the lower the sole, the darker + tighter the shadow
			local run = Rules.humanRun(e)
			if run > 0 then
				local soles = deps.Rigs.kidSoles(root, e.ph, run, e.s)
				for i, sole in soles do
					local sh = e.shadows[i]
					local hgt = sole.h
					local air = math.clamp(hgt / (8 * e.s), 0, 1)
					sh.Transparency = hgt > 0.3 * e.s and (0.25 + air * 0.55) or 0.55
					local sz = (5.8 + air * 4) * e.s
					sh.Size = V(0.12, sz, sz * 1.3)
					local p = sole.cf.Position
					sh.CFrame = CFrame.new(p.X, A.Y + 0.35, p.Z) * CFrame.Angles(0, e.h, 0) * CFrame.Angles(0, math.pi / 2, math.pi / 2)
					-- stomp sound when a nearby foot lands
					local key = e.id * 2 + i
					local landed = hgt < 0.3 * e.s and (lastSole[key] or 1) >= 0.3 * e.s
					lastSole[key] = hgt
					if landed then
						local hrp = Hub.myHRP()
						if hrp and (hrp.Position - p).Magnitude < 80 then
							Audio.stomp(math.clamp(1 - (hrp.Position - p).Magnitude / 80, 0, 1))
							if (hrp.Position - p).Magnitude < 30 then shake = math.max(shake, 0.25 * e.s) end
						end
					end
				end
			else
				for _, sh in e.shadows do sh.Transparency = 1 end
			end
		elseif e.kind == KIND.bot then
			local pose = e.v > 2 and "run" or "idle"
			if round.winnerId == e.id then pose = "cheer" end
			Models.poseSminski(e.rig, root, pose, t + e.id, { stride = 9 + e.v * 0.45 })
		end
	end

	local function myFeet()
		local hrp = Hub.myHRP()
		return hrp and (hrp.Position - V(0, 2.9, 0)) or nil, hrp
	end

	-- the fair check: what you see is what gets you
	local function checkMe(tn)
		if not round or round.meOut or round.over or tn < round.t0 + 1 or round.reported then return end
		if round.safeUntil and tn < round.safeUntil then return end
		local feet = myFeet()
		if not feet then return end
		local rel = feet - A
		local cover = Places.coverAt(rel)
		for _, e in round.ents do
			if e.ready and not e.dead and e.kind ~= KIND.bot then
				local how = Rules.entityHit(e, feet, Rules.PLAYER_R, cover)
				if how then
					round.reported = true
					Event:FireServer("hit", { id = e.id, how = how })
					task.delay(1.2, function() if round then round.reported = false end end)
					return
				end
			end
		end
		for _, pr in round.projs do
			local how = Rules.projHit(pr, feet, tn, Rules.PLAYER_R, cover)
			if how then
				round.reported = true
				Event:FireServer("hit", { id = pr.id, how = how })
				task.delay(1.2, function() if round then round.reported = false end end)
				return
			end
		end
	end

	-- the camera target while spectating
	local function spectateList()
		local list = {}
		for _, r in round.roster do
			if not round.out[r.id] and r.id ~= round.myId then table.insert(list, r) end
		end
		return list
	end

	local camPos, camLook
	function Park.update(dt, t)
		if not round then return end
		local tn = now()
		gui.Enabled = true
		local elapsed = math.max(0, (round.outAt and not round.over and round.outAt or tn) - round.t0)
		if tn < round.t0 then
			local left = math.ceil(round.t0 - tn)
			showBig(tostring(left), "GET READY TO RUN!", C.white)
			round.cd = left
		elseif round.cd then
			round.cd = nil
			showBig("SURVIVE!", "last Sminski alive wins", C.mint)
			Audio.play("Pop", 1.4, 1)
			Audio.musicStart()
			task.delay(1.2, function() if round and not round.meOut then showBig(nil) end end)
		end
		timerText.Text = string.format("%02d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60))
		survText.Text = (round.alive or 0) .. " / " .. (round.total or 0)
		local c = math.max(0, tn - round.t0)
		local tier = Places.parkTier(c)
		local def = Places.ParkTiers[tier]
		chaosName.Text = def.name
		chaosName.TextColor3 = def.color:Lerp(C.ink, 0.25)
		chaosFill.Size = UDim2.fromScale(math.clamp(Places.chaos(c) / 1.2, 0.04, 1), 1)
		chaosFill.BackgroundColor3 = def.color

		for _, e in round.ents do
			if not e.dead then driveEntity(e, dt, t, tn) end
		end
		-- thrown things
		for id, p in round.projs do
			local pos, lethal, dir, done = Places.projAt(p, tn)
			if pos then
				p.part.Parent = actors
				if p.kind == "frisbee" then
					p.part.CFrame = CFrame.new(A + pos) * CFrame.Angles(0, t * 12, 0) * CFrame.Angles(0, 0, math.pi / 2)
				else
					p.part.CFrame = CFrame.new(A + pos) * CFrame.Angles(t * 8, 0, 0)
				end
				local k = math.clamp((tn - p.t0) / p.T, 0, 1)
				p.marker.Transparency = k >= 1 and 1 or 0.65 - 0.4 * math.abs(math.sin(t * 8))
				local ms = 4 + (1 - k) * 6
				p.marker.Size = V(0.15, ms, ms)
			end
			if tn > p.t0 + p.T + 5 then
				p.part:Destroy()
				p.marker:Destroy()
				round.projs[id] = nil
			end
		end
		for _, h in round.heartPickups or {} do
			h.core.CFrame = at(h.x, 3.5 + math.sin(t * 3) * 0.6, h.z)
			h.ring.Transparency = 0.45 + math.sin(t * 4) * 0.15
		end
		heartBadge.Rotation = math.sin(t * 3) * 8
		-- sprinklers: spinning water jets that knock you back
		local sp = round.sprinklers
		local sprOn = sp and tn < sp.t0 + sp.dur
		for i, s in sprinklerHeads do
			s.part.CFrame = at(s.pos.X, sprOn and 0.8 or -1.5, s.pos.Z)
			s.pe.Rate = sprOn and 120 or 0
			if sprOn then
				local a = (tn - sp.t0) * 1.4 + i
				s.att.CFrame = CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(35), 0, 0)
				local feet, hrp = myFeet()
				if feet and hrp and not round.meOut then
					local rel = feet - (A + s.pos)
					local d = V(rel.X, 0, rel.Z)
					local jet = V(-math.sin(a), 0, -math.cos(a))
					if d.Magnitude < 55 and d.Magnitude > 2 and d.Unit:Dot(jet) > 0.96 and (round.splashT or 0) < tn then
						round.splashT = tn + 0.8
						hrp.AssemblyLinearVelocity = jet * 70 + V(0, 35, 0)
						UI.popText("SPLASH!", C.sky, 34, -40)
						Audio.play("Whoosh", 0.7, 1)
					end
				end
			end
		end

		checkMe(tn)

		-- your own Sminski + everyone else's (from their characters)
		local override = {}
		if round.winnerId then
			for _, p in Players:GetPlayers() do
				local r = round.rosterById[round.winnerId]
				if r and r.userId == p.UserId then override[p] = "cheer" end
			end
		end
		Hub.updateAvatars(dt, t, override)

		-- puddles slow you down
		local feet, hrp = myFeet()
		local hum = hrp and hrp.Parent:FindFirstChildOfClass("Humanoid")
		if hum and tn >= round.t0 and not round.meOut then
			local rel = feet - A
			local slow = false
			for _, pr in Places.arenaLayout() do
				if pr.puddle and (V(rel.X, 0, rel.Z) - pr.pos).Magnitude < pr.size.X * 0.45 then slow = true break end
			end
			hum.WalkSpeed = Config.Park.WalkSpeed * (slow and 0.6 or 1)
		end

		-- danger: a dog chasing (or about to pounce on) you
		local danger = 0
		if feet and not round.meOut then
			for _, e in round.ents do
				if e.kind == KIND.dog and e.ready and not e.dead and (e.st == DOG.chase or e.st == DOG.crouch or e.st == DOG.lunge) then
					local d = (V(e.x, 0, e.z) - V(feet.X - A.X, 0, feet.Z - A.Z)).Magnitude
					if d < 45 then danger = math.max(danger, 1 - d / 45) end
				end
			end
		end
		warn.Text = danger > 0.35 and "A DOG IS AFTER YOU! RUN!" or ""
		warn.TextTransparency = 0.1 + math.sin(t * 12) * 0.15
		UI.setDanger(danger * 0.7, t)
		Audio.update(dt, math.clamp(Places.chaos(c), 0, 1), danger, false)

		-- camera: follow your Sminski; spectate someone else once caught
		shake = math.max(0, shake - dt * 2.5)
		if round.meOut and not round.over and tn > (round.outAt or 0) + 2.2 then
			local list = spectateList()
			specHolder.Visible = #list > 0
			if #list > 0 then
				specIdx = ((specIdx - 1) % #list) + 1
				local r = list[specIdx]
				specName.Text = "SPECTATING  " .. r.name .. (r.bot and " (bot)" or "")
				local target
				if r.bot then
					local e = round.ents[r.id]
					if e then target = A + V(e.x, 0, e.z) end
				else
					for _, p in Players:GetPlayers() do
						if p.UserId == r.userId and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
							target = p.Character.HumanoidRootPart.Position - V(0, 2.9, 0)
						end
					end
				end
				if target then
					camera.CameraType = Enum.CameraType.Scriptable
					local want = target + V(0, 30, -34)
					camPos = camPos and camPos:Lerp(want, math.min(1, dt * 4)) or want
					camLook = camLook and camLook:Lerp(target, math.min(1, dt * 6)) or target
					camera.CFrame = CFrame.lookAt(camPos, camLook)
				end
			end
		elseif not round.over or not round.meOut then
			camera.CameraType = Enum.CameraType.Custom
			if shake > 0.02 then
				local o = V(math.random() - 0.5, math.random() - 0.5, 0) * shake * 0.8
				camera.CFrame = camera.CFrame * CFrame.new(o)
			end
		end
	end

	function Park.enter()
		Park.build()
		folder.Parent = workspace
		actors.Parent = workspace
		gui.Enabled = true
		resHolder.Visible = false
		specHolder.Visible = false
		if player then
			player.CameraMinZoomDistance = 22
			player.CameraMaxZoomDistance = 22
			task.delay(0.3, function()
				player.CameraMinZoomDistance = 14
				player.CameraMaxZoomDistance = 80
			end)
		end
		camPos, camLook = nil, nil
	end

	function Park.leave()
		gui.Enabled = false
		UI.setDanger(0, 0)
		if folder then folder.Parent = nil end
		if actors then actors.Parent = nil end
		camera.CameraType = Enum.CameraType.Custom
	end

	function Park.inRound()
		return round ~= nil
	end

	UIS.InputBegan:Connect(function(input, gp)
		if gp or not round or not round.meOut then return end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft then cycle(-1) end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.DPadRight then cycle(1) end
	end)

	return Park
end
