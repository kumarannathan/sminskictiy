-- SMISKI ESCAPE
-- An endless runner: you're a little glow-in-the-dark Smiski toy running
-- through a giant suburban house while a giant kid tries to grab you.
-- Everything (world, characters, UI) is built client-side by this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

-- when not running (edit-mode preview from the command bar) there is no real player
local PREVIEW = not RunService:IsRunning()
local player = not PREVIEW and Players.LocalPlayer or nil
local camera = workspace.CurrentCamera

task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then break end
		task.wait(0.5)
	end
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

---------------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------------
local LANE_W = 7
local LANES = { -LANE_W, 0, LANE_W }
local SEG_LEN = 80
local SEGS_AHEAD = 9
local SEGS_BEHIND = 2
local START_SPEED = 52
local MAX_SPEED = 112
local ACCEL = 0.75
local GRAVITY = 175
local JUMP_V = 54
local SLIDE_TIME = 0.6
local LANE_LERP = 13
local KID_FAR = 48
local KID_NEAR = 9
local STUMBLE_WINDOW = 6
local RECENTER_AT = 3000

local SMISKI_GREEN = Color3.fromRGB(212, 236, 176)
local STAR_COLOR = Color3.fromRGB(255, 200, 40)
local TOY_COLORS = {
	Color3.fromRGB(255, 105, 97), Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 225, 90),
	Color3.fromRGB(110, 200, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(170, 120, 230),
	Color3.fromRGB(255, 140, 190),
}

local RNG = Random.new()
local SM = Enum.Material.SmoothPlastic

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function part(parent, size, cf, color, material, opts)
	local p = Instance.new((opts and opts.class) or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SM
	if opts then
		if opts.shape then p.Shape = opts.shape end
		if opts.mesh then
			local m = Instance.new("SpecialMesh")
			m.MeshType = opts.mesh
			m.Parent = p
		end
		if opts.transparency then p.Transparency = opts.transparency end
		if opts.noShadow then p.CastShadow = false end
		if opts.walk then p.CanQuery = true end
		if opts.obs then
			p.CanQuery = true
			p:SetAttribute("Obs", true)
		end
		if opts.reflect then p.Reflectance = opts.reflect end
	end
	p.Parent = parent
	return p
end

local function pick(t)
	return t[RNG:NextInteger(1, #t)]
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local sfxFolder = Instance.new("Folder")
sfxFolder.Name = "SmiskiRunnerSFX"
sfxFolder.Parent = SoundService
local function newSound(id, vol)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.5
	s.Parent = sfxFolder
	return s
end
local SFX = {
	jump = newSound("rbxasset://sounds/action_jump.mp3", 0.35),
	land = newSound("rbxasset://sounds/action_jump_land.mp3", 0.25),
	star = newSound("rbxasset://sounds/volume_slider.ogg", 0.5),
	hit = newSound("rbxasset://sounds/ouch.ogg", 0.6),
	swoosh = newSound("rbxasset://sounds/action_swim.mp3", 0.2),
}
local function play(name, pitch)
	local s = SFX[name]
	if not s then return end
	s.PlaybackSpeed = pitch or 1
	s.TimePosition = 0
	s:Play()
end

---------------------------------------------------------------------------
-- WORLD FOLDERS
---------------------------------------------------------------------------
local world = Instance.new("Folder")
world.Name = "RunnerWorld"
world.Parent = workspace

local actors = Instance.new("Folder")
actors.Name = "RunnerActors"
actors.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { world }

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = { world }

---------------------------------------------------------------------------
-- SMISKI RIG
---------------------------------------------------------------------------
local function buildSmiski(parent, scale, glow)
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Smiski"
	local function sp(name, size)
		local p = part(m, size * s, CFrame.new(), SMISKI_GREEN, SM, { mesh = Enum.MeshType.Sphere })
		p.Name = name
		return p
	end
	local rig = { model = m, scale = s }
	rig.body = sp("Body", Vector3.new(1.75, 1.8, 1.5))
	rig.head = sp("Head", Vector3.new(2.35, 2.1, 2.05))
	rig.armL = sp("ArmL", Vector3.new(0.52, 1.15, 0.52))
	rig.armR = sp("ArmR", Vector3.new(0.52, 1.15, 0.52))
	rig.legL = sp("LegL", Vector3.new(0.64, 1.0, 0.68))
	rig.legR = sp("LegR", Vector3.new(0.64, 1.0, 0.68))
	if glow ~= false then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(190, 255, 150)
		light.Brightness = 0.9
		light.Range = 9 * s
		light.Shadows = false
		light.Parent = rig.body
	end
	m.PrimaryPart = rig.body
	m.Parent = parent
	return rig
end

-- rootCF sits at the smiski's feet; local +Z is "forward"
local function poseSmiski(rig, rootCF, pose, t, roll)
	local s = rig.scale
	local aL, aR, lL, lR = 0, 0, 0, 0
	local rL, rR = -0.18, 0.18
	local headTilt = 0
	local bodyCF = rootCF
	roll = roll or 0

	if pose == "run" then
		local w = math.sin(t * 15)
		lL, lR = -w * 0.95, w * 0.95
		aL, aR = w * 1.1, -w * 1.1
		bodyCF = rootCF * CFrame.new(0, math.abs(math.cos(t * 15)) * 0.28 * s, 0) * CFrame.Angles(0.14, 0, roll)
	elseif pose == "jump" then
		aL, aR = -2.7, -2.7
		rL, rR = -0.45, 0.45
		lL, lR = -0.9, -0.5
		bodyCF = rootCF * CFrame.Angles(0.05, 0, roll)
	elseif pose == "slide" then
		bodyCF = rootCF * CFrame.new(0, 0.3 * s, -0.4 * s) * CFrame.Angles(-1.2, 0, roll)
		lL, lR = -0.35, -0.2
		aL, aR = 0.9, 0.9
		rL, rR = -0.5, 0.5
		headTilt = 0.5
	elseif pose == "hide" then
		-- the iconic "covering my face" Smiski pose
		aL, aR = -2.25, -2.25
		rL, rR = 0.55, -0.55
		headTilt = 0.18 + math.sin(t * 2) * 0.03
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 2) * 0.04 * s, 0)
	elseif pose == "flail" then
		aL = -2.6 + math.sin(t * 22) * 0.6
		aR = -2.6 - math.sin(t * 22) * 0.6
		rL, rR = -0.6, 0.6
		lL, lR = math.sin(t * 18) * 0.8, -math.sin(t * 18) * 0.8
	elseif pose == "cheer" then
		aL = -2.9 + math.sin(t * 6) * 0.25
		aR = -2.9 - math.sin(t * 6) * 0.25
		rL, rR = -0.5, 0.5
		bodyCF = rootCF * CFrame.new(0, math.abs(math.sin(t * 6)) * 0.3 * s, 0)
	elseif pose == "sit" then
		bodyCF = rootCF * CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(-0.12, 0, 0)
		lL, lR = -1.5, -1.5
		aL, aR = -0.5, -0.5
		rL, rR = 0.35, -0.35
		headTilt = 0.1
	elseif pose == "hug" then
		-- hugging knees
		bodyCF = rootCF * CFrame.new(0, -0.35 * s, 0) * CFrame.Angles(0.15, 0, 0)
		lL, lR = -2.1, -2.1
		aL, aR = -1.3, -1.3
		rL, rR = 0.7, -0.7
		headTilt = 0.3
	else -- idle
		aL, aR = math.sin(t * 2) * 0.05, -math.sin(t * 2) * 0.05
		bodyCF = rootCF * CFrame.new(0, math.sin(t * 2) * 0.05 * s, 0)
	end

	local function limb(p, pivot, ax, az, off)
		p.CFrame = bodyCF * CFrame.new(pivot * s) * CFrame.Angles(ax, 0, az) * CFrame.new(0, off * s, 0)
	end
	rig.body.CFrame = bodyCF * CFrame.new(0, 1.45 * s, 0)
	rig.head.CFrame = bodyCF * CFrame.new(0, 2.25 * s, 0) * CFrame.Angles(headTilt, 0, 0) * CFrame.new(0, 0.72 * s, 0)
	limb(rig.armL, Vector3.new(-0.78, 2.0, 0), aL, rL, -0.45)
	limb(rig.armR, Vector3.new(0.78, 2.0, 0), aR, rR, -0.45)
	limb(rig.legL, Vector3.new(-0.42, 0.9, 0), lL, 0, -0.42)
	limb(rig.legR, Vector3.new(0.42, 0.9, 0), lR, 0, -0.42)
end

---------------------------------------------------------------------------
-- GIANT KID RIG
---------------------------------------------------------------------------
local KID_SKIN = Color3.fromRGB(255, 208, 172)
local KID_SHIRT = Color3.fromRGB(235, 85, 85)
local KID_STRIPE = Color3.fromRGB(255, 245, 235)
local KID_JEANS = Color3.fromRGB(70, 105, 170)
local KID_HAIR = Color3.fromRGB(95, 62, 40)

local function buildKid(parent)
	local m = Instance.new("Model")
	m.Name = "GiantKid"
	local kid = { model = m, entries = {} }
	local SPH = Enum.MeshType.Sphere
	local function add(joint, size, off, color, mesh, mat)
		local p = part(m, size, CFrame.new(), color, mat or SM, mesh and { mesh = mesh } or nil)
		table.insert(kid.entries, { p = p, joint = joint, off = off })
		return p
	end
	-- legs (joint at hip)
	for _, side in { "L", "R" } do
		local j = "leg" .. side
		add(j, Vector3.new(3.9, 12.5, 3.9), CFrame.new(0, -6, 0), KID_JEANS)
		add(j, Vector3.new(4.4, 2.6, 6.8), CFrame.new(0, -12.6, 1.1), Color3.fromRGB(245, 245, 245))
		add(j, Vector3.new(4.5, 0.8, 6.9), CFrame.new(0, -13.6, 1.1), Color3.fromRGB(235, 80, 80))
	end
	-- torso (joint at root/feet, already leaning)
	add("torso", Vector3.new(12, 11.5, 6.8), CFrame.new(0, 19.6, 0), KID_SHIRT)
	add("torso", Vector3.new(12.15, 1.6, 6.95), CFrame.new(0, 17.6, 0), KID_STRIPE)
	add("torso", Vector3.new(12.15, 1.6, 6.95), CFrame.new(0, 21.6, 0), KID_STRIPE)
	add("torso", Vector3.new(12.4, 2.2, 7.1), CFrame.new(0, 14.4, 0), KID_JEANS)
	-- head (joint at neck)
	add("head", Vector3.new(3.2, 2, 3.2), CFrame.new(0, 0.6, 0), KID_SKIN)
	add("head", Vector3.new(10.4, 10.2, 9.6), CFrame.new(0, 6, 0), KID_SKIN, SPH)
	add("head", Vector3.new(11, 6.4, 10.2), CFrame.new(0, 9.4, -0.7), KID_HAIR, SPH)
	add("head", Vector3.new(7.5, 2.6, 3), CFrame.new(0.8, 10, 3.6) * CFrame.Angles(0.5, 0, 0.15), KID_HAIR, SPH)
	add("head", Vector3.new(1.4, 1.9, 1), CFrame.new(-2.1, 7, 4.1), Color3.fromRGB(30, 25, 30), SPH)
	add("head", Vector3.new(1.4, 1.9, 1), CFrame.new(2.1, 7, 4.1), Color3.fromRGB(30, 25, 30), SPH)
	add("head", Vector3.new(0.5, 0.5, 0.3), CFrame.new(-1.8, 7.5, 4.6), Color3.fromRGB(255, 255, 255), SPH)
	add("head", Vector3.new(0.5, 0.5, 0.3), CFrame.new(2.4, 7.5, 4.6), Color3.fromRGB(255, 255, 255), SPH)
	add("head", Vector3.new(3.8, 2.0, 0.9), CFrame.new(0, 3.9, 4.15), Color3.fromRGB(150, 40, 50), SPH)
	add("head", Vector3.new(2.2, 0.6, 0.5), CFrame.new(0, 4.5, 4.45), Color3.fromRGB(255, 255, 255), SPH)
	add("head", Vector3.new(1.8, 1.1, 0.5), CFrame.new(-3.4, 5.2, 3.4), Color3.fromRGB(255, 150, 150), SPH)
	add("head", Vector3.new(1.8, 1.1, 0.5), CFrame.new(3.4, 5.2, 3.4), Color3.fromRGB(255, 150, 150), SPH)
	add("head", Vector3.new(1.4, 2.6, 1.8), CFrame.new(-5.2, 6, 0), KID_SKIN, SPH)
	add("head", Vector3.new(1.4, 2.6, 1.8), CFrame.new(5.2, 6, 0), KID_SKIN, SPH)
	-- arms (joint at shoulder)
	for _, side in { "L", "R" } do
		local j = "arm" .. side
		add(j, Vector3.new(3.6, 4.5, 3.6), CFrame.new(0, -1.8, 0), KID_SHIRT)
		add(j, Vector3.new(3.0, 11, 3.0), CFrame.new(0, -6.5, 0), KID_SKIN)
		kid["hand" .. side] = add(j, Vector3.new(4.2, 4.6, 3.2), CFrame.new(0, -12.6, 0), KID_SKIN, SPH)
	end
	m.Parent = parent
	return kid
end

-- run: 0..1 running intensity, reach: 0..1 grabbing intensity
local function poseKid(kid, rootCF, t, run, reach)
	local ph = t * 7.5
	local sw = math.sin(ph) * 0.6 * run
	local bob = math.abs(math.cos(ph)) * 1.3 * run
	local lean = 0.1 + 0.28 * reach
	local torso = rootCF * CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, math.sin(ph) * 0.04 * run)
	local grab = math.sin(t * 9) * 0.3 * reach
	local armIdle = -0.15 + math.sin(t * 1.7) * 0.05
	local joints = {
		torso = torso,
		legL = torso * CFrame.new(-2.9, 14.5, 0) * CFrame.Angles(-lean - sw, 0, 0),
		legR = torso * CFrame.new(2.9, 14.5, 0) * CFrame.Angles(-lean + sw, 0, 0),
		head = torso * CFrame.new(0, 25.2, 0) * CFrame.Angles(-lean * 0.7 + math.sin(t * 3) * 0.04, math.sin(t * 1.3) * 0.08, 0),
		armL = torso * CFrame.new(-7.6, 24, 0)
			* CFrame.Angles(lerp(sw * 0.9 + armIdle, -1.55 + grab, reach), 0, lerp(-0.12, 0.22, reach)),
		armR = torso * CFrame.new(7.6, 24, 0)
			* CFrame.Angles(lerp(-sw * 0.9 + armIdle, -1.55 - grab, reach), 0, lerp(0.12, -0.22, reach)),
	}
	for _, e in kid.entries do
		e.p.CFrame = joints[e.joint] * e.off
	end
end

---------------------------------------------------------------------------
-- DECOR BUILDERS
---------------------------------------------------------------------------
local function letterFace(p, text, color)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 1
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Parent = sg
	sg.Parent = p
end

local function decorSmiski(parent, cf, scale, pose)
	local rig = buildSmiski(parent, scale, false)
	poseSmiski(rig, cf, pose, RNG:NextNumber(0, 10))
	return rig
end

local function flower(parent, pos, h)
	local petal = pick({ Color3.fromRGB(255, 130, 170), Color3.fromRGB(255, 220, 90), Color3.fromRGB(180, 140, 255), Color3.fromRGB(255, 255, 255) })
	part(parent, Vector3.new(h, 1.2, 1.2), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(80, 160, 70), SM, { shape = Enum.PartType.Cylinder })
	local top = pos + Vector3.new(0, h, 0)
	part(parent, Vector3.new(3, 3, 3), CFrame.new(top), Color3.fromRGB(255, 200, 60), SM, { shape = Enum.PartType.Ball })
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		part(parent, Vector3.new(3.4, 3.4, 1.4), CFrame.new(top) * CFrame.Angles(0, 0, a) * CFrame.new(0, 3, -0.2), petal, SM, { mesh = Enum.MeshType.Sphere })
	end
	part(parent, Vector3.new(5, 1, 2.2), CFrame.new(pos + Vector3.new(1.8, h * 0.45, 0)) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(90, 175, 80), SM, { mesh = Enum.MeshType.Sphere })
end

local function toyCar(parent, pos, yaw)
	local c = pick(TOY_COLORS)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part(parent, Vector3.new(6, 2.4, 11), cf * CFrame.new(0, 2.2, 0), c)
	part(parent, Vector3.new(5.2, 2.2, 5.5), cf * CFrame.new(0, 4.4, -0.5), c)
	part(parent, Vector3.new(5.3, 1.6, 5.6), cf * CFrame.new(0, 4.5, -0.5), Color3.fromRGB(160, 220, 255), Enum.Material.Glass, { transparency = 0.3 })
	for _, o in { Vector3.new(-3, 1.2, 3.4), Vector3.new(3, 1.2, 3.4), Vector3.new(-3, 1.2, -3.4), Vector3.new(3, 1.2, -3.4) } do
		part(parent, Vector3.new(1.2, 2.4, 2.4), cf * CFrame.new(o) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(40, 40, 45), SM, { shape = Enum.PartType.Cylinder })
	end
end

local function crayon(parent, pos, yaw)
	local c = pick(TOY_COLORS)
	local cf = CFrame.new(pos + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, yaw, 0)
	part(parent, Vector3.new(12, 1.8, 1.8), cf, c, SM, { shape = Enum.PartType.Cylinder })
	part(parent, Vector3.new(6, 1.9, 1.9), cf, Color3.fromRGB(250, 250, 240), SM, { shape = Enum.PartType.Cylinder })
	part(parent, Vector3.new(2.4, 1.4, 1.4), cf * CFrame.new(7, 0, 0), c, SM, { shape = Enum.PartType.Cylinder })
end

local function ball(parent, pos, r)
	local p = part(parent, Vector3.new(r, r, r), CFrame.new(pos + Vector3.new(0, r / 2, 0)) * CFrame.Angles(RNG:NextNumber(0, 6), RNG:NextNumber(0, 6), 0), pick(TOY_COLORS), SM, { shape = Enum.PartType.Ball })
	part(parent, Vector3.new(r * 1.01, r * 0.2, r * 1.01), p.CFrame, Color3.fromRGB(255, 255, 255), SM, { shape = Enum.PartType.Cylinder })
end

local function toyBlockDecor(parent, pos, size)
	local p = part(parent, Vector3.new(size, size, size), CFrame.new(pos + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, RNG:NextNumber(-0.5, 0.5), 0), pick(TOY_COLORS))
	letterFace(p, string.char(RNG:NextInteger(65, 90)))
end

-- random scattered toy on the floor, away from lanes
local function scatterToy(parent, side, z)
	local x = side * RNG:NextNumber(15, 27)
	local pos = Vector3.new(x, 0, z)
	local r = RNG:NextInteger(1, 6)
	if r == 1 then
		toyCar(parent, pos, RNG:NextNumber(-0.6, 0.6))
	elseif r == 2 then
		crayon(parent, pos, RNG:NextNumber(0, math.pi))
	elseif r == 3 then
		ball(parent, pos, RNG:NextNumber(4, 7))
	elseif r == 4 then
		toyBlockDecor(parent, pos, RNG:NextNumber(3.5, 5))
	else
		decorSmiski(parent, CFrame.new(pos) * CFrame.Angles(0, side > 0 and -2.2 or 2.2, 0), RNG:NextNumber(1, 1.6), pick({ "sit", "hug", "cheer", "hide" }))
	end
end

local function sideWall(parent, z0, color, withWainscot)
	for _, side in { -1, 1 } do
		part(parent, Vector3.new(2, 150, SEG_LEN), CFrame.new(side * 37, 75, z0 + SEG_LEN / 2), color, SM, { noShadow = true })
		part(parent, Vector3.new(1.6, 6, SEG_LEN), CFrame.new(side * 35.6, 3, z0 + SEG_LEN / 2), Color3.fromRGB(250, 248, 240))
		if withWainscot then
			part(parent, Vector3.new(0.8, 30, SEG_LEN), CFrame.new(side * 35.8, 15, z0 + SEG_LEN / 2), Color3.fromRGB(245, 242, 232))
			part(parent, Vector3.new(1.8, 1.4, SEG_LEN), CFrame.new(side * 35.5, 30.5, z0 + SEG_LEN / 2), Color3.fromRGB(255, 255, 250))
		end
	end
end

local function wallWindow(parent, side, z)
	local x = side * 35.8
	part(parent, Vector3.new(1.2, 44, 34), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
	part(parent, Vector3.new(1.4, 38, 28), CFrame.new(x, 68, z), Color3.fromRGB(170, 215, 255), Enum.Material.Neon, { noShadow = true })
	part(parent, Vector3.new(1.6, 38, 1.2), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
	part(parent, Vector3.new(1.6, 1.2, 28), CFrame.new(x, 68, z), Color3.fromRGB(255, 255, 255))
	part(parent, Vector3.new(4, 1.5, 38), CFrame.new(x - side * 1.5, 46, z), Color3.fromRGB(255, 255, 255))
end

local function pictureFrame(parent, side, z)
	local x = side * 35.6
	local w, h = RNG:NextNumber(18, 30), RNG:NextNumber(20, 30)
	part(parent, Vector3.new(1.2, h, w), CFrame.new(x, 62, z), Color3.fromRGB(120, 80, 50))
	part(parent, Vector3.new(1.4, h - 3, w - 3), CFrame.new(x, 62, z), pick(TOY_COLORS):Lerp(Color3.new(1, 1, 1), 0.35))
	-- a little doodle "sun" in the picture
	part(parent, Vector3.new(1.6, 5, 5), CFrame.new(x, 66, z + w / 5), Color3.fromRGB(255, 220, 80), SM, { shape = Enum.PartType.Cylinder })
	part(parent, Vector3.new(1.5, h / 3, w - 3), CFrame.new(x, 62 - h / 3, z), Color3.fromRGB(120, 200, 110))
end

local function doorOnWall(parent, side, z)
	local x = side * 35.4
	part(parent, Vector3.new(1.5, 92, 44), CFrame.new(x, 46, z), Color3.fromRGB(255, 255, 255))
	part(parent, Vector3.new(1.8, 88, 38), CFrame.new(x, 44, z), Color3.fromRGB(215, 185, 150), Enum.Material.Wood)
	part(parent, Vector3.new(3.5, 3.5, 3.5), CFrame.new(x - side * 1.2, 42, z - 14), Color3.fromRGB(230, 200, 90), Enum.Material.Metal, { shape = Enum.PartType.Ball, reflect = 0.2 })
end

---------------------------------------------------------------------------
-- ZONES
---------------------------------------------------------------------------
local ZONES = {}

ZONES.Hallway = function(model, z0)
	local woods = { Color3.fromRGB(176, 118, 72), Color3.fromRGB(163, 108, 66), Color3.fromRGB(186, 128, 80), Color3.fromRGB(154, 100, 60) }
	for i = 0, 13 do
		local x = -35 + 2.5 + i * 5
		local cut = RNG:NextNumber(18, SEG_LEN - 18)
		part(model, Vector3.new(5, 2, cut - 0.3), CFrame.new(x, -1, z0 + cut / 2), pick(woods), Enum.Material.Wood, { walk = true })
		part(model, Vector3.new(5, 2, SEG_LEN - cut - 0.3), CFrame.new(x, -1, z0 + cut + (SEG_LEN - cut) / 2), pick(woods), Enum.Material.Wood, { walk = true })
	end
	part(model, Vector3.new(70, 1.8, SEG_LEN), CFrame.new(0, -1.1, z0 + SEG_LEN / 2), Color3.fromRGB(80, 50, 30), SM, { walk = true })
	sideWall(model, z0, Color3.fromRGB(246, 232, 205), true)
	for _, side in { -1, 1 } do
		local r = RNG:NextNumber()
		if r < 0.35 then
			pictureFrame(model, side, z0 + RNG:NextNumber(20, 60))
		elseif r < 0.6 then
			doorOnWall(model, side, z0 + 40)
		elseif r < 0.8 then
			wallWindow(model, side, z0 + 40)
		end
		-- power outlet on the baseboard
		if RNG:NextNumber() < 0.4 then
			local z = z0 + RNG:NextNumber(10, 70)
			part(model, Vector3.new(0.6, 7, 4.5), CFrame.new(side * 35.4, 14, z), Color3.fromRGB(252, 252, 248))
			part(model, Vector3.new(0.7, 1.4, 0.5), CFrame.new(side * 35.3, 15.5, z - 0.9), Color3.fromRGB(60, 60, 60))
			part(model, Vector3.new(0.7, 1.4, 0.5), CFrame.new(side * 35.3, 15.5, z + 0.9), Color3.fromRGB(60, 60, 60))
		end
		if RNG:NextNumber() < 0.7 then scatterToy(model, side, z0 + RNG:NextNumber(10, 70)) end
	end
end

ZONES.Kitchen = function(model, z0)
	local a, b = Color3.fromRGB(250, 250, 245), Color3.fromRGB(150, 200, 225)
	for ix = 0, 6 do
		for iz = 0, 7 do
			part(model, Vector3.new(10, 2, 10), CFrame.new(-30 + ix * 10, -1, z0 + 5 + iz * 10), (ix + iz) % 2 == 0 and a or b, SM, { walk = true, reflect = 0.04 })
		end
	end
	local cab = Color3.fromRGB(245, 240, 225)
	for _, side in { -1, 1 } do
		-- back wall with backsplash
		part(model, Vector3.new(2, 150, SEG_LEN), CFrame.new(side * 45, 75, z0 + SEG_LEN / 2), Color3.fromRGB(255, 244, 215), SM, { noShadow = true })
		part(model, Vector3.new(0.6, 24, SEG_LEN), CFrame.new(side * 43.8, 48, z0 + SEG_LEN / 2), Color3.fromRGB(200, 230, 225))
		-- lower cabinets
		part(model, Vector3.new(16, 34, SEG_LEN), CFrame.new(side * 36, 17, z0 + SEG_LEN / 2), cab)
		part(model, Vector3.new(15, 3, SEG_LEN), CFrame.new(side * 36.5, 1.5, z0 + SEG_LEN / 2), Color3.fromRGB(90, 80, 70))
		part(model, Vector3.new(19, 2.6, SEG_LEN), CFrame.new(side * 35.5, 35.3, z0 + SEG_LEN / 2), Color3.fromRGB(130, 130, 140), Enum.Material.Granite)
		for i = 0, 3 do
			local z = z0 + 10 + i * 20
			part(model, Vector3.new(0.6, 26, 17), CFrame.new(side * 27.8, 18.5, z), Color3.fromRGB(235, 228, 210))
			part(model, Vector3.new(1.2, 1.2, 5), CFrame.new(side * 27.2, 27, z), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
		end
		-- upper cabinets
		part(model, Vector3.new(12, 30, SEG_LEN), CFrame.new(side * 38.5, 78, z0 + SEG_LEN / 2), cab)
		-- stuff on the counter
		local r = RNG:NextNumber()
		local z = z0 + RNG:NextNumber(15, 65)
		if r < 0.3 then
			-- cereal box
			local c = pick(TOY_COLORS)
			local box = part(model, Vector3.new(6, 22, 15), CFrame.new(side * 35, 47.6, z), c)
			letterFace(box, "YUM", Color3.new(1, 1, 1))
		elseif r < 0.55 then
			-- mug
			part(model, Vector3.new(9, 8, 8), CFrame.new(side * 34, 41, z) * CFrame.Angles(0, 0, math.pi / 2), pick(TOY_COLORS), SM, { shape = Enum.PartType.Cylinder })
		elseif r < 0.85 then
			decorSmiski(model, CFrame.new(side * 32, 36.6, z) * CFrame.Angles(0, side > 0 and -1.9 or 1.9, 0), 1.8, pick({ "sit", "hug", "cheer" }))
		end
		-- dropped cereal on the floor
		for _ = 1, RNG:NextInteger(0, 3) do
			part(model, Vector3.new(0.8, 2.4, 2.4), CFrame.new(side * RNG:NextNumber(13, 26), 0.4, z0 + RNG:NextNumber(5, 75)) * CFrame.Angles(0, RNG:NextNumber(0, 3), math.pi / 2), Color3.fromRGB(230, 170, 80), SM, { shape = Enum.PartType.Cylinder })
		end
	end
	if RNG:NextNumber() < 0.35 then
		-- milk puddle beside the track
		part(model, Vector3.new(0.12, 10, 16), CFrame.new(pick({ -1, 1 }) * 18, 0.05, z0 + 40) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 255, 255), SM, { shape = Enum.PartType.Cylinder, noShadow = true, reflect = 0.15 })
	end
end

ZONES.LivingRoom = function(model, z0)
	part(model, Vector3.new(90, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(214, 198, 170), Enum.Material.Fabric, { walk = true })
	-- rug under the lanes
	part(model, Vector3.new(30, 0.12, SEG_LEN), CFrame.new(0, 0.04, z0 + SEG_LEN / 2), Color3.fromRGB(190, 80, 80), Enum.Material.Fabric, { noShadow = true })
	part(model, Vector3.new(25, 0.14, SEG_LEN), CFrame.new(0, 0.05, z0 + SEG_LEN / 2), Color3.fromRGB(240, 220, 180), Enum.Material.Fabric, { noShadow = true })
	for i = 0, 3 do
		part(model, Vector3.new(25, 0.16, 3), CFrame.new(0, 0.06, z0 + 10 + i * 20), Color3.fromRGB(80, 130, 180), Enum.Material.Fabric, { noShadow = true })
	end
	sideWall(model, z0, Color3.fromRGB(176, 200, 170), false)
	for _, side in { -1, 1 } do
		local r = RNG:NextNumber()
		if r < 0.45 then
			-- giant couch
			local c = pick({ Color3.fromRGB(90, 140, 190), Color3.fromRGB(230, 150, 90), Color3.fromRGB(150, 120, 200) })
			local x = side * 27
			local zc = z0 + SEG_LEN / 2
			part(model, Vector3.new(16, 12, 64), CFrame.new(x, 8, zc), c, Enum.Material.Fabric)
			part(model, Vector3.new(5, 30, 64), CFrame.new(x + side * 6, 17, zc), c, Enum.Material.Fabric)
			for k = -1, 1 do
				part(model, Vector3.new(12, 4.5, 20), CFrame.new(x - side * 1.5, 16, zc + k * 20.6), c:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Fabric)
			end
			part(model, Vector3.new(16, 20, 5), CFrame.new(x, 12, zc - 34), c, Enum.Material.Fabric)
			part(model, Vector3.new(16, 20, 5), CFrame.new(x, 12, zc + 34), c, Enum.Material.Fabric)
			for _, zz in { zc - 30, zc + 30 } do
				part(model, Vector3.new(2, 2, 2), CFrame.new(x - side * 6, 1, zz), Color3.fromRGB(80, 55, 35))
			end
			decorSmiski(model, CFrame.new(x - side * 1.5, 18.3, zc + RNG:NextNumber(-20, 20)) * CFrame.Angles(0, side > 0 and -1.7 or 1.7, 0), 2, pick({ "sit", "hug", "hide" }))
		elseif r < 0.7 then
			-- floor lamp
			local x, z = side * 26, z0 + RNG:NextNumber(20, 60)
			part(model, Vector3.new(1.4, 12, 12), CFrame.new(x, 0.7, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 60, 60), SM, { shape = Enum.PartType.Cylinder })
			part(model, Vector3.new(70, 1.4, 1.4), CFrame.new(x, 35, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 60, 60), SM, { shape = Enum.PartType.Cylinder })
			local shade = part(model, Vector3.new(14, 18, 18), CFrame.new(x, 70, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 240, 210), Enum.Material.Fabric, { shape = Enum.PartType.Cylinder })
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 220, 170)
			l.Range = 40
			l.Brightness = 1.2
			l.Parent = shade
		else
			wallWindow(model, side, z0 + 40)
			if RNG:NextNumber() < 0.6 then scatterToy(model, side, z0 + RNG:NextNumber(10, 70)) end
		end
	end
end

ZONES.Backyard = function(model, z0)
	part(model, Vector3.new(200, 2, SEG_LEN), CFrame.new(0, -1, z0 + SEG_LEN / 2), Color3.fromRGB(110, 180, 80), Enum.Material.Grass, { walk = true })
	-- stepping stone path under the lanes
	for i = 0, 3 do
		part(model, Vector3.new(24, 0.3, 17), CFrame.new(RNG:NextNumber(-0.8, 0.8), 0.05, z0 + 10 + i * 20) * CFrame.Angles(0, RNG:NextNumber(-0.05, 0.05), 0), Color3.fromRGB(185, 180, 170), Enum.Material.Slate, { noShadow = true })
	end
	for _, side in { -1, 1 } do
		-- white picket fence
		for i = 0, 15 do
			part(model, Vector3.new(1, 32, 3.6), CFrame.new(side * 40, 16, z0 + 2.5 + i * 5), Color3.fromRGB(252, 252, 248))
			part(model, Vector3.new(1, 2.6, 2.6), CFrame.new(side * 40, 32.2, z0 + 2.5 + i * 5) * CFrame.Angles(math.rad(45), 0, 0), Color3.fromRGB(252, 252, 248))
		end
		part(model, Vector3.new(1.2, 2, SEG_LEN), CFrame.new(side * 39.2, 10, z0 + SEG_LEN / 2), Color3.fromRGB(240, 240, 235))
		part(model, Vector3.new(1.2, 2, SEG_LEN), CFrame.new(side * 39.2, 24, z0 + SEG_LEN / 2), Color3.fromRGB(240, 240, 235))
		-- giant flowers + grass tufts
		for _ = 1, RNG:NextInteger(1, 2) do
			flower(model, Vector3.new(side * RNG:NextNumber(18, 34), 0, z0 + RNG:NextNumber(5, 75)), RNG:NextNumber(12, 26))
		end
		for _ = 1, 3 do
			local pos = Vector3.new(side * RNG:NextNumber(13, 36), 0, z0 + RNG:NextNumber(0, 80))
			for k = 1, 3 do
				part(model, Vector3.new(0.8, RNG:NextNumber(3, 6), 1.6), CFrame.new(pos) * CFrame.Angles(0, k * 2, (k - 2) * 0.35) * CFrame.new(0, 2, 0), Color3.fromRGB(90, 165, 70), SM, { mesh = Enum.MeshType.Sphere, noShadow = true })
			end
		end
		-- trees beyond the fence
		if RNG:NextNumber() < 0.6 then
			local x, z = side * RNG:NextNumber(60, 90), z0 + RNG:NextNumber(10, 70)
			part(model, Vector3.new(60, 9, 9), CFrame.new(x, 30, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 85, 55), Enum.Material.Wood, { shape = Enum.PartType.Cylinder })
			for k = 1, 4 do
				part(model, Vector3.new(34, 30, 34) * RNG:NextNumber(0.8, 1.2), CFrame.new(x + RNG:NextNumber(-10, 10), 64 + RNG:NextNumber(-6, 10), z + RNG:NextNumber(-10, 10)), Color3.fromRGB(95, 170, 85):Lerp(Color3.fromRGB(140, 200, 100), k / 5), Enum.Material.Grass, { mesh = Enum.MeshType.Sphere })
			end
		end
		if RNG:NextNumber() < 0.45 then
			local z = z0 + RNG:NextNumber(10, 70)
			if RNG:NextNumber() < 0.5 then
				ball(model, Vector3.new(side * RNG:NextNumber(18, 30), 0, z), RNG:NextNumber(7, 11))
			else
				decorSmiski(model, CFrame.new(side * RNG:NextNumber(16, 26), 0, z) * CFrame.Angles(0, side > 0 and -2.3 or 2.3, 0), RNG:NextNumber(1.2, 1.8), pick({ "cheer", "sit", "hide" }))
			end
		end
	end
end

local ZONE_ORDER = { "Hallway", "Kitchen", "LivingRoom", "Backyard" }

local function doorway(model, z)
	local wallC = Color3.fromRGB(250, 240, 222)
	for _, side in { -1, 1 } do
		part(model, Vector3.new(40, 150, 3), CFrame.new(side * 36, 75, z), wallC)
		part(model, Vector3.new(4, 60, 4.5), CFrame.new(side * 17, 30, z), Color3.fromRGB(255, 255, 255))
	end
	part(model, Vector3.new(38, 90, 3), CFrame.new(0, 105, z), wallC)
	part(model, Vector3.new(38, 4, 4.5), CFrame.new(0, 60, z), Color3.fromRGB(255, 255, 255))
end

---------------------------------------------------------------------------
-- OBSTACLES
---------------------------------------------------------------------------
local OBS = {}

-- ABC toy block: jump over it
OBS.block = function(model, x, z)
	local d = 4.2
	local p = part(model, Vector3.new(4.8, 4.2, d), CFrame.new(x, 2.1, z + d / 2), pick(TOY_COLORS), SM, { obs = true })
	letterFace(p, string.char(RNG:NextInteger(65, 90)))
	return d
end

-- giant pencil resting on two erasers: slide under it (or jump it)
OBS.bar = function(model, x, z)
	local y = 3.4
	local p = part(model, Vector3.new(6.6, 1.5, 1.5), CFrame.new(x, y, z + 0.75), Color3.fromRGB(255, 200, 50), SM, { shape = Enum.PartType.Cylinder, obs = true })
	part(model, Vector3.new(1.4, 1.52, 1.52), p.CFrame * CFrame.new(3.8, 0, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
	part(model, Vector3.new(1.4, 1.5, 1.5), p.CFrame * CFrame.new(5.1, 0, 0), Color3.fromRGB(255, 150, 170), SM, { shape = Enum.PartType.Cylinder })
	part(model, Vector3.new(1.8, 1.1, 1.1), p.CFrame * CFrame.new(-4.1, 0, 0), Color3.fromRGB(245, 220, 170), SM, { shape = Enum.PartType.Cylinder })
	part(model, Vector3.new(0.8, 0.6, 0.6), p.CFrame * CFrame.new(-5.2, 0, 0), Color3.fromRGB(50, 50, 50), SM, { shape = Enum.PartType.Cylinder })
	for _, s in { -1, 1 } do
		part(model, Vector3.new(1.1, y - 0.7, 2.2), CFrame.new(x + s * 3.3, (y - 0.7) / 2, z + 0.75), Color3.fromRGB(255, 150, 170), SM, { obs = true })
	end
	-- stripes on the ground to warn you
	part(model, Vector3.new(6, 0.08, 1), CFrame.new(x, 0.1, z - 3), Color3.fromRGB(255, 200, 50), SM, { noShadow = true })
	return 1.5
end

-- tall stack of books: switch lanes
OBS.wall = function(model, x, z)
	local y = 0
	local d = 5
	local n = RNG:NextInteger(4, 6)
	for i = 1, n do
		local h = RNG:NextNumber(2, 2.8)
		local c = pick(TOY_COLORS):Lerp(Color3.fromRGB(80, 60, 60), 0.25)
		local cf = CFrame.new(x + RNG:NextNumber(-0.4, 0.4), y + h / 2, z + d / 2) * CFrame.Angles(0, RNG:NextNumber(-0.12, 0.12), 0)
		part(model, Vector3.new(6.4, h, d), cf, c, SM, { obs = true })
		part(model, Vector3.new(6.2, h * 0.8, 0.1), cf * CFrame.new(0, 0, -d / 2 - 0.02), Color3.fromRGB(250, 245, 225), SM, { noShadow = true })
		if i == n and RNG:NextNumber() < 0.4 then
			-- a tiny Smiski sitting on top of the books
			decorSmiski(model, cf * CFrame.new(0, h / 2, 0), 1, "sit")
		end
		y += h
	end
	return d
end

-- wooden toy train car: switch lanes, or run up the ramp and ride the roof
OBS.train = function(model, x, z, withRamp)
	local len = 26
	local c = pick(TOY_COLORS)
	local startZ = z
	if withRamp then
		local ramp = part(model, Vector3.new(5.8, 5.8, 13), CFrame.new(x, 2.9, z + 6.5), Color3.fromRGB(215, 175, 120), Enum.Material.Wood, { class = "WedgePart", walk = true })
		ramp.Name = "Ramp"
		startZ = z + 13.5
	end
	local zc = startZ + len / 2
	part(model, Vector3.new(6.2, 5, len), CFrame.new(x, 2.7, zc), c, SM, { obs = true })
	part(model, Vector3.new(6.8, 0.6, len + 1), CFrame.new(x, 5.5, zc), c:Lerp(Color3.new(1, 1, 1), 0.3), SM, { obs = true })
	for i = 0, 3 do
		for _, s in { -1, 1 } do
			part(model, Vector3.new(0.3, 2, 3.5), CFrame.new(x + s * 3.12, 3.4, startZ + 4 + i * 6), Color3.fromRGB(170, 220, 255), Enum.Material.Neon, { noShadow = true })
			part(model, Vector3.new(0.7, 2.2, 2.2), CFrame.new(x + s * 3.2, 1.1, startZ + 3 + i * 6.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 50, 50), SM, { shape = Enum.PartType.Cylinder })
		end
	end
	-- face on the front of the train
	part(model, Vector3.new(5.6, 4.2, 0.2), CFrame.new(x, 2.9, startZ - 0.05), Color3.fromRGB(255, 250, 235), SM, { noShadow = true })
	part(model, Vector3.new(0.3, 0.7, 0.7), CFrame.new(x - 1.2, 3.5, startZ - 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 30), SM, { shape = Enum.PartType.Cylinder })
	part(model, Vector3.new(0.3, 0.7, 0.7), CFrame.new(x + 1.2, 3.5, startZ - 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 30), SM, { shape = Enum.PartType.Cylinder })
	part(model, Vector3.new(1.8, 0.4, 0.2), CFrame.new(x, 2.3, startZ - 0.2), Color3.fromRGB(200, 70, 80), SM, { noShadow = true })
	return (startZ - z) + len, startZ
end

---------------------------------------------------------------------------
-- SEGMENTS
---------------------------------------------------------------------------
local segments = {}
local nextZ = 0
local segCount = 0
local zoneIdx = 1
local zoneLeft = 6
local safeLane = 2
local speed = START_SPEED

local function makeStar(parent, pos)
	local a = part(parent, Vector3.new(1.5, 1.5, 0.4), CFrame.new(pos), STAR_COLOR, Enum.Material.Neon, { noShadow = true })
	local b = part(parent, Vector3.new(1.5, 1.5, 0.4), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(45)), STAR_COLOR, Enum.Material.Neon, { noShadow = true })
	return { a = a, b = b, pos = pos, alive = true }
end

local function starHeight(occ, z)
	for _, o in occ do
		if o.kind == "block" and z > o.a - 6 and z < o.b + 6 then
			return 6.5
		elseif o.kind == "bar" and z > o.a - 1.5 and z < o.b + 1.5 then
			return 1.1
		elseif o.kind == "wall" and z > o.a - 16 and z < o.b + 2 then
			return nil
		elseif o.kind == "ramp" and z >= o.a and z <= o.b then
			return 1.6 + (z - o.a) / (o.b - o.a) * 5.8
		elseif o.kind == "train" and z >= o.a - 0.5 and z <= o.b then
			return o.ramp and 7.4 or nil
		elseif o.kind == "train" and not o.ramp and z > o.a - 16 and z < o.a then
			return nil
		end
	end
	return 1.6
end

local function genObstacles(seg, model, z0)
	local diff = math.clamp((speed - START_SPEED) / (MAX_SPEED - START_SPEED), 0, 1)
	-- the "safe" lane only ever gets jumpable/slidable obstacles
	safeLane = math.clamp(safeLane + RNG:NextInteger(-1, 1), 1, 3)
	local occ = { {}, {}, {} }
	local zEnd = z0 + SEG_LEN - 8
	for l = 1, 3 do
		local x = LANES[l]
		local z = z0 + 16 + RNG:NextNumber(0, 10)
		while z < zEnd do
			local r = RNG:NextNumber()
			local kind
			if l == safeLane then
				kind = r < 0.35 and "block" or r < 0.65 and "bar" or "none"
			else
				kind = r < 0.22 and "block" or r < 0.38 and "bar" or r < 0.62 and "wall" or r < 0.85 and "train" or "none"
			end
			if kind == "train" and z + 42 > z0 + SEG_LEN - 2 then
				kind = "wall"
			end
			local len = 0
			if kind == "block" then
				len = OBS.block(model, x, z)
				table.insert(occ[l], { kind = "block", a = z, b = z + len })
			elseif kind == "bar" then
				len = OBS.bar(model, x, z)
				table.insert(occ[l], { kind = "bar", a = z, b = z + len })
			elseif kind == "wall" then
				len = OBS.wall(model, x, z)
				table.insert(occ[l], { kind = "wall", a = z, b = z + len })
			elseif kind == "train" then
				local withRamp = RNG:NextNumber() < 0.6
				local startZ
				len, startZ = OBS.train(model, x, z, withRamp)
				if withRamp then
					table.insert(occ[l], { kind = "ramp", a = z, b = startZ })
				end
				table.insert(occ[l], { kind = "train", a = startZ, b = z + len, ramp = withRamp })
			else
				len = 8
			end
			z += len + RNG:NextNumber(lerp(30, 18, diff), lerp(55, 30, diff))
		end
	end
	-- a trail of glow stars
	local sl = RNG:NextNumber() < 0.7 and safeLane or RNG:NextInteger(1, 3)
	local zs = z0 + RNG:NextNumber(4, 30)
	local ze = math.min(z0 + SEG_LEN - 2, zs + RNG:NextNumber(25, 60))
	for z = zs, ze, 5 do
		local h = starHeight(occ[sl], z)
		if h then
			table.insert(seg.stars, makeStar(model, Vector3.new(LANES[sl], h, z)))
		end
	end
end

local function genSegment()
	segCount += 1
	local z0 = nextZ
	local seg = { z0 = z0, stars = {} }
	local model = Instance.new("Model")
	model.Name = "Segment" .. segCount
	seg.model = model

	ZONES[ZONE_ORDER[zoneIdx]](model, z0)
	if segCount == 1 then
		doorway(model, z0)
	end
	zoneLeft -= 1
	if zoneLeft <= 0 then
		local newIdx = zoneIdx
		while newIdx == zoneIdx do
			newIdx = RNG:NextInteger(1, #ZONE_ORDER)
		end
		zoneIdx = newIdx
		zoneLeft = RNG:NextInteger(4, 7)
		doorway(model, z0 + SEG_LEN)
	end
	if z0 >= 80 then
		genObstacles(seg, model, z0)
	end
	model.Parent = world
	table.insert(segments, seg)
	nextZ += SEG_LEN
end

local function clearWorld()
	for _, s in segments do
		s.model:Destroy()
	end
	table.clear(segments)
	nextZ = -SEG_LEN * SEGS_BEHIND
	segCount = 0
	zoneIdx = 1
	zoneLeft = 6
	safeLane = 2
end

local function updateSegments(pz)
	while nextZ < pz + SEGS_AHEAD * SEG_LEN do
		genSegment()
	end
	while #segments > 0 and segments[1].z0 + SEG_LEN < pz - SEGS_BEHIND * SEG_LEN do
		local s = table.remove(segments, 1)
		s.model:Destroy()
	end
end

---------------------------------------------------------------------------
-- ACTORS
---------------------------------------------------------------------------
local smiski = buildSmiski(actors, 1, true)
local kid = buildKid(actors)

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SmiskiRunnerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player and player:WaitForChild("PlayerGui") or game:GetService("StarterGui")

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function rescale()
	local v = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(v.X / 1100, v.Y / 700), 0.55, 1.3)
end
rescale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

local DARK_GREEN = Color3.fromRGB(60, 95, 50)

local function txt(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		if k ~= "stroke" then l[k] = v end
	end
	local s = Instance.new("UIStroke")
	s.Thickness = props.stroke or 3
	s.Color = DARK_GREEN
	s.Parent = l
	l.Parent = parent
	return l
end

local function button(parent, text, pos, color)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = UDim2.fromOffset(280, 78)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 26)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = DARK_GREEN
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = b
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2.5
	ts.Color = DARK_GREEN
	ts.Parent = b
	b.Parent = parent
	return b
end

-- HUD
local hud = Instance.new("Frame")
hud.BackgroundTransparency = 1
hud.Size = UDim2.fromScale(1, 1)
hud.Visible = false
hud.Parent = gui
local scoreLabel = txt(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 20), Size = UDim2.fromOffset(300, 60), Text = "0", TextXAlignment = Enum.TextXAlignment.Right })
local starLabel = txt(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 84), Size = UDim2.fromOffset(240, 42), Text = "★ 0", TextColor3 = Color3.fromRGB(255, 240, 140), TextXAlignment = Enum.TextXAlignment.Right })
local bestHud = txt(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 130), Size = UDim2.fromOffset(240, 26), Text = "BEST 0", TextXAlignment = Enum.TextXAlignment.Right, stroke = 2 })
local dangerLabel = txt(hud, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(520, 52), Text = "THE KID IS RIGHT BEHIND YOU!", TextColor3 = Color3.fromRGB(255, 110, 100), Visible = false })

-- MENU
local menu = Instance.new("Frame")
menu.BackgroundTransparency = 1
menu.Size = UDim2.fromScale(1, 1)
menu.Parent = gui
txt(menu, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(760, 120), Text = "SMISKI ESCAPE", TextColor3 = Color3.fromRGB(215, 245, 175), stroke = 6 })
txt(menu, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), Size = UDim2.fromOffset(640, 38), Text = "run, little toy. don't get caught!", stroke = 3 })
local playBtn = button(menu, "PLAY", UDim2.new(0.5, 0, 1, -170), Color3.fromRGB(135, 200, 105))
local menuBest = txt(menu, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(400, 30), Text = "", stroke = 2 })
local controlsText = UIS.TouchEnabled and not UIS.KeyboardEnabled
	and "swipe left/right to dodge  •  swipe up to jump  •  swipe down to slide"
	or "A/D or ←/→ dodge  •  W/Space/↑ jump  •  S/↓ slide"
txt(menu, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(760, 30), Text = controlsText, stroke = 2 })

-- GAME OVER
local over = Instance.new("Frame")
over.AnchorPoint = Vector2.new(0.5, 0.5)
over.Position = UDim2.fromScale(0.5, 0.5)
over.Size = UDim2.fromOffset(440, 380)
over.BackgroundColor3 = Color3.fromRGB(255, 251, 238)
over.Visible = false
over.Parent = gui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 34)
	c.Parent = over
	local s = Instance.new("UIStroke")
	s.Thickness = 5
	s.Color = DARK_GREEN
	s.Parent = over
end
txt(over, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(360, 80), Text = "CAUGHT!", TextColor3 = Color3.fromRGB(255, 110, 100), stroke = 5 })
local overScore = txt(over, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.fromOffset(360, 56), Text = "0", TextColor3 = Color3.fromRGB(215, 245, 175), stroke = 4 })
local overStars = txt(over, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(360, 34), Text = "★ 0", TextColor3 = Color3.fromRGB(255, 225, 110), stroke = 3 })
local overBest = txt(over, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 212), Size = UDim2.fromOffset(360, 28), Text = "BEST 0", stroke = 2 })
local againBtn = button(over, "RUN AGAIN", UDim2.new(0.5, 0, 1, -62), Color3.fromRGB(135, 200, 105))

---------------------------------------------------------------------------
-- GAME STATE
---------------------------------------------------------------------------
local state = "menu"
local px, py, pz, vy = 0, 0, 0, 0
local lane, prevLane = 2, 2
local grounded = true
local slideTimer = 0
local stumbleTimer = 0
local hitCooldown = 0
local kidDist = KID_NEAR
local kidX = 0
local kidSide = 1
local distance = 0
local stars = 0
local best = 0
local t = 0
local overT = 0
local lastScore = 0
local camPos = Vector3.new(8, 6, 14)
local camLook = Vector3.new(0, 8, -6)
local shake = 0
local fastFall = false

local function score()
	return math.floor(distance / 2) + stars * 10
end

local function resetRun()
	clearWorld()
	px, py, pz, vy = 0, 0, 0, 0
	lane, prevLane = 2, 2
	grounded = true
	slideTimer, stumbleTimer, hitCooldown = 0, 0, 0
	kidDist = 22
	kidX = 0
	distance, stars = 0, 0
	speed = START_SPEED
	fastFall = false
	updateSegments(pz)
end

local function startRun()
	resetRun()
	state = "playing"
	menu.Visible = false
	over.Visible = false
	hud.Visible = true
	kidDist = 22
	stumbleTimer = 0
	play("swoosh", 0.8)
end

local function gameOver()
	if state ~= "playing" then return end
	state = "over"
	overT = 0
	lastScore = score()
	if lastScore > best then best = lastScore end
	hud.Visible = false
	play("hit", 1)
end

local function stumble()
	play("hit", 1.3)
	shake = 1
	hitCooldown = 0.5
	if stumbleTimer > 0 then
		gameOver()
	else
		stumbleTimer = STUMBLE_WINDOW
		-- the kid lunges in from whichever side has more room
		kidSide = px > 0.5 and -1 or px < -0.5 and 1 or (RNG:NextNumber() < 0.5 and -1 or 1)
	end
end

local function doAction(a)
	if state ~= "playing" then return end
	if a == "right" then
		if lane > 1 then
			prevLane = lane
			lane -= 1
			play("swoosh", 1.3)
		end
	elseif a == "left" then
		if lane < 3 then
			prevLane = lane
			lane += 1
			play("swoosh", 1.3)
		end
	elseif a == "jump" then
		if grounded then
			vy = JUMP_V
			grounded = false
			slideTimer = 0
			play("jump", 1.1)
		end
	elseif a == "slide" then
		slideTimer = SLIDE_TIME
		if not grounded then
			vy = math.min(vy, -JUMP_V * 1.2)
			fastFall = true
		end
		play("swoosh", 0.9)
	end
end

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local k = input.KeyCode
	if state == "menu" and (k == Enum.KeyCode.Space or k == Enum.KeyCode.Return) then
		startRun()
		return
	end
	if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
		doAction("left")
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
		doAction("right")
	elseif k == Enum.KeyCode.W or k == Enum.KeyCode.Up or k == Enum.KeyCode.Space then
		doAction("jump")
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down then
		doAction("slide")
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
	if d.Magnitude > 40 then
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

playBtn.Activated:Connect(startRun)
againBtn.Activated:Connect(startRun)

---------------------------------------------------------------------------
-- PHYSICS HELPERS
---------------------------------------------------------------------------
local function groundAt(x, y, z)
	local r = workspace:Raycast(Vector3.new(x, y + 2, z), Vector3.new(0, -60, 0), rayParams)
	if r then return r.Position.Y end
	return 0
end

local function hitObstacle(x, y, z, sliding)
	local h = sliding and 1.3 or 3.4
	local center = Vector3.new(x, y + 0.35 + h / 2, z)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(1.7, h, 1.2), overlapParams)
	for _, p in parts do
		if p:GetAttribute("Obs") then
			return p
		end
	end
	return nil
end

local function recenter()
	local d = Vector3.new(0, 0, RECENTER_AT)
	for _, inst in world:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CFrame -= d
		end
	end
	for _, s in segments do
		s.z0 -= RECENTER_AT
		for _, st in s.stars do
			st.pos -= d
		end
	end
	nextZ -= RECENTER_AT
	pz -= RECENTER_AT
	camPos -= d
	camLook -= d
end

---------------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------------
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 72
resetRun()

local function step(rawDt)
	local dt = math.min(rawDt, 1 / 20)
	t += dt
	camera.CameraType = Enum.CameraType.Scriptable

	local pose = "run"
	local kidRun, kidReach = 1, 0
	local wantCamPos, wantLook
	local roll = 0

	if state == "menu" then
		menuBest.Text = best > 0 and ("BEST " .. best) or ""
		pose = "hide"
		kidDist = 20
		kidRun, kidReach = 0, 0.55
		wantCamPos = Vector3.new(8, 3.5, pz + 17)
		wantLook = Vector3.new(0, 12, pz - 10)
	elseif state == "playing" then
		speed = math.min(MAX_SPEED, speed + ACCEL * dt)
		local dz = speed * dt
		pz += dz
		distance += dz

		-- lanes
		local tx = LANES[lane]
		px += (tx - px) * math.min(1, dt * LANE_LERP)
		roll = math.clamp((px - tx) * 0.09, -0.35, 0.35)

		-- vertical
		slideTimer = math.max(0, slideTimer - dt)
		local sliding = slideTimer > 0 and grounded or (slideTimer > 0 and fastFall)
		if grounded then vy = 0 end
		vy -= GRAVITY * dt
		py += vy * dt
		local g = groundAt(px, py, pz)
		if vy <= 0 and py <= g + (grounded and 1.6 or 0) then
			if not grounded then play("land", 1.2) end
			py = g
			vy = 0
			grounded = true
			fastFall = false
		else
			grounded = false
		end
		if py < -5 then py = 0 end

		-- collisions
		hitCooldown = math.max(0, hitCooldown - dt)
		if hitCooldown <= 0 then
			local hit = hitObstacle(px, py, pz, slideTimer > 0)
			if hit then
				if math.abs(px - tx) > 0.6 and prevLane ~= lane then
					lane = prevLane
					prevLane = lane
					stumble()
				else
					gameOver()
				end
			end
		end

		-- stars
		local center = Vector3.new(px, py + 1.6, pz)
		for _, s in segments do
			if s.z0 < pz + 250 and s.z0 + SEG_LEN > pz - 10 then
				for _, st in s.stars do
					if st.alive and (st.pos - center).Magnitude < 2.8 then
						st.alive = false
						stars += 1
						play("star", 1 + (stars % 5) * 0.05)
						for _, p in { st.a, st.b } do
							TweenService:Create(p, TweenInfo.new(0.25), { Size = p.Size * 2.2, Transparency = 1 }):Play()
						end
					end
				end
			end
		end

		-- kid chase
		stumbleTimer = math.max(0, stumbleTimer - dt)
		local targetDist = stumbleTimer > 0 and KID_NEAR or KID_FAR
		kidDist += (targetDist - kidDist) * math.min(1, dt * (stumbleTimer > 0 and 3 or 0.7))
		kidReach = stumbleTimer > 0 and 1 or 0.25
		dangerLabel.Visible = stumbleTimer > 0
		dangerLabel.TextTransparency = 0.25 + math.sin(t * 12) * 0.25

		if slideTimer > 0 and grounded then
			pose = "slide"
		elseif not grounded then
			pose = (slideTimer > 0) and "slide" or "jump"
		end

		local s = score()
		scoreLabel.Text = tostring(s)
		starLabel.Text = "★ " .. stars
		bestHud.Text = "BEST " .. math.max(best, s)

		local near = math.clamp(1 - (kidDist - KID_NEAR) / 20, 0, 1)
		shake = math.max(shake - dt * 2, near * 0.25 * math.abs(math.sin(t * 7.5)))
		wantCamPos = Vector3.new(px * 0.7, 7.5 + py * 0.6 + near * 1.5, pz - 13 - near * 1)
		wantLook = Vector3.new(px * 0.85, 2.5 + py * 0.5, pz + 14)
		if pz > RECENTER_AT then
			recenter()
			wantCamPos -= Vector3.new(0, 0, RECENTER_AT)
			wantLook -= Vector3.new(0, 0, RECENTER_AT)
		end
	elseif state == "over" then
		overT += dt
		kidDist += (7 - kidDist) * math.min(1, dt * 4)
		kidRun, kidReach = 0.2, 1
		pose = "flail"
		dangerLabel.Visible = false
		wantCamPos = Vector3.new(px * 0.5 + 16, 12, pz + 34)
		wantLook = Vector3.new(px * 0.7, 17, pz - 6)
		if overT > 1.3 and not over.Visible then
			over.Visible = true
			overScore.Text = tostring(lastScore)
			overStars.Text = "★ " .. stars
			overBest.Text = "BEST " .. best
		end
	end

	updateSegments(pz)

	-- spin stars
	local spin = t * 3
	for _, s in segments do
		if s.z0 < pz + 300 and s.z0 + SEG_LEN > pz - 20 then
			for _, st in s.stars do
				if st.alive then
					local cf = CFrame.new(st.pos + Vector3.new(0, math.sin(t * 4 + st.pos.Z * 0.2) * 0.2, 0)) * CFrame.Angles(0, spin, 0)
					st.a.CFrame = cf
					st.b.CFrame = cf * CFrame.Angles(0, 0, math.rad(45))
				end
			end
		end
	end

	-- place the kid: directly behind normally, off to one side when lunging close
	local kidTargetX = px
	if state == "playing" and kidDist < 30 then
		kidTargetX = px + kidSide * 13 * math.clamp((30 - kidDist) / 12, 0, 1)
	end
	kidX += (kidTargetX - kidX) * math.min(1, dt * 3)
	local kidRoot = CFrame.new(kidX, 0, pz - kidDist)
	poseKid(kid, kidRoot, t, kidRun, kidReach)

	-- place the smiski
	local rootCF
	if state == "over" and overT > 0.45 then
		local hand = kid.handR.Position
		local held = Vector3.new(hand.X, hand.Y - 3.5, hand.Z + 1)
		local k = math.clamp((overT - 0.45) * 3, 0, 1)
		rootCF = CFrame.new(Vector3.new(px, py, pz):Lerp(held, k)) * CFrame.Angles(0, math.pi, 0)
	else
		rootCF = CFrame.new(px, py, pz)
	end
	poseSmiski(smiski, rootCF, pose, t, roll)

	-- camera
	local a = math.min(1, dt * 8)
	camPos = camPos:Lerp(wantCamPos, a)
	camLook = camLook:Lerp(wantLook, a)
	local sh = Vector3.new(RNG:NextNumber(-1, 1), RNG:NextNumber(-1, 1), 0) * shake * 0.6
	camera.CFrame = CFrame.lookAt(camPos + sh, camLook)
end

if player then
	RunService.RenderStepped:Connect(step)
else
	-- edit-mode preview hooks (used for testing from Studio's command bar)
	return {
		step = step,
		start = startRun,
		act = doAction,
		stumble = stumble,
		info = function()
			return { state = state, pz = pz, px = px, py = py, lane = lane, stars = stars, score = score(), stumble = stumbleTimer, kidDist = kidDist, grounded = grounded }
		end,
		cleanup = function()
			world:Destroy()
			actors:Destroy()
			gui:Destroy()
			sfxFolder:Destroy()
		end,
	}
end
