--!nocheck
-- Headless tests. `lune run tests/run.luau` from the repo root.
--
-- WHY THESE EXIST. Until now the only way to find out whether a number was
-- wrong was to sync to Studio and play. These run in about a second and cover
-- the things that are pure data: the crop maths, the economy balance, and the
-- pixel grid. They are not a substitute for looking at the game -- nothing
-- here can tell you the HUD is ugly -- they are a substitute for ARGUING
-- about numbers in a document.
--
-- Config.lua loads cleanly outside Roblox because it is data and arithmetic
-- with no services in it. UI.lua and City.lua cannot: they are module
-- constructors that take live services, so anything about them is checked
-- statically against the source text instead.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local pass, fail = 0, 0
local function ok(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		print(("  FAIL  %s%s"):format(name, detail and ("  -- " .. detail) or ""))
	end
end
local function section(name) print("\n" .. name) end

---------------------------------------------------------------------------
-- load Config in a Roblox-shaped sandbox
---------------------------------------------------------------------------
-- Inject the Roblox datatypes as real globals rather than swapping the
-- chunk's environment. setfenv with a fresh table cuts Config off from `math`,
-- and it reaches for math.huge; chaining __index back to _G does not help
-- because a loadstring'd chunk's globals are not _G in Luau.
_G.Color3, _G.Vector3, _G.Vector2 = roblox.Color3, roblox.Vector3, roblox.Vector2
_G.Enum, _G.UDim, _G.UDim2 = roblox.Enum, roblox.UDim, roblox.UDim2
Color3, Vector3, Vector2 = roblox.Color3, roblox.Vector3, roblox.Vector2
Enum, UDim, UDim2 = roblox.Enum, roblox.UDim, roblox.UDim2

local chunk = assert((loadstring or load)(fs.readFile("game/Config.lua"), "Config"))
local Config = chunk()

---------------------------------------------------------------------------
section("Config integrity")
---------------------------------------------------------------------------
ok("roles exist", #Config.Roles == 3, "got " .. #Config.Roles)
for _, r in Config.Roles do
	ok("role " .. r.id .. " names a real job", Config.Job(r.job) ~= nil, r.job)
	ok("role " .. r.id .. " names a real hood", Config.Hood(r.hood) ~= nil, r.hood)
	local j = Config.Job(r.job)
	-- A ROLE MUST SPAWN YOU BESIDE A JOB YOU CAN ACTUALLY DO. Everything
	-- still marked `soon` has no gameplay behind it; a role pointing at one
	-- is worse than having no role at all (docs/ONBOARDING.md section 4).
	ok("role " .. r.id .. " job is playable", j and not j.soon, r.job .. " is soon=true")
end
ok("switch cost is set", (Config.RoleSwitchCost or 0) > 0)

for _, c in Config.Crops do
	ok("crop " .. c.id .. " grows in real time", c.grow >= 60, tostring(c.grow) .. "s")
	ok("crop " .. c.id .. " yield range sane", c.yield[1] > 0 and c.yield[2] >= c.yield[1])
	-- SEED IS PER PLOT, SELL IS PER UNIT. The invariant is that even the
	-- WORST roll of the yield range still clears the seed -- otherwise a bad
	-- harvest costs the player money and the job punishes luck.
	ok("crop " .. c.id .. " profits on a worst-case yield", c.yield[1] * c.sell > c.seed,
		("%d x %d vs seed %d"):format(c.yield[1], c.sell, c.seed))
end

---------------------------------------------------------------------------
section("Crop growth maths")
---------------------------------------------------------------------------
local now = 10000
local carrot = Config.Crop("carrot")
local function plot(t) return { crop = "carrot", at = now - t } end

ok("unplanted is 0", Config.CropProgress({}, now) == 0)
ok("half way is 0.5", math.abs(Config.CropProgress(plot(carrot.grow / 2), now) - 0.5) < 1e-6)
ok("ripe clamps to 1", Config.CropProgress(plot(carrot.grow * 5), now) == 1,
	"a ready crop must never exceed 1 or the stage index runs off the end")
ok("ready stage is the last one", Config.CropStage(plot(carrot.grow), now) == Config.Farm.Stages - 1)
ok("just-planted is stage 0", Config.CropStage(plot(0), now) == 0)

-- READY IS TERMINAL. docs/FARMING.md: a crop that is ready stays ready
-- forever, because nobody should be punished for being offline.
local long = plot(carrot.grow * 1000)
ok("ready never spoils", Config.CropStage(long, now) == Config.Farm.Stages - 1)

-- READY MEANS FINISHED. CropStage used to be floor(k * Stages), which handed
-- out the ready stage at 75% and made the last quarter of every grow time
-- decorative.
for _, k in { 0.5, 0.75, 0.9, 0.99 } do
	ok(("%d%% grown is not ready"):format(k * 100),
		Config.CropStage(plot(carrot.grow * k), now) < Config.Farm.Stages - 1,
		("stage %d at k=%.2f"):format(Config.CropStage(plot(carrot.grow * k), now), k))
end
ok("100% grown is ready", Config.CropStage(plot(carrot.grow), now) == Config.Farm.Stages - 1)

local w = plot(carrot.grow / 2); w.watered = true
ok("watering speeds growth", Config.CropProgress(w, now) > 0.5)
local f = plot(carrot.grow / 2); f.fert = true
ok("fertiliser speeds growth", Config.CropProgress(f, now) > 0.5)
ok("fertiliser beats watering", Config.CropProgress(f, now) > Config.CropProgress(w, now),
	"fertiliser costs coins; it has to be worth more than a free watering can")

---------------------------------------------------------------------------
section("Water and fertiliser")
---------------------------------------------------------------------------
-- THE BUG THIS GUARDS (Config.CropBoost): setting the flag alone re-scales
-- growth that already happened, so a crop watered at 90% done would jump
-- straight to ready and watering late would pay better than watering early.
local late = plot(carrot.grow * 0.9)
local beforeLate = Config.CropProgress(late, now)
Config.CropBoost(late, "watered", now)
ok("watering does not jump a crop forward",
	Config.CropProgress(late, now) < beforeLate + 0.01,
	("%.3f -> %.3f"):format(beforeLate, Config.CropProgress(late, now)))
ok("a late-watered crop is still not ready", Config.CropStage(late, now) < Config.Farm.Stages - 1)

-- watering EARLY saves more real time than watering late, because there is
-- more remaining span to shorten
local function secondsToReady(p)
	local t = 0
    while Config.CropStage(p, now + t) < Config.Farm.Stages - 1 and t < 100000 do t += 1 end
	return t
end
local early = plot(0); Config.CropBoost(early, "watered", now)
local mid = plot(carrot.grow * 0.5); Config.CropBoost(mid, "watered", now)
ok("watering early saves more than watering late",
	secondsToReady(early) < carrot.grow, "early water must beat the base grow time")
ok("watering mid-way still helps", secondsToReady(mid) < carrot.grow * 0.5)

ok("cannot water twice", Config.CropBoost(early, "watered", now) == false)
local done = plot(carrot.grow * 2)
ok("cannot fertilise a ready crop", Config.CropBoost(done, "fert", now) == false,
	"otherwise the player is charged 25 coins for nothing")
ok("boost refuses an empty plot", Config.CropBoost({}, "watered", now) == false)

---------------------------------------------------------------------------
section("Economy balance")
---------------------------------------------------------------------------
-- THE RISK THIS TEST EXISTS FOR (docs/FARMING.md section 5): twelve plots of
-- five-minute carrots would out-earn every other job in the game by an order
-- of magnitude, and farming would become the only sane way to make money.
-- The throttle is PLOT COUNT and CARRY CAPACITY, not crop price -- so if
-- somebody raises MaxPlots or a sell value, this is what should object.
local function coinsPerMin(crop, plots)
	local c = Config.Crop(crop)
	local perHarvest = (c.yield[1] + c.yield[2]) / 2 * c.sell
	local netPerPlot = perHarvest - c.seed
	return netPerPlot * plots / (c.grow / 60)
end

local taxiPerMin = Config.City.Taxi.base * 2 -- roughly two fares a minute
local startFarm = coinsPerMin("carrot", Config.Farm.StartPlots)
local maxFarm = coinsPerMin("carrot", Config.Farm.MaxPlots)

print(("  taxi ~%d/min | farm start ~%d/min | farm max ~%d/min")
	:format(taxiPerMin, startFarm, maxFarm))

ok("a starter farm is worth doing", startFarm > taxiPerMin * 0.4,
	"too slow and nobody picks farmer")
ok("a starter farm does not dominate", startFarm < taxiPerMin * 2,
	("%d vs %d/min"):format(startFarm, taxiPerMin))
ok("a maxed farm stays in the same league", maxFarm < taxiPerMin * 6,
	("%d vs %d/min -- raise plot cost or lower yield"):format(maxFarm, taxiPerMin))

---------------------------------------------------------------------------
section("City tasks")
---------------------------------------------------------------------------
-- THE WIDGET MUST NEVER BE EMPTY while work remains (docs/ONBOARDING.md
-- section 5.1). An empty goal widget is the "what do I do?" problem coming
-- straight back, so the chain is walked end to end here.
local seen, done, guard = {}, {}, 0
local order = {}
while guard < 100 do
	guard += 1
	local t = Config.NextTask(done, {})
	if not t then break end
	ok("task " .. t.id .. " not offered twice", not seen[t.id], t.id)
	seen[t.id] = true
	table.insert(order, t.id)
	done[t.id] = true
end
ok("every task is reachable", #order == #Config.Tasks,
	("reached %d of %d -- an `after` probably names a task that never completes"):format(#order, #Config.Tasks))

for i, id in Config.TaskOpening do
	ok("opening step " .. i .. " is " .. id, order[i] == id,
		"got " .. tostring(order[i]) .. " -- the guided sequence is out of order")
end

for _, t in Config.Tasks do
	ok("task " .. t.id .. " has a stat", type(t.stat) == "string" and #t.stat > 0)
	ok("task " .. t.id .. " has a goal", (t.goal or 0) > 0)
	ok("task " .. t.id .. " says how", type(t.how) == "string" and #t.how > 0,
		"a task without a HOW is a nag, not an instruction")
	if t.after then
		ok("task " .. t.id .. " after-id exists", Config.Task(t.after) ~= nil, t.after)
	end
end

-- nothing is offered before the role is picked
local first = Config.NextTask({}, {})
ok("role comes first", first and first.id == "role")

---------------------------------------------------------------------------
section("Pixel grid (static, against City.lua source)")
---------------------------------------------------------------------------
-- EVERY HUD DIMENSION IS A MULTIPLE OF 4 (docs/PIXEL_UI.md section 1). With
-- the canvas scale quantised to quarters, 4 * s is always a whole number of
-- real pixels -- but only if the dimension was a multiple of 4 to begin
-- with. A 42 in here puts half-pixel edges back on screen.
local city = fs.readFile("game/City.lua")
local zblock = city:match("local Z = {(.-)\n%s*}")
ok("City.lua has the size table", zblock ~= nil)
if zblock then
	local n = 0
	for key, value in zblock:gmatch("(%w+)%s*=%s*(%d+)") do
		n += 1
		ok("Z." .. key .. " is on the 4px grid", tonumber(value) % 4 == 0, value)
	end
	ok("size table is populated", n >= 8, tostring(n) .. " entries")
end

local ui = fs.readFile("game/UI.lua")
ok("skin images are pixelated", ui:find("ResampleMode = Enum.ResamplerMode.Pixelated") ~= nil,
	"without this every glyph is bilinear-blurred and the style collapses")
ok("canvas scale is quantised", ui:find("local function quantise") ~= nil)
ok("button squash is gone", ui:find("Scale = 0.96") == nil,
	"scaling pixel art by 0.96 on every tap is the same blur")
ok("tap floor is 44", Config and true)

---------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then process.exit(1) end
