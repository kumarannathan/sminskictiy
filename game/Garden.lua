-- Garden (client): the Sminski Garden on the lobby table.
--   * a raised wooden planter with 6 soil plots (3 open at first, buy more)
--   * each plot grows a plant you can see from across the table: it gets
--     taller as it grows and glows softly once it's ready to pick
--   * walk up + press GARDEN: plant seeds, water once, harvest for coins
-- The server owns the truth (data.Garden); everything here just draws it.

return function(deps)
	local Config, UI, Audio, Places, ctx, part = deps.Config, deps.UI, deps.Audio, deps.Places, deps.ctx, deps.part
	local C = UI.C
	local UIS = game:GetService("UserInputService")
	local RS = game:GetService("ReplicatedStorage")
	local HUB = Places.HUB
	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local MATTE = Enum.Material.Plaster
	local WOOD = Enum.Material.Wood
	local NEON = Enum.Material.Neon
	local WALNUT = rgb(112, 74, 50)
	local BIRCH = rgb(206, 168, 124)
	local CREAM = rgb(250, 244, 232)
	local SOIL = rgb(118, 86, 64)

	local Garden = {}
	local remote -- ReplicatedStorage.SminskiRemotes.Garden
	local function server(action, i, seed)
		remote = remote or (RS:FindFirstChild("SminskiRemotes") and RS.SminskiRemotes:FindFirstChild("Garden"))
		if not remote then return { ok = false, reason = "the garden needs a live server" } end
		local ok, res = pcall(remote.InvokeServer, remote, action, i, seed)
		if not ok then return { ok = false, reason = "network error" } end
		return res or { ok = false }
	end
	local function now() return workspace:GetServerTimeNow() end
	local function gdata()
		local d = ctx.data
		local g = d and d.Garden or {}
		return g.plots or {}, math.min(Config.Garden.MaxPlots, Config.Garden.StartPlots + (g.unlocked or 0)), g.unlocked or 0
	end
	local function progress(p)
		local def = p and Config.Seed(p.seed)
		if not def then return 0, 0 end
		local total = def.grow * (p.watered and (1 - Config.Garden.WaterCut) or 1)
		local left = math.max(0, p.t0 + total - now())
		return 1 - left / total, left
	end
	local function fmtTime(s)
		s = math.ceil(s)
		if s >= 3600 then return string.format("%dh %02dm", s // 3600, (s % 3600) // 60) end
		if s >= 60 then return string.format("%dm %02ds", s // 60, s % 60) end
		return s .. "s"
	end

	---------------------------------------------------------------------------
	-- THE PLANTER
	---------------------------------------------------------------------------
	local folder, frameCF
	local plots = {} -- [i] = { cf, model, key, lock }
	local W, D = 40, 26
	local PW, PD = 11, 9 -- plot size

	local function P(size, cf, color, mat, opts)
		return part(folder, size, cf, color, mat or MATTE, opts)
	end
	local function cyl(dia, len, cf, color, mat, opts)
		opts = opts or {}
		opts.shape = Enum.PartType.Cylinder
		return P(V(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, opts)
	end
	local function blob(size, cf, color, mat, opts)
		opts = opts or {}
		opts.mesh = Enum.MeshType.Sphere
		return P(size, cf, color, mat, opts)
	end

	local function plotCF(i)
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		return frameCF * CFrame.new(-W / 2 + 7.5 + col * 12.5, 3.2, -D / 2 + 7.6 + row * 10.8)
	end

	function Garden.build(e, parent, sign)
		folder = Instance.new("Folder")
		folder.Name = "Garden"
		folder.Parent = parent
		local pos = HUB + e.pos
		frameCF = CFrame.lookAt(pos, pos + V(math.sin(e.face), 0, math.cos(e.face)))
		-- raised planter: base, board walls with corner posts and a cap rail
		local base = P(V(W + 2, 1.2, D + 2), frameCF * CFrame.new(0, 0.6, 0), WALNUT, WOOD)
		base.CanCollide = true
		for _, sz in { -1, 1 } do
			P(V(W, 2.8, 1), frameCF * CFrame.new(0, 2.6, sz * (D / 2 - 0.5)), BIRCH, WOOD)
			P(V(W + 1.4, 0.6, 1.6), frameCF * CFrame.new(0, 4.3, sz * (D / 2 - 0.5)), WALNUT, WOOD)
		end
		for _, sx in { -1, 1 } do
			P(V(1, 2.8, D - 2), frameCF * CFrame.new(sx * (W / 2 - 0.5), 2.6, 0), BIRCH, WOOD)
			P(V(1.6, 0.6, D - 2), frameCF * CFrame.new(sx * (W / 2 - 0.5), 4.3, 0), WALNUT, WOOD)
			for _, sz in { -1, 1 } do P(V(1.8, 5, 1.8), frameCF * CFrame.new(sx * (W / 2 - 0.5), 2.5, sz * (D / 2 - 0.5)), WALNUT, WOOD) end
		end
		-- a low divider between rows
		P(V(W - 2, 0.9, 0.6), frameCF * CFrame.new(0, 3.4, -D / 2 + 13), BIRCH, WOOD)
		-- soil beds + a little name stake for each plot
		for i = 1, Config.Garden.MaxPlots do
			local cf = plotCF(i)
			P(V(PW, 0.6, PD), cf * CFrame.new(0, -0.2, 0), SOIL, Enum.Material.Ground, { noShadow = true })
			for k = 0, 2 do P(V(PW - 1, 0.25, 0.8), cf * CFrame.new(0, 0.2, -2.6 + k * 2.6), SOIL:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Ground, { noShadow = true }) end
			local stake = P(V(0.5, 3.6, 0.5), cf * CFrame.new(-PW / 2 + 1, 1.6, -PD / 2 + 0.8), BIRCH, WOOD)
			local tag = P(V(3.6, 1.8, 0.3), cf * CFrame.new(-PW / 2 + 1, 3.4, -PD / 2 + 0.5), CREAM)
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.CanvasSize = Vector2.new(180, 90)
			sg.LightInfluence = 0.6
			local lbl = UI.text(sg, "", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = rgb(70, 58, 84) })
			sg.Parent = tag
			-- a wooden lid over locked plots
			local lock = Instance.new("Folder")
			lock.Name = "Lock" .. i
			lock.Parent = folder
			for k = 0, 3 do
				local b = part(lock, V(PW + 0.4, 0.5, PD / 4 - 0.15), cf * CFrame.new(0, 0.55, -PD / 2 + PD / 8 + k * PD / 4), k % 2 == 0 and BIRCH or rgb(196, 158, 114), WOOD)
				b.CanCollide = false
			end
			local plate = part(lock, V(3.2, 0.3, 2.2), cf * CFrame.new(0, 0.95, 0), rgb(240, 196, 84), Enum.Material.Metal)
			plate.CanCollide = false
			plots[i] = { cf = cf, label = lbl, lock = lock, stake = stake }
		end
		-- props: watering can, trowel, a seed crate, a little fence and a sign board
		local can = frameCF * CFrame.new(W / 2 + 4, 0, -6)
		cyl(4.2, 4.4, can * CFrame.new(0, 2.2, 0), rgb(120, 190, 220), Enum.Material.Metal)
		P(V(0.6, 0.6, 5), can * CFrame.new(0, 4, -3.6) * CFrame.Angles(0.7, 0, 0), rgb(120, 190, 220), Enum.Material.Metal)
		cyl(1.3, 0.5, can * CFrame.new(0, 5.4, -5.3) * CFrame.Angles(0.7, 0, 0), rgb(96, 160, 196), Enum.Material.Metal)
		P(V(0.6, 3, 0.6), can * CFrame.new(0, 5.4, 1.6), rgb(96, 160, 196), Enum.Material.Metal)
		P(V(0.6, 0.6, 3.2), can * CFrame.new(0, 6.8, 0.2), rgb(96, 160, 196), Enum.Material.Metal)
		local crate = frameCF * CFrame.new(-W / 2 - 4.5, 0, 8)
		P(V(7, 0.5, 5), crate * CFrame.new(0, 0.25, 0), BIRCH, WOOD)
		for _, sx in { -1, 1 } do P(V(0.5, 3.6, 5), crate * CFrame.new(sx * 3.25, 1.8, 0), BIRCH, WOOD) end
		for _, sz in { -1, 1 } do P(V(7, 3.6, 0.5), crate * CFrame.new(0, 1.8, sz * 2.25), BIRCH, WOOD) end
		for k, s in Config.Seeds do
			if k > 4 then break end
			P(V(1.4, 2.2, 0.3), crate * CFrame.new(-2.2 + (k - 1) * 1.5, 3.4, 0.4) * CFrame.Angles(-0.25, 0, 0), s.color)
		end
		P(V(0.5, 0.5, 4.2), frameCF * CFrame.new(-W / 2 - 3, 0.6, -6) * CFrame.Angles(0, 0.5, 0), WALNUT, WOOD)
		P(V(1.6, 0.25, 2.4), frameCF * CFrame.new(-W / 2 - 1.6, 0.4, -8.2) * CFrame.Angles(0, 0.5, 0), rgb(196, 200, 210), Enum.Material.Metal)
		-- the sign board on two legs behind the planter
		local sb = frameCF * CFrame.new(0, 0, D / 2 + 2)
		for _, sx in { -10.8, 10.8 } do P(V(0.9, 11, 0.9), sb * CFrame.new(sx, 5.5, 0.7), WALNUT, WOOD) end
		local board = P(V(20, 4.4, 0.6), sb * CFrame.new(0, 9, 0), rgb(96, 132, 88))
		P(V(21, 5.4, 0.4), sb * CFrame.new(0, 9, 0.35), WALNUT, WOOD)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(400, 90)
		sg.LightInfluence = 0.5
		UI.text(sg, "SMINSKI GARDEN", { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = CREAM })
		sg.Parent = board
		-- a little hanging lamp on an arm over the beds
		P(V(0.5, 0.5, 9), sb * CFrame.new(10.8, 12.2, -4.5), WALNUT, WOOD)
		P(V(2.4, 1.2, 2.4), sb * CFrame.new(10.8, 11.4, -8.6), rgb(96, 132, 88))
		local lamp = part(folder, V(1.2, 1.2, 1.2), sb * CFrame.new(10.8, 10.6, -8.6), rgb(255, 232, 190), NEON, { shape = Enum.PartType.Ball, noShadow = true })
		local l = Instance.new("PointLight")
		l.Range = 42
		l.Brightness = 1.1
		l.Color = rgb(255, 214, 160)
		l.Shadows = false
		l.Parent = lamp
		-- soft fill straight over the beds so the soil and seedlings read at night
		local fill = part(folder, V(1, 1, 1), frameCF * CFrame.new(0, 16, -2), Color3.new(), MATTE, { transparency = 1 })
		local fl = Instance.new("PointLight")
		fl.Range = 30
		fl.Brightness = 0.9
		fl.Color = rgb(255, 236, 205)
		fl.Shadows = false
		fl.Parent = fill
		local door = part(folder, V(W, 8, 1), frameCF * CFrame.new(0, 4, -D / 2 - 2), Color3.new(), MATTE, { transparency = 1 })
		if sign then sign(door, e) end
		Garden.refresh(true)
		return door
	end

	---------------------------------------------------------------------------
	-- PLANTS: one small model per plot, rebuilt when the seed or stage changes
	---------------------------------------------------------------------------
	local function buildPlant(parent, cf, def, k, ready)
		-- k: growth 0..1 ; everything scales from a seedling up
		local s = (0.3 + 0.7 * k) * 1.35
		local function add(size, pcf, color, mat, opts)
			local p = part(parent, size * s, cf * pcf, color, mat or MATTE, opts)
			p.CanCollide = false
			return p
		end
		local function stem(h, color)
			local p = part(parent, V(h * s, 0.45 * s, 0.45 * s), cf * CFrame.new(0, h * s / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color or rgb(96, 160, 88), MATTE, { shape = Enum.PartType.Cylinder })
			p.CanCollide = false
			return p
		end
		local leaf = rgb(110, 184, 96)
		if def.id == "sprout" then
			stem(3)
			for _, sx in { -1, 1 } do
				local p = part(parent, V(2.4, 0.4, 1.4) * s, cf * CFrame.new(sx * 1 * s, 3 * s, 0) * CFrame.Angles(0, 0, -sx * 0.5), def.color, MATTE, { mesh = Enum.MeshType.Sphere })
				p.CanCollide = false
			end
		elseif def.id == "berry" then
			for q = 0, 4 do
				local a = q / 5 * math.pi * 2
				local p = part(parent, V(3, 2.6, 3) * s, cf * CFrame.new(math.cos(a) * 1.3 * s, 1.8 * s, math.sin(a) * 1.3 * s), leaf, MATTE, { mesh = Enum.MeshType.Sphere })
				p.CanCollide = false
			end
			if k > 0.45 then
				for q = 0, 6 do
					local a = q * 2.3
					local p = part(parent, V(0.9, 0.9, 0.9) * s, cf * CFrame.new(math.cos(a) * 2.2 * s, (1.6 + (q % 3) * 0.7) * s, math.sin(a) * 2.2 * s), def.color, ready and NEON or MATTE, { shape = Enum.PartType.Ball })
					p.CanCollide = false
				end
			end
		elseif def.id == "tulip" then
			for q = -1, 1 do
				local p = part(parent, V(0.4, 5.2, 0.4) * s, cf * CFrame.new(q * 1.4 * s, 2.6 * s, 0) * CFrame.Angles(0, 0, q * 0.18), rgb(96, 160, 88), MATTE)
				p.CanCollide = false
				if k > 0.5 then
					local head = cf * CFrame.new(q * 2.2 * s, 5.4 * s, 0)
					for pz = 0, 2 do
						local pp = part(parent, V(1.2, 2, 0.5) * s, head * CFrame.Angles(0, pz * 2.09, 0) * CFrame.new(0, 0, 0.35 * s) * CFrame.Angles(-0.25, 0, 0), q == 0 and def.color or def.color:Lerp(rgb(255, 180, 210), 0.5), MATTE, { mesh = Enum.MeshType.Sphere })
						pp.CanCollide = false
					end
				end
			end
		elseif def.id == "bloom" then
			stem(6.5)
			for _, sx in { -1, 1 } do
				local p = part(parent, V(2.4, 0.4, 1.2) * s, cf * CFrame.new(sx * 1 * s, 2.6 * s, 0) * CFrame.Angles(0, 0, -sx * 0.4), leaf, MATTE, { mesh = Enum.MeshType.Sphere })
				p.CanCollide = false
			end
			if k > 0.4 then
				for q = 0, 5 do
					local a = q / 6 * math.pi * 2
					local p = part(parent, V(1.6, 0.5, 1.6) * s, cf * CFrame.new(math.cos(a) * 1.1 * s, 6.8 * s, math.sin(a) * 1.1 * s), def.color, MATTE, { mesh = Enum.MeshType.Sphere })
					p.CanCollide = false
				end
				local c = part(parent, V(1.2, 1.2, 1.2) * s, cf * CFrame.new(0, 7 * s, 0), rgb(255, 240, 190), ready and NEON or MATTE, { shape = Enum.PartType.Ball })
				c.CanCollide = false
			end
		elseif def.id == "shroom" then
			local p = part(parent, V(3.4, 1.4, 1.4) * s, cf * CFrame.new(0, 1.7 * s, 0) * CFrame.Angles(0, 0, math.pi / 2), CREAM, MATTE, { shape = Enum.PartType.Cylinder })
			p.CanCollide = false
			local cap = part(parent, V(4.6, 2.4, 4.6) * s, cf * CFrame.new(0, 3.6 * s, 0), def.color, ready and NEON or MATTE, { mesh = Enum.MeshType.Sphere })
			cap.CanCollide = false
			for q = 0, 3 do
				local a = q * 1.6
				local d = part(parent, V(0.7, 0.3, 0.7) * s, cf * CFrame.new(math.cos(a) * 1.2 * s, 4.7 * s, math.sin(a) * 1.2 * s), CREAM, MATTE, { mesh = Enum.MeshType.Sphere })
				d.CanCollide = false
			end
		elseif def.id == "golden" then
			for _, sx in { -1, 1 } do
				local p = part(parent, V(3, 0.5, 1.6) * s, cf * CFrame.new(sx * 1.4 * s, 0.8 * s, 0) * CFrame.Angles(0, 0, -sx * 0.3), leaf, MATTE, { mesh = Enum.MeshType.Sphere })
				p.CanCollide = false
			end
			local pod = part(parent, V(2.8, 3.6, 2.8) * s, cf * CFrame.new(0, 2.4 * s, 0), def.color, k >= 1 and Enum.Material.Metal or MATTE, { mesh = Enum.MeshType.Sphere })
			pod.CanCollide = false
			pod.Reflectance = k >= 1 and 0.15 or 0
		end
		if ready then
			local glow = Instance.new("PointLight")
			glow.Range = 9
			glow.Brightness = 0.6
			glow.Color = def.color
			glow.Shadows = false
			glow.Parent = parent:FindFirstChildWhichIsA("BasePart")
			local att = Instance.new("Attachment")
			att.Position = V(0, 1, 0)
			local sp = Instance.new("ParticleEmitter")
			sp.Rate = 3
			sp.Lifetime = NumberRange.new(1, 1.6)
			sp.Speed = NumberRange.new(1, 2)
			sp.SpreadAngle = Vector2.new(40, 40)
			sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			sp.Color = ColorSequence.new(rgb(255, 240, 170))
			sp.LightEmission = 1
			sp.Parent = att
			att.Parent = parent:FindFirstChildWhichIsA("BasePart")
		end
	end

	local lastKeys = {}
	function Garden.refresh(force)
		if not folder then return end
		local list, open = gdata()
		for i, pl in plots do
			local p = list[tostring(i)]
			local key, labelText
			pl.lock.Parent = i > open and folder or nil
			if i > open then
				key = "locked"
				labelText = "LOCKED"
			elseif not p then
				key = "empty"
				labelText = "EMPTY"
			else
				local def = Config.Seed(p.seed)
				local k, left = progress(p)
				local stage = left <= 0 and 4 or math.clamp(math.floor(k * 4), 0, 3)
				key = p.seed .. ":" .. stage
				labelText = left <= 0 and "READY!" or fmtTime(left)
				if def and key ~= lastKeys[i] then
					if pl.model then pl.model:Destroy() end
					pl.model = Instance.new("Model")
					pl.model.Name = "Plant" .. i
					pl.model.Parent = folder
					buildPlant(pl.model, pl.cf * CFrame.new(0.8, 0.1, 0.4), def, left <= 0 and 1 or (0.15 + stage * 0.25), left <= 0)
				end
			end
			if key == "locked" or key == "empty" then
				if pl.model then pl.model:Destroy() pl.model = nil end
			end
			lastKeys[i] = key
			pl.label.Text = labelText
		end
	end

	---------------------------------------------------------------------------
	-- THE GARDEN SCREEN
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiGardenUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.Enabled = false
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = C.ink
	dim.BackgroundTransparency = 0.45
	dim.Active = true
	dim.Parent = gui
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local cam = workspace.CurrentCamera
	local function rescale()
		local v = cam.ViewportSize
		local s = math.clamp(math.min(v.X / 1280, v.Y / 760), UIS.TouchEnabled and 0.6 or 0.45, 1.25)
		sc.Scale = s
		root.Size = UDim2.fromOffset(v.X / s, v.Y / s)
	end
	rescale()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local holder, card = UI.card(root, UDim2.fromOffset(880, 560), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5), C.paper)
	UI.text(card, "SMINSKI GARDEN", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 16), Font = Enum.Font.FredokaOne, TextSize = 38 })
	local subL = UI.text(card, "plant a seed · come back later · sell what you grow", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 60), Font = Enum.Font.Gotham, TextSize = 15, TextColor3 = C.inkSoft })
	local coinsL = UI.text(card, "", { AnchorPoint = Vector2.new(0, 0), Size = UDim2.fromOffset(200, 30), Position = UDim2.fromOffset(28, 22), Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = rgb(200, 150, 40), TextXAlignment = Enum.TextXAlignment.Left })
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -56, 0, 380)
	grid.Position = UDim2.fromOffset(28, 96)
	grid.Parent = card
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(1 / 3, -12, 0.5, -8)
	gl.CellPadding = UDim2.fromOffset(16, 14)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	local tiles = {}
	local picking -- plot index while the seed picker is open

	-- seed picker (slides over the grid)
	local picker = Instance.new("Frame")
	picker.BackgroundColor3 = C.paper
	picker.Size = UDim2.new(1, -56, 0, 400)
	picker.Position = UDim2.fromOffset(28, 90)
	picker.Visible = false
	picker.ZIndex = 5
	picker.Parent = card
	local pickTitle = UI.text(picker, "PICK A SEED", { Size = UDim2.new(1, 0, 0, 30), Font = Enum.Font.FredokaOne, TextSize = 24, ZIndex = 6 })
	local pickList = Instance.new("Frame")
	pickList.BackgroundTransparency = 1
	pickList.Size = UDim2.new(1, 0, 1, -40)
	pickList.Position = UDim2.fromOffset(0, 38)
	pickList.ZIndex = 6
	pickList.Parent = picker
	local pgl = Instance.new("UIGridLayout")
	pgl.CellSize = UDim2.new(1 / 3, -10, 0.5, -6)
	pgl.CellPadding = UDim2.fromOffset(14, 12)
	pgl.Parent = pickList
	local seedCards = {}

	local function afterCall(res, okMsg)
		if res and res.ok then
			if res.data and ctx.setData then ctx.setData(res.data) end
			if okMsg then UI.toast(okMsg, C.mintDark) end
			return true
		end
		if res and res.reason == "coins" then UI.toast("not enough coins")
		elseif res and res.reason == "level" then UI.toast("reach level " .. tostring(res.level) .. " to grow that")
		elseif res and res.reason then UI.toast(res.reason) end
		Audio.play("Click", 0.6, 0.6)
		return false
	end

	local refreshScreen
	for k, def in Config.Seeds do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = C.white
		f.LayoutOrder = k
		f.ZIndex = 6
		f.Parent = pickList
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = f
		local st = Instance.new("UIStroke") st.Thickness = 2 st.Color = C.ink st.Transparency = 0.85 st.Parent = f
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(40, 40)
		dot.Position = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = def.color
		dot.ZIndex = 7
		dot.Parent = f
		local dc = Instance.new("UICorner") dc.CornerRadius = UDim.new(1, 0) dc.Parent = dot
		UI.text(f, def.name, { Size = UDim2.new(1, -70, 0, 24), Position = UDim2.fromOffset(62, 12), Font = Enum.Font.FredokaOne, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7 })
		UI.text(f, "grows in " .. fmtTime(def.grow) .. "  ·  sells ◉ " .. UI.fmt(def.sell), { Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(62, 36), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7 })
		local b = UI.button(f, "", { size = UDim2.new(1, -24, 0, 46), pos = UDim2.new(0.5, 0, 1, -10), anchor = Vector2.new(0.5, 1), textSize = 18, onClick = function()
			if not picking then return end
			local i = picking
			local res = server("plant", i, def.id)
			if afterCall(res) then
				Audio.play("Pop", 1.1, 1)
				picking = nil
				picker.Visible = false
				Garden.refresh()
				refreshScreen()
			end
		end })
		b.holder.ZIndex = 7
		seedCards[def.id] = { btn = b, def = def }
	end
	UI.button(picker, "BACK", { size = UDim2.fromOffset(110, 40), pos = UDim2.new(1, 0, 0, -4), anchor = Vector2.new(1, 0), color = C.paper2, textColor = C.ink, textSize = 17, onClick = function()
		picking = nil
		picker.Visible = false
	end }).holder.ZIndex = 7

	local function openPicker(i)
		picking = i
		pickTitle.Text = "PLOT " .. i .. "  ·  PICK A SEED"
		local d = ctx.data or {}
		for _, c in seedCards do
			local def = c.def
			if (d.Level or 1) < (def.level or 1) then
				c.btn.setText("🔒 LEVEL " .. def.level)
				c.btn.setColor(C.paper2:Lerp(C.inkSoft, 0.3))
			else
				c.btn.setText("PLANT  ◉ " .. UI.fmt(def.cost))
				c.btn.setColor((d.Coins or 0) >= def.cost and C.mint or C.paper2:Lerp(C.inkSoft, 0.3))
			end
		end
		picker.Visible = true
	end

	for i = 1, Config.Garden.MaxPlots do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = C.white
		f.LayoutOrder = i
		f.Parent = grid
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 16) cr.Parent = f
		local st = Instance.new("UIStroke") st.Thickness = 2 st.Color = C.ink st.Transparency = 0.85 st.Parent = f
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(1, -20, 0, 8)
		swatch.Position = UDim2.fromOffset(10, 10)
		swatch.BackgroundColor3 = SOIL
		swatch.Parent = f
		local swc = Instance.new("UICorner") swc.CornerRadius = UDim.new(1, 0) swc.Parent = swatch
		local name = UI.text(f, "", { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 26), Font = Enum.Font.FredokaOne, TextSize = 21 })
		local info = UI.text(f, "", { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 54), Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.inkSoft })
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -40, 0, 10)
		barBg.Position = UDim2.fromOffset(20, 80)
		barBg.BackgroundColor3 = C.paper2
		barBg.Parent = f
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(1, 0) bc.Parent = barBg
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(0, 1)
		bar.BackgroundColor3 = C.mint
		bar.Parent = barBg
		local bc2 = Instance.new("UICorner") bc2.CornerRadius = UDim.new(1, 0) bc2.Parent = bar
		local main = UI.button(f, "", { size = UDim2.new(1, -24, 0, 50), pos = UDim2.new(0.5, 0, 1, -12), anchor = Vector2.new(0.5, 1), textSize = 19, onClick = function()
			local t = tiles[i]
			if t.mode == "empty" then
				openPicker(i)
			elseif t.mode == "ready" then
				local res = server("harvest", i)
				if afterCall(res) then
					Audio.play("BigChime", 1.1, 0.9)
					UI.toast("+◉ " .. UI.fmt(res.coins) .. "  ·  " .. res.name, C.mintDark)
					Garden.refresh()
					refreshScreen()
				end
			elseif t.mode == "growing" and not t.watered then
				local res = server("water", i)
				if afterCall(res) then
					Audio.play("Whoosh", 1.4, 0.8)
					UI.toast("watered! grows a third faster", C.sky)
					Garden.refresh()
					refreshScreen()
				end
			elseif t.mode == "locked" then
				local res = server("unlock")
				if afterCall(res, "new plot unlocked!") then
					Audio.play("BigChime", 1, 0.8)
					Garden.refresh()
					refreshScreen()
				end
			end
		end })
		tiles[i] = { frame = f, name = name, info = info, bar = bar, barBg = barBg, swatch = swatch, main = main, mode = "empty" }
	end
	local harvestAll = UI.button(card, "HARVEST ALL", { size = UDim2.fromOffset(200, 48), pos = UDim2.new(0.5, 0, 1, -18), anchor = Vector2.new(0.5, 1), color = C.gold, textSize = 20, onClick = function()
		local res = server("harvestAll")
		if afterCall(res) then
			Audio.play("BigChime", 1.1, 0.9)
			UI.toast("+◉ " .. UI.fmt(res.coins or 0) .. "  ·  " .. tostring(res.name), C.mintDark)
		end
		Garden.refresh()
		refreshScreen()
	end })
	UI.button(card, "✕", { size = UDim2.fromOffset(52, 52), pos = UDim2.new(1, -16, 0, 14), anchor = Vector2.new(1, 0), color = C.coral, textSize = 24, onClick = function() Garden.close() end })

	refreshScreen = function()
		if not gui.Enabled then return end
		local d = ctx.data or {}
		coinsL.Text = "◉ " .. UI.fmt(d.Coins or 0)
		local list, open, unlocked = gdata()
		local anyReady = false
		for i, t in tiles do
			local p = list[tostring(i)]
			t.barBg.Visible = false
			if i > open then
				local cost = i == open + 1 and Config.Garden.PlotCosts[unlocked + 1]
				t.mode = "locked"
				t.name.Text = "LOCKED PLOT"
				t.info.Text = cost and "unlock for more space" or "unlock the plot before this one"
				t.swatch.BackgroundColor3 = C.paper2
				t.main.setText(cost and ("UNLOCK  ◉ " .. UI.fmt(cost)) or "🔒")
				t.main.setColor(cost and (d.Coins or 0) >= cost and C.gold or C.paper2:Lerp(C.inkSoft, 0.3))
			elseif not p then
				t.mode = "empty"
				t.name.Text = "EMPTY PLOT"
				t.info.Text = "plant a seed here"
				t.swatch.BackgroundColor3 = SOIL
				t.main.setText("PLANT")
				t.main.setColor(C.mint)
			else
				local def = Config.Seed(p.seed)
				local k, left = progress(p)
				t.name.Text = def and def.name or p.seed
				t.swatch.BackgroundColor3 = def and def.color or SOIL
				t.barBg.Visible = true
				t.bar.Size = UDim2.fromScale(math.clamp(k, 0.02, 1), 1)
				t.bar.BackgroundColor3 = left <= 0 and C.gold or C.mint
				t.watered = p.watered
				if left <= 0 then
					anyReady = true
					t.mode = "ready"
					t.info.Text = "ready!  sells for ◉ " .. UI.fmt(def and def.sell or 0)
					t.main.setText("HARVEST")
					t.main.setColor(C.gold)
				else
					t.mode = "growing"
					t.info.Text = fmtTime(left) .. " left" .. (p.watered and "  ·  watered" or "")
					t.main.setText(p.watered and "GROWING..." or "WATER")
					t.main.setColor(p.watered and C.paper2:Lerp(C.inkSoft, 0.2) or C.sky)
				end
			end
		end
		harvestAll.holder.Visible = anyReady
	end

	function Garden.open()
		gui.Parent = deps.player and deps.player:FindFirstChild("PlayerGui") or game:GetService("StarterGui")
		gui.Enabled = true
		picker.Visible = false
		picking = nil
		refreshScreen()
		local ks = holder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", holder)
		local fit = UI.fit(880, 560)
		ks.Scale = 0.85 * fit
		UI.tween(ks, 0.3, { Scale = fit }, Enum.EasingStyle.Back)
		Audio.play("Pop", 1.1, 0.8)
		if UI.inputKind and UI.inputKind() == "gamepad" then
			game:GetService("GuiService").SelectedObject = tiles[1].main.face
		end
	end
	function Garden.close()
		gui.Enabled = false
		picker.Visible = false
		game:GetService("GuiService").SelectedObject = nil
	end
	function Garden.isOpen() return gui.Enabled end
	UIS.InputBegan:Connect(function(input)
		if not gui.Enabled then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Backspace then
			if picker.Visible then picker.Visible = false picking = nil else Garden.close() end
		end
	end)

	-- tick: timers on the tags and the screen, plants grow in place
	local acc = 0
	function Garden.update(dt)
		acc += dt
		if acc < 0.5 then return end
		acc = 0
		Garden.refresh()
		refreshScreen()
	end
	-- how many plants are ready (the prompt can nudge the player)
	function Garden.readyCount()
		local list, open = gdata()
		local n = 0
		for i = 1, open do
			local p = list[tostring(i)]
			if p then
				local _, left = progress(p)
				if left <= 0 then n += 1 end
			end
		end
		return n
	end

	return Garden
end
