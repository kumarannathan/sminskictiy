-- CityHangouts (client): three places to be with other people.
--
-- These are REAL PLACES IN THE SHARED WORLD, not instanced rooms. That is the
-- whole distinction: your flat is built per-player on a private pitch, so two
-- neighbours never meet in it -- which is right for a home and useless for a
-- hangout. Everything here stands in the city where everyone can walk to it,
-- see each other's Sminskis, and sit down together.
--
-- Each one is built ONTO SOMETHING THAT ALREADY EXISTS rather than beside it:
--   THE CONCERT LAWN  the stage block already has a stage, a band and a crowd
--                     and no way to take part. Now it has a lawn to sit on
--                     and a dance floor in front.
--   THE BOARDWALK     the harbour already has piers, boats and a lighthouse.
--                     Now it has benches facing the water and a fire to sit at.
--   THE BANDSTAND     Button Park already has a gazebo. Now it has seats.
--
-- Poses are PUBLISHED (City.setPose -> the server's "pose" action) so the
-- other people at a hangout actually see you sitting and dancing.
--   deps: K, Build, Places, Models, UI, Audio, S, player, City

return function(deps)
	local K, Build, Places, Models = deps.K, deps.Build, deps.Places, deps.Models
	local UI, Audio, S, player, City = deps.UI, deps.Audio, deps.S, deps.player, deps.City
	local V, rgb, shade, tint = K.V, K.rgb, K.shade, K.tint
	local P, cyl, ball, blob, solid, walkable = K.P, K.cyl, K.ball, K.blob, K.solid, K.walkable
	local Cc = K.C
	local MATTE, WOODM, NEON, SMOOTH, METAL = K.MATTE, K.WOODM, K.NEON, K.SMOOTH, K.METAL
	local FABRIC = Enum.Material.Fabric
	local PAD = K.PAD_Y
	local CITY = Places.CITY
	local H = { spots = {}, flicker = {}, floor = {}, lanterns = {} }

	local function myChar()
		local c = player and player.Character
		return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
	end
	local function flat(v) return V(v.X, 0, v.Z) end
	local function W(x, y, z) return CFrame.new(CITY + V(x, y, z)) end

	-- a thing you can do here. `seat` pins you; `pose` is what everyone sees.
	local function spot(cf, title, sub, btn, icon, act)
		table.insert(H.spots, { pos = cf.Position - CITY, title = title, sub = sub, btn = btn, icon = icon, act = act })
	end

	---------------------------------------------------------------------------
	-- SHARED FURNITURE
	---------------------------------------------------------------------------
	local BLANKET = { rgb(236, 130, 130), rgb(120, 170, 220), rgb(240, 200, 110), rgb(150, 200, 150), rgb(200, 150, 220) }
	local function blanket(cf, col, i)
		P(V(13, 0.14, 13), cf * CFrame.new(0, 0.07, 0), col, FABRIC, { noShadow = true })
		P(V(11.6, 0.18, 11.6), cf * CFrame.new(0, 0.09, 0), tint(col, 0.3), FABRIC, { noShadow = true })
		-- a basket, and something to eat off it
		P(V(3, 1.8, 2.2), cf * CFrame.new(4, 0.9, 4), rgb(196, 156, 104), WOODM)
		P(V(3.2, 0.4, 2.4), cf * CFrame.new(4, 1.9, 4), rgb(216, 180, 130), WOODM)
		for k = 0, 2 do ball(1.1, cf * CFrame.new(-3 + k * 2.4, 0.6, -3.4), ({ rgb(240, 180, 200), rgb(250, 230, 170), rgb(180, 220, 170) })[k + 1]) end
		spot(cf * CFrame.new(0, 0, -2), "PICNIC BLANKET", "sit down, watch the band", "SIT", "heart",
			{ seat = cf * CFrame.new(0, 1.6, 1.4), pose = "sit" })
	end
	local function firepit(cf)
		cyl(11, 1, cf * CFrame.new(0, 0.5, 0), rgb(176, 176, 170))
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			P(V(2.4, 1.8, 1.6), cf * CFrame.new(math.cos(a) * 4.6, 1.3, math.sin(a) * 4.6) * CFrame.Angles(0, -a, 0), rgb(150, 146, 140))
		end
		for k = 0, 4 do
			P(V(0.9, 0.9, 6), cf * CFrame.new(0, 1.6 + k * 0.3, 0) * CFrame.Angles(0.3, k * 1.2, 0), rgb(140, 100, 72), WOODM)
		end
		local fire = ball(4.4, cf * CFrame.new(0, 3.2, 0), rgb(255, 170, 90), NEON)
		fire.CastShadow = false
		fire.Transparency = 0.25
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color, l.Shadows = 34, 1.4, rgb(255, 170, 100), false
		l.Parent = fire
		table.insert(H.flicker, fire)
		-- logs to sit on, round the fire
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + 0.4
			local lf = cf * CFrame.new(math.cos(a) * 13, 0, math.sin(a) * 13) * CFrame.Angles(0, -a + math.pi / 2, 0)
			solid(cyl(3.4, 11, lf * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(150, 110, 78), WOODM))
			if k == 0 then
				spot(lf * CFrame.new(0, 0, -4), "THE FIRE", "warm up, watch the boats", "SIT", "heart",
					{ seat = lf * CFrame.new(0, 3.4, 0), pose = "sit", lines = { "the sea is loud tonight", "someone should bring marshmallows" } })
			end
		end
	end

	---------------------------------------------------------------------------
	-- 1. THE CONCERT LAWN  (the stage block already has the stage and the band)
	---------------------------------------------------------------------------
	local function concertLawn()
		local cx, cz = -750, -150
		-- the lawn: this is the ONE paved-block exception, and it is deliberate.
		-- A lawn in front of an outdoor stage is what the place is for.
		P(V(180, 0.2, 90), W(cx, PAD + 0.1, cz - 60), rgb(132, 176, 104), MATTE, { noShadow = true })
		P(V(172, 0.24, 82), W(cx, PAD + 0.12, cz - 60), rgb(142, 186, 112), MATTE, { noShadow = true })
		-- blankets, offset so nobody is behind anybody
		local i = 0
		for _, dz in { -34, -58, -82 } do
			for _, dx in { -56, -28, 0, 28, 56 } do
				i += 1
				if (i % 3) ~= 0 then
					blanket(W(cx + dx + (dz == -58 and 14 or 0), PAD + 0.2, cz + dz), BLANKET[i % #BLANKET + 1], i)
				end
			end
		end
		-- a dance floor right at the front, lit from under the deck
		local df = W(cx, PAD, cz - 14)
		for a = 0, 3 do
			for b = 0, 3 do
				local t = P(V(11, 0.3, 11), df * CFrame.new(-16.5 + a * 11, 0.15, -16.5 + b * 11),
					(a + b) % 2 == 0 and rgb(236, 180, 220) or rgb(180, 210, 240), SMOOTH, { noShadow = true })
				table.insert(H.floor, t)
			end
		end
		spot(df, "THE DANCE FLOOR", "the band is playing -- go on", "DANCE", "star",
			{ pose = "cheer", hold = true, lines = { "nobody is watching. dance.", "the band nods at you", "you have MOVES" } })
		-- a drinks stand at the side, and bunting over the lawn
		local st = W(cx + 74, PAD, cz - 46)
		solid(P(V(16, 7, 8), st * CFrame.new(0, 3.5, 0), rgb(240, 180, 120), WOODM))
		P(V(18, 0.6, 10), st * CFrame.new(0, 7.3, 0), rgb(226, 120, 96))
		for k = -2, 2 do P(V(2.6, 0.5, 2.6), st * CFrame.new(k * 3, 7.6, 0), Cc.cream) end
		spot(st * CFrame.new(0, 0, -6), "THE DRINKS STAND", "something cold", "TAKE ONE", "bag",
			{ pose = "cheer", lines = { "ice cold. perfect.", "that hit the spot", "one lemonade, please" } })
		for k = 0, 8 do
			local x0 = cx - 88 + k * 22
			P(V(22, 0.2, 0.2), W(x0 + 11, PAD + 16 + math.sin(k) * 1.2, cz - 100), Cc.cream)
			for j = 0, 3 do
				P(V(1.8, 2.2, 0.1), W(x0 + 3 + j * 5, PAD + 15 + math.sin(k) * 1.2, cz - 100), K.FLOWER_COLS[(k + j) % 5 + 1], FABRIC)
			end
		end
	end

	---------------------------------------------------------------------------
	-- 2. THE BOARDWALK  (the harbour already has the piers, boats, lighthouse)
	---------------------------------------------------------------------------
	local function boardwalk()
		local z0 = 1010
		-- a deck along the front, with the fire on it
		walkable(P(V(230, 1, 46), W(-120, 0.5, z0 - 26), rgb(206, 164, 116), WOODM))
		for k = 0, 22 do P(V(230, 0.06, 0.4), W(-120, 1.04, z0 - 48 + k * 2), rgb(186, 146, 102), WOODM, { noShadow = true }) end
		firepit(W(-120, 1, z0 - 26))
		-- benches facing the sea
		for k = -1, 1 do
			local b = W(-120 + k * 62, 1, z0 - 44) * CFrame.Angles(0, math.pi, 0)
			K.bench(b)
			spot(b * CFrame.new(0, 0, -3), "A BENCH BY THE SEA", "sit and watch the boats", "SIT", "heart",
				{ seat = b * CFrame.new(0, 2.6, 0.4), pose = "sit" })
		end
		-- fishing off the end of the deck
		for _, sx in { -212, -28 } do
			local f = W(sx, 1, z0 - 8)
			cyl(0.5, 15, f * CFrame.new(0, 7, 0) * CFrame.Angles(0.5, 0, 0), rgb(150, 110, 78), WOODM)
			P(V(0.1, 0.1, 13), f * CFrame.new(0, 10.6, -5.6) * CFrame.Angles(-0.9, 0, 0), Cc.cream, SMOOTH)
			P(V(3.4, 2.4, 2.4), f * CFrame.new(2.6, 1.2, 1), rgb(120, 170, 200))
			spot(f, "FISHING SPOT", "nothing is biting. that is not the point.", "CAST", "star",
				{ pose = "idle", hold = true, lines = { "a little nibble... no.", "the water is very flat today", "you nearly had one", "peaceful out here" } })
		end
		-- lanterns strung along the boardwalk
		for k = 0, 7 do
			local x = -226 + k * 30
			cyl(0.4, 13, W(x, 1, z0 - 48) * CFrame.new(0, 6.5, 0), Cc.lampPost, METAL)
			local lamp = ball(2.4, W(x, 1, z0 - 48) * CFrame.new(0, 13.4, 0), rgb(255, 214, 150), NEON)
			lamp.CastShadow = false
			table.insert(H.lanterns, lamp)
		end
	end

	---------------------------------------------------------------------------
	-- 3. THE BANDSTAND  (Button Park already has the gazebo)
	---------------------------------------------------------------------------
	local function bandstand()
		local cx, cz = -450, -450
		-- the gazebo moved to the plaza's clear corner when the plaza is in;
		-- B.park says where it stands
		local g = Build.parkGazebo or V(cx - 50, 0, cz + 50)
		local c = W(g.X, PAD, g.Z)
		-- a ring of benches round the gazebo, all facing in
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			local b = CFrame.lookAt(c.Position + V(math.cos(a) * 26, 0, math.sin(a) * 26), c.Position)
			K.bench(b)
			if k % 2 == 0 then
				spot(b * CFrame.new(0, 0, -3.4), "PARK BENCH", "somebody usually turns up", "SIT", "heart",
					{ seat = b * CFrame.new(0, 2.6, 0.4), pose = "sit" })
			end
		end
		-- a chess table, because a park needs one
		local ch = Build.parkGazebo and W(g.X - 24, PAD, g.Z + 6) or W(cx - 20, PAD, cz + 78)
		cyl(1.2, 3, ch * CFrame.new(0, 1.5, 0), Cc.ink, METAL)
		solid(cyl(8, 0.6, ch * CFrame.new(0, 3.2, 0), Cc.cream, SMOOTH))
		for a = 0, 3 do
			for b = 0, 3 do
				P(V(1.5, 0.1, 1.5), ch * CFrame.new(-2.4 + a * 1.6, 3.55, -2.4 + b * 1.6), (a + b) % 2 == 0 and Cc.ink or Cc.cream, SMOOTH, { noShadow = true })
			end
		end
		for _, sx in { -1, 1 } do
			local s = ch * CFrame.new(sx * 7, 0, 0) * CFrame.Angles(0, -sx * math.pi / 2, 0)
			cyl(0.6, 2, s * CFrame.new(0, 1, 0), Cc.ink, METAL)
			cyl(3, 0.5, s * CFrame.new(0, 2.2, 0), rgb(150, 190, 220), SMOOTH)
			if sx == -1 then
				spot(s * CFrame.new(0, 0, -3), "CHESS TABLE", "your move", "PLAY", "star",
					{ seat = s * CFrame.new(0, 2.6, 0), pose = "sit", lines = { "you move a pawn. bold.", "check. probably.", "this game has been going for weeks" } })
			end
		end
	end

	---------------------------------------------------------------------------
	-- BUILD / PROMPT / UPDATE
	---------------------------------------------------------------------------
	function H.build(which)
		-- called from the block that owns each one, so they stream like
		-- everything else instead of loading the whole coast at spawn
		if which == "concert" then concertLawn()
		elseif which == "harbour" then boardwalk()
		elseif which == "park" then bandstand() end
	end

	local function use(sp)
		local act = sp.act
		if act.seat then H.sitting = { cf = act.seat, pose = act.pose or "sit" } end
		if act.hold then H.holding = { pose = act.pose or "cheer", untilT = os.clock() + 5 } end
		Audio.play(act.seat and "Pop" or "Chime", 1.1, 0.6)
		if act.lines then UI.toast(act.lines[math.random(1, #act.lines)], UI.C.mintDark) end
	end

	function H.prompt(me)
		if H.sitting then
			return { "TAKE YOUR TIME", "walk to get up", nil, "heart", nil, CITY + flat(me) }
		end
		local best, bd
		for _, sp in H.spots do
			local d = (flat(me) - flat(sp.pos)).Magnitude
			if d < 7 and (not bd or d < bd) then best, bd = sp, d end
		end
		if best then
			return { best.title, best.sub, best.btn, best.icon, function() use(best) end, CITY + best.pos }
		end
		return nil
	end

	local fT = 0
	function H.update(dt, t, me)
		local hrp, hum = myChar()
		if H.sitting and hrp then
			if hum and hum.MoveDirection.Magnitude > 0.2 then
				H.sitting = nil
			else
				hrp.CFrame = H.sitting.cf * CFrame.new(0, 2.9, 0)
				hrp.AssemblyLinearVelocity = Vector3.zero
				S.poses[player] = H.sitting.pose
			end
		end
		if H.holding then
			if os.clock() < H.holding.untilT and not (hum and hum.MoveDirection.Magnitude > 0.2) then
				S.poses[player] = H.holding.pose
			else
				H.holding = nil
			end
		end
		-- the fire breathes and the dance floor blinks, but only near you
		fT += dt
		if fT < 0.12 then return end
		fT = 0
		for _, f in H.flicker do
			if f.Parent and (flat(f.Position - CITY) - flat(me)).Magnitude < 220 then
				f.Size = V(1, 1, 1) * (4.2 + math.sin(t * 7) * 0.5 + math.sin(t * 11) * 0.25)
			end
		end
		if #H.floor > 0 and (flat(V(-750, 0, -164)) - flat(me)).Magnitude < 200 then
			for i, tile in H.floor do
				if tile.Parent then
					local on = (i + math.floor(t * 2.4)) % 3 == 0
					tile.Material = on and NEON or SMOOTH
					tile.Transparency = on and 0.12 or 0
				end
			end
		end
	end

	function H.leave()
		H.sitting, H.holding = nil, nil
	end

	return H
end
