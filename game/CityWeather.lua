-- CityWeather (client): puts Weather.lua on the screen.
--   W.enter() / W.leave()      take and give back the sky
--   W.step(dt, t, me)          the day curve, rain, fog, street lamps
--   W.look()                   the current look (signs + the ribbon read this)
--
-- Three things here are deliberate and were each a bug waiting to happen:
--
-- 1. WHO OWNS Lighting. applyLook("city") hard-sets ClockTime 14.6 and runs
--    again on EVERY return from a run or the dog park. Left alone that is a
--    full-noon flash each time you come back. So this module takes ownership
--    while you are in the city, and City.enter applies the first frame
--    synchronously rather than waiting for a tick.
--
-- 2. RAIN INDOORS. The city's walk-in rooms (cafes, shops, the arcade, the
--    cinema) are roofed boxes standing in the open world -- only houses and
--    flats are teleported underground. So "am I inside?" cannot be a flag;
--    it has to be a raycast straight up, and the emitter shuts off when
--    something is over your head.
--
-- 3. STREET LAMPS AT NIGHT. K.lamp builds a glowing ball and no light at all,
--    so at 2am the town was lit by nothing. Adding a PointLight per lamp
--    would be ~750 lights (performance.md forbids it). Instead lamps register
--    their parts at build time and a POOL OF EIGHT lights is re-parented to
--    whichever eight are nearest you, twice a second.
--   deps: K, Places, Weather, UI, player

return function(deps)
	local K, Places, Weather, UI, player = deps.K, deps.Places, deps.Weather, deps.UI, deps.player
	local V, rgb = K.V, K.rgb
	local Lighting = game:GetService("Lighting")
	local CITY = Places.CITY
	local W = { active = false }

	local LAMP_LIGHTS = 8
	local pool, fx, rain, rainPart = {}, {}, nil, nil
	local cur -- the look we last applied

	---------------------------------------------------------------------------
	-- LIGHTING
	---------------------------------------------------------------------------
	local function effect(class, name)
		local e = Lighting:FindFirstChild(name)
		if not e or not e:IsA(class) then
			if e then e:Destroy() end
			e = Instance.new(class)
			e.Name = name
			e.Parent = Lighting
		end
		return e
	end
	local function apply(f)
		Lighting.ClockTime = f.clock
		Lighting.Brightness = f.bright
		Lighting.Ambient = f.amb
		Lighting.OutdoorAmbient = f.out
		Lighting.ExposureCompensation = f.exp
		Lighting.ShadowSoftness = f.shadow
		Lighting.GlobalShadows = true
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 1
		local atm = effect("Atmosphere", "Atmosphere")
		atm.Density, atm.Offset, atm.Color, atm.Decay, atm.Glare, atm.Haze = table.unpack(f.atm)
		local bloom = effect("BloomEffect", "Bloom")
		bloom.Intensity, bloom.Size, bloom.Threshold = table.unpack(f.bloom)
		local cc = effect("ColorCorrectionEffect", "SminskiGrade")
		cc.Saturation, cc.Contrast, cc.TintColor, cc.Brightness = f.grade[1], f.grade[2], f.grade[3], 0.02
		local rays = effect("SunRaysEffect", "SunRays")
		rays.Intensity, rays.Spread = f.rays, 0.8
		local dof = effect("DepthOfFieldEffect", "SminskiDOF")
		dof.FarIntensity, dof.FocusDistance, dof.InFocusRadius, dof.NearIntensity = 0.12, 120, 400, 0
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		local clouds = terrain and (terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds", terrain))
		if clouds then
			clouds.Cover, clouds.Density, clouds.Color, clouds.Enabled = f.clouds[1], f.clouds[2], f.clouds[3], true
		end
		cur = f
	end

	---------------------------------------------------------------------------
	-- RAIN: one emitter that rides above the camera, off when under cover
	---------------------------------------------------------------------------
	local coverParams = RaycastParams.new()
	coverParams.FilterType = Enum.RaycastFilterType.Exclude
	local function buildRain()
		if rainPart then return end
		rainPart = Instance.new("Part")
		rainPart.Name = "SminskiRain"
		rainPart.Size = V(1, 1, 1)
		rainPart.Transparency = 1
		rainPart.Anchored, rainPart.CanCollide, rainPart.CanQuery, rainPart.CanTouch = true, false, false, false
		rainPart.Parent = K.actors
		local e = Instance.new("ParticleEmitter")
		e.Name = "Drops"
		e.Texture = "rbxassetid://241629053"
		e.Color = ColorSequence.new(rgb(196, 220, 236))
		e.LightEmission = 0.2
		e.LightInfluence = 0.6
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.22) })
		e.Speed = NumberRange.new(112, 138)
		e.Lifetime = NumberRange.new(0.85, 1.05)
		e.Rate = 0
		e.Rotation = NumberRange.new(-4, 4)
		e.SpreadAngle = Vector2.new(3, 3)
		e.Acceleration = V(0, -46, 0)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.Size = e.Size
		e.Squash = NumberSequence.new(4.5) -- streaks, not dots
		e.Parent = rainPart
		rain = e
	end
	local coverT, covered = 0, false
	local function underCover(hrp, dt)
		coverT += dt
		if coverT < 0.3 then return covered end
		coverT = 0
		coverParams.FilterDescendantsInstances = { K.actors, player and player.Character or workspace }
		local hit = workspace:Raycast(hrp.Position + V(0, 2, 0), V(0, 90, 0), coverParams)
		covered = hit ~= nil
		return covered
	end

	---------------------------------------------------------------------------
	-- STREET LAMPS: eight lights, re-homed to the nearest eight lamp posts
	---------------------------------------------------------------------------
	local lampT = 0
	local function buildPool()
		if #pool > 0 then return end
		for i = 1, LAMP_LIGHTS do
			local l = Instance.new("PointLight")
			l.Name = "StreetLamp" .. i
			l.Range = 46
			l.Brightness = 0
			l.Color = rgb(255, 226, 170)
			l.Shadows = false
			l.Enabled = false
			l.Parent = rainPart or K.actors
			pool[i] = l
		end
	end
	local function stepLamps(dt, me, lampK)
		lampT += dt
		if lampT < 0.5 then return end
		lampT = 0
		local lamps = K.lampGlobes
		if not lamps or #lamps == 0 then return end
		if lampK <= 0.02 then
			for _, l in pool do l.Enabled = false end
			return
		end
		-- the nearest few, by insertion into a small fixed list
		local best = {}
		for _, g in lamps do
			if g.Parent then
				local d = (V(g.Position.X, 0, g.Position.Z) - V(me.X + CITY.X, 0, me.Z + CITY.Z)).Magnitude
				if d < 190 then
					local at = #best + 1
					for i = 1, #best do if d < best[i].d then at = i break end end
					if at <= LAMP_LIGHTS then
						table.insert(best, at, { d = d, g = g })
						if #best > LAMP_LIGHTS then table.remove(best) end
					end
				end
			end
		end
		for i, l in pool do
			local b = best[i]
			if b then
				l.Parent = b.g
				l.Brightness = 1.15 * lampK
				l.Enabled = true
			else
				l.Enabled = false
			end
		end
	end

	---------------------------------------------------------------------------
	-- LAMP GLOBES + LIT WINDOWS follow the hour
	---------------------------------------------------------------------------
	local glowT = 0
	local function stepGlow(dt, lampK)
		glowT += dt
		if glowT < 0.5 then return end
		glowT = 0
		for _, g in K.lampGlobes or {} do
			if g.Parent then g.Transparency = 1 - math.clamp(lampK * 1.2, 0, 1) * 0.94 end
		end
	end

	---------------------------------------------------------------------------
	-- PUBLIC
	---------------------------------------------------------------------------
	function W.look() return cur end
	function W.now()
		return (W.debugHour and W.debugHour * (Weather.DAY / 24)) or workspace:GetServerTimeNow()
	end
	function W.current()
		local f = cur or Weather.lookAt(workspace:GetServerTimeNow())
		return { hour = f.hour, state = f.state, clock = Weather.clockText(f.hour or 0) }
	end

	function W.enter()
		W.active = true
		buildRain()
		buildPool()
		-- apply the first frame NOW: applyLook has just forced noon, and a tick
		-- of delay is a visible flash on every return from a run
		W.step(0, 0, Vector3.zero, true)
	end
	function W.leave()
		W.active = false
		if rain then rain.Rate = 0 end
		for _, l in pool do l.Enabled = false end
	end

	local acc = 0
	function W.step(dt, t, me, force)
		if not W.active then return end
		acc += dt
		if not force and acc < 0.25 then return end
		acc = 0
		local now = workspace:GetServerTimeNow()
		local f = Weather.lookAt(now, W.debugHour, W.debugState)
		apply(f)
		local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if rainPart and hrp then
			rainPart.CFrame = CFrame.new(hrp.Position + V(0, 46, 0))
			rainPart.Size = V(120, 6, 120)
			local wet = f.wet
			if wet > 0 and underCover(hrp, 0.3) then wet = 0 end
			rain.Rate = wet * 420
			rain.Speed = NumberRange.new(112 + wet * 26, 138 + wet * 30)
		end
		stepLamps(0.5, me, f.lamps)
		stepGlow(0.5, f.lamps)
	end

	return W
end
