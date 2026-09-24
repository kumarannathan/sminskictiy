-- CityEvents (client): the short loops. See docs/LOOPS.md and Config.Events.
--
-- The server's director decides what happens, where and when; this module
-- only draws it, routes you to it and asks the server to pay you. It holds no
-- authority: a claim is a request, and the server checks where you really are.
--
-- WHAT THE CLIENT KNOWS, AND WHEN. A hidden event arrives as clues only. The
-- exact spot comes in a separate "reveal" once you are already close enough
-- to see it -- so there is nothing in this module's state worth reading from
-- across town. An `open` event (a truck you race to) carries its spot from
-- the start, because the whole point is that everyone knows.
--
-- ONE ARCHETYPE SO FAR: `find`. The drawing is per event id (a Sminski in a
-- costume, a pup, a truck) but everything else -- the clock, the clues, the
-- prompt, the claim, the phone row -- is shared, and is what COLLECT and the
-- rest will reuse.
--   deps: K, UI, Audio, Places, Config, Models, Build, City, S, H, player,
--         remoteNamed, earned, modalCard
return function(deps)
	local K, UI, Audio, Places, Config, Models = deps.K, deps.UI, deps.Audio, deps.Places, deps.Config, deps.Models
	local Build, City, S, H, player = deps.Build, deps.City, deps.S, deps.H, deps.player
	local remoteNamed, earned, modalCard = deps.remoteNamed, deps.earned, deps.modalCard
	local V, rgb = K.V, K.rgb
	local C = UI.C
	local CITY = Places.CITY
	local EV = Config.Events

	-- syncFails: only the phone's "can't reach the city right now." line depends
	-- on it. Cleared by the first good `state` reply, so the phone heals itself
	-- on the existing tick without the player doing anything.
	local E = { list = {}, spotted = {}, news = {}, synced = false, compact = false, syncFails = 0 }

	---------------------------------------------------------------------------
	-- EVERY MUTABLE HANDLE LIVES AT THE TOP. A `local function` (and a local
	-- anything) is invisible to code written above it, and this module now has
	-- one path that runs top-down (the strip, built in E.init) and another that
	-- runs on a remote callback (the finish moment, written above E.init but
	-- needing its widgets). Declaring them here is what makes both legal.
	---------------------------------------------------------------------------
	local strip, sIcon, sTitle, sSub, sClock
	local tray, trayTap, trayCity, trayMine, trayTrack, trayFill
	local trayScale, cityScale, mineScale
	local bigHolder, bigText, bigStroke, bigScale
	local liveEv                -- the event the strip is currently showing
	local drawBudget = 0        -- item models allowed to be built this frame
	-- FORWARD DECLARED, same reason. Both belong with the strip far below, but
	-- takeStrip() (in the finish block, above them) has to draw the strip's sub
	-- line the way the 0.25s tick draws it and has to compare its claim the way
	-- headline() compares -- and it cannot see either if they are only declared
	-- where they are defined. Defining the same rule twice is how the two sites
	-- drift apart, which is exactly the bug this shape prevents.
	local latestClue, rank
	-- PHASE D (docs/specs/daily-capsule): the capsule pill and the Daily 3.
	-- Same discipline -- every mutable flag and every widget handle up here.
	--
	-- showBigLine lives with the finish moment below -- it IS phase B's big-line
	-- animation, extracted so the Daily 3's third find can borrow the same object
	-- without phase B's 250-stud audience test. Declared here so that the
	-- `function showBigLine(...)` below assigns THIS local instead of quietly
	-- creating a global, the same reason latestClue and rank are up here.
	local showBigLine
	-- the pill's whole state. `push*` is the CityEvent("ticket") payload, which
	-- is authoritative over ctx.data until the next `data` arrives, because a
	-- ticket can be granted on a deferred or server-initiated payout whose
	-- reply this client never sees.
	local cap = { latched = false, notches = 0, lastPulse = 0 }
	local capFillTween
	-- the last hunt block the server sent, merged in place; nil means "no hunt
	-- block yet", which hides the phone section rather than printing a zero
	local hunt = nil
	local huntDraw = {}          -- [1..3] = { at, root, rig } -- WORLD objects
	local huntSocial, huntWarm = {}, {}   -- the two halves of "a clue got warmer"
	local huntBusy, huntWarnedDay = false, nil
	local hSec, hCount, hRows, hReset, hSocial, hStreak

	local function now() return workspace:GetServerTimeNow() end
	local function flat(v) return V(v.X, 0, v.Z) end
	local function clock(sec)
		sec = math.max(0, math.floor(sec))
		return string.format("%d:%02d", sec // 60, sec % 60)
	end
	-- a 20-character display name overflows the phone's count line
	local function clampName(n)
		n = n or "someone"
		if #n > 10 then n = string.sub(n, 1, 10) .. "\u{2026}" end
		return n
	end
	local function singular(noun)
		noun = noun or "bags"
		return string.sub(noun, -1) == "s" and string.sub(noun, 1, #noun - 1) or noun
	end
	-- "CASH DROP!" -> "CASH DROP", so the receipt reads "CASH DROP OVER"
	local function plainTitle(def)
		local t = string.gsub(def.title or "", "!$", "")
		return t
	end
	local function notify(icon, title, sub, color)
		table.insert(E.news, 1, { t = now(), title = title, sub = sub or "" })
		while #E.news > 6 do table.remove(E.news) end
		if City.Jobs and City.Jobs.notify then City.Jobs.notify(icon, title, sub, color) end
	end
	local function groundY(p)
		return (Build.isRoad and (Build.isRoad(p.X) or Build.isRoad(p.Z))) and 0 or K.PAD_Y
	end

	---------------------------------------------------------------------------
	-- THE PICKUP RUN. A COLLECT event pays you forty times, so the sound it
	-- makes has to survive being heard forty times: a rising pentatonic run of
	-- Ticks that resets when you stop picking things up. Same shape as
	-- Audio.coin (Audio.lua:198) but kept LOCAL, because Audio.coin's 0.7s
	-- reset gap was tuned for the runner's dense coin lane -- city items are
	-- >= 8 studs apart and 0.7s would reset the run on almost every pickup.
	---------------------------------------------------------------------------
	local PICKUP_SCALE = { 1, 1.122, 1.26, 1.498, 1.682, 2, 2.245, 2.52 }
	local PICKUP_RESET_GAP = 2.5
	local pickupStep, lastPickup = 0, 0
	local function playPickup(gold)
		local tc = os.clock()
		if tc - lastPickup > PICKUP_RESET_GAP then pickupStep = 0 end
		lastPickup = tc
		pickupStep = pickupStep % #PICKUP_SCALE + 1
		Audio.play("Tick", 1.5 * PICKUP_SCALE[pickupStep], gold and 1.4 or 1)
		if gold then Audio.play("Chime", 1.4, 0.6) end
	end

	---------------------------------------------------------------------------
	-- DRAWING. One builder per event id; each returns { model, step, done }.
	-- Nothing here has collision or a light of its own (performance.md): the
	-- sparkle is one emitter, and the glow is the sky's.
	---------------------------------------------------------------------------
	local function sparkle(parent, color)
		local a = Instance.new("Attachment")
		a.Parent = parent
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(color)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Rate = 9
		pe.Speed = NumberRange.new(1.5, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.LightEmission = 0.6
		pe.Parent = a
		return pe
	end

	local DRAW = {}
	function DRAW.sighting(ev, at, face)
		local skin = ev.skinId and Config.Skin(ev.skinId) or nil
		local chars = Config.Characters
		local def = chars[(ev.uid * 7) % math.min(#chars, 10) + 1]
		local rig = Models.buildSminski(K.actors, 1, def, false, nil, skin)
		local root = CFrame.new(CITY + V(at.X, groundY(at), at.Z)) * CFrame.Angles(0, face, 0)
		local pe = sparkle(rig.body, rgb(255, 236, 150))
		return {
			anchor = rig.body,
			step = function(t, me)
				local d = (flat(me) - at).Magnitude
				local look = flat(me) - at
				local turned = d < 40 and CFrame.new(root.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0) or root
				Models.poseSminski(rig, turned, ev.mine and "cheer" or d < 26 and "surprised" or "peek", t)
			end,
			done = function()
				pe.Enabled = false
				rig.model:Destroy()
			end,
		}
	end
	function DRAW.lostpup(ev, at, face)
		local dog = Models.buildDog(K.actors, { scale = 0.18, name = "LostPup",
			fur = rgb(245, 245, 240), light = rgb(255, 255, 255), dark = rgb(200, 170, 140) })
		local root = CFrame.new(CITY + V(at.X, groundY(at) + E.PUP_Y, at.Z)) * CFrame.Angles(0, face, 0)
		local pe = sparkle(dog.head or dog.model:FindFirstChildWhichIsA("BasePart"), rgb(255, 214, 160))
		return {
			anchor = dog.head,
			step = function(t, me)
				local d = (flat(me) - at).Magnitude
				-- it wags harder the closer you get, which is also the tell
				-- that you are looking at the right dog
				Models.poseDog(dog, root, t, 0, ev.mine and 1 or 0, { phase = t * (d < 30 and 10 or 3) })
			end,
			done = function()
				pe.Enabled = false
				dog.model:Destroy()
			end,
		}
	end
	function DRAW.icecream(ev, at, face)
		local m = K.buildCar("icecream", K.CAR_COLORS[(ev.uid % 8) + 1], K.actors)
		m:PivotTo(CFrame.new(CITY + V(at.X, groundY(at), at.Z)) * CFrame.Angles(0, face, 0))
		local body = m:FindFirstChildWhichIsA("BasePart")
		local pe = body and sparkle(body, rgb(255, 190, 214))
		return {
			anchor = body,
			step = function() end,
			done = function()
				if pe then pe.Enabled = false end
				m:Destroy()
			end,
		}
	end
	-- MEASURED, NOT GUESSED. The hub seats its pup at y = 1.9, so this started
	-- as 1.9 -- and the pup hovered 1.83 studs over the pavement. The dog
	-- rig's root is already at paw level; the hub's 1.9 is its floor height.
	E.PUP_Y = 0.07

	---------------------------------------------------------------------------
	-- COLLECT: THE ITEMS. Three approved recipes, reused as they are -- the fun
	-- park's balloon (CityBuild ~2009), the runner's star coin (World ~1222)
	-- and the sweeping job's litter (City.litterModel).
	--
	-- POOLED, AND NOT ONE GUI OR LIGHT BETWEEN THEM. A Balloon Festival is up
	-- to 48 items; building and destroying 48 models per event, twice a minute,
	-- is the kind of churn `performance.md` exists to stop. A collected item is
	-- parked in `stash`, which has NO PARENT and so is not in the world at all,
	-- and the next event hands the same parts back out.
	---------------------------------------------------------------------------
	local stash = Instance.new("Folder")
	stash.Name = "SminskiCityEventPool"
	local pool = {}
	local COIN_COLOR = rgb(255, 200, 60)
	local ITEM_KIND = { cashdrop = "coin", balloons = "balloon", cleanup = "litter" }

	local function buildBalloon(seed)
		local m = Instance.new("Model")
		m.Name = "EventBalloon"
		local b = Models.part(m, V(2.4, 2.4, 2.4), CFrame.new(),
			K.CAR_COLORS[seed % #K.CAR_COLORS + 1], K.SMOOTH, { shape = Enum.PartType.Ball })
		b.Reflectance = 0.15
		local s = Models.part(m, V(0.1, 6, 0.1), CFrame.new(), K.C.ink, K.MATTE, { noShadow = true })
		-- ball bottom (7.2 - 1.2) sits exactly on the string's top (0 + 6)
		return { m = m, body = b, str = s, pool = "balloon", bodyY = 7.2, bob = true }
	end
	local function buildCoin()
		local m = Instance.new("Model")
		m.Name = "EventCashBag"
		local p
		if Models.hasMeshes("StarCoin") then
			p = Models.rigMesh(m, "StarCoin", 1, COIN_COLOR, Enum.Material.SmoothPlastic)
			p.Size = Models.coinSize(3)
			p.Reflectance = 0.22
			p.CastShadow = false
		else
			-- the runner's own fallback, minus its two SurfaceGuis: 24 bags must
			-- not mean 24 GUIs
			p = Models.part(m, V(0.5, 3, 3), CFrame.new(), COIN_COLOR, K.METAL,
				{ shape = Enum.PartType.Cylinder, noShadow = true })
		end
		return { m = m, body = p, pool = "coin", bodyY = 2.4, spin = true }
	end
	local function buildLitter(variant)
		if City.litterModel then
			local m, sp = City.litterModel(CFrame.new(), variant)
			m.Name = "EventLitter"
			return { m = m, body = sp, pool = "litter" .. variant }
		end
		-- City.litterModel is in City.lua and always there; this is only so a
		-- missing helper degrades to a visible item rather than an empty street
		local m = Instance.new("Model")
		m.Name = "EventLitter"
		local p = Models.part(m, V(1.6, 1.4, 1.6), CFrame.new(), rgb(246, 244, 236), K.MATTE,
			{ mesh = Enum.MeshType.Sphere })
		m.WorldPivot = CFrame.new()
		return { m = m, body = p, pool = "litter" .. variant }
	end

	local function acquire(key, make)
		local list = pool[key]
		local d = list and table.remove(list)
		if d then return d end
		return make()
	end
	local function release(d)
		if not d then return end
		-- the city tears K.actors out from under us on the way home; a model
		-- that has already been destroyed cannot be reparented
		local ok = pcall(function() d.m.Parent = stash end)
		if not ok then return end
		pool[d.pool] = pool[d.pool] or {}
		table.insert(pool[d.pool], d)
	end

	local function drawItem(ev, it)
		local kind = ITEM_KIND[ev.id] or "coin"
		local d
		if kind == "balloon" then
			d = acquire("balloon", function() return buildBalloon(it.id) end)
			d.body.Color = K.CAR_COLORS[it.id % #K.CAR_COLORS + 1]
			d.body.CFrame = it.cf * CFrame.new(0, d.bodyY, 0)
			d.str.CFrame = it.cf * CFrame.new(0, 3, 0)
		elseif kind == "litter" then
			local variant = it.id % 3
			d = acquire("litter" .. variant, function() return buildLitter(variant) end)
			d.m:PivotTo(it.cf * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, it.id * 1.3, 0))
		else
			d = acquire("coin", buildCoin)
			d.body.CFrame = it.cf * CFrame.new(0, d.bodyY, 0)
		end
		d.m.Parent = K.actors
		it.draw = d
	end
	-- one CFrame write per item per frame, and only for the ones you can see
	local function animItem(it, t)
		local d = it.draw
		if not d then return end
		if d.spin then
			d.body.CFrame = it.cf * CFrame.new(0, d.bodyY, 0) * CFrame.Angles(0, t * 2.2 + it.phase, 0)
		elseif d.bob then
			d.body.CFrame = it.cf * CFrame.new(0, d.bodyY + math.sin(t * 1.6 + it.phase) * 0.3, 0)
		end
	end

	local function addItem(ev, rec)
		local id = rec and rec.id
		if not id then return end
		ev.items = ev.items or {}
		if ev.items[id] then return end
		local at = V(rec.x or 0, 0, rec.z or 0)
		ev.items[id] = { id = id, at = at, phase = (id % 7) * 0.9,
			cf = CFrame.new(CITY + V(at.X, groundY(at), at.Z)) }
	end
	local function removeItem(ev, id)
		local it = ev.items and ev.items[id]
		if not it then return end
		release(it.draw)
		it.draw = nil
		ev.items[id] = nil
	end
	local function releaseItems(ev)
		for id in ev.items or {} do removeItem(ev, id) end
		ev.items = nil
	end
	-- the server's item list is authoritative: anything not in it is gone
	local function syncItems(ev, list)
		local seen = {}
		for _, rec in list do
			if rec and rec.id then
				seen[rec.id] = true
				addItem(ev, rec)
			end
		end
		for id in ev.items or {} do
			if not seen[id] then removeItem(ev, id) end
		end
	end

	local function undraw(ev)
		if ev.drawn then
			ev.drawn.done()
			ev.drawn = nil
		end
		releaseItems(ev)
		if ev.mark then ev.mark:Destroy() ev.mark = nil end
	end
	-- an open event gets a beacon you can see over the rooftops; a hidden one
	-- never does -- finding it is the game
	local function mark(ev, at)
		local m = Instance.new("Model")
		m.Name = "EventBeacon"
		local base = CFrame.new(CITY + V(at.X, K.PAD_Y, at.Z))
		local col = rgb(255, 170, 204)
		Models.part(m, V(160, 6, 6), base * CFrame.new(0, 80, 0) * CFrame.Angles(0, 0, math.pi / 2), col, Enum.Material.Neon,
			{ shape = Enum.PartType.Cylinder, transparency = 0.72 })
		m.Parent = K.actors
		ev.mark = m
	end
	local function draw(ev)
		if ev.drawn or not ev.spot then return end
		local fn = DRAW[ev.id]
		if not fn then return end
		local at = V(ev.spot[1], 0, ev.spot[2])
		ev.at = at
		ev.drawn = fn(ev, at, ev.spot[3] or 0)
		if ev.def.open then mark(ev, at) end
	end

	---------------------------------------------------------------------------
	-- COLLECT: THE PROGRESS TRAY.
	--
	-- The first number in this game that belongs to the server rather than to
	-- you, so it gets its own word: CITY on the left, YOU on the right. They
	-- are separated on four axes -- side, size, colour and a label each -- so
	-- the two can never be read as one another.
	--
	-- Which way the bar moves says which kind of event it is: cooperative
	-- GROWS (got/goal), competitive DRAINS (left/count). Nothing here scales
	-- with the item count; the tray is the same twelve instances whether there
	-- are 12 balloons or 48.
	---------------------------------------------------------------------------
	local function isComp(ev) return ev.def.shared == false end
	-- THE DENOMINATOR IS NOT def.count. The server places what fits and clamps
	-- the count to that, so a crowded zone can ship fewer than 24 bags; left +
	-- got is exactly the number actually placed.
	local function compTotal(ev)
		if type(ev.left) == "number" and type(ev.got) == "number" then
			return math.max(ev.left + ev.got, 1)
		end
		return math.max(ev.def.count or 0, 1)
	end
	-- Missing progress fields must hide the tray, never render "CITY nil of nil"
	local function trayOK(ev)
		if not ev or ev.def.kind ~= "collect" then return false end
		if now() < (ev.startT or 0) then return false end
		if isComp(ev) then
			return type(ev.left) == "number" and type(ev.got) == "number"
		end
		return type(ev.got) == "number" and type(ev.goal) == "number" and ev.goal > 0
	end
	local function cityFrac(ev)
		if isComp(ev) then return 0 end
		local g = ev.goal or 0
		if g <= 0 then return 0 end
		return math.clamp((ev.got or 0) / g, 0, 1)
	end

	local function cityString(ev)
		local def = ev.def
		if isComp(ev) then
			local total = compTotal(ev)
			local left = math.clamp(ev.left or 0, 0, total)
			local noun = def.noun or "bags"
			if left <= 0 then return "ALL GONE", C.coral end
			local txt = left .. " " .. string.upper(left == 1 and singular(noun) or noun) .. " LEFT"
			return txt, (left / total <= 0.25) and C.coral or C.ink
		end
		local got, goal = ev.got or 0, ev.goal or 0
		local txt = E.compact and (got .. "/" .. goal) or ("CITY " .. got .. " of " .. goal)
		return txt, ev.finished == "time" and C.inkSoft or C.ink
	end
	-- Past the bonus threshold your slot DROPS ITS DENOMINATOR, so at the
	-- moment you are most likely to stare at the tray the two numbers do not
	-- even share a shape.
	local function mineString(ev)
		local def = ev.def
		local mine = ev.myCount or 0
		local fin = ev.finished ~= nil and (os.clock() - (ev.finishedAt or 0)) >= 0.25
		if isComp(ev) then
			local noun = def.noun or "bags"
			local unit = string.upper(mine == 1 and singular(noun) or noun)
			local top = ev.top ~= nil and ev.top.name == player.DisplayName
			if fin then
				if top and mine > 0 then return "YOU " .. mine .. " \u{00B7} TOP", C.gold end
				if mine >= 1 then return "YOU " .. mine .. " " .. unit, C.gold end
				return "NONE THIS TIME", C.inkSoft
			end
			if mine <= 0 then return "YOU 0 " .. string.upper(noun), C.inkSoft end
			if top then return "YOU " .. mine .. " \u{00B7} LEADING", C.gold end
			return "YOU " .. mine .. " " .. unit, C.gold
		end
		local at = def.bonusAt
		if fin then
			-- PAID is only honest when the goal was actually reached; a timeout
			-- pays the per-item coins and nothing else, and says so
			local paid = ev.finished == "goal"
			if not at then return mine > 0 and ("YOU " .. mine) or "NEXT TIME!", mine > 0 and C.gold or C.inkSoft end
			if mine >= at and paid then return "YOU " .. mine .. " \u{00B7} PAID", C.mintDark end
			if mine >= 1 then return "YOU " .. mine .. " \u{00B7} NO BONUS", C.inkSoft end
			return "NEXT TIME!", C.inkSoft
		end
		if not at then
			if mine <= 0 then return "YOU 0", C.inkSoft end
			return "YOU " .. mine, C.gold
		end
		if mine >= at then return "YOU " .. mine .. " \u{00B7} BONUS", C.mintDark end
		if mine >= 1 then
			return E.compact and ("YOU " .. mine .. "/" .. at) or ("YOU " .. mine .. " of " .. at), C.gold
		end
		-- a late arrival is only told to hurry while getting three is honest
		if cityFrac(ev) >= 0.80 then return "GRAB " .. at .. ", QUICK!", C.coral end
		return E.compact and ("YOU 0/" .. at) or ("YOU 0 of " .. at), C.inkSoft
	end
	-- 1 of 40 is 7.7px and a 5px corner radius eats it, so one item is always
	-- worth at least 0.035 of the bar
	local function fillFor(ev)
		if isComp(ev) then
			local total = compTotal(ev)
			local left = math.clamp(ev.left or 0, 0, total)
			local p = left > 0 and math.max(0.035, left / total) or 0
			return p, (left / total <= 0.25) and C.coral or C.gold
		end
		local goal = math.max(ev.goal or 0, 1)
		local got = math.clamp(ev.got or 0, 0, goal)
		local p = got > 0 and math.max(0.035, got / goal) or 0
		return p, (got / goal >= 0.85) and C.gold or C.mint
	end

	-- pickups can land faster than the 0.25s fill tween finishes; two live tweens
	-- on one Size property fight each other every frame, so the old one goes.
	-- The last-applied fraction is tracked WITH THE EVENT IT BELONGS TO, because
	-- one bar serves whichever event is the headline: if the headline changes,
	-- the bar must snap to the new event's value rather than compare against a
	-- fraction the other event set.
	local fillTween, fillEv, fillAt
	local function renderTray(ev, tweenT)
		if not tray then return end
		-- only the headline's tray is ever drawn; a second event lives on the
		-- phone with its own numbers
		if ev and liveEv and ev ~= liveEv then return end
		if not trayOK(ev) then tray.Visible = false return end
		tray.Visible = true
		local tc = os.clock()
		local ct, cc = cityString(ev)
		if ev.cityHold and tc < ev.cityHold then ct, cc = ev.cityHoldText, ev.cityHoldColor end
		trayCity.Text = ct
		trayCity.TextColor3 = (ev.skyHold and tc < ev.skyHold) and C.sky or cc
		local mt, mc = mineString(ev)
		if ev.mineHold and tc < ev.mineHold then mt, mc = ev.mineHoldText, ev.mineHoldColor end
		trayMine.Text = mt
		trayMine.TextColor3 = mc
		local p, fc = fillFor(ev)
		trayFill.BackgroundColor3 = fc
		if ev.trayFresh or fillEv ~= ev then
			-- a mid-event arrival must not watch the bar sweep for two seconds
			ev.trayFresh = nil
			fillEv, fillAt = ev, p
			if fillTween then fillTween:Cancel() fillTween = nil end
			trayFill.Size = UDim2.fromScale(p, 1)
		elseif math.abs(p - fillAt) > 0.001 then
			fillAt = p
			if fillTween then fillTween:Cancel() end
			fillTween = UI.tween(trayFill, tweenT or 0.25, { Size = UDim2.fromScale(p, 1) })
		end
	end
	-- the strip's clock, with COLLECT's two finish words. FIND falls through to
	-- exactly what it did before.
	local function renderClock(ev, tn)
		if not sClock then return end
		if ev.finished == "goal" then sClock.Text = "DONE" sClock.TextColor3 = C.mintDark return end
		if ev.finished == "empty" then sClock.Text = "GONE" sClock.TextColor3 = C.gold return end
		local soon = tn < ev.startT
		sClock.Text = clock(soon and (ev.startT - tn) or (ev.endT - tn))
		sClock.TextColor3 = soon and C.inkSoft or C.coral
	end

	local function pulse(sc, peak, upT, downT)
		if not sc then return end
		sc.Scale = 1
		UI.tween(sc, upT, { Scale = peak })
		task.delay(upT, function()
			if sc.Parent then UI.tween(sc, downT, { Scale = 1 }, Enum.EasingStyle.Back) end
		end)
	end
	local function holdCity(ev, txt, col, secs)
		ev.cityHoldText, ev.cityHoldColor, ev.cityHold = txt, col, os.clock() + secs
		renderTray(ev)
		task.delay(secs + 0.03, function()
			if E.list[ev.uid] == ev then renderTray(ev) end
		end)
	end
	local function holdMine(ev, txt, col, secs)
		ev.mineHoldText, ev.mineHoldColor, ev.mineHold = txt, col, os.clock() + secs
		renderTray(ev)
		task.delay(secs + 0.03, function()
			if E.list[ev.uid] == ev then renderTray(ev) end
		end)
	end
	-- C.sky is used nowhere else in the tray, so "that was not me" is a colour
	-- you learn in one event
	local function skyFlash(ev)
		ev.skyHold = os.clock() + 0.30
		renderTray(ev)
		task.delay(0.33, function()
			if E.list[ev.uid] == ev then renderTray(ev) end
		end)
	end

	---------------------------------------------------------------------------
	-- THE CAPSULE PILL (phase D). docs/specs/daily-capsule/ux.md 2-5.
	--
	-- THE OBJECT IS PERMANENT AND SILENT; THE MOTION IS RARE AND CAUSED. The
	-- pill is always on screen in the city, in the money row beside the coins,
	-- and it does not creep, shimmer, countdown or pulse while nothing is
	-- happening. Every motion in here is caused by a credit, a ticket or a tap.
	--
	-- The instances are built in City.lua (H.capsule) because the meter is
	-- published inside the ordinary save and ctx is City's; everything they DO
	-- is here, with the `ticket` push and the Daily 3 that also feed them.
	--
	-- TWO TICKET SOURCES, TWO ANIMATIONS, ONE PILL. A meter ticket runs the
	-- fill to full and wipes it (capMeterMoment); a hunt or streak ticket only
	-- pips the count (capPipTo). Animating the meter for a ticket that did not
	-- come from the meter would be a lie.
	---------------------------------------------------------------------------
	-- THE BANKED-CAP COLOUR IS 3, AND IT IS NOT Config.Meter.MaxTickets.
	-- MaxTickets (4) caps what the METER may grant; the hunt's third-find ticket
	-- is granted unconditionally -- at the day cap and past the banked cap, since
	-- a once-a-day reward that silently does not arrive is worse than the cap it
	-- protects -- and the seventh-day streak grants another. So the count can
	-- honestly read 5, or 6 on a streak day, and the server deliberately does not
	-- clamp it. NOTHING HERE MAY CLAMP IT EITHER: the label is tostring(tickets),
	-- one glyph at FredokaOne 22 in a 30px box at any of those values, and coral
	-- from 3 upwards (ux.md 7 and the QA numbers key the colour on THREE banked).
	local CAP_CORAL = 3
	local CAP_MIN_FILL = 0.09   -- 6px of a 66px track = twice the corner radius
	local CAP_PULSE_MIN = 19    -- 1% of the bar; below it a credit does not pulse
	local CAP_PULSE_GAP = 0.60  -- at most one credit pulse per 0.6s
	local CAP_NOTCH = { 0.25, 0.50, 0.75 }
	-- Config.Meter belongs to the server lane and may not be there yet; a
	-- missing table must degrade to the published numbers, never throw.
	local function ticketUnits()
		local m = Config.Meter
		local n = m and tonumber(m.Ticket)
		return (n and n > 0) and n or 1870
	end
	local function dayCapN()
		local m = Config.Meter
		return (m and tonumber(m.DayCap)) or 12
	end
	local function capSrc()
		return (H and H.cityData) and H.cityData() or nil
	end
	-- THE NUMBERS THE PILL DRAWS, AND WHERE THEY COME FROM. `nil` for either of
	-- the first two means "I cannot vouch for this" -- the pill hides rather
	-- than printing a zero it invented.
	local function capNums()
		local src = capSrc()
		if cap.pushOn and src ~= cap.pushRef then
			-- a fresh save has landed, so the push is no longer the newest truth
			cap.pushOn, cap.pushRef, cap.pushMeter, cap.pushTickets = false, nil, nil, nil
		end
		local meter = (cap.pushOn and cap.pushMeter) or (src and tonumber(src.meter)) or nil
		local tickets = (cap.pushOn and cap.pushTickets) or (src and tonumber(src.tickets)) or nil
		local dayT = (src and tonumber(src.meterDayTickets)) or 0
		return meter, tickets, dayT
	end
	local function capAdopt(tickets, meter)
		if tickets == nil and meter == nil then return end
		if tickets ~= nil then cap.pushTickets = tickets end
		if meter ~= nil then cap.pushMeter = meter end
		cap.pushOn = true
		cap.pushRef = capSrc()
	end
	local function capCountColor(n)
		if n >= CAP_CORAL then return C.coral end
		return n >= 1 and C.gold or C.inkSoft
	end
	local function capNotches(meter, maxU)
		local f = meter / maxU
		local n = 0
		for _, th in CAP_NOTCH do if f >= th then n += 1 end end
		return n
	end
	-- one writer on the fill's Size, and it never tweens backwards
	local function capSetFill(f, tweenT)
		local p = H.capsule
		if not p or not p.fill then return end
		if cap.fillAt ~= nil and math.abs(f - cap.fillAt) < 0.001 then return end
		cap.fillAt = f
		if capFillTween then capFillTween:Cancel() capFillTween = nil end
		if tweenT and not City.hudOff then
			capFillTween = UI.tween(p.fill, tweenT, { Size = UDim2.fromScale(f, 1) })
		else
			p.fill.Size = UDim2.fromScale(f, 1)
		end
	end
	local function renderCap()
		local p = H.capsule
		if not p or not p.holder then return end
		local meter, tickets, dayT = capNums()
		if meter == nil or tickets == nil then
			-- before the first reply, or an old server. Once latched, Visible is
			-- NEVER written again (City.hudVisible owns it from then on), so a
			-- field going missing later must not flicker the pill off.
			if not cap.latched then p.holder.Visible = false end
			return
		end
		if not cap.latched then
			cap.latched = true
			p.holder.Visible = true
		end
		local maxU = ticketUnits()
		if cap.momentUntil and os.clock() < cap.momentUntil then
			-- the ticket moment owns the bar and the count for ~0.3s; two
			-- writers on one Size property fight each other every frame
			cap.shownMeter, cap.shownTickets = meter, tickets
			cap.notches = capNotches(meter, maxU)
			return
		end
		local f, col
		if tickets >= CAP_CORAL then
			-- the one state where the player is losing something they can act on
			f, col = 0.999, C.coral
		elseif dayT >= dayCapN() then
			f, col = 0.999, C.inkSoft
		else
			f = meter > 0 and math.max(CAP_MIN_FILL, math.min(1, meter / maxU)) or 0
			col = (f >= 0.80) and C.gold or C.mint
		end
		-- the third find's pip owns the count until it fires (ux.md 8: the
		-- increment belongs at +0.60s, with the pulse, not to whichever save
		-- reply happens to land first)
		if not (cap.countHold and os.clock() < cap.countHold) then
			local txt = tostring(tickets)
			if p.count.Text ~= txt then p.count.Text = txt end
			local tc = capCountColor(tickets)
			if p.count.TextColor3 ~= tc then p.count.TextColor3 = tc end
		end
		if p.fill.BackgroundColor3 ~= col then p.fill.BackgroundColor3 = col end
		local prev = cap.shownMeter
		cap.shownMeter, cap.shownTickets = meter, tickets
		if prev ~= nil and meter > prev and not City.hudOff then
			capSetFill(f, 0.25)
			local n = capNotches(meter, maxU)
			if n > cap.notches then
				cap.notches = n
				pulse(p.scale, 1.10, 0.12, 0.18)
				cap.lastPulse = os.clock()
			elseif (meter - prev) >= CAP_PULSE_MIN and (os.clock() - cap.lastPulse) >= CAP_PULSE_GAP then
				-- coalesced: six pulses a minute in the corner of the eye stops
				-- being a signal and becomes a tic
				pulse(p.scale, 1.06, 0.10, 0.16)
				cap.lastPulse = os.clock()
			end
		else
			-- a fresh pill, a ticket that already reset the bar, or a hidden HUD:
			-- the end state goes straight in, with no tween and no pulse
			capSetFill(f)
			cap.notches = capNotches(meter, maxU)
		end
	end
	-- THE MOMENT A METER TICKET COMPLETES (ux.md 4). ~1.0s, entirely inside a
	-- 120x48 rectangle: no banner, no modal, no coin pop -- a ticket is not
	-- coins and must not be drawn as coins.
	local function capMeterMoment(tickets)
		local p = H.capsule
		if not p or not p.holder then return end
		if City.hudOff then
			-- skip all of it; the pill renders from the numbers, so when the HUD
			-- comes back it is simply correct, with no stale animation
			cap.momentUntil = nil
			renderCap()
			return
		end
		cap.momentUntil = os.clock() + 0.34
		if capFillTween then capFillTween:Cancel() capFillTween = nil end
		cap.fillAt = 1
		p.fill.BackgroundColor3 = C.gold
		capFillTween = UI.tween(p.fill, 0.18, { Size = UDim2.fromScale(1, 1) })
		task.delay(0.30, function()
			if not p.holder.Parent then return end
			-- SET, NEVER TWEENED, back down: a bar running backwards reads as
			-- losing progress. cap.fillAt = nil forces the write through.
			cap.momentUntil = nil
			cap.fillAt = nil
			if capFillTween then capFillTween:Cancel() capFillTween = nil end
			if tickets then
				p.count.Text = tostring(tickets)
				p.count.TextColor3 = C.gold
			end
			renderCap()
			if City.hudOff then return end
			pulse(p.scale, 1.22, 0.10, 0.18)
			Audio.play("BigChime", 1.25, 0.75)
		end)
	end
	-- THE PIP: a ticket that did not come from the meter. The count changes and
	-- the pill flashes lavender; the fill does not move at all.
	local function capPipTo(n)
		local p = H.capsule
		if not p or not p.holder then return end
		cap.countHold = nil
		if n then
			capAdopt(n, nil)
			p.count.Text = tostring(n)
			p.count.TextColor3 = capCountColor(n)
		end
		cap.lastPipAt = os.clock()
		if City.hudOff then return end
		pulse(p.scale, 1.22, 0.10, 0.18)
		p.face.BackgroundColor3 = C.lav
		UI.tween(p.face, 0.50, { BackgroundColor3 = C.paper })
	end
	-- CityEvent("ticket", { tickets, meter, from = "meter"|"hunt"|"streak" })
	local function onTicket(info)
		if type(info) ~= "table" then return end
		local t, m = tonumber(info.tickets), tonumber(info.meter)
		capAdopt(t, m)
		if info.from == "meter" then
			-- the receipt goes through notify(), so it is waiting in CITY NEWS
			-- even if the HUD was hidden when the ticket landed
			task.delay(0.45, function()
				if t and t >= CAP_CORAL then
					notify("capsule", "3 CAPSULE TICKETS", "the meter stops here -- spend one at Capsule Corner", C.coral)
				else
					notify("capsule", "CAPSULE TICKET", "use it at Capsule Corner, in the mall", C.lav)
				end
			end)
			capMeterMoment(t)
		else
			-- the third find choreographs its own pip 0.60s after the big line
			-- (ux.md 8), so a push for that same grant must not pip twice
			if cap.pipOwn and os.clock() < cap.pipOwn then
				renderCap()
				return
			end
			capPipTo(t)
		end
	end
	-- TAP THE PILL. With a ticket it lays the existing green ribbon to Capsule
	-- Corner; with none it is where the exact unit figure lives, and nowhere
	-- else. Both are confirmations rather than news, so they go to
	-- City.Jobs.notify DIRECTLY and do not fill the phone's CITY NEWS.
	local function capTap()
		Audio.play("Click", 1.1, 0.6)
		local J = City.Jobs
		if not (J and J.notify) then return end
		local meter, tickets, dayT = capNums()
		if (tickets or 0) >= 1 then
			local mall = Places.MallShops and Places.MallShops[2]
			if mall and City.Way and City.Way.to then City.Way.to(mall.pos, "Capsule Corner") end
			J.notify("pin", "PATH SET", "Capsule Corner, in the mall", C.mintDark)
		elseif dayT >= dayCapN() then
			J.notify("capsule", "CAPSULE METER", "all earned today \u{00B7} back tomorrow", C.lav)
		else
			J.notify("capsule", "CAPSULE METER",
				(meter or 0) .. " of " .. ticketUnits() .. " \u{00B7} full = a free capsule", C.lav)
		end
	end
	-- REDEMPTION. rollCapsule's own table comes back, so UI.playCapsule plays
	-- unchanged and phase D needs no reward UI of its own. The count drops at
	-- 1.6s, as the capsule starts shaking -- which is when the ticket is gone
	-- (ctx.openCapsule's shape, SminskiRunner.client.lua:766-776).
	local capRedeeming = false
	local function capRedeem()
		if capRedeeming then return end
		capRedeeming = true
		task.spawn(function()
			local res = remoteNamed("City", "capsuleTicket")
			capRedeeming = false
			if not (res and res.ok) then
				-- the prompt re-renders every frame, so by now it says BROWSE
				-- again; the refusal only needs saying once, where the player is
				-- already looking
				if res and res.reason and City.Jobs and City.Jobs.notify then
					City.Jobs.notify("capsule", "CAPSULE CORNER", res.reason, C.coral)
				end
				return
			end
			if UI.playCapsule then UI.playCapsule(res) end
			task.delay(1.6, function()
				-- the push must stand down here, or it would hold the old count
				cap.pushOn, cap.pushRef, cap.pushMeter, cap.pushTickets = false, nil, nil, nil
				earned({ ok = true, data = res.data, city = res.city }, "")
				if res.tickets ~= nil or res.meter ~= nil then
					capAdopt(tonumber(res.tickets), tonumber(res.meter))
				end
				renderCap()
			end)
		end)
	end
	-- AT THE MACHINE. E.prompt runs before the MallShops loop (City.lua:2170 vs
	-- :2236), so holding a ticket turns BROWSE into USE TICKET -- and spending
	-- the last one hands BROWSE straight back, because promptTick re-renders
	-- every frame and this branch stops answering. setPrompt has exactly one
	-- button, which is the whole reason the count lives in the sub line.
	local function capPrompt(me)
		local mall = Places.MallShops and Places.MallShops[2]
		if not mall then return nil end
		local _, tickets = capNums()
		if not tickets or tickets < 1 then return nil end
		local r = (Config.Meter and tonumber(Config.Meter.Redeem)) or 14
		if (flat(me) - V(mall.pos.X, 0, mall.pos.Z)).Magnitude >= r then return nil end
		local sub = tickets == 1 and "1 capsule ticket ready \u{00B7} one free capsule"
			or (tickets .. " capsule tickets ready \u{00B7} one tap each")
		return { "CAPSULE CORNER", sub, "USE TICKET", "capsule", capRedeem, CITY + mall.pos }
	end
	-- compact buys legibility with height and type size, never with width: the
	-- free slot is 138 design px and 120 is what fits it on every canvas
	local function applyCapSize()
		local p = H.capsule
		if not p or not p.holder then return end
		local c = UI.compact()
		p.holder.Size = UDim2.fromOffset(120, c and 52 or 48)
		p.holder.Position = UDim2.new(1, -184, 0, c and 24 or 26)
		p.icon.Size = UDim2.fromOffset(c and 34 or 32, c and 34 or 32)
		p.icon.Position = UDim2.fromOffset(8, c and 9 or 8)
		p.count.Size = UDim2.fromOffset(30, c and 28 or 26)
		p.count.Position = UDim2.fromOffset(c and 48 or 46, c and 4 or 3)
		p.count.TextSize = c and 24 or 22
		p.track.Size = UDim2.fromOffset(c and 64 or 66, c and 7 or 6)
		p.track.Position = UDim2.fromOffset(c and 48 or 46, c and 38 or 34)
	end
	-- leaving the city: the latch is cleared so a return trip re-latches from
	-- fresh data rather than showing the last visit's numbers
	local function capReset()
		local p = H.capsule
		if capFillTween then capFillTween:Cancel() capFillTween = nil end
		cap.latched, cap.momentUntil, cap.fillAt = false, nil, nil
		cap.shownMeter, cap.shownTickets, cap.notches, cap.lastPulse = nil, nil, 0, 0
		cap.pushOn, cap.pushRef, cap.pushMeter, cap.pushTickets = false, nil, nil, nil
		cap.pipOwn, cap.countHold, cap.lastPipAt = nil, nil, nil
		if not p or not p.holder then return end
		p.holder.Visible = false
		p.scale.Scale = 1
		p.face.BackgroundColor3 = C.paper
		p.fill.Size = UDim2.fromScale(0, 1)
		p.fill.BackgroundColor3 = C.mint
		p.count.Text = "0"
		p.count.TextColor3 = C.inkSoft
	end

	-- the compact tray buys legibility by spending words, not pixels
	local function applyTraySize()
		local c = UI.compact()
		E.compact = c
		if tray then tray.Size = UDim2.fromOffset(340, c and 48 or 46) end
		if trayTrack then trayTrack.Size = UDim2.fromOffset(308, c and 12 or 10) end
		if trayCity then trayCity.TextSize = c and 20 or 18 end
		if trayMine then trayMine.TextSize = c and 18 or 16 end
		if bigHolder then bigHolder.Size = UDim2.fromOffset(c and 520 or 620, 48) end
		if bigText then bigText.TextSize = c and 26 or 34 end
		if liveEv then renderTray(liveEv) end
		-- phase D's pill rides this same ViewportSize connection, so the city's
		-- H.layout hook is not needed for it either
		applyCapSize()
	end

	---------------------------------------------------------------------------
	-- COLLECT: MILESTONES AND THE GOAL. Same bookkeeping idiom as the clue
	-- unlock loop below: count how many thresholds are crossed, announce only
	-- the new ones, and let a late arrival catch up silently.
	---------------------------------------------------------------------------
	local MILESTONES = { 0.25, 0.50, 0.75 }
	local function milestonesCrossed(ev)
		if isComp(ev) then return 0 end
		local frac = cityFrac(ev)
		local n = 0
		for _, th in MILESTONES do if frac >= th then n += 1 end end
		return n
	end
	-- BigChime has one voice, so the second call cuts the first short -- that is
	-- the two-note "ta-da", not a bug. The E.list checks are the ambientGen
	-- guard: if the event ended or you left the city, the delayed notes drop.
	local function goalFanfare(ev)
		ev.fanfareAt = os.clock()
		Audio.play("BigChime", 1.15, 0.7)
		task.delay(0.30, function()
			if E.list[ev.uid] == ev then Audio.play("BigChime", 1.50, 0.9) end
		end)
		task.delay(0.55, function()
			if E.list[ev.uid] == ev then Audio.play("Chime", 1.80, 0.45) end
		end)
	end
	local function applyProgress(ev)
		if isComp(ev) then
			-- the money is nearly gone: coral is the HUD's one urgency colour,
			-- and the tray pulses once to say so
			if type(ev.left) == "number" and ev.left <= 5 and not ev.lowWarned then
				ev.lowWarned = true
				pulse(trayScale, 1.05, 0.12, 0.18)
			end
		else
			local crossed = milestonesCrossed(ev)
			if crossed > (ev.milestonesShown or 0) then
				for i = (ev.milestonesShown or 0) + 1, crossed do
					Audio.play("Chime", 1.00 + 0.15 * (i - 1), 0.5)
					pulse(trayScale, 1.05, 0.12, 0.18)
					if i == 2 then holdCity(ev, "HALFWAY!", C.mintDark, 1.2) end
				end
				ev.milestonesShown = crossed
			end
			if cityFrac(ev) >= 1 and not ev.goalCelebrated then
				ev.goalCelebrated = true
				goalFanfare(ev)
			end
		end
		renderTray(ev)
	end

	---------------------------------------------------------------------------
	-- COLLECT: THE FINISH MOMENT. One stroked line over the world for ~4.2s,
	-- one notification with the receipt, and the bonus number exactly once.
	-- Nothing modal, nothing over the centre of the screen.
	---------------------------------------------------------------------------
	local bigGen, bigUntil = 0, 0
	-- THE ANIMATION, AND NOTHING ELSE: the bigGen guard, the City.hudOff early
	-- return, the pop, the hold and the PAIRED fade. Extracted from showBig so
	-- that phase D's third find can borrow the same 620x48 line without phase
	-- B's 250-stud audience test (the Daily 3 is personal -- a bystander gets
	-- nothing). Phase B's behaviour is unchanged: showBig still runs the test
	-- and then calls this. Forward declared at the top of the module, because
	-- the hunt block is written above here.
	function showBigLine(txt, col)
		if not bigHolder or City.hudOff then return end
		bigGen += 1
		local gen = bigGen
		bigText.Text = txt
		bigText.TextColor3 = col
		bigText.TextTransparency = 0
		if bigStroke then bigStroke.Transparency = 0 end
		bigScale.Scale = 0.6
		bigHolder.Visible = true
		bigUntil = os.clock() + 4.3
		UI.tween(bigScale, 0.30, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(3.70, function()
			if gen ~= bigGen or not bigHolder then return end
			-- UIStroke.Transparency is a separate property from
			-- TextTransparency; fading one leaves the outline hanging there
			UI.tween(bigText, 0.50, { TextTransparency = 1 })
			if bigStroke then UI.tween(bigStroke, 0.50, { Transparency = 1 }) end
		end)
		task.delay(4.20, function()
			if gen ~= bigGen or not bigHolder then return end
			bigHolder.Visible = false
		end)
	end
	-- PHASE B'S CALL SITE, WITH ITS AUDIENCE TEST WHERE IT ALWAYS WAS. A city
	-- goal is shared news, so it is only shown to players who took part or who
	-- are within 250 studs of it. A modal being open skips the big line and the
	-- coin pop entirely; the notification still runs through notify(), so the
	-- receipt is waiting in the phone's CITY NEWS and nothing is lost.
	local function showBig(ev, txt, col)
		if not bigHolder or City.hudOff then return end
		local near = (ev.myCount or 0) > 0
			or (E.me ~= nil and ev.at ~= nil and (E.me - ev.at).Magnitude <= 250)
		if not near then return end
		showBigLine(txt, col)
	end

	local function finishNotify(ev, why)
		local def = ev.def
		local title = plainTitle(def) .. " OVER"
		local mine = ev.myCount or 0
		local noun = def.noun or "bags"
		if isComp(ev) then
			local top = ev.top
			local topMe = top ~= nil and top.name == player.DisplayName
			if why == "empty" then
				if topMe then
					notify("coin", title, "you took the most \u{00B7} " .. mine .. " " .. noun, C.gold)
				elseif mine >= 1 and top then
					notify("coin", title, "you took " .. mine .. " " .. noun .. " \u{00B7} "
						.. clampName(top.name) .. " took " .. (top.n or 0), C.gold)
				elseif top then
					notify("hourglass", title, clampName(top.name) .. " took the most \u{00B7} "
						.. (top.n or 0) .. " " .. noun, C.inkSoft)
				else
					notify("hourglass", title, "nobody found the bags this time", C.inkSoft)
				end
			else
				notify("hourglass", title, (ev.left or 0) .. " " .. noun .. " never got found", C.inkSoft)
			end
			return
		end
		local at = def.bonusAt
		if why == "goal" then
			if at and mine >= at then
				notify("coin", "CITY GOAL REACHED", "you got " .. mine .. " of " .. (ev.goal or 0)
					.. " \u{00B7} bonus paid", C.gold)
			elseif mine >= 1 then
				notify("friends", "CITY GOAL REACHED", "you got " .. mine
					.. (at and (" \u{00B7} grab " .. at .. " next time") or ""), C.sky)
			else
				notify("friends", "CITY GOAL REACHED", "the city got there \u{00B7} join in next time", C.sky)
			end
		else
			notify("hourglass", title, "the city got " .. (ev.got or 0) .. " of " .. (ev.goal or 0)
				.. " \u{00B7} no bonus this time", C.inkSoft)
		end
	end

	-- THE STRIP'S SUB LINE, IN ONE PLACE. Both writers use this: the 0.25s tick
	-- and takeStrip below. COLLECT events are `open`, and the server gives every
	-- open event a clue, so "a collect event has no clue" is false -- writing
	-- `ev.area` here instead of the clue put the wrong line on screen for one
	-- frame of the celebration before the next tick corrected it.
	local function stripSub(ev, soon)
		if soon then return "starting soon \u{00B7} tap for details" end
		return latestClue(ev) or ev.area or ""
	end

	-- CLAIM THE STRIP NOW, not on the next 0.25s tick. The finish draws itself
	-- synchronously and renderTray only ever draws for liveEv, so a strip owned
	-- by another event a moment ago would make the celebration a quarter of a
	-- second late. rank() makes the next tick agree with this.
	local function takeStrip(ev)
		-- BUT DEFER TO A BETTER CLAIM, using headline()'s own comparison. Taking
		-- the strip unconditionally let a second finishing event seize it for one
		-- tick before headline() handed it straight back -- two mechanisms
		-- disagreeing, which is a visible flicker now and a real bug the moment
		-- phase C starts events of its own.
		if liveEv and liveEv ~= ev and E.list[liveEv.uid] == liveEv
			and not liveEv.quiet and not liveEv.mine then
			local held, want = rank(liveEv), rank(ev)
			if held > want or (held == want and liveEv.endT <= ev.endT) then return end
		end
		liveEv = ev
		if not strip then return end
		strip.Visible = not City.hudOff
		if sIcon then sIcon.Image = UI.Art and UI.Art.icons[ev.def.icon] or sIcon.Image end
		if sTitle then sTitle.Text = ev.def.title end
		if sSub then sSub.Text = stripSub(ev, now() < ev.startT) end
	end

	local function runFinish(ev, why)
		if ev.finished then return end
		ev.finished = why
		ev.finishedAt = os.clock()
		takeStrip(ev)
		if why == "empty" then ev.left = 0 end
		if why == "goal" and ev.goal then ev.got = math.max(ev.got or 0, ev.goal) end
		-- DROP EVERY PENDING FLASH. A refusal, a HALFWAY! or a BONUS LOCKED is
		-- stale news the moment the event is over, and renderTray prefers a live
		-- hold over the real string -- so a `too far away` caught in its last
		-- 0.4s would sit on top of CITY 12 of 12 and the finish would look late.
		-- The holds' own delayed re-renders still fire and now draw the truth.
		ev.cityHold, ev.cityHoldText, ev.cityHoldColor = nil, nil, nil
		ev.mineHold, ev.mineHoldText, ev.mineHoldColor = nil, nil, nil
		ev.skyHold = nil
		renderTray(ev, 0.18)
		renderClock(ev, now())
		-- the shared fanfare normally already fired off the progress push; this
		-- is the catch for a client that never saw the bar reach 100%
		if why == "goal" and not isComp(ev) and not ev.goalCelebrated then
			ev.goalCelebrated = true
			goalFanfare(ev)
		end
		-- no big line when we did not do it; saying so in 34pt would be mean
		if why ~= "time" then
			task.delay(0.10, function()
				if E.list[ev.uid] ~= ev then return end
				if isComp(ev) then
					local topMe = ev.top ~= nil and ev.top.name == player.DisplayName and (ev.myCount or 0) > 0
					showBig(ev, topMe and "YOU TOOK THE MOST!" or "ALL BAGS GONE!", C.gold)
				else
					showBig(ev, "WE DID IT!", C.mint)
				end
			end)
		end
		task.delay(0.25, function()
			if E.list[ev.uid] == ev then renderTray(ev, 0.18) end
		end)
		task.delay(0.80, function()
			if E.list[ev.uid] == ev then finishNotify(ev, why) end
		end)
	end

	---------------------------------------------------------------------------
	-- COLLECT: the two phone lines. No new instance -- `clue` and `count` are
	-- already there and already in the right place.
	---------------------------------------------------------------------------
	local function phoneClue(ev)
		local def = ev.def
		-- ev.area CARRIES NO PREPOSITION. The server builds it as "the downtown
		-- district" / "the south of town", so the sentence has to supply one --
		-- without it the row read "12 pieces of litter the south of town". "in"
		-- is the one word that works for both shapes areaOf() can return.
		local area = ev.area and ("in " .. ev.area) or "in town"
		if isComp(ev) then
			return compTotal(ev) .. " cash " .. (def.noun or "bags") .. " dropped " .. area
				.. " \u{00B7} first one there keeps it"
		end
		if ev.finished == "goal" or ((ev.goal or 0) > 0 and (ev.got or 0) >= ev.goal) then
			return "done -- the city did it!"
		end
		-- "40 balloons", but "12 pieces of litter": an uncountable noun needs the
		-- measure word or the line reads as a typo
		local n = def.noun or "things"
		if string.sub(n, -1) ~= "s" then n = "pieces of " .. n end
		return (ev.goal or 0) .. " " .. n .. " " .. area .. " \u{00B7} walk over them to grab them"
	end
	-- on the strip the bar carries the progress and the numbers can be quiet;
	-- in a list with no bar the numbers are the whole point, so C.ink
	-- THE COMPACT LINE SPENDS WORDS, NOT PIXELS, exactly as cityString and
	-- mineString already do: the longest desktop count is ~214px in a 236px box,
	-- but at compact 13 the same sentence is ~252px in a 234px box and would
	-- truncate. Shorter wording, bigger type.
	local function phoneCount(ev)
		local def = ev.def
		local mine = ev.myCount or 0
		local c = E.compact
		if isComp(ev) then
			local noun = def.noun or "bags"
			if not ev.top then
				if c then return compTotal(ev) .. " out there \u{00B7} none taken yet" end
				return compTotal(ev) .. " " .. noun .. " out there \u{00B7} nobody has one yet"
			end
			local left = ev.left or 0
			local head = c and (left .. " left") or (left .. " " .. noun .. " left")
			return head .. " \u{00B7} " .. clampName(ev.top.name)
				.. " " .. (ev.top.n or 0) .. " \u{00B7} YOU " .. mine
		end
		local got, goal = ev.got or 0, ev.goal or 0
		if ev.finished == "goal" or (goal > 0 and got >= goal) then
			if c then return got .. "/" .. goal .. " \u{00B7} DONE \u{00B7} YOU " .. mine end
			return "CITY " .. got .. " of " .. goal .. " \u{00B7} DONE \u{00B7} YOU " .. mine
		end
		local at = def.bonusAt
		if c then
			return "CITY " .. got .. "/" .. goal .. " \u{00B7} YOU " .. mine .. (at and ("/" .. at) or "")
		end
		return "CITY " .. got .. " of " .. goal .. "  \u{00B7}  YOU " .. mine .. (at and (" of " .. at) or "")
	end

	---------------------------------------------------------------------------
	-- THE DAILY 3 HUNT (phase D). docs/specs/daily-capsule/ux.md 6-8, 11.
	--
	-- NOT EVENTS, DELIBERATELY. The hunt has no uid, is never in E.list, never
	-- in headline(), never on the countdown strip and never in the tray -- it is
	-- a day-long objective with its own phone section, and keeping it out of
	-- E.list is what stops the two systems regressing each other.
	--
	-- THE CLIENT NEVER COMPUTES A CLUE TIER. The tier number is derivable but
	-- the SENTENCE is not, and sending tier-3 text before it is earned hands a
	-- modded client the answer. Everything drawn here was in the payload; if a
	-- field is absent, the section hides rather than printing a zero.
	---------------------------------------------------------------------------
	local HUNT_M = {
		desk = { rowH = 52, badge = 30, badgeY = 11, bIcon = 24,
			clueX = 46, clueY = 9, clueW = 174, clueH = 34, clueTS = 12,
			goW = 76, goH = 36, lineTS = 12 },
		compact = { rowH = 56, badge = 32, badgeY = 12, bIcon = 26,
			clueX = 48, clueY = 10, clueW = 166, clueH = 36, clueTS = 13,
			goW = 84, goH = 44, lineTS = 13 },
	}
	-- `found` IS A DENSE THREE-ELEMENT BOOLEAN ARRAY, AND IT IS CHECKED AS ONE.
	-- A sparse table round-trips through DataStore JSON as a string-keyed
	-- dictionary, so `found[1]` would read nil and a player at 2/3 would be
	-- shown 0/3. Anything that is not a 3-element array is treated as no hunt
	-- data at all, which hides the section -- it never reads as zero found.
	local function huntFoundOK(f)
		return type(f) == "table" and #f == 3
	end
	local function huntFound(i)
		local f = hunt and hunt.found
		return huntFoundOK(f) and f[i] == true
	end
	local function huntMine()
		local f = hunt and hunt.found
		if not huntFoundOK(f) then return 0 end
		local n = 0
		for i = 1, 3 do if f[i] == true then n += 1 end end
		return n
	end
	-- exactly three spots and a dense `found`, or nothing: "0 / 2" is a lie and
	-- an empty row is worse
	local function huntOK()
		return hunt ~= nil and huntFoundOK(hunt.found)
			and type(hunt.spots) == "table" and #hunt.spots == 3
	end

	local function huntUndraw(i)
		local d = huntDraw[i]
		if not d then return end
		huntDraw[i] = nil
		-- the city tears K.actors out from under us on the way home
		if d.rig and d.rig.model then pcall(function() d.rig.model:Destroy() end) end
	end
	-- A SMALL PLAIN SMINSKI, HIDING. Scale 0.5 and the plain body against a
	-- sighting's scale 1 and a costume, and the `hide` idle -- so the two
	-- categories are told apart at a glance with no new art. No sparkle, no
	-- mark(): a hidden thing has no beacon, and that is the game.
	local function huntDrawSpot(i, spot)
		if type(spot) ~= "table" then return end
		-- City.active, not E.me: it is true from the moment the city is entered,
		-- whereas E.me is only written by the first step -- and a reveal dropped
		-- on arrival would not come back until the next `state` call, because the
		-- server would still believe this client has the model.
		if not City.active then return end
		local x, z = tonumber(spot.x), tonumber(spot.z)
		if not (x and z) then return end
		huntUndraw(i)   -- a reseeded spot is redrawn, never doubled
		local at = V(x, 0, z)
		local ok, rig = pcall(Models.buildSminski, K.actors,
			(Config.Hunt and tonumber(Config.Hunt.Scale)) or 0.5,
			Config.Character and Config.Character("Glow") or Config.Characters[1], false, nil, nil)
		if not ok or not rig then return end
		huntDraw[i] = { at = at, rig = rig,
			-- poseSminski's rootCF sits at the feet, so the pavement height the
			-- events already use is the right number at any scale
			root = CFrame.new(CITY + V(at.X, groundY(at), at.Z)) * CFrame.Angles(0, tonumber(spot.face) or 0, 0) }
	end
	-- WORLD OBJECTS, AND THEY DO NOT RESPECT City.hudOff: hiding the city
	-- because a menu opened would be wrong. Three models at most, one pose
	-- write each, no particles and no lights.
	local function huntStep(t)
		for i = 1, 3 do
			local d = huntDraw[i]
			if d and d.rig then Models.poseSminski(d.rig, d.root, "hide", t) end
		end
	end

	-- never a negative clock, and never a hyphen in the string
	local function huntResetLine(ends)
		local left = (tonumber(ends) or 0) - os.time()
		if left <= 0 then return "new ones any moment now", C.coral end
		local h = left // 3600
		local mn = (left % 3600) // 60
		local txt
		if h > 0 then txt = string.format("new ones in %dh %02dm", h, mn)
		elseif mn > 0 then txt = string.format("new ones in %dm", mn)
		else txt = "new ones in under a minute" end
		return txt, (left < 1800) and C.coral or C.inkSoft
	end
	local function huntStreakLine(n)
		local target = (Config.Hunt and tonumber(Config.Hunt.StreakDays)) or 7
		if n <= 0 then return "finish all three to start a streak", C.inkSoft end
		if n < target then
			return n .. "-day streak \u{00B7} " .. (target - n) .. " more for a bonus ticket", C.gold
		end
		return n .. "-day streak \u{00B7} keep it going", C.gold
	end
	-- ONLY TEXT, COLOUR AND Visible. The section's instances are built once in
	-- E.init and nothing is allocated per find, per day or per tick.
	local function refreshHunt()
		if not hSec or not hRows then return end
		if not huntOK() then hSec.Visible = false return end
		hSec.Visible = true
		local mine = huntMine()
		hCount.Text = mine .. " / 3"
		hCount.TextColor3 = mine >= 3 and C.mintDark or C.inkSoft
		local tc = os.clock()
		local others = 0
		for i = 1, 3 do
			local r, sp = hRows[i], hunt.spots[i]
			if type(sp) ~= "table" then sp = nil end
			local found = huntFound(i)
			local here = (sp and tonumber(sp.here)) or 0
			-- paper -> sky (somebody else found it) -> mint (you found it), so
			-- the social clue-tiering is a colour you learn in one day
			local bcol, itr = C.paper2, 0.55
			if found then
				bcol, itr = C.mint, 0
			elseif here >= 1 then
				bcol, itr = C.sky, 0.25
				others += 1
			end
			r.badge.BackgroundColor3 = bcol
			r.badgeIcon.ImageTransparency = itr
			local short = sp and sp.clueShort
			local txt = (E.compact and short) or (sp and sp.clue) or ""
			local col = C.ink
			if found then
				txt = "found \u{00B7} " .. (short or (sp and sp.clue) or "one of today's three")
				col = C.inkSoft
			elseif txt == "" then
				-- a spot that failed to seed arrives with an empty clue. Say that,
				-- rather than leaving a blank row that reads as broken -- and never
				-- invent a place the payload did not carry.
				txt, col = "no clue yet -- check back in a moment", C.inkSoft
			end
			-- a 1.2s refusal, held in the line you are already reading
			if r.holdUntil and tc < r.holdUntil then txt, col = r.holdText, r.holdColor end
			r.clue.Text = txt
			r.clue.TextColor3 = col
			-- GO ONLY AT TIER 3, and only where the server actually sent an
			-- address. It points at the lot's door, never at the spot, so the
			-- last few studs are still yours to find.
			local tier = (sp and tonumber(sp.tier)) or 1
			r.goTarget = (not found) and tier >= 3 and sp and type(sp.go) == "table" and sp.go or nil
			r.found = found
			r.go.holder.Visible = r.goTarget ~= nil
		end
		hSocial.Visible = others >= 1 and not hunt.full
		if hSocial.Visible then
			hSocial.Text = "others have found " .. others .. " today \u{00B7} warmer clues"
		end
		local rt, rc = huntResetLine(hunt.ends)
		hReset.Text, hReset.TextColor3 = rt, rc
		local st, sc = huntStreakLine(tonumber(hunt.streak) or 0)
		hStreak.Text, hStreak.TextColor3 = st, sc
	end
	local function holdHuntRow(i, txt, col, secs)
		local r = hRows and hRows[i]
		if not r then return end
		r.holdText, r.holdColor, r.holdUntil = txt, col, os.clock() + secs
		refreshHunt()
		task.delay(secs + 0.03, function()
			if hSec and hSec.Visible then refreshHunt() end
		end)
	end
	local function huntGoTo(i)
		local r = hRows and hRows[i]
		local go = r and r.goTarget
		local x, z = go and tonumber(go.x), go and tonumber(go.z)
		if not (x and z) then
			Audio.play("Click", 0.6, 0.5)
			holdHuntRow(i, "not close enough yet -- follow the clue", C.coral, 1.2)
			return
		end
		if City.Way and City.Way.to then City.Way.to(V(x, 0, z), "today's hunt") end
		E.closePhone()
		-- a path confirmation is not city news, so it goes to the notification
		-- corner directly and stays out of the phone's feed
		if City.Jobs and City.Jobs.notify then
			City.Jobs.notify("pin", "PATH SET", "follow the green dots", C.mintDark)
		end
	end
	-- A REFUSAL MUST NOT CLOSE THE THING YOU ARE READING: the phone stays open
	-- and the row holds the reason for 1.2s.
	local function huntTap(i)
		local r = hRows and hRows[i]
		if not r then return end
		if r.goTarget then huntGoTo(i) return end
		Audio.play("Click", 0.6, 0.5)   -- the kit's dull refusal
		-- a found row needs no error copy: "you already did this" IS the
		-- `found \u{00B7} ...` line it is already showing
		if r.found then return end
		holdHuntRow(i, "not close enough yet -- follow the clue", C.coral, 1.2)
	end

	local function huntFindNotify(mine, first)
		-- ONE notification, carrying both facts, so the clue-tightening is felt
		-- rather than inferred
		if mine == 1 then
			if first then
				notify("capsule", "FOUND 1 OF 3", "first here today \u{00B7} the other clues got warmer", C.mint)
			else
				notify("capsule", "FOUND 1 OF 3", "the other clues just got warmer", C.mint)
			end
		elseif mine == 2 then
			notify("capsule", "FOUND 2 OF 3", "one to go \u{00B7} that clue is as good as it gets", C.mint)
		end
	end
	-- THE THIRD FIND: the one moment in phase D allowed to be loud, and it is
	-- loud for 4.2 seconds in a 620x48 strip that never covers the city centre.
	-- On a streak day the big line is REPLACED, never doubled.
	local function huntThird(res)
		local streakT = res.streakTicket == true
		local gotTicket = res.ticket == true or streakT
		local total = tonumber(res.tickets) or ((cap.shownTickets or 0) + (streakT and 2 or 1))
		if gotTicket then
			-- the pip is ours for the next few seconds, so the server's `ticket`
			-- push for this same grant cannot pip the pill a second time, and
			-- the count waits for its pip instead of arriving with the save
			cap.pipOwn = os.clock() + 3
			cap.countHold = os.clock() + (streakT and 0.87 or 0.62)
		end
		task.delay(0.10, function()
			if not E.me then return end   -- left the city
			showBigLine(streakT and "SEVEN DAYS RUNNING!" or "ALL THREE FOUND!", C.gold)
			-- goalFanfare's exact three notes, guarded on "still in the city"
			-- rather than on an event
			Audio.play("BigChime", 1.15, 0.7)
			task.delay(0.30, function() if E.me then Audio.play("BigChime", 1.50, 0.9) end end)
			task.delay(0.55, function() if E.me then Audio.play("Chime", 1.80, 0.45) end end)
		end)
		if gotTicket then
			-- THE PIP, NOT THE METER. This ticket did not come from the meter, so
			-- the fill does not run to full and wipe; two sources, two
			-- animations, one pill.
			task.delay(0.60, function()
				if E.me then capPipTo(streakT and (total - 1) or total) end
			end)
			if streakT then
				task.delay(0.85, function() if E.me then capPipTo(total) end end)
			end
		end
		task.delay(0.80, function()
			if not E.me then return end
			if streakT then
				notify("crown", "ALL THREE FOUND", "7-day streak \u{00B7} two tickets today", C.gold)
			else
				notify("capsule", "ALL THREE FOUND", "a capsule ticket \u{00B7} use it at Capsule Corner", C.gold)
			end
		end)
	end
	local function huntClaim(i)
		if huntBusy then return end
		huntBusy = true
		task.spawn(function()
			local res = remoteNamed("Events", "huntClaim", i)
			huntBusy = false
			if not (res and res.ok) then
				Audio.play("Click", 0.6, 0.5)
				-- UI.toast does not render in the city, so the server's own
				-- words go in the row's 1.2s coral hold
				if res and res.reason then holdHuntRow(i, res.reason, C.coral, 1.2) end
				return
			end
			-- the model goes at once, so E.prompt stops offering it next frame
			huntUndraw(i)
			hunt = hunt or {}
			if huntFoundOK(res.found) then hunt.found = res.found end
			if type(res.spots) == "table" then hunt.spots = res.spots end
			if res.streak ~= nil then hunt.streak = res.streak end
			local mine = tonumber(res.mine) or huntMine()
			if mine >= 3 then hunt.full = true end
			if res.tickets ~= nil then capAdopt(tonumber(res.tickets), nil) end
			-- coins, XP, the coin pop and the coin pill, all the normal way
			earned(res, mine >= 3 and "all three found!" or "you said hi!")
			if mine >= 3 then
				huntThird(res)
			else
				Audio.play("BigChime", 1.25, 0.8)   -- FIND's claim finale
				huntFindNotify(mine, res.first == true)
			end
			refreshHunt()
		end)
	end

	-- TWO HALVES OF ONE SENTENCE, IN EITHER ORDER. "Ari found the Downtown one"
	-- needs the name (huntFound) and the fact that it moved MY tier
	-- (huntClues); those are two independent pushes, so each half waits up to
	-- four seconds for the other and neither ever fires alone.
	local function huntWarmerNotify(i)
		local s, w = huntSocial[i], huntWarm[i]
		if not (s and w) then return end
		local tc = os.clock()
		if tc - s.t > 4 or tc - w > 4 then return end
		huntSocial[i], huntWarm[i] = nil, nil
		notify("capsule", "CLUE GOT WARMER",
			clampName(s.who) .. " found " .. (s.where or "one of them"), C.sky)
	end
	-- ONE MERGE, IN ONE PLACE. The clue push carries no `day`, so the day key is
	-- preserved rather than overwritten with nil.
	local function applyHunt(b, why)
		if type(b) ~= "table" then return end
		local had = hunt ~= nil
		local prevDay = hunt and hunt.day
		local prevMine = huntMine()
		local prevTier = {}
		if hunt and type(hunt.spots) == "table" then
			for i = 1, 3 do
				local sp = hunt.spots[i]
				prevTier[i] = type(sp) == "table" and tonumber(sp.tier) or nil
			end
		end
		hunt = hunt or {}
		if b.day ~= nil then hunt.day = b.day end
		if b.ends ~= nil then hunt.ends = b.ends end
		if b.streak ~= nil then hunt.streak = b.streak end
		if b.full ~= nil then hunt.full = b.full end
		if b.found ~= nil then hunt.found = b.found end
		if b.spots ~= nil then hunt.spots = b.spots end
		local rolled = why == "reset"
			or (had and prevDay ~= nil and b.day ~= nil and b.day ~= prevDay)
		if rolled then
			-- yesterday's three are gone, and the models go with them. NO big
			-- line and no fanfare: a loss is not celebrated in 34pt.
			for i = 1, 3 do huntUndraw(i) end
			huntWarnedDay = nil
			table.clear(huntSocial)
			table.clear(huntWarm)
			-- ONE notification, and only to somebody who had something to lose:
			-- ux.md 9 lists the 3/3 case and the 1-or-2/3 case, and a player who
			-- found nothing yesterday lost nothing, so they get a silent reset.
			if had and prevMine >= 3 then
				notify("capsule", "NEW HUNT TODAY", "three new hiding places \u{00B7} 0 of 3", C.lav)
			elseif had and prevMine >= 1 then
				notify("capsule", "NEW HUNT TODAY", "yesterday's three are gone \u{00B7} 0 of 3 again", C.lav)
			end
		elseif had then
			-- A TIER GOING DOWN IS NOT AN ERROR. A server restart clears the
			-- shared counts, so tiers fall back to your own progress; that
			-- re-renders quietly, with no notification and no flash.
			for i = 1, 3 do
				local sp = type(hunt.spots) == "table" and hunt.spots[i] or nil
				local tier = type(sp) == "table" and tonumber(sp.tier) or nil
				if tier and prevTier[i] and tier > prevTier[i] and not huntFound(i) then
					huntWarm[i] = os.clock()
					huntWarmerNotify(i)
				end
			end
		end
		-- anything already found has no model standing in the street
		for i = 1, 3 do if huntFound(i) then huntUndraw(i) end end
		E.refreshPhone()
	end
	local function onHuntFound(info)
		if type(info) ~= "table" then return end
		local i = tonumber(info.i)
		if not i or i < 1 or i > 3 then return end
		-- my own find speaks for itself, in its own notification
		if info.who ~= nil and info.who == player.DisplayName then return end
		huntSocial[i] = { who = info.who, where = info.where, t = os.clock() }
		-- nothing got warmer for a spot I have already found
		if not huntFound(i) then huntWarmerNotify(i) end
		E.refreshPhone()
	end
	local function onHuntReveal(info)
		if type(info) ~= "table" then return end
		local i = tonumber(info.i)
		if not i or i < 1 or i > 3 then return end
		if huntFound(i) then return end
		huntDrawSpot(i, info.spot)
	end
	local function onHuntHide(info)
		if type(info) ~= "table" then return end
		local i = tonumber(info.i)
		if i then huntUndraw(i) end
	end
	-- THE PROMPT. E.prompt already outranks every shop and business door
	-- (City.lua:2170 vs :2212/:2236), which is where the hunt's spots live.
	-- `SAY HI` is phase A's own verb for the same gesture; the title, the icon,
	-- the 0.5 scale and the plain skin are what separate the two.
	local function huntPrompt(me)
		if not hunt then return nil end
		local r = (Config.Hunt and tonumber(Config.Hunt.Claim)) or 12
		local mp = flat(me)
		local mine = huntMine()
		for i = 1, 3 do
			local d = huntDraw[i]
			if d and not huntFound(i) and (mp - d.at).Magnitude < r then
				return { "HIDING SMINSKI",
					mine >= 2 and "the last of today's three \u{00B7} say hello?"
						or "one of today's three \u{00B7} say hello?",
					"SAY HI", (Config.Hunt and Config.Hunt.Icon) or "capsule",
					function() huntClaim(i) end, CITY + d.at }
			end
		end
		return nil
	end
	local function applyHuntSize()
		if not hSec or not hRows then return end
		local m = UI.compact() and HUNT_M.compact or HUNT_M.desk
		for i = 1, 3 do
			local r = hRows[i]
			r.frame.Size = UDim2.new(1, 0, 0, m.rowH)
			r.badge.Size = UDim2.fromOffset(m.badge, m.badge)
			r.badge.Position = UDim2.fromOffset(8, m.badgeY)
			r.badgeIcon.Size = UDim2.fromOffset(m.bIcon, m.bIcon)
			r.clue.Size = UDim2.fromOffset(m.clueW, m.clueH)
			r.clue.Position = UDim2.fromOffset(m.clueX, m.clueY)
			r.clue.TextSize = m.clueTS
			r.go.holder.Size = UDim2.fromOffset(m.goW, m.goH)
		end
		hReset.TextSize = m.lineTS
		hSocial.TextSize = m.lineTS
		hStreak.TextSize = m.lineTS
	end

	---------------------------------------------------------------------------
	-- STATE
	---------------------------------------------------------------------------
	local function upsert(pub)
		local def = Config.Event(pub.id)
		if not def then return nil end
		local ev = E.list[pub.uid]
		local fresh = ev == nil
		if fresh then
			ev = { uid = pub.uid, id = pub.id, def = def, cluesShown = 0 }
			E.list[pub.uid] = ev
		end
		ev.startT, ev.endT = pub.startT, pub.endT
		ev.quiet = pub.quiet or nil
		ev.clues, ev.area = pub.clues or {}, pub.area
		ev.found, ev.firstBy, ev.hint = pub.found or 0, pub.firstBy, pub.hint
		if def.kind == "collect" then
			-- ev.mine IS NEVER SET ON A COLLECT EVENT. It is FIND's boolean and
			-- headline() skips any event carrying it, so setting it here would
			-- delete the countdown strip on your first balloon. The player's
			-- count is ev.myCount, an integer.
			if pub.got ~= nil then ev.got = pub.got end
			if pub.goal ~= nil then ev.goal = pub.goal end
			if pub.left ~= nil then ev.left = pub.left end
			if pub.myCount ~= nil then ev.myCount = pub.myCount end
			if pub.top ~= nil then ev.top = pub.top end
			ev.got, ev.myCount = ev.got or 0, ev.myCount or 0
			ev.shownGot = ev.got
			if pub.items then syncItems(ev, pub.items) end
			if fresh then
				-- a mid-event joiner catches up silently: no burst of missed
				-- milestone chimes, and no two-second bar sweep on arrival
				ev.milestonesShown = milestonesCrossed(ev)
				ev.goalCelebrated = cityFrac(ev) >= 1 or nil
				ev.trayFresh = true
			end
		end
		if pub.spot then
			-- a moved spot (the Studio hook does this) has to be redrawn
			if ev.spot and (ev.spot[1] ~= pub.spot[1] or ev.spot[2] ~= pub.spot[2]) then
				if def.kind == "collect" then
					-- ONLY THE BEACON MOVES. A collect event's spot is the zone
					-- centre and the items carry their own positions, so undraw()
					-- here would throw away every item record we just synced.
					if ev.mark then ev.mark:Destroy() ev.mark = nil end
				else
					undraw(ev)
				end
			end
			ev.spot = pub.spot
		end
		return ev, fresh
	end

	local function onStart(pub, why)
		-- A quiet sighting you walked into already exists here, marked quiet.
		-- When the server makes it public that is still news to the phone and
		-- the strip -- just not to the player who found it.
		local had = E.list[pub.uid]
		local wasQuiet = had ~= nil and had.quiet == true
		local ev, fresh = upsert(pub)
		if not ev or not (fresh or wasQuiet) then return end
		if ev.mine or ev.firstBy == player.DisplayName then return end
		local def = ev.def
		local lead = ev.startT - now()
		if why == "found" then
			notify(def.icon, "RARE SMINSKI SPOTTED", (ev.firstBy or "someone") .. " found one in " .. (ev.area or "town") .. "!", C.gold)
		elseif why == "news" then
			notify(def.icon, "CITY NEWS", "someone saw a rare Sminski in " .. (ev.area or "town"), C.gold)
		elseif lead > 3 then
			notify(def.icon, def.title, "in " .. math.ceil(lead) .. "s \u{00B7} " .. (ev.clues[1] and ev.clues[1].text or ev.area or ""), C.coral)
		else
			notify(def.icon, def.title, ev.clues[1] and ev.clues[1].text or (ev.area or ""), C.coral)
		end
		-- a competitive announce is a beat brighter: get there FIRST
		if def.kind == "collect" and def.shared == false then
			Audio.play("BigChime", 1.15, 0.65)
		else
			Audio.play("BigChime", 1.05, 0.6)
		end
	end

	local function onEnd(info)
		local ev = E.list[info.uid]
		if not ev then return end
		undraw(ev)
		E.list[info.uid] = nil
		if liveEv == ev then liveEv = nil end
		if ev.def.kind == "collect" then
			-- the finish moment already handed out the receipt 5s ago; only
			-- speak here if no "done" ever arrived (a late join, or a stall)
			if not ev.finished then finishNotify(ev, "time") end
			renderTray(nil)
			return
		end
		if not ev.mine then
			local sub = (info.found or 0) > 0 and ((info.firstBy or "someone") .. " got there first \u{00B7} " .. info.found .. " found it")
				or "nobody found it this time"
			notify("hourglass", ev.def.title .. " OVER", sub, C.inkSoft)
		end
	end

	local function onFound(info)
		local ev = E.list[info.uid]
		if not ev then return end
		ev.found, ev.firstBy, ev.endT, ev.hint = info.found, info.firstBy, info.endT or ev.endT, info.hint
		if info.found == 1 and info.who ~= player.DisplayName and not ev.def.ambient then
			notify(ev.def.icon, ev.def.title, info.who .. " found it first \u{00B7} still there for " .. clock(ev.endT - now()), C.sky)
		end
	end

	local function onReveal(sec)
		local ev = E.list[sec.uid]
		if not ev then
			-- a quiet sighting: nobody has been told about it, you walked into it
			local def = Config.Event("sighting")
			if not def then return end
			ev = { uid = sec.uid, id = "sighting", def = def, cluesShown = 0, clues = {}, found = 0,
				startT = now(), endT = now() + def.lasts, quiet = true }
			E.list[sec.uid] = ev
		end
		ev.spot, ev.skinId, ev.tierId = sec.spot, sec.skin, sec.tier
		if not ev.toldNear then
			ev.toldNear = true
			UI.toast(ev.id == "sighting" and "something is sparkling nearby..." or "you are close -- look around!", C.gold)
			Audio.play("Chime", 1.4, 0.5)
		end
	end

	---------------------------------------------------------------------------
	-- COLLECT: THE SERVER'S NUMBER MOVING. `progress` is coalesced to <= 4/s
	-- and only sent on change; `taken` fires per item so every client can
	-- remove it (and so "that was not me" can have a colour).
	---------------------------------------------------------------------------
	-- set once the server is seen to be sending `by` on "taken"; while it is
	-- false the sky pulse falls back to a got-delta, so the headline beat of the
	-- whole phase does not vanish if that one field is missing
	local sawTakenBy = false
	local function onProgress(p)
		local ev = E.list[p.uid]
		if not ev or ev.def.kind ~= "collect" then return end
		local wasGoal = ev.goal
		local grew = type(p.got) == "number" and p.got > (ev.shownGot or 0)
		if p.got ~= nil then ev.got = p.got end
		if p.left ~= nil then ev.left = p.left end
		if p.goal ~= nil then ev.goal = p.goal end
		if p.top ~= nil then ev.top = p.top end
		ev.shownGot = ev.got
		-- my own claim can have the broadcast beat its reply home, so "someone
		-- else did that" is suppressed while a claim of mine is in flight
		if grew and not sawTakenBy and not ev.claiming and liveEv == ev then
			pulse(cityScale, 1.18, 0.10, 0.16)
			skyFlash(ev)
		end
		-- the goal is scaled by player count, so it moves when people come and
		-- go. Never let the bar jump, and never let it go backwards silently.
		if wasGoal and ev.goal and ev.goal ~= wasGoal then
			skyFlash(ev)
			renderTray(ev, 0.40)
		end
		applyProgress(ev)
	end
	local function onTaken(info)
		local ev = E.list[info.uid]
		if not ev or ev.def.kind ~= "collect" then return end
		removeItem(ev, info.itemId)
		if info.by then sawTakenBy = true end
		-- someone else's pickup. On a one-player server you never see this; the
		-- first time another player's balloon moves your bar is the whole point
		-- of the phase, so it gets its own colour.
		if info.by and info.by ~= player.DisplayName and liveEv == ev then
			pulse(cityScale, 1.18, 0.10, 0.16)
			skyFlash(ev)
		end
	end
	local function onDone(info)
		local ev = E.list[info.uid]
		if not ev or ev.def.kind ~= "collect" then return end
		if info.got ~= nil then ev.got = info.got end
		if info.goal ~= nil then ev.goal = info.goal end
		if info.top ~= nil then ev.top = info.top end
		ev.shownGot = ev.got
		runFinish(ev, info.why or "time")
	end
	-- per-player, and only to players who actually collected something
	local function onReward(info)
		local ev = E.list[info.uid]
		if not ev or ev.def.kind ~= "collect" then return end
		if info.myCount ~= nil then ev.myCount = info.myCount end
		-- if the server sends the fresh save with it, take it the normal way
		if info.data or info.city then earned({ ok = true, data = info.data, city = info.city }, "") end
		if isComp(ev) then return end -- a cash bag was paid when you grabbed it
		local mine, at = ev.myCount or 0, ev.def.bonusAt or 3
		local bonus = info.bonus or 0
		-- "and here's yours" AFTER the shared moment, not on top of it. The big
		-- note is for a bonus that ACTUALLY LANDED -- a timeout pays nobody, and
		-- sounding like it did would be a lie. Zero contribution gets nothing at
		-- all: a sound for "you did not play" is a nag, not a smaller reward.
		local wait = 0
		if ev.fanfareAt then wait = math.max(0, 0.85 - (os.clock() - ev.fanfareAt)) end
		task.delay(wait, function()
			if E.list[info.uid] ~= ev then return end
			if mine >= at and bonus > 0 then Audio.play("BigChime", 1.35, 0.85)
			elseif mine >= 1 then Audio.play("Chime", 1.15, 0.5) end
		end)
		if bonus > 0 and City.popCoins and not City.hudOff then
			task.delay(0.60, function()
				if E.list[info.uid] == ev and not City.hudOff then City.popCoins(bonus) end
			end)
		end
		renderTray(ev, 0.18)
	end

	function E.sync()
		E.synced = true
		task.spawn(function()
			local res = remoteNamed("Events", "state")
			if not (res and res.ok) then
				E.synced = false
				E.syncFails += 1
				return
			end
			E.syncFails = 0
			E.spotted = res.spotted or {}
			for _, pub in res.events or {} do upsert(pub) end
			-- the hunt block rides the same reply. A server without it leaves
			-- `hunt` nil, which hides the phone section and nothing else.
			if res.hunt then applyHunt(res.hunt, "state") end
		end)
	end

	---------------------------------------------------------------------------
	-- CLAIMING
	---------------------------------------------------------------------------
	local function spottedCount()
		local n, total = 0, 0
		for _ in E.spotted do n += 1 end
		for _, sk in Config.Skins do if sk.id ~= "none" then total += 1 end end
		return n, total
	end
	local function claim(ev)
		if ev.claiming or ev.mine then return end
		ev.claiming = true
		task.spawn(function()
			local res = remoteNamed("Events", "claim", ev.uid)
			ev.claiming = false
			if not (res and res.ok) then
				if res and res.reason then UI.toast(res.reason, C.coral) end
				return
			end
			ev.mine = true
			ev.mineT = os.clock()
			if res.spotted then E.spotted = res.spotted end
			local what = ev.id == "sighting" and "you said hi!" or ev.id == "lostpup" and "pup rescued!" or "ice cream!"
			earned(res, what .. (res.first and "  FIRST!" or ""))
			if res.skin then
				local sk = Config.Skin(res.skin)
				local n, total = spottedCount()
				local tier = res.tier and (string.upper(string.sub(res.tier, 1, 1)) .. string.sub(res.tier, 2)) or ""
				notify("star", (res.isNew and "NEW! " or "") .. (sk and sk.name or "Sminski"), tier .. " \u{00B7} spotted " .. n .. "/" .. total, C.gold)
			end
			-- FIND'S FINALE, AND ONLY FIND'S. A COLLECT event claims through
			-- claimItem() below and its own pickup run; this line firing on all
			-- forty balloons is the exact "torture the 30th time" failure.
			if ev.def.kind ~= "collect" then Audio.play("BigChime", 1.25, 0.8) end
		end)
	end

	---------------------------------------------------------------------------
	-- COLLECT: AUTOMATIC PICKUP. Walking over a balloon is not a decision, so
	-- it does not get the prompt card: inside PickupRadius the client asks, and
	-- the server still checks where you really are (at a wider radius, to
	-- absorb latency). The race for a cash bag becomes pure movement.
	--
	-- TWO GUARDS, BOTH REQUIRED. One claim in flight at a time, and an itemId
	-- that came back refused is never asked for again -- without either, a
	-- player standing on a claimed bag sends a claim every single frame.
	---------------------------------------------------------------------------
	local function claimItem(ev, it)
		if ev.claiming or ev.finished or ev.noMore then return end
		if ev.retryAt and os.clock() < ev.retryAt then return end
		local id = it.id
		if ev.refused and ev.refused[id] then return end
		ev.claiming = true
		task.spawn(function()
			local res = remoteNamed("Events", "claim", ev.uid, id)
			ev.claiming = false
			if not (res and res.ok) then
				local why = res and res.reason
				-- UI.toast does not render in the city, so the refusal goes where
				-- the player is already looking: 1s in the tray. NOT once the
				-- event is over, though -- a claim in flight when "done" lands
				-- (the loser of the race for the last bag) would otherwise paint
				-- `already gone` over `ALL GONE` for a second.
				if why and not ev.finished then holdCity(ev, why, C.coral, 1.0) end
				-- WHICH REFUSALS ARE FINAL, AND WHICH ARE "NOT JUST NOW".
				--
				-- Only a settled answer may blacklist an itemId. Get this wrong
				-- either way and it is a real bug: blacklist too little and a
				-- player standing on a claimed bag sends a claim every frame;
				-- blacklist too much and a perfectly good bag dies forever.
				--
				--   already gone  settled -- somebody has it. Blacklist + remove.
				--   it's over     settled -- ev.noMore stops the whole event.
				--   too far away  NOT settled. The client claims at PickupRadius
				--                 6 and the server validates at PickupServer 9;
				--                 that 3-stud gap exists to absorb latency and
				--                 streaming, so this means "you were moving",
				--                 not "this is not yours". At running speed
				--                 ~150ms of round trip crosses it. Walk back on
				--                 and it must still be there.
				--   no reason     the rate limiter, the pre-start window, or a
				--                 dropped call. Also not settled.
				if why == "already gone" then
					ev.refused = ev.refused or {}
					ev.refused[id] = true
					removeItem(ev, id)
				elseif why == "it's over" then
					ev.refused = ev.refused or {}
					ev.refused[id] = true
					-- the goal was met with items still on the ground: stop
					-- asking for the other twenty of them one at a time
					ev.noMore = true
				else
					ev.retryAt = os.clock() + 0.5
				end
				return
			end
			ev.retryAt = nil
			removeItem(ev, id)
			local was = ev.myCount or 0
			ev.myCount = res.myCount or (was + 1)
			if res.got ~= nil then ev.got = res.got end
			if res.left ~= nil then ev.left = res.left end
			if res.goal ~= nil then ev.goal = res.goal end
			if res.top ~= nil then ev.top = res.top end
			ev.shownGot = ev.got
			-- COINS AND STATE THE NORMAL WAY, BUT NOT earned()'s CELEBRATION.
			-- earned() pops a 230x64 billboard, a toast and a Chime whenever
			-- res.coins is set; forty pickups would stack forty billboards. The
			-- coins are in res.data, so the balance updates and the reward for a
			-- single item stays one pooled Tick and one tray tick (ux.md 3).
			earned({ ok = true, data = res.data, city = res.city }, "")
			playPickup(isComp(ev) and (ev.left or 1) <= 0)
			pulse(mineScale, 1.18, 0.10, 0.16)
			local at = ev.def.bonusAt
			if at and not isComp(ev) and was < at and ev.myCount >= at and not ev.bonusTold then
				-- the one state change a player owns, so it gets the one
				-- milestone notification of the whole event
				ev.bonusTold = true
				-- same rule as the refusal above: after the finish, the finish
				-- string wins the slot
				if not ev.finished then holdMine(ev, "BONUS LOCKED", C.mintDark, 1.6) end
				notify("star", "BONUS LOCKED IN", at .. " collected \u{00B7} you get the finish bonus", C.mint)
			end
			applyProgress(ev)
		end)
	end

	local function stepCollect(ev, tn, t, mp)
		if tn < ev.startT then return end
		-- ev.at is the ZONE CENTRE for a collect event, not a claim target: the
		-- beacon stands on it and the finish line's 250-stud audience test needs
		-- it whether or not the event happens to be `open`
		if ev.spot and not ev.at then ev.at = V(ev.spot[1], 0, ev.spot[2]) end
		if not ev.mark and ev.at and ev.def.open then mark(ev, ev.at) end
		if not ev.items then return end
		local r = EV.PickupRadius or 6
		local pick = not (ev.finished or ev.noMore)
		local best, bd
		for id, it in ev.items do
			local d = (it.at - mp).Magnitude
			if not it.draw and drawBudget > 0 then
				-- a few models per frame: 48 in one go is a visible hitch
				drawBudget -= 1
				drawItem(ev, it)
			end
			if it.draw and d < 150 then animItem(it, t) end
			if pick and d < r and not (ev.refused and ev.refused[id]) then
				if not best or d < bd then best, bd = it, d end
			end
		end
		if best then claimItem(ev, best) end
	end

	function E.prompt(me)
		-- THE HUNT FIRST: it is a thing you are standing on top of, at 12 studs,
		-- and the server keeps its spots at least 12 studs from any live event,
		-- so this cannot shadow a claim you could also make.
		local hp = huntPrompt(me)
		if hp then return hp end
		for _, ev in E.list do
			-- a collect item never produces a prompt card: pickup is automatic
			if ev.def.kind ~= "collect" and ev.drawn and ev.at and not ev.mine and now() >= ev.startT then
				if (flat(me) - ev.at).Magnitude < EV.ClaimRadius - 2 then
					local def = ev.def
					local sub = ev.id == "sighting" and "a rare Sminski! say hello before it slips away"
						or ev.id == "lostpup" and "it looks lost. take it home?"
						or "one scoop, on the house"
					return { def.title, sub, def.verb or "GO", def.icon, function() claim(ev) end, CITY + ev.at }
				end
			end
		end
		-- CAPSULE CORNER LAST, of the three. A rare sighting can land on the mall
		-- block, and a ticket in your pocket must never make one unclaimable --
		-- but this still outranks the MallShops BROWSE prompt, because the whole
		-- of E.prompt runs before it (City.lua:2170 vs :2236).
		local cp = capPrompt(me)
		if cp then return cp end
		return nil
	end

	---------------------------------------------------------------------------
	-- THE STRIP: the one live headline, with its clock, under the district
	-- pill. Tapping it opens the phone. The countdown is what makes an event
	-- urgent; a notification that scrolled away cannot do that.
	---------------------------------------------------------------------------
	-- strip/sIcon/sTitle/sSub/sClock are declared at the top of the module: the
	-- finish moment is written above E.init and has to be able to reach sClock.
	local phone = {}
	-- WHICH EVENT OWNS THE STRIP.
	--
	-- Phase A's rule was "soonest ending", which is right when every event's
	-- strip says the same kind of thing. It stopped being right in phase B: a
	-- COLLECT strip carries the shared counter and the bar -- those ARE the
	-- event -- while a FIND strip carries a clock and a clue, and a FIND that
	-- loses the strip is still fully listed on the phone with its own clock and
	-- its own GO. A 110-second ambient sighting should not be able to evict the
	-- loudest thing in the city just by ending sooner.
	--
	--   3  a collect event inside its finish window (ev.finished is set, which
	--      only happens between "done" and "end"). NOTHING evicts WE DID IT!
	--      while it is on screen -- not a new find, not a new collect.
	--   2  a live collect event
	--   1  a find event
	--
	-- Within a rank, soonest-ending still wins, exactly as it did before, so
	-- FIND against FIND behaves identically to phase A.
	-- (forward declared at the top of the module: takeStrip compares with it)
	function rank(ev)
		if ev.def.kind ~= "collect" then return 1 end
		return ev.finished and 3 or 2
	end
	local function headline()
		local best, bestRank
		for _, ev in E.list do
			if not ev.quiet and not ev.mine then
				local r = rank(ev)
				if not best or r > bestRank or (r == bestRank and ev.endT < best.endT) then
					best, bestRank = ev, r
				end
			end
		end
		return best
	end
	-- (forward declared at the top of the module: takeStrip draws the sub line)
	function latestClue(ev)
		local text
		for _, c in ev.clues or {} do
			if now() >= c.t then text = c.text end
		end
		return text
	end

	---------------------------------------------------------------------------
	-- THE PHONE. A toy handset that slides up out of the bottom-left corner --
	-- the PHONE button's own column -- and not a centred modal card with the
	-- word PHONE written on it. docs/specs/phone-ui/ux.md is the contract.
	--
	-- WHAT IT KEEPS FROM modalCard, EXACTLY: the shade is a TextButton at
	-- ZIndex 20 and a DIRECT CHILD of H.root, because City.anyModalOpen
	-- (City.lua:1299) scans H.root for that shape and the title screen stops
	-- knowing a screen is open the moment it changes. The body is ZIndex 21
	-- with its own fitScale UIScale.
	--
	-- WHAT IT DOES NOT KEEP: modalCard's 0.5 dim. A phone you hold up does not
	-- black out the street, so the wash is 0.72 and the coin pill, the strip and
	-- the notification corner all stay readable behind it.
	--
	-- TWO SIZES, AND NEITHER IS EVER FIT-SCALED. A desktop canvas is never
	-- shorter than 760 (canvasH = vy / min(vx/1280, vy/760) >= 760), so 592
	-- gives UI.fit 1.0; the shortest compact canvas is 530, and (530-44)/480 =
	-- 1.01, so 480 does too. A 592 phone fitted to 0.8 and then multiplied by
	-- the 0.6 UIScale floor would draw 12px body text at 5.8 real pixels --
	-- compact gets a SHORTER phone with BIGGER text instead of a scaled one.
	---------------------------------------------------------------------------
	local PHONE_W = 376
	local PHONE_M = {
		desk = {
			shellH = 592, screenH = 500, statusH = 32, feedY = 34, feedH = 438,
			spottedY = 478, spottedTS = 14,
			clockY = 5, clockTS = 15,
			wxIcon = 20, wxIconX = -118, wxW = 100, wxH = 18, wxTS = 12,
			newsH = 84, newsLines = 4,
			rowH = 138, iconSz = 46, iconY = 12, textX = 64,
			titleW = -146, titleH = 22, titleTS = 17,
			clkW = 72, clkH = 22, clkTS = 17,
			clueY = 36, clueW = -78, clueH = 34, clueTS = 12,
			cntY = 70, cntW = -78, cntH = 16, cntTS = 12,
			goW = 100, goH = 40,
		},
		compact = {
			shellH = 480, screenH = 388, statusH = 34, feedY = 36, feedH = 324,
			spottedY = 366, spottedTS = 15,
			clockY = 6, clockTS = 16,
			wxIcon = 22, wxIconX = -122, wxW = 104, wxH = 20, wxTS = 13,
			newsH = 66, newsLines = 3,
			rowH = 156, iconSz = 48, iconY = 14, textX = 66,
			titleW = -152, titleH = 24, titleTS = 18,
			clkW = 76, clkH = 24, clkTS = 18,
			clueY = 38, clueW = -80, clueH = 36, clueTS = 13,
			cntY = 76, cntW = -80, cntH = 18, cntTS = 13,
			goW = 120, goH = 48,
		},
	}
	-- `tap the bar to close` is the least phone-like thing on the phone and the
	-- most useful to someone who has never seen a home bar: three opens, then it
	-- stops. Session-local on purpose -- no save field, no new payload.
	local PHONE_HINTS = 3
	local phoneOpens = 0

	local function pbox(parent, name, size, pos, color, radius, z)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		if z then f.ZIndex = z end
		f.Parent = parent
		if radius then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, radius)
			c.Parent = f
		end
		return f
	end

	-- A FEED SECTION. This is the growth hook: phases C/D/G each add ONE frame
	-- with their reserved LayoutOrder (20 JOB OFFERS, 40 TOP THIS HOUR, 50
	-- TODAY'S HUNT, 60 ERRANDS) and the UIListLayout reflows around it --
	-- nothing built here is touched, and a section with nothing to say sets
	-- Visible = false and leaves the flow for free.
	local function phoneSection(key, order, gap)
		local f = Instance.new("Frame")
		f.Name = "PhoneSec" .. key
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.LayoutOrder = order
		f.Parent = phone.feed
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, gap)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
		return f
	end

	-- ONE METRIC TABLE, APPLIED IN ONE PLACE. Same shape as applyTraySize: read
	-- UI.compact() here and re-read it on a viewport change, so the city's
	-- H.layout hook (another lane's file) is not needed.
	local function applyPhoneSize()
		local c = UI.compact()
		E.compact = c
		local m = c and PHONE_M.compact or PHONE_M.desk
		phone.m = m
		if not phone.body then return end
		phone.hidden = UDim2.new(0, 24, 1, m.shellH + 12)
		phone.shown = UDim2.new(0, 24, 1, -24)
		phone.body.Size = UDim2.fromOffset(PHONE_W, m.shellH)
		phone.body.Position = phone.open and phone.shown or phone.hidden
		phone.fitScale.Scale = UI.fit(PHONE_W, m.shellH, 44)
		phone.screen.Size = UDim2.fromOffset(344, m.screenH)
		phone.div1.Position = UDim2.fromOffset(0, m.statusH)
		phone.feed.Size = UDim2.fromOffset(344, m.feedH)
		phone.feed.Position = UDim2.fromOffset(0, m.feedY)
		phone.div2.Position = UDim2.fromOffset(0, m.feedY + m.feedH)
		phone.clock.Position = UDim2.fromOffset(14, m.clockY)
		phone.clock.TextSize = m.clockTS
		phone.wxIcon.Size = UDim2.fromOffset(m.wxIcon, m.wxIcon)
		phone.wxIcon.Position = UDim2.new(1, m.wxIconX, 0, 6)
		phone.wx.Size = UDim2.fromOffset(m.wxW, m.wxH)
		phone.wx.TextSize = m.wxTS
		phone.spotted.Position = UDim2.fromOffset(14, m.spottedY)
		phone.spotted.TextSize = m.spottedTS
		phone.news.Size = UDim2.new(1, 0, 0, m.newsH)
		phone.homeBar.Position = UDim2.fromOffset(122, m.shellH - 40)
		phone.homeHint.Position = UDim2.fromOffset(0, m.shellH - 26)
		phone.homeTap.Position = UDim2.fromOffset(78, m.shellH - 58)
		for _, r in phone.rows or {} do
			r.frame.Size = UDim2.new(1, 0, 0, m.rowH)
			r.icon.Size = UDim2.fromOffset(m.iconSz, m.iconSz)
			r.icon.Position = UDim2.fromOffset(10, m.iconY)
			r.title.Size = UDim2.new(1, m.titleW, 0, m.titleH)
			r.title.Position = UDim2.fromOffset(m.textX, 10)
			r.title.TextSize = m.titleTS
			r.clock.Size = UDim2.fromOffset(m.clkW, m.clkH)
			r.clock.TextSize = m.clkTS
			r.clue.Size = UDim2.new(1, m.clueW, 0, m.clueH)
			r.clue.Position = UDim2.fromOffset(m.textX, m.clueY)
			r.clue.TextSize = m.clueTS
			r.count.Size = UDim2.new(1, m.cntW, 0, m.cntH)
			r.count.Position = UDim2.fromOffset(m.textX, m.cntY)
			r.count.TextSize = m.cntTS
			r.go.holder.Size = UDim2.fromOffset(m.goW, m.goH)
		end
		-- phase D's section rides the same metric pass
		applyHuntSize()
	end

	-- A REFUSAL MUST NOT CLOSE THE THING YOU ARE READING. Same hold idiom as the
	-- tray's holdCity: the text lives on the row table for 1.2s and refreshPhone
	-- honours it, so no new instance and no new timer loop. Tied to the event,
	-- because a 4th event starting can change which row is which.
	local function holdRow(ev, txt, col, secs)
		for _, r in phone.rows or {} do
			if r.ev == ev then
				r.holdEv, r.holdText, r.holdColor, r.holdUntil = ev, txt, col, os.clock() + secs
			end
		end
		E.refreshPhone()
		task.delay(secs + 0.03, function()
			if phone.open then E.refreshPhone() end
		end)
	end

	function E.init(root)
		local holder, card = UI.card(root, UDim2.fromOffset(340, 50), UDim2.new(0.5, 0, 0, 152), Vector2.new(0.5, 0), C.paper)
		holder.Visible = false
		strip = holder
		sIcon = UI.icon(card, "star", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 5), ZIndex = 3 })
		sTitle = UI.text(card, "", { Size = UDim2.new(1, -126, 0, 20), Position = UDim2.fromOffset(52, 6),
			Font = Enum.Font.FredokaOne, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		sSub = UI.text(card, "", { Size = UDim2.new(1, -126, 0, 16), Position = UDim2.fromOffset(52, 27),
			TextSize = 12, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		sClock = UI.text(card, "", { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(64, 30),
			Position = UDim2.new(1, -12, 0.5, 0), Font = Enum.Font.FredokaOne, TextSize = 20,
			TextColor3 = C.coral, TextXAlignment = Enum.TextXAlignment.Right })
		local tap = Instance.new("TextButton")
		tap.Text = ""
		tap.BackgroundTransparency = 1
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = 6
		tap.Parent = card
		tap.Activated:Connect(function()
			Audio.play("Click", 1.1, 0.6)
			E.openPhone()
		end)

		-----------------------------------------------------------------------
		-- THE PROGRESS TRAY: a CHILD of the strip's card, hanging 46px past its
		-- bottom edge. A child, not a sibling, for two reasons: the card's own
		-- drop shadow ends at y209 and a sibling would sit in it, and
		-- strip.Visible already gates City.hudOff -- so the tray obeys the HUD
		-- toggle for free, with nothing new to wire.
		--
		-- ZIndex 4 clears the card's skin images and labels (1-3) and stays
		-- under the row's own tap button (6). y 202-248 is the next free slot in
		-- the top-centre stack: pill 18-82, boost 92-146, strip 152-202.
		-----------------------------------------------------------------------
		tray = Instance.new("Frame")
		tray.Name = "EventTray"
		tray.Size = UDim2.fromOffset(340, 46)
		tray.Position = UDim2.fromOffset(0, 50)
		tray.BackgroundColor3 = C.paper
		tray.BorderSizePixel = 0
		tray.ZIndex = 4
		tray.Visible = false
		tray.Parent = card
		local trc = Instance.new("UICorner") trc.CornerRadius = UDim.new(0, 14) trc.Parent = tray
		trayScale = Instance.new("UIScale") trayScale.Parent = tray
		trayTap = Instance.new("TextButton")
		trayTap.Name = "EventTrayTap"
		trayTap.Text = ""
		trayTap.BackgroundTransparency = 1
		trayTap.Size = UDim2.fromScale(1, 1)
		trayTap.ZIndex = 6
		trayTap.Parent = tray
		trayTap.Activated:Connect(function()
			Audio.play("Click", 1.1, 0.6)
			E.openPhone()
		end)
		trayCity = UI.text(tray, "", { Name = "EventTrayCity", Size = UDim2.fromOffset(170, 22),
			Position = UDim2.fromOffset(16, 4), Font = Enum.Font.FredokaOne, TextSize = 18,
			TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		cityScale = Instance.new("UIScale") cityScale.Parent = trayCity
		trayMine = UI.text(tray, "", { Name = "EventTrayMine", AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(138, 22), Position = UDim2.new(1, -16, 0, 4),
			Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
		mineScale = Instance.new("UIScale") mineScale.Parent = trayMine
		trayTrack = Instance.new("Frame")
		trayTrack.Name = "EventTrayTrack"
		trayTrack.Size = UDim2.fromOffset(308, 10)
		trayTrack.Position = UDim2.fromOffset(16, 30)
		trayTrack.BackgroundColor3 = C.paper2
		trayTrack.BorderSizePixel = 0
		trayTrack.Parent = tray
		local tkc = Instance.new("UICorner") tkc.CornerRadius = UDim.new(0, 5) tkc.Parent = trayTrack
		trayFill = Instance.new("Frame")
		trayFill.Name = "EventTrayFill"
		trayFill.Size = UDim2.fromScale(0, 1)
		trayFill.BackgroundColor3 = C.mint
		trayFill.BorderSizePixel = 0
		trayFill.Parent = trayTrack
		local tfc = Instance.new("UICorner") tfc.CornerRadius = UDim.new(0, 5) tfc.Parent = trayFill

		-----------------------------------------------------------------------
		-- THE FINISH LINE. A FRAME wrapping the label, not a bare TextLabel:
		-- City.hudVisible only sweeps direct Frame children of H.root, and a
		-- bare label would stay on screen over a modal (H.raceText and H.hint
		-- are the existing holes of exactly that shape).
		-----------------------------------------------------------------------
		bigHolder = Instance.new("Frame")
		bigHolder.Name = "EventBigLine"
		bigHolder.BackgroundTransparency = 1
		bigHolder.Size = UDim2.fromOffset(620, 48)
		bigHolder.Position = UDim2.new(0.5, 0, 0, 256)
		bigHolder.AnchorPoint = Vector2.new(0.5, 0)
		bigHolder.Visible = false
		bigHolder.Parent = root
		bigScale = Instance.new("UIScale") bigScale.Parent = bigHolder
		bigText = UI.text(bigHolder, "", { Name = "EventBigText", Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = C.mint, stroke = 3 })
		bigStroke = bigText:FindFirstChildOfClass("UIStroke")

		-----------------------------------------------------------------------
		-- THE PHONE. Built once, here: ~97 instances, and NOTHING is created at
		-- open, at refresh or per event -- the row count is fixed at 3 forever
		-- and E.refreshPhone only writes text and Visible. A city with 40
		-- balloons and 6 news items allocates no GUI at all (performance.md).
		--
		-- Sizes come from PHONE_M via applyPhoneSize() at the bottom of init;
		-- what is written inline here is only what never changes.
		-----------------------------------------------------------------------
		local m = UI.compact() and PHONE_M.compact or PHONE_M.desk
		local dim = Instance.new("TextButton")
		dim.Name = "PhoneShade"
		dim.Text = ""
		dim.AutoButtonColor = false
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.72
		dim.ZIndex = 20
		dim.Visible = false
		dim.Parent = root
		dim.Activated:Connect(function() E.closePhone() end)
		phone.shade = dim

		local body, pface = UI.card(dim, UDim2.fromOffset(PHONE_W, m.shellH),
			UDim2.new(0, 24, 1, m.shellH + 12), Vector2.new(0, 1), C.sky)
		body.Name = "PhoneBody"
		body.ZIndex = 21
		phone.body = body
		phone.fitScale = Instance.new("UIScale")
		phone.fitScale.Parent = body
		-- modalCard's `eat`, and it is not optional: without it every tap on the
		-- bezel or on empty feed space falls through to the shade and closes the
		-- phone you are reading. ZIndex 2 is above UI.skin's two images (1) and
		-- below every face child (3+), so it swallows nothing it should not.
		local eat = Instance.new("TextButton")
		eat.Name = "PhoneEat"
		eat.Text = ""
		eat.AutoButtonColor = false
		eat.BackgroundTransparency = 1
		eat.Size = UDim2.fromScale(1, 1)
		eat.ZIndex = 2
		eat.Parent = pface

		-- the handset: a speaker slot, a camera dot, and concentric rounding
		-- (shell ~27 from the card art, screen 20), which is the one thing that
		-- makes a bezel read as a bezel. Face children are ZIndex 3+ because
		-- UI.skin parents its 9-slices at the face's own ZIndex.
		local bezel = C.sky:Lerp(C.ink, 0.45)
		pbox(pface, "PhoneSpeaker", UDim2.fromOffset(78, 8), UDim2.fromOffset(149, 13), bezel, 4, 3)
		pbox(pface, "PhoneCam", UDim2.fromOffset(10, 10), UDim2.fromOffset(125, 12), bezel, 5, 3)
		local screen = pbox(pface, "PhoneScreen", UDim2.fromOffset(344, m.screenH),
			UDim2.fromOffset(16, 34), C.paper, 20, 3)
		screen.ClipsDescendants = true
		phone.screen = screen
		local sst = Instance.new("UIStroke")
		sst.Thickness = 2
		sst.Color = C.ink
		sst.Transparency = 0.72
		sst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		sst.Parent = screen

		-- STATUS BAND. The in-game clock and the weather appear nowhere else in
		-- the city HUD, so this is new information rather than a duplicate -- and
		-- a phone without a status bar does not read as a phone. If Weather is
		-- unavailable both labels HIDE: the bar may be empty, it may not lie
		-- about the time.
		phone.clock = UI.text(screen, "", { Name = "PhoneClock", Size = UDim2.fromOffset(140, 22),
			Position = UDim2.fromOffset(14, m.clockY), Font = Enum.Font.FredokaOne, TextSize = m.clockTS,
			TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		phone.wxIcon = UI.icon(screen, "star", { Name = "PhoneWxIcon", AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(m.wxIcon, m.wxIcon), Position = UDim2.new(1, m.wxIconX, 0, 6) })
		phone.wx = UI.text(screen, "", { Name = "PhoneWx", AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(m.wxW, m.wxH), Position = UDim2.new(1, -14, 0, 7),
			Font = Enum.Font.GothamBold, TextSize = m.wxTS, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
		phone.div1 = pbox(screen, "PhoneDiv1", UDim2.new(1, 0, 0, 2), UDim2.fromOffset(0, m.statusH), C.paper2)

		-- THE FEED: one scrolling list of sections, not tabs. Tabs would cost a
		-- 52px chrome row out of a 438px screen and hide two thirds of the phone
		-- behind a tap, and the director never runs two headline events at once.
		local feed = Instance.new("ScrollingFrame")
		feed.Name = "PhoneFeed"
		feed.Size = UDim2.fromOffset(344, m.feedH)
		feed.Position = UDim2.fromOffset(0, m.feedY)
		feed.BackgroundTransparency = 1
		feed.BorderSizePixel = 0
		feed.ClipsDescendants = true
		feed.CanvasSize = UDim2.new()
		feed.AutomaticCanvasSize = Enum.AutomaticSize.Y
		feed.ScrollingDirection = Enum.ScrollingDirection.Y
		feed.ScrollBarThickness = 4
		feed.ScrollBarImageColor3 = C.inkSoft
		feed.ScrollBarImageTransparency = 0.4
		feed.Parent = screen
		phone.feed = feed
		local fl = Instance.new("UIListLayout")
		fl.Padding = UDim.new(0, 12)
		fl.SortOrder = Enum.SortOrder.LayoutOrder
		fl.Parent = feed
		local fp = Instance.new("UIPadding")
		fp.PaddingLeft = UDim.new(0, 10)
		-- R20, not R10: the 4px scrollbar gets a gutter instead of sitting on a row
		fp.PaddingRight = UDim.new(0, 20)
		fp.PaddingTop = UDim.new(0, 8)
		fp.PaddingBottom = UDim.new(0, 10)
		fp.Parent = feed

		-- NOW IN TOWN (order 10) and CITY NEWS (order 70). 20/40/50/60 are
		-- reserved for phases C/D/G; 70 rather than 30 for news because the
		-- daily capsule's phase-D section lands 74px below the fold at 30.
		local secNow = phoneSection("Now", 10, 8)
		UI.text(secNow, "NOW IN TOWN", { Name = "PhoneNowHeader", Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1, Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Left })
		phone.blurb = UI.text(secNow, "", { Name = "PhoneBlurb", Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 2, TextSize = 14, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Left })
		phone.rows = {}
		for i = 1, 3 do
			-- THE ROW IS A STACK, NOT A LINE. Side by side on a 314px row the
			-- clue would get 174px and truncate a 60-character clue; stacked it
			-- gets 236 and fits in two lines.
			local row = pbox(secNow, "PhoneRow" .. i, UDim2.new(1, 0, 0, m.rowH), UDim2.new(), C.paper2, 14)
			row.LayoutOrder = 2 + i
			row.Visible = false
			local r = { frame = row }
			-- ZIndex 0: UNDER the GO holder, so GO keeps its own clicks, and
			-- under the labels, which consume nothing. Tapping anywhere else on
			-- the row does what GO does -- the CITY JOBS card's affordance, for
			-- three instances.
			r.tap = Instance.new("TextButton")
			r.tap.Name = "RowTap"
			r.tap.Text = ""
			r.tap.AutoButtonColor = false
			r.tap.BackgroundTransparency = 1
			r.tap.Size = UDim2.fromScale(1, 1)
			r.tap.ZIndex = 0
			r.tap.Parent = row
			r.tap.Activated:Connect(function()
				local ev = r.ev
				if not ev then return end
				if r.go and r.go.holder.Visible then E.go(ev) return end
				Audio.play("Click", 0.6, 0.5) -- the kit's dull refusal
				-- GO is hidden for two different reasons. A FIND you already
				-- claimed says "done -- nice one!" on the row and needs nothing
				-- more; an event with no address yet gets told so, in the line
				-- you are already reading.
				if not ev.mine and not ev.spot and not ev.hint then
					holdRow(ev, "no address yet -- follow the clues", C.coral, 1.2)
				end
			end)
			r.icon = UI.icon(row, "star", { Name = "RowIcon", Size = UDim2.fromOffset(m.iconSz, m.iconSz),
				Position = UDim2.fromOffset(10, m.iconY) })
			r.title = UI.text(row, "", { Name = "RowTitle", Size = UDim2.new(1, m.titleW, 0, m.titleH),
				Position = UDim2.fromOffset(m.textX, 10), Font = Enum.Font.FredokaOne, TextSize = m.titleTS,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			r.clock = UI.text(row, "", { Name = "RowClock", AnchorPoint = Vector2.new(1, 0),
				Size = UDim2.fromOffset(m.clkW, m.clkH), Position = UDim2.new(1, -12, 0, 10),
				Font = Enum.Font.FredokaOne, TextSize = m.clkTS, TextColor3 = C.coral,
				TextXAlignment = Enum.TextXAlignment.Right })
			r.clue = UI.text(row, "", { Name = "RowClue", Size = UDim2.new(1, m.clueW, 0, m.clueH),
				Position = UDim2.fromOffset(m.textX, m.clueY), TextSize = m.clueTS, TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true })
			-- TextTruncate is the second line of defence behind clampName
			r.count = UI.text(row, "", { Name = "RowCount", Size = UDim2.new(1, m.cntW, 0, m.cntH),
				Position = UDim2.fromOffset(m.textX, m.cntY), TextSize = m.cntTS, TextColor3 = C.inkSoft,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			r.go = UI.button(row, "GO", { size = UDim2.fromOffset(m.goW, m.goH), pos = UDim2.new(1, -12, 1, -10),
				anchor = Vector2.new(1, 1), color = C.mint, textSize = 18, icon = "pin", onClick = function()
					if r.ev then E.go(r.ev) end
				end })
			r.go.holder.Name = "RowGo"
			phone.rows[i] = r
		end
		phone.empty = UI.text(secNow, "Nothing on right now.\nKeep an eye out -- something always turns up.",
			{ Name = "PhoneEmpty", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 6, TextSize = 16,
				TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })

		-----------------------------------------------------------------------
		-- TODAY'S HUNT (LayoutOrder 50). The slot the phone reserved for phase
		-- D: above CITY NEWS (70), because the hunt is a standing objective a
		-- returning player opens the phone to read and news is history. At 30
		-- for news the section landed 74px below the fold; at 70 the whole 248
		-- -272px of it is visible with nothing else live.
		--
		-- Built ONCE, like the three event rows: refreshHunt only writes text,
		-- colour and Visible, and a whole day of hunting allocates no GUI.
		-----------------------------------------------------------------------
		local hm = UI.compact() and HUNT_M.compact or HUNT_M.desk
		hSec = phoneSection("Hunt", 50, 8)
		hSec.Visible = false
		local hHead = UI.text(hSec, "TODAY'S HUNT", { Name = "HuntHeader", Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1, Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Left })
		-- a second label inside the header's own 20px band rather than a second
		-- list row, so the count costs zero height
		hCount = UI.text(hHead, "0 / 3", { Name = "HuntCount", AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(54, 20), Position = UDim2.new(1, 0, 0, 0),
			Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
		hRows = {}
		for i = 1, 3 do
			local row = pbox(hSec, "HuntRow" .. i, UDim2.new(1, 0, 0, hm.rowH), UDim2.new(), C.paper2, 14)
			row.LayoutOrder = 1 + i
			local r = { frame = row }
			-- ZIndex 0, exactly as the event rows' own tap: under GO's holder so
			-- GO keeps its clicks, and under the labels, which consume nothing
			r.tap = Instance.new("TextButton")
			r.tap.Name = "HuntTap"
			r.tap.Text = ""
			r.tap.AutoButtonColor = false
			r.tap.BackgroundTransparency = 1
			r.tap.Size = UDim2.fromScale(1, 1)
			r.tap.ZIndex = 0
			r.tap.Parent = row
			r.tap.Activated:Connect(function() huntTap(i) end)
			r.badge = pbox(row, "HuntBadge", UDim2.fromOffset(hm.badge, hm.badge),
				UDim2.fromOffset(8, hm.badgeY), C.paper2, 11)
			r.badgeIcon = UI.icon(r.badge, "capsule", { Name = "HuntBadgeIcon",
				Size = UDim2.fromOffset(hm.bIcon, hm.bIcon), Position = UDim2.fromOffset(3, 3),
				ImageTransparency = 0.55 })
			r.clue = UI.text(row, "", { Name = "HuntClue", Size = UDim2.fromOffset(hm.clueW, hm.clueH),
				Position = UDim2.fromOffset(hm.clueX, hm.clueY), TextSize = hm.clueTS, TextColor3 = C.ink,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
				TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })
			r.go = UI.button(row, "GO", { size = UDim2.fromOffset(hm.goW, hm.goH),
				pos = UDim2.new(1, -10, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint,
				textSize = 18, onClick = function() huntGoTo(i) end })
			r.go.holder.Name = "HuntGo"
			r.go.holder.Visible = false
			hRows[i] = r
		end
		hReset = UI.text(hSec, "", { Name = "HuntReset", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 5,
			TextSize = hm.lineTS, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		hSocial = UI.text(hSec, "", { Name = "HuntSocial", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 6,
			TextSize = hm.lineTS, TextColor3 = C.sky, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Visible = false })
		hStreak = UI.text(hSec, "", { Name = "HuntStreak", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 7,
			TextSize = hm.lineTS, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })

		local secNews = phoneSection("News", 70, 6)
		UI.text(secNews, "CITY NEWS", { Name = "PhoneNewsHeader", Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1, Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Left })
		phone.news = UI.text(secNews, "", { Name = "PhoneNews", Size = UDim2.new(1, 0, 0, m.newsH),
			LayoutOrder = 2, TextSize = 13, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true })

		-- FOOTER: pinned, never scrolls. The collection hook is the one line on
		-- the phone that must not be able to scroll away.
		phone.div2 = pbox(screen, "PhoneDiv2", UDim2.new(1, 0, 0, 2),
			UDim2.fromOffset(0, m.feedY + m.feedH), C.paper2)
		phone.spotted = UI.text(screen, "", { Name = "PhoneSpotted", Size = UDim2.fromOffset(316, 20),
			Position = UDim2.fromOffset(14, m.spottedY), Font = Enum.Font.FredokaOne, TextSize = m.spottedTS,
			TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left })

		-- THE CHIN. Deeper than the forehead (58 vs 34) because that is where a
		-- toy handset's chunk lives, and because it gives the home bar a real
		-- 50px target -- 132x30 REAL pixels at the 0.6 compact scale floor.
		phone.homeBar = pbox(pface, "PhoneHomeBar", UDim2.fromOffset(132, 9),
			UDim2.fromOffset(122, m.shellH - 40), bezel, 5, 4)
		phone.homeHint = UI.text(pface, "tap the bar to close", { Name = "PhoneHomeHint",
			Size = UDim2.fromOffset(PHONE_W, 14), Position = UDim2.fromOffset(0, m.shellH - 26),
			Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.white, TextTransparency = 0.35,
			ZIndex = 4 })
		phone.homeTap = Instance.new("TextButton")
		phone.homeTap.Name = "PhoneHomeTap"
		phone.homeTap.Text = ""
		phone.homeTap.AutoButtonColor = false
		phone.homeTap.BackgroundTransparency = 1
		phone.homeTap.Size = UDim2.fromOffset(220, 50)
		phone.homeTap.Position = UDim2.fromOffset(78, m.shellH - 58)
		phone.homeTap.ZIndex = 5
		phone.homeTap.Parent = pface
		phone.homeTap.Activated:Connect(function() E.closePhone() end)

		-- THE CAPSULE PILL'S ONE BEHAVIOUR. The instances are City.lua's HUD
		-- furniture (H.capsule); what they do is phase D's, so the tap is
		-- connected here rather than there.
		if H.capsule and H.capsule.tap then
			H.capsule.tap.Activated:Connect(capTap)
		end
		renderCap()

		-- the compact variant. Read here and re-read on a viewport change; the
		-- city's H.layout hook is in another lane's file and this needs neither.
		applyTraySize()
		applyPhoneSize()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				applyTraySize()
				applyPhoneSize()
			end)
		end
	end

	-- GO lays the green path to the best place the client honestly knows
	-- about: the spot if it is open or revealed, the hint circle once someone
	-- has found it, otherwise nothing -- a hidden thing has no address yet
	--
	-- GO'S CONFIRMATION HAD NEVER RENDERED. UI.toast is UI.popText into UI.hud
	-- (UI.lua:832) and UI.hud.Visible is false in the city -- the city runs the
	-- "none" mode -- so both lines below used to be written to an invisible
	-- layer. They go to the notification corner instead, through
	-- City.Jobs.notify DIRECTLY rather than this module's notify(), because a
	-- path confirmation is not city news and must not fill the phone's feed.
	function E.go(ev)
		local target = ev.spot and V(ev.spot[1], 0, ev.spot[2]) or ev.hint and V(ev.hint[1], 0, ev.hint[2]) or nil
		if not target then
			-- and a refusal does NOT close the phone: it holds for 1.2s in the
			-- row's own count line, where you are already looking
			Audio.play("Click", 0.6, 0.5)
			holdRow(ev, "no address yet -- follow the clues", C.coral, 1.2)
			return
		end
		if City.Way and City.Way.to then City.Way.to(target, ev.def.title) end
		-- you pressed GO to go somewhere; staying in a menu after committing is
		-- friction, and on a phone it hands the thumbstick straight back
		E.closePhone()
		if City.Jobs and City.Jobs.notify then
			if ev.spot then
				City.Jobs.notify("pin", "PATH SET", ev.def.title .. " \u{00B7} follow the green dots", C.mintDark)
			else
				City.Jobs.notify("pin", "SEARCH THE AREA", "it was seen around " .. (ev.area or "here"), C.sky)
			end
		end
	end

	function E.refreshPhone()
		if not phone.rows then return end
		local m = phone.m or PHONE_M.desk
		local shown = {}
		for _, ev in E.list do
			if not ev.quiet then table.insert(shown, ev) end
		end
		table.sort(shown, function(a, b) return a.endT < b.endT end)
		for i, r in phone.rows do
			local ev = shown[i]
			r.ev = ev
			r.frame.Visible = ev ~= nil
			if ev then
				local t = now()
				local soon = t < ev.startT
				r.icon.Image = UI.Art and UI.Art.icons[ev.def.icon] or r.icon.Image
				r.title.Text = ev.def.title
				r.clock.Text = soon and ("in " .. clock(ev.startT - t)) or clock(ev.endT - t)
				r.clock.TextColor3 = soon and C.inkSoft or C.coral
				if ev.def.kind == "collect" then
					r.clue.Text = phoneClue(ev)
					r.count.Text = phoneCount(ev)
					r.count.TextColor3 = C.ink
				else
					r.clue.Text = ev.mine and "done -- nice one!" or latestClue(ev) or ev.area or ""
					r.count.Text = ev.found > 0 and ((ev.firstBy or "someone") .. " got there first \u{00B7} " .. ev.found .. " so far")
						or (ev.def.open and "nobody is there yet -- be first" or "nobody has found it yet")
					r.count.TextColor3 = C.inkSoft
				end
				r.go.holder.Visible = not ev.mine and (ev.spot ~= nil or ev.hint ~= nil)
				-- a 1.2s refusal, held in the line you are already reading. Tied
				-- to the event, because the endT sort can hand this row to a
				-- different event between ticks.
				if r.holdUntil and r.holdEv == ev and os.clock() < r.holdUntil then
					r.count.Text = r.holdText
					r.count.TextColor3 = r.holdColor
				end
			end
		end
		-- the rows and the empty line reflow through the UIListLayout, so 0 / 1 /
		-- 2 / 3 events each lay themselves out with no hole to leave behind
		phone.empty.Visible = #shown == 0
		if #shown == 0 then
			-- a failed sync used to be indistinguishable from a quiet city
			if E.syncFails >= 3 then
				phone.empty.Text = "can't reach the city right now.\nit'll catch up in a moment."
			elseif not E.synced then
				phone.empty.Text = "checking what's on..."
			else
				phone.empty.Text = "Nothing on right now.\nKeep an eye out -- something always turns up."
			end
		end
		local live = #shown
		if live == 0 then
			phone.blurb.Text = ""
		elseif live == 1 then
			phone.blurb.Text = "1 thing happening in the city"
		elseif live <= 3 then
			phone.blurb.Text = live .. " things happening in the city"
		else
			-- a fourth event used to be dropped silently
			phone.blurb.Text = "3 of " .. live .. " things happening in the city"
		end
		-- STATUS BAR. Two text writes per quarter second, and nothing invented:
		-- if Weather is not there yet, both labels hide rather than print a
		-- placeholder time.
		local wx = City.Weather and City.Weather.current and City.Weather.current()
		if wx and wx.clock then
			phone.clock.Text = wx.clock
			phone.clock.Visible = true
		else
			phone.clock.Visible = false
		end
		local st = wx and wx.state
		if st and st.name then
			phone.wx.Text = st.name
			phone.wx.Visible = true
			phone.wxIcon.Image = (UI.Art and UI.Art.icons[st.icon]) or phone.wxIcon.Image
			phone.wxIcon.Visible = true
		else
			phone.wx.Visible = false
			phone.wxIcon.Visible = false
		end
		local lines = {}
		for i = 1, math.min(m.newsLines, #E.news) do
			local n = E.news[i]
			table.insert(lines, "\u{2022} " .. n.title .. (n.sub ~= "" and (" -- " .. n.sub) or ""))
		end
		phone.news.Text = #lines > 0 and table.concat(lines, "\n") or "quiet so far"
		local n, total = spottedCount()
		phone.spotted.Text = "RARE SMINSKIS SPOTTED  " .. n .. " / " .. total
		-- TODAY'S HUNT (order 50). It hides itself when there is no hunt block,
		-- and the UIListLayout reflows with no hole left behind.
		refreshHunt()
	end

	---------------------------------------------------------------------------
	-- OPEN / CLOSE. phone.gen guards the delayed hide exactly as bigGen guards
	-- the finish line: a reopen during a close must not be killed by the
	-- outgoing timer.
	---------------------------------------------------------------------------
	phone.gen = 0
	function E.openPhone()
		if not phone.body then return end
		-- already up: refresh, do not re-tween
		if phone.open then E.refreshPhone() return end
		phone.gen += 1
		phone.open = true
		applyPhoneSize()
		phone.homeHint.Visible = phoneOpens < PHONE_HINTS
		phoneOpens += 1
		E.refreshPhone() -- fill it BEFORE it is seen
		if phone.slide then phone.slide:Cancel() phone.slide = nil end
		if phone.fade then phone.fade:Cancel() phone.fade = nil end
		if phone.tilt then phone.tilt:Cancel() phone.tilt = nil end
		-- reopening mid-close restarts from wherever the shell got to
		if not phone.shade.Visible then
			phone.body.Position = phone.hidden
			phone.body.Rotation = -3
			phone.shade.BackgroundTransparency = 1
			phone.shade.Visible = true
		end
		-- Quint: fast out of the gate, long soft landing. Back or Elastic would
		-- overshoot UPWARDS, off the top of a 530-tall canvas.
		phone.slide = UI.tween(phone.body, 0.26, { Position = phone.shown }, Enum.EasingStyle.Quint)
		-- the one toy flourish, on the one property that cannot leave the screen
		phone.tilt = UI.tween(phone.body, 0.30, { Rotation = 0 }, Enum.EasingStyle.Back)
		phone.fade = UI.tween(phone.shade, 0.20, { BackgroundTransparency = 0.72 })
		Audio.play("Whoosh", 1.25, 0.5)
	end
	-- instant: City.hudOff and E.leave(). A quarter second of phone over the
	-- title menu is visible, and a return trip must not start with one on screen.
	function E.closePhone(instant)
		if not phone.body then return end
		local wasOpen = phone.open or phone.shade.Visible
		phone.open = false
		phone.gen += 1
		local gen = phone.gen
		if phone.slide then phone.slide:Cancel() phone.slide = nil end
		if phone.fade then phone.fade:Cancel() phone.fade = nil end
		if phone.tilt then phone.tilt:Cancel() phone.tilt = nil end
		if instant or not wasOpen then
			phone.body.Position = phone.hidden
			phone.body.Rotation = 0
			phone.shade.BackgroundTransparency = 0.72
			phone.shade.Visible = false
			return
		end
		Audio.play("Whoosh", 0.85, 0.45)
		phone.slide = UI.tween(phone.body, 0.18, { Position = phone.hidden }, Enum.EasingStyle.Quart)
		phone.fade = UI.tween(phone.shade, 0.16, { BackgroundTransparency = 1 })
		-- 0.20 > the 0.18 slide, so the phone LEAVES rather than vanishes
		task.delay(0.20, function()
			if phone.gen ~= gen then return end
			phone.shade.Visible = false
			phone.shade.BackgroundTransparency = 0.72
			phone.body.Position = phone.hidden
			phone.body.Rotation = 0
		end)
	end

	---------------------------------------------------------------------------
	-- STEP
	---------------------------------------------------------------------------
	local lastUi = 0
	function E.step(dt, t, me)
		-- EVERY FRAME, BEFORE THE 0.25s GATE. City.hudVisible only sweeps Frame
		-- children of H.root and the phone's shade is a TextButton, so it is not
		-- swept -- and a quarter of a second of phone sitting over the title menu
		-- is plainly visible.
		if City.hudOff and phone.shade and (phone.open or phone.shade.Visible) then
			E.closePhone(true)
		end
		if not E.synced then E.sync() end
		local tn = now()
		local mp = flat(me)
		E.me = mp
		drawBudget = 6
		-- the Daily 3's models, three at most. World objects: no hudOff test.
		huntStep(t)
		for uid, ev in E.list do
			if tn >= ev.endT + 3 then
				-- the server's "end" should have removed it; never trust that
				undraw(ev)
				E.list[uid] = nil
				if liveEv == ev then liveEv = nil end
			elseif ev.def.kind == "collect" then
				stepCollect(ev, tn, t, mp)
			else
				if tn >= ev.startT and ev.spot and not ev.drawn and not (ev.mine and os.clock() - (ev.mineT or 0) > 3) then
					draw(ev)
				end
				if ev.drawn then
					ev.drawn.step(t, me)
					-- once it is yours it celebrates for a moment and goes
					if ev.mine and os.clock() - (ev.mineT or 0) > 3 then undraw(ev) end
				end
				-- clues unlock on the shared clock; announce each one once
				local unlocked = 0
				for _, c in ev.clues or {} do
					if tn >= c.t then unlocked += 1 end
				end
				if unlocked > ev.cluesShown then
					if ev.cluesShown > 0 and not ev.mine and ev.clues[unlocked] then
						notify(ev.def.icon, "NEW CLUE", ev.clues[unlocked].text, C.sky)
					end
					ev.cluesShown = unlocked
				end
			end
		end
		-- SELF-CORRECTING: the big line's own 4.2s timer cannot be trusted alone,
		-- because City.hudVisible(false) records it as "was visible" and
		-- hudVisible(true) would put a stale celebration back on screen.
		if bigHolder and bigHolder.Visible and os.clock() > bigUntil then
			bigHolder.Visible = false
		end
		if t - lastUi > 0.25 then
			lastUi = t
			local ev = headline()
			liveEv = ev
			if strip then
				strip.Visible = ev ~= nil and not City.hudOff
				if ev then
					sIcon.Image = UI.Art and UI.Art.icons[ev.def.icon] or sIcon.Image
					sTitle.Text = ev.def.title
					sSub.Text = stripSub(ev, tn < ev.startT)
					renderClock(ev, tn)
				end
			end
			renderTray(ev)
			-- the pill reads ctx.data on this same gate and writes only on
			-- change: no new timer and no task.spawn of its own
			renderCap()
			-- 5 MINUTES TO THE RESET, ONCE PER UTC DAY, and only while there is
			-- still something to find. Long enough to drive to a tier-3 spot,
			-- short enough not to nag.
			if hunt and hunt.day and huntWarnedDay ~= hunt.day then
				local left = (tonumber(hunt.ends) or 0) - os.time()
				if left > 0 and left <= 300 and huntMine() < 3 then
					huntWarnedDay = hunt.day
					notify("hourglass", "HUNT RESETS SOON", "new hiding places in 5 minutes", C.coral)
				end
			end
			if phone.shade and phone.shade.Visible then E.refreshPhone() end
		end
	end

	-- leaving the city: nothing of ours should be left standing in the world
	function E.leave()
		for _, ev in E.list do undraw(ev) end
		E.synced = false
		liveEv = nil
		E.me = nil
		fillEv = nil
		-- bump the generation so a delayed fade or hide cannot fire into the
		-- next visit's HUD
		bigGen += 1
		bigUntil = 0
		if tray then tray.Visible = false end
		if bigHolder then bigHolder.Visible = false end
		-- PHASE D. The hunt's models are ours to take home, and the pill's latch
		-- is cleared so a return trip re-latches from fresh data rather than
		-- showing the last visit's numbers.
		for i = 1, 3 do huntUndraw(i) end
		hunt = nil
		huntWarnedDay = nil
		huntBusy = false
		table.clear(huntSocial)
		table.clear(huntWarm)
		if hSec then hSec.Visible = false end
		capReset()
		E.closePhone(true)
	end

	do
		local folder = game:GetService("ReplicatedStorage"):WaitForChild("SminskiRemotes", 10)
		local ev = folder and folder:WaitForChild("CityEvent", 10)
		if ev then
			ev.OnClientEvent:Connect(function(kind, a, b)
				if kind == "start" then onStart(a, b)
				elseif kind == "end" then onEnd(a)
				elseif kind == "found" then onFound(a)
				elseif kind == "reveal" then onReveal(a)
				elseif kind == "progress" then onProgress(a)
				elseif kind == "taken" then onTaken(a)
				elseif kind == "done" then onDone(a)
				elseif kind == "reward" then onReward(a)
				-- PHASE D, ON ITS OWN KINDS. None of these may reuse "reveal":
				-- onReveal fabricates a whole sighting event for an unknown uid,
				-- so a hunt reveal on that kind would invent a phantom event in
				-- E.list, on the phone and on the strip.
				elseif kind == "ticket" then onTicket(a)
				elseif kind == "huntClues" then applyHunt(a, "clues")
				elseif kind == "huntFound" then onHuntFound(a)
				elseif kind == "huntReveal" then onHuntReveal(a)
				elseif kind == "huntHide" then onHuntHide(a)
				elseif kind == "huntReset" then applyHunt(a, "reset") end
			end)
		end
	end

	return E
end
