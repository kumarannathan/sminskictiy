-- CitySound (client): the city you can hear.
--
-- Audio.lua is the game's 2D sound: music, UI clicks, the chase. It is fine
-- at what it does and none of it is positional, which is most of what a town
-- needs -- a car should get louder as it comes past you and quieter behind,
-- and rain should stop when you step through a door.
--
-- EVERY SOUND HERE IS BUILT FROM TEN ENGINE BUILT-INS (Config.Sounds.City).
-- They were probed in-engine and all load, so nothing can go missing from the
-- marketplace. They are raw material, not finished sounds: a wind rush
-- low-passed and slowed is a distant sea; the same rush sped up and
-- high-passed is rain on a pavement; a one-second bass tone looped at a
-- quarter speed is a diesel engine. Shaping is PlaybackSpeed + an equaliser.
--
-- COST IS BOUNDED THE SAME WAY THE STREET LIGHTS ARE. A Sound per car and per
-- shop would be hundreds of emitters; instead there is a small POOL of
-- positional emitters that is re-homed to whatever is nearest you, a few
-- times a second (performance.md: no unbounded per-object anything).
--   deps: K, Places, Config, UI, player, City

return function(deps)
	local K, Places, Config, player, City = deps.K, deps.Places, deps.Config, deps.player, deps.City
	local V = K.V
	local SoundService = game:GetService("SoundService")
	local S = Config.Sounds.City
	local CITY = Places.CITY
	local Snd = { on = true }

	local root = Instance.new("Folder")
	root.Name = "SminskiCitySound"
	root.Parent = SoundService
	local group = Instance.new("SoundGroup")
	group.Name = "City"
	group.Volume = 1
	group.Parent = root

	local function mk(parent, id, vol, speed, looped)
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = vol or 0
		s.PlaybackSpeed = speed or 1
		s.Looped = looped ~= false
		s.SoundGroup = group
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = parent
		return s
	end
	local function eq(s, lo, mid, hi)
		local e = Instance.new("EqualizerSoundEffect")
		e.LowGain, e.MidGain, e.HighGain = lo, mid, hi
		e.Parent = s
		return e
	end
	local function toward(s, target, dt, rate)
		s.Volume += (target - s.Volume) * math.min(1, dt * (rate or 2))
	end

	---------------------------------------------------------------------------
	-- THE BEDS: non-positional, crossfaded by where you are
	---------------------------------------------------------------------------
	local beds = {}
	do
		-- town: a low roll of distant traffic
		beds.town = mk(root, S.Air, 0, 0.42)
		eq(beds.town, 4, -6, -22)
		-- the sea, out at the harbour
		beds.sea = mk(root, S.Water, 0, 0.55)
		eq(beds.sea, 2, -3, -12)
		-- open country: wind in the grass, thinner and higher
		beds.country = mk(root, S.Air, 0, 0.3)
		eq(beds.country, -6, -6, -14)
		-- rain on the pavement
		beds.rain = mk(root, S.Air, 0, 1.35)
		eq(beds.rain, -14, -2, 6)
		-- wind, which rises with the weather
		beds.wind = mk(root, S.Air, 0, 0.62)
		eq(beds.wind, -4, -4, -6)
		for name, b in beds do
			b.Name = "Bed_" .. name
			b:Play()
		end
	end

	---------------------------------------------------------------------------
	-- THE POOL: positional emitters, re-homed to whatever is nearest
	---------------------------------------------------------------------------
	local POOL = 12
	local pool = {}
	for i = 1, POOL do
		local holder = Instance.new("Part")
		holder.Name = "CitySoundEmitter" .. i
		holder.Size = V(1, 1, 1)
		holder.Transparency = 1
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
		holder.Parent = K.actors
		local e = {
			part = holder,
			engine = mk(holder, S.Tone, 0, 0.32),
			extra = mk(holder, S.Air, 0, 0.7),
			busy = nil,
		}
		e.engine.RollOffMaxDistance = 150
		e.engine.RollOffMinDistance = 12
		e.extra.RollOffMaxDistance = 120
		e.extra.RollOffMinDistance = 10
		eq(e.engine, 8, -4, -22)
		eq(e.extra, -10, -4, -2)
		e.engine:Play()
		e.extra:Play()
		pool[i] = e
	end

	-- one-shots, positional, from a small rotating set
	local shots, shotI = {}, 1
	for i = 1, 6 do
		local holder = Instance.new("Part")
		holder.Name = "CityShot" .. i
		holder.Size = V(1, 1, 1)
		holder.Transparency = 1
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
		holder.Parent = K.actors
		local s = mk(holder, S.Click, 0, 1, false)
		s.RollOffMaxDistance = 120
		s.RollOffMinDistance = 8
		shots[i] = { part = holder, snd = s }
	end
	-- play a one-shot somewhere in the world (pos is city-relative)
	function Snd.at(pos, id, vol, pitch)
		if not Snd.on then return end
		local e = shots[shotI]
		shotI = shotI % #shots + 1
		e.part.CFrame = CFrame.new(CITY + pos)
		e.snd.SoundId = id
		e.snd.Volume = vol or 0.4
		e.snd.PlaybackSpeed = pitch or 1
		e.snd.TimePosition = 0
		e.snd:Play()
	end
	-- named, so callers do not repeat asset ids
	function Snd.door(pos) Snd.at(pos, S.Switch, 0.35, 0.9 + math.random() * 0.2) end
	function Snd.till(pos) Snd.at(pos, S.Ping, 0.3, 1.1) end
	function Snd.splash(pos) Snd.at(pos, S.Splash, 0.45, 1) end
	function Snd.horn(pos) Snd.at(pos, S.Tone, 0.5, 2.6 + math.random() * 0.4) end

	---------------------------------------------------------------------------
	-- WHAT IS NEAR ME, AND WHAT SHOULD IT SOUND LIKE?
	---------------------------------------------------------------------------
	local function flat(v) return V(v.X, 0, v.Z) end
	local claimT = 0
	local function reassign(me)
		-- gather candidate emitters: moving cars first, then fixed sources
		local want = {}
		for _, c in City.trafficList() do
			if c.cf then
				local p = c.cf.Position - CITY
				local d = (flat(p) - flat(me)).Magnitude
				if d < 170 then
					table.insert(want, { d = d, pos = p, kind = c.kind == "bus" and "bus" or "car", speed = math.abs(c.speed or 0) })
				end
			end
		end
		for _, f in Snd.fixed do
			local d = (flat(f.pos) - flat(me)).Magnitude
			if d < (f.range or 150) then
				table.insert(want, { d = d, pos = f.pos, kind = f.kind, speed = 0 })
			end
		end
		table.sort(want, function(a, b) return a.d < b.d end)
		for i, e in pool do
			local w = want[i]
			if w then
				e.part.CFrame = CFrame.new(CITY + w.pos + V(0, 2, 0))
				e.busy = w.kind
				if w.kind == "car" or w.kind == "bus" then
					local k = math.clamp(w.speed / 46, 0, 1)
					e.engine.PlaybackSpeed = (w.kind == "bus" and 0.2 or 0.28) + k * 0.2
					e.engine.Volume = (w.kind == "bus" and 0.5 or 0.34) * (0.35 + k * 0.65)
					e.extra.PlaybackSpeed = 0.9 + k * 0.5
					e.extra.Volume = k * 0.1                      -- tyre roar
				elseif w.kind == "sea" then
					e.engine.Volume = 0
					e.extra.SoundId = S.Water
					e.extra.PlaybackSpeed = 0.6
					e.extra.Volume = 0.45
				elseif w.kind == "fire" then
					e.engine.Volume = 0
					e.extra.SoundId = S.Air
					e.extra.PlaybackSpeed = 1.1
					e.extra.Volume = 0.16
				elseif w.kind == "crowd" then
					e.engine.Volume = 0
					e.extra.Volume = 0
				elseif w.kind == "train" then
					e.engine.PlaybackSpeed = 0.22
					e.engine.Volume = 0.6
					e.extra.SoundId = S.Air
					e.extra.PlaybackSpeed = 1.2
					e.extra.Volume = 0.2
				else
					e.engine.Volume = 0
					e.extra.Volume = 0
				end
			else
				e.busy = nil
				e.engine.Volume = 0
				e.extra.Volume = 0
			end
		end
	end

	-- fixed sources registered by whoever builds them
	Snd.fixed = {}
	function Snd.register(kind, pos, range)
		table.insert(Snd.fixed, { kind = kind, pos = pos, range = range })
	end

	---------------------------------------------------------------------------
	-- CHATTER + BIRDS: sparse one-shots, so a crowd sounds like people rather
	-- than a loop of people
	---------------------------------------------------------------------------
	local chatT, birdT, thunderT = 0, 0, 0
	local function sparse(dt, me, look)
		chatT -= dt
		if chatT <= 0 then
			chatT = 2.2 + math.random() * 4
			local best, bd
			for _, f in Snd.fixed do
				if f.kind == "crowd" then
					local d = (flat(f.pos) - flat(me)).Magnitude
					if d < 110 and (not bd or d < bd) then best, bd = f, d end
				end
			end
			if best then
				local off = V(math.random(-18, 18), 0, math.random(-18, 18))
				Snd.at(best.pos + off, S.Voice, 0.16 + math.random() * 0.1, 0.8 + math.random() * 0.8)
			end
		end
		-- birds, but only in daylight and only in fair weather
		birdT -= dt
		if birdT <= 0 then
			birdT = 3 + math.random() * 6
			local hour = look and look.hour or 12
			local wet = look and look.wet or 0
			if hour > 6 and hour < 19 and wet < 0.1 then
				for _, f in Snd.fixed do
					if f.kind == "park" and (flat(f.pos) - flat(me)).Magnitude < 130 then
						Snd.at(f.pos + V(math.random(-30, 30), 14, math.random(-30, 30)), S.Ping, 0.1, 2.4 + math.random() * 0.9)
						break
					end
				end
			end
		end
		-- thunder, in a storm only
		thunderT -= dt
		if thunderT <= 0 then
			thunderT = 7 + math.random() * 12
			if look and look.state and look.state.id == "storm" then
				local p = me + V(math.random(-250, 250), 120, math.random(-250, 250))
				Snd.at(p, S.Tone, 0.9, 0.16 + math.random() * 0.06)
			end
		end
	end

	---------------------------------------------------------------------------
	-- PER FRAME
	---------------------------------------------------------------------------
	function Snd.enter()
		Snd.on = true
		for _, b in beds do if not b.IsPlaying then b:Play() end end
	end
	function Snd.leave()
		Snd.on = false
		for _, b in beds do b.Volume = 0 end
		for _, e in pool do e.engine.Volume = 0 e.extra.Volume = 0 end
	end

	function Snd.step(dt, t, me)
		if not Snd.on then return end
		local look = City.Weather and City.Weather.look()
		local wet = look and look.wet or 0
		-- are you under a roof? the same test the rain uses
		local indoors = City.Apts and City.Apts.inside
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local underCover = false
		if hrp and not indoors then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { K.actors, player.Character }
			underCover = workspace:Raycast(hrp.Position + V(0, 2, 0), V(0, 90, 0), rp) ~= nil
		end
		local muffle = (indoors or underCover) and 0.25 or 1

		-- which bed? distance from the middle of town decides it
		local d = flat(me).Magnitude
		local seaK = math.clamp((me.Z - 760) / 260, 0, 1)
		local countryK = math.clamp((math.max(math.abs(me.X), math.abs(me.Z)) - 540) / 380, 0, 1) * (1 - seaK)
		local townK = math.clamp(1 - countryK - seaK, 0, 1)
		toward(beds.town, 0.2 * townK * muffle, dt, 1.2)
		toward(beds.sea, 0.28 * seaK * muffle, dt, 1.2)
		toward(beds.country, 0.14 * countryK * muffle, dt, 1.2)
		toward(beds.rain, (indoors and 0.05 or underCover and 0.12 or 0.34) * wet, dt, 1.5)
		local windK = look and math.clamp((look.atm[6] - 1.45) / 1.2, 0, 1) or 0
		toward(beds.wind, (0.05 + windK * 0.16) * muffle, dt, 0.8)

		claimT += dt
		if claimT > 0.28 then
			claimT = 0
			reassign(me)
		end
		sparse(dt, me, look)
	end

	return Snd
end
