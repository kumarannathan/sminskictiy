-- City (client): Sminski City, a whole town in a valley between two big
-- mountains, through the arch in the bedroom wall. Walk or drive, say hi to
-- the townsfolk, and earn the same coins as everywhere else:
--   JOBS       deliveries, taxi fares, sweeping litter, farm fields, kart races
--   SPEND      cars at the dealer, businesses (they earn while you're away),
--              rides, the claw machine, and the main game's shops in the mall
-- The town streams in block by block (CityKit / CityBuild); the server only
-- checks the jobs and pays.
--   deps: Config, Models, UI, Audio, ctx, Places, Hub, player, call, getControls

return function(deps)
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local Config, Models, UI, Audio, ctx, Places = deps.Config, deps.Models, deps.UI, deps.Audio, deps.ctx, deps.Places
	local player = deps.player
	local camera = workspace.CurrentCamera
	local C = UI.C
	local CC = Config.City
	local CITY = Places.CITY
	local ROADS = Places.CityRoads
	local HALF = Places.CITY_HALF
	local here = script.Parent
	-- BOUNDED, AND LOUD. A bare WaitForChild here hung the whole client when
	-- the script tree was a step behind the sync (an Undo removed CityTycoon
	-- after it had been wired in): the city never loaded, nothing below the
	-- runner's require ran, and the player stood bodiless in the arcade. Ten
	-- seconds, then an error the runner's pcall turns into a toast.
	local function mod(name)
		local m = here:WaitForChild(name, 10)
		if not m then error("[City] module " .. name .. " is missing from SminskiRunner -- re-run _G.SR_sync()") end
		return m
	end
	local K = require(mod("CityKit"))({ Models = Models, UI = UI, Places = Places })
	local Build = require(mod("CityBuild"))({ K = K, Models = Models, Config = Config, Places = Places })
	-- kerb furniture, corner ponds, creek courtyards, traffic lights
	local Dress = require(mod("CityDress"))({ K = K, Build = Build, Places = Places })
	Build.dress, Build.courtyard, Build.signalsFn = Dress.block, Dress.courtyard, Dress.signals
	-- the corner map. Pure UI, no world state, so it is required like a kit.
	local Mini = require(mod("CityMinimap"))({ UI = UI, Places = Places })
	local V, rgb = K.V, K.rgb
	local part = Models.part
	local NEON, MATTE = K.NEON, K.MATTE

	local City = { active = false }
	local S = { -- runtime state (kept in one table: Luau caps locals per function)
		built = false, blocks = {}, loading = true, cullT = 0, loadT = 0,
		cityState = { litter = {}, plots = {}, cars = { convertible = true }, biz = {}, ripe = CC.RipeSeconds, now = os.time() },
		clockOffset = 0, litterModels = {}, pending = {}, cooldown = {},
		car = nil, camPos = nil, camLook = nil, sel = { kind = "convertible", color = 1 },
		ride = nil, race = nil, people = {}, traffic = {}, otherCars = {}, poses = {},
		exitArmed = false, lastCoins = nil, parkedDone = 0,
	}
	City.S, City.K, City.Build = S, K, Build

	---------------------------------------------------------------------------
	-- STREAMING: base first, then the nearest blocks, a few ms per frame
	---------------------------------------------------------------------------
	local function newBlock(b)
		local f = Instance.new("Folder")
		f.Name = b.kind .. " " .. b.cx .. "," .. b.cz
		b.folder = f
		b.visible = false
		b.done = false
		b.co = coroutine.create(function()
			K.cur = f
			b.run()
		end)
		table.insert(S.blocks, b)
	end
	function City.build()
		if S.built then return end
		S.built = true
		K.deadline = nil
		Build.base()
		for _, b in Build.blocks() do newBlock(b) end
		for _, b in Build.nature() do newBlock(b) end
	end
	-- give each finished block's parked cars a model
	local function spawnParked(folder)
		for i = S.parkedDone + 1, #Build.parked do
			local p = Build.parked[i]
			if not p.m then
				p.m = K.buildCar(p.kind, p.color, folder or K.actors)
				p.m:PivotTo(p.cf)
			end
		end
		S.parkedDone = #Build.parked
	end
	local function streamStep(me, budgetMs)
		local best, bd
		for _, b in S.blocks do
			if not b.done then
				local d = (V(b.cx, 0, b.cz) - me).Magnitude - (b.far and 300 or 0)
				if not bd or d < bd then best, bd = b, d end
			end
		end
		if not best then return true end
		K.deadline = os.clock() + budgetMs / 1000
		K.cur = best.cur or best.folder
		best.folder.Parent = K.root
		local ok, err = coroutine.resume(best.co)
		best.cur = K.cur
		K.deadline = nil
		if not ok then
			warn("[SminskiCity] block " .. best.kind .. " failed: " .. tostring(err) .. " :: " .. debug.traceback(best.co))
			best.done = true
		elseif coroutine.status(best.co) == "dead" then
			best.done = true
			best.visible = true
			spawnParked(best.folder)
		end
		K.cur = K.root
		return false
	end
	local function cull(me)
		for _, b in S.blocks do
			if b.done then
				local show = b.far or (V(b.cx, 0, b.cz) - me).Magnitude < 900
				if show ~= b.visible then
					b.visible = show
					b.folder.Parent = show and K.root or nil
				end
			end
		end
	end
	local function blockVisible(cx, cz, me, far)
		return far or (V(cx, 0, cz) - me).Magnitude < 700
	end

	---------------------------------------------------------------------------
	-- TOWNSFOLK: a pool of Sminskis that stroll the sidewalks near you
	---------------------------------------------------------------------------
	local LANES = {}
	for _, r in ROADS do
		table.insert(LANES, r - 27)
		table.insert(LANES, r + 27)
	end
	table.sort(LANES)
	local EDGE = LANES[#LANES]
	local OUTFITS = { false, false, "beanie", "bow", "scarf", "flowers", "party", "shades", "backpack", "sprout", "catears", "headband" }
	local function nearestOf(list, v)
		local best, bd = list[1], math.huge
		for _, l in list do if math.abs(l - v) < bd then best, bd = l, math.abs(l - v) end end
		return best
	end
	local function placePerson(n, me)
		n.axis = math.random() < 0.5 and "x" or "z"
		local tx, tz = me.X + math.random(-260, 260), me.Z + math.random(-260, 260)
		if n.axis == "x" then n.fixed, n.pos = nearestOf(LANES, tz), math.clamp(tx, -EDGE, EDGE)
		else n.fixed, n.pos = nearestOf(LANES, tx), math.clamp(tz, -EDGE, EDGE) end
		n.dir = math.random() < 0.5 and -1 or 1
		n.bpos = nil
	end
	local function buildPeople()
		local chars = Config.Characters
		for i = 1, 26 do
			local def = chars[math.random(1, math.min(#chars, 14))]
			local ok, rig = pcall(Models.buildSminski, K.actors, 1, def, false, OUTFITS[math.random(1, #OUTFITS)] or nil)
			if not ok then rig = Models.buildSminski(K.actors, 1, def, false, nil) end
			local n = { rig = rig, speed = math.random(45, 70) / 10, t0 = math.random() * 10, wait = 0, wave = 0, waved = -99 }
			if i % 3 == 0 then n.baby = Models.buildSminski(K.actors, 0.55, chars[math.random(1, math.min(#chars, 14))], false, math.random() < 0.5 and "bow" or nil) end
			if i % 4 == 1 then
				-- a crate of groceries: veg poking out the top
				local bag = Instance.new("Model")
				part(bag, V(2.2, 1.6, 1.6), CFrame.new(), rgb(214, 170, 120), K.WOODM)
				part(bag, V(0.9, 1.4, 0.9), CFrame.new(-0.5, 1, 0), K.C.leaf, MATTE, { mesh = Enum.MeshType.Sphere })
				part(bag, V(0.7, 0.7, 0.7), CFrame.new(0.5, 0.9, 0.2), rgb(236, 90, 90), MATTE, { shape = Enum.PartType.Ball })
				part(bag, V(0.5, 2.2, 0.5), CFrame.new(0.2, 1.3, -0.3) * CFrame.Angles(0, 0, 0.3), rgb(230, 190, 120), MATTE, { mesh = Enum.MeshType.Sphere })
				bag.WorldPivot = CFrame.new()
				bag.Parent = K.actors
				n.bag = bag
			end
			placePerson(n, Places.CitySpawn)
			table.insert(S.people, n)
		end
	end
	local function personPos(n)
		return n.axis == "x" and V(n.pos, 0, n.fixed) or V(n.fixed, 0, n.pos)
	end
	local function groundY(a, b) return (Build.isRoad(a) or Build.isRoad(b)) and 0 or K.PAD_Y end
	local function headingOf(n)
		return n.axis == "x" and (n.dir > 0 and -math.pi / 2 or math.pi / 2) or (n.dir > 0 and math.pi or 0)
	end
	local function stepPerson(n, dt, t, me)
		local p = personPos(n)
		if (p - me).Magnitude > 420 then placePerson(n, me) p = personPos(n) end
		if (p - me).Magnitude < 8 and t - n.waved > 14 then
			n.waved = t
			n.wave = 1.8
		end
		-- hang around for 2 seconds and they'll stop for a chat
		if (p - me).Magnitude < 9 then
			n.nearT = (n.nearT or 0) + dt
			if n.nearT >= 2 and t - (n.spoke or -99) > 10 then
				n.spoke = t
				n.wave = 4.5
				if City.npcSay then City.npcSay(n) end
			end
		else
			n.nearT = 0
		end
		if n.wave > 0 then
			n.wave -= dt
			local look = me - p
			Models.poseSminski(n.rig, CFrame.new(CITY + V(p.X, groundY(p.X, p.Z), p.Z)) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0), "cheer", t + n.t0)
		elseif n.wait > 0 then
			n.wait -= dt
			Models.poseSminski(n.rig, CFrame.new(CITY + V(p.X, groundY(p.X, p.Z), p.Z)) * CFrame.Angles(0, headingOf(n), 0), "idle", t + n.t0)
		else
			local nextPos = n.pos + n.dir * n.speed * dt
			local corner
			for _, c in LANES do
				if (n.pos - c) * (nextPos - c) <= 0 and math.abs(n.pos - c) > 0.001 then corner = c break end
			end
			if corner or math.abs(nextPos) > EDGE then
				local c = corner or (nextPos > 0 and EDGE or -EDGE)
				local roll = math.random()
				if math.abs(c) >= EDGE or roll < 0.35 then
					local old = n.fixed
					n.fixed = c
					n.pos = old
					n.axis = n.axis == "x" and "z" or "x"
					n.dir = math.abs(n.pos) >= EDGE and -math.sign(n.pos) or (math.random() < 0.5 and -1 or 1)
				elseif roll < 0.45 then
					n.pos = c
					n.wait = 1 + math.random() * 3
				else
					n.pos = nextPos
				end
			else
				n.pos = nextPos
			end
			local q = personPos(n)
			Models.poseSminski(n.rig, CFrame.new(CITY + V(q.X, groundY(q.X, q.Z), q.Z)) * CFrame.Angles(0, headingOf(n), 0), "run", t + n.t0, { stride = 5 + n.speed })
		end
		if n.bag then
			local q = personPos(n)
			n.bag:PivotTo(CFrame.new(CITY + V(q.X, groundY(q.X, q.Z), q.Z)) * CFrame.Angles(0, headingOf(n), 0) * CFrame.new(0, 2.4 + math.abs(math.sin(t * 6)) * 0.12, -1.3))
		end
		if n.baby then
			local q = personPos(n)
			local dir = n.axis == "x" and V(n.dir, 0, 0) or V(0, 0, n.dir)
			local want = q - dir * 2.8 + V(-dir.Z, 0, dir.X) * 2.2
			n.bpos = (n.bpos and (n.bpos - want).Magnitude < 20) and n.bpos:Lerp(want, math.min(1, dt * 5)) or want
			local moving = n.wait <= 0 and n.wave <= 0
			Models.poseSminski(n.baby, CFrame.new(CITY + V(n.bpos.X, groundY(n.bpos.X, n.bpos.Z), n.bpos.Z)) * CFrame.Angles(0, headingOf(n), 0), moving and "run" or (n.wave > 0 and "cheer" or "idle"), t * 1.4 + n.t0, { stride = 12 })
		end
	end

	---------------------------------------------------------------------------
	-- TRAFFIC: friendly cars on the road grid near you; they stop for you
	---------------------------------------------------------------------------
	local STEP = ROADS[2] - ROADS[1]
	local function roadIndex(v)
		for i, r in ROADS do if r == v then return i end end
		return nil
	end
	local function validDir(node, d)
		return roadIndex(node.X + d.X * STEP) ~= nil and roadIndex(node.Z + d.Z * STEP) ~= nil
	end
	local DIRS = { V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1) }
	-- TRAFFIC LIGHTS run off the server clock, so every player sees the same
	-- phase. North-south goes first, then east-west; neighbouring junctions
	-- are offset so a street is never all red at once.
	-- a 24s cycle: 9s green, 3s amber, 12s red
	local function lightState(node, alongX, now)
		local ph = (now + ((node.X // 300) * 7 + (node.Z // 300) * 11) % 24) % 24
		if alongX then ph = (ph + 12) % 24 end
		if ph < 9 then return "green" elseif ph < 12 then return "yellow" end
		return "red"
	end
	local function paintHead(hd, st)
		for name, bulb in hd do
			local lit = name == st
			bulb.Color = lit and Dress.LIGHT[name] or Dress.LIGHT.off
			bulb.Material = lit and NEON or Enum.Material.SmoothPlastic
		end
	end
	local function stepSignals(me, now)
		if not Build.signals then return end
		for _, sg in Build.signals do
			if math.abs(sg.x - me.X) < 420 and math.abs(sg.z - me.Z) < 420 then
				local node = V(sg.x, 0, sg.z)
				local ns, ew = lightState(node, false, now), lightState(node, true, now)
				if sg.lastNS ~= ns then sg.lastNS = ns for _, hd in sg.ns do paintHead(hd, ns) end end
				if sg.lastEW ~= ew then sg.lastEW = ew for _, hd in sg.ew do paintHead(hd, ew) end end
			end
		end
	end
	local function placeCar(c, me)
		c.from = V(nearestOf(ROADS, me.X + math.random(-500, 500)), 0, nearestOf(ROADS, me.Z + math.random(-500, 500)))
		c.dir = DIRS[math.random(1, 4)]
		c.s = math.random(0, STEP - 1)
		c.cf = nil
	end
	local function buildTraffic()
		local kinds = { "convertible", "van", "taxi", "convertible", "sports", "icecream", "convertible", "van" }
		for i = 1, 22 do
			local kind = kinds[i % #kinds + 1]
			local m, seat = K.buildCar(kind, K.CAR_COLORS[i % 8 + 1], K.actors)
			local c = { m = m, seat = seat, speed = 0, max = math.random(28, 40), kind = kind }
			c.driver = Models.buildSminski(K.actors, 1, Config.Characters[math.random(1, math.min(#Config.Characters, 10))], false, nil)
			placeCar(c, Places.CitySpawn)
			table.insert(S.traffic, c)
		end
		-- city buses: slower, longer, and they pull up for a few seconds
		-- on every block
		local BUS_COLS = { rgb(96, 150, 206), rgb(236, 130, 96), rgb(110, 176, 130), rgb(240, 196, 90) }
		for i = 1, 4 do
			local m = K.buildBus(BUS_COLS[i], "LINE " .. i, K.actors)
			local c = { m = m, seat = V(-1.8, 2.6, -9.4), speed = 0, max = 24, kind = "bus", dwell = 0 }
			c.driver = Models.buildSminski(K.actors, 1, Config.Characters[(i * 2) % math.min(#Config.Characters, 10) + 1], false, nil)
			placeCar(c, Places.CitySpawn)
			table.insert(S.traffic, c)
		end
	end
	local function stepCar(c, dt, t, me, cityPlayers)
		if not validDir(c.from, c.dir) then
			local opts = {}
			for _, d in DIRS do if validDir(c.from, d) then table.insert(opts, d) end end
			c.dir = opts[math.random(1, #opts)]
		end
		local right = V(-c.dir.Z, 0, c.dir.X)
		local lanePos = c.from + c.dir * c.s + right * 10
		if (lanePos - me).Magnitude > 800 then placeCar(c, me) return end
		local blocked, late = false, false
		local function check(p, reach)
			local rel = V(p.X - lanePos.X, 0, p.Z - lanePos.Z)
			local ahead = rel:Dot(c.dir)
			if ahead > 2 and ahead < reach and math.abs(rel:Dot(right)) < 6 then blocked = true end
		end
		for _, p in cityPlayers do check(p, 18) end
		for _, o in S.traffic do
			if o ~= c and o.cf then check(o.cf.Position - CITY, o.kind == "bus" and 26 or 18) end
		end
		-- someone on foot in the road: drivers DO brake, but late and not very
		-- hard -- stand still and they will stop short of you, step out in
		-- front of one and it cannot
		if S.onFoot and not blocked then
			check(S.onFoot, 15)
			late = blocked
		end
		-- red (or amber) at the junction ahead: hold at the stop line
		local st = lightState(c.from + c.dir * STEP, c.dir.X ~= 0, workspace:GetServerTimeNow())
		if st ~= "green" and c.s > STEP - 46 and c.s < STEP - 31 then blocked, late = true, false end
		-- buses pull up once per block
		if c.kind == "bus" then
			if c.dwell > 0 then
				c.dwell -= dt
				blocked, late = true, false
			elseif not c.stopped and c.s > STEP * 0.8 and c.s < STEP * 0.8 + 12 then
				c.stopped = true
				c.dwell = 3.5
			end
		end
		local target = blocked and 0 or c.max
		c.speed += (target - c.speed) * math.min(1, dt * (blocked and (late and 2.6 or 6) or 1.2))
		c.s += c.speed * dt
		if c.s >= STEP then
			c.from = c.from + c.dir * STEP
			c.s -= STEP
			c.stopped = false
			local straight, turns = nil, {}
			for _, d in { c.dir, V(-c.dir.Z, 0, c.dir.X), V(c.dir.Z, 0, -c.dir.X) } do
				if validDir(c.from, d) then
					if d == c.dir then straight = d else table.insert(turns, d) end
				end
			end
			if straight and (#turns == 0 or math.random() < 0.55) then c.dir = straight
			elseif #turns > 0 then c.dir = turns[math.random(1, #turns)]
			else c.dir = -c.dir end
			right = V(-c.dir.Z, 0, c.dir.X)
			lanePos = c.from + c.dir * c.s + right * 10
		end
		local want = CFrame.lookAt(CITY + lanePos, CITY + lanePos + c.dir)
		c.cf = c.cf and c.cf:Lerp(want, math.min(1, dt * 6)) or want
		c.m:PivotTo(c.cf)
		Models.poseSminski(c.driver, c.cf * CFrame.new(c.seat), "sit", t)
		-- and if you are under the bumper while it is still moving: you get hit
		if S.onFoot and c.speed > 12 and os.clock() > (S.hitUntil or 0) then
			local rel = V(S.onFoot.X - lanePos.X, 0, S.onFoot.Z - lanePos.Z)
			local bus = c.kind == "bus"
			if math.abs(rel:Dot(c.dir)) < (bus and 13 or 6.5) and math.abs(rel:Dot(right)) < (bus and 4.6 or 3.6) then
				City.knock(c.dir, c.speed)
			end
		end
	end
	-- knocked flying by traffic: a shove, a tumble, and a moment to get up
	function City.knock(dir, speed)
		local c = player and player.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end
		S.hitUntil = os.clock() + 2.6
		-- a seat pins you in place every frame; being hit gets you out of it
		if City.Venues then City.Venues.sitting = nil end
		if City.Home then City.Home.sitting = nil end
		hrp.AssemblyLinearVelocity = dir * math.clamp(speed * 1.5, 30, 70) + V(0, 42, 0)
		hum:ChangeState(Enum.HumanoidStateType.FallingDown)
		Audio.play("Bump", 0.9, 0.9)
		UI.toast("OUCH! look both ways!", C.coral)
		task.delay(1.3, function()
			if hum.Parent then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
		end)
	end

	---------------------------------------------------------------------------
	-- SERVER MIRROR
	---------------------------------------------------------------------------
	local lots = Places.cityLots()
	local marks = {}
	local function remote(action, arg)
		if not deps.call then return nil end
		local ok, res = pcall(deps.call, "City", action, arg)
		return ok and res or nil
	end
	-- some city screens have their own RemoteFunction rather than an action on
	-- the City one (the town roster reads every session, not just yours)
	-- FORWARD DECLARED. Defined with the rest of the business code far below,
	-- but the WORK screen up here needs it. Four bugs in this feature have now
	-- been "used above where it was declared", so it is worth saying plainly:
	-- in one Lua chunk, a `local function` is invisible to everything written
	-- before it.
	local bizWaiting
	local function remoteNamed(name, ...)
		if not deps.call then return nil end
		local ok, res = pcall(deps.call, name, ...)
		return ok and res or nil
	end
	local function beacon(name, pos, color)
		if marks[name] then marks[name]:Destroy() marks[name] = nil end
		if not pos then return end
		local m = Instance.new("Model")
		m.Name = name
		local base = CFrame.new(CITY + V(pos.X, K.PAD_Y, pos.Z))
		part(m, V(0.3, 14, 14), base * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, { shape = Enum.PartType.Cylinder, transparency = 0.35 })
		part(m, V(160, 7, 7), base * CFrame.new(0, 80, 0) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, { shape = Enum.PartType.Cylinder, transparency = 0.7 })
		m.Parent = K.actors
		marks[name] = m
	end
	-- ONE PIECE OF RUBBISH, ONE RECIPE, TWO CALLERS: the sweeping job's litter
	-- (applyState, just below) and City Cleanup's event items (CityEvents).
	-- `kind` picks the paper bag / can / flattened box, and the caller supplies
	-- the CFrame, so the two callers can place it however they like.
	--
	-- It returns the model AND its sparkle, because both callers need a handle
	-- on the sparkle. WorldPivot is set to `cf` so a model built at the origin
	-- and pooled can be PivotTo'd exactly (a Model with no PrimaryPart
	-- otherwise pivots around its bounding box centre, which is not `cf`).
	function City.litterModel(cf, kind)
		local m = Instance.new("Model")
		m.Name = "Litter"
		kind = (kind or 0) % 3
		if kind == 0 then
			part(m, V(1.6, 1.4, 1.6), cf, rgb(246, 244, 236), MATTE, { mesh = Enum.MeshType.Sphere })
			part(m, V(0.9, 1, 1), cf * CFrame.new(0.6, 0.2, 0.3), rgb(236, 232, 220), MATTE, { mesh = Enum.MeshType.Sphere })
		elseif kind == 1 then
			part(m, V(1.6, 0.8, 0.8), cf, ({ K.C.red, rgb(120, 180, 240), rgb(130, 210, 140) })[kind % 3 + 1], K.METAL, { shape = Enum.PartType.Cylinder })
		else
			part(m, V(2, 0.15, 1.3), cf * CFrame.new(0, -0.2, 0), rgb(255, 214, 120), MATTE)
			part(m, V(1.3, 0.16, 0.9), cf * CFrame.new(0.5, -0.15, 0.2) * CFrame.Angles(0, 0.7, 0), rgb(250, 250, 244), MATTE)
		end
		local sp = part(m, V(0.6, 0.6, 0.6), cf * CFrame.new(0, 1.8, 0), rgb(255, 250, 200), NEON, { shape = Enum.PartType.Ball })
		m.WorldPivot = cf
		return m, sp
	end
	local function applyState(cs)
		if not cs then return end
		S.cityState = cs
		if cs.now then S.clockOffset = cs.now - os.time() end
		local seen = {}
		for id, p in cs.litter or {} do
			seen[id] = true
			if not S.litterModels[id] then
				local n = tonumber(id) or 0
				local cf = CFrame.new(CITY + V(p[1], 0.35, p[2])) * CFrame.Angles(0, n * 1.3, 0)
				local m, sp = City.litterModel(cf, n % 3)
				m.Parent = K.actors
				S.litterModels[id] = { m = m, pos = V(p[1], 0, p[2]), sparkle = sp, cf = cf }
			end
		end
		for id, l in S.litterModels do
			if not seen[id] then
				l.m:Destroy()
				S.litterModels[id] = nil
			end
		end
		if City.Guide then City.Guide.onState(cs) end
		if City.Apts then City.Apts.onState(cs) end
		if City.Home then City.Home.onState(cs) end
		beacon("Job", cs.job and lots[cs.job.lot] and lots[cs.job.lot].door, rgb(255, 214, 110))
		beacon("Fare", cs.fare and Places.CityLandmarks[cs.fare.dest].pos, rgb(255, 236, 120))
	end

	---------------------------------------------------------------------------
	-- HUD
	---------------------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = "SminskiCityUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- (Global put the modal's dim layer over its own card)
	City.gui = gui
	local H = {}
	local function badgeRow(card, k, icon, title, col)
		local y = 48 + (k - 1) * 46
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(36, 36)
		badge.Position = UDim2.fromOffset(16, y)
		badge.BackgroundColor3 = col
		badge.Parent = card
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 10) cr.Parent = badge
		UI.icon(badge, icon, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(3, 3) })
		UI.text(card, title, { Size = UDim2.new(1, -76, 0, 18), Position = UDim2.fromOffset(62, y - 1), Font = Enum.Font.FredokaOne, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
		return UI.text(card, "", { Size = UDim2.new(1, -76, 0, 18), Position = UDim2.fromOffset(62, y + 18), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	do
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
			if H.layout then H.layout() end
		end
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		H.root = root
		H.rescale = rescale
		---------------------------------------------------------------------
		-- THE HUD BUTTONS.
		--
		--   RIGHT  getting around: the menu, home, the map, help, leaving.
		--   LEFT   the city's own things: your work, the shop, the town.
		--
		-- Splitting them that way means a thumb never has to hunt: anything
		-- that moves you is on one side, anything that opens a screen about
		-- the city is on the other.
		--
		-- SHOPS AND JOBS WERE TWO BUTTONS FOR ONE IDEA. Owning a pizzeria and
		-- looking for a shift are both "my work", so they are one WORK button
		-- that opens either -- which also buys back the row the menu needed.
		---------------------------------------------------------------------
		---------------------------------------------------------------------
		-- THE DOCK.
		--
		-- The split above is still the right idea -- things that move you on one
		-- side, things that open a screen on the other -- but it was expressed as
		-- two columns of 150x56 labelled buttons pinned to the left and right
		-- edges, and that is what makes a portrait phone impossible: 300px of the
		-- width is buttons before any of the game is drawn, and the left column
		-- lands exactly on the thumbstick.
		--
		-- One row of square icon tiles along the bottom keeps every entry point,
		-- costs 64px of height instead of 300px of width, and sits in the middle
		-- where neither thumb control lives. MENU and HELP leave the row: they
		-- are not about the city, so they go top-right with the other chrome.
		---------------------------------------------------------------------
		local dock = Instance.new("Frame")
		dock.Name = "Dock"
		dock.BackgroundTransparency = 1
		dock.AnchorPoint = Vector2.new(0.5, 1)
		dock.Size = UDim2.fromOffset(6 * 64 + 5 * 14, 84)
		dock.Parent = root
		H.dock = dock
		do
			local row = Instance.new("UIListLayout")
			row.FillDirection = Enum.FillDirection.Horizontal
			row.Padding = UDim.new(0, 14)
			row.HorizontalAlignment = Enum.HorizontalAlignment.Center
			row.VerticalAlignment = Enum.VerticalAlignment.Top
			row.SortOrder = Enum.SortOrder.LayoutOrder
			row.Parent = dock
		end
		-- A CELL, NOT A BUTTON. The label lives outside the button so it can sit
		-- on the world instead of on the tile -- a 64px tile with a word inside
		-- it leaves no room for the icon, and the icon is what makes a dock
		-- readable at a glance.
		local function tile(label, iconName, col, order, fn)
			local cell = Instance.new("Frame")
			cell.Name = label
			cell.BackgroundTransparency = 1
			cell.Size = UDim2.fromOffset(64, 84)
			cell.LayoutOrder = order
			cell.Parent = dock
			UI.button(cell, "", { size = UDim2.fromOffset(64, 64), color = col,
				icon = iconName, iconOnly = true, radius = 20, onClick = fn })
			UI.text(cell, label, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 66),
				Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.white, stroke = 1.5 })
			return cell
		end

		H.workBtn = tile("WORK", "chart", C.lav, 1, function() City.openWork() end)
		tile("SHOP", "bag", C.gold, 2, function() City.openStore() end)
		tile("TOWN", "friends", C.coral, 3, function() City.openTown() end)
		tile("PHONE", "bolt", C.sky, 4, function() if City.Events then City.Events.openPhone() end end)
		H.mapBtn = tile("MAP", "pin", C.mint, 5, function() City.toggleMap() end)
		tile("HOME", "house", C.paper2, 6, function()
			if City.Home then City.Home.guide() UI.toast("follow the glowing path home!", C.mintDark) end
		end)

		-- 56 square, not 56x52: the 44px touch floor is a floor, and a control
		-- that only clears it by 8 has nothing left when the canvas scale drops.
		H.helpBtn = UI.button(root, "", { size = UDim2.fromOffset(56, 56), color = C.paper2,
			icon = "star", iconOnly = true, onClick = function() if City.Guide then City.Guide.start() end end })
		H.menuBtn = UI.button(root, "", { size = UDim2.fromOffset(56, 56), color = C.paper2,
			icon = "gear", iconOnly = true, onClick = function()
			local ev = game:GetService("ReplicatedFirst"):FindFirstChild("SR_ShowMenu")
			if not ev then UI.toast("the title screen is not loaded", C.coral) return end
			-- put the game away before the menu climbs out over it, or the HUD
			-- sits on top of the title screen the whole time it is up
			City.hudVisible(false)
			if City.gui then City.gui.Enabled = false end
			if UI.gui then UI.gui.Enabled = false end
			ev:Fire()
		end })
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = C.paper
		pill.Size = UDim2.fromOffset(170, 48)
		pill.Parent = root
		UI.skin(pill, "pill", 24 / 80)
		UI.icon(pill, "coin", { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
		H.coins = UI.text(pill, "0", { Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(46, 0), Font = Enum.Font.FredokaOne, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		---------------------------------------------------------------------
		-- THE CAPSULE PILL (short loops phase D, docs/specs/daily-capsule).
		--
		-- 120x48 in the one free slot of the money row. The coin pill above is
		-- right-anchored at (1,-312) and 170 wide, so its right edge is
		-- canvasW-312; the nav column is 150 wide at (1,-24), so its left edge
		-- is canvasW-174. A 120-wide pill at (1,-184) anchored (1,0) therefore
		-- leaves 8px to the coins and 10px to MENU -- and because all three are
		-- right-anchored that is true at every canvas width. It cannot grow:
		-- 140 wide would land 12px inside the coin pill.
		--
		-- INSTANCES ONLY, AND ONE READER. Every number written into these, and
		-- every tween, pulse and tap, belongs to CityEvents -- that is where
		-- the meter's `ticket` push and the Daily 3 live. What has to be here
		-- is the HUD furniture and `H.cityData`, because the meter is published
		-- inside the ordinary save (publicData clones s.data, so data.City
		-- arrives with every reply that carries data) and ctx is City's.
		--
		-- A DIRECT Frame CHILD OF root, and `Visible` is latched exactly once
		-- by CityEvents and never written again, so City.hudVisible's
		-- record/restore sweeps it for free and cannot fight a per-tick writer.
		---------------------------------------------------------------------
		-- The 120x48 above is now just a size: H.layout below places it in a
		-- column, so the arithmetic the comment describes is no longer load-
		-- bearing. It cannot collide with the coin pill because it is stacked
		-- under it rather than squeezed beside it.
		local capHolder, capFace = UI.card(root, UDim2.fromOffset(150, 48), UDim2.new(), Vector2.new(0, 0), C.paper)
		capHolder.Name = "CapsulePill"
		capHolder.Visible = false
		H.capsule = { holder = capHolder, face = capFace }
		local cap = H.capsule
		cap.scale = Instance.new("UIScale")
		cap.scale.Name = "CapsuleScale"
		cap.scale.Parent = capHolder
		-- ZIndex >= 3 on every face child: UI.skin parents its two 9-slice
		-- images at the face's own ZIndex (the same reason H.district is 3).
		cap.icon = UI.icon(capFace, "capsule", { Name = "CapsuleIcon",
			Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(8, 8), ZIndex = 3 })
		cap.count = UI.text(capFace, "0", { Name = "CapsuleCount", Size = UDim2.fromOffset(30, 26),
			Position = UDim2.fromOffset(46, 3), Font = Enum.Font.FredokaOne, TextSize = 22,
			TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		cap.track = Instance.new("Frame")
		cap.track.Name = "CapsuleTrack"
		cap.track.Size = UDim2.fromOffset(66, 6)
		cap.track.Position = UDim2.fromOffset(46, 34)
		cap.track.BackgroundColor3 = C.paper2
		cap.track.BorderSizePixel = 0
		cap.track.ZIndex = 3
		cap.track.Parent = capFace
		local capCorner = Instance.new("UICorner")
		capCorner.CornerRadius = UDim.new(0, 3)
		capCorner.Parent = cap.track
		cap.fill = Instance.new("Frame")
		cap.fill.Name = "CapsuleFill"
		cap.fill.Size = UDim2.fromScale(0, 1)
		cap.fill.BackgroundColor3 = C.mint
		cap.fill.BorderSizePixel = 0
		cap.fill.ZIndex = 3
		cap.fill.Parent = cap.track
		capCorner = Instance.new("UICorner")
		capCorner.CornerRadius = UDim.new(0, 3)
		capCorner.Parent = cap.fill
		cap.tap = Instance.new("TextButton")
		cap.tap.Name = "CapsuleTap"
		cap.tap.Text = ""
		cap.tap.AutoButtonColor = false
		cap.tap.BackgroundTransparency = 1
		cap.tap.Size = UDim2.fromScale(1, 1)
		cap.tap.ZIndex = 6
		cap.tap.Parent = capFace
		-- the city half of the save, or nil until the first reply lands. Never
		-- invent a zero from it: a pill that cannot vouch for its number hides.
		H.cityData = function() return ctx.data and ctx.data.City or nil end
		local where = Instance.new("Frame")
		H.where = where
		where.BackgroundColor3 = C.paper
		where.Size = UDim2.fromOffset(320, 52)
		where.Parent = root
		UI.skin(where, "pill", 30 / 80)
		H.district = UI.text(where, "SMINSKI CITY", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 6), Font = Enum.Font.FredokaOne, TextSize = 24, ZIndex = 3 })
		H.street = UI.text(where, "", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 32), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.inkSoft, ZIndex = 3 })
		-----------------------------------------------------------------------
		-- THE MINIMAP. Built at a fixed 150: it is the one thing here that
		-- cannot be resized after the fact, because its pan maths is derived
		-- from the radius at build time (see CityMinimap.build).
		-----------------------------------------------------------------------
		local mini = Mini.build(root, 150, function() City.toggleMap() end)
		H.mini = mini
		-----------------------------------------------------------------------
		-- THE MISSION BAR. The thing you are working towards, on screen while
		-- you play rather than behind a tap. It is deliberately dumb: one line
		-- and one fill, written by City.setMission and by nothing else, so
		-- whatever owns the Daily 3 stays the only thing that knows the rules.
		-- It hides itself when there is nothing to say -- an empty progress bar
		-- is worse than no progress bar.
		-----------------------------------------------------------------------
		local mh, mcard = UI.card(root, UDim2.fromOffset(360, 48), UDim2.new(), Vector2.new(0.5, 1), C.paper)
		mh.Name = "MissionBar"
		mh.Visible = false
		H.mission = mh
		UI.icon(mcard, "star", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(8, 6), ZIndex = 3 })
		H.missionText = UI.text(mcard, "", { Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(50, 5),
			Font = Enum.Font.FredokaOne, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		H.missionCount = UI.text(mcard, "", { Size = UDim2.fromOffset(70, 22), Position = UDim2.new(1, -78, 0, 6),
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
		do
			local track = Instance.new("Frame")
			track.Size = UDim2.new(1, -60, 0, 7)
			track.Position = UDim2.fromOffset(50, 32)
			track.BackgroundColor3 = C.paper2
			track.BorderSizePixel = 0
			track.ZIndex = 3
			track.Parent = mcard
			local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 4) tc.Parent = track
			H.missionFill = Instance.new("Frame")
			H.missionFill.Size = UDim2.fromScale(0, 1)
			H.missionFill.BackgroundColor3 = C.gold
			H.missionFill.BorderSizePixel = 0
			H.missionFill.ZIndex = 4
			H.missionFill.Parent = track
			local fc = Instance.new("UICorner") fc.CornerRadius = UDim.new(0, 4) fc.Parent = H.missionFill
		end
		-- CITY JOBS: a card that folds down to its header. On a phone it starts
		-- folded (it was covering a fifth of the screen) and sits top-left,
		-- clear of the thumbstick; on a desktop it starts open, left-centre.
		local holder, card = UI.card(root, UDim2.fromOffset(300, 290), UDim2.new(0, 24, 0.5, -96), Vector2.new(0, 0), C.paper)
		H.jobs = holder
		card.ClipsDescendants = true
		UI.text(card, "CITY JOBS", { Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(18, 10), Font = Enum.Font.FredokaOne, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		local chev = UI.text(card, "▾", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -40, 0, 9), Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = C.inkSoft })
		local rowsF = Instance.new("Frame")
		rowsF.BackgroundTransparency = 1
		rowsF.Size = UDim2.fromScale(1, 1)
		rowsF.Parent = card
		H.rows = {
			badgeRow(rowsF, 1, "bag", "DELIVERIES", C.sky),
			badgeRow(rowsF, 2, "pin", "TAXI", C.gold),
			badgeRow(rowsF, 3, "coin", "TIDY UP", C.mint),
			badgeRow(rowsF, 4, "star", "FARM", C.mint),
			badgeRow(rowsF, 5, "chart", "MY BUSINESSES", C.lav),
		}
		do -- row 5 is the only tappable one: it opens the business card
			local y = 48 + 4 * 46
			local tapBiz = Instance.new("TextButton")
			tapBiz.Text = ""
			tapBiz.BackgroundTransparency = 1
			tapBiz.Size = UDim2.new(1, -12, 0, 44)
			tapBiz.Position = UDim2.fromOffset(6, y - 4)
			tapBiz.ZIndex = 6
			tapBiz.Parent = rowsF
			tapBiz.Activated:Connect(function()
				Audio.play("Click", 1.1, 0.6)
				City.openBiz()
			end)
			UI.text(rowsF, "\u{25B8}", { Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(266, y + 7), Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = C.inkSoft })
		end
		function H.setJobsOpen(open)
			H.jobsOpen = open
			rowsF.Visible = open
			chev.Text = open and "▾" or "▸"
			UI.tween(holder, 0.18, { Size = UDim2.fromOffset(open and 300 or 190, open and 290 or 52) })
		end
		local tap = Instance.new("TextButton")
		tap.Text = ""
		tap.BackgroundTransparency = 1
		tap.Size = UDim2.new(1, 0, 0, 52)
		tap.ZIndex = 5
		tap.Parent = card
		tap.Activated:Connect(function()
			H.setJobsOpen(not H.jobsOpen)
			Audio.play("Click", H.jobsOpen and 1.1 or 0.9, 0.6)
		end)
		local ph, prompt = UI.card(root, UDim2.fromOffset(470, 104), UDim2.new(0.5, 0, 1, -54), Vector2.new(0.5, 1), C.paper)
		ph.Visible = false
		H.prompt = ph
		H.pIcon = UI.icon(prompt, "star", { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(10, 10), ZIndex = 3 })
		H.pTitle = UI.text(prompt, "", { Size = UDim2.new(1, -270, 0, 34), Position = UDim2.fromOffset(100, 16), Font = Enum.Font.FredokaOne, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, ZIndex = 3 })
		H.pSub = UI.text(prompt, "", { Size = UDim2.new(1, -270, 0, 34), Position = UDim2.fromOffset(100, 52), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 3 })
		H.pBtn = UI.button(prompt, "GO", { size = UDim2.fromOffset(160, 62), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 20, onClick = function() City.doPrompt() end })
		local drive = Instance.new("Frame")
		drive.BackgroundTransparency = 1
		drive.AnchorPoint = Vector2.new(1, 1)
		drive.Size = UDim2.fromOffset(330, 150)
		drive.Position = UDim2.new(1, -24, 1, -24)
		drive.Parent = root
		H.drive = drive
		H.getOut = UI.button(drive, "GET OUT", { size = UDim2.fromOffset(160, 60), pos = UDim2.new(1, 0, 1, 0), anchor = Vector2.new(1, 1), color = C.lav, textSize = 20, onClick = function() City.exitCar() end })
		H.honk = UI.button(drive, "HONK", { size = UDim2.fromOffset(130, 60), pos = UDim2.new(1, -174, 1, 0), anchor = Vector2.new(1, 1), color = C.gold, textSize = 20, onClick = function() City.honk() end })
		H.myCar = UI.button(drive, "MY CAR", { size = UDim2.fromOffset(160, 60), pos = UDim2.new(1, 0, 1, 0), anchor = Vector2.new(1, 1), color = C.mint, textSize = 20, icon = "play", onClick = function() City.summonCar() end })
		H.speed = UI.text(drive, "", { AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(300, 40), Position = UDim2.new(1, 0, 1, -70), Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Right, stroke = 2 })
		H.raceText = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(600, 50), Position = UDim2.new(0.5, 0, 0, 96), Font = Enum.Font.FredokaOne, TextSize = 40, TextColor3 = C.white, stroke = 2 })
		H.hint = UI.text(root, "", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(800, 24), Position = UDim2.new(0.5, 0, 1, -14), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.white, stroke = 1 })
		-- COMPACT LAYOUT (phones, small windows). Buttons keep their size -- they
		-- are already at the limit of what a thumb can hit -- so the space comes
		-- from the information panels instead: the jobs card folds away, the
		-- place-name pill loses its second line, the prompt shrinks, keyboard
		-- hints go, and the driving buttons lift clear of Roblox's jump button.
		local promptScale = Instance.new("UIScale")
		promptScale.Parent = ph
		---------------------------------------------------------------------
		-- LAYOUT.
		--
		-- THIS RUNS ON EVERY RESCALE, not only when compact flips. The old
		-- version returned early unless compact changed, which was correct
		-- while every position was a constant: nothing depended on the canvas
		-- size, so there was nothing to recompute. Now everything does, and an
		-- early return would leave the HUD laid out for the previous window.
		-- Only setJobsOpen is still gated, because it tweens.
		--
		-- Read it top to bottom: it places four anchored groups and derives
		-- everything else from them.
		--   TOP-LEFT   minimap, then a column beside it (coins, capsule, place)
		--   TOP-RIGHT  help and menu -- the two things not about the city
		--   FLOOR      the lowest row we may use; the dock sits on it
		--   UP FROM IT prompt, mission, and whatever the drive bar needs
		---------------------------------------------------------------------
		function H.layout()
			local sa = UI.safe()
			local compact = UI.compact()
			local L, R, top = sa.side, sa.w - sa.side, sa.top

			mini.holder.Position = UDim2.fromOffset(L, top)
			local col = L + 150 + 14 -- the column to the right of the minimap

			pill.AnchorPoint = Vector2.new(0, 0)
			pill.Position = UDim2.fromOffset(col, top + 2)
			capHolder.AnchorPoint = Vector2.new(0, 0)
			capHolder.Position = UDim2.fromOffset(col, top + 56)

			where.AnchorPoint = Vector2.new(0, 0)
			where.Position = UDim2.fromOffset(col, top + 110)
			where.Size = UDim2.fromOffset(math.clamp(R - col - 128, 180, 320), compact and 42 or 52)
			H.street.Visible = not compact
			H.district.TextSize = compact and 19 or 24
			H.district.Position = UDim2.fromOffset(12, compact and 7 or 5)

			H.helpBtn.holder.AnchorPoint = Vector2.new(1, 0)
			H.helpBtn.holder.Position = UDim2.fromOffset(R - 66, top)
			H.menuBtn.holder.AnchorPoint = Vector2.new(1, 0)
			H.menuBtn.holder.Position = UDim2.fromOffset(R, top)

			-- WHERE THE SCREEN STOPS BEING OURS.
			--
			-- Roblox's touch controls are two boxes in the bottom CORNERS, not a
			-- band across the bottom. The first version of this treated them as
			-- a band, which on a landscape phone left 174 design pixels of usable
			-- height between the top bar and the "floor" -- the jobs card hung
			-- below it, the mission bar sat under the Roblox bar, and the place
			-- pill landed on the dock. The centre of the bottom edge is in fact
			-- free all the way down.
			--
			-- So the question is asked per column: what is the lowest row that
			-- content spanning x0..x1 may use?
			local function lowest(x0, x1)
				local y = sa.h - sa.bottom
				if x0 < sa.stick then y = math.min(y, sa.h - sa.bottom - sa.stick) end
				if x1 > sa.w - sa.jump then y = math.min(y, sa.h - sa.bottom - sa.jump) end
				return y
			end

			-- CENTRED IN THE FREE SPAN, NOT IN THE SCREEN.
			--
			-- A dock centred on the window is only centred between the two touch
			-- corners when the window is wide. On a short landscape phone its
			-- left edge clipped the thumbstick column by 27px, and because the
			-- rule above is "lift anything that overlaps a corner", 27px of
			-- overlap lifted the entire bottom stack 333px -- into the place
			-- pill. Sliding it 27px sideways costs nothing and keeps it down.
			--
			-- When the free span is genuinely too narrow (a portrait phone: the
			-- two corners nearly meet) there is nowhere to slide to, so it stays
			-- centred and lifts, which is the right answer there.
			local dockW = dock.Size.X.Offset
			local cx = sa.w / 2
			if sa.w - sa.stick - sa.jump >= dockW then
				cx = math.clamp(cx, sa.stick + dockW / 2, sa.w - sa.jump - dockW / 2)
			end
			local dockFloor = lowest(cx - dockW / 2, cx + dockW / 2)
			local dockTop = dockFloor - dock.Size.Y.Offset
			dock.Position = UDim2.fromOffset(cx, dockFloor)

			-- THE DRIVE BAR KEEPS ITS OWN CORNER. It is right-anchored, so the
			-- only touch control it can ever meet is the jump button -- ask for
			-- ITS column rather than assuming the dock's answer applies. (The
			-- version that stacked it above the mission bar on anything narrow
			-- threw away 350px of perfectly good screen on a small portrait
			-- phone and landed the bar on the place pill.) It only leaves the
			-- corner when the dock is actually in the way.
			local driveW, driveH = drive.Size.X.Offset, drive.Size.Y.Offset
			local driveY = lowest(R - driveW, R)
			local onDock = (R - driveW < cx + dockW / 2) and (R > cx - dockW / 2) and (driveY > dockTop)
			if onDock then driveY = dockTop - 10 end
			drive.AnchorPoint = Vector2.new(1, 1)
			drive.Position = UDim2.fromOffset(R, driveY)

			-- the prompt sits on whatever the bottom of the screen ended up being
			local stackTop = onDock and (driveY - driveH) or dockTop
			promptScale.Scale = compact and 0.84 or 1
			local promptBottom = stackTop - 10
			ph.AnchorPoint = Vector2.new(0.5, 1)
			ph.Position = UDim2.fromOffset(cx, promptBottom)

			-- HEADROOM: how far down a column may go, given everything already
			-- placed below it. lowest() only knows about Roblox's touch controls,
			-- and on a 320x568 phone the thing the left column actually collides
			-- with is our own prompt bar -- 250px above any touch control. The
			-- bottom stack is positioned first precisely so this can ask.
			local promptTop = promptBottom - 104 * promptScale.Scale
			local promptHalf = 470 * promptScale.Scale / 2
			local function headroom(x0, x1)
				local y = lowest(x0, x1)
				if x0 < cx + promptHalf and x1 > cx - promptHalf then
					y = math.min(y, promptTop - 10)
				end
				if x1 > R - driveW and x0 < R then
					y = math.min(y, driveY - driveH - 10)
				end
				return y
			end

			-- THE MISSION BAR LIVES WITH THE OTHER STATUS, not in the bottom
			-- stack. It started above the prompt, which put a fourth thing into
			-- the one strip that three things already compete for -- and on a
			-- small landscape phone it landed on the drive bar. Under the place
			-- pill it sits beside the coins and the capsule meter, which is
			-- where the eye already goes to ask "how am I doing", and the bottom
			-- of the screen stays for things you act on.
			local clusterBottom = top + 110 + where.Size.Y.Offset
			local mw = where.Size.X.Offset
			H.mission.AnchorPoint = Vector2.new(0, 0)
			H.mission.Size = UDim2.fromOffset(mw, 44)
			H.mission.Position = UDim2.fromOffset(col, clusterBottom + 8)
			-- read by City.setMission: a bar with nowhere to go stays hidden
			-- even when something asks for it
			H.missionRoom = (clusterBottom + 52) <= headroom(col, col + mw)
			if not H.missionRoom then H.mission.Visible = false end

			-- WHAT YIELDS WHEN IT DOES NOT ALL FIT.
			--
			-- On a 320x568 phone there is not room for the minimap column, the
			-- jobs card, the mission bar, the prompt, the drive bar and the dock
			-- at once, and pretending otherwise is how things end up on top of
			-- each other. Two of them yield, in this order, because they are the
			-- two whose content is reachable another way:
			--
			--   the jobs card  -- a convenience panel; WORK opens the same thing
			--   the mission bar -- purely informational; MISSIONS still lists it
			--
			-- Nothing that is the only route to something ever yields. The jobs
			-- card also sits below the WHOLE left column rather than at a fixed
			-- offset, because the mission bar above it changes that column's
			-- height and a constant would have put them on top of each other.
			local jw = compact and 190 or 300
			local jh = compact and 52 or 290
			local leftBottom = math.max(top + 150, clusterBottom + (H.missionRoom and 52 or 0))
			holder.Position = UDim2.fromOffset(L, leftBottom + 10)
			holder.Visible = (leftBottom + 10 + jh) <= headroom(L, L + jw)
			if H.compact ~= compact then
				H.compact = compact
				H.setJobsOpen(not compact)
			end
			H.hint.Visible = not compact
			if H.boost then
				H.boost.AnchorPoint = Vector2.new(0.5, 0)
				H.boost.Position = UDim2.new(0.5, 0, 0, top + 2)
			end
		end
		rescale()
		local cur = Instance.new("Frame")
		cur.Size = UDim2.fromScale(1, 1)
		cur.BackgroundColor3 = rgb(196, 226, 246)
		cur.ZIndex = 50
		cur.Parent = gui
		H.curtain = cur
		local bh, bcard = UI.card(root, UDim2.fromOffset(340, 54), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0), C.paper)
		H.boost = bh
		H.layout() -- bh did not exist on the first call, so place it now
		bh.Visible = false
		H.boost = bh
		UI.icon(bcard, "x2", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 5), ZIndex = 3 })
		H.boostText = UI.text(bcard, "", { Size = UDim2.new(1, -58, 1, 0), Position = UDim2.fromOffset(54, 0), Font = Enum.Font.FredokaOne, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
		H.curtainText = UI.text(cur, "ARRIVING IN SMINSKI CITY...", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(700, 60), Font = Enum.Font.FredokaOne, TextSize = 42, TextColor3 = C.white, stroke = 2, ZIndex = 51 })
	end

	---------------------------------------------------------------------------
	-- MODALS: the dealer, the map
	---------------------------------------------------------------------------
	local function modalCard(w, h, title)
		local dim = Instance.new("TextButton")
		dim.Text = ""
		dim.AutoButtonColor = false
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.5
		dim.ZIndex = 20
		dim.Visible = false
		dim.Parent = H.root
		dim.Activated:Connect(function() dim.Visible = false end) -- tap outside to close
		local holder, card = UI.card(dim, UDim2.fromOffset(w, h), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), C.paper)
		holder.ZIndex = 21
		-- never bigger than the screen it opens on (see UI.fit)
		local fitScale = Instance.new("UIScale")
		fitScale.Parent = holder
		dim:GetPropertyChangedSignal("Visible"):Connect(function()
			if dim.Visible then fitScale.Scale = UI.fit(w, h) end
		end)
		local eat = Instance.new("TextButton") -- taps on the card don't close it
		eat.Text = ""
		eat.AutoButtonColor = false
		eat.BackgroundTransparency = 1
		eat.Size = UDim2.fromScale(1, 1)
		eat.ZIndex = 0
		eat.Parent = card
		UI.text(card, title, { Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(24, 14), Font = Enum.Font.FredokaOne, TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left })
		UI.button(card, "X", { size = UDim2.fromOffset(56, 52), pos = UDim2.new(1, -16, 0, 14), anchor = Vector2.new(1, 0), color = C.coral, textSize = 24, onClick = function() dim.Visible = false end })
		return dim, card
	end

	local dealer = { rows = {}, swatches = {} }
	do
		local dim, card = modalCard(760, 540, "SMINSKI MOTORS")
		dealer.shade = dim
		for i, car in CC.Cars do
			local y = 70 + (i - 1) * 62
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -40, 0, 54)
			row.Position = UDim2.fromOffset(20, y)
			row.BackgroundColor3 = C.paper2
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			UI.text(row, car.name, { Size = UDim2.fromOffset(260, 26), Position = UDim2.fromOffset(16, 4), Font = Enum.Font.FredokaOne, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			UI.text(row, car.desc .. "  ·  top speed " .. math.floor(car.speed * 1.1) .. " mph", { Size = UDim2.fromOffset(470, 20), Position = UDim2.fromOffset(16, 30), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
			local btn = UI.button(row, "", { size = UDim2.fromOffset(170, 46), pos = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 18, onClick = function()
				local owned = S.cityState.cars and S.cityState.cars[car.id]
				if owned then
					S.sel.kind = car.id
					City.refreshDealer()
					UI.toast(car.name .. " selected · tap MY CAR to drive it", C.mintDark)
				else
					task.spawn(function()
						local res = remote("buyCar", car.id)
						if res and res.ok then
							if res.data and ctx.setData then ctx.setData(res.data) end
							applyState(res.city)
							S.sel.kind = car.id
							Audio.play("BigChime", 1, 0.8)
							UI.toast("You bought the " .. car.name .. "!", C.gold)
						elseif res and res.reason then
							UI.toast(res.reason, C.coral)
						end
						City.refreshDealer()
					end)
				end
			end })
			dealer.rows[i] = { car = car, btn = btn }
		end
		UI.text(card, "PAINT", { Size = UDim2.fromOffset(100, 30), Position = UDim2.new(0, 24, 1, -56), Font = Enum.Font.FredokaOne, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		for i, col in K.CAR_COLORS do
			local b = Instance.new("TextButton")
			b.Text = ""
			b.Size = UDim2.fromOffset(40, 40)
			b.Position = UDim2.new(0, 110 + (i - 1) * 50, 1, -62)
			b.BackgroundColor3 = col
			b.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(1, 0) cr.Parent = b
			local st = Instance.new("UIStroke") st.Thickness = 0 st.Color = C.ink st.Parent = b
			b.Activated:Connect(function()
				S.sel.color = i
				City.refreshDealer()
			end)
			dealer.swatches[i] = st
		end
	end
	function City.refreshDealer()
		for _, r in dealer.rows do
			local owned = S.cityState.cars and S.cityState.cars[r.car.id]
			if owned then
				r.btn.setText(S.sel.kind == r.car.id and "SELECTED" or "SELECT")
				r.btn.setColor(S.sel.kind == r.car.id and C.gold or C.sky)
			else
				r.btn.setText("BUY " .. r.car.price)
				r.btn.setColor(C.mint)
			end
		end
		for i, st in dealer.swatches do st.Thickness = i == S.sel.color and 4 or 0 end
	end
	function City.openDealer()
		City.refreshDealer()
		dealer.shade.Visible = true
	end

	-- THE SMINSKI ARCADE (Main St): the cabinets are the way into the other
	-- game modes. The city is the world you live in; these are the games
	-- inside it, and finishing one puts you back on the street outside.
	local arcade = {}
	do
		local dim, card = modalCard(720, 520, "SMINSKI ARCADE")
		arcade.shade = dim
		UI.text(card, "pick a cabinet", { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(24, 56), TextSize = 18, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left })
		local CABS = {
			{ title = "THE BIG HOUSE", sub = "Endless Run", icon = "house", color = C.lav,
			  go = function() if ctx.startRunMap then ctx.startRunMap("house") end end },
			{ title = "SMINSKI DOLLHOUSE", sub = "Endless Run", icon = "star", color = C.mint,
			  go = function() if ctx.startRunMap then ctx.startRunMap("dollhouse") end end },
			{ title = "DOG PARK RUN", sub = "Endless Run", icon = "paw", color = C.gold,
			  go = function() if ctx.startRunMap then ctx.startRunMap("dogpark") end end },
			{ title = "DOG PARK SURVIVAL", sub = "last sminski alive wins", icon = "dog", color = C.coral,
			  go = function() if ctx.enterPark then ctx.enterPark() end end },
			{ title = "THE BEDROOM TABLE", sub = "shops · outfits · collection", icon = "bag", color = C.sky,
			  go = function() if ctx.exitCity then ctx.exitCity() end end },
		}
		for i, cab in CABS do
			local y = 92 + (i - 1) * 78
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -48, 0, 68)
			row.Position = UDim2.fromOffset(24, y)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			local ic = Instance.new("ImageLabel")
			ic.Size = UDim2.fromOffset(44, 44)
			ic.Position = UDim2.fromOffset(14, 12)
			ic.BackgroundTransparency = 1
			ic.Image = UI.Art.icons[cab.icon] or ""
			ic.ImageColor3 = cab.color
			ic.Parent = row
			UI.text(row, cab.title, { Size = UDim2.new(1, -240, 0, 26), Position = UDim2.fromOffset(72, 12), Font = Enum.Font.FredokaOne, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			UI.text(row, cab.sub, { Size = UDim2.new(1, -240, 0, 20), Position = UDim2.fromOffset(72, 38), TextSize = 16, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(row, "PLAY", { size = UDim2.fromOffset(140, 50), pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5), color = cab.color, textSize = 20, onClick = function()
				dim.Visible = false
				cab.go()
			end })
		end
	end
	function City.openArcade()
		arcade.shade.Visible = true
	end

	-- THE TRAVEL PAD destination list. Every main place in town, one tap
	-- away from your own front door.
	local travel = {}
	do
		local dim, card = modalCard(720, 620, "TRAVEL")
		travel.shade = dim
		UI.text(card, "where to?", { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(24, 56), TextSize = 18, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left })
		local STOPS = {
			{ "HOME", "your house", "house", C.mint, function()
				return City.Home and City.Home.doorPos and City.Home.doorPos() or Places.CitySpawn
			end },
			{ "THE ARCADE", "runs · dog park · shops", "play", C.lav, Places.CityExit },
			{ "DOWNTOWN", "city hall · the towers", "pin", C.sky, Vector3.new(0, 0, -40) },
			{ "THE MALL", "shops · food court", "bag", C.gold, Places.MallShops[1].pos },
			{ "SMINSKI MOTORS", "buy a car", "star", C.coral, Places.CityDealer },
			{ "POST OFFICE", "pick up a parcel", "bag", C.sky, Places.CityDepot },
			{ "THE FUN PARK", "ferris wheel · karts", "trophy", C.gold, Places.CityRides.ferris },
			{ "THE FARM", "fields · gardens", "heart", C.mint, Vector3.new(-150, 0, 450) },
			{ "THE AIRPORT", "across the bay bridge", "pin", C.sky, Vector3.new(40, 4, 1752) },
		}
		for i, st in STOPS do
			local y = 92 + (i - 1) * 56
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -48, 0, 48)
			row.Position = UDim2.fromOffset(24, y)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 12) cr.Parent = row
			local ic = Instance.new("ImageLabel")
			ic.Size = UDim2.fromOffset(30, 30)
			ic.Position = UDim2.fromOffset(12, 9)
			ic.BackgroundTransparency = 1
			ic.Image = UI.Art.icons[st[3]] or ""
			ic.ImageColor3 = st[4]
			ic.Parent = row
			UI.text(row, st[1], { Size = UDim2.new(1, -210, 0, 22), Position = UDim2.fromOffset(54, 5), Font = Enum.Font.FredokaOne, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
			UI.text(row, st[2], { Size = UDim2.new(1, -210, 0, 18), Position = UDim2.fromOffset(54, 26), TextSize = 15, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left })
			local function dest()
				local d = st[5]
				if typeof(d) == "function" then d = d() end
				return d
			end
			-- WALK there (a green line along the streets) or JUMP there
			UI.button(row, "GUIDE", { size = UDim2.fromOffset(96, 38), pos = UDim2.new(1, -128, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 16, onClick = function()
				dim.Visible = false
				local d = dest()
				if d then City.Way.to(d, st[1]) end
			end })
			UI.button(row, "GO", { size = UDim2.fromOffset(110, 38), pos = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5), color = st[4], textSize = 18, onClick = function()
				dim.Visible = false
				local d = dest()
				if d then City.travel(d) end
			end })
		end
	end
	function City.openTravel()
		travel.shade.Visible = true
	end

	---------------------------------------------------------------------------
	-- THE SHOP. One place to spend Robux, reached from the bag button on the
	-- HUD: COINS (cash bundles), BOOSTS (skips and multipliers) and PASSES
	-- (the permanent ones). Everything here is a Roblox purchase; coins buy
	-- cars, homes and outfits elsewhere.
	--
	-- ANYTHING WITH ID 0 IS HIDDEN. Product and pass ids are created on the
	-- creator dashboard, not in code, so an unfilled entry must never show a
	-- button that cannot work -- it would prompt a purchase for asset 0 and
	-- fail in the player's face. An empty tab says so instead.
	---------------------------------------------------------------------------
	local Marketplace = game:GetService("MarketplaceService")
	local store = { tabs = {} }
	do
		local dim, card = modalCard(800, 640, "SHOP")
		store.shade = dim
		local tabRow = Instance.new("Frame")
		tabRow.BackgroundTransparency = 1
		tabRow.Size = UDim2.new(1, -48, 0, 46)
		tabRow.Position = UDim2.fromOffset(24, 72)
		tabRow.Parent = card
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, 10)
		lay.Parent = tabRow
		local pages, buttons = {}, {}
		local function show(id)
			for k, pg in pages do pg.Visible = k == id end
			for k, b in buttons do
				b.setColor(k == id and C.mint or C.paper2)
				b.face.TextColor3 = k == id and C.white or C.ink
			end
			store.tab = id
		end

		-- one row: art badge, name, blurb, optional flash, price button
		local function entry(page, i, o)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -16, 0, 100)
			row.Position = UDim2.fromOffset(0, (i - 1) * 110)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = page
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 16) cr.Parent = row
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(58, 58)
			badge.Position = UDim2.fromOffset(16, 21)
			badge.BackgroundColor3 = o.color
			badge.Parent = row
			local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 15) bc.Parent = badge
			UI.icon(badge, o.icon, { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(6, 6) })
			UI.text(row, o.name, { Size = UDim2.new(1, -270, 0, 26), Position = UDim2.fromOffset(88, 16),
				Font = Enum.Font.FredokaOne, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd })
			UI.text(row, o.blurb, { Size = UDim2.new(1, -274, 0, 42), Position = UDim2.fromOffset(88, 42),
				TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top })
			if o.flash then
				local f = Instance.new("Frame")
				f.Size = UDim2.fromOffset(136, 24)
				f.Position = UDim2.new(1, -16, 0, 10)
				f.AnchorPoint = Vector2.new(1, 0)
				f.BackgroundColor3 = o.flashColor or C.mintDark
				f.BorderSizePixel = 0
				f.Parent = row
				local fc = Instance.new("UICorner") fc.CornerRadius = UDim.new(0, 12) fc.Parent = f
				UI.text(f, o.flash, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne, TextSize = 13,
					TextColor3 = Color3.new(1, 1, 1) })
			end
			return UI.button(row, o.buy, { size = UDim2.fromOffset(152, 52), pos = UDim2.new(1, -16, 1, -12),
				anchor = Vector2.new(1, 1), color = o.color, textSize = 18, onClick = o.onClick })
		end

		local function page(id, label, order)
			local pg = Instance.new("ScrollingFrame")
			pg.Size = UDim2.new(1, -48, 1, -140)
			pg.Position = UDim2.fromOffset(24, 126)
			pg.BackgroundTransparency = 1
			pg.BorderSizePixel = 0
			pg.ScrollBarThickness = 6
			pg.ScrollBarImageColor3 = C.inkSoft
			pg.CanvasSize = UDim2.new()
			pg.Visible = false
			pg.Parent = card
			pages[id] = pg
			buttons[id] = UI.button(tabRow, label, { size = UDim2.fromOffset(160, 46), color = C.paper2,
				textColor = C.ink, textSize = 18, order = order, onClick = function() show(id) end })
			return pg
		end

		local function fill(pg, rows, empty)
			if #rows == 0 then
				UI.text(pg, empty, { Size = UDim2.new(1, -40, 0, 120), Position = UDim2.fromOffset(20, 40),
					TextSize = 16, TextColor3 = C.inkSoft, TextWrapped = true })
				return
			end
			for i, o in rows do entry(pg, i, o) end
			pg.CanvasSize = UDim2.fromOffset(0, #rows * 110)
		end

		local NOT_YET = "Nothing here yet.\n\nThese are created on the Roblox creator dashboard, then their ids go into Config.Products / Config.Passes. Until then they stay hidden rather than showing a button that cannot work."

		-- COINS
		do
			local rows = {}
			for _, pr in Config.Products do
				if pr.kind == "coins" and pr.productId ~= 0 then
					table.insert(rows, { name = pr.name, icon = pr.icon, color = pr.color,
						blurb = pr.desc or (UI.fmt(pr.coins) .. " coins, straight into your wallet."),
						flash = pr.badge, buy = "R$ " .. pr.robux,
						onClick = function() Marketplace:PromptProductPurchase(player, pr.productId) end })
				end
			end
			fill(page("coins", "COINS", 1), rows, NOT_YET)
		end

		-- BOOSTS (multipliers and skips: everything you buy again and again)
		do
			local rows = {}
			for _, pr in Config.Products do
				if pr.kind ~= "coins" and pr.productId ~= 0 then
					local blurb = pr.desc
					if not blurb and pr.kind == "boost" then
						blurb = pr.mult .. "x coins for " .. pr.minutes .. " minutes"
							.. (pr.scope == "server" and ", for everyone on this server." or ", just for you.")
					end
					table.insert(rows, { name = pr.name, icon = pr.icon, color = pr.color, blurb = blurb or "",
						flash = pr.scope == "server" and "WHOLE SERVER" or nil, flashColor = C.coral,
						buy = "R$ " .. pr.robux,
						onClick = function() Marketplace:PromptProductPurchase(player, pr.productId) end })
				end
			end
			fill(page("boosts", "BOOSTS", 2), rows, NOT_YET)
		end

		-- PASSES (bought once, kept forever)
		do
			local rows, btns = {}, {}
			for _, p in Config.Passes do
				if p.gamePassId ~= 0 then
					table.insert(rows, { name = p.name, icon = p.icon, color = p.color,
						blurb = table.concat(p.perks, " · "), buy = "R$ " .. p.robux, id = p.id,
						onClick = function()
							if ctx.data and ctx.data.Passes and ctx.data.Passes[p.id] then
								UI.toast("you already own " .. p.name, C.mintDark)
							else
								Marketplace:PromptGamePassPurchase(player, p.gamePassId)
							end
						end })
				end
			end
			local pg = page("passes", "PASSES", 3)
			if #rows > 0 then
				for i, o in rows do btns[o.id] = entry(pg, i, o) end
				pg.CanvasSize = UDim2.fromOffset(0, #rows * 110)
			else
				fill(pg, rows, NOT_YET)
			end
			store.passBtns = btns
		end
		store.show = show
		function City.storeTab() return store.tab end
	City.modalCard = modalCard
		show("coins")
	end

	function City.openStore(tab)
		if tab and store.show then store.show(tab) end
		-- owned passes read OWNED, so the screen never invites a second purchase
		for id, b in store.passBtns or {} do
			if ctx.data and ctx.data.Passes and ctx.data.Passes[id] then
				b.setText("OWNED  ✓")
				b.setColor(C.mintDark)
			end
		end
		store.shade.Visible = true
	end

	---------------------------------------------------------------------------
	-- THE TOWN DIRECTORY. Three ways of looking at the people on this server:
	-- where everyone lives, who owns which shop, and who is richest.
	--
	-- EVERY ROW GOES SOMEWHERE. A directory you can only read is a list; the
	-- point of this one is the VISIT button, which lays the wayfinding ribbon
	-- to somebody's actual front door. Knowing where the richest player lives
	-- is only interesting if you can go and look at their house.
	---------------------------------------------------------------------------
	local town = { rows = {} }
	do
		local dim, card = modalCard(760, 620, "TOWN")
		town.shade = dim
		local tabRow = Instance.new("Frame")
		tabRow.BackgroundTransparency = 1
		tabRow.Size = UDim2.fromOffset(510, 46)
		tabRow.Position = UDim2.fromOffset(24, 72)
		tabRow.Parent = card
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, 10)
		lay.Parent = tabRow
		local pages, buttons = {}, {}
		local function show(id)
			for k, pg in pages do pg.Visible = k == id end
			for k, b in buttons do
				b.setColor(k == id and C.mint or C.paper2)
				b.face.TextColor3 = k == id and C.white or C.ink
			end
			town.tab = id
			if town.fill then town.fill() end
		end
		town.show = show
		for i, t in { { "who", "NEIGHBOURS" }, { "shops", "SHOPS" }, { "rich", "RICHEST" } } do
			local pg = Instance.new("ScrollingFrame")
			pg.Size = UDim2.new(1, -48, 1, -140)
			pg.Position = UDim2.fromOffset(24, 126)
			pg.BackgroundTransparency = 1
			pg.BorderSizePixel = 0
			pg.ScrollBarThickness = 6
			pg.ScrollBarImageColor3 = C.inkSoft
			pg.CanvasSize = UDim2.new()
			pg.Visible = false
			pg.Parent = card
			pages[t[1]] = pg
			buttons[t[1]] = UI.button(tabRow, t[2], { size = UDim2.fromOffset(t[1] == "who" and 190 or 150, 46),
				color = C.paper2, textColor = C.ink, textSize = 18, order = i, onClick = function() show(t[1]) end })
		end

		-- one directory row: rank/badge, a heading, a line under it, a button
		local function line(pg, i, o)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -16, 0, 74)
			row.Position = UDim2.fromOffset(0, (i - 1) * 82)
			row.BackgroundColor3 = o.mine and C.mint:Lerp(C.white, 0.72) or C.paper2
			row.BorderSizePixel = 0
			row.Parent = pg
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			local chip = Instance.new("Frame")
			chip.Size = UDim2.fromOffset(46, 46)
			chip.Position = UDim2.fromOffset(14, 14)
			chip.BackgroundColor3 = o.color or C.lav
			chip.Parent = row
			local cc = Instance.new("UICorner") cc.CornerRadius = UDim.new(0, o.rank and 23 or 12) cc.Parent = chip
			if o.rank then
				UI.text(chip, tostring(o.rank), { Size = UDim2.fromScale(1, 1), Font = Enum.Font.FredokaOne,
					TextSize = 22, TextColor3 = C.white })
			else
				UI.icon(chip, o.icon or "friends", { Size = UDim2.fromOffset(38, 38), Position = UDim2.fromOffset(4, 4) })
			end
			UI.text(row, o.title, { Size = UDim2.new(1, -270, 0, 25), Position = UDim2.fromOffset(72, 12),
				Font = Enum.Font.FredokaOne, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd })
			UI.text(row, o.sub, { Size = UDim2.new(1, -274, 0, 32), Position = UDim2.fromOffset(72, 36),
				TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top })
			if o.right then
				UI.text(row, o.right, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(170, 30),
					Position = UDim2.new(1, -16, 0.5, 0), Font = Enum.Font.FredokaOne, TextSize = 22,
					TextColor3 = o.rightColor or C.gold, TextXAlignment = Enum.TextXAlignment.Right })
			elseif o.go then
				UI.button(row, "VISIT", { size = UDim2.fromOffset(130, 50), pos = UDim2.new(1, -14, 0.5, 0),
					anchor = Vector2.new(1, 0.5), color = C.sky, textSize = 18, icon = "pin", onClick = function()
						City.Way.to(V(o.go[1], 0, o.go[2]), o.goName)
						dim.Visible = false
					end })
			end
			return row
		end

		local function note(pg, txt)
			UI.text(pg, txt, { Size = UDim2.new(1, -60, 0, 130), Position = UDim2.fromOffset(30, 30),
				TextSize = 16, TextColor3 = C.inkSoft, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		end

		-- redraw whichever tab is showing from the last roster the server sent
		function town.fill()
			local pg = pages[town.tab or "who"]
			if not pg then return end
			for _, c in pg:GetChildren() do
				if not c:IsA("UIListLayout") then c:Destroy() end
			end
			local rows = town.roster
			if not rows then note(pg, "Asking the town hall...") return end
			local n = 0
			if town.tab == "shops" then
				for i, b in CC.Businesses do
					local owners = {}
					for _, r in rows do
						if table.find(r.biz, b.id) then table.insert(owners, r.me and "you" or r.name) end
					end
					line(pg, i, { icon = "chart", color = C.lav, title = string.upper(b.name),
						mine = table.find(owners, "you") ~= nil,
						sub = #owners == 0 and ("nobody here owns it yet \u{00B7} " .. b.price .. " coins")
							or (table.concat(owners, ", ") .. " \u{00B7} earns " .. b.rate .. "/min"),
						go = { Places.CityBiz[b.id].X, Places.CityBiz[b.id].Z }, goName = b.name })
					n = i
				end
			elseif town.tab == "rich" then
				local sorted = table.clone(rows)
				table.sort(sorted, function(a, b) return a.coins > b.coins end)
				for i, r in sorted do
					line(pg, i, { rank = i, color = i == 1 and C.gold or i == 2 and C.inkSoft or i == 3 and rgb(198, 140, 92) or C.sky,
						title = (r.vip and "\u{1F451} " or "") .. r.name .. (r.me and "  (you)" or ""),
						mine = r.me,
						sub = "level " .. r.level .. (#r.biz > 0 and (" \u{00B7} " .. #r.biz .. " shop" .. (#r.biz > 1 and "s" or "")) or "")
							.. (r.where and (" \u{00B7} " .. r.where.name) or ""),
						right = UI.fmt(r.coins) })
					n = i
				end
			else
				local sorted = table.clone(rows)
				table.sort(sorted, function(a, b)
					if a.me ~= b.me then return a.me end
					return a.name < b.name
				end)
				for i, r in sorted do
					line(pg, i, { icon = r.where and r.where.kind == "apt" and "house" or "house",
						color = r.vip and C.gold or C.mint,
						title = (r.vip and "\u{1F451} " or "") .. r.name .. (r.me and "  (you)" or ""),
						mine = r.me,
						sub = r.where and (r.where.name .. " \u{00B7} " .. r.where.sub) or "hasn't settled anywhere yet",
						go = r.door, goName = r.where and r.where.name or r.name })
					n = i
				end
			end
			if n == 0 then note(pg, "Nobody else is in town right now. This shows everyone on your server.") end
			pg.CanvasSize = UDim2.fromOffset(0, n * 82)
			town.count.Text = #rows .. (#rows == 1 and " Sminski in town" or " Sminskis in town")
		end
		town.count = UI.text(card, "", { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(190, 22),
			Position = UDim2.new(1, -24, 0, 84), TextSize = 14, TextColor3 = C.inkSoft,
			TextXAlignment = Enum.TextXAlignment.Right })
		show("who")
	end

	---------------------------------------------------------------------------
	-- WORK: one door to both halves of having a job -- the shops you own, and
	-- the shifts you can pick up. They were two HUD buttons for one idea.
	--
	-- It is a chooser rather than a merged screen because the two are genuinely
	-- different shapes: the business card is a live thing with bars filling in
	-- real time, and the Job Center is a catalogue you browse. Forcing them
	-- into one set of tabs would have made both worse.
	---------------------------------------------------------------------------
	do
		local dim, card = modalCard(560, 492, "WORK")
		City.workShade = dim
		UI.text(card, "", { Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(24, 66),
			TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		local sub = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(24, 66),
			TextSize = 14, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		City.workSub = sub
		UI.button(card, "MY SHOPS", { size = UDim2.fromOffset(470, 96), pos = UDim2.new(0.5, 0, 0, 110),
			anchor = Vector2.new(0.5, 0), color = C.lav, textSize = 26, icon = "chart", onClick = function()
				dim.Visible = false
				City.openBiz()
			end })
		UI.button(card, "FIND WORK", { size = UDim2.fromOffset(470, 96), pos = UDim2.new(0.5, 0, 0, 222),
			anchor = Vector2.new(0.5, 0), color = C.sky, textSize = 26, icon = "bag", onClick = function()
				dim.Visible = false
				local J = City.Jobs
				if J.found or (J.state and (J.state.tasks or 0) > 0) then
					J.open()
				else
					City.Way.to(Places.CityJobBoard, "the Job Center")
					UI.toast("the Job Center is downtown -- follow the green line", C.mintDark)
				end
			end })
		-- the third half: the restaurant you run (docs/TYCOON.md)
		UI.button(card, "MY RESTAURANT", { size = UDim2.fromOffset(470, 96), pos = UDim2.new(0.5, 0, 0, 334),
			anchor = Vector2.new(0.5, 0), color = C.coral, textSize = 26, icon = "heart", onClick = function()
				dim.Visible = false
				if City.Tycoon then City.Tycoon.open() end
			end })
	end
	function City.openWork()
		local owned, ready = 0, 0
		for _, b in CC.Businesses do
			local w, shift = bizWaiting(b)
			if w then owned += 1 if shift >= 1 then ready += 1 end end
		end
		local J = City.Jobs
		City.workSub.Text = (owned > 0 and (owned .. " shop" .. (owned > 1 and "s" or "")
			.. (ready > 0 and (" \u{00B7} " .. ready .. " ready to collect") or "")) or "no shops yet")
			.. "   \u{00B7}   " .. ((J.state and (J.state.rank .. " \u{00B7} " .. J.state.elo .. " rep")) or "find a career")
		City.workShade.Visible = true
	end

	---------------------------------------------------------------------------
	-- THE MISSION BAR'S ONLY WRITER.
	--
	-- Call with nothing to hide it. Call with a line and a pair of numbers to
	-- show what the player is working towards. This deliberately knows nothing
	-- about the Daily 3, weeklies or any other rule: whoever owns those rules
	-- stays the only thing that does, and gets one function to tell the HUD.
	--
	-- The hook: wherever the Daily 3 is refreshed (CityEvents), pick the first
	-- unfinished one and call City.setMission(it.label, it.have, it.need).
	---------------------------------------------------------------------------
	function City.setMission(label, have, need)
		if not H.mission then return end
		if not label or H.missionRoom == false then H.mission.Visible = false return end
		H.mission.Visible = true
		H.missionText.Text = label
		if have and need and need > 0 then
			H.missionCount.Text = ("%d/%d"):format(have, need)
			UI.tween(H.missionFill, 0.25, { Size = UDim2.fromScale(math.clamp(have / need, 0, 1), 1) })
		else
			H.missionCount.Text = ""
			H.missionFill.Size = UDim2.fromScale(0, 1)
		end
	end

	-- IS ANY CITY MODAL OPEN? The title screen needs to know when a screen it
	-- opened over the menu has been closed again, so it can fade the menu back.
	function City.anyModalOpen()
		for _, d in H.root:GetChildren() do
			if d:IsA("TextButton") and d.ZIndex == 20 and d.Visible then return true end
		end
		return false
	end
	-- Hide the HUD without hiding the whole gui, so a screen can be shown over
	-- the title menu without the city's buttons appearing behind it.
	--
	-- IT REMEMBERS WHAT IT HID. The first version just set every Frame in the
	-- HUD to Visible = on, which meant turning the HUD back on also revealed
	-- everything that was legitimately hidden -- the prompt card, the shift
	-- strip, and the welcome tour, which is why a blank tutorial card kept
	-- appearing after a transition.
	local hudHidden = {}
	function City.hudVisible(on)
		-- anything that decides its own visibility every tick (the event
		-- strip) has to be able to ask, or it just switches itself back on
		City.hudOff = not on
		if on then
			for _, d in hudHidden do
				if d.Parent then d.Visible = true end
			end
			table.clear(hudHidden)
		else
			-- DO NOT CLEAR THE RECORD ON THE WAY DOWN. Hiding is called twice
			-- in one ordinary flow: once by the HUD's MENU button, and again
			-- by the title when a menu option opens a screen over the menu.
			-- Clearing here meant the second call wiped the list and then
			-- found nothing still visible to re-record, so the list ended up
			-- empty and hudVisible(true) had nothing to put back -- the HUD
			-- never returned. Only the restore clears it.
			for _, d in H.root:GetChildren() do
				if d:IsA("Frame") and d.Visible then
					table.insert(hudHidden, d)
					d.Visible = false
				end
			end
		end
	end

	City.town = town
	function City.openTown(tab)
		town.shade.Visible = true
		if tab then town.show(tab) end
		task.spawn(function()
			local res = remoteNamed("Town")
			if res and res.ok then
				town.roster = res.rows
				town.fill()
			end
		end)
	end

	-- A VENUE'S MENU: four things, tap one. (CityVenues does the rest.)
	local menu = { rows = {} }
	do
		local dim, card = modalCard(520, 420, "MENU")
		menu.shade = dim
		menu.title = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.fromOffset(24, 56), TextSize = 18, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left })
		for i = 1, 4 do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -48, 0, 62)
			row.Position = UDim2.fromOffset(24, 92 + (i - 1) * 74)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			local name = UI.text(row, "", { Size = UDim2.new(1, -190, 1, 0), Position = UDim2.fromOffset(18, 0), Font = Enum.Font.FredokaOne, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(row, "ORDER", { size = UDim2.fromOffset(140, 46), pos = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 18, onClick = function()
				dim.Visible = false
				local v = menu.venue
				if v and v.menu[i] and City.Venues then City.Venues.order(v, v.menu[i]) end
			end })
			menu.rows[i] = { frame = row, name = name }
		end
	end
	function City.openMenu(v)
		menu.venue = v
		menu.title.Text = string.lower(v.name) .. " · on the house"
		for i, r in menu.rows do
			r.frame.Visible = v.menu[i] ~= nil
			r.name.Text = v.menu[i] or ""
		end
		menu.shade.Visible = true
	end

	local map = {}
	do
		local dim, card = modalCard(820, 600, "CITY MAP")
		map.shade = dim
		local area = Instance.new("Frame")
		area.Size = UDim2.fromOffset(500, 500)
		area.Position = UDim2.fromOffset(24, 70)
		area.BackgroundColor3 = rgb(176, 214, 146)
		area.Parent = card
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 16) cr.Parent = area
		local function toMap(x, z) return UDim2.fromOffset((x + HALF) / (2 * HALF) * 500, (HALF - z) / (2 * HALF) * 500) end
		map.toMap = toMap
		-- THREE LAYERS, all siblings of `area`: the district tiles (1), the road
		-- grid (2), the district names (3), and the player dots on top (5).
		-- The name used to be a CHILD of its tile, and the roads are built after
		-- the tiles, so every label sat under the grid. ZIndex on the label
		-- alone would not have fixed it: this GUI is ZIndexBehavior.Sibling
		-- (see :492), which keeps a subtree with its parent in the draw order,
		-- so a label inside a tile can never climb past the tile's siblings.
		-- It has to BE a sibling of the roads, which is why the labels are
		-- parented to `area` and positioned by hand.
		for _, d in Places.CityDistricts do
			local at = toMap(d.x0, d.z1)
			local w = (d.x1 - d.x0) / (2 * HALF) * 500
			local h = (d.z1 - d.z0) / (2 * HALF) * 500
			local f = Instance.new("Frame")
			f.BackgroundColor3 = d.color
			f.BackgroundTransparency = 0.25
			f.BorderSizePixel = 0
			f.Position = at
			f.Size = UDim2.fromOffset(w, h)
			f.ZIndex = 1
			f.Parent = area
			UI.text(area, string.upper(d.name), { Size = UDim2.fromOffset(w, 22), Position = at + UDim2.fromOffset(0, h / 2 - 11), ZIndex = 3, Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = C.ink })
		end
		for _, r in ROADS do
			for _, vert in { true, false } do
				local f = Instance.new("Frame")
				f.BackgroundColor3 = rgb(250, 246, 236)
				f.BorderSizePixel = 0
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Size = vert and UDim2.fromOffset(5, 470) or UDim2.fromOffset(470, 5)
				f.Position = vert and UDim2.fromOffset((r + HALF) / (2 * HALF) * 500, 250) or UDim2.fromOffset(250, (HALF - r) / (2 * HALF) * 500)
				f.ZIndex = 2
				f.Parent = area
			end
		end
		local function dot(col, size)
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Size = UDim2.fromOffset(size, size)
			f.BackgroundColor3 = col
			f.ZIndex = 5
			f.Parent = area
			local c2 = Instance.new("UICorner") c2.CornerRadius = UDim.new(1, 0) c2.Parent = f
			local st = Instance.new("UIStroke") st.Thickness = 2 st.Color = C.white st.Parent = f
			return f
		end
		map.me = dot(C.coral, 16)
		map.target = dot(rgb(255, 214, 90), 14)
		map.area, map.dot, map.others = area, dot, {}
		-- who's in town (tap a name or a dot to go and say hi)
		UI.text(card, "IN TOWN NOW", { Size = UDim2.fromOffset(240, 24), Position = UDim2.fromOffset(548, 552), Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left })
		map.count = UI.text(card, "", { Size = UDim2.fromOffset(250, 20), Position = UDim2.fromOffset(548, 572), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
		-- FAST TRAVEL lost 12px of button pitch to make room for the search box
		-- above it; seven buttons still land clear of IN TOWN NOW at y 552.
		local ftLabel = UI.text(card, "FAST TRAVEL", { Size = UDim2.fromOffset(240, 26), Position = UDim2.fromOffset(548, 118), Font = Enum.Font.FredokaOne, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
		local stops = { { name = "My House", home = true }, { name = "City Gate", pos = Places.CitySpawn + V(0, 0, 20) } }
		for _, d in Places.CityDistricts do table.insert(stops, { name = d.name, pos = d.stop }) end
		local stopBtns = {}
		for i, st in stops do
			stopBtns[i] = UI.button(card, string.upper(st.name), { size = UDim2.fromOffset(250, 48), pos = UDim2.fromOffset(548, 150 + (i - 1) * 56), color = ({ C.gold, C.mint, C.sky, C.coral, C.gold, C.lav, C.mint })[i], textSize = 16, onClick = function()
				if st.home then
					local i = player:GetAttribute("CityHouse")
					local l = i and lots[i]
					if l then City.travel(l.pos + V(math.sin(l.face), 0, math.cos(l.face)) * 20) end
				else
					City.travel(st.pos)
				end
				dim.Visible = false
			end })
		end

		-----------------------------------------------------------------------
		-- SEARCH. Fast travel is seven buttons, five of which are districts;
		-- the town has hundreds of named doors. Build.destinations has held
		-- every one of them since the blocks started streaming (name, btype,
		-- district, pos) and nothing ever read it. This reads it.
		--
		-- The results REPLACE the fast travel column while there is something
		-- in the box and hand it straight back when the box is empty, so the
		-- screen you have today is still the screen you get for free. They do
		-- not overlay it: a panel drawn on top of live buttons would leave
		-- those buttons clickable underneath, and tapping "DOWNTOWN" through a
		-- search result is exactly the kind of wrong-destination bug that is
		-- invisible until someone lands in the wrong district.
		-----------------------------------------------------------------------
		local RESULTS = 10 -- more than this and the list stops being a shortcut
		local box = Instance.new("TextBox")
		box.Size = UDim2.fromOffset(250, 42)
		box.Position = UDim2.fromOffset(548, 70)
		box.BackgroundColor3 = C.white
		box.Font = Enum.Font.GothamBold
		box.TextSize = 15
		box.Text = ""
		box.PlaceholderText = "search the city..."
		box.PlaceholderColor3 = C.inkSoft
		box.TextColor3 = C.ink
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextTruncate = Enum.TextTruncate.AtEnd
		box.ClearTextOnFocus = false -- default true; it would wipe a query you came back to refine
		box.BorderSizePixel = 0
		box.Parent = card
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 14) bc.Parent = box
		local bs = Instance.new("UIStroke") bs.Thickness = 2 bs.Color = C.ink bs.Transparency = 0.15 bs.Parent = box
		local bp = Instance.new("UIPadding") bp.PaddingLeft = UDim.new(0, 12) bp.PaddingRight = UDim.new(0, 12) bp.Parent = box
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.fromOffset(250, 416)
		list.Position = UDim2.fromOffset(548, 118)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = C.inkSoft
		list.CanvasSize = UDim2.new()
		list.Visible = false
		list.Parent = card
		-- ten rows built once and refilled, like menu.rows: a keystroke should
		-- not churn instances, and the map is stepped every frame while open.
		local hits, rows = {}, {}
		for i = 1, RESULTS do
			local row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = false
			row.Size = UDim2.fromOffset(236, 44)
			row.Position = UDim2.fromOffset(0, (i - 1) * 48)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Visible = false
			row.Parent = list
			local rc = Instance.new("UICorner") rc.CornerRadius = UDim.new(0, 12) rc.Parent = row
			local nm = UI.text(row, "", { Size = UDim2.fromOffset(212, 22), Position = UDim2.fromOffset(12, 3), Font = Enum.Font.FredokaOne, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			local sb = UI.text(row, "", { Size = UDim2.fromOffset(212, 16), Position = UDim2.fromOffset(12, 25), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			row.Activated:Connect(function()
				local h = hits[i]
				if not h then return end
				Audio.play("Click", 1.5, 0.5)
				-- d.pos is CITY-RELATIVE, the same space st.pos above is in, so
				-- it goes to City.travel untouched (travel adds CITY itself).
				-- Every writer agrees on this: the lot/apt/biz doors come out
				-- of Places in city space, and the mall unit at
				-- CityBuild.lua:2445 is the one built from a WORLD CFrame, so
				-- it is the one that subtracts CITY. Adding CITY here would
				-- put the mall 1500 studs out in the bay.
				City.travel(h.d.pos)
				dim.Visible = false
			end)
			rows[i] = { row = row, name = nm, sub = sb }
		end
		local note = UI.text(card, "", { Size = UDim2.fromOffset(250, 120), Position = UDim2.fromOffset(548, 150), TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, Visible = false })

		-- RANKING. Names repeat all over town (the same shop trades on twenty
		-- corners), so a bare name list would be ten identical rows. Sort by
		-- "starts with what you typed" first, then by how far it is from where
		-- you are standing, and label each row with its district and distance:
		-- the question behind the typing is almost always "where is the
		-- NEAREST one".
		local function fill()
			local q = string.match(string.lower(box.Text), "^%s*(.-)%s*$") or ""
			table.clear(hits)
			if q == "" then
				list.Visible = false
				note.Visible = false
				ftLabel.Visible = true
				for _, b in stopBtns do b.holder.Visible = true end
				map.searchPos = nil
				for _, r in rows do r.row.Visible = false end
				return
			end
			ftLabel.Visible = false
			for _, b in stopBtns do b.holder.Visible = false end
			list.Visible = true
			-- map.mePos is set by the step block below; it is nil only for the
			-- frame or two before the first step, hence the spawn fallback.
			local from = map.mePos or Places.CitySpawn
			for _, d in Build.destinations or {} do
				-- an unnamed or position-less entry cannot be searched or
				-- travelled to; both fields are optional for some writers
				if d.name and d.pos then
					local at = string.find(string.lower(d.name), q, 1, true)
					if at then
						table.insert(hits, { d = d, pre = at == 1 and 0 or 1, far = (V(d.pos.X, 0, d.pos.Z) - V(from.X, 0, from.Z)).Magnitude })
					end
				end
			end
			table.sort(hits, function(a, b)
				if a.pre ~= b.pre then return a.pre < b.pre end
				if a.far ~= b.far then return a.far < b.far end
				return a.d.name < b.d.name
			end)
			for i = #hits, RESULTS + 1, -1 do hits[i] = nil end
			for i, r in rows do
				local h = hits[i]
				r.row.Visible = h ~= nil
				if h then
					r.name.Text = string.upper(h.d.name)
					r.sub.Text = string.lower(h.d.district or h.d.btype or h.d.kind or "sminski city") .. "  \u{00B7}  " .. math.floor(h.far) .. " away"
				end
			end
			list.CanvasSize = UDim2.fromOffset(0, #hits * 48)
			list.CanvasPosition = Vector2.zero
			note.Visible = #hits == 0
			note.Text = "Nothing called that yet. The town fills in block by block as you get near it, so a place you have never been to may not be on the list until you are closer."
			-- the top hit gets the existing target pin, so the map and the
			-- list cannot disagree about where you are about to go
			map.searchPos = hits[1] and hits[1].d.pos or nil
		end
		box:GetPropertyChangedSignal("Text"):Connect(fill)

		-- KEYBOARD, which is the real trap here. The city's own keys (E, F, C,
		-- H, M) are live behind this modal, but Roblox flags keystrokes as
		-- gameProcessed while a TextBox holds focus, so the InputBegan handler
		-- at the bottom of this file already drops them and the default
		-- controls already stop walking the character -- WASD types, it does
		-- not drive. The price is that M cannot close the map mid-word; Enter
		-- and Escape both release the box, which hands M straight back, and
		-- closing the map by any route releases focus and empties the box (see
		-- below), so a hidden field can never sit there eating keys.
		--
		-- Enter also takes the top result, but ONLY where there is a real
		-- keyboard: on a phone the virtual keyboard's "done" reports
		-- enterPressed too, and a player who dismissed the keyboard would be
		-- teleported somewhere they never tapped.
		box.FocusLost:Connect(function(enter)
			if enter and not UIS.TouchEnabled and hits[1] then
				City.travel(hits[1].d.pos)
				dim.Visible = false
			end
		end)
		dim:GetPropertyChangedSignal("Visible"):Connect(function()
			if not dim.Visible then
				box:ReleaseFocus()
				box.Text = "" -- fires fill(), which restores FAST TRAVEL
			end
		end)
	end
	function City.toggleMap()
		map.shade.Visible = not map.shade.Visible
	end

	---------------------------------------------------------------------------
	-- DRIVING
	---------------------------------------------------------------------------
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	local TURN = 1.8
	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end
	local function carSpeed(kind)
		local def = Config.CityCar(kind)
		local base = def and def.speed or 72
		return base * (player and player:GetAttribute("CarMult") or 1)
	end
	local function dropParked(spot)
		local i = table.find(Build.parked, spot)
		if i then
			table.remove(Build.parked, i)
			S.parkedDone = math.max(0, S.parkedDone - 1)
		end
	end

	function City.enterCar(spot)
		local hrp, hum = myChar()
		if S.car or S.ride or not hrp or not hum then return end
		local kind = spot.kind or "convertible"
		if not (S.cityState.cars and S.cityState.cars[kind]) then kind = S.cityState.cars and S.cityState.cars[S.sel.kind] and S.sel.kind or "convertible" end
		-- you can only drive models you own: a borrowed car becomes yours
		if kind ~= spot.kind then
			local cf = spot.m:GetPivot()
			spot.m:Destroy()
			spot.m = K.buildCar(kind, spot.color, K.actors)
			spot.m:PivotTo(cf)
			spot.kind = kind
		end
		local cf = spot.m:GetPivot()
		local look = cf.LookVector
		local colorIndex = table.find(K.CAR_COLORS, spot.color) or 1
		S.car = { m = spot.m, kind = kind, color = colorIndex, seat = K.SEAT[kind], pos = cf.Position, v = 0, y = cf.Position.Y, yaw = math.atan2(-look.X, -look.Z), max = carSpeed(kind) }
		dropParked(spot)
		spot.m.Parent = K.actors
		hum.PlatformStand = true
		S.savedJump = hum.JumpHeight
		hum.JumpHeight = 0
		S.camPos, S.camLook = nil, nil
		Audio.play("Pop", 0.8, 0.8)
		task.spawn(remote, "drive", kind .. ":" .. colorIndex)
	end
	function City.exitCar()
		local car = S.car
		if not car then return end
		local hrp, hum = myChar()
		local cf = CFrame.new(car.pos) * CFrame.Angles(0, car.yaw, 0)
		table.insert(Build.parked, { m = car.m, cf = cf, kind = car.kind, color = K.CAR_COLORS[car.color] })
		S.parkedDone += 1
		S.car = nil
		if hum then
			hum.PlatformStand = false
			hum.JumpHeight = S.savedJump or 7
		end
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.CFrame = cf * CFrame.new(-(car.kind == "monster" and 8 or 5.5), 3.6, 0)
		end
		camera.CameraType = Enum.CameraType.Custom
		if hum then camera.CameraSubject = hum end
		if S.race then
			S.race = nil
			H.raceText.Text = ""
			task.spawn(remote, "raceQuit")
		end
		Audio.play("Pop", 1.1, 0.8)
		task.spawn(remote, "drive", nil)
	end
	-- call your selected car to your side
	function City.summonCar()
		local hrp = myChar()
		if S.car or S.ride or not hrp then return end
		local kind = S.sel.kind
		if not (S.cityState.cars and S.cityState.cars[kind]) then kind = "convertible" end
		local look = hrp.CFrame.LookVector
		local fl = V(look.X, 0, look.Z)
		if fl.Magnitude < 0.1 then fl = V(0, 0, -1) end
		fl = fl.Unit
		local pos = hrp.Position + fl * 8
		local g = workspace:Raycast(V(pos.X, CITY.Y + 40, pos.Z), V(0, -80, 0), groundParams)
		local gy = g and g.Position.Y or CITY.Y
		local cf = CFrame.lookAt(V(pos.X, gy, pos.Z), V(pos.X, gy, pos.Z) + fl)
		if S.summoned and S.summoned.m and S.summoned.m.Parent then
			dropParked(S.summoned)
			S.summoned.m:Destroy()
		end
		local m = K.buildCar(kind, K.CAR_COLORS[S.sel.color], K.actors)
		m:PivotTo(cf)
		local spot = { m = m, cf = cf, kind = kind, color = K.CAR_COLORS[S.sel.color] }
		S.summoned = spot
		Audio.play("Chime", 1.2, 0.6)
		City.enterCar(spot)
	end
	function City.honk()
		if not S.car then return end
		local p = S.car.kind == "monster" and 0.35 or S.car.kind == "sports" and 0.8 or 0.5
		Audio.play("Pop", p, 1)
		task.delay(0.12, function() Audio.play("Pop", p + 0.05, 1) end)
	end
	function City.travel(pos)
		if S.ride then return end
		if S.car then City.exitCar() end
		local hrp = myChar()
		if not hrp then return end
		-- every seat pins you to itself EVERY FRAME, so travelling while sat on
		-- a bench, a cafe stool or your own sofa would snap you straight back.
		-- One place to clear them all, because travel has four callers.
		if City.Venues then City.Venues.sitting = nil end
		if City.Apts then City.Apts.sitting = nil end
		if City.Home then City.Home.sitting = nil end
		if City.Roads then City.Roads.riding = nil end
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.new(CITY + pos + V(0, 3.4, 0))
		Audio.play("Whoosh", 1, 0.7)
		local d = Places.cityDistrictAt(pos)
		UI.toast("next stop: " .. (d and d.name or "the City Gate"), C.mintDark)
	end

	local function driveStep(dt, t)
		local car = S.car
		local hrp, hum = myChar()
		if not hrp then return end
		local controls = deps.getControls and deps.getControls()
		local mv = controls and controls:GetMoveVector() or Vector3.zero
		local th, st = -mv.Z, mv.X
		if mv.Magnitude < 0.05 and hum then
			-- the walk direction is camera-relative; the chase cam sits behind the car
			local md = hum.MoveDirection
			local camF = camera.CFrame.LookVector
			camF = V(camF.X, 0, camF.Z)
			if camF.Magnitude > 0.01 then
				camF = camF.Unit
				th, st = md:Dot(camF), md:Dot(V(-camF.Z, 0, camF.X))
			end
		end
		for _, inp in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if inp.KeyCode == Enum.KeyCode.ButtonR2 and inp.Position.Z > 0.1 then th = math.max(th, inp.Position.Z) end
			if inp.KeyCode == Enum.KeyCode.ButtonL2 and inp.Position.Z > 0.1 then th = math.min(th, -inp.Position.Z) end
		end
		local target = th > 0 and th * car.max or th < 0 and th * 24 or 0
		local braking = (th > 0 and car.v < -1) or (th < 0 and car.v > 1)
		local acc = braking and 110 or th ~= 0 and (car.kind == "sports" and 52 or 36) or 24
		if car.v < target then car.v = math.min(target, car.v + acc * dt) else car.v = math.max(target, car.v - acc * dt) end
		local grip = math.clamp(math.abs(car.v) / 16, 0, 1)
		car.yaw -= st * TURN * dt * grip * (car.v >= 0 and 1 or -1) * (car.kind == "sports" and 1.15 or 1)
		local fwd = V(-math.sin(car.yaw), 0, -math.cos(car.yaw))
		local step = fwd * car.v * dt
		if step.Magnitude > 0.001 then
			local sgn = car.v >= 0 and 1 or -1
			local reach = (car.kind == "van" or car.kind == "icecream") and 6.4 or 5.4
			for _, side in { -2.4, 0, 2.4 } do
				local o = car.pos + V(0, 2.4, 0) + fwd * sgn * reach + V(-fwd.Z, 0, fwd.X) * side
				local hit = workspace:Raycast(o, step + fwd * sgn * 0.6, rayParams)
				if hit then
					if math.abs(car.v) > 20 then Audio.play("Bump", 1.1, 0.7) end
					car.v = -car.v * 0.25
					step = Vector3.zero
					break
				end
			end
		end
		local rel = car.pos + step - CITY
		-- the world now reaches past the town square: the freeway runs outside
		-- it and the bridge goes out to the airport island
		rel = V(math.clamp(rel.X, -1010, 1010), 0, math.clamp(rel.Z, -(HALF - 14), 2130))
		-- look for ground from the car's OWN height, so it can climb a ramp and
		-- stay on a deck thirty studs up (it used to look from sea level only)
		local gHit = workspace:Raycast(V(CITY.X + rel.X, car.y + 9, CITY.Z + rel.Z), V(0, -26, 0), groundParams)
		if not gHit and (math.abs(rel.X) > HALF - 14 or rel.Z > HALF - 14) then
			-- nothing to drive on out here (open water, the edge of a deck): stop
			rel = V(car.pos.X - CITY.X, 0, car.pos.Z - CITY.Z)
			car.v = 0
			gHit = workspace:Raycast(V(car.pos.X, car.y + 9, car.pos.Z), V(0, -26, 0), groundParams)
		end
		local gy = gHit and gHit.Position.Y or CITY.Y
		car.y += (gy - car.y) * math.min(1, dt * 12)
		car.pos = V(CITY.X + rel.X, car.y, CITY.Z + rel.Z)
		local bob = math.sin(t * 9) * 0.04 * math.min(1, math.abs(car.v) / 20)
		local cf = CFrame.new(car.pos) * CFrame.Angles(0, car.yaw, 0) * CFrame.new(0, bob, 0)
		car.m:PivotTo(cf)
		hrp.CFrame = cf * CFrame.new(car.seat + V(0, 2.9, 0))
		hrp.AssemblyLinearVelocity = fwd * car.v
		camera.CameraType = Enum.CameraType.Scriptable
		local speedK = math.clamp(math.abs(car.v) / 110, 0, 1)
		local tall = car.kind == "monster" and 5 or (car.kind == "van" or car.kind == "icecream") and 2 or 0
		local want = (cf * CFrame.new(0, 9 + tall + speedK * 2, 20 + speedK * 8)).Position
		local look = (cf * CFrame.new(0, 3 + tall, -10)).Position
		S.camPos = S.camPos and S.camPos:Lerp(want, math.min(1, dt * 5)) or want
		S.camLook = S.camLook and S.camLook:Lerp(look, math.min(1, dt * 8)) or look
		camera.CFrame = CFrame.lookAt(S.camPos, S.camLook)
		camera.FieldOfView += ((70 + speedK * 16) - camera.FieldOfView) * math.min(1, dt * 3)
		H.speed.Text = math.floor(math.abs(car.v) * 1.1 + 0.5) .. " mph"
	end

	---------------------------------------------------------------------------
	-- RIDES: the ferris wheel + the carousel
	---------------------------------------------------------------------------
	function City.startRide(id)
		local hrp, hum = myChar()
		if not hrp or S.ride or S.car then return end
		hum.PlatformStand = true
		S.ride = { id = id, t = 0, dur = id == "ferris" and 48 or 24, back = hrp.CFrame }
		Audio.play("BigChime", 1.1, 0.7)
	end
	local function rideStep(dt, t)
		local r = S.ride
		local hrp, hum = myChar()
		if not hrp then S.ride = nil return end
		r.t += dt
		local seatCF
		if r.id == "ferris" and Build.ferris then
			local fw = Build.ferris
			if not r.g then
				local best, by
				for _, g in fw.gondolas do
					local y = g.m:GetPivot().Position.Y
					if not by or y < by then best, by = g, y end
				end
				r.g = best
			end
			seatCF = r.g.m:GetPivot() * CFrame.new(0, -5.2, 0)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(seatCF.Position + V(0, 6, -26), seatCF.Position + V(0, 2, 40))
		else
			local cc = CFrame.new(CITY + Places.CityRides.carousel + V(0, K.PAD_Y, 0))
			local a = t * 0.4 + 0.3
			seatCF = cc * CFrame.new(math.cos(a) * 15, 7.4 + math.sin(t * 2) * 1.2, math.sin(a) * 15) * CFrame.Angles(0, -a, 0)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(cc.Position + V(math.cos(a - 0.5) * 36, 14, math.sin(a - 0.5) * 36), seatCF.Position)
		end
		hrp.CFrame = seatCF * CFrame.new(0, 2.9, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		S.poses[player] = "sit"
		if r.t >= r.dur then
			S.ride = nil
			if hum then hum.PlatformStand = false end
			hrp.CFrame = r.back
			camera.CameraType = Enum.CameraType.Custom
			if hum then camera.CameraSubject = hum end
			UI.toast("what a ride!", C.mintDark)
		end
	end

	---------------------------------------------------------------------------
	-- PROMPTS + JOBS
	---------------------------------------------------------------------------
	local promptAction
	-- THE GREEN DOT: one small Smiski-green light that hovers over whatever you
	-- are close enough to use. It is the same green as the threshold mats, and
	-- it is the only thing in town that colour -- so "green = press E" is
	-- learned once and works everywhere (design.md, "interaction first").
	local dot = Instance.new("Part")
	dot.Name = "UseHere"
	dot.Shape = Enum.PartType.Ball
	dot.Size = V(1.5, 1.5, 1.5)
	dot.Color = K.OPEN
	dot.Material = NEON
	dot.Anchored, dot.CanCollide, dot.CanQuery, dot.CanTouch, dot.CastShadow = true, false, false, false, false
	dot.Transparency = 1
	dot.Parent = K.actors
	local halo = Instance.new("Part")
	halo.Name = "UseHalo"
	halo.Shape = Enum.PartType.Ball
	halo.Size = V(3.6, 3.6, 3.6)
	halo.Color = K.OPEN
	halo.Material = NEON
	halo.Anchored, halo.CanCollide, halo.CanQuery, halo.CanTouch, halo.CastShadow = true, false, false, false, false
	halo.Transparency = 1
	halo.Parent = K.actors
	local dotAt, dotOn = nil, 0
	function City.stepDot(dt, t)
		dotOn += ((dotAt and 1 or 0) - dotOn) * math.min(1, dt * 9)
		if dotOn < 0.02 then
			dot.Transparency, halo.Transparency = 1, 1
			return
		end
		local at = dotAt or dot.Position
		local bob = math.sin(t * 3.2) * 0.35
		dot.CFrame = CFrame.new(at + V(0, 3.4 + bob, 0))
		halo.CFrame = dot.CFrame
		dot.Transparency = 1 - dotOn
		halo.Transparency = 1 - dotOn * (0.24 + 0.1 * math.sin(t * 3.2))
		halo.Size = V(1, 1, 1) * (3.4 + math.sin(t * 3.2) * 0.5)
	end

	local function setPrompt(title, sub, btn, icon, action, at)
		dotAt = (title and btn) and at or nil
		if not title then
			H.prompt.Visible = false
			promptAction = nil
			return
		end
		H.prompt.Visible = true
		H.pTitle.Text = title
		H.pSub.Text = sub or ""
		H.pIcon.Image = UI.Art.icons[icon or "star"] or ""
		H.pBtn.holder.Visible = btn ~= nil
		if btn then H.pBtn.setText(btn) end
		promptAction = action
	end
	-- every prompt source hands its position through as the 6th value
	local function setPromptT(p) setPrompt(p[1], p[2], p[3], p[4], p[5], p[6]) end
	function City.doPrompt()
		if promptAction then promptAction() end
	end
	local function earned(res, what)
		if res and res.ok then
			if res.data and ctx.setData then ctx.setData(res.data) end
			if res.coins then
				if City.popCoins then City.popCoins(res.coins) end
				UI.toast(what, C.mintDark)
				Audio.play("Chime", 1.1 + math.random() * 0.1, 0.8)
			end
			applyState(res.city)
		elseif res and res.reason then
			UI.toast(res.reason, C.coral)
		end
	end
	local function act(key, action, arg, what, after)
		if S.pending[key] or (S.cooldown[key] and os.clock() < S.cooldown[key]) then return end
		S.pending[key] = true
		task.spawn(function()
			local res = remote(action, arg)
			S.pending[key] = nil
			if not (res and res.ok) then S.cooldown[key] = os.clock() + ((res and res.reason) and 2 or 0.3) end
			earned(res, what)
			if after then after(res) end
		end)
	end
	local function flat(v) return V(v.X, 0, v.Z) end
	local Home = require(mod("CityHome"))({
		K = K, Build = Build, Models = Models, UI = UI, Audio = Audio, ctx = ctx, Places = Places,
		player = player, remote = remote, earned = earned, City = City, S = S, H = H, gui = gui,
	})
	City.Home = Home
	-- cafes, bakeries, noodle bars: order, sit, eat
	local Venues = require(mod("CityVenues"))({
		K = K, Build = Build, Models = Models, UI = UI, Audio = Audio, Places = Places,
		S = S, player = player, City = City,
	})
	City.Venues = Venues
	-- the freeway, the bay bridge, The Elevated, the airport (Roads.lua)
	City.Roads = require(mod("CityRoads"))({
		K = K, Build = Build, Places = Places, Models = Models, Config = Config, UI = UI, Audio = Audio, S = S, player = player, City = City,
		Roads = require(game:GetService("ReplicatedStorage"):WaitForChild("SminskiShared"):WaitForChild("Roads")),
	})
	Build.roadsFn = City.Roads.build
	-- the sky: a 30-minute day and the weather over it (Weather.lua)
	local Weather = require(game:GetService("ReplicatedStorage"):WaitForChild("SminskiShared"):WaitForChild("Weather"))
	City.Weather = require(mod("CityWeather"))({
		K = K, Places = Places, Weather = Weather, UI = UI, player = player,
	})
	-- the soft green line along the street to wherever you said (CityWayfind)
	City.Way = require(mod("CityWayfind"))({
		K = K, Places = Places, Models = Models, UI = UI, Audio = Audio, player = player, City = City,
	})
	-- three places to be with other people, in the shared world (CityHangouts)
	City.Hang = require(mod("CityHangouts"))({
		K = K, Build = Build, Places = Places, Models = Models, UI = UI, Audio = Audio, S = S, player = player, City = City,
	})
	Build.hangout = City.Hang.build
	-- the city you can hear: positional traffic, rain, the sea, chatter
	City.Sound = require(mod("CitySound"))({
		K = K, Places = Places, Config = Config, player = player, City = City,
	})
	-- fixed things worth hearing, registered once
	City.Sound.register("sea", V(0, 0, 1040), 420)
	City.Sound.register("sea", V(-470, 0, 1400), 380)
	City.Sound.register("crowd", V(-750, 0, -190), 150)   -- the concert lawn
	City.Sound.register("crowd", V(450, 0, 150), 150)     -- the mall
	City.Sound.register("crowd", V(0, 0, -960), 150)      -- the arcade doors
	City.Sound.register("fire", V(-120, 0, 984), 130)     -- the boardwalk fire
	City.Sound.register("park", V(-450, 0, -450), 200)    -- Button Park
	City.Sound.register("park", V(-450, 0, 450), 220)     -- the orchard
	-- places to live: five buildings, five floor plans (CityApts)
	City.Apts = require(mod("CityApts"))({
		K = K, Build = Build, Places = Places, Config = Config, Models = Models, UI = UI, Audio = Audio,
		S = S, player = player, City = City, gui = gui, remote = remote, applyState = applyState, modalCard = modalCard,
	})
	-- SERVER-WIDE BOOST: the server tells everyone at once, and the banner
	-- names who paid for it, which is the whole point of buying one.
	do
		local ev = game:GetService("ReplicatedStorage"):WaitForChild("Boost", 10)
		if ev then
			ev.OnClientEvent:Connect(function(b)
				S.boost = b
				if b then
					UI.toast((b.who or "someone") .. " started " .. b.mult .. "x COINS for everyone!", C.gold)
					Audio.play("BigChime", 1.15, 0.8)
				end
			end)
		end
	end
	-- JOBS: the Job Center, the career browser and the shift strip; then the
	-- kitchen framework, which is what a restaurant job is actually played on
	City.Jobs = require(mod("CityJobs"))({
		K = K, UI = UI, Audio = Audio, Places = Places, Config = Config,
		City = City, S = S, H = H, player = player, remoteNamed = remoteNamed,
		setData = deps.setData,
	})
	City.Kitchen = require(mod("CityKitchen"))({
		K = K, UI = UI, Audio = Audio, Places = Places, Config = Config, Models = Models,
		Build = Build, City = City, Jobs = City.Jobs, S = S, player = player,
	})
	-- clocking out drops whatever order was in the air
	City.Jobs.onQuit = function() City.Kitchen.clear() end
	City.Jobs.init(H.root)
	-- THE SHORT LOOPS: server-wide events, the countdown strip and the phone
	-- (docs/LOOPS.md). After Jobs, because it speaks through Jobs.notify.
	City.Events = require(mod("CityEvents"))({
		K = K, UI = UI, Audio = Audio, Places = Places, Config = Config, Models = Models,
		Build = Build, City = City, S = S, H = H, player = player,
		remoteNamed = remoteNamed, earned = earned, modalCard = modalCard,
	})
	City.Events.init(H.root)
	-- GROCERIES: basket, till and fridge (docs/INVENTORY.md). After Venues,
	-- which owns the shelves' and the till's prompts and hands them here.
	City.Grocery = require(mod("CityGrocery"))({
		UI = UI, Audio = Audio, Config = Config, City = City, S = S, H = H, player = player,
		remote = remote, earned = earned, cityData = function() return ctx.data and ctx.data.City or nil end,
	})
	City.Grocery.init(H.root)
	-- RESTAURANT ROW: the tycoon (docs/TYCOON.md). After Kitchen (SERVE plays
	-- on its panel) and Grocery (the stockroom takes what the fridge holds).
	City.Tycoon = require(mod("CityTycoon"))({
		K = K, Build = Build, Models = Models, UI = UI, Audio = Audio, Places = Places, Config = Config,
		City = City, S = S, H = H, player = player, remoteNamed = remoteNamed, earned = earned,
		cityData = function() return ctx.data and ctx.data.City or nil end,
	})
	City.Tycoon.init(H.root)
	City.setJobsOpen = function(open) H.setJobsOpen(open) return H.jobsOpen end
	-- the welcome tour (first arrival, or HELP)
	City.Guide = require(mod("CityGuide"))({
		UI = UI, Audio = Audio, H = H,
		onDone = function()
			task.spawn(function()
				local res = remote("tourDone")
				if res and res.city then applyState(res.city) end
			end)
		end,
	})
	function bizWaiting(b)
		local since = S.cityState.biz and S.cityState.biz[b.id]
		if not since then return nil end
		local now = os.time() + S.clockOffset
		local ty = ctx.data and ctx.data.Passes and ctx.data.Passes.tycoon and Config.Pass("tycoon")
		local elapsed = (now - since) / 60
		local amount = math.floor(b.rate * (ty and ty.bizMult or 1) * math.min(elapsed, CC.CapMinutes * (ty and ty.bizCapMult or 1)))
		-- THE SHIFT. It fills over ShiftMinutes; only when it is full does the
		-- completion bonus come with the payout. Collect before then and you
		-- get exactly what is in the till, no more.
		local shift = math.clamp(elapsed / (CC.ShiftMinutes or 20), 0, 1)
		local bonus = shift >= 1 and math.floor(amount * (CC.ShiftBonus or 0)) or 0
		return amount, shift, bonus, elapsed
	end

	---------------------------------------------------------------------------
	-- THE BUSINESS CARD. Every shop in town on one page, each with its shift
	-- filling up in front of you.
	--
	-- YOU CAN ALWAYS TAKE THE MONEY. That is the point of the card -- there is
	-- no walking back to the shop, no "come back later", the COLLECT button is
	-- live from the first coin. What waiting buys you is the +50% at the end
	-- of the shift, so the bar is an offer rather than a lock.
	---------------------------------------------------------------------------
	local biz = { rows = {} }
	do
		local n = #CC.Businesses
		local dim, card = modalCard(720, n * 86 + 186, "MY BUSINESSES")
		biz.shade = dim
		biz.blurb = UI.text(card, "", { Size = UDim2.new(1, -48, 0, 36), Position = UDim2.fromOffset(24, 70),
			TextSize = 14, TextColor3 = C.inkSoft, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top })
		for i, b in CC.Businesses do
			local y = 112 + (i - 1) * 86
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -48, 0, 78)
			row.Position = UDim2.fromOffset(24, y)
			row.BackgroundColor3 = C.paper2
			row.BorderSizePixel = 0
			row.Parent = card
			local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 14) cr.Parent = row
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(46, 46)
			badge.Position = UDim2.fromOffset(14, 16)
			badge.BackgroundColor3 = C.lav
			badge.Parent = row
			local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 12) bc.Parent = badge
			UI.icon(badge, "chart", { Size = UDim2.fromOffset(38, 38), Position = UDim2.fromOffset(4, 4) })
			UI.text(row, string.upper(b.name), { Size = UDim2.new(1, -260, 0, 24), Position = UDim2.fromOffset(72, 10),
				Font = Enum.Font.FredokaOne, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
			local sub = UI.text(row, "", { Size = UDim2.new(1, -260, 0, 18), Position = UDim2.fromOffset(72, 32),
				TextSize = 12, TextColor3 = C.inkSoft, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			-- the shift bar
			local track = Instance.new("Frame")
			track.Size = UDim2.new(1, -332, 0, 10)
			track.Position = UDim2.fromOffset(72, 54)
			track.BackgroundColor3 = C.paper
			track.BorderSizePixel = 0
			track.Parent = row
			local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 5) tc.Parent = track
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(0, 1)
			fill.BackgroundColor3 = C.mint
			fill.BorderSizePixel = 0
			fill.Parent = track
			local fc = Instance.new("UICorner") fc.CornerRadius = UDim.new(0, 5) fc.Parent = fill
			local amt = UI.text(row, "", { Size = UDim2.fromOffset(120, 26), Position = UDim2.new(1, -168, 0, 12),
				AnchorPoint = Vector2.new(1, 0), Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = C.gold,
				TextXAlignment = Enum.TextXAlignment.Right })
			local note = UI.text(row, "", { Size = UDim2.fromOffset(120, 16), Position = UDim2.new(1, -168, 0, 40),
				AnchorPoint = Vector2.new(1, 0), Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = C.mintDark,
				TextXAlignment = Enum.TextXAlignment.Right })
			local btn = UI.button(row, "COLLECT", { size = UDim2.fromOffset(148, 54), pos = UDim2.new(1, -12, 0.5, 0),
				anchor = Vector2.new(1, 0.5), color = C.mint, textSize = 18, onClick = function()
					if bizWaiting(b) then
						act("collect" .. b.id, "collectBiz", b.id, b.name)
					else
						City.Way.to(Places.CityBiz[b.id], b.name)
						dim.Visible = false
					end
				end })
			biz.rows[i] = { def = b, sub = sub, fill = fill, amt = amt, note = note, btn = btn, row = row }
		end
		biz.all = UI.button(card, "COLLECT EVERYTHING", { size = UDim2.fromOffset(300, 54),
			pos = UDim2.new(0.5, 0, 1, -14), anchor = Vector2.new(0.5, 1), color = C.gold, textSize = 20, icon = "coin",
			onClick = function() act("collectAll", "collectAllBiz", nil, "your shops") end })
	end

	-- redrawn every frame the card is open, so a shift visibly fills
	function biz.refresh()
		local owned, ready, due = 0, 0, 0
		for _, r in biz.rows do
			local b = r.def
			local amount, shift, bonus = bizWaiting(b)
			if amount then
				owned += 1
				due += amount + bonus
				r.fill.Size = UDim2.fromScale(shift, 1)
				r.fill.BackgroundColor3 = shift >= 1 and C.gold or C.mint
				r.amt.Text = UI.fmt(amount + bonus)
				r.btn.setColor(C.mint)
				r.btn.setText("COLLECT")
				if shift >= 1 then
					ready += 1
					r.sub.Text = "shift finished · earns " .. b.rate .. "/min"
					r.note.Text = "+" .. math.floor((CC.ShiftBonus or 0) * 100) .. "% BONUS"
				else
					local left = math.max(0, (CC.ShiftMinutes or 20) * (1 - shift))
					r.sub.Text = string.format("%d/min · %d:%02d until the bonus", b.rate,
						math.floor(left), math.floor(left % 1 * 60))
					r.note.Text = ""
				end
			else
				r.fill.Size = UDim2.fromScale(0, 1)
				r.amt.Text = UI.fmt(b.price)
				r.note.Text = "TO BUY"
				r.sub.Text = "not yours yet · would earn " .. b.rate .. " coins a minute"
				r.btn.setColor(C.sky)
				r.btn.setText("SHOW ME")
			end
		end
		biz.blurb.Text = owned == 0
			and "You don't own a shop yet. Walk up to one in the Mall to buy it -- then it earns whether you are here or not."
			or (ready > 0 and (ready .. " shift" .. (ready > 1 and "s" or "") .. " finished -- collect now for the bonus")
				or "Collect any time. Let a shift finish and the payout comes with +" .. math.floor((CC.ShiftBonus or 0) * 100) .. "%.")
		biz.all.holder.Visible = owned > 0
		biz.all.setText(due > 0 and ("COLLECT EVERYTHING  " .. UI.fmt(due)) or "NOTHING TO COLLECT YET")
		biz.all.setColor(due > 0 and C.gold or C.paper2)
	end
	City.biz = biz
	function City.openBiz()
		biz.refresh()
		biz.shade.Visible = true
	end


	-- crop visuals: -1 empty, 0 seeds, 1 sprouts, 2 leafy, 3 ripe
	local VEG = { rgb(255, 150, 70), rgb(255, 140, 60), rgb(170, 220, 130), rgb(250, 110, 110) }
	local function setCrop(i, stage)
		local pm = Build.plotModels and Build.plotModels[i]
		if not pm or pm.stage == stage then return end
		pm.stage = stage
		pm.m:ClearAllChildren()
		if stage < 0 then return end
		local veg = VEG[(i - 1) % #VEG + 1]
		for r = -2, 2 do
			for k = -3, 3 do
				local cf = pm.cf * CFrame.new(k * 5, 0.9, r * 5.6)
				if stage == 0 then
					part(pm.m, V(0.6, 0.5, 0.6), cf, K.C.soil2, MATTE, { shape = Enum.PartType.Ball })
				elseif stage == 1 then
					part(pm.m, V(0.8, 1.6, 0.8), cf * CFrame.new(0, 0.8, 0), K.C.leaf2, MATTE, { mesh = Enum.MeshType.Sphere })
				else
					for q = 0, 2 do
						part(pm.m, V(1, 2.6, 1), cf * CFrame.new(math.cos(q * 2.1) * 0.6, 1.3, math.sin(q * 2.1) * 0.6) * CFrame.Angles(math.sin(q * 2.1) * 0.45, 0, math.cos(q * 2.1) * 0.45), stage == 3 and K.C.leaf3 or K.C.leaf, MATTE, { mesh = Enum.MeshType.Sphere })
					end
					if stage == 3 then part(pm.m, V(2.2, 1.8, 2.2), cf * CFrame.new(0, 0.7, 0), veg, MATTE, { mesh = Enum.MeshType.Sphere }) end
				end
			end
		end
	end

	-- the kart race: 3 laps through A -> B -> C -> the finish line
	local RACE_CPS = { V(-650, 0, 150), V(-750, 0, 200), V(-850, 0, 150), Places.RaceStart }
	local function raceStep(me)
		local r = S.race
		if not r then return end
		local el = os.clock() - r.t0
		H.raceText.Text = string.format("LAP %d/%d   %.1fs", math.min(r.lap, Places.RaceLaps), Places.RaceLaps, el)
		if (flat(me) - RACE_CPS[r.cp]).Magnitude < 32 then
			r.cp += 1
			if r.cp > #RACE_CPS then
				r.cp = 1
				r.lap += 1
				Audio.play("Chime", 1.3, 0.8)
				if r.lap > Places.RaceLaps then
					S.race = nil
					H.raceText.Text = string.format("FINISH!  %.2fs", el)
					act("raceFinish", "raceFinish", nil, "race", function(res)
						if res and res.ok then
							UI.toast(string.upper(res.medal or "") .. (res.record and "  ·  NEW RECORD!" or ""), C.gold)
						end
						task.delay(3, function() if not S.race then H.raceText.Text = "" end end)
					end)
				end
			end
		end
	end

	local function jobsTick(dt, t, me)
		local cs = S.cityState
		local truck = S.car and S.car.kind == "icecream"
		local reach = truck and 24 or S.car and 10 or 6
		local n = 0
		for id, l in S.litterModels do
			n += 1
			local d = (flat(me) - l.pos).Magnitude
			if d < 250 then
				l.sparkle.CFrame = l.cf * CFrame.new(0, 1.8 + math.sin(t * 3 + l.pos.X) * 0.3, 0)
				if d < reach then act("sweep" .. id, "sweep", id, "tidy town!") end
			end
		end
		H.rows[3].Text = n .. " bits of litter on the roads · +" .. CC.Sweep .. " each"
		local job = cs.job
		if job and lots[job.lot] then
			local lot = lots[job.lot]
			if (flat(me) - lot.door).Magnitude < 22 then act("deliver", "deliver", nil, "parcel delivered!") end
			H.rows[1].Text = "Deliver to " .. lot.address .. " · +" .. job.pay
		else
			H.rows[1].Text = "Pick up a parcel at the Post Office"
		end
		local fare = cs.fare
		if fare then
			local dest = Places.CityLandmarks[fare.dest]
			if S.car and (flat(me) - dest.pos).Magnitude < 36 then act("dropFare", "dropFare", nil, "thanks for the ride!") end
			H.rows[2].Text = "Drive your passenger to " .. dest.name .. " · +" .. fare.pay
		else
			H.rows[2].Text = "Passengers wait at the Taxi Stand downtown"
		end
		local ripe, growing = 0, 0
		local now = workspace:GetServerTimeNow()
		for i = 1, #Places.cityFarmPlots() do
			local t0 = cs.plots and cs.plots[tostring(i)]
			local stage = -1
			if t0 then
				local k = (now - t0) / (cs.ripe or 45)
				stage = k >= 1 and 3 or k >= 0.55 and 2 or k >= 0.2 and 1 or 0
				if stage == 3 then ripe += 1 else growing += 1 end
			end
			setCrop(i, stage)
		end
		H.rows[4].Text = ripe > 0 and (ripe .. " field" .. (ripe > 1 and "s" or "") .. " ready to harvest!") or growing > 0 and (growing .. " growing") or "Plant the city fields up north"
		local owned, waiting, ready = 0, 0, 0
		for _, b in CC.Businesses do
			local w, shift, bonus = bizWaiting(b)
			if w then
				owned += 1
				waiting += w + bonus
				if shift >= 1 then ready += 1 end
			end
		end
		H.rows[5].Size = UDim2.new(1, -104, 0, 18)
		H.rows[5].Text = owned == 0 and "Buy a shop in the Mall to earn while away"
			or (owned .. " owned · " .. waiting .. " waiting" .. (ready > 0 and (" · " .. ready .. " ready!") or "") .. "  (tap)")
		if biz.shade.Visible then biz.refresh() end
		local target = Home.target() or (fare and Places.CityLandmarks[fare.dest].pos) or (job and lots[job.lot] and lots[job.lot].door) or (S.race and RACE_CPS[S.race.cp])
		S.target = target
		if target and S.arrow then
			local dir = flat(target) - flat(me)
			if dir.Magnitude > 1 then
				local from = CITY + me + V(0, S.car and 11 or 8, 0)
				S.arrow:PivotTo(CFrame.lookAt(from, from + dir.Unit) * CFrame.new(0, math.sin(t * 4) * 0.25, 0))
				S.arrow.Parent = K.actors
			end
		elseif S.arrow then
			S.arrow.Parent = nil
		end
		raceStep(me)
	end

	local function near(me, spot, r) return (flat(me) - V(spot.X, 0, spot.Z)).Magnitude < r end
	local function promptTick(me)
		local cs = S.cityState
		if S.ride then setPrompt(nil) return end
		-- inside a lobby or a flat, only that room's prompts count
		local ap = City.Apts.prompt(me)
		if ap == "none" then setPrompt(nil) return end
		if ap then setPromptT(ap) return end
		local hp = Home.prompt(me)
		if hp == "none" then setPrompt(nil) return end
		if hp then setPromptT(hp) return end
		if not S.car then
			-- lifts and trains first: a platform has nothing else on it
			local rp = City.Roads.prompt(me)
			if rp then setPromptT(rp) return end
			local gp = City.Hang.prompt(me)
			if gp then setPromptT(gp) return end
			-- an event you are standing on beats a job you happen to be near:
			-- it is on a clock and the job is not
			local ep = City.Events.prompt(me)
			if ep then setPromptT(ep) return end
			-- a Restaurant Row plot has nothing on it but its own pads and pass
			local tp = City.Tycoon and City.Tycoon.prompt(me)
			if tp then setPromptT(tp) return end
			local jb = City.Jobs.prompt(me)
			if jb then setPromptT(jb) return end
			local kp = City.Kitchen.prompt(me)
			if kp then setPromptT(kp) return end
			local vp = Venues.prompt(me)
			if vp then setPromptT(vp) return end
		end
		if S.car then
			if not cs.fare and near(me, Places.CityTaxiStand, 36) then
				setPrompt("TAXI STAND", "pick up a passenger" .. (S.car.kind == "taxi" and " · taxi bonus +50%" or ""), "PICK UP", "friends", function()
					act("takeFare", "takeFare", nil, "")
				end, CITY + Places.CityTaxiStand)
				return
			end
			if not S.race and near(me, Places.RaceStart, 30) then
				setPrompt("KART TRACK", CC.Race.entry .. " coins · 3 laps · gold under " .. CC.Race.gold .. "s", "RACE", "trophy", function()
					act("raceStart", "raceStart", nil, "", function(res)
						if res and res.ok then
							S.race = { t0 = os.clock(), lap = 1, cp = 1 }
							Audio.play("BigChime", 1.2, 0.8)
						end
					end)
				end, CITY + Places.RaceStart)
				return
			end
			setPrompt(nil)
			return
		end
		if near(me, Places.CityExit, 40) then
			setPrompt("SMINSKI ARCADE", "endless runs · dog park survival · shops", "PLAY", "play", City.openArcade, CITY + Places.CityExit)
			return
		end
		if not cs.job and near(me, Places.CityDepot, 20) then
			setPrompt("PARCEL PICKUP", "take a parcel to a door in town", "TAKE", "bag", function() act("takeJob", "takeJob", nil, "") end, CITY + Places.CityDepot)
			return
		end
		if near(me, Places.CityDealer, 40) then
			setPrompt("SMINSKI MOTORS", "buy cars · pick your paint", "SHOP", "play", City.openDealer, CITY + Places.CityDealer)
			return
		end
		for _, b in CC.Businesses do
			local spot = Places.CityBiz[b.id]
			if near(me, spot, 16) then
				local w, shift, bonus = bizWaiting(b)
				if w then
					local sub = shift >= 1
						and ("shift finished · " .. (w + bonus) .. " waiting, bonus included")
						or ("earns " .. b.rate .. "/min · " .. w .. " waiting · " .. math.ceil((CC.ShiftMinutes or 20) * (1 - shift)) .. " min to the bonus")
					setPrompt(string.upper(b.name), sub, shift >= 1 and "COLLECT +" .. math.floor((CC.ShiftBonus or 0) * 100) .. "%" or "COLLECT", "coin", function()
						act("collect" .. b.id, "collectBiz", b.id, b.name)
					end)
				else
					setPrompt(string.upper(b.name), "own it: earns " .. b.rate .. " coins/min, even while you're away", "BUY " .. b.price, "chart", function()
						act("buy" .. b.id, "buyBiz", b.id, "", function(res)
							if res and res.ok then
								UI.toast("You own the " .. b.name .. "!", C.gold)
								Audio.play("BigChime", 1, 0.9)
							end
						end)
					end)
				end
				return
			end
		end
		for _, sh in Places.MallShops do
			if near(me, sh.pos, 14) then
				setPrompt(sh.name, "the same shop as back home", "BROWSE", "bag", function() UI.openShopTab(sh.tab) end, CITY + sh.pos)
				return
			end
		end
		for id, spot in Places.CityRides do
			if near(me, spot, 16) then
				local free = player:GetAttribute("VIP")
				setPrompt(id == "ferris" and "FERRIS WHEEL" or "CAROUSEL", free and "free for VIPs!" or (CC.Rides[id] .. " coins a ride"), "RIDE", "star", function()
					act("ride" .. id, "ride", id, "", function(res) if res and res.ok then City.startRide(id) end end)
				end, CITY + spot)
				return
			end
		end
		if near(me, Places.CityClaw, 26) then
			setPrompt("CLAW MACHINE", CC.Claw.price .. " coins · coins, outfits or a capsule!", "PLAY", "capsule", function()
				act("claw", "claw", nil, "", function(res)
					if res and res.ok and res.prize then
						local p = res.prize
						Audio.play("BigChime", 1.2, 0.9)
						if p.kind == "coins" then UI.toast("the claw won " .. p.coins .. " coins!", C.gold)
						elseif p.kind == "outfit" then UI.toast("NEW OUTFIT: " .. p.name .. "!", C.lav)
						else UI.toast("a capsule! " .. tostring(p.character) .. (p.duplicate and " (dupe)" or ""), C.lav) end
						if res.data and ctx.setData then ctx.setData(res.data) end
					end
				end)
			end)
			return
		end
		for i, p in Places.cityFarmPlots() do
			if near(me, p, 22) then
				local t0 = cs.plots and cs.plots[tostring(i)]
				if not t0 then
					setPrompt("FIELD " .. i, "plant seeds · ready in " .. (cs.ripe or 45) .. "s", "PLANT", "star", function() act("plant" .. i, "plant", i, "") end)
				else
					local left = math.ceil((cs.ripe or 45) - (workspace:GetServerTimeNow() - t0))
					if left > 0 then setPrompt("FIELD " .. i, "growing · ready in " .. left .. "s", nil, "clock")
					else setPrompt("FIELD " .. i, "ready to harvest! +" .. CC.Harvest, "HARVEST", "star", function() act("harvest" .. i, "harvest", i, "fresh veg!") end) end
				end
				return
			end
		end
		local spot, sd
		for _, p in Build.parked do
			if p.m and p.m.Parent then
				local d = (flat(me) - flat(p.m:GetPivot().Position - CITY)).Magnitude
				if d < 10 and (not sd or d < sd) then spot, sd = p, d end
			end
		end
		if spot then
			setPrompt("HOP IN", "drive around town (it becomes your selected car)", "DRIVE", "play", function() City.enterCar(spot) end)
			return
		end
		setPrompt(nil)
	end

	---------------------------------------------------------------------------
	-- OTHER PLAYERS' CARS
	---------------------------------------------------------------------------
	local function othersTick()
		table.clear(S.poses)
		local seen, cityPlayers = {}, {}
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("Activity") == "city" then
				local ch = p.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp and p ~= player then table.insert(cityPlayers, hrp.Position - CITY) end
				-- a sit/dance published by another player (see the server's "pose")
				local cp = p:GetAttribute("CityPose")
				if cp and p ~= player then S.poses[p] = cp end
				local col = p:GetAttribute("Driving")
				local kind = p:GetAttribute("DrivingCar") or "convertible"
				if col then
					S.poses[p] = "sit"
					if p ~= player and hrp then
						seen[p] = true
						local oc = S.otherCars[p]
						if not oc or oc.col ~= col or oc.kind ~= kind then
							if oc then oc.m:Destroy() end
							local m, seat = K.buildCar(kind, K.CAR_COLORS[col] or K.CAR_COLORS[1], K.actors)
							oc = { m = m, seat = seat, col = col, kind = kind }
							S.otherCars[p] = oc
						end
						local look = hrp.CFrame.LookVector
						local cf = CFrame.new(hrp.Position - V(0, oc.seat.Y + 2.9, 0)) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0) * CFrame.new(0, 0, -oc.seat.Z)
						oc.m:PivotTo(cf)
					end
				end
			end
		end
		if S.car then S.poses[player] = "sit" end
		for p, oc in S.otherCars do
			if not seen[p] then
				oc.m:Destroy()
				S.otherCars[p] = nil
			end
		end
		return cityPlayers
	end
	function City.poses() return S.poses end
	-- what the sound layer needs to know about moving traffic
	function City.trafficList() return S.traffic end

	-- PUBLISH your pose so the rest of the street can see it. Debounced: this
	-- is a remote call, and sitting down should cost one, not one per frame.
	local posted, postAt = nil, 0
	function City.setPose(pose)
		if pose == posted then return end
		if os.clock() - postAt < 0.35 then return end
		posted, postAt = pose, os.clock()
		task.spawn(remote, "pose", pose or "none")
	end

	---------------------------------------------------------------------------
	-- BUBBLES: little speech-bubble icons over every job spot, and a
	-- "+N COINS" pop-up over your head whenever you earn
	---------------------------------------------------------------------------
	local TweenService = game:GetService("TweenService")
	local bubbles = {}
	local function bubble(pos, icon, height)
		local anchor = part(K.actors, V(1, 1, 1), CFrame.new(CITY + V(pos.X, K.PAD_Y, pos.Z)), Color3.new(), MATTE, { transparency = 1 })
		anchor.Name = "BubbleAnchor"
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(64, 76)
		bb.StudsOffsetWorldSpace = V(0, height or 14, 0)
		bb.MaxDistance = 320
		bb.LightInfluence = 0
		bb.Adornee = anchor
		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(64, 64)
		card.BackgroundColor3 = C.white
		card.Parent = bb
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 18) cr.Parent = card
		local st = Instance.new("UIStroke") st.Thickness = 3 st.Color = rgb(98, 164, 96) st.Parent = card
		local tail = Instance.new("Frame")
		tail.Size = UDim2.fromOffset(16, 16)
		tail.AnchorPoint = Vector2.new(0.5, 0.5)
		tail.Position = UDim2.fromOffset(32, 64)
		tail.Rotation = 45
		tail.BackgroundColor3 = C.white
		tail.ZIndex = 0
		tail.Parent = bb
		UI.icon(card, icon, { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(6, 6), ZIndex = 2 })
		bb.Parent = anchor
		table.insert(bubbles, { bb = bb, h = height or 14, t0 = math.random() * 6 })
	end
	-- SKY LIFE: hot-air balloons drifting over town, a helicopter circling
	-- the towers, and a blimp with a banner
	local sky = {}
	local function buildSky()
		local cols = { { rgb(255, 170, 190), rgb(255, 236, 200) }, { rgb(150, 206, 250), rgb(255, 255, 255) }, { rgb(255, 214, 110), rgb(255, 150, 120) }, { rgb(190, 160, 250), rgb(255, 200, 230) } }
		for i, c in cols do
			local m = Instance.new("Model")
			part(m, V(40, 46, 40), CFrame.new(0, 30, 0), c[1], MATTE, { mesh = Enum.MeshType.Sphere })
			for k = 0, 3 do
				part(m, V(40.6, 46.4, 9), CFrame.new(0, 30, 0) * CFrame.Angles(0, k * math.pi / 4, 0), c[2], MATTE, { mesh = Enum.MeshType.Sphere })
			end
			part(m, V(12, 8, 12), CFrame.new(0, 6, 0), c[1], MATTE, { mesh = Enum.MeshType.Sphere })
			part(m, V(7, 5, 7), CFrame.new(0, -6, 0), rgb(190, 140, 96), K.WOODM)
			for _, sx in { -3, 3 } do for _, sz in { -3, 3 } do part(m, V(0.3, 12, 0.3), CFrame.new(sx, 1, sz), rgb(90, 70, 60), MATTE) end end
			m.WorldPivot = CFrame.new()
			m.Parent = K.actors
			table.insert(sky, { kind = "balloon", m = m, a = i * 1.7, r = 380 + i * 130, y = 330 + i * 40, sp = 0.012 + i * 0.003 })
		end
		local h = Instance.new("Model")
		part(h, V(7, 7, 16), CFrame.new(), rgb(255, 250, 240), K.SMOOTH, { mesh = Enum.MeshType.Sphere })
		part(h, V(6, 4, 6), CFrame.new(0, 0.6, -4.6), rgb(150, 206, 250), K.SMOOTH, { mesh = Enum.MeshType.Sphere })
		part(h, V(1.6, 1.6, 14), CFrame.new(0, 1, 13), rgb(255, 170, 190), K.SMOOTH)
		part(h, V(0.6, 5, 3), CFrame.new(0, 3, 19), rgb(255, 170, 190), K.SMOOTH)
		part(h, V(0.8, 2.4, 0.8), CFrame.new(0, 4.4, 0), K.C.ink, K.METAL)
		for _, sx in { -3, 3 } do part(h, V(0.5, 0.5, 12), CFrame.new(sx, -4.6, 0), K.C.ink, K.METAL) end
		local rotor = part(h, V(30, 0.3, 1.6), CFrame.new(0, 5.8, 0), K.C.ink, K.METAL)
		local rotor2 = part(h, V(1.6, 0.3, 30), CFrame.new(0, 5.8, 0), K.C.ink, K.METAL)
		h.WorldPivot = CFrame.new()
		h.Parent = K.actors
		table.insert(sky, { kind = "heli", m = h, a = 0, r = 260, y = 470, sp = 0.22, rotor = rotor, rotor2 = rotor2 })
		local b = Instance.new("Model")
		part(b, V(36, 36, 110), CFrame.new(), rgb(255, 236, 200), MATTE, { mesh = Enum.MeshType.Sphere })
		part(b, V(36.4, 8, 110.4), CFrame.new(), rgb(255, 150, 190), MATTE, { mesh = Enum.MeshType.Sphere })
		part(b, V(10, 6, 20), CFrame.new(0, -19, 0), rgb(150, 206, 250), K.SMOOTH)
		for _, a in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
			part(b, V(1.4, 16, 18), CFrame.new(0, 0, 48) * CFrame.Angles(0, 0, a) * CFrame.new(0, 14, 0), rgb(255, 150, 190), MATTE)
		end
		local banner = part(b, V(0.4, 12, 60), CFrame.new(18.4, 0, 0), rgb(255, 250, 240), MATTE)
		K.textOn(banner, Enum.NormalId.Right, "SMINSKI CITY", rgb(236, 110, 160), Vector2.new(900, 180), 0.4)
		local banner2 = part(b, V(0.4, 12, 60), CFrame.new(-18.4, 0, 0), rgb(255, 250, 240), MATTE)
		K.textOn(banner2, Enum.NormalId.Left, "SMINSKI CITY", rgb(236, 110, 160), Vector2.new(900, 180), 0.4)
		b.WorldPivot = CFrame.new()
		b.Parent = K.actors
		table.insert(sky, { kind = "blimp", m = b, a = 2, r = 640, y = 560, sp = 0.02 })
	end
	local function skyTick(dt, t)
		for _, s in sky do
			s.a += s.sp * dt
			local p = CITY + V(math.cos(s.a) * s.r, s.y + math.sin(t * 0.3 + s.r) * 8, math.sin(s.a) * s.r)
			if s.kind == "balloon" then
				s.m:PivotTo(CFrame.new(p) * CFrame.Angles(0, s.a, math.sin(t * 0.4 + s.r) * 0.03))
			else
				local ahead = CITY + V(math.cos(s.a + 0.05) * s.r, s.y, math.sin(s.a + 0.05) * s.r)
				local cf = CFrame.lookAt(p, V(ahead.X, p.Y, ahead.Z))
				if s.kind == "heli" then
					cf = cf * CFrame.Angles(-0.12, 0, -0.2)
					s.m:PivotTo(cf)
					s.rotor.CFrame = cf * CFrame.new(0, 5.8, 0) * CFrame.Angles(0, t * 30, 0)
					s.rotor2.CFrame = s.rotor.CFrame
				else
					s.m:PivotTo(cf)
				end
			end
		end
	end

	local function buildBubbles()
		bubble(Places.CityDepot, "bag", 26)
		bubble(Places.CityTaxiStand, "pin", 16)
		bubble(Places.CityDealer, "play", 16)
		for _, spot in Places.CityBiz do bubble(spot, "coin", 14) end
		for _, sh in Places.MallShops do bubble(sh.pos, "bag", 14) end
		bubble(Places.CityRides.ferris, "star", 12)
		bubble(Places.CityRides.carousel, "star", 30)
		bubble(Places.CityClaw, "capsule", 18)
		bubble(Places.RaceStart, "trophy", 22)
		bubble(V(-150, 0, 380), "star", 10)
		bubble(Places.CityExit + V(0, 0, 10), "play", 40)
	end
	local function popCoins(n)
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(230, 64)
		bb.StudsOffset = V(0, 4.5, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Adornee = hrp
		local g = Instance.new("CanvasGroup")
		g.Size = UDim2.fromScale(1, 1)
		g.BackgroundTransparency = 1
		g.Parent = bb
		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Position = UDim2.fromScale(0.5, 0.5)
		pill.Size = UDim2.fromOffset(210, 52)
		pill.BackgroundColor3 = C.white
		pill.Parent = g
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(1, 0) cr.Parent = pill
		local st = Instance.new("UIStroke") st.Thickness = 3 st.Color = rgb(98, 164, 96) st.Parent = pill
		UI.icon(pill, "coin", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(6, 3), ZIndex = 2 })
		UI.text(pill, "+" .. n .. " COINS", { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(54, 0), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = rgb(86, 156, 84), ZIndex = 2 })
		bb.Parent = gui.Parent or K.actors
		TweenService:Create(bb, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = V(0, 9, 0) }):Play()
		task.delay(0.9, function()
			TweenService:Create(g, TweenInfo.new(0.7), { GroupTransparency = 1 }):Play()
		end)
		task.delay(1.7, function() bb:Destroy() end)
	end
	City.popCoins = popCoins
	-- Studio preview: build + show every block regardless of distance
	function City.debugShowAll()
		for _, b in S.blocks do
			while not b.done do streamStep(V(b.cx, 0, b.cz), 1000) end
		end
		for _, b in S.blocks do
			b.far = true
			b.visible = true
			b.folder.Parent = K.root
		end
	end

	---------------------------------------------------------------------------
	-- SOCIAL: everyone in town on the map (tap to visit), chatty townsfolk
	---------------------------------------------------------------------------
	function City.mapPlayers()
		local seen, names = {}, {}
		for _, p in Players:GetPlayers() do
			if p ~= player and p:GetAttribute("Activity") == "city" then
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					seen[p] = true
					table.insert(names, p.DisplayName)
					local o = map.others[p]
					if not o then
						local d = map.dot(C.sky, 14)
						local lbl = UI.text(d, p.DisplayName, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(120, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.ink, stroke = 1 })
						lbl.ZIndex = 6
						local hit = Instance.new("TextButton")
						hit.Text = ""
						hit.BackgroundTransparency = 1
						hit.Size = UDim2.fromOffset(34, 34)
						hit.AnchorPoint = Vector2.new(0.5, 0.5)
						hit.Position = UDim2.fromScale(0.5, 0.5)
						hit.ZIndex = 7
						hit.Parent = d
						hit.Activated:Connect(function()
							local h2 = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
							if h2 and h2.Position.Y > CITY.Y - 100 then
								local rel = h2.Position - CITY
								City.travel(V(rel.X + 6, 0, rel.Z + 6))
								map.shade.Visible = false
							else
								UI.toast(p.DisplayName .. " is at home right now", C.mintDark)
							end
						end)
						o = { dot = d }
						map.others[p] = o
					end
					local rel = hrp.Position - CITY
					-- someone inside a house shows on their lot
					o.dot.Position = map.toMap(rel.X, rel.Z)
					o.dot.BackgroundColor3 = p:GetAttribute("Driving") and C.gold or C.sky
				end
			end
		end
		for p, o in map.others do
			if not seen[p] then
				o.dot:Destroy()
				map.others[p] = nil
			end
		end
		map.count.Text = #names == 0 and "just you so far: invite a friend!" or table.concat(names, ", ")
	end

	local CHAT = {
		"Lovely day in Sminski City!", "Have you seen the ferris wheel?", "The bakery smells amazing today.", "I heard parcels pay well!",
		"Nice to see you, neighbour!", "The harbour is so pretty at sunset.", "Beep beep! Watch for taxis.", "I'm saving up for the Sports Car.",
		"My baby just learned to wave!", "Don't forget to nap, it pays!", "The mall has a new boba place.", "Race you at the kart track!",
		"Tidy streets, happy Sminskis.", "Have you met your neighbours yet?", "The farm fields are ripe up north.", "I love your outfit!",
		"Times Sminski Square is so bright!", "Did you try the claw machine?", "Mind the ducks in Button Park.", "Welcome home!",
	}
	local function npcSay(n)
		local body = n.rig.body or n.rig.model.PrimaryPart
		if not body then return end
		if n.bubble then n.bubble:Destroy() end
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(250, 66)
		bb.StudsOffset = V(0, 4.6, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		bb.Adornee = body
		local pill = Instance.new("Frame")
		pill.Size = UDim2.new(1, 0, 0, 54)
		pill.BackgroundColor3 = C.white
		pill.Parent = bb
		local cr = Instance.new("UICorner") cr.CornerRadius = UDim.new(0, 18) cr.Parent = pill
		local st = Instance.new("UIStroke") st.Thickness = 3 st.Color = rgb(98, 164, 96) st.Parent = pill
		local tail = Instance.new("Frame")
		tail.Size = UDim2.fromOffset(14, 14)
		tail.AnchorPoint = Vector2.new(0.5, 0.5)
		tail.Position = UDim2.new(0.5, 0, 0, 54)
		tail.Rotation = 45
		tail.BackgroundColor3 = C.white
		tail.BorderSizePixel = 0
		tail.Parent = bb
		UI.text(pill, CHAT[math.random(1, #CHAT)], { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = true, TextColor3 = C.ink })
		bb.Parent = body
		n.bubble = bb
		Audio.play("Pop", 1.4, 0.4)
		task.delay(4.5, function()
			if n.bubble == bb then n.bubble = nil end
			bb:Destroy()
		end)
	end
	City.npcSay = npcSay

	---------------------------------------------------------------------------
	-- ENTER / LEAVE / UPDATE
	---------------------------------------------------------------------------
	function City.enter()
		City.build()
		K.root.Parent = workspace
		K.actors.Parent = workspace
		rayParams.FilterDescendantsInstances = { K.solidF }
		groundParams.FilterDescendantsInstances = { K.walkF }
		if #S.people == 0 then
			buildPeople()
			buildTraffic()
			buildBubbles()
			buildSky()
		end
		if not S.arrow then
			local a = Instance.new("Model")
			a.Name = "JobArrow"
			for _, sx in { -1, 1 } do part(a, V(0.7, 0.7, 3), CFrame.new(sx * 0.9, 0, -0.2) * CFrame.Angles(0, sx * 0.75, 0), rgb(255, 214, 110), NEON) end
			part(a, V(0.7, 0.7, 2.6), CFrame.new(0, 0, 1.6), rgb(255, 214, 110), NEON)
			a.WorldPivot = CFrame.new()
			S.arrow = a
		end
		-- the sky (clouds included) belongs to CityWeather from here on, and it
		-- applies its first frame synchronously: applyLook("city") has just
		-- forced noon, and this runs again on every return from a run
		City.Weather.enter()
		City.Sound.enter()
		gui.Enabled = true
		City.active = true
		Home.enter()
		S.exitArmed = false
		S.loading = true
		S.loadT = 0
		H.curtain.Visible = true
		H.curtain.BackgroundTransparency = 0
		H.curtainText.TextTransparency = 0
		camera.CameraType = Enum.CameraType.Custom
		if player then
			player.CameraMinZoomDistance = 10
			player.CameraMaxZoomDistance = 80
		end
		local kind = UI.inputKind and UI.inputKind() or "keyboard"
		H.hint.Text = kind == "touch" and "drag to walk · MY CAR calls your car · MAP to fast travel"
			or kind == "gamepad" and "stick walk / steer · RT gas · LT brake · X use · Y car · Back map"
			or "WASD walk / drive · E use · C call your car · H honk · M map"
		task.spawn(function()
			local res = remote("state")
			if res and res.ok then applyState(res.city) end
		end)
		Audio.play("BigChime", 1, 0.6)
	end

	function City.leave()
		if S.ride then
			local _, hum = myChar()
			if hum then hum.PlatformStand = false end
			S.ride = nil
		end
		if S.car then City.exitCar() end
		Home.leave()
		Venues.leave()
		City.Roads.leave()
		City.Apts.leave(true)
		City.Weather.leave()
		City.Sound.leave()
		City.Way.clear()
		City.Hang.leave()
		City.Events.leave()
		if City.Tycoon then City.Tycoon.leave() end
		gui.Enabled = false
		City.active = false
		setPrompt(nil)
		dealer.shade.Visible = false
		map.shade.Visible = false
		K.root.Parent = nil
		K.actors.Parent = nil
		if S.clouds then S.clouds:Destroy() S.clouds = nil end
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end

	local function streetAt(p)
		local NS, EW = Places.CityStreetsNS, Places.CityStreetsEW
		for _, r in ROADS do
			if math.abs(p.X - r) < Places.ROAD_W / 2 + 14 then return NS[r] end
			if math.abs(p.Z - r) < Places.ROAD_W / 2 + 14 then return EW[r] end
		end
		return ""
	end

	-- HOW FAR ALONG THE WORLD IS, 0..1, for the loading bar on the title
	-- screen. It counts the blocks NEAR YOU rather than all of them, because
	-- that is the same thing the in-city curtain waits for -- the far side of
	-- the map streaming in is not something a player should be held for.
	function City.loadProgress()
		if not S.blocks or #S.blocks == 0 then return 0 end
		local me = Places.CitySpawn
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then me = hrp.Position - CITY end
		local near, done = 0, 0
		for _, b in S.blocks do
			if not b.far and (V(b.cx, 0, b.cz) - V(me.X, 0, me.Z)).Magnitude < 350 then
				near += 1
				if b.done then done += 1 end
			end
		end
		if near == 0 then return S.built and 1 or 0 end
		return math.clamp(done / near, 0, 1)
	end

	function City.update(dt, t)
		if not S.built or not City.active then return end
		local hrp, hum = myChar()
		local me = hrp and (hrp.Position - CITY) or Places.CitySpawn
		local mePlane = V(me.X, 0, me.Z)
		local done = streamStep(mePlane, S.loading and 60 or 4)
		S.cullT -= dt
		if S.cullT <= 0 then
			S.cullT = 0.5
			cull(mePlane)
		end
		if S.loading then
			S.loadT += dt
			local ready = done
			if not ready then
				ready = true
				for _, b in S.blocks do
					if not b.done and not b.far and (V(b.cx, 0, b.cz) - mePlane).Magnitude < 350 then ready = false break end
				end
			end
			if ready or S.loadT > 15 then
				S.loading = false
				UI.tween(H.curtain, 0.8, { BackgroundTransparency = 1 })
				UI.tween(H.curtainText, 0.5, { TextTransparency = 1 })
				task.delay(0.9, function() if not S.loading then H.curtain.Visible = false end end)
			end
		end
		for _, a in Build.anims do
			if blockVisible(a.cx, a.cz, mePlane, a.far) then a.fn(dt, t) end
		end
		for _, dn in Build.dancers do
			if (V(dn.cx, 0, dn.cz) - mePlane).Magnitude < 300 then
				Models.poseSminski(dn.rig, dn.cf, (math.floor(t + dn.t0) % 3 == 0) and "idle" or "cheer", t * 1.3 + dn.t0)
			end
		end
		for _, bu in bubbles do
			bu.bb.StudsOffsetWorldSpace = V(0, bu.h + math.sin(t * 2 + bu.t0) * 0.6, 0)
		end
		for _, wk in Build.workers do
			local p = wk.cf.Position - CITY
			if (V(p.X, 0, p.Z) - mePlane).Magnitude < 260 then
				if wk.kind == "sweep" then
					local sw = math.sin(t * 3.2 + wk.t0)
					Models.poseSminski(wk.rig, wk.cf * CFrame.Angles(0, sw * 0.15, 0), "idle", t + wk.t0)
					wk.prop:PivotTo(wk.cf * CFrame.new(0.8, 3.6, -1.4) * CFrame.Angles(0.35, 0, sw * 0.45))
				else
					local seat = wk.cf * CFrame.new(0, 0.95, 0)
					Models.poseSminski(wk.rig, seat, "sit", t + wk.t0)
					wk.prop:PivotTo(seat * CFrame.new(0, 3.9, -1.3) * CFrame.Angles(-0.25 + math.sin(t * 0.7 + wk.t0) * 0.04, 0, 0))
				end
			end
		end
		local cityPlayers = othersTick()
		Home.update(dt, t, me)
		Venues.update(dt, t, me)
		City.Roads.update(dt, t, me)
		City.Apts.update(dt, t)
		City.Weather.step(dt, t, mePlane)
		City.Way.step(dt, t, mePlane)
		-- the shift clock ticks and old notifications fall off
		City.Jobs.stepNotes()
		if S.jobT == nil or t - S.jobT > 0.5 then
			S.jobT = t
			City.Jobs.refreshHud()
		end
		City.Hang.update(dt, t, mePlane)
		City.Events.step(dt, t, mePlane)
		City.Grocery.step(mePlane)
		City.Tycoon.step(dt, t, mePlane)
		City.Sound.step(dt, t, mePlane)
		-- the boost banner counts itself down and hides when it lapses
		local b = S.boost
		if b and H.boost then
			local left = b.untilT - (os.time() + S.clockOffset)
			if left <= 0 then
				S.boost = nil
				H.boost.Visible = false
			else
				H.boost.Visible = true
				H.boostText.Text = ("%dx COINS  ·  %d:%02d"):format(b.mult, left // 60, left % 60)
			end
		elseif H.boost then
			H.boost.Visible = false
		end
		-- QUICK FEET: the server publishes the multiplier as an attribute
		local wm = player and player:GetAttribute("WalkMult")
		local _, hum = myChar()
		if hum and wm and hum.WalkSpeed < 16 * wm - 0.1 then hum.WalkSpeed = 16 * wm end
		-- a horn now and then, from a car that is actually near you
		S.hornT = (S.hornT or 6) - dt
		if S.hornT <= 0 then
			local honked = false
			for _, c in S.traffic do
				if c.cf and (V(c.cf.Position.X, 0, c.cf.Position.Z) - V(mePlane.X + CITY.X, 0, mePlane.Z + CITY.Z)).Magnitude < 130 then
					City.Sound.horn(c.cf.Position - CITY)
					honked = true
					break
				end
			end
			-- only back off after an actual horn: on an empty street the long
			-- timer would keep resetting and the road would stay silent
			S.hornT = honked and (9 + math.random() * 16) or 2
		end
		-- LAST. othersTick() clears S.poses at the top of every frame and each
		-- sitting system writes it during its own update, so reading it any
		-- earlier publishes the pose from a frame that no longer exists.
		City.setPose(S.poses[player])
		City.stepDot(dt, t)
		-- mid-tumble after being hit by traffic
		if S.hitUntil and os.clock() < S.hitUntil - 1.3 then S.poses[player] = "flail" end
		skyTick(dt, t)
		if K.blinkers then
			local on = (t % 2) < 1
			for _, b in K.blinkers do b.Transparency = on and 0 or 0.85 end
		end
		-- in a car you are traffic (others queue behind you); on foot at street
		-- level you are a pedestrian, and pedestrians can be hit
		if S.car then table.insert(cityPlayers, S.car.pos - CITY) end
		S.onFoot = (not S.car and not S.ride and not Home.inside and not City.Apts.inside and me.Y < 9 and me.Y > -50) and mePlane or nil
		S.sigT = (S.sigT or 0) + dt
		if S.sigT > 0.2 then
			S.sigT = 0
			stepSignals(mePlane, workspace:GetServerTimeNow())
		end
		for _, n in S.people do stepPerson(n, dt, t, mePlane) end
		for _, c in S.traffic do stepCar(c, dt, t, mePlane, cityPlayers) end
		if S.ride then
			rideStep(dt, t)
		elseif S.car then
			driveStep(dt, t)
		else
			camera.CameraType = Enum.CameraType.Custom
			if hum and camera.CameraSubject ~= hum then camera.CameraSubject = hum end
			camera.FieldOfView += (70 - camera.FieldOfView) * math.min(1, dt * 4)
		end
		H.getOut.holder.Visible = S.car ~= nil
		H.honk.holder.Visible = S.car ~= nil
		H.myCar.holder.Visible = S.car == nil and S.ride == nil
		H.speed.Visible = S.car ~= nil
		if hrp then
			jobsTick(dt, t, me)
			promptTick(me)
			local d = Places.cityDistrictAt(me)
			H.district.Text = d and string.upper(d.name) or "SMINSKI CITY"
			H.street.Text = streetAt(me)
			local dEx = (mePlane - Places.CityExit).Magnitude
			if dEx > 24 then S.exitArmed = true end
			if S.exitArmed and not S.car and dEx < 12 and ctx.exitCity then ctx.exitCity() end
			-- kept fresh whether or not the map is open: the search ranks by
			-- distance from here the moment the first key lands
			map.mePos = me
			-- THE MINIMAP IS STEPPED WHETHER OR NOT THE MAP MODAL IS OPEN --
			-- that is the whole point of it. Heading is measured off the camera,
			-- not the character: you steer where you are looking, and a needle
			-- that lags the camera by a body turn feels broken.
			if H.mini then
				local look = camera.CFrame.LookVector
				Mini.step(H.mini, me, math.deg(math.atan2(look.X, look.Z)), S.target)
			end
			if map.shade.Visible then
				City.mapPlayers()
				map.me.Position = map.toMap(me.X, me.Z)
				-- a live search wins the pin over the job/fare arrow's target:
				-- you are looking at the map BECAUSE you typed something
				local pin = map.searchPos or S.target
				map.target.Visible = pin ~= nil
				if pin then map.target.Position = map.toMap(pin.X, pin.Z) end
			end
		end
		local coins = ctx.data and ctx.data.Coins or 0
		if coins ~= S.lastCoins then
			S.lastCoins = coins
			H.coins.Text = tostring(coins)
		end
	end

	UIS.InputBegan:Connect(function(input, gp)
		if gp or not City.active then return end
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonX then
			if S.car and not promptAction then City.exitCar() else City.doPrompt() end
		elseif k == Enum.KeyCode.F then
			if S.car then City.exitCar() end
		elseif k == Enum.KeyCode.C or k == Enum.KeyCode.ButtonY then
			if S.car then City.exitCar() else City.summonCar() end
		elseif k == Enum.KeyCode.H or k == Enum.KeyCode.ButtonL1 then
			City.honk()
		elseif k == Enum.KeyCode.M or k == Enum.KeyCode.ButtonSelect then
			City.toggleMap()
		end
	end)

	return City
end
