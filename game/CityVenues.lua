-- CityVenues (client): what you can do inside the city's rooms. CityBuild
-- builds them and lists them in Build.venues; this module makes them usable.
-- FOOD PLACES (cafes, bakeries, noodle bars, delis):
--   walk up to the counter  -> ORDER (pick something off the menu)
--   walk up to a free stool -> SIT   (stand up again by walking)
--   sitting with food       -> EAT   (a few bites, then it is gone)
-- SHOPS (everything else): each has one "spot" with something to do --
--   the clothes shop opens your real wardrobe, the toy shop the capsules,
--   electronics the upgrades; the rest are small moments (read, pet the
--   puppy, lift a weight, play the piano, sit in the barber's chair).
-- It is deliberately lightweight. There is no job here, no stock and no
-- money changing hands -- the point is that the doors open and the rooms
-- are somewhere to be, not another system to balance. If ordering should
-- cost coins one day, V.order() is the single place to charge for it.
--   deps: K, Build, Models, UI, Audio, Places, S (City's state), player, City

return function(deps)
	local K, Build, UI, Audio, Places, S = deps.K, deps.Build, deps.UI, deps.Audio, deps.Places, deps.S
	local player, City = deps.player, deps.City
	local V, rgb = K.V, K.rgb
	local part = deps.Models.part
	local CITY = Places.CITY
	local C = UI.C

	local Venues = { sitting = nil, food = nil }

	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end
	local function flat(v) return V(v.X, 0, v.Z) end

	-- what each thing on a menu looks like on the table: { colour, shape }
	local LOOK = {
		LATTE = { rgb(236, 214, 180), "cup" }, MATCHA = { rgb(150, 190, 120), "cup" }, TEA = { rgb(206, 170, 110), "cup" },
		SODA = { rgb(230, 110, 110), "cup" }, SOUP = { rgb(232, 150, 90), "bowl" }, RAMEN = { rgb(240, 214, 150), "bowl" },
		CROISSANT = { rgb(226, 170, 100), "bun" }, COOKIE = { rgb(196, 140, 90), "bun" }, DONUT = { rgb(244, 160, 190), "bun" },
		["MELON PAN"] = { rgb(214, 224, 140), "bun" }, ["CREAM PUFF"] = { rgb(250, 232, 190), "bun" }, TOAST = { rgb(232, 190, 120), "bun" },
		GYOZA = { rgb(244, 230, 200), "bun" }, ONIGIRI = { rgb(250, 250, 244), "bun" }, SANDWICH = { rgb(240, 214, 160), "bun" },
		PICKLES = { rgb(140, 180, 100), "bun" },
		-- THE 17 NEW MENUS' DRINKS AND BOWLS. Anything missing here falls back to
		-- CROISSANT -- a bun on a plate -- so without these a flat white, a boba
		-- and a bowl of udon would all be served as a pastry, and nothing would
		-- warn about it. Everything not listed falls to `bun`, which is right for
		-- the rest of the food.
		["FLAT WHITE"] = { rgb(226, 196, 160), "cup" }, ["HOT CHOCOLATE"] = { rgb(140, 92, 66), "cup" },
		["GREEN TEA"] = { rgb(160, 200, 130), "cup" }, ["FILTER COFFEE"] = { rgb(120, 78, 56), "cup" },
		MILKSHAKE = { rgb(250, 200, 214), "cup" }, ["MALTED MILK"] = { rgb(226, 196, 160), "cup" },
		["EGG CREAM"] = { rgb(244, 236, 214), "cup" }, ["MATCHA LATTE"] = { rgb(170, 200, 140), "cup" },
		["BROWN SUGAR BOBA"] = { rgb(160, 110, 74), "cup" }, ["TARO MILK TEA"] = { rgb(190, 170, 226), "cup" },
		["MANGO LASSI"] = { rgb(250, 200, 110), "cup" },
		["MISO SOUP"] = { rgb(200, 150, 90), "bowl" }, UDON = { rgb(244, 236, 214), "bowl" },
		["DAN DAN NOODLES"] = { rgb(220, 120, 80), "bowl" }, ["KATSU CURRY"] = { rgb(226, 160, 70), "bowl" },
		SUNDAE = { rgb(250, 214, 226), "bowl" }, ["PANCAKE STACK"] = { rgb(232, 190, 120), "bun" },
	}
	local function serve(name, cf)
		local look = LOOK[name] or LOOK.CROISSANT
		local m = Instance.new("Model")
		m.Name = "VenueFood"
		local plate = part(m, V(0.2, 2.6, 2.6), cf * CFrame.Angles(0, 0, math.pi / 2), rgb(250, 250, 246), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
		plate.CastShadow = false
		local bits = {}
		if look[2] == "cup" then
			table.insert(bits, part(m, V(1.5, 1.1, 1.1), cf * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(250, 250, 246), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder }))
			table.insert(bits, part(m, V(0.2, 0.9, 0.9), cf * CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.pi / 2), look[1], Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder }))
		elseif look[2] == "bowl" then
			table.insert(bits, part(m, V(2.2, 1.2, 2.2), cf * CFrame.new(0, 0.7, 0), rgb(226, 100, 90), Enum.Material.SmoothPlastic, { mesh = Enum.MeshType.Sphere }))
			table.insert(bits, part(m, V(0.2, 1.8, 1.8), cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2), look[1], Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder }))
		else
			table.insert(bits, part(m, V(1.7, 1.1, 1.4), cf * CFrame.new(0, 0.7, 0), look[1], Enum.Material.SmoothPlastic, { mesh = Enum.MeshType.Sphere }))
		end
		m.Parent = K.actors
		return { m = m, bits = bits, name = name, bites = 3 }
	end
	local function clearFood()
		if Venues.food then Venues.food.m:Destroy() Venues.food = nil end
	end

	-- the venue you are standing in (or at the counter of), if any
	local function nearest(me)
		local best, bd
		for _, v in Build.venues do
			local d = (flat(me) - flat(v.pos)).Magnitude
			-- THE REACH IS THE ROOM'S, NOT A CONSTANT. Rooms used to be 14 studs
			-- deep, so a flat 26 covered every one of them. They can now be set
			-- per block (Places.lua WALL[kind].d), and the moment a block goes
			-- past 52 deep, standing at the back wall puts you in no venue at all
			-- -- no prompt, no explanation. The fallback keeps the old number.
			if d < (v.radius or 26) and (not bd or d < bd) then best, bd = v, d end
		end
		return best
	end

	-- which room are you in? (also used by the Studio dev hooks)
	function Venues.here(me) return nearest(me) end

	-- ORDER: the one place an order happens (charge here if it ever costs)
	function Venues.order(v, item)
		clearFood()
		local at
		if Venues.sitting and Venues.sitting.venue == v then
			at = v.tables[Venues.sitting.seat.table]
		else
			-- not sitting yet: it waits for you on the counter
			at = v.counterTop
		end
		Venues.food = serve(item, at)
		Venues.food.venue = v
		Audio.play("Chime", 1.1, 0.7)
		if City.Sound then City.Sound.till(v.counter) end
		UI.toast(string.lower(item) .. " coming up!", C.mintDark)
	end

	function Venues.prompt(me)
		local hrp = myChar()
		if not hrp then return nil end
		-- sitting: eat if there is food in front of you
		if Venues.sitting then
			local f = Venues.food
			if f and f.venue == Venues.sitting.venue then
				return { string.upper(f.name), "tuck in", "EAT", "heart", function() Venues.eat() end, Venues.sitting.seat.cf.Position }
			end
			-- A CINEMA HAS NO COUNTER TO ORDER AT. The line was written when every
			-- venue was somewhere you ate, and telling someone in a film to go and
			-- order is the sort of thing that reads as the game not knowing where
			-- you are.
			local sv = Venues.sitting.venue
			return { string.upper(sv.name), sv.sitSub or "order at the counter, or just sit a while", nil, "heart", nil }
		end
		-- A SPOT YOU ARE STANDING ON WINS. nearest() picks the room whose
		-- centre is closest, which is right for 30-stud shops and wrong for
		-- the 150-stud supermarket: its outer shelves are nearer to the
		-- street-wall units on the kerb than to its own middle, so the wall
		-- unit "won" and the shelf had no prompt. Check every room in reach
		-- for a spot within arm's length first; only then fall back to the
		-- nearest centre for counters and seats.
		local v, spotV, spotSp, spotD = nil, nil, nil, 6
		for _, cand in Build.venues do
			if (flat(me) - flat(cand.pos)).Magnitude < (cand.radius or 26) + 6 then
				for _, sp in cand.spots do
					local dsp = (flat(me) - flat(sp.pos)).Magnitude
					if dsp < spotD then spotV, spotSp, spotD = cand, sp, dsp end
				end
			end
		end
		v = spotV or nearest(me)
		if not v then return nil end
		-- a shop's one thing to do
		for _, sp in v.spots do
			if (flat(me) - flat(sp.pos)).Magnitude < 6 then
				-- a sub can be a function, and a grocery spot's sub is live: the
				-- till says what your basket costs, a shelf what is in it already
				local sub = type(sp.sub) == "function" and sp.sub() or sp.sub
				local G = City.Grocery
				if G and sp.act then
					if sp.act.checkout then sub = G.tillLine()
					elseif sp.act.grocery then sub = G.shelfLine(sp.act.grocery) end
				end
				return { sp.title, sub, sp.btn, sp.icon, function() Venues.use(v, sp) end, CITY + sp.pos }
			end
		end
		if v.counter and (flat(me) - flat(v.counter)).Magnitude < 7 then
			return { v.name, table.concat(v.menu, " · "), "ORDER", "bag", function() if City.openMenu then City.openMenu(v) end end, CITY + v.counter }
		end
		for _, seat in v.seats do
			if (flat(me) - flat(seat.cf.Position - CITY)).Magnitude < 4.2 then
				return { v.name, "take a seat", "SIT", "heart", function()
					Venues.sitting = { venue = v, seat = seat }
					-- food ordered at the counter follows you to your table
					if Venues.food and Venues.food.venue == v then
						local name = Venues.food.name
						clearFood()
						Venues.food = serve(name, v.tables[seat.table])
						Venues.food.venue = v
					end
					Audio.play("Pop", 1, 0.6)
				end, seat.cf.Position }
			end
		end
		return nil
	end

	-- USE a shop's spot. Everything a spot can do is one of these few verbs,
	-- so a new kind of shop is a row in CityBuild's SHOPFIT table, not code.
	function Venues.use(v, sp)
		local act = sp.act
		-- groceries: a shelf puts a thing in your basket, the till takes the coins
		-- a door: step through it (ENTER / LEAVE on the prompt card, E)
		if act.warp then
			local hrp = myChar()
			if hrp then
				hrp.CFrame = CFrame.new(CITY + act.warp + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, act.face or 0, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
			Audio.play("Pop", 1, 0.6)
			return
		end
		if act.grocery and City.Grocery then City.Grocery.take(act.grocery, v) return end
		if act.checkout and City.Grocery then City.Grocery.checkout(v) return end
		if act.ui and UI.openShopTab then UI.openShopTab(act.ui) return end
		if act.sit and sp.seat then Venues.sitting = { venue = v, seat = { cf = sp.seat } } end
		if act.emote then Venues.emote = { pose = act.emote, untilT = os.clock() + (act.secs or 2.4) } end
		if act.sound then Audio.play(act.sound, 1.1, 0.7) else Audio.play("Pop", 1.1, 0.6) end
		if act.tune then
			-- a few notes on the shop piano
			task.spawn(function()
				for _, pitch in { 1, 1.12, 1.26, 1.5, 1.26, 1.5, 1.68 } do
					Audio.play("Chime", pitch, 0.7)
					task.wait(0.22)
				end
			end)
			Venues.emote = { pose = "cheer", untilT = os.clock() + 1.8 }
		end
		if act.lines then UI.toast(act.lines[math.random(1, #act.lines)], C.mintDark) end
	end

	function Venues.eat()
		local f = Venues.food
		if not f then return end
		f.bites -= 1
		Audio.play("Pop", 1.3 + (3 - f.bites) * 0.1, 0.6)
		for _, b in f.bits do b.Size = b.Size * 0.78 end
		if f.bites <= 0 then
			clearFood()
			UI.toast("yum! that hit the spot", C.mintDark)
			Audio.play("Chime", 1.3, 0.7)
		end
	end

	function Venues.update(dt, t, me)
		local hrp, hum = myChar()
		if Venues.sitting and hrp then
			if hum and hum.MoveDirection.Magnitude > 0.2 then
				Venues.sitting = nil
			else
				hrp.CFrame = Venues.sitting.seat.cf * CFrame.new(0, 2.9, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
				S.poses[player] = "sit"
			end
		end
		-- mid-emote (petting the puppy, lifting, playing)
		if Venues.emote then
			if os.clock() < Venues.emote.untilT and not (hum and hum.MoveDirection.Magnitude > 0.2) then
				S.poses[player] = Venues.emote.pose
			else
				Venues.emote = nil
			end
		end
		-- walk out without it and the plate is cleared away
		if Venues.food and (flat(me) - flat(Venues.food.venue.pos)).Magnitude > 40 then clearFood() end
		-- room lights only burn near you: a hundred rooms, a handful lit
		Venues.lightT = (Venues.lightT or 0) + dt
		if Venues.lightT > 0.5 then
			Venues.lightT = 0
			for _, v in Build.venues do
				if v.light then v.light.Enabled = (flat(me) - flat(v.pos)).Magnitude < 150 end
			end
		end
	end

	function Venues.leave()
		Venues.sitting = nil
		Venues.emote = nil
		clearFood()
	end

	return Venues
end
