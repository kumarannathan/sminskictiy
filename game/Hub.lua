-- Hub (client): the walkable Sminski neighborhood.
--   * a tiny toy town on a bedroom rug at night: Main House (Endless Run),
--     Dog Park gate + waiting pen (Survival), Arcade (Ranked), Toy Store (Shop),
--     Capsule Machine (Collection), Closet (Outfits), Friends Area (Multiplayer),
--     Challenge Board
--   * every player's Sminski drawn on top of their (invisible) character
--   * NPC Sminskis pottering about
--   * walk-up prompts, walk-in doors, the waiting-pen panel, the MENU button

return function(deps)
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local Lighting = game:GetService("Lighting")
	local Config, Models, World, Audio, UI, ctx = deps.Config, deps.Models, deps.World, deps.Audio, deps.UI, deps.ctx
	local Places = deps.Places
	local player = deps.player
	local camera = workspace.CurrentCamera
	local part = Models.part
	local SM = Enum.Material.SmoothPlastic
	local MATTE = Enum.Material.Plaster
	local C = UI.C
	local HUB = Places.HUB

	local Hub = {}
	local folder -- world geometry
	local actors -- avatars + NPCs
	local built = false
	local clockAcc = 10 -- day/night refresh timer

	local function V(x, y, z) return Vector3.new(x, y, z) end
	local function at(x, y, z) return CFrame.new(HUB + V(x, y, z)) end
	local function solid(p)
		p.CanCollide = true
		p.CanQuery = true
		return p
	end

	---------------------------------------------------------------------------
	-- BUILD HELPERS
	---------------------------------------------------------------------------
	-- building title banners: a bit smaller than before, and see-through when
	-- you're right up close (so they never block the doorway), solid from afar
	local signs = {}
	local function sign(parent, adornee, title, sub, color, iconName, height)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(208, 77)
		bb.StudsOffsetWorldSpace = V(0, height or 8, 0)
		bb.LightInfluence = 0
		bb.MaxDistance = 190
		bb.AlwaysOnTop = true
		bb.Adornee = adornee
		local holder = Instance.new("CanvasGroup")
		holder.Size = UDim2.fromOffset(260, 96)
		holder.BackgroundTransparency = 1
		holder.Parent = bb
		local sc = Instance.new("UIScale")
		sc.Scale = 0.8
		sc.Parent = holder
		table.insert(signs, { bb = bb, g = holder, a = adornee })
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 62)
		card.BackgroundColor3 = color
		card.Parent = holder
		UI.skin(card, "pill", 31 / 80)
		local ic = UI.icon(card, iconName, { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(-10, 0), ZIndex = 3 })
		UI.text(card, title, { Size = UDim2.new(1, -60, 0, 34), Position = UDim2.fromOffset(52, 4), Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, stroke = 2, ZIndex = 3 })
		UI.text(card, sub, { Size = UDim2.new(1, -60, 0, 18), Position = UDim2.fromOffset(52, 38), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		bb.Parent = parent
		return bb, ic
	end

	-- facing the plaza centre from p (relative to HUB)
	local function faceCentre(p)
		return CFrame.lookAt(HUB + p, HUB + V(0, p.Y, 0)) -- -Z looks at the centre
	end

	local function roof(parent, cf, w, d, h, color)
		-- two sloped halves made from wedges, eaves overhanging
		local left = part(parent, V(d + 2, h, w / 2 + 1.5), cf * CFrame.new(-w / 4 - 0.4, h / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), color, SM, { class = "WedgePart" })
		local right = part(parent, V(d + 2, h, w / 2 + 1.5), cf * CFrame.new(w / 4 + 0.4, h / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0), color, SM, { class = "WedgePart" })
		solid(left)
		solid(right)
	end

	local function windowGlow(parent, cf, w, h)
		local frame = part(parent, V(w + 0.8, h + 0.8, 0.5), cf, Color3.fromRGB(250, 245, 235), SM)
		local glass = part(parent, V(w, h, 0.6), cf * CFrame.new(0, 0, 0.05), Color3.fromRGB(255, 214, 140), Enum.Material.Neon)
		part(parent, V(0.4, h, 0.7), cf * CFrame.new(0, 0, 0.1), Color3.fromRGB(250, 245, 235), SM)
		part(parent, V(w, 0.4, 0.7), cf * CFrame.new(0, 0, 0.1), Color3.fromRGB(250, 245, 235), SM)
		return glass, frame
	end

	local function lampPost(parent, x, z)
		local base = at(x, 0, z)
		part(parent, V(2.2, 0.8, 2.2), base * CFrame.new(0, 0.4, 0), Color3.fromRGB(70, 60, 90), SM, { shape = Enum.PartType.Cylinder })
		solid(part(parent, V(0.6, 14, 0.6), base * CFrame.new(0, 7, 0), Color3.fromRGB(70, 60, 90), SM))
		local bulb = part(parent, V(2.4, 2.4, 2.4), base * CFrame.new(0, 14.6, 0), Color3.fromRGB(255, 220, 160), Enum.Material.Neon, { shape = Enum.PartType.Ball })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 205, 150)
		l.Range = 26
		l.Brightness = 0.9
		l.Shadows = false
		l.Parent = bulb
	end

	local function sminskiDeco(parent, cf, cid, pose, scale)
		local rig = Models.buildSminski(parent, scale or 1, Config.Character(cid), true, nil)
		Models.poseSminski(rig, cf, pose or "idle", math.random() * 10)
		return rig
	end

	---------------------------------------------------------------------------
	-- THE LOBBY: a Sminski diorama set on a brown side table in a cozy bedroom
	---------------------------------------------------------------------------
	local entranceParts = {}
	local penSign
	local statue
	local FY = Places.FLOOR_Y
	local WOOD = Color3.fromRGB(120, 78, 48)
	local DARKWOOD = Color3.fromRGB(70, 45, 32)
	local WARM = Color3.fromRGB(255, 196, 130)

	local lampLights = {} -- { light, nightBrightness }: dimmed by daylight
	local cityDots = {}
	local sky, rain, skyLight, wallClock
	local sideSkies = {} -- { part, light } for the windows
	local rainEmitters = {}
	local function light(parent, range, bright, color, kind)
		local l = Instance.new(kind or "PointLight")
		table.insert(lampLights, { l = l, b = bright })
		l.Range = range
		l.Brightness = bright
		l.Color = color or WARM
		l.Shadows = false
		l.Parent = parent
		return l
	end
	local function neonText(parent, cf, size, str, color, face)
		local p = part(parent, size, cf, Color3.fromRGB(30, 22, 40), SM)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face or Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 1.5
		local k = math.min(40, 260 / math.max(size.X, size.Y))
		sg.CanvasSize = Vector2.new(size.X * k, size.Y * k)
		UI.text(sg, str, { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = color, stroke = 0 })
		local st = sg:FindFirstChildWhichIsA("TextLabel")
		local g = Instance.new("UIStroke")
		g.Color = color
		g.Thickness = 3
		g.Transparency = 0.5
		g.Parent = st
		sg.Parent = p
		return p
	end
	-- a row of little books on a shelf (x along the shelf)
	local BOOK_COLS = { Color3.fromRGB(110, 170, 240), Color3.fromRGB(255, 125, 110), Color3.fromRGB(150, 205, 140), Color3.fromRGB(185, 160, 240),
		Color3.fromRGB(245, 196, 80), Color3.fromRGB(240, 235, 225), Color3.fromRGB(90, 70, 110), Color3.fromRGB(200, 120, 90) }
	local function bookRow(parent, cf, length, height, depth)
		local x = -length / 2
		local i = 0
		while x < length / 2 - 0.6 do
			i += 1
			local w = 0.6 + ((i * 37) % 5) * 0.18
			local h = height * (0.7 + ((i * 53) % 4) * 0.09)
			part(parent, V(w, h, depth), cf * CFrame.new(x + w / 2, h / 2, 0) * CFrame.Angles(0, 0, (i % 9 == 0) and 0.15 or 0), BOOK_COLS[i % #BOOK_COLS + 1], SM)
			x += w + 0.05
		end
	end

	-- an open-front diorama box. Returns its frame (local -Z = the open front)
	local function booth(e, w, d, h, wall, floor)
		local pos = HUB + e.pos
		local dir = V(math.sin(e.face), 0, math.cos(e.face))
		local cf = CFrame.lookAt(pos, pos + dir)
		local f = folder
		solid(part(f, V(w + 2, 1.2, d + 2), cf * CFrame.new(0, 0.6, 0), DARKWOOD, Enum.Material.Wood))
		part(f, V(w, 0.3, d), cf * CFrame.new(0, 1.3, 0), floor or Color3.fromRGB(190, 150, 110), Enum.Material.WoodPlanks)
		solid(part(f, V(w + 2, h, 1.4), cf * CFrame.new(0, h / 2, d / 2 + 0.7), DARKWOOD, Enum.Material.Wood))
		part(f, V(w, h - 1.5, 0.3), cf * CFrame.new(0, h / 2 + 0.6, d / 2 - 0.2), wall, SM)
		for _, sx in { -1, 1 } do
			solid(part(f, V(1.4, h, d + 2), cf * CFrame.new(sx * (w / 2 + 0.7), h / 2, 0), DARKWOOD, Enum.Material.Wood))
			part(f, V(0.3, h - 1.5, d), cf * CFrame.new(sx * (w / 2 - 0.2), h / 2 + 0.6, 0), wall:Lerp(Color3.new(0, 0, 0), 0.08), SM)
		end
		solid(part(f, V(w + 3, 1.6, d + 3), cf * CFrame.new(0, h + 0.8, 0), DARKWOOD, Enum.Material.Wood))
		part(f, V(w + 2, 2.2, 1.6), cf * CFrame.new(0, h - 1.1, -d / 2 - 0.2), DARKWOOD, Enum.Material.Wood)
		local bulb = part(f, V(1.6, 1.6, 1.6), cf * CFrame.new(0, h - 3, 0), Color3.fromRGB(255, 225, 170), Enum.Material.Neon, { shape = Enum.PartType.Ball })
		light(bulb, math.max(w, d) * 0.9, 1.1, WARM)
		return cf
	end
	local function boothSign(e, cf, h, iconName)
		local anchor = part(folder, V(1, 1, 1), cf * CFrame.new(0, h + 2, 0), Color3.new(), SM, { transparency = 1 })
		sign(folder, anchor, e.title, e.sub, e.color, iconName, 6)
		return anchor
	end

	local function buildCubbies(e)
		-- a lit display grid of little rooms, with a capsule machine in front
		local w, d, h = 50, 14, 46
		local pos = HUB + e.pos
		local dir = V(math.sin(e.face), 0, math.cos(e.face))
		local cf = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, 8)
		-- a real open shelf: back board, frame, dividers, and recessed cells, so
		-- nothing is coplanar (no flicker) and the figures stand inside the cells
		local T = 1.2 -- board thickness
		local MATTE = Enum.Material.Plaster
		local wood = Color3.fromRGB(150, 104, 70)
		part(folder, V(w, h, 1), cf * CFrame.new(0, h / 2, d / 2 - 0.5), DARKWOOD, Enum.Material.Wood) -- back
		for _, sx in { -1, 1 } do
			part(folder, V(T, h, d), cf * CFrame.new(sx * (w / 2 - T / 2), h / 2, 0), wood, Enum.Material.Wood)
		end
		local cols, rows = 4, 3
		local cellW = (w - T * (cols + 1)) / cols
		local cellH = (h - T * (rows + 1)) / rows
		for r = 0, rows do
			part(folder, V(w - T * 2, T, d), cf * CFrame.new(0, T / 2 + r * (cellH + T), 0), wood, Enum.Material.Wood) -- shelves
		end
		for c = 1, cols - 1 do
			part(folder, V(T, h - T * 2, d - 0.4), cf * CFrame.new(-w / 2 + T / 2 + c * (cellW + T), h / 2, 0.2), wood, Enum.Material.Wood) -- dividers
		end
		-- one invisible block keeps players out of the cells
		local block = part(folder, V(w, h, d), cf * CFrame.new(0, h / 2, 0), Color3.new(), SM, { transparency = 1 })
		solid(block)
		local ids = { "Glow", "Blush", "Sky", "Lemon", "Lavender", "Mint", "Peach", "Ghost", "Night", "Galaxy", "Secret", "Glow" }
		local walls = { Color3.fromRGB(250, 226, 190), Color3.fromRGB(205, 228, 248), Color3.fromRGB(250, 210, 222), Color3.fromRGB(216, 240, 204) }
		local i = 0
		for row = 0, rows - 1 do
			local y0 = T + row * (cellH + T) -- top of the shelf board under this row
			for col = 0, cols - 1 do
				i += 1
				local cx = -w / 2 + T + cellW / 2 + col * (cellW + T)
				-- painted back of the cell, set well in front of the back board
				part(folder, V(cellW, cellH, 0.4), cf * CFrame.new(cx, y0 + cellH / 2, d / 2 - 1.6), walls[(i + row) % #walls + 1], MATTE, { noShadow = true })
				-- little round stand + the figure, inside the cell
				part(folder, V(0.6, 6, 6), cf * CFrame.new(cx, y0 + 0.3, 0.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 232), MATTE, { shape = Enum.PartType.Cylinder, noShadow = true })
				sminskiDeco(folder, cf * CFrame.new(cx, y0 + 0.6, 0.5) * CFrame.Angles(0, math.pi, 0), ids[i], Config.Character(ids[i]).idle, 1.9)
			end
			-- one soft strip light per row, tucked under the shelf above
			local strip = part(folder, V(w - T * 4, 0.3, 0.8), cf * CFrame.new(0, y0 + cellH - 0.2, -d / 2 + 1.2), Color3.fromRGB(255, 236, 205), Enum.Material.Neon, { noShadow = true })
			light(strip, 16, 0.35, WARM)
		end
		-- the capsule machine
		local m = CFrame.lookAt(pos, pos + dir) * CFrame.new(20, 0, -8)
		solid(part(folder, V(9, 9, 9), m * CFrame.new(0, 4.5, 0), Color3.fromRGB(255, 125, 110), SM))
		local dome = part(folder, V(10, 10, 10), m * CFrame.new(0, 13.5, 0), Color3.fromRGB(225, 240, 255), SM, { shape = Enum.PartType.Ball, noShadow = true })
		dome.Transparency = 0.7
		for k = 1, 10 do
			local a = k * 2.39
			part(folder, V(2.2, 2.2, 2.2), m * CFrame.new(math.cos(a) * (k % 3 + 1), 11 + (k % 3) * 1.4, math.sin(a) * (k % 3 + 1)), walls[k % #walls + 1]:Lerp(Color3.fromRGB(255, 120, 150), 0.4), SM, { shape = Enum.PartType.Ball })
		end
		local door = part(folder, V(12, 12, 0.4), m * CFrame.new(0, 6, -5), Color3.new(), SM, { transparency = 1 })
		entranceParts[e.id] = door
		boothSign(e, cf, h, "capsule")
	end

	-- the Sminski Garden (its own module: planter, growing plants, garden screen)
	local Garden = require(script.Parent:WaitForChild("Garden"))({
		Config = Config, UI = UI, Audio = Audio, Places = Places, ctx = ctx, part = part, player = player,
	})
	Hub.Garden = Garden

	local Streets = require(script.Parent:WaitForChild("HubStreets"))({
		part = part, solid = solid, light = light, UI = UI, Places = Places, HUB = HUB,
	})

	-- every other diorama lives in HubSets (board-built, matte, one lamp each)
	local Sets = require(script.Parent:WaitForChild("HubSets"))({
		folder = function() return folder end,
		part = part, solid = solid, light = light, sign = sign, deco = sminskiDeco, neonText = neonText,
		World = World, Models = Models, Config = Config, UI = UI, C = C, ctx = ctx,
		HUB = HUB, BOOK_COLS = BOOK_COLS, WARM = WARM, entranceParts = entranceParts,
		setPen = function(t) penSign = t end,
		setPup = function(t) Hub.pup = t end,
	})

	---------------------------------------------------------------------------
	-- THE BEDROOM around the table (all far bigger than a Sminski)
	---------------------------------------------------------------------------
	local person
	local function fairyLights(from, to, n, sag)
		for i = 0, n do
			local k = i / n
			local p = from:Lerp(to, k) - V(0, math.sin(k * math.pi) * sag, 0)
			local b = part(folder, V(1.6, 1.6, 1.6), CFrame.new(HUB + p), Color3.fromRGB(255, 220, 150), Enum.Material.Neon, { shape = Enum.PartType.Ball, noShadow = true })
			if i % 5 == 0 then light(b, 26, 0.35, WARM) end
		end
	end

	-- Blender furniture (ReplicatedStorage.SminskiAssets, from art/blender/room.py):
	-- cf is the floor point + facing; the model is stood on it at its own size.
	-- Returns nil when the mesh isn't imported so the primitive version is built.
	local function roomCF(name, cf, scale)
		local src = World.asset(name)
		if not src then return nil end
		local _, ext = src:GetBoundingBox()
		ext = ext * (scale or 1)
		local m = World.placeAsset(folder, name, cf * CFrame.new(0, ext.Y / 2, 0), ext)
		if m then m:SetAttribute("Height", ext.Y) end
		return m
	end
	local function room(name, x, y, z, yaw, scale)
		return roomCF(name, at(x, y, z) * CFrame.Angles(0, yaw or 0, 0), scale)
	end

	local function buildBedroom()
		local f = folder
		-- a normal-sized bedroom; our side table stands right beside the gaming
		-- desk (on the gamer's right), so from the table you see their face
		local RX0, RX1, RZ0, RZ1, TOP = -470, 205, Places.HubGateZ, 245, 190
		local rng = Random.new(7)
		-- floor, walls, ceiling
		part(f, V(RX1 - RX0, 2, RZ1 - RZ0), at((RX0 + RX1) / 2, FY - 1, (RZ0 + RZ1) / 2), Color3.fromRGB(150, 105, 72), Enum.Material.WoodPlanks)
		local wall = Color3.fromRGB(196, 182, 230)
		-- desk wall, with an arched hole where the bridge to Sminski City goes in
		do
			local deskWall = wall:Lerp(Color3.new(0, 0, 0), 0.05)
			local gx, hw, hTop = Places.HubGateX, 13, 22 -- (the bridge deck is 22 wide)
			local function wallPiece(x0, x1, y0, y1)
				part(f, V(x1 - x0, y1 - y0, 4), at((x0 + x1) / 2, (y0 + y1) / 2, RZ0 - 2), deskWall, SM)
			end
			wallPiece(RX0, gx - hw, FY, TOP)
			wallPiece(gx + hw, RX1, FY, TOP)
			wallPiece(gx - hw, gx + hw, FY, -1)
			wallPiece(gx - hw, gx + hw, hTop, TOP) -- the arch itself is drawn on the wall face (see buildGate)
		end
		part(f, V(RX1 - RX0, TOP - FY, 4), at((RX0 + RX1) / 2, (TOP + FY) / 2, RZ1 + 2), wall, SM)
		part(f, V(4, TOP - FY, RZ1 - RZ0), at(RX0 - 2, (TOP + FY) / 2, (RZ0 + RZ1) / 2), wall:Lerp(Color3.new(0, 0, 0), 0.03), SM)
		part(f, V(4, TOP - FY, RZ1 - RZ0), at(RX1 + 2, (TOP + FY) / 2, (RZ0 + RZ1) / 2), wall:Lerp(Color3.new(0, 0, 0), 0.03), SM)
		part(f, V(RX1 - RX0, 4, RZ1 - RZ0), at((RX0 + RX1) / 2, TOP + 2, (RZ0 + RZ1) / 2), Color3.fromRGB(235, 228, 245), SM)
		for _, z in { RZ0 + 1, RZ1 - 1 } do
			part(f, V(RX1 - RX0, 5, 2), at((RX0 + RX1) / 2, FY + 2.5, z), Color3.fromRGB(245, 240, 250), SM)
		end

		-- THE TABLE the Sminskis live on
		local TX, TZ = Places.TABLE_X, Places.TABLE_Z
		solid(part(f, V(TX * 2 + 10, 4, TZ * 2 + 10), at(0, -2, 0), WOOD, Enum.Material.Wood))
		part(f, V(TX * 2 + 12, 2, TZ * 2 + 12), at(0, -4.5, 0), DARKWOOD, Enum.Material.Wood)
		for _, x in { -TX, TX } do for _, z in { -TZ, TZ } do
			part(f, V(7, -FY - 4, 7), at(x, (FY - 4) / 2, z), DARKWOOD, Enum.Material.Wood)
		end end
		-- a warm desk lamp on the table's back corner lighting the set
		local lb = at(TX - 12, 0, TZ - 12)
		local lampModel = roomCF("TableLamp", lb)
		local shade = lampModel and lampModel:FindFirstChild("Bulb")
		if not shade then
			part(f, V(3, 20, 20), lb * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 235, 230), SM, { shape = Enum.PartType.Cylinder })
			part(f, V(2.4, 110, 2.4), lb * CFrame.new(0, 56, 0), Color3.fromRGB(240, 235, 230), SM)
			part(f, V(2, 2, 30), lb * CFrame.new(-9, 111, -9) * CFrame.Angles(0, -math.pi / 4, 0), Color3.fromRGB(240, 235, 230), SM)
			shade = part(f, V(34, 22, 34), lb * CFrame.new(-18, 110, -18), Color3.fromRGB(255, 235, 200), SM, { mesh = Enum.MeshType.Sphere })
		end
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 95
		spot.Range = 200
		spot.Brightness = 1.1
		spot.Color = Color3.fromRGB(255, 205, 150)
		spot.Shadows = true
		spot.Parent = shade
		table.insert(lampLights, { l = spot, b = 1.1 })

		-- the desk wall: two windows (left + right of the gamer), neon signs, clock
		local function window(xc, w, h)
			local cfw = CFrame.new(HUB + V(xc, 70, RZ0 + 1)) * CFrame.Angles(0, math.pi, 0)
			part(f, V(w + 8, h + 8, 3), cfw, Color3.fromRGB(250, 246, 252), SM)
			local g = part(f, V(w, h, 1), cfw * CFrame.new(0, 0, -1.6), Color3.fromRGB(18, 22, 55), Enum.Material.Neon)
			g.Transparency = 0.15
			local l = light(g, 170, 0.5, Color3.fromRGB(110, 130, 255), "SurfaceLight")
			l.Face = Enum.NormalId.Front
			table.insert(sideSkies, { part = g, light = l })
			part(f, V(3, h, 4), cfw * CFrame.new(0, 0, -2.4), Color3.fromRGB(250, 246, 252), SM)
			part(f, V(w, 3, 4), cfw * CFrame.new(0, 0, -2.4), Color3.fromRGB(250, 246, 252), SM)
			part(f, V(w + 14, 4, 12), cfw * CFrame.new(0, -h / 2 - 4, -6), Color3.fromRGB(250, 246, 252), SM) -- sill
			for i = 1, 22 do
				local d = part(f, V(rng:NextNumber(2, 5), rng:NextNumber(2, 4), 0.4), cfw * CFrame.new(rng:NextNumber(-w / 2 + 3, w / 2 - 3), rng:NextNumber(-h / 2 + 3, h * 0.1), -2), ({ Color3.fromRGB(255, 210, 120), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 240, 200) })[i % 4 + 1], Enum.Material.Neon, { noShadow = true })
				table.insert(cityDots, d)
			end
			local att = Instance.new("Attachment")
			att.Position = V(0, h / 2, 0)
			att.Parent = g
			local r = Instance.new("ParticleEmitter")
			r.Rate = 30
			r.Lifetime = NumberRange.new(1.2, 2)
			r.Speed = NumberRange.new(30, 50)
			r.EmissionDirection = Enum.NormalId.Bottom
			r.Size = NumberSequence.new(0.25)
			r.Transparency = NumberSequence.new(0.6)
			r.Color = ColorSequence.new(Color3.fromRGB(180, 200, 255))
			r.Parent = att
			table.insert(rainEmitters, r)
			for _, sx in { -1, 1 } do
				if not roomCF("Curtain", cfw * CFrame.new(sx * (w / 2 + 12), -84, -6)) then
					part(f, V(18, h + 40, 7), cfw * CFrame.new(sx * (w / 2 + 12), -12, -6), Color3.fromRGB(165, 125, 185), Enum.Material.Fabric)
				end
			end
			-- a little plant on the sill
			if not roomCF("SillPlant", cfw * CFrame.new(w / 2 - 8, -h / 2 - 2, -7), 1.3) then
				part(f, V(8, 8, 8), cfw * CFrame.new(w / 2 - 8, -h / 2 + 2, -7) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), SM, { shape = Enum.PartType.Cylinder })
				part(f, V(10, 12, 10), cfw * CFrame.new(w / 2 - 8, -h / 2 + 10, -7), Color3.fromRGB(110, 185, 95), Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
			end
		end
		window(-418, 80, 100)
		window(-88, 80, 100)
		local wallZ = RZ0 + 3
		local gg = neonText(f, CFrame.new(HUB + V(-272, 150, wallZ)) * CFrame.Angles(0, math.pi, 0), V(70, 18, 1), "GAME ON", Color3.fromRGB(255, 120, 220), Enum.NormalId.Front)
		light(gg, 70, 0.7, Color3.fromRGB(255, 120, 220))
		wallClock = neonText(f, CFrame.new(HUB + V(-272, 124, wallZ)) * CFrame.Angles(0, math.pi, 0), V(34, 12, 1), "00:00", Color3.fromRGB(150, 230, 255), Enum.NormalId.Front)
		light(wallClock, 40, 0.4, Color3.fromRGB(150, 230, 255))
		local moon = part(f, V(26, 26, 3), CFrame.new(HUB + V(-332, 146, wallZ)), Color3.fromRGB(255, 220, 120), Enum.Material.Neon, { mesh = Enum.MeshType.Sphere, noShadow = true })
		part(f, V(22, 22, 4), CFrame.new(HUB + V(-325, 150, wallZ + 1.5)), wall:Lerp(Color3.new(0, 0, 0), 0.05), SM, { mesh = Enum.MeshType.Sphere })
		light(moon, 60, 0.6, Color3.fromRGB(255, 220, 120))
		local faceSign = part(f, V(28, 28, 3), CFrame.new(HUB + V(-168, 146, wallZ)), Color3.fromRGB(150, 255, 120), Enum.Material.Neon, { mesh = Enum.MeshType.Sphere, noShadow = true })
		for _, sx in { -1, 1 } do part(f, V(3, 5, 1), CFrame.new(HUB + V(-168 + sx * 5, 149, wallZ + 2.5)), Color3.fromRGB(30, 60, 30), SM) end
		light(faceSign, 60, 0.6, Color3.fromRGB(150, 255, 120))

		-- the gaming desk + the gamer (the table is on their right)
		local dz = RZ0 + 38
		local dy = FY + 46
		local dx = -272
		local deskTop = FY + 48 -- desk surface
		if not room("GamingDesk", dx, FY, dz) then
			part(f, V(230, 4, 72), at(dx, dy, dz), Color3.fromRGB(248, 248, 252), SM)
			for _, x in { dx - 108, dx + 108 } do part(f, V(6, 44, 64), at(x, FY + 23, dz), Color3.fromRGB(240, 240, 245), SM) end
			part(f, V(90, 3, 56), at(dx, dy + 0.6, dz + 6), Color3.fromRGB(60, 50, 90), Enum.Material.Fabric) -- desk mat
		end
		for i, x in { dx - 38, dx + 38 } do
			local yaw = (i == 1 and -0.14 or 0.14)
			local monModel = room("Monitor", x, deskTop, dz - 16, yaw)
			local screen = monModel and monModel:FindFirstChild("Screen")
			if not screen then
				local mon = part(f, V(66, 38, 3), at(x, dy + 34, dz - 16) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(30, 30, 38), SM)
				screen = part(f, V(62, 34, 0.6), mon.CFrame * CFrame.new(0, 0, 1.8), Color3.fromRGB(80, 90, 200), Enum.Material.Neon)
				part(f, V(6, 16, 6), at(x, dy + 10, dz - 18), Color3.fromRGB(40, 40, 48), SM)
			end
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Back
			sg.LightInfluence = 0
			sg.Brightness = 1.4
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundColor3 = Color3.fromRGB(40, 30, 80)
			img.Image = i == 1 and UI.Art.hero or UI.Art.logo
			img.ScaleType = Enum.ScaleType.Crop
			img.Parent = sg
			sg.Parent = screen
			light(screen, 70, 1, Color3.fromRGB(150, 160, 255), "SurfaceLight").Face = Enum.NormalId.Back
		end
		if not room("Keyboard", dx, deskTop, dz + 18) then
			part(f, V(44, 2, 14), at(dx, dy + 3, dz + 18), Color3.fromRGB(30, 30, 38), SM)
			local kbGlow = part(f, V(42, 0.6, 12), at(dx, dy + 4.2, dz + 18), Color3.fromRGB(190, 120, 255), Enum.Material.Neon)
			kbGlow.Transparency = 0.3
		end
		if not room("Mouse", dx + 36, deskTop, dz + 18, -0.3) then
			part(f, V(7, 2, 11), at(dx + 36, dy + 3, dz + 18), Color3.fromRGB(30, 30, 38), SM, { mesh = Enum.MeshType.Sphere })
		end
		-- snacks + a can on the desk
		if not room("SodaCan", dx - 70, deskTop, dz + 14, 0.5, 1.5) then
			part(f, V(7, 12, 7), at(dx - 70, dy + 8, dz + 14), Color3.fromRGB(235, 90, 90), SM, { shape = Enum.PartType.Cylinder }).CFrame = at(dx - 70, dy + 8, dz + 14) * CFrame.Angles(0, 0, math.pi / 2)
		end
		part(f, V(18, 4, 12), at(dx - 86, dy + 4, dz + 4) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(255, 205, 80), SM)
		-- RGB PC tower at the left end of the desk
		local tower = room("PCTower", dx - 88, deskTop, dz - 4)
		local tg = tower and tower:FindFirstChild("Glass")
		if not tg then
			part(f, V(26, 56, 52), at(dx - 88, dy + 30, dz - 4), Color3.fromRGB(25, 25, 32), SM)
			tg = part(f, V(0.6, 50, 46), at(dx - 74.8, dy + 30, dz - 4), Color3.fromRGB(160, 100, 255), Enum.Material.Neon)
			tg.Transparency = 0.45
			for k = 0, 2 do
				part(f, V(0.8, 12, 12), at(dx - 75.4, dy + 16 + k * 14, dz - 4) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 230, 255), Enum.Material.Neon, { shape = Enum.PartType.Cylinder })
			end
		end
		light(tg, 60, 1.4, Color3.fromRGB(170, 110, 255))
		local deskLamp = part(f, V(12, 8, 12), at(dx + 90, dy + 30, dz - 14), Color3.fromRGB(255, 225, 170), Enum.Material.Neon, { mesh = Enum.MeshType.Sphere })
		light(deskLamp, 110, 0.9, WARM)
		part(f, V(1.4, 26, 1.4), at(dx + 90, dy + 15, dz - 14), Color3.fromRGB(60, 60, 70), SM)
		-- gaming chair + the gamer
		local cz = dz + 70
		local chair = room("GamingChair", dx, FY, cz, math.pi - 0.4)
		local seatY = FY + (chair and 25 or 22)
		if not chair then
			part(f, V(44, 6, 40), CFrame.new(HUB + V(dx, seatY - 3, cz)), Color3.fromRGB(40, 40, 50), SM)
			part(f, V(44, 50, 8), CFrame.new(HUB + V(dx, seatY + 20, cz + 22)) * CFrame.Angles(-0.12, 0, 0), Color3.fromRGB(180, 150, 240), Enum.Material.Fabric)
			part(f, V(4, seatY - FY - 6, 4), CFrame.new(HUB + V(dx, (seatY + FY) / 2 - 3, cz)), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
			part(f, V(30, 2, 30), CFrame.new(HUB + V(dx, FY + 2, cz)), Color3.fromRGB(40, 40, 50), SM)
		end
		person =Models.buildKid(f, { scale = 2.7, hoodie = Color3.fromRGB(150, 125, 220), pants = Color3.fromRGB(70, 70, 90), cap = false, hair = Color3.fromRGB(60, 40, 35), name = "Roommate", face = "kidCalm" })
		-- turned a little toward the table so the Sminskis can see their face
		person.seatCF = CFrame.new(HUB + V(dx, seatY, cz + 2)) * CFrame.Angles(0, math.pi - 0.4, 0)
		Models.addHeadphones(person, Color3.fromRGB(40, 40, 50), Color3.fromRGB(120, 230, 255))
		Hub.person = person
		-- a round rug under the chair
		part(f, V(1, 170, 170), at(dx, FY + 0.5, cz - 10) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(235, 220, 245), Enum.Material.Fabric, { shape = Enum.PartType.Cylinder })

		-- the bed along the left wall, head against the back wall
		local bx = RX0 + 82
		local bz0, bz1 = 30, RZ1 - 4
		local bz = (bz0 + bz1) / 2
		local blen = bz1 - bz0
		if not room("Bed", bx, FY, bz) then
			part(f, V(160, 26, blen), at(bx, FY + 13, bz), Color3.fromRGB(165, 118, 82), Enum.Material.Wood)
			part(f, V(154, 18, blen - 6), at(bx, FY + 34, bz), Color3.fromRGB(252, 248, 244), Enum.Material.Fabric)
			part(f, V(162, 18, blen * 0.62), at(bx, FY + 43, bz0 + blen * 0.31), Color3.fromRGB(220, 190, 210), Enum.Material.Fabric)
			part(f, V(170, 80, 10), at(bx, FY + 58, RZ1 - 4), Color3.fromRGB(165, 118, 82), Enum.Material.Wood)
			for _, x in { -38, 38 } do part(f, V(62, 24, 34), at(bx + x, FY + 54, bz1 - 26), Color3.fromRGB(255, 250, 250), Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere }) end
		end
		-- a giant sleepy cat plush + little plushies
		local plush = Color3.fromRGB(90, 105, 140)
		if not room("CatPlush", bx + 10, FY + 44, bz1 - 60, math.pi - 0.15) then
			part(f, V(100, 90, 76), at(bx + 10, FY + 90, bz1 - 60), plush, Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
			part(f, V(76, 50, 48), at(bx + 10, FY + 86, bz1 - 92), Color3.fromRGB(235, 225, 205), Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
			part(f, V(76, 60, 60), at(bx + 10, FY + 145, bz1 - 62), plush, Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
			for _, sx in { -1, 1 } do
				part(f, V(18, 26, 12), at(bx + 10 + sx * 26, FY + 175, bz1 - 60) * CFrame.Angles(0, 0, -sx * 0.4), plush, Enum.Material.Fabric, { class = "WedgePart" })
				part(f, V(12, 3, 2), at(bx + 10 + sx * 14, FY + 147, bz1 - 92) * CFrame.Angles(0, 0, sx * 0.15), Color3.fromRGB(35, 30, 45), SM)
			end
		end
		for k, col in { Color3.fromRGB(255, 205, 80), Color3.fromRGB(255, 170, 190), Color3.fromRGB(150, 130, 230) } do
			local bear = room("Plushie", bx - 50 + k * 26, FY + 58, bz0 + 60 + k * 10, math.pi + 0.9 - k * 0.6)
			if bear then
				local body = bear:FindFirstChild("Body")
				if body then body.Color = col end
			else
				part(f, V(26, 24, 20), at(bx - 50 + k * 26, FY + 55, bz0 + 60 + k * 10), col, Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
				part(f, V(18, 16, 16), at(bx - 50 + k * 26, FY + 74, bz0 + 60 + k * 10), col, Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
			end
		end
		fairyLights(V(RX0 + 4, FY + 104, RZ1 - 6), V(RX0 + 164, FY + 104, RZ1 - 6), 20, 8)
		-- nightstand with the glowing moon lamp + a book
		if not room("Nightstand", bx + 106, FY, RZ1 - 26, math.pi) then
			part(f, V(44, 48, 40), at(bx + 106, FY + 24, RZ1 - 26), Color3.fromRGB(165, 118, 82), Enum.Material.Wood)
		end
		local moonModel = room("MoonLamp", bx + 106, FY + 48.5, RZ1 - 26)
		local moonLamp = moonModel and moonModel:FindFirstChild("Bulb")
		if not moonLamp then
			moonLamp = part(f, V(24, 24, 24), at(bx + 106, FY + 60, RZ1 - 26), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, { shape = Enum.PartType.Ball })
		end
		light(moonLamp, 90, 0.9, Color3.fromRGB(255, 225, 180))
		part(f, V(18, 4, 24), at(bx + 96, FY + 50.5, RZ1 - 30) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(110, 150, 220), SM)
		-- laundry basket at the foot of the bed
		if not room("LaundryBasket", RX0 + 40, FY, 0, 0.4) then
			part(f, V(40, 36, 36), at(RX0 + 40, FY + 18, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(220, 200, 170), Enum.Material.Fabric, { shape = Enum.PartType.Cylinder })
			part(f, V(34, 14, 30), at(RX0 + 40, FY + 38, 0), Color3.fromRGB(140, 190, 240), Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
		end

		-- THE BACKING behind the games row: a floor-to-ceiling plant shelf right
		-- behind the table, so looking past the huts you see books + greenery
		do
			local SZ = 118 -- shelf centre z (front face ~100, just past the table)
			local vine = Color3.fromRGB(105, 175, 90)
			local vine2 = Color3.fromRGB(135, 200, 110)
			local function trail(x, y, z, n, drift)
				for i = 0, n do
					local k = i / n
					local sway = math.sin(i * 1.7 + x) * 1.2
					part(f, V(3.4 - k * 1.2, 2.2, 3.4 - k * 1.2), at(x + sway + drift * k, y - i * 2.4, z - k * 2.5), i % 2 == 0 and vine or vine2, SM, { mesh = Enum.MeshType.Sphere })
					if i % 3 == 1 then
						part(f, V(5, 0.4, 3.2), at(x + sway + drift * k + 2, y - i * 2.4 - 0.6, z - k * 2.5) * CFrame.Angles(0.3, 0.4 * i, -0.4), vine2, SM, { mesh = Enum.MeshType.Sphere })
					end
				end
			end
			local shelfYs = {}
			for i, x in { -110, 0, 110 } do
				local bc = room("Bookcase", x, FY, SZ, math.pi, 1.2)
				if not bc then
					part(f, V(108, 182, 36), at(x, FY + 91, SZ), Color3.fromRGB(165, 118, 82), Enum.Material.Wood)
				end
			end
			for sh = 0, 4 do shelfYs[sh + 1] = FY + 9.6 + sh * 34.8 end
			local rng2 = Random.new(21)
			for i, x0 in { -110, 0, 110 } do
				for sh, y in shelfYs do
					if not World.asset("Bookcase") then
						part(f, V(103, 2.4, 31), at(x0, y, SZ + 3), Color3.fromRGB(150, 105, 72), Enum.Material.Wood)
					end
					local kind = (i + sh) % 3
					local x = x0 - 46
					local k = 0
					while x < x0 + 40 do
						k += 1
						local r = rng2:NextNumber()
						if kind == 0 or r < 0.55 then
							local w = 3 + (k * 7) % 5
							local h = 20 + (k * 11) % 10
							part(f, V(w, h, 22), at(x + w / 2, y + 1.2 + h / 2, SZ + 4), BOOK_COLS[(k + sh + i) % #BOOK_COLS + 1], SM)
							x += w + 0.4
						elseif r < 0.8 then
							-- a potted trailing plant that spills over the shelf edge
							if not room("SillPlant", x + 6, y + 1.2, SZ + 2, rng2:NextNumber(0, 6), 1.6) then
								part(f, V(9, 8, 9), at(x + 6, y + 5.2, SZ + 2) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), SM, { shape = Enum.PartType.Cylinder })
								part(f, V(12, 9, 12), at(x + 6, y + 12, SZ + 2), vine, Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
							end
							trail(x + 6, y + 8, SZ - 14, 5 + (k % 4) * 2, rng2:NextNumber(-3, 3))
							x += 16
						else
							sminskiDeco(f, at(x + 5, y + 1.2, SZ - 2), ({ "Sky", "Lemon", "Peach", "Night", "Blush", "Lavender" })[(k + sh * 2 + i) % 6 + 1], ({ "idle", "sit", "cheer", "yoga" })[k % 4 + 1], 3.2)
							x += 14
						end
					end
				end
				-- big plants on top, vines pouring down the front
				if not room("PottedPlant", x0 - 30 + i * 8, FY + 182, SZ + 6, rng2:NextNumber(0, 6), 0.65) then
					part(f, V(14, 16, 14), at(x0 - 30 + i * 8, FY + 190, SZ + 6) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), SM, { shape = Enum.PartType.Cylinder })
					part(f, V(30, 26, 30), at(x0 - 30 + i * 8, FY + 210, SZ + 6), vine, Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
				end
				for _, tx in { x0 - 48, x0 + 20, x0 + 44 } do
					trail(tx, FY + 183, SZ - 16, 12 + (i * 3) % 6, rng2:NextNumber(-4, 4))
				end
				-- a warm strip light under the top of each case
				local strip = part(f, V(100, 0.8, 4), at(x0, FY + 179, SZ - 14), Color3.fromRGB(255, 225, 170), Enum.Material.Neon, { noShadow = true })
				light(strip, 90, 0.45, WARM)
			end
			-- a hanging ivy garland along the top edge
			for i = 0, 36 do
				local x = -175 + i * 9.7
				local sag = math.sin((i / 36) * math.pi * 4) * 6
				part(f, V(6, 4, 6), at(x, FY + 186 - math.abs(sag), SZ - 18), i % 2 == 0 and vine or vine2, SM, { mesh = Enum.MeshType.Sphere })
			end
		end

		-- dresser on the back wall, between the bed and the plant shelf
		local drx = -243
		if not room("Dresser", drx, FY, RZ1 - 18, math.pi) then
			part(f, V(110, 70, 34), at(drx, FY + 35, RZ1 - 18), Color3.fromRGB(245, 240, 235), SM)
			for r = 0, 2 do for c = 0, 1 do
				part(f, V(50, 18, 1), at(drx - 26 + c * 52, FY + 14 + r * 22, RZ1 - 35.2), Color3.fromRGB(235, 228, 222), SM)
				part(f, V(8, 2, 2), at(drx - 26 + c * 52, FY + 14 + r * 22, RZ1 - 36.4), Color3.fromRGB(200, 170, 110), Enum.Material.Metal)
			end end
		end
		local frame = part(f, V(22, 28, 2), at(drx - 30, FY + 86, RZ1 - 20) * CFrame.Angles(-0.1, 0, 0), Color3.fromRGB(240, 235, 230), SM)
		local fg = Instance.new("SurfaceGui")
		fg.Face = Enum.NormalId.Front
		fg.LightInfluence = 0.6
		local fi = Instance.new("ImageLabel")
		fi.Size = UDim2.fromScale(0.86, 0.9)
		fi.Position = UDim2.fromScale(0.07, 0.05)
		fi.Image = UI.Art.chars.Blush
		fi.BackgroundColor3 = Color3.fromRGB(255, 225, 235)
		fi.Parent = fg
		fg.Parent = frame
		frame.CFrame = frame.CFrame * CFrame.Angles(0, math.pi, 0)
		if not room("SillPlant", drx + 30, FY + 71, RZ1 - 20, 0.7, 2.2) then
			part(f, V(12, 16, 12), at(drx + 30, FY + 78, RZ1 - 20) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), SM, { shape = Enum.PartType.Cylinder })
			part(f, V(22, 26, 22), at(drx + 30, FY + 98, RZ1 - 20), Color3.fromRGB(100, 175, 90), Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
		end
		local function poster(x, y, w, h, img)
			local p = part(f, V(w, h, 0.6), CFrame.new(HUB + V(x, y, RZ1 - 1)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(250, 250, 250), SM)
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.LightInfluence = 0.5
			local i = Instance.new("ImageLabel")
			i.Size = UDim2.fromScale(1, 1)
			i.Image = img
			i.ScaleType = Enum.ScaleType.Crop
			i.BackgroundColor3 = Color3.fromRGB(60, 50, 110)
			i.Parent = sg
			sg.Parent = p
		end
		poster(drx - 20, 60, 70, 40, UI.Art.hero)
		poster(drx + 55, 70, 34, 48, UI.Art.chars.Galaxy)
		poster(192, 60, 22, 30, UI.Art.chars.Mint)
		fairyLights(V(-300, TOP - 12, RZ1 - 4), V(RX1 - 6, TOP - 12, RZ1 - 4), 30, 14)

		-- bookcase + cork board on the right wall, bean bag in the corner
		local bcx = RX1 - 18
		local bookcase = room("Bookcase", bcx, FY, 110, -math.pi / 2)
		if not bookcase then
			part(f, V(30, 150, 90), at(bcx, FY + 75, 110), Color3.fromRGB(165, 118, 82), Enum.Material.Wood)
		end
		for sh = 0, 4 do
			local y = FY + 8 + sh * 29
			if not bookcase then
				part(f, V(28, 2, 86), at(bcx - 2, y, 110), Color3.fromRGB(150, 105, 72), Enum.Material.Wood)
			end
			local z = 70
			local k = 0
			while z < 150 do
				k += 1
				local w = 3 + (k * 7) % 4
				local h = 18 + (k * 11) % 8
				part(f, V(20, h, w), at(bcx - 6, y + 1 + h / 2, z + w / 2), BOOK_COLS[(k + sh) % #BOOK_COLS + 1], SM)
				z += w + 0.4
				if k % 9 == 0 then
					sminskiDeco(f, at(bcx - 6, y + 1, z + 6) * CFrame.Angles(0, -math.pi / 2, 0), ({ "Sky", "Lemon", "Peach", "Night" })[(k / 9) % 4 + 1], "idle", 4)
					z += 14
				end
			end
		end
		local cork = part(f, V(2, 50, 70), at(RX1 - 1, 70, -60), Color3.fromRGB(200, 160, 110), Enum.Material.Wood)
		for k = 0, 5 do
			part(f, V(1, 12, 12), at(RX1 - 2.2, 60 + (k % 2) * 16, -86 + k * 10) * CFrame.Angles((k % 3 - 1) * 0.1, 0, 0), ({ Color3.fromRGB(255, 240, 130), Color3.fromRGB(255, 190, 210), Color3.fromRGB(180, 230, 255) })[k % 3 + 1], SM)
		end
		if not room("BeanBag", -196, FY, 70, 2.4) then
			part(f, V(60, 40, 60), at(-196, FY + 20, 70), Color3.fromRGB(255, 170, 120), Enum.Material.Fabric, { mesh = Enum.MeshType.Sphere })
		end
		-- a tall plant in the corner by the desk wall
		if not room("PottedPlant", -440, FY, RZ0 + 22, 0.8) then
			part(f, V(26, 30, 26), at(-440, FY + 15, RZ0 + 22) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), SM, { shape = Enum.PartType.Cylinder })
			for k = 0, 5 do
				part(f, V(18, 50, 18), at(-440 + math.cos(k) * 10, FY + 55 + (k % 3) * 10, RZ0 + 22 + math.sin(k) * 10) * CFrame.Angles(math.sin(k) * 0.4, 0, math.cos(k) * 0.4), Color3.fromRGB(100, 175, 90), Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
			end
		end
		-- a round ceiling light + fairy lights along the desk wall
		local ceilModel = room("CeilingLamp", -100, TOP - 18, 20)
		local ceilingLamp = ceilModel and ceilModel:FindFirstChild("Bulb")
		if not ceilingLamp then
			ceilingLamp = part(f, V(40, 10, 40), at(-100, TOP - 6, 20), Color3.fromRGB(255, 240, 215), Enum.Material.Neon, { mesh = Enum.MeshType.Sphere })
		end
		light(ceilingLamp, 220, 0.55, Color3.fromRGB(255, 230, 200))
		fairyLights(V(RX0 + 6, TOP - 12, RZ0 + 5), V(RX1 - 6, TOP - 12, RZ0 + 5), 40, 12)
		Streets.buildGate(folder, { wallZ = RZ0, tableZ = -Places.TABLE_Z, FY = FY })
		-- soft fill so everything reads from the table
		for _, spotPos in { V(-250, 60, -60), V(-300, 60, 150), V(100, 70, 150) } do
			local anchor = part(f, V(1, 1, 1), CFrame.new(HUB + spotPos), Color3.new(), SM, { transparency = 1 })
			light(anchor, 200, 0.3, Color3.fromRGB(200, 175, 255))
		end
	end

	---------------------------------------------------------------------------
	-- DESK CLUTTER: everyday things, giant next to a Sminski
	---------------------------------------------------------------------------
	local function hexPencil(cf, len, col)
		part(folder, V(len * 0.78, 2.6, 2.6), cf * CFrame.Angles(0, 0, 0), col, SM, { shape = Enum.PartType.Cylinder })
		part(folder, V(len * 0.07, 2.7, 2.7), cf * CFrame.new(-len * 0.42, 0, 0), Color3.fromRGB(205, 205, 215), Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
		part(folder, V(len * 0.09, 2.6, 2.6), cf * CFrame.new(-len * 0.5, 0, 0), Color3.fromRGB(255, 150, 170), SM, { shape = Enum.PartType.Cylinder })
		local tip = part(folder, V(len * 0.14, 2.6, 2.6), cf * CFrame.new(len * 0.46, 0, 0), Color3.fromRGB(240, 205, 160), Enum.Material.Wood, { mesh = Enum.MeshType.Sphere })
		return tip
	end
	local function buildTabletop()
		local f = folder
		-- a stack of giant books you can climb like stairs
		local bookCols = { Color3.fromRGB(110, 150, 220), Color3.fromRGB(230, 110, 100), Color3.fromRGB(140, 195, 130) }
		for i = 0, 2 do
			local w, d = 46 - i * 6, 32 - i * 3
			local cf = at(-122 + i * 5, 2.2 + i * 4.4, -64 - i * 2) * CFrame.Angles(0, 0.18 * (i % 2 == 0 and 1 or -1), 0)
			solid(part(f, V(w, 4.4, d), cf, bookCols[i + 1], MATTE))
			part(f, V(w - 1.4, 3.6, d - 0.8), cf * CFrame.new(0.9, 0, 0), Color3.fromRGB(250, 245, 230), MATTE)
			part(f, V(1, 4.6, d + 0.2), cf * CFrame.new(-w / 2 + 0.3, 0, 0), bookCols[i + 1]:Lerp(Color3.new(0, 0, 0), 0.25), MATTE)
		end
		-- pencil cup with pencils + a ruler sticking out
		local cup = at(58, 0, 18)
		solid(part(f, V(26, 16, 16), cup * CFrame.new(0, 13, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 205, 120), MATTE, { shape = Enum.PartType.Cylinder }))
		part(f, V(1, 15, 15), cup * CFrame.new(0, 25.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 45, 40), MATTE, { shape = Enum.PartType.Cylinder })
		for k, col in { Color3.fromRGB(255, 205, 70), Color3.fromRGB(110, 170, 240), Color3.fromRGB(255, 125, 110), Color3.fromRGB(150, 205, 140) } do
			local a = k * 1.6
			hexPencil(cup * CFrame.new(math.cos(a) * 3.5, 30, math.sin(a) * 3.5) * CFrame.Angles(math.sin(a) * 0.25, 0, math.pi / 2 + math.cos(a) * 0.2), 34, col)
		end
		local ruler = part(f, V(3, 44, 0.8), cup * CFrame.new(-4, 34, 3) * CFrame.Angles(0.1, 0, 0.15), Color3.fromRGB(235, 225, 150), MATTE)
		for m = 0, 9 do part(f, V(1.2, 0.2, 0.9), ruler.CFrame * CFrame.new(-0.9, -18 + m * 4, 0), Color3.fromRGB(80, 70, 50), MATTE) end
		-- a tiny succulent by the leaderboard
		local pot = at(-142, 0, 26)
		solid(part(f, V(9, 10, 10), pot * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 235), MATTE, { shape = Enum.PartType.Cylinder }))
		for k = 0, 6 do
			local a = k / 7 * math.pi * 2
			part(f, V(3, 6, 3), pot * CFrame.new(math.cos(a) * 2, 11, math.sin(a) * 2) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), Color3.fromRGB(120, 190, 110), MATTE, { mesh = Enum.MeshType.Sphere })
		end
	end

	-- HALL OF FAME: the all-time leaderboard, a scoreboard standing on the table
	local function buildLeaderboard()
		local f = folder
		local pos = HUB + V(-128, 0, -12)
		local cf = CFrame.lookAt(pos, HUB + V(-20, 0, -6)) -- front (-Z) faces the middle of the table
		solid(part(f, V(54, 3, 10), cf * CFrame.new(0, 1.5, 0), DARKWOOD, Enum.Material.Wood))
		for _, sx in { -1, 1 } do
			solid(part(f, V(2.4, 46, 2.4), cf * CFrame.new(sx * 25, 25, 1.5) * CFrame.Angles(-0.1, 0, 0), DARKWOOD, Enum.Material.Wood))
		end
		local board = part(f, V(50, 40, 1.6), cf * CFrame.new(0, 25, 1.2) * CFrame.Angles(-0.1, 0, 0), Color3.fromRGB(40, 34, 70), SM)
		solid(board)
		part(f, V(52, 3, 2.2), board.CFrame * CFrame.new(0, 21.4, 0), Color3.fromRGB(245, 196, 80), SM)
		local star = part(f, V(7, 7, 1.2), board.CFrame * CFrame.new(0, 25.5, -0.4), Color3.fromRGB(255, 215, 110), Enum.Material.Neon, { mesh = Enum.MeshType.Sphere, noShadow = true })
		light(star, 40, 0.6, Color3.fromRGB(255, 215, 130))
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(1000, 800)
		sg.LightInfluence = 0
		sg.Brightness = 1.2
		sg.Parent = board
		UI.text(sg, "HALL OF FAME", { Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 14), Font = Enum.Font.FredokaOne, TextSize = 78, TextColor3 = C.gold, stroke = 4 })
		UI.text(sg, "all-time best  ·  every server", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 100), Font = Enum.Font.GothamBold, TextSize = 26, TextColor3 = C.white })
		local cols = {}
		for ci, def in { { "distance", "LONGEST RUN", C.mint, "m" }, { "wins", "DOG PARK WINS", C.coral, "" } } do
			local x0 = (ci - 1) * 500 + 24
			UI.text(sg, def[2], { Size = UDim2.fromOffset(452, 44), Position = UDim2.fromOffset(x0, 150), Font = Enum.Font.FredokaOne, TextSize = 38, TextColor3 = def[3], stroke = 2 })
			local rows = {}
			for i = 1, 10 do
				local y = 204 + (i - 1) * 58
				local rank = UI.text(sg, tostring(i), { Size = UDim2.fromOffset(56, 50), Position = UDim2.fromOffset(x0, y), Font = Enum.Font.FredokaOne, TextSize = 36, TextColor3 = i == 1 and C.gold or i <= 3 and C.white or Color3.fromRGB(170, 165, 200) })
				local name = UI.text(sg, "—", { Size = UDim2.fromOffset(270, 50), Position = UDim2.fromOffset(x0 + 60, y), Font = Enum.Font.GothamBold, TextSize = 30, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
				local val = UI.text(sg, "", { Size = UDim2.fromOffset(120, 50), Position = UDim2.fromOffset(x0 + 332, y), Font = Enum.Font.FredokaOne, TextSize = 32, TextColor3 = def[3], TextXAlignment = Enum.TextXAlignment.Right })
				rows[i] = { name = name, val = val }
			end
			cols[def[1]] = { rows = rows, unit = def[4] }
		end
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("SminskiRemotes")
		local value = remotes and remotes:FindFirstChild("Leaderboards")
		local function refresh()
			local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(value.Value) end)
			if not ok or type(data) ~= "table" then return end
			for id, col in cols do
				local list = data[id] or {}
				for i, r in col.rows do
					local e = list[i]
					r.name.Text = e and tostring(e.n) or "—"
					r.val.Text = e and (UI.fmt(e.v) .. col.unit) or ""
				end
			end
		end
		if value then
			value.Changed:Connect(refresh)
			refresh()
		end
		local anchor = part(f, V(1, 1, 1), board.CFrame * CFrame.new(0, 24, 0), Color3.new(), SM, { transparency = 1 })
		sign(f, anchor, "HALL OF FAME", "all-time leaderboard", Color3.fromRGB(245, 196, 80), "trophy", 8)
	end

	-- a wooden signpost near the middle of the table pointing at the cafe
	local function buildCafeSign()
		local f = folder
		local from = V(16, 0, 18)
		local cafe = Places.entrance("friends")
		local to = cafe and cafe.door or V(48, 0, 48)
		local dir = V(to.X - from.X, 0, to.Z - from.Z).Unit
		-- board frame: local +X runs toward the cafe
		local base = CFrame.fromMatrix(HUB + from, dir, V(0, 1, 0))
		solid(part(f, V(1.6, 16, 1.6), base * CFrame.new(0, 8, 0), DARKWOOD, Enum.Material.Wood))
		part(f, V(5, 1, 5), base * CFrame.new(0, 0.5, 0), DARKWOOD, Enum.Material.Wood)
		local board = part(f, V(24, 6, 1.2), base * CFrame.new(4, 13, 0), Color3.fromRGB(255, 170, 190), SM)
		part(f, V(4.4, 4.4, 1.2), base * CFrame.new(16.2, 13, 0) * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(255, 170, 190), SM) -- arrow tip
		part(f, V(25, 7, 0.8), base * CFrame.new(4, 13, 0), Color3.fromRGB(250, 245, 240), SM)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.CanvasSize = Vector2.new(480, 120)
			sg.LightInfluence = 0.2
			sg.Parent = board
			-- seen from the front, local +X is on the viewer's left
			local label = face == Enum.NormalId.Front and "◀  RUN WITH FRIENDS" or "RUN WITH FRIENDS  ▶"
			UI.text(sg, label, { Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.fromScale(0, 0.04), Font = Enum.Font.FredokaOne, TextSize = 46, TextColor3 = C.white, stroke = 3 })
			UI.text(sg, "Sminski Cafe  ·  quick play  ·  private lobbies", { Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.66), Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = C.white })
		end
		local lamp = part(f, V(2.2, 2.2, 2.2), base * CFrame.new(0, 17, 0), Color3.fromRGB(255, 225, 170), Enum.Material.Neon, { shape = Enum.PartType.Ball })
		light(lamp, 22, 0.7, WARM)
	end

	function Hub.build()
		if built then return end
		built = true
		folder = Instance.new("Folder")
		folder.Name = "SminskiHub"
		actors = Instance.new("Folder")
		actors.Name = "SminskiHubActors"
		buildBedroom()
		buildTabletop()
		buildLeaderboard()
		-- the town square: sidewalks, lamps, the stream + bridges, a signpost
		Streets.build(folder)
		-- the Sminski statue on its pedestal in the middle of the plaza
		solid(part(folder, V(3, 10, 10), at(0, 1.5, -4) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(225, 215, 240), SM, { shape = Enum.PartType.Cylinder }))
		statue = Models.buildSminski(folder, 2, Config.Character("Glow"), false, "crown")
		do
			local sl = Instance.new("PointLight")
			sl.Color = Color3.fromRGB(190, 255, 150)
			sl.Range = 16
			sl.Brightness = 0.5
			sl.Parent = statue.body
		end
		for _, e in Places.Entrances do
			if e.id == "capsule" then
				buildCubbies(e)
			elseif e.id == "garden" then
				entranceParts[e.id] = Garden.build(e, folder, function(door, en)
					sign(folder, door, en.title, en.sub, en.color, "star", 12)
				end)
			else
				Sets.build(e)
			end
		end
		-- perf: tiny decor doesn't need to cast shadows (books, vines, lights)
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and math.max(d.Size.X, d.Size.Y, d.Size.Z) < 4 then d.CastShadow = false end
		end
		folder.Parent = workspace
		actors.Parent = workspace
		Hub.spawnNPCs()
	end

	---------------------------------------------------------------------------
	-- NPC SMINSKIS
	---------------------------------------------------------------------------
	local npcs = {}
	function Hub.spawnNPCs()
		local ids = { "Glow", "Blush", "Sky", "Lemon", "Lavender", "Mint", "Peach", "Ghost", "Night", "Galaxy" }
		local outfits = { nil, "bow", "sprout", "party", "headband", "scarf", nil, "flowers", "catears", nil }
		for i = 1, 10 do
			local rig = Models.buildSminski(actors, 1, Config.Character(ids[i]), true, outfits[i])
			table.insert(npcs, {
				rig = rig, x = math.random(-80, 80), z = math.random(-30, 30), h = 0, goal = nil, wait = math.random() * 3,
				pose = Config.Character(ids[i]).idle or "idle", speed = 10 + math.random() * 5,
			})
		end
	end

	local function npcStep(n, dt, t)
		if n.wait > 0 then
			n.wait -= dt
			Models.poseSminski(n.rig, at(n.x, 0, n.z) * CFrame.Angles(0, n.h, 0), n.pose, t + n.x)
			return
		end
		if not n.goal then
			n.goal = V(math.random(-95, 85), 0, math.random(-34, 30))
		end
		local d = n.goal - V(n.x, 0, n.z)
		if d.Magnitude < 2 then
			n.goal = nil
			n.wait = 2 + math.random() * 5
			return
		end
		local dir = d.Unit
		n.h = math.atan2(dir.X, dir.Z)
		n.x += dir.X * n.speed * dt
		n.z += dir.Z * n.speed * dt
		Models.poseSminski(n.rig, at(n.x, 0, n.z) * CFrame.Angles(0, n.h, 0), "run", t, { stride = 12 })
	end

	---------------------------------------------------------------------------
	-- AVATARS: everyone's Sminski, drawn over their invisible character
	---------------------------------------------------------------------------
	local avatars = {} -- player -> { rig, char, outfit, idleT }
	Hub.avatars = avatars

	local function avatarFor(p)
		local a = avatars[p]
		local cid, oid = p:GetAttribute("Char") or "Glow", p:GetAttribute("Outfit") or "None"
		local kid = p:GetAttribute("Skin") or "none"
		-- your own three layers come from your data, not your attributes, so a
		-- change shows on you the instant the server confirms it rather than
		-- one attribute-replication round trip later
		if p == player then
			cid, oid = ctx.data.EquippedCharacter, ctx.data.EquippedOutfit
			kid = ctx.data.EquippedSkin or "none"
		end
		local matte = Hub.matte == true
		if a and a.char == cid and a.outfit == oid and a.skin == kid and a.matte == matte then return a end
		if a then a.rig.model:Destroy() end
		local def = Config.Character(cid)
		-- in daylight (the city) Sminskis are matte, with no glow light
		local rig = Models.buildSminski(actors, 1, def, not matte, oid ~= "None" and oid or nil, Config.Skin(kid))
		Models.addTrail(rig, def.trail)
		rig.trail.Enabled = false
		if p ~= player and deps.nameplate then
			deps.nameplate(rig, { name = (p:GetAttribute("VIP") and "👑 " or "") .. p.DisplayName, elo = p:GetAttribute("Elo") })
		end
		a = { rig = rig, char = cid, outfit = oid, skin = kid, idleT = 0, t0 = math.random() * 10, matte = matte }
		avatars[p] = a
		return a
	end

	-- where a character's feet are, and which way it faces
	local function footCF(hrp)
		local look = hrp.CFrame.LookVector
		local pos = hrp.Position - V(0, 2.9, 0)
		return CFrame.new(pos) * CFrame.Angles(0, math.atan2(look.X, look.Z), 0)
	end
	Hub.footCF = footCF

	function Hub.updateAvatars(dt, t, overridePose)
		local seen = {}
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local hidden = p:GetAttribute("Activity") == "run" or p:GetAttribute("ParkOut") == true
			if hrp and hum and not hidden then
				seen[p] = true
				local a = avatarFor(p)
				a.rig.model.Parent = actors
				local vel = hrp.AssemblyLinearVelocity
				local flat = V(vel.X, 0, vel.Z).Magnitude
				local air = hum.FloorMaterial == Enum.Material.Air
				local pose
				if overridePose and overridePose[p] then
					pose = overridePose[p]
				elseif air then
					pose = vel.Y < -4 and "fall" or "jump"
				elseif flat > 2 then
					pose = "run"
					a.idleT = 0
				else
					a.idleT += dt
					pose = a.idleT > 2.5 and (Config.Character(a.char).idle or "idle") or "idle"
				end
				a.rig.trail.Enabled = flat > 14
				Models.poseSminski(a.rig, footCF(hrp), pose, t + a.t0, { stride = 9 + math.min(flat, 30) * 0.45 })
			end
		end
		for p, a in avatars do
			if not seen[p] then
				a.rig.model.Parent = nil
				if not p.Parent then
					a.rig.model:Destroy()
					avatars[p] = nil
				end
			end
		end
	end

	function Hub.avatarOf(p)
		return avatars[p]
	end

	---------------------------------------------------------------------------
	-- HUB HUD: menu button, mini profile, prompt card, waiting-pen panel
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiHubUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Enabled = false
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local function rescale()
		local v = camera.ViewportSize
		local s = math.clamp(math.min(v.X / 1280, v.Y / 760), UIS.TouchEnabled and 0.6 or 0.45, 1.25)
		sc.Scale = s
		root.Size = UDim2.fromOffset(v.X / s, v.Y / s)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	Hub.gui = gui

	UI.button(root, "MENU", { size = UDim2.fromOffset(150, 58), pos = UDim2.new(1, -24, 0, 22), anchor = Vector2.new(1, 0), color = C.lav, textSize = 24, icon = "house", onClick = function() ctx.showHome() end })
	local coinPillHolder = Instance.new("Frame")
	coinPillHolder.BackgroundColor3 = C.paper
	coinPillHolder.Size = UDim2.fromOffset(170, 48)
	-- top-right: Roblox's chat window owns the top-left corner
	coinPillHolder.AnchorPoint = Vector2.new(1, 0)
	coinPillHolder.Position = UDim2.new(1, -190, 0, 27)
	coinPillHolder.Parent = root
	UI.skin(coinPillHolder, "pill", 24 / 80)
	UI.icon(coinPillHolder, "coin", { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
	local coinText = UI.text(coinPillHolder, "0", { Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(46, 0), Font = Enum.Font.FredokaOne, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local lvlText = UI.text(root, "LV 1", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(320, 26), Position = UDim2.new(1, -26, 0, 88), Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, stroke = 2 })
	local clockPill = Instance.new("Frame")
	clockPill.BackgroundColor3 = C.paper
	clockPill.AnchorPoint = Vector2.new(0.5, 0)
	clockPill.Size = UDim2.fromOffset(150, 46)
	clockPill.Position = UDim2.new(0.5, 0, 0, 20)
	clockPill.Parent = root
	UI.skin(clockPill, "pill", 23 / 80)
	UI.icon(clockPill, "clock", { Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0, -10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
	Hub._hudClock = (UI.text(clockPill, "00:00", { Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(40, 0), Font = Enum.Font.FredokaOne, TextSize = 26, ZIndex = 3 }))
	local hint = UI.text(root, "WASD / stick to walk around  ·  walk into a building to play", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(700, 24), Position = UDim2.new(0.5, 0, 1, -18), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.white, stroke = 1 })

	-- contextual prompt
	local promptHolder, prompt = UI.card(root, UDim2.fromOffset(420, 104), UDim2.new(0.5, 0, 1, -54), Vector2.new(0.5, 1), C.paper)
	promptHolder.Visible = false
	local pIcon = UI.icon(prompt, "house", { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(10, 10), ZIndex = 3 })
	local pTitle = UI.text(prompt, "", { Size = UDim2.new(1, -250, 0, 34), Position = UDim2.fromOffset(100, 16), Font = Enum.Font.FredokaOne, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 3 })
	local pSub = UI.text(prompt, "", { Size = UDim2.new(1, -250, 0, 22), Position = UDim2.fromOffset(100, 54), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local promptEntrance
	-- the hint speaks the player's language: touch, gamepad or keyboard
	if UI.onInputKind then
		UI.onInputKind(function(kind)
			hint.Text = kind == "touch" and "drag the left side to walk  ·  walk into a building to play"
				or kind == "gamepad" and "left stick to walk  ·  X to enter  ·  Y for the menu"
				or "WASD to walk around  ·  E to enter  ·  walk into a building to play"
		end)
	end
	local pBtn = UI.button(prompt, "ENTER", { size = UDim2.fromOffset(140, 62), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 22, onClick = function()
		if promptEntrance then Hub.activate(promptEntrance) end
	end })
	pBtn.holder.ZIndex = 3
	local pKey = UI.text(prompt, "[E]", { Size = UDim2.fromOffset(140, 16), Position = UDim2.new(1, -154, 1, -18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, ZIndex = 3 })

	-- waiting pen panel
	local penHolder, penCard = UI.card(root, UDim2.fromOffset(380, 196), UDim2.new(0.5, 0, 0, 20), Vector2.new(0.5, 0), C.paper)
	penHolder.Visible = false
	-- COMPACT (phones): the waiting panel was a third of the screen's height,
	-- and the walking hint is a line of text across the bottom that a touch
	-- player has no use for after the first minute
	do
		local penScale = Instance.new("UIScale")
		penScale.Parent = penHolder
		local function layout()
			local compact = UI.compact()
			penScale.Scale = compact and 0.7 or 1
			hint.Visible = not compact
		end
		layout()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	UI.icon(penCard, "paw", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(-16, -16), ZIndex = 3 })
	UI.text(penCard, "DOG PARK SURVIVAL", { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 12), Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = C.ink, ZIndex = 3 })
	UI.text(penCard, "LAST SMINSKI ALIVE WINS", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 48), Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = C.coral, ZIndex = 3 })
	local penPlayers = UI.text(penCard, "PLAYERS 1 / 16", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 80), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = C.mintDark, ZIndex = 3 })
	local penCount = UI.text(penCard, "STARTING IN 20", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 116), Font = Enum.Font.FredokaOne, TextSize = 38, TextColor3 = C.ink, ZIndex = 3 })
	local penNote = UI.text(penCard, "empty spots fill with bots", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 166), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, ZIndex = 3 })

	local penState = { n = 0, max = 16 }
	function Hub.setPen(st)
		penState = st
	end

	---------------------------------------------------------------------------
	-- ENTRANCES
	---------------------------------------------------------------------------
	local ACTIONS = {
		house = function() ctx.startRunMap("house") end,
		dollhouse = function() ctx.startRunMap("dollhouse") end,
		dogrun = function() ctx.startRunMap("dogpark") end,
		dogpark = function() UI.toast("walk into the fenced pen to join!", C.mintDark) end,
		arcade = function() UI.open("multi") end,
		store = function() UI.openShopTab("upgrades") end,
		capsule = function() UI.openShopTab("capsules") end,
		closet = function() UI.openShopTab("outfits") end,
		friends = function() UI.open("multi") end,
		board = function() UI.open("challenges") end,
		garden = function() Garden.open() end,
	}
	function Hub.activate(e)
		Audio.play("Pop", 1.1, 0.8)
		local f = ACTIONS[e.id]
		if f then f() end
	end

	local armed = {}
	local doorwayT = {} -- seconds spent standing in a walk-in doorway
	local DOORWAY_WAIT = 5
	local lastPromptDt = 0
	local function myHRP()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	end
	Hub.myHRP = myHRP

	UIS.InputBegan:Connect(function(input, gp)
		if gp or not gui.Enabled or ctx.tourRunning then return end
		if (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX) and promptEntrance then
			Hub.activate(promptEntrance)
		elseif input.KeyCode == Enum.KeyCode.ButtonY or input.KeyCode == Enum.KeyCode.M then
			ctx.showHome()
		end
	end)

	local function updatePrompts(hrp)
		local pos = hrp.Position - HUB
		local best, bd
		for _, e in Places.Entrances do
			local d = (V(pos.X, 0, pos.Z) - V(e.door.X, 0, e.door.Z)).Magnitude
			if d < 18 and (not bd or d < bd) then best, bd = e, d end
			-- walk-in doors fire once, re-arm when you step away
			if e.auto then
				if d < 6 and armed[e.id] ~= false then
					doorwayT[e.id] = doorwayT[e.id] or os.clock() -- wall-clock, so low frame rates don't stretch it
					if os.clock() - doorwayT[e.id] >= DOORWAY_WAIT then
						armed[e.id] = false
						doorwayT[e.id] = nil
						Hub.activate(e)
					end
				else
					doorwayT[e.id] = nil
					if d > 10 then armed[e.id] = true end
				end
			end
		end
		if best ~= promptEntrance then
			promptEntrance = best
			promptHolder.Visible = best ~= nil
			if best then
				pTitle.Text = best.title
				local ready = best.id == "garden" and Garden.readyCount() or 0
				pSub.Text = best.id == "dogpark" and "walk into the pen to queue" or ready > 0 and (ready .. " plant" .. (ready > 1 and "s" or "") .. " ready to pick!") or best.sub
				pIcon.Image = UI.Art.icons[({ garden = "star", house = "house", dollhouse = "heart", dogrun = "dog", dogpark = "paw", arcade = "trophy", store = "bag", capsule = "capsule", closet = "shirt", friends = "friends", board = "chart" })[best.id]] or ""
				pBtn.setText(best.key or "ENTER")
				pBtn.setColor(best.color)
				local ps = promptHolder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", promptHolder)
				-- a little smaller on a phone: it sits between the thumbstick and jump
				local full = UI.compact() and 0.84 or 1
				ps.Scale = 0.8 * full
				UI.tween(ps, 0.25, { Scale = full }, Enum.EasingStyle.Back)
				Audio.play("Click", 1.4, 0.4)
			end
		end
		if best and best.auto then
			local w = doorwayT[best.id]
			if w then
				pSub.Text = string.format("starting in %d...  (walk away to cancel)", math.max(1, math.ceil(DOORWAY_WAIT - (os.clock() - w))))
			else
				pSub.Text = "stand in the doorway 5s, or press " .. (best.key or "ENTER")
			end
		end
		-- waiting pen
		local inPen = Places.inPen(hrp.Position)
		penHolder.Visible = inPen or penState.running and (V(pos.X, 0, pos.Z) - V(Places.Pen.center.X, 0, Places.Pen.center.Z)).Magnitude < 60
		if penHolder.Visible then
			if penState.running then
				penPlayers.Text = "ROUND IN PROGRESS"
				penCount.Text = (penState.alive or 0) .. " / " .. (penState.total or 0) .. " ALIVE"
				penNote.Text = inPen and "you're in the next round" or "walk in to join the next round"
			else
				penPlayers.Text = "PLAYERS " .. (penState.n or 0) .. " / " .. (penState.max or 16)
				local left = penState.endsAt and math.max(0, penState.endsAt - workspace:GetServerTimeNow()) or nil
				penCount.Text = left and ("STARTING IN " .. math.ceil(left)) or (inPen and "GET READY..." or "WALK IN TO JOIN")
				penNote.Text = "empty spots fill with bots"
			end
		end
	end

	local function updatePenSign()
		if not penSign then return end
		if penState.running then
			penSign.line1.Text = "ROUND IN PROGRESS"
			penSign.line2.Text = (penState.alive or 0) .. " / " .. (penState.total or 0) .. " still running"
		else
			penSign.line1.Text = "PLAYERS " .. (penState.n or 0) .. " / " .. (penState.max or 16)
			local left = penState.endsAt and math.max(0, penState.endsAt - workspace:GetServerTimeNow()) or nil
			penSign.line2.Text = left and ("STARTING IN " .. math.ceil(left)) or "walk in to join"
		end
	end

	---------------------------------------------------------------------------
	-- ENTER / LEAVE / UPDATE
	---------------------------------------------------------------------------
	local HUB_LOOK = "hub"
	function Hub.enter(showHome)
		Hub.build()
		folder.Parent = workspace
		actors.Parent = workspace
		deps.applyLook(HUB_LOOK)
		clockAcc = 10
		gui.Enabled = not showHome
		if player then
			player.CameraMinZoomDistance = 8
			player.CameraMaxZoomDistance = 48
		end
	end

	function Hub.leave()
		gui.Enabled = false
		promptHolder.Visible = false
		penHolder.Visible = false
		promptEntrance = nil
	end

	---------------------------------------------------------------------------
	-- AT THIS TABLE: who's here + what they're doing, and a live activity feed
	---------------------------------------------------------------------------
	do
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("SminskiRemotes")
		local Players = game:GetService("Players")
		local W = 290
		local panel = UI.frame and nil
		panel = Instance.new("Frame")
		panel.Name = "TablePanel"
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -24, 0, 122)
		panel.Size = UDim2.fromOffset(W, 60)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		panel.BackgroundColor3 = Color3.fromRGB(34, 28, 52)
		panel.BackgroundTransparency = 0.22
		panel.Parent = root
		local pc = Instance.new("UICorner") pc.CornerRadius = UDim.new(0, 16) pc.Parent = panel
		local pst = Instance.new("UIStroke") pst.Color = Color3.fromRGB(255, 255, 255) pst.Transparency = 0.82 pst.Thickness = 1.5 pst.Parent = panel
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 12), UDim.new(0, 12)
		pad.Parent = panel
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 4)
		list.Parent = panel
		local head = Instance.new("TextButton")
		head.Size = UDim2.new(1, 0, 0, 24)
		head.BackgroundTransparency = 1
		head.Text = ""
		head.LayoutOrder = 0
		head.Parent = panel
		local headL = UI.text(head, "AT THIS TABLE", { Size = UDim2.new(1, -30, 1, 0), Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left })
		local chev = UI.text(head, "–", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(26, 24), Position = UDim2.fromScale(1, 0), Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = C.white })
		local body = Instance.new("Frame")
		body.Size = UDim2.new(1, 0, 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		body.LayoutOrder = 1
		body.Parent = panel
		local bl = Instance.new("UIListLayout") bl.SortOrder = Enum.SortOrder.LayoutOrder bl.Padding = UDim.new(0, 3) bl.Parent = body
		local rosterBox = Instance.new("Frame")
		rosterBox.Size = UDim2.new(1, 0, 0, 0) rosterBox.AutomaticSize = Enum.AutomaticSize.Y rosterBox.BackgroundTransparency = 1 rosterBox.LayoutOrder = 1 rosterBox.Parent = body
		local rl = Instance.new("UIListLayout") rl.SortOrder = Enum.SortOrder.LayoutOrder rl.Padding = UDim.new(0, 2) rl.Parent = rosterBox
		local rule = Instance.new("Frame")
		rule.Size = UDim2.new(1, 0, 0, 1) rule.BackgroundColor3 = Color3.new(1, 1, 1) rule.BackgroundTransparency = 0.85 rule.BorderSizePixel = 0 rule.LayoutOrder = 2 rule.Parent = body
		local feedBox = Instance.new("Frame")
		feedBox.Size = UDim2.new(1, 0, 0, 0) feedBox.AutomaticSize = Enum.AutomaticSize.Y feedBox.BackgroundTransparency = 1 feedBox.LayoutOrder = 3 feedBox.Parent = body
		local fl = Instance.new("UIListLayout") fl.SortOrder = Enum.SortOrder.LayoutOrder fl.Padding = UDim.new(0, 2) fl.Parent = feedBox

		local STATUS = {
			hub = { "on the table", C.mint },
			run = { "running", C.gold },
			park = { "in the Dog Park", C.coral },
		}
		local KIND_COL = { join = C.mint, leave = Color3.fromRGB(170, 165, 200), run = C.gold, result = C.white, best = C.gold, level = C.sky, rare = C.lav, squad = C.sky, park = C.coral, info = C.white }
		local function row(parent, order, dotCol, left, right, dim)
			local r = Instance.new("Frame")
			r.Size = UDim2.new(1, 0, 0, 20)
			r.BackgroundTransparency = 1
			r.LayoutOrder = order
			r.Parent = parent
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(8, 8) dot.Position = UDim2.fromOffset(1, 6) dot.BackgroundColor3 = dotCol dot.Parent = r
			local dc = Instance.new("UICorner") dc.CornerRadius = UDim.new(1, 0) dc.Parent = dot
			UI.text(r, left, { Size = UDim2.new(right and 0.5 or 1, -16, 1, 0), Position = UDim2.fromOffset(16, 0), Font = right and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = 14, TextColor3 = dim and Color3.fromRGB(200, 196, 220) or C.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
			if right then
				UI.text(r, right, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(1, 0), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = dotCol, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
			end
			return r
		end
		local function refreshRoster()
			for _, c in rosterBox:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
			local all = Players:GetPlayers()
			table.sort(all, function(a, b) return (a == player) or (b ~= player and a.DisplayName < b.DisplayName) end)
			for i, p in all do
				if i > 8 then
					row(rosterBox, 99, Color3.fromRGB(170, 165, 200), "+" .. (#all - 8) .. " more", nil, true)
					break
				end
				local act = p:GetAttribute("Activity") or "hub"
				local st = STATUS[act] or STATUS.hub
				local label = st[1]
				if act == "run" and p:GetAttribute("RunMap") then label = "running " .. p:GetAttribute("RunMap") end
				if act == "park" and p:GetAttribute("ParkOut") then label = "spectating park" end
				row(rosterBox, i, st[2], (p:GetAttribute("VIP") and "👑 " or "") .. p.DisplayName .. (p == player and " (you)" or ""), label)
			end
			headL.Text = "AT THIS TABLE  ·  " .. #all
		end
		local feedItems = {}
		local function ago(t)
			local s = math.max(0, os.time() - (t or os.time()))
			return s < 60 and "now" or s < 3600 and (math.floor(s / 60) .. "m") or (math.floor(s / 3600) .. "h")
		end
		local function drawFeed()
			for _, c in feedBox:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
			for i = 1, math.min(5, #feedItems) do
				local e = feedItems[i]
				local r = row(feedBox, i, KIND_COL[e.kind] or C.white, e.text, ago(e.t), i > 2)
				r.Size = UDim2.new(1, 0, 0, 20)
			end
			if #feedItems == 0 then row(feedBox, 1, Color3.fromRGB(170, 165, 200), "nothing yet — go make some noise", nil, true) end
		end
		local function watch(p)
			for _, a in { "Activity", "RunMap", "ParkOut", "VIP" } do
				p:GetAttributeChangedSignal(a):Connect(refreshRoster)
			end
		end
		for _, p in Players:GetPlayers() do watch(p) end
		Players.PlayerAdded:Connect(function(p) watch(p) refreshRoster() end)
		Players.PlayerRemoving:Connect(function() task.defer(refreshRoster) end)
		refreshRoster()
		if remotes then
			local fe = remotes:FindFirstChild("Feed")
			local gf = remotes:FindFirstChild("GetFeed")
			if fe then
				fe.OnClientEvent:Connect(function(e)
					table.insert(feedItems, 1, e)
					if #feedItems > 12 then table.remove(feedItems) end
					drawFeed()
				end)
			end
			if gf then
				task.spawn(function()
					local ok, got = pcall(function() return gf:InvokeServer() end)
					if ok and type(got) == "table" then
						local seen = {}
						for _, e in feedItems do seen[tostring(e.t) .. e.text] = true end
						for _, e in got do
							if not seen[tostring(e.t) .. e.text] then table.insert(feedItems, e) end
						end
						table.sort(feedItems, function(a, b) return (a.t or 0) > (b.t or 0) end)
						drawFeed()
					end
				end)
			end
		end
		drawFeed()
		task.spawn(function()
			while panel.Parent do task.wait(30) drawFeed() end
		end)
		-- collapse: tap the header (starts collapsed on phones)
		local open = true
		local function setOpen(on)
			open = on
			body.Visible = on
			chev.Text = on and "–" or "+"
		end
		head.Activated:Connect(function() setOpen(not open) end)
		if UI.inputKind and UI.inputKind() == "touch" then setOpen(false) end
	end

	function Hub.setHudVisible(on)
		gui.Enabled = on
	end

	---------------------------------------------------------------------------
	-- DAY / NIGHT: the room follows the player's real local clock
	---------------------------------------------------------------------------
	local NIGHT = { amb = Color3.fromRGB(80, 70, 118), out = Color3.fromRGB(90, 80, 128), bright = 1.0, exp = -0.05,
		sky = Color3.fromRGB(20, 26, 64), tint = Color3.fromRGB(240, 234, 255), atm = Color3.fromRGB(120, 105, 175) }
	local DUSK = { amb = Color3.fromRGB(150, 110, 120), out = Color3.fromRGB(170, 130, 140), bright = 1.8, exp = 0.1,
		sky = Color3.fromRGB(255, 150, 120), tint = Color3.fromRGB(255, 232, 220), atm = Color3.fromRGB(255, 180, 160) }
	local DAY = { amb = Color3.fromRGB(128, 122, 132), out = Color3.fromRGB(150, 150, 158), bright = 2.1, exp = -0.05,
		sky = Color3.fromRGB(150, 200, 255), tint = Color3.fromRGB(255, 250, 244), atm = Color3.fromRGB(215, 225, 245) }
	local function mixLook(a, b, k)
		local o = {}
		for key, v in a do
			local w = b[key]
			o[key] = typeof(v) == "Color3" and v:Lerp(w, k) or v + (w - v) * k
		end
		return o
	end
	function Hub.localHour()
		local d = os.date("*t")
		if Hub.debugHour then
			d.hour, d.min, d.sec = math.floor(Hub.debugHour), math.floor(Hub.debugHour % 1 * 60), 0
		end
		return d.hour + d.min / 60 + d.sec / 3600, d
	end
	local function dayCycle(dt)
		clockAcc += dt
		if clockAcc < 1 then return end
		clockAcc = 0
		local h, d = Hub.localHour()
		-- daylight 0..1 (6am -> 6pm), with dusk/dawn in between
		local day = math.clamp(math.sin((h - 6) / 12 * math.pi), 0, 1)
		day = math.clamp(day * 1.6, 0, 1)
		local dusk = math.clamp(1 - math.abs(h - 18.5) / 1.6, 0, 1) + math.clamp(1 - math.abs(h - 6.3) / 1.2, 0, 1)
		local look = mixLook(NIGHT, DAY, day)
		look = mixLook(look, DUSK, math.clamp(dusk, 0, 1) * 0.6)
		Lighting.ClockTime = h
		Lighting.Ambient = look.amb
		Lighting.OutdoorAmbient = look.out
		Lighting.Brightness = look.bright
		Lighting.ExposureCompensation = look.exp
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			atm.Color = look.atm
			atm.Density = 0.12
		end
		local cc = Lighting:FindFirstChild("SminskiGrade")
		if cc then cc.TintColor = look.tint end
		if sky then
			sky.Color = look.sky
			skyLight.Color = look.sky:Lerp(Color3.new(1, 1, 1), 0.3)
			skyLight.Brightness = 0.5 + day * 2.5
			skyLight.Range = 160 + day * 100
		end
		for _, dot in cityDots do dot.Transparency = 0.1 + day * 0.85 end
		for _, w in sideSkies do
			w.part.Color = look.sky
			w.light.Color = look.sky:Lerp(Color3.new(1, 1, 1), 0.3)
			w.light.Brightness = 0.4 + day * 2.2
		end
		if rain then rain.Enabled = day < 0.5 end
		for _, r in rainEmitters do r.Enabled = day < 0.5 end
		for _, e in lampLights do
			if e.l ~= skyLight then e.l.Brightness = e.b * (1 - day * 0.55) end
		end
		local stamp = string.format("%02d:%02d", d.hour, d.min)
		if wallClock then
			local lbl = wallClock:FindFirstChildWhichIsA("TextLabel", true)
			if lbl then lbl.Text = stamp end
		end
		if Hub._hudClock then Hub._hudClock.Text = stamp end
	end

	local signT = 0
	local function fadeSigns(dt)
		signT -= dt
		if signT > 0 then return end
		signT = 0.08
		local camPos = camera.CFrame.Position
		for i = #signs, 1, -1 do
			local s = signs[i]
			if not s.bb.Parent or not s.a.Parent then
				table.remove(signs, i)
			else
				local d = (s.a.Position + s.bb.StudsOffsetWorldSpace - camPos).Magnitude
				-- 0 = fully clear up close, 1 = solid from ~70 studs away
				local k = math.clamp((d - 22) / 48, 0, 1)
				s.g.GroupTransparency = 0.82 * (1 - k)
			end
		end
	end
	function Hub.update(dt, t, state)
		if not built then return end
		fadeSigns(dt)
		if Streets.update then Streets.update(dt, t) end
		-- through the arch in the wall: off to Sminski City
		if state == "hub" and ctx.enterCity and not ctx.tourRunning then
			local hrp = myHRP()
			if hrp then
				local p = hrp.Position - HUB
				if math.abs(p.X - Places.HubGateX) < 11 and p.Z < Places.HubGateZ - 2 and p.Z > Places.HubGateZ - 40 then ctx.enterCity() end
			end
		end
		Garden.update(dt)
		if state == "hub" or state == "home" then dayCycle(dt) end
		for _, n in npcs do npcStep(n, dt, t) end
		if Hub.pup then
			Models.poseDog(Hub.pup.rig, Hub.pup.cf, t, 0, 0.1)
		end
		if statue then
			Models.poseSminski(statue, at(0, 3 + math.sin(t * 1.5) * 0.2, -4) * CFrame.Angles(0, math.pi + math.sin(t * 0.4) * 0.3, 0), "cheer", t * 0.6)
		end
		if Hub.person then
			-- every so often they glance over at the little Sminski table
			local glance = math.clamp(math.sin(t * 0.21) * 3 - 2.2, 0, 1)
			Models.poseKidSeated(Hub.person, Hub.person.seatCF, t, { look = -glance * 0.9 })
		end
		updatePenSign()
		if gui.Enabled then
			coinText.Text = UI.fmt(ctx.data.Coins)
			local mult = ctx.data.StreakMult or 1
			lvlText.Text = "LV " .. ctx.data.Level .. "  ·  " .. (player and player.DisplayName or "") .. (mult > 1.001 and string.format("  ·  🔥 x%.1f", mult) or "")
			local hrp = myHRP()
			lastPromptDt = dt
			if hrp and state == "hub" then updatePrompts(hrp) end
			hint.Visible = state == "hub" and not UI.compact()
		end
	end

	return Hub
end
