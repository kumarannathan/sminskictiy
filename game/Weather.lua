-- Weather (ReplicatedStorage.SminskiShared.Weather)
-- The sky: a 30-minute day, and the weather over it.
--
-- NOTHING IS STORED AND NOTHING IS SENT. Both are pure functions of
-- workspace:GetServerTimeNow(), which every client already shares (the
-- traffic lights run off it too). Two players standing on the same corner
-- compute the same sun and the same rain from the same clock, with no
-- replication, no RemoteEvent and no server state to keep in step.
--
-- Weather.lookAt(t) returns a full lighting look in exactly the shape
-- SminskiRunner's LOOKS table uses, so the client can hand it straight to
-- applyLook's machinery.

local Weather = {}

local DAY = 1800          -- 30 real minutes = one Sminski day
Weather.DAY = DAY
local SLOT = DAY / 6      -- weather is re-rolled six times a day (5 real min)

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function lerp(a, b, k) return a + (b - a) * k end

---------------------------------------------------------------------------
-- THE DAY CURVE
-- Keyframes by hour. Between them everything is interpolated, so the sky
-- moves continuously rather than snapping between presets. The 14h frame is
-- the daylight look that was tuned by hand (natural sun, honest shadows, no
-- bloom wash) -- the rest of the day is built around it.
---------------------------------------------------------------------------
local KEYS = {
	{ h = 0, name = "night",
		clock = 0, bright = 0.9, amb = rgb(38, 44, 66), out = rgb(58, 66, 94), exp = 0.1,
		atm = { 0.42, 0.06, rgb(96, 112, 150), rgb(40, 52, 86), 0.05, 1.9 },
		bloom = { 0.35, 26, 1.35 }, grade = { 0.04, 0.09, rgb(224, 232, 255) }, rays = 0,
		shadow = 0.3, clouds = { 0.42, 0.04, rgb(96, 108, 140) }, lamps = 1 },
	{ h = 5.2, name = "dawn",
		clock = 5.6, bright = 1.35, amb = rgb(74, 70, 84), out = rgb(122, 112, 122), exp = 0.06,
		atm = { 0.4, 0.05, rgb(236, 196, 186), rgb(150, 126, 150), 0.18, 1.7 },
		bloom = { 0.28, 26, 1.7 }, grade = { 0.06, 0.07, rgb(255, 242, 234) }, rays = 0.06,
		shadow = 0.24, clouds = { 0.5, 0.045, rgb(240, 206, 198) }, lamps = 0.7 },
	{ h = 8, name = "morning",
		clock = 8.4, bright = 1.85, amb = rgb(70, 74, 86), out = rgb(116, 122, 134), exp = 0.02,
		atm = { 0.36, 0.03, rgb(212, 220, 234), rgb(120, 140, 172), 0.07, 1.55 },
		bloom = { 0.16, 24, 1.9 }, grade = { 0.03, 0.06, rgb(252, 252, 255) }, rays = 0.02,
		shadow = 0.16, clouds = { 0.5, 0.045, rgb(255, 255, 255) }, lamps = 0.15 },
	{ h = 14, name = "day",
		clock = 14.6, bright = 2.1, amb = rgb(74, 76, 86), out = rgb(118, 124, 136), exp = 0,
		atm = { 0.34, 0.02, rgb(202, 214, 230), rgb(104, 126, 158), 0.06, 1.45 },
		bloom = { 0.12, 24, 2 }, grade = { 0.02, 0.06, rgb(252, 252, 255) }, rays = 0,
		shadow = 0.12, clouds = { 0.55, 0.045, rgb(255, 255, 255) }, lamps = 0 },
	{ h = 18.4, name = "golden",
		clock = 17.6, bright = 1.95, amb = rgb(84, 74, 74), out = rgb(140, 120, 108), exp = 0.04,
		atm = { 0.38, 0.04, rgb(255, 214, 178), rgb(180, 140, 128), 0.22, 1.6 },
		bloom = { 0.24, 26, 1.75 }, grade = { 0.07, 0.07, rgb(255, 246, 236) }, rays = 0.1,
		shadow = 0.2, clouds = { 0.52, 0.045, rgb(255, 222, 196) }, lamps = 0.35 },
	{ h = 20.6, name = "dusk",
		clock = 19.2, bright = 1.35, amb = rgb(64, 62, 86), out = rgb(96, 94, 124), exp = 0.1,
		atm = { 0.42, 0.05, rgb(196, 176, 196), rgb(96, 92, 140), 0.12, 1.75 },
		bloom = { 0.32, 26, 1.5 }, grade = { 0.06, 0.08, rgb(244, 240, 255) }, rays = 0.04,
		shadow = 0.26, clouds = { 0.48, 0.045, rgb(198, 184, 206) }, lamps = 0.85 },
	{ h = 22.4, name = "night",
		clock = 22, bright = 0.95, amb = rgb(40, 46, 68), out = rgb(60, 68, 96), exp = 0.1,
		atm = { 0.42, 0.06, rgb(98, 114, 152), rgb(42, 54, 88), 0.05, 1.88 },
		bloom = { 0.35, 26, 1.35 }, grade = { 0.04, 0.09, rgb(224, 232, 255) }, rays = 0,
		shadow = 0.3, clouds = { 0.44, 0.04, rgb(96, 108, 140) }, lamps = 1 },
}

---------------------------------------------------------------------------
-- THE WEATHER STATES
-- `wet` drives rain, `fogK` thickens the air, and the multipliers bend the
-- day curve rather than replacing it -- so rain at noon and rain at midnight
-- are both plainly rain, and both still plainly noon and midnight.
--
-- The haze ceiling matters and is deliberate: sign text is capped at 700
-- studs (K.textOn's MaxDistance) and the wayfinding ribbon is read at a
-- grazing angle, so fog thick enough to hide a direction blade is fog that
-- has broken two other features. FOG_MAX is that ceiling.
---------------------------------------------------------------------------
Weather.FOG_MAX = 2.9

local STATES = {
	{ id = "clear", name = "Clear", icon = "star", weight = 34,
		bright = 1, haze = 1, sat = 0, wet = 0, cloud = 0.85, lamps = 1 },
	{ id = "fair", name = "Fair", icon = "star", weight = 26,
		bright = 0.97, haze = 1.06, sat = -0.01, wet = 0, cloud = 1.15, lamps = 1 },
	{ id = "overcast", name = "Overcast", icon = "clock", weight = 18,
		bright = 0.8, haze = 1.25, sat = -0.05, wet = 0, cloud = 1.7, lamps = 1.25 },
	{ id = "rain", name = "Rain", icon = "heart", weight = 14,
		bright = 0.64, haze = 1.5, sat = -0.08, wet = 1, cloud = 1.9, lamps = 1.5 },
	{ id = "storm", name = "Heavy Rain", icon = "bolt", weight = 4,
		bright = 0.5, haze = 1.7, sat = -0.11, wet = 1.7, cloud = 2, lamps = 1.8 },
	{ id = "fog", name = "Sea Fog", icon = "clock", weight = 4,
		bright = 0.74, haze = 1.95, sat = -0.07, wet = 0, cloud = 1.3, lamps = 1.6 },
}
Weather.STATES = STATES

-- a stable pseudo-random number for a given slot: no Math.random, so every
-- machine agrees and a given hour of a given day always has the same weather
-- (Luau has no ~ / & / | operators -- this is deliberately plain arithmetic,
-- not a bitwise hash, so it runs identically on every client.)
-- minstd. Every product here is kept under 2^53 on purpose: Luau numbers are
-- doubles, and a bigger multiplier silently loses precision -- which shows up
-- as a skewed forecast rather than as an error. (A sin-based hash was tried
-- first and gave 40% "fair" against a 26% weight.)
local function hash(n)
	local x = ((n % 1000000) * 48271 + 12345) % 2147483647
	for _ = 1, 3 do x = (x * 16807) % 2147483647 end
	return x / 2147483647
end

function Weather.stateAt(t)
	local slot = math.floor(t / SLOT)
	local r = hash(slot) * 100
	local acc = 0
	for _, st in STATES do
		acc += st.weight
		if r < acc then return st, slot end
	end
	return STATES[1], slot
end

-- 0 at the start and end of a slot, 1 in the middle: weather arrives and
-- leaves rather than appearing whole
function Weather.blend(t)
	local k = (t % SLOT) / SLOT
	return math.clamp(math.min(k, 1 - k) / 0.12, 0, 1)
end

function Weather.hourAt(t) return (t % DAY) / DAY * 24 end

-- how far through the slot, for a UI countdown
function Weather.nextChange(t) return SLOT - (t % SLOT) end

---------------------------------------------------------------------------
-- THE LOOK
---------------------------------------------------------------------------
local function frameAt(hour)
	local a, b = KEYS[#KEYS], KEYS[1]
	for i = 1, #KEYS - 1 do
		if hour >= KEYS[i].h and hour <= KEYS[i + 1].h then a, b = KEYS[i], KEYS[i + 1] break end
	end
	local span = (b.h - a.h) % 24
	if span <= 0 then span = 24 end
	local k = math.clamp(((hour - a.h) % 24) / span, 0, 1)
	k = k * k * (3 - 2 * k) -- ease, so noon does not arrive on a straight line
	local function L(f) return lerp(a[f], b[f], k) end
	-- ClockTime must not interpolate backwards through the day at the wrap
	local c0, c1 = a.clock, b.clock
	if c1 < c0 then c1 += 24 end
	return {
		name = k < 0.5 and a.name or b.name,
		clock = lerp(c0, c1, k) % 24,
		bright = L("bright"), exp = L("exp"), shadow = L("shadow"), rays = L("rays"), lamps = L("lamps"),
		amb = a.amb:Lerp(b.amb, k), out = a.out:Lerp(b.out, k),
		atm = { lerp(a.atm[1], b.atm[1], k), lerp(a.atm[2], b.atm[2], k), a.atm[3]:Lerp(b.atm[3], k),
			a.atm[4]:Lerp(b.atm[4], k), lerp(a.atm[5], b.atm[5], k), lerp(a.atm[6], b.atm[6], k) },
		bloom = { lerp(a.bloom[1], b.bloom[1], k), lerp(a.bloom[2], b.bloom[2], k), lerp(a.bloom[3], b.bloom[3], k) },
		grade = { lerp(a.grade[1], b.grade[1], k), lerp(a.grade[2], b.grade[2], k), a.grade[3]:Lerp(b.grade[3], k) },
		clouds = { lerp(a.clouds[1], b.clouds[1], k), lerp(a.clouds[2], b.clouds[2], k), a.clouds[3]:Lerp(b.clouds[3], k) },
	}
end

-- the whole sky at server time t. `over` forces an hour, `force` a state id.
function Weather.lookAt(t, over, force)
	local hour = over or Weather.hourAt(t)
	local f = frameAt(hour)
	local st = STATES[1]
	if force then
		for _, s in STATES do if s.id == force then st = s end end
	else
		st = Weather.stateAt(t)
	end
	local k = force and 1 or Weather.blend(t)
	local function mix(base, mult) return lerp(base, base * mult, k) end
	f.bright = mix(f.bright, st.bright)
	f.atm[6] = math.min(Weather.FOG_MAX, mix(f.atm[6], st.haze))
	f.atm[1] = mix(f.atm[1], 1 + (st.haze - 1) * 0.35)
	f.grade[1] = f.grade[1] + st.sat * k
	f.clouds[1] = math.clamp(mix(f.clouds[1], st.cloud), 0, 1)
	f.clouds[2] = mix(f.clouds[2], st.cloud > 1.5 and 1.6 or 1)
	f.lamps = math.clamp(f.lamps * lerp(1, st.lamps, k), 0, 1)
	f.rays = f.rays * lerp(1, st.id == "clear" and 1 or 0.2, k)
	f.wet = st.wet * k
	f.state = st
	f.hour = hour
	return f
end

-- "7:20 pm" for the HUD
--
-- WORK IN WHOLE MINUTES, AND ROUND ONCE. This used to floor the fractional
-- hour: (19.4 % 1) * 60 is 23.99999999999992 in float, so 7:24 pm printed as
-- 7:23 pm. It is not specific to 19.4 -- any fractional hour whose sixtieths
-- land just under a binary boundary loses a minute the same way.
--
-- Rounding on its own is not the fix either: 19.9999 would round to 60
-- minutes and print "7:60 pm". So the hour becomes one rounded minute count
-- and a single modulo does both carries -- 60 minutes into the next hour, and
-- 24 hours back to midnight.
function Weather.clockText(hour)
	local total = math.floor((hour or 0) * 60 + 0.5) % (24 * 60)
	local h = math.floor(total / 60)
	local m = total % 60
	local ampm = h < 12 and "am" or "pm"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%d:%02d %s", h12, m, ampm)
end

return Weather
