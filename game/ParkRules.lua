-- ParkRules (ReplicatedStorage.SminskiShared.ParkRules)
-- Dog Park Survival: what a dog / human / thrown thing looks like at a moment
-- and whether it just got a Sminski. Server (authoritative) and client (fair,
-- what-you-see checks + drawing) run exactly the same maths.

local Shared = script.Parent
local Rigs = require(Shared:WaitForChild("Rigs"))
local Places = require(Shared:WaitForChild("Places"))

local R = {}

R.KIND = { dog = 1, human = 2, bot = 3 }
R.KIND_NAME = { "dog", "human", "bot" }

-- dog states
R.DOG = { wander = 0, zoom = 1, chase = 2, crouch = 3, lunge = 4, recover = 5, sniff = 6, fetch = 7, leash = 8, enter = 9 }
-- human states
R.HUM = { walk = 0, jog = 1, stand = 2, windup = 3, leave = 4, sit = 5 }

R.CROUCH_T = 0.45
R.LUNGE_T = 0.5
R.WINDUP_T = 0.7
R.PLAYER_R = 0.9 -- a Sminski's footprint radius

-- dog/human variants (colours are client-only, scale matters to both)
R.DOGS = {
	{ name = "small", s = 0.55, fur = Color3.fromRGB(245, 245, 240), light = Color3.fromRGB(255, 255, 255), dark = Color3.fromRGB(200, 170, 140) },
	{ name = "golden", s = 0.78, fur = Color3.fromRGB(232, 172, 92), light = Color3.fromRGB(248, 214, 150), dark = Color3.fromRGB(196, 132, 64) },
	{ name = "lab", s = 0.8, fur = Color3.fromRGB(60, 55, 60), light = Color3.fromRGB(110, 100, 105), dark = Color3.fromRGB(40, 36, 40) },
	{ name = "choc", s = 0.72, fur = Color3.fromRGB(125, 80, 55), light = Color3.fromRGB(175, 125, 90), dark = Color3.fromRGB(90, 55, 35) },
	{ name = "big", s = 1.0, fur = Color3.fromRGB(210, 150, 80), light = Color3.fromRGB(240, 205, 150), dark = Color3.fromRGB(150, 95, 50) },
}
R.HUMANS = {
	{ s = 0.95, hoodie = Color3.fromRGB(235, 110, 100), pants = Color3.fromRGB(80, 110, 175), cap = Color3.fromRGB(255, 205, 70) },
	{ s = 1.05, hoodie = Color3.fromRGB(110, 170, 240), pants = Color3.fromRGB(70, 70, 90), cap = false, bun = true },
	{ s = 1.15, hoodie = Color3.fromRGB(150, 205, 140), pants = Color3.fromRGB(150, 150, 165), cap = Color3.fromRGB(60, 70, 120) },
	{ s = 1.1, hoodie = Color3.fromRGB(185, 160, 240), pants = Color3.fromRGB(60, 60, 75), cap = false },
	{ s = 1.0, hoodie = Color3.fromRGB(255, 190, 90), pants = Color3.fromRGB(90, 130, 190), cap = Color3.fromRGB(235, 90, 90) },
}

function R.rootCF(e)
	return CFrame.new(Places.ARENA + Vector3.new(e.x, 0, e.z)) * CFrame.Angles(0, e.h, 0)
end

function R.dogRun(e)
	if e.st == R.DOG.crouch or e.st == R.DOG.recover or e.st == R.DOG.sniff then return 0 end
	return math.clamp(e.v / 32, 0.15, 1)
end

function R.humanRun(e)
	if e.st == R.HUM.stand or e.st == R.HUM.windup or e.st == R.HUM.sit then return 0 end
	return e.role == "jogger" and 0.95 or 0.45
end

-- gait phase advance per second (same everywhere so feet agree)
function R.phaseRate(e)
	if e.kind == R.KIND.dog then
		local run = R.dogRun(e)
		return e.v / ((34 * run + 6) * e.s) * math.pi * 2
	elseif e.kind == R.KIND.human then
		local run = R.humanRun(e)
		if run <= 0 then return 0 end
		return e.v / ((53 * math.sin(0.6 * run) + 2) * e.s) * math.pi * 2
	end
	return 0
end

function R.pounce(e)
	if e.kind == R.KIND.dog and e.st == R.DOG.lunge then
		return math.clamp(e.stT / R.LUNGE_T, 0, 1)
	end
	return 0
end

-- p: world position of a Sminski's feet. Returns "squished"/"stomped"/"caught" or nil.
-- cover: nil | "shelter" | "bush" (from Places.coverAt)
function R.entityHit(e, p, margin, cover)
	local root = R.rootCF(e)
	local rel = p - root.Position
	local flat = Vector3.new(rel.X, 0, rel.Z).Magnitude
	if e.kind == R.KIND.human then
		if cover == "shelter" or flat > 22 * e.s then return nil end
		local run = R.humanRun(e)
		if run <= 0 then return nil end
		local soles = Rigs.kidSoles(root, e.ph, run, e.s)
		local before = Rigs.kidSoles(root, e.ph - 0.18, run, e.s)
		local hx, hz = Rigs.soleHalf(e.s)
		for i, sole in soles do
			if sole.h < 1.4 * e.s and sole.h < before[i].h - 0.05 then
				local l = sole.cf:PointToObjectSpace(p)
				if math.abs(l.X) < hx + margin and math.abs(l.Z) < hz + margin then
					return "squished"
				end
			end
		end
	elseif e.kind == R.KIND.dog then
		if flat > 30 * e.s then return nil end
		local k = R.pounce(e)
		local paws, mouth = Rigs.dogPoints(root, e.ph, R.dogRun(e), e.s, k > 0 and k or nil)
		if k > 0.55 then
			local m = Vector3.new(mouth.X - p.X, 0, mouth.Z - p.Z).Magnitude
			if m < 4.4 * e.s + margin then return "caught" end
		end
		if cover ~= "shelter" and e.v > 6 then
			for _, paw in paws do
				if paw.h < 1.1 * e.s then
					local d = Vector3.new(paw.pos.X - p.X, 0, paw.pos.Z - p.Z).Magnitude
					if d < 2.8 * e.s + margin then return "stomped" end
				end
			end
		end
	end
	return nil
end

function R.projHit(pr, p, now, margin, cover)
	if cover == "shelter" then return nil end
	local pos, lethal = Places.projAt(pr, now)
	if not pos or not lethal then return nil end
	local w = Places.ARENA + pos
	local r = pr.kind == "frisbee" and 4.5 or Places.BALL_R + 0.6
	local d = Vector3.new(w.X - p.X, 0, w.Z - p.Z).Magnitude
	if d < r + margin and w.Y - p.Y < 5 then
		return "bonked"
	end
	return nil
end

---------------------------------------------------------------------------
-- SNAPSHOT PACKING (23 bytes per entity)
---------------------------------------------------------------------------
local REC = 23
function R.pack(list, t)
	local b = buffer.create(10 + #list * REC)
	buffer.writef64(b, 0, t)
	buffer.writeu16(b, 8, #list)
	for i, e in list do
		local o = 10 + (i - 1) * REC
		buffer.writeu16(b, o, e.id)
		buffer.writeu8(b, o + 2, e.kind)
		buffer.writef32(b, o + 3, e.x)
		buffer.writef32(b, o + 7, e.z)
		buffer.writeu16(b, o + 11, math.floor((e.h % (math.pi * 2)) / (math.pi * 2) * 65535))
		buffer.writeu16(b, o + 13, math.clamp(math.floor(e.v * 100), 0, 65535))
		buffer.writef32(b, o + 15, e.ph % 1000)
		buffer.writeu8(b, o + 19, e.st)
		buffer.writeu16(b, o + 20, math.clamp(math.floor(e.stT * 1000), 0, 65535))
		buffer.writeu8(b, o + 22, e.flag or 0)
	end
	return b
end

function R.unpack(b)
	local t = buffer.readf64(b, 0)
	local n = buffer.readu16(b, 8)
	local out = table.create(n)
	for i = 1, n do
		local o = 10 + (i - 1) * REC
		out[i] = {
			id = buffer.readu16(b, o),
			kind = buffer.readu8(b, o + 2),
			x = buffer.readf32(b, o + 3),
			z = buffer.readf32(b, o + 7),
			h = buffer.readu16(b, o + 11) / 65535 * math.pi * 2,
			v = buffer.readu16(b, o + 13) / 100,
			ph = buffer.readf32(b, o + 15),
			st = buffer.readu8(b, o + 19),
			stT = buffer.readu16(b, o + 20) / 1000,
			flag = buffer.readu8(b, o + 22),
		}
	end
	return t, out
end

return R
