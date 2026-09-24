-- SMINSKI RUN — client runner (StarterPlayerScripts.SminskiRunner)
-- Child modules: Models, World, Audio, UI. Shared config lives in
-- ReplicatedStorage.SminskiShared.Config; coins/unlocks live on the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

-- not running = edit-mode preview driven from the command bar for testing
local PREVIEW = not RunService:IsRunning()
local Root = script or _G.SR_ROOT
local player = not PREVIEW and Players.LocalPlayer or nil

-- Safety net: a Studio preview (or an old publish) can bake a frozen copy of
-- the world + HUD into the place. Those clones never update, and a leftover
-- loading curtain would sit on top of everything. We run before anything of
-- ours is built, so whatever is already here can only be a leftover.
if player then
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if pg then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g.Name:match("^Sminski") and g.Name ~= "SminskiTitle" then g:Destroy() end
		end
	end
	for _, x in workspace:GetChildren() do
		if (x:IsA("Folder") or x:IsA("Model")) and (x.Name:match("^Sminski") or x.Name:match("^Runner")) and x.Name ~= "SminskiGround" then
			x:Destroy()
		end
	end
end
local camera = workspace.CurrentCamera

local Config = require(ReplicatedStorage:WaitForChild("SminskiShared"):WaitForChild("Config"))
local Models = require(Root:WaitForChild("Models"))
local World = require(Root:WaitForChild("World"))(Models, Config)
local Audio = require(Root:WaitForChild("Audio"))(Config)
local MPc = require(Root:WaitForChild("Multiplayer"))(Config, Models)
local myUserId = player and player.UserId or 0
-- active multiplayer match (nil in solo). zOffset turns local z into the shared "absolute" z
local mp = nil
-- bots this client simulates (quick play fills empty slots with them)
local bots = {}
local function clearBots()
	for _, b in bots do
		b.rig.model:Destroy()
	end
	table.clear(bots)
end

if not PREVIEW then
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then break end
			task.wait(0.5)
		end
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

---------------------------------------------------------------------------
-- NETWORK (server owns data; an offline stand-in is used in preview)
---------------------------------------------------------------------------
local remotes = not PREVIEW and ReplicatedStorage:WaitForChild("SminskiRemotes", 15) or nil

local offline = {}
do
	local d = {
		Coins = 2000, XP = 0, Level = 1, BestScore = 0, BestDistance = 0, TotalDistance = 0, TotalCoins = 0,
		TotalNearMisses = 0, RunsPlayed = 0, OwnedCharacters = { Glow = true }, EquippedCharacter = "Glow",
		OwnedOutfits = { None = true }, EquippedOutfit = "None", Upgrades = {},
		OwnedSkins = { none = true }, EquippedSkin = "none",
		Settings = { Music = true, Sfx = true, Shake = true, AutoCam = true }, Saveable = false,
	}
	local run
	offline.GetData = function() return table.clone(d) end
	offline.StartRun = function() run = { id = "offline", free = d.Upgrades.SecondChance or 0, paid = 0 } return run.id end
	offline.Revive = function(_, useFree)
		if useFree and run.free > 0 then run.free -= 1 return { ok = true, coins = d.Coins } end
		local cost = Config.ReviveBaseCost * 2 ^ run.paid
		if d.Coins < cost then return { ok = false } end
		d.Coins -= cost
		run.paid += 1
		return { ok = true, coins = d.Coins }
	end
	offline.EndRun = function(_, s)
		local xp = Config.XPForRun(s.distance, s.coins, s.nearMisses)
		local lvl = d.Level
		d.Coins += s.coins; d.TotalCoins += s.coins; d.TotalDistance += s.distance; d.TotalNearMisses += s.nearMisses
		d.XP += xp; d.Level = Config.LevelFromXP(d.XP); d.RunsPlayed += 1
		local nb = s.score > d.BestScore
		if nb then d.BestScore = s.score end
		d.BestDistance = math.max(d.BestDistance, s.distance)
		return { coinsEarned = s.coins, xpEarned = xp, score = s.score, newBest = nb, levelUp = d.Level > lvl, data = table.clone(d) }
	end
	offline.BuyUpgrade = function(id)
		local u = Config.Upgrade(id)
		local lvl = d.Upgrades[id] or 0
		local cost = u.costs[lvl + 1]
		if not cost or d.Coins < cost then return { ok = false, reason = "coins" } end
		d.Coins -= cost; d.Upgrades[id] = lvl + 1
		return { ok = true, data = table.clone(d) }
	end
	offline.BuyOutfit = function(id)
		local o = Config.Outfit(id)
		if d.OwnedOutfits[id] or d.Coins < o.price then return { ok = false, reason = "coins" } end
		d.Coins -= o.price; d.OwnedOutfits[id] = true; d.EquippedOutfit = id
		return { ok = true, data = table.clone(d) }
	end
	offline.EquipOutfit = function(id) d.EquippedOutfit = id return { ok = true, data = table.clone(d) } end
	offline.BuySkin = function(id)
		local k = Config.Skin(id)
		if d.OwnedSkins[id] or d.Coins < k.price then return { ok = false, reason = "coins" } end
		d.Coins -= k.price; d.OwnedSkins[id] = true; d.EquippedSkin = id
		return { ok = true, data = table.clone(d) }
	end
	offline.EquipSkin = function(id) d.EquippedSkin = id return { ok = true, data = table.clone(d) } end
	offline.Equip = function(id) d.EquippedCharacter = id return { ok = true, data = table.clone(d) } end
	offline.OpenCapsule = function()
		if d.Coins < Config.CapsuleCost then return { ok = false, reason = "coins" } end
		d.Coins -= Config.CapsuleCost
		local c = Config.Characters[math.random(1, #Config.Characters)]
		local dup = d.OwnedCharacters[c.id]
		d.OwnedCharacters[c.id] = true
		local refund = dup and Config.Rarity(c.rarity).refund or 0
		d.Coins += refund
		return { ok = true, character = c.id, rarity = c.rarity, duplicate = dup, refund = refund, data = table.clone(d) }
	end
	offline.SetSetting = function(k, v) d.Settings[k] = v return true end
	d.OwnedMaps = { house = true, dollhouse = true }
	if game:GetService("RunService"):IsStudio() and Config.StudioUnlockMaps then
		for _, m in Config.Maps do d.OwnedMaps[m.id] = true end
	end
	d.SelectedMap = "house"
	offline.ClaimChallenge = function() return { ok = false } end
	offline.SelectMap = function(id)
		if not d.OwnedMaps[id] then return { ok = false } end
		d.SelectedMap = id
		return { ok = true, data = table.clone(d) }
	end
	offline.BuyMap = function(id)
		local m = Config.Map(id)
		if d.OwnedMaps[id] or not m.price or d.Coins < m.price then return { ok = false, reason = "coins" } end
		d.Coins -= m.price
		d.OwnedMaps[id] = true
		d.SelectedMap = id
		return { ok = true, data = table.clone(d) }
	end
end

local function call(name, ...)
	if not remotes then
		return offline[name](...)
	end
	local rf = remotes:FindFirstChild(name)
	if not rf then return nil end
	local ok, res = pcall(rf.InvokeServer, rf, ...)
	if not ok then
		warn("[Sminski] " .. name .. " failed:", res)
		return nil
	end
	return res
end

---------------------------------------------------------------------------
-- WORLD + ACTORS
---------------------------------------------------------------------------
local worldFolder = Instance.new("Folder")
worldFolder.Name = "RunnerWorld"
worldFolder.Parent = workspace
World.init(worldFolder)

local actors = Instance.new("Folder")
actors.Name = "RunnerActors"
actors.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { worldFolder }
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = { worldFolder }

local kid = Models.buildKid(actors)
local dog = Models.buildDog(nil)
local chaserKind = "kid" -- "kid" | "dog" | nil (Sminski Dollhouse has no chaser)
local function setChaser(kind)
	chaserKind = kind
	kid.model.Parent = kind == "kid" and actors or nil
	dog.model.Parent = kind == "dog" and actors or nil
end
local function holdPoint()
	return chaserKind == "dog" and dog.mouth.Position or kid.handR.Position
end
local sminski
local shieldBubble

-- sparkle bursts (coins, near misses, powerups)
local fxPart = Models.part(actors, Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1), nil, { transparency = 1 })
local sparkle = Instance.new("ParticleEmitter")
sparkle.Enabled = false
sparkle.Rate = 0
sparkle.Lifetime = NumberRange.new(0.25, 0.45)
sparkle.Speed = NumberRange.new(6, 12)
sparkle.SpreadAngle = Vector2.new(180, 180)
sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
sparkle.LightEmission = 0.8
sparkle.Drag = 6
sparkle.Parent = fxPart
local function burst(pos, color, n)
	fxPart.CFrame = World.at(pos.Z, pos.X, pos.Y)
	sparkle.Color = ColorSequence.new(color)
	sparkle:Emit(n or 6)
end

local runFX = Instance.new("ColorCorrectionEffect")
runFX.Name = "SminskiRunFX"
runFX.Parent = Lighting

-- lighting per map: cozy night house, glowing green dollhouse, sunny park
local LOOKS = {
	night = {
		clock = 20.6, bright = 1.8, amb = Color3.fromRGB(74, 68, 100), out = Color3.fromRGB(100, 96, 140), exp = 0.55,
		atm = { 0.3, 0.12, Color3.fromRGB(120, 112, 170), Color3.fromRGB(70, 56, 110), 0.2, 1.6 },
		bloom = { 0.7, 36, 1.0 }, grade = { 0.06, 0.14, Color3.fromRGB(255, 246, 238) }, rays = 0.04,
	},
	green = {
		clock = 21, bright = 1.1, amb = Color3.fromRGB(88, 118, 76), out = Color3.fromRGB(110, 150, 92), exp = -0.15,
		atm = { 0.3, 0.1, Color3.fromRGB(150, 200, 130), Color3.fromRGB(70, 110, 60), 0.15, 1.2 },
		bloom = { 0.75, 36, 1.05 }, grade = { 0.16, 0.14, Color3.fromRGB(244, 255, 236) }, rays = 0.02,
	},
	-- the neighborhood hub: moonlit bedroom floor, warm pools of lamp light
	hub = {
		clock = 22.4, bright = 0.8, amb = Color3.fromRGB(62, 54, 92), out = Color3.fromRGB(72, 64, 110), exp = -0.15,
		atm = { 0.14, 0.05, Color3.fromRGB(110, 95, 170), Color3.fromRGB(60, 50, 100), 0.05, 0.6 },
		bloom = { 0.45, 30, 1.25 }, grade = { 0.08, 0.14, Color3.fromRGB(236, 232, 255) }, rays = 0.0,
	},
	day = {
		clock = 14.2, bright = 2.8, amb = Color3.fromRGB(128, 124, 120), out = Color3.fromRGB(160, 160, 150), exp = 0.1,
		atm = { 0.28, 0.08, Color3.fromRGB(230, 238, 255), Color3.fromRGB(200, 220, 245), 0.3, 1.2 },
		bloom = { 0.45, 30, 1.3 }, grade = { 0.06, 0.12, Color3.fromRGB(255, 250, 242) }, rays = 0.08,
	},
	-- Sminski City: a clear afternoon on a real street. Natural sun, honest
	-- shadows and genuine aerial haze for depth -- no bloom wash, no cream
	-- filter over everything. The haze is doing double duty: it also fades
	-- the far side of town so you never take the whole city in at once.
	city = {
		clock = 14.6, bright = 2.1, amb = Color3.fromRGB(74, 76, 86), out = Color3.fromRGB(118, 124, 136), exp = 0,
		-- density, offset, colour, decay, glare, haze
		atm = { 0.34, 0.02, Color3.fromRGB(202, 214, 230), Color3.fromRGB(104, 126, 160), 0.06, 1.45 },
		-- bloom threshold 2.0: only genuinely bright things bloom, nothing else
		bloom = { 0.12, 24, 2.0 }, grade = { 0.02, 0.06, Color3.fromRGB(252, 252, 255) }, rays = 0,
		shadow = 0.12, farDof = true, clouds = { 0.55, 0.045, Color3.fromRGB(255, 255, 255) },
	},
}
local look = {}
local function applyLook(name)
	local L = LOOKS[name or "night"] or LOOKS.night
	Lighting.ClockTime = L.clock
	Lighting.Brightness = L.bright
	Lighting.Ambient = L.amb
	Lighting.OutdoorAmbient = L.out
	-- full environment lighting + reflections so PBR surfaces read as real
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ExposureCompensation = L.exp
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = L.shadow or 0.22
	local function get(class, name)
		local e = Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(class)
		if not e then
			e = Instance.new(class)
			e.Name = name
			e.Parent = Lighting
			look[name] = e
		end
		return e
	end
	local atm = get("Atmosphere", "Atmosphere")
	atm.Density, atm.Offset, atm.Color, atm.Decay, atm.Glare, atm.Haze = table.unpack(L.atm)
	local bloom = get("BloomEffect", "Bloom")
	bloom.Intensity, bloom.Size, bloom.Threshold = table.unpack(L.bloom)
	local cc = get("ColorCorrectionEffect", "SminskiGrade")
	if cc == runFX then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "SminskiGrade"
		cc.Parent = Lighting
		look.SminskiGrade = cc
	end
	cc.Saturation, cc.Contrast, cc.TintColor = L.grade[1], L.grade[2], L.grade[3]
	cc.Brightness = 0.02
	local dof = get("DepthOfFieldEffect", "SminskiDOF")
	dof.FarIntensity = L.farDof and 0.12 or 0.28
	dof.FocusDistance = L.farDof and 120 or 24
	dof.InFocusRadius = L.farDof and 400 or 40
	dof.NearIntensity = 0
	look.dof = dof
	local rays = get("SunRaysEffect", "SunRays")
	rays.Intensity = L.rays
	rays.Spread = 0.8
	-- real drifting cloud cover. It gives the sky something to be other than
	-- a flat blue field, and moving shade across the street is most of what
	-- makes outdoor light feel alive.
	if L.clouds then
		local t = workspace:FindFirstChildOfClass("Terrain")
		local c = t and (t:FindFirstChildOfClass("Clouds") or Instance.new("Clouds", t))
		if c then
			c.Cover, c.Density = L.clouds[1], L.clouds[2]
			c.Color = L.clouds[3]
			c.Enabled = true
		end
	end
end
applyLook()

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local LANES = World.LANES
local LANE_LERP = 16
local laneK = 1 -- <1 during the "slippery floor" event
local GRAVITY = 175
local JUMP_V = 54
local SLIDE_TIME = 0.6
local RECENTER_AT = 3000

local data = call("GetData") or offline.GetData()
local ctx = { data = data, playerName = player and player.DisplayName or "sminski fan" }

local state = "home"
local t = 0
local stateT = 0
-- the city is the world; the runs, the dog park and the bedroom table are
-- games inside the Sminski Arcade on Main St. When a mode was launched from
-- a cabinet, finishing it puts you back on the street outside, not in the
-- bedroom (see docs/ROADMAP.md).
local cameFromCity = false
local px, py, pz, vy = 0, 0, 0, 0
local lane, prevLane = World.CENTER_LANE, World.CENTER_LANE
local wideK, lastRangeWide = 0, false
local hearts, maxHearts, heartT = nil, 0, 0 -- hearts mode (maps without a chaser)
local gliding, glideY0 = false, 0
local currentMap = "house"
local previewCam -- set by the Studio preview hook
local grounded, slideT, fastFall = true, 0, false
local speed = Config.SpeedAt(0)
local runTime, distance, score, coins = 0, 0, 0, 0
local comboPts, mult, bestMult, lastComboGain = 0, 1, 1, 0
local nearMisses = 0
local chase = 100
local invulnT, hitCooldown = 0, 0
local powerups = {}
local passive = {} -- the equipped Sminski's passive (Config.Passives)
local runsThisSession = 0
-- chaos meter (solo runs): tier by time + random events
local runTier, nextEventT, nextLineT = 0, 20, 12
local eventK = {} -- [kind] = { left = seconds }
local timeScale, slowmoT = 1, 0
local shake, landBounce, surprisedT = 0, 0, 0
local lookBack = 0
local runId
local paidRevives, freeRevives = 0, 0
local reviveT, revivePaused = 0, false
local kidDist, kidX, kidSide, kidLastSin = 24, 0, 1, 0
local camPos, camLook = Vector3.new(8, 4, 14), Vector3.new(0, 5, -5)
local announcedBest, announcedNear = false, false
local lastZone
local caughtAt

local function comboMult(pts)
	local m = 1
	for i, need in Config.ComboSteps do
		if pts >= need then m = i end
	end
	return m
end

local function addCombo(kind)
	comboPts += Config.ComboPoints[kind] or 0
	lastComboGain = t
	mult = comboMult(comboPts)
	bestMult = math.max(bestMult, mult)
end

local function luckLevel()
	return (data.Upgrades and data.Upgrades.Luck or 0) + (passive.luck or 0)
end
local function level(id)
	return data.Upgrades[id] or 0
end

local function rebuildSminski()
	if sminski then sminski.model:Destroy() end
	local def = Config.Character(data.EquippedCharacter)
	sminski = Models.buildSminski(actors, 1, def, true, data.EquippedOutfit ~= "None" and data.EquippedOutfit or nil,
		Config.Skin(data.EquippedSkin))
	Models.addTrail(sminski, def.trail or Color3.fromRGB(200, 255, 160))
	sminski.trail.Enabled = false
end

local function applySettings()
	Audio.setEnabled(data.Settings.Music, data.Settings.Sfx)
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local UI

local function setData(d)
	if not d then return end
	local oldChar, oldOutfit, oldSkin = data.EquippedCharacter, data.EquippedOutfit, data.EquippedSkin
	data = d
	ctx.data = d
	if d.EquippedCharacter ~= oldChar or d.EquippedOutfit ~= oldOutfit or d.EquippedSkin ~= oldSkin then
		rebuildSminski()
	end
	applySettings()
	UI.refresh()
end

local function resetRunState(seed, opts)
	local mapDef = Config.Map((opts and opts.map) or data.SelectedMap or "house")
	if opts and opts.wide and not opts.map then mapDef = Config.Map("house") end -- squads play the host's pick (default: the big house)
	currentMap = mapDef.id
	passive = Config.Passive(data.EquippedCharacter)
	runTier, nextEventT, nextLineT = 0, 20, 12
	table.clear(eventK)
	laneK = 1
	World.setMap(mapDef.id)
	setChaser(mapDef.chaser)
	applyLook(mapDef.look)
	hearts = mapDef.hearts
	maxHearts = mapDef.hearts or 0
	heartT = 0
	World.setForceWide(opts ~= nil and opts.wide == true)
	World.reset(seed or math.random(1, 2 ^ 30))
	px, py, pz, vy = 0, 0, 0, 0
	lane = opts and opts.lane or World.CENTER_LANE
	prevLane = lane
	px = LANES[lane]
	wideK, lastRangeWide = 0, false
	gliding = false
	grounded, slideT, fastFall = true, 0, false
	runTime, distance, score, coins = 0, 0, 0, 0
	comboPts, mult, bestMult = 0, 1, 1
	nearMisses = 0
	chase = Config.Chase.Start
	invulnT, hitCooldown = 0, 0
	table.clear(powerups)
	timeScale, slowmoT = 1, 0
	shake, landBounce, surprisedT, lookBack = 0, 0, 0, 0
	paidRevives = 0
	freeRevives = level("SecondChance") + (data.Passes and data.Passes.revive and (Config.Pass("revive").freeRevive or 0) or 0)
	speed = Config.SpeedAt(0)
	kidDist, kidX = 24, 0
	announcedBest, announcedNear = false, false
	lastZone = nil
	runFX.Saturation, runFX.TintColor, runFX.Brightness = 0, Color3.new(1, 1, 1), 0
	if shieldBubble then shieldBubble.Parent = nil end
	if sminski then sminski.trail.Enabled = false end
	World.update(pz, 0, luckLevel())
end

---------------------------------------------------------------------------
-- MODES: the hub (walking around as your Sminski), the runner, the park
---------------------------------------------------------------------------
local Hub, Park, City -- created after the UI
local Places = require(ReplicatedStorage:WaitForChild("SminskiShared"):WaitForChild("Places"))
local activityRemote = remotes and remotes:WaitForChild("SetActivity", 5)
local controls
if player then
	task.spawn(function()
		local ok, pm = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
		end)
		if ok and pm then controls = pm:GetControls() end
	end)
end
local function myCharacter()
	local c = player and player.Character
	return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end
-- park (anchor + no controls) your walking body while you're in a runner run
local function parkCharacter(on)
	local _, hrp = myCharacter()
	if hrp then hrp.Anchored = on end
	if controls then
		if on then controls:Disable() else controls:Enable() end
	end
end
local function setActivity(a, where)
	if activityRemote then activityRemote:FireServer(a, where) end
end
local function runnerVisible(on)
	worldFolder.Parent = on and workspace or nil
	actors.Parent = on and workspace or nil
end

local function goHome()
	if state == "city" and City then City.leave() end
	if MPc.matchServer then
		-- reserved match server: go back to a normal lobby server
		UI.toast("heading back to the lobby...", UI.C.mintDark)
		task.spawn(MPc.request, "returnToLobby")
		return
	end
	if mp then
		mp = nil
		MPc.clear()
	end
	clearBots()
	UI.setSquad(nil)
	UI.showDown(nil)
	UI.showMPResults(nil)
	resetRunState()
	local fromRun = state ~= "home" and state ~= "hub"
	state = "home"
	stateT = 0
	UI.setMode("home")
	UI.showResults(nil)
	UI.refresh()
	Audio.musicStop()
	Audio.ambient(true)
	kid.bubble.Enabled = false
	-- back into the neighborhood (out of the Main House door after a run)
	runnerVisible(false)
	if Hub then Hub.enter(true) end
	parkCharacter(false)
	setActivity("hub", fromRun and "house" or nil)
	if cameFromCity and ctx.enterCity then
		cameFromCity = false
		ctx.enterCity()
	end
end

local function startRun()
	if ctx.stopTour then ctx.stopTour() end
	if state == "intro" or state == "playing" or mp or state == "park" then return end
	if state == "city" and City then cameFromCity = true City.leave() end
	if Hub then Hub.leave() end
	runnerVisible(true)
	parkCharacter(true)
	setActivity("run")
	resetRunState()
	state = "intro"
	stateT = 0
	UI.setMode("run")
	UI.hud.Visible = false
	UI.showResults(nil)
	Audio.musicStop()
	Audio.ambient(false)
	runId = nil
	task.spawn(function()
		runId = call("StartRun")
	end)
	-- remind new players how to steer, in the words of whatever they're holding
	runsThisSession += 1
	if runsThisSession <= 2 and UI.inputKind then
		local kind = UI.inputKind()
		task.delay(3.2, function()
			if state ~= "playing" then return end
			UI.banner(kind == "touch" and "SWIPE  left / right  ·  up to jump  ·  down to slide"
				or kind == "gamepad" and "STICK to dodge  ·  A to jump  ·  B to slide"
				or "A / D to dodge  ·  SPACE to jump  ·  S to slide", UI.C.white, 3)
		end)
	end
	if passive.startCoins then coins = passive.startCoins end
	if passive.startShield then
		task.delay(2.6, function()
			if state == "playing" or state == "intro" then activatePowerup("Shield") end
		end)
	end
end

local function finishRun()
	state = "results"
	stateT = 0
	UI.setMode("results")
	local stats = { distance = distance, coins = coins, score = math.floor(score * (passive.score or 1)), nearMisses = nearMisses, bestCombo = bestMult, map = currentMap }
	task.spawn(function()
		local reward = runId and call("EndRun", runId, stats) or nil
		if reward and reward.data then setData(reward.data) end
		if state == "results" then
			UI.showResults(stats, reward)
		end
	end)
end

local function reviveCost()
	return Config.ReviveBaseCost * 2 ^ paidRevives
end

local function resumeAfterRevive()
	state = "playing"
	stateT = 0
	UI.setMode("run")
	UI.caught(false)
	UI.showRevive(nil)
	World.clearAhead(pz - 6, pz + 70)
	chase = 60
	invulnT = 2.5
	lookBack = 0
	if hearts then hearts = 1 end
	py = 0
	vy = 0
	grounded = true
	slideT = 0
	timeScale = 1
	TweenService:Create(runFX, TweenInfo.new(0.4), { Saturation = 0 }):Play()
	UI.countdown("GO!", UI.C.mint)
	task.delay(0.6, function() UI.countdown(nil) end)
	Audio.musicStart()
	Audio.play("Pop", 1.2, 1)
end

local function doRevive(kind)
	if state ~= "revive" then return end
	if kind == "robux" then
		if Config.ReviveProductId and player then
			revivePaused = true
			MarketplaceService:PromptProductPurchase(player, Config.ReviveProductId)
		end
		return
	end
	revivePaused = true
	task.spawn(function()
		local res = call("Revive", runId, kind == "free")
		revivePaused = false
		if res and res.ok then
			if kind == "coins" then paidRevives += 1 else freeRevives -= 1 end
			if res.coins then data.Coins = res.coins ; UI.refresh() end
			resumeAfterRevive()
		else
			UI.toast(kind == "coins" and "not enough coins" or "no free revives left")
		end
	end)
end

if player and remotes then
	local ev = remotes:WaitForChild("RobuxRevived", 5)
	if ev then
		ev.OnClientEvent:Connect(function()
			if state ~= "revive" then return end
			task.spawn(function()
				local res = call("Revive", runId, true)
				revivePaused = false
				if res and res.ok then resumeAfterRevive() end
			end)
		end)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, _, purchased)
		if not purchased then revivePaused = false end
	end)
end

ctx.startRun = startRun
ctx.startRunMap = function(id)
	local m = Config.Map(id)
	if not m then return end
	if not (data.OwnedMaps and data.OwnedMaps[id]) then
		UI.toast(m.name .. " is locked: " .. UI.fmt(m.price or 0) .. " coins", UI.C.gold)
		UI.open("maps")
		return
	end
	task.spawn(function()
		if data.SelectedMap ~= id then
			data.SelectedMap = id
			local res = call("SelectMap", id)
			if res and res.ok then setData(res.data) end
		end
		startRun()
	end)
end
ctx.goHome = goHome
-- MENU during a run: bank what you earned (solo) or leave the match, then back to the lobby
ctx.leaveRun = function()
	if state ~= "playing" and state ~= "intro" and state ~= "caught" and state ~= "revive" and state ~= "results" then return end
	if mp then
		task.spawn(MPc.request, "leaveMatch")
	elseif runId and state ~= "results" then
		local id = runId
		runId = nil
		local stats = { distance = distance, coins = coins, score = math.floor(score * (passive.score or 1)), nearMisses = nearMisses, bestCombo = bestMult, map = currentMap }
		task.spawn(function()
			local reward = call("EndRun", id, stats)
			if reward and reward.data then
				setData(reward.data)
				if (reward.coinsEarned or 0) > 0 then UI.toast("+◉ " .. UI.fmt(reward.coinsEarned) .. " banked", UI.C.mintDark) end
			end
		end)
	end
	UI.caught(false)
	goHome()
end
ctx.revive = doRevive
ctx.declineRevive = function()
	if state == "revive" then finishRun() end
end
local function shopResult(res, okMsg)
	if res and res.ok then
		setData(res.data)
		Audio.play("Chime", 1.2, 0.8)
		if okMsg then UI.toast(okMsg, UI.C.mintDark) end
	elseif res and res.reason == "coins" then
		Audio.play("Click", 0.6, 0.6)
		UI.toast("not enough coins")
	elseif res and res.reason == "level" then
		Audio.play("Click", 0.6, 0.6)
		UI.toast("reach level " .. tostring(res.level) .. " to wear this")
	end
end
ctx.buyOutfit = function(id) task.spawn(function() shopResult(call("BuyOutfit", id), "new outfit!") end) end
ctx.equipOutfit = function(id)
	task.spawn(function()
		local res = call("EquipOutfit", id)
		if res and res.ok then setData(res.data) ; Audio.play("Click", 1.8, 0.7) end
	end)
end
ctx.claimChallenge = function(kind, index)
	task.spawn(function()
		local res = call("ClaimChallenge", kind, index)
		if res and res.ok then
			setData(res.data)
			Audio.play("BigChime", 1.1, 0.9)
			UI.toast("+◉ " .. tostring(res.reward) .. "  challenge complete!", UI.C.mintDark)
		end
	end)
end
ctx.claimDaily = function()
	task.spawn(function()
		local res = call("ClaimDaily")
		if not (res and res.ok) then
			UI.toast(res and res.reason or "couldn't claim")
			return
		end
		Audio.play("BigChime", 1, 1)
		UI.flash(UI.C.gold, 0.35)
		local bits = {}
		if (res.coins or 0) > 0 then table.insert(bits, "+◉ " .. UI.fmt(res.coins)) end
		if res.outfit then table.insert(bits, Config.Outfit(res.outfit).name .. " unlocked!") end
		UI.toast("DAY " .. res.day .. " GIFT  ·  " .. table.concat(bits, "  ·  "), UI.C.mintDark)
		if res.capsule and res.capsule.ok then
			UI.open(nil)
			UI.playCapsule(res.capsule)
			task.delay(1.6, function() setData(res.capsule.data) end)
		else
			setData(res.data)
		end
	end)
end
ctx.buyUpgrade = function(id) task.spawn(function() shopResult(call("BuyUpgrade", id), "upgraded!") end) end
ctx.equipCharacter = function(id)
	task.spawn(function()
		local res = call("Equip", id)
		if res and res.ok then setData(res.data) ; Audio.play("Click", 1.8, 0.7) end
	end)
end
ctx.openCapsule = function()
	task.spawn(function()
		local res = call("OpenCapsule")
		if res and res.ok then
			UI.playCapsule(res)
			task.delay(1.6, function() setData(res.data) end)
		elseif res and res.reason == "coins" then
			UI.toast("not enough coins")
		end
	end)
end
ctx.setSetting = function(k, v)
	data.Settings[k] = v
	applySettings()
	UI.refresh()
	task.spawn(call, "SetSetting", k, v)
end

---------------------------------------------------------------------------
-- MULTIPLAYER GLUE
---------------------------------------------------------------------------
local caught -- defined with the gameplay events below
local mpStatus = {}

local function makeBot(info)
	local def = Config.Character(info.char)
	local rig = Models.buildSminski(actors, 1, def, true, info.outfit ~= "None" and info.outfit or nil,
		info.skin and Config.Skin(info.skin) or nil)
	Models.addTrail(rig, def.trail)
	MPc.nameplate(rig, info, math.max(0, ((mp and mp.startAt) or MPc.serverNow()) - MPc.serverNow()) + 5)
	bots[info.userId] = {
		id = info.userId, info = info, rig = rig,
		lane = info.lane, prevLane = info.lane, px = LANES[info.lane], py = 0, pz = 0, vy = 0,
		grounded = true, slideT = 0, chase = 60, alive = true, invulnT = 0, hitCd = 0, cool = 0,
		skill = info.skill or 0.6, distance = 0, score = 0, mult = 1, statT = 0, pose = "idle",
	}
end
local function squadList()
	if not mp then return nil end
	local list = {}
	for uid, info in mp.players do
		table.insert(list, {
			userId = uid,
			name = uid == myUserId and "you" or info.name,
			tier = info.tier,
			down = mp.down[uid] ~= nil,
			respawnAt = mp.down[uid],
			left = mp.left[uid],
		})
	end
	table.sort(list, function(a, b) return a.userId < b.userId end)
	return list
end

MPc.handlers.status = function(st)
	mpStatus = st or {}
	UI.setMPStatus(mpStatus)
end
MPc.handlers.queueTick = function(q)
	UI.setQueueTime(MPc.serverNow() - q.since, q.ranked)
end
MPc.handlers.toast = function(msg)
	UI.toast(msg)
end

MPc.handlers.matchStart = function(info)
	if ctx.stopTour then ctx.stopTour() end
	if Hub then Hub.leave() end
	runnerVisible(true)
	parkCharacter(true)
	setActivity("run")
	mp = { id = info.id, ranked = info.ranked, startAt = info.startAt, zOffset = 0, players = {}, down = {}, left = {}, sendT = 0, statT = 0 }
	for _, p in info.players do
		mp.players[p.userId] = p
	end
	local mine = mp.players[myUserId]
	resetRunState(info.seed, { wide = true, lane = mine and mine.lane or 3, map = info.map })
	MPc.setupMatch(info, actors, myUserId)
	clearBots()
	for _, p in info.players do
		if p.isBot and p.controller == myUserId then makeBot(p) end
	end
	state = "intro"
	stateT = 0
	UI.setMode("run")
	UI.hud.Visible = false
	UI.showResults(nil)
	UI.showMPResults(nil)
	UI.setSquad(squadList())
	Audio.musicStop()
	Audio.ambient(false) -- otherwise the lobby loop plays under the run music
	Audio.play("BigChime", 1.1, 0.8)
	UI.banner(info.ranked and "RANKED MATCH" or "MATCH FOUND", UI.C.sky, 2.5)
	runId = nil
	freeRevives = 0
	if info.joining then
		-- hopping into a run in progress: watch the leader until the server drops us in
		mp.down[myUserId] = info.respawnAt
		runTime = math.max(0, MPc.serverNow() - info.startAt)
		state = "down"
		stateT = 0
		UI.banner("JOINING THE RUN...", UI.C.sky, 2.5)
	end
end

MPc.handlers.down = function(d)
	if not mp then return end
	mp.down[d.userId] = d.respawnAt
	MPc.setAlive(d.userId, false)
	if d.userId ~= myUserId then
		local info = mp.players[d.userId]
		UI.popText((info and info.name or "someone") .. " got caught!", UI.C.coral, 26, -90)
	end
	UI.setSquad(squadList())
end

MPc.handlers.joined = function(info)
	if not mp or info.userId == myUserId then return end
	mp.players[info.userId] = info
	MPc.addRemote(info, 6)
	UI.setSquad(squadList())
	UI.popText(info.name .. " joined the run!", UI.C.sky, 28, -90)
	Audio.play("Chime", 1.2, 0.8)
end

MPc.handlers.left = function(d)
	if not mp then return end
	-- a bot we were simulating stepped aside for a real player
	local b = bots[d.userId]
	if b then
		if b.rig and b.rig.model then b.rig.model:Destroy() end
		bots[d.userId] = nil
	end
	mp.left[d.userId] = true
	MPc.setAlive(d.userId, false)
	UI.setSquad(squadList())
end

MPc.handlers.shoved = function(d)
	if d.bot then
		local b = bots[d.bot]
		if b and b.alive and b.invulnT <= 0 then
			b.prevLane = b.lane
			b.lane = math.clamp(b.lane + d.dir, 1, #LANES)
			b.chase -= Config.MP.ShoveChase
		end
		return
	end
	if not mp or state ~= "playing" or invulnT > 0 then return end
	local lo, hi = World.laneRangeAt(pz)
	local newLane = math.clamp(lane + d.dir, lo, hi)
	if newLane ~= lane then
		-- keep prevLane: getting shoved into something counts as a side bump, not a crash
		prevLane = lane
		lane = newLane
	end
	chase -= Config.MP.ShoveChase
	surprisedT = 0.3
	shake = math.max(shake, 0.5)
	Audio.play("Bump", 1.4, 0.8)
	UI.popText("SHOVED by " .. tostring(d.name) .. "!", UI.C.coral, 28)
	if chase <= 0 then
		chase = 0
		caught()
	end
end

-- respawnMe is set further down (needs the step helpers)
local respawnMe
MPc.handlers.respawn = function(d)
	if not mp then return end
	mp.down[d.userId] = nil
	MPc.setAlive(d.userId, true)
	UI.setSquad(squadList())
	local b = bots[d.userId]
	if b then
		b.pz = d.z - mp.zOffset
		b.lane = math.clamp(d.lane or b.lane, 1, #LANES)
		b.prevLane = b.lane
		b.px = LANES[b.lane]
		b.py, b.vy, b.grounded = 0, 0, true
		b.chase, b.invulnT, b.alive = 60, 3, true
	elseif d.userId == myUserId and respawnMe then
		respawnMe(d.z - mp.zOffset, d.lane)
	elseif d.userId ~= myUserId then
		local info = mp.players[d.userId]
		UI.popText((info and info.name or "someone") .. " is back!", UI.C.mint, 24, -90)
	end
end

MPc.handlers.matchEnd = function(d)
	if not mp then return end
	mp.over = true
	state = "mpresults"
	stateT = 0
	UI.setMode("results")
	UI.setSquad(nil)
	UI.showDown(nil)
	if d.reward and d.reward.data then setData(d.reward.data) end
	UI.showMPResults(d)
	Audio.musicStop(true)
	Audio.play(d.results[1] and d.results[1].userId == myUserId and "BigChime" or "Wobble", 1, 1)
end

ctx.mpQueue = function(ranked)
	task.spawn(function()
		local res = MPc.request("queue", ranked)
		if not res.ok then UI.toast(res.reason or "couldn't join the queue") end
	end)
end
ctx.serverNow = MPc.serverNow
ctx.mpBrowse = function()
	local res = MPc.request("browse")
	return res and res.ok and res.data or nil
end
ctx.mpJoinRun = function(id)
	task.spawn(function()
		local res = MPc.request("joinRun", id)
		if not res.ok then UI.toast(res.reason or "couldn't join that run") end
	end)
end
ctx.mpSetMap = function(id)
	task.spawn(function()
		local res = MPc.request("setLobbyMap", id)
		if not res.ok then UI.toast(res.reason or "couldn't pick that map") end
	end)
end
ctx.mpCancel = function() task.spawn(MPc.request, "cancelQueue") end
ctx.mpCreate = function()
	task.spawn(function()
		local res = MPc.request("createLobby")
		if not res.ok then UI.toast(res.reason or "couldn't make a lobby") end
	end)
end
ctx.mpJoin = function(code)
	task.spawn(function()
		local res = MPc.request("joinLobby", code)
		if res.teleporting then
			UI.toast("joining your friend's server...", UI.C.mintDark)
		elseif not res.ok then
			UI.toast(res.reason or "couldn't join")
		end
	end)
end
ctx.mpLeave = function() task.spawn(MPc.request, "leaveLobby") end
ctx.mpBots = function()
	task.spawn(function()
		local res = MPc.request("botMatch")
		if not res.ok then UI.toast(res.reason or "couldn't start") end
	end)
end
ctx.mpStart = function()
	task.spawn(function()
		local res = MPc.request("startLobby")
		if not res.ok then UI.toast(res.reason or "couldn't start") end
	end)
end
ctx.selectMap = function(id)
	task.spawn(function()
		local res = call("SelectMap", id)
		if res and res.ok then
			setData(res.data)
			Audio.play("Click", 1.8, 0.7)
			if state == "home" then goHome() end
		end
	end)
end
ctx.buyMap = function(id)
	task.spawn(function()
		local res = call("BuyMap", id)
		if res and res.ok then
			setData(res.data)
			Audio.play("BigChime", 1, 1)
			UI.toast("new map unlocked!", UI.C.mintDark)
			if state == "home" then goHome() end
		elseif res and res.reason == "coins" then
			UI.toast("not enough coins")
		end
	end)
end
ctx.buySkin = function(id)
	task.spawn(function()
		local k = Config.Skin(id)
		local res = call("BuySkin", id)
		if res and res.ok then
			setData(res.data)
			Audio.play("BigChime", 1, 1)
			UI.toast("you're wearing the " .. k.name .. "!", UI.C.mintDark)
		elseif res and res.reason == "level" then
			UI.toast("reach level " .. (res.level or k.level) .. " first", UI.C.gold)
		else
			UI.toast("not enough coins")
		end
	end)
end
ctx.equipSkin = function(id)
	task.spawn(function()
		local res = call("EquipSkin", id)
		if res and res.ok then
			setData(res.data)
			Audio.play("Chime", 1.2, 0.8)
		end
	end)
end
-- Robux cash bundles / boosts / skips. The server grants them in
-- ProcessReceipt; all the client does is raise the prompt.
ctx.buyProduct = function(id)
	local pr = Config.Product(id)
	if not pr then return end
	if pr.productId == 0 then
		UI.toast(pr.name .. " is coming soon!", UI.C.gold)
		return
	end
	MarketplaceService:PromptProductPurchase(player, pr.productId)
end
ctx.buyPass = function(id)
	local p = Config.Pass(id)
	if not p then return end
	if data.Passes and data.Passes[id] then
		UI.toast("you already own " .. p.name, UI.C.mintDark)
	elseif p.gamePassId and player then
		MarketplaceService:PromptGamePassPurchase(player, p.gamePassId)
	else
		UI.toast(p.name .. " is coming soon!", UI.C.gold)
	end
end
ctx.buyMapRobux = function(id)
	local m = Config.Map(id)
	if m.gamePassId and player then
		MarketplaceService:PromptGamePassPurchase(player, m.gamePassId)
	end
end
if remotes then
	local dc = remotes:WaitForChild("DataChanged", 5)
	if dc then
		dc.OnClientEvent:Connect(function(d)
			setData(d)
			if state == "home" then goHome() end
		end)
	end
	-- AUTO-COLLECT paid out while you were doing something else. Coins must
	-- never just appear: say where they came from.
	local ac = remotes:WaitForChild("AutoCollected", 5)
	if ac then
		ac.OnClientEvent:Connect(function(coins, shops)
			if not coins or coins < 1 then return end
			Audio.play("BigChime", 1, 0.8)
			UI.toast("auto-collect: +" .. coins .. " from " .. shops .. " shop" .. (shops > 1 and "s" or ""), UI.C.mintDark)
		end)
	end
end
ctx.mpAvailable = MPc.available
ctx.myUserId = myUserId

UI = require(Root:WaitForChild("UI"))(Config, Models, Audio, ctx)
UI.gui.Parent = player and player:WaitForChild("PlayerGui") or game:GetService("StarterGui")
if player then
	-- the whole game is laid out for landscape
	pcall(function() player.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor end)
end

-- the park gets a little more saturated/warm as it gets busier
local function parkLook(tier)
	applyLook("day")
	local k = ((tier or 1) - 1) / 3
	runFX.Saturation = 0.05 + k * 0.2
	runFX.Contrast = k * 0.12
	runFX.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 225, 200), k)
end
local hubDeps = {
	Config = Config, Models = Models, World = World, Audio = Audio, UI = UI, ctx = ctx, Places = Places,
	Rigs = require(ReplicatedStorage.SminskiShared:WaitForChild("Rigs")),
	player = player, applyLook = applyLook, parkLook = parkLook, nameplate = MPc.nameplate,
}
Hub = require(Root:WaitForChild("Hub"))(hubDeps)
Hub.gui.Parent = UI.gui.Parent
hubDeps.Hub = Hub
-- first-time tour: the camera glides around the table explaining each place
local Tour = require(Root:WaitForChild("Tour"))({
	UI = UI, Audio = Audio, Places = Places, player = player,
	setCam = function(cf) previewCam = cf end,
})
ctx.stopTour = function() if Tour.running then Tour.stop() end end
ctx.startTour = function()
	if Tour.running or (state ~= "home" and state ~= "hub") then return end
	local wasHub = state == "hub"
	UI.open(nil)
	UI.setMode("none")
	if Hub.setHudVisible then Hub.setHudVisible(false) end
	if Hub.Garden and Hub.Garden.isOpen() then Hub.Garden.close() end
	ctx.tourRunning = true
	Tour.run(function()
		ctx.tourRunning = false
		if not data.TutorialDone then
			data.TutorialDone = true
			task.spawn(call, "TutorialDone")
		end
		if wasHub and state == "hub" then
			UI.setMode("none")
			if Hub.setHudVisible then Hub.setHudVisible(true) end
		elseif state == "home" then
			UI.setMode("home")
			UI.refresh()
		end
		if ctx.maybeShowGift then ctx.maybeShowGift() end
	end)
end
Park = require(Root:WaitForChild("Park"))(hubDeps)
Park.gui.Parent = UI.gui.Parent

ctx.setData = function(d) setData(d) end
ctx.showHome = function()
	if state == "hub" then
		state = "home"
		stateT = 0
		UI.setMode("home")
		UI.refresh()
		Hub.setHudVisible(false)
	end
end
-- home page -> walking around the table
ctx.explore = function()
	if state ~= "home" then return end
	state = "hub"
	stateT = 0
	UI.open(nil)
	UI.setMode("none")
	Hub.enter(false)
	camera.CameraType = Enum.CameraType.Custom
	local _, _, hum = myCharacter()
	if hum then camera.CameraSubject = hum end
	Audio.play("Whoosh", 1, 0.6)
end
ctx.enterPark = function()
	if mp then return end
	if state == "city" and City then cameFromCity = true City.leave() end
	UI.open(nil)
	UI.setMode("none")
	UI.showResults(nil)
	Hub.leave()
	runnerVisible(false)
	parkCharacter(false)
	Park.enter()
	parkLook(1)
	state = "park"
	stateT = 0
	Audio.ambient(false)
	Audio.musicSoft()
end
ctx.exitPark = function()
	Park.leave()
	state = "hub"
	stateT = 0
	UI.setMode("none")
	Hub.enter(false)
	parkCharacter(false)
	camera.CameraType = Enum.CameraType.Custom
	Audio.musicStop()
	Audio.ambient(true)
	if cameFromCity and ctx.enterCity then
		cameFromCity = false
		ctx.enterCity()
	end
end

-- Sminski City: through the arch in the bedroom wall.
--
-- IN A PCALL, AND BOUNDED. This require used to be bare, and City.lua's own
-- module requires were bare WaitForChilds. A place whose script tree was a
-- step behind the sync (an Undo after a sync removed CityTycoon) hung here
-- for ever -- "Infinite yield possible on ...WaitForChild('CityTycoon')" --
-- and everything below this line never ran: no Sminski drawn, no PLAY
-- route, the player standing bodiless in the arcade. Now a city that cannot
-- load says so once, and the arcade still works with a body in it.
do
	local ok, res = pcall(function()
		local mod = Root:WaitForChild("City", 10)
		if not mod then error("City module missing from SminskiRunner -- re-run _G.SR_sync()") end
		return require(mod)({
			Config = Config, Models = Models, UI = UI, Audio = Audio, ctx = ctx, Places = Places, Hub = Hub,
			player = player, call = call, getControls = function() return controls end,
			-- job pay lands in the same wallet as everything else, so the city has to
			-- be able to push a fresh data snapshot back into the runner
			setData = function(d) setData(d) end,
		})
	end)
	if ok then
		City = res
		City.gui.Parent = UI.gui.Parent
	else
		City = nil
		warn("[SminskiRunner] Sminski City did not load; the arcade still works: " .. tostring(res))
		task.delay(3, function() UI.toast("Sminski City didn't load -- the arcade still works", UI.C.coral) end)
	end
end
ctx.City = City
ctx.enterCity = function()
	if not City then
		UI.toast("Sminski City didn't load this time -- try rejoining", UI.C.coral)
		return
	end
	if (state ~= "hub" and state ~= "home") or mp or ctx.tourRunning then return end
	if Hub.Garden and Hub.Garden.isOpen() then Hub.Garden.close() end
	UI.open(nil)
	UI.setMode("none")
	Hub.leave()
	setActivity("city")
	state = "city"
	stateT = 0
	Hub.matte = true
	applyLook("city")
	City.enter()
	Audio.ambient(false)
	Audio.musicSoft()
	Audio.play("Whoosh", 0.9, 0.7)
end
ctx.exitCity = function()
	if state ~= "city" or not City then return end
	City.leave()
	UI.toast("welcome to the Sminski Arcade!", UI.C.mintDark)
	Hub.matte = false
	setActivity("hub")
	state = "hub"
	stateT = 0
	UI.setMode("none")
	Hub.enter(false)
	parkCharacter(false)
	camera.CameraType = Enum.CameraType.Custom
	local _, _, hum = myCharacter()
	if hum then camera.CameraSubject = hum end
	Audio.musicStop()
	Audio.ambient(true)
	Audio.play("Whoosh", 1.1, 0.7)
end

---------------------------------------------------------------------------
-- GAMEPLAY EVENTS
---------------------------------------------------------------------------
caught = function()
	if state ~= "playing" then return end
	state = "caught"
	stateT = 0
	caughtAt = Vector3.new(px, py, pz)
	Audio.musicStop(true)
	Audio.play("Bump", 0.9, 1)
	Audio.duck(1, 1.5)
	shake = 1
	timeScale = 0
	if sminski then sminski.trail.Enabled = false end
	UI.hud.Visible = false
	UI.setDanger(0, 0)
	UI.countdown(nil)
	if mp then
		MPc.action("caught", { score = score, distance = distance, coins = coins, nearMisses = nearMisses, bestCombo = bestMult })
	end
end

local function stumble()
	Audio.play("Bump", 1.25, 0.9)
	Audio.duck(0.5, 0.5)
	shake = 0.8
	hitCooldown = 0.5
	comboPts = 0
	mult = 1
	chase -= Config.Chase.Stumble * (passive.stumble or 1)
	UI.flash(UI.C.coral, 0.25)
	if hearts then
		hearts -= 1
		invulnT = 1.2
		UI.popText("OUCH!  -1 ♥", UI.C.coral, 40)
		if hearts <= 0 then caught() end
		return
	end
	UI.popText("OOF!", UI.C.coral, 40)
	if chase <= 0 then
		chase = 0
		caught()
	end
	kidSide = px > 0.5 and -1 or px < -0.5 and 1 or (math.random() < 0.5 and -1 or 1)
end

local function activatePowerup(kind)
	local dur = Config.UpgradeValue(kind, level(kind)) * (passive.power or 1) * (kind == "Boost" and passive.boost or 1)
	powerups[kind] = { left = dur, total = dur }
	local def = Config.Powerups[kind]
	Audio.play("Chime", 1, 1)
	Audio.play("Pop", 1.3, 0.8)
	UI.banner(def.name .. "!", def.color, 1.2)
	UI.flash(def.color, 0.3)
	burst(Vector3.new(px, py + 2, pz), def.color, 16)
	if kind == "Shield" and shieldBubble then
		shieldBubble.Parent = actors
	end
end

local function hasPower(kind)
	local p = powerups[kind]
	return p ~= nil and p.left > 0
end

-- the chaser yells a line for the current chaos tier
local sayBB = Instance.new("BillboardGui")
sayBB.Size = UDim2.fromOffset(320, 84)
sayBB.AlwaysOnTop = true
sayBB.LightInfluence = 0
sayBB.Enabled = false
local sayLabel = Instance.new("TextLabel")
sayLabel.Size = UDim2.fromScale(1, 1)
sayLabel.BackgroundColor3 = Color3.fromRGB(255, 252, 244)
sayLabel.Font = Enum.Font.FredokaOne
sayLabel.TextScaled = true
sayLabel.TextColor3 = Color3.fromRGB(235, 85, 85)
sayLabel.Parent = sayBB
do
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0.4, 0) c.Parent = sayLabel
	local st = Instance.new("UIStroke") st.Thickness = 4 st.Color = Color3.fromRGB(60, 64, 52) st.Parent = sayLabel
	local pad = Instance.new("UIPadding") pad.PaddingLeft = UDim.new(0, 14) pad.PaddingRight = UDim.new(0, 14) pad.PaddingTop = UDim.new(0, 8) pad.PaddingBottom = UDim.new(0, 8) pad.Parent = sayLabel
end
local sayUntil = 0
local function chaserSay(tier)
	local lines = Config.VoiceLines[chaserKind]
	if not lines then return end
	local bucket = lines[math.clamp(tier, 1, #lines)]
	local head = chaserKind == "dog" and (dog.head or dog.model:FindFirstChild("DogHead", true) or dog.model.PrimaryPart) or kid.head
	if not head then return end
	sayBB.Adornee = head
	sayBB.StudsOffsetWorldSpace = Vector3.new(0, chaserKind == "dog" and 6 or 9, 0)
	sayBB.Parent = head
	sayLabel.Text = bucket[math.random(1, #bucket)]
	sayLabel.TextColor3 = chaserKind == "dog" and Color3.fromRGB(200, 120, 40) or Color3.fromRGB(235, 85, 85)
	sayBB.Enabled = true
	sayUntil = t + 2.4
	if chaserKind == "dog" then Audio.play("Bark", 0.9 + math.random() * 0.3, 0.8) else Audio.play("Pop", 0.7 + tier * 0.08, 0.9) end
end

-- random chaos events
local function startEvent()
	local pool = {}
	for kind, def in Config.RunEvents do
		local okMap = not def.maps or def.maps[currentMap]
		local okChaser = not def.needChaser or chaserKind ~= nil
		if okMap and okChaser and not eventK[kind] and runTier >= (def.minTier or 2) then table.insert(pool, kind) end
	end
	if #pool == 0 then return end
	local kind = pool[math.random(1, #pool)]
	local def = Config.RunEvents[kind]
	eventK[kind] = { left = def.dur }
	local title = (kind == "zoom" and chaserKind == "dog") and def.dogTitle or def.title
	UI.banner(title, UI.C.coral, 1.6)
	UI.flash(UI.C.coral, 0.25)
	Audio.play("Wobble", 1.2, 0.8)
	if kind == "rain" then
		powerups.Doubler = { left = def.dur, total = def.dur }
	elseif kind == "slippery" then
		laneK = 0.42
	elseif kind == "avalanche" then
		World.avalanche(pz, 3)
	elseif kind == "zoom" then
		chaserSay(math.min(5, runTier + 1))
	end
end
local function endEvent(kind)
	eventK[kind] = nil
	if kind == "slippery" then laneK = 1 end
end

local function doAction(a)
	if state ~= "playing" then return end
	if a == "right" then
		local lo = World.laneRangeAt(pz)
		if lane > lo then
			prevLane = lane
			lane -= 1
			Audio.play("Whoosh", 1.35, 0.8)
		end
	elseif a == "left" then
		local _, hi = World.laneRangeAt(pz)
		if lane < hi then
			prevLane = lane
			lane += 1
			Audio.play("Whoosh", 1.35, 0.8)
		end
	elseif a == "jump" then
		if grounded then
			vy = JUMP_V
			grounded = false
			slideT = 0
			Audio.play("Jump", 1.15, 1)
		end
	elseif a == "slide" then
		slideT = SLIDE_TIME
		if not grounded then
			vy = math.min(vy, -JUMP_V * 1.2)
			fastFall = true
		end
		Audio.play("Whoosh", 0.8, 0.7)
	end
end

---------------------------------------------------------------------------
-- INPUT: keyboard, touch swipes, gamepad
---------------------------------------------------------------------------
UIS.InputBegan:Connect(function(input, gp)
	if gp or ctx.tourRunning then return end
	local k = input.KeyCode
	if state == "home" and (k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA) then
		startRun()
		return
	end
	if k == Enum.KeyCode.A or k == Enum.KeyCode.Left or k == Enum.KeyCode.DPadLeft then
		doAction("left")
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right or k == Enum.KeyCode.DPadRight then
		doAction("right")
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up or k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.DPadUp then
		doAction("jump")
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down or k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.DPadDown then
		doAction("slide")
	end
end)

local stickArmed = true
UIS.InputChanged:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.Thumbstick1 then return end
	local v = input.Position
	if stickArmed then
		if v.X < -0.7 then doAction("left") ; stickArmed = false
		elseif v.X > 0.7 then doAction("right") ; stickArmed = false
		elseif v.Y > 0.7 then doAction("jump") ; stickArmed = false
		elseif v.Y < -0.7 then doAction("slide") ; stickArmed = false end
	elseif v.Magnitude < 0.3 then
		stickArmed = true
	end
end)

local touchStart
UIS.TouchStarted:Connect(function(input, gp)
	if gp then return end
	touchStart = input.Position
end)
UIS.TouchMoved:Connect(function(input)
	if not touchStart then return end
	local d = input.Position - touchStart
	if d.Magnitude > 36 then
		touchStart = nil
		if math.abs(d.X) > math.abs(d.Y) then
			doAction(d.X < 0 and "left" or "right")
		else
			doAction(d.Y < 0 and "jump" or "slide")
		end
	end
end)
UIS.TouchEnded:Connect(function()
	touchStart = nil
end)

---------------------------------------------------------------------------
-- PHYSICS HELPERS
---------------------------------------------------------------------------
local function groundAt(x, y, z)
	local f = World.frame(z)
	local r = workspace:Raycast((f * CFrame.new(x, y + 2, 0)).Position, f.UpVector * -60, rayParams)
	return r and f:PointToObjectSpace(r.Position).Y or 0
end

local function hitObstacle(x, y, z, sliding)
	local h = sliding and 1.3 or 3.4
	local parts = workspace:GetPartBoundsInBox(World.at(z, x, y + 0.35 + h / 2), Vector3.new(1.5, h, 1.2), overlapParams)
	for _, p in parts do
		if p:GetAttribute("Obs") then return p end
	end
	return nil
end

-- near miss / dodge / perfect-jump detection against obstacle groups
local function checkGroups()
	for _, g in World.groups do
		if not g.resolved and g.z0 < pz + 2 then
			local dx = math.abs(px - g.x)
			if pz >= g.z0 - 0.6 and pz <= g.z1 + 0.6 then
				if dx < 2.4 then
					g.inLane = true
					g.minClear = math.min(g.minClear, py - g.top)
					if slideT > 0 then g.slid = true end
				else
					g.minGap = math.min(g.minGap, dx - 0.75 - 3.2)
				end
			end
			if pz > g.z1 + 0.6 then
				g.resolved = true
				if invulnT > 0 or hasPower("Boost") then continue end
				if g.inLane then
					if g.kind == "block" and g.minClear < 1.3 and g.minClear > -0.5 then
						addCombo("Perfect")
						score += 10 * mult
						UI.popText("PERFECT JUMP!", UI.C.sky, 30)
						Audio.play("Chime", 1.5, 0.5)
					elseif g.kind == "block" or g.kind == "bar" then
						addCombo("Dodge")
						score += 5 * mult
					end
				elseif g.minGap < 1.2 and g.kind ~= "bar" then
					nearMisses += 1
					addCombo("NearMiss")
					if passive.nearMiss then addCombo("NearMiss") end
					score += 25 * mult
					UI.popText("NEAR MISS!  +" .. 25 * mult, UI.C.coral, 34)
					Audio.play("Whoosh", 1.6, 1)
					Audio.play("Chime", 1.8, 0.4)
					slowmoT = 0.14
					surprisedT = 0.3
					shake = math.max(shake, 0.35)
					burst(Vector3.new(px, py + 2, pz), Color3.fromRGB(255, 255, 255), 10)
				end
			end
		end
	end
end

local function allOthers()
	local list = MPc.others()
	for id, b in bots do
		table.insert(list, { userId = id, name = b.info.name, x = b.px, y = b.py, z = b.pz, lane = b.lane, alive = b.alive })
	end
	return list
end

-- one bot tick: look down its lane, dodge like a (fallible) player
local function botScan(l, z0, z1)
	if z1 <= z0 then return nil end
	local parts = workspace:GetPartBoundsInBox(World.at((z0 + z1) / 2, LANES[l], 5), Vector3.new(1.7, 10, z1 - z0), overlapParams)
	local best, bz
	for _, p in parts do
		if p:GetAttribute("Obs") or p.Name == "Ramp" then
			local z = p.Position.Z - p.Size.Z / 2
			if not bz or z < bz then bz = z; best = p end
		end
	end
	if not best then return nil end
	if best.Name == "Ramp" then return "ramp", bz end
	local bottom = best.Position.Y - best.Size.Y / 2
	local top = best.Position.Y + best.Size.Y / 2
	if bottom > 1.5 then return "bar", bz end
	if best.Size.Z > 10 then return "train", bz end
	if top < 5 then return "block", bz end
	return "wall", bz
end

local function botStep(b, dt, rt)
	if not b.alive then
		b.rig.model.Parent = nil
		return
	end
	b.rig.model.Parent = actors
	if rt <= 0 then
		Models.poseSminski(b.rig, World.at(b.pz, b.px, b.py), "idle", t + b.id)
		return
	end
	local spd = Config.SpeedAt(rt)
	b.pz += spd * dt
	b.distance += spd * dt
	b.mult = math.min(6, 1 + b.distance / 1200 * (0.5 + b.skill))
	b.score += spd * dt * 0.5 * b.mult + (math.random() < dt * 0.8 and 10 * b.mult or 0)

	-- decide
	b.cool -= dt
	local look = 8 + spd * (0.3 + 0.25 * b.skill)
	local kind, fz = botScan(b.lane, b.pz + 1.2, b.pz + look)
	if kind and b.cool <= 0 then
		local d = fz - b.pz
		if math.random() < (1 - b.skill) * 0.2 then
			b.cool = 0.4 -- a moment of hesitation
		elseif (kind == "wall" or (kind == "train" and b.py < 5)) then
			local options = {}
			for _, nl in { b.lane - 1, b.lane + 1 } do
				if nl >= 1 and nl <= #LANES then
					local k2 = botScan(nl, b.pz - 3, b.pz + look)
					if k2 ~= "wall" and k2 ~= "train" then table.insert(options, nl) end
				end
			end
			if #options > 0 then
				b.prevLane = b.lane
				b.lane = options[math.random(1, #options)]
				b.cool = 0.35
			end
		elseif kind == "block" and d < spd * 0.16 + 3 and b.grounded then
			b.vy = JUMP_V
			b.grounded = false
			b.cool = 0.3
		elseif kind == "bar" and d < spd * 0.12 + 2 and b.grounded then
			b.slideT = SLIDE_TIME
			b.cool = 0.3
		end
	end

	-- move
	local tx = LANES[b.lane]
	b.px += (tx - b.px) * math.min(1, dt * LANE_LERP)
	local bg = World.glideAt(b.pz)
	if bg then
		if not b.gliding then
			b.gliding = true
			b.glideY0 = math.max(b.py, 0)
			Models.setGlider(b.rig, true)
		end
		b.py = World.glideHeight(bg, b.pz, b.glideY0)
		b.pose = "glide"
		Models.poseSminski(b.rig, World.at(b.pz, b.px, b.py), "glide", t + b.id, { roll = math.clamp((b.px - tx) * 0.09, -0.35, 0.35) })
		return
	elseif b.gliding then
		b.gliding = false
		b.vy, b.grounded = 0, true
		Models.setGlider(b.rig, false)
	end
	b.slideT = math.max(0, b.slideT - dt)
	if b.grounded then b.vy = 0 end
	b.vy -= GRAVITY * dt
	b.py += b.vy * dt
	local g = groundAt(b.px, b.py, b.pz)
	if b.vy <= 0 and b.py <= g + (b.grounded and 1.6 or 0) then
		b.py, b.vy, b.grounded = g, 0, true
	else
		b.grounded = false
	end
	if b.py < -5 then b.py = 0 end

	-- hits
	b.invulnT = math.max(0, b.invulnT - dt)
	b.hitCd = math.max(0, b.hitCd - dt)
	if b.invulnT <= 0 and b.hitCd <= 0 and hitObstacle(b.px, b.py, b.pz, b.slideT > 0) then
		if math.abs(b.px - tx) > 0.6 and b.prevLane ~= b.lane then
			b.lane = b.prevLane
			b.chase -= Config.Chase.Stumble
			b.hitCd = 0.5
		else
			b.chase = 0
		end
	end
	b.chase = math.min(100, b.chase + Config.Chase.Regen * dt)
	if b.chase <= 0 then
		b.alive = false
		MPc.action("caught", { bot = b.id, score = b.score, distance = b.distance, coins = 0, nearMisses = 0, bestCombo = math.floor(b.mult) })
		return
	end

	b.pose = (b.slideT > 0 and b.grounded) and "slide" or (not b.grounded and (b.vy < -8 and "fall" or "jump")) or "run"
	Models.poseSminski(b.rig, World.at(b.pz, b.px, b.py), b.pose, t + b.id, { stride = 17, roll = math.clamp((b.px - tx) * 0.09, -0.35, 0.35) })
	b.statT += dt
	if b.statT >= 1 then
		b.statT = 0
		MPc.action("stats", { bot = b.id, score = b.score, distance = b.distance, coins = 0, nearMisses = 0, bestCombo = math.floor(b.mult) })
	end
end

-- preview helper: jump straight to a map on the home screen
local function previewMap(id)
	data.OwnedMaps = data.OwnedMaps or {}
	data.OwnedMaps[id] = true
	data.SelectedMap = id
end

local function recenter()
	local shift = World.recenter(RECENTER_AT)
	pz -= RECENTER_AT
	if mp then mp.zOffset += RECENTER_AT end
	for _, b in bots do b.pz -= RECENTER_AT end
	camPos -= shift
	camLook -= shift
end

---------------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------------
local function lerp(a, b, k) return a + (b - a) * k end
local QUARTER = CFrame.Angles(0, math.pi / 2, 0)

-- AUTO CAMERA (Settings): when something on the track gets between the
-- camera and your Sminski, the camera rises + leans in, and anything still
-- in the way turns see-through until it's out of the shot
local AC = { lift = 0, faded = {}, params = RaycastParams.new() }
AC.params.FilterType = Enum.RaycastFilterType.Exclude
function AC.cam(pos, look, dt)
	local faded, camParams = AC.faded, AC.params
	for p in faded do
		if p.Parent then p.LocalTransparencyModifier = 0 end
	end
	table.clear(faded)
	local ignore = { actors }
	if player and player.Character then table.insert(ignore, player.Character) end
	camParams.FilterDescendantsInstances = ignore
	local dir = pos - look
	local hit = workspace:Raycast(look, dir, camParams)
	local want = hit and 1 or 0
	AC.lift += (want - AC.lift) * math.min(1, dt * (hit and 7 or 1.8))
	local out = look + dir * (1 - AC.lift * 0.3) + Vector3.new(0, AC.lift * 6, 0)
	-- fade whatever still blocks the new shot
	for _ = 1, 4 do
		camParams.FilterDescendantsInstances = ignore
		local h = workspace:Raycast(look, out - look, camParams)
		if not h then break end
		local p = h.Instance
		if p:IsA("BasePart") and p.Size.Magnitude < 400 then
			p.LocalTransparencyModifier = 0.75
			faded[p] = true
		end
		table.insert(ignore, p)
	end
	return out
end

local function step(rawDt)
	local realDt = math.min(rawDt, 1 / 20)
	t += realDt
	stateT += realDt

	-- neighborhood (home page on top of it, or walking around) and the park
	if state == "city" then
		City.update(realDt, t)
		Hub.updateAvatars(realDt, t, City.poses())
		if previewCam then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = previewCam
		end
		Audio.update(realDt, 0, 0, false)
		return
	end
	if state == "home" or state == "hub" or state == "park" then
		Hub.update(realDt, t, state)
		if state == "park" then
			Park.update(realDt, t)
			return
		end
		Hub.updateAvatars(realDt, t)
		local _, hrp, hum = myCharacter()
		if previewCam then
			-- Studio preview hook: hold the camera still for screenshots
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = previewCam
			camera.FieldOfView = 60
		elseif state == "home" then
			-- cinematic: your Sminski in front of the plaza, UI on top
			camera.CameraType = Enum.CameraType.Scriptable
			local base = hrp and Hub.footCF(hrp) or (CFrame.new(Places.HUB + Places.HubSpawn) * CFrame.Angles(0, 0, 0))
			local sway = math.sin(t * 0.25) * 1.5
			local want = (base * CFrame.new(3.6 + sway, 3.1, 9.5)).Position
			local look = (base * CFrame.new(0, 2.5, 0)).Position
			camPos = camPos:Lerp(want, math.min(1, realDt * 3))
			camLook = camLook:Lerp(look, math.min(1, realDt * 3))
			camera.CFrame = CFrame.lookAt(camPos, camLook)
			camera.FieldOfView += (60 - camera.FieldOfView) * math.min(1, realDt * 4)
			-- start walking = step out of the menu into the neighborhood
			if hum and hum.MoveDirection.Magnitude > 0.1 and stateT > 0.4 and not UI.current() then
				ctx.explore()
			end
		else
			camera.CameraType = Enum.CameraType.Custom
			if hum and camera.CameraSubject ~= hum then camera.CameraSubject = hum end
			camera.FieldOfView += (70 - camera.FieldOfView) * math.min(1, realDt * 4)
			camPos, camLook = camera.CFrame.Position, camera.CFrame.Position + camera.CFrame.LookVector * 10
		end
		Audio.update(realDt, 0, 0, false)
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	-- tiny slow-motion on near misses
	if slowmoT > 0 then
		slowmoT -= realDt
		timeScale = 0.45
	elseif state == "playing" then
		timeScale = math.min(1, timeScale + realDt * 4)
	end
	local slowOn = hasPower("SlowTime")
	local dt = realDt * timeScale

	local pose = "run"
	local kidRun, kidReach = 1, 0.2
	local wantPos, wantLook
	local roll, squash = 0, 0
	local fov = 70
	local danger = 0

	if state == "home" then
		pose = Config.Character(data.EquippedCharacter).idle or "hide"
		kidDist = 22
		kidRun, kidReach = 0, 0.45
		wantPos = Vector3.new(4.2, 2.6, pz + 9.5)
		wantLook = Vector3.new(0, 4.6, pz - 6)
		Audio.update(realDt, 0, 0, false)
	elseif state == "intro" then
		if mp then
			-- everyone's intro ends at the same server time
			stateT = math.max(0, MPc.serverNow() - (mp.startAt - 3.1))
		end
		-- kid notices you, "HEY!", you look back, 3-2-1-GO
		pose = "idle"
		kidDist = lerp(24, 18, math.clamp(stateT / 1.2, 0, 1))
		kidRun, kidReach = 0, math.clamp(stateT / 0.6, 0.2, 0.8)
		if stateT > 0.3 and stateT - realDt <= 0.3 then
			if chaserKind == "kid" then
				kid.bubble.Enabled = true
				Audio.play("Pop", 0.6, 1)
				shake = 0.3
			elseif chaserKind == "dog" then
				Audio.play("Bark", 1, 1)
				UI.popText("WOOF!", UI.C.gold, 54, -60)
				shake = 0.4
			end
		end
		if stateT > 0.6 then lookBack = math.min(1, lookBack + realDt * 5) end
		if stateT > 0.8 and stateT < 1.1 then pose = "surprised" end
		if stateT > 1.4 then lookBack = math.max(0, lookBack - realDt * 3) end
		local k = math.clamp((stateT - 1.0) / 0.9, 0, 1)
		k = k * k * (3 - 2 * k)
		wantPos = Vector3.new(4.2, 2.6, pz + 9.5):Lerp(Vector3.new(0, 7.2, pz - 13), k)
		wantLook = Vector3.new(0, 4.6, pz - 6):Lerp(Vector3.new(0, 2.4, pz + 14), k)
		for i, mark in { { 1.3, "3" }, { 1.9, "2" }, { 2.5, "1" } } do
			if stateT >= mark[1] and stateT - realDt < mark[1] then
				UI.countdown(mark[2])
				Audio.play("Tick", 1.2 + i * 0.1, 1)
			end
		end
		if stateT >= 3.1 then
			UI.countdown("GO!", UI.C.mint)
			Audio.play("Pop", 1.4, 1)
			task.delay(0.5, function() if state == "playing" then UI.countdown(nil) end end)
			kid.bubble.Enabled = false
			state = "playing"
			stateT = 0
			UI.hud.Visible = true
			Audio.musicStart()
			if sminski then sminski.trail.Enabled = true end
		end
		Audio.update(realDt, 0, 0.2, false)
	elseif state == "playing" then
		if mp then
			runTime = math.max(0, MPc.serverNow() - mp.startAt)
		else
			runTime += dt
		end
		local boost = hasPower("Boost")
		speed = Config.SpeedAt(runTime) * (boost and 1.55 or 1) * (slowOn and 0.65 or 1)
		local dz = speed * dt
		pz += dz
		distance += dz
		score += dz * 0.5 * mult

		-- wide regions: 5 lanes. When the path narrows ahead, funnel inward.
		local lo, hi = World.laneRangeAt(pz + 14)
		local curLo, curHi = World.laneRangeAt(pz)
		lo, hi = math.max(lo, curLo), math.min(hi, curHi)
		if lane < lo or lane > hi then
			lane = math.clamp(lane, lo, hi)
			prevLane = lane
			Audio.play("Whoosh", 1.1, 0.6)
		end
		local isWide = curHi - curLo >= 4
		if isWide ~= lastRangeWide then
			lastRangeWide = isWide
			if isWide then
				UI.banner("5 LANES! it's getting wild", UI.C.lav, 1.8)
				Audio.play("Chime", 0.9, 0.8)
			end
		end
		wideK += ((isWide and 1 or 0) - wideK) * math.min(1, realDt * 1.5)
		local tx = LANES[lane]
		px += (tx - px) * math.min(1, dt * LANE_LERP * laneK)
		roll = math.clamp((px - tx) * 0.09, -0.35, 0.35)

		-- glide over gaps (launch ramps throw you into the air on a leaf glider)
		local glide = World.glideAt(pz)
		if glide then
			if not gliding then
				gliding = true
				glideY0 = math.max(py, 0)
				slideT = 0
				chase = math.min(100, chase + 20)
				Audio.play("Whoosh", 0.7, 1.2)
				Audio.play("Chime", 1.2, 0.6)
				UI.popText("GLIDE!", UI.C.sky, 44, -40)
				if sminski then Models.setGlider(sminski, true) end
			end
			py = World.glideHeight(glide, pz, glideY0)
			vy = 0
			grounded = false
		else
			if gliding then
				gliding = false
				vy = 0
				grounded = true
				landBounce = 1
				Audio.play("Land", 1, 1)
				if sminski then Models.setGlider(sminski, false) end
			end
			slideT = math.max(0, slideT - dt)
			local wasGrounded = grounded
			if grounded then vy = 0 end
			vy -= GRAVITY * dt * (vy < 0 and (passive.gravity or 1) or 1)
			py += vy * dt
			local g = groundAt(px, py, pz)
			if vy <= 0 and py <= g + (grounded and 1.6 or 0) then
				if not wasGrounded then
					Audio.play("Land", 1.2, 1)
					landBounce = 1
				end
				py = g
				vy = 0
				grounded = true
				fastFall = false
			else
				grounded = false
			end
			if py < -5 then py = 0 end
		end
		landBounce = math.max(0, landBounce - realDt * 5)

		-- collisions
		invulnT = math.max(0, invulnT - dt)
		hitCooldown = math.max(0, hitCooldown - dt)
		if hitCooldown <= 0 and invulnT <= 0 and not boost and not gliding then
			local hit = hitObstacle(px, py, pz, slideT > 0)
			if hit then
				if hasPower("Shield") then
					powerups.Shield.left = 0
					invulnT = 1.2
					Audio.play("Pop", 0.8, 1)
					UI.flash(Config.Powerups.Shield.color, 0.4)
					UI.popText("SHIELD POP!", Config.Powerups.Shield.color, 32)
				elseif math.abs(px - tx) > 0.6 and prevLane ~= lane then
					lane = prevLane
					prevLane = lane
					stumble()
				elseif hearts and hearts > 1 then
					hearts -= 1
					invulnT = 1.6
					shake = 0.8
					Audio.play("Bump", 1.1, 1)
					UI.flash(UI.C.coral, 0.35)
					UI.popText("BONK!  -1 ♥", UI.C.coral, 42)
				else
					if hearts then hearts = 0 end
					caught()
				end
			end
		end

		if state == "playing" then
			checkGroups()

			-- coins
			local center = Vector3.new(px, py + 1.8, pz)
			local magnet = hasPower("Magnet") or boost
			local pickR = (boost and 5 or 2.7) * (passive.magnet or 1)
			for _, c in World.coins do
				if c.alive and c.pos.Z < pz + 30 and c.pos.Z > pz - 4 then
					if magnet and (c.pos - center).Magnitude < 24 then
						c.pos = c.pos:Lerp(center, math.min(1, dt * 10))
					end
					if (c.pos - center).Magnitude < pickR then
						c.alive = false
						local value = math.floor((c.gold and Config.GoldCoinValue * (passive.gold or 1) or 1) * (passive.coin or 1) * (hasPower("Doubler") and 2 or 1))
						coins += value
						score += 10 * mult * value
						addCombo("Coin")
						Audio.coin(t, c.gold)
						UI.coinBump(value > 1 and value or nil)
						burst(c.pos, c.gold and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(255, 235, 140), c.gold and 12 or 5)
						shake = math.max(shake, 0.04)
						local p = c.part
						if p then
							TweenService:Create(p, TweenInfo.new(0.12), { Size = p.Size * 1.8, Transparency = 1 }):Play()
							task.delay(0.14, function() World.releaseCoin(c) end)
						end
						local tr = c.trail
						tr.got += 1
						if tr.got >= tr.total and tr.total >= 5 and not tr.done then
							tr.done = true
							addCombo("Chain")
							score += 25 * mult
							UI.popText("COIN CHAIN! +" .. 25 * mult, UI.C.gold, 28, -50)
						end
					end
				end
			end

			-- powerup capsules
			for _, pu in World.pickups do
				if pu.alive and math.abs(pu.pos.Z - pz) < 3 and (pu.pos - center).Magnitude < 3.4 then
					pu.alive = false
					pu.shell:Destroy()
					pu.core:Destroy()
					activatePowerup(pu.kind)
				end
			end
			for id, p in powerups do
				if p.left > 0 then
					p.left -= dt
					if p.left <= 0 then
						if id == "Boost" then invulnT = 1 end
						if id == "Shield" and shieldBubble then shieldBubble.Parent = nil end
						Audio.play("Click", 0.8, 0.5)
					end
				end
			end
			if shieldBubble then
				shieldBubble.Parent = hasPower("Shield") and actors or nil
			end

			-- combo slowly cools off when you stop doing things
			if t - lastComboGain > 4 and comboPts > 0 then
				comboPts = math.max(0, comboPts - 12 * dt * (passive.comboCool or 1))
				mult = comboMult(comboPts)
			end

			-- the chase: clean running pulls you away from the kid
			if hearts then
				chase = 100
				heartT += dt * (passive.heartRegen or 1)
				if heartT >= 60 and hearts < maxHearts then
					heartT = 0
					hearts += 1
					UI.popText("+1 ♥", UI.C.mint, 34)
					Audio.play("Chime", 1.3, 0.8)
				end
			else
				chase = math.min(100, chase + (Config.Chase.Regen * (passive.regen or 1) * (eventK.zoom and 0.3 or 1) + Config.Chase.RegenPerCombo * (mult - 1)) * dt)
			end

			-- chaos meter: tiers by time (solo only), random events in between
			if not mp then
				local tier = Config.RunTierAt(runTime)
				if tier ~= runTier then
					runTier = tier
					if tier > 1 then
						UI.banner("CHAOS TIER " .. tier .. "  ·  " .. Config.RunTiers[tier].name, UI.C.coral, 1.6)
						Audio.play("BigChime", 0.75 + tier * 0.1, 0.8)
						chaserSay(tier)
					end
				end
				if runTime > nextEventT then
					nextEventT = runTime + math.random(16, 26)
					if runTier >= 2 then startEvent() end
				end
				for kind, e in eventK do
					e.left -= dt
					if e.left <= 0 then endEvent(kind) end
				end
				if runTime > nextLineT and chaserKind and chase < 70 then
					nextLineT = runTime + math.random(8, 14)
					chaserSay(runTier)
				end
			end
			if sayBB.Enabled and t > sayUntil then sayBB.Enabled = false end

			-- milestones
			local bestM = data.BestDistance / Config.StudsPerMeter
			local curM = distance / Config.StudsPerMeter
			if not announcedNear and data.BestDistance > 0 and bestM - curM < 200 and bestM - curM > 0 then
				announcedNear = true
				UI.banner("NEW BEST IN " .. math.floor(bestM - curM) .. "m", UI.C.sky, 1.6)
			end
			if not announcedBest and data.BestScore > 0 and score > data.BestScore then
				announcedBest = true
				UI.banner("NEW HIGH SCORE!", UI.C.gold, 2)
				Audio.play("BigChime", 1, 0.9)
			end
			local zone = World.zoneAt(pz)
			if zone and zone ~= lastZone then
				if lastZone then UI.banner("~ " .. World.ZONE_TITLES[zone] .. " ~", UI.C.white, 1.4) end
				lastZone = zone
			end
		end

		if mp and state == "playing" then
			-- bumping into other players: whoever swerved into the other does the shoving
			mp.bumpT = math.max(0, (mp.bumpT or 0) - realDt)
			for _, o in allOthers() do
				if o.alive and mp.bumpT <= 0 and math.abs(o.z - pz) < 2.2 and math.abs(o.x - px) < 1.7 and math.abs(o.y - py) < 3 then
					local dirToThem = o.x > px and 1 or -1
					local swerving = lane ~= prevLane and math.abs(px - LANES[lane]) > 0.4 and ((LANES[lane] - px) > 0) == (dirToThem > 0)
					if swerving then
						MPc.action("shove", { target = o.userId, dir = dirToThem })
						lane = prevLane
						prevLane = lane
						UI.popText("BONK!", UI.C.gold, 30)
						Audio.play("Pop", 0.8, 1)
						shake = math.max(shake, 0.3)
						mp.bumpT = 0.6
					else
						mp.bumpT = 0.3
					end
				end
			end
			mp.sendT += realDt
			if mp.sendT >= 1 / 15 then
				mp.sendT = 0
				local pname = gliding and "glide" or (slideT > 0 and grounded) and "slide" or (not grounded and (vy < -8 and "fall" or "jump")) or "run"
				MPc.sendState({ z = pz + mp.zOffset, x = px, y = py, l = lane, p = MPc.POSE_CODE[pname] })
			end
			mp.statT += realDt
			if mp.statT >= 1 then
				mp.statT = 0
				MPc.action("stats", { score = score, distance = distance, coins = coins, nearMisses = nearMisses, bestCombo = bestMult })
			end
		end

		danger = math.clamp((60 - chase) / 60, 0, 1)
		local near = math.clamp((30 - kidDist) / 22, 0, 1)
		kidDist = lerp(kidDist, lerp(7, 62, chase / 100), math.min(1, realDt * 2.5))
		kidReach = chase < 45 and 1 or 0.25

		if slideT > 0 and grounded then
			pose = "slide"
			squash = 0.5
		elseif not grounded then
			pose = slideT > 0 and "slide" or (vy < -8 and "fall" or "jump")
		end
		if surprisedT > 0 then
			surprisedT -= realDt
			pose = "surprised"
		end
		if gliding then pose = "glide" end
		squash = math.max(squash, landBounce * 0.6)

		UI.updateHud({ coins = coins, score = score, distance = distance, best = data.BestScore, mult = mult, comboPts = comboPts, chase = chase, powerups = powerups, t = t, hearts = hearts, maxHearts = maxHearts, chaser = chaserKind })
		UI.setDanger(danger * 0.75, t)
		UI.setChaos(mp and 0 or runTier, runTime)
		UI.setSpeedLines(boost, realDt)
		Audio.update(realDt, math.clamp((speed - 50) / 70, 0, 1), danger, slowOn)
		runFX.TintColor = eventK.lights and Color3.fromRGB(135, 140, 210) or slowOn and Color3.fromRGB(215, 225, 255) or Color3.new(1, 1, 1)
		runFX.Brightness = eventK.lights and -0.28 or 0

		local speedK = math.clamp((speed - 50) / 70, 0, 1)
		local gk = gliding and 1 or 0
		fov = 70 + speedK * 10 + (boost and 8 or 0) + wideK * 5 + gk * 8
		wantPos = Vector3.new(px * lerp(0.7, 0.55, wideK), 7.2 + py * 0.6 + near * 1.5 - landBounce * 0.4 + wideK * 2.5 + gk * 3, pz - 13 - near * 1 - (boost and 2 or 0) - wideK * 2 - gk * 3)
		wantLook = Vector3.new(px * 0.85, 2.4 + py * 0.5, pz + 14)
		if gliding then
			-- follow the glider up close, like a kart glide cam
			wantPos = Vector3.new(px * 0.6, py + 6.5, pz - 11)
			wantLook = Vector3.new(px * 0.85, py + 1.5, pz + 16)
		end
		if pz > RECENTER_AT then
			recenter()
			wantPos -= Vector3.new(0, 0, RECENTER_AT)
			wantLook -= Vector3.new(0, 0, RECENTER_AT)
		end
	elseif state == "caught" then
		-- freeze, the hand comes down, CAUGHT!, scooped up
		if stateT > 0.35 then timeScale = 1 end
		kidDist = lerp(kidDist, 6.5, math.min(1, realDt * 5))
		kidRun, kidReach = 0.2, 1
		pose = stateT < 0.6 and "surprised" or "flail"
		lookBack = math.min(1, lookBack + realDt * 6)
		if stateT > 0.35 and stateT - realDt <= 0.35 then
			UI.caught(true, hearts ~= nil and "OUT OF HEARTS!" or chaserKind == "dog" and "FETCHED!" or "CAUGHT!")
			TweenService:Create(runFX, TweenInfo.new(0.6), { Saturation = -0.55 }):Play()
		end
		if stateT > 1.0 and stateT - realDt <= 1.0 then
			Audio.play("Wobble", 1, 1)
		end
		wantPos = Vector3.new(px * 0.5 + 16, 12, pz + 34)
		wantLook = Vector3.new(px * 0.7, 16, pz - 6)
		if stateT > 1.9 and mp then
			state = "down"
			stateT = 0
			UI.caught(false)
			UI.setMode("run")
			UI.hud.Visible = false
		elseif stateT > 1.9 then
			local canPay = data.Coins >= reviveCost()
			local robux = Config.ReviveProductId ~= nil and player ~= nil
			if freeRevives > 0 or canPay or robux then
				state = "revive"
				stateT = 0
				reviveT = 5
				revivePaused = false
				UI.caught(false)
				UI.showRevive({ free = freeRevives, cost = reviveCost(), coins = data.Coins, robux = robux })
			else
				finishRun()
			end
		end
		Audio.update(realDt, 0, 0, false)
	elseif state == "down" or state == "mpresults" then
		-- spectate whoever is furthest ahead while waiting to respawn
		local leader
		for _, o in allOthers() do
			if o.alive and (not leader or o.z > leader.z) then leader = o end
		end
		if leader and state == "down" then
			-- glide to the leader (a late joiner may be thousands of studs behind)
			pz += math.clamp(leader.z - pz, -2000, 900)
			px = leader.x
		end
		kidRun, kidReach = 1, 0.3
		pose = "run"
		wantPos = Vector3.new(px * 0.7, 9.5, pz - 15)
		wantLook = Vector3.new(px * 0.85, 2.4, pz + 14)
		if state == "down" and mp then
			local at = mp.down[myUserId]
			UI.showDown(at and math.max(0, at - MPc.serverNow()) or nil, leader and leader.name)
		end
		if pz > RECENTER_AT then
			recenter()
			wantPos -= Vector3.new(0, 0, RECENTER_AT)
			wantLook -= Vector3.new(0, 0, RECENTER_AT)
		end
		Audio.update(realDt, 0.3, 0, false)
	elseif state == "revive" or state == "results" then
		kidRun, kidReach = 0.1, 1
		pose = "flail"
		lookBack = 1
		wantPos = Vector3.new(px * 0.5 + 16, 12, pz + 34)
		wantLook = Vector3.new(px * 0.7, 16, pz - 6)
		if state == "revive" and not revivePaused then
			reviveT -= realDt
			UI.setReviveTimer(reviveT / 5)
			if reviveT <= 0 then finishRun() end
		end
		if state == "results" and stateT > 0.1 and stateT - realDt <= 0.1 then
			Audio.musicSoft()
		end
		Audio.update(realDt, 0, 0, false)
	end

	World.update(pz, runTime, luckLevel())
	World.updateHazards(state == "playing" and dt or 0, pz)

	-- spin coins + bob powerups
	local spin = t * 4
	for _, c in World.coins do
		if c.alive and c.part and c.pos.Z < pz + 260 and c.pos.Z > pz - 20 then
			c.part.CFrame = World.at(c.pos.Z, c.pos.X, c.pos.Y + math.sin(t * 4 + c.pos.Z * 0.2) * 0.18) * CFrame.Angles(0, spin, 0) * (c.part:GetAttribute("M") and CFrame.identity or QUARTER)
		end
	end
	for _, pu in World.pickups do
		if pu.alive then
			local cf = World.at(pu.pos.Z, pu.pos.X, pu.pos.Y + math.sin(t * 3) * 0.4) * CFrame.Angles(0, t * 2, 0)
			pu.shell.CFrame = cf
			pu.core.CFrame = cf
		end
	end

	-- the kid: behind you, lunging in from the side when close
	local kidTargetX = px
	if (state == "playing") and kidDist < 30 then
		kidTargetX = px + kidSide * 13 * math.clamp((30 - kidDist) / 12, 0, 1)
	end
	kidX += (kidTargetX - kidX) * math.min(1, realDt * 3)
	local kidPh = 0
	if chaserKind == "kid" then
		local ks = pz - kidDist
		local kg = World.glideAt(ks)
		kidPh = Models.poseKid(kid, World.at(ks, kidX, kg and World.glideHeight(kg, ks, 0) or 0), t, kidRun, kidReach)
	elseif chaserKind == "dog" then
		-- the dog's body sits further back so its mouth lands where the kid's hand would
		local ds = pz - kidDist - 12
		local dg = World.glideAt(ds)
		kidPh = Models.poseDog(dog, World.at(ds, kidX, dg and World.glideHeight(dg, ds, 0) or 0), t, kidRun, kidReach)
		if state == "playing" and danger > 0.45 and math.random() < realDt * 0.5 then
			Audio.play("Bark", 0.95 + math.random() * 0.15, 0.8)
		end
	end
	local s = math.sin(kidPh)
	if state == "playing" and chaserKind and (s > 0) ~= (kidLastSin > 0) then
		Audio.stomp(danger)
		if danger > 0.5 and data.Settings.Shake then shake = math.max(shake, danger * 0.25) end
	end
	kidLastSin = s

	if mp then
		MPc.update(t, mp.zOffset, World.at)
		if not mp.over and next(bots) then
			local rt = MPc.serverNow() - mp.startAt
			for _, b in bots do
				botStep(b, realDt, rt)
			end
			mp.botSendT = (mp.botSendT or 0) + realDt
			if mp.botSendT >= 1 / 15 then
				mp.botSendT = 0
				local pack = {}
				for id, b in bots do
					pack[tostring(id)] = { z = b.pz + mp.zOffset, x = b.px, y = b.py, l = b.lane, p = b.alive and (MPc.POSE_CODE[b.pose] or 1) or 5 }
				end
				MPc.sendState({ bots = pack })
			end
		end
	end

	-- the sminski
	if sminski then
		sminski.model.Parent = (state == "down" or state == "mpresults") and nil or actors
		local rootCF
		if (state == "caught" and stateT > 0.5) or state == "revive" or state == "results" then
			local here = World.at(pz, px, py)
			local held = chaserKind and (holdPoint() - Vector3.new(0, 3.2, 0)) or World.at(pz, px, py + 1.5).Position
			local k = state == "caught" and math.clamp((stateT - 0.5) * 3, 0, 1) or 1
			rootCF = CFrame.new(here.Position:Lerp(held, k)) * here.Rotation * CFrame.Angles(0, math.pi, 0)
		else
			rootCF = World.at(pz, px, py)
		end
		local stride = 13 + math.clamp((speed - 50) / 70, 0, 1) * 8
		Models.poseSminski(sminski, rootCF, pose, t, { roll = roll, lookBack = lookBack, squash = squash, stride = stride })
		if shieldBubble then
			shieldBubble.CFrame = rootCF * CFrame.new(0, 1.9, 0)
		end
		-- blink while invulnerable after a revive/boost
		local blink = invulnT > 0 and state == "playing" and (math.floor(t * 12) % 2 == 0)
		for _, e in sminski.parts do
			e.p.LocalTransparencyModifier = blink and 0.6 or 0
		end
	end

	-- camera
	local a = math.min(1, realDt * 7)
	camPos = camPos:Lerp(World.toWorld(wantPos), a)
	camLook = camLook:Lerp(World.toWorld(wantLook), a)
	shake = math.max(0, shake - realDt * 2.5)
	local sh = data.Settings.Shake and shake or shake * 0.2
	local offset = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, 0) * sh * 0.5
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, realDt * 4)
	local finalPos = camPos
	if data.Settings.AutoCam ~= false then finalPos = AC.cam(camPos, camLook, realDt) end
	camera.CFrame = CFrame.lookAt(finalPos + offset, camLook)
	if previewCam then camera.CFrame = previewCam end
end

respawnMe = function(localZ, newLane)
	pz = localZ
	if maxHearts and maxHearts > 0 then hearts = maxHearts end -- hearts maps: come back with full hearts
	gliding = false
	if sminski then Models.setGlider(sminski, false) end
	lane = math.clamp(newLane or lane, 1, #LANES)
	prevLane = lane
	px = LANES[lane]
	py, vy = 0, 0
	grounded = true
	slideT = 0
	World.clearAhead(pz - 6, pz + 70)
	chase = 60
	invulnT = 3
	lookBack = 0
	timeScale = 1
	state = "playing"
	stateT = 0
	UI.showDown(nil)
	UI.setMode("run")
	UI.hud.Visible = true
	TweenService:Create(runFX, TweenInfo.new(0.4), { Saturation = 0 }):Play()
	UI.popText("BACK IN!", UI.C.mint, 40)
	Audio.play("Pop", 1.2, 1)
	Audio.musicStart()
	if sminski then sminski.trail.Enabled = true end
end

---------------------------------------------------------------------------
-- BOOT
---------------------------------------------------------------------------
camera.CameraType = Enum.CameraType.Scriptable
rebuildSminski()
shieldBubble = Models.part(nil, Vector3.new(5.2, 5.2, 5.2), CFrame.new(), Color3.fromRGB(150, 200, 255), Enum.Material.ForceField, { shape = Enum.PartType.Ball, noShadow = true })
applySettings()
UI.refresh()
goHome()
-- the daily gift pops up once per session, after the tour if there is one
ctx.maybeShowGift = function()
	if ctx._giftShown or not player then return end
	task.delay(1, function()
		if ctx._giftShown or ctx.tourRunning or (state ~= "home" and state ~= "hub") or UI.current() then return end
		if data.DailyReady then
			ctx._giftShown = true
			UI.open("daily")
		end
	end)
end
-- brand-new players get the tour once (replay it from Settings)
-- everyone starts out WALKING, on the bridge between the table (mini games)
-- and the arch to Sminski City: no menu wall, nobody left standing at spawn.
-- (The menu is one tap away, and the table tour is in Settings.)
-- the game opens in Sminski City: you're already walking around town, and the
-- big ARCADE on Main St is the way into the runs / dog park / shops
if player then
	task.defer(function()
		if state == "home" and not UI.current() then
			state = "hub"
			stateT = 0
			UI.open(nil)
			UI.setMode("none")
			if ctx.enterCity then ctx.enterCity() end
		end
		---------------------------------------------------------------------
		-- THE TITLE SCREEN. SminskiTitle (ReplicatedFirst) is already up and
		-- covering the screen. The city has just STARTED streaming above --
		-- deliberately, because the whole point is that the world builds
		-- behind the intro instead of in front of the player.
		--
		-- So this does two things: feed the loading bar the truth, and hold
		-- the game's own UI back until PLAY is pressed.
		---------------------------------------------------------------------
		local RF = game:GetService("ReplicatedFirst")
		local bar = RF:FindFirstChild("SR_Progress")
		local playEvent = RF:FindFirstChild("SR_Play")
		if bar and playEvent then
			UI.gui.Enabled = false
			if City and City.gui then City.gui.Enabled = false end
			-- hold the welcome tour: the city is entered behind the title, so
			-- without this it runs and finishes against a screen nobody is
			-- looking at, and all the player ever sees is the leftover card
			if City and City.Guide then City.Guide.hold = true end
			-- the bar tracks the blocks that are actually built near you,
			-- which is the same readiness test the in-city curtain uses
			local feeding = true
			task.spawn(function()
				while feeding do
					local ok, frac = pcall(function() return City.loadProgress() end)
					bar.Value = (ok and frac) or 0
					task.wait(0.15)
				end
			end)
			-- PEEK: a menu option that is a screen rather than a place. The
			-- title stays up with the world drifting behind it; we just turn
			-- the game's UI on long enough to show the screen, then turn it
			-- back off and tell the title to fade its menu back in.
			local peekEv = RF:FindFirstChild("SR_Peek")
			local backEv = RF:FindFirstChild("SR_MenuBack")
			local entered = false
			if peekEv and backEv then
				peekEv.Event:Connect(function(what)
					UI.gui.Enabled = true
					if City and City.gui then City.gui.Enabled = true end
					if City then City.hudVisible(false) end
					task.wait(0.15)
					if what == "work" and City.openWork then City.openWork()
					elseif what == "shop" and City.openStore then City.openStore()
					else
						UI.setMode("home")
						UI.refresh()
						UI.open("settings")
					end
					-- wait for them to close it, then hand the menu back
					task.wait(0.6)
					while (UI.current() ~= nil) or (City and City.anyModalOpen and City.anyModalOpen()) do
						task.wait(0.25)
					end
					-- back to the menu, which is still up behind this screen
					UI.setMode("none")
					UI.gui.Enabled = false
					if City and City.gui then City.gui.Enabled = false end
					backEv:Fire()
				end)
			end
			-- CONNECT, do not Wait. The menu can be reopened from the city HUD
			-- any number of times, and a one-shot :Wait() would hand over once
			-- and then silently swallow every press after that.
			playEvent.Event:Connect(function()
				entered = true
				if City and City.Guide then City.Guide.release() end
				feeding = false
				local ch = RF:FindFirstChild("SR_Choice")
				local picked = ch and ch.Value or "play"
				UI.gui.Enabled = true
				if City and City.gui then City.gui.Enabled = true end
				if City then City.hudVisible(true) end
				-- GO TO MY HOUSE actually goes there. Laying a green line and
				-- leaving you at the far side of town is not what a menu item
				-- called "go to my house" promises.
				task.delay(0.3, function()
					if picked == "home" and City then
						local at = City.Home and City.Home.doorPos and City.Home.doorPos()
						if at and City.travel then
							City.travel(at)
							UI.toast("home sweet home", UI.C.mintDark)
						elseif City.Home then
							City.Home.guide()
							UI.toast("follow the green line home!", UI.C.mintDark)
						end
					end
				end)
			end)
		end
		ctx.maybeShowGift()
	end)
end
if MPc.available then
	task.spawn(MPc.request, "status")
end

if not PREVIEW then
	RunService.RenderStepped:Connect(step)
	if RunService:IsStudio() then
		-- Studio-only dev hooks (screenshots / testing from the command bar)
		_G.SRdev = {
			cam = function(pos, look) previewCam = pos and CFrame.lookAt(pos, look) or nil end,
			start = startRun,
			map = function(id) previewMap(id) end,
			godMode = function(secs) invulnT = secs or 999 end,
			setHour = function(h) Hub.debugHour = h end,
			hud = function(on) UI.gui.Enabled = on end,
			-- the three look layers, through the same calls the shop buttons
			-- make (which matters: your OWN avatar is drawn from ctx.data, so
			-- poking the remote directly leaves the rig showing the old look)
			skin = function(id, buy)
				if buy then ctx.buySkin(id) else ctx.equipSkin(id) end
				task.wait(0.7)
				return (data.EquippedSkin or "none") .. " | owned=" .. tostring((data.OwnedSkins or {})[id] == true)
			end,
			look = function() return (data.EquippedCharacter or "?") .. " / " .. (data.EquippedSkin or "none") .. " / " .. (data.EquippedOutfit or "None") end,
			info = function() return { state = state, pz = pz, tier = runTier, events = eventK, chase = chase, coins = coins } end,
			home = function() goHome() end,
			open = function(name) UI.open(name) end,
			explore = function() ctx.explore() end,
			tp = function(x, y, z)
				local _, hrp = myCharacter()
				if hrp then hrp.CFrame = CFrame.new(Places.HUB + Vector3.new(x, y, z)) end
			end,
			-- drive the city's interactions without a mouse (automated tests):
			--   city("tour") / ("tourNext") / ("tourSkip")   the welcome tour
			--   city("jobs", bool)                            fold / unfold CITY JOBS
			--   city("prompt")                                press whatever venue prompt is up
			--   city("eat") / ("venue")                       eat a bite / report venue state
			--   city("knock")                                 get hit by an imaginary bus
			city = function(cmd, arg)
				local Cy = ctx.City
				if not Cy then return "no city" end
				local _, hrp = myCharacter()
				local me = hrp and (hrp.Position - Places.CITY) or Vector3.zero
				if cmd == "tour" then Cy.Guide.start() return Cy.Guide.step
				elseif cmd == "tourNext" then Cy.Guide.next() return Cy.Guide.step or "done"
				elseif cmd == "tourSkip" then Cy.Guide.finish() return "done"
				elseif cmd == "stand" then
					-- a scripted Humanoid:Move is overwritten by Roblox's own
					-- control module every frame, so a test cannot "walk off" a
					-- seat the way a player does. This releases every seat.
					Cy.Hang.sitting, Cy.Hang.holding = nil, nil
					if Cy.Venues then Cy.Venues.sitting = nil end
					if Cy.Apts then Cy.Apts.sitting = nil end
					if Cy.Home then Cy.Home.sitting = nil end
					return "released"
				elseif cmd == "way" then
					-- city("way", "the Mall") routes there; city("way", false) clears
					local Wy = Cy.Way
					if arg == false then Wy.clear() return "cleared" end
					if type(arg) == "string" then
						for _, m in Places.CityLandmarks do
							if string.lower(m.name) == string.lower(arg) then Wy.to(m.pos, m.name) break end
						end
					end
					local segs = 0
					local mdl = Cy and workspace:FindFirstChild("SminskiCityActors")
					mdl = mdl and mdl:FindFirstChild("Wayfinding")
					if mdl then for _, d in mdl:GetDescendants() do if d:IsA("BasePart") then segs += 1 end end end
					return { dest = Wy.name or false, reachable = Wy.reachable, parts = segs }
				elseif cmd == "sky" then
					-- city("sky") reports; city("sky", 2.5) forces 2:30am;
					-- city("sky", "rain") forces a state; city("sky", false) releases
					local Wx = Cy.Weather
					if arg == false then Wx.debugHour, Wx.debugState = nil, nil
					elseif type(arg) == "number" then Wx.debugHour = arg
					elseif type(arg) == "string" then Wx.debugState = arg end
					Wx.step(0, 0, me, true)
					local f = Wx.look()
					return f and { hour = f.hour, clock = f.clock, state = f.state and f.state.id, name = f.state and f.state.name,
						bright = f.bright, haze = f.atm[6], wet = f.wet, lamps = f.lamps, cloudCover = f.clouds[1] } or "no look"
				elseif cmd == "apts" then
					-- arg = nil: report; arg = "tour:<plan>" / "buy:<plan>" / "leave"
					local A = Cy.Apts
					if type(arg) == "string" then
						local verb, plan = string.match(arg, "^(%a+):?(%a*)$")
						if verb == "tour" then A.tour(plan) elseif verb == "buy" then A.buy(plan) elseif verb == "leave" then A.leave() end
					end
					local doors = {}
					-- one door per building, so a test can reach any of the five
					local seen = {}
					for _, d in A.doors do
						if not seen[d.id] then seen[d.id] = true table.insert(doors, { id = d.id, x = d.pos.X, z = d.pos.Z }) end
					end
					return { inside = A.inside and A.inside.id or false, owned = A.owned, doors = doors, nDoors = #A.doors }
				elseif cmd == "rail" then
					-- where the trains and the lifts are (for the automated tests)
					local out = { trains = {}, lifts = {}, riding = Cy.Roads.riding ~= nil }
					for i, tr in Cy.Roads.trains do out.trains[i] = { s = math.floor(tr.s), v = math.floor(tr.v), dwell = tr.dwell, at = tr.at and tr.at.name or false } end
					for i, lf in Cy.Roads.lifts do out.lifts[i] = { name = lf.station.name, bx = lf.bottom.X, bz = lf.bottom.Z, tx = lf.top.X, ty = lf.top.Y, tz = lf.top.Z } end
					return out
				elseif cmd == "prompt" then
					-- same order the real promptTick uses, or the hook lies about
					-- what a player would actually be offered here
					local pr = Cy.Apts.prompt(me)
					if pr == "none" or not pr then
						pr = Cy.Roads.prompt(me) or Cy.Hang.prompt(me) or Cy.Venues.prompt(me)
					end
					if not pr then return "no prompt" end
					if pr[5] then pr[5]() end
					return tostring(pr[1]) .. " / " .. tostring(pr[3])
				elseif cmd == "order" then
					-- what the menu card's ORDER button does, for the venue you are in
					local v = Cy.Venues.here(me)
					if not v or not v.menu then return "not in a food place" end
					Cy.Venues.order(v, v.menu[arg or 1])
					return v.name .. ": " .. v.menu[arg or 1]
				elseif cmd == "jobs" then return Cy.setJobsOpen(arg == true)
				elseif cmd == "eat" then Cy.Venues.eat() return Cy.Venues.food and Cy.Venues.food.bites or "finished"
				elseif cmd == "venue" then
					local V = Cy.Venues
					return { sitting = V.sitting ~= nil, food = V.food and V.food.name or false, bites = V.food and V.food.bites or 0, emote = V.emote and V.emote.pose or false }
				elseif cmd == "knock" then Cy.knock(Vector3.new(1, 0, 0), 40) return "knocked"
				elseif cmd == "store" then
					-- arg = a tab name ("coins" / "boosts" / "passes")
					Cy.openStore(type(arg) == "string" and arg or nil)
					local rows = {}
					for _, pg in Cy.storePages or {} do rows[pg.name] = #pg:GetChildren() end
					return { open = true, tab = Cy.storeTab and Cy.storeTab() or "?" }
				elseif cmd == "job" then
					-- arg = "open" / "start:<id>" / "quit" / "order" / "step" / nil
					local J, Kt = Cy.Jobs, Cy.Kitchen
					if type(arg) == "string" then
						local verb, id = string.match(arg, "^(%a+):?([%w_]*)$")
						if verb == "open" then J.open()
						elseif verb == "start" then J.start(id) task.wait(0.6)
						elseif verb == "quit" then J.quit() task.wait(0.6)
						elseif verb == "order" then Kt.newOrder(Kt.venue or Kt.at(me)) task.wait(0.3)
						elseif verb == "step" or verb == "sloppy" then
							-- walk the pipeline without a human thumb: open the
							-- station this ticket wants next, then play it
							local pr = Kt.prompt(me)
							if pr and pr[5] then pr[5]() task.wait(0.25) end
							if Kt.autoPlay then Kt.autoPlay(verb == "sloppy") end
							task.wait(0.4)
						end
					end
					local o = Kt.order
					return {
						elo = J.state and J.state.elo, rank = J.state and J.state.rank,
						job = J.state and J.state.job, tasks = J.state and J.state.tasks,
						shift = J.state and J.state.shift,
						order = o and { item = o.ticket.name, want = o.ticket.note, step = o.step, scores = o.scores } or false,
						at = (Kt.at(me) or {}).name or false,
					}
				elseif cmd == "press" then
					-- press whatever the prompt card is offering right now (a
					-- shelf's TAKE, the till's PAY, the fridge's SNACK) -- the
					-- only way a test can push that button
					if Cy.doPrompt then Cy.doPrompt() end
					task.wait(0.4)
					local G = Cy.Grocery
					return { basket = G and G.basket or {}, count = G and G.count or 0, total = G and G.total() or 0, pantry = G and G.pantryCount() or 0 }
				elseif cmd == "tycoon" then
					-- Restaurant Row (docs/TYCOON.md). arg = "goto:<lot>" (stand at
					-- that lot's gate) / "spot:<lot>:<name>" (stand on a spot) /
					-- "open" / "stock" / "menu:<lot>" / "serve" (play the queued
					-- customer's steps with the kitchen's auto-player) / nil
					local Ty = Cy.Tycoon
					local Places = require(game.ReplicatedStorage.SminskiShared.Places)
					if type(arg) == "string" then
						local verb, a, b = string.match(arg, "^(%a+):?([%w_]*):?([%w_]*)$")
						local function standAt(p, face)
							local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							if hrp and p then
								hrp.CFrame = CFrame.new(Places.CITY + p + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, face or 0, 0)
								hrp.AssemblyLinearVelocity = Vector3.zero
							end
							task.wait(0.5)
						end
						local lot = Places.tycoonLots()[tonumber(a) or 0]
						if verb == "goto" and lot then standAt(Places.tycoonSpot(lot, "gate"), lot.face)
						elseif verb == "spot" and lot then standAt(Places.tycoonSpot(lot, b), lot.face)
						elseif verb == "open" then Ty.open()
						elseif verb == "stock" then Ty.openStock()
						elseif verb == "menu" and lot then Ty.openMenu(lot.i)
						elseif verb == "serve" then
							Ty.serve()
							task.wait(0.3)
							for _ = 1, 3 do
								if Cy.Kitchen.autoPlay then Cy.Kitchen.autoPlay() end
								task.wait(0.5)
							end
							task.wait(0.8)
						end
					end
					local cu = Ty.cust
					local d = ctx and ctx.data and ctx.data.City and ctx.data.City.tycoon
					local pieces = {}
					for id in pairs(d and d.pieces or {}) do table.insert(pieces, id) end
					table.sort(pieces)
					return {
						mine = Ty.mine, sum = Ty.sum, pieces = pieces, stock = d and d.stock or {}, till = d and d.till, bank = d and d.bank,
						name = d and d.name, chains = d and d.chains, xp = d and d.xp,
						customer = cu and { dish = cu.dish.id, arrived = cu.arrived } or false,
						prompt = (function() local p = Ty.prompt(me) return p and { p[1], p[2], p[3] } or false end)(),
					}
				elseif cmd == "town" then
					-- arg = a tab name ("who" / "shops" / "rich")
					Cy.openTown(type(arg) == "string" and arg or nil)
					local t0 = os.clock()
					while not Cy.town.roster and os.clock() - t0 < 5 do task.wait(0.1) end
					local out = {}
					for _, r in Cy.town.roster or {} do
						table.insert(out, r.name .. " lvl" .. r.level .. " " .. r.coins .. "c "
							.. (r.where and r.where.name or "nowhere") .. " biz=" .. #r.biz)
					end
					return { tab = Cy.town.tab, n = #out, rows = out }
				elseif cmd == "biz" then
					-- arg = "open" / "collect:<id>" / "all"
					if arg == "all" then
						Cy.biz.all.face.Text = Cy.biz.all.face.Text
					end
					Cy.openBiz()
					local out = {}
					for _, r in Cy.biz.rows do
						table.insert(out, r.def.id .. "=" .. r.amt.Text .. (r.note.Text ~= "" and ("/" .. r.note.Text) or "") .. " " .. string.format("%.2f", r.fill.Size.X.Scale))
					end
					return { open = Cy.biz.shade.Visible, blurb = Cy.biz.blurb.Text, rows = out }
				end
				return "unknown"
			end,
		}
		-- the command bar runs in its own environment, so expose the hooks as a BindableFunction too
		local bf = Instance.new("BindableFunction")
		bf.Name = "SminskiDev"
		bf.OnInvoke = function(cmd, ...)
			local f = _G.SRdev[cmd]
			return f and f(...)
		end
		bf.Parent = player:WaitForChild("PlayerScripts")
	end
else
	-- edit-mode preview hooks
	return {
		step = step,
		start = startRun,
		act = doAction,
		stumble = stumble,
		ctx = ctx,
		previewMap = function(id) previewMap(id) goHome() end,
		godMode = function(secs) invulnT = secs or 999 end,
		setHour = function(h) Hub.debugHour = h end,
		cam = function(pos, look) previewCam = pos and CFrame.lookAt(pos, look) or nil end,
		glideInfo = function() return gliding, py end,
		UI = UI,
		info = function()
			local lo, hi = World.laneRangeAt(pz)
			return { lo = lo, hi = hi, state = state, pz = pz, px = px, py = py, lane = lane, coins = coins, score = math.floor(score), chase = chase, mult = mult, kidDist = kidDist, grounded = grounded, nearMisses = nearMisses }
		end,
		cleanup = function()
			worldFolder:Destroy()
			actors:Destroy()
			shieldBubble:Destroy()
			UI.gui:Destroy()
			Audio.destroy()
			runFX:Destroy()
			for _, e in look do if typeof(e) == "Instance" then e:Destroy() end end
			dog.model:Destroy()
		end,
	}
end
