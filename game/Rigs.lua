-- Rigs (ReplicatedStorage.SminskiShared.Rigs)
-- Joint math for the giant kid/humans and the dogs, shared by the client
-- (drawing them) and the server (Dog Park Survival hit checks), so a foot is
-- in exactly the same place on every machine.
--
-- Everything is built at scale 1 and multiplied by `s`. rootCF sits on the
-- ground under the body, facing +Z.

local Rigs = {}

---------------------------------------------------------------------------
-- HUMANS (the chibi kid model, also used for adults at a bigger scale)
---------------------------------------------------------------------------
-- ph: gait phase (radians), run: 0..1 stride size, reach: 0..1 grabbing,
-- t: clock for idle motion, s: scale, throw: 0..1 arm wind-up (optional)
function Rigs.kidJoints(rootCF, ph, run, reach, t, s, throw)
	s = s or 1
	throw = throw or 0
	local sw = math.sin(ph) * 0.6 * run
	local bob = math.abs(math.cos(ph)) * 1.2 * run * s
	local lean = 0.12 + 0.26 * reach
	local torso = rootCF * CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, math.sin(ph) * 0.04 * run)
	local grab = math.sin(t * 9) * 0.3 * reach
	local armIdle = -0.15 + math.sin(t * 1.7) * 0.05
	-- knees flex as each leg swings back, like a real stride
	local kneeL = math.max(0, math.sin(ph + 0.9)) * 1.3 * run + 0.08
	local kneeR = math.max(0, math.sin(ph + 0.9 + math.pi)) * 1.3 * run + 0.08
	local thighL = torso * CFrame.new(-3 * s, 14 * s, 0) * CFrame.Angles(-lean - sw - 0.1 * run, 0, 0)
	local thighR = torso * CFrame.new(3 * s, 14 * s, 0) * CFrame.Angles(-lean + sw - 0.1 * run, 0, 0)
	local armRx = -sw * 0.9 * (1 - reach) + armIdle * (1 - reach) + (-1.55 - grab) * reach
	armRx = armRx + (-2.6 - armRx) * throw -- wind up over the head
	return {
		torso = torso,
		thighL = thighL,
		thighR = thighR,
		shinL = thighL * CFrame.new(0, -5.6 * s, 0) * CFrame.Angles(kneeL, 0, 0),
		shinR = thighR * CFrame.new(0, -5.6 * s, 0) * CFrame.Angles(kneeR, 0, 0),
		head = torso * CFrame.new(0, 25.6 * s, 0) * CFrame.Angles(-lean * 0.7 + math.sin(t * 3) * 0.04, math.sin(t * 1.3) * 0.08, 0),
		armL = torso * CFrame.new(-7.2 * s, 22.8 * s, 0) * CFrame.Angles(sw * 0.9 * (1 - reach) + armIdle * (1 - reach) + (-1.55 + grab) * reach, 0, -0.14 + 0.36 * reach),
		armR = torso * CFrame.new(7.2 * s, 22.8 * s, 0) * CFrame.Angles(armRx, 0, 0.14 - 0.36 * reach),
	}
end

-- sneaker soles: { cf = sole centre, h = height of the sole's bottom above the ground }
local SOLE = CFrame.new(0, -7.7, 1.3)
function Rigs.kidSoles(rootCF, ph, run, s)
	s = s or 1
	local j = Rigs.kidJoints(rootCF, ph, run, 0, 0, s)
	local out = {}
	for _, name in { "shinL", "shinR" } do
		local cf = j[name] * CFrame.new(SOLE.Position * s)
		local h = rootCF:PointToObjectSpace(cf.Position).Y - 0.65 * s
		table.insert(out, { cf = cf, h = h })
	end
	return out
end

-- sole footprint half-size (local x, z) at scale s
function Rigs.soleHalf(s)
	return 2.9 * s, 4.3 * s
end

---------------------------------------------------------------------------
-- DOGS
---------------------------------------------------------------------------
-- ph: gait phase, run: 0..1 gallop, reach: 0..1 open mouth, t: clock,
-- s: scale, pounce: 0..1 through a leap (0 = none)
function Rigs.dogJoints(rootCF, ph, run, reach, t, s, pounce)
	s = s or 1
	pounce = pounce or 0
	local sn = math.sin(ph) * run
	local bob = math.abs(math.cos(ph)) * 1.8 * run * s
	local pitch = math.sin(ph) * 0.08 * run - reach * 0.08
	local lift = 0
	local legF, legB = 0, 0
	local headDip = 0
	if pounce > 0 then
		-- leap: nose up and airborne, then land nose-first with front paws out
		local k = pounce
		lift = math.sin(math.pi * math.min(k, 1)) * 7 * s - k * k * 3.2 * s
		pitch = -0.35 + 0.95 * k
		legF = -0.9 - 0.4 * k
		legB = 0.9
		headDip = 0.35 * k
		sn = 0
		bob = 0
	end
	local body = rootCF * CFrame.new(0, 13.4 * s + bob + lift, 0) * CFrame.Angles(pitch, 0, 0)
	local mouthOpen = 0.15 + reach * 0.35 + math.max(0, math.sin(t * 5)) * 0.15
	local head = body * CFrame.new(0, 7 * s, 12 * s) * CFrame.Angles(-0.1 + reach * 0.35 + headDip + math.sin(ph * 0.5) * 0.05, math.sin(t * 1.5) * 0.12 * (1 - run), 0)
	return {
		body = body,
		head = head,
		jaw = head * CFrame.new(0, -2.6 * s, 6 * s) * CFrame.Angles(mouthOpen, 0, 0),
		earL = head * CFrame.new(-6.2 * s, 6 * s, 1.5 * s) * CFrame.Angles(math.sin(ph) * 0.25 * run - 0.2, 0, -0.35),
		earR = head * CFrame.new(6.2 * s, 6 * s, 1.5 * s) * CFrame.Angles(math.sin(ph + 0.6) * 0.25 * run - 0.2, 0, 0.35),
		-- gallop: front pair and back pair swing out of phase
		FL = body * CFrame.new(-4.6 * s, -2.5 * s, 9 * s) * CFrame.Angles(-sn * 0.8 + legF - pitch * (pounce > 0 and 0 or 1), 0, 0),
		FR = body * CFrame.new(4.6 * s, -2.5 * s, 9 * s) * CFrame.Angles(-sn * 0.65 + legF - pitch * (pounce > 0 and 0 or 1), 0, 0),
		BL = body * CFrame.new(-4.6 * s, -2.5 * s, -9 * s) * CFrame.Angles(sn * 0.8 + legB - pitch * (pounce > 0 and 0 or 1), 0, 0),
		BR = body * CFrame.new(4.6 * s, -2.5 * s, -9 * s) * CFrame.Angles(sn * 0.65 + legB - pitch * (pounce > 0 and 0 or 1), 0, 0),
		tail = body * CFrame.new(0, 4 * s, -13.5 * s) * CFrame.Angles(0.7, math.sin(t * 14) * 0.6, 0),
	}
end

local PAW = Vector3.new(0, -9.4, 1)
local MOUTH = Vector3.new(0, 0, 3.6)
-- paws: { pos, h }, plus the mouth position
function Rigs.dogPoints(rootCF, ph, run, s, pounce)
	s = s or 1
	local j = Rigs.dogJoints(rootCF, ph, run, pounce and pounce > 0 and 1 or 0, 0, s, pounce)
	local paws = {}
	for _, leg in { "FL", "FR", "BL", "BR" } do
		local p = (j[leg] * CFrame.new(PAW * s)).Position
		table.insert(paws, { pos = p, h = rootCF:PointToObjectSpace(p).Y - 1.5 * s })
	end
	return paws, (j.jaw * CFrame.new(MOUTH * s)).Position
end

return Rigs
