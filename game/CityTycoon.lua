-- CityTycoon (client): Restaurant Row -- the restaurant tycoon.
--
-- THE LOOP (docs/TYCOON.md). Walk up to a FOR LEASE gate on the Row and
-- CLAIM the lot. Build pads stand on the strip beside it, one per thing you
-- can afford next: step on, E, and the piece appears -- the doors, the
-- counter, a grill, tables, an oven, a terrace, a drive-thru. The pieces
-- unlock dishes; the dishes are recipes over the groceries; the STOCKROOM
-- holds the groceries, filled from the supplier or out of your own fridge.
-- While it is stocked the place sells on its own (collect at the register);
-- when you are behind the counter, customers queue and you SERVE them on
-- the kitchen panel; when a FRIEND walks in they ORDER off your menu and pay
-- you out of their own pocket.
--
-- WHAT THIS FILE OWNS. Everything you SEE of a restaurant: the building
-- drawn from the lot's replicated attributes (ReplicatedStorage.
-- SminskiTycoon.Lot<i>: Owner, Name, Pieces, Stars, Open, Chains, Gold), so
-- a friend's place looks the same on your screen as on theirs; the pads,
-- which only the owner sees; the prompt card lines; three cards (MY
-- RESTAURANT, STOCKROOM, the visitor's MENU); the customers at the pass.
-- Every coin is the server's: this module asks, the server prices, checks
-- where you are standing, and pays. CityBuild draws the plots (the apron,
-- the gate, the FOR LEASE post); CityKitchen lends its step panel for SERVE.
--   deps: K, Build, Models, UI, Audio, Places, Config, City, S, H, player,
--         remoteNamed, earned, cityData
return function(deps)
	local K, Build, Models, UI, Audio, Places, Config = deps.K, deps.Build, deps.Models, deps.UI, deps.Audio, deps.Places, deps.Config
	local City, S, H, player = deps.City, deps.S, deps.H, deps.player
	local remoteNamed, earned, cityData = deps.remoteNamed, deps.earned, deps.cityData
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local C, Cc = UI.C, K.C
	local CITY = Places.CITY
	local TY, CC = Config.Tycoon, Config.City
	local P, cyl, ball, blob = K.P, K.cyl, K.ball, K.blob
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL
	local Marketplace = game:GetService("MarketplaceService")

	local T = { lots = {}, mine = nil, sum = nil, cust = nil, nextCust = 0, lastState = 0 }
	local lots = Places.tycoonLots()
	local function flat(v) return V(v.X, 0, v.Z) end
	local function fmt(n) return UI.fmt and UI.fmt(n) or tostring(n) end
	local function stars(n) return string.rep("\u{2605}", n) .. string.rep("\u{2606}", 5 - n) end
	local function myTycoon()
		local c = cityData()
		return c and c.tycoon or nil
	end
	local function pieceSet(csv)
		local set = {}
		for id in string.gmatch(csv or "", "[^,]+") do set[id] = true end
		return set
	end

	-- one folder for the whole Row, under the city root (which leaves the
	-- world with the city). Not a streamed block: a lot's model is culled by
	-- distance in step(), because it changes while the block does not.
	local folder = Instance.new("Folder")
	folder.Name = "RestaurantRow"
	folder.Parent = K.root

	-- NOT K.solid / K.walkable: those file a part into whichever block's
	-- collision bin was seen last, and a wall that streams out with a block
	-- three roads away is a wall you walk through. Collision here is set on
	-- the part and the part stays in the lot's own model.
	local function solid(p) p.CanCollide, p.CanQuery = true, true return p end

	-- a colour per lot, so the Row is not twelve of the same restaurant
	local ACCENTS = { rgb(226, 100, 90), rgb(96, 150, 230), rgb(240, 150, 80), rgb(150, 96, 70), rgb(120, 170, 130), rgb(236, 110, 160),
		rgb(230, 150, 70), rgb(110, 160, 190), rgb(170, 150, 220), rgb(96, 180, 120), rgb(240, 170, 80), rgb(200, 100, 90) }
	local WALLS = { rgb(255, 238, 222), rgb(238, 244, 252), rgb(255, 244, 200), rgb(214, 244, 214), rgb(240, 226, 255), rgb(255, 222, 232) }

	---------------------------------------------------------------------------
	-- THE BUILDING. Drawn from a set of piece ids; every piece has a place on
	-- the plot (Config.Tycoon's plot-local coordinates: x right, z into the
	-- block). A piece that names an Inventory template stands as that
	-- template; otherwise it is board-built here, in the kit's own style.
	---------------------------------------------------------------------------
	local function table_(m, f, x, z, acc, seats, parasol)
		-- indoors the table stands on the floor (0.9 up the frame); a terrace
		-- table stands on the apron, which is the plot's own 0.5 slab
		local tcf = f * CFrame.new(x, parasol and 0.5 or 0.9, z)
		cyl(0.6, 2.6, tcf * CFrame.new(0, 1.3, 0), Cc.ink, METAL)
		solid(cyl(4.4, 0.4, tcf * CFrame.new(0, 2.8, 0), Cc.cream, SMOOTH))
		for _, sz in { -2.8, 2.8 } do
			local scf = tcf * CFrame.new(0, 0, sz) * CFrame.Angles(0, sz > 0 and 0 or math.pi, 0)
			cyl(0.5, 1.8, scf * CFrame.new(0, 0.9, 0), Cc.ink, METAL)
			cyl(2.2, 0.5, scf * CFrame.new(0, 2, 0), acc, SMOOTH)
			table.insert(seats, scf * CFrame.new(0, 2.2, 0))
		end
		if parasol then
			cyl(0.3, 8, tcf * CFrame.new(0, 4, 0), Cc.cream, SMOOTH)
			local can = blob(V(8, 2.2, 8), tcf * CFrame.new(0, 8.2, 0), acc, MATTE)
			can.CastShadow = false
		end
	end
	local function bench(f, x, z, w, acc, label, face)
		local cf = f * CFrame.new(x, 0.9, z) * CFrame.Angles(0, face or 0, 0)
		solid(P(V(w, 3.4, 4), cf * CFrame.new(0, 1.7, 0), Cc.cream, WOODM))
		P(V(w + 0.4, 0.4, 4.4), cf * CFrame.new(0, 3.6, 0), shade(Cc.stone, 0.05), SMOOTH)
		local plate = P(V(w - 1, 0.1, 0.9), cf * CFrame.new(0, 3.85, -1.9), acc, SMOOTH)
		K.textOn(plate, Enum.NormalId.Top, label, Cc.cream, Vector2.new(360, 60), 0)
		return cf
	end
	-- an appliance: the owner's kit piece if the template exists, else boards
	local function appliance(m, f, x, z, piece, acc, fallback)
		if piece.model and K.inv(piece.model) then
			-- the kit's appliances are clusters (the fries maker is 33 studs
			-- across), so they are fitted to the slot: whichever of a 7-stud
			-- footprint or a 5-stud height binds first
			local placed = K.place(piece.model, f * CFrame.new(x, 0.9, z), { width = 7, height = 5 })
			if placed then
				for _, d in placed:GetDescendants() do
					if d:IsA("BasePart") and d.Size.Magnitude > 3 then d.CanCollide, d.CanQuery = true, true end
				end
				placed.Parent = m
				return
			end
		end
		fallback()
	end

	local function build(L)
		if L.model then L.model:Destroy() L.model = nil end
		L.pads, L.seats, L.actors = {}, {}, {}
		if L.owner == 0 then return end
		local def = L.def
		local pieces = L.pieces
		local f = K.frameOf(def.pos, def.face)
		local acc = ACCENTS[(def.i - 1) % #ACCENTS + 1]
		local wall = WALLS[(def.i - 1) % #WALLS + 1]
		local m = Instance.new("Model")
		m.Name = "Lot" .. def.i
		local prev = K.cur
		K.cur = m
		L.model = m
		local name = string.upper(L.name ~= "" and L.name or "RESTAURANT")

		-- THE NAME BOARD over the FOR LEASE post, on both faces, with the stars
		do
			local sp = TY.Spots.sign
			local board = P(V(7.4, 3.6, 0.5), f * CFrame.new(sp[1], 9.6, sp[2] - 0.4), L.gold and Cc.gold or acc)
			local line = name .. "\n" .. stars(L.stars) .. (L.chains > 0 and ("  \u{00B7} " .. (L.chains + 1) .. " LOCATIONS") or "")
			K.textOn(board, Enum.NormalId.Front, line, L.gold and Cc.ink or Cc.cream, Vector2.new(320, 160), 0.4)
			K.textOn(board, Enum.NormalId.Back, line, L.gold and Cc.ink or Cc.cream, Vector2.new(320, 160), 0.4)
		end

		if pieces.doors then
			-- floor, three walls, a glass shopfront round an open door, a roof
			local fl = P(V(36, 0.4, 29), f * CFrame.new(-4, 0.7, 4.5), rgb(222, 204, 176), WOODM)
			solid(fl)
			local inner = tint(wall, 0.35)
			solid(P(V(36, 11, 1), f * CFrame.new(-4, 6.4, 18.5), inner))
			solid(P(V(1, 11, 29), f * CFrame.new(-21.5, 6.4, 4.5), inner))
			solid(P(V(1, 11, 29), f * CFrame.new(13.5, 6.4, 4.5), inner))
			local dx = TY.Spots.door[1]
			for _, seg in { { -22, dx - 3 }, { dx + 3, 14 } } do
				local w = seg[2] - seg[1]
				local cx = (seg[1] + seg[2]) / 2
				solid(P(V(w, 2.4, 1), f * CFrame.new(cx, 2.1, -9.5), shade(wall, 0.08)))
				local g = solid(P(V(w, 7.4, 0.4), f * CFrame.new(cx, 7, -9.5), Cc.pane, K.GLASS, { transparency = 0.6 }))
				g.CastShadow = false
			end
			for _, sx in { -1, 1 } do solid(P(V(0.6, 11, 1.2), f * CFrame.new(dx + sx * 3, 6.4, -9.5), acc)) end
			P(V(36, 1.4, 1), f * CFrame.new(-4, 11.6, -9.5), wall)
			P(V(37, 0.6, 30), f * CFrame.new(-4, 12.2, 4.5), acc)
			K.threshold(f * CFrame.new(dx, 0.5, -12), 7, 5)
			-- the menu board on the back wall
			local board = P(V(14, 3.2, 0.3), f * CFrame.new(4, 9.2, 18.3), Cc.ink)
			local names = {}
			for _, d in Config.TycoonMenuFor(pieces) do table.insert(names, string.upper(d.name)) end
			K.textOn(board, Enum.NormalId.Front, #names > 0 and table.concat(names, "  \u{00B7}  ") or "MENU COMING SOON", Cc.cream, Vector2.new(700, 160), 0)
			-- one warm light and the OPEN lamp over the door
			local lamp = ball(1.6, f * CFrame.new(-4, 10.6, 4.5), rgb(255, 236, 200), NEON)
			lamp.CastShadow = false
			local pl = Instance.new("PointLight")
			pl.Range, pl.Brightness, pl.Color, pl.Shadows = 30, 1, rgb(255, 232, 196), false
			pl.Parent = lamp
			local open = ball(1.2, f * CFrame.new(dx, 12.9, -9.9), L.open and rgb(120, 230, 140) or rgb(230, 96, 90), NEON)
			open.CastShadow = false
		end
		if pieces.counter then
			-- the pass: a bar from x -2 to 12 at z 9..11, the register on its
			-- right end, the tip jar on its left, a little fridge in the back
			solid(P(V(14, 3.4, 2.4), f * CFrame.new(5, 2.6, 10), shade(acc, 0.1), WOODM))
			P(V(14.6, 0.4, 3), f * CFrame.new(5, 4.5, 10), Cc.cream)
			local reg = K.inv("Register") and K.place("Register", f * CFrame.new(TY.Spots.till[1], 4.7, 10) * CFrame.Angles(0, math.pi, 0), { height = 1.6 })
			if reg then reg.Parent = m else P(V(1.6, 1.2, 1.4), f * CFrame.new(TY.Spots.till[1], 5.3, 10), Cc.ink, SMOOTH) end
			local jar = P(V(1.1, 1.3, 1.1), f * CFrame.new(TY.Spots.tips[1], 5.35, 10), Cc.pane, K.GLASS, { transparency = 0.4 })
			jar.CastShadow = false
			P(V(0.9, 0.5, 0.9), f * CFrame.new(TY.Spots.tips[1], 4.95, 10), Cc.gold, METAL)
			local sp = TY.Spots.stock
			appliance(m, f, sp[1] - 1, sp[2] + 3, { model = "Tyc_Fridge" }, acc, function()
				solid(P(V(3.2, 6.2, 3), f * CFrame.new(sp[1] - 1, 4, sp[2] + 3), rgb(232, 238, 242), SMOOTH))
				P(V(0.3, 2.4, 0.3), f * CFrame.new(sp[1] - 1 - 1.3, 4.4, sp[2] + 1.4), Cc.ink, METAL)
			end)
		end
		if pieces.stockroom then
			-- shelving along the back-left wall, and the farm pack's crates
			local sp = TY.Spots.stock
			solid(P(V(8, 7.4, 1.2), f * CFrame.new(sp[1] + 4, 4.6, 18.2), rgb(200, 146, 96), WOODM))
			for k = 0, 2 do P(V(7.6, 0.3, 1.4), f * CFrame.new(sp[1] + 4, 2.2 + k * 2.2, 18.1), Cc.cream, WOODM) end
			for k, nm in { "Crate_1", "Crate_4", "Crate_7" } do
				local cr = K.inv(nm) and K.place(nm, f * CFrame.new(sp[1] + 1.5 + k * 2.4, 0.9, 15), { height = 1.8 })
				if cr then cr.Parent = m else P(V(2, 1.8, 2), f * CFrame.new(sp[1] + 1.5 + k * 2.4, 1.8, 15), rgb(200, 146, 96), WOODM) end
			end
		end
		if pieces.grill then
			appliance(m, f, -8, 16, Config.TycoonPiece("grill"), acc, function()
				local cf = bench(f, -8, 16, 6, acc, "THE GRILL", math.pi)
				P(V(4.6, 0.3, 2.6), cf * CFrame.new(0, 3.75, 0.2), Cc.ink, METAL)
				P(V(5, 1.4, 3.4), cf * CFrame.new(0, 9.4, 0.4), shade(Cc.stone, 0.1), METAL)
			end)
		end
		if pieces.oven then
			appliance(m, f, 0, 16, Config.TycoonPiece("oven"), acc, function()
				local cf = f * CFrame.new(0, 0.9, 16)
				solid(P(V(6, 6.4, 4.4), cf * CFrame.new(0, 3.2, 0), rgb(200, 120, 96), Enum.Material.Brick))
				P(V(3.4, 2.2, 0.6), cf * CFrame.new(0, 3, -2.1), rgb(60, 40, 40), SMOOTH)
				local fire = P(V(2.8, 1.2, 0.3), cf * CFrame.new(0, 2.8, -2.2), rgb(255, 170, 80), NEON)
				fire.CastShadow = false
			end)
		end
		if pieces.drinks then
			appliance(m, f, 10, 16, Config.TycoonPiece("drinks"), acc, function()
				local cf = f * CFrame.new(10, 0.9, 16)
				solid(P(V(3.6, 6.6, 3), cf * CFrame.new(0, 3.3, 0), acc, SMOOTH))
				local face = P(V(3, 3, 0.3), cf * CFrame.new(0, 4.6, -1.6), rgb(255, 176, 130), NEON)
				face.CastShadow = false
				K.textOn(face, Enum.NormalId.Front, "FIZZ", Cc.ink, Vector2.new(200, 100), 0)
				for k = 0, 2 do P(V(0.5, 1.2, 0.5), cf * CFrame.new(-1 + k, 2.4, -1.7), Cc.ink, METAL) end
			end)
		end
		if pieces.fryer then
			appliance(m, f, -19, 6, Config.TycoonPiece("fryer"), acc, function()
				local cf = bench(f, -19, 6, 6, acc, "THE FRYER", -math.pi / 2)
				for _, dx in { -1.4, 1.4 } do
					P(V(2.2, 1.6, 2.2), cf * CFrame.new(dx, 4.3, 0.2), Cc.ink, METAL)
					P(V(1.8, 0.4, 1.8), cf * CFrame.new(dx, 5.2, 0.2), rgb(240, 200, 120), MATTE)
				end
			end)
		end
		if pieces.dessert then
			local cf = f * CFrame.new(-19, 0.9, -2) * CFrame.Angles(0, -math.pi / 2, 0)
			solid(P(V(7, 2.6, 3.6), cf * CFrame.new(0, 1.3, 0), Cc.cream, WOODM))
			local g = P(V(7, 2.2, 3.6), cf * CFrame.new(0, 3.7, 0), Cc.pane, K.GLASS, { transparency = 0.55 })
			g.CastShadow = false
			for k = 0, 2 do
				blob(V(1.6, 1.1, 1.6), cf * CFrame.new(-2.2 + k * 2.2, 3.3, 0), ({ rgb(255, 150, 190), rgb(255, 230, 150), rgb(200, 140, 90) })[k + 1], SMOOTH)
			end
			local plate = P(V(6, 0.1, 0.9), cf * CFrame.new(0, 2.65, -1.7), acc, SMOOTH)
			K.textOn(plate, Enum.NormalId.Top, "DESSERTS", Cc.cream, Vector2.new(360, 60), 0)
		end
		if pieces.tables1 then table_(m, f, -14, -3, acc, L.seats) table_(m, f, -6, -3, acc, L.seats) end
		if pieces.tables2 then table_(m, f, 3, -3, acc, L.seats) table_(m, f, 9, -3, acc, L.seats) end
		if pieces.terrace then
			-- x -14 / -5 / 11: clear of the door (x -1..5), the FOR LEASE post
			-- (x < -17.5) and the pad strip (x > 16) with the parasols open
			for _, x in { -14, -5, 11 } do table_(m, f, x, -14, acc, L.seats, true) end
		end
		if pieces.drivethru then
			local g = solid(P(V(0.5, 3.2, 5), f * CFrame.new(14.3, 6, 14), Cc.pane, K.GLASS, { transparency = 0.5 }))
			g.CastShadow = false
			P(V(0.6, 0.5, 5.6), f * CFrame.new(14.3, 4.2, 14), Cc.cream)
			local sg = P(V(5, 1.6, 0.4), f * CFrame.new(17.2, 9.4, 14) * CFrame.Angles(0, math.pi / 2, 0), acc)
			K.textOn(sg, Enum.NormalId.Front, "DRIVE-THRU", Cc.cream, Vector2.new(400, 110), 0.3)
			K.textOn(sg, Enum.NormalId.Back, "DRIVE-THRU", Cc.cream, Vector2.new(400, 110), 0.3)
			cyl(0.4, 9, f * CFrame.new(17.2, 4.5, 14), Cc.lampPost, METAL)
		end
		if pieces.sign then
			K.neonSign(f * CFrame.new(-4, 14.6, -9.4), string.sub(name, 1, 14), L.gold and Cc.gold or acc, false, 2.6)
		end
		if pieces.chef then
			local cdef = Config.Characters[(def.i * 3) % #Config.Characters + 1]
			local rig = Models.buildSminski(m, 1, cdef, false, "beanie")
			local at = f * CFrame.new(5, 0.9, 13)
			Models.poseSminski(rig, at, "idle", 0)
			-- the hat: a toque is a white cylinder, and a beanie is not white
			local hat = P(V(1.7, 1.2, 1.7), at * CFrame.new(0, 3.3, 0), Cc.cream, SMOOTH)
			table.insert(L.actors, { rig = rig, cf = at, hat = hat, pose = "idle", t0 = math.random() * 9 })
		end
		-- DINERS, if there is anything to sell: one Sminski per table, sat,
		-- for every player to see. What a busy restaurant looks like.
		if L.open and #L.seats > 0 then
			for k = 1, #L.seats, 2 do
				if math.random() < 0.7 then
					local cdef = Config.Characters[(def.i + k) % #Config.Characters + 1]
					local rig = Models.buildSminski(m, 1, cdef, false, nil)
					local seat = L.seats[k] * CFrame.new(0, 0.95, 0)
					Models.poseSminski(rig, seat, "sit", k)
					table.insert(L.actors, { rig = rig, cf = seat, pose = "sit", t0 = k })
				end
			end
		end
		-- THE PADS: the owner's alone. One per piece whose turn it is.
		if L.owner == player.UserId then
			for k, p in Config.TycoonAvailable(pieces) do
				local slot = TY.Spots.pads[k]
				if not slot then break end
				local pcf = f * CFrame.new(slot[1], 0.5, slot[2])
				local pad = K.inv("TycoonPad") and K.place("TycoonPad", pcf, { width = 4.2 })
				if pad then pad.Parent = m else cyl(4.2, 0.3, pcf * CFrame.new(0, 0.15, 0), p.price == 0 and rgb(120, 230, 140) or acc, SMOOTH) end
				local board = P(V(5.4, 2.4, 0.3), pcf * CFrame.new(0, 4.4, 0), Cc.cream)
				local line = string.upper(p.name) .. "\n" .. (p.price == 0 and "FREE" or (fmt(p.price) .. " COINS"))
				K.textOn(board, Enum.NormalId.Front, line, Cc.ink, Vector2.new(300, 130), 0.4)
				K.textOn(board, Enum.NormalId.Back, line, Cc.ink, Vector2.new(300, 130), 0.4)
				cyl(0.25, 3.2, pcf * CFrame.new(0, 1.6, 0), Cc.lampPost, METAL)
				L.pads[p.id] = { pos = Places.tycoonPoint(def, slot[1], slot[2]), piece = p }
			end
		end
		K.cur = prev
		m.Parent = folder
	end

	---------------------------------------------------------------------------
	-- THE LOTS, mirrored from ReplicatedStorage. Attributes, not a remote: a
	-- friend's restaurant arrives the moment they buy a piece.
	---------------------------------------------------------------------------
	local function readLot(L)
		local cfg = L.cfg
		L.owner = cfg:GetAttribute("Owner") or 0
		L.ownerName = cfg:GetAttribute("OwnerName") or ""
		L.name = cfg:GetAttribute("Name") or ""
		L.pieces = pieceSet(cfg:GetAttribute("Pieces"))
		L.stars = cfg:GetAttribute("Stars") or 1
		L.open = cfg:GetAttribute("Open") == true
		L.chains = cfg:GetAttribute("Chains") or 0
		L.gold = cfg:GetAttribute("Gold") == true
		if L.owner == player.UserId then T.mine = L.def.i elseif T.mine == L.def.i then T.mine = nil end
	end
	local function watch()
		local RS = game:GetService("ReplicatedStorage")
		local root = RS:WaitForChild("SminskiTycoon", 20)
		if not root then return end
		for _, def in lots do
			local cfg = root:WaitForChild("Lot" .. def.i, 10)
			if cfg then
				local L = { def = def, cfg = cfg, pads = {}, seats = {}, actors = {}, dirty = true, near = false }
				T.lots[def.i] = L
				readLot(L)
				cfg.AttributeChanged:Connect(function()
					readLot(L)
					L.dirty = true
				end)
			end
		end
	end

	---------------------------------------------------------------------------
	-- ASKING THE SERVER
	---------------------------------------------------------------------------
	local function call(action, arg, what, after)
		local key = "ty" .. action
		if S.pending[key] then return end
		S.pending[key] = true
		task.spawn(function()
			local res = remoteNamed("Tycoon", action, arg)
			S.pending[key] = nil
			if res and res.ok then
				T.sum = res.sum
				T.mine = res.lot or T.mine
			end
			earned(res, what or "")
			if after then after(res) end
		end)
	end
	function T.refresh()
		T.lastState = os.clock()
		call("state", nil, "")
	end
	function T.claim(i)
		call("claim", i, "", function(res)
			if res and res.ok then
				UI.toast("lot " .. i .. " is yours -- step on the green pad to open the doors", C.mintDark)
				Audio.play("BigChime", 1.2, 0.8)
				if City.Jobs and City.Jobs.notify then City.Jobs.notify("chart", "RESTAURANT ROW", "your lot. Build pads are on the right of the gate.", C.gold) end
			end
		end)
	end
	local function buy(p)
		call("buy", p.id, "", function(res)
			if res and res.ok then
				UI.toast(string.lower(p.name) .. (p.price > 0 and (" -- " .. fmt(p.price) .. " coins") or "") .. "  \u{00B7}  " .. p.blurb, C.mintDark)
				Audio.play("BigChime", 1.1, 0.8)
			end
		end)
	end

	---------------------------------------------------------------------------
	-- THE CARDS
	---------------------------------------------------------------------------
	local manage, stockCard, menuCard = {}, {}, {}
	local function row(parent, y, h)
		local r = Instance.new("Frame")
		r.Size = UDim2.new(1, -48, 0, h or 56)
		r.Position = UDim2.fromOffset(24, y)
		r.BackgroundColor3 = C.paper2
		r.BorderSizePixel = 0
		r.Parent = parent
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = r
		return r
	end
	local function robuxButton(parent, prod, y, isPass)
		local id = isPass and prod.gamePassId or prod.productId
		local label = prod.name .. (id ~= 0 and ("  \u{00B7}  R$" .. prod.robux) or "  \u{00B7}  COMING SOON")
		local b = UI.button(parent, label, { size = UDim2.new(1, -48, 0, 50), pos = UDim2.fromOffset(24, y), color = id ~= 0 and prod.color or C.paper2,
			textColor = id ~= 0 and C.white or C.inkSoft, textSize = 17, icon = prod.icon, onClick = function()
				if id == 0 then UI.toast("not on sale yet", C.coral) return end
				if isPass then Marketplace:PromptGamePassPurchase(player, id) else Marketplace:PromptProductPurchase(player, id) end
			end })
		return b
	end

	function T.init(root)
		-- MY RESTAURANT ---------------------------------------------------------
		do
			local dim, card = City.modalCard(640, 600, "MY RESTAURANT")
			manage.shade = dim
			manage.sub = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(24, 64),
				TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			-- the name
			local nr = row(card, 92, 56)
			local box = Instance.new("TextBox")
			box.Size = UDim2.new(1, -190, 0, 40)
			box.Position = UDim2.fromOffset(14, 8)
			box.BackgroundColor3 = C.paper
			box.BorderSizePixel = 0
			box.Font = Enum.Font.FredokaOne
			box.TextSize = 20
			box.TextColor3 = C.ink
			box.PlaceholderText = "name your restaurant"
			box.ClearTextOnFocus = false
			box.Text = ""
			box.Parent = nr
			local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 12) bc.Parent = box
			manage.name = box
			UI.button(nr, "NAME IT", { size = UDim2.fromOffset(150, 44), pos = UDim2.new(1, -10, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.sky, textSize = 17, onClick = function()
				call("rename", box.Text, "", function(res)
					if res and res.ok then UI.toast("the sign says " .. string.upper(box.Text), C.mintDark) Audio.play("Chime", 1.2, 0.7) end
				end)
			end })
			-- the numbers
			manage.lines = {}
			for k = 1, 4 do
				manage.lines[k] = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(24, 156 + (k - 1) * 24),
					TextSize = 15, TextColor3 = k == 1 and C.ink or C.inkSoft, Font = k == 1 and Enum.Font.FredokaOne or Enum.Font.GothamMedium,
					TextXAlignment = Enum.TextXAlignment.Left })
			end
			-- the stockroom bar
			local track = Instance.new("Frame")
			track.Size = UDim2.new(1, -48, 0, 12)
			track.Position = UDim2.fromOffset(24, 256)
			track.BackgroundColor3 = C.paper2
			track.BorderSizePixel = 0
			track.Parent = card
			local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 6) tc.Parent = track
			manage.fill = Instance.new("Frame")
			manage.fill.Size = UDim2.fromScale(0, 1)
			manage.fill.BackgroundColor3 = C.mint
			manage.fill.BorderSizePixel = 0
			manage.fill.Parent = track
			local fc = Instance.new("UICorner") fc.CornerRadius = UDim.new(0, 6) fc.Parent = manage.fill
			-- the coin buttons
			manage.chain = UI.button(card, "", { size = UDim2.new(1, -48, 0, 54), pos = UDim2.fromOffset(24, 282), color = C.lav, textSize = 18, icon = "chart", onClick = function()
				call("chain", nil, "", function(res)
					if res and res.ok then UI.toast("location #" .. (res.chains + 1) .. " is open -- +" .. math.floor(TY.Chain.rate * 100) .. "% sales", C.mintDark) Audio.play("BigChime", 1.2, 0.8) end
				end)
			end })
			manage.go = UI.button(card, "TAKE ME THERE", { size = UDim2.new(1, -48, 0, 50), pos = UDim2.fromOffset(24, 344), color = C.mint, textSize = 18, icon = "pin", onClick = function()
				dim.Visible = false
				local L = T.mine and T.lots[T.mine]
				City.Way.to(L and Places.tycoonSpot(L.def, "gate") or Places.RestaurantRow, L and "your restaurant" or "Restaurant Row")
				UI.toast("follow the green line", C.mintDark)
			end })
			-- Robux: time and skips, never a rate
			UI.text(card, "WITH ROBUX", { Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(24, 404), Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			robuxButton(card, Config.Product("tycoonrush"), 424)
			robuxButton(card, Config.Product("tycoonpantry"), 480)
			robuxButton(card, Config.Pass("restaurateur"), 536, true)
		end
		-- THE STOCKROOM ---------------------------------------------------------
		do
			local dim, card = City.modalCard(620, 620, "STOCKROOM")
			stockCard.shade = dim
			stockCard.sub = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 36), Position = UDim2.fromOffset(24, 62),
				TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
			local list = Instance.new("ScrollingFrame")
			list.Size = UDim2.new(1, -48, 0, 360)
			list.Position = UDim2.fromOffset(24, 104)
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.ScrollBarThickness = 6
			list.CanvasSize = UDim2.new(0, 0, 0, 0)
			list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			list.Parent = card
			local lay = Instance.new("UIListLayout")
			lay.Padding = UDim.new(0, 6)
			lay.Parent = list
			stockCard.list = list
			stockCard.fill = UI.button(card, "", { size = UDim2.new(0.5, -30, 0, 54), pos = UDim2.fromOffset(24, 478), color = C.gold, textSize = 17, icon = "bag", onClick = function()
				call("restock", "all", "", function(res)
					if res and res.ok then UI.toast(res.crates .. " crate" .. (res.crates == 1 and "" or "s") .. " delivered  \u{00B7}  " .. fmt(res.paid) .. " coins", C.mintDark) Audio.play("Chime", 1.2, 0.7) stockCard.refresh() end
				end)
			end })
			stockCard.unload = UI.button(card, "", { size = UDim2.new(0.5, -30, 0, 54), pos = UDim2.new(0.5, 6, 0, 478), color = C.mint, textSize = 17, icon = "house", onClick = function()
				call("unload", nil, "", function(res)
					if res and res.ok then UI.toast(res.moved .. " thing" .. (res.moved == 1 and "" or "s") .. " out of your fridge, into the stockroom", C.mintDark) Audio.play("Chime", 1.2, 0.7) stockCard.refresh() end
				end)
			end })
			UI.text(card, "The kitchen cooks from what is here. When it runs bare, nothing sells -- and nothing banks while you are away.",
				{ Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 546), TextSize = 13, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
		end
		-- THE MENU (a visitor's) -----------------------------------------------
		do
			local dim, card = City.modalCard(600, 560, "MENU")
			menuCard.shade = dim
			menuCard.title = card:FindFirstChildOfClass("TextLabel")
			menuCard.sub = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(24, 62),
				TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			local list = Instance.new("ScrollingFrame")
			list.Size = UDim2.new(1, -48, 0, 400)
			list.Position = UDim2.fromOffset(24, 92)
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.ScrollBarThickness = 6
			list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			list.CanvasSize = UDim2.new()
			list.Parent = card
			local lay = Instance.new("UIListLayout")
			lay.Padding = UDim.new(0, 6)
			lay.Parent = list
			menuCard.list = list
			UI.text(card, "What you pay goes straight into their till. You get the meal, and the XP.",
				{ Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 500), TextSize = 13, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
		end
		-- the owner hears about friends at the counter
		task.spawn(function()
			local RS = game:GetService("ReplicatedStorage")
			local rem = RS:WaitForChild("SminskiRemotes", 10)
			local ev = rem and rem:WaitForChild("TycoonEvent", 10)
			if ev then
				ev.OnClientEvent:Connect(function(e)
					if type(e) ~= "table" then return end
					if e.kind == "order" then
						if City.Jobs and City.Jobs.notify then City.Jobs.notify("coin", "ORDER!", (e.who or "someone") .. " bought a " .. string.lower(e.dish or "meal") .. "  \u{00B7}  +" .. fmt(e.coins or 0) .. " in the till", C.gold) end
						Audio.play("Chime", 1.3, 0.6)
					elseif e.kind == "tip" then
						if City.Jobs and City.Jobs.notify then City.Jobs.notify("coin", "A TIP!", (e.who or "someone") .. " left " .. fmt(e.coins or 0) .. " coins in your jar", C.gold) end
						Audio.play("Chime", 1.4, 0.6)
					end
				end)
			end
		end)
		task.spawn(watch)
	end

	function manage.refresh()
		local t = myTycoon()
		local sm = T.sum
		if not t then return end
		local L = T.mine and T.lots[T.mine]
		manage.name.Text = t.name or ""
		local n = 0
		for _ in pairs(t.pieces or {}) do n += 1 end
		local st = sm and sm.stars or Config.TycoonStars(t.xp or 0)
		manage.sub.Text = (L and ("lot " .. T.mine .. " on Restaurant Row") or "no lot claimed -- walk up to a FOR LEASE gate") .. "  \u{00B7}  " .. n .. "/" .. #TY.Pieces .. " pieces"
		manage.lines[1].Text = stars(st) .. "   " .. string.format("%.0f coins of sales a minute while stocked", sm and sm.rate or 0)
		manage.lines[2].Text = sm and string.format("%s in the till  \u{00B7}  %s sold since you last collected%s", fmt(sm.bank + sm.till + sm.due), fmt(sm.dueOrders), sm.dry and "  \u{00B7}  the stockroom ran bare" or "") or ""
		manage.lines[3].Text = string.format("%s served by you  \u{00B7}  %s ordered by friends  \u{00B7}  %s sold on its own", fmt(t.served or 0), fmt(t.sold or 0), fmt(t.sales or 0))
		manage.lines[4].Text = sm and string.format("stockroom %d / %d", sm.stock, sm.cap) or ""
		manage.fill.Size = UDim2.fromScale(sm and sm.cap > 0 and math.clamp(sm.stock / sm.cap, 0, 1) or 0, 1)
		manage.fill.BackgroundColor3 = (sm and sm.stock / math.max(1, sm.cap) < 0.2) and C.coral or C.mint
		local chains = t.chains or 0
		local maxC = sm and sm.maxChains or TY.Chain.max
		if chains >= maxC then
			manage.chain.setText((chains + 1) .. " LOCATIONS -- THAT IS ALL OF THEM")
			manage.chain.setColor(C.paper2)
		else
			manage.chain.setText(string.format("OPEN LOCATION #%d  \u{00B7}  %s COINS  \u{00B7}  +%d%% SALES", chains + 2, fmt(sm and sm.chainPrice or (TY.Chain.base + TY.Chain.step * chains)), math.floor(TY.Chain.rate * 100)))
			manage.chain.setColor(C.lav)
		end
	end
	function T.open()
		T.refresh()
		manage.refresh()
		manage.shade.Visible = true
		task.delay(0.5, function() if manage.shade.Visible then manage.refresh() end end)
	end

	function stockCard.refresh()
		local t = myTycoon()
		local sm = T.sum
		if not t then return end
		for _, c in stockCard.list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		stockCard.sub.Text = sm and string.format("%d / %d in the stockroom. The supplier sells crates of %d at %d%% of the shelf price.", sm.stock, sm.cap, TY.Crate, math.floor(TY.CrateDiscount * 100)) or ""
		local menu = Config.TycoonMenuFor(t.pieces or {})
		local ids = {}
		for _, d in menu do for _, gid in d.needs do if not table.find(ids, gid) then table.insert(ids, gid) end end end
		local total = 0
		for k, gid in ids do
			local g = Config.Grocery(gid)
			local have = (t.stock or {})[gid] or 0
			local price = math.floor(g.price * TY.Crate * TY.CrateDiscount + 0.5)
			local r = row(stockCard.list, 0, 50)
			r.LayoutOrder = k
			r.Size = UDim2.new(1, -8, 0, 50)
			local sw = Instance.new("Frame")
			sw.Size = UDim2.fromOffset(14, 14)
			sw.Position = UDim2.fromOffset(14, 18)
			sw.BackgroundColor3 = g.col or C.mint
			sw.BorderSizePixel = 0
			sw.Parent = r
			local sc = Instance.new("UICorner") sc.CornerRadius = UDim.new(1, 0) sc.Parent = sw
			UI.text(r, g.name, { Size = UDim2.fromOffset(200, 50), Position = UDim2.fromOffset(36, 0), Font = Enum.Font.FredokaOne, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left })
			UI.text(r, have .. " in stock", { Size = UDim2.fromOffset(120, 50), Position = UDim2.fromOffset(240, 0), TextSize = 14, TextColor3 = have == 0 and C.coral or C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(r, "+" .. TY.Crate .. "  \u{00B7}  " .. fmt(price), { size = UDim2.fromOffset(160, 40), pos = UDim2.new(1, -8, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.gold, textSize = 15, onClick = function()
				call("restock", gid, "", function(res)
					if res and res.ok then Audio.play("Pop", 1.2, 0.6) stockCard.refresh() end
				end)
			end })
			-- what FILL IT UP would buy of this one: up to its even share of the cap
			local target = sm and math.floor(sm.cap / #ids) or 0
			total += price * math.max(0, math.floor((target - have) / TY.Crate))
		end
		if #ids == 0 then
			UI.text(stockCard.list, "Build the counter first -- there is no menu to stock for yet.", { Size = UDim2.new(1, -8, 0, 40), TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true })
		end
		stockCard.fill.setText("FILL IT UP  \u{00B7}  ~" .. fmt(total))
		local pantry = 0
		local c = cityData()
		for _, q in pairs(c and c.pantry or {}) do pantry += q end
		stockCard.unload.setText("UNLOAD MY FRIDGE  (" .. pantry .. ")")
		stockCard.unload.setColor(pantry > 0 and C.mint or C.paper2)
	end
	function T.openStock()
		call("state", nil, "", function() stockCard.refresh() end)
		stockCard.refresh()
		stockCard.shade.Visible = true
	end

	function T.openMenu(i)
		local L = T.lots[i]
		if not L then return end
		if menuCard.title then menuCard.title.Text = string.upper(L.name ~= "" and L.name or "MENU") end
		menuCard.sub.Text = "run by " .. L.ownerName .. "  \u{00B7}  " .. stars(L.stars) .. (L.open and "" or "  \u{00B7}  sold out right now")
		for _, c in menuCard.list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local menu = Config.TycoonMenuFor(L.pieces)
		for k, d in menu do
			local r = row(menuCard.list, 0, 54)
			r.LayoutOrder = k
			r.Size = UDim2.new(1, -8, 0, 54)
			UI.icon(r, "heart", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(12, 12) })
			UI.text(r, d.name, { Size = UDim2.fromOffset(220, 30), Position = UDim2.fromOffset(50, 4), Font = Enum.Font.FredokaOne, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left })
			local ing = {}
			for _, gid in d.needs do local g = Config.Grocery(gid) if g then table.insert(ing, string.lower(g.name)) end end
			UI.text(r, table.concat(ing, ", "), { Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(50, 30), TextSize = 12, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(r, "ORDER  \u{00B7}  " .. fmt(d.price), { size = UDim2.fromOffset(170, 42), pos = UDim2.new(1, -8, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.coral, textSize = 15, onClick = function()
				call("order", { lot = i, dish = d.id }, "", function(res)
					if res and res.ok then
						menuCard.shade.Visible = false
						UI.toast("yum! " .. string.lower(d.name) .. " at " .. string.upper(L.name) .. "  \u{00B7}  +" .. math.floor(d.price * TY.DineXPPerCoin) .. " xp", C.mintDark)
						Audio.play("BigChime", 1.25, 0.7)
						if City.Venues then City.Venues.emote = { pose = "cheer", untilT = os.clock() + 2.2 } end
					end
				end)
			end })
		end
		if #menu == 0 then
			UI.text(menuCard.list, "Nothing on the menu yet -- they are still building.", { Size = UDim2.new(1, -8, 0, 40), TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true })
		end
		menuCard.shade.Visible = true
	end

	---------------------------------------------------------------------------
	-- CUSTOMERS AT YOUR PASS. Client-side company: somebody walks in, stands
	-- at the counter with a ticket over their head, and waits. SERVE plays
	-- the dish's two steps on the kitchen panel and tells the server; the
	-- server prices it, paces it, eats the ingredients and pays.
	---------------------------------------------------------------------------
	local function clearCust(walkOut)
		local cu = T.cust
		if not cu then return end
		T.cust = nil
		if walkOut then
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 1.6 and cu.rig.model.Parent do
					local a = (os.clock() - t0) / 1.6
					Models.poseSminski(cu.rig, cu.at:Lerp(cu.door, a) * CFrame.Angles(0, math.pi, 0), "run", os.clock() * 1.2, { stride = 14 })
					task.wait()
				end
				cu.rig.model:Destroy()
			end)
		else
			cu.rig.model:Destroy()
		end
	end
	local function spawnCust(L)
		local t = myTycoon()
		if not t then return end
		local menu = {}
		for _, d in Config.TycoonMenuFor(t.pieces or {}) do
			local ok = true
			for _, gid in d.needs do if ((t.stock or {})[gid] or 0) < 1 then ok = false break end end
			if ok then table.insert(menu, d) end
		end
		if #menu == 0 then return end
		local dish = menu[math.random(1, #menu)]
		local f = K.frameOf(L.def.pos, L.def.face)
		local q, dr = TY.Spots.queue, TY.Spots.door
		local cdef = Config.Characters[math.random(1, #Config.Characters)]
		local rig = Models.buildSminski(folder, 1, cdef, false, nil)
		local at = f * CFrame.new(q[1], 0.9, q[2])
		local door = f * CFrame.new(dr[1], 0.9, dr[2] - 4)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(190, 62)
		bb.StudsOffset = Vector3.new(0, 5.4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.Adornee = rig.body
		bb.Parent = rig.body
		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = C.paper
		card.BorderSizePixel = 0
		card.Parent = bb
		local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, 12) cc.Parent = card
		UI.text(card, string.upper(dish.name), { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 6), Font = Enum.Font.FredokaOne, TextSize = 19 })
		UI.text(card, fmt(dish.price) .. " coins", { Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 32), TextSize = 13, TextColor3 = C.inkSoft })
		T.cust = { rig = rig, dish = dish, at = at, door = door, t0 = os.clock(), lot = L.def.i, arrived = false }
		Audio.play("Chime", 1.3, 0.5)
	end
	function T.serve()
		local cu = T.cust
		if not cu or not cu.arrived or T.serving then return end
		if not City.Kitchen or not City.Kitchen.play then return end
		T.serving = true
		local ok = City.Kitchen.play({ name = cu.dish.name, note = "for the customer at the pass" }, cu.dish.steps, function(score)
			T.serving = nil
			if score == nil then UI.toast("the order was dropped", C.coral) return end
			call("serve", { dish = cu.dish.id, score = score }, string.format("served a %s  \u{00B7}  %d%%", string.lower(cu.dish.name), math.floor(score * 100)), function(res)
				if res and res.ok then
					if City.Venues then City.Venues.emote = { pose = "cheer", untilT = os.clock() + 1.4 } end
					clearCust(true)
					T.nextCust = os.clock() + math.random(TY.CustomerEvery[1], TY.CustomerEvery[2]) * 0.5
				end
			end)
		end)
		if not ok then T.serving = nil end
	end

	---------------------------------------------------------------------------
	-- THE PROMPT CARD. One line for wherever you are standing on the Row.
	---------------------------------------------------------------------------
	function T.prompt(me)
		local best, bd
		for _, L in T.lots do
			local d = (flat(me) - flat(L.def.pos)).Magnitude
			if d < TY.Reach and (not bd or d < bd) then best, bd = L, d end
		end
		if not best then return nil end
		local L, def, i = best, best.def, best.def.i
		local function at(spot, r)
			local p = Places.tycoonSpot(def, spot)
			return p and (flat(me) - flat(p)).Magnitude < (r or TY.SpotRadius)
		end
		local gate = CITY + Places.tycoonSpot(def, "gate")
		if L.owner == 0 then
			if at("gate", TY.ClaimRadius) then
				if T.mine then return { "LOT " .. i .. "  \u{00B7}  FOR LEASE", "you already run lot " .. T.mine .. " -- one restaurant each", nil, "chart", nil } end
				return { "LOT " .. i .. "  \u{00B7}  FOR LEASE", "claim it and open a restaurant  \u{00B7}  free", "CLAIM", "chart", function() T.claim(i) end, gate }
			end
			return nil
		end
		local name = string.upper(L.name ~= "" and L.name or "RESTAURANT")
		if L.owner == player.UserId then
			local sm = T.sum
			-- the NEAREST pad, not the first in reach: the slots are five studs
			-- apart, and pairs() order once offered THE SIGN from the counter's pad
			local pad, pd
			for _, cand in pairs(L.pads) do
				local d = (flat(me) - flat(cand.pos)).Magnitude
				if d < 4 and (not pd or d < pd) then pad, pd = cand, d end
			end
			if pad then
				local p = pad.piece
				return { string.upper(p.name), p.blurb .. (p.rate > 0 and ("  \u{00B7}  +" .. p.rate .. " sales/min") or ""),
					p.price == 0 and "OPEN UP" or ("BUY  \u{00B7}  " .. fmt(p.price)), "chart", function() buy(p) end, CITY + pad.pos }
			end
			if not L.pieces.counter then
				if at("gate", TY.ClaimRadius) then return { name, "your lot  \u{00B7}  the build pads are along the strip", "MANAGE", "chart", T.open, gate } end
				return nil
			end
			if at("till") then
				local waiting = sm and (sm.bank + sm.till + sm.due) or 0
				local sub = sm and (sm.full and (fmt(waiting) .. " waiting  \u{00B7}  shift finished, +" .. math.floor((CC.ShiftBonus or 0) * 100) .. "% on the takings")
					or (fmt(waiting) .. " waiting  \u{00B7}  " .. math.ceil(sm.shiftLeft / 60) .. " min to the bonus" .. (sm.dry and "  \u{00B7}  stockroom bare" or ""))) or "the register"
				return { "THE REGISTER", sub, "COLLECT", "coin", function()
					call("collect", nil, "from the register", function(res)
						if res and res.ok then
							if res.bonus > 0 then UI.toast("+" .. fmt(res.bonus) .. " shift bonus on top", C.gold) end
							Audio.play("BigChime", 1.2, 0.8)
						end
					end)
				end, CITY + Places.tycoonSpot(def, "till") }
			end
			if at("stock") then
				local sub = sm and (sm.stock .. " / " .. sm.cap .. " in the stockroom" .. (sm.stock == 0 and "  \u{00B7}  nothing sells until it is stocked" or "")) or "the stockroom"
				return { "STOCKROOM", sub, "RESTOCK", "bag", T.openStock, CITY + Places.tycoonSpot(def, "stock") }
			end
			if at("queue", TY.SpotRadius + 1) then
				local cu = T.cust
				if cu and cu.arrived then
					return { "ORDER UP", string.lower(cu.dish.name) .. "  \u{00B7}  " .. fmt(cu.dish.price) .. " coins  \u{00B7}  two quick steps", "SERVE", "heart", T.serve, CITY + Places.tycoonSpot(def, "queue") }
				end
				return { "THE PASS", L.open and "a customer will be along in a moment" or "stock the kitchen and they will come", nil, "heart", nil }
			end
			if at("gate", TY.ClaimRadius) or at("sign") then
				return { name, "yours  \u{00B7}  " .. stars(L.stars) .. (L.chains > 0 and ("  \u{00B7}  " .. (L.chains + 1) .. " locations") or ""), "MANAGE", "chart", T.open, gate }
			end
			return nil
		end
		-- somebody else's restaurant. The jar first: it is six studs from
		-- the pass, inside the pass's reach, so it has to win when you are on it
		if L.pieces.counter and at("tips", 3.5) then
			return { "TIP JAR", TY.Tip .. " coins, straight to " .. L.ownerName, "TIP", "coin", function()
				call("tip", i, "", function(res)
					if res and res.ok then UI.toast("you tipped " .. L.ownerName .. " " .. TY.Tip .. " coins", C.mintDark) Audio.play("Chime", 1.4, 0.6) end
				end)
			end, CITY + Places.tycoonSpot(def, "tips") }
		end
		if at("queue", TY.SpotRadius + 1) then
			return { name, "run by " .. L.ownerName .. "  \u{00B7}  " .. (L.open and "open" or "sold out right now"), "ORDER", "heart", function() T.openMenu(i) end, CITY + Places.tycoonSpot(def, "queue") }
		end
		if at("gate", TY.ClaimRadius) or at("sign") then
			return { name, L.ownerName .. "'s place  \u{00B7}  " .. stars(L.stars) .. "  \u{00B7}  order at the counter", nil, "heart", nil }
		end
		return nil
	end

	---------------------------------------------------------------------------
	-- EVERY FRAME
	---------------------------------------------------------------------------
	function T.step(dt, t, me)
		local now = os.clock()
		for _, L in T.lots do
			local d = (flat(me) - flat(L.def.pos)).Magnitude
			local near = d < 420
			if L.dirty and near then
				L.dirty = false
				build(L)
			end
			if L.model then
				if near ~= L.near then
					L.near = near
					L.model.Parent = near and folder or nil
				end
				if near and d < 160 then
					for _, a in L.actors do
						if a.pose == "sit" then
							Models.poseSminski(a.rig, a.cf, "sit", t + a.t0)
						else
							Models.poseSminski(a.rig, a.cf * CFrame.Angles(0, math.sin(t * 0.7 + a.t0) * 0.2, 0), "idle", t + a.t0)
							if a.hat then a.hat.CFrame = a.cf * CFrame.new(0, 3.3 + math.sin((t + a.t0) * 2) * 0.03, 0) end
						end
					end
				end
			end
		end
		-- my own place: keep the numbers fresh while I am there, run the queue
		local L = T.mine and T.lots[T.mine]
		local here = L and (flat(me) - flat(L.def.pos)).Magnitude < TY.Reach
		if here then
			if now - T.lastState > 8 and not (manage.shade and manage.shade.Visible) then T.refresh() end
			local cu = T.cust
			if cu then
				local a = math.clamp((now - cu.t0) / 2.2, 0, 1)
				if a < 1 then
					Models.poseSminski(cu.rig, cu.door:Lerp(cu.at, a) * CFrame.Angles(0, math.pi, 0), "run", now * 1.2, { stride = 14 })
				else
					cu.arrived = true
					Models.poseSminski(cu.rig, cu.at * CFrame.Angles(0, math.pi + math.sin(now * 0.8) * 0.1, 0), "idle", now)
					if now - cu.t0 > TY.CustomerWaits and not T.serving then
						clearCust(true)
						UI.toast("a customer gave up waiting", C.coral)
						T.nextCust = now + 6
					end
				end
			elseif L.open and L.pieces.counter and now > T.nextCust then
				spawnCust(L)
				T.nextCust = now + math.random(TY.CustomerEvery[1], TY.CustomerEvery[2])
			end
		elseif T.cust then
			clearCust(false)
		end
		if manage.shade and manage.shade.Visible and now - T.lastState > 3 then T.refresh() manage.refresh() end
	end

	function T.leave()
		clearCust(false)
		if manage.shade then manage.shade.Visible = false end
		if stockCard.shade then stockCard.shade.Visible = false end
		if menuCard.shade then menuCard.shade.Visible = false end
		if City.Kitchen and City.Kitchen.playing then City.Kitchen.clear() end
	end

	return T
end
