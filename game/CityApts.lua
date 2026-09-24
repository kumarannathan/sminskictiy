-- CityApts (client): places to live. Five buildings around town, five floor
-- plans; walk up to a front door and press the prompt.
--   street door -> LOBBY (shared: you meet the neighbours here)
--   leasing desk -> TOUR any of the five plans, BUY the one you like
--   lift         -> straight up to YOUR flat (and back down)
-- A building holds any number of residents, because a flat is not a place in
-- the tower: it is built for you, on your machine, when you step out of the
-- lift, and taken away when you leave. Flats stand on a per-player pitch far
-- outside town so two neighbours never see each other's avatars walking
-- through their walls; lobbies are one shared room per building on purpose.
--   deps: K, Build, Places, Config, Models, UI, Audio, S, H, player, City, remote, applyState, modalCard

return function(deps)
	local K, Places, Config, Models = deps.K, deps.Places, deps.Config, deps.Models
	local UI, Audio, S, player, City = deps.UI, deps.Audio, deps.S, deps.player, deps.City
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local part = Models.part
	local Cc = K.C
	local C = UI.C
	local CITY = Places.CITY
	local MATTE, WOOD, NEON, SMOOTH, METAL, FABRIC = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL, Enum.Material.Fabric
	local lots = Places.cityLots()

	local Apts = { inside = nil, owned = {} }

	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end
	local function flat(v) return V(v.X, 0, v.Z) end

	---------------------------------------------------------------------------
	-- WHERE THE FRONT DOORS ARE
	---------------------------------------------------------------------------
	local DOORS = {} -- { id, pos (city-relative), out (where you step back out to) }
	for id in Places.CityApts do
		local a = Places.CityApts[id]
		local dir = V(math.sin(a.face), 0, math.cos(a.face))
		table.insert(DOORS, { id = id, pos = Places.aptDoor(id) + dir * 6, out = Places.aptDoor(id) + dir * 12 })
	end
	for _, l in lots do
		-- the brownstones and the townhouses are buildings that already stand
		local id = (l.kind == "apartment" and "mochi") or (l.kind == "rowhouse" and "willow") or nil
		if id then
			-- the prompt belongs at the building's own front step, not out on the
			-- pavement, or everyone walking past gets asked in
			local dir = V(math.sin(l.face), 0, math.cos(l.face))
			local step = l.kind == "apartment" and 21 or 17
			table.insert(DOORS, { id = id, pos = l.pos + dir * step, out = l.pos + dir * (step + 5), r = 6 })
		end
	end

	-- a private pitch for your flat, and one shared pitch per building's lobby
	local uid = player and player.UserId or 0
	-- DEPTH MATTERS: workspace.FallenPartsDestroyHeight is -500, and anything
	-- below it is swept away -- a character put at -700 is back on the street
	-- within a frame or two. -420 is safely above it (the houses' own
	-- interiors sit at -400 for the same reason).
	local DEPTH = -420
	local FLAT_AT = CITY + V(-3000 + (uid % 12) * 400, DEPTH, -3400 - ((uid // 12) % 6) * 400)
	local LOBBY_AT = {}
	for i, b in Config.City.AptBuildings do LOBBY_AT[b.id] = CITY + V(-3000 + i * 500, DEPTH, -2600) end

	---------------------------------------------------------------------------
	-- ROOM + FURNITURE KIT (everything is parented to one model per room)
	---------------------------------------------------------------------------
	local cur -- the model being built
	local function P(size, cf, col, mat, opts)
		local p = part(cur, size, cf, col, mat or MATTE, opts)
		return p
	end
	local function solid(p) p.CanCollide = true return p end
	local function cyl(dia, len, cf, col, mat) return P(V(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2), col, mat, { shape = Enum.PartType.Cylinder }) end
	local function blob(size, cf, col, mat) return P(size, cf, col, mat, { mesh = Enum.MeshType.Sphere }) end
	local function light(cf, range, bright)
		local b = P(V(2, 0.5, 2), cf, rgb(255, 240, 214), NEON)
		b.CastShadow = false
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color, l.Shadows = range or 40, bright or 1, rgb(255, 236, 206), false
		l.Parent = b
	end

	-- a shell: floor, ceiling, three walls, and a WINDOW WALL on +Z looking
	-- out at a little skyline (boxes in haze: the real town is a mile away)
	local function shell(f, w, d, h, wall, floorCol, view)
		solid(P(V(w, 1, d), f * CFrame.new(0, -0.5, 0), floorCol, WOOD))
		P(V(w, 1, d), f * CFrame.new(0, h + 0.5, 0), rgb(250, 248, 242))
		solid(P(V(w, h, 1), f * CFrame.new(0, h / 2, -d / 2 - 0.5), wall))
		for _, sx in { -1, 1 } do solid(P(V(1, h, d), f * CFrame.new(sx * (w / 2 + 0.5), h / 2, 0), wall)) end
		P(V(w, 0.8, 0.4), f * CFrame.new(0, 0.4, -d / 2 + 0.2), Cc.cream)
		-- the window wall
		local wf = f * CFrame.new(0, 0, d / 2)
		solid(P(V(w, 2.4, 1), wf * CFrame.new(0, 1.2, 0.5), wall))
		solid(P(V(w, 1.6, 1), wf * CFrame.new(0, h - 0.8, 0.5), wall))
		local g = solid(P(V(w, h - 4, 0.4), wf * CFrame.new(0, 2.4 + (h - 4) / 2, 0.5), Cc.pane, K.GLASS, { transparency = 0.72 }))
		g.CastShadow = false
		for k = -math.floor(w / 24), math.floor(w / 24) do P(V(0.6, h - 4, 0.8), wf * CFrame.new(k * 12, 2.4 + (h - 4) / 2, 0.4), Cc.cream) end
		-- the view: sky, haze, and a few towers
		local sky = P(V(w + 160, h + 120, 1), wf * CFrame.new(0, h / 2 + 10, 150), view == "garden" and rgb(178, 214, 240) or rgb(160, 200, 238), NEON)
		sky.CastShadow = false
		if view == "garden" then
			for k = -3, 3 do blob(V(34, 40, 20), wf * CFrame.new(k * 26, 2, 70 + (k % 2) * 14), k % 2 == 0 and rgb(122, 170, 104) or rgb(140, 186, 116)) end
			P(V(w + 120, 1, 120), wf * CFrame.new(0, -4, 70), rgb(150, 196, 120))
		else
			for k = -5, 5 do
				local th = 40 + ((k * 37) % 70)
				local tw = P(V(18, th, 14), wf * CFrame.new(k * 22 + (k % 2) * 5, th / 2 - 50, 90 + (k % 3) * 18), ({ rgb(186, 204, 226), rgb(200, 196, 214), rgb(176, 198, 214) })[k % 3 + 1])
				tw.CastShadow = false
			end
			P(V(w + 160, 1, 160), wf * CFrame.new(0, -52, 90), rgb(150, 170, 190))
		end
		light(f * CFrame.new(0, h - 0.4, 0), math.max(w, d) * 0.8, 1.1)
	end

	local SPOTS -- the things you can do in the room being built
	local function spot(cf, title, sub, btn, icon, act) table.insert(SPOTS, { pos = cf.Position, title = title, sub = sub, btn = btn, icon = icon, act = act }) end

	-- THE FURNITURE NOW LIVES IN CityKit AS K.furn.
	-- It was written here, but a bed is not an apartment-only idea and a shop
	-- had no way to reach it, so every street room was inline primitives
	-- instead. The pieces moved out unchanged; what stays here is the drawing
	-- CONTEXT, because a flat is one Model that is built on approach and
	-- destroyed on exit (buildFlat / clearRoom), so its "solid" only sets
	-- CanCollide and must NOT be reparented out into the block collision bins
	-- the way K.solid does for a street room.
	--
	-- `cur` and `SPOTS` are read at call time, not captured, so one context
	-- serves every room this module ever builds.
	local CTX = { P = P, solid = solid, spot = spot }
	local FURN = setmetatable({}, { __index = function(t, k)
		local fn = K.furn[k]
		if not fn then return nil end
		local wrapped = function(...) return fn(CTX, ...) end
		t[k] = wrapped -- memoise: the PLANS call these dozens of times a room
		return wrapped
	end })


	-- the lift door every flat has, on the back wall
	local function liftDoor(f, d, label, act)
		local lf = f * CFrame.new(0, 0, -d / 2 + 0.6)
		P(V(9, 11, 0.6), lf * CFrame.new(0, 5.5, 0), rgb(176, 182, 186), METAL)
		P(V(0.2, 10.4, 0.7), lf * CFrame.new(0, 5.4, 0.1), Cc.ink)
		P(V(10.4, 1, 0.8), lf * CFrame.new(0, 11.4, 0), Cc.ink)
		local lamp = P(V(1.6, 0.6, 0.3), lf * CFrame.new(0, 11.4, 0.5), rgb(255, 214, 120), NEON)
		lamp.CastShadow = false
		spot(lf * CFrame.new(0, 0, 4), "THE LIFT", label, "GO", "pin", act)
		return lf * CFrame.new(0, 3.4, 6) * CFrame.Angles(0, math.pi, 0)
	end

	---------------------------------------------------------------------------
	-- THE FIVE FLOOR PLANS: size, then where everything goes
	---------------------------------------------------------------------------
	local PLANS = {}
	function PLANS.studio(f, wall, acc)
		local w, d, h = 42, 30, 14
		shell(f, w, d, h, wall, rgb(214, 186, 150), "city")
		FURN.bed(f * CFrame.new(-14, 0, 6) * CFrame.Angles(0, math.pi / 2, 0), acc)
		FURN.rug(f * CFrame.new(6, 0, 5), 18, 12, acc)
		FURN.sofa(f * CFrame.new(6, 0, 1) * CFrame.Angles(0, math.pi, 0), tint(acc, 0.2))
		FURN.coffee(f * CFrame.new(6, 0, 6))
		FURN.tv(f * CFrame.new(6, 0, 12.4) * CFrame.Angles(0, math.pi, 0))
		FURN.kitchen(f * CFrame.new(12, 0, -13) , 10, rgb(236, 232, 222))
		FURN.wardrobe(f * CFrame.new(-15, 0, -12.6))
		FURN.plant(f * CFrame.new(18, 0, 12))
		return w, d
	end
	function PLANS.onebed(f, wall, acc)
		local w, d, h = 58, 34, 14
		shell(f, w, d, h, wall, rgb(206, 178, 142), "city")
		FURN.wallZ(f * CFrame.new(-10, 0, 4), 26, h, wall)      -- the bedroom wall
		FURN.bed(f * CFrame.new(-20, 0, 6) * CFrame.Angles(0, math.pi / 2, 0), acc)
		FURN.wardrobe(f * CFrame.new(-22, 0, -14.6))
		FURN.lamp(f * CFrame.new(-13, 0, 14))
		FURN.rug(f * CFrame.new(10, 0, 6), 20, 13, acc)
		FURN.sofa(f * CFrame.new(10, 0, 1.6) * CFrame.Angles(0, math.pi, 0), tint(acc, 0.2))
		FURN.coffee(f * CFrame.new(10, 0, 7))
		FURN.tv(f * CFrame.new(10, 0, 14.4) * CFrame.Angles(0, math.pi, 0))
		FURN.kitchen(f * CFrame.new(18, 0, -15), 12, rgb(236, 232, 222))
		FURN.dining(f * CFrame.new(-1, 0, -8), acc)
		FURN.plant(f * CFrame.new(26, 0, 14))
		return w, d
	end
	function PLANS.loft(f, wall, acc)
		local w, d, h = 54, 36, 26
		shell(f, w, d, h, wall, rgb(190, 170, 146), "city")
		-- the sleeping deck, up a ramp along the side wall
		local deck = solid(P(V(24, 1, 16), f * CFrame.new(-15, 12, -10), rgb(206, 178, 142), WOOD))
		for _, sx in { -26, -4 } do solid(P(V(1, 12, 1), f * CFrame.new(sx, 6, -2.5), Cc.ink, METAL)) end
		P(V(24, 3, 0.4), f * CFrame.new(-15, 14, -2.2), Cc.pane, K.GLASS, { transparency = 0.5 })
		solid(P(V(5, 1, 22), CFrame.lookAt((f * CFrame.new(-24.4, 6.1, 6)).Position, (f * CFrame.new(-24.4, 12.3, -2)).Position), rgb(176, 136, 100), WOOD))
		FURN.bed(f * CFrame.new(-12, 12.5, -11) * CFrame.Angles(0, math.pi / 2, 0), acc)
		FURN.lamp(f * CFrame.new(-5.4, 12.5, -16))
		FURN.rug(f * CFrame.new(10, 0, 6), 22, 14, acc)
		FURN.sofa(f * CFrame.new(10, 0, 1) * CFrame.Angles(0, math.pi, 0), tint(acc, 0.2))
		FURN.coffee(f * CFrame.new(10, 0, 6.6))
		FURN.tv(f * CFrame.new(10, 0, 16) * CFrame.Angles(0, math.pi, 0))
		FURN.kitchen(f * CFrame.new(15, 0, -16), 14, Cc.ink)
		FURN.desk(f * CFrame.new(-15, 0, -14))
		FURN.shelf(f * CFrame.new(-25.6, 0, -9) * CFrame.Angles(0, math.pi / 2, 0))
		FURN.wardrobe(f * CFrame.new(-4, 0, -16.6))
		FURN.plant(f * CFrame.new(24, 0, 15), 1.4)
		return w, d
	end
	function PLANS.family(f, wall, acc)
		local w, d, h = 74, 40, 14
		shell(f, w, d, h, wall, rgb(214, 190, 156), "garden")
		FURN.wallZ(f * CFrame.new(-14, 0, 6), 28, h, wall)
		FURN.wallX(f * CFrame.new(-25.5, 0, -2), 23, h, wall)
		FURN.bed(f * CFrame.new(-27, 0, 9) * CFrame.Angles(0, math.pi / 2, 0), acc)
		FURN.wardrobe(f * CFrame.new(-19, 0, 17) * CFrame.Angles(0, math.pi, 0))
		FURN.bed(f * CFrame.new(-28, 0, -11) * CFrame.Angles(0, math.pi / 2, 0), tint(acc, 0.35))
		FURN.shelf(f * CFrame.new(-18, 0, -18.6))
		FURN.rug(f * CFrame.new(8, 0, 8), 24, 14, acc)
		FURN.sofa(f * CFrame.new(8, 0, 3) * CFrame.Angles(0, math.pi, 0), tint(acc, 0.2))
		FURN.coffee(f * CFrame.new(8, 0, 8.6))
		FURN.tv(f * CFrame.new(8, 0, 17.6) * CFrame.Angles(0, math.pi, 0))
		FURN.kitchen(f * CFrame.new(20, 0, -18), 18, rgb(236, 232, 222))
		FURN.dining(f * CFrame.new(-2, 0, -9), acc)
		FURN.tub(f * CFrame.new(32, 0, 10))
		FURN.plant(f * CFrame.new(34, 0, -4))
		FURN.lamp(f * CFrame.new(-9, 0, 17))
		return w, d
	end
	function PLANS.penthouse(f, wall, acc)
		local w, d, h = 92, 48, 18
		shell(f, w, d, h, wall, rgb(226, 214, 196), "city")
		FURN.wallZ(f * CFrame.new(-20, 0, 8), 32, h, wall)
		FURN.bed(f * CFrame.new(-34, 0, 10) * CFrame.Angles(0, math.pi / 2, 0), acc)
		FURN.wardrobe(f * CFrame.new(-38, 0, -8) * CFrame.Angles(0, math.pi / 2, 0))
		FURN.tub(f * CFrame.new(-26, 0, -14) * CFrame.Angles(0, math.pi / 2, 0))
		FURN.rug(f * CFrame.new(6, 0, 10), 30, 18, acc)
		FURN.sofa(f * CFrame.new(6, 0, 3) * CFrame.Angles(0, math.pi, 0), tint(acc, 0.2))
		FURN.sofa(f * CFrame.new(-7, 0, 11) * CFrame.Angles(0, -math.pi / 2, 0), tint(acc, 0.2))
		FURN.coffee(f * CFrame.new(6, 0, 10))
		FURN.tv(f * CFrame.new(6, 0, 21.4) * CFrame.Angles(0, math.pi, 0))
		FURN.kitchen(f * CFrame.new(26, 0, -22), 22, Cc.ink)
		FURN.dining(f * CFrame.new(14, 0, -10), acc)
		FURN.piano(f * CFrame.new(34, 0, 10) * CFrame.Angles(0, -0.6, 0))
		FURN.shelf(f * CFrame.new(-10, 0, -22.6))
		FURN.desk(f * CFrame.new(-2, 0, -20))
		FURN.plant(f * CFrame.new(42, 0, 21), 1.5)
		FURN.plant(f * CFrame.new(-16, 0, 21), 1.3)
		FURN.lamp(f * CFrame.new(20, 0, 20))
		light(f * CFrame.new(28, h - 0.4, 0), 50, 0.9)
		return w, d
	end

	---------------------------------------------------------------------------
	-- BUILD A FLAT / A LOBBY
	---------------------------------------------------------------------------
	local LOOK = { -- wall + accent per building, so each address feels like itself
		bankside = { rgb(238, 236, 230), rgb(96, 140, 196) }, motorrow = { rgb(244, 232, 210), rgb(226, 120, 96) },
		funfair = { rgb(232, 244, 232), rgb(240, 150, 190) }, mochi = { rgb(236, 224, 212), rgb(176, 110, 90) },
		willow = { rgb(244, 240, 226), rgb(110, 170, 130) },
	}
	local room -- { m, spots, kind, building, plan }
	local function clearRoom()
		if room then room.m:Destroy() room = nil end
	end
	local function buildFlat(building, plan, touring)
		clearRoom()
		cur = Instance.new("Model")
		cur.Name = "SminskiFlat"
		SPOTS = {}
		local f = CFrame.new(FLAT_AT)
		local look = LOOK[building] or LOOK.bankside
		local _, d = PLANS[plan](f, look[1], look[2])
		local arrive = liftDoor(f, d, touring and "back down to the leasing desk" or "down to the lobby", { lobby = true })
		cur.Parent = workspace
		room = { m = cur, spots = SPOTS, kind = touring and "tour" or "flat", building = building, plan = plan }
		return arrive
	end
	local function buildLobby(building)
		clearRoom()
		cur = Instance.new("Model")
		cur.Name = "SminskiLobby"
		SPOTS = {}
		local b = Config.AptBuilding(building)
		local look = LOOK[building] or LOOK.bankside
		local f = CFrame.new(LOBBY_AT[building])
		local w, d, h = 66, 46, 16
		solid(P(V(w, 1, d), f * CFrame.new(0, -0.5, 0), rgb(232, 226, 214), Enum.Material.Marble))
		P(V(w, 1, d), f * CFrame.new(0, h + 0.5, 0), rgb(250, 248, 242))
		for _, sz in { -1, 1 } do solid(P(V(w, h, 1), f * CFrame.new(0, h / 2, sz * (d / 2 + 0.5)), look[1])) end
		for _, sx in { -1, 1 } do solid(P(V(1, h, d), f * CFrame.new(sx * (w / 2 + 0.5), h / 2, 0), look[1])) end
		P(V(w, 3, 0.4), f * CFrame.new(0, 1.5, -d / 2 + 0.2), shade(look[1], 0.12), WOOD)
		FURN.rug(f * CFrame.new(0, 0, 4), 30, 18, look[2])
		light(f * CFrame.new(-16, h - 0.4, 0), 46, 1)
		light(f * CFrame.new(16, h - 0.4, 0), 46, 1)
		-- the way out (front doors, on +Z)
		local out = f * CFrame.new(0, 0, d / 2 - 0.4)
		local g = P(V(18, 12, 0.5), out * CFrame.new(0, 6, 0), rgb(214, 236, 244), SMOOTH, { transparency = 0.35 })
		g.CastShadow = false
		P(V(20, 1, 0.8), out * CFrame.new(0, 12.6, 0), look[2])
		spot(out * CFrame.new(0, 0, -4), b.name, "back out to the street", "EXIT", "house", { exit = true })
		-- reception, with the concierge behind it
		local desk = f * CFrame.new(-20, 0, -12)
		solid(P(V(16, 4, 3.4), desk * CFrame.new(0, 2, 0), shade(look[2], 0.1), WOOD))
		P(V(16.6, 0.4, 4), desk * CFrame.new(0, 4.2, 0), rgb(240, 236, 228), Enum.Material.Marble)
		local who = Models.buildSminski(cur, 1, Config.Characters[3], false, "tie")
		Models.poseSminski(who, desk * CFrame.new(0, 0, -3) , "idle", 1)
		local sgn = P(V(16, 2.4, 0.3), f * CFrame.new(-20, 11, -d / 2 + 0.5), Cc.ink)
		K.textOn(sgn, Enum.NormalId.Back, "LEASING  ·  TOUR A FLAT", rgb(255, 232, 180), Vector2.new(560, 70), 0)
		spot(desk * CFrame.new(0, 0, 4.6), "LEASING DESK", "tour the five floor plans, pick one", "VIEW PLANS", "house", { lease = true })
		-- somewhere to wait, and the post
		FURN.sofa(f * CFrame.new(16, 0, 9) * CFrame.Angles(0, math.pi, 0), look[2])
		FURN.sofa(f * CFrame.new(16, 0, -1), look[2])
		FURN.coffee(f * CFrame.new(16, 0, 4))
		FURN.plant(f * CFrame.new(29, 0, 19), 1.4)
		FURN.plant(f * CFrame.new(-29, 0, 19), 1.4)
		local post = f * CFrame.new(w / 2 - 0.8, 0, -6)
		P(V(0.6, 8, 16), post * CFrame.new(0, 6, 0), rgb(176, 182, 186), METAL)
		for r = 0, 2 do for k = 0, 5 do P(V(0.2, 1.8, 2.2), post * CFrame.new(-0.4, 3.6 + r * 2.4, -6.2 + k * 2.5), Cc.ink) end end
		-- THE LIFT
		local arrive = liftDoor(f, d, "up to your flat", { up = true })
		cur.Parent = workspace
		room = { m = cur, spots = SPOTS, kind = "lobby", building = building }
		-- you arrive WELL clear of the doors: at 8 studs the exit prompt fires the
		-- moment you walk in, and the first thing the building offers you is to
		-- leave it. Stand them in the middle, facing reception.
		return (out * CFrame.new(0, 3.4, -17) * CFrame.Angles(0, math.pi, 0)), arrive
	end

	---------------------------------------------------------------------------
	-- MOVING BETWEEN THEM
	---------------------------------------------------------------------------
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 40
	fade.Parent = deps.gui
	local function go(cf)
		local hrp = myChar()
		if not hrp then return end
		fade.BackgroundTransparency = 0
		Apts.sitting, Apts.emote = nil, nil
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = cf
		UI.tween(fade, 0.45, { BackgroundTransparency = 1 })
	end
	function Apts.enter(door)
		local hallCF = buildLobby(door.id)
		Apts.inside = { id = door.id, out = door.out }
		player.CameraMaxZoomDistance = 26
		if City.Home then City.Home.indoorLook(true) end
		go(hallCF)
		Audio.play("Pop", 1, 0.7)
		if City.Sound then City.Sound.door(door.pos) end
	end
	function Apts.leave(silent)
		local at = Apts.inside
		if not at then return end
		Apts.inside = nil
		clearRoom()
		player.CameraMaxZoomDistance = 80
		if City.Home then City.Home.indoorLook(false) end
		if not silent then go(CFrame.new(CITY + at.out + V(0, K.PAD_Y + 3.2, 0))) end
	end

	---------------------------------------------------------------------------
	-- THE LEASING CARD: five plans, TOUR or BUY
	---------------------------------------------------------------------------
	local lease = { rows = {} }
	do
		local dim, card = deps.modalCard(760, 600, "FLOOR PLANS")
		lease.shade = dim
		lease.sub = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(24, 56), TextSize = 17, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		for i, plan in Config.City.AptPlans do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -48, 0, 86)
			row.Position = UDim2.fromOffset(24, 90 + (i - 1) * 96)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			UI.text(row, plan.name, { Size = UDim2.new(1, -330, 0, 28), Position = UDim2.fromOffset(18, 10), Font = Enum.Font.FredokaOne, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
			UI.text(row, plan.desc, { Size = UDim2.new(1, -330, 0, 20), Position = UDim2.fromOffset(18, 40), TextSize = 15, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			local price = UI.text(row, "", { Size = UDim2.new(1, -330, 0, 20), Position = UDim2.fromOffset(18, 60), Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = C.mintDark, TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(row, "TOUR", { size = UDim2.fromOffset(120, 50), pos = UDim2.new(1, -160, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.sky, textSize = 19, onClick = function()
				dim.Visible = false
				Apts.tour(plan.id)
			end })
			local buy = UI.button(row, "BUY", { size = UDim2.fromOffset(136, 50), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 19, onClick = function()
				Apts.buy(plan.id)
			end })
			lease.rows[i] = { price = price, buy = buy, plan = plan }
		end
	end
	function Apts.openLease()
		local at = Apts.inside
		if not at then return end
		local b = Config.AptBuilding(at.id)
		lease.sub.Text = b.name .. "  ·  " .. b.blurb
		for _, r in lease.rows do
			local mine = Apts.owned[b.id] == r.plan.id
			r.price.Text = mine and "this is your flat" or (UI.fmt and UI.fmt(Config.AptPrice(b, r.plan)) or tostring(Config.AptPrice(b, r.plan))) .. " coins"
			r.buy.setText(mine and "YOURS" or (Apts.owned[b.id] and "SWITCH" or "BUY"))
			r.buy.setColor(mine and C.gold or C.mint)
		end
		lease.shade.Visible = true
	end
	function Apts.tour(planId)
		local at = Apts.inside
		if not at then return end
		go(buildFlat(at.id, planId, true))
		UI.toast("have a look round. the lift takes you back down.", C.mintDark)
	end
	function Apts.buy(planId)
		local at = Apts.inside
		if not at then return end
		local b, p = Config.AptBuilding(at.id), Config.AptPlan(planId)
		if Apts.owned[b.id] == p.id then return end
		task.spawn(function()
			local res = deps.remote("buyApt", b.id .. ":" .. p.id)
			if res and res.ok then
				if res.city then deps.applyState(res.city) end
				lease.shade.Visible = false
				Audio.play("BigChime", 1.1, 0.8)
				UI.toast("welcome home! take the lift up.", C.mintDark)
				if room and room.kind == "tour" then go(buildFlat(b.id, p.id, false)) end
			else
				UI.toast(res and res.reason or "could not buy that right now", C.coral)
			end
		end)
	end
	function Apts.onState(cs)
		if cs and type(cs.apts) == "table" then Apts.owned = cs.apts end
	end

	---------------------------------------------------------------------------
	-- PROMPTS + UPDATE
	---------------------------------------------------------------------------
	local function use(sp)
		local act = sp.act
		if act.exit then Apts.leave() return end
		if act.lease then Apts.openLease() return end
		if act.up then
			local plan = Apts.owned[Apts.inside.id]
			if not plan then UI.toast("you don't live here yet -- ask at the leasing desk", C.gold) return end
			go(buildFlat(Apts.inside.id, plan, false))
			Audio.play("Chime", 1.2, 0.6)
			return
		end
		if act.lobby then
			local _, arrive = buildLobby(Apts.inside.id)
			go(arrive)
			return
		end
		if act.ui and UI.openShopTab then UI.openShopTab(act.ui) return end
		if act.sit then Apts.sitting = act.sit end
		if act.emote then Apts.emote = { pose = act.emote, untilT = os.clock() + 2.2 } end
		if act.tune then
			task.spawn(function()
				for _, pitch in { 1, 1.26, 1.5, 1.26, 1.68, 1.5, 2 } do Audio.play("Chime", pitch, 0.7) task.wait(0.2) end
			end)
		else
			Audio.play("Pop", 1.1, 0.6)
		end
		if act.lines then UI.toast(act.lines[math.random(1, #act.lines)], C.mintDark) end
	end

	-- returns a prompt, "none" (inside, nothing nearby: keep the street's
	-- prompts quiet), or nil (not our business)
	function Apts.prompt(me)
		local hrp = myChar()
		if Apts.inside then
			if not hrp or not room then return "none" end
			local best, bd
			for _, sp in room.spots do
				local dist = (flat(hrp.Position) - flat(sp.pos)).Magnitude
				if dist < 7 and math.abs(hrp.Position.Y - sp.pos.Y) < 9 and (not bd or dist < bd) then best, bd = sp, dist end
			end
			if best then return { best.title, best.sub, best.btn, best.icon, function() use(best) end, best.pos } end
			if room.kind == "tour" then
				local b, p = Config.AptBuilding(room.building), Config.AptPlan(room.plan)
				return { p.name .. " · " .. Config.AptPrice(b, p) .. " coins", "like it? it can be yours", "BUY", "house", function() Apts.buy(p.id) end }
			end
			return "none"
		end
		for _, door in DOORS do
			if (flat(me) - flat(door.pos)).Magnitude < (door.r or 9) then
				local b = Config.AptBuilding(door.id)
				local mine = Apts.owned[door.id] ~= nil
				return { b.name, mine and "home sweet home" or "flats for sale · come and look round", mine and "GO IN" or "VISIT", "house", function() Apts.enter(door) end, CITY + door.pos }
			end
		end
		return nil
	end

	function Apts.update(dt, t)
		local hrp, hum = myChar()
		if not Apts.inside or not hrp then return end
		if Apts.sitting then
			if hum and hum.MoveDirection.Magnitude > 0.2 then
				Apts.sitting = nil
			else
				hrp.CFrame = Apts.sitting * CFrame.new(0, 2.9, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
				S.poses[player] = "sit"
			end
		end
		if Apts.emote then
			if os.clock() < Apts.emote.untilT then S.poses[player] = Apts.emote.pose else Apts.emote = nil end
		end
		-- fell out of the room somehow? put them back by the lift
		if room and hrp.Position.Y < FLAT_AT.Y - 60 then Apts.leave() end
	end

	Apts.doors = DOORS
	return Apts
end
