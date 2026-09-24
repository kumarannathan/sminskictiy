-- Survival (ServerScriptService.SminskiServer.Survival)
-- Dog Park Survival: free-roam, last Sminski alive wins.
--   Waiting pen in the hub -> countdown -> everyone teleports into the park ->
--   dogs, people and thrown things get busier over time (Chaos Meter + events)
--   -> caught players spectate -> last one standing wins -> back to the hub.
-- The server runs every dog/human/ball/bot and is the final word on who got
-- caught; clients draw from 10Hz snapshots and report what they saw.

return function(api)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Config = api.Config
	local Shared = ReplicatedStorage:WaitForChild("SminskiShared")
	local Places = require(Shared:WaitForChild("Places"))
	local Rules = require(Shared:WaitForChild("ParkRules"))
	local PK = Config.Park
	local DOG, HUM, KIND = Rules.DOG, Rules.HUM, Rules.KIND
	local IS_STUDIO = RunService:IsStudio()
	local HALF = Places.ARENA_HALF - 10
	local rng = Random.new()

	local function now()
		return workspace:GetServerTimeNow()
	end

	---------------------------------------------------------------------------
	-- REMOTES
	---------------------------------------------------------------------------
	local folder = Instance.new("Folder")
	folder.Name = "SminskiPark"
	local Event = Instance.new("RemoteEvent")
	Event.Name = "Event"
	Event.Parent = folder
	local Snap = Instance.new("UnreliableRemoteEvent")
	Snap.Name = "Snap"
	Snap.Parent = folder
	folder.Parent = ReplicatedStorage

	---------------------------------------------------------------------------
	-- STATE
	---------------------------------------------------------------------------
	local pen = { endsAt = nil }
	local match -- current round (nil between rounds)
	local obstacles = Places.arenaObstacles()

	local function fireAll(kind, data)
		Event:FireAllClients(kind, data)
	end
	local function fireMatch(kind, data)
		if not match then return end
		for _, p in match.people do
			if p.player and p.player.Parent then Event:FireClient(p.player, kind, data) end
		end
	end

	local function charOf(player)
		local c = player.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		return c, hrp, hum
	end
	-- feet position of a real player, arena-relative
	local function feetRel(player)
		local _, hrp = charOf(player)
		if not hrp then return nil end
		return hrp.Position - Vector3.new(0, 2.9, 0) - Places.ARENA
	end

	---------------------------------------------------------------------------
	-- STEERING (shared by dogs, humans, bots)
	---------------------------------------------------------------------------
	local function steer(e, dir, speed, turn, dt, radius, avoidScale)
		local avoid = Vector3.zero
		local pos = Vector3.new(e.x, 0, e.z)
		for _, o in obstacles do
			local d = pos - o.pos
			local dist = d.Magnitude
			local rr = o.r + radius + 5
			if dist < rr and dist > 0.01 then
				avoid += d.Unit * ((rr - dist) / rr) * 2.2 * (avoidScale or 1)
			end
		end
		local edge = HALF - 25
		if e.x > edge then avoid += Vector3.new(-(e.x - edge) / 20, 0, 0) end
		if e.x < -edge then avoid += Vector3.new((-edge - e.x) / 20, 0, 0) end
		if e.z > edge then avoid += Vector3.new(0, 0, -(e.z - edge) / 20) end
		if e.z < -edge then avoid += Vector3.new(0, 0, (-edge - e.z) / 20) end
		if e.leaving then avoid = Vector3.zero end
		local want = dir + avoid
		if want.Magnitude < 1e-3 then want = Vector3.new(math.sin(e.h), 0, math.cos(e.h)) end
		want = want.Unit
		local target = math.atan2(want.X, want.Z)
		local diff = (target - e.h + math.pi) % (math.pi * 2) - math.pi
		e.h += math.clamp(diff, -turn * dt, turn * dt)
		e.v += (speed - e.v) * math.min(1, dt * 3.5)
		e.x += math.sin(e.h) * e.v * dt
		e.z += math.cos(e.h) * e.v * dt
		if not e.leaving then
			e.x = math.clamp(e.x, -HALF, HALF)
			e.z = math.clamp(e.z, -HALF, HALF)
		end
	end

	local function toward(e, x, z)
		local d = Vector3.new(x - e.x, 0, z - e.z)
		return d.Magnitude > 0.01 and d.Unit or Vector3.zero, d.Magnitude
	end

	local function randomSpot(margin)
		for _ = 1, 20 do
			local x, z = rng:NextNumber(-HALF + margin, HALF - margin), rng:NextNumber(-HALF + margin, HALF - margin)
			local ok = true
			for _, o in obstacles do
				if (Vector3.new(x, 0, z) - o.pos).Magnitude < o.r + 8 then ok = false break end
			end
			if ok then return x, z end
		end
		return 0, 0
	end

	---------------------------------------------------------------------------
	-- SPAWNING
	---------------------------------------------------------------------------
	local function newId()
		match.nextId += 1
		return match.nextId
	end

	local function gateSpawn()
		local g = Places.Gates[rng:NextInteger(1, #Places.Gates)]
		local out = g * 1.07
		return out.X, out.Z, math.atan2(-g.X, -g.Z)
	end

	local function spawnDog(variant, role, opts)
		opts = opts or {}
		local def = Rules.DOGS[variant]
		local x, z, h = gateSpawn()
		if opts.x then x, z, h = opts.x, opts.z, opts.h or 0 end
		local e = {
			id = newId(), kind = KIND.dog, variant = variant, s = def.s, role = role,
			x = x, z = z, h = h, v = 0, ph = 0, st = DOG.enter, stT = 0,
			think = 0, owner = opts.owner, loose = opts.loose,
		}
		local gx, gz = randomSpot(40)
		e.gx, e.gz = gx * 0.6, gz * 0.6
		match.entities[e.id] = e
		match.dogCount += 1
		fireMatch("spawn", { id = e.id, kind = e.kind, variant = variant, s = e.s, role = role })
		return e
	end

	local function spawnHuman(role, opts)
		opts = opts or {}
		local variant = rng:NextInteger(1, #Rules.HUMANS)
		local def = Rules.HUMANS[variant]
		local x, z, h = gateSpawn()
		local e = {
			id = newId(), kind = KIND.human, variant = variant, s = def.s, role = role,
			x = x, z = z, h = h, v = 0, ph = rng:NextNumber(0, 6), st = role == "jogger" and HUM.jog or HUM.walk, stT = 0,
			life = opts.life or rng:NextNumber(35, 70), throwT = rng:NextNumber(6, 14), think = 0, dir = rng:NextInteger(0, 1) * 2 - 1,
		}
		if opts.x then e.x, e.z, e.h = opts.x, opts.z, opts.h end
		e.gx, e.gz = randomSpot(30)
		match.entities[e.id] = e
		match.humanCount += 1
		fireMatch("spawn", { id = e.id, kind = e.kind, variant = variant, s = e.s, role = role })
		if role == "owner" then
			spawnDog(rng:NextInteger(1, #Rules.DOGS - 1), "leash", { owner = e.id, x = e.x + 18, z = e.z, h = e.h })
		end
		return e
	end

	local function removeEntity(e)
		match.entities[e.id] = nil
		if e.kind == KIND.dog then match.dogCount -= 1 elseif e.kind == KIND.human then match.humanCount -= 1 end
		fireMatch("despawn", e.id)
	end

	local function throwThing(kind, fromX, fromZ, fromH, toX, toZ)
		local d = Vector3.new(toX - fromX, 0, toZ - fromZ).Magnitude
		local p = {
			id = newId(), kind = kind,
			from = Vector3.new(fromX, fromH, fromZ), to = Vector3.new(toX, 0, toZ),
			t0 = now(), T = kind == "frisbee" and math.max(0.9, d / 60) or math.max(0.9, d / 55),
			arc = kind == "ball" and rng:NextNumber(18, 34) or nil, roll = rng:NextNumber(26, 40),
		}
		match.projs[p.id] = p
		fireMatch("proj", { id = p.id, kind = kind, from = p.from, to = p.to, t0 = p.t0, T = p.T, arc = p.arc, roll = p.roll })
		return p
	end

	---------------------------------------------------------------------------
	-- PARTICIPANTS
	---------------------------------------------------------------------------
	local function aliveList()
		local out = {}
		for _, p in match.people do
			if p.alive then table.insert(out, p) end
		end
		return out
	end

	local function posOf(p)
		if p.bot then return Vector3.new(p.x, 0, p.z) end
		return feetRel(p.player)
	end

	local eliminate
	local function checkEnd()
		if not match or match.over then return end
		local alive = aliveList()
		local humansAlive = 0
		for _, p in alive do if not p.bot then humansAlive += 1 end end
		if #alive <= 1 then
			match.over = true
			task.defer(function() match.finish(alive) end)
		elseif humansAlive == 0 and not match.ghostUntil then
			-- every player is out: the bots play on for a while so the
			-- eliminated can spectate the ending, then the round wraps up
			match.ghostUntil = now() + (PK.SpectateAfterOut or 30)
			fireMatch("event", { kind = "ghost", title = "BOTS ONLY  ·  spectating", t0 = now() })
		end
	end

	eliminate = function(p, how, byId)
		if not p.alive or match.over then return end
		if (p.safeUntil or 0) > now() then return end
		-- a heart pickup saves you once: pop it, knock you clear, brief safety
		if (p.hearts or 0) > 0 and how ~= "fell" and how ~= "left" then
			p.hearts -= 1
			p.safeUntil = now() + PK.HeartSafe
			fireMatch("saved", { id = p.id, how = how, by = byId, safe = PK.HeartSafe })
			if p.bot then
				local e = match.entities[byId]
				if e then
					local d = Vector3.new(p.x - e.x, 0, p.z - e.z)
					d = d.Magnitude > 0.1 and d.Unit or Vector3.new(1, 0, 0)
					p.x, p.z = math.clamp(p.x + d.X * 14, -HALF, HALF), math.clamp(p.z + d.Z * 14, -HALF, HALF)
				end
			end
			return
		end
		p.alive = false
		p.outAt = now()
		match.placeCounter -= 1
		p.place = match.placeCounter + 1
		fireMatch("elim", { id = p.id, name = p.name, how = how, by = byId, left = #aliveList(), total = #match.order })
		if p.player then
			p.player:SetAttribute("ParkOut", true)
			local _, hrp = charOf(p.player)
			if hrp then hrp.Anchored = true end
		end
		checkEnd()
	end

	---------------------------------------------------------------------------
	-- AI
	---------------------------------------------------------------------------
	local function nearestTarget(e, radius)
		local best, bd
		for _, p in match.people do
			if p.alive then
				local pos = posOf(p)
				if pos then
					local d = (Vector3.new(pos.X - e.x, 0, pos.Z - e.z)).Magnitude
					local cover = Places.coverAt(pos)
					local r = cover == "bush" and 12 or radius
					if d < r and (not bd or d < bd) then best, bd = p, d end
				end
			end
		end
		return best, bd
	end

	local function dogThink(e, dt, c)
		local fwd = Vector3.new(math.sin(e.h), 0, math.cos(e.h))
		local trot = (13 + 5 * c) * (0.8 + e.s * 0.3)
		local sprint = (26 + 9 * math.min(c, 1.3)) * (e.s < 0.6 and 1.15 or 1)
		local turn = e.s < 0.6 and 4.2 or e.s > 0.9 and 2.0 or 2.8
		e.stT += dt
		e.think -= dt
		local r = 7 * e.s
		if e.st == DOG.enter then
			local dir, dist = toward(e, e.gx, e.gz)
			steer(e, dir, trot, turn, dt, r)
			if dist < 20 or e.stT > 12 then e.st, e.stT = e.role == "leash" and DOG.leash or DOG.wander, 0 end
		elseif e.st == DOG.leash then
			local o = match.entities[e.owner]
			if not o then e.st, e.stT = DOG.wander, 0 return end
			local side = Vector3.new(math.cos(o.h), 0, -math.sin(o.h)) * 16
			local tx, tz = o.x + side.X + math.sin(o.h) * 6, o.z + side.Z + math.cos(o.h) * 6
			local dir, dist = toward(e, tx, tz)
			steer(e, dir, math.clamp(dist * 1.5, 0, 30), turn * 1.4, dt, r, 0.4)
		elseif e.st == DOG.wander then
			local dir, dist = toward(e, e.gx, e.gz)
			steer(e, dir, trot, turn, dt, r)
			if dist < 12 then
				if rng:NextNumber() < 0.35 then e.st, e.stT = DOG.sniff, 0 end
				e.gx, e.gz = randomSpot(30)
			end
			if e.think <= 0 then
				e.think = 0.5
				local aggro = (e.role == "zoomer" and 0.25 or 1) * (0.03 + 0.22 * math.min(c, 1.2)) * (e.loose and 3 or 1)
				if rng:NextNumber() < aggro then
					local tgt = nearestTarget(e, 55 + 45 * math.min(c, 1.2))
					if tgt then
						e.st, e.stT, e.target, e.chaseFor = DOG.chase, 0, tgt.id, rng:NextNumber(5, 9) + (e.loose and 5 or 0)
						if e.stT == 0 then fireMatch("bark", e.id) end
						return
					end
				end
				if e.role == "zoomer" and rng:NextNumber() < 0.12 + 0.2 * c then
					e.st, e.stT, e.zoomFor = DOG.zoom, 0, rng:NextNumber(3, 6)
				end
			end
		elseif e.st == DOG.sniff then
			steer(e, fwd, 0, turn, dt, r)
			if e.stT > 1.8 then e.st, e.stT = DOG.wander, 0 end
		elseif e.st == DOG.zoom then
			e.wig = (e.wig or 0) + dt * rng:NextNumber(-3, 3)
			local dir = Vector3.new(math.sin(e.h + e.wig * 0.5), 0, math.cos(e.h + e.wig * 0.5))
			steer(e, dir, sprint * 1.1, turn * 1.2, dt, r)
			if e.stT > (e.zoomFor or 4) then e.st, e.stT = DOG.wander, 0 end
		elseif e.st == DOG.fetch then
			local dir, dist = toward(e, e.gx, e.gz)
			steer(e, dir, sprint, turn, dt, r, 0.6)
			if dist < 5 or e.stT > 7 then
				e.st, e.stT = DOG.sniff, 0
				e.gx, e.gz = randomSpot(30)
			end
		elseif e.st == DOG.chase then
			local p = match.people[e.target]
			local pos = p and p.alive and posOf(p)
			if not pos or e.stT > (e.chaseFor or 7) then
				e.st, e.stT = DOG.wander, 0
				e.gx, e.gz = randomSpot(30)
				return
			end
			-- lose track of someone hiding in a bush
			if Places.coverAt(pos) == "bush" and (Vector3.new(pos.X - e.x, 0, pos.Z - e.z)).Magnitude > 14 then
				e.lostT = (e.lostT or 0) + dt
				if e.lostT > 1.2 then e.st, e.stT, e.lostT = DOG.sniff, 0, 0 return end
			else
				e.lostT = 0
			end
			local vel = p.vel or Vector3.zero
			local aim = pos + vel * 0.35
			local dir, dist = toward(e, aim.X, aim.Z)
			steer(e, dir, sprint, turn, dt, r, 0.5)
			local reach = 12 * e.s + 7
			local facing = fwd:Dot(dir) > 0.85
			if dist < reach and facing then
				e.st, e.stT = DOG.crouch, 0
				fireMatch("bark", e.id)
			end
		elseif e.st == DOG.crouch then
			steer(e, fwd, 0, turn * 0.6, dt, r)
			if e.stT >= Rules.CROUCH_T then
				local p = match.people[e.target]
				local pos = p and p.alive and posOf(p)
				local aim = pos and (pos + (p.vel or Vector3.zero) * 0.25) or (Vector3.new(e.x, 0, e.z) + fwd * 12)
				local from = Vector3.new(e.x, 0, e.z)
				local d = Vector3.new(aim.X - e.x, 0, aim.Z - e.z)
				-- land so the mouth (about 21*s ahead of the body) ends on the target
				local mouthAhead = 21 * e.s
				local travel = math.clamp(d.Magnitude - mouthAhead, 0, 20 * e.s + 8)
				local dir = d.Magnitude > 0.1 and d.Unit or fwd
				e.lungeFrom, e.lungeTo = from, from + dir * travel
				e.h = math.atan2(dir.X, dir.Z)
				e.st, e.stT = DOG.lunge, 0
			end
		elseif e.st == DOG.lunge then
			local k = math.clamp(e.stT / Rules.LUNGE_T, 0, 1)
			local s = k * k * (3 - 2 * k)
			local p = e.lungeFrom:Lerp(e.lungeTo, s)
			e.v = (e.lungeTo - e.lungeFrom).Magnitude / Rules.LUNGE_T
			e.x, e.z = p.X, p.Z
			if e.stT >= Rules.LUNGE_T then
				e.st, e.stT, e.v = DOG.recover, 0, 0
			end
		elseif e.st == DOG.recover then
			e.v = 0
			if e.stT > 0.9 then
				if rng:NextNumber() < 0.55 and match.people[e.target] and match.people[e.target].alive then
					e.st, e.stT = DOG.chase, 0
				else
					e.st, e.stT = DOG.wander, 0
					e.gx, e.gz = randomSpot(30)
				end
			end
		end
	end

	local function humanThink(e, dt, c)
		e.stT += dt
		e.life -= dt
		local r = 8 * e.s
		local walk = (11 + 5 * math.min(c, 1.3)) * e.s
		if e.st == HUM.leave then
			local g = e.exit
			local dir, dist = toward(e, g.X, g.Z)
			e.leaving = dist < 30
			steer(e, dir, walk, 2.5, dt, r)
			if dist < 6 then removeEntity(e) end
			return
		end
		if e.life <= 0 and e.st ~= HUM.windup then
			local best
			for _, g in Places.Gates do
				if not best or (g - Vector3.new(e.x, 0, e.z)).Magnitude < (best - Vector3.new(e.x, 0, e.z)).Magnitude then best = g end
			end
			e.exit = best * 1.1
			e.st, e.stT = HUM.leave, 0
			return
		end
		if e.st == HUM.jog then
			-- loop the jogging ring
			local a = math.atan2(e.z, e.x) + e.dir * 0.35
			local tx, tz = math.cos(a) * Places.RING_R, math.sin(a) * Places.RING_R
			local dir = toward(e, tx, tz)
			steer(e, dir, (28 + 6 * math.min(c, 1)) * e.s, 2.2, dt, r, 0.6)
		elseif e.st == HUM.walk then
			local dir, dist = toward(e, e.gx, e.gz)
			steer(e, dir, walk, 1.8, dt, r)
			if dist < 10 then
				e.gx, e.gz = randomSpot(30)
				if rng:NextNumber() < 0.3 then e.st, e.stT = HUM.stand, 0 end
			end
			e.throwT -= dt
			if e.throwT <= 0 then
				e.throwT = math.max(2.5, rng:NextNumber(10, 16) * (1.2 - 0.7 * math.min(c, 1)))
				e.st, e.stT = HUM.windup, 0
			end
		elseif e.st == HUM.stand then
			steer(e, Vector3.new(math.sin(e.h), 0, math.cos(e.h)), 0, 1, dt, r)
			if e.stT > 2.5 then e.st, e.stT = HUM.walk, 0 end
		elseif e.st == HUM.windup then
			steer(e, Vector3.new(math.sin(e.h), 0, math.cos(e.h)), 0, 1, dt, r)
			if e.stT >= Rules.WINDUP_T then
				-- throw somewhere busy later on, somewhere random early
				local tx, tz
				local alive = aliveList()
				if #alive > 0 and rng:NextNumber() < 0.25 + 0.5 * math.min(c, 1) then
					local p = alive[rng:NextInteger(1, #alive)]
					local pos = posOf(p)
					if pos then tx, tz = pos.X + rng:NextNumber(-10, 10), pos.Z + rng:NextNumber(-10, 10) end
				end
				if not tx then tx, tz = e.x + math.sin(e.h) * rng:NextNumber(60, 140), e.z + math.cos(e.h) * rng:NextNumber(60, 140) end
				tx, tz = math.clamp(tx, -HALF, HALF), math.clamp(tz, -HALF, HALF)
				throwThing(rng:NextNumber() < 0.55 and "ball" or "frisbee", e.x, e.z, 26 * e.s, tx, tz)
				e.st, e.stT = HUM.walk, 0
			end
		end
	end

	-- bot Sminskis: flee whatever is closest and scariest, wander otherwise
	local function botThink(p, dt, c)
		p.react -= dt
		if p.react <= 0 then
			p.react = 0.12 + (1 - p.skill) * 0.3
			local pos = Vector3.new(p.x, 0, p.z)
			local threat = Vector3.zero
			for _, e in match.entities do
				local d = pos - Vector3.new(e.x, 0, e.z)
				local dist = d.Magnitude
				if e.kind == KIND.dog then
					local chasing = (e.st == DOG.chase or e.st == DOG.crouch or e.st == DOG.lunge) and e.target == p.id
					local R = chasing and 75 or 34 * e.s + 14
					if dist < R and dist > 0.01 then threat += d.Unit * (1 - dist / R) ^ 2 * (chasing and 4 or 1.2) end
				elseif e.kind == KIND.human then
					local front = Vector3.new(e.x + math.sin(e.h) * 10 * e.s, 0, e.z + math.cos(e.h) * 10 * e.s)
					local d2 = pos - front
					local R = 26 * e.s
					if d2.Magnitude < R and d2.Magnitude > 0.01 then threat += d2.Unit * (1 - d2.Magnitude / R) ^ 2 * 1.6 end
				end
			end
			local t = now()
			for _, pr in match.projs do
				if t < pr.t0 + pr.T + 0.4 then
					local d = pos - pr.to
					if d.Magnitude < 16 and d.Magnitude > 0.01 then threat += d.Unit * (1 - d.Magnitude / 16) * 2 end
				end
			end
			-- go for a nearby heart if it isn't too dangerous
			local pull = Vector3.zero
			if (p.hearts or 0) < PK.HeartMax then
				for _, h in match.hearts do
					local d = Vector3.new(h.x, 0, h.z) - pos
					if d.Magnitude < 70 and d.Magnitude > 0.01 then pull += d.Unit * (1 - d.Magnitude / 70) * 1.6 end
				end
			end
			threat += pull
			p.wander = (p.wander or rng:NextNumber(0, 6.28)) + rng:NextNumber(-0.6, 0.6)
			local wander = Vector3.new(math.cos(p.wander), 0, math.sin(p.wander))
			local home = -pos / (HALF * 1.2)
			local want = threat * 3 + wander * 0.5 * (1 - math.min(1, threat.Magnitude)) + home * 0.5
			if rng:NextNumber() < (1 - p.skill) * 0.06 then want = wander end -- a silly moment
			p.want = want.Magnitude > 0.01 and want.Unit or Vector3.zero
		end
		local speed = PK.WalkSpeed * (0.82 + 0.13 * p.skill)
		if p.want.Magnitude < 0.01 then speed = 0 end
		local ox, oz = p.x, p.z
		steer(p, p.want, speed, 7, dt, 1.5, 0.35)
		p.vel = Vector3.new((p.x - ox) / dt, 0, (p.z - oz) / dt)
	end

	---------------------------------------------------------------------------
	-- EVENTS (random park chaos)
	---------------------------------------------------------------------------
	local EVENTS = {}
	EVENTS.loose = function()
		local d = spawnDog(5, "chaser", { loose = true })
		d.st, d.stT = DOG.wander, 0
		return "A DOG GOT LOOSE!"
	end
	EVENTS.frisbees = function()
		task.spawn(function()
			for _ = 1, 14 do
				if not match or match.over then return end
				local side = rng:NextInteger(1, 4)
				local g = Places.Gates[side] * 1.02
				local tx, tz = randomSpot(20)
				throwThing("frisbee", g.X + rng:NextNumber(-60, 60), g.Z + rng:NextNumber(-60, 60), 24, tx, tz)
				task.wait(rng:NextNumber(0.35, 0.7))
			end
		end)
		return "FRISBEE STORM!"
	end
	EVENTS.joggers = function()
		local g = Places.Gates[rng:NextInteger(1, 4)]
		local dir = -g.Unit
		local side = Vector3.new(dir.Z, 0, -dir.X)
		for i = 1, 5 do
			local start = g * 1.05 + side * (i - 3) * 16 - dir * i * 6
			local e = spawnHuman("sprinter", { life = 9, x = start.X, z = start.Z, h = math.atan2(dir.X, dir.Z) })
			e.st = HUM.jog
			e.role = "jogger"
			e.gx, e.gz = -g.X * 1.1, -g.Z * 1.1
			e.sprint = true
		end
		return "JOGGER RUSH!"
	end
	EVENTS.balls = function()
		local x, z = randomSpot(60)
		for _ = 1, 8 do
			throwThing("ball", x + rng:NextNumber(-12, 12), z + rng:NextNumber(-12, 12), 60, x + rng:NextNumber(-35, 35), z + rng:NextNumber(-35, 35))
		end
		for _, e in match.entities do
			if e.kind == KIND.dog and e.st ~= DOG.leash and e.st ~= DOG.lunge then
				e.st, e.stT, e.gx, e.gz = DOG.fetch, 0, x, z
			end
		end
		return "TENNIS BALL DROP!"
	end
	EVENTS.zoomies = function()
		for _, e in match.entities do
			if e.kind == KIND.dog and e.st ~= DOG.leash and e.st ~= DOG.lunge then
				e.st, e.stT, e.zoomFor = DOG.zoom, 0, rng:NextNumber(5, 8)
			end
		end
		return "ZOOMIES!"
	end
	EVENTS.sprinklers = function()
		match.sprinklers = { t0 = now(), dur = 12 }
		return "SPRINKLERS ON!"
	end
	local EVENT_ORDER = { "balls", "frisbees", "zoomies", "joggers", "sprinklers", "loose" }

	---------------------------------------------------------------------------
	-- MATCH
	---------------------------------------------------------------------------
	local BOT_NAMES = { "Pip", "Mochi", "Bean", "Nugget", "Tofu", "Pickle", "Sprout", "Button", "Gummy", "Dot", "Waffle", "Biscuit" }

	local function startMatch(players)
		if api.feed then
			local names = {}
			for _, p in players do table.insert(names, p.DisplayName) end
			api.feed("Dog Park round started  ·  " .. table.concat(names, ", "), "park")
		end
		local t0 = now() + PK.FreezeTime
		match = {
			people = {}, order = {}, entities = {}, projs = {}, nextId = 100, dogCount = 0, humanCount = 0,
			t0 = t0, over = false, tier = 1, nextEvent = t0 + 32, spawnT = 0, snapT = 0,
			hearts = {}, nextHeart = t0 + PK.HeartFirst,
		}
		local total = math.max(#players, math.min(PK.MinTotal, #players + PK.MinTotal))
		if #players >= PK.MinTotal then total = #players end
		local names = table.clone(BOT_NAMES)
		local idx = 0
		for _, player in players do
			idx += 1
			local s = api.sessions[player]
			local p = { id = idx, player = player, name = player.DisplayName, alive = true, char = s and s.data.EquippedCharacter or "Glow", outfit = s and s.data.EquippedOutfit or "None" }
			match.people[p.id] = p
			table.insert(match.order, p)
		end
		while #match.order < total do
			idx += 1
			local c = Config.Characters[rng:NextInteger(1, #Config.Characters)]
			local name = table.remove(names, rng:NextInteger(1, #names)) or ("Bot" .. idx)
			local p = { id = idx, bot = true, name = name, alive = true, char = c.id, outfit = Config.Outfits[rng:NextInteger(1, #Config.Outfits)].id, skill = rng:NextNumber(0.35, 0.9), react = 0, want = Vector3.zero }
			match.people[p.id] = p
			table.insert(match.order, p)
		end
		match.placeCounter = #match.order + 1
		-- teleport everyone to the spawn ring, frozen for the countdown
		local roster = {}
		for i, p in match.order do
			local sp = Places.arenaSpawn(i, #match.order)
			local face = math.atan2(-sp.X, -sp.Z)
			if p.bot then
				p.x, p.z, p.h, p.v = sp.X, sp.Z, face, 0
			else
				p.player:SetAttribute("ParkOut", nil)
				api.placeCharacter(p.player, CFrame.new(Places.ARENA + sp + Vector3.new(0, 3, 0)) * CFrame.Angles(0, face, 0), "park")
				api.freeze(p.player, true)
			end
			table.insert(roster, { id = p.id, userId = p.player and p.player.UserId or nil, name = p.name, bot = p.bot, char = p.char, outfit = p.outfit })
		end
		fireMatch("start", { t0 = t0, roster = roster, total = #match.order })
		task.delay(PK.FreezeTime, function()
			if not match then return end
			for _, p in match.order do
				if p.player then api.freeze(p.player, false) end
			end
		end)
		-- a calm park to start: a couple of dogs + one walker
		spawnDog(2, "chaser")
		spawnDog(1, "zoomer")
		spawnHuman("walker")
	end

	local function populate(c)
		local wantDogs = math.floor(2 + 10 * math.min(c, 1) + math.max(0, c - 1) * 8)
		local wantHumans = math.floor(1 + 6 * math.min(c, 1) + math.max(0, c - 1) * 5)
		wantDogs = math.min(wantDogs, 16)
		wantHumans = math.min(wantHumans, 10)
		if match.dogCount < wantDogs then
			local variant = c > 0.35 and rng:NextNumber() < 0.3 and 5 or rng:NextInteger(1, 4)
			spawnDog(variant, rng:NextNumber() < 0.35 and "zoomer" or "chaser")
		end
		if match.humanCount < wantHumans then
			local roll = rng:NextNumber()
			spawnHuman(c > 0.3 and roll < 0.3 and "jogger" or roll < 0.55 and "owner" or "walker")
		end
	end

	local function finish(alive)
		local t = now()
		-- survivors rank above everyone who was caught
		local ranked = table.clone(match.order)
		for _, p in alive do
			p.outAt = t
		end
		table.sort(ranked, function(a, b)
			if a.alive ~= b.alive then return a.alive end
			return (a.outAt or t) > (b.outAt or t)
		end)
		local winner = ranked[1]
		if api.feed and winner then api.feed(winner.name .. (winner.bot and " (bot)" or "") .. " won Dog Park Survival!", winner.bot and "info" or "best") end
		local results = {}
		for i, p in ranked do
			local secs = math.max(0, (p.outAt or t) - match.t0)
			table.insert(results, { id = p.id, name = p.name, bot = p.bot, place = i, time = secs, char = p.char, outfit = p.outfit })
			if p.player and p.player.Parent then
				local coins = math.floor(secs * 0.6) + (i == 1 and 150 or i == 2 and 80 or i == 3 and 50 or 10)
				local xp = math.floor(secs * 1.2) + (i == 1 and 120 or 20)
				p.reward = api.grant(p.player, coins, xp, function(d)
					d.SurvivalPlayed = (d.SurvivalPlayed or 0) + 1
					if i == 1 then d.SurvivalWins = (d.SurvivalWins or 0) + 1 end
					d.BestSurvival = math.max(d.BestSurvival or 0, math.floor(secs))
					if api.bump then
						api.bump(d, "parkPlayed", 1)
						api.bump(d, "parkBest", math.floor(secs))
						if i == 1 then api.bump(d, "parkWins", 1) end
					end
				end, math.max(0, t - match.t0))
			end
		end
		for _, p in match.order do
			if p.player and p.player.Parent and not p.gone then
				Event:FireClient(p.player, "results", { winner = results[1], results = results, reward = p.reward, duration = t - match.t0, you = p.id })
			end
		end
		local m = match
		task.delay(PK.ResultsTime, function()
			for i, p in m.order do
				if p.player and p.player.Parent and not p.gone then
					p.player:SetAttribute("ParkOut", nil)
					local a = (i / #m.order) * math.pi * 2
					local at = Places.HUB + Places.HubReturnFromPark + Vector3.new(math.cos(a) * 10, 3, math.sin(a) * 6)
					api.placeCharacter(p.player, CFrame.new(at) * CFrame.Angles(0, math.pi, 0), "hub")
					api.freeze(p.player, false)
				end
			end
			if match == m then match = nil end
			fireAll("idle", {})
		end)
	end

	---------------------------------------------------------------------------
	-- CLIENT REPORTS ("a foot just came down on me")
	---------------------------------------------------------------------------
	Event.OnServerEvent:Connect(function(player, kind, data)
		if kind == "leave" then
			-- walk out of the round: you're out (if still alive) and back on the table
			if not match then return end
			for _, p in match.order do
				if p.player == player and not p.gone then
					p.gone = true
					p.safeUntil = 0
					if p.alive then eliminate(p, "left") end
					player:SetAttribute("ParkOut", nil)
					api.placeCharacter(player, CFrame.new(Places.HUB + Places.HubReturnFromPark + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.pi, 0), "hub")
					api.freeze(player, false)
					Event:FireClient(player, "left", {})
				end
			end
			return
		end
		if kind ~= "hit" or not match or match.over or type(data) ~= "table" then return end
		local me
		for _, p in match.people do
			if p.player == player then me = p end
		end
		if not me or not me.alive or now() < match.t0 + 1 then return end
		local pos = feetRel(player)
		if not pos then return end
		-- sanity: the thing that got you must actually be near you on the server too
		local src = match.entities[data.id] or match.projs[data.id]
		if not src then return end
		local sp = src.x and Vector3.new(src.x, 0, src.z) or (Places.projAt(src, now()) or src.to)
		if (Vector3.new(sp.X - pos.X, 0, sp.Z - pos.Z)).Magnitude > 45 then return end
		local how = data.how == "caught" and "caught" or data.how == "stomped" and "stomped" or data.how == "bonked" and "bonked" or "squished"
		eliminate(me, how, data.id)
	end)

	---------------------------------------------------------------------------
	-- MAIN LOOP (20Hz sim, 10Hz snapshots)
	---------------------------------------------------------------------------
	local acc = 0
	RunService.Heartbeat:Connect(function(frameDt)
		acc += frameDt
		if acc < 1 / 20 then return end
		local dt = math.min(acc, 0.1)
		acc = 0
		local t = now()

		-- waiting pen + countdown (between rounds)
		if not match then
			local waiting = {}
			for _, player in Players:GetPlayers() do
				local _, hrp = charOf(player)
				if hrp and player:GetAttribute("Activity") == "hub" and Places.inPen(hrp.Position) then
					table.insert(waiting, player)
				end
			end
			if #waiting > 0 then
				local full = #waiting >= PK.MaxPlayers
				local wantEnd = t + (IS_STUDIO and PK.StudioCountdown or PK.Countdown)
				pen.endsAt = pen.endsAt or wantEnd
				if #waiting >= 8 then pen.endsAt = math.min(pen.endsAt, t + PK.FullCountdown) end
				if full then pen.endsAt = math.min(pen.endsAt, t + 3) end
				if t >= pen.endsAt then
					pen.endsAt = nil
					local chosen = {}
					for i = 1, math.min(#waiting, PK.MaxPlayers) do chosen[i] = waiting[i] end
					startMatch(chosen)
				end
			else
				pen.endsAt = nil
			end
			pen.n = #waiting
		end

		if match and not match.over then
			local c = math.max(0, t - match.t0)
			local chaos = Places.chaos(c)
			if match.ghostUntil and t >= match.ghostUntil then
				match.over = true
				local alive = aliveList()
				task.defer(function() match.finish(alive) end)
			end
			if t >= match.t0 and not match.over then
				-- chaos meter tier
				local tier = Places.parkTier(c)
				if tier ~= match.tier then
					match.tier = tier
					fireMatch("tier", tier)
				end
				match.spawnT -= dt
				if match.spawnT <= 0 then
					match.spawnT = math.max(0.8, 3.5 - 2.5 * math.min(chaos, 1))
					populate(chaos)
				end
				if t >= match.nextEvent then
					match.nextEvent = t + rng:NextNumber(18, 28) * (1.25 - 0.55 * math.min(chaos, 1))
					local kind = EVENT_ORDER[rng:NextInteger(1, math.clamp(math.floor(2 + chaos * 5), 2, #EVENT_ORDER))]
					local title = EVENTS[kind]()
					fireMatch("event", { kind = kind, title = title, t0 = t, sprinklers = match.sprinklers })
				end
				for _, e in match.entities do
					if e.kind == KIND.dog then dogThink(e, dt, chaos) else humanThink(e, dt, chaos) end
					e.ph += Rules.phaseRate(e) * dt
				end
				for _, p in match.order do
					if p.alive and p.bot then botThink(p, dt, chaos) end
				end
				-- heart pickups: rare, one held at most, they don't hang around
				local live = 0
				for id, h in match.hearts do
					if t > h.t0 + PK.HeartLife then
						match.hearts[id] = nil
						fireMatch("heart", { id = id, gone = true })
					else
						live += 1
					end
				end
				if t >= match.nextHeart then
					match.nextHeart = t + rng:NextNumber(PK.HeartEvery[1], PK.HeartEvery[2])
					local alive = aliveList()
					if live < math.max(1, math.ceil(#alive / 4)) then
						local x, z = randomSpot(40)
						local h = { id = newId(), x = x, z = z, t0 = t }
						match.hearts[h.id] = h
						fireMatch("heart", { id = h.id, x = x, z = z })
					end
				end
				for id, h in match.hearts do
					for _, p in match.order do
						if p.alive and (p.hearts or 0) < PK.HeartMax then
							local pos = posOf(p)
							if pos and (Vector3.new(pos.X - h.x, 0, pos.Z - h.z)).Magnitude < 4.5 then
								p.hearts = (p.hearts or 0) + 1
								match.hearts[id] = nil
								fireMatch("heart", { id = id, by = p.id, name = p.name })
								break
							end
						end
					end
				end
			end
			-- velocities of real players (dogs lead their targets a little)
			for _, p in match.order do
				if p.alive and p.player then
					local pos = feetRel(p.player)
					if pos and p.lastPos then p.vel = (pos - p.lastPos) / dt end
					p.lastPos = pos
					local _, _, hum = charOf(p.player)
					if not p.player.Parent or not hum or hum.Health <= 0 or (pos and pos.Y < -30) then
						eliminate(p, "fell")
					end
				end
			end
			-- server hit checks: bots get the full check, players a strict core-only
			-- one (their own client does the fair, generous check and reports it)
			if t >= match.t0 + 1 then
				for _, p in match.order do
					if p.alive then
						local pos = posOf(p)
						if pos then
							local world = Places.ARENA + pos
							local cover = Places.coverAt(pos)
							local margin = p.bot and Rules.PLAYER_R or -0.4
							local how, by
							for _, e in match.entities do
								how = Rules.entityHit(e, world, margin, cover)
								if how then by = e.id break end
							end
							if not how then
								for _, pr in match.projs do
									how = Rules.projHit(pr, world, t, margin, cover)
									if how then by = pr.id break end
								end
							end
							if how then eliminate(p, how, by) end
						end
					end
				end
			end
			-- expire thrown things
			for id, pr in match.projs do
				if t > pr.t0 + pr.T + 6 then match.projs[id] = nil end
			end
			-- snapshot
			match.snapT -= dt
			if match.snapT <= 0 and not match.over then
				match.snapT = 0.1
				local list = {}
				for _, e in match.entities do table.insert(list, e) end
				for _, p in match.order do
					if p.bot and p.alive then
						table.insert(list, { id = p.id, kind = KIND.bot, x = p.x, z = p.z, h = p.h or 0, v = p.v or 0, ph = 0, st = 0, stT = 0 })
					end
				end
				local pack = Rules.pack(list, t)
				for _, p in match.order do
					if p.player and p.player.Parent then Snap:FireClient(p.player, pack) end
				end
			end
		end
		if match then match.finish = finish end
	end)

	-- pen / round status for everyone in the hub (the sign + the pen HUD)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local alive, total = 0, 0
			if match then
				for _, p in match.order do
					total += 1
					if p.alive then alive += 1 end
				end
			end
			fireAll("pen", { n = pen.n or 0, max = PK.MaxPlayers, endsAt = pen.endsAt, running = match ~= nil, alive = alive, total = total })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if not match then return end
		for _, p in match.order do
			if p.player == player and p.alive then eliminate(p, "left") end
		end
	end)

	return {}
end
